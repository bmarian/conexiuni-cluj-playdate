-- Route Detail: a flat schematic line of stops with buses drawn where the
-- schedule says they should be right now (elapsed time since a departure,
-- against the hour's cumulative stop offsets -- never live vehicle data).
--
-- Three stops are on screen at a time, each owning a 132px slot and drawing
-- its name horizontally inside 120px of it, wrapped over two lines. That is
-- the whole trick: a label can never be wider than its slot, so labels can
-- never collide, and there is room for a 14px bold face instead of the tiny
-- rotated text this screen used to need to fit a dozen stops on at once.
--
-- Left/Right steps one stop along the line, the crank pans freely, Up/Down
-- flips direction, A opens the timetable.
--
-- Scene properties: { route, dirKey (optional) }.

RouteScene = {}
class("RouteScene").extends(NobleScene)
local scene = RouteScene

scene.backgroundColor = Graphics.kColorWhite

-- Horizontal geometry. Three slots of SPACING very nearly fill the 400px
-- screen. LABEL_W is 124 because "Memorandumului" -- the longest single word
-- in the Cluj stop list -- measures 123px in FONT_BIG and looks silly
-- truncated; that still leaves an 8px gutter between neighbouring names.
local SPACING <const> = 132
local FIRST_X <const> = 66
local LABEL_W <const> = 124
local VISIBLE_SLOTS <const> = 3

-- Vertical bands inside the content area. Each one owns its rows outright so
-- nothing can grow into its neighbour: chips, then the line (buses are drawn
-- centered on it, 13px either side), then two 20px label lines, then the
-- position readout and the scrollbar.
local DIRECTION_CENTER_Y <const> = 47
local DIRECTION_RULE_Y <const> = 61
local CHIP_CENTER_Y <const> = 88
local LINE_Y <const> = 116
local LABEL_TOP <const> = 132
local COUNTER_CENTER_Y <const> = 184
local SCROLLBAR_Y <const> = 198

local CRANK_PIXELS_PER_DEGREE <const> = 1.6
local PAN_SMOOTHING <const> = 0.35

local route, dirKey, stops
local worldX, targetX, focusIndex
local favoriteMenuItem = nil

local function clamp(value, lo, hi)
	if value < lo then return lo end
	if value > hi then return hi end
	return value
end

local function direction()
	return dirKey ~= nil and route.directions[dirKey] or nil
end

local function maxWorld()
	return math.max(0, (#stops - VISIBLE_SLOTS) * SPACING)
end

local function worldXCentering(index)
	return clamp(FIRST_X + (index - 1) * SPACING - Theme.WIDTH // 2, 0, maxWorld())
end

local function setDirection(key)
	dirKey = key
	stops = route.directions[dirKey].stops or {}
	focusIndex = 1
	worldX = 0
	targetX = 0
end

local function bothDirections()
	return route.directions.out ~= nil and route.directions["in"] ~= nil
end

local function toggleDirection()
	if bothDirections() then
		setDirection(dirKey == "out" and "in" or "out")
	end
end

local function focusStop(index)
	if #stops == 0 then return end
	focusIndex = clamp(index, 1, #stops)
	targetX = worldXCentering(focusIndex)
end

local function parseHHMM(s)
	local hour, minute = s:match("(%d+):(%d+)")
	if hour == nil then return nil end
	return tonumber(hour) * 3600 + tonumber(minute) * 60
end

-- Fractional 1-based stop index (2.5 = halfway between stops 2 and 3) for a
-- trip `elapsed` seconds into its run, from this hour's cumulative offsets.
local function logicalIndexForElapsed(offsets, elapsed)
	for i = 1, #stops - 1 do
		local a, b = offsets[i], offsets[i + 1]
		if a ~= nil and b ~= nil and elapsed >= a and elapsed <= b then
			if b <= a then return i end
			return i + (elapsed - a) / (b - a)
		end
	end
	return nil
end

-- Today's departures for the active direction, earliest first. Entries can
-- carry an empty string for one direction (a trip that only runs the other
-- way), and 36 of the 107 routes have no Sunday service at all, so "nothing
-- here" is a normal answer rather than a data problem.
local function departuresToday()
	if route.timetable == nil then return {} end
	local day = route.timetable[Store.scheduleKeyForToday()]
	if day == nil then return {} end

	local field = (dirKey == "out") and "departure_out" or "departure_in"
	local times = {}
	for _, entry in ipairs(day.entries or {}) do
		local value = entry[field]
		if value ~= nil and value ~= "" then
			local seconds = parseHHMM(value)
			if seconds ~= nil then
				table.insert(times, { label = value, seconds = seconds })
			end
		end
	end
	table.sort(times, function(a, b) return a.seconds < b.seconds end)
	return times
end

-- What to say when no bus is on the line. "No buses running right now" is
-- true but reads like a broken screen; on a route with a 35 minute headway
-- and a 28 minute run there's genuinely nothing in transit a fifth of the
-- time, and the useful thing to show is when that changes.
local function noBusesText()
	local times = departuresToday()
	if #times == 0 then return "no service today" end

	local now = playdate.getTime()
	local nowSeconds = now.hour * 3600 + now.minute * 60 + now.second
	for _, departure in ipairs(times) do
		if departure.seconds > nowSeconds then
			return "next departure " .. Text.clockLabel(departure.label)
		end
	end
	return "last departure was " .. Text.clockLabel(times[#times].label)
end

-- Every trip that should currently be somewhere on this line, as
-- { logicalIndex, elapsed }. A frequent route has several at once; outside
-- service hours there are none.
local function activeTrips()
	if #stops < 2 or route.timetable == nil then return {}, nil end

	local day = route.timetable[Store.scheduleKeyForToday()]
	if day == nil then return {}, nil end

	local now = playdate.getTime()
	local offsets = Store.offsetsForHour(direction(), now.hour)
	if offsets == nil then return {}, nil end

	local totalDuration = offsets[#stops]
	if totalDuration == nil or totalDuration <= 0 then return {}, offsets end

	local field = (dirKey == "out") and "departure_out" or "departure_in"
	local nowSeconds = now.hour * 3600 + now.minute * 60 + now.second

	local trips = {}
	for _, entry in ipairs(day.entries or {}) do
		local departure = entry[field]
		if departure ~= nil and departure ~= "" then
			local parsed = parseHHMM(departure)
			if parsed ~= nil then
				local elapsed = nowSeconds - parsed
				-- A night departure is published as "25:05" and the clock says
				-- 01:10, so elapsed comes out about minus a day. Rolling it
				-- forward finds the trip; a genuinely future departure still
				-- lands way past totalDuration and is filtered out below.
				if elapsed < 0 then elapsed = elapsed + 24 * 3600 end
				if elapsed >= 0 and elapsed <= totalDuration then
					local index = logicalIndexForElapsed(offsets, elapsed)
					if index ~= nil then
						table.insert(trips, { logicalIndex = index, elapsed = elapsed })
					end
				end
			end
		end
	end
	return trips, offsets
end

function scene:init(__sceneProperties)
	scene.super.init(self)

	route = __sceneProperties.route
	favoriteMenuItem = nil

	-- Stop Detail knows which direction you picked; honour it rather than
	-- always opening outbound.
	local requested = __sceneProperties.dirKey
	if requested ~= nil and route.directions[requested] ~= nil then
		setDirection(requested)
	elseif route.directions.out ~= nil then
		setDirection("out")
	elseif route.directions["in"] ~= nil then
		setDirection("in")
	else
		dirKey, stops, worldX, targetX, focusIndex = nil, {}, 0, 0, 1
	end
end

local function favoriteLabel()
	return Store.isFavoriteRoute(route.route_id) and "unfavorite route" or "favorite route"
end

function scene:start()
	scene.super.start(self)
	-- Favouriting has no spare button on this screen, and the system menu is
	-- where the Playdate expects per-screen extras to live. The label has to
	-- say what pressing it will do, so it is rebuilt when the state changes.
	local function install()
		if favoriteMenuItem ~= nil then
			playdate.getSystemMenu():removeMenuItem(favoriteMenuItem)
		end
		favoriteMenuItem = playdate.getSystemMenu():addMenuItem(favoriteLabel(), function()
			Store.toggleFavoriteRoute(route.route_id)
			install()
		end)
	end
	install()
end

function scene:exit()
	scene.super.exit(self)
	if favoriteMenuItem ~= nil then
		playdate.getSystemMenu():removeMenuItem(favoriteMenuItem)
		favoriteMenuItem = nil
	end
end

function scene:update()
	scene.super.update(self)
	-- Ease toward the snapped target so stepping between stops glides
	-- instead of jumping; the crank writes worldX and targetX together, so
	-- this is a no-op while cranking.
	if math.abs(targetX - worldX) < 0.5 then
		worldX = targetX
	else
		worldX = worldX + (targetX - worldX) * PAN_SMOOTHING
	end
end

-- The "in" direction is drawn right-to-left. Same geometry, mirrored about
-- the screen: the terminus you start from sits on the right and the bus
-- travels left, so flipping direction visibly reverses the map instead of
-- redrawing an identical-looking line with different names on it.
local function isFlipped()
	return dirKey == "in"
end

local function stopScreenX(index)
	local x = FIRST_X + (index - 1) * SPACING - worldX
	if isFlipped() then return Theme.WIDTH - x end
	return x
end

local function drawDirectionRow()
	local centerY = DIRECTION_CENTER_Y
	local available = Theme.WIDTH - 2 * Theme.MARGIN

	if bothDirections() then
		Icons.drawCentered("chevron-up", 12, Theme.WIDTH - Theme.MARGIN - 6, centerY - 7)
		Icons.drawCentered("chevron-down", 12, Theme.WIDTH - Theme.MARGIN - 6, centerY + 7)
		available = available - 24
	end

	local headsign = direction() ~= nil and Text.clean(direction().headsign or "") or ""
	Theme.textCentered(
		Text.truncateToWidth("to " .. headsign, available, Theme.FONT_TITLE),
		Theme.MARGIN, centerY, kTextAlignment.left, Theme.FONT_TITLE
	)

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(0, DIRECTION_RULE_Y, Theme.WIDTH, DIRECTION_RULE_Y)
end

local function drawStop(index, stop, offsets, reference)
	local x = stopScreenX(index)
	-- A slot is drawn only when its whole label box is on screen, so nothing
	-- is ever half-cut at the edges.
	if x < -SPACING or x > Theme.WIDTH + SPACING then return end

	-- Minutes of schedule distance from the reference trip.
	if reference ~= nil and offsets ~= nil and offsets[index] ~= nil then
		local label = math.floor(math.abs(offsets[index] - reference.elapsed) / 60 + 0.5) .. "m"
		Theme.badge(x - Theme.badgeWidth(label, Theme.FONT_SMALL) // 2, CHIP_CENTER_Y, label, Theme.FONT_SMALL)
	end

	-- Node: terminus stops are solid, the focused one is ringed.
	Graphics.setColor(Graphics.kColorWhite)
	Graphics.fillCircleAtPoint(x, LINE_Y, 6)
	Graphics.setColor(Graphics.kColorBlack)
	if index == 1 or index == #stops then
		Graphics.fillCircleAtPoint(x, LINE_Y, 5)
	else
		Graphics.setLineWidth(2)
		Graphics.drawCircleAtPoint(x, LINE_Y, 5)
	end
	if index == focusIndex then
		Graphics.setLineWidth(1)
		Graphics.drawCircleAtPoint(x, LINE_Y, 9)
	end

	local lines = Text.wrapToWidth(Text.clean(stop.stop_name), LABEL_W, 2, Theme.FONT_BIG)
	local lineHeight = Theme.FONT_BIG:getHeight()
	for i, line in ipairs(lines) do
		Noble.Text.draw(line, x, LABEL_TOP + (i - 1) * lineHeight, kTextAlignment.center, false, Theme.FONT_BIG)
	end
end

local function drawBus(logicalIndex)
	local x = stopScreenX(logicalIndex)
	if x < -20 or x > Theme.WIDTH + 20 then return end

	-- Punch a white hole in the line so the bus reads as sitting on it.
	Graphics.setColor(Graphics.kColorWhite)
	Graphics.fillRoundRect(x - 15, LINE_Y - 13, 30, 26, 5)
	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawRoundRect(x - 15, LINE_Y - 13, 30, 26, 5)
	-- The pixelarticons bus faces right (its roof stops short of the body on
	-- that side -- a raked windscreen). On the mirrored "in" direction the
	-- bus travels left, so it has to be flipped or it drives backwards.
	Icons.drawCentered("bus", 24, x, LINE_Y,
		isFlipped() and Graphics.kImageFlippedX or Graphics.kImageUnflipped)
end

local function drawRouteLine()
	local trips, offsets = activeTrips()
	-- The "Nm" chips are measured against one reference trip: with several
	-- buses running there is no single right answer, and the first active
	-- trip is the simplest choice.
	local reference = trips[1]

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(2)
	Graphics.drawLine(0, LINE_Y, Theme.WIDTH, LINE_Y)
	Graphics.setLineWidth(1)

	for index, stop in ipairs(stops) do
		drawStop(index, stop, offsets, reference)
	end

	for _, trip in ipairs(trips) do
		drawBus(trip.logicalIndex)
	end

	if #trips == 0 then
		Theme.textCentered(noBusesText(), Theme.WIDTH // 2, CHIP_CENTER_Y,
			kTextAlignment.center, Theme.FONT_SMALL)
	end

	Theme.textCentered(
		"stop " .. focusIndex .. " of " .. #stops,
		Theme.WIDTH // 2, COUNTER_CENTER_Y, kTextAlignment.center, Theme.FONT_SMALL
	)
	-- Runs the same way as the line, or it contradicts it.
	local position = focusIndex - 1
	if isFlipped() then position = math.max(0, #stops - VISIBLE_SLOTS - position) end
	Theme.scrollbarH(
		Theme.MARGIN, SCROLLBAR_Y, Theme.WIDTH - 2 * Theme.MARGIN,
		position, VISIBLE_SLOTS, #stops
	)
end

function scene:drawBackground()
	scene.super.drawBackground(self)

	Theme.header({
		title = route.route_long_name,
		badge = Text.clean(route.route_short_name),
		icon = Store.isFavoriteRoute(route.route_id) and "heart" or nil,
	})

	if #stops == 0 then
		Theme.emptyState("square-alert", "No stops for this direction")
	else
		drawDirectionRow()
		drawRouteLine()
	end

	local hints = { { pad = "leftRight", label = "stops" } }
	if bothDirections() then table.insert(hints, { pad = "upDown", label = "direction" }) end
	table.insert(hints, { button = "A", label = "timetable" })
	table.insert(hints, { button = "B", label = "back" })
	Theme.footer(hints)
end

scene.inputHandler = {
	-- Step toward the stop you're pointing at, which is the other way round
	-- once the line is mirrored.
	leftButtonDown = function() focusStop(focusIndex + (isFlipped() and 1 or -1)) end,
	rightButtonDown = function() focusStop(focusIndex + (isFlipped() and -1 or 1)) end,
	upButtonDown = function() toggleDirection() end,
	downButtonDown = function() toggleDirection() end,
	AButtonDown = function()
		if dirKey ~= nil then
			Nav.push(TimetableScene, { route = route, dirKey = dirKey })
		end
	end,
	BButtonDown = function() Nav.pop() end,
	cranked = function(change)
		if #stops == 0 then return end
		worldX = clamp(worldX + change * CRANK_PIXELS_PER_DEGREE, 0, maxWorld())
		targetX = worldX
		-- Keep the focus (and the scrollbar) on whichever stop is nearest
		-- the middle of the screen while free-panning.
		focusIndex = clamp(math.floor((worldX + Theme.WIDTH // 2 - FIRST_X) / SPACING + 1.5), 1, #stops)
	end,
}
