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

function devLog(...)
  local parts = {}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  local msg = table.concat(parts, " ")
  print(msg)
  if objc and objc.log then
    msg = "🧑‍💻 " .. msg
    objc.log(msg)
  end
end

--bootstrapCTBM()

--print = devLog

viewer.mode = FULLSCREEN
-- AFTER
MIN_WORD_LEN = 3
SOWPODS_URL = "https://people.sc.fsu.edu/~jburkardt/datasets/words/sowpods.txt"
SOWPODS_LOCAL_NAME = asset .. "SOWPODS.txt"

recordsOverlay = false
recordsScrollY = 0
recordsScrollTouchId = nil
recordsScrollPrevY = 0

showInfoOverlay = false

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

local function _sanitizeBoardSize(v)
  v = math.floor(tonumber(v) or 4)
  if v ~= 4 and v ~= 5 then return 4 end
  return v
end

local function _sanitizeMinWordLen(v)
  v = math.floor(tonumber(v) or 3)
  if v < 3 then v = 3 end
  if v > 5 then v = 5 end
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
--####################################################################

function setup()
  devLog("started Main setup()", "SAFE_BOOT=", SAFE_BOOT)
  math.randomseed(os.time())
  useFunctionalEndScreen = useFunctionalEndScreen or true
  loadGameplaySettings()
  
  parameter.action("Clear Opponent Records", function()
    saveLocalData("OpponentRecords", nil)
    opponentRecords = {}
    print("Opponent records cleared")
  end)
  parameter.boolean("useFunctionalEndScreen", useFunctionalEndScreen)
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
  
  if SAFE_BOOT then
    devLog("SAFE_BOOT active: skipping CTBM/GameCenter wiring")
    return
  end
  
  tbm = CTBM()

  tbm:uponDetectingAuthentication(function()
    defineAvatarsAfterMicrodelay()
    otherPlayerAvatar = unknownPlayerAvatar(200, Color.uiAccent)
    requestHomeScreenBadgePermission()
    refreshHomeScreenBadgeFromGCMatches("auth")
  end)

  tbm:onReceivingTurn(function(gkMatch, dataTable)
    print("GC → QUOZZY RECEIVE turnData:")
    print(dataTable and json.encode(dataTable) or "nil dataTable")
    
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
  setupGCDebugParameters()
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

function draw()
  local function safeDrawCall(name, fn)
    local ok, err = pcall(fn)
    if not ok then
      devLog("DRAW ERROR in", name, tostring(err), "state=", state)
      return false
    end
    return true
  end

  background(Color.bg)
  updateSeasonTransition(DeltaTime)
  updateConfetti(DeltaTime)
  updateMatchBadge(DeltaTime)
  
  if state == STATE_MENU then
    drawMenu()
    drawRecordsOverlay()
    drawMatchBadge()
    drawInfoOverlay()
    drawGCMatchmakerErrorOverlay()
    drawConfetti()        
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
  -- match badge tap gets first dibs on menu screen
  if state == STATE_MENU and handleMatchBadgeTouch(t) then
    return
  end
  
  if showInfoOverlay and (t.state == ENDED or t.state == CANCELLED) then
    showInfoOverlay = false
    return
  end

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
    if handleQuitButtonTouch(t) then 
      endGameRound()
      return 
    end
    if t.state == BEGAN then
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
