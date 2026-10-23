-- Downloads the city's network, unpacks it a line at a time, then hands off
-- to the main menu. The only screen besides the city list that touches the
-- network.

SyncScene = {}
class("SyncScene").extends(NobleScene)
local scene = SyncScene

scene.backgroundColor = Graphics.kColorWhite

local IDLE <const> = "idle"
local DOWNLOADING <const> = "downloading"
local UNPACKING <const> = "unpacking"
-- The server is on the network already loaded; nothing to unpack.
local UP_TO_DATE <const> = "upToDate"
local LOADING <const> = "loading"
local FAILED <const> = "failed"

-- Unpacking stops for the frame once it has used this much of it, so the
-- progress bar keeps moving.
local FRAME_BUDGET_MS <const> = 25

local phase = IDLE
local detail = nil
local bytesRead, bytesTotal = 0, 0
local unpacked, linesDone = 0, 0
local frames = 0
local worker = nil
local loadAtFrame = nil

local function startSync()
	phase = DOWNLOADING
	detail = nil
	bytesRead, bytesTotal = 0, 0
	unpacked, linesDone = 0, 0
	worker = nil

	Store.sync(
		function(read, total)
			bytesRead, bytesTotal = read or 0, total or 0
		end,
		function(ok, err, unchanged)
			if not ok then
				phase = FAILED
				detail = tostring(err)
				return
			end
			if unchanged then
				phase = UP_TO_DATE
				return
			end
			phase = UNPACKING
			worker = Store.unpack()
		end
	)
end

function scene:init(__sceneProperties)
	scene.super.init(self)
	phase = IDLE
	detail = nil
	frames = 0
	worker = nil
	loadAtFrame = nil
end

function scene:enter()
	scene.super.enter(self)
	startSync()
end

local function unpackSome()
	local started = playdate.getCurrentTimeMilliseconds()
	while coroutine.status(worker) ~= "dead" do
		local resumed, a, b = coroutine.resume(worker)
		if not resumed then
			phase, detail, worker = FAILED, tostring(a), nil
			return
		end
		if coroutine.status(worker) == "dead" then
			worker = nil
			if a == true then
				-- Let "Opening" paint before the index is read.
				phase, loadAtFrame = LOADING, frames + 2
			else
				phase, detail = FAILED, tostring(b)
			end
			return
		end
		unpacked, linesDone = a or unpacked, b or linesDone
		if playdate.getCurrentTimeMilliseconds() - started > FRAME_BUDGET_MS then return end
	end
end

function scene:update()
	scene.super.update(self)
	frames = frames + 1

	if phase == UP_TO_DATE then
		Nav.reset(MainMenuScene)
	elseif phase == UNPACKING and worker ~= nil then
		unpackSome()
	elseif phase == LOADING and loadAtFrame ~= nil and frames >= loadAtFrame then
		loadAtFrame = nil
		if Store.load() then
			Nav.reset(MainMenuScene)
		else
			phase = FAILED
			detail = "the timetables could not be read"
		end
	end
end

local function statusText()
	if phase == FAILED then return "Sync failed" end
	if phase == UNPACKING then return "Unpacking timetables" end
	if phase == LOADING then return "Opening" end
	-- DNS and TLS take seconds before the first byte, and a re-sync asks for
	-- the version before the network, so this is most of the wait.
	local label = bytesRead > 0 and "Downloading" or "Connecting"
	-- One dot per half second.
	return label .. string.rep(".", (frames // 15) % 4)
end

local function progressDetail()
	if phase == UNPACKING then
		return linesDone == 1 and "1 line" or (linesDone .. " lines")
	end
	if phase ~= DOWNLOADING or bytesTotal <= 0 then return nil end
	return string.format("%d of %d KB", bytesRead // 1024, bytesTotal // 1024)
end

local function progress()
	if phase == UNPACKING then return unpacked end
	if phase == DOWNLOADING and bytesTotal > 0 then return bytesRead / bytesTotal end
	return nil
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({ title = Store.city ~= nil and Store.city.name or "Ce autobuz iau?", icon = "reload" })

	local message = detail and Text.truncateToWidth(detail, 360, Theme.FONT_SMALL) or progressDetail()
	Theme.emptyState("bus", statusText(), message)

	local fraction = progress()
	if fraction ~= nil then
		local centerY = (Theme.CONTENT_TOP + Theme.CONTENT_BOTTOM) // 2
		Theme.progressBar(100, centerY + 44, 200, fraction)
	end

	if phase == FAILED then
		local hints = { { button = "A", label = "retry" } }
		if Store.data ~= nil then table.insert(hints, { button = "B", label = "back" }) end
		table.insert(hints, { pad = "left", label = "city" })
		Theme.footer(hints)
	else
		Theme.footer({})
	end
end

scene.inputHandler = {
	AButtonDown = function()
		if phase == FAILED then startSync() end
	end,
	BButtonDown = function()
		if phase == FAILED and Store.data ~= nil then Nav.reset(MainMenuScene) end
	end,
	leftButtonDown = function()
		if phase == FAILED then Nav.reset(CityScene) end
	end,
}
