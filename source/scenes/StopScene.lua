-- Stop Detail: what's leaving from here, soonest first. The screen you open
-- standing at a stop, so it answers one question -- which bus is next and
-- when -- and nothing else.
--
-- One row per route *and direction*, since a route that passes both ways is
-- two different answers. Only directions with departures still to come today
-- are listed, and only ones you could actually board: a trip that terminates
-- at this stop is dropped, or a terminus shows a board full of buses going
-- out of service.
--
-- Times are relative under the hour ("6m") and absolute beyond it ("14:38"),
-- which is how you actually think about a bus: three minutes is a countdown,
-- three hours is an appointment.
--
-- Scene properties: { stop }.

StopScene = {}
class("StopScene").extends(NobleScene)
local scene = StopScene

scene.backgroundColor = Graphics.kColorWhite

local ROW_H <const> = 30
local MAX_TIMES <const> = 3
-- A headsign narrower than this is useless, so a row drops its later times
-- rather than squeezing the destination out.
local MIN_LABEL_W <const> = 104
local CRANK_DEGREES_PER_ROW <const> = 12

local stop
local departures = {}
local grid = nil
local crankAccumulator = 0
local favoriteMenuItem = nil

local function listHeight()
	return Theme.CONTENT_BOTTOM - Theme.CONTENT_TOP
end

local function parseHHMM(s)
	local hour, minute = s:match("(%d+):(%d+)")
	if hour == nil then return nil end
	return tonumber(hour) * 3600 + tonumber(minute) * 60
end

local function formatClock(seconds)
	seconds = seconds % (24 * 3600)
	return string.format("%02d:%02d", seconds // 3600, (seconds % 3600) // 60)
end

--- "now" when it's pulling in, "6m" while it's a countdown, "14:38" once
--- it's far enough away to be an appointment.
local function whenLabel(secondsAway, absolute)
	if secondsAway < 60 then return "now" end
	if secondsAway < 3600 then return (secondsAway // 60) .. "m" end
	return formatClock(absolute)
end

local function stopIndexIn(direction, stopId)
	for index, each in ipairs(direction.stops or {}) do
		if each.stop_id == stopId then return index end
	end
	return nil
end

-- The next few calls at this stop for one route/direction. The time here is
-- the trip's departure plus this stop's cumulative offset -- the route's
-- origin time is not what you want when you're standing halfway along it.
local function upcomingCalls(route, dirKey, direction, day, nowSeconds)
	local index = stopIndexIn(direction, stop.stop_id)
	if index == nil then return nil end
	-- The last stop is where the trip ends. Standing at a terminus, half the
	-- board would otherwise be buses arriving to go out of service -- real
	-- times, but you can't get on one.
	if index == #direction.stops then return nil end

	local field = (dirKey == "out") and "departure_out" or "departure_in"
	local calls = {}
	for _, entry in ipairs(day.entries or {}) do
		local time = entry[field]
		if time ~= nil and time ~= "" then
			local departure = parseHHMM(time)
			if departure ~= nil then
				local offsets = Store.offsetsForHour(direction, departure // 3600)
				local offset = offsets ~= nil and offsets[index] or nil
				if offset ~= nil then
					local arrival = departure + offset
					local away = arrival - nowSeconds
					-- A night departure is published as "25:05"; against a
					-- clock that already rolled past midnight it looks like
					-- most of a day ago, so bring it back.
					if away < -12 * 3600 then away = away + 24 * 3600 end
					if away >= 0 then
						table.insert(calls, { away = away, arrival = arrival })
					end
				end
			end
		end
	end
	if #calls == 0 then return nil end

	table.sort(calls, function(a, b) return a.away < b.away end)
	while #calls > MAX_TIMES do table.remove(calls) end
	return calls
end

-- Scans every route's two directions for this stop. That's ~107 routes at up
-- to 31 route/direction pairs on the busiest stop, done once when the scene
-- opens rather than kept as a permanent index -- the snapshot is already the
-- big thing in memory.
local function buildDepartures()
	departures = {}
	if Store.data == nil then return end

	local dayKey = Store.scheduleKeyForToday()
	local now = playdate.getTime()
	local nowSeconds = now.hour * 3600 + now.minute * 60 + now.second

	for _, route in ipairs(Store.data.routes) do
		local day = route.timetable ~= nil and route.timetable[dayKey] or nil
		if day ~= nil then
			for _, dirKey in ipairs({ "out", "in" }) do
				local direction = route.directions[dirKey]
				if direction ~= nil then
					local calls = upcomingCalls(route, dirKey, direction, day, nowSeconds)
					if calls ~= nil then
						table.insert(departures, {
							route = route,
							dirKey = dirKey,
							headsign = Text.clean(direction.headsign or ""),
							shortName = Text.clean(route.route_short_name),
							calls = calls,
						})
					end
				end
			end
		end
	end

	-- Soonest first: this is a departure board, not a route index.
	table.sort(departures, function(a, b) return a.calls[1].away < b.calls[1].away end)
end

--- As many times as leave the destination readable -- "the next 2 or 3
--- depending on how many fit", decided per row because a long route number
--- and a long headsign both eat into the same width.
local function labelsThatFit(entry, width)
	local labelStart = Theme.MARGIN + Theme.badgeWidth(entry.shortName, Theme.FONT_TITLE) + Theme.MARGIN
	local labels, used = {}, 0

	for i, call in ipairs(entry.calls) do
		local label = whenLabel(call.away, call.arrival)
		local cost
		if i == 1 then
			cost = Theme.badgeWidth(label, Theme.FONT_SMALL) + Theme.MARGIN
		else
			cost = Theme.FONT_SMALL:getTextWidth(label) + 10
		end
		if width - Theme.MARGIN - used - cost - labelStart < MIN_LABEL_W then break end
		used = used + cost
		table.insert(labels, label)
	end
	return labels
end

function scene:init(__sceneProperties)
	stop = __sceneProperties.stop
	scene.super.init(self)

	buildDepartures()
	crankAccumulator = 0
	favoriteMenuItem = nil

	grid = UI.gridview.new(0, ROW_H)
	grid:setNumberOfRows(math.max(1, #departures))
	grid.scrollCellsToCenter = false
	grid:setScrollDuration(120)

	function grid:drawCell(_, row, _, selected, x, y, width, height)
		local entry = departures[row]
		if entry == nil then return end
		Theme.row(y, height, selected, {
			badge = entry.shortName,
			label = "to " .. entry.headsign,
			accessories = labelsThatFit(entry, width),
			width = width,
		})
	end
end

function scene:start()
	scene.super.start(self)
	favoriteMenuItem = playdate.getSystemMenu():addMenuItem("favorite stop", function()
		Store.setFavoriteStop(stop.stop_id)
	end)
end

function scene:exit()
	scene.super.exit(self)
	if favoriteMenuItem ~= nil then
		playdate.getSystemMenu():removeMenuItem(favoriteMenuItem)
		favoriteMenuItem = nil
	end
end

local function moveSelection(delta)
	if #departures == 0 then return end
	if delta > 0 then
		grid:selectNextRow(false, true, true)
	else
		grid:selectPreviousRow(false, true, true)
	end
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({
		title = stop.stop_name,
		icon = Store.favorites.stop_id == stop.stop_id and "star" or "map-pin",
	})

	if #departures == 0 then
		Theme.emptyState("clock", "Nothing more today", "no departures left from this stop")
	else
		grid:drawInRect(0, Theme.CONTENT_TOP, Theme.WIDTH - 10, listHeight())

		local _, scrollY = grid:getScrollPosition()
		Theme.scrollbarV(
			Theme.WIDTH - 9, Theme.CONTENT_TOP + 2, listHeight() - 4,
			scrollY // ROW_H, listHeight() // ROW_H, #departures
		)
	end

	local hints = {}
	if #departures > 0 then
		table.insert(hints, { pad = "upDown", label = "routes" })
		table.insert(hints, { button = "A", label = "route" })
	end
	table.insert(hints, { button = "B", label = "back" })
	Theme.footer(hints)
end

scene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function()
		local entry = departures[grid:getSelectedRow()]
		if entry ~= nil then
			Nav.push(RouteScene, { route = entry.route, dirKey = entry.dirKey })
		end
	end,
	BButtonDown = function() Nav.pop() end,
	cranked = function(change)
		crankAccumulator = crankAccumulator + change
		while crankAccumulator >= CRANK_DEGREES_PER_ROW do
			moveSelection(1)
			crankAccumulator = crankAccumulator - CRANK_DEGREES_PER_ROW
		end
		while crankAccumulator <= -CRANK_DEGREES_PER_ROW do
			moveSelection(-1)
			crankAccumulator = crankAccumulator + CRANK_DEGREES_PER_ROW
		end
	end,
}
