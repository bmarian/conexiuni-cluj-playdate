-- Back stack over Noble's one-way scene transitions. Scenes are rebuilt on
-- pop, not resumed, so state worth keeping across a round trip lives in them.

Nav = Nav or {}

local stack = {}

local DURATION <const> = 0.25
local PUSH_TRANSITION <const> = Noble.Transition.SlideOnLeft
local POP_TRANSITION <const> = Noble.Transition.SlideOffRight

-- Noble ignores a transition requested mid-transition; pushing anyway would
-- desync the stack from what is on screen.
local function canMove()
	return not Noble.isTransitioning()
end

function Nav.start(Scene, properties)
	stack = { { scene = Scene, properties = properties } }
	Noble.new(Scene, 0.1, Noble.Transition.Cut, nil, {
		defaultTransition = Noble.Transition.CrossDissolve,
		defaultTransitionDuration = DURATION,
		-- Scenes draw in drawBackground and own no sprites, so without this
		-- nothing marks the screen dirty and it freezes after a transition.
		alwaysRedraw = true,
	}, properties)
end

function Nav.push(Scene, properties)
	if not canMove() then return end
	table.insert(stack, { scene = Scene, properties = properties })
	Noble.transition(Scene, DURATION, PUSH_TRANSITION, nil, properties)
end

-- No-op at the root; the caller decides what B means there.
function Nav.pop()
	if not canMove() or #stack < 2 then return end
	table.remove(stack)
	local entry = stack[#stack]
	Noble.transition(entry.scene, DURATION, POP_TRANSITION, nil, entry.properties)
end

-- Replaces the stack, for moves that are neither in nor out.
function Nav.reset(Scene, properties)
	if not canMove() then return end
	stack = { { scene = Scene, properties = properties } }
	Noble.transition(Scene, DURATION, Noble.Transition.CrossDissolve, nil, properties)
end
