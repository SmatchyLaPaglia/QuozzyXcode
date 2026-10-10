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
  local panelH = math.min(HEIGHT - 110, 320)
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
  local clearBtnX, clearBtnY = panelX, panelY
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
