function getEndUpperRightAvatarLayout(args)
  local cameoSize = math.min(args.rightW, args.areaH) * 0.62
  local dx = args.rightW * 0.14
  local dy = args.areaH  * 0.12
  
  local xNudge1, xNudge2 = 5, 10

  -- Originator (first speaker / opponent, top balloon) sits on the LEFT of the
  -- cluster; responder (second speaker / local, bottom balloon) sits on the
  -- RIGHT, so the responder balloon's tail is the rightmost and overlaps the
  -- least of the first balloon's text while staying inside its boundary.
  return {
    opponentX = args.rightCX - dx + xNudge1,
    opponentY = args.areaCY + dy,
    localX = args.rightCX + dx + xNudge2,
    localY = args.areaCY - dy * 0.45,
    opponentSize = cameoSize,
    localSize = cameoSize * 0.92,
  }
end

function drawEndUpperRightAvatarsOnly(args)
  local layout = getEndUpperRightAvatarLayout(args)
  
  local oppImg = args.opponentAvatar or otherPlayerAvatar
  
  pushStyle()
  drawAvatarCircle(oppImg, layout.opponentX, layout.opponentY, layout.opponentSize, "O")
  drawAvatarCircle(localPlayerAvatar, layout.localX, layout.localY, layout.localSize, "Y")
  popStyle()
end

function drawEndWordColumnHeaders(args)
  -- args:
  --  yourCX, theirCX, titlesCY
  --  oppName
  --  titleH
  --  color
  
  pushStyle()
  fill(args.color)
  textAlign(CENTER)
  textMode(CENTER)
  fontSize(args.titleH * 0.45)
  
  text("you", args.yourCX, args.titlesCY)
  text(args.oppName or "opponent", args.theirCX, args.titlesCY)
  
  popStyle()
end

function drawEndTotalsTwoLine(args)
  -- args:
  --  cx, bottomCY, rowH
  --  myScore, oppScore
  --  wins, losses
  --  color

  local cx      = args.cx
  local centerY = args.bottomCY
  local rowH    = args.rowH
  
  pushStyle()
  fill(args.color)
  textAlign(LEFT)
  textMode(CORNER)
  
  local lines = {}
  
  -- LINE 1 (ALWAYS FIRST): Score this game
  if args.myScore ~= nil and args.oppScore ~= nil then
    lines[#lines + 1] = {
      label = "Score this game:",
      value = tostring(args.myScore) .. " / " .. tostring(args.oppScore),
      fontSize = 22,
      fontName = "HelveticaNeue-Medium"
    }
  end
  
  -- LINE 2 (ALWAYS SECOND): Win/Loss vs player
  do
    local w, l = normalizeWinTotals(
    args.wins,
    args.losses,
    args.myScore,
    args.oppScore
    )
    
    lines[#lines + 1] = {
      label = "Win/Loss vs This Player:",
      value = tostring(w) .. " / " .. tostring(l),
      fontSize = 16,
      fontName = nil
    }
  end
  
  if #lines == 0 then
    popStyle()
    return
  end
  
  -- Measure vertical stack
  local lineGap = 4
  local totalH = 0
  local heights = {}
  
  for i, line in ipairs(lines) do
    fontSize(line.fontSize)
    if line.fontName then font(line.fontName) end
    local _, h = textSize("88")
    heights[i] = h
    totalH = totalH + h
    if i < #lines then
      totalH = totalH + lineGap
    end
  end
  
  -- Vertically center the whole block
  local y = centerY
  
  for i, line in ipairs(lines) do
    fontSize(line.fontSize)
    if line.fontName then font(line.fontName) end
    
    local wLabel = textSize(line.label)
    local wValue = textSize(line.value)
    local x = cx - (wLabel + 8 + wValue) * 0.5
    
    drawTextIgnoringDescendersWithBottomAt(line.label, x, y)
    drawTextIgnoringDescendersWithBottomAt(line.value, x + wLabel + 8, y)
    
    y = y - heights[i] + lineGap
  end
  
  popStyle()
end

function resolveEndScreenScores(q)
  local myScore = score or 0
  local oppScore = nil
  
  if q and q.players then
    local myId = localPID()
    for pid,p in pairs(q.players) do
      if pid ~= myId and type(p.score) == "number" then
        oppScore = p.score
        break
      end
    end
  end
  
  return myScore, oppScore
end

function normalizeWinTotals(myWins, oppWins, myScore, oppScore)
  myWins  = myWins  or 0
  oppWins = oppWins or 0
  
  myScore  = myScore  or 0
  oppScore = oppScore or 0
  
  if myScore > oppScore then
    if myWins == 0 then myWins = 1 end
  elseif oppScore > myScore then
    if oppWins == 0 then oppWins = 1 end
  end
  
  return myWins, oppWins
end

function drawEndScreen2PButtonArea(g, label, color)
  local cx = g.panelX
  local cy = g.playAgainRect.y + g.playAgainRect.h * 0.5
  local w  = g.contentW
  local h  = g.buttonH
  
  endScreen2PButtonRect = {
    x = cx - w * 0.5,
    y = cy - h * 0.5,
    w = w,
    h = h
  }
  
  drawRoundedRect(cx, cy, w, h, 22, color, color)
  
  pushStyle()
  fill(255)
  textMode(CENTER)
  textAlign(CENTER)
  fontSize(h * 0.32)
  text(label, cx, cy + 1)
  popStyle()
end
