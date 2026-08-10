recordsOverlayMode = recordsOverlayMode or "grid"   -- "grid" (opponents) | "detail" (that opponent's matches)
recordsSelectedOppKey = recordsSelectedOppKey or nil

RECORDS_VIEWED_KEY = RECORDS_VIEWED_KEY or "QB_RECORDS_VIEWED_V1"
recordsViewedByOpp = recordsViewedByOpp or nil   -- loaded dict: [oppKey] = lastViewedUnixTime

recordsThumbCache = recordsThumbCache or {}       -- [matchId or sig] = image
recordsThumbCacheOrder = recordsThumbCacheOrder or {}  -- simple LRU list if you want later

-- Row hit rects, rebuilt each frame by the active list, consumed by handleRecordsTouch.
-- Stored in CORNER coords {x, y, w, h, ...} (bottom-left origin) so the touch code can do
-- plain rect containment without the pointInRect CENTER convention.
recordsRowRects      = recordsRowRects      or {}   -- opponents list (grid mode): {..., oppId}
recordsMatchRowRects = recordsMatchRowRects or {}   -- matches list (detail mode): {..., matchIndex}

-- Saved live game state while a historical match is being viewed on the end screen, so we
-- can restore it (and reopen the records match list) when the user closes that end screen.
-- See openHistoricalMatchEndScreen / restoreLiveStateAfterHistoricalView, and the intercept
-- in disposeEndScreenAndReturnToMenu (EndScreen.lua) that reads endScreenReturnToRecords.
recordsSavedLiveState    = recordsSavedLiveState    or nil
endScreenReturnToRecords = endScreenReturnToRecords or nil

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
        if m.complete and endedAt > lastViewed then
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
    font(GLOBAL_UI_FONT_DICE)  -- pinned: dice letters are exempt from GLOBAL_UI_FONT, see Main.lua
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

--####################################################################
-- Shared list helpers (module-level so both the opponents list and the
-- matches list can use them)
--####################################################################

local _MONTHS = { "Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec" }

local function _formatMatchDate(t)
    t = tonumber(t) or 0
    if t <= 0 then return "" end
    local d = os.date("*t", t)
    local h = d.hour % 12
    if h == 0 then h = 12 end
    local ampm = (d.hour < 12) and "AM" or "PM"
    return string.format("%s %d, %d  %d:%02d %s", _MONTHS[d.month] or "?", d.day, d.year, h, d.min, ampm)
end

local function _truncateWithEllipsis(s, maxW)
    if not s or s == "" then return "" end
    if textSize(s) <= maxW then return s end
    local ell = "…"
    local i = #s
    while i > 0 do
        -- Never cut in the middle of a multi-byte UTF-8 char: if the NEXT byte is a
        -- continuation byte (0x80-0xBF), move the cut earlier. Cutting mid-char produces
        -- invalid UTF-8 that textSize() mis-measures and text() renders as nothing — that
        -- was the bug that made the in-progress row's "— waiting" line vanish.
        local nb = s:byte(i + 1)
        if nb and nb >= 0x80 and nb < 0xC0 then
            i = i - 1
        else
            local candidate = string.sub(s, 1, i) .. ell
            if textSize(candidate) <= maxW then return candidate end
            i = i - 1
        end
    end
    return ell
end

-- Enlarged version of the old records badges: two red circles (wins | losses) with
-- white digits and "to" between, right-aligned so the cluster ends at rightX. Returns
-- the leftmost x it used so the caller can keep the name from overlapping it.
local function _drawLargeScoreBadges(rightX, cy, wins, losses)
    pushStyle()
    textMode(CENTER)
    textAlign(CENTER)

    local wText = tostring(wins or 0)
    local lText = tostring(losses or 0)

    local digitFont = 21
    font("HelveticaNeue-Bold")
    fontSize(digitFont)
    local wTextW = textSize(wText)
    local lTextW = textSize(lText)

    local minR, maxR, pad = 19, 26, 10
    local leftR  = math.max(minR, math.min(maxR, math.floor(wTextW * 0.5 + pad)))
    local rightR = math.max(minR, math.min(maxR, math.floor(lTextW * 0.5 + pad)))

    font("HelveticaNeue")
    fontSize(18)
    local toText = "to"
    local toW = textSize(toText)
    local gap = 6

    local totalW = (leftR * 2) + gap + toW + gap + (rightR * 2)
    local leftX  = rightX - totalW
    local leftCx = leftX + leftR
    local rightCx = rightX - rightR

    noStroke()
    ellipseMode(CENTER)
    fill(220, 63, 63, 255)
    ellipse(leftCx, cy, leftR * 2)
    ellipse(rightCx, cy, rightR * 2)

    font("HelveticaNeue-Bold")
    fontSize(digitFont)
    fill(255, 255, 255, 255)
    text(wText, leftCx, cy)
    text(lText, rightCx, cy)

    font("HelveticaNeue")
    fontSize(18)
    fill(Color.tileText)
    text(toText, (leftCx + rightCx) * 0.5, cy)

    popStyle()
    return leftX
end

-- Compact "speech balloon" for a match row's comment: a rounded bubble sized to one
-- truncated line, with a small downward tail. Reuses ONE persistent mesh for the tail
-- (updated in place each call) so nothing is allocated per frame — important given the
-- avatar-texture leak lesson (see Avatars.lua). x,yBot = bottom-left of the whole balloon
-- (tail tip sits at yBot).
local function _drawMiniBalloon(txt, x, yBot, maxW, fillCol, txtCol)
    txt = tostring(txt or "")
    if txt == "" then return end
    _miniTailMesh = _miniTailMesh or mesh()   -- lazy: don't allocate a GPU object at file load

    pushStyle()
    textMode(CORNER)
    textAlign(LEFT)
    font(GLOBAL_UI_FONT)
    local fs = 15
    fontSize(fs)

    local padX = 10
    local bodyH = 28
    local tailH = 7
    local shown = _truncateWithEllipsis(txt, maxW - padX * 2)
    local tw = textSize(shown)
    local w = math.min(maxW, tw + padX * 2)

    local bodyBottom = yBot + tailH
    local bodyCy = bodyBottom + bodyH * 0.5
    local cx = x + w * 0.5

    -- body
    drawRoundedRect(cx, bodyCy, w, bodyH, 9, fillCol, fillCol)

    -- tail (persistent mesh, vertices re-set each call)
    local tm = _miniTailMesh
    local baseX = x + 16
    tm.vertices = {
        vec2(baseX, bodyBottom + 1),
        vec2(baseX + 12, bodyBottom + 1),
        vec2(baseX + 2, yBot),
    }
    tm:setColors(fillCol)
    tm:draw()

    -- text
    fill(txtCol)
    text(shown, x + padX, bodyBottom + (bodyH - fs) * 0.5)

    popStyle()
    return w
end

--####################################################################
-- Overlay draw (dispatches on recordsOverlayMode)
--####################################################################

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
    local panelX = WIDTH / 2
    local panelY = HEIGHT / 2

    -- panel (rounded, prebuilt per season)
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
    local listWidth   = innerRight - innerLeft

    local titleBandH  = 56
    local buttonBandH = 70
    local listTop     = innerTop - titleBandH
    local listBottom  = innerBottom + buttonBandH
    local listHeight  = listTop - listBottom

    local bounds = {
        panelX = panelX, panelY = panelY,
        innerLeft = innerLeft, innerRight = innerRight,
        innerTop = innerTop, innerBottom = innerBottom,
        listWidth = listWidth, listTop = listTop,
        listBottom = listBottom, listHeight = listHeight,
    }

    local isDetail = (recordsOverlayMode == "detail" and recordsSelectedOppKey ~= nil)

    if isDetail then
        drawRecordsMatchesList(bounds)
    else
        drawRecordsOpponentsList(bounds)
    end

    -- bottom button: "Close" (opponents) / "Back" (matches)
    local btnW, btnH = 200, 48
    local btnX = panelX
    local btnY = innerBottom + btnH/2
    drawButton(btnX, btnY, btnW, btnH, isDetail and "Back" or "Close", false)

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
        isDetail    = isDetail,
    }
end

--####################################################################
-- LEVEL 1 — opponents list
--####################################################################

function drawRecordsOpponentsList(b)
    pushStyle()
    textMode(CORNER)

    -- Title
    fill(Color.tileText)
    font("HelveticaNeue-Bold")
    fontSize(30)
    textAlign(CENTER)
    textMode(CENTER)
    text("Records", b.panelX, b.innerTop - 26)

    -- Build + sort entries
    local entries = {}
    for id, rec in pairs(opponentRecords or {}) do
        entries[#entries + 1] = {
            id = id,
            alias = rec.alias or id,
            wins = rec.wins or 0,
            losses = rec.losses or 0,
        }
    end
    table.sort(entries, function(a, b2) return (a.alias or "") < (b2.alias or "") end)

    recordsRowRects = {}

    local rowH = 92
    local avSize = 60

    -- Pre-generate avatar images BEFORE the clip region. unknownPlayerAvatar renders via
    -- setContext (render-to-texture); doing that while a clip() scissor is active corrupts
    -- the texture into GPU garbage. Generating here (unclipped, cached) makes the in-clip
    -- loop a pure draw. Pass the resolved image to drawAvatarCircle so it never creates one
    -- itself inside the clip.
    local entryAvatars = {}
    for i, e in ipairs(entries) do
        entryAvatars[i] = (getOpponentRecordAvatar and getOpponentRecordAvatar(e.id))
            or unknownPlayerAvatar(avSize, Color.uiAccent)
    end

    clip(b.innerLeft, b.listBottom, b.listWidth, b.listHeight)

    for i, e in ipairs(entries) do
        local rowTopY = b.listTop - recordsScrollY - (i - 1) * rowH
        local rowBotY = rowTopY - rowH
        if rowBotY < b.listTop and rowTopY > b.listBottom then
            local cy = (rowTopY + rowBotY) * 0.5

            -- avatar (left)
            local avCx = b.innerLeft + 8 + avSize * 0.5
            drawAvatarCircle(entryAvatars[i], avCx, cy, avSize, "O")

            -- W/L badges (right), then name in the remaining middle space
            local badgesLeftX = _drawLargeScoreBadges(b.innerRight - 8, cy, e.wins, e.losses)

            local nameX = avCx + avSize * 0.5 + 16
            local nameMaxW = badgesLeftX - 14 - nameX
            pushStyle()
            fill(Color.tileText)
            font("HelveticaNeue-Bold")
            fontSize(20)
            textMode(CORNER)
            textAlign(LEFT)
            local nameStr = _truncateWithEllipsis(e.alias or e.id, math.max(20, nameMaxW))
            local _, nh = textSize(nameStr)
            text(nameStr, nameX, cy - (nh or 22) * 0.5)
            popStyle()

            -- separator
            pushStyle()
            stroke(Color.tileText.r, Color.tileText.g, Color.tileText.b, 40)
            strokeWidth(1)
            line(b.innerLeft + 6, rowBotY, b.innerRight - 6, rowBotY)
            popStyle()

            recordsRowRects[#recordsRowRects + 1] = {
                x = b.innerLeft, y = rowBotY, w = b.listWidth, h = rowH, oppId = e.id,
            }
        end
    end

    clip()

    -- empty state
    if #entries == 0 then
        pushStyle()
        fill(Color.tileText.r, Color.tileText.g, Color.tileText.b, 150)
        font("HelveticaNeue")
        fontSize(18)
        textMode(CENTER)
        textAlign(CENTER)
        text("No opponents yet.", b.panelX, (b.listTop + b.listBottom) * 0.5)
        popStyle()
    end

    -- clamp scroll
    local totalH = #entries * rowH
    local maxScroll = math.max(0, totalH - b.listHeight)
    if recordsScrollY < 0 then recordsScrollY = 0 end
    if recordsScrollY > maxScroll then recordsScrollY = maxScroll end

    popStyle()
end

--####################################################################
-- LEVEL 2 — one opponent's matches
--####################################################################

function drawRecordsMatchesList(b)
    local oppId = recordsSelectedOppKey
    local rec = opponentRecords and opponentRecords[oppId]
    local alias = (rec and rec.alias) or oppId or "Opponent"

    pushStyle()

    -- Title (opponent name)
    fill(Color.tileText)
    font("HelveticaNeue-Bold")
    fontSize(28)
    textMode(CENTER)
    textAlign(CENTER)
    local titleStr = _truncateWithEllipsis(alias, b.listWidth - 20)
    text(titleStr, b.panelX, b.innerTop - 26)

    local matches = recordsMatchesForOpponent(oppId)
    recordsMatchRowRects = {}

    local rowH = 132

    -- Pre-generate board thumbnails BEFORE the clip region (getRecordsBoardThumb uses
    -- setContext render-to-texture, which corrupts under an active clip scissor — same
    -- reason as the avatars in the opponents list). Cached, so this is one-time cost.
    local matchThumbs = {}
    for i, m in ipairs(matches) do
        matchThumbs[i] = getRecordsBoardThumb(m, 96)
    end

    clip(b.innerLeft, b.listBottom, b.listWidth, b.listHeight)

    for i, m in ipairs(matches) do
        local rowTopY = b.listTop - recordsScrollY - (i - 1) * rowH
        local rowBotY = rowTopY - rowH
        if rowBotY < b.listTop and rowTopY > b.listBottom then
            -- thumbnail (left, upper strip)
            local thumbSize = 74
            local thumbCx = b.innerLeft + 8 + thumbSize * 0.5
            local thumbCy = rowTopY - 10 - thumbSize * 0.5
            local thumb = matchThumbs[i]
            if thumb then
                pushStyle()
                spriteMode(CENTER)
                sprite(thumb, thumbCx, thumbCy, thumbSize, thumbSize)
                popStyle()
            end

            -- score / word-count / date text block (right of thumb)
            local nLocalWords = #(m.localWords or {})
            local nOppWords   = #(m.oppWords or {})
            local textX = b.innerLeft + 8 + thumbSize + 14
            local textAvailW = b.innerRight - 8 - textX
            local lineTop = rowTopY - 14

            pushStyle()
            textMode(CORNER)
            textAlign(LEFT)
            fill(Color.tileText)

            font("HelveticaNeue-Bold")
            fontSize(18)
            text(_truncateWithEllipsis(string.format("You  %d  ·  %d words", m.localScore or 0, nLocalWords), textAvailW),
                textX, lineTop - 18)

            font("HelveticaNeue")
            fontSize(18)
            -- Both branches: truncate the (possibly long) alias to leave room for a short
            -- fixed suffix, so the suffix is never what gets truncated away.
            local suffix = m.complete
                and string.format("  %d  ·  %d words", m.oppScore or 0, nOppWords)
                or  "  · waiting to play"
            local aliasW = math.max(24, textAvailW - textSize(suffix))
            local oppLine = _truncateWithEllipsis(alias, aliasW) .. suffix
            text(_truncateWithEllipsis(oppLine, textAvailW), textX, lineTop - 42)

            fill(Color.tileText.r, Color.tileText.g, Color.tileText.b, 150)
            font("HelveticaNeue")
            fontSize(14)
            text(_truncateWithEllipsis(_formatMatchDate(m.endedAt), textAvailW), textX, lineTop - 64)
            popStyle()

            -- comment balloons (bottom strip): opponent (left), local (right)
            local stripBottom = rowBotY + 10
            local half = (b.listWidth - 16) * 0.5
            local fillA = Color.uiAccent or color(40, 80, 60)
            local txtC  = Color.panelBG or color(255)
            if (m.oppComment or "") ~= "" then
                _drawMiniBalloon(m.oppComment, b.innerLeft + 8, stripBottom, half - 6, fillA, txtC)
            end
            if (m.localComment or "") ~= "" then
                _drawMiniBalloon(m.localComment, b.innerLeft + 8 + half, stripBottom, half - 6, fillA, txtC)
            end

            -- separator
            pushStyle()
            stroke(Color.tileText.r, Color.tileText.g, Color.tileText.b, 40)
            strokeWidth(1)
            line(b.innerLeft + 6, rowBotY, b.innerRight - 6, rowBotY)
            popStyle()

            recordsMatchRowRects[#recordsMatchRowRects + 1] = {
                x = b.innerLeft, y = rowBotY, w = b.listWidth, h = rowH, matchIndex = i,
            }
        end
    end

    clip()

    if #matches == 0 then
        pushStyle()
        fill(Color.tileText.r, Color.tileText.g, Color.tileText.b, 150)
        font("HelveticaNeue")
        fontSize(18)
        textMode(CENTER)
        textAlign(CENTER)
        text("No games recorded yet.", b.panelX, (b.listTop + b.listBottom) * 0.5)
        popStyle()
    end

    local totalH = #matches * rowH
    local maxScroll = math.max(0, totalH - b.listHeight)
    if recordsScrollY < 0 then recordsScrollY = 0 end
    if recordsScrollY > maxScroll then recordsScrollY = maxScroll end

    popStyle()
end

--####################################################################
-- LEVEL 3 — open the full end screen for a stored match
--####################################################################

function openHistoricalMatchEndScreen(m)
    if not (m and m.id and m.oppId) then return end
    local myId = localPID()
    if not myId then return end

    -- Save live game state so we can restore it when the end screen closes.
    recordsSavedLiveState = {
        currentQMatch = currentQMatch,
        useTurnBased = useTurnBased,
        score = score,
        opponentScore = opponentScore,
        foundWords = foundWords,
        foundWordsSet = foundWordsSet,
        currentOpponentID = currentOpponentID,
        opponentAlias = opponentAlias,
        boardSize = boardSize,
        MIN_WORD_LEN = MIN_WORD_LEN,
        detailScrollY = recordsScrollY,
    }

    -- Reconstruct a qMatch from the stored snapshot. recordOutcomeApplied=true stops the
    -- end screen from re-counting this match's W/L (EndScreenFP.lua). Opponent didPlay
    -- mirrors completeness so an in-progress snapshot shows the waiting/incomplete screen.
    local recon = {
        id = m.id,
        source = "history",
        boardSize = m.boardSize,
        minWordLen = m.minWordLen,
        boardTiles = m.boardTiles,
        otherId = m.oppId,
        opponentId = m.oppId,
        otherName = m.oppAlias,
        opponentName = m.oppAlias,
        lastUpdated = m.endedAt,
        recordOutcomeApplied = true,
        players = {
            [myId] = {
                score = m.localScore or 0,
                words = m.localWords or {},
                wordTimes = {},
                comment = m.localComment or "",
                didPlay = true,
            },
            [m.oppId] = {
                score = m.oppScore or 0,
                words = m.oppWords or {},
                wordTimes = {},
                comment = m.oppComment or "",
                didPlay = (m.complete and true or false),
            },
        },
    }

    currentQMatch = recon
    useTurnBased = true
    currentOpponentID = m.oppId
    opponentAlias = m.oppAlias
    boardSize = m.boardSize or boardSize
    MIN_WORD_LEN = m.minWordLen or MIN_WORD_LEN
    score = m.localScore or 0
    opponentScore = m.oppScore or 0
    foundWords = m.localWords or {}
    foundWordsSet = {}
    for _, w in ipairs(foundWords) do
        local ws = (type(w) == "table") and w.word or w
        if type(ws) == "string" then foundWordsSet[ws] = true end
    end

    -- opponent cameo
    qPlayersById = qPlayersById or {}
    qPlayersById[m.oppId] = qPlayersById[m.oppId] or {}
    if not qPlayersById[m.oppId].avatar and getOpponentRecordAvatar then
        qPlayersById[m.oppId].avatar = getOpponentRecordAvatar(m.oppId)
    end

    endScreenReturnToRecords = { oppId = m.oppId }
    recordsOverlay = false
    recordsScrollTouchId = nil
    endScreenLastMatchId = nil   -- force end-screen model/layout rebuild for this match

    state = STATE_END
end

-- Restore the live game state saved by openHistoricalMatchEndScreen. Called from the
-- disposeEndScreenAndReturnToMenu intercept (EndScreen.lua) on plain close.
function restoreLiveStateAfterHistoricalView()
    local s = recordsSavedLiveState
    if not s then return end
    currentQMatch = s.currentQMatch
    useTurnBased = s.useTurnBased
    score = s.score
    opponentScore = s.opponentScore
    foundWords = s.foundWords
    foundWordsSet = s.foundWordsSet
    currentOpponentID = s.currentOpponentID
    opponentAlias = s.opponentAlias
    boardSize = s.boardSize
    MIN_WORD_LEN = s.MIN_WORD_LEN
    recordsSavedLiveState = nil
end

-- Reopen the records overlay at the matches list for oppId (used on close-from-end-screen).
function reopenRecordsInDetailMode(oppId)
    recordsOverlay = true
    recordsOverlayMode = "detail"
    recordsSelectedOppKey = oppId
    recordsScrollY = (recordsSavedLiveState and recordsSavedLiveState.detailScrollY) or 0
    recordsScrollTouchId = nil
end

--####################################################################
-- Touch handling (tap-vs-drag aware; row taps drill down)
--####################################################################

local _RECORDS_TAP_SLOP = 10   -- px of movement before a touch becomes a scroll, not a tap

function handleRecordsTouch(t)
    if not recordsOverlay then return false end

    local g = recordsOverlayGeom
    if not g then
        if t.state == ENDED then closeRecordsOverlay() end
        return true
    end

    if t.state == BEGAN then
        -- Bottom button (Close in grid / Back in detail): act immediately.
        if pointInRect(t.x, t.y, g.btnX, g.btnY, g.btnW, g.btnH) then
            if g.isDetail then
                -- Back to opponents list
                recordsOverlayMode = "grid"
                recordsSelectedOppKey = nil
                recordsScrollY = recordsGridScrollY or 0
            else
                closeRecordsOverlay()
            end
            recordsScrollTouchId = nil
            return true
        end

        -- Start a potential scroll/tap inside the list.
        if t.x >= g.innerLeft and t.x <= g.innerLeft + g.listWidth and
           t.y >= g.listBottom and t.y <= g.listBottom + g.listHeight then
            recordsScrollTouchId = t.id
            recordsScrollPrevY = t.y
            recordsTouchStartX = t.x
            recordsTouchStartY = t.y
            recordsTouchMoved = false
        end
        return true

    elseif t.state == MOVING then
        if recordsScrollTouchId and t.id == recordsScrollTouchId then
            local dy = t.y - recordsScrollPrevY
            recordsScrollPrevY = t.y
            recordsScrollY = recordsScrollY - dy
            if math.abs(t.y - (recordsTouchStartY or t.y)) > _RECORDS_TAP_SLOP or
               math.abs(t.x - (recordsTouchStartX or t.x)) > _RECORDS_TAP_SLOP then
                recordsTouchMoved = true
            end
        end
        return true

    elseif t.state == ENDED or t.state == CANCELLED then
        if recordsScrollTouchId and t.id == recordsScrollTouchId then
            recordsScrollTouchId = nil
            -- A tap (no significant movement) selects a row.
            if t.state == ENDED and not recordsTouchMoved then
                if g.isDetail then
                    for _, r in ipairs(recordsMatchRowRects) do
                        if t.x >= r.x and t.x <= r.x + r.w and t.y >= r.y and t.y <= r.y + r.h then
                            local matches = recordsMatchesForOpponent(recordsSelectedOppKey)
                            local m = matches[r.matchIndex]
                            if m then openHistoricalMatchEndScreen(m) end
                            return true
                        end
                    end
                else
                    for _, r in ipairs(recordsRowRects) do
                        if t.x >= r.x and t.x <= r.x + r.w and t.y >= r.y and t.y <= r.y + r.h then
                            recordsGridScrollY = recordsScrollY
                            recordsOverlayMode = "detail"
                            recordsSelectedOppKey = r.oppId
                            recordsScrollY = 0
                            if markRecordsViewedForOpponent then
                                markRecordsViewedForOpponent(r.oppId)
                            end
                            return true
                        end
                    end
                end
            end
        end
        return true
    end

    return true
end
