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

------------------------------------------------------------
-- INFO / ABOUT OVERLAY
------------------------------------------------------------
-- Content blocks for the About panel. type:
--   "h1"     section header
--   "p"      plain paragraph
--   "bullet" bold lead-in line (its own line) + an indented body paragraph below it
-- Wrapped into flat display lines by buildAboutLines() (below), cached per panel width.
ABOUT_CONTENT = {
  { type = "h1", text = "What Is This?" },
  { type = "p",  text = "It's a word-hunt game. You know the deal." },

  { type = "h1", text = "But Why?" },
  { type = "p",  text = "Who needs another one of these, right? Well this version has a couple agendas:" },
  { type = "bullet", lead = "No Engagement Strategies:", text =
    "one goal is to be uncluttered. To not do all those flashy promotions like \"here's 20 free ZagBux for logging in during the third lunar cycle\226\128\148be sure to log in for the Vernal Equinox too!\" It's just, like, this app, you know?" },
  { type = "bullet", lead = "Emphasizing Rivalries:", text =
    "Another goal is to put front and center your most frequent opponent, and to show, right there on the home screen, how many games you've won against each other. How else can you have grudge matches? And isn't that what makes life worth living?" },
  { type = "bullet", lead = "Abundant Irrelevant Theming:", text =
    "Why all the seasonal stuff and changing colors? It's just frippery, for sure. But it makes the experience a little different than other word-hunt games. Plus it's kind of soothing to watch the transitions, mannn." },
  { type = "bullet", lead = "Haiku for the Heck of It:", text =
    "There's a hidden seasonally-themed Classical Japanese haiku on every menu screen, for no real reason than it's kind of cool to have a little haiku break in your day. Which is a little soothing too." },

  { type = "h1", text = "Where'd You Get The Haiku?" },
  { type = "p",  text = "The haiku come from \"Japanese Haiku\" (1955), a publicly-available translation of Classical Japanese haiku by Peter Beilenson. Thanks Peter!" },

  { type = "h1", text = "About AI" },
  { type = "p",  text = "I designed this. I did the things that make it odd. The haiku. The speech balloons. The wacky tilty-tappy menu. Thems warn't anyone but me." },
  { type = "p",  text = "Yes, AI brought my messy sketches to life. Yes, everything that makes it work is AI. But everything that makes it weird is me." },
  { type = "p",  text = "I hope you like it." },
}

infoScrollY       = infoScrollY       or 0
infoScrollTouchId = infoScrollTouchId or nil
infoScrollPrevY   = infoScrollPrevY   or 0
infoOverlayGeom   = infoOverlayGeom   or nil
aboutLinesCache   = aboutLinesCache   or nil  -- { wrapWidth = , lines = } — rebuilt only when panel width changes

function openInfoOverlay()
  showInfoOverlay   = true
  infoScrollY       = 0
  infoScrollTouchId = nil
end

function closeInfoOverlay()
  showInfoOverlay   = false
  infoScrollTouchId = nil
end

-- Greedy word-wrap using the CURRENTLY SET font/fontSize (caller must set them first).
local function wrapTextLines(str, maxWidth)
  local words = {}
  for word in tostring(str or ""):gmatch("%S+") do
    words[#words + 1] = word
  end
  if #words == 0 then return { "" } end

  local lines = {}
  local current = words[1]
  for i = 2, #words do
    local candidate = current .. " " .. words[i]
    if textSize(candidate) <= maxWidth then
      current = candidate
    else
      lines[#lines + 1] = current
      current = words[i]
    end
  end
  lines[#lines + 1] = current
  return lines
end

-- Flattens ABOUT_CONTENT into display lines: {text, font, size, indent, gapBefore, alpha}.
-- gapBefore is extra vertical space above that line (paragraph/section spacing); only the
-- first wrapped line of a block carries it, so mid-paragraph wrap lines sit tight together.
function buildAboutLines(wrapWidth)
  if aboutLinesCache and aboutLinesCache.wrapWidth == wrapWidth then
    return aboutLinesCache.lines
  end

  local out = {}
  pushStyle()
  textMode(CORNER)

  for bi, block in ipairs(ABOUT_CONTENT) do
    if block.type == "h1" then
      font("Georgia-Bold"); fontSize(26)
      local lines = wrapTextLines(block.text, wrapWidth)
      for li, l in ipairs(lines) do
        out[#out + 1] = { text = l, font = "Georgia-Bold", size = 26, indent = 0,
          gapBefore = (li == 1) and (bi > 1 and 26 or 0) or 0, alpha = 255 }
      end

    elseif block.type == "p" then
      font("Georgia"); fontSize(18)
      local lines = wrapTextLines(block.text, wrapWidth)
      for li, l in ipairs(lines) do
        out[#out + 1] = { text = l, font = "Georgia", size = 18, indent = 0,
          gapBefore = (li == 1) and 10 or 0, alpha = 235 }
      end

    elseif block.type == "bullet" then
      font("Georgia-Bold"); fontSize(18)
      local leadLines = wrapTextLines("\226\128\162 " .. (block.lead or ""), wrapWidth)
      for li, l in ipairs(leadLines) do
        out[#out + 1] = { text = l, font = "Georgia-Bold", size = 18, indent = 0,
          gapBefore = (li == 1) and 16 or 0, alpha = 255 }
      end

      font("Georgia"); fontSize(18)
      local bodyLines = wrapTextLines(block.text, wrapWidth - 22)
      for li, l in ipairs(bodyLines) do
        out[#out + 1] = { text = l, font = "Georgia", size = 18, indent = 22,
          gapBefore = (li == 1) and 4 or 0, alpha = 235 }
      end
    end
  end

  popStyle()
  aboutLinesCache = { wrapWidth = wrapWidth, lines = out }
  return out
end

function drawInfoOverlay()
  if not showInfoOverlay then return end

  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)
  popStyle()

  local panelW = WIDTH - 32
  local panelH = HEIGHT - 110
  local panelX = WIDTH * 0.5
  local panelY = HEIGHT * 0.5

  pushStyle()
  rectMode(CENTER)
  noStroke()
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)
  popStyle()

  local innerPadding = 24
  local innerLeft   = panelX - panelW/2 + innerPadding
  local innerRight  = panelX + panelW/2 - innerPadding
  local innerTop    = panelY + panelH/2 - innerPadding
  local innerBottom = panelY - panelH/2 + innerPadding
  local innerWidth  = innerRight - innerLeft

  pushStyle()
  local tileText = Color.tileText or color(255)

  -- Title (fixed, does not scroll)
  fill(tileText)
  font("Georgia-Bold")
  fontSize(28)
  textMode(CORNER)
  textAlign(CENTER)
  text("About", panelX, innerTop - 30)

  -- Close button (fixed, bottom of panel)
  local btnW, btnH = 200, 48
  local btnX = panelX
  local btnY = innerBottom + btnH/2
  drawButton(btnX, btnY, btnW, btnH, "Close", false)

  -- Scrollable body, between the title and the close button
  local bodyTop    = innerTop - 58
  local bodyBottom = btnY + btnH/2 + 16
  local bodyHeight = bodyTop - bodyBottom
  local bodyLeft   = innerLeft

  local lines = buildAboutLines(innerWidth)

  local totalH = 20  -- trailing padding so the last line doesn't feel clipped
  for _, ln in ipairs(lines) do
    totalH = totalH + ln.gapBefore + math.floor(ln.size * 1.3)
  end
  local maxScroll = math.max(0, totalH - bodyHeight)
  if infoScrollY < 0 then infoScrollY = 0 end
  if infoScrollY > maxScroll then infoScrollY = maxScroll end

  clip(bodyLeft, bodyBottom, innerWidth, bodyHeight)
  textMode(CORNER)
  textAlign(LEFT)

  -- infoScrollY grows as the user scrolls FORWARD through the content (drags up), which
  -- must bring later lines UP toward bodyTop — i.e. ADD infoScrollY here, not subtract.
  -- (Verified by walking through the totalH/bodyHeight numbers by hand: with a minus sign,
  -- any infoScrollY > 0 pushes every single line below bodyBottom and the panel renders
  -- blank — caught via a forced infoScrollY=900 test + devLog before shipping this.)
  local cursorY = bodyTop + infoScrollY
  for _, ln in ipairs(lines) do
    cursorY = cursorY - ln.gapBefore
    local lineH = math.floor(ln.size * 1.3)
    local drawY = cursorY - lineH
    if drawY < bodyTop + lineH and drawY > bodyBottom - lineH then
      font(ln.font)
      fontSize(ln.size)
      fill(tileText.r, tileText.g, tileText.b, ln.alpha)
      text(ln.text, bodyLeft + ln.indent, drawY)
    end
    cursorY = drawY
  end
  clip()

  popStyle()

  infoOverlayGeom = {
    bodyLeft = bodyLeft, bodyBottom = bodyBottom, bodyWidth = innerWidth, bodyHeight = bodyHeight,
    btnX = btnX, btnY = btnY, btnW = btnW, btnH = btnH,
  }
end

function handleInfoOverlayTouch(t)
  if not showInfoOverlay then return false end

  local g = infoOverlayGeom
  if not g then
    if t.state == ENDED then closeInfoOverlay() end
    return true
  end

  if t.state == BEGAN then
    if pointInRect(t.x, t.y, g.btnX, g.btnY, g.btnW, g.btnH) then
      closeInfoOverlay()
      return true
    end
    if t.x >= g.bodyLeft and t.x <= g.bodyLeft + g.bodyWidth and
       t.y >= g.bodyBottom and t.y <= g.bodyBottom + g.bodyHeight then
      infoScrollTouchId = t.id
      infoScrollPrevY   = t.y
      return true
    end
    return true
  elseif t.state == MOVING then
    if infoScrollTouchId and t.id == infoScrollTouchId then
      local dy = t.y - infoScrollPrevY
      infoScrollPrevY = t.y
      -- Drag up (finger moves toward larger y, dy > 0) reveals later content, matching
      -- cursorY's "+infoScrollY" above — so this ADDS dy, the mirror image of that formula.
      infoScrollY = infoScrollY + dy
    end
    return true
  elseif t.state == ENDED or t.state == CANCELLED then
    if infoScrollTouchId and t.id == infoScrollTouchId then
      infoScrollTouchId = nil
    end
    return true
  end

  return true
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
