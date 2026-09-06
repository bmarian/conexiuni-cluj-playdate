-- A back stack on top of Noble Engine's scene transitions.
--
-- Noble transitions are one-way -- `Noble.transition(Scene)` has no notion of
-- "the screen I came from" -- but this app is a drill-down browser where B
-- always means back. So the stack lives here: push records the scene class
-- and the properties it was entered with, pop re-enters the previous one with
-- the properties it had. Scenes are rebuilt on the way back rather than
-- resumed, so anything worth preserving across a round trip (a list's
-- selected row) is kept by the scene itself, not here.

Nav = Nav or {}

local stack = {}

local DURATION <const> = 0.25
-- Drilling in slides the new screen over the old one; backing out slides the
-- current one away to reveal it again. The direction is the only cue that
-- says which way through the hierarchy you just went.
local PUSH_TRANSITION <const> = Noble.Transition.SlideOnLeft
local POP_TRANSITION <const> = Noble.Transition.SlideOffRight

-- Noble ignores a transition requested while one is already running. If the
-- stack were updated anyway it would drift out of step with what's actually
-- on screen, and B would start going to the wrong place.
local function canMove()
	return not Noble.isTransitioning()
end

--- Boots the engine on `Scene` and makes it the bottom of the stack.
function Nav.start(Scene, properties)
	stack = { { scene = Scene, properties = properties } }
	-- Noble's launcher transition is a 1.5s dip-to-black by default, which is
	-- a long time to stare at nothing before a bus timetable.
	Noble.new(Scene, 0.1, Noble.Transition.Cut, nil, {
		defaultTransition = Noble.Transition.CrossDissolve,
		defaultTransitionDuration = DURATION,
		-- Must be passed explicitly: Noble only calls
		-- Graphics.sprite.setAlwaysRedraw for keys present in the config
		-- table, and the SDK default is off. Every scene here draws its whole
		-- screen in drawBackground and owns no sprites, so without this
		-- nothing marks the screen dirty and the display freezes on the first
		-- frame after a transition -- buses included.
		alwaysRedraw = true,
	}, properties)
end

--- Drills into a new scene, remembering the current one.
function Nav.push(Scene, properties)
	if not canMove() then return end
	table.insert(stack, { scene = Scene, properties = properties })
	Noble.transition(Scene, DURATION, PUSH_TRANSITION, nil, properties)
end

--- Goes back one screen. Does nothing at the root -- the caller decides what
--- B means there (the Main Menu makes it a re-sync).
function Nav.pop()
	if not canMove() or #stack < 2 then return end
	table.remove(stack)
	local entry = stack[#stack]
	Noble.transition(entry.scene, DURATION, POP_TRANSITION, nil, entry.properties)
end

--- Replaces the whole stack, for moves that aren't drilling in or out --
--- finishing a sync and landing on the Main Menu, say.
function Nav.reset(Scene, properties)
	if not canMove() then return end
	stack = { { scene = Scene, properties = properties } }
	Noble.transition(Scene, DURATION, Noble.Transition.CrossDissolve, nil, properties)
end
