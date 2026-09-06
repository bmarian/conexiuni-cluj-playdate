-- The only screen that touches the network: fetches the offline snapshot,
-- then hands off to the Main Menu. Everything after this reads local data.

SyncScene = {}
class("SyncScene").extends(NobleScene)
local scene = SyncScene

scene.backgroundColor = Graphics.kColorWhite

local status = ""
local detail = nil
local syncing = false
local frames = 0

local function startSync()
	syncing = true
	status = "Syncing"
	detail = "downloading the timetable"
	Store.sync(function(ok, err)
		syncing = false
		if ok then
			status = "Synced"
			detail = nil
			Nav.reset(MainMenuScene)
		else
			status = "Sync failed"
			detail = tostring(err)
		end
	end)
end

function scene:init(__sceneProperties)
	scene.super.init(self)
	status = "Syncing"
	detail = nil
	syncing = false
	frames = 0
end

function scene:enter()
	scene.super.enter(self)
	startSync()
end

function scene:update()
	scene.super.update(self)
	frames = frames + 1
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({ title = "Conexiuni Cluj", icon = "reload" })

	local message = status
	if syncing then
		-- One dot per half second, so a long download still looks alive.
		message = status .. string.rep(".", (frames // 15) % 4)
	end
	Theme.emptyState("bus", message, detail and Text.truncateToWidth(detail, 360, Theme.FONT_SMALL) or nil)

	if syncing then
		Theme.footer({})
	else
		Theme.footer({ { button = "A", label = "retry" } })
	end
end

scene.inputHandler = {
	AButtonDown = function()
		if not syncing then startSync() end
	end,
}
