-- The fonts have no glyphs for Romanian diacritics, so names have to be
-- stripped to ASCII before any drawText* call.

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

-- drawText/drawTextAligned do not clip, so callers cap length themselves.
function Text.truncate(s, maxLen)
	if s == nil then return "" end
	if #s <= maxLen then return s end
	return s:sub(1, maxLen - 1) .. "."
end

local function widthOf(s, font)
	if font ~= nil then return font:getTextWidth(s) end
	return playdate.graphics.getTextSize(s)
end

-- `font` must be the font the text is drawn in, or labels collide.
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

-- Greedy wrap into at most `maxLines` lines, each truncated to `maxWidth`.
-- Hand-rolled because drawTextInRect renders nothing here (see AGENTS.md).
function Text.wrapToWidth(s, maxWidth, maxLines, font)
	if s == nil or s == "" then return {} end

	local lines = {}
	local current = nil
	for word in s:gmatch("%S+") do
		local candidate = current and (current .. " " .. word) or word
		if current ~= nil and widthOf(candidate, font) > maxWidth then
			if #lines + 1 >= maxLines then
				-- No room for another line; truncation below handles it.
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

-- Natural sort: zero-pads digit runs so "25N" falls between "25" and "26"
-- ("25N" -> "000025n"). Digits sort before letters, so "M11" comes last.
function Text.sortKey(s)
	if s == nil then return "" end
	return (Text.clean(s):lower():gsub("%d+", function(digits)
		return string.format("%06d", tonumber(digits))
	end))
end

-- Past-midnight departures are published GTFS-style as "25:05". Sort on the
-- raw value, draw this.
function Text.clockLabel(hhmm)
	if hhmm == nil then return "" end
	local hour, minute = hhmm:match("(%d+):(%d+)")
	if hour == nil then return hhmm end
	return string.format("%02d:%s", tonumber(hour) % 24, minute)
end

-- "now" under a minute, a countdown under an hour, a clock time beyond that.
function Text.whenLabel(secondsAway, absoluteSeconds)
	if secondsAway < 60 then return "now" end
	if secondsAway < 3600 then return (secondsAway // 60) .. "m" end
	local wrapped = absoluteSeconds % (24 * 3600)
	return string.format("%02d:%02d", wrapped // 3600, (wrapped % 3600) // 60)
end
