recordsOverlayMode = recordsOverlayMode or "grid"   -- "grid" | "detail"
recordsSelectedOppKey = recordsSelectedOppKey or nil

RECORDS_VIEWED_KEY = RECORDS_VIEWED_KEY or "QB_RECORDS_VIEWED_V1"
recordsViewedByOpp = recordsViewedByOpp or nil   -- loaded dict: [oppKey] = lastViewedUnixTime

recordsThumbCache = recordsThumbCache or {}       -- [matchId or sig] = image
recordsThumbCacheOrder = recordsThumbCacheOrder or {}  -- simple LRU list if you want later

function loadRecordsViewed()
    if recordsViewedByOpp ~= nil then return end
    local raw = readProjectData(RECORDS_VIEWED_KEY)
    if raw and raw ~= "" then
        local ok, t = pcall(json.decode, raw)
        if ok and type(t) == "table" then recordsViewedByOpp = t return end
    end
    recordsViewedByOpp = {}
end

function persistRecordsViewed()
    if not recordsViewedByOpp then return end
    local ok, s = pcall(json.encode, recordsViewedByOpp)
    if ok and s then saveProjectData(RECORDS_VIEWED_KEY, s) end
end

function markRecordsViewedForOpponent(oppKey)
    if not oppKey then return end
    loadRecordsViewed()
    recordsViewedByOpp[oppKey] = os.time()
    persistRecordsViewed()
end

function recordsMatchesForOpponent(oppKey)
    -- Return matches for this opponent from the history store (newest first)
    local store = matchHistoryByOpponent
    local list = store and store[oppKey]
    if type(list) ~= "table" then return {} end
    return list
end

function recordsNewFinishedCountForOpponent(oppKey)
    -- Count how many finished matches occurred after last view timestamp
    loadRecordsViewed()
    local lastViewed = recordsViewedByOpp[oppKey] or 0
    local matches = recordsMatchesForOpponent(oppKey)
    
    local n = 0
    for i = 1, #matches do
        local m = matches[i]
        local endedAt = m.endedAt or m.lastUpdated or 0
        local status = m.status or m.turnStatus or ""
        local isFinished = (status == "ended") or (status == "final") or (status == "completed") or (status == "closed")
        if isFinished and endedAt > lastViewed then
            n = n + 1
        end
    end
    return n
end

function boardSigFromTiles(tiles)
    if type(tiles) ~= "table" then return "nil" end
    return table.concat(tiles, "")
end

function drawBoardThumbnailFromTiles(tiles, n, cx, cy, side)
    if type(tiles) ~= "table" or not n then return end
    
    local tileSize = side / n
    local startX = cx - side * 0.5
    local startY = cy - side * 0.5
    
    pushStyle()
    rectMode(CENTER)
    textAlign(CENTER)
    textMode(CENTER)
    fontSize(tileSize * 0.45)
    
    -- background
    drawRoundedRect(cx, cy, side + 10, side + 10, tileSize * 0.22, Color.gridBg, Color.gridBg)
    
    local idx = 1
    for r = 1, n do
        for c = 1, n do
            local x = startX + (c - 0.5) * tileSize
            local y = startY + (r - 0.5) * tileSize
            local label = tiles[idx] or "?"
            idx = idx + 1
            
            drawRoundedRect(x, y, tileSize * 0.9, tileSize * 0.9, tileSize * 0.25, Color.tileFill, Color.tileStroke)
            fill(Color.tileLetter or color(255))
            text(label, x, y)
        end
    end
    popStyle()
end

function getRecordsBoardThumb(m, px)
    -- px is the requested square size in pixels (e.g. 96)
    if not m then return nil end
    local n = m.boardSize or 4
    local tiles = m.boardTiles
    if type(tiles) ~= "table" then return nil end
    
    local key = (m.id or "") .. "|" .. tostring(n) .. "|" .. boardSigFromTiles(tiles) .. "|" .. tostring(px)
    local cached = recordsThumbCache[key]
    if cached then return cached end
    
    local img = image(px, px)
    setContext(img)
    background(0,0,0,0)
    
    local side = px * 0.86
    drawBoardThumbnailFromTiles(tiles, n, px * 0.5, px * 0.5, side)
    
    setContext()
    recordsThumbCache[key] = img
    return img
end

function openRecordsOverlay()
    recordsOverlay = true
    recordsOverlayMode = "grid"
    recordsSelectedOppKey = nil
    recordsScrollY = 0
    recordsScrollTouchId = nil
end

function closeRecordsOverlay()
    recordsOverlay = false
    recordsScrollTouchId = nil
end

function drawRecordsOverlay()
    if not recordsOverlay then return end
    
    -- dim everything
    pushStyle()
    fill(Color.panelDim)
    noStroke()
    rectMode(CORNER)
    rect(0, 0, WIDTH, HEIGHT)
    popStyle()
    
    local panelW = WIDTH * 0.85
    local panelH = HEIGHT * 0.85
    local panelX = WIDTH/2
    local panelY = HEIGHT/2
    
    -- panel (rounded, prebuilt in nextSeason)
    local panelSprite = overlayPanelRecords
    if panelSprite then
        local c = Color.panelBG or color(40, 40, 40, 220)
        pushStyle()
        spriteMode(CENTER)
        tint(255, 255, 255, c.a or 255)
        sprite(panelSprite, panelX, panelY)
        noTint()
        popStyle()
    else
        -- fallback if nextSeason hasn't run yet
        pushStyle()
        rectMode(CENTER)
        noStroke()
        fill(Color.panelBG)
        rect(panelX, panelY, panelW, panelH)
        popStyle()
    end
    
    local innerPadding = 24
    local innerLeft   = panelX - panelW/2 + innerPadding
    local innerRight  = panelX + panelW/2 - innerPadding
    local innerTop    = panelY + panelH/2 - innerPadding
    local innerBottom = panelY - panelH/2 + innerPadding
    
    pushStyle()
    textMode(CORNER)
    fill(Color.tileText)
    
    -- title
    fontSize(30)
    text("Games Won", innerLeft, innerTop - 32)
    
    local entries = {}
    for id, rec in pairs(opponentRecords) do
        local w = rec.wins   or 0
        local l = rec.losses or 0
        table.insert(entries, {
            id = id,
            alias = rec.alias or id,
            wins  = w,
            losses= l
        })
    end
    
    table.sort(entries, function(a, b)
        return (a.alias or "") < (b.alias or "")
    end)

    -- Grid area
    local listTop    = innerTop - 100
    local listBottom = innerBottom + 72
    local listHeight = listTop - listBottom
    local listWidth  = innerRight - innerLeft
    
    clip(innerLeft, listBottom, listWidth, listHeight)
    
    local columns = 3
    local colGap = 12
    local rowGap = 30
    local cellW = (listWidth - colGap * (columns - 1)) / columns
    local avatarSize = math.max(74, math.min(128, cellW * 0.94))
    local rowH = avatarSize + 112

    local function drawLabelValueCentered(cx, y, label, value)
        pushStyle()
        textMode(CORNER)
        textAlign(LEFT)

        font("HelveticaNeue")
        fontSize(16)
        local wLabel = textSize(label)

        font("HelveticaNeue-Bold")
        fontSize(16)
        local wValue = textSize(tostring(value))

        local x = cx - (wLabel + wValue) * 0.5

        font("HelveticaNeue")
        fill(Color.tileText)
        text(label, x, y)

        font("HelveticaNeue-Bold")
        fill(Color.tileText)
        text(tostring(value), x + wLabel, y)
        popStyle()
    end

    for i, e in ipairs(entries) do
        local row = math.floor((i - 1) / columns)
        local col = (i - 1) % columns
        local cx = innerLeft + col * (cellW + colGap) + cellW * 0.5
        local rowTop = listTop - recordsScrollY - row * (rowH + rowGap)
        local avatarCY = rowTop - avatarSize * 0.5
        local avatar = getOpponentRecordAvatar and getOpponentRecordAvatar(e.id) or nil

        drawAvatarCircle(avatar, cx, avatarCY, avatarSize, "O")

        pushStyle()
        textMode(CENTER)
        textAlign(CENTER)
        font("HelveticaNeue")
        fontSize(16)
        fill(Color.tileText)
        text(e.alias or e.id, cx, avatarCY - avatarSize * 0.72)
        popStyle()

        local lineY1 = avatarCY - avatarSize * 0.72 - 26
        local lineY2 = lineY1 - 22
        drawLabelValueCentered(cx, lineY1, "you: ", e.wins or 0)
        drawLabelValueCentered(cx, lineY2, "them: ", e.losses or 0)
    end
    
    clip()
    
    -- clamp scroll
    local rows = math.ceil(#entries / columns)
    local totalH = rows * rowH + math.max(0, rows - 1) * rowGap
    local maxScroll = math.max(0, totalH - listHeight)
    if recordsScrollY < 0 then recordsScrollY = 0 end
    if recordsScrollY > maxScroll then recordsScrollY = maxScroll end
    
    -- Close button at bottom of panel
    local btnW, btnH = 200, 48
    local btnX = panelX
    local btnY = innerBottom + btnH/2
    
    drawButton(btnX, btnY, btnW, btnH, "Close", false)
    
    -- store geometry for touch handler
    recordsOverlayGeom = {
        innerLeft   = innerLeft,
        innerBottom = innerBottom,
        listTop     = listTop,
        listBottom  = listBottom,
        listHeight  = listHeight,
        listWidth   = listWidth,
        btnX        = btnX,
        btnY        = btnY,
        btnW        = btnW,
        btnH        = btnH,
    }
    
    popStyle()
end

function handleRecordsTouch(t)
    if not recordsOverlay then return false end
    
    -- swallow all touches while open
    local g = recordsOverlayGeom
    if not g then
        -- no geometry yet; just close on any ENDED tap
        if t.state == ENDED then
            closeRecordsOverlay()
        end
        return true
    end
    
    local btnX, btnY, btnW, btnH = g.btnX, g.btnY, g.btnW, g.btnH
    
    if t.state == BEGAN then
        -- Close button
        if pointInRect(t.x, t.y, btnX, btnY, btnW, btnH) then
            closeRecordsOverlay()
            return true
        end
        
        -- start scroll if inside list area
        if t.x >= g.innerLeft and t.x <= g.innerLeft + g.listWidth and
        t.y >= g.listBottom and t.y <= g.listBottom + g.listHeight then
            recordsScrollTouchId = t.id
            recordsScrollPrevY = t.y
            return true
        end
        
        return true  -- consume tap even if it hit nothing
    elseif t.state == MOVING then
        if recordsScrollTouchId and t.id == recordsScrollTouchId then
            local dy = t.y - recordsScrollPrevY
            recordsScrollPrevY = t.y
            recordsScrollY = recordsScrollY - dy
        end
        return true
    elseif t.state == ENDED or t.state == CANCELLED then
        if recordsScrollTouchId and t.id == recordsScrollTouchId then
            recordsScrollTouchId = nil
        end
        return true
    end
    
    return true
end
