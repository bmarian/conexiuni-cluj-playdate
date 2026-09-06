-- One departure, stop by stop: pick "the 13:37" in the timetable and this
-- says what time it reaches every stop on the way. The web app's most-used
-- view, and the reason the export carries `hourly_offset_seconds` at all.
--
-- Purely schedule math against the snapshot -- departure time plus that
-- stop's cumulative offset for the departure's hour. No live data, same as
-- everywhere else in this app.
--
-- Scene properties: { route, dirKey, departure = "13:37" }.

TripScene = {}
class("TripScene").extends(NobleScene)
local scene = TripScene

scene.backgroundColor = Graphics.kColorWhite

local HEADSIGN_CENTER_Y <const> = 47
local HEADSIGN_RULE_Y <const> = 61
local LIST_TOP <const> = 62
local ROW_H <const> = 30
local CRANK_DEGREES_PER_ROW <const> = 12

local route, dirKey, departure
local calls = {}   -- { stopName, timeLabel, isNow }
local grid = nil
local crankAccumulator = 0

local function listHeight()
	return Theme.CONTENT_BOTTOM - LIST_TOP
end

local function parseHHMM(s)
	local hour, minute = s:match("(%d+):(%d+)")
	if hour == nil then return nil end
	return tonumber(hour) * 3600 + tonumber(minute) * 60
end

local function formatClock(seconds)
	-- A late trip can run past midnight; wrap rather than printing "24:10".
	seconds = seconds % (24 * 3600)
	return string.format("%02d:%02d", seconds // 3600, (seconds % 3600) // 60)
end

-- Builds one row per stop. The offsets are the ones for the hour the trip
-- departs in, not the current hour -- this screen is about that departure,
-- which may be hours away.
local function buildCalls()
	calls = {}

	local direction = route.directions[dirKey]
	if direction == nil then return end

	local departureSeconds = parseHHMM(departure)
	if departureSeconds == nil then return end

	local offsets = Store.offsetsForHour(direction, departureSeconds // 3600)
	if offsets == nil then return end

	-- Only mark a "you are here" stop while this trip is actually running.
	-- Without the upper bound every finished trip marks its last stop, since
	-- "elapsed is past the final offset" is true for the rest of the day.
	local now = playdate.getTime()
	local nowSeconds = now.hour * 3600 + now.minute * 60 + now.second
	local elapsed = nowSeconds - departureSeconds
	local total = offsets[#direction.stops]
	local running = total ~= nil and elapsed >= 0 and elapsed <= total

	for index, stop in ipairs(direction.stops) do
		local offset = offsets[index]
		if offset ~= nil then
			local nextOffset = offsets[index + 1]
			table.insert(calls, {
				stopName = stop.stop_name,
				timeLabel = formatClock(departureSeconds + offset),
				isNow = running and elapsed >= offset
					and (nextOffset == nil or elapsed < nextOffset),
			})
		end
	end
end

function scene:init(__sceneProperties)
	route = __sceneProperties.route
	dirKey = __sceneProperties.dirKey
	departure = __sceneProperties.departure
	scene.super.init(self)

	buildCalls()
	crankAccumulator = 0

	grid = UI.gridview.new(0, ROW_H)
	grid:setNumberOfRows(math.max(1, #calls))
	grid.scrollCellsToCenter = false
	grid:setScrollDuration(120)

	-- Open on the stop the bus should be at, when the trip is under way.
	for index, call in ipairs(calls) do
		if call.isNow then
			grid:setSelectedRow(index)
			grid:scrollCellToCenter(1, index, 1, false)
			break
		end
	end

	function grid:drawCell(_, row, _, selected, x, y, width, height)
		local call = calls[row]
		if call == nil then return end
		Theme.row(y, height, selected, {
			icon = call.isNow and "bus" or "map-pin",
			label = call.stopName,
			accessory = call.timeLabel,
			-- The times are the whole point of this screen, so they get the
			-- body face rather than the small one accessories usually take.
			accessoryFont = Theme.FONT_BODY,
			width = width,
		})
	end
end

local function moveSelection(delta)
	if #calls == 0 then return end
	if delta > 0 then
		grid:selectNextRow(false, true, true)
	else
		grid:selectPreviousRow(false, true, true)
	end
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({
		-- The raw value can be "25:05"; that's the right thing to do the
		-- maths with and the wrong thing to show anybody.
		title = "Departing " .. Text.clockLabel(departure),
		badge = Text.clean(route.route_short_name),
		icon = "clock",
	})

	local direction = route.directions[dirKey]
	local headsign = direction ~= nil and Text.clean(direction.headsign or "") or ""
	Theme.textCentered(
		Text.truncateToWidth("to " .. headsign, Theme.WIDTH - 2 * Theme.MARGIN, Theme.FONT_TITLE),
		Theme.MARGIN, HEADSIGN_CENTER_Y, kTextAlignment.left, Theme.FONT_TITLE
	)
	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(0, HEADSIGN_RULE_Y, Theme.WIDTH, HEADSIGN_RULE_Y)

	if #calls == 0 then
		Theme.emptyState("square-alert", "No stop times for this trip")
	else
		grid:drawInRect(0, LIST_TOP, Theme.WIDTH - 10, listHeight())

		local _, scrollY = grid:getScrollPosition()
		Theme.scrollbarV(
			Theme.WIDTH - 9, LIST_TOP + 2, listHeight() - 4,
			scrollY // ROW_H, listHeight() // ROW_H, #calls
		)
	end

	Theme.footer({ { pad = "upDown", label = "stops" }, { button = "B", label = "back" } })
end

scene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
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
