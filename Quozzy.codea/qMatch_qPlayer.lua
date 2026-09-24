PENDING_TURN_SENDS_KEY = PENDING_TURN_SENDS_KEY or "Q_PendingTurnSends"
pendingTurnSendsByMatchId = pendingTurnSendsByMatchId or {}

function persistPendingTurnSends()
    local ok, s = pcall(json.encode, pendingTurnSendsByMatchId)
    if ok and s then saveProjectData(PENDING_TURN_SENDS_KEY, s) end
end

function loadPendingTurnSends()
    local s = readProjectData(PENDING_TURN_SENDS_KEY)
    if not s or s=="" then pendingTurnSendsByMatchId = {}; return end
    local ok, t = pcall(json.decode, s)
    pendingTurnSendsByMatchId = (ok and type(t)=="table") and t or {}
end

-- A match I've locally finished playing but haven't yet decided a comment
-- for (see COMMENT_WINDOW_SECONDS / computeNextOwedLeg). Written to disk the
-- instant a round finishes (endGameRound), not just once a decision is
-- eventually made -- otherwise a kill between finishing and deciding loses
-- the whole result, not just the send. Kept in sync by decideComment while a
-- decision is pending, and removed once onLegSendSucceeded confirms the
-- resulting send actually went through.
FINISHED_AWAITING_DECISION_KEY = FINISHED_AWAITING_DECISION_KEY or "Q_FinishedAwaitingDecision"
finishedAwaitingDecisionByMatchId = finishedAwaitingDecisionByMatchId or {}

function persistFinishedAwaitingDecision()
    local ok, s = pcall(json.encode, finishedAwaitingDecisionByMatchId)
    if ok and s then saveProjectData(FINISHED_AWAITING_DECISION_KEY, s) end
end

function loadFinishedAwaitingDecision()
    local s = readProjectData(FINISHED_AWAITING_DECISION_KEY)
    if not s or s=="" then finishedAwaitingDecisionByMatchId = {}; return end
    local ok, t = pcall(json.decode, s)
    finishedAwaitingDecisionByMatchId = (ok and type(t)=="table") and t or {}
end

-- Sweeps every locally-known finished-but-undecided match and applies the
-- comment timeout where it has expired. Pure aside from the persistence
-- calls -- no tbm/objc access -- so the caller (Main.lua, on foreground/
-- launch) is responsible for then attempting to actually send anything this
-- unblocks, the same way it already does for pendingTurnSendsByMatchId.
-- Returns a list of match ids that just became decided.
function checkFinishedMatchesForCommentTimeout(now)
  now = now or os.time()
  local justDecided = {}
  local dirty = false
  for matchId, q in pairs(finishedAwaitingDecisionByMatchId) do
    local myId = localPID()
    if applyCommentTimeoutIfExpired(q, myId, now) then
      dirty = true
      justDecided[#justDecided+1] = matchId
    end
  end
  if dirty then persistFinishedAwaitingDecision() end
  return justDecided
end

function newQMatch(id, source, localId, opponentId, opponentName, bSize, minLen)
  local q = {
    id = id,
    source = source,
    localId = localId,
    opponentId = opponentId,
    opponentName = opponentName,
    boardSize = bSize,
    minWordLen = minLen,
    outcome = "pending",
    lastUpdated = os.time(),
    players = {}
  }
  
  q.players[localId] = { score=0, words={}, wordTimes={}, didPlay=false, comment="", commentSentAt=nil }
  
  if opponentId then
    q.players[opponentId] = { score=0, words={}, wordTimes={}, didPlay=false, comment="", commentSentAt=nil }
  end
  
  return q
end

_lastDidPlaySig = _lastDidPlaySig or {}

function dbgDidPlay(tag, q)
    local myId = localPID()
    local otherId = nil
    
    if q and q.players then
        for pid,_ in pairs(q.players) do
            if pid ~= myId then otherId = pid break end
        end
    end
    
    local me   = q and q.players and q.players[myId] or nil
    local them = q and q.players and otherId and q.players[otherId] or nil
    
    local sig = table.concat({
        tostring(q and q.id),
        tostring(myId),
        tostring(otherId),
        tostring(me and me.didPlay),
        tostring(them and them.didPlay),
        tostring(me and me.score),
        tostring(them and them.score),
        tostring(me and me.words and #me.words or -1),
        tostring(them and them.words and #them.words or -1),
        tostring(state),
    }, "|")
    
    if _lastDidPlaySig[tag] == sig then return end
    _lastDidPlaySig[tag] = sig
    
    print("DIDPLAY:",
    tag,
    "match", q and q.id or "nil",
    "myId", myId,
    "otherId", otherId,
    "me.didPlay", me and me.didPlay,
    "them.didPlay", them and them.didPlay,
    "me.score", me and me.score,
    "them.score", them and them.score,
    "me.words#", me and me.words and #me.words or -1,
    "them.words#", them and them.words and #them.words or -1
    )
end

function ensureQMatchPlayers(q, localId, opponentId)
  if not q then return nil end
  
  q.players = q.players or {}
  
  function ensureSlot(pid)
    if not pid then return nil end
    local p = q.players[pid]
    if not p then p = {}; q.players[pid] = p end
    p.words     = p.words     or {}
    p.wordTimes = p.wordTimes or {}
    p.score     = p.score     or 0
    p.comment   = p.comment   or ""
    p.commentSentAt = p.commentSentAt or nil
    if p.didPlay == nil then p.didPlay = false end
    -- commentDecided: true once THIS player has locked in their comment
    -- decision (blank or not) — screen closed, backgrounded, or timed out.
    -- Distinct from `comment == ""`, which is ambiguous between "declined"
    -- and "hasn't looked yet". commentWindowStartedAt is stamped the moment
    -- didPlay becomes true, and is what a timeout check measures against.
    -- resultSent is local bookkeeping only (has THIS device already
    -- transmitted its own score+comment for this match).
    if p.commentDecided == nil then p.commentDecided = false end
    p.commentWindowStartedAt = p.commentWindowStartedAt or nil
    if p.resultSent == nil then p.resultSent = false end
    return p
  end
  
  ensureSlot(localId)
  ensureSlot(opponentId)

  return q
end

-- How long a player has, after finishing their round, to decide on a
-- comment (typed or explicitly blank) before their own device treats the
-- decision as timed-out-blank. Self-enforced only: whichever device is
-- sitting on the undecided comment is the one that resolves it, on its own
-- next foreground/launch — never the other player's device on their behalf.
COMMENT_WINDOW_SECONDS = COMMENT_WINDOW_SECONDS or 24 * 60 * 60

-- Pure decision function: given the current local view of a match, what (if
-- anything) does THIS device still owe the other side? No tbm/objc/network
-- access here — callers decide separately whether they currently hold the
-- turn to actually act on the answer. Returns one of:
--   "handshake" — the board has never gone out for this match.
--   "result"    — I've finished and decided my comment, but haven't sent
--                 that combined score+comment yet; opponent isn't fully
--                 resolved yet, so this is a plain relay (not the final one).
--   "finalize"  — same as above, except the opponent's result already
--                 arrived fully resolved too, so this leg also closes the
--                 match out for GameKit's purposes.
--   nil         — nothing to send right now (includes: I've finished but
--                 haven't decided my comment yet — deliberately wait for
--                 that, never send a bare score ahead of it).
function computeNextOwedLeg(q, myId, now)
  if not (q and q.players) then return nil end
  myId = myId or localPID()
  local me = q.players[myId]
  if not me then return nil end

  if q.needsInitialHandshake then
    return "handshake"
  end

  if not (me.didPlay and me.commentDecided) then
    return nil
  end
  if me.resultSent then
    return nil
  end

  local opp = nil
  for pid, pdata in pairs(q.players) do
    if pid ~= myId then opp = pdata end
  end

  if opp and opp.didPlay and opp.commentDecided then
    return "finalize"
  end
  return "result"
end

-- Pure timeout check: if I finished this match's round and never decided on
-- a comment within COMMENT_WINDOW_SECONDS, lock it in as blank now. Meant to
-- run against every locally-known open match on app foreground/launch,
-- before computeNextOwedLeg is consulted — mutates `me` in place and returns
-- true if it changed anything.
function applyCommentTimeoutIfExpired(q, myId, now, windowSeconds)
  if not (q and q.players) then return false end
  myId = myId or localPID()
  local me = q.players[myId]
  if not me then return false end
  now = now or os.time()
  windowSeconds = windowSeconds or COMMENT_WINDOW_SECONDS

  if me.didPlay and not me.commentDecided
     and me.commentWindowStartedAt
     and (now - me.commentWindowStartedAt) >= windowSeconds then
    me.commentDecided = true
    -- me.comment stays whatever draft (if any) was already there — an
    -- untouched draft field defaults to "" from ensureQMatchPlayers.
    return true
  end
  return false
end

-- was localPlayerId()
function localPID()
    local lp = objc.GKLocalPlayer and objc.GKLocalPlayer.localPlayer
    return (lp and (lp.gamePlayerID or lp.playerID)) or "local"
end

function startRoundFromCurrentSettings()
    defineAvatars()
    local pid, matchId, gk, src, q, otherId, otherName
    pid, matchId = localPID(), (currentQMatch and currentQMatch.id)
    
    if not matchId then
        if tbm and tbm.currentMatch then
          matchId = tbm.currentMatch.matchID
        else
          matchId = "local-"..os.time()
        end
    end
    
  src = (tbm and tbm.currentMatch) and "CTBM" or "local"
    
    otherId   = currentOpponentID
    otherName = opponentAlias
    
  if useTurnBased and currentQMatch and currentQMatch.id and currentQMatch.players then
    currentQMatch = ensureQMatchPlayers(currentQMatch, pid, otherId)
  else
    q = newQMatch(matchId, src, pid, otherId, otherName, boardSize, MIN_WORD_LEN)
    q.timeLimit, q.status = timeOptions[timeOptionIndex], "inProgress"
    currentQMatch = ensureQMatchPlayers(q, pid, otherId)
  end
    print("ROUND tiles sig (start):", currentQMatch and currentQMatch.boardTiles and table.concat(currentQMatch.boardTiles, "") or "nil")

    score, foundWords, foundWordsSet = 0, {}, {}
    lastWord, lastWordValid = "", false
    timeRemaining = timeOptions[timeOptionIndex]
    
    if resetWordListScroll then resetWordListScroll() end
    confetti, confettiActive = {}, false
    
    generateBoard(currentQMatch)
    state = STATE_READY
end

function makeDebugQMatch()
    local idx, opp, matchId, myId, q, qp, avatar, fakeWords, slot
    if not FAKE_OPPONENTS or #FAKE_OPPONENTS==0 then return nil end
    
    idx, opp = math.random(1,#FAKE_OPPONENTS), FAKE_OPPONENTS[math.random(1,#FAKE_OPPONENTS)]
    matchId = string.format("debug-%s-%d-%d", opp.id, os.time(), math.random(1000,9999))
    myId = localPID()
    
    q = newQMatch(matchId, "debug", myId, opp.id, opp.name, boardSize, MIN_WORD_LEN)
    q.status, q.isMyTurn, q.lastUpdated, q.rawMatchData = "theirTurn", true, os.time(), nil
    q.config = { boardSize=boardSize, minWordLen=MIN_WORD_LEN, timeLimit=nil, variant=nil }
    q.boardTiles = q.boardTiles or generateBoardTiles(boardSize, DICE_4x4, DICE_5x5, DICE_6x6)
    
    fakeWords = {"ALPHA","BRAVO","CHARLIE","DELTA","ECHO","FOXTROT","GOLF","HOTEL","INDIA","JULIET","ALPHA","BRAVO","CHARLIE","DELTA","ECHO","FOXTROT","GOLF","HOTEL","INDIA","JULIET"}
    
    slot = q.players[opp.id]
    slot.words = fakeWords
    slot.wordTimes = slot.wordTimes or {}
    slot.didPlay = true
    
    q = ensureQMatchPlayers(q, myId, opp.id)
    
    qp = getOrCreateQPlayer(opp.id, opp.name)
    if qp and ensureAvatarForOpponent then
        avatar = ensureAvatarForOpponent(opp.id, opp.name)
        if avatar then qp.avatar, qp.avatarStatus = avatar, "ready" end
    end
    
    do
        local them = q and q.players and q.players[opp.id]
    end
        dbgDidPlay("makeDebugQMatch return", q)
    
    return q
end

function firstNonLocalParticipant(gkMatch)
    local p,pl
    if not (gkMatch and gkMatch.participants) then return nil end
    for i=1,#gkMatch.participants do
        p = gkMatch.participants[i]; pl = p and p.player
        if pl and not pl.isLocalPlayer then return pl end
    end
end

local function firstNonLocalParticipantSlot(gkMatch)
    if not (gkMatch and gkMatch.participants) then return nil end
    for i = 1, #gkMatch.participants do
        local p = gkMatch.participants[i]
        local pl = p and p.player
        if pl then
            if not pl.isLocalPlayer then return p end
        else
            -- No player object yet; this is still a non-local slot candidate.
            return p
        end
    end
end

local function nonLocalSlotState(gkMatch)
  local p = firstNonLocalParticipantSlot(gkMatch)
  if not p then return nil end
  
  if p.player then
    return "assigned"
  end
  
  local enum = objc and objc.enum and objc.enum.GKTurnBasedParticipantStatus
  local s = p.status
  if enum and s then
    if enum.matching and s == enum.matching then return "matching" end
    if enum.invited and s == enum.invited then return "invited" end
    if enum.declined and s == enum.declined then return "declined" end
    if enum.done and s == enum.done then return "done" end
  end
  
  return "unresolved"
end

function makeQMatchFromGK(gkMatch, dataTable)
  if dataTable and type(dataTable) ~= "table" then
    print("GC WARN: dataTable is not a table, type=", type(dataTable))
    return nil
  end
  if not gkMatch then
    print("GC WARN: makeQMatchFromGK called with nil match")
    return nil
  end
  
  local localId = localPID()
  local pl = firstNonLocalParticipant(gkMatch)
  
  local matchId =
  gkMatch.matchID or gkMatch.matchId or gkMatch.matchIdentifier or gkMatch.id
  if not matchId then
    print("GC WARN: GK match has no id")
    return nil
  end
  
  local opponentId =
  (pl and (pl.gamePlayerID or pl.playerID)) or nil
  local opponentPlayerID =
  (pl and pl.playerID) or nil
  local opponentName =
  (pl and (pl.alias or pl.displayName)) or nil
  devLog("COMMENT_DBG makeQMatchFromGK: matchId=", matchId, "localId=", localId, "pl=", tostring(pl~=nil), "opponentId=", tostring(opponentId), "opponentPlayerID=", tostring(opponentPlayerID), "hasDataTablePlayers=", tostring(dataTable and type(dataTable.players)=="table"))
  
  local requestedBoardSize =
    (tbm and tbm.pendingRequestedBoardSize) or boardSize
  local requestedMinWordLen =
    (tbm and tbm.pendingRequestedMinWordLen) or MIN_WORD_LEN

  -- shell qMatch
  local q = newQMatch(
  matchId,
  "gameCenter",
  localId,
  opponentId,
  opponentName,
  (dataTable and dataTable.boardSize) or requestedBoardSize,
  (dataTable and dataTable.minWordLen) or requestedMinWordLen
  )
  
  q.opponentPlayerID = opponentPlayerID
  q.boardTiles   = dataTable and dataTable.boardTiles or q.boardTiles
  if dataTable and type(dataTable.commentPhase) == "table" then
    q.commentPhase = dataTable.commentPhase
  end
  do
    local inferred = inferBoardSizeFromTiles and inferBoardSizeFromTiles(q.boardTiles) or nil
    if inferred and areBoardTilesValidForSize and areBoardTilesValidForSize(q.boardTiles, inferred) then
      q.boardSize = inferred
    end
  end
  q.lastUpdated  = (dataTable and dataTable.lastUpdated) or os.time()
  q.remoteSlotState = nonLocalSlotState(gkMatch)
  
  -- apply players patch (THIS is the important part)
  if dataTable and type(dataTable.players) == "table" then
    for pid, patch in pairs(dataTable.players) do
      if type(pid) == "string" and type(patch) == "table" then
        q.players[pid] = q.players[pid] or {}
        local slot = q.players[pid]
        if patch.score ~= nil then slot.score = patch.score end
        if patch.words ~= nil then slot.words = patch.words end
        if patch.wordTimes ~= nil then slot.wordTimes = patch.wordTimes end
        if patch.didPlay ~= nil then slot.didPlay = patch.didPlay end
        if patch.comment ~= nil then slot.comment = patch.comment end
        if patch.commentSentAt ~= nil then slot.commentSentAt = patch.commentSentAt end
      end
    end
  end
  
  ensureQMatchPlayers(q, localId, opponentId)
  do
    local keys = {}; for k in pairs(q.players) do keys[#keys+1] = k end
    devLog("COMMENT_DBG makeQMatchFromGK final players slots:", table.concat(keys, " | "))
  end
  dbgDidPlay("makeQMatchFromGK", q)
  return q
end

-- GCDebug.lua
FAKE_OPPONENTS = FAKE_OPPONENTS or {
    { id = "fake-op-amy",   name = "Amy Bot"      },
    { id = "fake-op-bob",   name = "Bobulous"     },
    { id = "fake-op-chi",   name = "Chi Master"   },
    { id = "fake-op-dee",   name = "Dee Wordly"   },
    { id = "fake-op-eli",   name = "Eli Gamer"    },
}

function ensureQPlayerForQMatch(q)
    if not q then return nil end
    
    local id   = q.opponentId
    or q.opponentID
    or q.opponentKey  -- if you later add one
    
    local name = q.opponentName
    or q.opponentAlias
    or "Opponent"
    
    return getOrCreateQPlayer(id or name, name)
end

function getOrCreateQPlayer(id, name)
    if not id and not name then
        return nil
    end
    
    local key = id or name          -- fallback to name if no stable id
    local qp  = qPlayersById[key]
    
    if not qp then
        qp = {
            id              = key,
            name            = name or "Opponent",
            avatar          = nil,          -- UIImage (from GameKit)
            avatarStatus    = "pending",    -- "pending" | "loading" | "ready" | "failed"
            lastAvatarFetch = 0,            -- os.time() when last fetched
        }
        qPlayersById[key] = qp
        table.insert(qPlayersList, qp)
    else
        -- keep display name fresh
        if name and name ~= "" then
            qp.name = name
        end
    end
    
    return qp
end

function openDebugCommentPhasePreview()
    local q = makeDebugQMatch()
    if not q then
        print("GCDBG: could not create debug qMatch for comment preview")
        return
    end

    local myId = localPID()
    local oppId = nil
    for pid, _ in pairs(q.players or {}) do
        if pid ~= myId then
            oppId = pid
            break
        end
    end
    if not oppId then
        print("GCDBG: comment preview missing opponent slot")
        return
    end

    q.players[myId] = q.players[myId] or {}
    q.players[oppId] = q.players[oppId] or {}

    -- A's perspective: I played first, opponent hasn't played yet
    q.players[myId].didPlay        = true
    q.players[myId].score          = q.players[myId].score or 17
    q.players[myId].words          = q.players[myId].words or {"ALPHA", "BETA", "GAMMA"}
    q.players[myId].comment        = ""
    q.players[myId].commentSentAt  = nil

    q.players[oppId].didPlay       = false
    q.players[oppId].score         = 0
    q.players[oppId].words         = {}
    q.players[oppId].comment       = ""
    q.players[oppId].commentSentAt = nil

    q.pendingFinalOutcome = "win"
    q.awaitingCommentBeforeFinalization = true
    q.lastUpdated = os.time()

    currentQMatch = ensureQMatchPlayers(q, myId, oppId)
    if tbm then
        tbm.currentMatch = {
            matchID = q.id,
            participants = {}
        }
        tbm.isMyTurn = true
    end

    if enterQMatch then
        enterQMatch(currentQMatch)
    else
        useTurnBased = true
        currentMatchID = q.id
        currentOpponentID = oppId
        opponentAlias = q.otherName or q.opponentName or "Opponent"
        score = tonumber(q.players[myId].score) or 0
        opponentScore = tonumber(q.players[oppId].score) or 0
        foundWords = q.players[myId].words or {}
        foundWordsSet = {}
        for _, w in ipairs(foundWords) do
            if type(w) == "string" then
                foundWordsSet[w] = true
            end
        end
        state = STATE_END
    end

    endScreenSpeechBalloonsVisible = true
    endScreenCommentDraft = ""

    print("GCDBG: opened comment phase preview for match", q.id, "vs", opponentAlias)
end

function openDebugBothBalloonsPreview()
    local q = makeDebugQMatch()
    if not q then print("GCDBG: could not create debug qMatch") return end

    local myId = localPID()
    local oppId = nil
    for pid, _ in pairs(q.players or {}) do
        if pid ~= myId then oppId = pid break end
    end
    if not oppId then print("GCDBG: both-balloons preview missing opponent slot") return end

    q.players[myId]  = q.players[myId]  or {}
    q.players[oppId] = q.players[oppId] or {}

    -- B's perspective: both played, opponent (A) left a comment, I haven't yet
    q.players[myId].didPlay        = true
    q.players[myId].score          = 15
    q.players[myId].words          = {"DELTA", "EPSILON", "ZETA"}
    q.players[myId].comment        = ""
    q.players[myId].commentSentAt  = nil

    q.players[oppId].didPlay       = true
    q.players[oppId].score         = 17
    q.players[oppId].words         = {"ALPHA", "BETA", "GAMMA"}
    q.players[oppId].comment       = "Nice board. I missed two obvious ones."
    q.players[oppId].commentSentAt = os.time() - 90

    q.pendingFinalOutcome = "loss"
    q.awaitingCommentBeforeFinalization = true

    currentQMatch = ensureQMatchPlayers(q, myId, oppId)
    if tbm then
        tbm.currentMatch = { matchID = q.id, participants = {} }
        tbm.isMyTurn = true
    end

    if enterQMatch then
        enterQMatch(currentQMatch)
    else
        useTurnBased = true
        currentMatchID = q.id
        currentOpponentID = oppId
        opponentAlias = q.otherName or q.opponentName or "Opponent"
        score = q.players[myId].score or 0
        foundWords = q.players[myId].words or {}
        foundWordsSet = {}
        for _, w in ipairs(foundWords) do
            if type(w) == "string" then foundWordsSet[w] = true end
        end
        state = STATE_END
    end

    endScreenSpeechBalloonsVisible = true
    endScreenCommentDraft = ""
    print("GCDBG: opened both-balloons preview for match", q.id)
end

function openDebugPostMatchReview()
    local q = makeDebugQMatch()
    if not q then print("GCDBG: could not create debug qMatch") return end

    local myId = localPID()
    local oppId = nil
    for pid, _ in pairs(q.players or {}) do
        if pid ~= myId then oppId = pid break end
    end
    if not oppId then return end

    q.players[myId]  = q.players[myId]  or {}
    q.players[oppId] = q.players[oppId] or {}

    -- Post-match: both played, both commented, match is over
    q.players[myId].didPlay        = true
    q.players[myId].score          = 15
    q.players[myId].words          = {"DELTA", "EPSILON", "ZETA"}
    q.players[myId].comment        = "Ha, yeah — QUILT was hiding in plain sight."
    q.players[myId].commentSentAt  = os.time() - 30

    q.players[oppId].didPlay       = true
    q.players[oppId].score         = 17
    q.players[oppId].words         = {"ALPHA", "BETA", "GAMMA"}
    q.players[oppId].comment       = "Nice board. I missed two obvious ones."
    q.players[oppId].commentSentAt = os.time() - 90

    q.pendingFinalOutcome = "loss"
    q.awaitingCommentBeforeFinalization = false

    currentQMatch = ensureQMatchPlayers(q, myId, oppId)
    if tbm then
        tbm.currentMatch = { matchID = q.id, participants = {} }
        tbm.isMyTurn = false
    end

    if enterQMatch then
        enterQMatch(currentQMatch)
    else
        useTurnBased = true
        currentMatchID = q.id
        currentOpponentID = oppId
        opponentAlias = q.otherName or q.opponentName or "Opponent"
        score = q.players[myId].score or 0
        foundWords = q.players[myId].words or {}
        foundWordsSet = {}
        for _, w in ipairs(foundWords) do
            if type(w) == "string" then foundWordsSet[w] = true end
        end
        state = STATE_END
    end

    endScreenSpeechBalloonsVisible = true
    endScreenCommentDraft = ""
    print("GCDBG: opened post-match review preview for match", q.id)
end

function setupGCDebugParameters()
  parameter.action("Dump Opponent Records", function()
    dumpOpponentRecords()
  end)
    -- somewhere in your GC debug setup
    parameter.action("Debug: Simulate Incoming Turn", function()
        local q = makeDebugQMatch()
        if not q then
            print("GCDBG: could not create debug qMatch")
            return
        end
        storePendingTurnMatch(q)

        -- keep badge in sync with new pending matches
        if updateMatchBadgeStatus then
            updateMatchBadgeStatus()
        end
        
        print("GCDBG: added debug match vs", q.otherName or "?", "otherId:", q.otherId or "?", "playersHasOther:", (q.players and q.otherId and q.players[q.otherId]) and "yes" or "no", "matchId:", q.id)
    end)
    parameter.action("Debug: Clear All Matches", function()
      tbm:clearAllMatches()
    end)
    parameter.action("GCDBG_LoadLocalAvatar", function()
        loadLocalPlayerAvatar()
    end)
    parameter.action("Debug: End Screen (first to play)", function()
        openDebugCommentPhasePreview()
    end)
    parameter.action("Debug: End Screen (second to play)", function()
        openDebugBothBalloonsPreview()
    end)
    parameter.action("Debug: End Screen (post-match review)", function()
        openDebugPostMatchReview()
    end)
end

-- Canonical: opponent key for whatever match is on screen right now
function opponentKeyForCurrentMatch()
    local q = currentQMatch
    if not q then return nil end
    return q.otherId or q.opponentId or (q.otherName or q.opponentName or opponentAlias or "Opponent")
end
