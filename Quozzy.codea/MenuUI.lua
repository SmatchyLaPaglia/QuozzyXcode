function drawButton(x, y, w, h, label, selected)
  pushStyle()
  rectMode(CENTER)
  textMode(CENTER)
  fontSize(22)
  
  local fillCol   = selected and Color.uiAccent2 or Color.uiAccent
  local borderCol = fillCol
  drawRoundedRect(x, y, w, h, 10, fillCol, borderCol)
  
  -- high-contrast text on dark-ish button
  fill(255, 255, 255, 255)
  text(label, x, y)
  
  popStyle()
end

function pointInRect(px, py, x, y, w, h)
  return px >= x - w/2 and px <= x + w/2 and
  py >= y - h/2 and py <= y + h/2
end

function drawMenu()
  background(Color.bg)
  
  pushStyle()
  textMode(CENTER)
  fontSize(40)
  fill(Color.tileText)
  text("Quozzy", WIDTH/2, HEIGHT - 120)
  
  fontSize(22)
  fill(Color.tileText)
  text("Single-player • drag to form words", WIDTH/2, HEIGHT - 160)
  
  btnW, btnH = 260, 50
  
  local buttonCount = 4
  local gap = 14          -- tighter than before
  local stackH = buttonCount * btnH + (buttonCount - 1) * gap
  local topY = HEIGHT/2 + stackH/2
  
  local y = topY
  
  -- Start Game
  drawButton(WIDTH/2, y, btnW, btnH, "Play on yer Lonesome", false)
  y = y - (btnH + gap)
  
  -- Board Size
  drawButton(
  WIDTH/2,
  y,
  btnW,
  btnH,
  string.format("Board: %dx%d", boardSize, boardSize),
  false
  )
  y = y - (btnH + gap)
  
  -- Online Play
  drawButton(WIDTH/2, y, btnW, btnH, "Play a Mate", false)
  y = y - (btnH + gap)
  
  -- Records
  drawButton(WIDTH/2, y, btnW, btnH, "Records", recordsOverlay)
  
  popStyle()
  
  drawDictStatusMenu()
end

function handleMenuTouch(t)
  didSwipeOnPoofingText(t, menuSpecA, menuSpecB)
  if true then return end

  if t.state ~= ENDED then return end
  
  btnW, btnH = 260, 50
  local gap = 14
  local buttonCount = 4
  local stackH = buttonCount * btnH + (buttonCount - 1) * gap
  local topY = HEIGHT/2 + stackH/2
  
  local y = topY
  
  local startX, startY = WIDTH/2, y
  y = y - (btnH + gap)
  
  local sizeX, sizeY = WIDTH/2, y
  y = y - (btnH + gap)
  
  local onlineX, onlineY = WIDTH/2, y
  y = y - (btnH + gap)
  
  local recordsX, recordsY = WIDTH/2, y
  
  if pointInRect(t.x, t.y, startX, startY, btnW, btnH) then
    setTurnBasedEnabled(false)
    startRoundFromCurrentSettings()        
    return
  end
  
  if pointInRect(t.x, t.y, sizeX, sizeY, btnW, btnH) then
    -- toggle board size
    if boardSize == 4 then boardSize = 5 else boardSize = 4 end
    return
  end
  
  if pointInRect(t.x, t.y, onlineX, onlineY, btnW, btnH) then
    if tbm and tbm.showMatchmaker then
      tbm:showMatchmaker()
    end
    return
  end
  
  if pointInRect(t.x, t.y, recordsX, recordsY, btnW, btnH) then
    openRecordsOverlay()
    return
  end
end

