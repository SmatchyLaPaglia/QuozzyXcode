--############################################################
-- vs-button badge (menu)
--############################################################
-- Replaces the old hopping "MATCH READY / TAP HERE" floating badge (which
-- used to roam the menu and separately poll Game Center on its own timer).
-- The vs button now carries a small static red dot instead — no number, no
-- animation — driven by vsHasActionable (MatchSelection.lua's
-- refreshVsMatchesList), which is already true exactly when the vs button's
-- own list has something needing attention (an unplayed or unviewed-finished
-- match). Suppressed under the same overlays the old badge was, so it can
-- never float over a panel.

pendingTurnMatches = pendingTurnMatches or {}  -- legacy store; kept only for the debug
                                                -- "Simulate Incoming Turn" parameter hook

function badgeSuppressed()
  return colorInspectorOverlay or showInfoOverlay or recordsOverlay or balloonMockupOverlay
     or balloonColorPickerOverlay or gcSignInOverlay or gcMatchmakerErrorOverlay or genericAlertActive
     or vsOverlay or ripplePickerOverlay
end

-- Small solid red dot, radius r, centered at (cx, cy). Shared by the vs-button badge and
-- the per-row "unseen result" badges in the vs list (MatchSelection.lua _drawVsMatchesList).
function drawRedBadgeDot(cx, cy, r)
  pushStyle()
  noStroke()
  ellipseMode(CENTER)
  fill(230, 40, 40, 255)
  ellipse(cx, cy, r * 2)
  popStyle()
end

-- rect = {cx, cy, w, h} of the vs button (menuHitRects.vs)
function drawVsButtonBadge(rect)
  if not rect then return end
  if state ~= STATE_MENU then return end
  if badgeSuppressed() then return end
  if not vsHasActionable then return end

  local r = math.max(8, math.min(rect.w, rect.h) * 0.12)
  local x = rect.cx + rect.w * 0.5 - r * 0.6
  local y = rect.cy + rect.h * 0.5 - r * 0.6
  drawRedBadgeDot(x, y, r)
end

--############################################################
-- Quick Start (menu) — fast path into whichever match needs you next,
-- without opening the vs list at all
--############################################################
-- This is the action half of what used to be a single hopping "MATCH READY /
-- TAP HERE" badge (the vs-button red dot above is the other half — passive
-- signal only). Re-implemented on the same hop/ripple mechanic as before,
-- clearer label, retargeted to vsListEntries/vsHasActionable (MatchSelection.lua)
-- instead of the old standalone pendingTurnMatches/refreshPendingMatchesForBadge
-- poll loop.

quickStart = quickStart or {
  active          = false,
  x               = 0,
  y               = 0,
  radius          = 42,

  phase           = "hidden",
  phaseTime       = 0,

  visibleDuration = 4.4,
  hiddenDuration  = 0.005,
  appearDuration  = 0.25,
  disappearDuration = 0.25,

  maxScale        = 1.15,
  rippleCount     = 4,
  rippleWidth     = 4,
  rippleDuration  = 3,
  rippleSpeed     = 7,

  permanentRippleOffset = 8,
  permanentRippleWidth  = 7,

  minHopDistance  = 140,
  avoidOrigin = vec2(WIDTH/2, HEIGHT/2 + 20),
  avoidW            = 320,
  avoidH            = 300,
  showDebugRect    = false,

  lastX           = nil,
  lastY           = nil,

  rotationDegRange = 40,
  rotation        = 0,
  rotationDir     = 1,
}

quickStartWasMenuLastFrame = quickStartWasMenuLastFrame or false
quickStartLastPollAt = quickStartLastPollAt or 0
quickStartPollInterval = quickStartPollInterval or 8.0

local function _quickStartInsideAvoidRect(px, py)
  local o  = quickStart.avoidOrigin
  local hw = (quickStart.avoidW or 0) * 0.5
  local hh = (quickStart.avoidH or 0) * 0.5
  if px >= o.x - hw and px <= o.x + hw and py >= o.y - hh and py <= o.y + hh then
    return true
  end
  -- Also keep the whole circle (+ margin) off every live menu button. handleQuickStartTouch
  -- gets touches first, so a hop onto solo/vs/replay/records/info hijacked that button's tap.
  -- (Measured 2026-09-26 via DevRemote: 4 of 7 hops overlapped a button.)
  local clear = (quickStart.radius or 0) * (quickStart.maxScale or 1.25) + 8
  for _, b in pairs(menuHitRects or {}) do
    local bx, by = b.cx or b.x, b.cy or b.y
    if bx and by and b.w and b.h then
      local nx = math.max(bx - b.w * 0.5, math.min(px, bx + b.w * 0.5))
      local ny = math.max(by - b.h * 0.5, math.min(py, by + b.h * 0.5))
      if (px - nx)^2 + (py - ny)^2 < clear * clear then return true end
    end
  end
  return false
end

-- One word per line; the badge advances to the next phrase on every hop.
QUICK_START_PHRASES = QUICK_START_PHRASES or {
  { "QUICK", "START", "NEXT", "MATCH" },
  { "PROVE", "YOU'RE", "MAD", "FIT!" },
  { "JUMP", "IN!", "PLAY", "NOW!" },
  { "DON'T", "LET", "BULLIES", "WIN" },
  { "TAP", "HERE", "TO", "RUMBLE!" },
  { "SHAKE", "THEM", "DICE", "BRA!" },
  { "TAP", "AND", "THROW", "DOWN" },
  { "DANCE", "WITH", "THE", "DEVIL!" },
  { "HUNT", "DOWN", "SOME", "WORDS!" },
  { "SHOW", "THEM", "THEY", "STINK" },
}
quickStartPhraseIdx = quickStartPhraseIdx or 0

local function _advanceQuickStartPhrase()
  quickStartPhraseIdx = quickStartPhraseIdx % #QUICK_START_PHRASES + 1
end

local function _pickQuickStartPosition()
  local qs  = quickStart
  local r   = qs.radius
  local pad = 20

  local safeTop = getTopSafeY()
  local safeBot = getBottomSafeY()

  local minX = r + pad
  local maxX = WIDTH  - r - pad
  local minY = safeBot + r + pad
  local maxY = safeTop - r - 80

  local lastX, lastY = qs.x, qs.y
  local minHopDist = r * 2 + 10

  for _ = 1, 40 do
    local x = math.random(minX, maxX)
    local y = math.random(minY, maxY)
    if not _quickStartInsideAvoidRect(x, y) then
      if lastX == 0 and lastY == 0 then
        qs.x, qs.y = x, y
        break
      else
        local dx, dy = x - lastX, y - lastY
        if dx*dx + dy*dy >= minHopDist * minHopDist then
          qs.x, qs.y = x, y
          break
        end
      end
    end
  end

  local range = qs.rotationDegRange or 0
  if range > 0 then
    local dir = qs.rotationDir or 1
    local mag = (math.random(1000) / 1000) * range
    local minMag = range * 0.35
    if mag < minMag then mag = minMag end
    qs.rotation    = dir * mag
    qs.rotationDir = -dir
  else
    qs.rotation    = 0
    qs.rotationDir = 1
  end
end

local function _activateQuickStart()
  quickStart.active    = true
  quickStart.phase     = "visible"
  quickStart.phaseTime = 0
  quickStart.rippled   = false
  _advanceQuickStartPhrase()
  _pickQuickStartPosition()
end

local function _deactivateQuickStart()
  quickStart.active    = false
  quickStart.phase     = "hidden"
  quickStart.phaseTime = 0
end

-- The single best match to jump into: the newest entry that still needs the
-- local player's attention (mirrors vsListEntries' own newest-first sort).
function vsQuickStartBestEntry()
  for _, e in ipairs(vsListEntries or {}) do
    if e.playable then return e end
  end
  return nil
end

function updateQuickStart(dt)
  if state ~= STATE_MENU then
    quickStartWasMenuLastFrame = false
    _deactivateQuickStart()
    return
  end

  if not quickStartWasMenuLastFrame then
    quickStartWasMenuLastFrame = true
    if refreshVsMatchesList then refreshVsMatchesList("menuEntry") end
  end

  local now = ElapsedTime or 0
  if (now - (quickStartLastPollAt or 0)) >= (quickStartPollInterval or 8.0) then
    quickStartLastPollAt = now
    if refreshVsMatchesList then refreshVsMatchesList("menuPeriodic") end
  end

  if not vsHasPlayable then
    _deactivateQuickStart()
    return
  end

  if not quickStart.active then
    _activateQuickStart()
  end

  quickStart.phaseTime = quickStart.phaseTime + dt

  if quickStart.phase == "visible" then
    if quickStart.phaseTime >= quickStart.visibleDuration then
      quickStart.phase     = "hidden"
      quickStart.phaseTime = 0
    end
  else
    if quickStart.phaseTime >= quickStart.hiddenDuration then
      quickStart.phase     = "visible"
      quickStart.phaseTime = 0
      quickStart.rippled   = false
      _advanceQuickStartPhrase()
      _pickQuickStartPosition()
    end
  end

  -- Water ripple spreading from the badge rim (settings: rippleTune, RippleShader.lua)
  if quickStart.phase == "visible" and not quickStart.rippled and not badgeSuppressed()
     and quickStart.phaseTime >= rippleTune.delay then
    quickStart.rippled = true
    startScreenRipple(quickStart.x, quickStart.y, rippleTune.rim)
  end
end

-- Draws the quick-start disc at (x, y) for badge-age t seconds (pop-in, hold, shrink-out).
function drawQuickStartBadgeAt(x, y, t, visibleDur)
  local qs         = quickStart
  local r          = qs.radius
  local appear     = qs.appearDuration or 0.25
  local disappear  = qs.disappearDuration or 0.25

  local maxScale = qs.maxScale or 1.25
  local scale    = 1.0
  local alpha    = 255

  if t < appear then
    local a = math.min(t / appear, 1.0)
    scale = maxScale - (maxScale - 1.0) * a
  elseif t > visibleDur - disappear then
    local d = math.min((t - (visibleDur - disappear)) / disappear, 1.0)
    scale = 1.0 - d
    if scale < 0.0 then scale = 0.0 end
    alpha = 255 * (1.0 - d)
  else
    scale = 1.0
  end

  pushStyle()
  pushMatrix()
  translate(x, y)
  -- text stays level (the disc is round, so rotating only ever tilted the words)

  noStroke()
  fill(230, 40, 40, alpha)
  ellipse(0, 0, r * 2 * scale, r * 2 * scale)

  fill(255, 255, 255, alpha)
  textMode(CENTER)
  textAlign(CENTER)
  fontSize(14 * scale)
  font("Baskerville-SemiBold")
  -- One text() per line so each word is centered on its own (textAlign is unreliable
  -- inside a textMode(CENTER) multi-line block).
  local lines = QUICK_START_PHRASES[math.max(quickStartPhraseIdx, 1)]
  local lineH = 14 * scale * 1.05
  for i, line in ipairs(lines) do
    text(line, 0, (#lines + 1) * 0.5 * lineH - i * lineH)
  end

  popMatrix()
  popStyle()
end

function drawQuickStart()
  if state ~= STATE_MENU then return end
  if badgeSuppressed() then return end
  if not quickStart.active then return end
  if quickStart.phase ~= "visible" then return end

  local qs = quickStart
  local x, y = qs.x, qs.y
  local r    = qs.radius

  if qs.showDebugRect == true then
    pushStyle()
    rectMode(CENTER)
    noFill()
    stroke(255, 255, 0, 150)
    strokeWidth(8)
    rect(qs.avoidOrigin.x, qs.avoidOrigin.y, qs.avoidW, qs.avoidH)
    popStyle()
  end

  local t          = qs.phaseTime or 0
  local visibleDur = qs.visibleDuration or ((qs.appearDuration or 0.25) + (qs.disappearDuration or 0.25) + 0.2)
  drawQuickStartBadgeAt(x, y, t, visibleDur)
end

function handleQuickStartTouch(t)
  if state ~= STATE_MENU then return false end
  if not quickStart.active then return false end
  if quickStart.phase ~= "visible" then return false end
  if badgeSuppressed() then return false end
  if t.state ~= BEGAN then return false end

  local dx = t.x - quickStart.x
  local dy = t.y - quickStart.y
  local r  = quickStart.radius

  if dx*dx + dy*dy <= r*r then
    local entry = vsQuickStartBestEntry()
    if entry and vsOpenMatchEntry then
      vsOpenMatchEntry(entry)
      return true
    end
  end

  return false
end

------------------------------------------------------------
-- Legacy pending-matches store: no longer drives any visible UI (superseded
-- by MatchSelection.lua's vsListEntries, sourced live from Game Center).
-- Kept only so the "Debug: Simulate Incoming Turn" parameter action
-- (qMatch_qPlayer.lua) still has somewhere to write; wired to nudge the real
-- vs list/badge so that debug hook stays meaningful.
------------------------------------------------------------

function storePendingTurnMatch(q)
  if not q or not q.id then return end
  local sid = tostring(q.id)
  for i = 1, #pendingTurnMatches do
    local item = pendingTurnMatches[i]
    if item and tostring(item.id or "") == sid then
      pendingTurnMatches[i] = q
      if refreshVsMatchesList then refreshVsMatchesList("debugSimulate") end
      return
    end
  end
  pendingTurnMatches[#pendingTurnMatches + 1] = q
  if refreshVsMatchesList then refreshVsMatchesList("debugSimulate") end
end

function removePendingMatchById(id)
  if not id or not pendingTurnMatches then return end
  local sid = tostring(id)
  for i = #pendingTurnMatches, 1, -1 do
    local item = pendingTurnMatches[i]
    if item and tostring(item.id or "") == sid then
      table.remove(pendingTurnMatches, i)
      break
    end
  end
end

function clearPendingMatches()
  pendingTurnMatches = {}
end
