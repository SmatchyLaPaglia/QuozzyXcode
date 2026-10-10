------------------------------------------------------------
-- DEBUG MENU (RipplePicker.lua, 2026-10-08 — repurposed)
-- Opened via the 🐛 debug button (SHOW_DEBUG_BUTTON, Main.lua). Used to show a
-- 6-candidate comparison grid for the match-ready badge's "droplet hits still
-- water" entrance animation — that comparison is done (the winning variant
-- shipped into RippleShader.lua's drawShaderRipple, see STRUCTURE.md "Ripple
-- Picker debug overlay" / "Match-ready badge ripple" for that history), so
-- this file now just hosts a "Clear All Matches" button for day-to-day GC
-- debugging. Kept the filename and the ripplePickerOverlay/
-- openRipplePickerOverlay/handleRipplePickerTouch names so HaikuMenu.lua,
-- Main.lua, and Badges.lua's overlay-suppression check didn't need to change.
------------------------------------------------------------

ripplePickerOverlay = ripplePickerOverlay or false

function openRipplePickerOverlay()
  ripplePickerOverlay = true
end

clearMatchesStatus = clearMatchesStatus or nil
local clearMatchesBtnRect = nil
local closeBtnRect = nil

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
  local panelH = math.min(HEIGHT - 110, 520)
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

  if clearMatchesStatus then
    fill(tileText.r, tileText.g, tileText.b, 200)
    font("HelveticaNeue-Bold")
    fontSize(14)
    textMode(CENTER)
    textAlign(CENTER)
    text(clearMatchesStatus, clearBtnX, clearBtnY - clearBtnH / 2 - 20)
  end

  local closeBtnW, closeBtnH = 200, 48
  local closeBtnX = panelX
  local closeBtnY = innerBottom + closeBtnH / 2

  drawRecordsInfoLayoutMockup(panelX, panelW, closeBtnY + closeBtnH / 2 + 24, clearBtnY - clearBtnH / 2 - 40)
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
    if closeBtnRect and pointInRect(t.x, t.y, closeBtnRect.x, closeBtnRect.y, closeBtnRect.w, closeBtnRect.h) then
      ripplePickerOverlay = false
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
