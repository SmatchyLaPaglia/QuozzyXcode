-- # Render

function updateBlink()
    BLINK_TIME = BLINK_TIME + DeltaTime
    if BLINK_TIME > 0.5 then
        BLINK_TIME = BLINK_TIME - 0.5
        BLINK_ON = not BLINK_ON
    end
end

function drawBlueSpeechBalloonDemoScreen()
    local panelW = WIDTH * 0.5
    local panelH = HEIGHT * 0.5
    local panelX = (WIDTH - panelW) * 0.5
    local panelY = (HEIGHT - panelH) * 0.5
    local tailAnchorX = panelX + panelW * 0.2
    local tailAnchorY = math.max(30, panelY - panelH * 0.2)
    local shadowContour = buildSpeechBalloonContour(panelX + 6, panelY - 6, panelW, panelH, tailAnchorX + 8, tailAnchorY - 8, {
        cornerRadius = 32,
        tailLength = panelH * 0.18,
        tailBaseWidth = panelW * 0.13,
        arcSegments = 10,
        tailSide = "down"
    })
    local panelContour = buildSpeechBalloonContour(panelX, panelY, panelW, panelH, tailAnchorX, tailAnchorY, {
        cornerRadius = 32,
        tailLength = panelH * 0.18,
        tailBaseWidth = panelW * 0.13,
        arcSegments = 10,
        tailSide = "down"
    })

    pushStyle()
    drawSpeechBalloonShaderShape(panelX + 6, panelY - 6, panelW, panelH, shadowContour, {
        fillColor = color(0, 0, 0, 42),
        outlineColor = color(0, 0, 0, 0),
        outlineWidth = 0,
        shaderPadding = 8
    })
    drawSpeechBalloonShaderShape(panelX, panelY, panelW, panelH, panelContour, {
        fillColor = GLOBAL_BLUE,
        outlineColor = color(160, 210, 255, 120),
        outlineWidth = 2,
        shaderPadding = 6
    })
    popStyle()

    GAME.sceneRect = sceneRect()
end

function drawGame()
    drawSceneCanvas()

    if GAME.overlay.kind == "ready" then
        drawReadyOverlay()
    elseif GAME.overlay.kind == "confirm" then
        drawConfirmOverlay()
    elseif GAME.overlay.kind == "the_end" then
        drawEndOverlay()
    elseif GAME.overlay.kind == "flipbook" then
        drawFlipbookOverlay()
    elseif GAME.overlay.kind == "storybook_save_load" then
        drawStorybookSaveLoadOverlay()
    end
end

function chooseSpeechTailSide(bodyCenterX, bodyCenterY, tailAnchorX, tailAnchorY)
    local dx = tailAnchorX - bodyCenterX
    local dy = tailAnchorY - bodyCenterY
    if math.abs(dy) >= math.abs(dx) then
        if dy <= 0 then
            return "down"
        end
        return "up"
    end
    if dx < 0 then
        return "left"
    end
    return "right"
end

function speechTailBaseCenterForSide(side, bodyX, bodyY, w, h, tailAnchorX, tailAnchorY)
    if side == "down" or side == "up" then
        return tailAnchorX
    end
    return tailAnchorY
end

function clampSpeechTailBase(side, bodyX, bodyY, w, h, cornerRadius, tailBaseWidth, desiredCenter)
    local halfBase = tailBaseWidth * 0.5
    if side == "down" or side == "up" then
        local minValue = bodyX + cornerRadius + halfBase
        local maxValue = bodyX + w - cornerRadius - halfBase
        return clamp(desiredCenter, minValue, maxValue)
    end

    local minValue = bodyY + cornerRadius + halfBase
    local maxValue = bodyY + h - cornerRadius - halfBase
    return clamp(desiredCenter, minValue, maxValue)
end

function addSpeechPoint(pts, px, py)
    local last = pts[#pts]
    if last and math.abs(last.x - px) < 0.001 and math.abs(last.y - py) < 0.001 then
        return
    end
    pts[#pts + 1] = vec2(px, py)
end

function addSpeechArcPoints(pts, cx, cy, radius, startAngle, endAngle, segments, skipFirst)
    for i = 0, segments do
        if not (skipFirst and i == 0) then
            local t = i / segments
            local angle = startAngle + (endAngle - startAngle) * t
            addSpeechPoint(pts, cx + math.cos(angle) * radius, cy + math.sin(angle) * radius)
        end
    end
end

function buildSpeechBalloonContour(bodyX, bodyY, w, h, tailAnchorX, tailAnchorY, opts)
    opts = opts or {}

    local cornerRadius = math.max(0, math.min(opts.cornerRadius or 18, math.min(w, h) * 0.5))
    local arcSegments = math.max(4, math.floor(opts.arcSegments or 6))
    local tailBaseWidth = math.max(1, opts.tailBaseWidth or speechBalloonTailWidthAtBase)
    local tailLength = math.max(0, opts.tailLength or speechBalloonTailLength)
    local bodyCenterX = bodyX + w * 0.5
    local bodyCenterY = bodyY + h * 0.5
    local side = opts.tailSide or chooseSpeechTailSide(bodyCenterX, bodyCenterY, tailAnchorX, tailAnchorY)
    local baseCenter = clampSpeechTailBase(
        side,
        bodyX,
        bodyY,
        w,
        h,
        cornerRadius,
        tailBaseWidth,
        speechTailBaseCenterForSide(side, bodyX, bodyY, w, h, tailAnchorX, tailAnchorY)
    )
    local halfBase = tailBaseWidth * 0.5
    local baseTipX = tailAnchorX
    local baseTipY = tailAnchorY

    if side == "down" then
        baseTipX = baseCenter
        baseTipY = bodyY
    elseif side == "up" then
        baseTipX = baseCenter
        baseTipY = bodyY + h
    elseif side == "left" then
        baseTipX = bodyX
        baseTipY = baseCenter
    else
        baseTipX = bodyX + w
        baseTipY = baseCenter
    end

    local tailTipX = tailAnchorX
    local tailTipY = tailAnchorY
    local tailDX = tailAnchorX - baseTipX
    local tailDY = tailAnchorY - baseTipY
    local tailDistance = math.sqrt(tailDX * tailDX + tailDY * tailDY)
    if tailDistance > 0.001 then
        local actualTailLength = math.min(tailDistance, tailLength)
        tailTipX = baseTipX + tailDX / tailDistance * actualTailLength
        tailTipY = baseTipY + tailDY / tailDistance * actualTailLength
    end

    local pts = {}

    addSpeechPoint(pts, bodyX + cornerRadius, bodyY)
    if side == "down" then
        addSpeechPoint(pts, baseCenter - halfBase, bodyY)
        addSpeechPoint(pts, tailTipX, tailTipY)
        addSpeechPoint(pts, baseCenter + halfBase, bodyY)
    end
    addSpeechPoint(pts, bodyX + w - cornerRadius, bodyY)
    addSpeechArcPoints(pts, bodyX + w - cornerRadius, bodyY + cornerRadius, cornerRadius, -math.pi * 0.5, 0, arcSegments, true)

    addSpeechPoint(pts, bodyX + w, bodyY + h - cornerRadius)
    if side == "right" then
        addSpeechPoint(pts, bodyX + w, baseCenter - halfBase)
        addSpeechPoint(pts, tailTipX, tailTipY)
        addSpeechPoint(pts, bodyX + w, baseCenter + halfBase)
    end
    addSpeechArcPoints(pts, bodyX + w - cornerRadius, bodyY + h - cornerRadius, cornerRadius, 0, math.pi * 0.5, arcSegments, true)

    addSpeechPoint(pts, bodyX + cornerRadius, bodyY + h)
    if side == "up" then
        addSpeechPoint(pts, baseCenter + halfBase, bodyY + h)
        addSpeechPoint(pts, tailTipX, tailTipY)
        addSpeechPoint(pts, baseCenter - halfBase, bodyY + h)
    end
    addSpeechArcPoints(pts, bodyX + cornerRadius, bodyY + h - cornerRadius, cornerRadius, math.pi * 0.5, math.pi, arcSegments, true)

    addSpeechPoint(pts, bodyX, bodyY + cornerRadius)
    if side == "left" then
        addSpeechPoint(pts, bodyX, baseCenter + halfBase)
        addSpeechPoint(pts, tailTipX, tailTipY)
        addSpeechPoint(pts, bodyX, baseCenter - halfBase)
    end
    addSpeechArcPoints(pts, bodyX + cornerRadius, bodyY + cornerRadius, cornerRadius, math.pi, math.pi * 1.5, arcSegments, true)

    local firstPt = pts[1]
    local lastPt = pts[#pts]
    if firstPt and lastPt and math.abs(firstPt.x - lastPt.x) < 0.001 and math.abs(firstPt.y - lastPt.y) < 0.001 then
        table.remove(pts, #pts)
    end

    return {
        points = pts,
        side = side,
        baseCenter = baseCenter,
        tailBaseWidth = tailBaseWidth,
        tailLength = tailLength,
        tailTipX = tailTipX,
        tailTipY = tailTipY,
        cornerRadius = cornerRadius
    }
end

function drawSpeechBalloonFilledContour(contourPts, fillCol)
    local triangles = triangulateSimplePolygon(contourPts)
    if #triangles == 0 then
        return false
    end

    local poly = mesh()
    poly.vertices = {}
    poly.colors = {}

    for _, tri in ipairs(triangles) do
        for i = 1, 3 do
            poly.vertices[#poly.vertices + 1] = tri[i]
            poly.colors[#poly.colors + 1] = fillCol
        end
    end

    poly:draw()
    return true
end

function speechBalloon(aText, x, y, w, h, tailAnchorX, tailAnchorY, owner, showCloseX, opts)
    opts = opts or {}

    local theme = textElementTheme(owner)
    local fillCol = opts.fillColor or lightBlueForTextElements
    local cornerRadius = opts.cornerRadius or 18
    local textFontSize = opts.textFontSize or 20
    local lineHeight = opts.lineHeight or 24
    local bodyX = x - w * 0.5
    local bodyY = y - h * 0.5
    local textInsetX = opts.textInsetX or 20
    local textInsetTop = opts.textInsetTop or 20
    local textInsetBottom = opts.textInsetBottom or 18
    local textColor = opts.textColor or theme.fontColor
    local centerTextVertically = opts.centerTextVertically ~= false
    local textAreaW = math.max(40, w - textInsetX * 2)
    local textAreaH = math.max(lineHeight, h - textInsetTop - textInsetBottom)
    local lines = wrapTextLines(aText or "", textAreaW, TEXT_FONT, textFontSize)
    local maxLines = math.max(1, math.floor(textAreaH / lineHeight))
    local tailBaseWidth = opts.tailBaseWidth or speechBalloonTailWidthAtBase
    local tailLength = opts.tailLength or speechBalloonTailLength
    local contour = buildSpeechBalloonContour(bodyX, bodyY, w, h, tailAnchorX, tailAnchorY, {
        cornerRadius = cornerRadius,
        arcSegments = opts.arcSegments or 6,
        tailLength = tailLength,
        tailBaseWidth = tailBaseWidth
    })

    while #lines > maxLines do
        lines[#lines - 1] = lines[#lines - 1] .. " " .. lines[#lines]
        table.remove(lines, #lines)
    end

    pushStyle()
    drawSpeechBalloonShaderShape(bodyX, bodyY, w, h, contour, {
        fillColor = fillCol,
        outlineColor = color(255, 255, 255, 0),
        outlineWidth = 0,
        shaderPadding = 4
    })

    fill(textColor)
    noStroke()
    font(TEXT_FONT)
    fontSize(textFontSize)

    local blockH = #lines * lineHeight
    local firstLineY = bodyY + h - textInsetTop
    if centerTextVertically then
        local extraY = math.max(0, textAreaH - blockH) * 0.5
        firstLineY = bodyY + h - textInsetTop - extraY
    end

    for i, lineText in ipairs(lines) do
        local yy = firstLineY - (i - 1) * lineHeight
        textMode(CENTER)
        text(lineText, bodyX + w * 0.5, yy)
    end
    popStyle()
end

function drawSceneCanvas()
    local r = GAME.sceneRect
    local boardAccent = currentTurnCol()

    pushStyle()
    noStroke()
    fill(BOARD_INNER_COL)
    rect(0, 0, WIDTH, HEIGHT)

    if GAME.role == "gm" then
        fill(alphaColor(boardAccent, 180))
        noStroke()
        font(TEXT_FONT)
        fontSize(11)
        textMode(CENTER)
        text("GM", WIDTH * 0.5, HEIGHT - 18)
    end
    popStyle()

    pushMatrix()
    translate(r.x, r.y)
    scale(r.scale)

    drawBackgroundStrokes()
    drawFigures()
    drawElements()

    if shouldDrawFigureHandles() then
        drawFigureHandles()
    end

    popMatrix()

    drawSceneOverlayUI()
end

function drawBackgroundStrokes()
    drawStrokeArray(GAME.scene.background, false)
    drawLiveStrokePreview("background", "background")
end

function drawFigures()
    local figs = sortedFiguresForDraw()
    for _, fig in ipairs(figs) do
        drawSingleFigure(fig)
    end
end

function sortedFiguresForDraw()
    local out = {}
    for _, fig in ipairs(GAME.scene.figures) do
        table.insert(out, fig)
    end
    table.sort(out, function(a, b)
        if a.id == "player" then
            return true
        end
        if b.id == "player" then
            return false
        end
        return a.id < b.id
    end)
    return out
end

function drawSingleFigure(fig)
    pushMatrix()
    translate(fig.pos.x, fig.pos.y)
    rotate(math.deg(fig.rotation))
    scale(fig.scale)
    translate(-fig.baseW * 0.5, -fig.baseH * 0.5)
    DRAW_FIGURE_STROKE_SCALE = fig.scale
    drawStrokeArray(fig.strokes, true)
    drawLiveStrokePreview("figure", fig.id)
    DRAW_FIGURE_STROKE_SCALE = nil
    popMatrix()

    if liveStrokeMatchesTarget("figure", fig.id) then
        drawActiveFigureHighlight(fig)
    end

    if shouldShowFigureBox(fig) then
        local strokeCol = GAME.mode == "draw" and color(39, 174, 96) or unpackCol(fig.boxCol)
        local pts = figurePolygonPoints(fig)
        local dashStroke = GAME.mode == "draw" and alphaColor(strokeCol, 190) or alphaColor(strokeCol, 208)
        pushStyle()
        noFill()
        if GAME.mode == "draw" then
            stroke(dashStroke)
            strokeWidth(2)
            for i = 1, #pts do
                local a = pts[i]
                local b = pts[i % #pts + 1]
                drawDashedLine(a.x, a.y, b.x, b.y, 7, 5)
            end
        else
            drawPolygon(pts, color(255, 255, 255, 0), dashStroke, 2)
        end
        popStyle()
    end
end

function liveStrokeMatchesTarget(kind, id)
    local ts = GAME.touchState
    local owner = ts and ts.strokeOwner or nil
    return ts and ts.currentStroke and owner and owner.kind == kind and owner.id == id
end

function drawLiveStrokePreview(kind, id)
    if not liveStrokeMatchesTarget(kind, id) then
        return
    end
    drawStrokeArray({GAME.touchState.currentStroke}, kind == "figure")
end


function currentFigureStrokeWidthScale()
    local scaleValue = DRAW_FIGURE_STROKE_SCALE or 1
    if scaleValue == 0 then
        return 1
    end
    return 1 / scaleValue
end

function drawActiveFigureHighlight(fig)
    local outerInset = 4
    local innerInset = 1.5
    local outerStroke = 7 / math.max(fig.scale, 0.001)
    local innerStroke = 2.5 / math.max(fig.scale, 0.001)
    local cornerRadius = 10

    pushStyle()
    pushMatrix()
    translate(fig.pos.x, fig.pos.y)
    rotate(math.deg(fig.rotation))
    scale(fig.scale)
    translate(-fig.baseW * 0.5, -fig.baseH * 0.5)
    drawRoundedRectOutline(-outerInset, -outerInset, fig.baseW + outerInset * 2, fig.baseH + outerInset * 2, cornerRadius, alphaColor(currentTurnCol(), 240), outerStroke, 6)
    drawRoundedRectOutline(-innerInset, -innerInset, fig.baseW + innerInset * 2, fig.baseH + innerInset * 2, cornerRadius - 1, color(255, 255, 255, 220), innerStroke, 6)
    popMatrix()
    popStyle()
end
function drawStrokeArray(arr, onFigure)
    local widthScale = onFigure and currentFigureStrokeWidthScale() or 1
    for _, st in ipairs(arr) do
        pushStyle()
        if st.erase then
            blendMode(ZERO, ONE_MINUS_SRC_ALPHA)
            stroke(0, 0, 0, 255)
        else
            stroke(unpackCol(st.col))
            blendMode(NORMAL)
        end
        strokeWidth(st.size * widthScale)
        noFill()
        lineCapMode(ROUND)
        local pts = st.pts
        for i = 2, #pts do
            line(pts[i - 1].x, pts[i - 1].y, pts[i].x, pts[i].y)
        end
        if #pts == 1 then
            local p = pts[1]
            line(p.x, p.y, p.x + 0.01, p.y + 0.01)
        end
        popStyle()
    end
end

function shouldShowFigureBox(fig)
    if GAME.mode ~= "draw" then
        return false
    end
    if GAME.role == "gm" then
        return true
    end
    return fig.id == "player"
end

function shouldDrawFigureHandles()
    if GAME.role == "gm" then
        return GAME.mode == "move" and GAME.showFigureWidgets
    end
    return GAME.mode == "draw"
end

function shouldShowDeleteHandle(fig)
    return GAME.role == "gm" and GAME.mode == "move" and GAME.showFigureWidgets and fig.owner == "gm" and fig.id ~= "player"
end

function shouldShowScaleHandle(fig)
    return GAME.role == "gm" and GAME.mode == "move" and GAME.showFigureWidgets and canScaleFigure(fig)
end

function shouldShowRotateHandle(fig)
    if GAME.role == "gm" then
        return GAME.mode == "move" and GAME.showFigureWidgets
    end
    return GAME.mode == "draw" and fig.id == "player"
end

function drawFigureHandles()
    for _, fig in ipairs(GAME.scene.figures) do
        if shouldShowHandles(fig) then
            local hp = figureHandlePositions(fig)
            if shouldShowDeleteHandle(fig) then
                drawHandleCircle(hp.dismiss.x, hp.dismiss.y, HANDLE_R, "✕", color(192, 57, 43), color(255, 255, 255))
            end
            if shouldShowScaleHandle(fig) then
                drawHandleCircle(hp.scale.x, hp.scale.y, HANDLE_R, "⤡", color(50, 50, 50), color(255, 255, 255))
            end
            if shouldShowRotateHandle(fig) then
                drawHandleCircle(hp.rotate.x, hp.rotate.y, HANDLE_R, "↻", color(50, 50, 50), color(255, 255, 255))
            end
        end
    end
end

function canScaleFigure(fig)
    if GAME.role == "gm" then
        return true
    end
    return fig.id ~= "player"
end

function shouldShowHandles(fig)
    return shouldShowDeleteHandle(fig) or shouldShowScaleHandle(fig) or shouldShowRotateHandle(fig)
end

function drawHandleCircle(x, y, r, label, labelCol, fillCol)
    pushStyle()
    fill(fillCol)
    stroke(alphaColor(labelCol, 80))
    strokeWidth(1.8)
    ellipseMode(CENTER)
    ellipse(x, y, r * 2)
    fill(labelCol)
    noStroke()
    font(UI_FONT)
    fontSize(13)
    textMode(CENTER)
    text(label, x, y - 0.5)
    popStyle()
end

function drawElements()
    for _, el in ipairs(GAME.scene.elements) do
        if elementVisibleToCurrentRole(el) and el.visible then
            if el.type == "speech" then
                drawSpeech(el, false)
            elseif el.type == "action" then
                drawAction(el, false)
            end
        end
    end
end

function elementVisibleToCurrentRole(el)
    return true
end

function shouldShowSpeechDismiss(el, isCapture)
    return not isCapture and el.owner == "gm" and GAME.isGMTurn
end

function drawSpeech(el, isCapture)
    local metrics = speechMetrics(el)
    el.w = metrics.w
    el.h = metrics.h
    local theme = textElementTheme(el.owner)
    local placeholder = (el.text or "") == "" and not (GAME.textEdit.active and GAME.textEdit.elementId == el.id)
    local textColor = placeholder and alphaColor(theme.fontColor, 160) or theme.fontColor

    pushStyle()
    local shadowX = metrics.x + 2.5
    local shadowY = metrics.y - 2.5
    drawRoundedRect(shadowX, shadowY, metrics.w, metrics.h, 11, alphaColor(color(0, 0, 0), isCapture and 20 or 28), color(0, 0, 0, 0), 0)

    speechBalloon(
        displayTextForElement(el, "speech…"),
        metrics.x + metrics.w * 0.5,
        metrics.y + metrics.h * 0.5,
        metrics.w,
        metrics.h,
        metrics.tailAnchorX,
        metrics.tailAnchorY,
        el.owner,
        shouldShowSpeechDismiss(el, isCapture),
        {
            fillColor = lightBlueForTextElements,
            textFontSize = 14,
            lineHeight = 16,
            cornerRadius = 11,
            textInsetX = 10,
            textInsetTop = 9,
            textInsetBottom = 9,
            textColor = textColor,
            centerTextVertically = true,
            tailLength = speechBalloonTailLength,
            tailBaseWidth = speechBalloonTailWidthAtBase,
            arcSegments = 6
        }
    )
    popStyle()

    if shouldShowSpeechDismiss(el, isCapture) then
        drawSpeechDismiss(el)
    end
end

function drawSpeechDismiss(el)
    local m = speechMetrics(el)
    pushStyle()
    fill(136, 136, 136)
    stroke(255, 255, 255)
    strokeWidth(1.5)
    ellipseMode(CENTER)
    ellipse(m.delX, m.delY, 12)
    fill(255)
    noStroke()
    font(UI_FONT)
    fontSize(9)
    textMode(CENTER)
    text("✕", m.delX, m.delY - 0.5)
    popStyle()
end

function drawAction(el, isCapture)
    local metrics = actionMetrics(el)
    el.w = metrics.w
    el.h = metrics.h
    local accent = color(192, 57, 43)
    local bubbleFillColor = lightBlueForTextElements
    local theme = textElementTheme(el.owner)
    local textColor = nil
    local lines = wrapTextLines(displayTextForElement(el, "action…"), metrics.w - 18, TEXT_FONT, 14)
    local placeholder = (el.text or "") == "" and not (GAME.textEdit.active and GAME.textEdit.elementId == el.id)
    textColor = placeholder and alphaColor(theme.fontColor, 160) or theme.fontColor

    if el.dot then
        pushStyle()
        stroke(accent)
        strokeWidth(2.5)
        drawDashedLine(el.pos.x, el.pos.y, el.dot.x, el.dot.y, 7, 4)
        fill(color(192, 57, 43, 220))
        noStroke()
        ellipseMode(CENTER)
        ellipse(el.dot.x, el.dot.y, DOT_R * 2)
        popStyle()
    end

    pushStyle()
    drawRoundedRect(metrics.x, metrics.y, metrics.w, metrics.h, 10, bubbleFillColor, bubbleFillColor, 1.2)
    fill(textColor)
    noStroke()
    font(TEXT_FONT)
    fontSize(14)
    textMode(CORNER)
    drawTextBlock(lines, metrics.x + 10, metrics.y + metrics.h - 18, 16, "left")
    popStyle()
end

function displayTextForElement(el, placeholder)
    local txt = el.text or ""
    if GAME.textEdit.active and GAME.textEdit.elementId == el.id then
        txt = GAME.textEdit.text
        if BLINK_ON then
            txt = txt .. "|"
        end
    end
    if txt == "" then
        return placeholder
    end
    return txt
end

function drawSceneOverlayUI()
    local layoutMetrics = uiLayoutMetrics()
    local stackRects = layoutMetrics.stackRects
    GAME.ui.speech = nil
    GAME.ui.action = nil
    GAME.ui.pass = nil
    GAME.ui.figlib = nil
    GAME.ui.modeToggle = nil
    GAME.ui.storybook = nil
    GAME.ui.storybookSaveLoad = nil
    GAME.ui.figureWidgets = nil
    GAME.ui.endStory = nil
    GAME.ui.bglib = nil
    GAME.ui.undo = nil
    GAME.ui.redo = nil
    GAME.ui.pencil = nil
    GAME.ui.erase = nil
    GAME.ui.clear = nil
    GAME.ui.paletteToggle = nil
    GAME.ui.paletteDots = {}
    GAME.ui.sizes = {}
    GAME.ui.figurePreviewRects = {}
    GAME.ui.figureAdd = nil
    GAME.ui.backgroundPreviewRects = {}
    GAME.ui.backgroundAdd = nil
    GAME.ui.readyStorybook = nil
    GAME.ui.confirmCancel = nil
    GAME.ui.confirmOK = nil
    GAME.ui.storybookSaveLoadClose = nil
    GAME.ui.storybookSaveMode = nil
    GAME.ui.storybookLoadMode = nil
    GAME.ui.storybookSaveLoadSlots = {}

    GAME.ui.modeToggle = stackRects[1]
    drawModeToggleButton(stackRects[1])

    local buttons = currentModeStackButtons()
    for i, button in ipairs(buttons) do
        local rect = stackRects[i + 1]
        if rect then
            GAME.ui[button.key] = rect
            if button.key == "figureWidgets" then
                drawFigureWidgetToggleButton(rect, button.active, button.tint)
            else
                drawStackButton(rect, button.label, button.active, button.tint)
            end
        end
    end

    if GAME.mode == "draw" then
        drawPaletteControls()
    end

    if GAME.mode == "move" and GAME.role == "gm" and GAME.ui.showFigureLibrary then
        drawFigureLibraryPanel(layoutMetrics)
    end

    if GAME.mode == "move" and GAME.role == "gm" and GAME.ui.showBackgroundLibrary then
        drawBackgroundLibraryPanel(layoutMetrics)
    end
end

function uiLayoutMetrics()
    local frame = safeContentFrame(14)
    local buttonW = 58
    local buttonH = 38
    local buttonGap = 10
    local stackX = frame.right - buttonW
    local startY = frame.top - buttonH
    local stackRects = {}

    for i = 1, 10 do
        stackRects[i] = {x = stackX, y = startY - (i - 1) * (buttonH + buttonGap), w = buttonW, h = buttonH}
    end

    return {
        frame = frame,
        buttonW = buttonW,
        buttonH = buttonH,
        buttonGap = buttonGap,
        stackRects = stackRects
    }
end

function currentModeStackButtons()
    local buttons = {}

    if GAME.mode == "draw" then
        buttons[#buttons + 1] = {key = "undo", label = "↩", active = false, tint = nil}
        buttons[#buttons + 1] = {key = "redo", label = "↪", active = false, tint = nil}
        buttons[#buttons + 1] = {key = "pencil", label = "✏️", active = not GAME.erase, tint = currentTurnCol()}
        buttons[#buttons + 1] = {key = "erase", label = "🧽", active = GAME.erase, tint = currentTurnCol()}
        buttons[#buttons + 1] = {key = "clear", label = "clear", active = false, tint = nil}
    else
        if GAME.role == "gm" then
            buttons[#buttons + 1] = {key = "figlib", label = #GAME.figureLibrary > 0 and "🧍📚" or "🧍+", active = GAME.ui.showFigureLibrary, tint = GM_COL}
            buttons[#buttons + 1] = {key = "bglib", label = #GAME.backgroundLibrary > 0 and "🖼️📚" or "🖼️+", active = GAME.ui.showBackgroundLibrary, tint = BG_COL}
            buttons[#buttons + 1] = {key = "figureWidgets", label = nil, active = GAME.showFigureWidgets, tint = color(192, 57, 43)}
        end
        buttons[#buttons + 1] = {key = "speech", label = GAME.role == "gm" and "💬+" or "💬", active = speechButtonActive(), tint = currentTurnCol()}
        buttons[#buttons + 1] = {key = "action", label = "🎯", active = actionButtonActive(), tint = currentTurnCol()}
    end

    if GAME.turnCount > 0 then
        buttons[#buttons + 1] = {key = "storybook", label = "📖", active = false, tint = nil}
        buttons[#buttons + 1] = {key = "storybookSaveLoad", label = "💾📖", active = false, tint = nil}
    end

    if GAME.role == "gm" and GAME.turnCount > 0 then
        buttons[#buttons + 1] = {key = "endStory", label = "🏳️", active = false, tint = nil}
    end

    buttons[#buttons + 1] = {key = "pass", label = GAME.role == "gm" and "▶" or "⏎", active = false, tint = color(192, 57, 43)}

    return buttons
end

function speechButtonActive()
    if GAME.role == "pl" and GAME.playerSpeechId then
        local el = getElementById(GAME.playerSpeechId)
        return el and el.visible
    end
    return false
end

function actionButtonActive()
    if GAME.role == "pl" and GAME.playerActionId then
        local el = getElementById(GAME.playerActionId)
        return el and el.visible
    end
    return false
end

EMOJI_ICON_LABELS = {
    ["💬"] = true,
    ["💬+"] = true,
    ["🎯"] = true,
    ["🧍📚"] = true,
    ["🧍+"] = true,
    ["🖼️📚"] = true,
    ["🖼️+"] = true,
    ["✏️"] = true,
    ["🧽"] = true,
    ["🎨"] = true,
    ["🎬"] = true,
    ["🏳️"] = true,
    ["💾📖"] = true
}

COMBINED_ICON_LABELS = {
    ["💬+"] = true,
    ["🧍📚"] = true,
    ["🧍+"] = true,
    ["🖼️📚"] = true,
    ["🖼️+"] = true,
    ["💾📖"] = true
}

function applyIconLabelStyle(label, baseSize)
    local usesEmoji = EMOJI_ICON_LABELS[label] == true
    font(usesEmoji and EMOJI_FONT or UI_FONT)

    local fontSizeValue = baseSize
    if COMBINED_ICON_LABELS[label] then
        fontSizeValue = math.max(baseSize - 4, 10)
    elseif usesEmoji then
        fontSizeValue = math.max(baseSize - 1, 10)
    end
    fontSize(fontSizeValue)
end

function currentModeButtonColors()
    if GAME.mode == "draw" then
        return {
            fill = color(224, 145, 64, 96),
            stroke = color(236, 156, 72, 168)
        }
    end
    return {
        fill = color(128, 92, 196, 96),
        stroke = color(154, 116, 224, 168)
    }
end

function currentModeButtonTint()
    return currentModeButtonColors().fill
end

function drawButtonShell(r, active, accent)
    pushStyle()
    local baseColors = currentModeButtonColors()
    local fillCol = baseColors.fill
    local strokeCol = baseColors.stroke

    if accent then
        fillCol = mixColor(baseColors.fill, alphaColor(accent, baseColors.fill.a), active and 0.5 or 0.22)
        strokeCol = mixColor(baseColors.stroke, alphaColor(accent, baseColors.stroke.a), active and 0.45 or 0.2)
    end

    if active then
        fillCol = alphaColor(fillCol, math.min(fillCol.a + 44, 255))
        strokeCol = alphaColor(strokeCol, math.min(strokeCol.a + 42, 255))
    end

    drawRoundedRect(r.x, r.y, r.w, r.h, 12, fillCol, strokeCol, active and 1.8 or 1.2)
    popStyle()
end

function drawButtonLabel(r, label, labelCol, size)
    pushStyle()
    fill(labelCol or color(255, 255, 255, 228))
    noStroke()
    applyIconLabelStyle(label, size or 18)
    textMode(CENTER)
    text(label, r.x + r.w * 0.5, r.y + r.h * 0.5 - 0.5)
    popStyle()
end

function drawStackButton(r, label, active, accent)
    drawButtonShell(r, active, accent)
    local labelCol = active and color(255, 255, 255, 246) or color(255, 255, 255, 228)
    drawButtonLabel(r, label, labelCol, 18)
end

function drawFigureWidgetToggleButton(r, active, accent)
    drawButtonShell(r, active, accent)

    local centerY = r.y + r.h * 0.5 - 0.5
    local spacing = r.w * 0.22
    local cx = r.x + r.w * 0.5

    pushStyle()
    textMode(CENTER)
    noStroke()

    font(UI_FONT)
    fontSize(15)
    fill(255, 255, 255, active and 246 or 228)
    text("↻", cx - spacing, centerY)
    text("⤡", cx, centerY)

    fill(color(228, 74, 74, active and 246 or 228))
    text("✕", cx + spacing, centerY)

    if not active then
        stroke(color(228, 74, 74, 240))
        strokeWidth(2.2)
        line(r.x + 11, r.y + 10, r.x + r.w - 11, r.y + r.h - 10)
    end
    popStyle()
end

function drawModeToggleButton(r)
    drawButtonShell(r, true, nil)

    local isDraw = GAME.mode == "draw"
    local activeAlpha = 255
    local inactiveAlpha = 118
    local paintSize = isDraw and 21 or 16
    local danceSize = isDraw and 13 or 17
    local cy = r.y + r.h * 0.5 - 0.5
    local danceCx = r.x + r.w * 0.69
    local danceSpacing = 7

    pushStyle()
    noStroke()
    font(EMOJI_FONT)
    fill(255, 255, 255, isDraw and activeAlpha or inactiveAlpha)
    fontSize(paintSize)
    textMode(CENTER)
    text("🎨", r.x + r.w * 0.31, cy)

    font(UI_FONT)
    fill(255, 255, 255, 185)
    fontSize(15)
    text("/", r.x + r.w * 0.5, cy)

    fill(255, 255, 255, isDraw and inactiveAlpha or activeAlpha)
    font(EMOJI_FONT)
    fontSize(danceSize)
    text("💃", danceCx - danceSpacing * 0.5, cy + 0.35)
    text("🕺", danceCx + danceSpacing * 0.5, cy - 0.35)
    popStyle()
end

function drawIconButton(cx, cy, radius, label, fillCol, labelCol)
    local r = {x = cx - radius, y = cy - radius, w = radius * 2, h = radius * 2}
    pushStyle()
    drawRoundedRect(r.x, r.y, r.w, r.h, math.min(12, radius), fillCol, color(255, 255, 255, 38), 1.2)
    fill(labelCol)
    noStroke()
    applyIconLabelStyle(label, 16)
    textMode(CENTER)
    text(label, cx, cy - 0.5)
    popStyle()
end

function drawMiniButton(r, label)
    drawStackButton(r, label, false, nil)
end

function drawPaletteControls()
    local frame = safeContentFrame(14)
    local baseX = frame.left
    local baseY = frame.bottom
    local sizeW = 28
    local sizeGap = 8
    local buttonH = 28

    for i, sz in ipairs(BRUSH_SIZES) do
        local rr = {x = baseX + (i - 1) * (sizeW + sizeGap), y = baseY, w = sizeW, h = buttonH}
        GAME.ui.sizes[i] = rr
        drawButtonShell(rr, i == GAME.brushSizeIndex, nil)
        pushStyle()
        fill(0, 0, 0, 0)
        stroke(i == GAME.brushSizeIndex and 255 or color(255, 255, 255, 70))
        strokeWidth(i == GAME.brushSizeIndex and 1.8 or 1)
        ellipseMode(CENTER)
        ellipse(rr.x + rr.w * 0.5, rr.y + rr.h * 0.5, 18)
        fill(GAME.activeCol)
        noStroke()
        local dot = math.min(sz * 1.4, 14)
        ellipse(rr.x + rr.w * 0.5, rr.y + rr.h * 0.5, dot)
        popStyle()
    end

    local toggleX = baseX + #BRUSH_SIZES * (sizeW + sizeGap)
    GAME.ui.paletteToggle = {x = toggleX, y = baseY, w = 30, h = buttonH}
    drawStackButton(GAME.ui.paletteToggle, GAME.showPalette and "▾" or "▴", GAME.showPalette, nil)

    if not GAME.showPalette then
        return
    end

    local idx = 0
    local swatchW = 24
    local swatchGap = 6
    for row = 1, #PALETTE_ROWS do
        local y = baseY + buttonH + 10 + (#PALETTE_ROWS - row) * (swatchW + swatchGap)
        for colIdx = 1, #PALETTE_ROWS[row] do
            idx = idx + 1
            local rr = {
                x = baseX + (colIdx - 1) * (swatchW + swatchGap),
                y = y,
                w = swatchW,
                h = swatchW
            }
            GAME.ui.paletteDots[idx] = rr
            drawButtonShell(rr, colorsEqual(GAME.activeCol, PALETTE_ROWS[row][colIdx]), nil)
            pushStyle()
            fill(PALETTE_ROWS[row][colIdx])
            stroke(colorsEqual(GAME.activeCol, PALETTE_ROWS[row][colIdx]) and 255 or color(255, 255, 255, 70))
            strokeWidth(colorsEqual(GAME.activeCol, PALETTE_ROWS[row][colIdx]) and 2.5 or 1.4)
            ellipseMode(CENTER)
            ellipse(rr.x + rr.w * 0.5, rr.y + rr.h * 0.5, 16)
            popStyle()
        end
    end
end

function colorsEqual(a, b)
    return a.r == b.r and a.g == b.g and a.b == b.b and a.a == b.a
end

function libraryPanelLayout(layoutMetrics, stackRect, cardW, cardH, itemCount)
    local frame = layoutMetrics.frame
    local gap = 8
    local innerPad = 10
    local titleH = 18
    local cols = math.max(1, math.min(4, itemCount + 1))
    local contentW = cols * cardW + math.max(0, cols - 1) * gap
    local w = contentW + innerPad * 2
    local rows = math.max(1, math.ceil((itemCount + 1) / cols))
    local contentH = rows * cardH + math.max(0, rows - 1) * gap
    local h = titleH + contentH + innerPad * 2
    local x = clamp(stackRect.x - w - 12, frame.left, stackRect.x - 12)
    local y = clamp(stackRect.y - h + layoutMetrics.buttonH, frame.bottom, frame.top - h)
    return {
        x = x,
        y = y,
        w = w,
        h = h,
        pad = innerPad,
        gap = gap,
        titleH = titleH,
        cols = cols,
        cardW = cardW,
        cardH = cardH,
        contentX = x + innerPad,
        contentY = y + innerPad,
        titleY = y + h - 14
    }
end

function libraryGridRect(panel, index)
    local col = (index - 1) % panel.cols
    local row = math.floor((index - 1) / panel.cols)
    return {
        x = panel.contentX + col * (panel.cardW + panel.gap),
        y = panel.contentY + row * (panel.cardH + panel.gap),
        w = panel.cardW,
        h = panel.cardH
    }
end

function drawLibraryPanelShell(panel, title)
    pushStyle()
    drawRoundedRect(panel.x + 4, panel.y - 4, panel.w, panel.h, 12, color(0, 0, 0, 44), color(0, 0, 0, 0), 0)
    drawRoundedRect(panel.x, panel.y, panel.w, panel.h, 12, color(20, 20, 20, 235), color(255, 255, 255, 30), 1.4)
    fill(255, 255, 255, 132)
    noStroke()
    font(TEXT_FONT)
    fontSize(9)
    textMode(CORNER)
    text(title, panel.x + panel.pad, panel.titleY)
    popStyle()
end

function drawLibraryAddCard(r)
    pushStyle()
    drawRoundedRect(r.x, r.y, r.w, r.h, 6, color(255, 255, 255, 14), color(255, 255, 255, 0), 0)
    stroke(255, 255, 255, 88)
    strokeWidth(1.5)
    lineCapMode(ROUND)
    local dash = 5
    local gap = 4
    drawDashedLine(r.x + 7, r.y + 1, r.x + r.w - 7, r.y + 1, dash, gap)
    drawDashedLine(r.x + r.w - 1, r.y + 7, r.x + r.w - 1, r.y + r.h - 7, dash, gap)
    drawDashedLine(r.x + r.w - 7, r.y + r.h - 1, r.x + 7, r.y + r.h - 1, dash, gap)
    drawDashedLine(r.x + 1, r.y + r.h - 7, r.x + 1, r.y + 7, dash, gap)
    fill(255, 255, 255, 124)
    noStroke()
    font(UI_FONT)
    fontSize(math.min(r.h * 0.52, 22))
    textMode(CENTER)
    text("+", r.x + r.w * 0.5, r.y + r.h * 0.5 - 1)
    popStyle()
end

function drawLibraryPreviewCard(r, borderCol, drawContents)
    pushStyle()
    drawRoundedRect(r.x, r.y, r.w, r.h, 6, color(255, 255, 255, 12), alphaColor(borderCol, 210), 1.5)
    clip(r.x + 1, r.y + 1, math.max(1, r.w - 2), math.max(1, r.h - 2))
    drawContents()
    noClip()
    popStyle()
end

function drawFigureLibraryPanel(layoutMetrics)
    local stackRect = layoutMetrics.stackRects[2]
    local cardW = math.floor(FIGURE_W * 0.35)
    local cardH = math.floor(FIGURE_H * 0.35)
    local panel = libraryPanelLayout(layoutMetrics, stackRect, cardW, cardH, #GAME.figureLibrary)

    drawLibraryPanelShell(panel, "AVATAR LIBRARY")

    GAME.ui.figurePreviewRects = {}
    GAME.ui.figureAdd = libraryGridRect(panel, 1)
    drawLibraryAddCard(GAME.ui.figureAdd)

    for i, fig in ipairs(GAME.figureLibrary) do
        local rr = libraryGridRect(panel, i + 1)
        GAME.ui.figurePreviewRects[i] = rr
        drawFigurePreview(rr, fig)
    end
end

function drawBackgroundLibraryPanel(layoutMetrics)
    local stackRect = layoutMetrics.stackRects[3]
    local cardW = 52
    local cardH = 36
    local panel = libraryPanelLayout(layoutMetrics, stackRect, cardW, cardH, #GAME.backgroundLibrary)

    drawLibraryPanelShell(panel, "BACKGROUND LIBRARY")

    GAME.ui.backgroundPreviewRects = {}
    GAME.ui.backgroundAdd = libraryGridRect(panel, 1)
    drawLibraryAddCard(GAME.ui.backgroundAdd)

    for i, bg in ipairs(GAME.backgroundLibrary) do
        local rr = libraryGridRect(panel, i + 1)
        GAME.ui.backgroundPreviewRects[i] = rr
        drawBackgroundPreview(rr, bg)
    end
end

function drawFigurePreview(r, fig)
    local borderCol = unpackCol(fig.boxCol or packCol(GM_COL))
    drawLibraryPreviewCard(r, borderCol, function()
        pushMatrix()
        translate(r.x + r.w * 0.5, r.y + 2)
        local s = math.min((r.w - 8) / math.max(fig.baseW, 1), (r.h - 4) / math.max(fig.baseH, 1))
        scale(s, s)
        translate(-fig.baseW * 0.5, 0)
        drawStrokeArray(fig.strokes or {}, true)
        popMatrix()
    end)
end

function drawBackgroundPreview(r, bg)
    drawLibraryPreviewCard(r, BG_COL, function()
        pushMatrix()
        translate(r.x, r.y)
        local previewW = math.max(r.w, 1)
        local previewH = math.max(r.h, 1)
        local sx = previewW / math.max(SCENE_W, 1)
        local sy = previewH / math.max(SCENE_H, 1)
        scale(sx, sy)
        drawStrokeArray(bg.strokes or {}, false)
        popMatrix()
    end)
end

function drawBottomControls()
    GAME.ui.move = nil
    GAME.ui.draw = nil
end

function drawModePill(r, label, active)
    drawStackButton(r, label, active, active and currentTurnCol() or nil)
end

function drawReadyOverlay()
    local label = GAME.overlay.readyFor == "gm" and "gm's turn" or "player's turn"
    local hasStorybook = GAME.turnCount > 0
    local panelW = math.min(WIDTH - 56, 360)
    local panelH = HEIGHT * 0.4
    local panelX = WIDTH * 0.5 - panelW * 0.5
    local panelY = HEIGHT * 0.5 - panelH * 0.5

    pushStyle()
    drawRoundedRect(panelX + 4, panelY - 4, panelW, panelH, 18, color(0, 0, 0, 32), color(0, 0, 0, 0), 0)
  drawRoundedRect(panelX, panelY, panelW, panelH, 18, TURN_START_PANEL_BG, TURN_START_PANEL_BG, 1.4)

    fill(255, 255, 255, 236)
    noStroke()
    font(TEXT_FONT)
    fontSize(50)
    textMode(CENTER)
    text(label, WIDTH * 0.5, panelY + (panelH * 0.55))

    fill(255, 162)
    fontSize(30)
  text("tap anywhere to start", WIDTH * 0.5, panelY + (panelH * 0.42))

    if hasStorybook then
    GAME.ui.readyStorybook = {x = WIDTH * 0.5 - 82, y = panelY + (panelH * 0.24), w = 164, h = 34}
        drawTextClose(GAME.ui.readyStorybook, "story so far")
    end
    popStyle()
end

function drawConfirmOverlay()
    local panelW = math.min(WIDTH - 56, 360)
    local panelH = 156
    local panelX = WIDTH * 0.5 - panelW * 0.5
    local panelY = HEIGHT * 0.5 - panelH * 0.5

    pushStyle()
    fill(color(8, 8, 12, 128))
    noStroke()
    rect(0, 0, WIDTH, HEIGHT)

    drawRoundedRect(panelX + 4, panelY - 4, panelW, panelH, 18, color(0, 0, 0, 40), color(0, 0, 0, 0), 0)
    drawRoundedRect(panelX, panelY, panelW, panelH, 18, color(215, 109, 227, 236), color(221, 140, 224, 148), 1.4)

    fill(255, 255, 255, 236)
    font(TEXT_FONT)
    fontSize(26)
    textMode(CENTER)
    text(GAME.overlay.title or "are you sure?", WIDTH * 0.5, panelY + panelH - 36)

    fill(255, 255, 255, 150)
    fontSize(16)
    textWrapWidth(panelW - 48)
    text(GAME.overlay.message or "", WIDTH * 0.5, panelY + panelH - 72)
    textWrapWidth(0)

    GAME.ui.confirmCancel = {x = panelX + 26, y = panelY + 22, w = 120, h = 36}
    GAME.ui.confirmOK = {x = panelX + panelW - 146, y = panelY + 22, w = 120, h = 36}
    drawTextClose(GAME.ui.confirmCancel, "cancel")
    drawButtonShell(GAME.ui.confirmOK, false, color(192, 57, 43))
    pushStyle()
    fill(color(255, 255, 255, 228))
    noStroke()
    font(TEXT_FONT)
    fontSize(16)
    textMode(CENTER)
    text(GAME.overlay.confirmLabel or "confirm", GAME.ui.confirmOK.x + GAME.ui.confirmOK.w * 0.5, GAME.ui.confirmOK.y + GAME.ui.confirmOK.h * 0.5)
    popStyle()
    popStyle()
end

function drawEndOverlay()
    pushStyle()
    fill(DARK_OVERLAY)
    noStroke()
    rect(0, 0, WIDTH, HEIGHT)
    fill(255, 255, 255, 230)
    font(TEXT_FONT)
    fontSize(48)
    textMode(CENTER)
    text("The End", WIDTH * 0.5, HEIGHT * 0.56)
    fill(255, 255, 255, 90)
    fontSize(14)
    text("TAP ANYWHERE TO START OVER", WIDTH * 0.5, HEIGHT * 0.45)
    popStyle()
end

function drawFlipbookOverlay()
    local frame = safeContentFrame(14)
    pushStyle()
    fill(DARK_OVERLAY)
    noStroke()
    rect(0, 0, WIDTH, HEIGHT)

    if #GAME.flipbook == 0 then
        fill(255)
        font(TEXT_FONT)
        fontSize(24)
        textMode(CENTER)
        text("storybook is empty", WIDTH * 0.5, HEIGHT * 0.5)
        popStyle()
        return
    end

    local img = GAME.flipbook[GAME.flipIndex]
    local iw = img.width
    local ih = img.height
    local s = math.min((WIDTH - 70) / iw, (HEIGHT - 180) / ih)
    local sw = iw * s
    local sh = ih * s
    local cx = WIDTH * 0.5
    local cy = HEIGHT * 0.54

    drawRoundedRect(cx - sw * 0.5 - 8, cy - sh * 0.5 - 8, sw + 16, sh + 16, 10, color(255, 255, 255, 26), color(255, 255, 255, 24), 1.2)
    spriteMode(CENTER)
    sprite(img, cx, cy, sw, sh)

    fill(255, 255, 255, 128)
    noStroke()
    font(TEXT_FONT)
    fontSize(22)
    textMode(CENTER)
    text("storybook — page " .. GAME.flipIndex .. " of " .. #GAME.flipbook, WIDTH * 0.5, HEIGHT - 42)

    local buttonY = frame.bottom
    GAME.ui.flipPrev = {x = cx - 82, y = buttonY, w = 44, h = 30}
    GAME.ui.flipNext = {x = cx - 24, y = buttonY, w = 44, h = 30}
    GAME.ui.flipClose = {x = cx + 42, y = buttonY, w = 64, h = 30}
    drawModePill(GAME.ui.flipPrev, "←", false)
    drawModePill(GAME.ui.flipNext, "→", false)
    drawTextClose(GAME.ui.flipClose, "Close")
    popStyle()
end

function drawStorybookSaveLoadOverlay()
    local panelW = math.min(WIDTH - 50, 430)
    local panelH = math.min(HEIGHT - 60, 320)
    local panelX = WIDTH * 0.5 - panelW * 0.5
    local panelY = HEIGHT * 0.5 - panelH * 0.5

    pushStyle()
    fill(DARK_OVERLAY)
    noStroke()
    rect(0, 0, WIDTH, HEIGHT)

    drawRoundedRect(panelX + 4, panelY - 4, panelW, panelH, 18, color(0, 0, 0, 40), color(0, 0, 0, 0), 0)
    drawRoundedRect(panelX, panelY, panelW, panelH, 18, color(28, 31, 40, 240), color(255, 255, 255, 32), 1.4)

    fill(255, 255, 255, 236)
    noStroke()
    font(TEXT_FONT)
    fontSize(24)
    textMode(CENTER)
    text("storybook saves", WIDTH * 0.5, panelY + panelH - 30)

    local saveActive = GAME.storybookSaveMode ~= "load"
    local loadActive = GAME.storybookSaveMode == "load"
    GAME.ui.storybookSaveMode = {x = panelX + 24, y = panelY + panelH - 74, w = 96, h = 34}
    GAME.ui.storybookLoadMode = {x = panelX + 132, y = panelY + panelH - 74, w = 96, h = 34}
    GAME.ui.storybookSaveLoadClose = {x = panelX + panelW - 96, y = panelY + panelH - 74, w = 72, h = 34}
    drawStackButton(GAME.ui.storybookSaveMode, "save", saveActive, color(39, 174, 96))
    drawStackButton(GAME.ui.storybookLoadMode, "load", loadActive, color(41, 128, 185))
    drawTextClose(GAME.ui.storybookSaveLoadClose, "close")

    fill(255, 255, 255, 132)
    fontSize(14)
    textMode(CORNER)
    local summary = tostring(#GAME.flipbook) .. " pages • " .. tostring(#GAME.figureLibrary) .. " avatars • " .. tostring(#GAME.backgroundLibrary) .. " backgrounds"
    text(summary, panelX + 24, panelY + panelH - 102)

    GAME.ui.storybookSaveLoadSlots = {}
    local slotY = panelY + panelH - 146
    local slotH = 48
    local slotGap = 12
    for i = 1, STORYBOOK_SAVE_SLOT_COUNT do
        local rr = {x = panelX + 24, y = slotY - (i - 1) * (slotH + slotGap), w = panelW - 48, h = slotH}
        GAME.ui.storybookSaveLoadSlots[i] = rr
        local hasData = GAME.storybookSaveSlots[i] ~= nil
        local accent = GAME.storybookSaveMode == "load" and color(41, 128, 185) or color(39, 174, 96)
        drawButtonShell(rr, false, hasData and accent or nil)

        local slot = GAME.storybookSaveSlots[i]
        local label = storybookSlotLabel(i)
        local updatedAt = slot and slot.updatedAt or (GAME.storybookSaveMode == "load" and "no save available" or "tap to save current storybook")
        local actionLabel = GAME.storybookSaveMode == "load" and (hasData and "load" or "empty") or (hasData and "overwrite" or "save")

        pushStyle()
        fill(255, 255, 255, hasData and 228 or 150)
        noStroke()
        font(TEXT_FONT)
        fontSize(17)
        textMode(CORNER)
        text(label, rr.x + 12, rr.y + rr.h - 15)

        fill(255, 255, 255, 120)
        fontSize(12)
        text(updatedAt, rr.x + 12, rr.y + 11)

        fill(accent)
        font(UI_FONT)
        fontSize(15)
        textMode(CENTER)
        text(string.upper(actionLabel), rr.x + rr.w - 42, rr.y + rr.h * 0.5 - 0.5)
        popStyle()
    end

    if GAME.storybookSaveNotice then
        fill(255, 255, 255, 174)
        noStroke()
        font(TEXT_FONT)
        fontSize(13)
        textMode(CENTER)
        text(GAME.storybookSaveNotice, WIDTH * 0.5, panelY + 24)
    end
    popStyle()
end

function drawTextClose(r, label)
    pushStyle()
    drawRoundedRect(r.x, r.y, r.w, r.h, 10, color(255, 0), color(255, 125), 1.2)
    fill(56, 177)
    noStroke()
    font(TEXT_FONT)
    fontSize(16)
    textMode(CENTER)
    text(label, r.x + r.w * 0.5, r.y + r.h * 0.5)
    popStyle()
end

