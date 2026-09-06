-- The scrollable list behind both "All routes" and "All stops". One scene,
-- two configurations, so the two lists can't drift apart visually.
--
-- Built on playdate.ui.gridview rather than Noble.Menu: Noble.Menu draws
-- every item at once, which is fine for a four-item menu and wrong for a
-- hundred routes. gridview windows and clips for us.
--
-- Scene properties: { key, title, items }.

ListScene = {}
class("ListScene").extends(NobleScene)
local scene = ListScene

scene.backgroundColor = Graphics.kColorWhite

local ROW_H <const> = 30
local CRANK_DEGREES_PER_ROW <const> = 12

-- Coming back from a detail screen rebuilds this scene from scratch (see
-- lib/nav.lua), so the selected row is remembered per list here.
local selectedRows = {}

local key, title, items
local grid = nil
local crankAccumulator = 0

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

function scene:init(__sceneProperties)
	scene.super.init(self)

	key = __sceneProperties.key
	title = __sceneProperties.title
	items = __sceneProperties.items or {}
	crankAccumulator = 0

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
			})
		else
			Theme.row(y, height, selected, {
				icon = "map-pin",
				label = item.stop_name,
			})
		end
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
		icon = key == "routes" and "bus" or "map-pin",
	})

	if #items == 0 then
		Theme.emptyState("square-alert", "Nothing synced yet", "sync from the main menu")
	else
		local height = Theme.contentHeight()
		grid:drawInRect(0, Theme.CONTENT_TOP, Theme.WIDTH - 10, height)

		local _, scrollY = grid:getScrollPosition()
		Theme.scrollbarV(
			Theme.WIDTH - 9, Theme.CONTENT_TOP + 2, height - 4,
			scrollY // ROW_H, height // ROW_H, #items
		)
	end

	Theme.footer({ { button = "A", label = "open" }, { button = "B", label = "back" } })
end

scene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
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
