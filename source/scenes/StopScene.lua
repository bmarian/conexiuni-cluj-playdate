-- Stop Detail: not built yet (it wants the routes serving a stop and each
-- one's timetable -- see AGENTS.md). Until then it's a real scene with the
-- app's chrome rather than a bare placeholder, so picking a stop from a list
-- lands somewhere that looks like the rest of the app and B gets you out.
--
-- Scene properties: { stop }.

StopScene = {}
class("StopScene").extends(NobleScene)
local scene = StopScene

scene.backgroundColor = Graphics.kColorWhite

local stop
local favoriteMenuItem = nil

function scene:init(__sceneProperties)
	scene.super.init(self)
	stop = __sceneProperties.stop
	favoriteMenuItem = nil
end

function scene:start()
	scene.super.start(self)
	favoriteMenuItem = playdate.getSystemMenu():addMenuItem("favorite stop", function()
		Store.setFavoriteStop(stop.stop_id)
	end)
end

function scene:exit()
	scene.super.exit(self)
	if favoriteMenuItem ~= nil then
		playdate.getSystemMenu():removeMenuItem(favoriteMenuItem)
		favoriteMenuItem = nil
	end
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({
		title = stop.stop_name,
		icon = Store.favorites.stop_id == stop.stop_id and "star" or "map-pin",
	})

	Theme.emptyState("clock", "Stop detail coming soon", "routes serving this stop, with times")

	Theme.footer({ { button = "B", label = "back" } })
end

scene.inputHandler = {
	BButtonDown = function() Nav.pop() end,
}
