-- Regression suite for the simultaneous-play relay/ending/comment logic.
-- Run from the repo root:  lua tests/run_tests.lua
--
-- Loads the REAL Quozzy.codea/*.lua source files into a stubbed Codea/GameKit
-- environment (tests/env.lua) — these are production files, not reimplemented
-- copies. See MULTIPLAYER_TEST_PLAN.md for the manual two-device plan this
-- complements; this suite only covers logic reachable without a live device.

local ROOT = arg[0]:match("(.*)/tests/run_tests%.lua$") or "."
dofile(ROOT .. "/tests/env.lua")

loadSource("qMatch_qPlayer.lua")
loadSource("GameCenter.lua")
loadSource("opponentRecords.lua")
loadSource("MatchSelection.lua")

-- ---------------------------------------------------------------- harness --
local pass, fail = 0, 0
local failures = {}

local function reset()
  _test_resetPersistence()
  state = STATE_MENU
  currentQMatch = nil
  useTurnBased = false
  score, opponentScore = 0, 0
  foundWords, foundWordsSet = {}, {}
  awaitingHandshakeSend = false
  pendingTurnSendsByMatchId = {}
  finishedAwaitingDecisionByMatchId = {}
  oppFinishedObservedAtByMatchId = {}
  reminderSentByMatchId = {}
  matchHistoryByOpponent = {}
  endedMatchBadgeIds = {}
  commentMatchBadgeIds = {}
  tbm = FakeTBM.new()
end

local function eq(a, b)
  if type(a) == "table" and type(b) == "table" then
    for k, v in pairs(a) do if not eq(v, b[k]) then return false end end
    for k, v in pairs(b) do if not eq(v, a[k]) then return false end end
    return true
  end
  return a == b
end

local function check(name, cond, detail)
  if cond then
    pass = pass + 1
  else
    fail = fail + 1
    failures[#failures+1] = string.format("  FAIL: %s%s", name, detail and (" — " .. detail) or "")
  end
end

-- Mirrors how production code always uses these two together (see
-- startRoundFromCurrentSettings, makeQMatchFromGK, makeDebugQMatch) so slot
-- defaults (commentDecided, scoreSent, etc.) are actually populated.
local function freshQMatch(...)
  local q = newQMatch(...)
  return ensureQMatchPlayers(q, q.localId, q.opponentId)
end

local function test(name, fn)
  reset()
  local ok, err = pcall(fn)
  if not ok then
    fail = fail + 1
    failures[#failures+1] = string.format("  ERROR: %s — %s", name, tostring(err))
  end
end

-- ============================================================ tests ======

test("newQMatch/ensureQMatchPlayers: creates both player slots", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  check("both slots exist", q.players["me"] and q.players["opp"])
  check("local didPlay false", q.players["me"].didPlay == false)
end)

-- ---- handshake send: baseline behavior of the existing single-leg send ---

-- beginInitialHandshakeSend is only ever called from enterQMatch, which
-- always sets useTurnBased=true first -- these tests replicate that
-- precondition rather than exercising it in isolation from it.

test("beginInitialHandshakeSend: sends immediately when isMyTurn", function()
  useTurnBased = true
  tbm.isMyTurn = true
  local q = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  q.boardTiles = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P"}
  beginInitialHandshakeSend(q)
  check("one send recorded", #tbm.sentCalls == 1, tostring(#tbm.sentCalls))
  local sent = tbm.sentCalls[1]
  check("boardTiles carried", eq(sent.boardTiles, q.boardTiles))
  check("no score/comment fields on handshake payload", sent.score == nil and sent.__gcMessage == nil)
end)

test("beginInitialHandshakeSend: handshake payload carries the sender's recordSync", function()
  useTurnBased = true
  tbm.isMyTurn = true
  local q = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  q.boardTiles = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P"}
  beginInitialHandshakeSend(q)
  local sync = tbm.sentCalls[1] and tbm.sentCalls[1].recordSync
  check("recordSync attached", sync ~= nil)
  check("recordSync targets the opponent", sync and sync.opponentId == "opp")
  check("recordSync sender is me", sync and sync.senderId == "local-player-id")
end)

test("beginInitialHandshakeSend: recordSync uses q.opponentId when opponent has no player slot yet", function()
  useTurnBased = true
  tbm.isMyTurn = true
  local q = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  q.players["opp"] = nil -- brand-new match: opponent not seated yet
  q.boardTiles = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P"}
  beginInitialHandshakeSend(q)
  local sync = tbm.sentCalls[1] and tbm.sentCalls[1].recordSync
  check("recordSync still attached", sync ~= nil and sync.opponentId == "opp")
end)

test("attemptPendingLegSend: retries on failure up to HANDSHAKE_MAX_ATTEMPTS, then gives up", function()
  useTurnBased = true
  tbm.isMyTurn = true
  tbm.failNextSends = HANDSHAKE_MAX_ATTEMPTS -- fail every attempt
  local q = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  q.boardTiles = {"A"}
  awaitingHandshakeSend = true
  currentQMatch = q
  beginInitialHandshakeSend(q)

  check("attempt 1 made, 0 sent (failed)", #tbm.sentCalls == 0)
  check("attempt count recorded", pendingTurnSendsByMatchId["m1"].attempts == 1)
  check("a retry was queued", _test_pendingTweenCount() == 1)

  _test_flushTweens() -- attempt 2
  check("attempt 2 recorded", pendingTurnSendsByMatchId["m1"].attempts == 2)
  check("still awaiting (below max)", awaitingHandshakeSend == true)

  _test_flushTweens() -- attempt 3 = HANDSHAKE_MAX_ATTEMPTS, exhausts retries
  check("attempt 3 recorded", pendingTurnSendsByMatchId["m1"].attempts == HANDSHAKE_MAX_ATTEMPTS)
  check("gives up after max attempts", awaitingHandshakeSend == false)
  check("no further retry queued", _test_pendingTweenCount() == 0)
end)

test("attemptPendingLegSend: cannot send when it is not my turn (matches real CTBM contract)", function()
  useTurnBased = true
  tbm.isMyTurn = false
  local q = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  q.boardTiles = {"A"}
  beginInitialHandshakeSend(q)
  check("nothing sent", #tbm.sentCalls == 0)
  check("treated as a failure (queued for retry)", pendingTurnSendsByMatchId["m1"].attempts == 1)
end)

-- ---- enterQMatch merge-guard: protecting an in-progress local round ------

test("enterQMatch: merges opponent data into an in-progress local round (STATE_PLAY), does not restart it", function()
  state = STATE_PLAY
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.boardTiles = {"MY","BOARD"}
  currentQMatch.players["local-player-id"].didPlay = false

  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.players["opp"].didPlay = true
  incoming.players["opp"].score = 12
  incoming.boardTiles = {"DIFFERENT","BOARD"} -- would prove a restart if it leaked through

  enterQMatch(incoming)

  check("state still PLAY (round not restarted)", state == STATE_PLAY)
  check("local board untouched", eq(currentQMatch.boardTiles, {"MY","BOARD"}))
  check("opponent score merged in", currentQMatch.players["opp"].score == 12)
end)

test("enterQMatch: protects a finished-but-unsubmitted local result sitting on STATE_END (MULTIPLAYER_TEST_PLAN.md 1.6)", function()
  state = STATE_END
  useTurnBased = true
  tbm.isMyTurn = false -- can't currently submit, mirrors post-handshake state
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].score = 42 -- the real, unsent result
  currentQMatch.players["local-player-id"].words = {"CAT","DOG"}

  local staleIncoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  -- Stale payload: opponent's device never received our score, so it still
  -- shows us as not having played.
  staleIncoming.players["local-player-id"].didPlay = false
  staleIncoming.players["opp"].didPlay = true
  staleIncoming.players["opp"].score = 5

  enterQMatch(staleIncoming)

  check("local score survives", currentQMatch.players["local-player-id"].score == 42)
  check("local words survive", eq(currentQMatch.players["local-player-id"].words, {"CAT","DOG"}))
  check("local didPlay still true", currentQMatch.players["local-player-id"].didPlay == true)
  check("opponent's genuinely new data still merges in", currentQMatch.players["opp"].score == 5)
  check("state stays END (no restart)", state == STATE_END)
end)

test("enterQMatch: does not apply the finished-result guard once the state has moved to MENU", function()
  state = STATE_MENU
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].score = 42

  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.players["local-player-id"].didPlay = false
  incoming.players["opp"].didPlay = true
  incoming.boardTiles = {"NEW","ROUND"}

  enterQMatch(incoming)

  -- Once we've left STATE_END (back at the menu, this match already fully
  -- wrapped up locally), a fresh incoming q for the SAME id is a legitimate
  -- new round (e.g. a rematch) and should be allowed through normally.
  check("guard does not fire outside READY/PLAY/END", currentQMatch.boardTiles ~= nil)
end)

-- ---- endGameRound: current (pre-relay-generalization) behavior ----------

test("endGameRound: single player just records local score, no GK involvement", function()
  useTurnBased = false
  currentQMatch = freshQMatch("m1", "local", "local-player-id", nil, nil, 4, 3)
  score = 17
  foundWords = {"CAT","DOG"}
  endGameRound()
  check("state END", state == STATE_END)
  check("score recorded", currentQMatch.players["local-player-id"].score == 17)
  check("didPlay true", currentQMatch.players["local-player-id"].didPlay == true)
  check("no GK sends", #tbm.sentCalls == 0)
end)

test("endGameRound: multiplayer sends the score immediately when isMyTurn (MULTIPLAYER_DESIGN.md rule 2)", function()
  useTurnBased = true
  tbm.isMyTurn = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  score = 23
  foundWords = {"WORD"}
  endGameRound()
  check("local score recorded", currentQMatch.players["local-player-id"].score == 23)
  check("didPlay true", currentQMatch.players["local-player-id"].didPlay == true)
  check("awaiting comment flag set", currentQMatch.awaitingCommentBeforeFinalization == true)
  check("score sent immediately via turn-pass, independent of comment status",
    #tbm.sentCalls == 1 and tbm.sentCalls[1].players["local-player-id"].score == 23)
end)

-- ---- enterQMatch: needsInitialHandshake flag threading (hazard #1) -------

test("enterQMatch: stores needsInitialHandshake=true for the creator's first-ever turn-event", function()
  tbm.isMyTurn = true
  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.boardTiles = nil -- never sent by anyone yet
  enterQMatch(incoming)
  check("flag set", currentQMatch.needsInitialHandshake == true)
end)

test("enterQMatch: stores needsInitialHandshake=false once real tiles have already arrived (the receiver's view)", function()
  tbm.isMyTurn = true
  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.boardTiles = {"A","B","C","D","E","F","G","H","I","J","K","L","M","N","O","P"} -- just received via handshake
  enterQMatch(incoming)
  check("flag clear", currentQMatch.needsInitialHandshake == false)
end)

test("enterQMatch: needsInitialHandshake stays true even after startRoundFromCurrentSettings locally generates real tiles", function()
  tbm.isMyTurn = true
  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.boardTiles = nil
  enterQMatch(incoming)
  -- startRoundFromCurrentSettings ran as part of enterQMatch above; confirm
  -- the flag survived it (this is the whole point of storing it explicitly
  -- rather than re-deriving from tile validity afterward).
  check("still true post-generation", currentQMatch.needsInitialHandshake == true)
  local a = computeNextOwedAction(currentQMatch, "local-player-id", true, os.time())
  check("computeNextOwedAction still sees it", a and a.kind == "handshake")
end)

test("enterQMatch: needsInitialHandshake false when it is not my turn (not the creator)", function()
  tbm.isMyTurn = false
  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.boardTiles = nil
  enterQMatch(incoming)
  check("flag clear", currentQMatch.needsInitialHandshake == false)
end)

test("enterQMatch: needsInitialHandshake false if someone has already played (belt-and-suspenders)", function()
  tbm.isMyTurn = true
  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.boardTiles = nil
  incoming.players["opp"].didPlay = true
  enterQMatch(incoming)
  check("flag clear", currentQMatch.needsInitialHandshake == false)
end)

-- ---- enterQMatch: a pending local decision beats a stale incoming payload
-- about my own slot, outside the STATE_END-guarded window too (hazard #3) --

test("enterQMatch: a queued-but-unsent local result survives a stale incoming payload once back at STATE_MENU", function()
  state = STATE_MENU -- already left the end screen; STATE_END guard no longer applies
  useTurnBased = true
  tbm.isMyTurn = true

  -- I finished earlier and decided my comment, but couldn't send yet at the
  -- time (not my turn then) -- exactly what attemptLegSend/decideComment
  -- would have queued, frozen at the moment of decision.
  pendingTurnSendsByMatchId["m1"] = {
    kind = "comment",
    via = "turn",
    attempts = 0,
    turnData = {
      boardSize = 4, minWordLen = 3, boardTiles = {"X"},
      players = {
        ["local-player-id"] = { didPlay = true, score = 99, words = {"ZEBRA"},
          wordTimes = {}, comment = "gg", commentDecided = true, scoreSent = true, commentSent = false },
      },
    },
  }

  -- The incoming turn-event is necessarily stale about me (built before my
  -- decision existed), but genuinely fresh about the opponent, who has now
  -- also finished.
  local staleIncoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  staleIncoming.players["local-player-id"].didPlay = false
  staleIncoming.players["opp"].didPlay = true
  staleIncoming.players["opp"].score = 5

  enterQMatch(staleIncoming)

  check("my queued score survives", currentQMatch.players["local-player-id"].score == 99)
  check("my queued comment survives", currentQMatch.players["local-player-id"].comment == "gg")
  check("my queued didPlay survives", currentQMatch.players["local-player-id"].didPlay == true)
  check("opponent's genuinely new data still merges in", currentQMatch.players["opp"].score == 5)
  -- With both sides now showing didPlay==true (thanks to the restored local
  -- truth), this should land correctly on the results screen instead of
  -- falling through to startRoundFromCurrentSettings and wrongly restarting.
  check("lands on END with correct score, not a restarted round",
    state == STATE_END and score == 99)
end)

-- ---- onLegSendSucceeded: the tbm:onTurnEnded success path (hazard #2) ----

test("onLegSendSucceeded: handshake success clears needsInitialHandshake, awaitingHandshakeSend, and the pending entry", function()
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.needsInitialHandshake = true
  awaitingHandshakeSend = true
  pendingTurnSendsByMatchId["m1"] = { kind = "handshake", turnData = {}, attempts = 1 }

  onLegSendSucceeded("m1")

  check("needsInitialHandshake cleared", currentQMatch.needsInitialHandshake == false)
  check("awaitingHandshakeSend cleared", awaitingHandshakeSend == false)
  check("pending entry removed", pendingTurnSendsByMatchId["m1"] == nil)
end)

test("onLegSendSucceeded: a 'comment' send marks scoreSent and commentSent instead of touching the handshake flags", function()
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.needsInitialHandshake = false
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].commentDecided = true
  awaitingHandshakeSend = false
  pendingTurnSendsByMatchId["m1"] = { kind = "comment", via = "turn", turnData = {}, attempts = 1 }

  onLegSendSucceeded("m1")

  -- The full players table is always sent regardless of kind, so a
  -- "comment" send succeeding marks both -- see onLegSendSucceeded.
  check("scoreSent marked", currentQMatch.players["local-player-id"].scoreSent == true)
  check("commentSent marked", currentQMatch.players["local-player-id"].commentSent == true)
  check("pending entry removed", pendingTurnSendsByMatchId["m1"] == nil)
end)

test("onLegSendSucceeded: no-op if there is no pending entry for that match id", function()
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  onLegSendSucceeded("m1") -- must not error
  check("still nil, no crash", pendingTurnSendsByMatchId["m1"] == nil)
end)

test("onLegSendSucceeded: clears the pending entry for a match that isn't the currently-active one, without touching currentQMatch", function()
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].scoreSent = false
  pendingTurnSendsByMatchId["m2"] = { kind = "comment", via = "turn", turnData = {}, attempts = 1 }

  onLegSendSucceeded("m2")

  check("unrelated match's pending entry cleared", pendingTurnSendsByMatchId["m2"] == nil)
  check("active match untouched", currentQMatch.players["local-player-id"].scoreSent == false)
end)

-- ---- end-to-end wiring: enterQMatch / decideComment now drive real sends -

test("enterQMatch: automatically sends the handshake for a brand-new match, with no direct beginInitialHandshakeSend call", function()
  tbm.isMyTurn = true
  local incoming = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  incoming.boardTiles = nil
  enterQMatch(incoming) -- the outer wrapper should call attemptLegSend on our behalf
  check("handshake sent", #tbm.sentCalls == 1)
  -- FakeTBM's endTurnWithDataTable "succeeding" only means it didn't call
  -- onError -- exactly like the real bridge, that is NOT the success signal
  -- (see onLegSendSucceeded/hazard #2). The flag only clears once the
  -- separate tbm:onTurnEnded path (simulated here) actually fires.
  check("needsInitialHandshake NOT yet cleared by the send itself", currentQMatch.needsInitialHandshake == true)
  onLegSendSucceeded("m1")
  check("needsInitialHandshake cleared once onTurnEnded fires", currentQMatch.needsInitialHandshake == false)
end)

test("decideComment: sends a 'comment' leg via turn-pass when the opponent hasn't played yet", function()
  useTurnBased = true
  tbm.isMyTurn = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].scoreSent = true -- sent already, via endGameRound
  score, foundWords = 10, {"CAT"}

  local ok = decideComment("nice board!")
  check("decideComment returns true", ok == true)
  check("comment recorded", currentQMatch.players["local-player-id"].comment == "nice board!")
  check("commentDecided", currentQMatch.players["local-player-id"].commentDecided == true)
  check("one relay sent", #tbm.sentCalls == 1)
  check("comment rides along as the GK message", tbm.sentCalls[1].__gcMessage == "nice board!")
  check("not yet a finalize call", #tbm.wonCalls + #tbm.lostCalls + #tbm.tiedCalls == 0)
end)

test("decideComment: sends 'finalize' and calls localPlayerWon when the opponent already resolved and I'm ahead", function()
  useTurnBased = true
  tbm.isMyTurn = true
  tbm.currentMatch = { matchID = "m1" } -- needed for buildFinalTurnDataAndOutcome's precondition
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].scoreSent = true -- sent already, via endGameRound's own attemptLegSend call
  currentQMatch.players["local-player-id"].words = {"CAT","DOG","BIRD"} -- score 3 via the test env's reconcile stub
  currentQMatch.players["opp"].didPlay = true
  currentQMatch.players["opp"].commentDecided = true
  currentQMatch.players["opp"].comment = "gg"
  currentQMatch.players["opp"].words = {"ANT"} -- score 1

  local ok = decideComment("")
  check("decideComment returns true", ok == true)
  check("no plain relay sent (this was the finalize leg)", #tbm.sentCalls == 0)
  check("localPlayerWon called", #tbm.wonCalls == 1)
  check("pending entry cleared after finalize", pendingTurnSendsByMatchId["m1"] == nil)
end)

test("onExchangeDataReceived: finalizes immediately if the opponent's data arriving via exchange completes the picture", function()
  -- Regression case: I've already done everything on my end and am just
  -- sitting idle; the opponent's comment -- the one remaining missing piece
  -- -- arrives via exchange (they didn't hold the turn) rather than a normal
  -- turn-pass. A turn-pass receipt gets a free re-check via enterQMatch's own
  -- attemptLegSend call; an exchange receipt needs its own, or finalize-
  -- eligible matches sit undetected until something unrelated happens to
  -- call attemptLegSend again.
  useTurnBased = true
  tbm.isMyTurn = true
  tbm.currentMatch = { matchID = "m1" }
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].scoreSent = true
  currentQMatch.players["local-player-id"].commentDecided = true
  currentQMatch.players["local-player-id"].commentSent = true
  currentQMatch.players["local-player-id"].words = {"CAT","DOG","BIRD"} -- score 3
  currentQMatch.players["opp"].didPlay = true
  currentQMatch.players["opp"].words = {"ANT"} -- score 1
  -- opponent's commentDecided is still false -- about to arrive via exchange

  onExchangeDataReceived({ matchID = "m1" }, {
    players = { opp = { commentDecided = true, comment = "gg" } }
  })

  check("opponent's commentDecided applied from the exchange payload",
    currentQMatch.players["opp"].commentDecided == true)
  check("finalize triggered without any other action", #tbm.wonCalls == 1)
  check("pending entry cleared after finalize", pendingTurnSendsByMatchId["m1"] == nil)
end)

test("decideComment: sends via exchange when not holding the turn, rather than waiting for it", function()
  useTurnBased = true
  tbm.isMyTurn = false -- e.g. the match creator, right after sending the handshake
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].scoreSent = true -- sent already, via endGameRound

  local ok = decideComment("thoughts recorded even without the turn")
  check("decideComment still returns true (decision recorded)", ok == true)
  check("commentDecided true regardless of turn ownership", currentQMatch.players["local-player-id"].commentDecided == true)
  check("nothing sent via turn-pass", #tbm.sentCalls == 0)
  -- The whole point of the exchange path (MULTIPLAYER_DESIGN.md "GameKit
  -- exchange trial"): a comment no longer has to wait on the phone for the
  -- turn to arrive, risking the 24h clock -- it goes out immediately via
  -- exchange instead.
  check("sent via exchange instead of waiting for the turn", #tbm.exchangeSentCalls == 1)
  -- Regression: exchanges have their own (smaller) GameKit data-size limit --
  -- confirmed live ("the match data was too large" on a full-state payload
  -- that sends fine via turn-pass). An exchange must only carry the sender's
  -- own update, not the opponent's slot or board data the recipient already
  -- has from the handshake.
  local sent = tbm.exchangeSentCalls[1]
  check("exchange payload has only my own player slot", sent.players["opp"] == nil)
  check("exchange payload omits boardTiles (recipient already has it)", sent.boardTiles == nil)
end)

-- ---- finishedAwaitingDecisionByMatchId: surviving a kill before deciding --

test("endGameRound: persists the finished-but-undecided result to disk immediately, before any decision is made", function()
  useTurnBased = true
  tbm.isMyTurn = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  score, foundWords = 17, {"ZEBRA"}
  endGameRound()

  check("tracked in memory", finishedAwaitingDecisionByMatchId["m1"] ~= nil)
  check("score present in the tracked snapshot",
    finishedAwaitingDecisionByMatchId["m1"].players["local-player-id"].score == 17)

  -- Simulate an app restart: wipe the in-memory table, reload from the
  -- persisted disk copy, and confirm the result is recoverable purely from
  -- what was written -- not from anything still sitting in memory.
  finishedAwaitingDecisionByMatchId = {}
  loadFinishedAwaitingDecision()
  local recovered = finishedAwaitingDecisionByMatchId["m1"]
  check("recovered after simulated restart", recovered ~= nil)
  check("recovered score matches", recovered and recovered.players["local-player-id"].score == 17)
  check("recovered didPlay", recovered and recovered.players["local-player-id"].didPlay == true)
  check("recovered commentDecided still false (nothing decided yet)",
    recovered and recovered.players["local-player-id"].commentDecided == false)
end)

test("onLegSendSucceeded: clears the finished-awaiting-decision snapshot once my comment actually sends", function()
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].commentDecided = true -- locked, about to send
  finishedAwaitingDecisionByMatchId["m1"] = currentQMatch
  persistFinishedAwaitingDecision()
  pendingTurnSendsByMatchId["m1"] = { kind = "comment", via = "turn", turnData = {}, attempts = 1 }

  onLegSendSucceeded("m1")

  check("snapshot cleared", finishedAwaitingDecisionByMatchId["m1"] == nil)
end)

test("onLegSendSucceeded: a successful SCORE-ONLY send does NOT clear the snapshot while the comment is still undecided", function()
  -- Regression case: under the old bundled design, any non-handshake send
  -- succeeding meant the comment was sent too (they always went out
  -- together). Now that score and comment are independent sends, a
  -- score-only success must leave the snapshot in place, or
  -- checkFinishedMatchesForCommentTimeout would permanently lose the
  -- ability to ever sweep this match's still-undecided comment. Found via a
  -- live device test that backdated commentWindowStartedAt right after a
  -- score-via-exchange send and discovered the snapshot was already gone.
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  -- commentDecided deliberately left false -- comment not decided yet
  finishedAwaitingDecisionByMatchId["m1"] = currentQMatch
  persistFinishedAwaitingDecision()
  pendingTurnSendsByMatchId["m1"] = { kind = "score", via = "exchange", turnData = {}, attempts = 1 }

  onLegSendSucceeded("m1")

  check("scoreSent marked", currentQMatch.players["local-player-id"].scoreSent == true)
  check("snapshot survives -- comment still undecided", finishedAwaitingDecisionByMatchId["m1"] ~= nil)
end)

test("onLegSendSucceeded: a successful handshake does NOT touch the finished-awaiting-decision table", function()
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  finishedAwaitingDecisionByMatchId["m2"] = { id = "m2", players = {} } -- unrelated match, still finishing
  pendingTurnSendsByMatchId["m1"] = { kind = "handshake", turnData = {}, attempts = 1 }

  onLegSendSucceeded("m1")

  check("unrelated finished-awaiting-decision entry untouched", finishedAwaitingDecisionByMatchId["m2"] ~= nil)
end)

test("checkFinishedMatchesForCommentTimeout: decides blank once the window has expired, and reports the match id", function()
  local now = os.time()
  local q = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  q.players["local-player-id"].didPlay = true
  q.players["local-player-id"].commentWindowStartedAt = now - (COMMENT_WINDOW_SECONDS + 1)
  finishedAwaitingDecisionByMatchId["m1"] = q

  local justDecided = checkFinishedMatchesForCommentTimeout(now)

  check("reported as newly decided", #justDecided == 1 and justDecided[1] == "m1")
  check("commentDecided now true", q.players["local-player-id"].commentDecided == true)
end)

test("checkFinishedMatchesForCommentTimeout: leaves matches still inside their window alone", function()
  local now = os.time()
  local q = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  q.players["local-player-id"].didPlay = true
  q.players["local-player-id"].commentWindowStartedAt = now - 10
  finishedAwaitingDecisionByMatchId["m1"] = q

  local justDecided = checkFinishedMatchesForCommentTimeout(now)

  check("nothing decided yet", #justDecided == 0)
  check("still undecided", q.players["local-player-id"].commentDecided == false)
end)

-- ---- noteOpponentFinishedIfNew / computeReminderDue / maybeSendReminderForCurrentMatch
-- (sendReminderToParticipants production wiring -- MULTIPLAYER_DESIGN.md
-- "silent player never reopens") --------------------------------------------

test("noteOpponentFinishedIfNew: stamps the observation the first time the opponent is seen to have played", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["opp"].didPlay = true
  local before = os.time()

  noteOpponentFinishedIfNew(q, "me", before)

  check("stamped", oppFinishedObservedAtByMatchId["m1"] == before)
end)

test("noteOpponentFinishedIfNew: does not re-stamp on a later call (q rebuilt fresh from a later turn event)", function()
  -- makeQMatchFromGK rebuilds q from scratch on every incoming turn/exchange
  -- event (enterQMatch_inner, GameCenter.lua), so the opponent's didPlay==true
  -- reappears "fresh" on every subsequent event too -- the FIRST observation
  -- must stick regardless.
  local q1 = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q1.players["opp"].didPlay = true
  noteOpponentFinishedIfNew(q1, "me", 1000)

  local q2 = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q2.players["opp"].didPlay = true
  noteOpponentFinishedIfNew(q2, "me", 5000)

  check("still the original timestamp", oppFinishedObservedAtByMatchId["m1"] == 1000)
end)

test("noteOpponentFinishedIfNew: no-op while the opponent hasn't played yet", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  noteOpponentFinishedIfNew(q, "me", os.time())
  check("nothing recorded", oppFinishedObservedAtByMatchId["m1"] == nil)
end)

test("computeReminderDue: false before I've finished my own side", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["opp"].didPlay = true
  oppFinishedObservedAtByMatchId["m1"] = os.time() - (COMMENT_WINDOW_SECONDS + 1)
  check("false", computeReminderDue(q, "me", os.time()) == false)
end)

test("computeReminderDue: false if the opponent hasn't played at all", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay = true
  q.players["me"].commentDecided = true
  check("false", computeReminderDue(q, "me", os.time()) == false)
end)

test("computeReminderDue: false once the opponent has already decided their comment", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].commentDecided = true, true
  q.players["opp"].didPlay, q.players["opp"].commentDecided = true, true
  oppFinishedObservedAtByMatchId["m1"] = os.time() - (COMMENT_WINDOW_SECONDS + 1)
  check("false", computeReminderDue(q, "me", os.time()) == false)
end)

test("computeReminderDue: false before the window has elapsed since I observed them finish", function()
  local now = os.time()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].commentDecided = true, true
  q.players["opp"].didPlay = true
  oppFinishedObservedAtByMatchId["m1"] = now - 10
  check("false", computeReminderDue(q, "me", now) == false)
end)

test("computeReminderDue: true once the window has elapsed since I observed them finish", function()
  local now = os.time()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].commentDecided = true, true
  q.players["opp"].didPlay = true
  oppFinishedObservedAtByMatchId["m1"] = now - (COMMENT_WINDOW_SECONDS + 1)
  check("true", computeReminderDue(q, "me", now) == true)
end)

test("maybeSendReminderForCurrentMatch: sends when due, and never sends a second time for the same match", function()
  useTurnBased = true
  local now = os.time()
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay, currentQMatch.players["local-player-id"].commentDecided = true, true
  currentQMatch.players["opp"].didPlay = true
  oppFinishedObservedAtByMatchId["m1"] = now - (COMMENT_WINDOW_SECONDS + 1)

  maybeSendReminderForCurrentMatch(currentQMatch)
  check("sent once", #tbm.reminderCalls == 1)
  check("marked sent", reminderSentByMatchId["m1"] == true)

  maybeSendReminderForCurrentMatch(currentQMatch)
  check("not sent again", #tbm.reminderCalls == 1)
end)

test("maybeSendReminderForCurrentMatch: does nothing the moment I first observe the opponent finish (not due yet)", function()
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay, currentQMatch.players["local-player-id"].commentDecided = true, true
  currentQMatch.players["opp"].didPlay = true

  maybeSendReminderForCurrentMatch(currentQMatch)

  check("nothing sent", #tbm.reminderCalls == 0)
  check("not marked sent", reminderSentByMatchId["m1"] == nil)
end)

test("maybeSendReminderForCurrentMatch: a failed send still counts as attempted, and is not retried", function()
  -- Marked sent up front rather than in the completion handler -- a failed
  -- attempt (network blip, rate limit) must not retry on its own. See
  -- REMINDER_SENT_KEY's comment (qMatch_qPlayer.lua).
  useTurnBased = true
  local now = os.time()
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay, currentQMatch.players["local-player-id"].commentDecided = true, true
  currentQMatch.players["opp"].didPlay = true
  oppFinishedObservedAtByMatchId["m1"] = now - (COMMENT_WINDOW_SECONDS + 1)
  tbm.failNextReminders = 1

  maybeSendReminderForCurrentMatch(currentQMatch)
  check("attempted", #tbm.reminderCalls == 1)
  check("still marked sent despite failure", reminderSentByMatchId["m1"] == true)

  maybeSendReminderForCurrentMatch(currentQMatch)
  check("not retried", #tbm.reminderCalls == 1)
end)

test("maybeSendReminderForCurrentMatch: reminderSentByMatchId survives a simulated restart", function()
  useTurnBased = true
  local now = os.time()
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay, currentQMatch.players["local-player-id"].commentDecided = true, true
  currentQMatch.players["opp"].didPlay = true
  oppFinishedObservedAtByMatchId["m1"] = now - (COMMENT_WINDOW_SECONDS + 1)

  maybeSendReminderForCurrentMatch(currentQMatch)
  check("sent", #tbm.reminderCalls == 1)

  reminderSentByMatchId = {}
  loadReminderSent()
  check("recovered after simulated restart", reminderSentByMatchId["m1"] == true)
end)

-- ---- shouldShowFinalCommentComposer: no longer gated on holding the turn -

test("shouldShowFinalCommentComposer: available after finishing even without the turn (the post-handshake creator's case)", function()
  useTurnBased = true
  tbm.isMyTurn = false
  tbm.currentMatch = nil -- exactly what the real CTBM leaves behind after the handshake succeeds
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  check("composer available", shouldShowFinalCommentComposer() == true)
end)

test("shouldShowFinalCommentComposer: hidden before the player has finished playing", function()
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  check("composer hidden", shouldShowFinalCommentComposer() == false)
end)

test("shouldShowFinalCommentComposer: hidden once already decided (no re-editing)", function()
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.players["local-player-id"].commentDecided = true
  check("composer hidden", shouldShowFinalCommentComposer() == false)
end)

test("shouldShowFinalCommentComposer: hidden for a reconstructed historical match view", function()
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "history", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  -- RecordsUI.lua's openHistoricalMatchEndScreen sets this explicitly and
  -- never populates commentDecided at all -- this is the field that has to
  -- do the excluding for that case.
  currentQMatch.recordOutcomeApplied = true
  check("composer hidden", shouldShowFinalCommentComposer() == false)
end)

test("shouldShowFinalCommentComposer: hidden once the match has already been finalized", function()
  useTurnBased = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  currentQMatch.players["local-player-id"].didPlay = true
  currentQMatch.recordOutcomeApplied = true -- set by finalizeCompletedTurnBasedMatch
  check("composer hidden", shouldShowFinalCommentComposer() == false)
end)

-- ---- badges: "game ended" and "opponent commented" -----------------------

test("matchNeedsEndedBadge: false until both players have played", function()
  check("not played yet", matchNeedsEndedBadge(false, nil) == false)
end)

test("matchNeedsEndedBadge: true once both played and never recorded (never viewed)", function()
  check("unseen ended match", matchNeedsEndedBadge(true, nil) == true)
end)

test("matchNeedsEndedBadge: true if recorded but the recorded version was still in-progress", function()
  check("stale incomplete record", matchNeedsEndedBadge(true, { complete = false }) == true)
end)

test("matchNeedsEndedBadge: false once viewed as complete", function()
  check("already seen complete", matchNeedsEndedBadge(true, { complete = true }) == false)
end)

test("matchNeedsCommentBadge: false when the opponent hasn't left one", function()
  check("no comment", matchNeedsCommentBadge("", nil) == false)
  check("nil comment", matchNeedsCommentBadge(nil, { oppComment = "old" }) == false)
end)

test("matchNeedsCommentBadge: true for a comment that's never been recorded", function()
  check("brand new comment, no history at all", matchNeedsCommentBadge("nice game", nil) == true)
end)

test("matchNeedsCommentBadge: false once the exact comment text has already been recorded", function()
  check("already seen", matchNeedsCommentBadge("nice game", { oppComment = "nice game" }) == false)
end)

test("matchNeedsCommentBadge: true when the live comment differs from what was recorded (a later, different comment)", function()
  check("comment changed since last seen", matchNeedsCommentBadge("actually, gg", { oppComment = "nice game" }) == true)
end)

test("findMatchHistoryEntry: locates by match id within an opponent's list, nil when absent", function()
  matchHistoryByOpponent["opp"] = { { id = "m1", complete = true }, { id = "m2", complete = false } }
  check("finds m2", findMatchHistoryEntry("opp", "m2").complete == false)
  check("missing id -> nil", findMatchHistoryEntry("opp", "m3") == nil)
  check("missing opponent -> nil", findMatchHistoryEntry("nobody", "m1") == nil)
end)

test("computeMatchBadges: partitions a mixed batch of live matches correctly", function()
  matchHistoryByOpponent["opp"] = {
    { id = "already-seen-complete", complete = true, oppComment = "gg" },
    { id = "seen-but-still-in-progress", complete = false, oppComment = "" },
  }
  local liveMatches = {
    { id = "already-seen-complete", oppId = "opp", bothPlayed = true, oppComment = "gg" },      -- fully caught up, no badges
    { id = "seen-but-still-in-progress", oppId = "opp", bothPlayed = true, oppComment = "" },    -- just finished since last seen -> ended badge
    { id = "brand-new-finished-match", oppId = "opp", bothPlayed = true, oppComment = "nice!" }, -- never recorded at all -> both badges
    { id = "still-in-progress-elsewhere", oppId = "opp", bothPlayed = false, oppComment = "" },  -- not done -> no badges
  }

  local ended, commented = computeMatchBadges(liveMatches)

  local function has(list, id)
    for _, v in ipairs(list) do if v == id then return true end end
    return false
  end

  check("already-seen-complete: no ended badge", not has(ended, "already-seen-complete"))
  check("seen-but-still-in-progress: gets ended badge", has(ended, "seen-but-still-in-progress"))
  check("brand-new-finished-match: gets ended badge", has(ended, "brand-new-finished-match"))
  check("brand-new-finished-match: gets comment badge", has(commented, "brand-new-finished-match"))
  check("still-in-progress-elsewhere: no badges at all",
    not has(ended, "still-in-progress-elsewhere") and not has(commented, "still-in-progress-elsewhere"))
  check("already-seen-complete: no comment badge (same text already recorded)",
    not has(commented, "already-seen-complete"))
end)

test("recordMatchSnapshot + computeMatchBadges: viewing a match clears its badges going forward", function()
  local snapshot = { id = "m1", oppId = "opp", complete = true, endedAt = os.time(),
    outcome = "you won 10 to 5", localScore = 10, oppScore = 5,
    localWords = {}, oppWords = {}, localComment = "", oppComment = "well played" }
  recordMatchSnapshot(snapshot) -- simulates the player having viewed the end screen

  local ended, commented = computeMatchBadges({
    { id = "m1", oppId = "opp", bothPlayed = true, oppComment = "well played" },
  })
  check("no ended badge after viewing", #ended == 0)
  check("no comment badge for the exact text already seen", #commented == 0)

  -- A later, different comment (e.g. the opponent edited/re-sent -- or more
  -- realistically, this simulates the comment arriving after an earlier
  -- partial view) should re-surface a comment badge even though the match
  -- itself was already marked complete.
  local ended2, commented2 = computeMatchBadges({
    { id = "m1", oppId = "opp", bothPlayed = true, oppComment = "well played, and gg on that last word" },
  })
  check("still no ended badge (already seen complete)", #ended2 == 0)
  check("new comment badge fires", #commented2 == 1 and commented2[1] == "m1")
end)

test("recordMatchSnapshot: clears both badges for a match the instant it's viewed", function()
  endedMatchBadgeIds["m1"] = true
  commentMatchBadgeIds["m1"] = true
  recordMatchSnapshot({ id = "m1", oppId = "opp", complete = true, endedAt = os.time(),
    localScore = 1, oppScore = 1, localWords = {}, oppWords = {}, localComment = "", oppComment = "gg" })
  check("ended badge cleared", endedMatchBadgeIds["m1"] == nil)
  check("comment badge cleared", commentMatchBadgeIds["m1"] == nil)
end)

-- ---- computeNextOwedAction: exchange-aware relay decision -----------------
-- See MULTIPLAYER_DESIGN.md "GameKit exchange trial": a score is sent the
-- instant a round ends, regardless of comment status or turn ownership --
-- via="turn" if I hold it, via="exchange" if I don't.

test("computeNextOwedAction: handshake owed when flagged, overrides everything else", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.needsInitialHandshake = true
  q.players["me"].didPlay = true -- shouldn't matter, handshake wins
  local a = computeNextOwedAction(q, "me", true, os.time())
  check("handshake", a and a.kind == "handshake")
end)

test("computeNextOwedAction: nothing owed before I've finished playing", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  check("nil", computeNextOwedAction(q, "me", true, os.time()) == nil)
end)

test("computeNextOwedAction: score owed via turn the instant I finish, even if my comment isn't decided", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay = true
  q.players["me"].commentDecided = false
  local a = computeNextOwedAction(q, "me", true, os.time())
  check("score via turn", a and a.kind == "score" and a.via == "turn")
end)

test("computeNextOwedAction: score owed via exchange when I don't hold the turn", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay = true
  local a = computeNextOwedAction(q, "me", false, os.time())
  check("score via exchange", a and a.kind == "score" and a.via == "exchange")
end)

test("computeNextOwedAction: comment owed once decided, after score already sent", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].scoreSent = true, true
  q.players["me"].commentDecided = true
  local a = computeNextOwedAction(q, "me", true, os.time())
  check("comment via turn", a and a.kind == "comment" and a.via == "turn")
end)

test("computeNextOwedAction: comment owed via exchange when I don't hold the turn", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].scoreSent = true, true
  q.players["me"].commentDecided = true
  local a = computeNextOwedAction(q, "me", false, os.time())
  check("comment via exchange", a and a.kind == "comment" and a.via == "exchange")
end)

test("computeNextOwedAction: nothing owed once score+comment both sent and opponent unresolved", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].scoreSent = true, true
  q.players["me"].commentDecided, q.players["me"].commentSent = true, true
  check("nil", computeNextOwedAction(q, "me", true, os.time()) == nil)
end)

test("computeNextOwedAction: finalize once both sides fully resolved and I hold the turn", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].scoreSent = true, true
  q.players["me"].commentDecided, q.players["me"].commentSent = true, true
  q.players["opp"].didPlay, q.players["opp"].commentDecided = true, true
  local a = computeNextOwedAction(q, "me", true, os.time())
  check("finalize", a and a.kind == "finalize")
end)

test("computeNextOwedAction: finalize takes priority over a redundant comment send, even if my own commentSent is still false", function()
  -- Regression case: if I'm the second side to become fully resolved (e.g.
  -- decideComment just locked my comment), my own commentSent flag hasn't
  -- been marked true yet (that only happens once a send actually succeeds) --
  -- but since the finalize call carries the same full payload, sending a
  -- "comment" leg first would be a pointless extra round trip.
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].scoreSent = true, true
  q.players["me"].commentDecided = true -- commentSent deliberately left false
  q.players["opp"].didPlay, q.players["opp"].commentDecided = true, true
  local a = computeNextOwedAction(q, "me", true, os.time())
  check("finalize, not comment", a and a.kind == "finalize")
end)

test("computeNextOwedAction: nothing owed if both resolved but I don't hold the turn (not my job to finalize)", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].scoreSent = true, true
  q.players["me"].commentDecided, q.players["me"].commentSent = true, true
  q.players["opp"].didPlay, q.players["opp"].commentDecided = true, true
  check("nil", computeNextOwedAction(q, "me", false, os.time()) == nil)
end)

test("computeNextOwedAction: 'comment' (not finalize) if opponent played but hasn't decided a comment yet", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  q.players["me"].didPlay, q.players["me"].scoreSent = true, true
  q.players["me"].commentDecided = true
  q.players["opp"].didPlay, q.players["opp"].commentDecided = true, false
  local a = computeNextOwedAction(q, "me", true, os.time())
  check("comment via turn", a and a.kind == "comment" and a.via == "turn")
end)

-- ---- applyCommentTimeoutIfExpired -----------------------------------------

test("applyCommentTimeoutIfExpired: locks in a blank decision once the window has passed", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  local now = os.time()
  q.players["me"].didPlay = true
  q.players["me"].commentWindowStartedAt = now - (COMMENT_WINDOW_SECONDS + 1)
  local changed = applyCommentTimeoutIfExpired(q, "me", now)
  check("changed", changed == true)
  check("commentDecided now true", q.players["me"].commentDecided == true)
end)

test("applyCommentTimeoutIfExpired: does nothing while still inside the window", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  local now = os.time()
  q.players["me"].didPlay = true
  q.players["me"].commentWindowStartedAt = now - (COMMENT_WINDOW_SECONDS - 10)
  local changed = applyCommentTimeoutIfExpired(q, "me", now)
  check("unchanged", changed == false)
  check("still undecided", q.players["me"].commentDecided == false)
end)

test("applyCommentTimeoutIfExpired: no-op if already decided", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  local now = os.time()
  q.players["me"].didPlay = true
  q.players["me"].commentDecided = true
  q.players["me"].commentWindowStartedAt = now - (COMMENT_WINDOW_SECONDS + 1000)
  check("no-op", applyCommentTimeoutIfExpired(q, "me", now) == false)
end)

test("applyCommentTimeoutIfExpired: no-op before the player has even played", function()
  local q = freshQMatch("m1", "gameCenter", "me", "opp", "Opp", 4, 3)
  check("no-op", applyCommentTimeoutIfExpired(q, "me", os.time()) == false)
end)

-- ---- endGameRound stamps the comment-timeout clock ------------------------

test("endGameRound: stamps commentWindowStartedAt exactly once for multiplayer", function()
  useTurnBased = true
  tbm.isMyTurn = true
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  score, foundWords = 10, {"A"}
  local before = os.time()
  endGameRound()
  local stampedFirst = currentQMatch.players["local-player-id"].commentWindowStartedAt
  check("stamped at finish time", stampedFirst ~= nil and stampedFirst >= before)

  -- Calling it again (shouldn't happen in practice, but defensively) must
  -- not push the deadline back out.
  endGameRound()
  check("timestamp not reset on a second call",
    currentQMatch.players["local-player-id"].commentWindowStartedAt == stampedFirst)
end)

-- ---- makeQMatchFromGK: a finished-but-unmerged local result must survive --
-- ---- a reload where the server's matchData hasn't caught up yet         --

-- Reproduces: P1 creates a match (turn passes to P2 via the handshake),
-- plays, quits (= finishes their round without holding the turn, so their
-- score goes out via exchange). The exchange reaches P2's device, but
-- nothing merges it into GameKit's own matchData until P2 does something
-- turn-related -- which they haven't, because they're "still in game."
-- Reopening the vs list / the match entry re-decodes fresh from that
-- unmerged server snapshot, which still says P1 hasn't played. Without a
-- fix, P1's own already-finished result gets silently discarded, the match
-- keeps showing "your move", and P1 can re-enter and replay it indefinitely.
test("makeQMatchFromGK: my own finished result survives a reload where the opponent hasn't merged my exchange yet", function()
  useTurnBased = true
  tbm.isMyTurn = false  -- the handshake already passed the turn to the opponent
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  score, foundWords = 7, {"CAT"}
  endGameRound()  -- quit/finished; sent via exchange since I don't hold the turn

  check("finished locally", currentQMatch.players["local-player-id"].didPlay == true)
  check("snapshot recorded", finishedAwaitingDecisionByMatchId["m1"] ~= nil)

  local fakeGkMatch = {
    matchID = "m1",
    participants = {
      { player = { isLocalPlayer = false, gamePlayerID = "opp", alias = "Opp" } },
    },
  }
  -- What a fresh GameKit reload still looks like: the opponent hasn't
  -- merged my exchange, so the server's own matchData still has me at
  -- didPlay=false/score=0 -- stale, but it's genuinely what the server has.
  local staleDataTable = {
    boardSize = 4,
    minWordLen = 3,
    players = {
      ["local-player-id"] = { didPlay = false, score = 0, words = {} },
      ["opp"]              = { didPlay = false },
    },
  }

  local reopened = makeQMatchFromGK(fakeGkMatch, staleDataTable)

  check("my own finished result is not discarded by a stale reload",
    reopened.players["local-player-id"].didPlay == true,
    "didPlay="..tostring(reopened.players["local-player-id"].didPlay))
  check("my score survives the reload too",
    reopened.players["local-player-id"].score == 7,
    "score="..tostring(reopened.players["local-player-id"].score))
  check("opponent's (genuinely unplayed) slot is unaffected",
    reopened.players["opp"].didPlay == false)
end)

-- ---- The four visible symptoms of the bug above, checked explicitly -----
-- (badge, status text, no replay, correct partial end screen) rather than
-- just trusting that the data-layer fix implies all of them.

test("vs entry: I played, opponent hasn't yet -- no badge, status reads 'waiting', not 'your move'", function()
  check("needsAction false once I've played (even though match isn't ended)",
    computeVsEntryNeedsAction(false, true, false) == false)
  check("status text defers to the opponent",
    vsStatusTextForEntry({ ended = false, localDidPlay = true, oppName = "Opp" }) == "Waiting for Opp")

  -- Non-regression: the pre-fix case (I haven't played) must still read as
  -- actionable -- this bug was never "nothing is ever actionable".
  check("needsAction true before I've played",
    computeVsEntryNeedsAction(false, false, false) == true)
  check("status text still says it's my move before I've played",
    vsStatusTextForEntry({ ended = false, localDidPlay = false, oppName = "Opp" }) == "Your move")
end)

test("enterQMatch: reopening my own just-finished match shows the end screen with only my side known, never restarts play", function()
  useTurnBased = true
  tbm.isMyTurn = false  -- handshake already passed the turn to the opponent
  currentQMatch = freshQMatch("m1", "gameCenter", "local-player-id", "opp", "Opp", 4, 3)
  score, foundWords = 7, {"CAT"}
  endGameRound()  -- I quit; score sent via exchange since I don't hold the turn

  -- Mirrors the real flow: closing the end screen returns to the menu
  -- (startSeasonTransition eventually sets state = STATE_MENU) well before
  -- the player taps back into this match from the vs list.
  state = STATE_MENU

  local fakeGkMatch = {
    matchID = "m1",
    participants = {
      { player = { isLocalPlayer = false, gamePlayerID = "opp", alias = "Opp" } },
    },
  }
  -- Server still hasn't merged my exchange -- same stale snapshot as above.
  local staleDataTable = {
    boardSize = 4,
    minWordLen = 3,
    players = {
      ["local-player-id"] = { didPlay = false, score = 0, words = {} },
      ["opp"]              = { didPlay = false },
    },
  }
  tbm:_setCurrentMatch(fakeGkMatch, "test-reopen")  -- mirrors vsOpenMatchEntry

  local reopenedQ = makeQMatchFromGK(fakeGkMatch, staleDataTable)
  enterQMatch(reopenedQ)

  check("does not restart gameplay", state == STATE_END, "state="..tostring(state))
  check("my own score is shown", score == 7, "score="..tostring(score))
  check("opponent's score is NOT fabricated as 0-and-final",
    currentQMatch.players["opp"].didPlay == false)
  check("opponent score reads as 0 only because they haven't played, not as a real result",
    opponentScore == 0)
end)

-- =========================================================== summary =====

print(string.format("\n%d passed, %d failed", pass, fail))
if #failures > 0 then
  print(table.concat(failures, "\n"))
  os.exit(1)
end
