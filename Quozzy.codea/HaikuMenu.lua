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
  
  if seed then math.randomseed(seed) end
  
  local count = 8
  
  local yCenter = r.cy - r.h * 0.10
  local ySpread = r.h * 0.22
  local xSpread = r.w * 0.45
  
  for i = 1, count do
    local rx = math.random(-1000, 1000) / 1000
    local ry = math.random(-1000, 1000) / 1000
    
    local x = r.cx + rx * xSpread
    local y = yCenter + ry * ySpread
    
    local d = math.random(2, 5)
    ellipse(x, y, d, d)
  end
  
  popStyle()
end

function drawMenu()
  background(Color.bg)
  
  ------------------------------------------------------------
  -- LAYOUT SECTIONS (from your guides)
  ------------------------------------------------------------
  
  local titleRect   = rectFromGuides(1, 2, 1, 4)
  local stripRect   = rectFromGuides(2, 3, 1, 4)
  local seasonRect  = rectFromGuides(4, 5, 1, 4)
  local buttonsRect = rectFromGuides(6, 7, 2, 3)
  local footerRect  = rectFromGuides(8, 9, 1, 4)
  
  ------------------------------------------------------------
  -- TITLE
  ------------------------------------------------------------
  
  drawTitleSection(titleRect)
  
  ------------------------------------------------------------
  -- SMALL STRIP (SEASON LABEL)
  ------------------------------------------------------------
  
  pushStyle()
  font("Georgia")
  fontSize(stripRect.h * 0.45)
  fill(Color.tileText)
  textMode(CENTER)
  textAlign(CENTER)
  text("SEASONS", stripRect.cx, stripRect.cy)
  popStyle()
  
  ------------------------------------------------------------
  -- MAIN SEASON (POOF TEXT)
  ------------------------------------------------------------
  
  drawMenuSeasonPoof(seasonRect)
  ------------------------------------------------------------
  -- BUTTON GRID
  ------------------------------------------------------------
  
  drawButtonGridSection(buttonsRect)
  
  ------------------------------------------------------------
  -- FOOTER
  ------------------------------------------------------------
  
  drawFooterSection(footerRect)
  
end

local function getButtonGridHitRects(r)
  local gapY = r.h * 0.06
  local btnH = (r.h - gapY * 3) / 4
  local btnW = r.w * 0.47
  
  local leftX  = r.cx - r.w * 0.25
  local rightX = r.cx + r.w * 0.25
  
  local y1 = r.y + r.h - btnH * 0.5
  local y2 = y1 - (btnH + gapY)
  local y3 = y2 - (btnH + gapY)
  
  return {
    size    = { cx=leftX,  cy=y1, w=btnW, h=btnH },
    min     = { cx=rightX, cy=y1, w=btnW, h=btnH },
    solo    = { cx=leftX,  cy=y2, w=btnW, h=btnH },
    versus  = { cx=rightX, cy=y2, w=btnW, h=btnH },
    records = { cx=leftX,  cy=y3, w=btnW, h=btnH },
    info    = { cx=rightX, cy=y3, w=btnW, h=btnH },  -- same size as others
  }
end

pressedButton = pressedButton or nil
pressedInside = pressedInside or false

function handleMenuTouch(t)
  
  didSwipeOnPoofingText(t)
  
  local buttonsRect = rectFromGuides(6, 7, 2, 3)
  local R = getButtonGridHitRects(buttonsRect)
  
  local function hitKeyAt(x, y)
    for k, rr in pairs(R) do
      if pointInRect(x, y, rr.cx, rr.cy, rr.w, rr.h) then
        return k
      end
    end
    return nil
  end
  
  if t.state == BEGAN then
    pressedButton = hitKeyAt(t.x, t.y)
    pressedInside = (pressedButton ~= nil)
    return
  end
  
  if t.state == MOVING then
    if pressedButton then
      local rr = R[pressedButton]
      pressedInside = pointInRect(t.x, t.y, rr.cx, rr.cy, rr.w, rr.h)
    end
    return
  end
  
  if t.state ~= ENDED then return end
  
  local key = pressedButton
  local shouldFire = false
  
  if key then
    local rr = R[key]
    shouldFire = pointInRect(t.x, t.y, rr.cx, rr.cy, rr.w, rr.h)
  end
  
  pressedButton = nil
  pressedInside = false
  
  if not shouldFire then return end
  
  if key == "size" then
    boardSize = (boardSize == 4) and 5 or 4
    if persistGameplaySettings then persistGameplaySettings() end
    
  elseif key == "min" then
    MIN_WORD_LEN = MIN_WORD_LEN + 1
    if MIN_WORD_LEN > 5 then MIN_WORD_LEN = 3 end
    if persistGameplaySettings then persistGameplaySettings() end
    
  elseif key == "solo" then
    setTurnBasedEnabled(false)
    startRoundFromCurrentSettings()
    
  elseif key == "versus" then
    if not (tbm and tbm.showMatchmaker) then
      openGCMatchmakerErrorOverlay("Game Center is unavailable in this build or environment.")
      return
    end
    
    local ok, err = pcall(function()
      tbm:showMatchmaker()
    end)
    
    if not ok then
      openGCMatchmakerErrorOverlay(err)
    end
    
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
  for i = 1, 9 do y[i] = HEIGHT * yFrac[i] end
  
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

function drawTitleSection(r)
  pushStyle()
  
  font("Georgia-Bold")
  fontSize(r.h * 0.55)
  fill(Color.tileText)
  
  textMode(CENTER)
  textAlign(CENTER)
  text("Quozzy", r.cx, r.cy + r.h * 0.15)
  
  fontSize(r.h * 0.25)
  text("SEASONS", r.cx, r.cy - r.h * 0.2)
  
  popStyle()
end


pressedButton = pressedButton or nil

function drawButtonGridSection(r)
  pushStyle()
  font("Helvetica")
  
  local gapY = r.h * 0.06
  local btnH = (r.h - gapY * 3) / 4
  local btnW = r.w * 0.47
  
  local leftX  = r.cx - r.w * 0.25
  local rightX = r.cx + r.w * 0.25
  
  local y = r.y + r.h - btnH * 0.5
  
  ----------------------------------------------------------
  -- Row 1
  ----------------------------------------------------------
  
  drawButton(
  leftX, y, btnW, btnH,
  string.format("%d x %d", boardSize, boardSize),
  pressedButton == "size"
  )
  
  drawButton(
  rightX, y, btnW, btnH,
  string.format("min %d", MIN_WORD_LEN),
  pressedButton == "min"
  )
  
  y = y - (btnH + gapY)
  
  ----------------------------------------------------------
  -- Row 2
  ----------------------------------------------------------
  
  drawButton(leftX,  y, btnW, btnH, "solo",   pressedButton == "solo")
  drawButton(rightX, y, btnW, btnH, "versus", pressedButton == "versus")
  
  y = y - (btnH + gapY)
  
  ----------------------------------------------------------
  -- Row 3
  ----------------------------------------------------------
  
  drawButton(leftX,  y, btnW, btnH, "records", pressedButton == "records")
  drawButton(rightX, y, btnW, btnH, "i",       pressedButton == "info")
  
  popStyle()
end

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

function drawFooterSection(r)
  pushStyle()
  
  font("Georgia")
  fontSize(r.h * 0.45)
  fill(Color.tileText.r, Color.tileText.g, Color.tileText.b, 110)
  
  textMode(CENTER)
  textAlign(CENTER)
  textWrapWidth(WIDTH*0.9)
  text(
  "Seasons have no effect on gameplay\n they're just pretty pretty",
  r.cx,
  r.cy
  )
  
  popStyle()
end

function drawMenuLayout()
  background(Color.bg)
  
  -- Title
  drawTitleSection(
  rectFromGuides(1, 2, 1, 4)
  )
  
  -- Season label (small strip)
  drawSeasonSection(
  rectFromGuides(2, 3, 1, 4)
  )
  
  -- Season name big
  drawSeasonSection(
  rectFromGuides(4, 5, 1, 4)
  )
  
  -- Button grid (center box)
  drawButtonGridSection(
  rectFromGuides(6, 7, 2, 3)
  )
  
  -- Footer
  drawFooterSection(
  rectFromGuides(8, 9, 1, 4)
  )
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
