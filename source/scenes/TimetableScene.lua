-- The CTP timetable for one route in one direction: three day tabs and an
-- hour-grouped grid, the same shape the web app's RouteView uses.
--
-- Every departure is individually selectable, because picking one is the
-- point: A opens TripScene, which turns "the 13:37" into a time for each
-- stop along the way. That is the feature this screen exists to reach.
--
-- Focus moves between the day tabs and the grid, so the d-pad covers both
-- without a modifier: Left/Right switches day on the tabs and steps between
-- departures in the grid, Up from the top row goes back to the tabs.
--
-- Scene properties: { route, dirKey }.

TimetableScene = {}
class("TimetableScene").extends(NobleScene)
local scene = TimetableScene

scene.backgroundColor = Graphics.kColorWhite

local TABS_TOP <const> = 36
local TABS_H <const> = 24
local TABS_RULE_Y <const> = 63
local GRID_TOP <const> = 65
local ROW_H <const> = 21
-- The hour needs a clear gutter before the minutes start, or the row reads as
-- one run-on number.
local HOUR_COLUMN <const> = 54
-- Route 25 puts 12 departures into the 07:00 hour on a weekday, which is the
-- widest row in the whole dataset; the column pitch is sized so that fits.
-- 12 columns from HOUR_COLUMN at this pitch end at x=380, inside GRID_RIGHT.
local COLUMN_W <const> = 27
-- The selected-departure chip, a touch narrower than the pitch so two
-- neighbours never touch.
local CHIP_W <const> = 26
local GRID_RIGHT <const> = 386

local FOCUS_TABS <const> = "tabs"
local FOCUS_GRID <const> = "grid"

local DAY_ORDER <const> = { "weekdays", "saturday", "sunday" }
local DAY_LABELS <const> = { weekdays = "Mon-Fri", saturday = "Saturday", sunday = "Sunday" }

local route, dirKey
local dayKey, focus
local rows = {}
local selectedRow, selectedColumn = 1, 1
local scrollTop, crankAccumulator = 0, 0

-- Backing out of a trip rebuilds this scene from scratch (see lib/nav.lua),
-- so where you were is remembered here, per route and direction. Without it
-- B from a trip always dumped you back on the first hour of today.
local remembered = {}
local rememberKey = nil

local function visibleRows()
	return (Theme.CONTENT_BOTTOM - GRID_TOP) // ROW_H
end

local function clamp(value, lo, hi)
	if value < lo then return lo end
	if value > hi then return hi end
	return value
end

local function day()
	return route.timetable ~= nil and route.timetable[dayKey] or nil
end

local function departureField()
	return (dirKey == "out") and "departure_out" or "departure_in"
end

-- Departures grouped into one row per hour, each keeping the full "HH:MM"
-- so a selected one can be handed straight to TripScene.
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
				table.insert(byHour[hour], { minute = minute, time = time })
			end
			-- `hour` stays raw ("25") so the row sorts after 23 rather than
			-- leaping to the top of the day; only the label wraps.
		end
	end

	local hours = {}
	for hour in pairs(byHour) do table.insert(hours, hour) end
	table.sort(hours)
	for _, hour in ipairs(hours) do
		local departures = byHour[hour]
		table.sort(departures, function(a, b) return a.minute < b.minute end)
		table.insert(rows, {
			hour = hour,
			label = string.format("%02d", tonumber(hour) % 24),
			departures = departures,
		})
	end
end

--- Puts the selection on the next departure at or after right now, so the
--- screen opens on the part of the day you're actually in.
local function selectNextDeparture()
	selectedRow, selectedColumn = 1, 1
	if #rows == 0 then return end

	local now = playdate.getTime()
	local nowMinutes = now.hour * 60 + now.minute
	for rowIndex, row in ipairs(rows) do
		for columnIndex, departure in ipairs(row.departures) do
			if tonumber(row.hour) * 60 + tonumber(departure.minute) >= nowMinutes then
				selectedRow, selectedColumn = rowIndex, columnIndex
				return
			end
		end
	end
	-- Everything today has already gone; sit on the last one.
	selectedRow = #rows
	selectedColumn = #rows[selectedRow].departures
end

local function scrollToSelection()
	local visible = visibleRows()
	scrollTop = clamp(scrollTop, math.max(0, selectedRow - visible), selectedRow - 1)
	scrollTop = clamp(scrollTop, 0, math.max(0, #rows - visible))
end

local function setDay(key)
	dayKey = key
	scrollTop = 0
	crankAccumulator = 0
	buildRows()
	selectNextDeparture()
	scrollToSelection()
	-- 143 of the route/day/direction combinations in the export have no
	-- departures at all. With nothing in the grid to move between, focus has
	-- to sit on the tabs or the d-pad does nothing and the only way off the
	-- screen is B.
	if #rows == 0 then focus = FOCUS_TABS end
end

local function stepDay(delta)
	for i, key in ipairs(DAY_ORDER) do
		if key == dayKey then
			setDay(DAY_ORDER[((i - 1 + delta) % #DAY_ORDER) + 1])
			return
		end
	end
end

--- Steps one departure forward or back, rolling over into the next or
--- previous hour, so the grid reads as one ordered day rather than rows.
local function stepDeparture(delta)
	if #rows == 0 then focus = FOCUS_TABS return end
	local column = selectedColumn + delta

	if column < 1 then
		if selectedRow == 1 then return end
		selectedRow = selectedRow - 1
		selectedColumn = #rows[selectedRow].departures
	elseif column > #rows[selectedRow].departures then
		if selectedRow == #rows then return end
		selectedRow = selectedRow + 1
		selectedColumn = 1
	else
		selectedColumn = column
	end
	scrollToSelection()
end

local function stepHour(delta)
	if #rows == 0 then focus = FOCUS_TABS return end
	if delta < 0 and selectedRow == 1 then
		focus = FOCUS_TABS
		return
	end
	selectedRow = clamp(selectedRow + delta, 1, #rows)
	selectedColumn = clamp(selectedColumn, 1, #rows[selectedRow].departures)
	scrollToSelection()
end

local function selectedDeparture()
	local row = rows[selectedRow]
	if row == nil then return nil end
	return row.departures[selectedColumn]
end

function scene:init(__sceneProperties)
	route = __sceneProperties.route
	dirKey = __sceneProperties.dirKey
	scene.super.init(self)

	rememberKey = route.route_id .. ":" .. tostring(dirKey)
	local saved = remembered[rememberKey]
	if saved == nil then
		focus = FOCUS_GRID
		setDay(Store.scheduleKeyForToday())
		return
	end

	focus = saved.focus
	dayKey = saved.dayKey
	scrollTop = 0
	crankAccumulator = 0
	buildRows()
	selectedRow = clamp(saved.row, 1, math.max(1, #rows))
	local row = rows[selectedRow]
	selectedColumn = row ~= nil and clamp(saved.column, 1, #row.departures) or 1
	scrollToSelection()
end

function scene:exit()
	scene.super.exit(self)
	remembered[rememberKey] = {
		dayKey = dayKey,
		row = selectedRow,
		column = selectedColumn,
		focus = focus,
	}
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
		-- A ring around the active tab shows the d-pad is on the tab strip
		-- rather than down in the grid.
		if selected and focus == FOCUS_TABS then
			Graphics.setColor(Graphics.kColorBlack)
			Graphics.setLineWidth(2)
			Graphics.drawRoundRect(x - 3, TABS_TOP - 3, width + 6, TABS_H + 6, 7)
			Graphics.setLineWidth(1)
		end
	end

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.drawLine(0, TABS_RULE_Y, Theme.WIDTH, TABS_RULE_Y)
end

local function drawGrid()
	local today = day()
	if today == nil then
		Theme.emptyState("square-alert", "No service this day", "pick another day above")
		return
	end

	local frequency = today[(dirKey == "out") and "out_frequency" or "in_frequency"]
	if frequency ~= nil then
		Theme.emptyState("clock",
			string.format("every %d-%d min", frequency.min_minutes, frequency.max_minutes),
			string.format("%s - %s", frequency.start, frequency["end"]))
		return
	end

	if #rows == 0 then
		Theme.emptyState("square-alert", "No service this day", "pick another day above")
		return
	end

	local todaysHour = (dayKey == Store.scheduleKeyForToday())
		and string.format("%02d", playdate.getTime().hour) or nil

	for offset = 0, visibleRows() - 1 do
		local index = scrollTop + offset + 1
		local row = rows[index]
		if row == nil then break end

		local y = GRID_TOP + offset * ROW_H
		local centerY = y + ROW_H // 2

		-- The current hour is marked with a caret in the margin, not a badge
		-- or a filled row: a badge is taller than a 21px row and a fill would
		-- compete with the selected departure, which owns the black on this
		-- screen. A 7px arrow costs no vertical room at all.
		if row.label == todaysHour then
			Graphics.setColor(Graphics.kColorBlack)
			Graphics.fillTriangle(4, centerY - 5, 4, centerY + 5, 11, centerY)
		end
		Theme.textCentered(row.label, Theme.MARGIN + 8, centerY, kTextAlignment.left, Theme.FONT_TITLE)

		for columnIndex, departure in ipairs(row.departures) do
			-- Everything in the cell is placed from its center, so the chip
			-- and the two digits inside it can't drift apart.
			local center = HOUR_COLUMN + (columnIndex - 1) * COLUMN_W + COLUMN_W // 2
			if center + CHIP_W // 2 > GRID_RIGHT then break end

			local isSelected = focus == FOCUS_GRID
				and index == selectedRow and columnIndex == selectedColumn
			if isSelected then
				Graphics.setColor(Graphics.kColorBlack)
				Graphics.fillRoundRect(center - CHIP_W // 2, y + 1, CHIP_W, ROW_H - 2, 4)
				Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite)
			end
			Theme.textCentered(departure.minute, center, centerY, kTextAlignment.center, Theme.FONT_BODY)
			Graphics.setImageDrawMode(Graphics.kDrawModeCopy)
		end
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

	if focus == FOCUS_TABS then
		Theme.footer({
			{ pad = "leftRight", label = "day" },
			{ pad = "upDown", label = "times" },
			{ button = "B", label = "back" },
		})
	else
		Theme.footer({
			{ pad = "leftRight", label = "departure" },
			{ pad = "upDown", label = "hour" },
			{ button = "A", label = "stop times" },
			{ button = "B", label = "back" },
		})
	end
end

scene.inputHandler = {
	leftButtonDown = function()
		if focus == FOCUS_TABS then stepDay(-1) else stepDeparture(-1) end
	end,
	rightButtonDown = function()
		if focus == FOCUS_TABS then stepDay(1) else stepDeparture(1) end
	end,
	upButtonDown = function()
		if focus == FOCUS_GRID then stepHour(-1) end
	end,
	downButtonDown = function()
		if focus == FOCUS_TABS then
			if #rows > 0 then focus = FOCUS_GRID end
		else
			stepHour(1)
		end
	end,
	AButtonDown = function()
		if focus == FOCUS_TABS then
			if #rows > 0 then focus = FOCUS_GRID end
			return
		end
		local departure = selectedDeparture()
		if departure ~= nil then
			Nav.push(TripScene, { route = route, dirKey = dirKey, departure = departure.time })
		end
	end,
	BButtonDown = function() Nav.pop() end,
	cranked = function(change)
		if focus ~= FOCUS_GRID then return end
		crankAccumulator = crankAccumulator + change
		while crankAccumulator >= 15 do
			stepDeparture(1)
			crankAccumulator = crankAccumulator - 15
		end
		while crankAccumulator <= -15 do
			stepDeparture(-1)
			crankAccumulator = crankAccumulator + 15
		end
	end,
}
