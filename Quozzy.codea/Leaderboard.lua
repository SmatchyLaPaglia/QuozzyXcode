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
    buttons = {
      { text = "my settings", isPrimary = false, callback = function()
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
