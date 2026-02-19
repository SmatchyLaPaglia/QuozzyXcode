function tileAtPoint(px, py)
    -- radius factor < 0.5 means “a bit smaller than the tile”
    local radiusFactor = 0.45
    
    for r = 1, boardSize do
        for c = 1, boardSize do
            local tr = tileRects[r][c]
            if tr then
                local dx = px - tr.x
                local dy = py - tr.y
                local radius = math.min(tr.w, tr.h) * radiusFactor
                if dx*dx + dy*dy <= radius * radius then
                    return r, c
                end
            end
        end
    end
    return nil, nil
end

function isInPath(r, c)
    for i, step in ipairs(currentPath) do
        if step.r == r and step.c == c then
            return i
        end
    end
    return nil
end

function areAdjacent(r1, c1, r2, c2)
    local dr = math.abs(r1 - r2)
    local dc = math.abs(c1 - c2)
    return dr <= 1 and dc <= 1 and not (dr == 0 and dc == 0)
end

function buildWordFromPath()
    local parts = {}
    for i, step in ipairs(currentPath) do
        local tile = board[step.r][step.c]
        parts[#parts+1] = tile
    end
    local s = table.concat(parts, "")
    s = string.upper(s)
    return s
end

function finalizeWord()
    -- no path, nothing to do
    if #currentPath == 0 then
        lastWord      = ""
        lastWordValid = false
        dragLastX     = nil
        dragLastY     = nil
        return
    end
    
    -- make sure our list tables exist
    foundWords    = foundWords    or {}
    foundWordsSet = foundWordsSet or {}
    
    local word = buildWordFromPath()
    local len  = #word
    
    -- always remember what they just tried
    lastWord = word
    
    -- validity check
    local isValid = (len >= MIN_WORD_LEN) and DICT[word] and not foundWordsSet[word]
    
    if isValid then
        ----------------------------------------------------------------
        -- VALID WORD
        ----------------------------------------------------------------
        lastWordValid = true
        
        local pts = scoreForWordLength(len)
        score = score + pts
        
        foundWordsSet[word] = true
        
        -- **explicit 1-based insertion**
        local idx = #foundWords + 1
        local words = ensureMyWordStore(currentQMatch)
        local idx = #words + 1
        words[idx] = { word = word, points = pts }
        
        -- pop animation for the newest *permanent* entry
        wordNewAnim = { index = idx, t = 0 }
        
        -- any prior invalid animation is no longer relevant
        lastWordAnimT = 0
        
        -- auto-scroll so this new word is visible at the bottom
        inGameWordList:markDirtyAuto()
        
    else
        ----------------------------------------------------------------
        -- INVALID WORD (too short / not in dict / duplicate)
        ----------------------------------------------------------------
        lastWordValid = false
        
        -- start / restart the little “pop” on the red ephemeral row
        lastWordAnimT = 0
        
        -- treat it like a new row visually so list can auto-scroll too
        inGameWordList:markDirtyAuto()
    end
    
    -- clear out the current drag / path state
    currentPath   = {}
    pathActive    = false
    touchIdActive = nil
    dragLastX     = nil
    dragLastY     = nil

  do
    local q = currentQMatch
    local pid = localPID()
--    print( "[WORD COMMIT]",    "q=", q,  "id=", q and q.id,   "wordsTbl=", q and q.players and q.players[pid] and q.players[pid].words,    "words#", q and q.players and q.players[pid] and #q.players[pid].words    )
  end
end

-- Convert a screen point into continuous board coordinates (in tile units)
-- rowf/colf ~ 1.0,2.0,... at tile centers.
function boardCoordsFromPoint(px, py)
    local tileSize, startX, startY = computeGridLayout()
    local colf = (px - startX) / tileSize + 0.5
    local rowf = (py - startY) / tileSize + 0.5
    return rowf, colf
end

function handleGameTouch(t)
    if state ~= STATE_PLAY then return end
    
    -- let the in-game word list handle scroll gestures first
    if handleWordListTouchInGame(t) then
        return
    end
    
    local ts = t.state
    
    if ts == BEGAN then
        -- First: check if this is a word-list scroll gesture
        local nFound    = (foundWords and #foundWords) or 0
        local hasInvalid = (lastWord and lastWord ~= "" and not lastWordValid)
        if (nFound > 0 or hasInvalid) and isInWordListRegion(t.x, t.y) then
            wordScrollDragId      = t.id
            wordScrollDragStartY  = t.y
            wordScrollStartAtDrag = wordScroll
            return
        end
        
        -- Otherwise, start a board path if we tapped on a tile
        local r, c = tileAtPoint(t.x, t.y)
        if r and c then
            currentPath   = { { r = r, c = c } }
            pathActive    = true
            touchIdActive = t.id
            
            spawnPathParticles(t.x, t.y)
        end
        return
    end
    
    if not pathActive or t.id ~= touchIdActive then
        return
    end
    
    if ts == MOVING then
        -- word list drag?
        if wordScrollDragId and t.id == wordScrollDragId then
            local labelY, viewTop, viewBot, viewH = getWordListLayout()
            
            local lineH     = 26
            local nFound    = (foundWords and #foundWords) or 0
            local hasInvalid = (lastWord and lastWord ~= "" and not lastWordValid)
            local totalRows = nFound + (hasInvalid and 1 or 0)
            local contentH  = totalRows * lineH
            local maxScroll = math.max(0, contentH - viewH)
            
            local dy = t.y - wordScrollDragStartY
            local newScroll = wordScrollStartAtDrag - dy   -- drag up → scroll down
            if newScroll < 0 then newScroll = 0 end
            if newScroll > maxScroll then newScroll = maxScroll end
            
            wordScroll       = newScroll
            wordScrollTarget = newScroll   -- keep auto/visual in sync
            return
        end
        local r, c = tileAtPoint(t.x, t.y)
        if not (r and c) then
            return
        end
        
        local n = #currentPath
        if n == 0 then
            -- Safety: if somehow empty, treat as fresh start
            currentPath = { { r = r, c = c } }
            return
        end
        
        local last = currentPath[n]
        
        -- Still on the same tile → no change
        if last.r == r and last.c == c then
            return
        end
        
        -- Check if this tile is already in the path
        local idx = isInPath(r, c)
        
        -- Backtrack exactly one step if we moved onto the immediate previous tile
        if idx and idx == n - 1 and n >= 2 then
            table.remove(currentPath, n)
            return
        end
        
        -- Any other earlier tile: ignore (never rewrite history)
        if idx then
            return
        end
        
            if areAdjacent(last.r, last.c, r, c) then
                table.insert(currentPath, { r = r, c = c })
                -- NEW: emit trail at this step
                spawnPathParticles(t.x, t.y)
            end
        
    elseif ts == ENDED or ts == CANCELLED then
        -- releasing a word list drag?
        if wordScrollDragId and t.id == wordScrollDragId then
            wordScrollDragId = nil
            return
        end
        
        -- finishing a board path?
        if not pathActive or t.id ~= touchIdActive then
            return
        end
        
        finalizeWord()
    end
end

function resetWordListScroll()
    wordScroll          = 0
    wordScrollTarget    = 0
    wordScrollMax       = 0
    wordScrollDragId    = nil
    wordScrollDirtyAuto = false
    wordNewAnim         = nil
    lastWordAnimT       = 0
end

