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
  "haiku from translation by Peter Beilenson, \"Japanese Haiku\" (1955)\n\nvia sacred-texts.com"
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