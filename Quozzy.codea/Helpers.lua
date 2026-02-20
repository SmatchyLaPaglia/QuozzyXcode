-- Generic 1D inertial scrolling helper.
-- offset, velocity = applyScrollInertia(offset, velocity, minOffset, maxOffset, dt)
-- Exponential, velocity-based scroll inertia
-- scrollY: current offset
-- currentVel: pixels per second (set from swipe speed)
-- minY, maxY: scroll bounds
-- dt: DeltaTime
function applyScrollInertia(scrollY, currentVel, minY, maxY, dt)
    -- no inertia if we have no meaningful velocity
    if not currentVel or math.abs(currentVel) < 5 then
        return scrollY, 0
    end
    
    -- --------------------------------------------------------
    -- Exponential decay, roughly modeled after UIScrollView
    -- dv/dt = -k * v  → v(t) = v0 * e^(-k t)
    -- k picked so that an average fling dies out in ~0.5–0.7s
    -- --------------------------------------------------------
    local k = 2.0                         -- deceleration “strength” per second
    local decay = math.exp(-k * dt)       -- 0 < decay < 1
    currentVel = currentVel * decay       -- shrink velocity
    
    -- integrate position
    scrollY = scrollY + currentVel * dt
    
    -- clamp to bounds
    if scrollY < minY then
        scrollY = minY
        currentVel = 0
    elseif scrollY > maxY then
        scrollY = maxY
        currentVel = 0
    end
    
    -- hard stop when velocity is tiny so it doesn't creep
    if math.abs(currentVel) < 5 then
        currentVel = 0
    end
    
    return scrollY, currentVel
end

-- Return a flat { "T","E","S","T", ... } list of current tiles
function captureBoardTilesFromBoard()
    local tiles = {}
    if not board or not boardSize then return tiles end
    
    for r = 1, boardSize do
        local row = board[r]
        for c = 1, boardSize do
            local v = row and row[c] or "?"
            tiles[#tiles + 1] = v
        end
    end
    return tiles
end

-- Draw a mini-board inside a square preview area.
-- cx, cy  = centre of preview
-- side    = size of the square preview area
-- tiles   = optional flat list { "A","B",... } length N*N
-- n       = optional boardSize for these tiles (4 or 5). Defaults to global boardSize.
function drawBoardPreview(cx, cy, side, tiles, n)
    n = n or boardSize or 4
    
    -- Prefer match snapshot tiles for end-screen/replay contexts.
    if (not tiles or #tiles == 0) and currentQMatch and currentQMatch.boardTiles and #currentQMatch.boardTiles > 0 then
        tiles = currentQMatch.boardTiles
        n = currentQMatch.boardSize or n
    end
    
    -- Fall back to live board if no explicit/snapshot tiles are available.
    if not tiles or #tiles == 0 then
        tiles = captureBoardTilesFromBoard()
    end
    
    -- Last resort: infer n from tile count when possible.
    if tiles and #tiles > 0 then
        local inferred = math.floor(math.sqrt(#tiles))
        if inferred > 0 and inferred * inferred == #tiles then
            n = inferred
        end
    end
    
    if not n or n <= 0 then return end
    
    -- keep a small margin inside the preview rect
    local gridSide = side
    if gridSide <= 0 then return end
    
    local tileSize = gridSide / n
    local gridW    = gridSide
    local gridH    = gridSide
    
    local gridLeft = cx - gridW * 0.5
    local gridBot  = cy - gridH * 0.5
    
    pushStyle()
    pushMatrix()
    translate(cx, cy)
    
    rectMode(CENTER)
    textAlign(CENTER)
    textMode(CENTER)
    
    -- background exactly the size of the preview area
--[[
    local bgW = gridSide
    local bgH = gridSide
    local bgR = tileSize * 0.28
    
    local bgFill   = Color.gridBg
    local bgStroke = Color.gridBg
    
    drawRoundedRect(
    0, 0,
    bgW, bgH,
    bgR,
    bgFill,
    bgStroke
    )
]]
    
    fontSize(tileSize * 0.55)
    
    -- local grid extents, centered at (0,0)
    local gridLeft = -gridW * 0.5
    local gridBot  = -gridH * 0.5
    
    for row = 1, n do
        for col = 1, n do
            local idx   = (row - 1) * n + col
            local label = tiles[idx] or "?"
            
            local x = gridLeft + (col - 0.5) * tileSize
            local y = gridBot  + (row - 0.5) * tileSize
            
            -- simple static tiles, no path highlighting
            local fillCol   = Color.tileFill
            local strokeCol = Color.tileStroke
            
            drawRoundedRect(
            x, y,
            tileSize * 0.9,
            tileSize * 0.9,
            tileSize * 0.25,
            fillCol,
            strokeCol
            )
            
            fill(Color.tileLetter or color(255, 255, 255, 255))
            text(label, x, y)
        end
    end
    
    popMatrix()
    popStyle()
end

function ensureMyWordStore(q, pid)
    q = q or currentQMatch
    if not q then return nil, nil end
    
    pid = pid or q.playerId or localPID()
    q.playerId = pid
    
    q.players = q.players or {}
    q.players[pid] = q.players[pid] or {}
    q.players[pid].words = q.players[pid].words or {}
    q.players[pid].wordTimes = q.players[pid].wordTimes or {}
    
    return q.players[pid].words, q.players[pid].wordTimes
end

function drawCameoImage(img, cx, cy, size)
    if not (img and cx and cy and size) then return end
    
    pushStyle()
    spriteMode(CENTER)
    
    -- subtle frame/backing (keeps GK photos from looking harsh on light panels)
    noStroke()
    fill(0,0,0,25)
    ellipseMode(CENTER)
    ellipse(cx, cy, size * 1.08, size * 1.08)
    
    -- the image itself (your default avatars are already circular-on-transparent)
    tint(255)
    sprite(img, cx, cy, size, size)
    
    popStyle()
end

function dumpOpponentRecords()
  print("---- OPPONENT RECORDS ----")
  
  if not opponentRecords then
    print("(opponentRecords is nil)")
    return
  end
  
  local count = 0
  
  for oppId, rec in pairs(opponentRecords) do
    count = count + 1
    
    local name   = rec.name or rec.opponentName or tostring(oppId)
    local wins   = rec.wins
    local losses = rec.losses
    
    print(string.format(
    "%s  |  wins: %s  losses: %s",
    name,
    tostring(wins),
    tostring(losses)
    ))
  end
  
  if count == 0 then
    print("(no opponents recorded)")
  end
  
  print("---- END ----")
end

function currentFoundWords()
  myId = localPID()
  otherId = nil
  local q = currentQMatch
  if q and q.players then
    for pid,_ in pairs(q.players) do
      if pid ~= myId then otherId = pid break end
    end
  end
  meP   = (q and q.players and q.players[myId]) or nil
  return ensureMyWordStore(currentQMatch)
end
