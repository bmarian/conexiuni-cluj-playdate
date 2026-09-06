-- Draws the launcher art into source/launcher/; run through
-- tools/launcher.ps1. A bus in front of Cluj, as 1-bit silhouettes.

import "libraries/noble/Noble"
import "lib/text"
import "lib/icons"
import "lib/theme"

local OUT <const> = "@@OUTPUT_DIR@@/"

local black <const> = Graphics.kColorBlack
local white <const> = Graphics.kColorWhite

local function fill(color) Graphics.setColor(color) end

-- `density` is roughly the fraction of windows lit.
local function drawBuilding(x, y, w, h, density)
	fill(black)
	Graphics.fillRect(x, y, w, h)

	fill(white)
	local windowW, windowH, gap = 3, 4, 4
	local cols = (w - gap) // (windowW + gap)
	local rows = (h - gap) // (windowH + gap)
	local left = x + (w - (cols * (windowW + gap) - gap)) // 2
	for row = 0, rows - 1 do
		for col = 0, cols - 1 do
			if math.random() < density then
				Graphics.fillRect(
					left + col * (windowW + gap),
					y + gap + row * (windowH + gap),
					windowW, windowH
				)
			end
		end
	end
end

-- Saint Michael's: gothic tower, spire, and the clock face that identifies it.
local function drawSpire(centerX, baseY, towerH, spireH)
	local w = 22
	local x = centerX - w // 2

	fill(black)
	Graphics.fillRect(x, baseY - towerH, w, towerH)
	Graphics.fillTriangle(x - 3, baseY - towerH, x + w + 3, baseY - towerH, centerX, baseY - towerH - spireH)

	-- Clock face and the lancet window below it.
	fill(white)
	Graphics.fillCircleAtPoint(centerX, baseY - towerH + 14, 5)
	Graphics.fillRect(centerX - 3, baseY - towerH + 26, 6, 12)
	fill(black)
	Graphics.fillCircleAtPoint(centerX, baseY - towerH + 14, 2)

	-- Cross on top.
	fill(black)
	Graphics.fillRect(centerX - 1, baseY - towerH - spireH - 7, 2, 7)
	Graphics.fillRect(centerX - 3, baseY - towerH - spireH - 5, 6, 2)
end

-- The Orthodox cathedral: drum, dome, and a base wide enough to sit under it.
local function drawDome(centerX, baseY, height)
	local w = 34
	local x = centerX - w // 2

	fill(black)
	Graphics.fillRect(x, baseY - height, w, height)
	-- Drum plus a half-round dome.
	Graphics.fillRect(centerX - 11, baseY - height - 12, 22, 12)
	Graphics.fillCircleAtPoint(centerX, baseY - height - 12, 11)
	Graphics.fillRect(x, baseY - height - 12, w, 12 + 11)

	fill(white)
	Graphics.fillRect(centerX - 8, baseY - height + 8, 4, 9)
	Graphics.fillRect(centerX + 4, baseY - height + 8, 4, 9)
	fill(black)
	Graphics.fillRect(centerX - 1, baseY - height - 34, 2, 8)
end

-- `shortest` has to clear the bus roof, or the skyline is just a fringe
-- poking over it.
local function drawSkyline(baseY, width, shortest, tallest)
	math.randomseed(20260906) -- fixed, so every build draws the same art

	local x = -6
	while x < width do
		local w = 18 + math.random(0, 16)
		local h = shortest + math.random(0, tallest - shortest)
		drawBuilding(x, baseY - h, w, h, 0.55)
		x = x + w + math.random(2, 7)
	end
end

-- Side-view bus, facing right, drawn from its bottom-left corner.
local function drawBus(x, y, w, h)
	local wheelR = math.max(5, h // 5)
	local bodyY = y - h

	-- Thin knock-out between the bus and the buildings; any thicker erases
	-- the skyline instead of outlining the bus.
	fill(white)
	Graphics.fillRoundRect(x - 2, bodyY - 2, w + 4, h + 4, 8)
	Graphics.fillCircleAtPoint(x + w // 4, y, wheelR + 2)
	Graphics.fillCircleAtPoint(x + w - w // 5, y, wheelR + 2)

	fill(black)
	Graphics.fillRoundRect(x, bodyY, w, h, 7)

	-- Windscreen, then a run of side windows.
	local windowY = bodyY + 6
	local windowH = h // 3
	fill(white)
	Graphics.fillRoundRect(x + w - 26, windowY, 20, windowH, 3)

	local sideW, gap = 16, 5
	local sideX = x + 8
	while sideX + sideW < x + w - 32 do
		Graphics.fillRoundRect(sideX, windowY, sideW, windowH, 3)
		sideX = sideX + sideW + gap
	end

	-- Door, headlight, trim.
	Graphics.fillRect(x + w - 34, windowY + windowH + 4, 8, h - windowH - 12)
	Graphics.fillRect(x + w - 7, bodyY + h - 10, 5, 4)
	Graphics.fillRect(x + 6, bodyY + h - 9, w - 46, 2)

	-- Wheels: black tyre, white hub.
	fill(black)
	Graphics.fillCircleAtPoint(x + w // 4, y, wheelR)
	Graphics.fillCircleAtPoint(x + w - w // 5, y, wheelR)
	fill(white)
	Graphics.fillCircleAtPoint(x + w // 4, y, wheelR - 3)
	Graphics.fillCircleAtPoint(x + w - w // 5, y, wheelR - 3)
end

-- Kerb line and dashed centre on white; filling it black flattened the
-- picture against the bus.
local function drawRoad(y, width, height)
	fill(black)
	Graphics.fillRect(0, y, width, 3)
	local x = 8
	local dashY = y + math.max(10, height // 2)
	while x < width do
		Graphics.fillRect(x, dashY, 16, 3)
		x = x + 30
	end
end

-- Rendered small and scaled up: chunky pixels, and no display font to bundle.
local function drawTitle(centerX, y, scale)
	local text <const> = "CONEXIUNI CLUJ"
	local width = Theme.FONT_BIG:getTextWidth(text)
	local height = Theme.FONT_BIG:getHeight()

	local label = Graphics.image.new(width, height, Graphics.kColorClear)
	Graphics.pushContext(label)
	Graphics.setImageDrawMode(Graphics.kDrawModeCopy)
	Noble.Text.draw(text, 0, 0, kTextAlignment.left, false, Theme.FONT_BIG)
	Graphics.popContext()

	label:drawScaled(centerX - (width * scale) // 2, y, scale)
end

local function newCanvas(w, h)
	local image = Graphics.image.new(w, h, Graphics.kColorWhite)
	Graphics.pushContext(image)
	fill(white)
	Graphics.fillRect(0, 0, w, h)
	return image
end

-- card.png: 350x155, the launcher's card view.
local function drawCard()
	local w, h = 350, 155
	local image = newCanvas(w, h)

	local horizon = 124
	-- The bus roof lands at horizon-46, so nothing shorter than that.
	drawSkyline(horizon, w, 50, 84)
	drawSpire(44, horizon, 70, 28)
	drawDome(306, horizon, 54)
	drawRoad(horizon, w, h - horizon)
	drawBus(64, horizon, 214, 46)

	-- Card view shows nothing but this image, so it has to name the app.
	drawTitle(w // 2 + 10, 6, 1)

	Graphics.popContext()
	playdate.simulator.writeToFile(image, OUT .. "card.png")
end

-- launchImage.png: 400x240, the splash while the game loads.
local function drawLaunchImage()
	local w, h = 400, 240
	local image = newCanvas(w, h)

	local horizon = 196
	drawSkyline(horizon, w, 62, 118)
	-- Landmarks sit outside the title's span, roughly x 70..330.
	drawSpire(38, horizon, 92, 36)
	drawDome(356, horizon, 70)
	drawRoad(horizon, w, h - horizon)
	drawBus(75, horizon, 250, 56)

	-- Title in the sky, above the roofline.
	drawTitle(w // 2, 16, 2)

	Graphics.popContext()
	playdate.simulator.writeToFile(image, OUT .. "launchImage.png")
end

-- icon.png: 32x32, the launcher's list view. Too small for the city, so it is
-- the bus alone.
local function drawIcon()
	local image = newCanvas(32, 32)

	fill(black)
	Graphics.fillRoundRect(2, 7, 28, 16, 4)
	fill(white)
	Graphics.fillRect(5, 10, 6, 5)
	Graphics.fillRect(13, 10, 6, 5)
	Graphics.fillRect(21, 10, 6, 5)
	Graphics.fillRect(5, 18, 22, 2)

	fill(black)
	Graphics.fillCircleAtPoint(9, 24, 4)
	Graphics.fillCircleAtPoint(23, 24, 4)
	fill(white)
	Graphics.fillCircleAtPoint(9, 24, 2)
	Graphics.fillCircleAtPoint(23, 24, 2)

	Graphics.popContext()
	playdate.simulator.writeToFile(image, OUT .. "icon.png")
end

if playdate.simulator == nil then
	function playdate.update()
		Graphics.clear(Graphics.kColorWhite)
		Graphics.drawTextAligned("Launcher art generator", 200, 100, kTextAlignment.center)
		Graphics.drawTextAligned("Simulator only, not the app.", 200, 126, kTextAlignment.center)
	end
	return
end

drawCard()
drawLaunchImage()
drawIcon()
playdate.simulator.exit()
