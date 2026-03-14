

function enterMatchFromCTBM(gkMatch, dataTable)
  -- 1. Build qMatch immediately (UI-first)
  local q = makeQMatchFromGK(gkMatch, dataTable)
  if not q then return end
  
  currentQMatch = ensureQMatchPlayers(
  q,
  localPID(),
  q.otherId or q.opponentId
  )
  
  -- 2. Turn-based mode ON
  setTurnBasedEnabled(true)
  
  -- 3. Identity
  currentMatchID    = q.id
  currentOpponentID = q.otherId or q.opponentId
  opponentAlias     = q.otherName or q.opponentName or opponentAlias
  
  -- 4. Apply rules if needed
  if applyMatchRules then
    applyMatchRules(q)
  end
  
  -- 5. Start the round immediately (no waiting on GK)
  if startRoundFromCurrentSettings then
    startRoundFromCurrentSettings()
  elseif gameOnTurnAvailable then
    gameOnTurnAvailable(q, false)
  end
  
  -- 6. Remove from pending list
  if removePendingMatchById and q.id then
    removePendingMatchById(q.id)
  end
end
