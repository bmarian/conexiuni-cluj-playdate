-- The city and how old its timetables are, and the ways in: favorite lines,
-- favorite stops, the full lists of each, and the city list.

MainMenuScene = {}
class("MainMenuScene").extends(NobleScene)
local scene = MainMenuScene

scene.backgroundColor = Graphics.kColorWhite

local BANNER_H <const> = 26
local ROW_H <const> = 30

local rows = {}
local grid = nil
local builtAtRevision = nil
-- Kept across visits.
local selectedRow = 1
local favoriteMenuItem = nil

local function listTop()
    return Theme.CONTENT_TOP + BANNER_H
end

-- Each row carries its own action.
local function buildRows()
    rows = {
        {
            icon = "heart",
            label = "Favorite lines",
            accessory = #Store.favoriteRoutes() .. "",
            open = function()
                Nav.push(ListScene, {
                    key = "favroutes",
                    title = "Favorite lines",
                    icon = "heart",
                    items = Store.favoriteRoutes(),
                    refresh = Store.favoriteRoutes,
                    emptyIcon = "heart",
                    emptyTitle = "No favorite lines",
                    emptyDetail = "press right on a line in All lines",
                })
            end,
        },
        {
            icon = "heart",
            label = "Favorite stops",
            accessory = #Store.favoriteStations() .. "",
            open = function()
                Nav.push(ListScene, {
                    key = "favstops",
                    title = "Favorite stops",
                    icon = "heart",
                    items = Store.favoriteStations(),
                    refresh = Store.favoriteStations,
                    emptyIcon = "heart",
                    emptyTitle = "No favorite stops",
                    emptyDetail = "press right on a stop in All stops",
                })
            end,
        },
        {
            icon = "bus",
            label = "All lines",
            accessory = Store.data and #Store.data.routes .. "" or "0",
            open = function()
                Nav.push(ListScene, { key = "routes", title = "All lines", items = Store.data.routes })
            end,
        },
        {
            icon = "map-pin",
            label = "All stops",
            accessory = Store.data and #Store.data.stations .. "" or "0",
            open = function()
                Nav.push(ListScene, { key = "stops", title = "All stops", items = Store.data.stations })
            end,
        },
        {
            icon = "map-pin",
            label = "City",
            accessory = Text.clean(Store.city ~= nil and Store.city.name or ""),
            open = function()
                Nav.push(CityScene)
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

    favoriteMenuItem = nil

    refresh()
end

function scene:start()
    scene.super.start(self)

    local function install()
        if favoriteMenuItem ~= nil then
            playdate.getSystemMenu():removeMenuItem(favoriteMenuItem)
        end
        favoriteMenuItem = playdate.getSystemMenu():addMenuItem("Sync now", function()
            Nav.reset(SyncScene)
        end)
    end
    install()
end

function scene:exit()
    scene.super.exit(self)

    if favoriteMenuItem ~= nil then
        playdate.getSystemMenu():removeMenuItem(favoriteMenuItem)
        favoriteMenuItem = nil
    end
end

function scene:enter()
    scene.super.enter(self)
    refresh()
end

function scene:update()
    scene.super.update(self)
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

    Theme.header({ title = "Ce autobuz iau?" })

    -- How old the timetables are, with a warning icon once it's worth refreshing.
    local agoText, stale = Store.syncedAgoText()
    local bannerCenterY = Theme.CONTENT_TOP + BANNER_H // 2
    Icons.drawCentered(stale and "square-alert" or "clock", 12, Theme.MARGIN + 6, bannerCenterY)
    if stale then agoText = agoText .. " - update recommended" end
    Theme.textCentered(agoText, Theme.MARGIN + 20, bannerCenterY, kTextAlignment.left, Theme.FONT_SMALL)

    Graphics.setColor(Graphics.kColorBlack)
    Graphics.setLineWidth(1)
    Graphics.drawLine(0, listTop(), Theme.WIDTH, listTop())

    grid:drawInRect(0, listTop() + 1, Theme.WIDTH, ROW_H * #rows)

    Theme.footer({ { button = "A", label = "open" } })
end

scene.inputHandler = {
    upButtonDown = function() moveSelection(-1) end,
    downButtonDown = function() moveSelection(1) end,
    AButtonDown = function()
        local entry = rows[grid:getSelectedRow()]
        if entry ~= nil then entry.open() end
    end,
}
