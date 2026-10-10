-- ===== Objective-C callback hand-off (CLAUDE.md hard rule) =====
-- An objc callback may only hand data over; the work runs in draw(). Running
-- work inside a callback froze the app: a block delivered while draw()/touched()
-- was mid-bridge-call made Codea's objc.async throw and wedged the render
-- thread for good (2026-10-10). tests/callback_rule_test.lua enforces that every
-- callback body is just a handOff(...)/deferToDraw(...) call.
_deferredWork = _deferredWork or {}

-- Plain table writes only (no C calls), so safe even mid-bridge-call.
function deferToDraw(fn, a, b, c)
  _deferredWork[#_deferredWork + 1] = { fn = fn, a = a, b = b, c = c }
end

local function _runGuarded(fn, a, b, c)
  local ok, err = xpcall(fn, debug.traceback, a, b, c)
  if not ok and devLog then devLog("callback work failed:", tostring(err)) end
end

-- While the app is drawing, queue the work for the next frame. While it isn't
-- (backgrounded/asleep -- e.g. woken by a GameKit push), draw() won't run to
-- drain the queue, but nothing can be mid-bridge-call either, so run it now.
function handOff(fn, a, b, c)
  local drawing = CODEA_RENDER_PASS or (_lastDrawAt and os.time() - _lastDrawAt <= 1)
  if drawing then deferToDraw(fn, a, b, c) else _runGuarded(fn, a, b, c) end
end

function drainDeferredWork()
  if #_deferredWork == 0 then return end
  local work = _deferredWork
  _deferredWork = {}
  for _, w in ipairs(work) do _runGuarded(w.fn, w.a, w.b, w.c) end
end

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
-- relay vs. a finalize) to computeNextOwedAction/attemptLegSend rather than
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
  -- The whole point of the nudge (scheduleCommentTimeoutNotification,
  -- endGameRound) was to get the player to come back and do exactly this --
  -- no longer needed once they have.
  cancelCommentTimeoutNotification(q.id)
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
-- previously-queued local decision sendable per computeNextOwedAction).
-- True only while the end screen up right now is showing the result of a round the local
-- player just actually finished PLAYING this session (set by endGameRound() below). Every
-- other way to land on STATE_END — opening an already-decided match from the vs list,
-- Records, or a background sync — leaves it false. disposeEndScreenAndReturnToMenu /
-- commitEndScreenCommentAndExit (EndScreen.lua / EndScreenFP.lua) gate startSeasonTransition()
-- on this, so browsing old results no longer advances the season.
justFinishedLiveGame = justFinishedLiveGame or false

-- background == true: an incoming GameKit event, not the player. Every bit of
-- model/send work still happens, but NOTHING here may change the screen
-- (MULTIPLAYER_DESIGN.md rule 8: no screen or overlay appears unless the
-- player opened it). Only the player's own taps call this without it.
local function enterQMatch_inner(q, background)
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
          mergeOpponentSlot(currentQMatch, pid, pdata)
        end
      end
      currentQMatch.lastUpdated = q.lastUpdated or currentQMatch.lastUpdated
      devLog("enterQMatch: merged incoming opponent data without disturbing local state",
        "reason=", protectInProgressRound and "in-progress-round" or "finished-unsent-result")
      return
    end
  end

  -- Background event for some OTHER match while the player is in a match
  -- screen: adopting it would replace the round/result they're looking at.
  -- Leave the model alone -- retryPendingHandshakeSends (called alongside
  -- this from onReceivingTurn) still sends whatever this device owes for it.
  if background and state ~= STATE_MENU and not (currentQMatch and currentQMatch.id == q.id) then
    devLog("enterQMatch(background): player busy in another screen; not adopting", q.id)
    -- The listener already pointed tbm.currentMatch/isMyTurn at the incoming
    -- match; point them back at the player's own, or their next send would
    -- pick turn-pass vs exchange from the wrong match's turn state.
    if currentQMatch and currentQMatch.id and tbm and tbm.ensureCurrentMatch then
      tbm:ensureCurrentMatch(currentQMatch.id, function() end)
    end
    return
  end

  -- A real entry into a match context (as opposed to the protective background merge just
  -- above, which returns early and must NOT reach here): whatever justFinishedLiveGame was
  -- claiming is no longer applicable until/unless endGameRound() sets it again below.
  if not background then
    justFinishedLiveGame = false
    if endReplayMatchmakingBusy then
      endReplayMatchmakingBusy()
    end
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
  -- computeNextOwedAction (qMatch_qPlayer.lua) needs to read this signal AFTER
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
      if not background then
        applyResolvedWordsToEndScreen(currentQMatch, localPID())
        state = STATE_END
      end
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
      if background then return end
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
    if background then return end
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

  if background then return end
  startRoundFromCurrentSettings()   -- generates+stores boardTiles, sets STATE_READY
end

-- Take the incoming opponent slot unless it would undo something already known:
-- a copy of the match decoded before the opponent's exchange was visible says
-- "not played", and must not wipe a result that has since arrived.
function mergeOpponentSlot(q, pid, incoming)
  if not (q and q.players and pid and incoming) then return end
  local cur = q.players[pid]
  if cur then
    if cur.didPlay == true and incoming.didPlay ~= true then return end
    if cur.commentDecided == true and incoming.commentDecided ~= true then return end
  end
  q.players[pid] = incoming
end

-- Exchange pushes don't reliably arrive (seen on device: an opponent's score
-- exchange sat unanswered on the match with no event ever delivered), so while
-- an end screen is waiting on the opponent, re-read the match ourselves: merge
-- whatever the opponent has sent, answer their pending exchange, and send
-- anything that's now owed. Called when a round ends and every few seconds on
-- the end screen (pollEndScreenMatch).
function refreshCurrentMatchFromGK(reason)
  local q = currentQMatch
  if not (useTurnBased and q and q.id and objc and objc.GKTurnBasedMatch) then return end
  if refreshCurrentMatchInFlight then return end
  refreshCurrentMatchInFlight = true
  local matchId = q.id
  local ok = pcall(function()
    objc.GKTurnBasedMatch:loadMatchWithID_withCompletionHandler_(matchId, function(o__match, o__err)
      -- Callback only hands the result over; the merge/reply runs in draw().
      deferToDraw(function(o__match, o__err)
        refreshCurrentMatchInFlight = false
        if o__err or not o__match then return end
        if not (currentQMatch and currentQMatch.id == matchId) then return end
        local dt = tbm._matchWithNSDataToDataTable and tbm:_matchWithNSDataToDataTable(o__match) or nil
        local fresh = makeQMatchFromGK(o__match, dt)
        if not fresh then return end
        local myId = localPID()
        local before = json.encode(currentQMatch.players or {})
        for pid, pdata in pairs(fresh.players or {}) do
          if pid ~= myId then mergeOpponentSlot(currentQMatch, pid, pdata) end
        end
        if json.encode(currentQMatch.players or {}) ~= before then
          devLog("refreshCurrentMatchFromGK: opponent data updated", matchId, "reason=", reason)
          local _, otherP = nil, nil
          for pid, pdata in pairs(currentQMatch.players) do if pid ~= myId then otherP = pdata end end
          opponentScore = tonumber(otherP and otherP.score) or opponentScore
        end
        -- Read-only with respect to the send machinery: never swap tbm.currentMatch
        -- or start a send from here (a poll shouldn't race the real send path).
        -- Only answer the opponent's pending exchange, on this freshly loaded
        -- object, when there actually is one.
        local active = o__match.activeExchanges
        if active and #active > 0 and not pendingTurnSendsByMatchId[matchId] then
          for _, ex in ipairs(active) do
            pcall(function()
              ex:replyWithLocalizableMessageKey_arguments_data_completionHandler_(
                "XCHG_REPLY", {}, tbm:_dataTableToNSData({}), function(o__err) end)
            end)
          end
        end
      end, o__match, o__err)
    end)
  end)
  if not ok then refreshCurrentMatchInFlight = false end
end

END_SCREEN_POLL_INTERVAL = 8.0
function pollEndScreenMatch()
  if state ~= STATE_END or not useTurnBased or not currentQMatch then return end
  local myId = localPID()
  local waiting = false
  for pid, pdata in pairs(currentQMatch.players or {}) do
    if pid ~= myId and not (pdata.didPlay == true and pdata.commentDecided == true) then waiting = true end
  end
  if not waiting then return end
  local now = ElapsedTime or 0
  if now - (_endScreenPollAt or -1e9) >= END_SCREEN_POLL_INTERVAL then
    _endScreenPollAt = now
    refreshCurrentMatchFromGK("endScreenPoll")
  end
end

function enterQMatch(q, opts)
  local matchId = q and q.id
  enterQMatch_inner(q, opts and opts.background == true)
  -- Runs after EVERY exit path above, not just the fallthrough — a merge
  -- guard branch or an end-screen branch may have just made something
  -- newly sendable (e.g. the opponent's resolution arriving completes what
  -- I already decided and queued earlier).
  if matchId and currentQMatch and currentQMatch.id == matchId then
    attemptLegSend(currentQMatch)
    maybeSendReminderForCurrentMatch(currentQMatch)
  end
end

HANDSHAKE_MAX_ATTEMPTS = 3
HANDSHAKE_RETRY_DELAYS = {1.0, 2.5, 5.0}

-- Kept for backward compatibility with existing call sites/tests that invoke
-- the handshake directly; routes through the same generalized path as every
-- other kind of send.
function beginInitialHandshakeSend(q)
  q.needsInitialHandshake = true
  attemptLegSend(q)
end

-- The single entry point for "do I owe this match anything right now, and if
-- so, try to send it." Safe to call speculatively and often (e.g. after every
-- enterQMatch, once a comment gets decided, or when an exchange arrives or
-- gets replied to) -- it's a no-op whenever computeNextOwedAction has nothing
-- to say, and it dedupes: an already-pending attempt for the same kind+via is
-- retried in place rather than restarted. See MULTIPLAYER_DESIGN.md "GameKit
-- exchange trial" for the design this implements -- a score/comment goes out
-- the instant it's ready, via a normal turn-pass if I hold the turn or a
-- GameKit exchange if I don't.
function attemptLegSend(q)
  if not (useTurnBased and q and q.id and tbm) then return end
  local myId = localPID()
  local action = computeNextOwedAction(q, myId, tbm.isMyTurn, os.time())
  if not action then return end

  local pending = pendingTurnSendsByMatchId[q.id]
  if not pending or pending.kind ~= action.kind or pending.via ~= action.via then
    -- Freeze the payload now rather than recomputing it on every retry, so a
    -- retry always resends the exact same bytes (same idiom the original
    -- handshake used).
    --
    -- Exchanges have their own GameKit data-size limit, confirmed live to be
    -- smaller than matchDataMaximumSize -- a full-state payload that sends
    -- fine via turn-pass failed every attempt via exchange with "the match
    -- data was too large" once both players' accumulated word lists grew.
    -- An exchange only needs to carry MY update: the recipient already has
    -- their own data with full authority, and already has boardTiles from
    -- the handshake -- so send just my own player slot, not the full
    -- q.players table, and skip boardTiles/boardSize/minWordLen entirely.
    -- A turn-pass keeps carrying the full table (the authoritative snapshot
    -- mechanism this design relies on elsewhere), unchanged.
    local payload
    if action.via == "exchange" then
      payload = {
        players     = { [myId] = q.players[myId] },
        lastUpdated = os.time(),
      }
    else
      payload = {
        boardSize   = q.boardSize or boardSize,
        minWordLen  = q.minWordLen or MIN_WORD_LEN,
        boardTiles  = q.boardTiles,
        players     = q.players,
        lastUpdated = os.time(),
      }
    end
    -- Every outgoing send carries the sender's current W/L record against this
    -- opponent so each side's local totals can self-heal from the other's.
    -- The handshake needs it too: a match abandoned right after creation
    -- otherwise never syncs at all. Outcome isn't known yet on either kind
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

    if action.kind == "handshake" then
      awaitingHandshakeSend = true
      attachRecordSync()
    elseif action.kind == "score" or action.kind == "comment" then
      -- __gcMessage only matters for endTurnWithDataTable (sets the
      -- system-matchmaker-UI message) -- unused by sendExchangeWithDataTable,
      -- so skip it for exchanges rather than waste the bytes.
      if action.via ~= "exchange" then
        local me = q.players[myId]
        if me and me.comment and me.comment ~= "" then
          payload.__gcMessage = me.comment
        end
      end
      attachRecordSync()
    end
    pending = { kind = action.kind, via = action.via, turnData = payload, attempts = 0 }
    pendingTurnSendsByMatchId[q.id] = pending
    persistPendingTurnSends()
  end

  attemptPendingLegSend(q.id)
end

-- tbm:endTurnWithDataTable only reports failure via its callback -- a
-- successful turn-pass send is only observable via the separate
-- tbm:onTurnEnded(...) global callback (Main.lua), which calls this. An
-- exchange send's success is observable directly (sendExchangeWithDataTable's
-- own completion handler), so attemptPendingLegSend calls this itself for
-- that case. Kept as its own testable function rather than inline in either
-- callback so the kind-dispatch (what actually changed, given which send just
-- succeeded) has real test coverage.
function onLegSendSucceeded(matchId)
  local pending = pendingTurnSendsByMatchId[matchId]
  if not pending then return end

  if currentQMatch and currentQMatch.id == matchId and currentQMatch.players then
    if pending.kind == "handshake" then
      currentQMatch.needsInitialHandshake = false
    else
      local me = currentQMatch.players[localPID()]
      -- The full players table is always sent regardless of which kind
      -- triggered this send, so mark whichever of score/comment were
      -- already true locally -- avoids a redundant follow-up send for the
      -- rare case both became ready before either went out.
      if me then
        if me.didPlay then me.scoreSent = true end
        if me.commentDecided then me.commentSent = true end
      end
    end
  end

  pendingTurnSendsByMatchId[matchId] = nil
  persistPendingTurnSends()

  if pending.kind == "handshake" and awaitingHandshakeSend
     and currentQMatch and currentQMatch.id == matchId then
    awaitingHandshakeSend = false
  end

  -- The disk snapshot (endGameRound's "I finished but haven't fully
  -- communicated this yet" record) is only done being needed once MY OWN
  -- comment has actually sent -- not just whenever any send succeeds. Under
  -- the old bundled design "any non-handshake send succeeding" and "comment
  -- sent" were the same event; they aren't anymore now that score and
  -- comment are independent sends (see MULTIPLAYER_DESIGN.md). A successful
  -- score-only send clearing this snapshot would permanently blind
  -- checkFinishedMatchesForCommentTimeout to a still-undecided comment --
  -- found via a live test that backdated commentWindowStartedAt right after
  -- a score-via-exchange send and discovered the snapshot was already gone.
  --
  -- And only once that comment went out via a TURN-PASS. An exchange reaches
  -- the opponent's device but not GameKit's own matchData until they merge
  -- it -- and this snapshot is also what makeQMatchFromGK overlays onto the
  -- stale server copy of my own slot. Clearing it after an exchange-sent
  -- comment (e.g. the blank comment locked by closing the end screen right
  -- after quitting) made every later reload read "I haven't played": a red
  -- vs badge, "Your move", and tapping the match restarted the round.
  -- makeQMatchFromGK prunes it instead, once the server has caught up.
  if pending.kind ~= "handshake" and finishedAwaitingDecisionByMatchId[matchId] then
    local me = currentQMatch and currentQMatch.id == matchId and currentQMatch.players
      and currentQMatch.players[localPID()]
    if me and me.commentSent and pending.via == "turn" then
      finishedAwaitingDecisionByMatchId[matchId] = nil
    end
    -- Either way, flush: the scoreSent/commentSent just set above live on
    -- this snapshot's own slot, and must survive a relaunch so the retry
    -- sweep doesn't resend.
    persistFinishedAwaitingDecision()
  end
end

-- Sends whatever kind/via is currently frozen in
-- pendingTurnSendsByMatchId[matchId] (set by attemptLegSend), with the same
-- retry/backoff/give-up shape the original handshake used -- now shared by
-- every kind. Also the resend target for retryPendingHandshakeSends
-- (Main.lua) on foreground/auth.
--
-- Every turn-passing action (a normal "via=turn" send, or "finalize") must
-- merge any completed exchanges into matchData first -- GameKit errors on
-- endTurn/endMatch otherwise (confirmed live, see MULTIPLAYER_DESIGN.md
-- "GameKit exchange trial"). mergeCompletedExchanges is a no-op straight to
-- its success callback when there's nothing to merge, so this is safe to call
-- unconditionally rather than checking first.
function attemptPendingLegSend(matchId)
  local pending = pendingTurnSendsByMatchId[matchId]
  if not pending then return end
  pending.attempts = pending.attempts + 1
  persistPendingTurnSends()

  local function onSendFailed(err)
    local p = pendingTurnSendsByMatchId[matchId]
    if not p then return end
    devLog("leg send failed", "matchId=", matchId, "kind=", p.kind, "via=", p.via,
      "attempt=", p.attempts, "err=", err and err.localizedDescription or "n/a")
    if p.attempts < HANDSHAKE_MAX_ATTEMPTS then
      tween.delay(HANDSHAKE_RETRY_DELAYS[p.attempts], function()
        attemptPendingLegSend(matchId)
      end)
    else
      devLog("leg send exhausted attempts; will retry in background", matchId, p.kind)
      if p.kind == "handshake" and awaitingHandshakeSend and currentQMatch and currentQMatch.id == matchId then
        awaitingHandshakeSend = false
      end
      -- pending stays in pendingTurnSendsByMatchId / on disk for background retry
    end
  end

  -- tbm.currentMatch can be nil or stale here -- endTurnWithDataTable's own
  -- success path nils it out deliberately, but an exchange send can become
  -- owed at any time independent of turn-pass state (confirmed live: a
  -- same-session score send after a handshake's turn-pass succeeded failed
  -- every attempt with currentMatch nil before this guard existed). Reload
  -- first rather than trusting it.
  tbm:ensureCurrentMatch(matchId, function()
    if pending.kind == "finalize" then
      tbm:mergeCompletedExchanges(pending.turnData, onSendFailed, function()
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
      end)
      return
    end

    if pending.via == "exchange" then
      tbm:sendExchangeWithDataTable(pending.turnData, onSendFailed, function()
        onLegSendSucceeded(matchId)
      end)
      return
    end

    -- via == "turn": merge first, then pass the turn. Success is reported
    -- asynchronously via tbm:onTurnEnded -> onLegSendSucceeded, same as
    -- before this generalization existed -- endTurnWithDataTable has no
    -- separate success callback of its own.
    tbm:mergeCompletedExchanges(pending.turnData, onSendFailed, function()
      tbm:endTurnWithDataTable(pending.turnData, onSendFailed)
    end)
  end)
end

-- Fires when another participant sends me a GameKit exchange (see
-- MULTIPLAYER_DESIGN.md "GameKit exchange trial") -- independent of who
-- currently holds the turn. Applies their data to our local model right away
-- (same patch shape a normal turn-pass carries) so a score/comment sent while
-- the opponent didn't hold the turn is reflected immediately, then replies to
-- the exchange -- replying doesn't require holding the turn either, so this
-- can happen the instant the exchange arrives.
function onExchangeDataReceived(gkMatch, dataTable)
  local matchId = gkMatch and gkMatch.matchID
  if dataTable and type(dataTable.players) == "table"
     and currentQMatch and matchId and currentQMatch.id == matchId then
    applyIncomingPlayersPatch(currentQMatch, dataTable.players)
    if dataTable.recordSync and mergeOpponentRecordFromTurnData then
      mergeOpponentRecordFromTurnData(gkMatch, dataTable)
    end
  end

  tbm:replyToActiveExchanges(nil, function(repliedCount)
    devLog("onExchangeDataReceived: replied to", repliedCount, "exchange(s)", "matchId=", matchId)
    -- The opponent's data just applied above might be the last missing piece
    -- (e.g. their comment, arriving via exchange because they didn't hold the
    -- turn) -- if I already hold the turn and have everything else done,
    -- that makes the match finalize-eligible right now. Nothing else
    -- re-checks this on receipt of an exchange specifically (a normal
    -- turn-pass receipt already gets this for free via enterQMatch's own
    -- attemptLegSend call) -- re-check here too, after the reply has
    -- actually round-tripped so a finalize's merge step sees this exchange
    -- as resolved. Called with the same frozen-payload-reuse/dedup semantics
    -- as every other attemptLegSend call, not a special case.
    if tbm.isMyTurn and currentQMatch and currentQMatch.id == matchId then
      attemptLegSend(currentQMatch)
    end
    if currentQMatch and currentQMatch.id == matchId then
      maybeSendReminderForCurrentMatch(currentQMatch)
    end
  end)

  if refreshHomeScreenBadgeFromGCMatches then refreshHomeScreenBadgeFromGCMatches("exchangeReceived") end
  if refreshVsMatchesList then refreshVsMatchesList("exchangeReceived") end
end

-- Fires once an exchange I sent has been replied to -- visible to both the
-- original sender and whoever currently holds the turn (per Apple's docs).
-- If I hold the turn, this is my signal that something is ready to merge --
-- attemptLegSend will pick it up via attemptPendingLegSend's merge-first step
-- the next time anything needs sending, including right now if I have my own
-- pending send queued.
function onExchangeRepliesReceived(gkMatch)
  local matchId = gkMatch and gkMatch.matchID
  if currentQMatch and matchId and currentQMatch.id == matchId then
    if tbm.isMyTurn then
      attemptLegSend(currentQMatch)
    end
    maybeSendReminderForCurrentMatch(currentQMatch)
  end
end

-- Schedules a local notification nudging the player to reopen the app,
-- firing delaySeconds after they finished -- the same moment the
-- self-enforced timeout (applyCommentTimeoutIfExpired) would otherwise
-- silently lock their comment in as blank. This is a plain UserNotifications
-- feature, unrelated to GameKit's own (unreliable, see MULTIPLAYER_DESIGN.md)
-- turnTimeout -- it doesn't force anything by itself (a local notification
-- can't run app code unless the user taps it), it only raises the odds the
-- silent player actually reopens, so the existing on-foreground logic gets a
-- chance to run. One identifier per match, so a later comment decision can
-- cancel it (cancelCommentTimeoutNotification) rather than nagging after the
-- fact. Requires requestNotificationPermissions (Main.lua) to have been
-- granted alert+sound -- silently does nothing otherwise, same as every
-- other best-effort devLog-guarded bridge call in this file.
function scheduleCommentTimeoutNotification(matchId, delaySeconds, opponentName)
  if not (objc and objc.UNUserNotificationCenter) then return end
  local ok = pcall(function()
    local UN = objc.UNUserNotificationCenter
    local center = UN.currentNotificationCenter or (UN.currentNotificationCenter and UN:currentNotificationCenter())
    if not center then return end

    local content = objc.UNMutableNotificationContent:alloc():init()
    content.title = "Your turn is waiting"
    content.body = opponentName and (opponentName .. " is waiting for your comment on your match!")
      or "Your match is waiting for your comment."
    content.sound = objc.UNNotificationSound.defaultSound

    local trigger = objc.UNTimeIntervalNotificationTrigger:triggerWithTimeInterval_repeats_(delaySeconds, false)
    local identifier = "commentTimeout-" .. tostring(matchId)
    local request = objc.UNNotificationRequest:requestWithIdentifier_content_trigger_(identifier, content, trigger)

    -- The completion block must do NOTHING. iOS answers this request almost
    -- instantly, so the block can be delivered into Lua while the round-end code
    -- is still inside another bridge call; objc.async there then got the wrong
    -- argument and threw, unwinding LuaKit while it held the render thread's lock
    -- -- the frozen-app bug (traceback from the Xcode console, 2026-10-10).
    center:addNotificationRequest_withCompletionHandler_(request, function(o__err) end)
    devLog("scheduleCommentTimeoutNotification requested", matchId)
  end)
  if not ok then
    devLog("scheduleCommentTimeoutNotification failed (bridge call)", matchId)
  end
end

-- Cancels a previously-scheduled comment-timeout nudge. Call once the
-- comment is actually decided (decideComment) so a player who responds
-- promptly doesn't get an irrelevant notification a day later. Harmless
-- no-op if nothing was pending under this identifier.
function cancelCommentTimeoutNotification(matchId)
  if not (objc and objc.UNUserNotificationCenter) then return end
  pcall(function()
    local UN = objc.UNUserNotificationCenter
    local center = UN.currentNotificationCenter or (UN.currentNotificationCenter and UN:currentNotificationCenter())
    if not center then return end
    center:removePendingNotificationRequestsWithIdentifiers_({ "commentTimeout-" .. tostring(matchId) })
  end)
end

-- The production call site for sendReminderToParticipants (see
-- MULTIPLAYER_DESIGN.md "silent player never reopens" -- confirmed live to
-- wake even a fully-terminated opponent app in the background via Apple's own
-- push infrastructure, no server of our own needed, and that wake runs the
-- very same comment-timeout sweep (Main.lua's retryPendingHandshakeSends,
-- called from onReceivingTurn) that can actually resolve a stuck match once
-- the window is up). Safe to call speculatively and often, same as
-- attemptLegSend -- a no-op whenever computeReminderDue says it isn't due, or
-- a reminder has already gone out for this match. Called from every choke
-- point that means "this match's resolution state may have just changed":
-- enterQMatch, onExchangeDataReceived, onExchangeRepliesReceived.
function maybeSendReminderForCurrentMatch(q)
  if not (useTurnBased and q and q.id and tbm) then return end
  local myId = localPID()
  noteOpponentFinishedIfNew(q, myId, os.time())
  if reminderSentByMatchId[q.id] then return end
  if not computeReminderDue(q, myId, os.time()) then return end

  -- Marked sent up front, not inside the completion handler -- a failed
  -- attempt (network blip, rate limit) should not retry on its own; see
  -- REMINDER_SENT_KEY's comment (qMatch_qPlayer.lua) for why at-most-once.
  reminderSentByMatchId[q.id] = true
  persistReminderSent()

  local matchId = q.id
  tbm:ensureCurrentMatch(matchId, function()
    tbm:sendReminderWithMessage("Your match is waiting for you!", {},
      function(o__err)
        devLog("maybeSendReminderForCurrentMatch: send failed", matchId,
          o__err and o__err.localizedDescription or "nil")
      end,
      function()
        devLog("maybeSendReminderForCurrentMatch: sent", matchId)
      end)
  end)
end

function endGameRound()
  print("DEBUG:endGameRound: currentFoundWords():", json.encode(currentFoundWords()))
  
  state = STATE_END
  justFinishedLiveGame = true  -- the ONLY place this becomes true; see declaration above
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
  if vsNoteLocalRoundFinished then vsNoteLocalRoundFinished(q.id) end
  -- Starts the self-enforced comment-timeout clock (see
  -- applyCommentTimeoutIfExpired in qMatch_qPlayer.lua) — only stamped once,
  -- the first time this player's round finishes for this match.
  local isFirstFinish = q.players[pid].commentWindowStartedAt == nil
  q.players[pid].commentWindowStartedAt = q.players[pid].commentWindowStartedAt or os.time()
  if isFirstFinish then
    scheduleCommentTimeoutNotification(q.id, COMMENT_WINDOW_SECONDS, q.otherName or q.opponentName or opponentAlias)
  end

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

  -- Score goes out the instant the round ends, regardless of comment status
  -- (MULTIPLAYER_DESIGN.md "GameKit exchange trial", rule 2) -- previously
  -- this only got attempted later, on some other trigger (enterQMatch,
  -- decideComment); now that a score never waits on a comment decision, this
  -- is the natural place to kick the first attempt.
  attemptLegSend(q)
  -- First end-screen re-check comes one poll interval later, after the score's
  -- own send has settled (see refreshCurrentMatchFromGK).
  _endScreenPollAt = ElapsedTime or 0
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
