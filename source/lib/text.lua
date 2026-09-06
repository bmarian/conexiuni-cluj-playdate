-- The default system font has no glyphs for Romanian diacritics, so synced
-- route/stop names (real Romanian text) render as "?" placeholders. Strip
-- them to plain ASCII before any drawText* call. Covers both the standard
-- comma-below letters (ș/ț) and the cedilla variants (ş/ţ) some sources use
-- interchangeably.

Text = Text or {}

local replacements = {
	["ă"] = "a", ["Ă"] = "A",
	["â"] = "a", ["Â"] = "A",
	["î"] = "i", ["Î"] = "I",
	["ș"] = "s", ["Ș"] = "S", ["ş"] = "s", ["Ş"] = "S",
	["ț"] = "t", ["Ț"] = "T", ["ţ"] = "t", ["Ţ"] = "T",
}

function Text.clean(s)
	if s == nil then return "" end
	for from, to in pairs(replacements) do
		s = s:gsub(from, to)
	end
	return s
end

-- Manual length cap for text drawn with the unclipped drawText/drawTextAligned
-- (no bounding box to truncate against automatically).
function Text.truncate(s, maxLen)
	if s == nil then return "" end
	if #s <= maxLen then return s end
	return s:sub(1, maxLen - 1) .. "."
end

local function widthOf(s, font)
	if font ~= nil then return font:getTextWidth(s) end
	return playdate.graphics.getTextSize(s)
end

-- Same idea but measured in actual pixel width, for laying out labels next to
-- each other (list rows, stop names along the route line) where a character
-- count can't predict overlap. `font` is the font it will be drawn in --
-- measuring in one font and drawing in another is how labels end up colliding.
function Text.truncateToWidth(s, maxWidth, font)
	if s == nil or s == "" then return "" end
	if widthOf(s, font) <= maxWidth then return s end

	local lo, hi = 0, #s
	while lo < hi do
		local mid = (lo + hi + 1) // 2
		local candidate = s:sub(1, mid) .. "."
		if widthOf(candidate, font) <= maxWidth then
			lo = mid
		else
			hi = mid - 1
		end
	end
	if lo == 0 then return "." end
	return s:sub(1, lo) .. "."
end

-- Greedy word wrap into at most `maxLines` lines of at most `maxWidth`
-- pixels, so a two-word stop name can use two lines instead of being cut in
-- half. Anything that still doesn't fit (one very long word, or more lines
-- than allowed) is truncated by width, so the result is always inside the
-- box the caller asked for. Returns an array of lines.
--
-- Hand-rolled rather than using drawTextInRect: that call renders nothing at
-- all in this project (see AGENTS.md), and the caller needs the line count
-- up front to place the block anyway.
function Text.wrapToWidth(s, maxWidth, maxLines, font)
	if s == nil or s == "" then return {} end

	local lines = {}
	local current = nil
	for word in s:gmatch("%S+") do
		local candidate = current and (current .. " " .. word) or word
		if current ~= nil and widthOf(candidate, font) > maxWidth then
			if #lines + 1 >= maxLines then
				-- No room for another line: cram the rest onto this one and
				-- let truncation deal with it.
				current = candidate
				break
			end
			table.insert(lines, current)
			current = word
		else
			current = candidate
		end
	end
	if current ~= nil then table.insert(lines, current) end

	for i, line in ipairs(lines) do
		lines[i] = Text.truncateToWidth(line, maxWidth, font)
	end
	return lines
end

-- Sort key for natural (human) ordering: route "25N" belongs between "25" and
-- "26", not between "2" and "3", and plain string comparison gets that wrong
-- because it compares "1" against "0" of "100" character by character.
--
-- Zero-padding every run of digits to a fixed width turns the problem back
-- into a plain string compare: "25N" -> "000025n", "100" -> "000100",
-- "M11" -> "m000011". Digits sort before letters in ASCII, so numbered routes
-- come before the M-prefixed metropolitan ones, which is the order the paper
-- timetables use. Diacritics are stripped first so stop names sort the way
-- they're drawn.
function Text.sortKey(s)
	if s == nil then return "" end
	return (Text.clean(s):lower():gsub("%d+", function(digits)
		return string.format("%06d", tonumber(digits))
	end))
end

-- CTP publishes a service day that runs past midnight the GTFS way: the
-- 01:05 night bus is listed as "25:05", so its departures keep sorting after
-- the 23:00 one instead of jumping to the top of the timetable. Sort on the
-- raw value, draw this.
function Text.clockLabel(hhmm)
	if hhmm == nil then return "" end
	local hour, minute = hhmm:match("(%d+):(%d+)")
	if hour == nil then return hhmm end
	return string.format("%02d:%s", tonumber(hour) % 24, minute)
end
