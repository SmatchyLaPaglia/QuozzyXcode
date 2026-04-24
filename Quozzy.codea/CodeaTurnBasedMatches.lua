--CTMB stands for Codea Turn-Based Matches
CTBM = class()
CTBM.ENDSTATE = {
  WIN  = "win",
  LOSS = "loss",
  DRAW = "draw",
  QUIT = "quit"
}

function CTBM:init()
  self:_major("init start")
  -- public state
  self.localPlayer = objc.GKLocalPlayer.localPlayer
  self.viewController = objc.viewer
  self.currentMatch = nil
  self.isMyTurn = false
  self:_major("local player fetched", self.localPlayer ~= nil, "authenticated=", self.localPlayer and self.localPlayer.authenticated or false)
  
  -- internal state
  self._logActive = false
  self._matchmakingEventSeq = 0
  self._isAuthenticated = false
  self._listener = self:_makeLocalPlayerListener()
  self._gkTBHandler, self._gkTBHandlerDelegate =
  self:_makeDeprecatedTurnBasedHandler()
  
  -- callbacks (set by user)
  self._uponDetectingAuthentication = function()
    self:log("CTBM: _uponDetectingAuthentication undefined")
  end
  self._onSettingCurrentMatch = function(match, data)
    self:log("CTBM: _onSettingCurrentMatch undefined")
  end
  self._onReceivingTurn = function(match, data)
    self:log("CTBM: __onReceivingTurn undefined")
  end
  self._onFindingReadyMatch = function(match, data)
    self:log("CTBM: _onFindingReadyMatch undefined")
  end
  self._onTurnEnded = function(match, dataTable)
    self:log("CTBM: _onTurnEnded undefined")
  end
  self._onMatchmakerCancelled = function()
    self:log("CTBM: _onMatchmakerCancelled undefined")
  end
  self._onMatchmakerError = function(err) 
    self:log("CTBM: _is onMatchmakerError undefined")
  end
  self._onLocalPlayerWon = function(match, payload)
    self:log("CTBM: _onLocalPlayerWon undefined")
  end 
  self._onLocalPlayerLost = function(match, payload)
    self:log("CTBM: _onLocalPlayerLost undefined")
  end  
  self._onLocalPlayerTied = function(match, payload)
    self:log("CTBM: _onLocalPlayerTied undefined")
  end  
  self._onLocalPlayerQuit = function(match, payload)
    self:log("CTBM: _onLocalPlayerQuit undefined")
  end  
  self._onOtherPlayerQuit = function(match, payload)
    self:log("CTBM: _onOtherPlayerQuit undefined")
  end
  
  -- final initializations
  self:_major("registering GKLocalPlayer listener")
  self.localPlayer: registerListener_(self._listener)
  self:_major("listener registered; starting auth")
  self:_authenticate()
end

function CTBM:log(...)
  if self._logActive then
    print(...)
  end
end

-- High-signal diagnostics for app-level debugging.
-- Uses devLog when available so messages reliably reach Xcode console.
function CTBM:_major(...)
  local parts = {"CTBM"}
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  local msg = table.concat(parts, " | ")
  if type(devLog) == "function" then
    devLog(msg)
  else
    print(msg)
  end
end

function CTBM:setLogging(onOrOff)
  self._logActive = onOrOff
end
function CTBM:_logMatchmakingEvent(tag, match, extra)
  if not self._logActive then return end
  self._matchmakingEventSeq = self._matchmakingEventSeq + 1
  local id = match and match.matchID or "nil"
  print(
  string.format(
  "[%02d] %s | match=%s %s",
  self._matchmakingEventSeq,
  tag,
  id,
  extra or ""
  )
  )
end

function CTBM:_participantStatusName(status)
  local E = objc and objc.enum and objc.enum.GKTurnBasedParticipantStatus
  if not E or status == nil then return "unknown" end
  if E.unknown and status == E.unknown then return "unknown" end
  if E.invited and status == E.invited then return "invited" end
  if E.declined and status == E.declined then return "declined" end
  if E.matching and status == E.matching then return "matching" end
  if E.active and status == E.active then return "active" end
  if E.done and status == E.done then return "done" end
  return tostring(status)
end

function CTBM:_logDismissedMatchState(match, reason)
  if not match then
    self:_major("matchmaker dismissed", "reason=", reason or "?", "match=nil")
    return
  end
  
  local localId = self.localPlayer and self.localPlayer.playerID
  local cp = match.currentParticipant
  local cpId = cp and cp.playerID
  local turnOwner = "unknown"
  if not cp then
    turnOwner = "none"
  elseif not cpId then
    turnOwner = "unassigned"
  elseif cpId == localId then
    turnOwner = "me"
  else
    turnOwner = "opponent"
  end
  
  local endState = self:_getEndStateFromMatch(match)
  local lifecycle = endState and ("ended:" .. tostring(endState)) or "open"
  
  local remoteAssigned = false
  local remoteStatus = "none"
  if match.participants then
    for i = 1, #match.participants do
      local p = match.participants[i]
      local pl = p and p.player
      local pid = p and p.playerID
      local isLocal = (pid and localId and pid == localId) or (pl and pl.isLocalPlayer) or false
      if not isLocal then
        if pl then
          remoteAssigned = true
          remoteStatus = "assigned"
        else
          remoteStatus = self:_participantStatusName(p and p.status)
        end
        break
      end
    end
  end
  
  self:_major(
    "matchmaker dismissed state",
    "reason=", reason or "?",
    "match=", match.matchID or "nil",
    "lifecycle=", lifecycle,
    "turnOwner=", turnOwner,
    "remoteAssigned=", tostring(remoteAssigned),
    "remoteStatus=", remoteStatus
  )
end

function CTBM:onMatchesCleared(fn)
  self._onMatchesCleared = fn
end
function CTBM:onReceivingTurn(fn)
  self._onReceivingTurn = fn
end
function CTBM:onSettingCurrentMatch(fn)
  self._onSettingCurrentMatch = fn
end
function CTBM:onTurnEnded(fn)
  self._onTurnEnded = fn
end
function CTBM:onMatchmakerCancelled(fn)
  self._onMatchmakerCancelled = fn
end
function CTBM:onMatchmakerError(fn)
  self._onMatchmakerError = fn
end
function CTBM:onLocalPlayerWon(fn)      self._onLocalPlayerWon = fn end
function CTBM:onLocalPlayerLost(fn)     self._onLocalPlayerLost = fn end
function CTBM:onLocalPlayerTied(fn)     self._onLocalPlayerTied = fn end
function CTBM:onLocalPlayerQuit(fn)     self._onLocalPlayerQuit = fn end
function CTBM:onOtherPlayerQuit(fn)     self._onOtherPlayerQuit = fn end

function CTBM:localPlayerWon(payload)
  self:_endMatchLocal(CTBM.ENDSTATE.WIN, payload)
end
function CTBM:localPlayerLost(payload)
  self:_endMatchLocal(CTBM.ENDSTATE.LOSS, payload)
end
function CTBM:localPlayerTied(payload)
  self:_endMatchLocal(CTBM.ENDSTATE.DRAW, payload)
end
function CTBM:localPlayerQuit(payload)
  self:_endMatchLocal(CTBM.ENDSTATE.QUIT, payload)
end

function CTBM:uponDetectingAuthentication(fn)
  self._uponDetectingAuthentication = fn  
  self:_major("uponDetectingAuthentication handler set")
  -- If authentication already happened, fire immediately
  if fn and self.localPlayer and self.localPlayer.authenticated then
    self:_major("already authenticated at handler set-time; firing callback now")
    self._uponDetectingAuthentication()    
  end
end

function CTBM:_matchWithNSDataToDataTable(o__match)
  local decodedTable = nil
  self._lastReceivedDataTable = nil
  
  local data = o__match and o__match.matchData
  if not data or not data.bytes or data.length == 0 then
    self:log("CTBM: no match data found")    
    return nil
  end
  
  local function decodeJSONString(str, label)
    if not str or str == "" then return nil end
    local okDecode, decodedOrErr = pcall(function()
      return json.decode(str)
    end)
    if not okDecode then
      self:log("CTBM:", label, "json.decode failed:", tostring(decodedOrErr), "len=", tostring(data.length))
      return nil
    end
    if type(decodedOrErr) ~= "table" then
      self:log("CTBM:", label, "decoded match data is not table", type(decodedOrErr), "len=", tostring(data.length))
      return nil
    end
    return decodedOrErr
  end

  -- 1) Legacy path first for compatibility with previously written matches.
  local legacyStr = nil
  local okLegacyStr = pcall(function()
    local nsLegacy = objc.NSString:stringWithUTF8String_(data.bytes)
    if nsLegacy then legacyStr = tostring(nsLegacy) end
  end)
  if okLegacyStr then
    decodedTable = decodeJSONString(legacyStr, "legacy")
    if decodedTable then
      self._lastReceivedDataTable = decodedTable
      self:log("CTBM: decoded match data ok (legacy)", "len=", tostring(data.length))
      return decodedTable
    end
  else
    self:log("CTBM: legacy decode string conversion failed", "len=", tostring(data.length))
  end

  -- 2) Fallback: length-aware path (correct for NSData).
  local str = nil
  local okStr, errStr = pcall(function()
    local ns = objc.NSString:alloc():initWithData_encoding_(data, 4) -- NSUTF8StringEncoding
    if ns then str = tostring(ns) end
  end)
  if not okStr then
    self:log("CTBM: fallback decode string conversion failed:", tostring(errStr), "len=", tostring(data.length))
    return nil
  end

  decodedTable = decodeJSONString(str, "fallback")
  if not decodedTable then
    return nil
  end

  self._lastReceivedDataTable = decodedTable
  self:log("CTBM: decoded match data ok (fallback)", "len=", tostring(data.length))
  return decodedTable
end

function CTBM:_endMatchLocal(endState, payload)
  assert(self.currentMatch, "CTBM: no current match")
  
  if not self.isMyTurn then
    self:log("CTBM:end ignored: not my turn")
    return
  end
  
  if self:_isMatchEnded(self.currentMatch) then
    self:log("CTBM:_endMatchLocal ignored: already ended")
    return
  end
  
  self:_notifyGameCenterOfGameEnd(endState, payload)
end

function CTBM:_isMatchEnded(match)
  if not match or not match.participants then return false end
  
  for _,p in ipairs(match.participants) do
    local o = p.matchOutcome
    if o == objc.enum.GKTurnBasedMatchOutcome.won
    or o == objc.enum.GKTurnBasedMatchOutcome.lost
    or o == objc.enum.GKTurnBasedMatchOutcome.tied
    or o == objc.enum.GKTurnBasedMatchOutcome.quit then
      return true
    end
  end
  return false
end

function CTBM:_notifyGameCenterOfGameEnd(endState, payload)
  if not self.currentMatch then return end
  
  local match = self.currentMatch
  local data  = self:_dataTableToNSData(payload)
  
  ------------------------------------------------------------
  -- Apply match outcomes (except QUIT)
  ------------------------------------------------------------
  if endState ~= CTBM.ENDSTATE.QUIT then
    for i,p in ipairs(match.participants) do
      local isLocal = (p and p.playerID == self.localPlayer.playerID)
      
      if endState == CTBM.ENDSTATE.DRAW then
        p.matchOutcome = objc.enum.GKTurnBasedMatchOutcome.tied
        
      elseif endState == CTBM.ENDSTATE.WIN then
        p.matchOutcome = isLocal
        and objc.enum.GKTurnBasedMatchOutcome.won
        or  objc.enum.GKTurnBasedMatchOutcome.lost
        
      elseif endState == CTBM.ENDSTATE.LOSS then
        p.matchOutcome = isLocal
        and objc.enum.GKTurnBasedMatchOutcome.lost
        or  objc.enum.GKTurnBasedMatchOutcome.won
      end
    end
  end
  
  ------------------------------------------------------------
  -- Notify Game Center
  ------------------------------------------------------------
  if endState == CTBM.ENDSTATE.QUIT then
    local localId = self.localPlayer.playerID
    local nextParticipants = {}
    
    for _,p in ipairs(match.participants) do
      if p and p.playerID ~= localId then
        nextParticipants[#nextParticipants+1] = p
      end
    end
    
    match:participantQuitInTurnWithOutcome_nextParticipants_turnTimeout_matchData_completionHandler_(
    objc.enum.GKTurnBasedMatchOutcome.quit,
    nextParticipants,
    0,
    data,
    function(o__Error)
      if o__Error then
        self:log("CTBM: quit error:", o__Error.localizedDescription)
      else
        self:log("CTBM: quit sent")
      end
    end
    )
    
  else
    match:endMatchInTurnWithMatchData_completionHandler_(
    data,
    function(o__Error)
      if o__Error then
        self:log("CTBM: endMatch error:", o__Error.localizedDescription)
      else
        self:log("CTBM: endMatch sent")
        self:_finalizeGameEnd(match, payload, endState)
      end
    end
    )
  end
end

function CTBM:_finalizeGameEnd(match, payload, endState)
  local localId = self.localPlayer.playerID
  local localOutcome = nil
  local otherOutcome = nil
  
  for _,p in ipairs(match.participants or {}) do
    if p.playerID == localId then
      localOutcome = p.matchOutcome
    else
      otherOutcome = p.matchOutcome
    end
  end
  
  local outcome = localOutcome
  
  -- Fallback when Game Center hasn't populated matchOutcome yet
  if not outcome and endState then
    if endState == CTBM.ENDSTATE.WIN  then outcome = objc.enum.GKTurnBasedMatchOutcome.won  end
    if endState == CTBM.ENDSTATE.LOSS then outcome = objc.enum.GKTurnBasedMatchOutcome.lost end
    if endState == CTBM.ENDSTATE.DRAW then outcome = objc.enum.GKTurnBasedMatchOutcome.tied end
    if endState == CTBM.ENDSTATE.QUIT then outcome = objc.enum.GKTurnBasedMatchOutcome.quit end
  end
  
  ------------------------------------------------
  -- LOCAL PLAYER EVENTS
  ------------------------------------------------
  
  if outcome == objc.enum.GKTurnBasedMatchOutcome.won then
    self._onLocalPlayerWon(match, payload)
    
  elseif outcome == objc.enum.GKTurnBasedMatchOutcome.lost then
    self._onLocalPlayerLost(match, payload)
    
  elseif outcome == objc.enum.GKTurnBasedMatchOutcome.tied then
    self._onLocalPlayerTied(match, payload)
    
  elseif outcome == objc.enum.GKTurnBasedMatchOutcome.quit then
    self._onLocalPlayerQuit(match, payload)
  end
  
  ------------------------------------------------
  -- OTHER PLAYER EVENTS
  ------------------------------------------------
  
  if otherOutcome == objc.enum.GKTurnBasedMatchOutcome.quit then
    if self._onOtherPlayerQuit then self._onOtherPlayerQuit(match, payload) end
  end
  
  print("localOutcome =", localOutcome)
  print("endState =", endState)
  
  self.currentMatch = nil
  self.isMyTurn = false
  
  self:log("CTBM: ended match ", match.matchID)
end

function CTBM:_dataTableToNSData(dataTable)
  local nsData = nil
  if dataTable then
    local jsonStr = json.encode(dataTable)
    nsData = objc.string(jsonStr):dataUsingEncoding_(4) -- UTF8
  else
    nsData = objc.NSData:data_()
  end
  return nsData
end

function CTBM:findReadyMatch()
  self:log("CTBM: findReadyMatch")
  
  objc.GKTurnBasedMatch:loadMatchesWithCompletionHandler_(
  function(o__matches, o__err)
    if o__err then
      self:log("CTBM: loadMatches error:", o__err.localizedDescription)
      return
    end
    
    if not o__matches or #o__matches == 0 then
      self:log("CTBM: no matches found")
      return
    end
    
    local localId = self.localPlayer.playerID
    
    for _,m in ipairs(o__matches) do
      local cp = m.currentParticipant
      if cp and cp.playerID == localId then
        self:log("CTBM: ready match found:", m.matchID)
        
        self:_setCurrentMatch(m, "findReadyMatch")
        
        if self._onFindingReadyMatch then
          local dataTable = self:_matchWithNSDataToDataTable(m)
          self._onFindingReadyMatch(m, dataTable)
        end
        return
      end
    end
    
    self:log("CTBM: no ready matches (none are your turn)")
  end
  )
end

function CTBM:vernacularForTurnOwner()
  if not self.currentMatch then
    return "no current match"
  end
  
  local cp = self.currentMatch.currentParticipant
  if not cp then
    return "unassigned opponent"
  end
  
  local localId = self.localPlayer.playerID
  local pid = cp.playerID
  
  if not pid then
    return "unassigned opponent"
  end
  
  if pid == localId then
    return "me"
  end
  
  return "opponent"
end

function CTBM:clearAllMatches()
  self:log("CTBM: clearAllMatches requested")
  
  objc.GKTurnBasedMatch:loadMatchesWithCompletionHandler_(
  function(o__matches, o__error)
    if o__error then
      self:log("CTBM: loadMatches error:", o__error.localizedDescription)
      return
    end
    
    if not o__matches or #o__matches == 0 then
      self:log("CTBM: no matches to clear")
      if self._onMatchesCleared then
        self._onMatchesCleared(0)
      end
      return
    end
    
    local count = #o__matches
    self:log("CTBM: clearing", count, "matches")
    
    for i = 1, count do
      local m = o__matches[i]
      self:log("CTBM: removing match", m.matchID)
      
      m:removeWithCompletionHandler_(function(o__err)
        if o__err then
          self:log("CTBM: remove error:", o__err.localizedDescription)
        end
      end)
    end
    
    if self._onMatchesCleared then
      self._onMatchesCleared(count)
      self:log("CTBM: ran callback self._onMatchesCleared")
    end
  end
  )
end

function CTBM:_makeLocalPlayerListener()
  
  local PlayerListener = objc.delegate("GKLocalPlayerListener")
  local thisCTBM = self
  
  function PlayerListener:
    player_receivedTurnEventForMatch_didBecomeActive_(
    o__player,
    o__match,
    bDidBecomeActive
    )
    thisCTBM:_logMatchmakingEvent(
    "PLAYER_LISTENER_RECEIVED_TURN",
    o__match,
    "didBecomeActive=" .. tostring(bDidBecomeActive)
    )
    
    if not o__match then
      thisCTBM:log("CTBM: turn received with nil match")
      return
    end
    
    if not thisCTBM.currentMatch then
      thisCTBM:log(
      "CTBM: received turn event while not in match, setting as current match"
      )
    else
      thisCTBM:log("CTBM: refreshing current match from turn event", o__match and o__match.matchID)
    end
    thisCTBM:_setCurrentMatch(o__match, "player listener")
    
    local dataTable = thisCTBM:_matchWithNSDataToDataTable(o__match)
    
    thisCTBM:_logMatchmakingEvent("CALLBACK_onReceivingTurn reached", o__match)
    thisCTBM._onReceivingTurn(o__match, dataTable)
    
    thisCTBM:log(
    "CTBM: reached end of player_receivedTurnEventForMatch_didBecomeActive_"
    )
  end
  
  return PlayerListener()
end

function CTBM:showMatchmaker()
  self:log("CTBM: showMatchmaker requested")
  self:_major("showMatchmaker requested")
  -- Remember the locally selected rules in case a newly-created match comes
  -- back before any matchData exists yet.
  self.pendingRequestedBoardSize = boardSize
  self.pendingRequestedMinWordLen = MIN_WORD_LEN
  
  local request = objc.GKMatchRequest()
  request.minPlayers = 2
  request.maxPlayers = 2
  
  local vc = objc.GKTurnBasedMatchmakerViewController
  :alloc()
  :initWithMatchRequest_(request)
  
  self._matchmakerDelegate =
  self._matchmakerDelegate or self:_makeMatchmakerDelegate()
  
  vc.turnBasedMatchmakerDelegate = self._matchmakerDelegate
  
  self:_major("presenting matchmaker UI")
  self.viewController:presentModalViewController_animated_(vc, true)
end

function CTBM:_makeMatchmakerDelegate()
  local Delegate = objc.class("CTBMMatchmakerDelegate")
  local thisCTBM = self
  
  function Delegate:turnBasedMatchmakerViewControllerWasCancelled_(o__vc)
    thisCTBM:_logMatchmakingEvent("MM_DELEGATE_CANCELLED", nil)
    
    thisCTBM.viewController:dismissModalViewControllerAnimated_(true, nil)
    
    if thisCTBM._onMatchmakerCancelled then
      thisCTBM._onMatchmakerCancelled()
    end
  end
  
      function Delegate:turnBasedMatchmakerViewController_didFailWithError_(o__vc, o__err)
    thisCTBM:log(
    "CTBM: matchmaker error:",
        o__err and o__err.localizedDescription
    )
    
    thisCTBM.viewController:dismissModalViewControllerAnimated_(true, nil)
    
    if thisCTBM._onMatchmakerError then
          thisCTBM._onMatchmakerError(o__err)
    end
  end
  
  function Delegate:turnBasedMatchmakerViewController_didFindMatch_(o__vc, o__match)
    thisCTBM:_logMatchmakingEvent(
    "MM_DELEGATE_DID_FIND_MATCH",
        o__match,
    "(UI only)")
    
    
    thisCTBM.viewController:dismissModalViewControllerAnimated_(true, nil)
    thisCTBM:_logDismissedMatchState(o__match, "didFindMatch")
    
    -- NOTE: match may be nil here; authoritative delivery is via GKLocalPlayerListener
        if o__match then
          thisCTBM:_logMatchmakingEvent("MM_DELEGATE_MATCH_NONNIL", o__match, "(ignoring; waiting for player listener)")
    else
      thisCTBM:_logMatchmakingEvent("MM_DELEGATE_MATCH_NIL", nil, "(expected sometimes; waiting for player listener)")
    end
  end
  
  return Delegate()
end

function CTBM:_makeDeprecatedTurnBasedHandler()
  
  local handlerClass = objc.GKTurnBasedEventHandler
  if not handlerClass then
    self:_major("deprecated event handler class unavailable; skipping")
    return nil, nil
  end
  
  local handler = handlerClass:sharedTurnBasedEventHandler_()
  if not handler then
    self:_major("deprecated event handler instance unavailable; skipping")
    return nil, nil
  end
  
  local Delegate = objc.delegate("GKTurnBasedEventHandlerDelegate")
  if not Delegate then
    self:_major("GKTurnBasedEventHandlerDelegate unavailable; skipping deprecated delegate")
    return handler, nil
  end
  
  local this = self
  
  function Delegate:handleTurnEventForMatch_(oMatch)
    this:log("EVENTHANDLER: handleTurnEventForMatch",
    oMatch and oMatch.matchID)
  end
  
  function Delegate:handleMatchEnded_(oMatch)
    this:log("EVENTHANDLER: handleMatchEnded",
    oMatch and oMatch.matchID)
    
    if not oMatch then return end
    
    local data = this:_matchWithNSDataToDataTable(oMatch)
    local endState = this:_getEndStateFromMatch(oMatch)
    
    this:_finalizeGameEnd(oMatch, data, endState)
  end
  
  function Delegate:handleInviteFromGameCenter_(oPlayers)
    this:log("EVENTHANDLER: invite received")
  end
  
  local delegate = Delegate()
  if not delegate then
    self:_major("failed to instantiate deprecated delegate; skipping")
    return handler, nil
  end
  handler.delegate = delegate
  
  self:log("EVENTHANDLER installed")
  return handler, delegate
end

function CTBM:_authenticate()
  self:_major("_authenticate start", "localPlayer=", self.localPlayer ~= nil, "authenticated=", self.localPlayer and self.localPlayer.authenticated or false)
  if self.localPlayer.authenticated then
    self:_major("already authenticated before handler setup")
    self._uponDetectingAuthentication()
    self:log("CTBM: already authenticated, ran callback self._uponDetectingAuthentication")
    return
  end
  
  self.localPlayer.authenticateHandler = function(o__vc, o__err)
    self:_major("authenticateHandler callback", "vc=", o__vc ~= nil, "err=", o__err ~= nil, "authenticated=", self.localPlayer and self.localPlayer.authenticated or false)
    if o__err then
      self:_major("authenticateHandler error", o__err.localizedDescription or o__err)
      self:log("CTBM: authenticateHandler aborted with error: ", o__err)
      return
    end
    
    if o__vc then
      self:_major("presenting Game Center auth UI")
      self.viewController:presentModalViewController_animated_(o__vc, true)
      return
    end
    
    self:_major("authentication succeeded; firing app callback")
    self:_uponDetectingAuthentication()
    self:log("CTBM: authenticateHandler successful, ran callback self._uponDetectingAuthentication")
  end
end

function CTBM:findOrMakeMatch()
  
  local request = objc.GKMatchRequest()
  request.minPlayers = 2
  request.maxPlayers = 2
  
  objc.GKTurnBasedMatch:findMatchForRequest_withCompletionHandler_(
  request,
  function(o__match, o__err)
    if o__err then
      self:log("CTBM: findMatchForRequest aborted with error: ", o__err)
      return
    end
    
    if not o__match then
      self:log("CTBM: findMatchForRequest aborted because no match returned")
      return
    end
    
    self:log("CTBM: findMatchForRequest found ", o__match.matchID)
    self:_setCurrentMatch(o__match, "findOrMakeMatch")
  end
  )
end

function CTBM:_setCurrentMatch(o__match, setterString)
  if not o__match then
    self:_logMatchmakingEvent("SET_MATCH_SKIPPED_NIL", nil, "from=" .. tostring(setterString))
    return
  end
  
  self:_logMatchmakingEvent("SET_MATCH_ACCEPTED", o__match, "called from " .. tostring(setterString))
  
  self.currentMatch = o__match
  
  -- recompute turn ownership
  self.isMyTurn = self:vernacularForTurnOwner() == "me" or false
  
  -- decode any existing match data
  local dataTable = self:_matchWithNSDataToDataTable(o__match)
  
  -- notify "match found"
  self:_logMatchmakingEvent("CALLBACK_onSettingCurrentMatch reached", o__match)
  self._onSettingCurrentMatch(o__match, dataTable)
  
end

function CTBM:endTurnWithDataTable(t)
  if not self.currentMatch then
    self:log("CTBM: can't end turn because currentMatch is nil")
    return
  end
  
  if not self.isMyTurn then
    self:log("CTBM: can't end turn because it's not my turn")
    return
  end
  
  local localId = self.localPlayer.playerID
  local nextParticipants = {}
  
  for _,p in ipairs(self.currentMatch.participants) do
    if p and p.playerID ~= localId then
      table.insert(nextParticipants, p)
    end
  end
  
  if #nextParticipants == 0 then
    self:log("CTBM: no valid next participants")
    return
  end
  
  self:log("CTBM:endTurn -> passing turn on match ",
  self.currentMatch.matchID)
  
  local data = self:_dataTableToNSData(t)
  if t and type(t.__gcMessage) == "string" and t.__gcMessage ~= "" then
    self.currentMatch.message = t.__gcMessage
  end
  self.currentMatch: endTurnWithNextParticipants_turnTimeout_matchData_completionHandler_(
  nextParticipants,
  0,
  data,
  function(o__err)
    if o__err then
      self:log("CTBM:endTurn error:", o__err.localizedDescription)
    else    
      self:log("CTBM: endTurnWithNextParticipants succeeded")
      local sentDataTable = t or nil
      local associatedMatch = self.currentMatch
      
      self.currentMatch = nil
      self.isMyTurn = false
      
      self._onTurnEnded(
      associatedMatch,
      sentDataTable
      )
      
      self:log("CTBM: endTurnWithNextParticipants callback ended")
    end
  end
  )
end

function CTBM:_getEndStateFromMatch(match)
  if not match or not match.participants then return nil end
  
  local localId = self.localPlayer.playerID
  
  for i,p in ipairs(match.participants) do
    if p.playerID == localId then
      local o = p.matchOutcome
      
      if o == objc.enum.GKTurnBasedMatchOutcome.won  then return CTBM.ENDSTATE.WIN end
      if o == objc.enum.GKTurnBasedMatchOutcome.lost then return CTBM.ENDSTATE.LOSS end
      if o == objc.enum.GKTurnBasedMatchOutcome.tied then return CTBM.ENDSTATE.DRAW end
      if o == objc.enum.GKTurnBasedMatchOutcome.quit then return CTBM.ENDSTATE.QUIT end
    end
  end
  
  return nil
end
