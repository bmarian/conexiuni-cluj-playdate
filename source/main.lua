import "CoreLibs/graphics"
import "CoreLibs/timer"

local gfx <const> = playdate.graphics
local net <const> = playdate.network

-- Network smoke test. Proves the toolchain works AND that the device can
-- reach the live conexiuni-cluj API over Wi-Fi using playdate.network.http.
-- See AGENTS.md: v1 fetches live over HTTP rather than shipping a bundled
-- offline snapshot.

local API_HOST <const> = "bus.bmarian.online"
local API_PATH <const> = "/api/routes"

local statusText = "Checking network..."
local requestState = "idle" -- idle -> requesting -> done/error
local conn = nil
local responseBody = ""
local responseChunks = {}

local function networkStatusText()
	local status = net.getStatus()
	if status == net.kStatusConnected then
		return "Wi-Fi: connected"
	elseif status == net.kStatusNotAvailable then
		return "Wi-Fi: not available"
	else
		return "Wi-Fi: connecting..."
	end
end

local function onRequestCallback()
	local bytes = conn:getBytesAvailable()
	if bytes > 0 then
		table.insert(responseChunks, conn:read(bytes))
	end
end

local function onRequestComplete()
	local err = conn:getError()
	if err ~= nil and err ~= "Connection closed" then
		requestState = "error"
		statusText = "HTTP error: " .. tostring(err)
		return
	end

	responseBody = table.concat(responseChunks)

	local ok, decoded = pcall(json.decode, responseBody)
	if ok and decoded ~= nil then
		statusText = string.format("Got %d routes from %s", #decoded, API_HOST)
	else
		statusText = string.format("Got %d bytes (not JSON?)", #responseBody)
	end

	requestState = "done"
	conn:close()
end

local function startRequest()
	requestState = "requesting"
	statusText = "Requesting " .. API_PATH .. " ..."
	responseChunks = {}

	conn = net.http.new(API_HOST, 443, true, "Conexiuni Cluj")
	if not conn then
		requestState = "error"
		statusText = "Network access denied by user"
		return
	end

	conn:setRequestCallback(onRequestCallback)
	conn:setRequestCompleteCallback(onRequestComplete)

	local ok, err = conn:get(API_PATH)
	if not ok then
		requestState = "error"
		statusText = "GET failed: " .. tostring(err)
	end
end

function playdate.update()
	gfx.clear(gfx.kColorWhite)

	gfx.drawTextAligned("*Conexiuni Cluj*", 200, 40, kTextAlignment.center)
	gfx.drawTextAligned(networkStatusText(), 200, 70, kTextAlignment.center)
	gfx.drawTextInRect(statusText, 20, 100, 360, 100, nil, nil, kTextAlignment.center)

	if requestState == "idle" and net.getStatus() == net.kStatusConnected then
		startRequest()
	end

	gfx.drawTextAligned("A: retry", 200, 210, kTextAlignment.center)

	playdate.timer.updateTimers()
end

function playdate.AButtonUp()
	if requestState ~= "requesting" then
		requestState = "idle"
	end
end
-- watch test Sun Sep  6 08:24:19 GTBDT 2026
-- probe 1788672280
