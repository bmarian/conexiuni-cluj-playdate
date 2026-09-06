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
-- Arrays of ids, not sets. A set keyed by number survives neither
-- json.encode (which turns the keys into strings) nor the round trip back,
-- and there are never enough favourites for a linear scan to matter.
Store.favorites = { routes = {}, stops = {} }
-- Bumped on every change. The Main Menu caches its rows (a favourite stop's
-- departures are too expensive to recompute per frame) and watches this to
-- know when that cache is stale, whoever changed them.
Store.favoritesRevision = 0

-- load() reads whatever was persisted from a previous sync. Returns true if
-- there is data to browse. The decode is the one expensive thing this app
-- does; it happens here, at launch, rather than inside a frame.
function Store.load()
	Store.loadFavorites()

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

--- Reads favourites, upgrading the one-route-one-stop file older builds
--- wrote. Kept separate from the snapshot: favourites are small, personal,
--- and must survive a failed or skipped sync.
function Store.loadFavorites()
	local stored = playdate.datastore.read(FAVORITES_FILE)
	Store.favorites = { routes = {}, stops = {} }
	Store.favoritesRevision = Store.favoritesRevision + 1
	if stored == nil then return end

	if stored.routes ~= nil or stored.stops ~= nil then
		Store.favorites.routes = stored.routes or {}
		Store.favorites.stops = stored.stops or {}
		return
	end

	-- Legacy shape: a single { route_id, stop_id }.
	if stored.route_id ~= nil then table.insert(Store.favorites.routes, stored.route_id) end
	if stored.stop_id ~= nil then table.insert(Store.favorites.stops, stored.stop_id) end
end

local function indexOf(list, id)
	for i, each in ipairs(list) do
		if each == id then return i end
	end
	return nil
end

local function toggle(list, id)
	local at = indexOf(list, id)
	if at ~= nil then
		table.remove(list, at)
	else
		table.insert(list, id)
	end
	Store.favoritesRevision = Store.favoritesRevision + 1
	playdate.datastore.write(Store.favorites, FAVORITES_FILE)
end

function Store.isFavoriteRoute(routeId)
	return indexOf(Store.favorites.routes, routeId) ~= nil
end

function Store.isFavoriteStop(stopId)
	return indexOf(Store.favorites.stops, stopId) ~= nil
end

function Store.toggleFavoriteRoute(routeId)
	toggle(Store.favorites.routes, routeId)
end

function Store.toggleFavoriteStop(stopId)
	toggle(Store.favorites.stops, stopId)
end

--- Favourited routes/stops as objects, in the snapshot's order, skipping ids
--- that a later sync dropped.
function Store.favoriteRoutes()
	local result = {}
	for _, id in ipairs(Store.favorites.routes) do
		local route = Store.findRoute(id)
		if route ~= nil then table.insert(result, route) end
	end
	return result
end

function Store.favoriteStops()
	local result = {}
	for _, id in ipairs(Store.favorites.stops) do
		local stop = Store.findStop(id)
		if stop ~= nil then table.insert(result, stop) end
	end
	return result
end

local function parseHHMM(s)
	local hour, minute = s:match("(%d+):(%d+)")
	if hour == nil then return nil end
	return tonumber(hour) * 3600 + tonumber(minute) * 60
end

local function stopIndexIn(direction, stopId)
	for index, each in ipairs(direction.stops or {}) do
		if each.stop_id == stopId then return index end
	end
	return nil
end

-- The next few calls at one stop for one route/direction. The time is the
-- trip's departure plus this stop's cumulative offset -- the route's origin
-- time is not what you want when you're standing halfway along it.
local function upcomingCalls(stopId, direction, dirKey, day, nowSeconds, maxTimes)
	local index = stopIndexIn(direction, stopId)
	if index == nil then return nil end
	-- The last stop is where the trip ends. Standing at a terminus, half the
	-- board would otherwise be buses arriving to go out of service -- real
	-- times, but you can't get on one.
	if index == #direction.stops then return nil end

	local field = (dirKey == "out") and "departure_out" or "departure_in"
	local calls = {}
	for _, entry in ipairs(day.entries or {}) do
		local time = entry[field]
		if time ~= nil and time ~= "" then
			local departure = parseHHMM(time)
			if departure ~= nil then
				local offsets = Store.offsetsForHour(direction, departure // 3600)
				local offset = offsets ~= nil and offsets[index] or nil
				if offset ~= nil then
					local arrival = departure + offset
					local away = arrival - nowSeconds
					-- A night departure is published as "25:05"; against a
					-- clock that already rolled past midnight it looks like
					-- most of a day ago, so bring it back.
					if away < -12 * 3600 then away = away + 24 * 3600 end
					if away >= 0 then
						table.insert(calls, { away = away, arrival = arrival })
					end
				end
			end
		end
	end
	if #calls == 0 then return nil end

	table.sort(calls, function(a, b) return a.away < b.away end)
	while #calls > maxTimes do table.remove(calls) end
	return calls
end

--- Everything still to leave a stop today, soonest first, as
--- { route, dirKey, headsign, shortName, calls = {{away, arrival}, ...} }.
---
--- Scans every route's two directions rather than keeping a permanent
--- stop->routes index: the busiest stop in the export (31 route/direction
--- pairs) measured 2ms in the Simulator, and the snapshot is already the big
--- thing in memory.
function Store.departuresAtStop(stopId, maxTimes)
	local departures = {}
	if Store.data == nil then return departures end

	local dayKey = Store.scheduleKeyForToday()
	local now = playdate.getTime()
	local nowSeconds = now.hour * 3600 + now.minute * 60 + now.second

	for _, route in ipairs(Store.data.routes) do
		local day = route.timetable ~= nil and route.timetable[dayKey] or nil
		if day ~= nil then
			for _, dirKey in ipairs({ "out", "in" }) do
				local direction = route.directions[dirKey]
				if direction ~= nil then
					local calls = upcomingCalls(stopId, direction, dirKey, day, nowSeconds, maxTimes or 3)
					if calls ~= nil then
						table.insert(departures, {
							route = route,
							dirKey = dirKey,
							headsign = Text.clean(direction.headsign or ""),
							shortName = Text.clean(route.route_short_name),
							calls = calls,
						})
					end
				end
			end
		end
	end

	-- Soonest first: this is a departure board, not a route index.
	table.sort(departures, function(a, b) return a.calls[1].away < b.calls[1].away end)
	return departures
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
