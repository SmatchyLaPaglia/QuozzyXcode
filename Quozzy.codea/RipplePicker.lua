------------------------------------------------------------
-- DEBUG MENU (RipplePicker.lua, 2026-10-08 — repurposed)
-- Opened via the 🐛 debug button (SHOW_DEBUG_BUTTON, Main.lua). Hosts a
-- "Clear All Matches" button for day-to-day GC debugging, plus buttons that
-- open their own dedicated tuning overlays (Plate Placement, Ripple Tuning)
-- so each stays uncluttered rather than all living in one panel. Board-
-- reroll tuning steppers live directly in this panel (small enough that a
-- separate overlay isn't worth it yet). Kept the filename and the
-- ripplePickerOverlay/openRipplePickerOverlay/handleRipplePickerTouch names
-- so HaikuMenu.lua, Main.lua, and Badges.lua's overlay-suppression check
-- didn't need to change.
------------------------------------------------------------

ripplePickerOverlay = ripplePickerOverlay or false

function openRipplePickerOverlay()
  ripplePickerOverlay = true
end

clearMatchesStatus = clearMatchesStatus or nil
local clearMatchesBtnRect = nil
local platePlacementBtnRect = nil
local rippleTuningBtnRect = nil
local menuLettersBtnRect = nil
local closeBtnRect = nil
local rerollTuneBtnRects = {}   -- { rect, key, dir }
local rerollTuneResetRect = nil

local function handleClearMatchesTouch(t)
  if not clearMatchesBtnRect then return false end
  if not pointInRect(t.x, t.y, clearMatchesBtnRect.x, clearMatchesBtnRect.y, clearMatchesBtnRect.w, clearMatchesBtnRect.h) then
    return false
  end
  if not tbm then
    clearMatchesStatus = "No GameCenter session"
    return true
  end
  clearMatchesStatus = "Clearing matches..."
  tbm:onMatchesCleared(function(count)
    clearMatchesStatus = "Cleared " .. tostring(count) .. " match" .. (count == 1 and "" or "es")
  end)
  tbm:clearAllMatches()
  return true
end

function drawRipplePickerOverlay()
  if not ripplePickerOverlay then return end

  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)
  popStyle()

  local panelW = WIDTH - 32
  local panelH = math.min(HEIGHT - 90, 640)
  local panelX = WIDTH * 0.5
  local panelY = HEIGHT * 0.5
  panelY, panelH = clampPanelTopToSafeArea(panelY, panelH)

  pushStyle()
  rectMode(CENTER)
  noStroke()
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)
  popStyle()

  local innerTop    = panelY + panelH / 2 - 20
  local innerBottom = panelY - panelH / 2 + 20

  pushStyle()
  local tileText = Color.tileText or color(255)

  fill(tileText)
  font("Georgia-Bold")
  fontSize(24)
  textMode(CORNER)
  textAlign(CENTER)
  local title = "Debug Menu"
  text(title, panelX - textSize(title) * 0.5, innerTop - 26)

  local clearBtnW, clearBtnH = 260, 56
  local clearBtnX, clearBtnY = panelX, innerTop - 90
  drawButton(clearBtnX, clearBtnY, clearBtnW, clearBtnH, "Clear All Matches", false)
  clearMatchesBtnRect = { x = clearBtnX, y = clearBtnY, w = clearBtnW, h = clearBtnH }

  -- Opens the Plate Placement overlay (MenuPanels.lua): live tuning of the menu's panels
  local plateBtnW, plateBtnH = 260, 48
  local plateBtnX, plateBtnY = panelX, clearBtnY - clearBtnH / 2 - 14 - plateBtnH / 2
  drawButton(plateBtnX, plateBtnY, plateBtnW, plateBtnH, "Plate Placement", false)
  platePlacementBtnRect = { x = plateBtnX, y = plateBtnY, w = plateBtnW, h = plateBtnH }

  -- Opens its own overlay (below): ripple-distortion tuning, moved out of
  -- this panel so it doesn't compete for space with reroll tuning.
  local rippleBtnW, rippleBtnH = 260, 48
  local rippleBtnX, rippleBtnY = panelX, plateBtnY - plateBtnH / 2 - 14 - rippleBtnH / 2
  drawButton(rippleBtnX, rippleBtnY, rippleBtnW, rippleBtnH, "Ripple Tuning", false)
  rippleTuningBtnRect = { x = rippleBtnX, y = rippleBtnY, w = rippleBtnW, h = rippleBtnH }

  -- Opens the Menu Letters overlay (below): the menu's changing letters.
  local lettersBtnW, lettersBtnH = 260, 48
  local lettersBtnX, lettersBtnY = panelX, rippleBtnY - rippleBtnH / 2 - 14 - lettersBtnH / 2
  drawButton(lettersBtnX, lettersBtnY, lettersBtnW, lettersBtnH, "Menu Letters", false)
  menuLettersBtnRect = { x = lettersBtnX, y = lettersBtnY, w = lettersBtnW, h = lettersBtnH }

  if clearMatchesStatus then
    fill(tileText.r, tileText.g, tileText.b, 200)
    font("HelveticaNeue-Bold")
    fontSize(14)
    textMode(CENTER)
    textAlign(CENTER)
    text(clearMatchesStatus, clearBtnX, lettersBtnY - lettersBtnH / 2 - 12)
  end

  local closeBtnW, closeBtnH = 200, 48
  local closeBtnX = panelX
  local closeBtnY = innerBottom + closeBtnH / 2

  -- Board-reroll tuning steppers: "- Label value +" grid, driven by
  -- rerollTuneDefs/rerollTune (Board.lua).
  local rowH, btnS = 38, 34
  local colW = panelW * 0.5 - 12
  local rerollTuneBottom = closeBtnY + closeBtnH / 2 + 16
  rerollTuneBtnRects = {}
  local rerollCells = #rerollTuneDefs + 1
  local rerollRows = math.ceil(rerollCells / 2)
  for i, d in ipairs(rerollTuneDefs) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local cx = panelX + (col - 0.5) * (colW + 8)
    local cy = rerollTuneBottom + (rerollRows - 1 - row) * rowH + rowH / 2
    local mx, px = cx - colW / 2 + btnS / 2, cx + colW / 2 - btnS / 2
    drawButton(mx, cy, btnS, btnS - 2, "-", false)
    drawButton(px, cy, btnS, btnS - 2, "+", false)
    rerollTuneBtnRects[#rerollTuneBtnRects + 1] = { x = mx, y = cy, w = btnS, h = btnS - 2, key = d.key, dir = -1 }
    rerollTuneBtnRects[#rerollTuneBtnRects + 1] = { x = px, y = cy, w = btnS, h = btnS - 2, key = d.key, dir = 1 }
    fill(tileText)
    font("HelveticaNeue-Bold")
    fontSize(14)
    textMode(CENTER)
    text(d.label .. " " .. tostring(rerollTune[d.key]), cx, cy)
  end
  do
    local i = #rerollTuneDefs
    local col, row = i % 2, math.floor(i / 2)
    local cx = panelX + (col - 0.5) * (colW + 8)
    local cy = rerollTuneBottom + (rerollRows - 1 - row) * rowH + rowH / 2
    drawButton(cx, cy, colW, btnS - 2, "Reset reroll", false)
    rerollTuneResetRect = { x = cx, y = cy, w = colW, h = btnS - 2 }
  end
  drawButton(closeBtnX, closeBtnY, closeBtnW, closeBtnH, "Close", false)
  closeBtnRect = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH }

  popStyle()
end

function handleRipplePickerTouch(t)
  if not ripplePickerOverlay then return false end
  if t.state == ENDED then
    if handleClearMatchesTouch(t) then
      return true
    end
    if platePlacementBtnRect and pointInRect(t.x, t.y, platePlacementBtnRect.x, platePlacementBtnRect.y, platePlacementBtnRect.w, platePlacementBtnRect.h) then
      ripplePickerOverlay = false
      openPlatePlacementOverlay()
      return true
    end
    if rippleTuningBtnRect and pointInRect(t.x, t.y, rippleTuningBtnRect.x, rippleTuningBtnRect.y, rippleTuningBtnRect.w, rippleTuningBtnRect.h) then
      ripplePickerOverlay = false
      openRippleTuneOverlay()
      return true
    end
    if menuLettersBtnRect and pointInRect(t.x, t.y, menuLettersBtnRect.x, menuLettersBtnRect.y, menuLettersBtnRect.w, menuLettersBtnRect.h) then
      ripplePickerOverlay = false
      menuFlipTuneOverlay = true
      return true
    end
    for _, r in ipairs(rerollTuneBtnRects) do
      if pointInRect(t.x, t.y, r.x, r.y, r.w, r.h) then
        rerollTuneNudge(r.key, r.dir)
        return true
      end
    end
    if rerollTuneResetRect and pointInRect(t.x, t.y, rerollTuneResetRect.x, rerollTuneResetRect.y, rerollTuneResetRect.w, rerollTuneResetRect.h) then
      rerollTuneReset()
      return true
    end
    if closeBtnRect and pointInRect(t.x, t.y, closeBtnRect.x, closeBtnRect.y, closeBtnRect.w, closeBtnRect.h) then
      ripplePickerOverlay = false
    end
  end
  return true
end

------------------------------------------------------------
-- Ripple Tuning overlay — split out of the main debug panel above so
-- ripple's 7 steppers don't crowd out reroll's. Opened only from the
-- "Ripple Tuning" button there (same pattern as Plate Placement: closes
-- the main panel on the way in, closes straight to the menu on the way
-- out, not back to the main panel).
------------------------------------------------------------
rippleTuneOverlay = rippleTuneOverlay or false
local rtCloseBtnRect = nil
local rtResetBtnRect = nil
local rtTestBtnRect = nil
local rtTuneBtnRects = {}
local rtDemoStart = nil   -- ElapsedTime the test badge appeared (drawn over the panel)
local rtDemoRippled = false

function openRippleTuneOverlay()
  rippleTuneOverlay = true
end

local function rtDemoAge()
  if not rtDemoStart then return nil end
  local age = ElapsedTime - rtDemoStart
  if age > quickStart.visibleDuration then rtDemoStart = nil return nil end
  return age
end

function drawRippleTuneOverlay()
  if not rippleTuneOverlay then return end

  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)
  popStyle()

  local panelW = WIDTH - 32
  local panelH = math.min(HEIGHT - 90, 560)
  local panelX = WIDTH * 0.5
  local panelY = HEIGHT * 0.5
  panelY, panelH = clampPanelTopToSafeArea(panelY, panelH)

  pushStyle()
  rectMode(CENTER)
  noStroke()
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)
  popStyle()

  local innerTop    = panelY + panelH / 2 - 20
  local innerBottom = panelY - panelH / 2 + 20

  pushStyle()
  local tileText = Color.tileText or color(255)

  fill(tileText)
  font("Georgia-Bold")
  fontSize(24)
  textMode(CORNER)
  textAlign(CENTER)
  local title = "Ripple Tuning"
  text(title, panelX - textSize(title) * 0.5, innerTop - 26)

  local rippleBtnW, rippleBtnH = 260, 56
  local rippleBtnX, rippleBtnY = panelX, innerTop - 90
  drawButton(rippleBtnX, rippleBtnY, rippleBtnW, rippleBtnH, "Test Ripple", false)
  rtTestBtnRect = { x = rippleBtnX, y = rippleBtnY, w = rippleBtnW, h = rippleBtnH }

  local closeBtnW, closeBtnH = 200, 48
  local closeBtnX = panelX
  local closeBtnY = innerBottom + closeBtnH / 2

  -- ripple tuning steppers: 2 columns of "- Label value +", plus Reset in the last cell
  local rowH, btnS = 38, 34
  local colW = panelW * 0.5 - 12
  local tuneBottom = closeBtnY + closeBtnH / 2 + 16
  rtTuneBtnRects = {}
  local cells = #rippleTuneDefs + 1
  local rows = math.ceil(cells / 2)
  for i, d in ipairs(rippleTuneDefs) do
    local col, row = (i - 1) % 2, math.floor((i - 1) / 2)
    local cx = panelX + (col - 0.5) * (colW + 8)
    local cy = tuneBottom + (rows - 1 - row) * rowH + rowH / 2
    local mx, px = cx - colW / 2 + btnS / 2, cx + colW / 2 - btnS / 2
    drawButton(mx, cy, btnS, btnS - 2, "-", false)
    drawButton(px, cy, btnS, btnS - 2, "+", false)
    rtTuneBtnRects[#rtTuneBtnRects + 1] = { x = mx, y = cy, w = btnS, h = btnS - 2, key = d.key, dir = -1 }
    rtTuneBtnRects[#rtTuneBtnRects + 1] = { x = px, y = cy, w = btnS, h = btnS - 2, key = d.key, dir = 1 }
    fill(tileText)
    font("HelveticaNeue-Bold")
    fontSize(14)
    textMode(CENTER)
    text(d.label .. " " .. tostring(rippleTune[d.key]), cx, cy)
  end
  do
    local i = #rippleTuneDefs
    local col, row = i % 2, math.floor(i / 2)
    local cx = panelX + (col - 0.5) * (colW + 8)
    local cy = tuneBottom + (rows - 1 - row) * rowH + rowH / 2
    drawButton(cx, cy, colW, btnS - 2, "Reset ripple", false)
    rtResetBtnRect = { x = cx, y = cy, w = colW, h = btnS - 2 }
  end

  drawButton(closeBtnX, closeBtnY, closeBtnW, closeBtnH, "Close", false)
  rtCloseBtnRect = { x = closeBtnX, y = closeBtnY, w = closeBtnW, h = closeBtnH }

  popStyle()

  -- test badge on top of the panel; ripple fires rippleTune.delay seconds after it appears
  local age = rtDemoAge()
  if age then
    drawQuickStartBadgeAt(WIDTH / 2, HEIGHT / 2, age, quickStart.visibleDuration)
    if not rtDemoRippled and age >= rippleTune.delay then
      rtDemoRippled = true
      startScreenRipple(WIDTH / 2, HEIGHT / 2, rippleTune.rim)
    end
  end
end

function handleRippleTuneTouch(t)
  if not rippleTuneOverlay then return false end
  if t.state == ENDED then
    if rtTestBtnRect and pointInRect(t.x, t.y, rtTestBtnRect.x, rtTestBtnRect.y, rtTestBtnRect.w, rtTestBtnRect.h) then
      rtDemoStart = ElapsedTime
      rtDemoRippled = false
      return true
    end
    for _, r in ipairs(rtTuneBtnRects) do
      if pointInRect(t.x, t.y, r.x, r.y, r.w, r.h) then
        rippleTuneNudge(r.key, r.dir)
        return true
      end
    end
    if rtResetBtnRect and pointInRect(t.x, t.y, rtResetBtnRect.x, rtResetBtnRect.y, rtResetBtnRect.w, rtResetBtnRect.h) then
      rippleTuneReset()
      return true
    end
    if rtCloseBtnRect and pointInRect(t.x, t.y, rtCloseBtnRect.x, rtCloseBtnRect.y, rtCloseBtnRect.w, rtCloseBtnRect.h) then
      rippleTuneOverlay = false
    end
  end
  return true
end

------------------------------------------------------------
-- Menu Letters overlay — live tuning of the main menu's changing letters
-- (menuFlipTune, HaikuMenu.lua). Unlike the panels above it's a bottom
-- sheet with no dimming, so the board preview stays visible above it while
-- you tune. Two tabs: Board (the preview's letter-change effect: timing,
-- scale, color) and Dice (the min-length dice spin). Values persist.
-- Opened from the Debug Menu's "Menu Letters" button; Close returns to the menu.
------------------------------------------------------------
menuFlipTuneOverlay = menuFlipTuneOverlay or false
menuFlipTunePage = menuFlipTunePage or "board"
local mfRects = {}   -- { x, y, w, h, act, key, dir } (centre-based, like drawButton)

function drawMenuFlipTuneOverlay()
  if not menuFlipTuneOverlay then return end
  mfRects = {}

  local defs = {}
  for _, d in ipairs(menuFlipTuneDefs) do
    if d.page == menuFlipTunePage then defs[#defs + 1] = d end
  end

  local rowH, btnS = 31, 28
  local cells = #defs + 1             -- + "Tick now" / spacer cell
  local rows = math.ceil(cells / 2) + 1   -- + the tab/Reset/Close row
  local headerH = 24
  local panelW = math.min(WIDTH - 24, 560)
  local panelH = headerH + rows * rowH + 16
  local panelX = WIDTH * 0.5
  local panelBot = getBottomSafeY() + 6
  local panelY = panelBot + panelH / 2

  pushStyle()
  rectMode(CENTER)
  noStroke()
  local bg = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 235)
  drawRoundedRect(panelX, panelY, panelW, panelH, 16, bg, bg)

  local tileText = Color.tileText or color(255)
  fill(tileText)
  font("HelveticaNeue-Bold")
  fontSize(15)
  textMode(CENTER)
  textAlign(CENTER)
  text("Menu Letters — " .. (menuFlipTunePage == "board" and "board" or "min. length dice"),
       panelX, panelBot + panelH - 8 - headerH / 2)

  local colW = panelW * 0.5 - 12
  local gridTop = panelBot + panelH - 8 - headerH
  local function cellCenter(i)   -- i is 0-based, row-major, 2 columns
    local col, row = i % 2, math.floor(i / 2)
    return panelX + (col - 0.5) * (colW + 8), gridTop - row * rowH - rowH / 2
  end

  for i, d in ipairs(defs) do
    local cx, cy = cellCenter(i - 1)
    local mx, px = cx - colW / 2 + btnS / 2, cx + colW / 2 - btnS / 2
    drawButton(mx, cy, btnS, btnS - 2, "-", false)
    drawButton(px, cy, btnS, btnS - 2, "+", false)
    mfRects[#mfRects + 1] = { x = mx, y = cy, w = btnS, h = btnS - 2, act = "nudge", key = d.key, dir = -1 }
    mfRects[#mfRects + 1] = { x = px, y = cy, w = btnS, h = btnS - 2, act = "nudge", key = d.key, dir = 1 }
    local v = menuFlipTune[d.key]
    local shown = string.format("%g", v)
    if d.key == "percent" and v == 0 then shown = "diff."
    elseif d.key == "customColor" then shown = (v >= 1) and "on" or "off" end
    fill(tileText)
    font("HelveticaNeue-Bold")
    fontSize(13)
    text(d.label .. " " .. shown, cx, cy)
  end

  -- Last grid cell (board tab): change tiles right now instead of waiting for the tick
  local sx, sy = cellCenter(#defs)
  if menuFlipTunePage == "board" then
    drawButton(sx, sy, colW, btnS - 2, "Tick now", false)
    mfRects[#mfRects + 1] = { x = sx, y = sy, w = colW, h = btnS - 2, act = "tick" }
  end

  -- Bottom row: tab switch | Reset (this tab) | Close
  local by = panelBot + 8 + rowH / 2
  local bw = (panelW - 40) / 3
  local labels = { menuFlipTunePage == "board" and "Dice >" or "Board >", "Reset", "Close" }
  local acts = { "page", "reset", "close" }
  for i = 1, 3 do
    local bx = panelX + (i - 2) * (bw + 8)
    drawButton(bx, by, bw, btnS, labels[i], false)
    mfRects[#mfRects + 1] = { x = bx, y = by, w = bw, h = btnS, act = acts[i] }
  end
  popStyle()
end

function handleMenuFlipTuneTouch(t)
  if not menuFlipTuneOverlay then return false end
  if t.state ~= ENDED then return true end
  for _, r in ipairs(mfRects) do
    if pointInRect(t.x, t.y, r.x, r.y, r.w, r.h) then
      if r.act == "nudge" then
        menuFlipTuneNudge(r.key, r.dir)
      elseif r.act == "tick" then
        menuPreviewBoard.forceTick = true
      elseif r.act == "page" then
        menuFlipTunePage = (menuFlipTunePage == "board") and "dice" or "board"
      elseif r.act == "reset" then
        menuFlipTuneReset(menuFlipTunePage)
      elseif r.act == "close" then
        menuFlipTuneOverlay = false
      end
      return true
    end
  end
  return true   -- swallow touches elsewhere so tuning never starts a game
end
