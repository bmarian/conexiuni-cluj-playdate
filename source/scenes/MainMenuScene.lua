-- Main Menu: when the snapshot was synced, the two favourites, and the way
-- into the full route and stop lists.
--
-- The four entries are a Noble.Menu (it owns selection and click handling),
-- but every row is drawn through Theme.row, so they are the same rows as the
-- ones on the list screens rather than a second, menu-shaped design.

MainMenuScene = {}
class("MainMenuScene").extends(NobleScene)
local scene = MainMenuScene

scene.backgroundColor = Graphics.kColorWhite

local BANNER_H <const> = 26
local ROW_H <const> = 34

local menu = nil
local rows = {}
-- Coming back from a detail screen rebuilds the scene (see lib/nav.lua), so
-- the highlight is remembered here rather than resetting to the top row --
-- same as the list screens do.
local selectedRow = 1

local function favoriteRoute()
	return Store.favorites.route_id ~= nil and Store.findRoute(Store.favorites.route_id) or nil
end

local function favoriteStop()
	return Store.favorites.stop_id ~= nil and Store.findStop(Store.favorites.stop_id) or nil
end

-- Rebuilt every frame: the accessory text on the favourite rows changes as
-- soon as a favourite is set on another screen, and it costs two lookups.
local function buildRows()
	local route = favoriteRoute()
	local stop = favoriteStop()
	local routeCount = Store.data and #Store.data.routes or 0
	local stopCount = Store.data and #Store.data.stops or 0

	rows = {
		{
			icon = "star",
			label = route and Text.clean(route.route_long_name) or "Favorite route",
			badge = route and Text.clean(route.route_short_name) or nil,
			accessory = route == nil and "not set" or nil,
		},
		{
			icon = "star",
			label = stop and Text.clean(stop.stop_name) or "Favorite stop",
			accessory = stop == nil and "not set" or nil,
		},
		{ icon = "bus", label = "All routes", accessory = routeCount .. "" },
		{ icon = "map-pin", label = "All stops", accessory = stopCount .. "" },
	}
end

function scene:init(__sceneProperties)
	scene.super.init(self)

	buildRows()

	menu = Noble.Menu.new(
		true, Noble.Text.ALIGN_LEFT, false, Graphics.kColorBlack,
		math.max(0, ROW_H - Theme.FONT_BODY:getHeight()), -- padding: sets the row height
		nil,
		0,                                                -- margin: rows sit flush, like a list
		Theme.FONT_BODY
	)

	menu:addItem("Favorite route", function()
		local route = favoriteRoute()
		if route ~= nil then Nav.push(RouteScene, { route = route }) end
	end)
	menu:addItem("Favorite stop", function()
		local stop = favoriteStop()
		if stop ~= nil then Nav.push(StopScene, { stop = stop }) end
	end)
	menu:addItem("All routes", function()
		Nav.push(ListScene, { key = "routes", title = "All routes", items = Store.data.routes })
	end)
	menu:addItem("All stops", function()
		Nav.push(ListScene, { key = "stops", title = "All stops", items = Store.data.stops })
	end)

	-- Noble.Menu draws item text itself; this hands each row to the shared
	-- row widget instead, so icons/badges/accessories come along for free.
	function menu:drawCell(_, row, _, selected, x, y, width, height)
		Theme.row(y, height, selected, rows[row] or {})
	end

	menu:setSelectedRow(selectedRow)
end

local function moveSelection(delta)
	if delta > 0 then
		menu:selectNext(false, true)
	else
		menu:selectPrevious(false, true)
	end
	selectedRow = menu:getSelectedRow()
end

function scene:drawBackground()
	scene.super.drawBackground(self)
	buildRows()

	Theme.header({ title = "Conexiuni Cluj" })

	-- Sync banner: how old the snapshot is, and a warning icon once it's old
	-- enough to be worth refreshing.
	local agoText, stale = Store.syncedAgoText()
	local bannerCenterY = Theme.CONTENT_TOP + BANNER_H // 2
	Icons.drawCentered(stale and "square-alert" or "clock", 12, Theme.MARGIN + 6, bannerCenterY)
	if stale then agoText = agoText .. " - update recommended" end
	Theme.textCentered(agoText, Theme.MARGIN + 20, bannerCenterY, kTextAlignment.left, Theme.FONT_SMALL)

	local top = Theme.CONTENT_TOP + BANNER_H
	Graphics.setColor(Graphics.kColorBlack)
	Graphics.drawLine(0, top, Theme.WIDTH, top)
	menu:drawInRect(0, top + 1, Theme.WIDTH, ROW_H * #rows)

	Theme.footer({ { button = "A", label = "open" }, { button = "B", label = "sync now" } })
end

scene.inputHandler = {
	upButtonDown = function() moveSelection(-1) end,
	downButtonDown = function() moveSelection(1) end,
	AButtonDown = function() menu:click() end,
	BButtonDown = function()
		-- Root screen: there's nothing to go back to, so B re-syncs.
		Nav.reset(SyncScene)
	end,
}
