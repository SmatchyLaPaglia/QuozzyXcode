-- Daily solo leaderboard (Game Center, recurring leaderboard).
-- The leaderboard itself lives in App Store Connect: a RECURRING leaderboard with ID
-- LEADERBOARD_ID, 24-hour reset, high-score-first. Apple handles the daily reset (UTC
-- start time chosen there) and keeps only each player's best score per instance.
-- Only solo 5x5 / 4-letter-minimum "leaderboard games" submit scores.

LEADERBOARD_ID = "solo_daily_5x5_4"
LEADERBOARD_BOARD_SIZE = 5
LEADERBOARD_MIN_WORD_LEN = 4

-- A leaderboard game temporarily forces 5x5/4 without persisting; the player's own menu
-- settings are stashed here and put back the next time the menu draws.
leaderboardSavedSettings = leaderboardSavedSettings or nil

-- Solo button tap: pick between a regular round and a leaderboard round.
-- Tapping anywhere outside the buttons cancels (generic alert behavior).
function openSoloChoiceDialog()
  showGenericAlert({
    message = "Play at your current settings, or a daily leaderboard game (5×5 board, 4-letter minimum)?\n\ntap outside to cancel",
    btnFont = 17,
    margin = 16, panelWidthFrac = 0.96, panelMaxW = 640,
    buttons = {
      { text = "current settings", isPrimary = false, callback = function()
          setTurnBasedEnabled(false)
          startRoundFromCurrentSettings()
        end },
      { text = "leaderboard", isPrimary = true, callback = function()
          startLeaderboardGame()
        end },
    },
  })
end

function startLeaderboardGame()
  if not gcIsAuthenticated() then
    openGCSignInOverlay()
    return
  end
  if not leaderboardSavedSettings then
    leaderboardSavedSettings = { boardSize = boardSize, minWordLen = MIN_WORD_LEN }
  end
  boardSize = LEADERBOARD_BOARD_SIZE
  MIN_WORD_LEN = LEADERBOARD_MIN_WORD_LEN
  setTurnBasedEnabled(false)
  startRoundFromCurrentSettings()
  if currentQMatch then currentQMatch.leaderboardGame = true end
end

-- Called from drawMenu's state block: the menu is back, so give the player their settings back.
function restoreSettingsAfterLeaderboardGame()
  if not leaderboardSavedSettings then return end
  boardSize = leaderboardSavedSettings.boardSize
  MIN_WORD_LEN = leaderboardSavedSettings.minWordLen
  leaderboardSavedSettings = nil
end

-- Called from endGameRound for a finished solo leaderboard game.
function submitLeaderboardScore(finalScore)
  if not (objc and objc.GKLeaderboard and gcIsAuthenticated()) then return end
  local ok, err = pcall(function()
    local lp = objc.GKLocalPlayer.localPlayer
    -- Network call: the handler fires later, so it must only hand off (never nil here —
    -- Apple may invoke the block). See callback rule in CLAUDE.md.
    objc.GKLeaderboard:submitScore_context_player_leaderboardIDs_completionHandler_(
      finalScore, 0, lp, { LEADERBOARD_ID },
      function(oError) handOff(function(oError)
        devLog("leaderboard: submit done, error=", tostring(oError))
      end, oError) end)
  end)
  devLog("leaderboard: submit score", finalScore, "ok=", tostring(ok), ok and "" or tostring(err))
end

local leaderboardDelegate = nil

-- Present Apple's leaderboard UI. Call from touched()/draw() only (UIKit work).
function showLeaderboard()
  markLeaderboardSeen()
  if not gcIsAuthenticated() then
    if state == STATE_MENU then openGCSignInOverlay() end
    return
  end
  local presenter = (tbm and tbm.viewController) or objc.viewer
  if not (objc and objc.GKGameCenterViewController and presenter) then return end
  local ok, err = pcall(function()
    local vc = objc.GKGameCenterViewController:alloc():initWithLeaderboardID_playerScope_timeScope_(
      LEADERBOARD_ID, 0, 0)   -- scope Global=0, time Today=0
    if not leaderboardDelegate then
      local Delegate = objc.class("LeaderboardGCDelegate")
      function Delegate:gameCenterViewControllerDidFinish_(o__vc) handOff(function(o__vc)
        local p = (tbm and tbm.viewController) or objc.viewer
        if p then p:dismissModalViewControllerAnimated_(true, nil) end
      end, o__vc) end
      leaderboardDelegate = Delegate()
    end
    vc.gameCenterDelegate = leaderboardDelegate
    presenter:presentModalViewController_animated_(vc, true)
  end)
  if not ok then devLog("leaderboard: present failed", tostring(err)) end
end

--############################################################
-- "Friends posted something new" badge
--############################################################
-- Game Center sends no push for leaderboard changes, so while the menu is up we poll every
-- LB_POLL_INTERVAL seconds: friends list -> leaderboard object -> those friends' entries
-- (loadEntriesForPlayers, so no NSRange). Each entry is keyed "playerID:score"; any key not in
-- the persisted "seen" set means something new. Tapping a leaderboard button marks the latest
-- fetch as seen (markLeaderboardSeen). Every callback below only hands off; the work runs in draw().

LB_POLL_INTERVAL = 60
LB_SEEN_KEY = "LeaderboardSeen"

leaderboardHasUnseen = leaderboardHasUnseen or false
local lbLatestKeys = nil        -- set {["id:score"]=true} from the last successful fetch
local lbSeenKeys = nil          -- persisted set
local lbBusy, lbBusySince = false, 0
local lbLastPollAt = -1e9

local function lbLoadSeen()
  if lbSeenKeys then return end
  lbSeenKeys = {}
  local ok, list = pcall(function() return json.decode(readLocalData(LB_SEEN_KEY) or "[]") end)
  if ok and type(list) == "table" then
    for _, k in ipairs(list) do lbSeenKeys[k] = true end
  end
end

local function lbRecomputeUnseen()
  lbLoadSeen()
  local any = false
  for k in pairs(lbLatestKeys or {}) do
    if not lbSeenKeys[k] then any = true break end
  end
  leaderboardHasUnseen = any
end

function markLeaderboardSeen()
  lbLoadSeen()
  for k in pairs(lbLatestKeys or {}) do lbSeenKeys[k] = true end
  local list = {}
  for k in pairs(lbSeenKeys) do list[#list + 1] = k end
  saveLocalData(LB_SEEN_KEY, json.encode(list))
  leaderboardHasUnseen = false
end

local function lbCount(arr)
  if not arr then return 0 end
  if type(arr) == "table" then return #arr end
  local ok, n = pcall(function() return tonumber(arr.count) or tonumber(arr:count()) or 0 end)
  return ok and n or 0
end

local function lbGet(arr, i)
  if type(arr) == "table" then return arr[i] end
  local ok, v = pcall(function() return arr:objectAtIndex_(i - 1) end)
  return ok and v or nil
end

local function lbDone(why)
  lbBusy = false
  if why then devLog("leaderboard poll:", why) end
end

local function lbOnEntries(oEntries, oError)
  if oError then return lbDone("entries error " .. tostring(oError.localizedDescription)) end
  local keys = {}
  for i = 1, lbCount(oEntries) do
    local e = lbGet(oEntries, i)
    local p = e and e.player
    local id = p and (p.gamePlayerID or p.playerID)
    if id then keys[tostring(id) .. ":" .. tostring(math.floor(tonumber(e.score) or 0))] = true end
  end
  lbLatestKeys = keys
  lbRecomputeUnseen()
  lbDone("friend entries=" .. lbCount(oEntries) .. " unseen=" .. tostring(leaderboardHasUnseen))
end

local lbFriends = nil

local function lbOnFriends(oPlayers, oError)
  if oError or lbCount(oPlayers) == 0 then
    lbLatestKeys = {}
    lbRecomputeUnseen()
    return lbDone("no friends " .. tostring(oError and oError.localizedDescription))
  end
  lbFriends = oPlayers
  objc.GKLeaderboard:loadLeaderboardsWithIDs_completionHandler_({ LEADERBOARD_ID },
    function(oBoards, oError2) handOff(function(oBoards, oError2)
      if oError2 or lbCount(oBoards) == 0 then return lbDone("no leaderboard " .. tostring(oError2 and oError2.localizedDescription)) end
      local board = lbGet(oBoards, 1)
      local ok, err = pcall(function()
        board:loadEntriesForPlayers_timeScope_completionHandler_(lbFriends, 0,
          function(oLocal, oEntries, oError3) handOff(function(oEntries, oError3)
            lbOnEntries(oEntries, oError3)
          end, oEntries, oError3) end)
      end)
      if not ok then lbDone("entries call failed " .. tostring(err)) end
    end, oBoards, oError2) end)
end

local function lbStart()
  lbBusy, lbBusySince, lbLastPollAt = true, ElapsedTime, ElapsedTime
  local lp = objc.GKLocalPlayer and objc.GKLocalPlayer.localPlayer
  local ok, err = pcall(function()
    lp:loadFriendPlayersWithCompletionHandler_(function(oPlayers, oError)
      handOff(function(oPlayers, oError) lbOnFriends(oPlayers, oError) end, oPlayers, oError)
    end)
  end)
  if not ok then lbDone("friends call failed " .. tostring(err)) end
end

-- Called every frame from the menu block in Main.lua.
function leaderboardBadgePoll()
  if state ~= STATE_MENU or not gcIsAuthenticated() then return end
  if lbBusy and ElapsedTime - lbBusySince > 30 then lbBusy = false end   -- a lost callback must not wedge polling
  if lbBusy or ElapsedTime - lbLastPollAt < LB_POLL_INTERVAL then return end
  lbLoadSeen()
  lbStart()
end

-- Dot on the menu's Records button (rect = menuHitRects.records).
function drawLeaderboardRecordsBadge(rect)
  if not rect or not leaderboardHasUnseen then return end
  if state ~= STATE_MENU or badgeSuppressed() then return end
  local r = math.max(8, math.min(rect.w, rect.h) * 0.12)
  drawRedBadgeDot(rect.cx + rect.w * 0.5 - r * 0.6, rect.cy + rect.h * 0.5 - r * 0.6, r)
end
