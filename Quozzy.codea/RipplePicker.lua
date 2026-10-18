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
  local panelH = math.min(HEIGHT - 90, 700)
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

  if clearMatchesStatus then
    fill(tileText.r, tileText.g, tileText.b, 200)
    font("HelveticaNeue-Bold")
    fontSize(14)
    textMode(CENTER)
    textAlign(CENTER)
    text(clearMatchesStatus, clearBtnX, rippleBtnY - rippleBtnH / 2 - 12)
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
  local rerollTuneTop = rerollTuneBottom + rerollRows * rowH

  drawRecordsInfoLayoutMockup(panelX, panelW, rerollTuneTop + 8, rippleBtnY - rippleBtnH / 2 - 40)
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

-- Proposal mockup (for approval): current overlapping records/info pair vs.
-- the proposed side-by-side pair (info left, records right) with the
-- "unseen result" badge on records. Drawn at real menu size with the menu's
-- own button drawing.
function drawRecordsInfoLayoutMockup(cx, panelW, bottom, top)
  if not (drawMenuRecordsButton and drawMenuInfoButton) then return end
  local h5   = HEIGHT * (infoRow or 0.07)
  local pad  = math.max(5, math.min((h5 - 2) * 0.5, 10))
  local d    = h5 - pad * 2
  local hGap = math.min(math.max(h5 * 0.5, 20), 60)
  local tileText = Color.tileText or color(255)
  local btnY = bottom + (top - bottom) * 0.42
  local colL, colR = cx - panelW * 0.25, cx + panelW * 0.25

  pushStyle()
  fill(tileText)
  font("Georgia-Bold")
  fontSize(18)
  textMode(CENTER)
  text("Proposed records / info buttons", cx, top - 4)
  font("HelveticaNeue-Bold")
  fontSize(13)
  fill(tileText.r, tileText.g, tileText.b, 190)
  text("now", colL, btnY + d * 0.5 + 22)
  text("proposed", colR, btnY + d * 0.5 + 22)

  -- now: overlapping, records left / info right
  drawMenuRecordsButton(colL - hGap * 0.5, btnY, d, false)
  drawMenuInfoButton(colL + hGap * 0.5, btnY, d, false)

  -- proposed: info left, records right, a small gap, badge on records
  local gap = d * (MENU_RECORDS_INFO_GAP or 0.15)
  local infoCx    = colR - (d + gap) * 0.5
  local recordsCx = colR + (d + gap) * 0.5
  drawMenuInfoButton(infoCx, btnY, d, false)
  drawMenuRecordsButton(recordsCx, btnY, d, false)
  drawCircleButtonBadge(recordsCx, btnY, d)

  fontSize(12)
  fill(tileText.r, tileText.g, tileText.b, 170)
  text("Same red dot on Records rows: opponent row (any unseen) and match row (unseen result)",
    cx, btnY - d * 0.5 - 22)
  popStyle()
end
