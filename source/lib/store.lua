-- The ~1MB snapshot is a plain file decoded once at load, not a datastore
-- entry: datastore.write re-encodes the table and trips the 10s watchdog.

Store = Store or {}

Store.SYNC_HOST = "bus.bmarian.online"
Store.SYNC_PORT = 443
Store.SYNC_USE_SSL = true
Store.SYNC_PATH = "/api/playdate/export"

local DATA_PATH <const> = "snapshot.json"
local DOWNLOAD_PATH <const> = "snapshot.download"
-- Left behind by the pre-streaming sync; deleted on the next launch.
local LEGACY_DATA_PATH <const> = "transit_data.json"

local META_FILE <const> = "sync_meta"
local FAVORITES_FILE <const> = "favorites"

Store.data = nil     -- { generated_at, routes = {...}, stops = {...} }
Store.syncedAt = nil -- epoch seconds of the last successful sync
-- Arrays, not sets: json.encode turns number keys into strings.
Store.favorites = { routes = {}, stops = {} }
-- Watched by screens that cache rows built from favorites.
Store.favoritesRevision = 0

-- True if there is data to browse. The decode is slow, so it runs at launch
-- rather than inside a frame.
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
		playdate.file.delete(DATA_PATH)
		Store.data = nil
		return false
	end

	-- The export arrives in the backend's order.
	Store.sortInPlace(decoded.routes, function(route) return route.route_short_name end)
	Store.sortInPlace(decoded.stops, function(stop) return stop.stop_name end)

	Store.data = decoded
	return true
end

-- Decorate-sort-undecorate; Text.sortKey is too slow to redo per comparison.
function Store.sortInPlace(items, fieldOf)
	if items == nil then return end

	local keys = {}
	for _, item in ipairs(items) do
		keys[item] = Text.sortKey(fieldOf(item))
	end
	table.sort(items, function(a, b) return keys[a] < keys[b] end)
end

-- onDownloaded(ok, err) fires once the bytes are stored; the caller decodes
-- with Store.load() on a later frame so the screen can repaint in between.
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
			-- Promote only when complete, so a failed sync keeps the old one.
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

-- Returns the label and whether it is stale (>24h).
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

-- Kept out of the snapshot so favorites survive a failed or skipped sync.
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

-- Skips ids a later sync dropped.
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

-- Which timetable column serves a direction -- and it is not the one the two
-- names suggest. `directions.out` is served by `departure_in`, and
-- `directions.in` by `departure_out`, for every route in the snapshot.
--
-- The backend scrapes the timetable from CTP-CJ, whose own in/out labels are
-- unrelated to Tranzy's direction ids, and reconciles them in
-- `alignTimetableToDirectionIDs`: after it runs, `departure_in` is the column
-- for Tranzy direction_id 0. The Playdate export then walks the directions as
-- `{OUTGOING_SUFFIX, "out"}, {INCOMING_SUFFIX, "in"}` with
-- `OUTGOING_SUFFIX = "_0"` -- so the geometry it publishes as "out" is that
-- same direction_id 0, whose departures are in the column named "in".
--
-- Pairing them by name put every time in this app against the wrong stop
-- sequence: the route line's buses and chips, the stop's departure list, the
-- timetable grid and its stop times. It read plausibly, because the wrong
-- direction of a two-way route is still a real timetable -- it is just not
-- yours. Verified against route 32: `directions.out` runs from Disp. Alverna,
-- the 08:55 trip out of Disp. Alverna is in `departure_in`, and nothing in
-- `departure_out` matches it.
--
-- If the export is ever changed to line the two up, these two functions are
-- the only thing to flip.
function Store.departureField(dirKey)
	return (dirKey == "out") and "departure_in" or "departure_out"
end

-- Headway-based directions carry the same swap; the backend swaps the two
-- frequency fields alongside the departure columns.
function Store.frequencyField(dirKey)
	return (dirKey == "out") and "in_frequency" or "out_frequency"
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

-- Times are the trip's departure plus this stop's cumulative offset.
local function upcomingCalls(stopId, direction, dirKey, day, nowSeconds, maxTimes)
	local index = stopIndexIn(direction, stopId)
	if index == nil then return nil end
	-- Trips end at the last stop; nothing to board there.
	if index == #direction.stops then return nil end

	local field = Store.departureField(dirKey)
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
					-- Night departures are published as "25:05".
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

-- Soonest first, as { route, dirKey, headsign, shortName, calls }. The full
-- scan measures 2ms at the busiest stop, so there is no stop->routes index.
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

	table.sort(departures, function(a, b) return a.calls[1].away < b.calls[1].away end)
	return departures
end

-- playdate.getTime() numbers Monday..Sunday as 1..7.
function Store.scheduleKeyForToday()
	local weekday = playdate.getTime().weekday
	if weekday == 7 then return "sunday" end
	if weekday == 6 then return "saturday" end
	return "weekdays"
end

-- Offsets are per hour of the day, and hours without service are missing, so
-- fall back to the nearest hour present.
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
