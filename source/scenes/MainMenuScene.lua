-- Main Menu: how old the snapshot is, and four ways in -- your favourite
-- routes, your favourite stops, and the full lists of each.
--
-- Favourites get their own screens rather than being listed here. An earlier
-- version put them inline with their next departures, which read as a wall of
-- numbers on a 400x240 screen; the counts belong here and the detail belongs
-- one press away.

MainMenuScene = {}
class("MainMenuScene").extends(NobleScene)
local scene = MainMenuScene

scene.backgroundColor = Graphics.kColorWhite

local BANNER_H <const> = 26
local ROW_H <const> = 34

local rows = {}
local grid = nil
local builtAtRevision = nil
-- Survives leaving and coming back, the way the list screens remember theirs.
local selectedRow = 1

local function listTop()
	return Theme.CONTENT_TOP + BANNER_H
end

-- Each row carries its own action, so the input handler doesn't need to know
-- what the menu is made of.
local function buildRows()
	rows = {
		{
			icon = "heart",
			label = "Favorite routes",
			accessory = #Store.favoriteRoutes() .. "",
			open = function()
				Nav.push(ListScene, {
					key = "favroutes",
					title = "Favorite routes",
					icon = "heart",
					items = Store.favoriteRoutes(),
					refresh = Store.favoriteRoutes,
					emptyIcon = "heart",
					emptyTitle = "No favorite routes",
					emptyDetail = "press right on a route in All routes",
				})
			end,
		},
		{
			icon = "heart",
			label = "Favorite stops",
			accessory = #Store.favoriteStops() .. "",
			open = function()
				Nav.push(ListScene, {
					key = "favstops",
					title = "Favorite stops",
					icon = "heart",
					items = Store.favoriteStops(),
					refresh = Store.favoriteStops,
					emptyIcon = "heart",
					emptyTitle = "No favorite stops",
					emptyDetail = "press right on a stop in All stops",
				})
			end,
		},
		{
			icon = "bus",
			label = "All routes",
			accessory = Store.data and #Store.data.routes .. "" or "0",
			open = function()
				Nav.push(ListScene, { key = "routes", title = "All routes", items = Store.data.routes })
			end,
		},
		{
			icon = "map-pin",
			label = "All stops",
			accessory = Store.data and #Store.data.stops .. "" or "0",
			open = function()
				Nav.push(ListScene, { key = "stops", title = "All stops", items = Store.data.stops })
			end,
		},
	}
end

local function refresh()
	buildRows()
	builtAtRevision = Store.favoritesRevision
	grid:setNumberOfRows(#rows)
	grid:setSelectedRow(math.max(1, math.min(selectedRow, #rows)))
end

function scene:init(__sceneProperties)
	scene.super.init(self)

	grid = UI.gridview.new(0, ROW_H)
	grid.scrollCellsToCenter = false
	grid:setScrollDuration(120)

	function grid:drawCell(_, row, _, selected, x, y, width, height)
		local entry = rows[row]
		if entry == nil then return end
		Theme.row(y, height, selected, {
			icon = entry.icon,
			label = entry.label,
			accessory = entry.accessory,
			width = width,
		})
	end

	refresh()
end

function scene:enter()
	scene.super.enter(self)
	refresh()
end

function scene:update()
	scene.super.update(self)
	-- The counts are the only live thing here, so this is cheap.
	if Store.favoritesRevision ~= builtAtRevision then refresh() end
end

local function moveSelection(delta)
	if delta > 0 then
		grid:selectNextRow(false, true, true)
	else
		grid:selectPreviousRow(false, true, true)
	end
	selectedRow = grid:getSelectedRow()
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({ title = "Conexiuni Cluj" })

	-- How old the snapshot is, with a warning icon once it's worth refreshing.
	local agoText, stale = Store.syncedAgoText()
	local bannerCenterY = Theme.CONTENT_TOP + BANNER_H // 2
	Icons.drawCentered(stale and "square-alert" or "clock", 12, Theme.MARGIN + 6, bannerCenterY)
	if stale then agoText = agoText .. " - update recommended" end
	Theme.textCentered(agoText, Theme.MARGIN + 20, bannerCenterY, kTextAlignment.left, Theme.FONT_SMALL)

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(0, listTop(), Theme.WIDTH, listTop())

	grid:drawInRect(0, listTop() + 1, Theme.WIDTH, ROW_H * #rows)

	Theme.footer({ { button = "A", label = "open" }, { button = "B", label = "sync now" } })
end

scene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function()
		local entry = rows[grid:getSelectedRow()]
		if entry ~= nil then entry.open() end
	end,
	BButtonDown = function()
		-- Root screen: there's nothing to go back to, so B re-syncs.
		Nav.reset(SyncScene)
	end,
}
