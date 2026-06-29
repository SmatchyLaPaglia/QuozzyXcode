function nextHaiku()
  local seasonName = seasons[seasonIndex]
  local key = seasonName and string.lower(seasonName) or nil
  local list = key and haikuBySeason[key] or nil

  if not list or #list == 0 then
    currentHaiku = nil
    return
  end

  currentHaiku = list[math.random(1, #list)]
end

function xPositionToCenterText(aText, fontName, fontSizeValue, centerX)
  pushStyle()

  if fontName then font(fontName) end
  if fontSizeValue then fontSize(fontSizeValue) end

  local w, h = textSize(aText)

  popStyle()

  return centerX - w * 0.5
end

------------------------------------------------------------
-- ONE AND ONLY MENU POOF RENDERER
------------------------------------------------------------
function drawMenuSeasonPoof(r)

  ----------------------------------------------------------
  -- Build specs EXACTLY like current code
  ----------------------------------------------------------

  menuSpecA = {
    text  = seasons[seasonIndex],
    font  = "HelveticaNeue-LightItalic",
    size  = math.floor(r.h * 0.75),
    x     = r.cx,
    y     = r.cy,
    color = Color.uiAccent,
    mode  = CENTER,
    align = CENTER
  }

  menuSpecB = {
    text = (currentHaiku and currentHaiku ~= "" and currentHaiku)
    or "Still-song:\nLeaf alone, fluttering alas, leaf alone, fluttering ...\nFloating down the wind",
    "Still-song:\nLeaf alone, fluttering alas, leaf alone, fluttering ...\nFloating down the wind",
    font  = "Helvetica-Oblique",
    size  = math.floor(r.h * 0.19),

    x = xPositionToCenterText(
    currentHaiku or "",
    "Helvetica-Oblique",
    math.floor(r.h * 0.19),
    r.cx
    ),
    y     = r.y * 1.035,

    color = Color.uiAccent2,
    mode  = CORNER,
    align = LEFT
  }

  ----------------------------------------------------------
  -- Initialize module ONCE
  ----------------------------------------------------------


  ----------------------------------------------------------
  -- Draw
  ----------------------------------------------------------

  pushStyle()
  drawPoofingText(menuSpecA, menuSpecB)
  popStyle()
  if TextGoPoof_state() == "A" then
    drawSeasonScatter(r, seasonIndex * 1000 + 17)
  end
end

function drawSeasonScatter(r, seed)

  pushStyle()
  fill(Color.uiAccent)
  noStroke()

  local function seededUnit(s, i, salt)
    local v = math.sin((s or 0) * 12.9898 + i * 78.233 + salt * 37.719) * 43758.5453
    return v - math.floor(v)
  end

  local count = 8

  local yCenter = r.cy - r.h * 0.10
  local ySpread = r.h * 0.22
  local xSpread = r.w * 0.45

  for i = 1, count do
    local rx = seededUnit(seed, i, 1) * 2 - 1
    local ry = seededUnit(seed, i, 2) * 2 - 1

    local x = r.cx + rx * xSpread
    local y = yCenter + ry * ySpread

    local d = 2 + math.floor(seededUnit(seed, i, 3) * 4)
    ellipse(x, y, d, d)
  end

  popStyle()
end

-- Six named globals for section height fractions (Codea hot-reload safe with "or")
titleRow       = titleRow       or (0.27)   -- Section 1: Title & Season height fraction
boardRow       = boardRow       or (0.33)   -- Section 2: Board Area height fraction
minLettersRow  = minLettersRow  or (0.14)   -- Section 3: Minimum Dice Area height fraction
startGameRow   = startGameRow   or (0.13)   -- Section 4: Play Modes height fraction
infoRow        = infoRow        or (0.07)   -- Section 5: Records / Info height fraction
disclaimerRow  = disclaimerRow  or (0.06)   -- Section 6: Disclaimer height fraction
showRowDividers = true  -- toggle pink section boundary lines

function getSectionBoundaries()
  -- Compute section Y boundaries from the six globals (bottom-up stack)
  local dBottom = 0
  local dBot    = dBottom
  local dTop    = dBot + disclaimerRow
  local iBot    = dTop
  local iTop    = iBot + infoRow
  local sBot    = iTop
  local sTop    = sBot + startGameRow
  local mBot    = sTop
  local mTop    = mBot + minLettersRow
  local bBot    = mTop
  local bTop    = bBot + boardRow
  local tBot    = bTop

  local s = {}
  s[6] = { yBot = dBot * HEIGHT, yTop = dTop * HEIGHT }
  s[5] = { yBot = iBot * HEIGHT, yTop = iTop * HEIGHT }
  s[4] = { yBot = sBot * HEIGHT, yTop = sTop * HEIGHT }
  s[3] = { yBot = mBot * HEIGHT, yTop = mTop * HEIGHT }
  s[2] = { yBot = bBot * HEIGHT, yTop = bTop * HEIGHT }
  s[1] = { yBot = tBot * HEIGHT, yTop = HEIGHT          }
  return s
end

------------------------------------------------------------
-- NEW MENU — 6-SECTION PROPORTIONAL LAYOUT
------------------------------------------------------------

function drawMenu()
  background(Color.bg)

  ------------------------------------------------------------
  -- LAYOUT CONSTANTS
  ------------------------------------------------------------

  local HPAD   = 24
  local innerW = WIDTH - 48

  -- Section Y boundaries from named globals
  local s = getSectionBoundaries()

  local function midY(sec)
    return (s[sec].yBot + s[sec].yTop) * 0.5
  end

  -- Initialize global hit rects for touch handling
  menuHitRects = {}

  ------------------------------------------------------------
  -- SECTION 1 — TITLE & SEASON (HANDOFF §3)
  ------------------------------------------------------------

  pushStyle()

  local h1  = HEIGHT * titleRow
  local cx  = WIDTH * 0.5
  local cy1 = midY(1)

  -- Font sizes
  local qSize    = math.min(h1 * 0.34, 64)
  local sSize    = math.min(h1 * 0.16, 28)
  local wSize    = math.min(h1 * 0.28, 52)
  local gap      = math.min(h1 * 0.06, 14)

  -- Stack: Quozzy (top), SEASONS (middle), season name (bottom)
  local totalStackH = qSize + sSize + wSize + 2 * gap
  local stackBot    = cy1 - totalStackH * 0.5

  local seasonNameY = stackBot + wSize * 0.5
  local seasonsY    = seasonNameY + wSize * 0.5 + gap + sSize * 0.5
  local quozzyY     = seasonsY + sSize * 0.5 + gap + qSize * 0.5

  -- "Quozzy" — Georgia Bold
  font("Georgia-Bold")
  fontSize(qSize)
  fill(Color.tileText)
  textMode(CENTER)
  textAlign(CENTER)
  text("Quozzy", cx, quozzyY)

  -- "SEASONS" — Georgia Bold
  font("Georgia-Bold")
  fontSize(sSize)
  text("SEASONS", cx, seasonsY)

  -- Season name / haiku poof area
  local seasonRect = {
    cx = cx,
    cy = seasonNameY,
    x  = cx - innerW * 0.5,
    y  = seasonNameY - wSize * 1.5 * 0.5,
    w  = innerW,
    h  = wSize * 1.5
  }
  drawMenuSeasonPoof(seasonRect)

  popStyle()

  ------------------------------------------------------------
  -- SECTION 2 — BOARD AREA (HANDOFF §4)
  ------------------------------------------------------------

  pushStyle()

  local h2       = HEIGHT * boardRow
  local GRID_GAP = 5

  -- Grid center
  local gridCy = midY(2)

  -- Board grid fills the FULL row height (square)
  local gridW = h2
  local gridH = h2

  -- Derive cell size
  local cellPx = math.max(4, math.floor((gridW - (boardSize - 1) * GRID_GAP) / boardSize))

  -- Recompute exact grid size from cell size
  gridW = boardSize * cellPx + (boardSize - 1) * GRID_GAP
  gridH = gridW

  -- Column split
  local colW       = gridW  -- right column matches grid width
  local leftColW    = innerW - colW
  local rightColCx  = HPAD + leftColW + colW * 0.5

  -- Draw grid preview (right column, upright)
  pushMatrix()
  translate(rightColCx, gridCy)
  -- no rotation — board is drawn upright

  -- Preview letters seeded by boardSize + elapsed seconds
  local previewSeed = boardSize * 1000 + math.floor(ElapsedTime)
  local function seededRand(s, i)
    local v = math.sin((s or 0) * 12.9898 + i * 78.233 + 37.719) * 43758.5453
    return v - math.floor(v)
  end

  local gridLeft = -gridW * 0.5
  local gridBot  = -gridH * 0.5

  for row = 1, boardSize do
    for col = 1, boardSize do
      local idx  = (row - 1) * boardSize + col
      local tx   = gridLeft + (col - 0.5) * (cellPx + GRID_GAP)
      local ty   = gridBot  + (row - 0.5) * (cellPx + GRID_GAP)
      local r    = cellPx * 0.15

      drawRoundedRect(tx, ty, cellPx, cellPx, r, Color.uiAccent, Color.uiAccent)

      -- Decorative letter
      local ltrIdx = math.floor(seededRand(previewSeed, idx) * 26) + 1
      local letter = string.sub("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ltrIdx, ltrIdx)

      font("Georgia-Bold")
      fontSize(cellPx * 0.55)
      fill(255, 255, 255, 255)
      textMode(CENTER)
      textAlign(CENTER)
      text(letter, tx, ty)
    end
  end

  popMatrix()

  -- Left column text: "size" above "N x N"
  local labelSize  = math.max(9,  math.min(h2 * 0.10, 22))
  local numberSize = math.max(12, math.min(h2 * 0.15, 28))
  local textLeftX  = HPAD + 8

  font("Georgia-Italic")
  fontSize(labelSize)
  fill(Color.uiAccent)
  textMode(CORNER)
  textAlign(LEFT)
  local sizeLabelY = gridCy + numberSize * 0.2
  text("size", textLeftX, sizeLabelY)

  font("Georgia-Bold")
  fontSize(numberSize)
  fill(Color.uiAccent)
  local numberStr = boardSize .. " x " .. boardSize
  local numberY   = gridCy - numberSize * 0.5
  text(numberStr, textLeftX, numberY)

  popStyle()

  ------------------------------------------------------------
  -- SECTION 3 — MINIMUM DICE AREA (HANDOFF §5)
  ------------------------------------------------------------

  pushStyle()

  local h3       = HEIGHT * minLettersRow
  local DICE_GAP = 5
  local cy3      = midY(3)

  -- Rocking constants (dice still rocks, just no padding constraint)
  local DICE_ROCK_BASE   = -5.0
  local DICE_ROCK_AMP    = 2.5
  local DICE_ROCK_PERIOD = 5.1

  -- Width constraint from column (as before, no padding constraint)
  local diceColW = innerW * 0.6
  local die5 = (diceColW - 4 * DICE_GAP) / 5
  local die6 = (diceColW - 5 * DICE_GAP) / 6
  local die4 = die5
  local die3 = die4 * 1.13
  local rawDie = ({ [3]=die3, [4]=die4, [5]=die5, [6]=die6 })[MIN_WORD_LEN]

  -- Height cap: limit die size to 72% of row height
  local maxFromH = h3 * 0.72
  local dicePx = math.max(4, math.floor(math.min(rawDie, maxFromH)))
  local diceRowW = MIN_WORD_LEN * dicePx + (MIN_WORD_LEN - 1) * DICE_GAP

  -- Dice row rocking animation
  local diceAngle = DICE_ROCK_BASE + DICE_ROCK_AMP * math.sin((ElapsedTime / DICE_ROCK_PERIOD) * math.pi * 2)

  -- Layout: [dice row] [12px gap] [text column]
  local textColW  = math.min(diceRowW, innerW - diceRowW - 12)
  local totalRowW = diceRowW + 12 + textColW
  local diceRowCx = HPAD + (innerW - totalRowW) * 0.5 + diceRowW * 0.5
  local textColCx = diceRowCx + diceRowW * 0.5 + 12 + textColW * 0.5

  -- Draw tilted dice row
  pushMatrix()
  translate(diceRowCx, cy3)
  rotate(diceAngle)  -- negative base means CW tilt in Codea coordinates

  local dieRowLeft = -(diceRowW * 0.5)
  for i = 1, MIN_WORD_LEN do
    local dx = dieRowLeft + (i - 0.5) * (dicePx + DICE_GAP)
    local r  = dicePx * 0.15

    drawRoundedRect(dx, 0, dicePx, dicePx, r, Color.uiAccent, Color.uiAccent)

    -- Decorative letter: A, B, C...
    local letter = string.sub("ABCDEFGHIJKLMNOPQRSTUVWXYZ", i, i)
    font("Georgia-Bold")
    fontSize(dicePx * 0.5)
    fill(255, 255, 255, 255)
    textMode(CENTER)
    textAlign(CENTER)
    text(letter, dx, 0)
  end

  popMatrix()

  -- Text column: "minimum" above the number
  local diceLabelSize  = math.max(9,  math.min(h3 * 0.12, 20))
  local diceNumberSize = math.max(12, math.min(h3 * 0.18, 26))

  font("Georgia-Italic")
  fontSize(diceLabelSize)
  fill(Color.uiAccent)
  textMode(CENTER)
  textAlign(CENTER)
  text("minimum", textColCx, cy3 + diceLabelSize * 0.3)

  font("Georgia-Bold")
  fontSize(diceNumberSize)
  fill(Color.uiAccent)
  text(tostring(MIN_WORD_LEN), textColCx, cy3 - diceNumberSize * 0.5)

  popStyle()

  ------------------------------------------------------------
  -- SECTION 4 — PLAY MODES (HANDOFF §6)
  ------------------------------------------------------------

  pushStyle()

  local h4     = HEIGHT * startGameRow
  local btnH   = h4 * 0.84
  local btnW   = btnH * 0.82
  local btnR   = btnW * 0.18
  local btnGap = WIDTH * 0.04

  local totalW = 3 * btnW + 2 * btnGap
  local startX = (WIDTH - totalW) * 0.5 + btnW * 0.5

  local soloCx  = startX
  local vsCx    = startX + btnW + btnGap
  local robotCx = startX + 2 * (btnW + btnGap)
  local btn4Cy  = midY(4)

  -- Rocking angles per button
  local soloAngle  = -8.0 + 2.5 * math.sin((ElapsedTime / 3.7) * math.pi * 2)
  local vsAngle    =  4.0 + 2.5 * math.sin((ElapsedTime / 4.9) * math.pi * 2)
  local robotAngle = -5.0 + 2.5 * math.sin((ElapsedTime / 5.5) * math.pi * 2)

  local labelFontSize = math.min(btnH * 0.28, 30)

  local function drawModeButton(cx, cy, angle, label, key)
    pushMatrix()
    translate(cx, cy)
    rotate(angle)

    local fillCol = (pressedButton == key) and Color.uiAccent2 or Color.uiAccent
    drawRoundedRect(0, 0, btnW, btnH, btnR, fillCol, fillCol)

    font("Georgia-Bold")
    fontSize(labelFontSize)
    fill(255, 255, 255, 255)
    textMode(CENTER)
    textAlign(CENTER)
    text(label, 0, 0)

    popMatrix()
  end

  drawModeButton(soloCx, btn4Cy, soloAngle, "solo", "solo")
  drawModeButton(vsCx,   btn4Cy, vsAngle,   "vs",   "vs")
  drawModeButton(robotCx, btn4Cy, robotAngle, "🤖", "robot")

  -- Store hit rects
  menuHitRects.solo  = { cx = soloCx,  cy = btn4Cy, w = btnW, h = btnH }
  menuHitRects.vs    = { cx = vsCx,    cy = btn4Cy, w = btnW, h = btnH }
  menuHitRects.robot = { cx = robotCx, cy = btn4Cy, w = btnW, h = btnH }

  popStyle()

  ------------------------------------------------------------
  -- SECTION 5 — RECORDS / INFO (HANDOFF §7)
  ------------------------------------------------------------

  pushStyle()

  local h5   = HEIGHT * infoRow
  local pad  = math.max(5, math.min((h5 - 2) * 0.5, 10))
  local btnD = h5 - pad * 2
  local hGap = math.min(math.max(h5 * 0.5, 20), 60)
  local midX = WIDTH * 0.5
  local leftBtnCx  = midX - hGap * 0.5
  local rightBtnCx = midX + hGap * 0.5
  local btn5Cy     = midY(5)

  -- Left button (records) — circular
  local recordsFill = (pressedButton == "records") and Color.uiAccent2 or Color.uiAccent
  ellipseMode(CENTER)
  fill(recordsFill)
  noStroke()
  ellipse(leftBtnCx, btn5Cy, btnD, btnD)

  -- Notebook icon inside left button
  pushMatrix()
  translate(leftBtnCx, btn5Cy)
  local iconH = btnD * 0.7
  local iconW = btnD * 0.55
  local ir    = iconW * 0.15
  drawRoundedRect(0, 0, iconW, iconH, ir, color(255, 255, 255, 255), color(255, 255, 255, 255))
  -- horizontal lines
  stroke(Color.uiAccent)
  strokeWidth(1.5)
  noFill()
  for i = 1, 3 do
    local ly = -iconH * 0.25 + (i - 1) * iconH * 0.25
    line(-iconW * 0.35, ly, iconW * 0.35, ly)
  end
  popMatrix()

  -- Right button (info) — circular
  local infoFill = (pressedButton == "info") and Color.uiAccent2 or Color.uiAccent
  fill(infoFill)
  ellipse(rightBtnCx, btn5Cy, btnD, btnD)

  -- "i" label
  fill(255, 255, 255, 255)
  font("Georgia-Bold")
  fontSize(btnD * 0.6)
  textMode(CENTER)
  textAlign(CENTER)
  text("i", rightBtnCx, btn5Cy)

  -- Store hit rects
  menuHitRects.records = { cx = leftBtnCx,  cy = btn5Cy, w = btnD, h = btnD }
  menuHitRects.info    = { cx = rightBtnCx, cy = btn5Cy, w = btnD, h = btnD }

  popStyle()

  ------------------------------------------------------------
  -- SECTION 6 — DISCLAIMER (HANDOFF §8)
  ------------------------------------------------------------

  pushStyle()

  local h6     = HEIGHT * disclaimerRow
  local ftSize = math.max(8, math.min(h6 * 0.13, 14))
  local cy6    = midY(6)

  font("Georgia-Italic")
  fontSize(ftSize)
  fill(Color.tileText.r, Color.tileText.g, Color.tileText.b, 110)
  textMode(CENTER)
  textAlign(CENTER)

  text("Seasons have no effect on gameplay", WIDTH * 0.5, cy6 + ftSize * 0.35)
  text("they're just pretty pretty",         WIDTH * 0.5, cy6 - ftSize * 0.45)

  popStyle()

  -- Draw row dividers (pink lines at section boundaries)
  if showRowDividers then
    pushStyle()
    stroke(255, 105, 180, 220)  -- pink
    strokeWidth(2)
    noFill()
    local s = getSectionBoundaries()
    -- Draw lines at each section boundary (the yBot of each section is the boundary)
    for sec = 5, 1, -1 do
      local y = s[sec].yBot  -- bottom of this section = top of section below it
      line(0, y, WIDTH, y)
    end
    -- Also draw y=0 (bottom) and y=HEIGHT (top) boundaries
    line(0, 0, WIDTH, 0)
    line(0, HEIGHT, WIDTH, HEIGHT)
    popStyle()
  end
end

pressedButton = pressedButton or nil
pressedInside = pressedInside or false

------------------------------------------------------------
-- NEW TOUCH HANDLER — 6-SECTION HIT TESTING
------------------------------------------------------------

function handleMenuTouch(t)
  if t.state == ENDED then
    devLog("DBG_MENU handleMenuTouch ENDED: pressedButton=", tostring(pressedButton))
  end

  didSwipeOnPoofingText(t)

  -- Recompute section boundaries from named globals
  local HPAD = 24
  local s = getSectionBoundaries()

  local function pointInSection(x, y, sec)
    return x >= HPAD and x <= WIDTH - HPAD and
           y >= s[sec].yBot and y <= s[sec].yTop
  end

  -- Find which interactive element was hit
  local function hitKeyAt(x, y)
    -- Check named button rects from drawMenu() first
    if menuHitRects then
      for k, rr in pairs(menuHitRects) do
        if type(rr) == "table" and rr.cx and rr.cy and rr.w and rr.h then
          if pointInRect(x, y, rr.cx, rr.cy, rr.w, rr.h) then
            return k
          end
        end
      end
    end
    -- Check full-section taps
    if pointInSection(x, y, 2) then return "boardSize" end
    if pointInSection(x, y, 3) then return "minWordLen" end
    return nil
  end

  if t.state == BEGAN then
    pressedButton = hitKeyAt(t.x, t.y)
    pressedInside = (pressedButton ~= nil)
    return
  end

  if t.state == MOVING then
    if pressedButton then
      local hit = hitKeyAt(t.x, t.y)
      pressedInside = (hit == pressedButton)
    end
    return
  end

  if t.state ~= ENDED then return end

  local key = pressedButton
  local shouldFire = pressedInside

  pressedButton = nil
  pressedInside = false

  if not shouldFire then return end

  if key == "boardSize" then
    if boardSize == 4 then
      boardSize = 5
    elseif boardSize == 5 then
      boardSize = 6
    else
      boardSize = 4
    end
    if persistGameplaySettings then persistGameplaySettings() end

  elseif key == "minWordLen" then
    MIN_WORD_LEN = MIN_WORD_LEN + 1
    if MIN_WORD_LEN > 6 then MIN_WORD_LEN = 3 end
    if persistGameplaySettings then persistGameplaySettings() end

  elseif key == "solo" then
    setTurnBasedEnabled(false)
    startRoundFromCurrentSettings()

  elseif key == "vs" then
    devLog("DBG_MENU versus tapped: tbm=", tostring(tbm~=nil), "authenticated=", tostring(tbm and tbm.localPlayer and tbm.localPlayer.authenticated))
    if not (tbm and tbm.showMatchmaker) then
      openGCMatchmakerErrorOverlay("Game Center is unavailable in this build or environment.")
      return
    end

    if tbm.localPlayer and tbm.localPlayer.authenticated == true then
      local ok, err = pcall(function() tbm:showMatchmaker() end)
      if not ok then openGCMatchmakerErrorOverlay(err) end
    else
      openGCSignInOverlay()
    end

  elseif key == "robot" then
    setTurnBasedEnabled(false)
    startRoundFromCurrentSettings()

  elseif key == "records" then
    openRecordsOverlay()

  elseif key == "info" then
    showInfoOverlay = true
  end
end

------------------------------------------------------------
-- GUIDE LINES (edit these until they match your screenshot)
-- 9 horizontals (top -> bottom), 4 verticals (left -> right)
------------------------------------------------------------

function getGuideLines()
  -- Fractions of screen; change these numbers only.
  local yShift = 0.04 -- move full menu stack upward by ~half a button height
  local xFrac = {
    0.125, -- v1
    0.175, -- v2
    0.825, -- v3
    0.875  -- v4
  }

  local yFrac = {
    0.873, -- h1 (near top)
    0.65, -- h2
    0.65, -- h3
    0.66, -- h4
    0.54, -- h5
    0.5, -- h6 -- buttons top?
    0.11, -- h7
    0.11, -- h8
    0.06  -- h9 (near bottom)
  }

  local x = {}
  for i = 1, 4 do x[i] = WIDTH * xFrac[i] end

  local y = {}
  for i = 1, 9 do
    y[i] = HEIGHT * math.min(1, yFrac[i] + yShift)
  end

  return x, y
end

------------------------------------------------------------
-- DEBUG DRAW: pink lines
------------------------------------------------------------

function drawPinkLines()
  local x, y = getGuideLines()

  pushStyle()
  stroke(255, 0, 200, 190)
  strokeWidth(3)
  noFill()

  -- verticals
  for i = 1, 4 do
    line(x[i], 0, x[i], HEIGHT)
  end

  -- horizontals
  for i = 1, 9 do
    line(0, y[i], WIDTH, y[i])
  end

  popStyle()
end

------------------------------------------------------------
-- DEBUG DRAW: purple boxes based on your constraints
------------------------------------------------------------

function drawBoxByGuides(x, y, hTop, hBot, vLeft, vRight)
  local left  = x[vLeft]
  local right = x[vRight]
  local top   = y[hTop]
  local bot   = y[hBot]

  -- assume y decreases downward? (Codea: y increases upward)
  -- We want a CORNER rect with bottom-left origin:
  local x0 = left
  local y0 = bot
  local w  = right - left
  local h  = top - bot

  rect(x0, y0, w, h)
end

function drawPurpleSquares()
  local x, y = getGuideLines()

  pushStyle()
  stroke(120, 60, 255, 210)
  strokeWidth(7)
  noFill()
  rectMode(CORNER)

  -- constraints you gave:

  -- horizontals 1-2, verticals 1-4
  drawBoxByGuides(x, y, 1, 2, 1, 4)

  -- horizontals 2-3, verticals 1-4
  drawBoxByGuides(x, y, 2, 3, 1, 4)

  -- horizontals 4-5, verticals 1-4
  drawBoxByGuides(x, y, 4, 5, 1, 4)

  -- horizontals 6-7, verticals 2-3
  drawBoxByGuides(x, y, 6, 7, 2, 3)

  -- horizontals 8-9, verticals 1-4
  drawBoxByGuides(x, y, 8, 9, 1, 4)

  popStyle()
end

------------------------------------------------------------
-- Get rectangle from guide indices
------------------------------------------------------------

function rectFromGuides(hTop, hBot, vLeft, vRight)
  local x, y = getGuideLines()

  local left  = x[vLeft]
  local right = x[vRight]
  local top   = y[hTop]
  local bot   = y[hBot]

  return {
    x = left,
    y = bot,
    w = right - left,
    h = top - bot,
    cx = (left + right) * 0.5,
    cy = (top + bot) * 0.5
  }
end

------------------------------------------------------------
-- LEGACY BUTTON HELPER (kept for backward compatibility)
------------------------------------------------------------

function drawMenuButton(x, y, w, h, label, id)
  pushStyle()

  rectMode(CENTER)
  textMode(CENTER)
  fontSize(22)

  local selected = (pressedButton == id)
  local fillCol  = selected and Color.uiAccent2 or Color.uiAccent

  drawRoundedRect(x, y, w, h, 10, fillCol, fillCol)

  fill(255,255,255,255) -- allowed exception
  text(label, x, y)

  popStyle()
end

menuSpecA = menuSpecA or {
  text  = currentSeasonName or "Autumn",
  font  = "Georgia-Italic",
  size  = 80,
  x     = WIDTH/2,
  y     = HEIGHT/2 + 40,
  color = color(177,114,51),
  mode  = CENTER,
  align = CENTER
}

menuSpecB = menuSpecB or {
  text  = currentHaiku or
  "A world of dew,\nand within every dewdrop\na world of struggle.",
  font  = "Helvetica-Bold",
  size  = 20,
  x     = WIDTH/2 - 120,
  y     = HEIGHT/2 - 40,
  color = color(222,151,75),
  mode  = CORNER,
  align = LEFT
}

menuSpecA = menuSpecA or nil
menuSpecB = menuSpecB or nil
