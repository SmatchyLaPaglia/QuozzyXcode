function buildOverlaySprite(w, h, bgOverride, cornerR)
    w = math.floor(w + 0.5)
    h = math.floor(h + 0.5)
    
    local img = image(w, h)
    setContext(img)
    pushStyle()
    background(0, 0, 0, 0)
    rectMode(CENTER)
    
    local bg = bgOverride or Color.panelBG
    local solid = color(bg.r, bg.g, bg.b, 255)
    
    -- Fall back to percentage roundedness if not provided
    local r = cornerR or math.min(w, h) * 0.06
    
    drawRoundedRect(w/2, h/2, w, h, r, solid, solid)
    
    popStyle()
    setContext()
    
    return img
end

function rebuildOverlayPanelsForSeason()
    local endW = WIDTH  * 0.8
    local endH = HEIGHT * 0.8
    overlayPanelEnd = buildOverlaySprite(endW, endH)
    
    local recW = WIDTH  * 0.85
    local recH = HEIGHT * 0.85
    overlayPanelRecords = buildOverlaySprite(recW, recH)
    
    -----------------------------------------------------
    -- READY TAP PANEL SPRITE (uses OLD dimensions)
    -----------------------------------------------------
    local tileSize, startX, startY = computeGridLayout()
    
    -- Measure the text in advance (same text, same font)
    local fs = tileSize * 0.35
    fontSize(fs)
    local label = "Tap anywhere\nto start"
    local tw, th = textSize(label)
    
    -- Use your old padding and roundedness
    local padX   = tileSize * 0.7
    local padY   = tileSize * 0.45
    local panelW = tw + padX * 2
    local panelH = th + padY * 2
    local cornerR = tileSize * 0.25
    
    -- Seasonal color for fill
    local bgCol = Color.selectLineAlsoWeirdlyTileHighlight
    
    -- Build sprite with the old shape & corner curves
    readyTapPanel = buildOverlaySprite(panelW, panelH, bgCol, cornerR)
end

function drawInfoOverlay()
  if not showInfoOverlay then return end
  local HAIKU_ATTRIBUTION_TEXT =
  "haiku from translation by Peter Beilenson, \"Japanese Haiku\" (1955)"
  ------------------------------------------------------------
  -- Dim background (same as records overlay)
  ------------------------------------------------------------
  
  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)
  popStyle()
  
  ------------------------------------------------------------
  -- Measure wrapped text to size panel
  ------------------------------------------------------------
  
  pushStyle()
  fontSize(22)
  textMode(CORNER)
  
  local textW = WIDTH - 100
  textWrapWidth(textW)
  
  local w, h = textSize(HAIKU_ATTRIBUTION_TEXT)
  
  local margin = 40
  local panelW = w + margin * 2
  local panelH = h + margin * 2
  
  local panelX = WIDTH / 2
  local panelY = HEIGHT / 2
  
  ------------------------------------------------------------
  -- Panel (simple rounded rect fallback)
  ------------------------------------------------------------
  
  pushStyle()
  rectMode(CENTER)
  noStroke()
  
  local r = 22  -- corner radius; tweak if desired
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b) or color(40, 40, 40)
  
  drawRoundedRect(panelX, panelY, panelW, panelH, r, solid, solid)
  
  popStyle()
  
  ------------------------------------------------------------
  -- Text
  ------------------------------------------------------------
  
  fill(Color.tileText or color(255))
  
  local textX = panelX - panelW/2 + margin
  local textY = panelY + panelH/2 - margin - h
  
  text(HAIKU_ATTRIBUTION_TEXT, textX, textY)
  
  popStyle()
end

------------------------------------------------------------
-- THEME COLOR INSPECTOR OVERLAY (debug)
-- Lists every color in the live Color palette (reflects the
-- active season) as swatch + key name + RGBA. Tap to dismiss.
------------------------------------------------------------

colorInspectorOverlay = colorInspectorOverlay or false

function drawColorInspectorOverlay()
  if not colorInspectorOverlay then return end

  pushStyle()

  -- Dim background
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)

  -- Collect color entries from the live palette
  local entries = {}
  for k, v in pairs(Color) do
    if type(v) == "userdata" and v.r ~= nil then
      entries[#entries + 1] = { name = k, col = v }
    end
  end
  table.sort(entries, function(a, b) return a.name < b.name end)

  -- Panel
  local panelX, panelY = WIDTH * 0.5, HEIGHT * 0.5
  local panelW = WIDTH - 32
  local panelH = HEIGHT - 110
  local solid  = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  rectMode(CENTER)
  noStroke()
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)

  local pad    = 22
  local left   = panelX - panelW / 2 + pad
  local right   = panelX + panelW / 2 - pad
  local top    = panelY + panelH / 2 - pad
  local bottom = panelY - panelH / 2 + pad

  local tileText = Color.tileText or color(255)

  -- Title + hint
  fill(tileText)
  font("Georgia-Bold")
  fontSize(22)
  textMode(CENTER)
  textAlign(CENTER)
  text("Theme colors — " .. (seasons[seasonIndex] or "?"), panelX, top - 14)

  fill(tileText.r, tileText.g, tileText.b, 130)
  font("Georgia-Italic")
  fontSize(12)
  text("tap anywhere to close", panelX, bottom + 4)

  -- Grid (2 columns)
  local gridTop = top - 40
  local gridBot = bottom + 22
  local cols    = 2
  local colGap  = 14
  local cellW   = (right - left - colGap * (cols - 1)) / cols
  local n       = #entries
  local rows    = math.ceil(n / cols)
  local rowH    = (gridTop - gridBot) / math.max(1, rows)

  for i, e in ipairs(entries) do
    local ci     = (i - 1) % cols
    local ri     = math.floor((i - 1) / cols)
    local cellX  = left + ci * (cellW + colGap)
    local cellCy = gridTop - (ri + 0.5) * rowH

    -- Swatch (bordered so light colors show against the panel)
    local sw = math.min(rowH * 0.62, 32)
    rectMode(CENTER)
    stroke(tileText.r, tileText.g, tileText.b, 120)
    strokeWidth(1)
    fill(e.col)
    rect(cellX + sw / 2, cellCy, sw, sw, 6)
    noStroke()

    local tx     = cellX + sw + 8
    local availW = cellW - sw - 8

    -- Name (shrink to fit the cell; the longest key is an outlier)
    local nameFs = 14
    font("Georgia-Bold")
    fontSize(nameFs)
    local nw = textSize(e.name)
    if nw and nw > availW and nw > 0 then
      nameFs = math.max(8, nameFs * availW / nw)
    end
    fontSize(nameFs)
    textMode(CORNER)
    textAlign(LEFT)
    fill(tileText)
    text(e.name, tx, cellCy + 1)

    -- RGBA below the name
    local c = e.col
    font("Georgia")
    fontSize(10)
    fill(tileText.r, tileText.g, tileText.b, 150)
    text(string.format("%d, %d, %d, %d",
      math.floor(c.r + 0.5), math.floor(c.g + 0.5),
      math.floor(c.b + 0.5), math.floor(c.a + 0.5)),
      tx, cellCy - 13)
  end

  popStyle()
end

gcMatchmakerErrorOverlay = gcMatchmakerErrorOverlay or false
gcMatchmakerErrorText = gcMatchmakerErrorText or "Could not open Game Center matchmaking."

------------------------------------------------------------
-- GC Sign-In Overlay
------------------------------------------------------------
gcSignInOverlay = gcSignInOverlay or false

function openGCSignInOverlay()
  gcSignInOverlay = true
end

function closeGCSignInOverlay()
  gcSignInOverlay = false
end

function drawGCSignInOverlay()
  if not gcSignInOverlay then return end

  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)

  local margin  = 28
  local panelW  = math.min(WIDTH * 0.86, 560)
  local innerW  = panelW - margin * 2
  local panelX  = WIDTH / 2
  local panelY  = HEIGHT / 2

  local title     = "Something Ker-Flumped"
  local body      = "You'll have to open Settings and log in to Game Center to play friends."
  local titleFont = 22
  local bodyFont  = 20

  fontSize(titleFont); textWrapWidth(innerW)
  local _, titleH = textSize(title)
  fontSize(bodyFont); textWrapWidth(innerW)
  local _, bodyH = textSize(body)

  local panelH = margin + titleH + 18 + bodyH + margin

  rectMode(CENTER); noStroke()
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)

  local left = panelX - panelW/2 + margin
  local yTop = panelY + panelH/2 - margin

  fill(Color.tileText or color(255))
  fontSize(titleFont); textWrapWidth(innerW); textMode(CORNER)
  text(title, left, yTop - titleH)

  fontSize(bodyFont); textWrapWidth(innerW)
  text(body, left, yTop - titleH - 18 - bodyH)

  popStyle()
end

function handleGCSignInOverlayTouch(t)
  if not gcSignInOverlay then return false end
  if t.state ~= ENDED and t.state ~= CANCELLED then return true end
  closeGCSignInOverlay()
  return true
end

function openGCMatchmakerErrorOverlay(details)
  gcMatchmakerErrorOverlay = true
  if details and details ~= "" then
    gcMatchmakerErrorText = "Could not open Game Center matchmaking.\n\n" .. tostring(details)
  else
    gcMatchmakerErrorText = "Could not open Game Center matchmaking."
  end
end

function drawGCMatchmakerErrorOverlay()
  if not gcMatchmakerErrorOverlay then return end

  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)
  popStyle()

  pushStyle()
  textMode(CORNER)
  local margin = 28
  local panelW = math.min(WIDTH * 0.86, 560)
  local innerW = panelW - margin * 2
  local panelMaxH = HEIGHT * 0.86
  local panelX = WIDTH / 2
  local panelY = HEIGHT / 2
  
  local title = "Game Center Error"
  local footer = "Tap anywhere to dismiss"
  local titleFont = 22
  local bodyFont = 20
  local footerFont = 16
  
  local titleH, bodyH, footerH
  while true do
    fontSize(titleFont)
    textWrapWidth(innerW)
    local _, tH = textSize(title)
    
    fontSize(bodyFont)
    textWrapWidth(innerW)
    local _, bH = textSize(gcMatchmakerErrorText)
    
    fontSize(footerFont)
    textWrapWidth(innerW)
    local _, fH = textSize(footer)
    
    titleH, bodyH, footerH = tH, bH, fH
    local needed = margin + titleH + 18 + bodyH + 18 + footerH + margin
    if needed <= panelMaxH or bodyFont <= 16 then break end
    bodyFont = bodyFont - 1
  end
  
  local panelH = margin + titleH + 18 + bodyH + 18 + footerH + margin

  rectMode(CENTER)
  noStroke()
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)

  fill(Color.tileText or color(255))
  local left = panelX - panelW/2 + margin
  local yTop = panelY + panelH/2 - margin
  
  fontSize(titleFont)
  textWrapWidth(innerW)
  text(title, left, yTop - titleH)
  
  fontSize(bodyFont)
  textWrapWidth(innerW)
  local textY = yTop - titleH - 18 - bodyH
  text(gcMatchmakerErrorText, left, textY)

  fill(Color.uiAccent2 or color(255, 120, 120))
  fontSize(footerFont)
  textWrapWidth(innerW)
  local footerY = panelY - panelH/2 + margin
  text(footer, left, footerY)
  popStyle()
end
