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
     or vsOverlay
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

  pushStyle()
  noStroke()
  ellipseMode(CENTER)
  fill(230, 40, 40, 255)
  ellipse(x, y, r * 2)
  popStyle()
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
