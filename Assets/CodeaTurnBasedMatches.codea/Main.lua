status = {
  lastEvent      = "",
  matchId        = "--",
  authStatus     = "authenticating…",
  localPlayer    = "--",
  opponent       = "--",
  seatStatus     = "--",
  matchesCleared   = "--",
  lastSentData = "--",
  lastReceivedData = "--",
  gameEndedMatchId = "--",
  gameEndState     = "--",
  gameEndPayload   = "--"
}

matchmakerBtn = {
  w = 260,
  h = 56,
  x = 0,
  y = 0
}

function setup()

  viewer.mode = STANDARD
  local handlerDelegateType = objc.delegate("GKTurnBasedEventHandlerDelegate")
  local handlerDelegate = handlerDelegateType()
  -- CTBM initialization launches authentication immediately
  tbm = CTBM()
  tbm:setLogging(true)
  matchmakerBtn.x = WIDTH * 0.5
  matchmakerBtn.y = HEIGHT * 0.15
    
  -- callbacks for Game Center interactions
  tbm:uponDetectingAuthentication(function()
    -- if not authenticated, this fires after authentication, but if already authenticatned, this fires as soon as set
    status.authStatus  = "authenticated"
    status.localPlayer = tbm.localPlayer and tbm.localPlayer.alias or ""
    status.lastEvent   = "authenticated"
  end)  
  tbm: onSettingCurrentMatch(function(gkMatch, dataTable)
    status.matchId   = gkMatch.matchID or ""
    
    -- opponent (if available)
    local localId = tbm.localPlayer.playerID
    status.opponent = ""
    
    if gkMatch.participants then
      for _,p in ipairs(gkMatch.participants) do
        if p and p.playerID ~= localId then
          status.opponent = p.playerID or "unassigned"
          break
        end
      end
    end
    
    -- seat / turn status
    status.seatStatus =
    tbm.isMyTurn and "your turn" or "opponent turn"
    
    status.lastEvent = "currentMatch set"
    status.lastReceivedData = json.encode(dataTable)
    status.gameEndedMatchId = "--"
    status.gameEndState     = "--"
    status.gameEndPayload   = "--"
  end)  
  tbm: onReceivingTurn(function(gkMatch, dataTable)
    status.lastEvent = "data received"
    status.lastReceivedData = json.encode(dataTable)
  end)      
  tbm: onMatchesCleared(function(count)
    status.matchesCleared = count
    status.lastEvent = "cleared " .. tostring(count) .. " matches"
  end)
  tbm:onTurnEnded(function(match, data)
    status.matchId          = "--"
    status.opponent         = "--"
    status.lastEvent = "turn ended (confirmed)"
    status.lastSentData = json.encode(data)
    status.seatStatus = "opponent turn"
  end)
  tbm:onLocalPlayerWon(function(match, payload)
    print("running Main callback for local player won")
    status.lastEvent        = "local player won"
    status.gameEndedMatchId = match and match.matchID or "--"
    status.gameEndState     = "win"
    status.gameEndPayload   = json.encode(payload)
    
    status.lastReceivedData = "--"
    status.lastSentData     = "--"
    status.matchId          = "--"
    status.opponent         = "--"
    status.seatStatus       = "no active match"
  end)
  
  tbm:onLocalPlayerLost(function(match, payload)
    print("running Main callback for local player lost")
    status.lastEvent        = "local player lost"
    status.gameEndedMatchId = match and match.matchID or "--"
    status.gameEndState     = "loss"
    status.gameEndPayload   = json.encode(payload)
    
    status.lastReceivedData = "--"
    status.lastSentData     = "--"
    status.matchId          = "--"
    status.opponent         = "--"
    status.seatStatus       = "no active match"
  end)
  
  tbm:onLocalPlayerTied(function(match, payload)
    print("running Main callback for local player tied")
    status.lastEvent        = "local player tied"
    status.gameEndedMatchId = match and match.matchID or "--"
    status.gameEndState     = "draw"
    status.gameEndPayload   = json.encode(payload)
    
    status.lastReceivedData = "--"
    status.lastSentData     = "--"
    status.matchId          = "--"
    status.opponent         = "--"
    status.seatStatus       = "no active match"
  end)
  
  tbm:onLocalPlayerQuit(function(match, payload)
    print("running Main callback for local player quit")
    status.lastEvent        = "local player quit"
    status.gameEndedMatchId = match and match.matchID or "--"
    status.gameEndState     = "quit"
    status.gameEndPayload   = json.encode(payload)
    
    status.lastReceivedData = "--"
    status.lastSentData     = "--"
    status.matchId          = "--"
    status.opponent         = "--"
    status.seatStatus       = "no active match"
  end)
  
  tbm:onOtherPlayerQuit(function(match, payload)
    print("running Main callback for other player quit")
    status.lastEvent        = "opponent quit"
    status.gameEndedMatchId = match and match.matchID or "--"
    status.gameEndState     = "other quit"
    status.gameEndPayload   = json.encode(payload)
    
    status.lastReceivedData = "--"
    status.lastSentData     = "--"
    status.matchId          = "--"
    status.opponent         = "--"
    status.seatStatus       = "no active match"
  end)
  
  -- parameters setters 
  -- these illustrate how to use CTBM to interact with Game Center
  parameter.action("Find Any Match", function()
    tbm:findOrMakeMatch()
  end)
  parameter.action("Find Next Ready Match", function()
    tbm:findReadyMatch()
  end)
  parameter.action("Clear Game Center Matches", function()
    tbm:clearAllMatches()
  end)
  parameter.action("End Turn with Test Data", function()
    local payload = {
      msg = "hello",
      time = ElapsedTime
    }
    tbm:endTurnWithDataTable(payload)
    if tbm.currentMatch then
      status.lastSentData = json.encode(payload)
    end
  end)
  parameter.action("End Turn with No Data", function()
    status.lastSentData = "nil"
    tbm:endTurnWithDataTable(nil)
  end)
  parameter.action("End Match: WIN", function()
    tbm:localPlayerWon({ reason = "test win" })
  end)
  
  parameter.action("End Match: LOSS", function()
    tbm:localPlayerLost({ reason = "test loss" })
  end)
  
  parameter.action("End Match: DRAW", function()
    tbm:localPlayerTied({ reason = "test draw" })
  end)
  
  parameter.action("End Match: QUIT", function()
    tbm:localPlayerQuit({ reason = "test quit" })
  end)
end

function draw()
  background(30)
  
  local lines = {
    {"Authentication", status.authStatus},
    {"Local player",    status.localPlayer},
    {"Match ID",        status.matchId},
    {"Opponent",        status.opponent},
    {
      "player turn",
      status.gameEndedMatchId ~= "--"
      and "game ended"
      or tbm:vernacularForTurnOwner()
    },
    {"# matches cleared", status.matchesCleared},
    {"Last event",      status.lastEvent},
    {"Last sent data",     status.lastSentData},
    {"Last received data", status.lastReceivedData},
    {"Match ended", status.gameEndedMatchId},
    {"End state",         status.gameEndState},
    {"End payload",       status.gameEndPayload},
  }
  
  local x = WIDTH/2 - 90
  local y = HEIGHT * 0.9
  local lineH = 22

  fill(255)
  textAlign(LEFT)
  textWrapWidth = WIDTH * 0.5
  textMode(CORNER)
  
  for _,line in ipairs(lines) do
    local label, value = line[1], line[2] or ""
    
    -- label
    fontSize(16)
    text(label .. ":", x, y)
    fontSize(20)
    y = y - lineH
    
    if label == "Match ID" and value ~= "" then
      local chunkSize = 18
      local i = 1
      while i <= #value do
        local chunk = value:sub(i, i + chunkSize - 1)
        text("  " .. chunk, x, y)
        y = y - lineH
        i = i + chunkSize
      end
      
    elseif label == "Last sent data"
    or label == "Last received data"
    or label == "End payload"
    or label == "Match ended"
    then
      y = drawWrappedText(
      value,
      x,
      y,
      WIDTH - x - 40, -- hard right margin
      lineH
      )
      
    else
      text("  " .. value, x, y)
      y = y - lineH
    end
    
    y = y - 6
  end
  
  -- Matchmaker button
  pushStyle()
  rectMode(CENTER)
  
  fill(60, 140, 200)
  noStroke()
  rect(
  matchmakerBtn.x,
  matchmakerBtn.y,
  matchmakerBtn.w,
  matchmakerBtn.h,
  12
  )
  
  fill(255)
  textAlign(CENTER)
  textMode(CENTER)
  fontSize(20)
  text(
  "Show Matchmaker",
  matchmakerBtn.x,
  matchmakerBtn.y
  )
  popStyle()
end

function drawWrappedText(str, x, y, maxWidth, lineH)
  local line = ""
  local cursorY = y
  
  for i = 1, #str do
    local c = str:sub(i, i)
    local test = line .. c
    local w = textSize(test)
    
    if w > maxWidth then
      text("  " .. line, x, cursorY)
      cursorY = cursorY - lineH
      line = c
    else
      line = test
    end
  end
  
  if line ~= "" then
    text("  " .. line, x, cursorY)
    cursorY = cursorY - lineH
  end
  
  return cursorY
  end
  
function touched(t)
  if t.state ~= BEGAN then return end
  
  local b = matchmakerBtn
  if math.abs(t.x - b.x) <= b.w * 0.5
  and math.abs(t.y - b.y) <= b.h * 0.5 then
    tbm:showMatchmaker()
  end
end