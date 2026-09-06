import "CoreLibs/graphics"
import "CoreLibs/timer"

local gfx <const> = playdate.graphics
local net <const> = playdate.network

-- Network smoke test. Proves the toolchain works AND that the device can
-- reach the live conexiuni-cluj API over Wi-Fi using playdate.network.http.
-- See AGENTS.md: v1 fetches live over HTTP rather than shipping a bundled
-- offline snapshot.

print("[net] main.lua loaded")

local API_HOST <const> = "192.168.50.37"
local API_PORT <const> = 6698
local API_USE_SSL <const> = false
local API_PATH <const> = "/api/routes"

local statusText = "Checking network..."
local requestState = "idle" -- idle -> requesting -> done/error
local conn = nil
local responseBody = ""
local responseChunks = {}
local lastLoggedStatus = nil

local function log(fmt, ...)
	print(string.format("[net] " .. fmt, ...))
end

local function networkStatusText()
	local status = net.getStatus()
	if status ~= lastLoggedStatus then
		log("wifi status changed: %s", tostring(status))
		lastLoggedStatus = status
	end

	if status == net.kStatusConnected then
		return "Wi-Fi: connected"
	elseif status == net.kStatusNotAvailable then
		return "Wi-Fi: not available"
	else
		return "Wi-Fi: connecting..."
	end
end

local function onHeadersRead()
	log("headers read, response status: %d", conn:getResponseStatus())
end

local function onConnectionClosed()
	log("connection closed")
end

local function onRequestCallback()
	local bytes = conn:getBytesAvailable()
	log("data available: %d bytes", bytes)
	if bytes > 0 then
		table.insert(responseChunks, conn:read(bytes))
	end
end

local function onRequestComplete()
	local err = conn:getError()
	log("request complete, error: %s", tostring(err))

	if err ~= nil and err ~= "Connection closed" then
		requestState = "error"
		statusText = "HTTP error: " .. tostring(err)
		return
	end

	responseBody = table.concat(responseChunks)
	log("total response bytes: %d", #responseBody)

	local ok, decoded = pcall(json.decode, responseBody)
	if ok and decoded ~= nil then
		statusText = string.format("Got %d routes from %s", #decoded, API_HOST)
	else
		statusText = string.format("Got %d bytes (not JSON?)", #responseBody)
		log("json.decode failed or empty, ok=%s", tostring(ok))
	end

	requestState = "done"
	conn:close()
end

local function startRequest()
	requestState = "requesting"
	statusText = "Requesting " .. API_PATH .. " ..."
	responseChunks = {}

	log("connecting to %s:%d (ssl=%s)", API_HOST, API_PORT, tostring(API_USE_SSL))
	conn = net.http.new(API_HOST, API_PORT, API_USE_SSL, "Conexiuni Cluj")
	if not conn then
		requestState = "error"
		statusText = "Network access denied by user"
		log("net.http.new returned nil/false")
		return
	end

	conn:setHeadersReadCallback(onHeadersRead)
	conn:setConnectionClosedCallback(onConnectionClosed)
	conn:setRequestCallback(onRequestCallback)
	conn:setRequestCompleteCallback(onRequestComplete)
	conn:setConnectTimeout(5)

	log("sending GET %s", API_PATH)
	local ok, err = conn:get(API_PATH)
	log("get() returned ok=%s err=%s", tostring(ok), tostring(err))
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
		log("starting request")
		startRequest()
	end

	gfx.drawTextAligned("A: retry", 200, 210, kTextAlignment.center)

	playdate.timer.updateTimers()
end

function playdate.AButtonUp()
	if requestState ~= "requesting" then
		print("[net] retry requested")
		requestState = "idle"
	end
end
