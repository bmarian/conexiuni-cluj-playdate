-- The cities the server has, the ones already downloaded marked. Picking one
-- opens it, syncing first if it has never been downloaded.

CityScene = {}
class("CityScene").extends(NobleScene)
local scene = CityScene

scene.backgroundColor = Graphics.kColorWhite

local ROW_H <const> = 30
local CRANK_DEGREES_PER_ROW <const> = 12

local cities = {}
-- Checked once per list, not per frame.
local downloaded = {}
local grid = nil
local crankAccumulator = 0
local loading, failure = false, nil

local function selectCurrent()
    if Store.city == nil then return end
    for index, city in ipairs(cities) do
        if city.slug == Store.city.slug then
            grid:setSelectedRow(index)
            grid:scrollCellToCenter(1, index, 1, false)
            return
        end
    end
end

local function show(list)
    cities = list or {}
    downloaded = {}
    for _, city in ipairs(cities) do downloaded[city.slug] = Store.hasData(city.slug) end
    grid:setNumberOfRows(math.max(1, #cities))
    selectCurrent()
end

local function refresh()
    loading, failure = true, nil
    Store.fetchCities(function(list, err)
        loading = false
        if list ~= nil then
            show(list)
        else
            failure = err
        end
    end)
end

local function open(city)
    if city == nil then return end
    Store.setCity(city)
    if Store.load() then
        Nav.reset(MainMenuScene)
    else
        Nav.reset(SyncScene)
    end
end

function scene:init(__sceneProperties)
    scene.super.init(self)
    crankAccumulator = 0

    grid = UI.gridview.new(0, ROW_H)
    grid.scrollCellsToCenter = false
    grid:setScrollDuration(120)

    function grid:drawCell(_, row, _, selected, x, y, width, height)
        local city = cities[row]
        if city == nil then return end
        local current = Store.city ~= nil and Store.city.slug == city.slug
        Theme.row(y, height, selected, {
            icon = "map-pin",
            label = city.name,
            accessory = (current and "current") or (downloaded[city.slug] and "downloaded") or nil,
            width = width,
        })
    end

    show(Store.cities)
end

function scene:enter()
    scene.super.enter(self)
    refresh()
end

local function moveSelection(delta)
    if #cities == 0 then return end
    if delta > 0 then
        grid:selectNextRow(false, true, true)
    else
        grid:selectPreviousRow(false, true, true)
    end
end

function scene:drawBackground()
    scene.super.drawBackground(self)

    Theme.header({ title = "Pick a city", icon = "map-pin" })

    if #cities == 0 then
        if failure ~= nil then
            Theme.emptyState("square-alert", "No connection", Text.truncateToWidth(failure, 360, Theme.FONT_SMALL))
        else
            Theme.emptyState("reload", "Finding cities", "the list comes from ceautobuziau.ro")
        end
    else
        local height = Theme.contentHeight()
        grid:drawInRect(0, Theme.CONTENT_TOP, Theme.WIDTH - 10, height)

        local _, scrollY = grid:getScrollPosition()
        Theme.scrollbarV(
            Theme.WIDTH - 9, Theme.CONTENT_TOP + 2, height - 4,
            scrollY // ROW_H, height // ROW_H, #cities
        )
    end

    local hints = {}
    if #cities > 0 then table.insert(hints, { button = "A", label = "open" }) end
    if #cities == 0 and failure ~= nil then table.insert(hints, { button = "A", label = "retry" }) end
    if Store.data ~= nil then table.insert(hints, { button = "B", label = "back" }) end
    Theme.footer(hints)
end

scene.inputHandler = {
    upButtonDown = function() moveSelection(-1) end,
    downButtonDown = function() moveSelection(1) end,
    AButtonDown = function()
        if #cities == 0 then
            if not loading then refresh() end
            return
        end
        open(cities[grid:getSelectedRow()])
    end,
    BButtonDown = function()
        if Store.data ~= nil then Nav.pop() end
    end,
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
