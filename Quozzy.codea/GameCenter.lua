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

_dbgCommentPhaseSig = _dbgCommentPhaseSig or ""
function currentFinalCommentPhase()
  local q = currentQMatch
  -- Deliberately NOT requiring tbm.currentMatch here (the old guard did): the
  -- real CTBM clears tbm.currentMatch the instant a turn-end succeeds (see
  -- CodeaTurnBasedMatches.lua:854-855), which happens to the match CREATOR
  -- right after their own initial handshake — before they've even played.
  -- Requiring it meant the creator could never see the composer at all,
  -- regardless of anything else. Composability is a property of local match
  -- state (did I play, have I decided), not of holding a live GK turn
  -- reference — attemptLegSend already handles queuing a decision made
  -- without the turn.
  if not (useTurnBased and q and q.players) then
    local sig = "nil:ut="..tostring(useTurnBased).." q="..tostring(q~=nil)
    if _dbgCommentPhaseSig ~= sig then _dbgCommentPhaseSig = sig; devLog("COMMENT_DBG currentFinalCommentPhase -> nil: guard1 failed", sig) end
    return nil
  end
  local pid, me, oppId, oppData = getLocalAndOpponentPlayers(q)
  if not (pid and me and me.didPlay) then
    local sig = "nil:pid="..tostring(pid~=nil).." me="..tostring(me~=nil).." oppId="..tostring(oppId).." oppData="..tostring(oppData~=nil).." didPlay="..tostring(me and me.didPlay)
    if _dbgCommentPhaseSig ~= sig then _dbgCommentPhaseSig = sig; devLog("COMMENT_DBG currentFinalCommentPhase -> nil: guard2 failed", sig) end
    return nil
  end
  local sig = "ok:oppId="..tostring(oppId).." isMyTurn="..tostring(tbm and tbm.isMyTurn).." oppDidPlay="..tostring(oppData and oppData.didPlay)
  if _dbgCommentPhaseSig ~= sig then _dbgCommentPhaseSig = sig; devLog("COMMENT_DBG currentFinalCommentPhase -> non-nil", sig) end

  return {
    localId         = pid,
    localPlayer     = me,
    opponentId      = oppId,
    opponentPlayer  = oppData,
    opponentPlayed  = (oppData ~= nil and oppData.didPlay == true),
    -- I can compose once I've played and haven't already locked in a
    -- decision — independent of whose GameKit turn it currently is.
    -- `recordOutcomeApplied` excludes both an already-finalized live match
    -- and a reconstructed historical view (RecordsUI.lua sets it
    -- explicitly for the latter; it never carries commentDecided at all,
    -- so that alone wouldn't have excluded it).
    localCanCompose = (me.commentDecided ~= true) and (q.recordOutcomeApplied ~= true),
  }
end

function shouldShowFinalCommentComposer()
  local info = currentFinalCommentPhase()
  return info and info.localCanCompose or false
end

-- The UI's entry point for "the player closed their comment box" (blank or
-- not — see MULTIPLAYER_TEST_PLAN.md, treated as the same decision either
-- way). Records the decision locally, then leaves WHAT to send (a plain
-- relay vs. a finalize) to computeNextOwedLeg/attemptLegSend rather than
-- branching on opponentPlayed here directly — that branch now lives in one
-- place instead of being duplicated between this function and endGameRound.
-- Note: this previously called tbm:endTurnWithDataTable directly with no
-- retry/backoff at all; routing through attemptLegSend gives this leg the
-- same resilience the initial handshake already had.
function decideComment(commentText)
  local q = currentQMatch
  local pid = localPID()
  if not (useTurnBased and q and q.players and q.players[pid] and q.players[pid].didPlay) then
    return false
  end
  local me = q.players[pid]
  local newComment = sanitizeMatchComment(commentText)
  me.comment = newComment
  me.commentDecided = true
  if newComment ~= "" then
    me.commentSentAt = os.time()
  end
  -- Keep the disk snapshot current with the decision (finishedAwaitingDecisionByMatchId[q.id]
  -- is the same table as q when this match was the one that finished locally,
  -- but the on-disk copy still needs an explicit flush).
  if finishedAwaitingDecisionByMatchId[q.id] then
    persistFinishedAwaitingDecision()
  end
  attemptLegSend(q)
  return true
end

function submitFinalCommentFromEndScreen(commentText)
  return decideComment(commentText)
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

-- Renamed from the old top-level enterQMatch: the real work, unchanged
-- internally (every existing early return is preserved as-is). Wrapped below
-- by the actual public enterQMatch so that EVERY exit path — not just the
-- final fallthrough — gets a chance to check "is there something I can now
-- send?" (e.g. a merge just brought in the opponent's resolution, making a
-- previously-queued local decision sendable per computeNextOwedLeg).
local function enterQMatch_inner(q)
  if not q or not q.id then
    print("enterQMatch: nil q or id")
    return
  end

  -- Two situations where an incoming turn-event must never be allowed to
  -- clobber local state — in both, we take ONLY the opponent's slot from the
  -- incoming payload and keep our own, since nobody but us can correctly
  -- report our own result:
  --   (a) I'm actively playing locally (STATE_READY/STATE_PLAY) and haven't
  --       submitted yet — under simultaneous play this is routine (the
  --       opponent's turn can pass back to me mid-round); without this guard
  --       startRoundFromCurrentSettings() below would wipe my live progress.
  --   (b) I've already finished my round (STATE_END, didPlay==true) but
  --       haven't been able to send it yet (e.g. I don't hold the turn) — the
  --       incoming payload is necessarily stale about my own slot in that
  --       case, and letting it through here would silently discard my
  --       already-completed result.
  do
    local myId = localPID()
    local localAlreadyPlayed = currentQMatch and currentQMatch.players
      and currentQMatch.players[myId] and currentQMatch.players[myId].didPlay

    local protectInProgressRound = currentQMatch and currentQMatch.id == q.id
      and (state == STATE_READY or state == STATE_PLAY)
      and not localAlreadyPlayed

    local protectFinishedUnsentResult = currentQMatch and currentQMatch.id == q.id
      and state == STATE_END
      and localAlreadyPlayed == true

    if protectInProgressRound or protectFinishedUnsentResult then
      for pid, pdata in pairs(q.players or {}) do
        if pid ~= myId then
          currentQMatch.players[pid] = pdata
        end
      end
      currentQMatch.lastUpdated = q.lastUpdated or currentQMatch.lastUpdated
      devLog("enterQMatch: merged incoming opponent data without disturbing local state",
        "reason=", protectInProgressRound and "in-progress-round" or "finished-unsent-result")
      return
    end
  end

  if endReplayMatchmakingBusy then
    endReplayMatchmakingBusy()
  end

  -- Detect "this is my very first turn-event for a brand-new match I just created":
  -- I own the turn, and the incoming payload has no valid board tiles yet (the only
  -- way boardTiles ever gets set is from decoded GK match data — see makeQMatchFromGK
  -- in qMatch_qPlayer.lua — so no valid tiles means nothing has ever been sent for
  -- this match). Belt-and-suspenders: nobody has played yet either.
  local needsInitialHandshake = (tbm and tbm.isMyTurn == true)
    and not areBoardTilesValidForSize(q.boardTiles, q.boardSize or boardSize)
  if needsInitialHandshake and q.players then
    for _, pdata in pairs(q.players) do
      if pdata and pdata.didPlay == true then needsInitialHandshake = false; break end
    end
  end

  currentQMatch = ensureQMatchPlayers(q, localPID(), q.otherId or q.opponentId)
  -- Stored on the object (not just the local var above) because
  -- computeNextOwedLeg (qMatch_qPlayer.lua) needs to read this signal AFTER
  -- startRoundFromCurrentSettings() below has locally generated real board
  -- tiles — at which point re-deriving "were tiles ever sent" from tile
  -- validity alone would always read true and the signal would be lost.
  currentQMatch.needsInitialHandshake = needsInitialHandshake

  -- If I already have a locally-decided result queued to send for this exact
  -- match (pendingTurnSendsByMatchId), it takes precedence over whatever
  -- this freshly-arrived incoming payload says about MY OWN slot — that
  -- payload was necessarily built before my decision existed, since nobody
  -- but me can correctly report my own result. The merge-guard above already
  -- protects this for STATE_READY/STATE_PLAY/STATE_END; this covers every
  -- other state (e.g. I've already navigated back to STATE_MENU while still
  -- waiting for a chance to send).
  do
    local pending = pendingTurnSendsByMatchId[q.id]
    local myId = localPID()
    if pending and pending.turnData and pending.turnData.players
       and pending.turnData.players[myId] then
      currentQMatch.players[myId] = pending.turnData.players[myId]
    end
  end

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
  -- Only persist replay settings when the GK match is already ended (e.g.
  -- auto-opening a finished match). A freshly-created open match must not
  -- overwrite the completed match ID that Play Again depends on.
  if persistLastMatchReplaySettingsFromQMatch then
    local _gcMatchEnded = false
    if tbm and tbm.currentMatch and tbm._getEndStateFromMatch then
      local _ok, _es = pcall(function()
        return tbm:_getEndStateFromMatch(tbm.currentMatch)
      end)
      _gcMatchEnded = _ok and _es ~= nil
    end
    if _gcMatchEnded then
      persistLastMatchReplaySettingsFromQMatch(currentQMatch)
    end
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

  startRoundFromCurrentSettings()   -- generates+stores boardTiles, sets STATE_READY
end

function enterQMatch(q)
  local matchId = q and q.id
  enterQMatch_inner(q)
  -- Runs after EVERY exit path above, not just the fallthrough — a merge
  -- guard branch or an end-screen branch may have just made something
  -- newly sendable (e.g. the opponent's resolution arriving completes what
  -- I already decided and queued earlier).
  if matchId and currentQMatch and currentQMatch.id == matchId then
    attemptLegSend(currentQMatch)
  end
end

HANDSHAKE_MAX_ATTEMPTS = 3
HANDSHAKE_RETRY_DELAYS = {1.0, 2.5, 5.0}

-- Kept for backward compatibility with existing call sites/tests that invoke
-- the handshake directly; routes through the same generalized path as every
-- other leg.
function beginInitialHandshakeSend(q)
  q.needsInitialHandshake = true
  attemptLegSend(q)
end

-- The single entry point for "do I owe this match anything right now, and if
-- so, try to send it." Safe to call speculatively and often (e.g. after
-- every enterQMatch, or once a comment gets decided) — it's a no-op whenever
-- computeNextOwedLeg has nothing to say, and it dedupes: an already-pending
-- attempt for the same leg is retried in place rather than restarted.
function attemptLegSend(q)
  if not (useTurnBased and q and q.id and tbm) then return end
  local myId = localPID()
  local leg = computeNextOwedLeg(q, myId, os.time())
  if not leg then return end

  local pending = pendingTurnSendsByMatchId[q.id]
  if not pending or pending.leg ~= leg then
    -- Freeze the payload now rather than recomputing it on every retry, so
    -- a retry always resends the exact same bytes (same idiom the original
    -- handshake used).
    local payload = {
      boardSize   = q.boardSize or boardSize,
      minWordLen  = q.minWordLen or MIN_WORD_LEN,
      boardTiles  = q.boardTiles,
      players     = q.players,
      lastUpdated = os.time(),
    }
    -- Every outgoing leg carries the sender's current W/L record against this
    -- opponent so each side's local totals can self-heal from the other's.
    -- The handshake needs it too: a match abandoned right after creation
    -- otherwise never syncs at all. Outcome isn't known yet on either leg
    -- (that's what distinguishes them from "finalize"), hence nil. At
    -- handshake time the opponent may not be in q.players yet, so prefer
    -- the match's own opponent fields.
    local function attachRecordSync()
      if not buildRecordSyncForOpponent then return end
      local oppId = q.opponentId or q.otherId
      if not oppId then
        for pid, _ in pairs(q.players or {}) do
          if pid ~= myId then oppId = pid end
        end
      end
      if oppId then
        local alias = q.otherName or q.opponentName or opponentAlias
        local sync = buildRecordSyncForOpponent(oppId, alias, myId, nil)
        if sync then payload.recordSync = sync end
      end
    end

    if leg == "handshake" then
      awaitingHandshakeSend = true
      attachRecordSync()
    elseif leg == "result" then
      local me = q.players[myId]
      if me and me.comment and me.comment ~= "" then
        payload.__gcMessage = me.comment
      end
      attachRecordSync()
    end
    pending = { leg = leg, turnData = payload, attempts = 0 }
    pendingTurnSendsByMatchId[q.id] = pending
    persistPendingTurnSends()
  end

  attemptPendingLegSend(q.id)
end

-- tbm:endTurnWithDataTable only reports failure via its callback (see
-- CodeaTurnBasedMatches.lua:806-855) — a successful send is only observable
-- via the separate tbm:onTurnEnded(...) global callback (Main.lua), which
-- calls this. Kept as its own testable function rather than inline in that
-- callback so the leg-kind dispatch (what actually changed, given which leg
-- just succeeded) has real test coverage.
function onLegSendSucceeded(matchId)
  local pending = pendingTurnSendsByMatchId[matchId]
  if not pending then return end

  if currentQMatch and currentQMatch.id == matchId and currentQMatch.players then
    if pending.leg == "handshake" then
      currentQMatch.needsInitialHandshake = false
    else
      local me = currentQMatch.players[localPID()]
      if me then me.resultSent = true end
    end
  end

  pendingTurnSendsByMatchId[matchId] = nil
  persistPendingTurnSends()

  if pending.leg == "handshake" and awaitingHandshakeSend
     and currentQMatch and currentQMatch.id == matchId then
    awaitingHandshakeSend = false
  end

  -- A "result"/"finalize" send succeeding means this match's finished result
  -- has now actually reached GameKit -- it no longer needs the standalone
  -- disk snapshot endGameRound wrote (that snapshot exists purely to survive
  -- a kill before this point was ever reached).
  if pending.leg ~= "handshake" and finishedAwaitingDecisionByMatchId[matchId] then
    finishedAwaitingDecisionByMatchId[matchId] = nil
    persistFinishedAwaitingDecision()
  end
end

-- Renamed from attemptHandshakeSend: sends whatever leg is currently frozen
-- in pendingTurnSendsByMatchId[matchId] (set by attemptLegSend), with the
-- same retry/backoff/give-up shape the original handshake used — now shared
-- by every leg kind. Also the resend target for
-- retryPendingHandshakeSends (Main.lua) on foreground/auth.
function attemptPendingLegSend(matchId)
  local pending = pendingTurnSendsByMatchId[matchId]
  if not pending then return end
  pending.attempts = pending.attempts + 1
  persistPendingTurnSends()

  if pending.leg == "finalize" then
    -- finalizeCompletedTurnBasedMatch (and the tbm:localPlayerWon/Lost/Tied
    -- calls inside it) are fire-and-forget in the bridge today — no error
    -- channel to retry against, same as before this generalization existed.
    -- Best-effort: try once, then clear the pending entry either way.
    local ok = finalizeCompletedTurnBasedMatch(nil)
    if not ok then
      devLog("attemptPendingLegSend: finalize preconditions not met", matchId)
    end
    pendingTurnSendsByMatchId[matchId] = nil
    persistPendingTurnSends()
    return
  end

  tbm:endTurnWithDataTable(pending.turnData, function(err)
    local p = pendingTurnSendsByMatchId[matchId]
    if not p then return end
    devLog("leg send failed", "matchId=", matchId, "leg=", p.leg, "attempt=", p.attempts,
      "err=", err and err.localizedDescription or "n/a")
    if p.attempts < HANDSHAKE_MAX_ATTEMPTS then
      tween.delay(HANDSHAKE_RETRY_DELAYS[p.attempts], function()
        attemptPendingLegSend(matchId)
      end)
    else
      devLog("leg send exhausted attempts; will retry in background", matchId, p.leg)
      if p.leg == "handshake" and awaitingHandshakeSend and currentQMatch and currentQMatch.id == matchId then
        awaitingHandshakeSend = false
      end
      -- pending stays in pendingTurnSendsByMatchId / on disk for background retry
    end
  end)
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
  -- Starts the self-enforced comment-timeout clock (see
  -- applyCommentTimeoutIfExpired in qMatch_qPlayer.lua) — only stamped once,
  -- the first time this player's round finishes for this match.
  q.players[pid].commentWindowStartedAt = q.players[pid].commentWindowStartedAt or os.time()

  -- Persist THIS finished-but-undecided result to disk right now, before
  -- anything else — a kill between finishing and deciding a comment must not
  -- lose the round entirely, only delay its send. Cleared by
  -- onLegSendSucceeded once the eventual send actually goes through.
  finishedAwaitingDecisionByMatchId[q.id] = q
  persistFinishedAwaitingDecision()

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

  devLog("COMMENT_DBG endGameRound: pid=", pid, "oppId=", oppId, "opponentPlayed=", opponentPlayed, "playersCount=", (function() local n=0; for _ in pairs(q.players) do n=n+1 end; return n end)())
  ------------------------------------------------------------
  -- Stay on end screen regardless; comment submission passes turn or finalizes
  ------------------------------------------------------------
  if opponentPlayed then
    local _, pendingOutcome = buildFinalTurnDataAndOutcome(nil)
    if pendingOutcome then
      q.pendingFinalOutcome = pendingOutcome
    end
  end
  q.awaitingCommentBeforeFinalization = true
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
