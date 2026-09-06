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

--- Boots the engine on `Scene` and makes it the bottom of the stack.
function Nav.start(Scene, properties)
	stack = { { scene = Scene, properties = properties } }
	Noble.new(Scene, nil, nil, nil, nil, properties)
end

--- Drills into a new scene, remembering the current one.
function Nav.push(Scene, properties)
	table.insert(stack, { scene = Scene, properties = properties })
	Noble.transition(Scene, DURATION, PUSH_TRANSITION, nil, properties)
end

--- Goes back one screen. Does nothing at the root -- the caller decides what
--- B means there (the Main Menu makes it a re-sync).
function Nav.pop()
	if #stack < 2 then return end
	table.remove(stack)
	local entry = stack[#stack]
	Noble.transition(entry.scene, DURATION, POP_TRANSITION, nil, entry.properties)
end

--- Replaces the whole stack, for moves that aren't drilling in or out --
--- finishing a sync and landing on the Main Menu, say.
function Nav.reset(Scene, properties)
	stack = { { scene = Scene, properties = properties } }
	Noble.transition(Scene, DURATION, Noble.Transition.CrossDissolve, nil, properties)
end
