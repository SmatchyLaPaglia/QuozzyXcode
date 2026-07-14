endWordList        = endWordList        or ScrollList.new()
endCardScrollLists = endCardScrollLists or { ScrollList.new(), ScrollList.new(), ScrollList.new() }
endCardIndex       = endCardIndex       or 1
endCardAnimPx      = endCardAnimPx      or 0
endCardDragPx      = endCardDragPx      or 0
endCardDragTouchId = nil
endCardDragStartX  = 0
endCardDragStartY  = 0
endCardGestureMode = nil   -- nil, "swipe", or "scroll"
endCardCount       = 0
endScreenLastMatchId      = nil
endScreenHighlightedPath  = nil   -- path shown on mini-board when a word is tapped
endScreenHighlightedWord  = nil   -- word string for the highlighted row
endScreenCurrentCardWords = {}   -- words in the currently visible card (set each frame)
endCardAffordanceTouchId    = nil   -- touch tracking for adjacent-card sliver taps
endCardAffordanceTargetIdx  = nil   -- which card index the affordance tap is targeting

END_STATE_SINGLE        = 1
END_STATE_2P_INCOMPLETE = 2
END_STATE_2P_COMPLETE   = 3

function currentEndScreenState()
  --[[
  local opp = opponentKeyForCurrentMatch()
  print("currentEndScreenState: opponentKeyForCurrentMatch: ", opp)
  ]]
  if not useTurnBased then
    return END_STATE_SINGLE
  end
  
  local q = currentQMatch
  if not (q and q.players) then
    return END_STATE_2P_INCOMPLETE
  end
  
  local myId = localPID()
  for pid, p in pairs(q.players) do
    if pid ~= myId then
      if p and p.didPlay == true then
        return END_STATE_2P_COMPLETE
      else
        return END_STATE_2P_INCOMPLETE
      end
    end
  end
  
  -- Fallback: no opponent slot yet
  return END_STATE_2P_INCOMPLETE
end

function endScreenStateLabel()
  local s = currentEndScreenState()
  if s == END_STATE_SINGLE        then return "single-player" end
  if s == END_STATE_2P_INCOMPLETE then return "2P incomplete" end
  if s == END_STATE_2P_COMPLETE   then return "2P complete" end
  return "unknown"
end

AGAIN_LABELS = AGAIN_LABELS or {
  "Again!",
  "AgainAgainAgain!",
  "More More More",
  "Play More Now",
  "Play Again",
  "Fun Again Please",
  "Another?",
  "GAME HAPPEN MORE",
  "Tap To Play Again",
}

playAgainLabelIndex = playAgainLabelIndex or math.random(1, #AGAIN_LABELS)
playAgainLabel      = playAgainLabel      or AGAIN_LABELS[playAgainLabelIndex]

fallbackOppCameos = fallbackOppCameos or {}

function rotatePlayAgainLabel()
  playAgainLabelIndex = (playAgainLabelIndex % #AGAIN_LABELS) + 1
  playAgainLabel = AGAIN_LABELS[playAgainLabelIndex]
end

endScreenLayout = endScreenLayout or {}
endWordListMine  = endWordListMine  or ScrollList.new()
endWordListTheirs= endWordListTheirs or ScrollList.new()

function getCurrentOpponentKeyForEndScreen()
  local q = currentQMatch
  local myId = localPID()
  local otherId
  
  if q and q.players then
    for pid,_ in pairs(q.players) do
      if pid ~= myId then otherId = pid break end
    end
  end
  
  return otherId or q and (q.otherId or q.opponentId) or currentOpponentID,
  q and (q.otherName or q.opponentName) or opponentAlias or "Opponent"
end

function drawEndPinkRects(enabled, g)
  local pinkFill, pinkStroke, pr
  if not enabled or not g then return end
  
  pinkFill, pinkStroke = color(255,0,180,45), color(255,0,180,90)
  
  pr = function(cx, cy, w, h, r)
    if not (cx and cy and w and h) then return end -- never crash
    drawRoundedRect(cx, cy, w, h, r or 10, pinkFill, pinkStroke)
  end
  
  pushStyle()
  
  -- top row
  pr(g.rightCX, g.msgCY,   g.rightW,   g.msgH)
  pr(g.rightCX, g.scoreCY, g.rightW,   g.scoreH)
  pr(g.boardCX, g.boardCY, g.boardSide, g.boardSide)
  
  -- lists (2P layout only, but safe to call regardless if nil)
  pr(g.yourWordsCX,  g.listAreaCY, g.wordsColW, g.listAreaH)
  pr(g.theirWordsCX, g.listAreaCY, g.wordsColW, g.listAreaH)
  pr(g.yourWordsCX,  g.titlesCY,   g.wordsColW, g.titleH, 6)
  pr(g.theirWordsCX, g.titlesCY,   g.wordsColW, g.titleH, 6)
  
  -- buttons
  pr(g.nextVsCX,       g.nextVsCY,       g.nextVsW,       g.buttonH)
  pr(g.nextReceivedCX, g.nextReceivedCY, g.nextReceivedW, g.buttonH)
  
  popStyle()
end

-- Draws the board preview, win/lose (2P only) and score block
function drawEndTopRowContent(boardCX, boardCY, boardSide,
  rightCX, rightW,
  msgCY,  msgH,
  scoreCY, scoreH, avatars)
  
  local C, myScore, oppScore
  local msgCol, msgText, fs
  local label, scoreStr, numFS0, labelFS0, gap0, availW, s, numFS, labelFS, gap
  local labelW2, numW2, totalW, leftX, labelX, numX, bottomY
  local leftStr, midStr, rightStr, bottomY2, midFS0, wL, wR, wM, totalW0, midFS, wL2, wR2, wM2
  local xL, xM, xR, numH, midH, midY
  
  C = Color
  myScore  = score or 0
  oppScore = opponentScore
  
  -- board preview
  drawBoardPreview(boardCX, boardCY, boardSide)
  
  local endState = currentEndScreenState()
  local oppHasPlayed = (endState == END_STATE_2P_COMPLETE)
  
  -- Optional: keep opponentScore in sync when we can (only when complete)
  if oppHasPlayed then
    local q = currentQMatch
    local myId = localPID()
    local otherId = nil
    
    if q and q.players then
      for pid,_ in pairs(q.players) do
        if pid ~= myId then otherId = pid break end
      end
    end
    
    local themP = (q and q.players and otherId and q.players[otherId]) or nil
    if themP and type(themP.score) == "number" then
      opponentScore = themP.score
      oppScore = opponentScore
    end
  end
  
  -- -- ------------------------------------------------------------
  -- Message area (right/top)  [2P: avatars only, NO TEXT]
  -- ------------------------------------------------------------
  -- Message area (right/top): avatars only
  if useTurnBased then
    local topY    = msgCY   + msgH   * 0.5
    local bottomY = scoreCY - scoreH * 0.5
    local areaH   = math.max(1, topY - bottomY)
    local areaCY  = (topY + bottomY) * 0.5
    
    drawEndUpperRightAvatarsOnly{
      rightCX = rightCX,
      areaCY  = areaCY,
      rightW  = rightW,
      areaH   = areaH,
      opponentAvatar = avatars and avatars.opponentAvatar or nil
    }
  end
  
  -- ------------------------------------------------------------
  -- Score block (right/bottom)
  -- Old behavior if opponent played: X to Y
  -- New behavior if waiting: keep it empty (avoid “to nil”)
  -- ------------------------------------------------------------
  pushStyle()
  textMode(CENTER)
  
  if endState == END_STATE_SINGLE then
    -- single player unchanged
    label, scoreStr = "Score:", tostring(myScore)
    numFS0 = math.min(scoreH * 0.66, rightW * 0.4)
    labelFS0, gap0 = numFS0 * 0.75, scoreH * 0.10
    availW, s = rightW * 0.90, 1.0
    
    fontSize(labelFS0); labelW2 = textSize(label)
    fontSize(numFS0);   numW2   = textSize(scoreStr)
    totalW0 = labelW2 + gap0 + numW2
    if totalW0 > availW and totalW0 > 0 then s = availW / totalW0 end
    
    numFS, labelFS, gap = numFS0 * s, labelFS0 * s, gap0 * s
    
    fontSize(labelFS); labelW2 = textSize(label)
    fontSize(numFS);   numW2   = textSize(scoreStr)
    
    totalW = labelW2 + gap + numW2
    leftX  = rightCX - totalW * 0.5
    labelX, numX = leftX, leftX + labelW2 + gap
    bottomY = (scoreCY - scoreH * 0.5) + (boardSide * 0.05)
    
    textAlign(LEFT); textMode(CORNER)
    fill(C.tileText or color(40,80,60,255))
    
    fontSize(labelFS); drawTextIgnoringDescendersWithBottomAt(label,    labelX, bottomY)
    fontSize(numFS);   drawTextIgnoringDescendersWithBottomAt(scoreStr, numX,   bottomY)
  end
  
  popStyle()
end

function calculateEndScreenDimensions()
  local g, C, W, H, panelW, panelH, panelX, panelY, cornerRadius, innerPad, vGap, colGap,
  innerLeft, innerRight, innerTop, innerBottom, contentW,
  buttonH, yCursor, nextReceivedCX, nextReceivedCY, nextReceivedW, nextVsCX, nextVsCY, nextVsW,
  avatarFrac, avatarSize, opponentRowCY, opponentRowTop, oppAvatarW, oppStatsW, oppStatsCX, oppAvatarCX,
  remainingTop, remainingBot, remainingH, squareFrac, desiredSide, minListsH, maxTopRowH,
  boardSide, topRowH, listsH, topRowCY, listsTop,
  boardCX, boardCY, rightW, rightCX, msgH, scoreH, msgCY, scoreCY,
  closeSize, closeX, closeY,
  listTop, singleBtnCY, listBot, listH2
  
  g, C, W, H = endScreenLayout, Color, WIDTH, HEIGHT
  
  panelW, panelH, panelX, panelY = W-30, H-80, W*0.5, H*0.5
  cornerRadius, innerPad, vGap, colGap = 18, 16, 2, 2
  
  innerLeft  = panelX - panelW*0.5 + innerPad
  innerRight = panelX + panelW*0.5 - innerPad
  innerTop   = panelY + panelH*0.5 - innerPad
  innerBottom= panelY - panelH*0.5 + innerPad
  contentW   = innerRight - innerLeft
  
  buttonH = 60
  
  -- shared bottom button (1P + 2P)
  local playBtnX = innerLeft
  local playBtnY = innerBottom
  local playBtnW = contentW
  local playBtnH = buttonH
  
  -- yCursor starts ABOVE the button
  yCursor = playBtnY + playBtnH
  
  -- Thin totals row (replaces the old opponent row)
  local totalsH        = 34
  local padToButtons   = 12   -- padding between totals row and the top button
  local gapAboveTotals = 6    -- small gap between lists and totals row
  
  local totalsBottom = (playBtnY + playBtnH) + padToButtons
  local totalsCY     = totalsBottom + totalsH * 0.5
  local totalsTop    = totalsBottom + totalsH
  
  -- Treat this like the "opponent row" slot so the rest of the file stays stable
  opponentRowCY  = totalsCY
  opponentRowTop = totalsTop
  
  oppStatsW  = contentW
  oppStatsCX = panelX
  
  yCursor = opponentRowTop + gapAboveTotals
  
  remainingTop, remainingBot = innerTop, yCursor
  remainingH = remainingTop - remainingBot
  
  squareFrac, desiredSide, minListsH = 0.52, contentW*0.52, 100
  maxTopRowH = remainingH - vGap - minListsH
  if maxTopRowH < 80 then maxTopRowH = remainingH - vGap - 60 end
  if maxTopRowH < 40 then maxTopRowH = remainingH * 0.5 end
  
  boardSide = math.min(desiredSide, maxTopRowH)
  topRowH   = boardSide
  
  listsH = remainingH - topRowH - vGap
  if listsH < 60 then
    listsH = 60
    local newTop = remainingH - listsH - vGap
    if newTop < boardSide then boardSide, topRowH = newTop, newTop end
  end
  
  topRowCY = remainingTop - topRowH*0.5
  listsTop = remainingTop - topRowH - vGap
  
  boardCX, boardCY = innerLeft + boardSide*0.5, topRowCY
  
  rightW  = math.max(120, contentW - boardSide - colGap)
  rightCX = innerLeft + boardSide + colGap + rightW*0.5
  
  msgH   = topRowH*0.6
  scoreH = topRowH - msgH - vGap
  if scoreH < 40 then scoreH, msgH = 40, topRowH - 40 - vGap end
  
  msgCY   = innerTop - msgH*0.5
  scoreCY = (innerTop - msgH - vGap) - scoreH*0.5
  
  closeSize = 40
  closeX, closeY = innerRight + 6, innerTop + 8
  
  -- single-player list + button rects (cached too)
  listTop = listsTop
  
  -- anchor lists to shared bottom button
  local playBtnCY = playBtnY + playBtnH * 0.5
  listBot = (playBtnCY + playBtnH * 0.5) + vGap
  
  listH2 = math.max(40, listTop - listBot)
  
  local wordsColW, titleH, listsInnerGap, titlesCY, listAreaTop, listAreaH, listAreaCY,
  yourWordsCX, theirWordsCX
  
  local cameoH = 44
  wordsColW, titleH, listsInnerGap = (contentW - colGap) * 0.5, cameoH, vGap
  yourWordsCX, theirWordsCX = innerLeft + wordsColW * 0.5, innerRight - wordsColW * 0.5
  
  titlesCY    = listsTop - titleH * 0.5
  listAreaTop = listsTop - titleH - listsInnerGap
  listAreaH   = math.max(40, listsH - titleH - listsInnerGap)
  listAreaCY  = listAreaTop - listAreaH * 0.5
  
  g.wordsColW, g.titleH, g.titlesCY = wordsColW, titleH, titlesCY
  g.listAreaCY, g.listAreaH = listAreaCY, listAreaH
  g.yourWordsCX, g.theirWordsCX = yourWordsCX, theirWordsCX
  
  g.yourListRect  = { x = innerLeft,            y = listAreaTop - listAreaH, w = wordsColW, h = listAreaH }
  g.theirListRect = { x = innerRight-wordsColW, y = listAreaTop - listAreaH, w = wordsColW, h = listAreaH }

  -- Card layout: full-width single list with dot indicators at bottom
  local dotsH = 22
  g.cardW         = contentW
  g.cardHeaderCY  = titlesCY
  g.cardHeaderH   = titleH
  g.cardListRect  = {
    x = innerLeft,
    y = listAreaTop - listAreaH + dotsH,
    w = contentW,
    h = math.max(20, listAreaH - dotsH)
  }
  g.cardDotsY = listAreaTop - listAreaH + dotsH * 0.5
  g.cardPadV  = panelH / 20

  g._W, g._H, g._turn = W, H, useTurnBased
  
  g.panelW, g.panelH, g.panelX, g.panelY = panelW, panelH, panelX, panelY
  g.cornerRadius, g.innerPad, g.vGap, g.colGap = cornerRadius, innerPad, vGap, colGap
  
  g.innerLeft, g.innerRight, g.innerTop, g.innerBottom = innerLeft, innerRight, innerTop, innerBottom
  g.contentW, g.buttonH = contentW, buttonH
  
  g.nextReceivedCX, g.nextReceivedCY, g.nextReceivedW = nextReceivedCX, nextReceivedCY, nextReceivedW
  g.nextVsCX, g.nextVsCY, g.nextVsW = nextVsCX, nextVsCY, nextVsW
  
  g.oppStatsCX, g.oppStatsCY, g.oppStatsW, g.oppStatsH = oppStatsCX, opponentRowCY, oppStatsW, totalsH
  g.oppAvatarCX, g.oppAvatarCY, g.oppAvatarW, g.oppAvatarH = oppAvatarCX, opponentRowCY, oppAvatarW, avatarSize
  
  g.boardCX, g.boardCY, g.boardSide = boardCX, boardCY, boardSide
  g.rightCX, g.rightW, g.msgCY, g.msgH, g.scoreCY, g.scoreH = rightCX, rightW, msgCY, msgH, scoreCY, scoreH
  g.topToggleRect = {
    x = innerLeft,
    y = listsTop,
    w = contentW,
    h = innerTop - listsTop
  }
  
  g.closeX, g.closeY, g.closeSize = closeX, closeY, closeSize
  
  g.singleListRect = { x = innerLeft, y = listBot, w = contentW, h = listH2 }
  g.playAgainRect  = { x = innerLeft, y = innerBottom, w = contentW, h = buttonH }
end

function ensureEndScreenLayout()
  local g = endScreenLayout
  if g._W ~= WIDTH or g._H ~= HEIGHT or g._turn ~= useTurnBased then
    calculateEndScreenDimensions()
  end
end

function drawEndScreen()
  ensureEndScreenLayout()
  if true then
    drawEndScreenFP()
    return
  end
  
  -- ===== ORIGINAL IMPLEMENTATION BELOW =====
  -- (leave your existing drawEndScreen body here unchanged)
  
  dbgDidPlay("drawEndScreen", currentQMatch)
  local g,C,panelSprite,listRect,words,totalRows,lineH,baseX,btnCX,btnCY,padT,padB,yourR,theirR
  local q,myId,otherId,meP,themP,myWords,theirWords
  
  ensureEndScreenLayout()
  g,C = endScreenLayout,Color
  q = currentQMatch
  
  local endState = currentEndScreenState()
  local is2P = (endState ~= END_STATE_SINGLE)
  local oppComplete = (endState == END_STATE_2P_COMPLETE)
  endScreenSingleListRect,endScreenYourListRect,endScreenTheirListRect = nil,nil,nil
  
  pushStyle()
  fill(C.panelDim); noStroke(); rectMode(CORNER); rect(0,0,WIDTH,HEIGHT)
  popStyle()
  
  panelSprite = overlayPanelEnd
  if panelSprite then
    local c = C.panelBG or color(40,40,40,220)
    pushStyle()
    spriteMode(CENTER); tint(255,255,255,c.a or 255)
    sprite(panelSprite,g.panelX,g.panelY,g.panelW,g.panelH)
    popStyle()
  else
    drawRoundedRect(g.panelX,g.panelY,g.panelW,g.panelH,g.cornerRadius,
    C.panelBG or color(245,242,232,255),
    C.tileStroke or color(180,160,140,255))
  end
  
  drawEndTopRowContent(
  g.boardCX,g.boardCY,g.boardSide,
  g.rightCX,g.rightW,
  g.msgCY,g.msgH,
  g.scoreCY,g.scoreH,
  oppScoreEff
  )
  
  drawEndPinkRects(false,g)
  
  padT,padB = 6,10
  lineH = 28
  
  function asWordArray(src)
    local a,k,v
    if type(src)~="table" then return {} end
    if #src > 0 then return src end -- already an array
    a = {}
    for k,v in pairs(src) do
      if type(k)=="string" then
        a[#a+1] = k
      elseif type(v)=="string" then
        a[#a+1] = v
      elseif type(v)=="table" and v.word then
        a[#a+1] = v.word
      end
    end
    table.sort(a)
    return a
  end
  
  function drawRowFrom(wordsSrc)
    return function(row,y,x)
      local entry,w,pts,label
      entry = wordsSrc[row]
      if type(entry)=="table" then w,pts = entry.word or "",entry.points else w,pts = tostring(entry),nil end
      label = pts and string.format("%s  (+%d)",w,pts) or w
      pushStyle()
      textAlign(LEFT); textMode(CORNER); fontSize(24)
      fill(C.uiAccent or color(40,80,60,255))
      text(label,x,y)
      popStyle()
    end
  end
  
  -- canonical ids + player records (derive from q.players; don't trust legacy fields)
  myId = localPID()
  otherId = nil
  
  if q and q.players then
    for pid,_ in pairs(q.players) do
      if pid ~= myId then otherId = pid break end
    end
  end
  
  meP   = (q and q.players and q.players[myId]) or nil
  themP = (q and q.players and otherId and q.players[otherId]) or nil
  
  local opponentHasPlayed = oppComplete
  
  local myScoreEff = (meP and meP.score) or (score or 0)
  local oppScoreEff = oppComplete and ((themP and themP.score) or 0) or nil
  
  -- canonical word sources (with safe fallbacks)
  myWords = asWordArray(currentFoundWords())
  theirWords = asWordArray((themP and themP.words) or {})
  
  if endState == END_STATE_SINGLE then
    -- SINGLE PLAYER: use the SAME canonical source (players[myId].words) when present
    listRect,words = g.singleListRect,myWords
    if #words == 0 then words = {"(no words recorded)"} end
    
    totalRows,baseX = #words,listRect.x + 12
    
    listRect = {x=listRect.x,y=listRect.y+padB,w=listRect.w,h=listRect.h-padT-padB}
    endScreenSingleListRect = listRect
    endWordList:draw(listRect,totalRows,lineH,drawRowFrom(words),baseX)
    
    playAgainButtonRect = g.playAgainRect
    btnCX,btnCY = g.panelX,g.playAgainRect.y + g.playAgainRect.h*0.5
    
    drawRoundedRect(btnCX,btnCY,g.contentW,g.buttonH,22,C.uiAccent,C.uiAccent)
    fill(255); textMode(CENTER); textAlign(CENTER); fontSize(g.buttonH*0.34)
    text(playAgainLabel or "Play Again",btnCX,btnCY+1)
    
  else
    -- TWO PLAYER: left = myWords, right = theirWords (canonical players table)
    if #myWords == 0 then myWords = {"(no words recorded)"} end
    local oppNotPlayedString = "opponent hasn't played yet"
    if not oppComplete then
      theirWords = {oppNotPlayedString}
    elseif #theirWords == 0 then
      theirWords = {"(no words recorded)"}
    end
    
    yourR,theirR = g.yourListRect,g.theirListRect
    
    do
      local q = currentQMatch
      local myId = localPID()
      local otherId = nil
      
      if q and q.players then
        for pid,_ in pairs(q.players) do
          if pid ~= myId then otherId = pid break end
        end
      end
      
      local oppId   = otherId or currentOpponentID
      local oppName = opponentAlias or (q and (q.otherName or q.opponentName)) or "Opponent"
      
      -- pick images (no names)
      local myImg = localPlayerAvatar
      if not myImg then
        -- fallback cameo if GC avatar hasn’t loaded
        myImg = buildDefaultAvatarImage("Y")
      end
      
      local oppKey = oppId or oppName or "Opponent"
      
      local oppImg = nil
      if ensureAvatarForOpponent then
        oppImg = ensureAvatarForOpponent(oppId, oppName)
      end
      
      if not oppImg then
        if not fallbackOppCameos[oppKey] then
          local initial = string.upper(string.sub(oppName or "O", 1, 1))
          fallbackOppCameos[oppKey] = buildDefaultAvatarImage(initial)
        end
        oppImg = fallbackOppCameos[oppKey]
      end
      
      local cameoSize = math.min(g.titleH * 0.92, g.wordsColW * 0.28)
      
      drawEndWordColumnHeaders{
        yourCX  = g.yourWordsCX,
        theirCX = g.theirWordsCX,
        titlesCY = g.titlesCY,
        oppName = oppName,
        titleH  = g.titleH,
        color   = C.tileText or color(40,80,60,255)
      }
    end
    
    if yourR then
      local r = {x=yourR.x,y=yourR.y+padB,w=yourR.w,h=yourR.h-padT-padB}
      endScreenYourListRect = r
      endWordListMine:draw(r,#myWords,lineH,drawRowFrom(myWords),r.x+10)
    end
    
    if theirR then
      if not oppComplete then
        theirWords = {oppNotPlayedString}
      elseif #theirWords == 0 then
        theirWords = {"(no words recorded)"}
      end
      local r = {x=theirR.x,y=theirR.y+padB,w=theirR.w,h=theirR.h-padT-padB}
      endScreenTheirListRect = r
      endWordListTheirs:draw(r,#theirWords,lineH,drawRowFrom(theirWords),r.x+10)
    end
    
    -- ------------------------------------------------------------
    -- Opponent stats + avatar + two placeholder buttons (2P only)
    -- ------------------------------------------------------------
    do
      local q = currentQMatch
      local myId = localPID()
      local otherId = nil
      
      if q and q.players then
        for pid,_ in pairs(q.players) do
          if pid ~= myId then otherId = pid break end
        end
      end
      
      local oppId   = otherId or currentOpponentID or "?"
      local oppName = opponentAlias or (q and (q.otherName or q.opponentName)) or "Opponent"
      
      local rec = opponentRecords and opponentRecords[oppId]
      local w = rec and rec.wins
      local l = rec and rec.losses
      
      local me, them = resolveEndScreenScores(q)
      
      drawEndTotalsTwoLine{
        cx        = g.panelX,
        bottomCY = g.oppStatsCY,
        rowH     = g.oppStatsH,
        myScore  = me,
        oppScore = them,
        wins     = w,
        losses   = l,
        color    = C.tileText or color(40,80,60,255)
      }
      
      drawEndScreen2PButtonArea(
      g,
      "Play Another Match",
      C.uiAccent
      )
      
    end
  end
  
  pushStyle()
  ellipseMode(CENTER); noStroke(); fill(C.uiAccent)
  ellipse(g.closeX,g.closeY,g.closeSize,g.closeSize)
  fill(255); fontSize(g.closeSize*0.75); textMode(CENTER); textAlign(CENTER)
  text("×",g.closeX,g.closeY+2)
  popStyle()
end


function handleEndScreenTouch(t)
  local g,r

  if state ~= STATE_END then return false end
  ensureEndScreenLayout()
  g = endScreenLayout
  
  if t.state == ENDED and pointInRect(t.x,t.y,g.closeX,g.closeY,g.closeSize,g.closeSize) then
    if commitEndScreenCommentAndExit and shouldShowFinalCommentComposer and shouldShowFinalCommentComposer() then
      if commitEndScreenCommentAndExit() then
        return true
      end
    else
      if finalizeCompletedTurnBasedMatch then
        finalizeCompletedTurnBasedMatch(nil)
      end
      if teardownEndScreenCommentField then teardownEndScreenCommentField() end
      endScrollY,endScrollTouchId,endScrollPrevY = 0,nil,0
      startSeasonTransition()
      return true
    end
  end
  
  if t.state == BEGAN and g.topToggleRect then
    local r = g.topToggleRect
    if t.x >= r.x and t.x <= r.x + r.w and
       t.y >= r.y and t.y <= r.y + r.h then
      if currentQMatch and currentQMatch.players then
        local myId = localPID()
        local me = currentQMatch.players[myId] or {}
        local otherComment = ""
        for pid, pdata in pairs(currentQMatch.players) do
          if pid ~= myId and pdata and type(pdata.comment) == "string" then
            otherComment = pdata.comment
            break
          end
        end
        if (me.comment and me.comment ~= "") or otherComment ~= "" then
          endScreenSpeechBalloonsVisible = not endScreenSpeechBalloonsVisible
          return true
        end
      end
    end
  end
  
  if t.state == ENDED and endScreen2PButtonRect and shouldShowFinalCommentComposer and shouldShowFinalCommentComposer() then
    local r = endScreen2PButtonRect
    if t.x >= r.x and t.x <= r.x + r.w and
       t.y >= r.y and t.y <= r.y + r.h then
      endScreenCommentFocused = true
      setEndScreenCommentKeyboardVisible(true)
      return true
    end
  end
  
  -- card gesture handling: swipe between cards or scroll within a card
  local cr = g.cardListRect
  if cr then
    local inCardBand = (t.y >= cr.y and t.y <= cr.y + cr.h)
    local inCardArea = (t.x >= cr.x and t.x <= cr.x + cr.w and inCardBand)
    if t.state == BEGAN and inCardBand then
      local n = endCardCount or 0
      local inLeft  = t.x < WIDTH * 0.25
      local inRight = t.x > WIDTH * 0.75
      endCardDragTouchId = t.id
      endCardDragStartX  = t.x
      endCardDragStartY  = t.y
      endCardGestureMode = nil
      endCardAffordanceTouchId = t.id
      if (inLeft and endCardIndex > 1) or (inRight and endCardIndex < n) then
        endCardAffordanceTargetIdx = inRight and (endCardIndex + 1) or (endCardIndex - 1)
      else
        endCardAffordanceTargetIdx = nil
      end
      return true
    elseif t.id == endCardDragTouchId then
      local dx = t.x - endCardDragStartX
      local dy = t.y - endCardDragStartY
      if t.state == MOVING then
        -- Commit gesture direction once past threshold
        if endCardGestureMode == nil and (math.abs(dx) > 8 or math.abs(dy) > 8) then
          if math.abs(dx) >= math.abs(dy) then
            endCardGestureMode = "swipe"
          else
            endCardGestureMode = "scroll"
            -- Synthetic BEGAN so the scroll list tracks from the right start point
            local sl = endCardScrollLists and endCardScrollLists[endCardIndex]
            if sl then
              sl:touched({ state=BEGAN, x=endCardDragStartX, y=endCardDragStartY, id=t.id }, cr)
            end
          end
        end
        if endCardGestureMode == "swipe" then
          endCardDragPx = dx
          -- Rubber-band past the first/last card
          local n = endCardCount or 1
          if endCardIndex == 1 and endCardDragPx > 0 then endCardDragPx = endCardDragPx * 0.3 end
          if endCardIndex == n and endCardDragPx < 0 then endCardDragPx = endCardDragPx * 0.3 end
        elseif endCardGestureMode == "scroll" then
          local sl = endCardScrollLists and endCardScrollLists[endCardIndex]
          if sl then sl:touched(t, cr) end
        end
        return true
      elseif t.state == ENDED or t.state == CANCELLED then
        if endCardGestureMode == "swipe" then
          local n       = endCardCount or 1
          local cardW   = g.cardW or 100
          local threshold = cardW * 0.25
          local newIndex  = endCardIndex
          if endCardDragPx > threshold and newIndex > 1 then
            newIndex = newIndex - 1
          elseif endCardDragPx < -threshold and newIndex < n then
            newIndex = newIndex + 1
          end
          -- Kick off snap animation from where the drag left off
          endCardAnimPx = endCardDragPx + (newIndex - endCardIndex) * cardW
          endCardIndex  = newIndex
          endCardDragPx = 0
        elseif endCardGestureMode == "scroll" then
          local sl = endCardScrollLists and endCardScrollLists[endCardIndex]
          if sl then sl:touched(t, cr) end
        end
        -- Tap (no gesture committed): side affordance flips, otherwise detect row
        -- and toggle path highlight when tapping inside the actual card area.
        if endCardGestureMode == nil then
          local targetIdx = endCardAffordanceTargetIdx
          if targetIdx and targetIdx >= 1 and targetIdx <= (endCardCount or 0) then
            local cardW = g.cardW or 100
            endCardAnimPx = (targetIdx - endCardIndex) * cardW
            endCardIndex = targetIdx
          elseif inCardArea then
            local padT, padB, lineH = 6, 10, 28
            local padV  = g.cardPadV or 0
            local sl    = endCardScrollLists and endCardScrollLists[endCardIndex]
            local words = endScreenCurrentCardWords
            if sl and words and #words > 0 then
              local ry     = cr.y + padV + padB
              local rh     = cr.h - 2 * padV - padT - padB
              local firstY = ry + rh - lineH + (sl.scroll or 0)
              local topY   = firstY + lineH
              local row    = math.floor((topY - t.y) / lineH) + 1
              if row >= 1 and row <= #words then
                local e    = words[row]
                local word = type(e) == "table" and (e.word or "") or tostring(e or "")
                local path = (type(e) == "table" and e.path)
                          or (currentQMatch and currentQMatch.wordPaths and currentQMatch.wordPaths[string.upper(word)])
                if word == endScreenHighlightedWord then
                  endScreenHighlightedPath = nil
                  endScreenHighlightedWord = nil
                else
                  endScreenHighlightedPath = path
                  endScreenHighlightedWord = word
                end
              end
            end
          end
        end
        endCardDragTouchId = nil
        endCardGestureMode = nil
        endCardAffordanceTouchId = nil
        endCardAffordanceTargetIdx = nil
        return true
      end
    end
  end
  
  -- single-player "Again"
  if (not useTurnBased) and playAgainButtonRect and t.state == ENDED then
    r = playAgainButtonRect
    if t.x >= r.x and t.x <= r.x+r.w and t.y >= r.y and t.y <= r.y+r.h then
      rotatePlayAgainLabel()
      currentQMatch = nil
      endWordList.scroll,endWordList.vel,endWordList.dragId = 0,0,nil
      startRoundFromCurrentSettings()
      return true
    end
  end
  
  -- 2P button area
  if t.state == ENDED and endScreen2PButtonRect then
    local r = endScreen2PButtonRect
    if t.x >= r.x and t.x <= r.x+r.w and
    t.y >= r.y and t.y <= r.y+r.h then
      
      if endScreenButtonAction then
        endScreenButtonAction()
      end
      return true
    end
  end
  
  return true
end

function findAnyPendingMatchIndexExcludingOpponentKey(excludeKey)
  local list = pendingTurnMatches or {}
  for i = 1, #list do
    local m = list[i]
    local k = m and (m.otherId or m.opponentId or (m.otherName or m.opponentName or "Opponent"))
    if k and k ~= excludeKey then
      return i
    end
  end
  return nil
end
