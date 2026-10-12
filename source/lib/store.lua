-- The ~1.4MB network bundle is a plain file decoded once at load, not a
-- datastore entry: datastore.write re-encodes the table and trips the 10s
-- watchdog.

Store = Store or {}

Store.SYNC_HOST = "bus.bmarian.online"
Store.SYNC_PORT = 443
Store.SYNC_USE_SSL = true
-- The same bundle the website and phone app sync. Fetched uncompressed: the
-- server gzips it on request, but the SDK has nothing to inflate it with.
Store.SYNC_PATH = "/api/network"
Store.VERSION_PATH = "/api/network/version"

local DATA_PATH <const> = "network.json"
local DOWNLOAD_PATH <const> = "network.download"
local VERSION_FILE <const> = "network_version.json"
-- Left behind by older syncs; deleted on the next launch.
local LEGACY_DATA_PATHS <const> = { "transit_data.json", "snapshot.json" }

local META_FILE <const> = "sync_meta"
local FAVORITES_FILE <const> = "favorites"

-- The bundle as served -- { version, generated_at, rules, routes, stops } --
-- plus `route.directions`, built at load.
Store.data = nil
Store.syncedAt = nil -- epoch seconds of the last successful sync
-- How long after its predicted arrival a run is still worth waiting for:
-- how late runs usually are, learned on the server.
Store.lateGraceSeconds = 0
-- Arrays, not sets: json.encode turns number keys into strings.
Store.favorites = { routes = {}, stops = {} }
-- Watched by screens that cache rows built from favorites.
Store.favoritesRevision = 0

-- The bundle has each route's trips -- `<route_id>_0`, `<route_id>_1`, either
-- of which may be missing -- as bare stop ids, against offsets laid out for
-- the whole route. Screens walk a direction as a list of stops, so that is
-- built once here, as `directions.out` for `_0` and `directions["in"]` for
-- `_1`; the offsets stay as served until Store.offsetsForHour needs them.
local function buildDirections(route, stopsById)
	route.directions = {}
	-- Where this trip's entries start in the route's flat offsets arrays.
	local skip = 0
	for _, trip in ipairs(route.trips or {}) do
		local stops = {}
		for i, stopId in ipairs(trip.stop_ids or {}) do
			-- A placeholder keeps the stops lined up with their offsets.
			stops[i] = stopsById[stopId] or { stop_id = stopId, stop_name = "?" }
		end
		local suffix = tostring(trip.trip_id):match("_(%d+)$")
		local dirKey = (suffix == "0" and "out") or (suffix == "1" and "in") or nil
		if dirKey ~= nil and #stops > 0 then
			route.directions[dirKey] = {
				stops = stops,
				headsign = stops[#stops].stop_name,
				offsets = route.offsets,
				skip = skip,
				cumulative = {},
			}
		end
		skip = skip + #stops
	end
end

-- True if there is data to browse. The decode is slow, so it runs at launch
-- rather than inside a frame.
function Store.load()
	Store.loadFavorites()

	local meta = playdate.datastore.read(META_FILE)
	Store.syncedAt = meta ~= nil and meta.synced_at or nil

	for _, path in ipairs(LEGACY_DATA_PATHS) do
		if playdate.file.exists(path) then playdate.file.delete(path) end
	end

	-- Dropped first so a re-sync does not hold two copies at once.
	Store.data = nil
	if not playdate.file.exists(DATA_PATH) then
		return false
	end

	local ok, decoded = pcall(json.decodeFile, DATA_PATH)
	if not ok or decoded == nil or decoded.routes == nil or decoded.stops == nil then
		playdate.file.delete(DATA_PATH)
		return false
	end

	local stopsById = {}
	for _, stop in ipairs(decoded.stops) do
		stopsById[stop.stop_id] = stop
	end
	for _, route in ipairs(decoded.routes) do
		buildDirections(route, stopsById)
	end

	-- Rounded: it is learned, so 2.2166... minutes is 133 seconds.
	local rules = decoded.rules or {}
	Store.lateGraceSeconds = math.floor((rules.late_grace_min or 0) * 60 + 0.5)

	-- The bundle arrives in the backend's order.
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

local function request(path, destination, onProgress, onSuccess, onError)
	Api.download({
		host = Store.SYNC_HOST,
		port = Store.SYNC_PORT,
		useSSL = Store.SYNC_USE_SSL,
		path = path,
		reason = "Conexiuni Cluj sync",
		destination = destination,
		onProgress = onProgress,
		onSuccess = onSuccess,
		onError = onError,
	})
end

local function markSynced()
	Store.syncedAt = playdate.getSecondsSinceEpoch()
	playdate.datastore.write({ synced_at = Store.syncedAt }, META_FILE)
end

local function downloadBundle(onProgress, onDone)
	request(Store.SYNC_PATH, DOWNLOAD_PATH, onProgress, function()
		-- Promote only when complete, so a failed sync keeps the old one.
		if playdate.file.exists(DATA_PATH) then
			playdate.file.delete(DATA_PATH)
		end
		local renamed, renameError = playdate.file.rename(DOWNLOAD_PATH, DATA_PATH)
		if not renamed then
			onDone(false, "could not save: " .. tostring(renameError), false)
			return
		end
		markSynced()
		onDone(true, nil, false)
	end, function(message)
		onDone(false, message, false)
	end)
end

-- onVersion(version), or onVersion(nil) if the server could not be asked.
local function fetchVersion(onVersion)
	request(Store.VERSION_PATH, VERSION_FILE, nil, function()
		local ok, decoded = pcall(json.decodeFile, VERSION_FILE)
		playdate.file.delete(VERSION_FILE)
		onVersion(ok and decoded ~= nil and decoded.version or nil)
	end, function()
		onVersion(nil)
	end)
end

-- onDone(ok, err, unchanged). With unchanged set, the bundle on disk is still
-- the server's and is already loaded. Otherwise the new bytes are stored and
-- the caller decodes them with Store.load() on a later frame, so the screen
-- can repaint in between.
function Store.sync(onProgress, onDone)
	local current = Store.data ~= nil and Store.data.version or nil
	if current == nil then
		downloadBundle(onProgress, onDone)
		return
	end
	-- A few bytes that can save a 1.4MB download and a decode of seconds.
	fetchVersion(function(latest)
		if latest == current then
			markSynced()
			onDone(true, nil, true)
		else
			-- Unreadable counts as changed; the download reports its own error.
			downloadBundle(onProgress, onDone)
		end
	end)
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
-- names suggest. `directions.out` (the `_0` trip) leaves at `departure_in`,
-- and `directions["in"]` (`_1`) at `departure_out`; the backend documents the
-- pairing. The column names are CTP-CJ's own in/out labels, which have
-- nothing to do with the trip ids.
--
-- Pairing them by name puts every time in this app against the wrong stop
-- sequence: the route line's buses and chips, the stop's departure list, the
-- timetable grid and its stop times. It reads plausibly, because the wrong
-- direction of a two-way route is still a real timetable -- it is just not
-- yours. These two functions are the only place the pairing lives.
function Store.departureField(dirKey)
	return (dirKey == "out") and "departure_in" or "departure_out"
end

-- Headway-based directions carry the same swap.
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

-- Times are the trip's departure plus this stop's cumulative offset. A run
-- stays listed until Store.lateGraceSeconds past its predicted arrival.
local function upcomingCalls(stopId, direction, dirKey, dayKey, day, nowSeconds, maxTimes)
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
				local offsets = Store.offsetsForHour(direction, dayKey, departure // 3600)
				local offset = offsets ~= nil and offsets[index] or nil
				if offset ~= nil then
					local arrival = departure + offset
					local away = arrival - nowSeconds
					-- Night departures are published as "25:05".
					if away < -12 * 3600 then away = away + 24 * 3600 end
					if away >= -Store.lateGraceSeconds then
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
					local calls = upcomingCalls(stopId, direction, dirKey, dayKey, day, nowSeconds, maxTimes or 3)
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

-- The timetable says "weekdays" where the offsets say "weekday".
local OFFSET_DAYS <const> = { weekdays = "weekday", saturday = "saturday", sunday = "sunday" }

-- Seconds from the terminus departure to each stop of `direction`, for a trip
-- leaving in `hour` on `dayKey` (a timetable key), or nil.
--
-- The bundle keeps, per kind of day and hour, one flat array for the whole
-- route: every trip's stops in `trips` order, each the seconds from the
-- previous stop. So this skips the trips before this one and takes a running
-- sum. The first stop's entry is the learned delay at the terminus, and can be
-- negative -- buses leave early.
--
-- Built on first use and kept: the route line asks every frame.
function Store.offsetsForHour(direction, dayKey, hour)
	local day = OFFSET_DAYS[dayKey]
	if direction == nil or direction.offsets == nil or day == nil then return nil end

	-- A night trip published as "25:05" runs on the 01:00 offsets.
	hour = hour % 24
	local cache = direction.cumulative[day]
	if cache == nil then
		cache = {}
		direction.cumulative[day] = cache
	end
	if cache[hour] ~= nil then return cache[hour] or nil end

	local hourly = direction.offsets[day]
	local flat = hourly ~= nil and hourly[hour + 1] or nil
	local cumulative = false
	if flat ~= nil then
		cumulative = {}
		local total = 0
		for i = 1, #direction.stops do
			local step = flat[direction.skip + i]
			-- Stops past a gap get no time rather than a wrong one.
			if step == nil then break end
			total = total + step
			cumulative[i] = total
		end
	end
	-- false, not nil, so a miss is not worked out again.
	cache[hour] = cumulative
	return cumulative or nil
end
