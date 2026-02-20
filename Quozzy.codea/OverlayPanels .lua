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

gcMatchmakerErrorOverlay = gcMatchmakerErrorOverlay or false
gcMatchmakerErrorText = gcMatchmakerErrorText or "Could not open Game Center matchmaking."

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
