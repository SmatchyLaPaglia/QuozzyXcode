-- Stub Codea/GameKit environment so real Quozzy.codea/*.lua files can be
-- `dofile`d and exercised outside the Codea runtime. Every file loaded this
-- way is production code, unmodified — only the environment around it is
-- fake. Keep stubs explicit (no catch-all metatable fallback): a missing
-- global should error loudly so a real new dependency gets added here on
-- purpose, not silently no-op.

local ROOT = (...) or "."
local PROJECT_DIR = ROOT .. "/Quozzy.codea/"

json = dofile((ROOT) .. "/tests/json_mini.lua")

-- ---- Codea persistence built-ins (in-memory per test run) ----
local _projectStore = {}
local _localStore = {}

function saveProjectData(key, val) _projectStore[key] = val end
function readProjectData(key) return _projectStore[key] end
function saveLocalData(key, val) _localStore[key] = val end
function readLocalData(key) return _localStore[key] end

function _test_resetPersistence()
  _projectStore = {}
  _localStore = {}
end

-- ---- logging ----
function devLog(...) end -- silence by default; tests can override to print

-- ---- state machine constants ----
STATE_MENU  = "MENU"
STATE_READY = "READY"
STATE_PLAY  = "PLAY"
STATE_END   = "END"
state = STATE_MENU

-- ---- misc globals GameCenter.lua / qMatch_qPlayer.lua touch ----
boardSize = 4
MIN_WORD_LEN = 3
score = 0
opponentScore = 0
foundWords = {}
foundWordsSet = {}
currentQMatch = nil
useTurnBased = false
currentMatchID = nil
currentOpponentID = nil
opponentAlias = "Opponent"
timeOptions = {60, 90, 120}
timeOptionIndex = 1
qPlayersById = {}
qPlayersList = {}
endScreenSpeechBalloonsVisible = false
endScreenCommentDraft = ""
awaitingHandshakeSend = false
pendingHandshakeResendReason = nil

function currentFoundWords() return foundWords or {} end

-- ---- no-op stand-ins for other-file UI/board functions not under test ----
function defineAvatars() end
function defineAvatarsAfterMicrodelay() end
function generateBoard(q) end
function resetWordListScroll() end
function rotatePlayAgainLabel() end
function endReplayMatchmakingBusy() end
function persistLastMatchReplaySettingsFromQMatch(q) end
function updateOpponentRecord(outcome) end
function ensureAvatarForOpponent(id, name) return nil end
function loadLocalPlayerAvatar() end
function storePendingTurnMatch(q) end
function updateMatchBadgeStatus() end
function inferBoardSizeFromTiles(tiles) return nil end
function areBoardTilesValidForSize(tiles, n)
  return type(tiles) == "table" and n ~= nil and #tiles == n * n
end
function buildRecordSyncForOpponent(oppId, alias, senderId, result) return nil end
function reconcileCompetitiveWordResults(wordsA, wordsB)
  return { entriesA = wordsA, scoreA = #wordsA, entriesB = wordsB, scoreB = #wordsB }
end

-- ---- fake `objc` / GameKit surface ----
objc = {
  GKLocalPlayer = { localPlayer = { gamePlayerID = "local-player-id", playerID = "local-player-id" } },
  enum = { GKTurnBasedParticipantStatus = {} },
}

-- ---- fake `tween` with a manually-flushable delay queue, so tests control
-- retry-backoff timing deterministically instead of racing real time. ----
local _tweenQueue = {}
tween = {
  delay = function(seconds, fn)
    _tweenQueue[#_tweenQueue+1] = fn
  end,
}
function _test_flushTweens()
  local q = _tweenQueue
  _tweenQueue = {}
  for _, fn in ipairs(q) do fn() end
end
function _test_pendingTweenCount() return #_tweenQueue end

-- ---- FakeTBM: mirrors the real CTBM's observable contract from
-- CodeaTurnBasedMatches.lua:806-855 — endTurnWithDataTable requires
-- isMyTurn==true, and on success clears both currentMatch and isMyTurn. ----
local FakeTBM = {}
FakeTBM.__index = FakeTBM

function FakeTBM.new()
  return setmetatable({
    isMyTurn = false,
    currentMatch = nil,
    localPlayer = { playerID = "local-player-id", authenticated = true },
    sentCalls = {},       -- every successful endTurnWithDataTable payload
    wonCalls = {}, lostCalls = {}, tiedCalls = {}, -- finalize calls
    failNextSends = 0,    -- how many upcoming sends should call onError instead
  }, FakeTBM)
end

function FakeTBM:endTurnWithDataTable(t, onError)
  if not self.isMyTurn then
    if onError then onError({ localizedDescription = "not my turn" }) end
    return
  end
  if self.failNextSends and self.failNextSends > 0 then
    self.failNextSends = self.failNextSends - 1
    if onError then onError({ localizedDescription = "simulated failure" }) end
    return
  end
  self.sentCalls[#self.sentCalls+1] = t
  self.currentMatch = nil
  self.isMyTurn = false
end

function FakeTBM:_getEndStateFromMatch(m) return nil end
function FakeTBM:_setCurrentMatch(m, reason) self.currentMatch = m end
function FakeTBM:localPlayerWon(t) self.wonCalls[#self.wonCalls+1] = t end
function FakeTBM:localPlayerLost(t) self.lostCalls[#self.lostCalls+1] = t end
function FakeTBM:localPlayerTied(t) self.tiedCalls[#self.tiedCalls+1] = t end

_G.FakeTBM = FakeTBM

-- ---- source loader ----
function loadSource(relPath)
  local chunk = assert(loadfile(PROJECT_DIR .. relPath))
  return chunk()
end
