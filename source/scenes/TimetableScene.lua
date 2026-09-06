-- The CTP timetable for one route in one direction: three day tabs and an
-- hour-grouped grid, the same shape the web app's RouteView uses.
--
-- It used to be an overlay drawn on top of Route Detail, which is why the two
-- screens had different headers and different footers. It's a scene now, so
-- it gets the same chrome as everything else and B just goes back.
--
-- Scene properties: { route, dirKey }.

TimetableScene = {}
class("TimetableScene").extends(NobleScene)
local scene = TimetableScene

scene.backgroundColor = Graphics.kColorWhite

local TABS_TOP <const> = 32
local TABS_H <const> = 24
local TABS_RULE_Y <const> = 59
local GRID_TOP <const> = 61
local ROW_H <const> = 21
local HOUR_COLUMN <const> = 52
local CRANK_DEGREES_PER_ROW <const> = 15

local DAY_ORDER <const> = { "weekdays", "saturday", "sunday" }
local DAY_LABELS <const> = { weekdays = "Mon-Fri", saturday = "Saturday", sunday = "Sunday" }

local route, dirKey
local dayKey, scrollTop, crankAccumulator
local rows = {}

local function visibleRows()
	return (Theme.CONTENT_BOTTOM - GRID_TOP) // ROW_H
end

local function clamp(value, lo, hi)
	if value < lo then return lo end
	if value > hi then return hi end
	return value
end

local function scheduleKeyForToday()
	local weekday = playdate.getTime().weekday
	if weekday == 7 then return "sunday" end
	if weekday == 6 then return "saturday" end
	return "weekdays"
end

local function day()
	return route.timetable ~= nil and route.timetable[dayKey] or nil
end

local function departureField()
	return (dirKey == "out") and "departure_out" or "departure_in"
end

-- Departures grouped into one row per hour: { hour = "07", minutes = "15 35 55" }.
local function buildRows()
	rows = {}
	local today = day()
	if today == nil then return end

	local byHour = {}
	for _, entry in ipairs(today.entries or {}) do
		local time = entry[departureField()]
		if time ~= nil and time ~= "" then
			local hour, minute = time:match("(%d+):(%d+)")
			if hour ~= nil then
				byHour[hour] = byHour[hour] or {}
				table.insert(byHour[hour], minute)
			end
		end
	end

	local hours = {}
	for hour in pairs(byHour) do table.insert(hours, hour) end
	table.sort(hours)
	for _, hour in ipairs(hours) do
		table.sort(byHour[hour])
		table.insert(rows, { hour = hour, minutes = table.concat(byHour[hour], "  ") })
	end
end

local function setDay(key)
	dayKey = key
	scrollTop = 0
	crankAccumulator = 0
	buildRows()
end

local function stepDay(delta)
	for i, key in ipairs(DAY_ORDER) do
		if key == dayKey then
			setDay(DAY_ORDER[((i - 1 + delta) % #DAY_ORDER) + 1])
			return
		end
	end
end

local function scroll(delta)
	scrollTop = clamp(scrollTop + delta, 0, math.max(0, #rows - visibleRows()))
end

function scene:init(__sceneProperties)
	scene.super.init(self)
	route = __sceneProperties.route
	dirKey = __sceneProperties.dirKey
	setDay(scheduleKeyForToday())
end

local function drawTabs()
	local width = (Theme.WIDTH - 2 * Theme.MARGIN - 8) // #DAY_ORDER
	local centerY = TABS_TOP + TABS_H // 2

	for i, key in ipairs(DAY_ORDER) do
		local x = Theme.MARGIN + (i - 1) * (width + 4)
		local selected = key == dayKey
		if selected then
			Graphics.setColor(Graphics.kColorBlack)
			Graphics.fillRoundRect(x, TABS_TOP, width, TABS_H, 5)
			Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite)
		end
		Theme.textCentered(DAY_LABELS[key], x + width // 2, centerY, kTextAlignment.center, Theme.FONT_TITLE)
		Graphics.setImageDrawMode(Graphics.kDrawModeCopy)
	end

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(0, TABS_RULE_Y, Theme.WIDTH, TABS_RULE_Y)
end

local function drawGrid()
	local today = day()
	if today == nil then
		Theme.emptyState(nil, "No schedule for this day")
		return
	end

	-- Some routes are published as a headway window rather than a departure
	-- list; that's one line, not a grid.
	local frequency = today[(dirKey == "out") and "out_frequency" or "in_frequency"]
	if frequency ~= nil then
		Theme.emptyState("clock",
			string.format("every %d-%d min", frequency.min_minutes, frequency.max_minutes),
			string.format("%s - %s", frequency.start, frequency["end"]))
		return
	end

	if #rows == 0 then
		Theme.emptyState(nil, "No departures listed")
		return
	end

	scrollTop = clamp(scrollTop, 0, math.max(0, #rows - visibleRows()))
	local todaysHour = (dayKey == scheduleKeyForToday())
		and string.format("%02d", playdate.getTime().hour) or nil

	for offset = 0, visibleRows() - 1 do
		local index = scrollTop + offset + 1
		local row = rows[index]
		if row == nil then break end

		local y = GRID_TOP + offset * ROW_H
		local centerY = y + ROW_H // 2
		local isNow = row.hour == todaysHour
		if isNow then
			Graphics.setColor(Graphics.kColorBlack)
			Graphics.fillRect(0, y, Theme.WIDTH - 10, ROW_H)
			Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite)
		end

		Theme.textCentered(row.hour, Theme.MARGIN + 8, centerY, kTextAlignment.left, Theme.FONT_TITLE)
		local available = Theme.WIDTH - HOUR_COLUMN - 20
		Theme.textCentered(
			Text.truncateToWidth(row.minutes, available, Theme.FONT_BODY),
			HOUR_COLUMN, centerY, kTextAlignment.left, Theme.FONT_BODY
		)

		Graphics.setImageDrawMode(Graphics.kDrawModeCopy)
	end

	Theme.scrollbarV(
		Theme.WIDTH - 9, GRID_TOP, visibleRows() * ROW_H,
		scrollTop, visibleRows(), #rows
	)
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	local headsign = route.directions[dirKey] ~= nil and route.directions[dirKey].headsign or ""
	Theme.header({
		title = "to " .. Text.clean(headsign),
		badge = Text.clean(route.route_short_name),
		icon = "calendar",
	})

	drawTabs()
	drawGrid()

	Theme.footer({ { pad = "leftRight", label = "day" }, { button = "B", label = "back" } })
end

scene.inputHandler = {
	leftButtonDown = function() stepDay(-1) end,
	rightButtonDown = function() stepDay(1) end,
	upButtonDown = function() scroll(-1) end,
	downButtonDown = function() scroll(1) end,
	BButtonDown = function() Nav.pop() end,
	cranked = function(change)
		crankAccumulator = crankAccumulator + change
		while crankAccumulator >= CRANK_DEGREES_PER_ROW do
			scroll(1)
			crankAccumulator = crankAccumulator - CRANK_DEGREES_PER_ROW
		end
		while crankAccumulator <= -CRANK_DEGREES_PER_ROW do
			scroll(-1)
			crankAccumulator = crankAccumulator + CRANK_DEGREES_PER_ROW
		end
	end,
}
