-- One list for All routes, All stops and both favorites screens. Properties:
-- { key, title, items, icon, emptyIcon, emptyTitle, emptyDetail, refresh }.

ListScene = {}
class("ListScene").extends(NobleScene)
local scene = ListScene

scene.backgroundColor = Graphics.kColorWhite

local ROW_H <const> = 30
local CRANK_DEGREES_PER_ROW <const> = 12

-- Scenes are rebuilt on pop, so the selection is kept per list here.
local selectedRows = {}

local key, title, items, options
local grid = nil
local crankAccumulator = 0
local builtAtRevision = nil

local function isRoute(item)
	return item.route_short_name ~= nil
end

local function open(item)
	if isRoute(item) then
		Nav.push(RouteScene, { route = item })
	else
		Nav.push(StopScene, { stop = item })
	end
end

-- Right adds, Left removes. Not a toggle: from a list you often add several
-- in a row, and a toggle means checking the heart before each press.
local function setFavorite(item, favorite)
	if item == nil then return end
	if isRoute(item) then
		if Store.isFavoriteRoute(item.route_id) ~= favorite then
			Store.toggleFavoriteRoute(item.route_id)
		end
	elseif Store.isFavoriteStop(item.stop_id) ~= favorite then
		Store.toggleFavoriteStop(item.stop_id)
	end
end

function scene:init(__sceneProperties)
	scene.super.init(self)

	options = __sceneProperties
	key = __sceneProperties.key
	title = __sceneProperties.title
	-- A refreshable list rebuilds rather than trust the array it was pushed
	-- with, which may be stale by the time you come back.
	if __sceneProperties.refresh ~= nil then
		items = __sceneProperties.refresh() or {}
	else
		items = __sceneProperties.items or {}
	end
	builtAtRevision = Store.favoritesRevision
	crankAccumulator = 0

	-- gridview windows and clips; Noble.Menu draws every item at once.
	grid = UI.gridview.new(0, ROW_H) -- cell width 0 = full width
	grid:setNumberOfRows(math.max(1, #items))
	grid.scrollCellsToCenter = false
	grid:setScrollDuration(120)
	if selectedRows[key] ~= nil then
		grid:setSelectedRow(math.min(selectedRows[key], #items))
		grid:scrollCellToCenter(1, selectedRows[key], 1, false)
	end

	function grid:drawCell(_, row, _, selected, x, y, width, height)
		local item = items[row]
		if item == nil then return end
		if isRoute(item) then
			Theme.row(y, height, selected, {
				badge = Text.clean(item.route_short_name),
				label = item.route_long_name,
				markIcon = Store.isFavoriteRoute(item.route_id) and "heart" or nil,
				width = width,
			})
		else
			Theme.row(y, height, selected, {
				icon = "map-pin",
				label = item.stop_name,
				markIcon = Store.isFavoriteStop(item.stop_id) and "heart" or nil,
				width = width,
			})
		end
	end
end

-- A favorites list has to drop a row as soon as it stops being one, or Left
-- appears to do nothing.
function scene:update()
	scene.super.update(self)
	if options.refresh == nil or Store.favoritesRevision == builtAtRevision then return end

	builtAtRevision = Store.favoritesRevision
	items = options.refresh() or {}
	grid:setNumberOfRows(math.max(1, #items))
	if #items > 0 then
		grid:setSelectedRow(math.min(grid:getSelectedRow(), #items))
		selectedRows[key] = grid:getSelectedRow()
	end
end

local function moveSelection(delta)
	if #items == 0 then return end
	if delta > 0 then
		grid:selectNextRow(false, true, true)
	else
		grid:selectPreviousRow(false, true, true)
	end
	selectedRows[key] = grid:getSelectedRow()
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({
		title = title,
		icon = options.icon,
	})

	if #items == 0 then
		Theme.emptyState(
			options.emptyIcon or "square-alert",
			options.emptyTitle or "Nothing synced yet",
			options.emptyDetail or "sync from the main menu"
		)
	else
		local height = Theme.contentHeight()
		grid:drawInRect(0, Theme.CONTENT_TOP, Theme.WIDTH - 10, height)

		local _, scrollY = grid:getScrollPosition()
		Theme.scrollbarV(
			Theme.WIDTH - 9, Theme.CONTENT_TOP + 2, height - 4,
			scrollY // ROW_H, height // ROW_H, #items
		)
	end

	local hints = {}
	if #items > 0 then
		table.insert(hints, { button = "A", label = "open" })
		table.insert(hints, { pad = "right", label = "favorite" })
		table.insert(hints, { pad = "left", label = "remove" })
	end
	table.insert(hints, { button = "B", label = "back" })
	Theme.footer(hints)
end

scene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	rightButtonDown = function() setFavorite(items[grid:getSelectedRow()], true) end,
	leftButtonDown = function() setFavorite(items[grid:getSelectedRow()], false) end,
	AButtonDown = function()
		local item = items[grid:getSelectedRow()]
		if item ~= nil then open(item) end
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
