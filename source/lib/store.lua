-- Local data: the synced transit snapshot and favorites.
--
-- The snapshot is a ~1MB JSON file the sync streams straight to disk (see
-- lib/api.lua) and this decodes once, at load. It deliberately does NOT go
-- through playdate.datastore: datastore.write re-encodes the whole table to
-- JSON, and doing that to a megabyte of routes blocked the update loop long
-- enough for the device to report "loop stalled for more than 10s". The
-- datastore is still the right home for the small stuff -- favourites, and
-- when the last sync happened -- which is what it's used for here.
--
-- See AGENTS.md "Networking" -- sync is the only time this app touches the
-- network.

Store = Store or {}

Store.SYNC_HOST = "bus.bmarian.online"
Store.SYNC_PORT = 443
Store.SYNC_USE_SSL = true
Store.SYNC_PATH = "/api/playdate/export"

-- The snapshot, and the partial file a download writes before it's promoted.
local DATA_PATH <const> = "snapshot.json"
local DOWNLOAD_PATH <const> = "snapshot.download"
-- playdate.datastore.write(t, "name") produces "name.json"; this is the file
-- the pre-streaming version of sync left behind, worth reclaiming a megabyte
-- from on the first launch after upgrading.
local LEGACY_DATA_PATH <const> = "transit_data.json"

local META_FILE <const> = "sync_meta"
local FAVORITES_FILE <const> = "favorites"

Store.data = nil     -- { generated_at, routes = {...}, stops = {...} }
Store.syncedAt = nil -- epoch seconds of the last successful sync
Store.favorites = { route_id = nil, stop_id = nil }

-- load() reads whatever was persisted from a previous sync. Returns true if
-- there is data to browse. The decode is the one expensive thing this app
-- does; it happens here, at launch, rather than inside a frame.
function Store.load()
	Store.favorites = playdate.datastore.read(FAVORITES_FILE) or { route_id = nil, stop_id = nil }

	local meta = playdate.datastore.read(META_FILE)
	Store.syncedAt = meta ~= nil and meta.synced_at or nil

	if playdate.file.exists(LEGACY_DATA_PATH) then
		playdate.file.delete(LEGACY_DATA_PATH)
	end

	if not playdate.file.exists(DATA_PATH) then
		Store.data = nil
		return false
	end

	local ok, decoded = pcall(json.decodeFile, DATA_PATH)
	if not ok or decoded == nil or decoded.routes == nil then
		-- A truncated or corrupt snapshot is worth throwing away: the app
		-- will offer a re-sync rather than half-browsing it.
		playdate.file.delete(DATA_PATH)
		Store.data = nil
		return false
	end

	-- The export arrives in the backend's order, which is neither numeric for
	-- routes nor alphabetical for stops. Sorting once here means every screen
	-- and every count agrees, rather than each list sorting its own way.
	Store.sortInPlace(decoded.routes, function(route) return route.route_short_name end)
	Store.sortInPlace(decoded.stops, function(stop) return stop.stop_name end)

	Store.data = decoded
	return true
end

-- Decorate-sort-undecorate: Text.sortKey strips diacritics and pads numbers,
-- which is far too much work to redo on every comparison of 793 stops.
function Store.sortInPlace(items, fieldOf)
	if items == nil then return end

	local keys = {}
	for _, item in ipairs(items) do
		keys[item] = Text.sortKey(fieldOf(item))
	end
	table.sort(items, function(a, b) return keys[a] < keys[b] end)
end

-- sync() downloads a fresh snapshot to disk. onDownloaded(ok, errorMessage)
-- fires when the bytes are safely stored; the caller then calls Store.load()
-- to decode them -- on its own frame, so the screen can say what it's doing
-- instead of freezing mid-download.
function Store.sync(onProgress, onDownloaded)
	Api.download({
		host = Store.SYNC_HOST,
		port = Store.SYNC_PORT,
		useSSL = Store.SYNC_USE_SSL,
		path = Store.SYNC_PATH,
		reason = "Conexiuni Cluj sync",
		destination = DOWNLOAD_PATH,
		onProgress = onProgress,
		onSuccess = function()
			-- Promote the download only once it's complete, so a failed sync
			-- leaves the previous snapshot intact rather than truncating it.
			if playdate.file.exists(DATA_PATH) then
				playdate.file.delete(DATA_PATH)
			end
			local renamed, renameError = playdate.file.rename(DOWNLOAD_PATH, DATA_PATH)
			if not renamed then
				onDownloaded(false, "could not save: " .. tostring(renameError))
				return
			end
			Store.syncedAt = playdate.getSecondsSinceEpoch()
			playdate.datastore.write({ synced_at = Store.syncedAt }, META_FILE)
			onDownloaded(true, nil)
		end,
		onError = function(message)
			onDownloaded(false, message)
		end,
	})
end

-- syncedAgoText() is a short "synced Nh ago" string for the Main Menu banner,
-- and whether it's stale enough to recommend a re-sync (>24h).
function Store.syncedAgoText()
	if Store.syncedAt == nil then
		return "never synced", true
	end
	local now = playdate.getSecondsSinceEpoch()
	local deltaSeconds = now - Store.syncedAt
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

-- Which of the timetable's three service days applies right now.
-- Sunday=7, Saturday=6, Monday..Friday=1..5 (playdate.getTime() convention).
function Store.scheduleKeyForToday()
	local weekday = playdate.getTime().weekday
	if weekday == 7 then return "sunday" end
	if weekday == 6 then return "saturday" end
	return "weekdays"
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
