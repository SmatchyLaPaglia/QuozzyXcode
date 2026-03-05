GameCenter = GameCenter or {}
GameCenter.testMode = GameCenter.testMode or false

function enterQMatch(q)
  if not q or not q.id then
    print("enterQMatch: nil q or id")
    return
  end
  if endReplayMatchmakingBusy then
    endReplayMatchmakingBusy()
  end
  
  currentQMatch = ensureQMatchPlayers(q, localPID(), q.otherId or q.opponentId)
  dbgDidPlay("enterQMatch", currentQMatch)
  
  useTurnBased      = true
  currentMatchID    = q.id
  currentOpponentID = q.otherId or q.opponentId or nil
  opponentAlias     = q.otherName or q.opponentName or ""

  -- Apply match-specific rules from Game Center payload (e.g. 5x5 boards).
  if q.boardSize and tonumber(q.boardSize) then
    boardSize = math.floor(tonumber(q.boardSize))
  end
  if q.minWordLen and tonumber(q.minWordLen) then
    MIN_WORD_LEN = math.floor(tonumber(q.minWordLen))
  end
  if persistLastMatchReplaySettingsFromQMatch then
    persistLastMatchReplaySettingsFromQMatch(currentQMatch)
  end
  
  defineAvatarsAfterMicrodelay()

  -- Gate round start when user selected an already-ended Game Center match.
  if tbm and tbm.currentMatch and tbm._getEndStateFromMatch then
    local endState = tbm:_getEndStateFromMatch(tbm.currentMatch)
    if endState then
      devLog("enterQMatch: selected match already ended; staying on end screen", "endState=", endState)
      state = STATE_END
      return
    end
  end

  -- If this is an open match but not our turn, show the end/waiting screen
  -- with our submitted words/score instead of starting a fresh round.
  if tbm and tbm.currentMatch and tbm.isMyTurn == false then
    local myId = localPID()
    local meP = q.players and q.players[myId] or nil
    local otherId, otherP = nil, nil
    if q.players then
      for pid, pdata in pairs(q.players) do
        if pid ~= myId then
          otherId, otherP = pid, pdata
          break
        end
      end
    end
    
    if meP then
      score = tonumber(meP.score) or 0
      q.players[myId].words = q.players[myId].words or {}
      q.players[myId].wordTimes = q.players[myId].wordTimes or {}
      foundWords = q.players[myId].words
      foundWordsSet = {}
      for _, w in ipairs(foundWords) do
        if type(w) == "string" then foundWordsSet[w] = true end
      end
    end
    
    if meP and meP.didPlay == true then
      opponentScore = tonumber(otherP and otherP.score) or 0
      devLog("enterQMatch: selected open match not on my turn after I played; showing end/waiting screen",
        "myDidPlay=", meP and meP.didPlay,
        "otherDidPlay=", otherP and otherP.didPlay,
        "otherId=", otherId)
      state = STATE_END
      return
    end

    devLog("enterQMatch: selected open match not on my turn and I have not played; not forcing end screen",
      "myDidPlay=", meP and meP.didPlay,
      "otherDidPlay=", otherP and otherP.didPlay,
      "otherId=", otherId)
  end

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

  if oppId and buildRecordSyncForOpponent then
    local alias = q.otherName or q.opponentName or opponentAlias
    local sync = buildRecordSyncForOpponent(oppId, alias, pid)
    if sync then
      turnData.recordSync = sync
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
  q.recordOutcomeApplied = true
  q.recordOutcome = outcome
  if persistLastMatchReplaySettingsFromQMatch then
    persistLastMatchReplaySettingsFromQMatch(q)
  end
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
