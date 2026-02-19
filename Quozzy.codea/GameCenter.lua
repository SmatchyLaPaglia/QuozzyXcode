GameCenter = GameCenter or {}
GameCenter.testMode = GameCenter.testMode or false

function enterQMatch(q)
  if not q or not q.id then
    print("enterQMatch: nil q or id")
    return
  end
  
  currentQMatch = ensureQMatchPlayers(q, localPID(), q.otherId or q.opponentId)
  dbgDidPlay("enterQMatch", currentQMatch)
  
  useTurnBased      = true
  currentMatchID    = q.id
  currentOpponentID = q.otherId or q.opponentId or currentOpponentID
  opponentAlias     = q.otherName or q.opponentName or opponentAlias
  
  defineAvatarsAfterMicrodelay()
  startRoundFromCurrentSettings()
end

function endGameRound()
  print("DEBUG:endGameRound: currentFoundWords():", json.encode(currentFoundWords()))
  
  state = STATE_END
  rotatePlayAgainLabel()
  
  local q   = currentQMatch
  local pid = localPID()
  
  ------------------------------------------------------------
  -- SINGLE PLAYER
  ------------------------------------------------------------
  if not useTurnBased then
    opponentScore = 0
    
    if q and q.players then
      q.players[pid] = q.players[pid] or {}
      
      q.players[pid].score     = score or 0
      q.players[pid].words     = currentFoundWords() or {}
      q.players[pid].wordTimes = q.players[pid].wordTimes or {}
      q.players[pid].didPlay   = true
      q.lastUpdated            = os.time()
    end
    
    return
  end
  
  ------------------------------------------------------------
  -- TURN-BASED MULTIPLAYER
  ------------------------------------------------------------
  
  if not q then return end
  
  q.players = q.players or {}
  q.players[pid] = q.players[pid] or {}
  
  -- Update ONLY your entry (single source of truth)
  q.players[pid].score     = score or 0
  q.players[pid].words     = currentFoundWords() or {}
  q.players[pid].wordTimes = q.players[pid].wordTimes or {}
  q.players[pid].didPlay   = true
  
  ------------------------------------------------------------
  -- Build outgoing payload (FULL state)
  ------------------------------------------------------------
  
  local turnData = {
    boardSize   = q.boardSize or boardSize,
    minWordLen  = q.minWordLen or MIN_WORD_LEN,
    boardTiles  = q.boardTiles,
    players     = q.players,      -- send ENTIRE table
    lastUpdated = os.time(),
  }
  
  ------------------------------------------------------------
  -- DEBUG
  ------------------------------------------------------------
  
  print("QUOZZY → GC SEND turnData:")
  print(json.encode(turnData))
  
  ------------------------------------------------------------
  -- Did opponent already play?
  ------------------------------------------------------------
  
  local opponentPlayed = false
  local oppId, oppData = nil, nil
  
  for id, pdata in pairs(q.players) do
    if id ~= pid and pdata then
      oppId   = id
      oppData = pdata
      if pdata.didPlay then
        opponentPlayed = true
      end
      break
    end
  end
  
  ------------------------------------------------------------
  -- If opponent hasn't played → pass turn
  ------------------------------------------------------------
  
  if not opponentPlayed then
    tbm:endTurnWithDataTable(turnData)
    return
  end
  
  ------------------------------------------------------------
  -- BOTH PLAYED → determine outcome and end match
  ------------------------------------------------------------
  
  local myScore  = q.players[pid].score or 0
  local oppScore = (oppData and oppData.score) or 0
  
  local outcome
  if myScore > oppScore then
    outcome = "win"
    tbm:localPlayerWon(turnData)
    
  elseif myScore < oppScore then
    outcome = "loss"
    tbm:localPlayerLost(turnData)
    
  else
    outcome = "tie"
    tbm:localPlayerTied(turnData)
  end
  
  updateOpponentRecord(outcome)
end

useTurnBased     = false   -- NEW: master toggle for opponent / records

currentMatchID    = nil
currentOpponentID = nil    -- no opponent when toggle is OFF
opponentAlias     = "Opponent"
opponentScore     = 0

-- Pending matches that are waiting on *you* to play
pendingTurnMatches          = pendingTurnMatches or {}
pendingTurnMatchesIndexById = pendingTurnMatchesIndexById or {}
PENDING_MATCHES_KEY         = "PendingTurnMatches"

qPlayersById   = qPlayersById   or {}
qPlayersList   = qPlayersList   or {}

-- Optional flag the rest of the UI can look at
hasPendingMatches           = hasPendingMatches or false