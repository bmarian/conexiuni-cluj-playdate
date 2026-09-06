-- The only screen that touches the network: downloads the offline snapshot,
-- then hands off to the Main Menu. Everything after this reads local data.
--
-- The work is split into visible phases on purpose. The export is ~1MB, so
-- there are two slow steps -- pulling it down, and decoding it -- and each
-- gets its own state with something on screen. In particular the decode runs
-- a frame *after* the screen says it's happening, so the device isn't left
-- looking frozen on "Downloading" while it parses a megabyte of JSON.

SyncScene = {}
class("SyncScene").extends(NobleScene)
local scene = SyncScene

scene.backgroundColor = Graphics.kColorWhite

local IDLE <const> = "idle"
local DOWNLOADING <const> = "downloading"
local READING <const> = "reading"
local FAILED <const> = "failed"

local phase = IDLE
local detail = nil
local bytesRead, bytesTotal = 0, 0
local frames = 0
local decodeAtFrame = nil

local function startSync()
	phase = DOWNLOADING
	detail = nil
	bytesRead, bytesTotal = 0, 0
	decodeAtFrame = nil

	Store.sync(
		function(read, total)
			bytesRead, bytesTotal = read or 0, total or 0
		end,
		function(ok, err)
			if not ok then
				phase = FAILED
				detail = tostring(err)
				return
			end
			-- Downloaded, not yet readable. Let the "Reading timetable"
			-- frame actually paint before spending seconds in json.decode.
			phase = READING
			decodeAtFrame = frames + 2
		end
	)
end

function scene:init(__sceneProperties)
	scene.super.init(self)
	phase = IDLE
	detail = nil
	frames = 0
	decodeAtFrame = nil
end

function scene:enter()
	scene.super.enter(self)
	startSync()
end

function scene:update()
	scene.super.update(self)
	frames = frames + 1

	if phase == READING and decodeAtFrame ~= nil and frames >= decodeAtFrame then
		decodeAtFrame = nil
		if Store.load() then
			Nav.reset(MainMenuScene)
		else
			phase = FAILED
			detail = "downloaded file could not be read"
		end
	end
end

local function statusText()
	if phase == FAILED then return "Sync failed" end
	if phase == READING then return "Reading timetable" end
	-- DNS, TLS and the server building the export take about four seconds
	-- before a single byte arrives -- most of the wait. Saying "Downloading"
	-- through all of it, with a progress bar stuck at zero, looks broken.
	local label = bytesRead > 0 and "Downloading" or "Connecting"
	-- One dot per half second, so a slow connection still looks alive.
	return label .. string.rep(".", (frames // 15) % 4)
end

local function progressDetail()
	if phase ~= DOWNLOADING or bytesTotal <= 0 then return nil end
	return string.format("%d of %d KB", bytesRead // 1024, bytesTotal // 1024)
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({ title = "Conexiuni Cluj", icon = "reload" })

	local message = detail and Text.truncateToWidth(detail, 360, Theme.FONT_SMALL) or progressDetail()
	Theme.emptyState("bus", statusText(), message)

	if phase == DOWNLOADING and bytesTotal > 0 then
		local centerY = (Theme.CONTENT_TOP + Theme.CONTENT_BOTTOM) // 2
		Theme.progressBar(100, centerY + 44, 200, bytesRead / bytesTotal)
	end

	if phase == FAILED then
		Theme.footer({ { button = "A", label = "retry" } })
	else
		Theme.footer({})
	end
end

scene.inputHandler = {
	AButtonDown = function()
		if phase == FAILED then startSync() end
	end,
}
