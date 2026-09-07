-- What is leaving this stop, soonest first, one row per route and direction.
-- Properties: { stop }.

StopScene = {}
class("StopScene").extends(NobleScene)
local scene = StopScene

scene.backgroundColor = Graphics.kColorWhite

local ROW_H <const> = 30
local MAX_TIMES <const> = 3
-- Below this the headsign is useless, so a row drops its later times instead.
local MIN_LABEL_W <const> = 104
local CRANK_DEGREES_PER_ROW <const> = 12

local stop
local departures = {}
local grid = nil
local crankAccumulator = 0
local favoriteMenuItem = nil
local builtAtMinute = nil
-- Selection per stop, so backing out of a route returns to it.
local rememberedRows = {}

local function listHeight()
	return Theme.CONTENT_BOTTOM - Theme.CONTENT_TOP
end

-- As many times as fit while the destination stays readable, decided per row.
local function labelsThatFit(entry, width)
	local labelStart = Theme.MARGIN + Theme.badgeWidth(entry.shortName, Theme.FONT_TITLE) + Theme.MARGIN
	local labels, used = {}, 0

	for i, call in ipairs(entry.calls) do
		local label = Text.whenLabel(call.away, call.arrival)
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

	departures = Store.departuresAtStop(stop.stop_id, MAX_TIMES)
	builtAtMinute = playdate.getTime().minute
	crankAccumulator = 0
	favoriteMenuItem = nil

	grid = UI.gridview.new(0, ROW_H)
	grid:setNumberOfRows(math.max(1, #departures))
	grid.scrollCellsToCenter = false
	grid:setScrollDuration(120)

	local saved = rememberedRows[stop.stop_id]
	if saved ~= nil and #departures > 0 then
		grid:setSelectedRow(math.min(saved, #departures))
		grid:scrollCellToCenter(1, math.min(saved, #departures), 1, false)
	end

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

-- Rebuilt once a minute so the countdowns tick and gone departures drop off.
function scene:update()
	scene.super.update(self)
	local minute = playdate.getTime().minute
	if minute ~= builtAtMinute then
		builtAtMinute = minute
		local selected = grid:getSelectedRow()
		departures = Store.departuresAtStop(stop.stop_id, MAX_TIMES)
		grid:setNumberOfRows(math.max(1, #departures))
		grid:setSelectedRow(math.min(selected, math.max(1, #departures)))
	end
end

local function favoriteLabel()
	return Store.isFavoriteStop(stop.stop_id) and "unfavorite stop" or "favorite stop"
end

function scene:start()
	scene.super.start(self)
	-- The label says what pressing it will do, so it is rebuilt on change.
	local function install()
		if favoriteMenuItem ~= nil then
			playdate.getSystemMenu():removeMenuItem(favoriteMenuItem)
		end
		favoriteMenuItem = playdate.getSystemMenu():addMenuItem(favoriteLabel(), function()
			Store.toggleFavoriteStop(stop.stop_id)
			install()
		end)
	end
	install()
end

function scene:exit()
	scene.super.exit(self)
	rememberedRows[stop.stop_id] = grid:getSelectedRow()
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
		icon = Store.isFavoriteStop(stop.stop_id) and "heart" or nil,
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
			-- Pass the stop so the route line opens where you are standing.
			Nav.push(RouteScene, {
				route = entry.route,
				dirKey = entry.dirKey,
				stopId = stop.stop_id,
			})
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
