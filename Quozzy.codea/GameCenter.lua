GameCenter = GameCenter or {}
GameCenter.testMode = GameCenter.testMode or false
MAX_MATCH_COMMENT_LEN = MAX_MATCH_COMMENT_LEN or 100
FINAL_COMMENT_TURN_MESSAGE = FINAL_COMMENT_TURN_MESSAGE or "Check out the results of your game!"

local function sanitizeMatchComment(text)
  local s = tostring(text or "")
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("%s+", " ")
  s = s:match("^%s*(.-)%s*$") or ""
  if #s > MAX_MATCH_COMMENT_LEN then
    s = s:sub(1, MAX_MATCH_COMMENT_LEN)
  end
  return s
end

local function buildFinalTurnDataAndOutcome(commentText)
  local q = currentQMatch
  local pid = localPID()
  if not (useTurnBased and q and q.players and q.players[pid]) then return nil, nil, nil end
  if not (tbm and tbm.currentMatch and tbm._getEndStateFromMatch) then return nil, nil, nil end
  if tbm:_getEndStateFromMatch(tbm.currentMatch) then return nil, nil, nil end

  local oppId, oppData = nil, nil
  for id, pdata in pairs(q.players) do
    if id ~= pid and pdata then
      oppId = id
      oppData = pdata
      break
    end
  end
  if not (oppId and oppData and oppData.didPlay and q.players[pid].didPlay) then return nil, nil, nil end

  q.players[pid].words = q.players[pid].words or {}
  q.players[pid].wordTimes = q.players[pid].wordTimes or {}
  q.players[pid].comment = q.players[pid].comment or ""
  oppData.comment = oppData.comment or ""

  local newComment = sanitizeMatchComment(commentText)
  if newComment ~= "" and q.players[pid].comment == "" then
    q.players[pid].comment = newComment
    q.players[pid].commentSentAt = os.time()
  end

  if reconcileCompetitiveWordResults then
    local reconciled = reconcileCompetitiveWordResults(
      q.players[pid].words or {},
      oppData.words or {}
    )
    q.players[pid].words = reconciled.entriesA
    q.players[pid].score = reconciled.scoreA
    oppData.words = reconciled.entriesB
    oppData.score = reconciled.scoreB
    score = reconciled.scoreA
    opponentScore = reconciled.scoreB
  end

  local myScore = q.players[pid].score or 0
  local oppScore = oppData.score or 0
  local outcome = "tie"
  if myScore > oppScore then
    outcome = "win"
  elseif myScore < oppScore then
    outcome = "loss"
  end

  q.lastUpdated = os.time()
  q.awaitingCommentBeforeFinalization = (q.players[pid].comment == "")

  local turnData = {
    boardSize   = q.boardSize or boardSize,
    minWordLen  = q.minWordLen or MIN_WORD_LEN,
    boardTiles  = q.boardTiles,
    players     = q.players,
    lastUpdated = q.lastUpdated,
    commentPhase = q.commentPhase,
  }

  if oppId and buildRecordSyncForOpponent then
    local alias = q.otherName or q.opponentName or opponentAlias
    local sync = buildRecordSyncForOpponent(oppId, alias, pid, outcome)
    if sync then turnData.recordSync = sync end
  end

  return turnData, outcome, oppId
end

local function getLocalAndOpponentPlayers(q)
  local pid = localPID()
  local me = q and q.players and q.players[pid] or nil
  local oppId, oppData = nil, nil
  if q and q.players then
    for id, pdata in pairs(q.players) do
      if id ~= pid and pdata then
        oppId = id
        oppData = pdata
        break
      end
    end
  end
  return pid, me, oppId, oppData
end

local function ensureCommentPhaseForCompletedGameplay(q, initiatorId, responderId)
  if not q then return nil end
  q.commentPhase = q.commentPhase or {}
  q.commentPhase.initiatorId = q.commentPhase.initiatorId or initiatorId
  q.commentPhase.responderId = q.commentPhase.responderId or responderId
  q.commentPhase.stage = q.commentPhase.stage or "initiatorTurn"
  q.commentPhase.startedAt = q.commentPhase.startedAt or os.time()
  q.commentPhase.lastUpdated = os.time()
  return q.commentPhase
end

function currentFinalCommentPhase()
  local q = currentQMatch
  if not (useTurnBased and q and q.players and tbm and tbm.currentMatch) then return nil end
  local pid, me, oppId, oppData = getLocalAndOpponentPlayers(q)
  if not (pid and me and oppId and oppData and me.didPlay and oppData.didPlay) then return nil end
  
  local phase = ensureCommentPhaseForCompletedGameplay(q, q.commentPhase and q.commentPhase.initiatorId or pid, oppId)
  if not phase then return nil end
  
  local isInitiatorTurn = phase.stage == "initiatorTurn"
  local isResponderTurn = phase.stage == "responderTurn"
  local localCanCompose =
    (tbm.isMyTurn == true) and (
      (isInitiatorTurn and phase.initiatorId == pid) or
      (isResponderTurn and phase.responderId == pid)
    )
  
  return {
    phase = phase,
    localId = pid,
    localPlayer = me,
    opponentId = oppId,
    opponentPlayer = oppData,
    isInitiatorTurn = isInitiatorTurn,
    isResponderTurn = isResponderTurn,
    localCanCompose = localCanCompose,
  }
end

function shouldShowFinalCommentComposer()
  local info = currentFinalCommentPhase()
  return info and info.localCanCompose or false
end

function submitFinalCommentFromEndScreen(commentText)
  local info = currentFinalCommentPhase()
  if not info then
    return finalizeCompletedTurnBasedMatch and finalizeCompletedTurnBasedMatch(commentText) or false
  end
  
  local q = currentQMatch
  local pid = info.localId
  local me = info.localPlayer
  local oppId = info.opponentId
  local newComment = sanitizeMatchComment(commentText)
  
  me.comment = me.comment or ""
  if newComment ~= "" and me.comment == "" then
    me.comment = newComment
    me.commentSentAt = os.time()
  end
  
  q.lastUpdated = os.time()
  if info.isInitiatorTurn then
    info.phase.stage = "responderTurn"
    info.phase.lastSenderId = pid
    info.phase.lastUpdated = q.lastUpdated
    q.awaitingCommentBeforeFinalization = false
    local turnData = {
      boardSize   = q.boardSize or boardSize,
      minWordLen  = q.minWordLen or MIN_WORD_LEN,
      boardTiles  = q.boardTiles,
      players     = q.players,
      lastUpdated = q.lastUpdated,
      commentPhase = q.commentPhase,
      __gcMessage = FINAL_COMMENT_TURN_MESSAGE,
    }
    if oppId and buildRecordSyncForOpponent then
      local alias = q.otherName or q.opponentName or opponentAlias
      local sync = buildRecordSyncForOpponent(oppId, alias, pid, nil)
      if sync then turnData.recordSync = sync end
    end
    tbm:endTurnWithDataTable(turnData)
    return true
  end
  
  info.phase.stage = "complete"
  info.phase.lastSenderId = pid
  info.phase.lastUpdated = q.lastUpdated
  return finalizeCompletedTurnBasedMatch(commentText)
end

function finalizeCompletedTurnBasedMatch(commentText)
  local turnData, outcome = buildFinalTurnDataAndOutcome(commentText)
  if not (turnData and outcome) then return false end

  if outcome == "win" then
    tbm:localPlayerWon(turnData)
  elseif outcome == "loss" then
    tbm:localPlayerLost(turnData)
  else
    tbm:localPlayerTied(turnData)
  end

  updateOpponentRecord(outcome)
  currentQMatch.recordOutcomeApplied = true
  currentQMatch.recordOutcome = outcome
  currentQMatch.awaitingCommentBeforeFinalization = false
  if persistLastMatchReplaySettingsFromQMatch then
    persistLastMatchReplaySettingsFromQMatch(currentQMatch)
  end
  return true
end

local function applyResolvedWordsToEndScreen(q, pid)
  local meP = q and q.players and q.players[pid] or nil
  if not meP then return nil, nil end
  
  score = tonumber(meP.score) or 0
  meP.words = meP.words or {}
  meP.wordTimes = meP.wordTimes or {}
  foundWords = meP.words
  foundWordsSet = {}
  for _, w in ipairs(foundWords) do
    if type(w) == "string" then foundWordsSet[w] = true end
  end
  
  local otherId, otherP = nil, nil
  for id, pdata in pairs(q.players or {}) do
    if id ~= pid then
      otherId = id
      otherP = pdata
      break
    end
  end
  opponentScore = tonumber(otherP and otherP.score) or 0
  return otherId, otherP
end

local function enterEndScreenForOpenCompletedGameplay(q, reasonTag)
  local myId = localPID()
  local meP = q and q.players and q.players[myId] or nil
  if not (meP and meP.didPlay == true) then return false end
  
  local otherId, otherP = applyResolvedWordsToEndScreen(q, myId)
  currentQMatch.awaitingCommentBeforeFinalization =
    (tbm and tbm.isMyTurn == true and (meP.comment or "") == "")
  
  devLog(reasonTag,
    "myDidPlay=", meP and meP.didPlay,
    "otherDidPlay=", otherP and otherP.didPlay,
    "otherId=", otherId,
    "isMyTurn=", tbm and tbm.isMyTurn)
  state = STATE_END
  return true
end

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
  currentQMatch.awaitingCommentBeforeFinalization = false

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
      applyResolvedWordsToEndScreen(currentQMatch, localPID())
      state = STATE_END
      return
    end
  end
  
  do
    local myId = localPID()
    local meP = q.players and q.players[myId] or nil
    local otherP = nil
    if q.players then
      for pid, pdata in pairs(q.players) do
        if pid ~= myId then
          otherP = pdata
          break
        end
      end
    end
    if meP and meP.didPlay == true and otherP and otherP.didPlay == true then
      if enterEndScreenForOpenCompletedGameplay(
        q,
        "enterQMatch: open match has completed gameplay; showing comment/results screen"
      ) then
        return
      end
    end
  end

  -- If this is an open match but not our turn, show the end/waiting screen
  -- with our submitted words/score instead of starting a fresh round.
  if tbm and tbm.currentMatch and tbm.isMyTurn == false then
    local myId = localPID()
    local meP = q.players and q.players[myId] or nil
    local otherId, otherP = applyResolvedWordsToEndScreen(q, myId)
    
    if meP and meP.didPlay == true then
      currentQMatch.awaitingCommentBeforeFinalization = ((meP.comment or "") == "")
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
  q.players[pid].comment   = q.players[pid].comment or ""
  
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
    local turnData = {
      boardSize   = q.boardSize or boardSize,
      minWordLen  = q.minWordLen or MIN_WORD_LEN,
      boardTiles  = q.boardTiles,
      players     = q.players,
      lastUpdated = os.time(),
      commentPhase = q.commentPhase,
    }
    if oppId and buildRecordSyncForOpponent then
      local alias = q.otherName or q.opponentName or opponentAlias
      local sync = buildRecordSyncForOpponent(oppId, alias, pid, nil)
      if sync then turnData.recordSync = sync end
    end
    print("QUOZZY → GC SEND turnData:")
    print(json.encode(turnData))
    tbm:endTurnWithDataTable(turnData)
    return
  end
  
  ------------------------------------------------------------
  -- BOTH PLAYED → stay on end screen until dismiss or comment send
  ------------------------------------------------------------
  local _, pendingOutcome = buildFinalTurnDataAndOutcome(nil)
  if pendingOutcome then
    ensureCommentPhaseForCompletedGameplay(q, pid, oppId)
    q.pendingFinalOutcome = pendingOutcome
    q.awaitingCommentBeforeFinalization = true
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
