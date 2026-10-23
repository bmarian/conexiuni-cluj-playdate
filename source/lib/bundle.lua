-- Splits a downloaded network bundle into an index and one file per line and
-- kind of day. București's bundle decodes to more than the Playdate's 16 MB,
-- so it is never decoded whole: one line at a time is read, written out and
-- dropped.

Bundle = Bundle or {}

local CHUNK <const> = 32 * 1024
-- Where the routes array ends and the stops begin, in the server's compact JSON.
local ROUTES_START <const> = '"routes":['
local ROUTES_END <const> = '}],"stops":['

Bundle.DAYS = { "weekdays", "saturday", "sunday" }
-- The timetable says "weekdays" where the offsets say "weekday".
Bundle.OFFSET_DAYS = { weekdays = "weekday", saturday = "saturday", sunday = "sunday" }

function Bundle.dayPath(dir, routeId, dayKey)
    return dir .. "/" .. routeId .. "-" .. dayKey .. ".json"
end

function Bundle.indexPath(dir)
    return dir .. "/index.json"
end

-- Unread bytes are buf from pos on; more() drops the rest and appends a chunk.
local function newReader(path)
    local file = playdate.file.open(path, playdate.file.kFileRead)
    if file == nil then return nil end
    return { file = file, buf = "", pos = 1, done = false, read = 0, size = playdate.file.getSize(path) or 0 }
end

local function more(r)
    if r.done then return false end
    local chunk = r.file:read(CHUNK)
    if chunk == nil or #chunk == 0 then
        r.done = true
        return false
    end
    r.buf = r.buf:sub(r.pos) .. chunk
    r.pos = 1
    r.read = r.read + #chunk
    return true
end

-- The first of `a` or `b` at or after r.pos, reading on until one turns up:
-- returns its index and which one it was.
local function findEither(r, a, b)
    local from = r.pos
    while true do
        local atA = r.buf:find(a, from, true)
        local atB = b ~= nil and r.buf:find(b, from, true) or nil
        if atA ~= nil and (atB == nil or atA < atB) then return atA, a end
        if atB ~= nil then return atB, b end
        -- A match may straddle the chunk boundary.
        local resume = math.max(r.pos, #r.buf - math.max(#a, b ~= nil and #b or 0) + 2)
        local shift = r.pos - 1
        if not more(r) then return nil end
        from = resume - shift
    end
end

local function restOfFile(r)
    local parts = { r.buf:sub(r.pos) }
    while true do
        local chunk = r.file:read(CHUNK)
        if chunk == nil or #chunk == 0 then break end
        r.read = r.read + #chunk
        table.insert(parts, chunk)
    end
    r.buf, r.pos, r.done = "", 1, true
    return table.concat(parts)
end

local function writeRoute(dir, route)
    for _, dayKey in ipairs(Bundle.DAYS) do
        local timetable = route.timetable ~= nil and route.timetable[dayKey] or nil
        local offsets = route.offsets ~= nil and route.offsets[Bundle.OFFSET_DAYS[dayKey]] or nil
        json.encodeToFile(Bundle.dayPath(dir, route.route_id, dayKey), false, { day = timetable, offsets = offsets })
    end

    local trips = {}
    for _, trip in ipairs(route.trips or {}) do
        table.insert(trips, { trip_id = trip.trip_id, stop_ids = trip.stop_ids })
    end
    return {
        route_id = route.route_id,
        route_short_name = route.route_short_name,
        route_long_name = route.route_long_name,
        route_type = route.route_type,
        trips = trips,
    }
end

-- Runs inside a coroutine and yields after every line with the share of the
-- file read so far. Returns true, or false and why.
function Bundle.unpack(source, dir)
    local r = newReader(source)
    if r == nil then return false, "could not open the download" end

    local startAt = findEither(r, ROUTES_START)
    if startAt == nil then
        r.file:close()
        return false, "not a network bundle"
    end
    local head = r.buf:sub(r.pos, startAt - 1)
    r.pos = startAt + #ROUTES_START

    local routes = {}
    -- Elements are split on "},{" plus the key every route starts with.
    while #r.buf - r.pos < 64 and more(r) do end
    local firstKey = r.buf:match('^{"([^"]+)":', r.pos)
    if firstKey ~= nil then
        local separator = '},{"' .. firstKey .. '":'
        while true do
            local at, which = findEither(r, separator, ROUTES_END)
            if at == nil then
                r.file:close()
                return false, "the download ends early"
            end
            local ok, route = pcall(json.decode, r.buf:sub(r.pos, at))
            if not ok or route == nil then
                r.file:close()
                return false, "a line could not be read"
            end
            table.insert(routes, writeRoute(dir, route))
            route = nil
            r.pos = at + 2
            coroutine.yield(r.read / math.max(1, r.size), #routes)
            if which == ROUTES_END then
                r.pos = at + #ROUTES_END - #'"stops":['
                break
            end
        end
    elseif r.buf:sub(r.pos, r.pos) == "]" then
        r.pos = r.pos + 2
    end

    -- What is left (stops, rules, holidays) is small enough to decode at once.
    local tail = restOfFile(r)
    r.file:close()
    local ok, rest = pcall(json.decode, "{" .. tail)
    local okHead, meta = pcall(json.decode, head .. '"routes":[]}')
    if not ok or rest == nil or not okHead or meta == nil then
        return false, "the stops could not be read"
    end

    local stops = {}
    for _, stop in ipairs(rest.stops or {}) do
        table.insert(stops, { stop_id = stop.stop_id, stop_name = stop.stop_name, station_id = stop.station_id })
    end
    json.encodeToFile(Bundle.indexPath(dir), false, {
        version = meta.version,
        rules = rest.rules,
        schedule_days = rest.schedule_days,
        routes = routes,
        stops = stops,
    })
    return true
end
