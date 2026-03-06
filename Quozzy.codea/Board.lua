--####################################################################
-- Boggle Dice / Board Generation
--####################################################################

-- New Boggle (4x4) dice (16 dice) – "New Boggle" distribution
-- (Q on die is treated as "Qu" tile visually/semantically)
DICE_4x4 = {
    "AAEEGN",
    "ABBJOO",
    "ACHOPS",
    "AFFKPS",
    "AOOTTW",
    "CIMOTU",
    "DEILRX",
    "DELRVY",
    "DISTTY",
    "EEGHNW",
    "EEINSU",
    "EHRTVW",
    "EIOSST",
    "ELRTTY",
    "HIMNUQ", -- original has "HIMNUQu"; we treat Q as Qu
    "HLNNRZ"
}

-- Big Boggle 5x5 dice (25 dice)
-- (lowercase from reference; we uppercase and treat q as "Qu")
DICE_5x5 = {
    "AAAFRS",
    "AAEEEE",
    "AAFIRS",
    "ADENNN",
    "AEEEEM",
    "AEEGMU",
    "AEGMNN",
    "AFIRSY",
    "BJKQXZ",
    "CCENST",
    "CEIILT",
    "CEILPT",
    "CEIPST",
    "DDHNOT",
    "DHHLOR",
    "DHLNOR",
    "DHLNOR",
    "EIIITT",
    "EMOTTT",
    "ENSSSU",
    "FIPRSY",
    "GORRVW",
    "IPRRRY",
    "NOOTUW",
    "OOOTTU"
}

inGameWordList = inGameWordList or ScrollList.new()

wordNewAnim   = wordNewAnim or nil
lastWordAnimT = lastWordAnimT or 0

function getWordListLayout()
    local safeTopY = getTopSafeY()
    local tileSize, startX, startY = computeGridLayout()
    local boardTopY = startY + boardSize * tileSize
    
    -- HUD row is at safeTopY - 32 in drawTopHUD
    local hudTopY = safeTopY - 32
    
    -- label sits a little below the HUD
    local labelY = hudTopY - 28
    
    -- TOP of list area: only ~8px under the label
    local gapLabelToList = 8
    local viewTop = labelY - gapLabelToList
    
    -- BOTTOM of list area: a bit above the board
    -- (move this UP a little compared to before)
    local gapToBoard = 20   -- tweak to taste (18–22 range)
    local viewBot = boardTopY + gapToBoard
    
    -- height of list viewport
    local viewH = viewTop - viewBot
    if viewH < 60 then viewH = 60 end   -- safety so it never collapses
    
    return labelY, viewTop, viewBot, viewH
end

function isInWordListRegion(x, y)
    local labelY, viewTop, viewBot, viewH = getWordListLayout()
    return x >= sideMargin - 20 and x <= WIDTH * 0.6
    and y >= viewBot and y <= viewTop
end

function shuffle(t)
    for i = #t, 2, -1 do
        local j = math.random(i)
        t[i], t[j] = t[j], t[i]
    end
end

function getTopSafeY()
    if layout and layout.safeArea then
        -- safe area top inset subtracts from HEIGHT
        return HEIGHT - layout.safeArea.top
    else
        return HEIGHT
    end
end

function getBottomSafeY()
    if layout and layout.safeArea then
        return layout.safeArea.bottom
    else
        return 0
    end
end

function generateBoardTiles(n, dice4x4, dice5x5)
    local dice = (n == 4) and dice4x4 or dice5x5
    local diceCopy = {}
    for i = 1, #dice do diceCopy[i] = dice[i] end
    shuffle(diceCopy)
    
    local tiles = {}
    local idx = 1
    for i = 1, n*n do
        local die = diceCopy[idx]
        idx = idx + 1
        
        local faceIndex = math.random(#die)
        local ch = string.upper(die:sub(faceIndex, faceIndex))
        tiles[i] = (ch == "Q") and "Qu" or ch
    end
    return tiles
end

function inferBoardSizeFromTiles(tiles)
    if type(tiles) ~= "table" then return nil end
    local len = #tiles
    if len == 16 then return 4 end
    if len == 25 then return 5 end
    return nil
end

function areBoardTilesValidForSize(tiles, n)
    if type(tiles) ~= "table" then return false end
    if n ~= 4 and n ~= 5 then return false end
    if #tiles ~= n * n then return false end
    for i = 1, #tiles do
        local t = tiles[i]
        if type(t) ~= "string" or t == "" then
            return false
        end
    end
    return true
end

function buildBoardFromTiles(tiles, n)
    board = {}
    tileRects = {}
    
    local idx = 1
    for r = 1, n do
        board[r] = {}
        tileRects[r] = {}
        for c = 1, n do
            board[r][c] = tiles[idx] or "?"
            idx = idx + 1
        end
    end
end

function ensureBoardTilesForQMatch(q)
  local size = q.boardSize or boardSize or 4
  
  if areBoardTilesValidForSize(q.boardTiles, size) then
    return q.boardTiles
  end

  local inferred = inferBoardSizeFromTiles(q.boardTiles)
  if inferred and areBoardTilesValidForSize(q.boardTiles, inferred) then
    q.boardSize = inferred
    return q.boardTiles
  end
  
  local tiles = generateBoardTiles(size, DICE_4x4, DICE_5x5)
  q.boardTiles = tiles
  q.boardSize = size
  return tiles
end

function generateBoard(currentQMatch)
    local q = currentQMatch
    local size = (q and q.boardSize) or boardSize or 4
    local tiles = ensureBoardTilesForQMatch(q)
    -- Keep global layout state aligned with the match we are rendering.
    boardSize = size
    buildBoardFromTiles(tiles, size)
end

--####################################################################
-- Layout and Drawing Helpers
--####################################################################

function computeGridLayout()
    usableWidth  = WIDTH  - 2 * sideMargin
    local usableHeight = HEIGHT - topMargin - bottomMargin
    local tileSize = math.min(usableWidth / boardSize, usableHeight / boardSize)
    
    local gridWidth  = tileSize * boardSize
    local gridHeight = tileSize * boardSize
    
    local startX = WIDTH/2  - gridWidth/2
    local startY = bottomMargin * 1.45
    
    return tileSize, startX, startY
end

function drawRoundedRect(x, y, w, h, r, fillCol, strokeCol)
    pushStyle()
    
    -- CENTER → CORNER
    local cx, cy = x - w/2, y - h/2
    
    -- choose colors
    local fc = fillCol or color(255)
    local sc = strokeCol or fillCol or color(255)
    
    fill(fc)
    stroke(sc)
    
    rectMode(CORNER)
    noSmooth()
    
    local insetPos  = vec2(cx + r, cy + r)
    local insetSize = vec2(w - 2*r, h - 2*r)
    rect(insetPos.x, insetPos.y, insetSize.x, insetSize.y)
    
    if r > 0 then
        smooth()
        lineCapMode(ROUND)
        strokeWidth(r * 2)
        
        -- top
        line(insetPos.x, insetPos.y,
        insetPos.x + insetSize.x, insetPos.y)
        -- bottom
        line(insetPos.x, insetPos.y + insetSize.y,
        insetPos.x + insetSize.x, insetPos.y + insetSize.y)
        -- left
        line(insetPos.x, insetPos.y,
        insetPos.x, insetPos.y + insetSize.y)
        -- right
        line(insetPos.x + insetSize.x, insetPos.y,
        insetPos.x + insetSize.x, insetPos.y + insetSize.y)
    end
    
    popStyle()
end

function buildTileRects()
    local tileSize, startX, startY = computeGridLayout()
    
    tileRects = tileRects or {}
    
    for r = 1, boardSize do
        tileRects[r] = tileRects[r] or {}
        for c = 1, boardSize do
            tileRects[r][c] = {
                x = startX + (c - 0.5) * tileSize,
                y = startY + (r - 0.5) * tileSize,
                w = tileSize,
                h = tileSize
            }
        end
    end
end

function tileInCurrentPath(r, c)
    for i, step in ipairs(currentPath) do
        if step.r == r and step.c == c then
            return true
        end
    end
    return false
end

function drawBoard()
    local tileSize, startX, startY = computeGridLayout()
    buildTileRects()
    
    pushStyle()
    rectMode(CENTER)
    textAlign(CENTER)
    textMode(CENTER)
    fontSize(tileSize * 0.45)
    
    -- rounded grid background with higher contrast
    local bgW = boardSize * tileSize + 28
    local bgH = boardSize * tileSize + 28
    local bgX = WIDTH/2
    local bgY = startY + (boardSize * tileSize)/2
    
    local bgFill   = Color.gridBg
    local bgStroke = Color.gridBg
    
    drawRoundedRect(
    bgX, bgY,
    bgW, bgH,
    tileSize * 0.28,     -- corner radius
    bgFill,
    bgStroke
    )
    
    for r = 1, boardSize do
        for c = 1, boardSize do
            local tr = tileRects[r][c]
            local x, y, w, h = tr.x, tr.y, tr.w, tr.h
            
            local inPath = tileInCurrentPath(r, c)
            
            local inPath = tileInCurrentPath(r, c)
            
            local fillCol   = inPath and Color.uiAccent2 or Color.tileFill
            local strokeCol = inPath and Color.selectLineAlsoWeirdlyTileHighlight or Color.tileStroke
            
            drawRoundedRect(x, y, w * 0.9, h * 0.9, w * 0.25, fillCol, strokeCol)
            
            local label
            if state == STATE_READY then
                label = "?"
            else
                label = board[r][c]
            end
            
            if inPath then
                fill(Color.tileLetterHighlight)
            else
                fill(Color.tileLetter or color(255, 255, 255, 255))
            end
            text(label, x, y)
        end
    end
    
    popStyle()
end

function drawReadyMessage()
    if state ~= STATE_READY then return end
    
    pushStyle()
    textMode(CENTER)
    textAlign(CENTER)
    
    local tileSize, startX, startY = computeGridLayout()
    
    -- Grid dims exactly like before
    local gridW = boardSize * tileSize
    local gridH = boardSize * tileSize
    local bgW  = gridW + 28
    local bgH  = gridH + 28
    local bgX  = WIDTH/2
    local bgY  = startY + gridH/2
    
    -- EXACT SAME POSITION:
    local panelX = bgX
    local panelY = bgY + bgH/2
    
    local fs = tileSize * 0.35
    fontSize(fs)

    local knownOpponent =
      useTurnBased and
      currentOpponentID and currentOpponentID ~= "" and currentOpponentID ~= "?" and
      opponentAlias and opponentAlias ~= "" and opponentAlias ~= "Opponent"

    if knownOpponent then
      local line1 = "Match ready versus"
      local line2 = tostring(opponentAlias)
      local w1, h1 = textSize(line1)
      local w2, h2 = textSize(line2)
      local padX = tileSize * 0.8
      local padY = tileSize * 0.55
      local panelW = math.max(w1, w2) + padX * 2
      local panelH = (h1 + h2) + padY * 2 + (tileSize * 0.12)
      local panelR = tileSize * 0.25

      tint(255, 241)
      drawRoundedRect(
        panelX, panelY,
        panelW, panelH,
        panelR,
        Color.selectLineAlsoWeirdlyTileHighlight,
        Color.selectLineAlsoWeirdlyTileHighlight
      )

      fill(Color.tileLetter)
      local lineGap = tileSize * 0.08
      local y1 = panelY + (h2 + lineGap) * 0.5
      local y2 = panelY - (h1 + lineGap) * 0.5
      text(line1, panelX, y1)
      text(line2, panelX, y2)
    else
      -- Draw sprite exactly where the rect used to be
      spriteMode(CENTER)
      tint(255, 241)
      sprite(readyTapPanel, panelX, panelY)
      
      -- Draw the text on top (same font size as before)
      fill(Color.tileLetter)
      text("Tap anywhere\nto start", panelX, panelY)
    end
    
    popStyle()
end

function drawSelectionPath()
    if not pathActive or #currentPath == 0 then return end
    
    pushStyle()
    
    -- bright cyan-white, always visible regardless of theme
    stroke(color(120, 255, 255, 180))
    strokeWidth(10)
    lineCapMode(ROUND)
    
    local prevCx, prevCy
    for i, step in ipairs(currentPath) do
        local tr = tileRects[step.r][step.c]
        local cx, cy = tr.x, tr.y
        if i > 1 then
            line(prevCx, prevCy, cx, cy)
        end
        prevCx, prevCy = cx, cy
    end
    
    popStyle()
end

function drawTopHUD()
    pushStyle()
    textMode(CORNER)
    fill(40, 80, 60, 255)
    
    local safeTopY = getTopSafeY()
    local hudTopY  = safeTopY - 32   -- row for timer/score
    
    ------------------------------------------------
    -- Font sizes (numbers ~26, labels 3/4 of that)
    ------------------------------------------------
    local numSize = math.floor(WIDTH * 0.035 + 0.5)
    if numSize < 22 then numSize = 22 end
    if numSize > 28 then numSize = 28 end
    local labelSize = math.floor(numSize * 0.75 + 0.5)
    
    ------------------------------------------------
    -- TIME (left)
    ------------------------------------------------
    local timeLabel = "Time:"
    fontSize(labelSize)
    local timeLabelW, timeLabelH = textSize(timeLabel)
    text(timeLabel, sideMargin, hudTopY)
    
    local t    = math.max(0, timeRemaining)
    local tStr = string.format("%d", math.floor(t + 0.5))
    fontSize(numSize)
    local timeNumW, timeNumH = textSize(tStr)
    
    local timeNumX = sideMargin + timeLabelW + 6
    text(tStr, timeNumX, hudTopY)
    
    ------------------------------------------------
    -- QUIT button (right)
    ------------------------------------------------
    local quitLabel = "Quit"
    fontSize(labelSize)
    local qW, qH = textSize(quitLabel)
    local padX, padY = 20, 4        -- was 4; smaller vertical padding
    
    local btnW = qW + padX * 2
    local btnH = qH + padY * 2
    
    local btnX = WIDTH - sideMargin - btnW
    -- bottom is padY (~2px) below the baseline (hudTopY)
    local btnY = hudTopY - padY + 4      -- keeps text baseline at hudTopY
    
    quitButtonRect = { x = btnX, y = btnY, w = btnW, h = btnH }
    
    ------------------------------------------------
    -- SCORE (snug to the left of Quit)
    ------------------------------------------------
    local scoreLabel = "Score:"
    fontSize(labelSize)
    local scoreLabelW, scoreLabelH = textSize(scoreLabel)
    
    local scoreStr = tostring(score)
    fontSize(numSize)
    local scoreNumW, scoreNumH = textSize(scoreStr)
    
    local gapAfterTime = 16           -- space after time number
    local gapToQuit    = 16           -- space before Quit button
    local innerGap     = 6            -- between "Score:" and number
    
    -- band between time block and quit button
    local bandLeft   = timeNumX + timeNumW + gapAfterTime
    local bandRight  = btnX - gapToQuit
    local bandCenter = (bandLeft + bandRight) * 0.5
    
    local scoreTotalW = scoreLabelW + innerGap + scoreNumW
    local scoreLabelX = bandCenter - scoreTotalW * 0.5
    local scoreNumX   = scoreLabelX + scoreLabelW + innerGap
    
    fontSize(labelSize)
    text(scoreLabel, scoreLabelX, hudTopY)
    
    fontSize(numSize)
    text(scoreStr, scoreNumX, hudTopY)
    
    ------------------------------------------------
    -- Quit button rect + text (colors unchanged)
    ------------------------------------------------
    local fillCol   = Color.tileStroke
    local strokeCol = fillCol
    drawRoundedRect(
    btnX + btnW/2,
    btnY + btnH/2,
    btnW,
    btnH,
    8,
    fillCol,
    strokeCol
    )
    
    fill(255)
    fontSize(labelSize)
    textMode(CORNER)
    text(quitLabel, btnX + padX, btnY + padY)
    
    ------------------------------------------------
    -- Dictionary status at bottom (unchanged)
    ------------------------------------------------
    fontSize(18)
    fill(60, 90, 70, 255)
    text("Dict: "..dictStatus, sideMargin, 10)
    
    popStyle()
end

function handleQuitButtonTouch(t)
    -- only active on the board-style screens
    if state ~= STATE_PLAY and state ~= STATE_READY then
        return false
    end
    
    if not quitButtonRect then return false end
    
    local r = quitButtonRect
    if t.state == ENDED and
    t.x >= r.x and t.x <= r.x + r.w and
    t.y >= r.y and t.y <= r.y + r.h then
        state = STATE_MENU      -- or call your go-to-menu helper here
        return true
    end
    
    return false
end

function drawDictStatusMenu()
    pushStyle()
    textMode(CORNER)
    fontSize(18)
    fill(Color.tileText)
    text("Dict: "..dictStatus, sideMargin, 10)
    popStyle()
end

function scoreForWordLength(len)
    if len <= 2 then return 0
    elseif len <= 4 then return 1
    elseif len == 5 then return 2
    elseif len == 6 then return 3
    elseif len == 7 then return 5
    else return 11 end
end

lastWordAnimInfo = lastWordAnimInfo or nil

function startWordAnimation(word, startX, startY, startSize)
    -- For now this only records where/what the newest row is.
    -- Drawing still behaves exactly as before.
    local s = startSize or 1.35
    
    if lastWord and lastWord ~= "" and not lastWordValid then
        -- invalid attempt animation
        lastWordAnimInfo = {
            word       = word,
            startX     = startX,
            startY     = startY,
            startScale = s
        }
    elseif wordNewAnim then
        -- valid newly-added word animation
        wordNewAnim.word       = word
        wordNewAnim.startX     = startX
        wordNewAnim.startY     = startY
        wordNewAnim.startScale = s
    end
end

function drawInGameWordList()
    if state ~= STATE_PLAY then return end
    
    local words = ensureMyWordStore(currentQMatch) or {}
    local nFound = #words
    local hasInvalid = (lastWord and lastWord ~= "" and not lastWordValid)
    
    -- layout + label
    local labelY, viewTop, viewBot, viewH = getWordListLayout()
    
    pushStyle()
    textAlign(LEFT)
    textMode(CORNER)
    
    -- label ALWAYS visible
    fontSize(16)
    fill(Color.tileText or color(40, 80, 60, 255))
    text("Words found:", sideMargin, labelY)
    
    -- if nothing else, we're done (label only)
    if nFound == 0 and not hasInvalid then
        popStyle()
        return
    end
    
    local lineH     = 26
    local totalRows = nFound + (hasInvalid and 1 or 0)
    local dt        = DeltaTime or 0
    
    -- update animations (unchanged)
    if wordNewAnim then
        wordNewAnim.t = wordNewAnim.t + dt
        if wordNewAnim.t >= 0.3 then
            wordNewAnim = nil
        end
    end
    if hasInvalid then
        lastWordAnimT = lastWordAnimT + dt
    end
    
    function drawWordListRow(row, y, baseX)
        local w, pts, isValid, isNewest, animT
        
        if row <= nFound then
            local entry = words[row]
            if type(entry) == "table" then
                w   = entry.word or ""
                pts = entry.points
            else
                w   = tostring(entry)
                pts = nil
            end
            isValid  = true
            isNewest = (wordNewAnim and row == wordNewAnim.index)
            animT    = isNewest and (wordNewAnim.t or 0) or nil
        else
            w        = lastWord or ""
            pts      = nil
            isValid  = false
            isNewest = true
            animT    = lastWordAnimT or 0
        end
        
        local label
        if pts then
            label = string.format("%s  (+%d)", w, pts)
        else
            label = w
        end
        
        if isValid then
            fill(Color.valid or color(60, 140, 80, 255))
        else
            fill(Color.invalid or color(200, 60, 60, 255))
        end
        
        local scaleFactor = 1.0
        if isNewest and animT then
            local u  = math.min(1, animT / 0.15)
            local s0 = 1.35
            local s1 = 1.0
            scaleFactor = s0 + (s1 - s0) * u
            
            if animT == 0 then
                startWordAnimation(label, baseX, y, s0)
            end
        end
        
        pushMatrix()
        translate(baseX, y)
        scale(scaleFactor)
        fontSize(25)
        text(label, 0, 0)
        popMatrix()
    end
    
    -- viewport rect (CORNER) for the list area (label stays outside)
    local rect = {
        x = sideMargin - 4,
        y = viewBot,
        w = (WIDTH * 0.6) - (sideMargin - 4),
        h = viewH
    }
    local baseX = sideMargin + 8
    
    inGameWordList:draw(rect, totalRows, lineH, drawWordListRow, baseX)
    popStyle()
end

function handleWordListTouchInGame(t)
    if state ~= STATE_PLAY then return false end
    
    local words = ensureMyWordStore(currentQMatch) or {}
    local nFound = #words
    local hasInvalid = (lastWord and lastWord ~= "" and not lastWordValid)
    
    -- if there is nothing or not enough to scroll, ignore touches here
    if nFound == 0 and not hasInvalid then
        return false
    end
    if not inGameWordList or (inGameWordList.maxScroll or 0) <= 0 then
        return false
    end
    
    local _, viewTop, viewBot, viewH = getWordListLayout()
    
    local rect = {
        x = sideMargin - 4,
        y = viewBot,
        w = (WIDTH * 0.6) - (sideMargin - 4),
        h = viewH
    }
    
    return inGameWordList:touched(t, rect)
end
