--[[require(asset.documents.CodeaTurnBasedMatches)

local function bootstrapCTBM()
  local attempts = {}
  local function tryLoadAssetPath(assetPath, label)
    local source = readText(assetPath)
    if not source or #source == 0 then
      attempts[#attempts + 1] = label .. ": missing source at " .. tostring(assetPath)
      return false
    end

    local chunk, loadErr = load(source, label)
    if not chunk then
      attempts[#attempts + 1] = label .. ": compile error: " .. tostring(loadErr)
      return false
    end

    local okChunk, errChunk = pcall(chunk)
    if not okChunk then
      attempts[#attempts + 1] = label .. ": runtime error: " .. tostring(errChunk)
      return false
    end

    return true
  end

  -- Exported app primary path: keep dependency inside this .codea bundle.
  local inProjectPath = asset .. "CodeaTurnBasedMatches.lua"
  if tryLoadAssetPath(inProjectPath, "in-project CTBM") then return true end

  -- Keep Codea-editor behavior first for local development.
  local okDocs, errDocs = pcall(require, asset.documents.CodeaTurnBasedMatches)
  if okDocs then return true end
  attempts[#attempts + 1] = "asset.documents.CodeaTurnBasedMatches: " .. tostring(errDocs)

  -- Legacy fallback kept for compatibility with prior layout assumptions.
  local legacyBundledPath = asset .. "Assets/CodeaTurnBasedMatches.codea/CodeaTurnBasedMatches.lua"
  if tryLoadAssetPath(legacyBundledPath, "legacy bundled CTBM") then return true end

  devLog("CTBM bootstrap failed")
  for i = 1, #attempts do
    devLog("  " .. attempts[i])
  end

  error("Cannot load CodeaTurnBasedMatches dependency")
end
]]

------------------------------------------------------------
-- DIAGNOSTIC LOGGING SYSTEM
-- All print() and devLog() output reaches:
--   1. Codea console (via native print)
--   2. Xcode / system log (via objc.log, prefix 🧑‍💻)
--   3. Persistent ring buffer in saveLocalData (key "DevLogBuffer", JSON array)
-- Read from outside the sim with:
--   log show: xcrun simctl spawn <SIM> log show --last Ns --predicate 'process == "Quozzy"'
--   plist:    plutil -p <container>/Library/Preferences/com.jessewonderclark.quozzyseasons.plist | grep DevLogBuffer
------------------------------------------------------------

local _nativePrint = print  -- captured before we replace the global

DEV_LOG_BUFFER = DEV_LOG_BUFFER or {}
DEV_LOG_BUFFER_MAX = 200
DEV_LOG_FLUSH_INTERVAL = 1.0  -- seconds between saveLocalData flushes
DEV_LOG_TIME_SINCE_FLUSH = DEV_LOG_TIME_SINCE_FLUSH or 0

local function _appendToLogBuffer(msg)
  DEV_LOG_BUFFER[#DEV_LOG_BUFFER + 1] = msg
  if #DEV_LOG_BUFFER > DEV_LOG_BUFFER_MAX then
    table.remove(DEV_LOG_BUFFER, 1)
  end
end

function _flushLogBuffer()
  local ok, encoded = pcall(json.encode, DEV_LOG_BUFFER)
  if ok then
    saveLocalData("DevLogBuffer", encoded)
  end
end

function devLog(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  local msg = table.concat(parts, " ")
  _nativePrint(msg)                       -- Codea console
  _appendToLogBuffer(os.date("!%H:%M:%S") .. " " .. msg)  -- ring buffer with timestamp
  if objc and objc.log then
    objc.log("🧑‍💻 " .. msg)              -- Xcode / system log
  end
end

print = devLog  -- all print() calls now reach all three channels

--bootstrapCTBM()

viewer.mode = FULLSCREEN
FORCE_RED_BOOT_SCREEN = false
FORCE_COMMENT_PHASE_BOOT_PREVIEW = false
AUTO_SHOW_DEBUG_ALERT = false  -- auto-show debug alert on launch for layout testing
-- AFTER
MIN_WORD_LEN = 3
SOWPODS_URL = "https://people.sc.fsu.edu/~jburkardt/datasets/words/sowpods.txt"
SOWPODS_LOCAL_NAME = asset .. "SOWPODS.txt"

recordsOverlay = false
recordsScrollY = 0
recordsScrollTouchId = nil
recordsScrollPrevY = 0

showInfoOverlay = false
colorInspectorOverlay = false

-- Deliberate ambient default font for the whole app (2026-08-09): originally the font
-- used only on the not-yet-typed-in speech-balloon placeholder (EndScreenFP.lua's
-- positionCommentField), which used to LEAK into everything drawn afterward each frame
-- because that one call site never wrapped its font() in pushStyle()/popStyle(). Now set
-- deliberately here, once per frame (see draw()), so anything that doesn't explicitly
-- pin its own font() picks this up automatically — same effect the leak had, just
-- intentional and consistent from frame 1 instead of only after the composer first ran.
-- Explicit exceptions (each already pins its own font, so they're unaffected by this):
-- HaikuMenu.lua (main screen), OverlayPanels.lua's drawInfoOverlay (info panel),
-- EndScreenFP.lua's drawSpeechBalloon (balloon text once typed), and dice/tile letters
-- (Board.lua drawBoard, Helpers.lua drawBoardPreview, RecordsUI.lua
-- drawBoardThumbnailFromTiles — each pinned to GLOBAL_UI_FONT_DICE below).
GLOBAL_UI_FONT      = "HelveticaNeue-BoldItalic"
GLOBAL_UI_FONT_DICE = "Helvetica"  -- what dice/tile letters rendered as before this change (no font() was ever set for them)
BALLOON_MOCKUP_DEV = false  -- dev-only: true auto-opens the balloon mockup at launch (and forces teal).
SHOW_DEBUG_BUTTON = false  -- dev-only: true shows the 🐛 button on the main menu (opens the balloon mockup). FALSE for shipped builds.
balloonMockupOverlay = BALLOON_MOCKUP_DEV == true
mockupScenarioIndex = mockupScenarioIndex or 1  -- which of the 7 BALLOON_MOCKUP_STATES is showing
mockupChipRects = nil           -- hit rects for the 7 scenario chips, set each frame
mockupCloseBtnRect = nil        -- hit rect for the close button

-- Balloon color picker debug screen (used 2026-08-10 to pick "Grid Wash" as the
-- permanent balloon color scheme — see balloonColorSchemeIndex, EndScreenFP.lua).
-- Not wired to the 🐛 button by default anymore (see HaikuMenu.lua debugDialog);
-- kept around as opt-in QA tooling for re-tuning later — set balloonColorPickerOverlay
-- = true directly (e.g. from debugDialog) to reopen it.
balloonColorPickerOverlay = false
colorPickerScrollY        = 0
colorPickerScrollTouchId  = nil
colorPickerScrollPrevY    = 0
colorPickerTouchStartX    = 0
colorPickerTouchStartY    = 0
colorPickerTouchMoved     = false
colorPickerRowRects       = nil  -- hit rects for the 10 scheme rows, set each frame
colorPickerGeom           = nil  -- close/preview button rects + list viewport, set each frame

STATE_MENU   = "menu"
STATE_PLAY   = "play"
STATE_END    = "end"
STATE_READY  = "ready"  

previewMode = nil              -- nil, "board", or "end"
previewSavedEndState = nil     -- used to restore real game state after end-preview

state = STATE_MENU

boardSize = 4
timeOptions = {30, 180}
timeOptionIndex = 2
timeRemaining = timeOptions[timeOptionIndex]
quitButtonRect = quitButtonRect or nil

local BOARD_SIZE_KEY = "SelectedBoardSize"
local MIN_WORD_LEN_KEY = "SelectedMinWordLen"
local LAST_MATCH_REPLAY_KEY = "LastMatchReplayV1"
local LAST_MATCH_REPLAY_AVATAR_KEY = "QB_LastMatchReplayAvatar"
local LAST_VIEWED_FINISHED_MATCH_ID_KEY = "LastViewedFinishedMatchID"
local AUTO_OPEN_FINISHED_MATCH_ENABLED = true
local INSTALL_SIGNATURE_KEY = "LastInstalledBundleSignature"
local INSTALL_EPOCH_KEY = "LastInstalledAtEpoch"
local INSTALL_TEXT_KEY = "LastInstalledAtText"
local LOADING_ART_VERSION_KEY = "LoadingArtVersion"
local LOADING_ART_VERSION = 7
local LOADING_ART_NAME = "Loading_QuozzySeasons"
local ENABLE_LOADING_ART_GENERATOR = false -- set true temporarily when you want to regenerate
local MENU_CAPTURE_NAME = "MenuFrameCapture"
menuFrameCapturePending = menuFrameCapturePending == nil and false or menuFrameCapturePending
loadingArtGenerationPending = loadingArtGenerationPending == nil and ENABLE_LOADING_ART_GENERATOR or loadingArtGenerationPending
lastMatchReplaySettings = lastMatchReplaySettings or nil
lastMatchReplayAvatar = lastMatchReplayAvatar or nil
replayMatchmakingBusy = replayMatchmakingBusy or false
replayMatchmakingBusyMessage = replayMatchmakingBusyMessage or "matching..."
appWasActiveLastFrame = appWasActiveLastFrame == nil and true or appWasActiveLastFrame
finishedMatchAutoCheckInFlight = finishedMatchAutoCheckInFlight or false
finishedMatchAutoCheckPendingReason = finishedMatchAutoCheckPendingReason or nil
pendingRematchAfterEndScreenExit = pendingRematchAfterEndScreenExit or false
awaitingHandshakeSend = awaitingHandshakeSend or false
pendingHandshakeResendReason = pendingHandshakeResendReason or nil

local function _sanitizeBoardSize(v)
  v = math.floor(tonumber(v) or 4)
  if v ~= 4 and v ~= 5 and v ~= 6 then return 4 end
  return v
end

local function _sanitizeMinWordLen(v)
  v = math.floor(tonumber(v) or 3)
  if v < 3 then v = 3 end
  if v > 6 then v = 6 end
  return v
end

function persistGameplaySettings()
  boardSize = _sanitizeBoardSize(boardSize)
  MIN_WORD_LEN = _sanitizeMinWordLen(MIN_WORD_LEN)
  saveLocalData(BOARD_SIZE_KEY, boardSize)
  saveLocalData(MIN_WORD_LEN_KEY, MIN_WORD_LEN)
end

function loadGameplaySettings()
  local savedBoardSize = readLocalData(BOARD_SIZE_KEY)
  local savedMinWordLen = readLocalData(MIN_WORD_LEN_KEY)
  boardSize = _sanitizeBoardSize(savedBoardSize or boardSize)
  MIN_WORD_LEN = _sanitizeMinWordLen(savedMinWordLen or MIN_WORD_LEN)
end

function getLastMatchReplaySettings()
  if lastMatchReplaySettings ~= nil then return lastMatchReplaySettings end
  local raw = readLocalData(LAST_MATCH_REPLAY_KEY)
  if not raw or raw == "" then
    lastMatchReplaySettings = false
    return nil
  end
  local ok, decoded = pcall(json.decode, raw)
  if ok and type(decoded) == "table" then
    lastMatchReplaySettings = decoded
    return decoded
  end
  lastMatchReplaySettings = false
  return nil
end

function getLastMatchReplayAvatar()
  if lastMatchReplayAvatar ~= nil then return lastMatchReplayAvatar end
  local ok, img = pcall(function()
    return readImage("Documents:" .. LAST_MATCH_REPLAY_AVATAR_KEY)
  end)
  if ok and img then
    lastMatchReplayAvatar = img
    return img
  end
  lastMatchReplayAvatar = false
  return nil
end

function persistLastMatchReplaySettingsFromQMatch(q)
  if not q or not q.players then return false end
  local myId = localPID and localPID() or nil
  if not myId then return false end

  local oppId = q.otherId or q.opponentId or currentOpponentID
  if not oppId or oppId == "" then
    for pid, _ in pairs(q.players) do
      if pid ~= myId then
        oppId = pid
        break
      end
    end
  end
  if not oppId or oppId == "" then return false end

  local oppName = q.otherName or q.opponentName or opponentAlias or ""
  if oppName == "" then
    local qp = qPlayersById and qPlayersById[oppId]
    oppName = (qp and qp.name) or ""
  end

  local payload = {
    matchId = q.id,
    opponentId = oppId,
    opponentPlayerID = q.opponentPlayerID or nil,
    opponentName = oppName,
    boardSize = _sanitizeBoardSize(q.boardSize or boardSize),
    minWordLen = _sanitizeMinWordLen(q.minWordLen or MIN_WORD_LEN),
    updatedAt = os.time(),
  }

  local avatar = nil
  if getOpponentRecordAvatar then
    avatar = getOpponentRecordAvatar(oppId)
  end
  if (not avatar) and qPlayersById and qPlayersById[oppId] then
    avatar = qPlayersById[oppId].avatar
  end

  if avatar then
    local okSave = pcall(function()
      saveImage("Documents:" .. LAST_MATCH_REPLAY_AVATAR_KEY, avatar)
    end)
    if okSave then
      lastMatchReplayAvatar = avatar
    end
  end

  local okEncode, s = pcall(json.encode, payload)
  if okEncode and s then
    saveLocalData(LAST_MATCH_REPLAY_KEY, s)
    lastMatchReplaySettings = payload
    return true
  end
  return false
end

function updateLastMatchReplayAvatarForOpponent(oppId, avatarImage)
  if not oppId or not avatarImage then return false end
  local settings = getLastMatchReplaySettings()
  if not settings or settings.opponentId ~= oppId then return false end
  local okSave = pcall(function()
    saveImage("Documents:" .. LAST_MATCH_REPLAY_AVATAR_KEY, avatarImage)
  end)
  if okSave then
    lastMatchReplayAvatar = avatarImage
    return true
  end
  return false
end

function beginReplayMatchmakingBusy(message)
  devLog("DBG_BUSY beginReplayMatchmakingBusy: set true")
  replayMatchmakingBusy = true
  replayMatchmakingBusyMessage = message or "matching..."
end

function endReplayMatchmakingBusy()
  devLog("DBG_BUSY endReplayMatchmakingBusy: cleared")
  replayMatchmakingBusy = false
end

local function _showGenericMatchmaker()
  endReplayMatchmakingBusy()
  if not (tbm and tbm.showMatchmaker) then
    openGCMatchmakerErrorOverlay("Game Center is unavailable in this build or environment.")
    return
  end
  local ok, err = pcall(function()
    tbm:showMatchmaker()
  end)
  if not ok then
    openGCMatchmakerErrorOverlay(err)
  end
end

local function _tryRematchForLastReplay(settings)
  devLog("DBG_PA _tryRematch: entry opponentPlayerID=", tostring(settings and settings.opponentPlayerID), "opponentId=", tostring(settings and settings.opponentId))
  if not settings or not settings.opponentId then
    devLog("DBG_PA _tryRematch: no settings/opponentId -> generic matchmaker")
    _showGenericMatchmaker()
    return
  end
  local GKTurnBasedMatch = objc and objc.GKTurnBasedMatch
  if not GKTurnBasedMatch then
    devLog("DBG_PA _tryRematch: no GKTurnBasedMatch -> generic matchmaker")
    _showGenericMatchmaker()
    return
  end

  if tbm then
    tbm.pendingRequestedBoardSize  = settings.boardSize  or boardSize
    tbm.pendingRequestedMinWordLen = settings.minWordLen or MIN_WORD_LEN
  end

  -- Use deprecated playerID with loadPlayersForIdentifiers (the only API that
  -- resolves a stored ID string back to a live GKPlayer object). gamePlayerID
  -- ("A:_..." / "G:...") returns 0 results from this call; playerID works.
  local lookupId = settings.opponentPlayerID or settings.opponentId
  local ok = pcall(function()
    devLog("DBG_PA _tryRematch: calling loadPlayersForIdentifiers, id=", lookupId)
    objc.GKPlayer:loadPlayersForIdentifiers_withCompletionHandler_(
      {lookupId},
      function(o__players, o__err)
        objc.async(function()
          devLog("DBG_PA _tryRematch: loadPlayers callback, err=", tostring(o__err), "count=", tostring(o__players and #o__players))
          if o__err then
            devLog("Play Again: load player error", o__err.localizedDescription or tostring(o__err))
            _showGenericMatchmaker()
            return
          end
          local gkOpponent = o__players and #o__players > 0 and o__players[1] or nil
          devLog("DBG_PA _tryRematch: gkOpponent=", tostring(gkOpponent))
          if not gkOpponent then
            devLog("Play Again: opponent not found for id", lookupId)
            _showGenericMatchmaker()
            return
          end
          devLog("DBG_PA _tryRematch: calling findMatchForRequest")
          local request = objc.GKMatchRequest()
          request.minPlayers = 2
          request.maxPlayers = 2
          request.recipients  = {gkOpponent}
          GKTurnBasedMatch:findMatchForRequest_withCompletionHandler_(
            request,
            function(o__match, o__matchErr)
              objc.async(function()
                devLog("DBG_PA _tryRematch: findMatch callback, err=", tostring(o__matchErr), "match=", tostring(o__match))
                if o__matchErr or not o__match then
                  devLog("Play Again: create match failed", o__matchErr and o__matchErr.localizedDescription or "nil match")
                  _showGenericMatchmaker()
                  return
                end
                devLog("Play Again: match created", o__match.matchID or "?")
                endReplayMatchmakingBusy()
                if tbm and tbm._setCurrentMatch then
                  tbm:_setCurrentMatch(o__match, "menu-play-again")
                end
                local dataTable = nil
                if tbm and tbm._matchWithNSDataToDataTable then
                  dataTable = tbm:_matchWithNSDataToDataTable(o__match)
                end
                local q = makeQMatchFromGK and makeQMatchFromGK(o__match, dataTable) or nil
                if q and enterQMatch then
                  enterQMatch(q)
                else
                  devLog("Play Again: unable to build qMatch")
                end
              end)
            end
          )
        end)
      end
    )
  end)
  devLog("DBG_PA _tryRematch: pcall returned ok=", ok)
  if not ok then
    devLog("Play Again: pcall failed in _tryRematchForLastReplay")
    _showGenericMatchmaker()
  end
end

-- Shared "play this opponent again?" confirmation, used by both the menu's
-- "re" button and the end-screen rematch button. onConfirmed() is only
-- called if the user taps "heck yeah"; it does NOT start matchmaking itself
-- (callers decide when/how, since the end screen must dispose of itself first).
function confirmRematchAgainstLastOpponent(onConfirmed)
  if not (tbm and tbm.localPlayer and tbm.localPlayer.authenticated == true) then
    openGCSignInOverlay()
    return
  end
  local settings = getLastMatchReplaySettings and getLastMatchReplaySettings() or nil
  if not settings then return end
  local oppName = settings.opponentName or "that player"
  local bs = settings.boardSize or boardSize
  local mwl = settings.minWordLen or MIN_WORD_LEN
  local avatar = getLastMatchReplayAvatar and getLastMatchReplayAvatar() or nil
  local rec    = opponentRecords and opponentRecords[settings.opponentId]
  local recWins   = (rec and rec.wins)   or 0
  local recLosses = (rec and rec.losses) or 0
  showGenericAlert({
    message = "Play another " .. bs .. "x" .. bs .. " (minimum length " .. mwl .. ") game against " .. oppName .. "? Your record against them is " .. recWins .. " to " .. recLosses .. ".",
    avatar  = avatar,
    buttons = {
      { text = "heck yeah", callback = onConfirmed, isPrimary = true },
      { text = "nah",       callback = function() end, isPrimary = false },
    },
  })
end

function startLastMatchReplayFromMenu()
  local settings = getLastMatchReplaySettings()
  if not settings then
    return
  end

  boardSize = _sanitizeBoardSize(settings.boardSize or boardSize)
  MIN_WORD_LEN = _sanitizeMinWordLen(settings.minWordLen or MIN_WORD_LEN)
  if persistGameplaySettings then persistGameplaySettings() end

  currentOpponentID = settings.opponentId or currentOpponentID
  opponentAlias = settings.opponentName or opponentAlias
  setTurnBasedEnabled(true)

  beginReplayMatchmakingBusy("matching...")
  _tryRematchForLastReplay(settings)
end

local function requestAutoOpenFinishedMatchCheck(reason)
  if not AUTO_OPEN_FINISHED_MATCH_ENABLED then return end
  finishedMatchAutoCheckPendingReason = reason or "unknown"
end

local function requestPendingHandshakeResendCheck(reason)
  pendingHandshakeResendReason = reason or "unknown"
end

local function _extractMatchSortTime(gkMatch, dataTable)
  local ts = nil
  local ok = pcall(function()
    local d = gkMatch and (gkMatch.lastTurnDate or gkMatch.date)
    if d and d.timeIntervalSince1970 then
      ts = tonumber(d.timeIntervalSince1970)
    end
  end)
  if not ok then ts = nil end
  if not ts and dataTable and dataTable.lastUpdated then
    ts = tonumber(dataTable.lastUpdated)
  end
  return ts or 0
end

local function _safeObjCString(v)
  if v == nil then return nil end
  local ok, s = pcall(function() return tostring(v) end)
  if not ok then return nil end
  if not s or s == "" then return nil end
  return s
end

local function _safeArrayCount(arr)
  if not arr then return 0 end
  if type(arr) == "table" then
    local okLen, n = pcall(function() return #arr end)
    if okLen and type(n) == "number" then return n end
    return 0
  end
  local okCount, n = pcall(function()
    if arr.respondsToSelector_ and arr:respondsToSelector_("count") then
      return tonumber(arr.count) or tonumber(arr:count()) or 0
    end
    return 0
  end)
  if okCount and type(n) == "number" then return n end
  return 0
end

local function _safeArrayGet(arr, i)
  if not arr or i < 1 then return nil end
  if type(arr) == "table" then
    return arr[i]
  end
  local ok, v = pcall(function()
    if arr.respondsToSelector_ and arr:respondsToSelector_("objectAtIndex:") then
      return arr:objectAtIndex_(i - 1) -- NSArray is 0-based
    end
    return nil
  end)
  if ok then return v end
  return nil
end

local function maybeAutoOpenMostRecentFinishedMatch(reason)
  if not AUTO_OPEN_FINISHED_MATCH_ENABLED then return end
  if finishedMatchAutoCheckInFlight then return end
  if replayMatchmakingBusy then return end
  if state ~= STATE_MENU then return end
  if not (tbm and tbm.localPlayer and tbm.localPlayer.authenticated) then return end
  local GKTurnBasedMatch = objc and objc.GKTurnBasedMatch
  if not GKTurnBasedMatch then return end
  
  finishedMatchAutoCheckInFlight = true
  local lastViewedId = readLocalData(LAST_VIEWED_FINISHED_MATCH_ID_KEY)
  
  local ok = pcall(function()
    GKTurnBasedMatch:loadMatchesWithCompletionHandler_(function(o__matches, o__err)
      objc.async(function()
        local okInner, errInner = pcall(function()
          finishedMatchAutoCheckInFlight = false
          if o__err then
            local errText = _safeObjCString(o__err.localizedDescription) or _safeObjCString(o__err) or "unknown"
            devLog("Auto-open finished match: load error", errText)
            return
          end
          local matches = o__matches
          local matchCount = _safeArrayCount(matches)
          if matchCount <= 0 then return end
          local bestMatch, bestData, bestTs = nil, nil, -1
          for i = 1, matchCount do
            local m = _safeArrayGet(matches, i)
            local ended = (tbm and tbm._getEndStateFromMatch and tbm:_getEndStateFromMatch(m)) or nil
            if ended then
              local dataTable = tbm and tbm._matchWithNSDataToDataTable and tbm:_matchWithNSDataToDataTable(m) or nil
              local ts = _extractMatchSortTime(m, dataTable)
              if ts > bestTs then
                bestTs = ts
                bestMatch = m
                bestData = dataTable
              end
            end
          end
          
          if not bestMatch then return end
          local bestId = _safeObjCString(bestMatch.matchID)
          if not bestId then return end
          local lastViewed = _safeObjCString(lastViewedId)
          if lastViewed and lastViewed == bestId then
            return
          end
          
          devLog("Auto-opening finished match", "match=", bestId, "reason=", reason or "?")
          if tbm and tbm._setCurrentMatch then
            tbm:_setCurrentMatch(bestMatch, "auto-open-finished")
          end
          local q = makeQMatchFromGK and makeQMatchFromGK(bestMatch, bestData) or nil
          if q and enterQMatch then
            saveLocalData(LAST_VIEWED_FINISHED_MATCH_ID_KEY, bestId)
            enterQMatch(q)
          else
            devLog("Auto-open finished match: failed to build qMatch", bestId)
          end
        end)
        if not okInner then
          finishedMatchAutoCheckInFlight = false
          devLog("Auto-open finished match crashed safely", tostring(errInner))
        end
      end)
    end)
  end)
  
  if not ok then
    finishedMatchAutoCheckInFlight = false
  end
end

function retryPendingHandshakeSends(reason)
  if not next(pendingTurnSendsByMatchId) then return end
  local GKTurnBasedMatch = objc and objc.GKTurnBasedMatch
  if not (tbm and GKTurnBasedMatch) then return end

  local ok = pcall(function()
    GKTurnBasedMatch:loadMatchesWithCompletionHandler_(function(o__matches, o__err)
      objc.async(function()
        local okInner, errInner = pcall(function()
          if o__err then
            local errText = _safeObjCString(o__err.localizedDescription) or _safeObjCString(o__err) or "unknown"
            devLog("retryPendingHandshakeSends: load error", errText)
            return
          end
          local matches = o__matches
          local matchCount = _safeArrayCount(matches)
          for pendingId, _ in pairs(pendingTurnSendsByMatchId) do
            for i = 1, matchCount do
              local m = _safeArrayGet(matches, i)
              local mid = m and _safeObjCString(m.matchID)
              if mid and mid == pendingId then
                tbm:_setCurrentMatch(m, "handshake-resend")
                if tbm.isMyTurn == true then
                  devLog("retryPendingHandshakeSends: resending", "matchId=", pendingId, "reason=", reason)
                  attemptHandshakeSend(pendingId)
                end
                break
              end
            end
          end
        end)
        if not okInner then
          devLog("retryPendingHandshakeSends crashed safely", tostring(errInner))
        end
      end)
    end)
  end)
  if not ok then
    devLog("retryPendingHandshakeSends: loadMatches call failed")
  end
end

local function isRunningOnSimulator()
  local ok, yes = pcall(function()
    local env = objc and objc.NSProcessInfo and objc.NSProcessInfo.processInfo and objc.NSProcessInfo.processInfo.environment
    if not env then return false end
    local name = env["SIMULATOR_DEVICE_NAME"]
    return name ~= nil
  end)
  return ok and yes or false
end

local function _currentInstallSignature()
  local bundlePath = nil
  local ok = pcall(function()
    local bundle = objc and objc.NSBundle and objc.NSBundle.mainBundle
    bundlePath = bundle and bundle.bundlePath
  end)
  if not ok then
    bundlePath = nil
  end
  return tostring(bundlePath or "?")
end

function trackInstallTimestampForXcodeLoad()
  -- On iOS, each install typically gets a new bundle container path:
  -- /var/containers/Bundle/Application/<UUID>/Quozzy.app
  -- Using this lets us detect "new app payload installed" even when build/version
  -- values are unchanged.
  local sig = _currentInstallSignature()
  local prevSig = readLocalData(INSTALL_SIGNATURE_KEY)
  if prevSig == sig then return end
  
  local now = os.time()
  local text = os.date("%Y-%m-%d %H:%M:%S", now)
  saveLocalData(INSTALL_SIGNATURE_KEY, sig)
  saveLocalData(INSTALL_EPOCH_KEY, now)
  saveLocalData(INSTALL_TEXT_KEY, text)
  devLog("Install timestamp updated", "bundlePath=", sig, "at=", text)
end

local function _buildLoadingEmojiPool()
  local pool = {}
  if type(SeasonConfettiEmoji) == "table" then
    for _, arr in pairs(SeasonConfettiEmoji) do
      if type(arr) == "table" then
        for i = 1, #arr do
          pool[#pool + 1] = arr[i]
        end
      end
    end
  end
  if type(genericConfettiEmoji) == "table" then
    for i = 1, #genericConfettiEmoji do
      pool[#pool + 1] = genericConfettiEmoji[i]
    end
  end
  if #pool == 0 then
    pool = { "✨", "⭐️", "🎉", "🍁", "🌸", "❄️", "☀️" }
  end
  return pool
end

function generateLoadingScreenImage(force)
  local existingVersion = tonumber(readLocalData(LOADING_ART_VERSION_KEY) or 0) or 0
  if not force and existingVersion >= LOADING_ART_VERSION then return end

  -- Render at current drawable size; avoids oversized offscreen buffers.
  local targetW = WIDTH
  local targetH = HEIGHT

  local img = image(targetW, targetH)
  local ok = pcall(function()
    setContext(img)
    background(Color.panelBG or color(239, 238, 229, 255))

    local cx = targetW * 0.5
    local cy = targetH * 0.5

    -- subtle watermark layer
    pushStyle()
    textMode(CENTER)
    textAlign(CENTER)
    font("Georgia-Bold")
    fill(Color.tileText.r, Color.tileText.g, Color.tileText.b, 22)
    fontSize(targetH * 0.17)
    for row = -1, 1 do
      for col = -1, 1 do
        local x = cx + col * (targetW * 0.50)
        local y = cy + row * (targetH * 0.32)
        text("Vivaldi-ku", x, y + targetH * 0.03)
        fontSize(targetH * 0.085)
        text("SEASONS", x, y - targetH * 0.09)
        fontSize(targetH * 0.17)
      end
    end
    popStyle()

    -- main centered text block
    pushStyle()
    textMode(CENTER)
    textAlign(CENTER)
    font("Georgia-Bold")
    fill(Color.tileText)
    -- Match menu-title proportions exactly (see drawTitleSection):
    -- Quozzy size = 0.55*h, Seasons size = 0.25*h
    -- Quozzy y = +0.15*h, Seasons y = -0.2*h
    local titleSideMargin = math.floor(targetW * 0.055)
    local maxTitleW = targetW - (titleSideMargin * 2)
    local titleBlockH = math.floor(targetH * 0.34)

    while titleBlockH > 120 do
      local qSize = math.floor(titleBlockH * 0.55)
      local sSize = math.floor(titleBlockH * 0.25)
      fontSize(qSize)
      local qW = textSize("Vivaldi-ku")
      fontSize(sSize)
      local sW = textSize("SEASONS")
      if qW <= maxTitleW and sW <= maxTitleW then
        break
      end
      titleBlockH = titleBlockH - 2
    end

    local qSize = math.floor(titleBlockH * 0.55)
    local sSize = math.floor(titleBlockH * 0.25)
    local qY = cy + titleBlockH * 0.15
    local sY = cy - titleBlockH * 0.20

    fontSize(qSize)
    text("Vivaldi-ku", cx, qY)
    fontSize(sSize)
    text("SEASONS", cx, sY)
    popStyle()

    -- seasonal emoji scatter around the title block
    local pool = _buildLoadingEmojiPool()
    local emojiCount = 30
    local safeHalfW = targetW * 0.32
    local safeHalfH = targetH * 0.18
    pushStyle()
    textMode(CENTER)
    textAlign(CENTER)
    for i = 1, emojiCount do
      local ch = pool[math.random(1, #pool)]
      local x, y
      local tries = 0
      repeat
        x = math.random(math.floor(targetW * 0.07), math.floor(targetW * 0.93))
        y = math.random(math.floor(targetH * 0.08), math.floor(targetH * 0.92))
        tries = tries + 1
      until ((math.abs(x - cx) > safeHalfW or math.abs(y - cy) > safeHalfH) or tries > 18)

      local fs = math.random(math.floor(targetH * 0.022), math.floor(targetH * 0.038))
      fontSize(fs)
      fill(255, 255, 255, math.random(170, 235))
      text(ch, x, y)
    end
    popStyle()

    setContext()
  end)

  pcall(setContext)
  if not ok then
    devLog("Loading art generation failed")
    return
  end

  local outName = LOADING_ART_NAME .. "_v" .. tostring(LOADING_ART_VERSION)
  local saveOk = pcall(function()
    saveImage("Documents:" .. outName, img)
  end)
  if saveOk then
    pcall(function()
      saveImage("Documents:" .. LOADING_ART_NAME, img)
    end)
    saveLocalData(LOADING_ART_VERSION_KEY, LOADING_ART_VERSION)
    devLog("Generated loading image", "Documents:" .. outName, targetW .. "x" .. targetH)
  else
    devLog("Failed to save loading image", "Documents:" .. outName)
  end
end

score = 0
foundWords = {}
foundWordsSet = {}

board = {}
tileRects = {}

currentPath = {}
pathActive = false
touchIdActive = nil
dragLastX = nil
dragLastY = nil

lastWord = ""
lastWordValid = false

DICT = {}
dictStatus = "Fallback"

endScrollY = 0
endScrollTouchId = nil
endScrollPrevY = 0

topMargin    = 80
bottomMargin = 80
sideMargin   = 40

-- Cached rounded overlay panel sprite
-- Rounded overlay sprites, built per-theme in nextSeason()
overlayPanelEnd      = nil   -- 0.8 x 0.8 panel (end screen)
overlayPanelRecords  = nil   -- 0.85 x 0.85 panel (records screen)
readyTapPanel        = nil   -- “Tap anywhere to start” panel

-- Toggle this during simulator bring-up:
-- true  = keep menu/draw/touch flow, skip heavy runtime integrations
-- false = full game boot
SAFE_BOOT = false

gcBadgePermissionRequested = gcBadgePermissionRequested or false

local function setHomeScreenBadgeCount(count)
  count = math.max(0, math.floor(tonumber(count) or 0))
  local app = objc and objc.UIApplication and (objc.UIApplication.sharedApplication or (objc.UIApplication.sharedApplication and objc.UIApplication:sharedApplication()))
  if not app then return false end
  local ok = pcall(function()
    app.applicationIconBadgeNumber = count
  end)
  if not ok then
    ok = pcall(function()
      app:setApplicationIconBadgeNumber_(count)
    end)
  end
  if ok then
    devLog("Home badge set to", count)
  end
  return ok
end

local function requestHomeScreenBadgePermission()
  if gcBadgePermissionRequested then return end
  gcBadgePermissionRequested = true
  
  local ok = pcall(function()
    local UN = objc and objc.UNUserNotificationCenter
    if not UN then
      devLog("Badge permission request skipped (UNUserNotificationCenter unavailable)")
      return
    end
    local center = UN.currentNotificationCenter or (UN.currentNotificationCenter and UN:currentNotificationCenter())
    if not center then
      devLog("Badge permission request skipped (notification center unavailable)")
      return
    end
    local opts = nil
    if objc.enum and objc.enum.UNAuthorizationOptions then
      opts = objc.enum.UNAuthorizationOptions.badge
    end
    if not opts then
      -- badge-only is bit 1 << 0 on iOS
      opts = 1
    end
    center:requestAuthorizationWithOptions_completionHandler_(opts, function(granted, err)
      objc.async(function()
        local grantedBool = (granted == true or granted == 1)
        devLog("Badge permission callback", "granted=", grantedBool, "err=", err ~= nil)
      end)
    end)
  end)
  if not ok then
    devLog("Badge permission request failed (bridge call)")
  end
end

local function refreshHomeScreenBadgeFromGCMatches(reason)
  if SAFE_BOOT then return end
  if not (tbm and tbm.localPlayer and tbm.localPlayer.authenticated) then
    return
  end
  local GKTurnBasedMatch = objc and objc.GKTurnBasedMatch
  if not GKTurnBasedMatch then return end
  
  local localId = tbm.localPlayer.playerID
  local localGamePlayerId = tbm.localPlayer.gamePlayerID
  
  local ok = pcall(function()
    GKTurnBasedMatch:loadMatchesWithCompletionHandler_(function(o__matches, o__err)
      objc.async(function()
        if o__err then
          devLog("Home badge refresh GC load error", o__err.localizedDescription or tostring(o__err))
          return
        end
        local pending = 0
        local matches = o__matches or {}
        for i = 1, #matches do
          local m = matches[i]
          local isEnded = (tbm and tbm._isMatchEnded and tbm:_isMatchEnded(m)) or false
          if not isEnded then
            local cp = m and m.currentParticipant
            local cpId = cp and cp.playerID
            local cpGameId = cp and cp.gamePlayerID
            if (cpId and localId and cpId == localId) or (cpGameId and localGamePlayerId and cpGameId == localGamePlayerId) then
              pending = pending + 1
            end
          end
        end
        setHomeScreenBadgeCount(pending)
        devLog("Home badge refresh", "pendingMatches=", pending, "reason=", reason or "?")
      end)
    end)
  end)
  if not ok then
    devLog("Home badge refresh failed (bridge call)", reason or "?")
  end
end

--####################################################################
-- Game Loop
function launchNumber()
  local n = (readLocalData("PIN_lc") or 0) + 1
  saveLocalData("PIN_lc", n)
  return n
end

function textsFoundByDocuments()
  local a = readText("Documents:_pin_str.txt")
  return a and ("'" .. a .. "'") or "nil"
end

function textsFoundByAssetDocuments()
  local a = readText(asset.documents .. "_pin_key.txt")
  return a and ("'" .. a .. "'") or "nil"
end

function saveTextsBothWays()
  saveText("Documents:_pin_str.txt", "hello")
  saveText(asset.documents .. "_pin_key.txt", "hello")
  return "saved"
end

function testTextSaves()
  devLog("launch " .. launchNumber())
  devLog("texts found by 'Documents:': " .. textsFoundByDocuments())
  devLog("texts found by asset.documents: " .. textsFoundByAssetDocuments())
  devLog(saveTextsBothWays())
end

function resetTestState()
  saveLocalData("PIN_lc", 0)
  saveText("Documents:_pin_str.txt", nil)
  saveText(asset.documents .. "_pin_key.txt", nil)
  saveImage("Documents:_pin_str_img", nil)
  saveImage(asset.documents .. "_pin_key_img", nil)
  devLog("reset done — next launch will be launch 1 with all nil")
end

function imagesFoundByDocuments()
  local a = nil; pcall(function() a = readImage("Documents:_pin_str_img") end)
  return a and ("image " .. a.width .. "x" .. a.height) or "nil"
end

function imagesFoundByAssetDocuments()
  local a = nil; pcall(function() a = readImage(asset.documents .. "_pin_key_img") end)
  return a and ("image " .. a.width .. "x" .. a.height) or "nil"
end

function saveImagesBothWays()
  local r = image(32,32); setContext(r); background(255,0,0,255); setContext()
  saveImage("Documents:_pin_str_img", r)
  saveImage(asset.documents .. "_pin_key_img", r)
  return "saved"
end

function testImageSaves()
  devLog("images found by 'Documents:': " .. imagesFoundByDocuments())
  devLog("images found by asset.documents: " .. imagesFoundByAssetDocuments())
  devLog(saveImagesBothWays())
end


function setup()
  -- Clear stale log buffer from previous session; fresh buffer for this launch
  saveLocalData("DevLogBuffer", "[]")
  devLog("started Main setup()", "SAFE_BOOT=", SAFE_BOOT)
  testTextSaves()
  testImageSaves()
  --resetTestState()
  if isRunningOnSimulator() then
    AUTO_OPEN_FINISHED_MATCH_ENABLED = false
    devLog("Auto-open finished match disabled on Simulator")
  end
  loadGameplaySettings()
  trackInstallTimestampForXcodeLoad()
  
  parameter.action("Clear Opponent Records", function()
    saveLocalData("OpponentRecords", nil)
    opponentRecords = {}
    print("Opponent records cleared")
  end)
  initDictionary()
  applyStartingSeason()

  nextHaiku()

  avatarMesh = mesh()
  avatarMesh:addRect(0,0,1,1)
  
  avatarMesh.shader = shader(
  CircleS.vertexShader,
  CircleS.fragmentShader
  )
  
  avatarMesh.shader.circleSize = 0.5   -- full circle
  
  setupSparklerParameters()
  
  if SAFE_BOOT or BALLOON_MOCKUP_DEV then
    devLog("SAFE_BOOT/BALLOON_MOCKUP_DEV active: skipping CTBM/GameCenter wiring")
    return
  end
  
  tbm = CTBM()

  tbm:uponDetectingAuthentication(function()
    defineAvatarsAfterMicrodelay()
    otherPlayerAvatar = unknownPlayerAvatar(200, Color.uiAccent)
    requestHomeScreenBadgePermission()
    refreshHomeScreenBadgeFromGCMatches("auth")
    requestAutoOpenFinishedMatchCheck("auth")
    requestPendingHandshakeResendCheck("auth")
  end)

  tbm:onReceivingTurn(function(gkMatch, dataTable)
    print("GC → QUOZZY RECEIVE turnData:")
    print(dataTable and json.encode(dataTable) or "nil dataTable")
    if dataTable and dataTable.players then
      for pid, pdata in pairs(dataTable.players) do
        local comment = pdata and pdata.comment
        if type(comment) == "string" and comment ~= "" then
          devLog("Received match comment", "pid=", pid, "comment=", comment)
        end
      end
    end
    if mergeOpponentRecordFromTurnData then
      mergeOpponentRecordFromTurnData(gkMatch, dataTable)
    end
    
    local q = makeQMatchFromGK(gkMatch, dataTable)
    if q then
      enterQMatch(q)
    else
      print("makeQMatchFromGK failed")
    end
    refreshHomeScreenBadgeFromGCMatches("receivingTurn")
  end)

  tbm:onTurnEnded(function(gkMatch, dataTable)
    refreshHomeScreenBadgeFromGCMatches("turnEnded")
    local mid = gkMatch and gkMatch.matchID
    if mid and pendingTurnSendsByMatchId[mid] then
      pendingTurnSendsByMatchId[mid] = nil
      persistPendingTurnSends()
      if awaitingHandshakeSend and currentQMatch and currentQMatch.id == mid then
        awaitingHandshakeSend = false
      end
    end
  end)

  tbm:onSettingCurrentMatch(function(gkMatch, data)
    print("QUOZZY: onSettingCurrentMatch fired", gkMatch)
    if not (tbm and tbm._getEndStateFromMatch) then return end
    local endState = tbm:_getEndStateFromMatch(gkMatch)
    if endState then
      devLog("Selected GC match is finished", "endState=", endState)
      state = STATE_END
    end
    refreshHomeScreenBadgeFromGCMatches("settingCurrentMatch")
  end)

  loadPendingTurnSends()
  requestPendingHandshakeResendCheck("setup")
  setupGCDebugParameters()
  if FORCE_COMMENT_PHASE_BOOT_PREVIEW and openDebugCommentPhasePreview then
    openDebugCommentPhasePreview()
  end

  -- Auto-test hooks (set to true to auto-navigate on launch)
  if AUTO_SHOW_DEBUG_ALERT then
    -- Delayed call: generic alert needs HaikuMenu globals loaded
    autoShowDebugAlertPending = true
  end
end

function setupSparklerParameters()
  -- integer-ish (we snap to int)
  parameter.number("Spark_spawnFrequency", 1, 30, Sparkler.spawnFrequency, function(v)
    Sparkler.spawnFrequency = math.floor(v + 0.5)
  end)
  
  parameter.number("Spark_spawnSize", 8, 60, Sparkler.spawnSize, function(v)
    Sparkler.spawnSize = v
  end)
  
  parameter.number("Spark_maxVelocity", 40, 1200, Sparkler.maxVelocity, function(v)
    Sparkler.maxVelocity = v
  end)
  
  parameter.number("Spark_maxSpin", 0, 720, Sparkler.maxSpin, function(v)
    Sparkler.maxSpin = v
  end)
  
  parameter.number("Spark_maxDistance", 40, 1200, Sparkler.maxDistance, function(v)
    Sparkler.maxDistance = v
  end)
  
  parameter.number("Spark_timeBeforeFade", 0, 1.5, Sparkler.timeBeforeFade, function(v)
    Sparkler.timeBeforeFade = v
  end)
  
  parameter.number("Spark_fadeEaseOut", 0.5, 4.0, Sparkler.fadeEaseOut, function(v)
    Sparkler.fadeEaseOut = v
  end)
end

function drawReplayMatchmakingOverlay()
  if not replayMatchmakingBusy then return end
  pushStyle()
  rectMode(CORNER)
  fill(0, 0, 0, 110)
  noStroke()
  rect(0, 0, WIDTH, HEIGHT)

  local w = math.min(WIDTH * 0.60, 420)
  local h = math.min(HEIGHT * 0.18, 160)
  local cx, cy = WIDTH * 0.5, HEIGHT * 0.5
  drawRoundedRect(cx, cy, w, h, 18, Color.panelBG, Color.panelBG)

  local dotR = math.max(4, math.floor(h * 0.06))
  local orbit = h * 0.22
  local phase = ElapsedTime * 3.0
  for i = 1, 8 do
    local a = phase + (i - 1) * (math.pi * 0.25)
    local alpha = math.floor(60 + 195 * ((i - 1) / 7))
    fill(255, 255, 255, alpha)
    ellipse(cx + math.cos(a) * orbit, cy + h * 0.14 + math.sin(a) * orbit, dotR * 2)
  end

  fill(Color.tileText)
  font("Helvetica-Bold")
  fontSize(math.floor(h * 0.22))
  textMode(CENTER)
  textAlign(CENTER)
  text(replayMatchmakingBusyMessage or "matching...", cx, cy - h * 0.20)
  popStyle()
end

function draw()
  if FORCE_RED_BOOT_SCREEN then
    background(255, 0, 0)
    return
  end

  -- Periodic flush of diagnostic log ring buffer to saveLocalData
  DEV_LOG_TIME_SINCE_FLUSH = (DEV_LOG_TIME_SINCE_FLUSH or 0) + DeltaTime
  if DEV_LOG_TIME_SINCE_FLUSH >= DEV_LOG_FLUSH_INTERVAL then
    _flushLogBuffer()
    DEV_LOG_TIME_SINCE_FLUSH = 0
  end

  local function safeDrawCall(name, fn)
    local ok, err = pcall(fn)
    if not ok then
      devLog("DRAW ERROR in", name, tostring(err), "state=", state)
      return false
    end
    return true
  end

  background(Color.bg)
  font(GLOBAL_UI_FONT)  -- ambient default for the frame; see GLOBAL_UI_FONT comment above
  local appStateActive = true
  local okAppState = pcall(function()
    local app = objc and objc.UIApplication and (objc.UIApplication.sharedApplication or (objc.UIApplication.sharedApplication and objc.UIApplication:sharedApplication()))
    if app and app.applicationState ~= nil then
      appStateActive = (tonumber(app.applicationState) == 0)
    end
  end)
  if not okAppState then appStateActive = true end
  
  if appStateActive and (not appWasActiveLastFrame) then
    requestAutoOpenFinishedMatchCheck("foreground")
    requestPendingHandshakeResendCheck("foreground")
  end
  appWasActiveLastFrame = appStateActive

  updateSeasonTransition(DeltaTime)
  updateConfetti(DeltaTime)
  updateMatchBadge(DeltaTime)

  if finishedMatchAutoCheckPendingReason then
    local reason = finishedMatchAutoCheckPendingReason
    finishedMatchAutoCheckPendingReason = nil
    maybeAutoOpenMostRecentFinishedMatch(reason)
  end

  if pendingHandshakeResendReason then
    local reason = pendingHandshakeResendReason
    pendingHandshakeResendReason = nil
    retryPendingHandshakeSends(reason)
  end
  
  if state == STATE_MENU then
    if ENABLE_LOADING_ART_GENERATOR and loadingArtGenerationPending then
      generateLoadingScreenImage(true)
      loadingArtGenerationPending = false
    end

    if menuFrameCapturePending then
      local cap = image(WIDTH, HEIGHT)
      local okCapture = pcall(function()
        setContext(cap)
        drawMenu()
        setContext()
      end)
      pcall(setContext)
      
      local okSave = false
      if okCapture then
        okSave = pcall(function()
          saveImage("Documents:" .. MENU_CAPTURE_NAME, cap)
        end)
      end
      
      if okCapture and okSave then
        devLog("Saved one-shot menu capture", "Documents:" .. MENU_CAPTURE_NAME, tostring(WIDTH) .. "x" .. tostring(HEIGHT))
      else
        devLog("Menu capture failed", "captureOk=", tostring(okCapture), "saveOk=", tostring(okSave))
      end
      menuFrameCapturePending = false
    end

    -- Auto-test: show debug alert on first menu frame
    if autoShowDebugAlertPending then
      autoShowDebugAlertPending = nil
      if showGenericAlert then
        showGenericAlert({
          message = "Play another 4x4 (minimum word length 3) game against DebugPlayer?",
          avatar = nil,
          buttons = {
            { text = "heck yeah", callback = function() dismissGenericAlert() end, isPrimary = true },
            { text = "nah",       callback = function() dismissGenericAlert() end, isPrimary = false },
          },
        })
      end
    end

    drawMenu()
    drawRecordsOverlay()
    drawMatchBadge()
    drawInfoOverlay()
    drawColorInspectorOverlay()
    drawGCSignInOverlay()
    drawBalloonMockupOverlay()
    drawBalloonColorPickerOverlay()
    drawGCMatchmakerErrorOverlay()
    drawReplayMatchmakingOverlay()
    drawConfetti()
    drawGenericAlert()
    -- Local avatar
    if avatarTest then
      if localPlayerAvatar then
        sprite(localPlayerAvatar, 40, HEIGHT - 296, 256, 256)
        drawAvatarCircle(localPlayerAvatar, 40, 90, 256, "Y")
      end
      -- Other avatar
      if otherPlayerAvatar then
        sprite(otherPlayerAvatar, 320, HEIGHT - 296, 256, 256)
        drawAvatarCircle(otherPlayerAvatar, 320, 90, 256, "O")
      end    
    end
      return
  end
  
  updatePathParticles(DeltaTime)
  
  if state == STATE_PLAY then
    timeRemaining = timeRemaining - DeltaTime
    if timeRemaining <= 0 then
      timeRemaining = 0
      endGameRound()
    end
  end
  
  if state == STATE_READY then
    safeDrawCall("updateReadyRattle", updateReadyRattle)
  end

  if state == STATE_READY or state == STATE_PLAY then
    safeDrawCall("drawBoard", drawBoard)
    safeDrawCall("drawSelectionPath", drawSelectionPath)
    safeDrawCall("drawPathParticles", drawPathParticles)
    safeDrawCall("drawTopHUD", drawTopHUD)
  end
  
  if state == STATE_READY then
    safeDrawCall("drawReadyMessage", drawReadyMessage)
  end
  
  if state == STATE_PLAY then
    safeDrawCall("drawInGameWordList", drawInGameWordList)
  end
  
  if state == STATE_END then
    safeDrawCall("drawEndScreen", drawEndScreen)
  end
  safeDrawCall("drawRecordsOverlay", drawRecordsOverlay)
  safeDrawCall("drawConfetti", drawConfetti)
  safeDrawCall("drawGenericAlert", drawGenericAlert)
end

function handlePreviewTouch(t)
  if not previewMode then return false end
  
  if t.state == BEGAN or t.state == ENDED then
    if previewCloseX and previewCloseY and previewCloseSize then
      if pointInRect(t.x, t.y,
      previewCloseX, previewCloseY,
      previewCloseSize, previewCloseSize) then
        dismissPreview()
        return true
      end
    end
  end
  
  -- swallow all touches while preview is up
  return true
end

function touched(t)
  if FORCE_RED_BOOT_SCREEN then
    return
  end

  if replayMatchmakingBusy then
    if t.state == ENDED then
      devLog("DBG_BUSY TOUCH BLOCKED by replayMatchmakingBusy=true")
    end
    return
  end

  -- Generic alert overlay eats all touches, from any state
  if genericAlertActive then
    handleGenericAlertTouch(t)
    return
  end

  -- match badge tap gets first dibs on menu screen
  if state == STATE_MENU and handleMatchBadgeTouch(t) then
    return
  end
  
  if showInfoOverlay and handleInfoOverlayTouch(t) then
    return
  end

  -- Color inspector overlay eats all touches; dismiss on release
  if colorInspectorOverlay then
    if t.state == ENDED or t.state == CANCELLED then
      colorInspectorOverlay = false
    end
    return
  end

  -- Balloon mockup overlay eats all Codea touches. A row of 7 numbered chips
  -- picks one of the real comment-balloon scenarios (BALLOON_MOCKUP_STATES,
  -- EndScreenFP.lua) — one tap, one complete valid state. A tap on the live
  -- composer field focuses it natively (handled by UIKit hit-testing before
  -- it ever reaches here). Any OTHER tap, while the field is focused, is
  -- treated the same as hitting Return: unfocus without submitting anything
  -- (dismiss the overlay itself only via "close").
  if balloonMockupOverlay then
    if t.state == ENDED or t.state == CANCELLED then
      local hitChip = nil
      if mockupChipRects then
        for i, r in ipairs(mockupChipRects) do
          if pointInRect(t.x, t.y, r.cx, r.cy, r.w, r.h) then hitChip = i break end
        end
      end
      if hitChip then
        mockupScenarioIndex = hitChip
      elseif mockupCloseBtnRect and pointInRect(t.x, t.y, mockupCloseBtnRect.cx, mockupCloseBtnRect.cy, mockupCloseBtnRect.w, mockupCloseBtnRect.h) then
        if teardownMockupTextField then teardownMockupTextField() end
        balloonMockupOverlay = false
      elseif commentFields[2] and commentFields[2].focused and commentFields[2].tv then
        commentFields[2].tv:resignFirstResponder_()
      end
    end
    return
  end

  -- Balloon color picker overlay (dev) eats all touches. Drag-to-scroll +
  -- tap-slop over the 10 BALLOON_COLOR_SCHEMES rows (see
  -- drawBalloonColorPickerOverlay, EndScreenFP.lua) — a tap (no significant
  -- movement) on a row selects that scheme immediately; "preview on full end
  -- screen" jumps into the existing balloon mockup (scenario 6) so the picked
  -- scheme can be seen in full context.
  if balloonColorPickerOverlay then
    local g = colorPickerGeom
    if not g then
      if t.state == ENDED or t.state == CANCELLED then balloonColorPickerOverlay = false end
      return
    end
    if t.state == BEGAN then
      if pointInRect(t.x, t.y, g.closeBtn.cx, g.closeBtn.cy, g.closeBtn.w, g.closeBtn.h)
        or pointInRect(t.x, t.y, g.previewBtn.cx, g.previewBtn.cy, g.previewBtn.w, g.previewBtn.h) then
        colorPickerScrollTouchId = nil
      elseif t.x >= g.listLeft and t.x <= g.listLeft + g.listWidth and
             t.y >= g.listBottom and t.y <= g.listBottom + g.listHeight then
        colorPickerScrollTouchId = t.id
        colorPickerScrollPrevY   = t.y
        colorPickerTouchStartX   = t.x
        colorPickerTouchStartY   = t.y
        colorPickerTouchMoved    = false
      end
    elseif t.state == MOVING then
      if colorPickerScrollTouchId and t.id == colorPickerScrollTouchId then
        local dy = t.y - colorPickerScrollPrevY
        colorPickerScrollPrevY = t.y
        colorPickerScrollY = colorPickerScrollY - dy
        if math.abs(t.y - colorPickerTouchStartY) > 10 or math.abs(t.x - colorPickerTouchStartX) > 10 then
          colorPickerTouchMoved = true
        end
      end
    elseif t.state == ENDED or t.state == CANCELLED then
      if pointInRect(t.x, t.y, g.closeBtn.cx, g.closeBtn.cy, g.closeBtn.w, g.closeBtn.h) then
        balloonColorPickerOverlay = false
      elseif pointInRect(t.x, t.y, g.previewBtn.cx, g.previewBtn.cy, g.previewBtn.w, g.previewBtn.h) then
        balloonColorPickerOverlay = false
        balloonMockupOverlay = true
        mockupScenarioIndex = 6
      elseif colorPickerScrollTouchId and t.id == colorPickerScrollTouchId
             and t.state == ENDED and not colorPickerTouchMoved and colorPickerRowRects then
        for i, r in pairs(colorPickerRowRects) do
          if t.x >= r.x and t.x <= r.x + r.w and t.y >= r.y and t.y <= r.y + r.h then
            balloonColorSchemeIndex = i
            break
          end
        end
      end
      colorPickerScrollTouchId = nil
    end
    return
  end

  if handleGCSignInOverlayTouch(t) then return end

  if gcMatchmakerErrorOverlay and (t.state == ENDED or t.state == CANCELLED) then
    gcMatchmakerErrorOverlay = false
    return
  end
  
  if seasonTransition and seasonTransition.active then
    -- block all input during palette fade + confetti
    return
  end
  
  if recordsOverlay and handleRecordsTouch(t) then
    return
  end
  
  -- existing preview overlay handling
  if previewMode and handlePreviewTouch(t) then
    return
  end
  
  -- READY: any tap starts the round
  if state == STATE_READY then
    if awaitingHandshakeSend then return end   -- board still sending; nothing tappable yet
    if handleQuitButtonTouch(t) then
      endGameRound()
      return
    end
    if t.state == BEGAN then
      captureBoardSnapAnim()
      state = STATE_PLAY
    end
    return
  end
  
  if state == STATE_MENU then
    handleMenuTouch(t)
    return
  end
  
  if state == STATE_PLAY then
    if handleQuitButtonTouch(t) then 
      endGameRound()
      return 
    end
    handleGameTouch(t)
    return
  end
  
  if state == STATE_END then
    handleEndScreenTouch(t)
    return
  end
end
