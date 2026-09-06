-- Screenshot harness. Not part of the shipped app -- `tools/screenshots.ps1`
-- copies source/ to a temp folder, drops this in as main.lua, builds it and
-- runs it. It boots Noble Engine for real against fake data, walks the whole
-- nav stack a step at a time, and writes a PNG of the actual display at each
-- stop along the way, then quits.
--
-- Why bother: every scene draws itself with unclipped text calls, so layout
-- bugs (labels colliding, a name running under an icon) are invisible until
-- someone looks at a render. And booting for real is what catches the engine
-- wiring -- transitions, scene lifecycle, redraw config -- that a static
-- render of drawBackground would happily paper over.
--
-- The Simulator's console isn't reachable from a script, so any error is
-- rendered into ERROR.png instead of vanishing.

import "libraries/noble/Noble"

import "lib/text"
import "lib/icons"
import "lib/theme"
import "lib/nav"
import "lib/api"
import "lib/store"

import "scenes/SyncScene"
import "scenes/MainMenuScene"
import "scenes/ListScene"
import "scenes/RouteScene"
import "scenes/TimetableScene"
import "scenes/TripScene"
import "scenes/StopScene"

Noble.Text.setFont(Theme.FONT_BODY)

-- `playdate.simulator` doesn't exist on hardware, and every screenshot below
-- goes through it. If this build ends up on a device -- easy to do by
-- accident, since the Simulator's "upload to device" ships whatever it
-- currently has open, and running this leaves the harness open -- say so
-- instead of dying on a nil index at the first screenshot.
if playdate.simulator == nil then
	function playdate.update()
		Graphics.clear(Graphics.kColorWhite)
		Graphics.drawTextAligned("Screenshot harness", 200, 84, kTextAlignment.center)
		Graphics.drawTextAligned("Simulator only, not the app.", 200, 112, kTextAlignment.center)
		Graphics.drawTextAligned("Install ConexiuniCluj.pdx instead.", 200, 132, kTextAlignment.center)
	end
	return
end

-- Substituted by tools/screenshots.ps1.
local OUT <const> = "@@OUTPUT_DIR@@/"

-- Real Cluj stop names, diacritics included: they're the worst case for both
-- Text.clean and the route line's label boxes.
local stopNames <const> = {
	"Izlazului", "Calea Mănăștur", "Agronomia", "Calea Moților",
	"Memorandumului Sud", "Victoria", "Regionala CFR", "Piața 1 Mai Sosire",
	"Bucium", "Aleea Slănic", "Str. Unirii", "Disp. Clăbucet",
}

local function makeDirection(headsign)
	local stops, offsets = {}, {}
	for i, name in ipairs(stopNames) do
		stops[i] = { stop_id = i, stop_name = name }
		offsets[i] = (i - 1) * 130
	end
	local hourly = {}
	for hour = 0, 23 do hourly[tostring(hour)] = offsets end
	return { headsign = headsign, stops = stops, hourly_offset_seconds = hourly }
end

local entries = {}
for hour = 5, 23 do
	-- 07:00 gets twelve departures: that's the densest hour in the real data
	-- (route 25 on a weekday), and the case the timetable grid's column
	-- pitch has to survive.
	local minutes = hour == 7
		and { 0, 5, 10, 15, 20, 25, 30, 35, 40, 45, 50, 55 }
		or { 5, 25, 45 }
	for _, minute in ipairs(minutes) do
		table.insert(entries, {
			departure_out = string.format("%02d:%02d", hour, minute),
			departure_in = string.format("%02d:%02d", hour, (minute + 10) % 60),
		})
	end
end
local timetable <const> = {
	weekdays = { entries = entries },
	saturday = { entries = entries },
	sunday = { entries = entries },
}

local route <const> = {
	route_id = 1,
	route_short_name = "1",
	route_long_name = "Str. Bucium - P-ța 1 Mai",
	directions = {
		out = makeDirection("P-ța 1 Mai Sosire"),
		["in"] = makeDirection("Disp. Clăbucet"),
	},
	timetable = timetable,
}

-- Deliberately in the order the backend sends them, and using the shapes
-- that break a plain string sort: "25N" belongs after "25", "100" after "99",
-- and the M-prefixed metropolitan routes after all of those.
local shortNames <const> = {
	"102L", "25", "9", "M11", "100", "5N", "25N", "1", "M9", "43B",
	"26", "101", "8L", "A1", "M21", "3", "50D", "102", "12", "57L",
}
local routes = { route }
for i, shortName in ipairs(shortNames) do
	routes[i + 1] = {
		route_id = i + 1,
		route_short_name = shortName,
		route_long_name = "P-ța Mihai Viteazul - Str. Emil Quinet nr. " .. i,
		directions = route.directions,
		timetable = timetable,
	}
end

local stops = {}
for i, name in ipairs(stopNames) do
	stops[i] = { stop_id = i, stop_name = name }
end

Store.data = { routes = routes, stops = stops }
Store.syncedAt = playdate.getSecondsSinceEpoch() - 35 * 60
Store.favorites = {}

-- Store.load() does this after decoding a real snapshot; the harness injects
-- its data directly, so it has to sort it the same way to be representative.
Store.sortInPlace(Store.data.routes, function(r) return r.route_short_name end)
Store.sortInPlace(Store.data.stops, function(st) return st.stop_name end)

Nav.start(MainMenuScene)

local function shoot(name)
	playdate.simulator.writeToFile(Graphics.getDisplayImage(), OUT .. name .. ".png")
end

-- Renders a scene that the walk doesn't reach (Sync only exists while the
-- network call is in flight) without letting it run its enter() hook.
local function shootDetached(name, scene)
	local image = Graphics.image.new(400, 240)
	Graphics.pushContext(image)
	scene:drawBackground()
	Graphics.popContext()
	playdate.simulator.writeToFile(image, OUT .. name .. ".png")
end

-- Input handlers are called directly: Noble.Input polls real button state,
-- which a script can't fake. Everything else -- transitions, the nav stack,
-- the scene lifecycle -- runs for real.
--
-- Steps are a plain ordered list, not a frame-number table. Noble's
-- transitions run on wall-clock time while a script counts frames, so any
-- fixed frame spacing is a bet on the Simulator's frame rate; the driver
-- below waits for the transition to actually finish instead. Add a step here
-- when you add a screen.
local steps <const> = {
	function() shoot("01-mainmenu") end,
	function()
		MainMenuScene.inputHandler.downButtonDown()
		MainMenuScene.inputHandler.downButtonDown()
		MainMenuScene.inputHandler.AButtonDown()
	end,
	function() shoot("02-routelist") end,
	function()
		ListScene.inputHandler.downButtonDown()
		ListScene.inputHandler.AButtonDown()
	end,
	function() shoot("03-route") end,
	-- Pan into the middle of the line, where labels have neighbours on both
	-- sides and the most room to collide.
	function() for _ = 1, 4 do RouteScene.inputHandler.rightButtonDown() end end,
	function() shoot("04-route-panned") end,
	function() RouteScene.inputHandler.upButtonDown() end,
	function() shoot("05-route-other-direction") end,
	function() RouteScene.inputHandler.AButtonDown() end,
	function() shoot("06-timetable") end,
	-- The timetable opens on the current hour, not the top, so "hold Up" is
	-- how you actually reach the tab strip. It stops there rather than
	-- wrapping, which makes this deterministic whatever time the run happens.
	function() for _ = 1, 40 do TimetableScene.inputHandler.upButtonDown() end end,
	function() shoot("07-timetable-tabs-focused") end,
	function() TimetableScene.inputHandler.rightButtonDown() end,
	function() TimetableScene.inputHandler.downButtonDown() end,
	function() shoot("08-timetable-other-day") end,
	-- Back to the top, then down to the third row: 05, 06, 07 -- and 07:00
	-- holds twelve departures, the widest row the real data ever produces.
	function() for _ = 1, 40 do TimetableScene.inputHandler.upButtonDown() end end,
	function()
		TimetableScene.inputHandler.downButtonDown() -- tabs -> grid, row 1
		TimetableScene.inputHandler.downButtonDown()
		TimetableScene.inputHandler.downButtonDown()
	end,
	function() shoot("09-timetable-dense-hour") end,
	function() TimetableScene.inputHandler.AButtonDown() end,
	function() shoot("10-trip-stop-times") end,
	function() for _ = 1, 4 do TripScene.inputHandler.downButtonDown() end end,
	function() shoot("11-trip-scrolled") end,
	function() TripScene.inputHandler.BButtonDown() end,
	function() TimetableScene.inputHandler.BButtonDown() end,
	function() RouteScene.inputHandler.BButtonDown() end,
	function() ListScene.inputHandler.BButtonDown() end,
	function() shoot("12-back-at-mainmenu") end,
	function()
		MainMenuScene.inputHandler.downButtonDown()
		MainMenuScene.inputHandler.AButtonDown()
	end,
	function() shoot("13-stoplist") end,
	function() ListScene.inputHandler.AButtonDown() end,
	function() shoot("14-stop") end,
	function()
		shootDetached("15-sync", SyncScene({}))
		-- Stale snapshot, no favourites: the other half of the menu's states.
		Store.data.synced_at = playdate.getSecondsSinceEpoch() - 3 * 24 * 60 * 60
		shootDetached("16-mainmenu-stale", MainMenuScene({}))
	end,
}

local function bail(where, err)
	local image = Graphics.image.new(400, 240)
	Graphics.pushContext(image)
	Graphics.clear(Graphics.kColorWhite)
	Graphics.drawText("ERROR in " .. where, 4, 4)
	local text = tostring(err)
	local y = 26
	while #text > 0 do
		Graphics.drawText(text:sub(1, 56), 4, y)
		text = text:sub(57)
		y = y + 18
	end
	Graphics.popContext()
	playdate.simulator.writeToFile(image, OUT .. "ERROR.png")
	playdate.simulator.exit()
end

local nobleUpdate <const> = playdate.update
local index = 1
local frame = 0

-- Frames to wait after a step before running the next one. It has to outlast
-- a transition (0.25s, ~8 frames) on its own, because Noble.isTransitioning()
-- is still false in the gap between a step asking for a transition and the
-- engine starting it -- gate on that alone and steps fire mid-slide, or
-- before the very first frame has been painted at all.
local SETTLE <const> = 12
local cooldown = SETTLE

function playdate.update()
	local ok, err = pcall(nobleUpdate)
	if not ok then return bail("step " .. index .. " update", err) end

	frame = frame + 1
	-- Hard backstop: if a step never becomes runnable, dump the screen and
	-- quit rather than hanging the build.
	if frame > 1200 then
		shoot("STALLED-at-step-" .. index)
		return playdate.simulator.exit()
	end

	if cooldown > 0 then
		cooldown = cooldown - 1
		return
	end
	-- Noble ignores anything asked of it mid-transition, and Nav refuses to
	-- move then too. Waiting it out is what makes the walk frame-rate proof.
	if Noble.isTransitioning() then return end

	local step = steps[index]
	if step == nil then return playdate.simulator.exit() end
	index = index + 1
	cooldown = SETTLE

	local stepOk, stepErr = pcall(step)
	if not stepOk then return bail("step " .. (index - 1), stepErr) end
end
