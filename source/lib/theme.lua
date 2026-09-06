-- The app's one and only set of visual decisions: four fonts with fixed
-- roles, a fixed header/content/footer split, and the handful of widgets
-- every scene is built out of (rows, badges, button hints, scrollbars).
--
-- Scenes are not allowed their own type scale or their own chrome. If a
-- screen needs something new, it goes in here so every screen gets it --
-- that is the whole point of the file. Named `Theme` because Noble Engine
-- already claims the global `UI` (it aliases `playdate.ui`).
--
-- Everything that measures text measures it in the font it will actually be
-- drawn in, and every label is truncated to the space it actually has, so
-- two labels can't collide no matter how long the synced name turns out to
-- be. `Graphics.drawTextAligned` does no clipping of its own.

Theme = Theme or {}

-- Fonts, by role. Nothing draws text without picking one of these.
Theme.FONT_TITLE = Graphics.font.new("fonts/Roobert-11-Bold")       -- headers, badges, selected rows
Theme.FONT_BODY = Graphics.getSystemFont()                          -- list rows, timetable cells
Theme.FONT_BIG = Graphics.font.new("fonts/Asheville-Sans-14-Bold")  -- stop names on the route line
Theme.FONT_SMALL = Noble.Text.FONT_SMALL                            -- footer hints, chips, "3m" labels

-- Layout. The header and footer are the same height on every scene; content
-- lives strictly between them.
-- (Table fields, so no <const>: Lua 5.4 only allows that on locals.)
Theme.WIDTH = 400
Theme.HEIGHT = 240
-- 32 leaves 6px of air around a 20px badge; at 28 the badge filled the bar
-- edge to edge and sat right on the divider.
Theme.HEADER_H = 32
Theme.CONTENT_TOP = 33
-- The footer only holds one 9px row of hints, so it gives 4px back to the
-- content -- which is what keeps the timetable at seven visible hours
-- despite the taller header.
Theme.CONTENT_BOTTOM = 213
Theme.FOOTER_Y = 214
Theme.MARGIN = 8

--- Height available between the header rule and the footer rule.
function Theme.contentHeight()
	return Theme.CONTENT_BOTTOM - Theme.CONTENT_TOP
end

-- Where the glyphs actually sit inside each font's line box, measured by
-- rendering digits offscreen and scanning for ink (tools/screenshots can
-- reproduce it; the numbers are in AGENTS.md). getHeight() is the whole box
-- including leading -- 22px for an 11px-looking Roobert -- so sizing a badge
-- from it produced a box as tall as the entire header and taller than a
-- timetable row. The ink is also consistently a couple of pixels above the
-- box's middle, so centering on getHeight() alone draws every label high.
local INK = {
	[Theme.FONT_TITLE] = { top = 2, height = 15 },
	[Theme.FONT_BODY] = { top = 1, height = 14 },
	[Theme.FONT_BIG] = { top = 1, height = 14 },
	[Theme.FONT_SMALL] = { top = 1, height = 7 },
}

local function inkOf(font)
	local ink = INK[font]
	if ink ~= nil then return ink end
	local height = font:getHeight()
	return { top = 0, height = height }
end

--- Draws `text` with the *ink* vertically centered on `centerY`
--- (drawTextAligned takes a box top edge, and every widget here thinks in
--- centers). Centering the ink rather than the box is what keeps a label
--- looking level inside a badge, a filled row or the footer.
function Theme.textCentered(text, x, centerY, alignment, font)
	local ink = inkOf(font)
	Noble.Text.draw(text, x, centerY - ink.top - ink.height // 2, alignment, false, font)
end

--- Width Theme.badge will take for this text, for callers that need to
--- center one or lay out around it before drawing.
--- Height of a badge drawn in this font. Sized to the glyphs, not the leading.
function Theme.badgeHeight(font)
	return inkOf(font or Theme.FONT_TITLE).height + 8
end

function Theme.badgeWidth(text, font)
	font = font or Theme.FONT_TITLE
	return math.max(font:getTextWidth(text) + 12, Theme.badgeHeight(font))
end

--- A rounded outline box around short text -- route numbers, day tabs, the
--- "3m" chips on the route line. Returns its width so callers can lay out
--- what follows. Draws in white when `white` is true, for use on a filled row.
function Theme.badge(x, centerY, text, font, white)
	font = font or Theme.FONT_TITLE
	local height = Theme.badgeHeight(font)
	local width = Theme.badgeWidth(text, font)
	local y = centerY - height // 2

	Graphics.setColor(white and Graphics.kColorWhite or Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawRoundRect(x, y, width, height, 4)
	if white then Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite) end
	Theme.textCentered(text, x + width // 2, centerY, kTextAlignment.center, font)
	Graphics.setImageDrawMode(Graphics.kDrawModeCopy)
	Graphics.setColor(Graphics.kColorBlack)

	return width
end

--- The header: an optional badge on the left, a centered title, an optional
--- icon on the right, and the rule that separates it from the content. Every
--- scene calls this first, with the same shape, so the top of the screen
--- never moves between screens.
---
--- opts: { title, badge, icon }
function Theme.header(opts)
	local centerY = Theme.HEADER_H // 2
	local left = Theme.MARGIN
	local right = Theme.MARGIN

	if opts.badge ~= nil then
		left = left + Theme.badge(Theme.MARGIN, centerY, opts.badge, Theme.FONT_TITLE) + 14
	end
	if opts.icon ~= nil then
		Icons.draw(opts.icon, 24, Theme.WIDTH - Theme.MARGIN - 24, centerY - 12)
		right = right + 24 + Theme.MARGIN
	end

	-- The title is centered in what's left over and truncated to it, so it
	-- can never run under the badge or the icon.
	local available = Theme.WIDTH - left - right
	local title = Text.truncateToWidth(Text.clean(opts.title or ""), available, Theme.FONT_TITLE)
	Theme.textCentered(title, left + available // 2, centerY, kTextAlignment.center, Theme.FONT_TITLE)

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(0, Theme.HEADER_H, Theme.WIDTH, Theme.HEADER_H)
end

-- Button hints. The Playdate's Ⓐ/Ⓑ glyphs only exist in some fonts, so the
-- chips are drawn rather than typed -- that way the footer looks identical
-- whichever font a scene happens to be using.
local CHIP <const> = 16

local function drawChip(x, centerY, letter)
	Graphics.setColor(Graphics.kColorBlack)
	Graphics.fillCircleInRect(x, centerY - CHIP // 2, CHIP, CHIP)
	Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite)
	Theme.textCentered(letter, x + CHIP // 2, centerY, kTextAlignment.center, Theme.FONT_SMALL)
	Graphics.setImageDrawMode(Graphics.kDrawModeCopy)
end

-- A hint's leading glyph is either an A/B chip or one or two d-pad chevrons.
-- Single chevrons are for when the two directions do different things --
-- Right favourites, Left removes -- rather than being two ends of one axis.
local HINT_GLYPHS <const> = {
	leftRight = { "chevron-left", "chevron-right" },
	upDown = { "chevron-up", "chevron-down" },
	left = { "chevron-left" },
	right = { "chevron-right" },
	up = { "chevron-up" },
	down = { "chevron-down" },
}

local function hintGlyphWidth(hint)
	local glyphs = HINT_GLYPHS[hint.pad]
	if glyphs ~= nil then return #glyphs * 12 end
	return CHIP
end

local function hintWidth(hint)
	return hintGlyphWidth(hint) + 4 + Theme.FONT_SMALL:getTextWidth(hint.label)
end

--- The footer: the rule, then a centered row of control hints.
--- hints: an array of { button = "A"|"B", label = "..." } or
--- { pad = "leftRight"|"upDown", label = "..." }.
function Theme.footer(hints)
	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(0, Theme.FOOTER_Y, Theme.WIDTH, Theme.FOOTER_Y)

	local gap = 14
	local total = 0
	for i, hint in ipairs(hints) do
		total = total + hintWidth(hint)
		if i > 1 then total = total + gap end
	end

	local centerY = (Theme.FOOTER_Y + Theme.HEIGHT) // 2
	local x = (Theme.WIDTH - total) // 2
	for _, hint in ipairs(hints) do
		local glyphs = HINT_GLYPHS[hint.pad]
		if glyphs ~= nil then
			for i, glyph in ipairs(glyphs) do
				Icons.drawCentered(glyph, 12, x + 6 + (i - 1) * 12, centerY)
			end
		else
			drawChip(x, centerY, hint.button)
		end
		x = x + hintGlyphWidth(hint) + 4
		Theme.textCentered(hint.label, x, centerY, kTextAlignment.left, Theme.FONT_SMALL)
		x = x + Theme.FONT_SMALL:getTextWidth(hint.label) + gap
	end
end

--- One full-width list row, the shared building block of every list on every
--- screen: optional icon, optional badge, label, optional right-hand
--- accessory text. The label gets whatever horizontal space the other three
--- leave it and is truncated to exactly that, so rows never collide.
---
--- `width` defaults to the full screen; pass the cell width when the list is
--- drawn narrower (to leave room for a scrollbar), or the accessory ends up
--- drawn past the clip and loses its last character.
---
--- `accessories` is a right-aligned group of short strings, soonest first,
--- for rows that carry several values (the next few departures at a stop).
--- The first is boxed, because it's the one that matters.
---
--- `markIcon` is a 12px mark at the right edge -- a favourite heart on a
--- list row -- placed outside the label so rows stay aligned whether or not
--- they carry one.
---
--- opts: { icon, badge, label, accessory, accessories, markIcon, font, accessoryFont, width }
function Theme.row(y, height, selected, opts)
	local centerY = y + height // 2
	local font = opts.font or Theme.FONT_BODY
	local width = opts.width or Theme.WIDTH

	if selected then
		Graphics.setColor(Graphics.kColorBlack)
		Graphics.fillRect(0, y, width, height)
		Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite)
	end

	local x = Theme.MARGIN
	if opts.icon ~= nil then
		Icons.drawCentered(opts.icon, 24, x + 12, centerY)
		x = x + 24 + Theme.MARGIN
	end
	if opts.badge ~= nil then
		x = x + Theme.badge(x, centerY, opts.badge, Theme.FONT_TITLE, selected) + Theme.MARGIN
		-- badge() restores the copy draw mode; a selected row still wants white.
		if selected then Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite) end
	end

	-- Everything on the right is placed from the right edge inward; whatever
	-- is left over is the label's, and it gets truncated to exactly that.
	local labelRight = width - Theme.MARGIN

	if opts.markIcon ~= nil then
		Icons.drawCentered(opts.markIcon, 12, labelRight - 6, centerY)
		labelRight = labelRight - 12 - Theme.MARGIN
	end

	if opts.accessory ~= nil then
		local accessoryFont = opts.accessoryFont or Theme.FONT_SMALL
		Theme.textCentered(opts.accessory, labelRight, centerY, kTextAlignment.right, accessoryFont)
		labelRight = labelRight - accessoryFont:getTextWidth(opts.accessory) - Theme.MARGIN
	end

	if opts.accessories ~= nil then
		-- Drawn back to front so the soonest still ends up leftmost.
		for i = #opts.accessories, 2, -1 do
			local label = opts.accessories[i]
			Theme.textCentered(label, labelRight, centerY, kTextAlignment.right, Theme.FONT_SMALL)
			labelRight = labelRight - Theme.FONT_SMALL:getTextWidth(label) - 10
		end
		local next = opts.accessories[1]
		if next ~= nil then
			local boxWidth = Theme.badgeWidth(next, Theme.FONT_SMALL)
			Theme.badge(labelRight - boxWidth, centerY, next, Theme.FONT_SMALL, selected)
			if selected then Graphics.setImageDrawMode(Graphics.kDrawModeFillWhite) end
			labelRight = labelRight - boxWidth - Theme.MARGIN
		end
	end

	local available = labelRight - x
	Theme.textCentered(
		Text.truncateToWidth(Text.clean(opts.label or ""), available, font),
		x, centerY, kTextAlignment.left, font
	)

	Graphics.setImageDrawMode(Graphics.kDrawModeCopy)
	Graphics.setColor(Graphics.kColorBlack)
end

--- Vertical scrollbar for a list: a hairline track with a solid thumb sized
--- to the fraction of rows on screen. Nothing is drawn when it all fits.
function Theme.scrollbarV(x, y, height, first, visible, total)
	if total <= visible then return end

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(x + 2, y, x + 2, y + height)

	local thumb = math.max(12, height * visible // total)
	local span = height - thumb
	local offset = span * first // math.max(1, total - visible)
	Graphics.fillRoundRect(x, y + offset, 5, thumb, 2)
end

--- Horizontal equivalent, used by the route line to show where along the
--- route the visible window sits.
function Theme.scrollbarH(x, y, width, offset, visible, total)
	if total <= visible then return end

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawLine(x, y + 2, x + width, y + 2)

	local thumb = math.max(16, width * visible // total)
	local span = width - thumb
	local position = span * offset // math.max(1, total - visible)
	Graphics.fillRoundRect(x + position, y, thumb, 5, 2)
end

--- A determinate progress bar: outlined track, solid fill. `fraction` is
--- 0..1 and is clamped, since a server's byte count and what we've actually
--- written don't have to agree.
function Theme.progressBar(x, y, width, fraction)
	local height = 10
	fraction = math.max(0, math.min(1, fraction or 0))

	Graphics.setColor(Graphics.kColorBlack)
	Graphics.setLineWidth(1)
	Graphics.drawRoundRect(x, y, width, height, 3)
	local filled = math.floor((width - 4) * fraction)
	if filled > 0 then
		Graphics.fillRoundRect(x + 2, y + 2, filled, height - 4, 2)
	end
end

--- Centered icon-over-message block, for every "there's nothing here" state.
function Theme.emptyState(icon, message, detail)
	local centerY = (Theme.CONTENT_TOP + Theme.CONTENT_BOTTOM) // 2
	if icon ~= nil then
		Icons.drawCentered(icon, 24, Theme.WIDTH // 2, centerY - 26)
	end
	Theme.textCentered(message, Theme.WIDTH // 2, centerY, kTextAlignment.center, Theme.FONT_TITLE)
	if detail ~= nil then
		Theme.textCentered(detail, Theme.WIDTH // 2, centerY + 22, kTextAlignment.center, Theme.FONT_SMALL)
	end
end
