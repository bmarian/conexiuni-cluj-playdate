Store = Store or {}

Store.SYNC_HOST = "ceautobuziau.ro"
Store.SYNC_PORT = 443
Store.SYNC_USE_SSL = true
-- The same bundle the website and phone app sync. Fetched uncompressed: the
-- server gzips it on request, but the SDK has nothing to inflate it with.
local CITIES_PATH <const> = "/api/cities"
local function networkPath(slug) return "/api/" .. slug .. "/network" end
local function versionPath(slug) return "/api/" .. slug .. "/network/version" end

local CITY_FILE <const> = "city"
local CITIES_FILE <const> = "cities"
local CITIES_DOWNLOAD <const> = "cities.download"
-- Each city keeps its own folder: the unpacked network, favorites and sync time.
local function cityDir(slug) return slug end
local function networkDir(slug) return cityDir(slug) .. "/network" end
local function unpackDir(slug) return cityDir(slug) .. "/network.new" end
local function downloadPath(slug) return cityDir(slug) .. "/network.download" end
local function metaPath(slug) return cityDir(slug) .. "/sync_meta.json" end
local function favoritesPath(slug) return cityDir(slug) .. "/favorites.json" end

-- Everything 0.2 kept at the top level, when Cluj was the only city.
local LEGACY_CITY <const> = "cluj"
local LEGACY_FAVORITES <const> = "favorites"
local LEGACY_FILES <const> = { "network.json", "network.download", "network_version.json", "sync_meta.json", "transit_data.json", "snapshot.json" }

-- Day files kept decoded while the Lua heap stays under this, half the
-- Playdate's 16 MB.
local DAY_CACHE_BUDGET_KB <const> = 8 * 1024

Store.city = nil   -- { slug, name } of the city on screen
Store.cities = nil -- the server's list, as last fetched
-- The unpacked index -- { version, routes, stops, stations } -- plus
-- `route.directions`, built at load. Timetables and offsets stay on disk until
-- Store.dayData asks for them.
Store.data = nil
Store.syncedAt = nil -- epoch seconds of the last successful sync
-- How long after its predicted arrival a run is still worth waiting for:
-- how late runs usually are, learned on the server.
Store.lateGraceSeconds = 0
Store.favorites = { routes = {}, stations = {} }
-- Watched by screens that cache rows built from favorites.
Store.favoritesRevision = 0

local scheduleDays = {}
local dayCache, dayCacheOrder = {}, {}

local function readJSON(path)
    if not playdate.file.exists(path) then return nil end
    local ok, decoded = pcall(json.decodeFile, path)
    return ok and decoded or nil
end

-- Moves 0.2's Cluj favorites into Cluj's folder; its network is in the old
-- format and comes down again on the next sync.
local function migrateLegacy()
    local legacy = playdate.datastore.read(LEGACY_FAVORITES)
    if legacy ~= nil then
        playdate.file.mkdir(cityDir(LEGACY_CITY))
        if not playdate.file.exists(favoritesPath(LEGACY_CITY)) then
            json.encodeToFile(favoritesPath(LEGACY_CITY), false, {
                routes = legacy.routes or { legacy.route_id },
                stations = legacy.stops or { legacy.stop_id },
            })
        end
        if playdate.datastore.read(CITY_FILE) == nil then
            playdate.datastore.write({ slug = LEGACY_CITY, name = "Cluj-Napoca" }, CITY_FILE)
        end
        playdate.datastore.delete(LEGACY_FAVORITES)
    end
    for _, path in ipairs(LEGACY_FILES) do
        if playdate.file.exists(path) then playdate.file.delete(path) end
    end
end

-- The bundle has each route's trips -- `<route_id>_0`, `<route_id>_1`, either
-- of which may be missing -- as bare stop ids, against offsets laid out for
-- the whole route. Screens walk a direction as a list of stops, so that is
-- built once here, as `directions.out` for `_0` and `directions["in"]` for
-- `_1`; the offsets are read per day by Store.offsetsForHour.
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
                route = route,
                key = dirKey,
                stops = stops,
                headsign = stops[#stops].stop_name,
                skip = skip,
            }
        end
        skip = skip + #stops
    end
    route.trips = nil
end

-- Platforms of one station share a station_id and nearly always a name; the
-- station takes the name most of them carry.
local function buildStations(stops)
    local stations, byId = {}, {}
    for _, stop in ipairs(stops) do
        local id = stop.station_id or stop.stop_id
        local station = byId[id]
        if station == nil then
            station = { station_id = id, stops = {}, names = {} }
            byId[id] = station
            table.insert(stations, station)
        end
        table.insert(station.stops, stop)
        station.names[stop.stop_name] = (station.names[stop.stop_name] or 0) + 1
    end
    for _, station in ipairs(stations) do
        local best, count = nil, 0
        for name, n in pairs(station.names) do
            if n > count or (n == count and name < best) then best, count = name, n end
        end
        station.stop_name = best or "?"
        station.names = nil
    end
    return stations, byId
end

function Store.loadCity()
    migrateLegacy()
    local saved = playdate.datastore.read(CITY_FILE)
    Store.city = saved ~= nil and saved.slug ~= nil and saved or nil
    Store.cities = playdate.datastore.read(CITIES_FILE)
    return Store.city ~= nil
end

function Store.setCity(city)
    Store.city = { slug = city.slug, name = city.name }
    playdate.datastore.write(Store.city, CITY_FILE)
end

function Store.hasData(slug)
    return playdate.file.exists(Bundle.indexPath(networkDir(slug)))
end

-- True if there is data to browse. The decode takes a moment, so it runs
-- between frames rather than inside one.
function Store.load()
    Store.data = nil
    dayCache, dayCacheOrder = {}, {}
    if Store.city == nil then return false end
    local slug = Store.city.slug

    local meta = readJSON(metaPath(slug))
    Store.syncedAt = meta ~= nil and meta.synced_at or nil

    local decoded = readJSON(Bundle.indexPath(networkDir(slug)))
    if decoded == nil or decoded.routes == nil or decoded.stops == nil then
        Store.loadFavorites()
        return false
    end

    local stopsById = {}
    for _, stop in ipairs(decoded.stops) do
        stopsById[stop.stop_id] = stop
    end
    for _, route in ipairs(decoded.routes) do
        buildDirections(route, stopsById)
    end
    decoded.stopsById = stopsById
    decoded.stations, decoded.stationsById = buildStations(decoded.stops)

    -- Rounded: it is learned, so 2.2166... minutes is 133 seconds.
    local rules = decoded.rules or {}
    Store.lateGraceSeconds = math.floor((rules.late_grace_min or 0) * 60 + 0.5)
    scheduleDays = decoded.schedule_days or {}
    decoded.schedule_days = nil

    -- The bundle arrives in the backend's order.
    Store.sortInPlace(decoded.routes, function(route) return route.route_short_name end)
    Store.sortInPlace(decoded.stations, function(station) return station.stop_name end)

    Store.data = decoded
    Store.loadFavorites()
    return true
end

-- Decorate-sort-undecorate, Text.sortKey is too slow to redo per comparison.
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
        reason = "Ce autobuz iau? downloads the timetables",
        destination = destination,
        onProgress = onProgress,
        onSuccess = onSuccess,
        onError = onError,
    })
end

-- onDone(cities) with the server's list, or onDone(nil, err) with the last one kept.
function Store.fetchCities(onDone)
    request(CITIES_PATH, CITIES_DOWNLOAD, nil, function()
        local list = readJSON(CITIES_DOWNLOAD)
        playdate.file.delete(CITIES_DOWNLOAD)
        if type(list) ~= "table" or #list == 0 then
            onDone(nil, "the city list could not be read")
            return
        end
        local cities = {}
        for _, city in ipairs(list) do
            table.insert(cities, { slug = city.slug, name = city.name, operator = city.operator })
        end
        Store.cities = cities
        playdate.datastore.write(cities, CITIES_FILE)
        onDone(cities)
    end, function(message)
        onDone(nil, message)
    end)
end

local function markSynced(slug)
    Store.syncedAt = playdate.getSecondsSinceEpoch()
    json.encodeToFile(metaPath(slug), false, { synced_at = Store.syncedAt })
end

local function downloadBundle(slug, onProgress, onDone)
    playdate.file.mkdir(cityDir(slug))
    request(networkPath(slug), downloadPath(slug), onProgress, function()
        onDone(true, nil, false)
    end, function(message)
        onDone(false, message, false)
    end)
end

-- onVersion(version), or onVersion(nil) if the server could not be asked.
local function fetchVersion(slug, onVersion)
    local file = cityDir(slug) .. "/network_version.json"
    request(versionPath(slug), file, nil, function()
        local decoded = readJSON(file)
        playdate.file.delete(file)
        onVersion(decoded ~= nil and decoded.version or nil)
    end, function()
        onVersion(nil)
    end)
end

-- onDone(ok, err, unchanged). With unchanged set, the network on disk is still
-- the server's and is already loaded. Otherwise the download waits for
-- Store.unpack, which the caller runs over several frames.
function Store.sync(onProgress, onDone)
    local slug = Store.city.slug
    local current = Store.data ~= nil and Store.data.version or nil
    if current == nil then
        downloadBundle(slug, onProgress, onDone)
        return
    end
    -- A few bytes that can save a download of megabytes and the unpacking.
    fetchVersion(slug, function(latest)
        if latest == current then
            markSynced(slug)
            onDone(true, nil, true)
        else
            -- Unreadable counts as changed; the download reports its own error.
            downloadBundle(slug, onProgress, onDone)
        end
    end)
end

-- A coroutine over Bundle.unpack that swaps the new network in only when it
-- is complete, so a failed sync keeps the old one. Each resume returns the
-- share done and the lines written; the last returns true or false, err.
function Store.unpack()
    local slug = Store.city.slug
    return coroutine.create(function()
        local target, staging = networkDir(slug), unpackDir(slug)
        if playdate.file.exists(staging) then playdate.file.delete(staging, true) end
        playdate.file.mkdir(staging)

        local ok, err = Bundle.unpack(downloadPath(slug), staging)
        playdate.file.delete(downloadPath(slug))
        if not ok then
            playdate.file.delete(staging, true)
            return false, err
        end
        -- Dropped first so the old network does not hold memory or files twice.
        Store.data = nil
        dayCache, dayCacheOrder = {}, {}
        if playdate.file.exists(target) then playdate.file.delete(target, true) end
        if not playdate.file.rename(staging, target) then
            return false, "could not save the timetables"
        end
        markSynced(slug)
        return true
    end)
end

-- Returns the label and whether it is stale
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

function Store.findStation(stationId)
    if Store.data == nil then return nil end
    return Store.data.stationsById[stationId]
end

-- 0.2 saved stops, not stations: an id that is a stop rather than a station
-- moves to the station it belongs to.
local function stationIdsFrom(ids)
    if Store.data == nil then return ids end
    local result, seen = {}, {}
    for _, id in ipairs(ids) do
        local stationId = id
        if Store.data.stationsById[id] == nil and Store.data.stopsById[id] ~= nil then
            stationId = Store.data.stopsById[id].station_id or id
        end
        if not seen[stationId] then
            seen[stationId] = true
            table.insert(result, stationId)
        end
    end
    return result
end

-- Kept out of the network so favorites survive a failed or skipped sync.
function Store.loadFavorites()
    Store.favorites = { routes = {}, stations = {} }
    Store.favoritesRevision = Store.favoritesRevision + 1
    if Store.city == nil then return end

    local stored = readJSON(favoritesPath(Store.city.slug))
    if stored == nil then return end
    Store.favorites.routes = stored.routes or {}
    Store.favorites.stations = stationIdsFrom(stored.stations or {})
end

local function saveFavorites()
    playdate.file.mkdir(cityDir(Store.city.slug))
    json.encodeToFile(favoritesPath(Store.city.slug), false, Store.favorites)
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
    saveFavorites()
end

function Store.isFavoriteRoute(routeId)
    return indexOf(Store.favorites.routes, routeId) ~= nil
end

function Store.isFavoriteStation(stationId)
    return indexOf(Store.favorites.stations, stationId) ~= nil
end

function Store.toggleFavoriteRoute(routeId)
    toggle(Store.favorites.routes, routeId)
end

function Store.toggleFavoriteStation(stationId)
    toggle(Store.favorites.stations, stationId)
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

function Store.favoriteStations()
    local result = {}
    for _, id in ipairs(Store.favorites.stations) do
        local station = Store.findStation(id)
        if station ~= nil then table.insert(result, station) end
    end
    return result
end

function Store.departureField(dirKey)
    return (dirKey == "out") and "departure_in" or "departure_out"
end

function Store.frequencyField(dirKey)
    return (dirKey == "out") and "in_frequency" or "out_frequency"
end

local function evictDays()
    while #dayCacheOrder > 1 and collectgarbage("count") > DAY_CACHE_BUDGET_KB do
        dayCache[table.remove(dayCacheOrder, 1)] = nil
        collectgarbage("collect")
    end
end

-- One line's timetable and learned offsets for one kind of day, as
-- { day, offsets, cumulative }, read from disk on first use.
function Store.dayData(route, dayKey)
    if Store.city == nil or route == nil then return nil end
    local key = route.route_id .. ":" .. dayKey
    local cached = dayCache[key]
    if cached ~= nil then
        local at = indexOf(dayCacheOrder, key)
        if at ~= nil then table.remove(dayCacheOrder, at) end
        table.insert(dayCacheOrder, key)
        return cached
    end

    local decoded = readJSON(Bundle.dayPath(networkDir(Store.city.slug), route.route_id, dayKey))
    if decoded == nil then return nil end
    decoded.cumulative = {}
    dayCache[key] = decoded
    table.insert(dayCacheOrder, key)
    evictDays()
    return decoded
end

function Store.timetableDay(route, dayKey)
    local data = Store.dayData(route, dayKey)
    return data ~= nil and data.day or nil
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
local function upcomingCalls(index, direction, dirKey, dayKey, day, nowSeconds, maxTimes)
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

-- Soonest first, as { route, dirKey, stopId, headsign, shortName, calls }:
-- one row per line and direction, at whichever platform it reaches first.
function Store.departuresAtStation(station, maxTimes)
    local departures = {}
    if Store.data == nil then return departures end

    local dayKey = Store.scheduleKeyForToday()
    local now = playdate.getTime()
    local nowSeconds = now.hour * 3600 + now.minute * 60 + now.second

    local platforms = {}
    for _, stop in ipairs(station.stops) do platforms[stop.stop_id] = true end

    for _, route in ipairs(Store.data.routes) do
        for _, dirKey in ipairs({ "out", "in" }) do
            local direction = route.directions[dirKey]
            local best = nil
            if direction ~= nil then
                -- The terminus is where runs end, not where they leave from.
                for index = 1, #direction.stops - 1 do
                    local stop = direction.stops[index]
                    if platforms[stop.stop_id] then
                        local day = Store.timetableDay(route, dayKey)
                        local calls = day ~= nil and upcomingCalls(index, direction, dirKey, dayKey, day, nowSeconds, maxTimes or 3) or nil
                        if calls ~= nil and (best == nil or calls[1].away < best.calls[1].away) then
                            best = {
                                route = route,
                                dirKey = dirKey,
                                stopId = stop.stop_id,
                                headsign = Text.clean(direction.headsign or ""),
                                shortName = Text.clean(route.route_short_name),
                                calls = calls,
                            }
                        end
                    end
                end
            end
            if best ~= nil then table.insert(departures, best) end
        end
    end

    table.sort(departures, function(a, b) return a.calls[1].away < b.calls[1].away end)
    return departures
end

-- Holidays run on another day's timetable; the server lists them by date.
function Store.scheduleKeyForToday()
    local now = playdate.getTime()
    local special = scheduleDays[string.format("%04d-%02d-%02d", now.year, now.month, now.day)]
    if special == "weekdays" or special == "saturday" or special == "sunday" then return special end
    if now.weekday == 7 then return "sunday" end
    if now.weekday == 6 then return "saturday" end
    return "weekdays"
end

-- Seconds from the terminus departure to each stop of `direction`, for a trip
-- leaving in `hour` on `dayKey` (a timetable key), or nil.
--
-- The bundle keeps, per kind of day and hour, one flat array for the whole
-- route: every trip's stops in `trips` order, each the seconds from the
-- previous stop. So this skips the trips before this one and takes a running
-- sum. The first stop's entry is the learned delay at the terminus, and can be
-- negative -- buses leave early.
--
-- Built on first use and kept with the day: the route line asks every frame.
function Store.offsetsForHour(direction, dayKey, hour)
    if direction == nil then return nil end
    local data = Store.dayData(direction.route, dayKey)
    if data == nil or data.offsets == nil then return nil end

    -- A night trip published as "25:05" runs on the 01:00 offsets.
    hour = hour % 24
    local cache = data.cumulative[direction.key]
    if cache == nil then
        cache = {}
        data.cumulative[direction.key] = cache
    end
    if cache[hour] ~= nil then return cache[hour] or nil end

    local flat = data.offsets[hour + 1]
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
