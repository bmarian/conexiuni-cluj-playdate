-- Local data: the synced transit snapshot and favorites. Everything here is
-- playdate.datastore-backed. See AGENTS.md "Networking" -- sync is the only
-- time this app touches the network.

Store = Store or {}

Store.SYNC_HOST = "192.168.50.37"
Store.SYNC_PORT = 6698
Store.SYNC_USE_SSL = false
Store.SYNC_PATH = "/api/playdate/export"

local DATA_FILE <const> = "transit_data"
local FAVORITES_FILE <const> = "favorites"

Store.data = nil -- { synced_at, generated_at, routes = {...}, stops = {...} }
Store.favorites = { route_id = nil, stop_id = nil }

-- load() reads whatever was persisted from a previous sync. Returns true if
-- there is data to browse.
function Store.load()
	Store.data = playdate.datastore.read(DATA_FILE)
	Store.favorites = playdate.datastore.read(FAVORITES_FILE) or { route_id = nil, stop_id = nil }
	return Store.data ~= nil
end

-- sync() fetches a fresh snapshot and persists it. onDone(ok, errorMessage).
function Store.sync(onDone)
	Api.get(Store.SYNC_HOST, Store.SYNC_PORT, Store.SYNC_USE_SSL, Store.SYNC_PATH, "Conexiuni Cluj sync",
		function(decoded)
			local seconds = playdate.getSecondsSinceEpoch()
			decoded.synced_at = seconds
			local ok = playdate.datastore.write(decoded, DATA_FILE)
			if ok == false then
				onDone(false, "could not save to device")
				return
			end
			Store.data = decoded
			onDone(true, nil)
		end,
		function(err)
			onDone(false, err)
		end)
end

-- syncedAgoText() is a short "synced Nh ago" string for the Main Menu banner,
-- and whether it's stale enough to recommend a re-sync (>24h).
function Store.syncedAgoText()
	if Store.data == nil or Store.data.synced_at == nil then
		return "never synced", true
	end
	local now = playdate.getSecondsSinceEpoch()
	local deltaSeconds = now - Store.data.synced_at
	local stale = deltaSeconds > 24 * 60 * 60

	if deltaSeconds < 60 then
		return "synced just now", stale
	elseif deltaSeconds < 3600 then
		return string.format("synced %dm ago", deltaSeconds // 60), stale
	elseif deltaSeconds < 86400 then
		return string.format("synced %dh ago", deltaSeconds // 3600), stale
	else
		return string.format("synced %dd ago", deltaSeconds // 86400), stale
	end
end

function Store.findRoute(routeId)
	if Store.data == nil then return nil end
	for _, r in ipairs(Store.data.routes) do
		if r.route_id == routeId then return r end
	end
	return nil
end

function Store.findStop(stopId)
	if Store.data == nil then return nil end
	for _, s in ipairs(Store.data.stops) do
		if s.stop_id == stopId then return s end
	end
	return nil
end

function Store.setFavoriteRoute(routeId)
	Store.favorites.route_id = routeId
	playdate.datastore.write(Store.favorites, FAVORITES_FILE)
end

function Store.setFavoriteStop(stopId)
	Store.favorites.stop_id = stopId
	playdate.datastore.write(Store.favorites, FAVORITES_FILE)
end

-- The export ships one cumulative-offset array per hour of the day
-- (`hourly_offset_seconds`), because segment travel times vary by time of day
-- and a snapshot is browsed for up to a day after it's synced. Route Detail
-- wants the array for the hour it is right now; hours with no service are
-- absent from the table, so fall back to the nearest one that is present
-- rather than assuming all 24 exist.
function Store.offsetsForHour(direction, hour)
	local hourly = direction ~= nil and direction.hourly_offset_seconds or nil
	if hourly == nil then return nil end

	local exact = hourly[tostring(hour)]
	if exact ~= nil then return exact end

	local nearest, nearestDistance
	for key, offsets in pairs(hourly) do
		local candidateHour = tonumber(key)
		if candidateHour ~= nil then
			local distance = math.abs(candidateHour - hour)
			distance = math.min(distance, 24 - distance) -- 23:00 is an hour from 00:00
			if nearestDistance == nil or distance < nearestDistance then
				nearest, nearestDistance = offsets, distance
			end
		end
	end
	return nearest
end
