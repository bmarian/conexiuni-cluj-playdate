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
Theme.HEADER_H = 28
Theme.CONTENT_TOP = 29
Theme.CONTENT_BOTTOM = 209
Theme.FOOTER_Y = 210
Theme.MARGIN = 8

--- Height available between the header rule and the footer rule.
function Theme.contentHeight()
	return Theme.CONTENT_BOTTOM - Theme.CONTENT_TOP
end

local function textHeight(font)
	return font:getHeight()
end

--- Draws `text` with its vertical center at `centerY` (drawTextAligned takes
--- a top edge, and every widget here thinks in centers).
function Theme.textCentered(text, x, centerY, alignment, font)
	Noble.Text.draw(text, x, centerY - textHeight(font) // 2, alignment, false, font)
end

--- Width Theme.badge will take for this text, for callers that need to
--- center one or lay out around it before drawing.
function Theme.badgeWidth(text, font)
	font = font or Theme.FONT_TITLE
	return math.max(font:getTextWidth(text) + 12, textHeight(font) + 6)
end

--- A rounded outline box around short text -- route numbers, day tabs, the
--- "3m" chips on the route line. Returns its width so callers can lay out
--- what follows. Draws in white when `white` is true, for use on a filled row.
function Theme.badge(x, centerY, text, font, white)
	font = font or Theme.FONT_TITLE
	local height = textHeight(font) + 6
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
		left = left + Theme.badge(Theme.MARGIN, centerY, opts.badge, Theme.FONT_TITLE) + Theme.MARGIN
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

-- A hint's leading glyph is either an A/B chip or a pair of d-pad chevrons.
local HINT_GLYPHS <const> = {
	leftRight = { "chevron-left", "chevron-right" },
	upDown = { "chevron-up", "chevron-down" },
}

local function hintGlyphWidth(hint)
	if HINT_GLYPHS[hint.pad] ~= nil then return 24 end
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
			Icons.drawCentered(glyphs[1], 12, x + 6, centerY)
			Icons.drawCentered(glyphs[2], 12, x + 18, centerY)
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
--- opts: { icon, badge, label, accessory, font }
function Theme.row(y, height, selected, opts)
	local centerY = y + height // 2
	local font = opts.font or Theme.FONT_BODY

	if selected then
		Graphics.setColor(Graphics.kColorBlack)
		Graphics.fillRect(0, y, Theme.WIDTH, height)
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

	local right = Theme.MARGIN
	if opts.accessory ~= nil then
		local width = Theme.FONT_SMALL:getTextWidth(opts.accessory)
		Theme.textCentered(opts.accessory, Theme.WIDTH - Theme.MARGIN, centerY, kTextAlignment.right, Theme.FONT_SMALL)
		right = right + width + Theme.MARGIN
	end

	local available = Theme.WIDTH - x - right
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
