endScreenMissedWordsJob = endScreenMissedWordsJob or nil
endScreenMissedWordsJobMatchId = endScreenMissedWordsJobMatchId or nil
endScreenCommentDraft = endScreenCommentDraft or ""
endScreenCommentMatchId = endScreenCommentMatchId or nil
endScreenSpeechBalloonsVisible = endScreenSpeechBalloonsVisible ~= false
endScreenCommentUIActive = endScreenCommentUIActive or false
endScreenSpeechBalloonAlpha = endScreenSpeechBalloonAlpha or 1
endScreenLocalBalloonAlpha = endScreenLocalBalloonAlpha or 1
endScreenCommentFieldActivated = endScreenCommentFieldActivated or false
endScreenCommentFieldTornDown = endScreenCommentFieldTornDown or false

speechBalloonPOCShader = speechBalloonPOCShader or {
vert = [[
precision highp float;
uniform mat4 modelViewProjection;
attribute vec4 position;
attribute vec2 texCoord;

varying highp vec2 vTexCoord;

void main()
{
    vTexCoord = texCoord;
    gl_Position = modelViewProjection * position;
}
]],

frag = [[
precision highp float;

const int MAX_CONTOUR_POINTS = 64;

uniform lowp vec4 fillColor;
uniform lowp vec4 outlineColor;
uniform vec2 canvasSize;
uniform vec2 contourPoints[MAX_CONTOUR_POINTS];
uniform float contourPointCount;
uniform float outlineWidth;
uniform float edgeSoftness;

varying highp vec2 vTexCoord;

float sdContourPolygon(vec2 p)
{
    vec2 previous = contourPoints[0];
    for (int i = 1; i < MAX_CONTOUR_POINTS; i = i + 1) {
        if (float(i) >= contourPointCount) {
            break;
        }
        previous = contourPoints[i];
    }

    float minDistanceSq = dot(p - contourPoints[0], p - contourPoints[0]);
    float windingSign = 1.0;

    for (int i = 0; i < MAX_CONTOUR_POINTS; i = i + 1) {
        if (float(i) >= contourPointCount) {
            break;
        }

        vec2 current = contourPoints[i];
        vec2 edge = previous - current;
        vec2 relative = p - current;
        float edgeLengthSq = max(dot(edge, edge), 0.000001);
        vec2 nearest = relative - edge * clamp(dot(relative, edge) / edgeLengthSq, 0.0, 1.0);
        minDistanceSq = min(minDistanceSq, dot(nearest, nearest));

        bool aboveCurrent = p.y >= current.y;
        bool belowPrevious = p.y < previous.y;
        bool leftOfEdge = edge.x * relative.y > edge.y * relative.x;
        if ((aboveCurrent && belowPrevious && leftOfEdge) || (!aboveCurrent && !belowPrevious && !leftOfEdge)) {
            windingSign = -windingSign;
        }

        previous = current;
    }

    return windingSign * sqrt(minDistanceSq);
}

void main()
{
    vec2 p = (vTexCoord - 0.5) * canvasSize;
    float dist = sdContourPolygon(p);
    float aa = max(edgeSoftness, 0.75);

    float fillMask = 1.0 - smoothstep(0.0, aa, dist);
    float strokeMask = 0.0;
    if (outlineWidth > 0.0) {
        float innerStrokeMask = smoothstep(-outlineWidth - aa, -outlineWidth + aa, dist);
        strokeMask = fillMask * innerStrokeMask;
    }

    float fillAlpha = fillColor.a * fillMask;
    float strokeAlpha = outlineColor.a * strokeMask;
    float outAlpha = strokeAlpha + fillAlpha * (1.0 - strokeAlpha);

    if (outAlpha <= 0.001) {
        discard;
    }

    vec3 outRgb = (outlineColor.rgb * strokeAlpha + fillColor.rgb * fillAlpha * (1.0 - strokeAlpha)) / outAlpha;
    gl_FragColor = vec4(outRgb, outAlpha);
}
]]
}

function ensureSpeechBalloonPOCResources()
    if SPEECH_BALLOON_POC_SHADER then
        return
    end

    SPEECH_BALLOON_POC_SHADER = shader(speechBalloonPOCShader.vert, speechBalloonPOCShader.frag)
    SPEECH_BALLOON_POC_MESH = mesh()
    SPEECH_BALLOON_POC_MESH:addRect(0, 0, 1, 1)
    SPEECH_BALLOON_POC_MESH.shader = SPEECH_BALLOON_POC_SHADER
end

function speechBalloonShaderContourPoints(contour, canvasCenterX, canvasCenterY)
    local maxContourPoints = 64
    local points = {}
    local contourPoints = contour.points or {}
    local total = math.min(#contourPoints, maxContourPoints)

    for i = 1, total do
        local pt = contourPoints[i]
        points[i] = vec2(pt.x - canvasCenterX, pt.y - canvasCenterY)
    end

    if total == 0 then
        points[1] = vec2(0, 0)
        total = 1
    end

    local lastPoint = points[total]
    for i = total + 1, maxContourPoints do
        points[i] = lastPoint
    end

    return points, total
end

local function normalizeCommentDraft(text)
  local s = tostring(text or "")
  s = s:gsub("[\r\n]+", " ")
  s = s:gsub("%s+", " ")
  local maxLen = MAX_MATCH_COMMENT_LEN or 100
  if #s > maxLen then
    s = s:sub(1, maxLen)
  end
  return s
end

local function syncEndScreenCommentState(model)
  local qid = currentQMatch and currentQMatch.id or nil
  if endScreenCommentMatchId ~= qid then
    endScreenCommentMatchId = qid
    endScreenCommentDraft = ""
    endScreenSpeechBalloonsVisible = true
    endScreenCommentFieldActivated = false
    endScreenCommentFieldTornDown = false
  end

  local shouldActivate = model and model.commentUI and model.commentUI.canCompose or false
  if shouldActivate and not endScreenCommentFieldActivated then
    endScreenCommentFieldActivated = true
    -- Do NOT auto-focus here; keyboard appears only when user taps the balloon
  end
  endScreenCommentUIActive = shouldActivate or endScreenCommentFieldActivated
end

-- Tears down slot 3 of the shared commentFields table (see the field-management
-- functions below, near drawBalloonMockupOverlay) — the production composer's
-- own field. Never touches slots 1/2 (the dev mockup's fields).
function teardownEndScreenCommentField()
  local F = commentFields and commentFields[3]
  if F and F.tv then
    F.tv:resignFirstResponder_()
    F.tv:removeFromSuperview_()
    F.tv = nil
  end
  if F then F.focused = false end
  endScreenCommentFieldActivated = false
  endScreenCommentFieldTornDown = true
end

function commitEndScreenCommentAndExit()
  local submitted = false
  if submitFinalCommentFromEndScreen then
    submitted = submitFinalCommentFromEndScreen(endScreenCommentDraft)
  elseif finalizeCompletedTurnBasedMatch then
    submitted = finalizeCompletedTurnBasedMatch(endScreenCommentDraft)
  end
  if not submitted then return false end
  endScreenCommentDraft = ""
  teardownEndScreenCommentField()
  startSeasonTransition()
  return true
end

local function codeaToUIKitRect(x, y, w, h)
  return objc.rect(x, HEIGHT - y - h, w, h)
end

local function wrapSpeechBalloonText(textValue, maxWidth, fontSizeValue, maxLines)
  local words = {}
  for word in tostring(textValue or ""):gmatch("%S+") do
    words[#words + 1] = word
  end
  if #words == 0 then return {} end

  pushStyle()
  font("HelveticaNeue")
  fontSize(fontSizeValue)
  local lines = {}
  local current = words[1]
  for i = 2, #words do
    local candidate = current .. " " .. words[i]
    local w = textSize(candidate)
    if w <= maxWidth then
      current = candidate
    else
      lines[#lines + 1] = current
      current = words[i]
    end
  end
  lines[#lines + 1] = current

  -- Cap at maxLines; the last kept line gets an ellipsis (trimmed to fit) so
  -- overflow text is indicated rather than silently dropped.
  if maxLines and #lines > maxLines then
    for i = #lines, maxLines + 1, -1 do lines[i] = nil end
    local last = lines[maxLines] or ""
    while last ~= "" and textSize(last .. "…") > maxWidth do
      local trimmed = last:gsub("%s*%S+%s*$", "")
      if trimmed == last then break end
      last = trimmed
    end
    lines[maxLines] = (last == "") and "…" or (last .. "…")
  end
  popStyle()
  return lines
end

local function measureSpeechBalloonText(textValue, maxWidth, fontSizeValue, lineHeight, insetX, insetY, maxLines)
  local lines = wrapSpeechBalloonText(textValue, maxWidth, fontSizeValue, maxLines)
  local contentH = math.max(lineHeight, #lines * lineHeight)
  local totalH = contentH + insetY * 2
  return {
    lines = lines,
    height = totalH,
    textWidth = maxWidth,
    insetX = insetX,
    insetY = insetY,
  }
end

local function addSpeechPoint(pts, px, py)
  local last = pts[#pts]
  if last and math.abs(last.x - px) < 0.001 and math.abs(last.y - py) < 0.001 then
    return
  end
  pts[#pts + 1] = vec2(px, py)
end

local function addSpeechArcPoints(pts, cx, cy, radius, startAngle, endAngle, segments, skipFirst)
  for i = 0, segments do
    if not (skipFirst and i == 0) then
      local t = i / segments
      local angle = startAngle + (endAngle - startAngle) * t
      addSpeechPoint(pts, cx + math.cos(angle) * radius, cy + math.sin(angle) * radius)
    end
  end
end

local function clampSpeechTailBase(side, bodyX, bodyY, w, h, cornerRadius, tailBaseWidth, desiredCenter)
  local halfBase = tailBaseWidth * 0.5
  if side == "down" or side == "up" then
    local minValue = bodyX + cornerRadius + halfBase
    local maxValue = bodyX + w - cornerRadius - halfBase
    return math.max(minValue, math.min(maxValue, desiredCenter))
  end
  local minValue = bodyY + cornerRadius + halfBase
  local maxValue = bodyY + h - cornerRadius - halfBase
  return math.max(minValue, math.min(maxValue, desiredCenter))
end

local function speechTailBaseCenterForSide(side, bodyX, bodyY, w, h, tailAnchorX, tailAnchorY)
  if side == "down" or side == "up" then
    return tailAnchorX
  end
  return tailAnchorY
end

local function buildSpeechBalloonContour(bodyX, bodyY, w, h, tailAnchorX, tailAnchorY, opts)
  opts = opts or {}
  local cornerRadius = math.max(0, math.min(opts.cornerRadius or math.min(w, h) * 0.28, math.min(w, h) * 0.5))
  local arcSegments = math.max(6, math.floor(opts.arcSegments or 10))
  local tailBaseWidth = math.max(1, opts.tailBaseWidth or (w * 0.14))
  local tailLength = math.max(0, opts.tailLength or (h * 0.28))
  local side = opts.tailSide or "down"
  local desiredBaseCenter = opts.tailBaseCenterOverride or speechTailBaseCenterForSide(side, bodyX, bodyY, w, h, tailAnchorX, tailAnchorY)
  local baseCenter = clampSpeechTailBase(
    side, bodyX, bodyY, w, h, cornerRadius, tailBaseWidth, desiredBaseCenter
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

  return { points = pts }
end

local function contourBounds(contour)
  local pts = contour and contour.points or {}
  local minX, minY = math.huge, math.huge
  local maxX, maxY = -math.huge, -math.huge
  for i = 1, #pts do
    local p = pts[i]
    if p.x < minX then minX = p.x end
    if p.y < minY then minY = p.y end
    if p.x > maxX then maxX = p.x end
    if p.y > maxY then maxY = p.y end
  end
  if #pts == 0 then
    return 0, 0, 1, 1
  end
  return minX, minY, maxX, maxY
end

local function drawSpeechBalloon(rect, textValue, tailAnchorX, tailAnchorY, tailSide, fillColor, outlineColor, opts)
  if not rect or not textValue or textValue == "" then return end
  opts = opts or {}
  local alphaMul = opts.alphaMul or 1
  if alphaMul <= 0.01 then return end

  local fc  = fillColor    or color(255, 255, 255, 245)
  local oc  = outlineColor or (Color.uiAccent or color(40, 80, 60, 255))
  local fa  = math.floor((fc.a or 255) * alphaMul)
  local oa  = math.floor((oc.a or 255) * alphaMul)
  local bodyFill   = color(fc.r, fc.g, fc.b, fa)
  local borderFill = color(oc.r, oc.g, oc.b, oa)
  local cr         = opts.cornerRadius  or math.min(rect.w, rect.h) * 0.30
  local outlineW   = opts.outlineWidth  or 1.5
  local hasTail    = not opts.noTail

  -- Tail geometry (skipped entirely when opts.noTail — a plain rounded-rect
  -- balloon with no triangle, e.g. the local composer before it's "attached"
  -- to anyone in particular).
  local P1x, P1y, P2x, P2y, tipX, tipY
  if hasTail then
    local tailBaseW  = opts.tailBaseWidth or (rect.w * 0.13)
    local tailLen    = opts.tailLength    or (rect.h * 0.36)

    -- Tail base: top or bottom edge depending on tailSide
    local onTop = (tailSide == "up" or tailSide == "top")
    local baseY = onTop and (rect.y + rect.h - 2) or (rect.y + 2)  -- overlap into body so tail+balloon fills merge
    local baseX = opts.tailAnchorOverrideX or (rect.x + rect.w * 0.5)
    baseX = math.max(rect.x + cr + tailBaseW * 0.5,
            math.min(rect.x + rect.w - cr - tailBaseW * 0.5, baseX))

    -- Tail tip: step toward anchor from the chosen edge, limited to tailLen
    local dx = tailAnchorX - baseX
    local dy = tailAnchorY - baseY
    local dist = math.sqrt(dx * dx + dy * dy)
    tipX = baseX
    tipY = onTop and (baseY + tailLen) or (baseY - tailLen)
    if dist > 0.01 then
      local s = math.min(dist, tailLen) / dist
      tipX = baseX + dx * s
      tipY = baseY + dy * s
    end

    -- Tail geometry: the FILL comes to a SHARP point (tip); only the OUTLINE is
    -- rounded around that point, line-cap style (a small border cap circle).
    local halfB = tailBaseW * 0.5
    P1x, P1y = baseX - halfB, baseY   -- left base
    P2x, P2y = baseX + halfB, baseY   -- right base
  end

  -- Border pass: dark, uniform-width outline around body AND tail (if any).
  if outlineW > 0 then
    if hasTail then
      local cenX = (P1x + P2x + tipX) / 3
      local cenY = (P1y + P2y + tipY) / 3
      local function outwardNormal(Qx, Qy, Rx, Ry)
        local dx, dy = Rx - Qx, Ry - Qy
        local len = math.sqrt(dx*dx + dy*dy)
        if len < 0.0001 then return 0, 0 end
        local nx, ny = -dy/len, dx/len
        local mx, my = (Qx + Rx) * 0.5, (Qy + Ry) * 0.5
        if (nx*(mx - cenX) + ny*(my - cenY)) < 0 then nx, ny = -nx, -ny end
        return nx, ny
      end
      local nLx, nLy = outwardNormal(P1x, P1y, tipX, tipY)  -- left side
      local nRx, nRy = outwardNormal(P2x, P2y, tipX, tipY)  -- right side
      local bm = mesh()
      bm.vertices = {
        vec2(P1x, P1y), vec2(tipX, tipY), vec2(tipX + nLx*outlineW, tipY + nLy*outlineW),
        vec2(P1x, P1y), vec2(tipX + nLx*outlineW, tipY + nLy*outlineW), vec2(P1x + nLx*outlineW, P1y + nLy*outlineW),
        vec2(P2x, P2y), vec2(tipX, tipY), vec2(tipX + nRx*outlineW, tipY + nRy*outlineW),
        vec2(P2x, P2y), vec2(tipX + nRx*outlineW, tipY + nRy*outlineW), vec2(P2x + nRx*outlineW, P2y + nRy*outlineW),
      }
      local bcol = {}
      for i = 1, 12 do bcol[i] = borderFill end
      bm.colors = bcol
      bm:draw()
      -- rounded outline tip, line-cap style: a small circle at the sharp fill point
      pushStyle()
      noStroke()
      fill(borderFill)
      ellipseMode(CENTER)
      ellipse(tipX, tipY, outlineW * 2, outlineW * 2)
      popStyle()
    end
    drawRoundedRect(
      rect.x + rect.w * 0.5, rect.y + rect.h * 0.5,
      rect.w + outlineW * 2,  rect.h + outlineW * 2,
      cr + outlineW, borderFill, borderFill
    )
  end

  -- Fill pass: sharp-pointed tail triangle (no rounded fill cap), if any.
  if hasTail then
    local fm = mesh()
    fm.vertices = {
      vec2(P1x, P1y), vec2(P2x, P2y), vec2(tipX, tipY),
    }
    fm.colors = { bodyFill, bodyFill, bodyFill }
    fm:draw()
  end
  drawRoundedRect(
    rect.x + rect.w * 0.5, rect.y + rect.h * 0.5,
    rect.w, rect.h,
    cr, bodyFill, bodyFill
  )

  -- Text
  local textInsetX = opts.textInsetX or (rect.w * 0.06)
  local textInsetY = opts.textInsetY or 4
  local fontSizeValue = opts.fontSizeValue or math.max(14, rect.h * 0.24)
  local lineH  = opts.lineHeight or (fontSizeValue * 1.08)
  local lines  = opts.lines or wrapSpeechBalloonText(textValue, rect.w - textInsetX * 2, fontSizeValue, opts.maxLines)
  local textCenterY = rect.y + rect.h * 0.5
  local startY = textCenterY + ((#lines - 1) * lineH) * 0.5
  pushStyle()
  local tc = opts.textColor or Color.tileText or color(40, 80, 60, 255)
  fill(tc.r, tc.g, tc.b, math.floor((tc.a or 255) * alphaMul))
  textAlign(CENTER)
  textMode(CENTER)
  font("HelveticaNeue")
  fontSize(fontSizeValue)
  for i = 1, #lines do
    text(lines[i], rect.x + rect.w * 0.5, startY - (i - 1) * lineH)
  end
  popStyle()
end

-- Ten candidate balloon color schemes, built live from the ACTIVE season's Color
-- table (not hardcoded per-season) so every option auto-translates across seasons
-- via blendColor(). Each entry supplies an active style (fill/stroke/text) and a
-- further-muted placeholder style (for the empty/unfocused composer balloon).
-- #10 is the original pre-muting look (bright uiAccent fill), kept as a baseline
-- for comparison in the debug picker. See drawBalloonColorPickerOverlay below.
BALLOON_COLOR_SCHEMES = BALLOON_COLOR_SCHEMES or {
  { name = "Soft Accent", build = function(C)
      local fill = blendColor(C.uiAccent, C.panelBG, 0.55)
      return { fill = fill, stroke = C.tileStroke, text = C.tileText,
        placeholderFill = blendColor(fill, C.panelBG, 0.5),
        placeholderStroke = blendColor(C.tileStroke, C.panelBG, 0.5) }
    end },
  { name = "Pastel Tile", build = function(C)
      return { fill = C.tileFill, stroke = C.tileStroke, text = C.tileText,
        placeholderFill = blendColor(C.tileFill, C.panelBG, 0.5),
        placeholderStroke = blendColor(C.tileStroke, C.panelBG, 0.5) }
    end },
  { name = "Muted Accent 2", build = function(C)
      local fill = blendColor(C.uiAccent2, C.panelBG, 0.5)
      local stroke = blendColor(C.uiAccent2, C.tileText, 0.35)
      return { fill = fill, stroke = stroke, text = C.tileText,
        placeholderFill = blendColor(fill, C.panelBG, 0.5),
        placeholderStroke = blendColor(stroke, C.panelBG, 0.5) }
    end },
  { name = "Ink on Cream", build = function(C)
      return { fill = C.panelBG, stroke = C.tileText, text = C.tileText,
        placeholderFill = blendColor(C.panelBG, C.gridBg, 0.5),
        placeholderStroke = blendColor(C.tileText, C.panelBG, 0.6) }
    end },
  { name = "Grid Wash", build = function(C)
      local fill = blendColor(C.gridBg, C.uiAccent, 0.25)
      return { fill = fill, stroke = C.tileStroke, text = C.tileText,
        placeholderFill = blendColor(C.gridBg, C.panelBG, 0.4),
        placeholderStroke = blendColor(C.tileStroke, C.panelBG, 0.5) }
    end },
  { name = "Dusty Ink", build = function(C)
      local fill = blendColor(C.tileText, C.panelBG, 0.78)
      return { fill = fill, stroke = C.tileText, text = C.panelBG,
        placeholderFill = blendColor(fill, C.panelBG, 0.4),
        placeholderStroke = blendColor(C.tileText, C.panelBG, 0.65) }
    end },
  { name = "Accent Whisper", build = function(C)
      local fill = blendColor(C.uiAccent, C.bg, 0.6)
      local stroke = blendColor(C.uiAccent, C.tileText, 0.4)
      return { fill = fill, stroke = stroke, text = C.tileText,
        placeholderFill = blendColor(fill, C.bg, 0.45),
        placeholderStroke = blendColor(stroke, C.bg, 0.45) }
    end },
  { name = "Warm Neutral", build = function(C)
      local fill = blendColor(C.panelBG, C.tileStroke, 0.22)
      return { fill = fill, stroke = C.tileStroke, text = C.tileText,
        placeholderFill = blendColor(fill, C.panelBG, 0.5),
        placeholderStroke = blendColor(C.tileStroke, C.panelBG, 0.5) }
    end },
  { name = "Highlight Soft", build = function(C)
      local hl = C.selectLineAlsoWeirdlyTileHighlight
      local fill = blendColor(hl, C.panelBG, 0.6)
      local stroke = blendColor(hl, C.tileText, 0.35)
      return { fill = fill, stroke = stroke, text = C.tileText,
        placeholderFill = blendColor(fill, C.panelBG, 0.5),
        placeholderStroke = blendColor(stroke, C.panelBG, 0.5) }
    end },
  { name = "Original (baseline)", build = function(C)
      return { fill = C.uiAccent, stroke = C.tileText, text = C.panelBG,
        placeholderFill = color(214, 214, 214, 255),
        placeholderStroke = color(168, 168, 168, 255) }
    end },
}
balloonColorSchemeIndex = balloonColorSchemeIndex or 1  -- default = "Soft Accent" (muted)

function currentBalloonColorScheme()
  local entry = BALLOON_COLOR_SCHEMES[balloonColorSchemeIndex] or BALLOON_COLOR_SCHEMES[1]
  return entry.build(Color)
end

local function drawEndScreenSpeechBalloons(model, layout)
  local ui = model and model.commentUI
  endScreenOppBalloonRect = nil
  endScreenLocalBalloonRect = nil
  if not (ui and ui.hasAnyComment) then return end
  -- Per-balloon visibility: showOpponent/showLocal default to true and are gated
  -- by the master showBalloons flag, so existing callers (which set neither) keep
  -- the original single-toggle behavior. The mockup drives each balloon separately.
  local oppTarget   = (ui.showBalloons and (ui.showOpponent ~= false)) and 1 or 0
  local localTarget = (ui.showBalloons and (ui.showLocal   ~= false)) and 1 or 0
  endScreenSpeechBalloonAlpha = endScreenSpeechBalloonAlpha + (oppTarget   - endScreenSpeechBalloonAlpha) * math.min(1, DeltaTime * 14)
  endScreenLocalBalloonAlpha  = endScreenLocalBalloonAlpha  + (localTarget - endScreenLocalBalloonAlpha)  * math.min(1, DeltaTime * 14)
  local oppAlpha   = endScreenSpeechBalloonAlpha
  local localAlpha = endScreenLocalBalloonAlpha
  if oppAlpha <= 0.01 and localAlpha <= 0.01 then return end

  local topY    = layout.msgCY + layout.msgH * 0.5
  local bottomY = layout.scoreCY - layout.scoreH * 0.5
  local areaCY  = (topY + bottomY) * 0.5
  local areaH   = math.max(1, topY - bottomY)
  local avatarLayout = getEndUpperRightAvatarLayout{
    rightCX = layout.rightCX, areaCY = areaCY,
    rightW  = layout.rightW,  areaH  = areaH,
  }

  local balloonFontSize = layout.cardHeaderH * 0.44
  local lineHeight      = balloonFontSize * 1.12
  local bLeft           = layout.panelX - layout.panelW * 0.5 + 6
  local bRight          = layout.panelX + layout.panelW * 0.5 - 28
  local bubbleW         = bRight - bLeft
  local panelLeft       = layout.panelX - layout.panelW * 0.5
  local panelRight      = layout.panelX + layout.panelW * 0.5
  local boardBottom     = layout.boardCY - layout.boardSide * 0.5
  local insetY = 14
  local maxBalloonLines = 3   -- balloons wrap up to 3 lines, then ellipsize
  -- Per-balloon color overrides: <opp/local>FillOverride wins, then the shared
  -- fillOverride (legacy single override), then the seasonal default. Lets the
  -- mockup grey each balloon out independently based on its own field state.
  local scheme          = currentBalloonColorScheme()
  local defFill         = scheme.fill   or Color.uiAccent or color(40, 80, 60, 255)
  local defStroke       = scheme.stroke or Color.tileText  or color(40, 80, 60, 255)
  local oppFill         = ui.oppFillOverride     or ui.fillOverride   or defFill
  local oppStroke       = ui.oppStrokeOverride   or ui.strokeOverride or defStroke
  local localFill       = ui.localFillOverride   or ui.fillOverride   or defFill
  local localStroke     = ui.localStrokeOverride or ui.strokeOverride or defStroke
  local bText           = scheme.text or Color.panelBG or color(245, 242, 232, 255)

  -- When only ONE balloon is visible, center it horizontally; when both show, keep
  -- the staggered left/right positions. The tail stays put across the shift because
  -- its base is anchored to the avatar X (tailAnchorOverrideX), not the body center.
  -- ui.centerBothBalloons overrides this to center BOTH regardless (mockup scenario 2:
  -- the opponent's real comment centered like a solo balloon, with the local composer,
  -- tail-less below, centered the same way — see localTailUsesOpponentSlot below for
  -- how scenario 1 uses the opponent tail X but keeps the staggered layout).
  local oppShown   = (ui.opponentComment and ui.opponentComment ~= "" and ui.showOpponent ~= false)
  local localShown = (ui.localComment   and ui.localComment   ~= "" and ui.showLocal   ~= false)
  local centeredX  = layout.panelX - bubbleW * 0.5
  local oppRectX, localRectX
  if ui.centerBothBalloons then
    oppRectX, localRectX = centeredX, centeredX
  else
    oppRectX   = (oppShown   and not localShown) and centeredX or (panelLeft + 2)
    localRectX = (localShown and not oppShown)   and centeredX or (panelRight - 2 - bubbleW)
  end

  -- Opponent (originator) balloon — tail points at opponent avatar
  local oppRect = nil
  if ui.opponentComment and ui.opponentComment ~= "" then
    local measured = measureSpeechBalloonText(ui.opponentComment, bubbleW - 8, balloonFontSize, lineHeight, 4, insetY, maxBalloonLines)
    local bH = math.max(layout.boardSide * 0.16, measured.height)
    oppRect = {
      -- ui.oppBodyXNudge (default 0) shifts the BODY only — tailAnchorOverrideX below
      -- stays avatarLayout.opponentX regardless, so the tail doesn't move with it.
      x = oppRectX + (ui.oppBodyXNudge or 0),
      -- Same top-anchor offset (14) as the solo-local fallback below, so the
      -- topmost balloon sits at a consistent height whether it's alone or
      -- has a second balloon stacked under it.
      y = boardBottom - 14 - bH,
      w = bubbleW, h = bH,
    }
    drawSpeechBalloon(oppRect, ui.opponentComment,
      avatarLayout.opponentX, avatarLayout.opponentY, "up",
      oppFill, oppStroke, {
        fontSizeValue = balloonFontSize, lineHeight = lineHeight,
        cornerRadius  = 16,
        tailLength    = 43 * (2 / 3),  -- 2026-07-20: shortened to 2/3 of the original 43
        tailBaseWidth = 18,
        textInsetX = 4, textInsetY = insetY,
        alphaMul = oppAlpha,
        outlineWidth = 7,
        textColor = (ui.suppressText and color(0, 0, 0, 0)) or bText,
        tailAnchorOverrideX = avatarLayout.opponentX,
        lines = measured.lines,
        maxLines = maxBalloonLines,
      })
    endScreenOppBalloonRect = oppRect
  end

  -- Local (responder) balloon — stacked below opponent, tail points at local avatar.
  -- ui.localTailUsesOpponentSlot (mockup scenario 1 only, "initiator composing" — no
  -- one has spoken yet so the lone balloon reads as the FIRST word, not a reply) points
  -- the tail at the opponent avatar's X instead — same X the opponent balloon's tail
  -- uses (avatarLayout.opponentX, no +18) — while the balloon itself stays in its
  -- normal bottom/local Y position. Both avatars still draw normally either way.
  -- ui.localTailXNudge (default 0, mockup scenario 6: -9, half of tailBaseWidth=18)
  -- shifts just the tail, independent of the body nudges above.
  local localTailX = (ui.localTailUsesOpponentSlot and avatarLayout.opponentX or (avatarLayout.localX + 18))
    + (ui.localTailXNudge or 0)
  if ui.localComment and ui.localComment ~= "" then
    local measured = measureSpeechBalloonText(ui.localComment, bubbleW - 8, balloonFontSize, lineHeight, 4, insetY, maxBalloonLines)
    local bH = math.max(layout.boardSide * 0.15, measured.height)
    -- ui.localGapExtra (default 0) adds extra breathing room below the opponent
    -- balloon, on top of the normal 14 stacking gap — only meaningful when oppRect
    -- exists (mockup scenario 2: paired with centerBothBalloons/suppressLocalTail
    -- so the two don't read as a merged block).
    local localGap = 14 + (ui.localGapExtra or 0)
    local localRect = {
      -- ui.localBodyXNudge (default 0) shifts the BODY only — localTailX above stays
      -- put, so the tail doesn't move with it.
      x = localRectX + (ui.localBodyXNudge or 0),
      y = oppRect and (oppRect.y - localGap - bH) or (boardBottom - 14 - bH),
      w = bubbleW, h = bH,
    }
    drawSpeechBalloon(localRect, ui.localComment,
      localTailX, avatarLayout.localY, "up",
      localFill, localStroke, {
        fontSizeValue = balloonFontSize, lineHeight = lineHeight,
        cornerRadius  = 16,
        tailLength    = 40 * (2 / 3),  -- 2026-07-20: shortened to 2/3 of the original 40
        tailBaseWidth = 18,
        textInsetX = 4, textInsetY = insetY,
        alphaMul = localAlpha,
        outlineWidth = 7,
        textColor = (ui.suppressLocalText and color(0, 0, 0, 0)) or bText,
        tailAnchorOverrideX = localTailX,
        noTail = ui.suppressLocalTail or false,
        lines = measured.lines,
        maxLines = maxBalloonLines,
      })
    endScreenLocalBalloonRect = localRect
  end
end

-- Native UITextViews that live inside speech balloons for real typing. A
-- UITextView (not UITextField) so input wraps to multiple lines with a
-- correctly positioned caret. The view shows the VISIBLE text; the balloon
-- is drawn shape-only (suppressText/suppressLocalText) behind it and is
-- sized to the typed text so it grows to match.
--
-- SHARED between the dev balloon mockup (slot 2 — the local/composing
-- balloon, see drawBalloonMockupOverlay below, gated by balloonMockupOverlay;
-- slot 1 is unused since the opponent balloon is never live-typed, in the
-- mockup or in production) and the production end-screen composer (slot 3 —
-- see positionEndScreenCommentField, gated by
-- useTurnBased/endScreenCommentFieldTornDown). Both paths call the exact
-- same ensure/update/line-cap/placeholder code so production visually and
-- behaviorally matches the approved mockup — no parallel reimplementation.
commentFields = commentFields or { [1] = {}, [2] = {} }  -- [i] = { tv, focused, flash, lastValid }
commentFieldDelegate = commentFieldDelegate or nil        -- one shared delegate; dispatches by tv.tag

local function ensureCommentFieldDelegate()
  if commentFieldDelegate then return commentFieldDelegate end
  if not (objc and objc.delegate) then return nil end
  local Delegate = objc.delegate("UITextViewDelegate")
  -- Callbacks ONLY set Lua flags — never call UIKit/Codea from an objc callback (it can
  -- crash the draw cycle). Actual text mutation / resignFirstResponder happens in draw()
  -- (enforceCommentFieldLineCap), driven by these flags. Params use type-prefixed names (o=object).
  function Delegate:textViewDidBeginEditing_(oTV)
    local i = tonumber(oTV.tag) or 0
    if commentFields[i] then commentFields[i].focused = true end
  end
  function Delegate:textViewDidEndEditing_(oTV)
    local i = tonumber(oTV.tag) or 0
    if commentFields[i] then commentFields[i].focused = false end
  end
  commentFieldDelegate = Delegate()
  return commentFieldDelegate
end

local function ensureCommentField(i, fontSize)
  commentFields[i] = commentFields[i] or {}
  local F = commentFields[i]
  if F.tv then return end
  if not (objc and objc.UITextView) then return end
  local hostView = (objc.viewer and objc.viewer.view and objc.viewer.view.subviews and objc.viewer.view.subviews[1])
    or (objc.viewer and objc.viewer.view)
  if not hostView then return end
  local tv = objc.UITextView:alloc():init()
  hostView:addSubview_(tv)
  tv.tag = i                              -- delegate dispatches per-field by tag
  tv.backgroundColor = color(0, 0, 0, 0)  -- transparent (bridge assigns Codea color() to UIColor props)
  tv.font = objc.UIFont:fontWithName_size_("HelveticaNeue", fontSize or 18)
  pcall(function() tv.scrollEnabled = true end)   -- text beyond 3 lines scrolls in-place
  pcall(function() tv.editable = true end)
  pcall(function() tv.textAlignment = objc.enum.NSTextAlignment.center end)
  pcall(function() tv.textContainer.lineFragmentPadding = 0 end)  -- wrap width ≈ frame width
  tv.delegate = ensureCommentFieldDelegate()
  F.tv = tv
  F.focused = false
end

local function updateCommentField(i, rect, shown, fontSize, textEntryEnabled)
  ensureCommentField(i, fontSize)
  local F = commentFields[i]
  local tv = F.tv
  if not tv then return end
  if shown and rect then
    tv.hidden = false
    local enabled = (textEntryEnabled ~= false)
    tv.userInteractionEnabled = enabled
    if not enabled then
      tv:resignFirstResponder_()
      F.focused = false
    end
    -- visible native text in the balloon's seasonal text color — or RED while the
    -- line-cap flash timer is active (set when an over-limit keystroke was blocked).
    local tc = (currentBalloonColorScheme().text) or Color.panelBG or color(245, 242, 232, 255)
    if (F.flash or 0) > 0 then
      tv.textColor = color(224, 48, 48, 255)
    else
      tv.textColor = color(tc.r or 245, tc.g or 242, tc.b or 232, 255)
    end
    pcall(function() tv.tintColor = color(tc.r or 245, tc.g or 242, tc.b or 232, 255) end)
    tv.frame = codeaToUIKitRect(rect.x, rect.y, rect.w, rect.h)
  else
    tv.hidden = true
    tv:resignFirstResponder_()
    F.focused = false
  end
end

-- Line cap: a balloon holds at most 3 lines. If a keystroke would wrap the text to a
-- 4th line, revert it (block the input) and flash that balloon's text red. Measured
-- with the SAME width/font the renderer uses so the check matches the balloon's own
-- wrap. All UITextView mutation happens HERE in draw() (never in the objc callbacks).
-- Return-to-dismiss: strips any newline (keeps the comment one wrapped paragraph) and
-- drops the keyboard — it does NOT submit anything; callers decide what "submit" means.
local function enforceCommentFieldLineCap(i, fontSizeValue, wrapWidth)
  local F = commentFields[i]
  if not F then return "" end
  F.flash = math.max(0, (F.flash or 0) - DeltaTime)
  local tv = F.tv
  if not tv then return "" end
  local s = tostring(tv.text or "")
  if s:find("\n") then
    s = (s:gsub("\n", ""))
    tv.text = s
    tv:resignFirstResponder_()
  end
  local MAX_LINES = 3
  local lines = wrapSpeechBalloonText(s, wrapWidth, fontSizeValue)
  local overflow = #lines > MAX_LINES
  if not overflow and #lines == MAX_LINES then
    -- Reserve ~5 characters of headroom on the last line. The native UITextView
    -- measures slightly differently than this Lua wrap, so a 3rd line filled right to
    -- the edge (e.g. after tacking on an ellipsis) can wrap to a 4th line in the view
    -- even while this check still counts 3. Blocking a near-full last line early keeps
    -- the two in sync and avoids that edge case.
    pushStyle()
    font("HelveticaNeue"); fontSize(fontSizeValue)
    local margin = textSize("nnnnn")            -- ~5 characters of slack
    if textSize(lines[#lines] or "") > wrapWidth - margin then overflow = true end
    popStyle()
  end
  if overflow then
    tv.text = F.lastValid or ""                 -- block: revert to the last ≤3-line text
    F.flash = 0.22                              -- flash red
    return F.lastValid or ""
  end
  F.lastValid = s
  return s
end

-- Positions the native comment view inside `balloonRect` and draws the Codea
-- placeholder (bold italic, tileText@80%, dead-centered in the rect) behind
-- it whenever the field is inactive (empty + unfocused). Both the mockup and
-- the production composer call this exact function.
local function positionCommentField(i, balloonRect, shownFlag, activeFlag, placeholderText, fontSizeValue, textEntryEnabled, setHitRect)
  if shownFlag and balloonRect then
    local br = balloonRect
    local fRect = { x = br.x + 6, y = br.y + 6, w = br.w - 12, h = br.h - 12 }
    updateCommentField(i, fRect, true, fontSizeValue, textEntryEnabled)
    if setHitRect then
      setHitRect({ cx = fRect.x + fRect.w * 0.5, cy = fRect.y + fRect.h * 0.5, w = fRect.w, h = fRect.h })
    end
    if not activeFlag then
      -- pushStyle/popStyle here (previously missing — the bug that used to leak this
      -- font into whatever drew next this frame) now just belongs to good hygiene:
      -- GLOBAL_UI_FONT (Main.lua) makes HelveticaNeue-BoldItalic the deliberate ambient
      -- default everywhere that doesn't explicitly pin its own font, so this call no
      -- longer needs to "leak" to have its old effect — but it shouldn't clobber
      -- whatever runs right after it either.
      pushStyle()
      local pc = Color.tileText or color(40, 80, 60)
      fill(pc.r, pc.g, pc.b, 204)                       -- 20% transparent
      textMode(CENTER); textAlign(CENTER)
      font("HelveticaNeue-BoldItalic")
      fontSize(18)
      text(placeholderText or "", br.x + br.w * 0.5, br.y + br.h * 0.5)
      popStyle()
    end
  else
    updateCommentField(i, nil, false)
    if setHitRect then setHitRect(nil) end
  end
end

-- Global: torn down from Main.lua when the mockup overlay is dismissed. Only
-- ever touches slot 2 (the mockup's local/composing field) — slot 1 is
-- unused (the opponent balloon is never live-typed, even in the mockup) and
-- slot 3 (production) has its own lifecycle, torn down by
-- teardownEndScreenCommentField() above.
function teardownMockupTextField()
  local F = commentFields[2]
  if F and F.tv then
    F.tv:resignFirstResponder_()
    F.tv:removeFromSuperview_()
    F.tv = nil
  end
  if F then F.focused = false end
end

-- Production end-screen composer: lives in the local player's balloon
-- (commentFields slot 3), using the exact same field-management functions as
-- the dev mockup above. Split into two calls because they run at different
-- points in the frame: the line-cap enforcement must run BEFORE
-- buildEndScreenModel() (so the just-typed text feeds this frame's balloon
-- sizing, not next frame's), while positioning must run AFTER
-- drawEndScreenSpeechBalloons() (so it can read the balloon rect that
-- function just computed).
function enforceEndScreenCommentDraft(layout)
  if not (useTurnBased and not endScreenCommentFieldTornDown) then return end
  endScreenCommentDraft = enforceCommentFieldLineCap(3, layout.cardHeaderH * 0.44, layout.panelW - 42)
end

function positionEndScreenCommentField(model, layout)
  if not (useTurnBased and not endScreenCommentFieldTornDown) then
    updateCommentField(3, nil, false)
    return
  end
  local ui = model.commentUI
  local balloonFontSize = layout.cardHeaderH * 0.44
  local shown = ui and ui.canCompose and (ui.showBalloons ~= false)
  local F = commentFields[3]
  local active = shown and ((F and F.focused) or (endScreenCommentDraft ~= ""))
  positionCommentField(3, endScreenLocalBalloonRect, shown, active, ui and ui.placeholder, balloonFontSize, true, nil)
end

-- The 7 real situations the end-screen comment balloons can be in (see
-- STRUCTURE.md "Turn-Based Comment Speech Balloons"). Each entry is a
-- complete, valid snapshot rather than an independent combination of
-- toggles, so the debug picker can never land on a state the real game
-- doesn't produce (e.g. two grey placeholder balloons at once). Only the
-- LOCAL balloon is ever live-typed in production — the opponent balloon is
-- always either absent or an already-submitted comment in theme colors —
-- so localComposing is the only flag that turns on the native text field.
BALLOON_MOCKUP_STATES = BALLOON_MOCKUP_STATES or {
  { label = "1 · initiator composing",
    opponentComment = nil, localComposing = true, localTailUsesOpponentSlot = true },
  { label = "2 · composing, opponent spoke first",
    opponentComment = "nice board, that Q tile was brutal", localComposing = true,
    centerBothBalloons = true, suppressLocalTail = true, localGapExtra = 16 / 6,
    placeholder = "tap to reply",
    -- Once real text is typed (not just focus), the composer "becomes" a real
    -- reply: tail back, both balloons shift to scenario 6's staggered positions.
    -- Clearing the text back to empty reverts to this entry's own base values above.
    activeOverrides = {
      suppressLocalTail  = false,
      centerBothBalloons = false,
      oppBodyXNudge      = -8,
      localBodyXNudge    = 8,
      localTailXNudge    = -9,
    } },
  { label = "3 · composing, opponent silent",
    -- Same tail X as scenario 5 (avatarLayout.localX + 18 - 9).
    opponentComment = nil, localComposing = true, localTailXNudge = -9 },
  { label = "4 · only opponent ever commented",
    opponentComment = "gg, that board was rough", localComposing = false, localComment = nil },
  { label = "5 · only you ever commented",
    opponentComment = nil, localComposing = false, localComment = "rematch? I want a redo on that Z",
    -- Same tail X as scenario 6's lower balloon (avatarLayout.localX + 18 - 9).
    localTailXNudge = -9 },
  { label = "6 · both commented",
    opponentComment = "nice board, that Q tile was brutal", localComposing = false,
    localComment = "rematch? I want a redo on that Z", localGapExtra = 16 / 6,
    oppBodyXNudge = -8, localBodyXNudge = 8, localTailXNudge = -9 },
  { label = "7 · no balloons",
    opponentComment = nil, localComposing = false, localComment = nil },
}
mockupScenarioIndex = mockupScenarioIndex or 1

-- Dev-only static mockup of the turn-based comment balloon overlay.
-- Reuses the real drawEndScreenSpeechBalloons renderer + the real end-screen
-- layout so visual QA doesn't require playing a full match. Gated by
-- BALLOON_MOCKUP_DEV / balloonMockupOverlay (see Main.lua).
function drawBalloonMockupOverlay()
  if not balloonMockupOverlay then return end

  -- QA only: force the teal (Summer) palette so the mockup matches the teal
  -- reference for hue comparison. Gated by BALLOON_MOCKUP_DEV, so it never
  -- runs in production (where the 🐛 button opens the mockup in the live season).
  if BALLOON_MOCKUP_DEV and not _mockupSeasonForced then
    _mockupSeasonForced = true
    seasonIndex = 2
    if applySeasonPalette then applySeasonPalette() end
  end

  pushStyle()

  -- Dim scrim
  noStroke()
  fill(0, 0, 0, 140)
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)

  -- Ensure layout
  ensureEndScreenLayout()
  local layout = endScreenLayout

  -- Draw card backdrop — SAME function the real end screen uses (sprite-or-fallback),
  -- so the panel is pixel-identical, not a parallel drawRoundedRect approximation.
  drawEndScreenPanelBackground(layout)

  if mockupScenarioIndex < 1 or mockupScenarioIndex > #BALLOON_MOCKUP_STATES then
    mockupScenarioIndex = 1
  end
  local scn = BALLOON_MOCKUP_STATES[mockupScenarioIndex]

  -- Draw the board preview + avatars via drawEndTopRowContent — the SAME function
  -- drawEndScreenWith() calls — so board size/position and avatar layout are
  -- guaranteed identical to production rather than a hand-rolled reimplementation.
  -- Avatars are gated on useTurnBased inside that function; force it on for this one
  -- call since comment balloons are a turn-based-only feature anyway, so this is the
  -- state the mockup should always represent regardless of what the menu's last game was.
  -- Both avatars always draw, in every scenario (see localTailUsesOpponentSlot below
  -- for how scenario 1's tail is distinguished without hiding either avatar).
  local savedUseTurnBased = useTurnBased
  useTurnBased = true
  drawEndTopRowContent(
    layout.boardCX, layout.boardCY, layout.boardSide,
    layout.rightCX, layout.rightW,
    layout.msgCY, layout.msgH,
    layout.scoreCY, layout.scoreH,
    { opponentAvatar = genericOpponentAvatar() }
  )
  useTurnBased = savedUseTurnBased

  local PLACEHOLDER = scn.placeholder or "tap here to comment"
  local balloonFontSize = layout.cardHeaderH * 0.44
  local wrapWidth = layout.panelW - 42            -- == bubbleW - 8 in the renderer

  -- Line cap enforcement — shared with the production composer, see
  -- enforceCommentFieldLineCap() above. Only runs (and only shows a native
  -- field) while this scenario has you composing; otherwise the local
  -- balloon is plain already-submitted text, same as production.
  local localDraft, localActive
  if scn.localComposing then
    localDraft  = enforceCommentFieldLineCap(2, balloonFontSize, wrapWidth)
    localActive = commentFields[2].focused or (localDraft ~= "")
  else
    updateCommentField(2, nil, false)
  end

  -- scn.activeOverrides (mockup scenario 2 only): once real text has been
  -- entered (not just focus — an empty-but-focused field doesn't count), the
  -- lower balloon gets its tail back and both balloons shift to scenario 6's
  -- positions, so you can see the composer "become" a real reply in place.
  -- Clearing the text back to empty reverts to the scenario's own base values.
  local hasComment = scn.localComposing and (localDraft ~= "")
  local eff = {
    suppressLocalTail  = scn.suppressLocalTail,
    centerBothBalloons = scn.centerBothBalloons,
    oppBodyXNudge      = scn.oppBodyXNudge,
    localBodyXNudge    = scn.localBodyXNudge,
    localTailXNudge     = scn.localTailXNudge,
  }
  if hasComment and scn.activeOverrides then
    for k, v in pairs(scn.activeOverrides) do eff[k] = v end
  end

  -- Draw the balloon(s) via the EXISTING renderer. While composing, the local
  -- balloon is shape-only (suppressLocalText) and sized to the typed text so
  -- it grows downward as you type; otherwise it's plain themed text, exactly
  -- like an already-submitted comment renders in production.
  local model = {
    commentUI = {
      hasAnyComment   = true,
      showBalloons    = true,
      opponentComment = scn.opponentComment,
      localComment    = scn.localComposing
        and ((localDraft ~= "" and localDraft) or PLACEHOLDER)
        or scn.localComment,
      suppressLocalText = scn.localComposing or false,
      localTailUsesOpponentSlot = scn.localTailUsesOpponentSlot or false,
      centerBothBalloons = eff.centerBothBalloons or false,
      suppressLocalTail  = eff.suppressLocalTail or false,
      localGapExtra      = scn.localGapExtra or 0,
      oppBodyXNudge      = eff.oppBodyXNudge or 0,
      localBodyXNudge    = eff.localBodyXNudge or 0,
      localTailXNudge    = eff.localTailXNudge or 0,
    }
  }
  if scn.localComposing and not localActive then
    local placeholderScheme = currentBalloonColorScheme()
    model.commentUI.localFillOverride   = placeholderScheme.placeholderFill
    model.commentUI.localStrokeOverride = placeholderScheme.placeholderStroke
  end
  drawEndScreenSpeechBalloons(model, layout)

  -- Positioning + placeholder — shared with the production composer, see
  -- positionCommentField() above.
  if scn.localComposing then
    positionCommentField(2, endScreenLocalBalloonRect, true, localActive, PLACEHOLDER, balloonFontSize, true, nil)
  end

  -- Scenario chips (one tap = one complete, valid state) + close, replacing
  -- the old free-form show/hide + text-entry toggles that could express
  -- combinations the real game never produces.
  local rowW    = layout.panelW * 0.66
  local chipGap = 5
  local chipW   = (rowW - chipGap * 6) / 7
  local chipH   = 40
  local rowCX   = layout.panelX
  local rowLeft = rowCX - rowW * 0.5
  local closeBtnH = 44
  local closeCY = (layout.panelY - layout.panelH * 0.5) + 18 + closeBtnH * 0.5
  local chipCY  = closeCY + closeBtnH * 0.5 + 12 + chipH * 0.5

  mockupChipRects = {}
  for i = 1, 7 do
    local cx = rowLeft + chipW * 0.5 + (i - 1) * (chipW + chipGap)
    local isActive = (i == mockupScenarioIndex)
    local chipFill = isActive and (Color.tileText or color(20, 60, 50, 255)) or Color.uiAccent
    drawRoundedRect(cx, chipCY, chipW, chipH, 10, chipFill, chipFill)
    pushStyle()
    fill(255)
    textMode(CENTER); textAlign(CENTER)
    font("HelveticaNeue-Bold")
    fontSize(16)
    text(tostring(i), cx, chipCY + 1)
    popStyle()
    mockupChipRects[i] = { cx = cx, cy = chipCY, w = chipW, h = chipH }
  end

  drawRoundedRect(rowCX, closeCY, rowW, closeBtnH, 20, Color.uiAccent, Color.uiAccent)
  pushStyle()
  fill(255)
  textMode(CENTER); textAlign(CENTER)
  font("HelveticaNeue-Bold")
  fontSize(16)
  text("close debug screen", rowCX, closeCY + 1)
  popStyle()
  mockupCloseBtnRect = { cx = rowCX, cy = closeCY, w = rowW, h = closeBtnH }

  -- Scenario caption, just above the chip row
  pushStyle()
  fill(Color.tileText or color(255, 255, 255, 255))
  textMode(CENTER); textAlign(CENTER)
  font("HelveticaNeue-Italic")
  fontSize(14)
  text(scn.label, rowCX, chipCY + chipH * 0.5 + 18)
  popStyle()

  -- Screen title
  fill(255)
  textMode(CENTER)
  font("HelveticaNeue")
  fontSize(13)
  text("balloon mockup (dev)", WIDTH * 0.5, HEIGHT - 40)

  popStyle()
end

-- Dev-only scrollable picker over the 10 BALLOON_COLOR_SCHEMES candidates.
-- Each row renders TWO live balloons via the real drawSpeechBalloon primitive:
-- an "active" sample (left) and a "placeholder/inactive" sample (right), so
-- both states the user asked to mute are visible side by side. Tapping a row
-- sets balloonColorSchemeIndex immediately (drawEndScreenSpeechBalloons picks
-- it up on the very next frame, in the real end screen too). Manual
-- drag-to-scroll + tap-slop, same pattern as RecordsUI.lua's opponent/match
-- lists (not the ScrollList class — that class swallows short taps as
-- zero-distance drags, which would make row selection impossible here).
function drawBalloonColorPickerOverlay()
  if not balloonColorPickerOverlay then return end
  pushStyle()

  noStroke()
  fill(0, 0, 0, 140)
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)

  local panelW = math.min(WIDTH * 0.92, 640)
  local panelH = HEIGHT * 0.86
  local panelX, panelY = WIDTH * 0.5, HEIGHT * 0.5
  drawRoundedRect(panelX, panelY, panelW, panelH, 24,
    Color.panelBG or color(245, 242, 232, 255), Color.tileStroke or color(180, 160, 140, 255))

  local panelTop    = panelY + panelH * 0.5
  local panelBottom = panelY - panelH * 0.5

  pushStyle()
  fill(Color.tileText or color(40, 80, 60, 255))
  textMode(CENTER); textAlign(CENTER)
  font("HelveticaNeue-Bold")
  fontSize(17)
  text("balloon colors (dev)", panelX, panelTop - 28)
  font("HelveticaNeue-Italic")
  fontSize(12)
  text("tap a row to select  ·  left = active, right = placeholder", panelX, panelTop - 48)
  popStyle()

  -- Bottom buttons
  local closeBtnH   = 44
  local closeCY     = panelBottom + 18 + closeBtnH * 0.5
  local previewBtnH = 40
  local previewCY   = closeCY + closeBtnH * 0.5 + 10 + previewBtnH * 0.5
  local btnW        = panelW * 0.7

  drawRoundedRect(panelX, previewCY, btnW, previewBtnH, 18,
    Color.uiAccent2 or Color.uiAccent, Color.uiAccent2 or Color.uiAccent)
  pushStyle()
  fill(255); textMode(CENTER); textAlign(CENTER); font("HelveticaNeue-Bold"); fontSize(15)
  text("preview on full end screen", panelX, previewCY + 1)
  popStyle()

  drawRoundedRect(panelX, closeCY, btnW, closeBtnH, 20, Color.uiAccent, Color.uiAccent)
  pushStyle()
  fill(255); textMode(CENTER); textAlign(CENTER); font("HelveticaNeue-Bold"); fontSize(16)
  text("close debug screen", panelX, closeCY + 1)
  popStyle()

  -- Scrollable option list
  local listLeft   = panelX - panelW * 0.5 + 10
  local listWidth  = panelW - 20
  local listBottom = previewCY + previewBtnH * 0.5 + 14
  local listTop    = panelTop - 64
  local listHeight = math.max(10, listTop - listBottom)

  local rowH      = 118
  local totalRows = #BALLOON_COLOR_SCHEMES
  local contentH  = totalRows * rowH
  local maxScroll = math.max(0, contentH - listHeight)
  if colorPickerScrollY < 0 then colorPickerScrollY = 0 end
  if colorPickerScrollY > maxScroll then colorPickerScrollY = maxScroll end

  colorPickerGeom = {
    closeBtn   = { cx = panelX, cy = closeCY, w = btnW, h = closeBtnH },
    previewBtn = { cx = panelX, cy = previewCY, w = btnW, h = previewBtnH },
    listLeft = listLeft, listBottom = listBottom, listWidth = listWidth, listHeight = listHeight,
    maxScroll = maxScroll,
  }

  colorPickerRowRects = {}
  clip(listLeft, listBottom, listWidth, listHeight)
  local firstY = (listBottom + listHeight) - rowH
  for row = 1, totalRows do
    local y = firstY - (row - 1) * rowH + colorPickerScrollY
    if y > listBottom - rowH and y < listBottom + listHeight + rowH then
      local scheme = BALLOON_COLOR_SCHEMES[row].build(Color)
      local cardLeft   = listLeft + 4
      local cardW      = listWidth - 8
      local cardBottom = y + 5
      local cardH      = rowH - 10
      local cardCX     = cardLeft + cardW * 0.5
      local cardCY     = cardBottom + cardH * 0.5

      local isSel = (row == balloonColorSchemeIndex)
      local borderCol = isSel and (Color.uiAccent2 or Color.uiAccent) or (Color.tileStroke or color(150, 150, 150, 255))
      local innerT = isSel and 3 or 1.5
      drawRoundedRect(cardCX, cardCY, cardW, cardH, 14, borderCol, borderCol)
      drawRoundedRect(cardCX, cardCY, cardW - 2 * innerT, cardH - 2 * innerT, math.max(0, 14 - innerT),
        Color.panelBG or color(245, 242, 232, 255), Color.panelBG or color(245, 242, 232, 255))

      colorPickerRowRects[row] = { x = cardLeft, y = cardBottom, w = cardW, h = cardH }

      pushStyle()
      fill(Color.tileText or color(40, 80, 60, 255))
      -- CORNER mode here (not the file's usual CENTER) because this label is
      -- left-anchored: textAlign(LEFT) has no effect while textMode(CENTER)
      -- is active (the given x,y stays the CENTER of the text block
      -- regardless), which was clipping the front off longer names. CORNER
      -- anchors bottom-left and flows upward, per project convention.
      textMode(CORNER); textAlign(LEFT)
      font(isSel and "HelveticaNeue-Bold" or "HelveticaNeue")
      fontSize(15)
      text(row .. ". " .. BALLOON_COLOR_SCHEMES[row].name .. (isSel and "  (selected)" or ""),
        cardLeft + 14, cardCY + cardH * 0.5 - 26)
      popStyle()

      local balloonY = cardBottom + 8
      local balloonH = cardH - 34
      local gap      = 10
      local halfW    = (cardW - 28 - gap) * 0.5
      local activeRect      = { x = cardLeft + 14, y = balloonY, w = halfW, h = balloonH }
      local placeholderRect = { x = cardLeft + 14 + halfW + gap, y = balloonY, w = halfW, h = balloonH }

      drawSpeechBalloon(activeRect, "Great game, rematch?", 0, 0, "up",
        scheme.fill, scheme.stroke, {
          noTail = true, cornerRadius = 10, outlineWidth = 3,
          fontSizeValue = 12, textInsetX = 6, textInsetY = 4,
          textColor = scheme.text, maxLines = 2,
        })
      drawSpeechBalloon(placeholderRect, "tap here to comment", 0, 0, "up",
        scheme.placeholderFill, scheme.placeholderStroke, {
          noTail = true, cornerRadius = 10, outlineWidth = 3,
          fontSizeValue = 11, textInsetX = 6, textInsetY = 4,
          textColor = Color.tileText, maxLines = 2,
        })
    end
  end
  clip()

  popStyle()
end

-- Confirms + starts a rematch against this match's opponent, exactly like the
-- menu's "re" button. The actual matchmaking is deferred until the end
-- screen has fully disposed of itself (see pendingRematchAfterEndScreenExit
-- in ConfettiEffectsEtc.lua) so it can't race the season-transition fade.
function offerEndScreenRematch()
  local q = currentQMatch
  if not (q and q.players) then return end
  if persistLastMatchReplaySettingsFromQMatch then
    persistLastMatchReplaySettingsFromQMatch(q)
  end
  confirmRematchAgainstLastOpponent(function()
    pendingRematchAfterEndScreenExit = true
    disposeEndScreenAndReturnToMenu()
  end)
end

local function clearMissedWordsJob()
  endScreenMissedWordsJob = nil
  endScreenMissedWordsJobMatchId = nil
end

local function beginMissedWordsJob(q)
  if not q or not q.boardTiles or not createIncrementalBoardWordSolver then return end
  local n = q.boardSize or inferBoardSizeFromTiles(q.boardTiles) or 4
  local solver = createIncrementalBoardWordSolver(q.boardTiles, n, q.minWordLen or MIN_WORD_LEN)
  if not solver then return end

  ensureWordPathsForPlayers(q)

  endScreenMissedWordsJobMatchId = q.id
  endScreenMissedWordsJob = coroutine.create(function()
    while not solver.done do
      solver:step(250)
      coroutine.yield(false)
    end

    local allWords, wordPaths = solver:getResults()
    local foundSet = {}
    if q.players then
      for _, p in pairs(q.players) do
        for _, entry in ipairs((p and p.words) or {}) do
          local w = type(entry) == "table" and entry.word or tostring(entry or "")
          if w ~= "" then
            foundSet[string.upper(w)] = true
          end
        end
      end
    end

    local missed = {}
    for i = 1, #allWords do
      local entry = allWords[i]
      if not foundSet[entry.word] then
        missed[#missed + 1] = entry
      end
    end

    q.wordPaths = wordPaths
    q.missedWords = missed
    coroutine.yield(true)
  end)
end

local function pumpMissedWordsJobIfNeeded(activeCard)
  local q = currentQMatch
  if not q or not activeCard or not activeCard.isMissedPlaceholder then return end
  if q.missedWords then
    clearMissedWordsJob()
    return
  end
  if endScreenMissedWordsJobMatchId ~= q.id or not endScreenMissedWordsJob then
    clearMissedWordsJob()
    beginMissedWordsJob(q)
  end
  if not endScreenMissedWordsJob then return end
  if coroutine.status(endScreenMissedWordsJob) == "dead" then
    clearMissedWordsJob()
    return
  end
  local ok = coroutine.resume(endScreenMissedWordsJob)
  if not ok then
    clearMissedWordsJob()
  end
end

function buildEndScreenModel()
  local q = currentQMatch
  local localId = localPID()
  local otherId, pLocal, pOther
 
  if q and q.players then
    for pid,_ in pairs(q.players) do
      if pid ~= localId then otherId = pid break end
    end
  end
  
  pLocal = q and q.players and q.players[localId]
  pOther = q and q.players and otherId and q.players[otherId]
  
  if otherId then
    local qp = qPlayersById and qPlayersById[otherId]
    avatar2 = qp and qp.avatar
  end
  
  local endState = currentEndScreenState()
  local is2P     = (endState ~= END_STATE_SINGLE)
  local complete = (endState == END_STATE_2P_COMPLETE)
  local assignedOpponent = (otherId ~= nil and otherId ~= "")
  local rawOppName = (q and (q.otherName or q.opponentName)) or opponentAlias or ""
  local oppDisplayName = assignedOpponent and rawOppName or ""
  local opponentAvatarOverride = nil
  if not assignedOpponent and genericOpponentAvatar then
    opponentAvatarOverride = genericOpponentAvatar()
  end

  local waitingWords
  if not complete then
    if assignedOpponent then
      waitingWords = {
        "waiting for opponent",
        "to play",
      }
    else
      waitingWords = {
        "waiting for",
        "opponent",
      }
    end
  end
  
  local isSinglePlayer = (not otherId)
  local matchComplete = complete or isSinglePlayer

  if q and matchComplete and ensureWordPathsForPlayers then
    ensureWordPathsForPlayers(q)
  end

  local scoreA = (pLocal and pLocal.score) or (score or 0)
  local scoreB = (pOther and pOther.score) or 0
  
  local rec = opponentRecords and opponentRecords[otherId] or nil
  local wins   = rec and rec.wins or 0
  local losses = rec and rec.losses or 0
  local commentInfo = currentFinalCommentPhase and currentFinalCommentPhase() or nil
  local localComment = (pLocal and pLocal.comment) or ""
  local opponentComment = (pOther and pOther.comment) or ""
  local canComposeComment = commentInfo and commentInfo.localCanCompose or false
  
  local line1 = nil
  local singleList = nil
  local column1Words = nil
  local column2Words = nil
  local missedWords = q and q.missedWords or nil
  local scoreAResolved = scoreA
  local scoreBResolved = scoreB

  if not is2P then
    singleList = buildSortedEndWordEntries and buildSortedEndWordEntries(currentFoundWords() or {}) or (currentFoundWords() or {})
  elseif complete then
    local reconciled = reconcileCompetitiveWordResults and reconcileCompetitiveWordResults(
      (pLocal and pLocal.words) or {},
      (pOther and pOther.words) or {}
    ) or nil
    if reconciled then
      column1Words = reconciled.entriesA
      column2Words = reconciled.entriesB
      scoreAResolved = reconciled.scoreA
      scoreBResolved = reconciled.scoreB
    else
      column1Words = (pLocal and pLocal.words) or {}
      column2Words = (pOther and pOther.words) or {}
    end
  else
    column1Words = buildSortedEndWordEntries and buildSortedEndWordEntries((pLocal and pLocal.words) or {}) or ((pLocal and pLocal.words) or {})
    column2Words = waitingWords
  end

  if missedWords and buildSortedEndWordEntries then
    missedWords = buildSortedEndWordEntries(missedWords)
  end

  if complete then
    if scoreAResolved > scoreBResolved then
      line1 = string.format("You won %d to %d!", scoreAResolved, scoreBResolved)
    elseif scoreAResolved < scoreBResolved then
      line1 = string.format("You lost %d to %d!", scoreAResolved, scoreBResolved)
    else
      line1 = string.format("Tie game, %d all!", scoreAResolved)
    end
  end

  -- Ensure W/L summary reflects the just-finished match even if persistence
  -- hasn't been updated yet.
  if complete and assignedOpponent then
    local alreadyCounted = false
    if q and q.recordOutcomeApplied then
      alreadyCounted = true
    else
      local recUpdatedAt = math.floor(tonumber(rec and rec.updatedAt) or 0)
      local matchUpdatedAt = math.floor(tonumber(q and q.lastUpdated) or 0)
      if matchUpdatedAt > 0 and recUpdatedAt >= matchUpdatedAt then
        alreadyCounted = true
      end
    end

    if not alreadyCounted then
      if scoreAResolved > scoreBResolved then
        wins = wins + 1
      elseif scoreAResolved < scoreBResolved then
        losses = losses + 1
      end
    end
  end
  
  local line2 = (complete and assignedOpponent)
  and string.format("Win/Loss vs This Player: %d / %d", wins, losses)
  or nil

  -- Capture this match into per-opponent history (opponentRecords.lua) whenever a
  -- full record is on the device and the local player has played it — complete OR
  -- in-progress (initiator examining before the opponent moves). recordMatchSnapshot
  -- upserts by id and only touches disk on a real change, so calling it every frame
  -- here is cheap. Stores RAW per-player found-words (+ resolved scores separately)
  -- so a re-view reconstructs the SAME reconciled columns the original showed, and
  -- the match-list row can show both "words found" (raw count) and the counted score.
  if recordMatchSnapshot and assignedOpponent and pLocal and pLocal.didPlay then
    local snap = {
      id         = q and q.id,
      oppId      = otherId,
      oppAlias   = (oppDisplayName ~= "" and oppDisplayName) or rawOppName or "",
      boardSize  = (q and q.boardSize) or boardSize,
      minWordLen = (q and q.minWordLen) or MIN_WORD_LEN,
      boardTiles = q and q.boardTiles,
      endedAt    = math.floor(tonumber(q and q.lastUpdated) or os.time()),
      complete   = complete and true or false,
      localScore = complete and scoreAResolved or ((pLocal and pLocal.score) or 0),
      oppScore   = complete and scoreBResolved or ((pOther and pOther.score) or 0),
      localWords = (pLocal and pLocal.words) or {},
      oppWords   = (pOther and pOther.words) or {},
      localComment = localComment or "",
      oppComment   = opponentComment or "",
    }
    if complete then
      if scoreAResolved > scoreBResolved then snap.outcome = "win"
      elseif scoreAResolved < scoreBResolved then snap.outcome = "loss"
      else snap.outcome = "tie" end
    end
    if snap.id and snap.oppId and snap.boardTiles then
      recordMatchSnapshot(snap)
    end
  end

  -- While composing, the balloon shows the live draft (or a placeholder so it
  -- renders/grows even before any text exists) instead of the (not yet
  -- submitted) persisted comment. suppressLocalText hides the Codea-drawn
  -- text since the native UITextView renders it instead; the grey
  -- fill/stroke overrides mark the balloon as "not active yet" until the
  -- field is focused or has text, matching the balloon mockup's states.
  -- "Add a reply..." only makes sense when there's an actual opponent comment to reply
  -- to. commentInfo.opponentPlayed alone isn't enough — the opponent may have played
  -- their turn and left no comment, in which case this composer is the first word in
  -- the thread just as much as the initiator's is, so it gets the same generic prompt.
  local hasOpponentComment = commentInfo and commentInfo.opponentPlayed and opponentComment ~= ""
  local placeholderText = hasOpponentComment
    and "Add a reply to their comment"
    or "tap here to comment"
  local composingActive = (commentFields and commentFields[3] and commentFields[3].focused) or (endScreenCommentDraft ~= "")
  local placeholderScheme  = currentBalloonColorScheme()
  local composingOffFill   = placeholderScheme.placeholderFill
  local composingOffStroke = placeholderScheme.placeholderStroke

  local rematchInfo = nil
  if is2P and complete and assignedOpponent then
    rematchInfo = {
      canOffer = true,
      label = "Play " .. (oppDisplayName ~= "" and oppDisplayName or "them") .. " again?",
    }
  end

  return {
    missedWords = missedWords,
    missedWordsPending = matchComplete and (q ~= nil) and not (q and q.missedWords),

    dimColor = Color.panelDim,
    
    headers = is2P and {
      column1 = "you",
      column2 = oppDisplayName,
      color   = Color.tileText or color(40,80,60,255)
    } or nil,
    opponentAvatar = opponentAvatarOverride,
    
    -- SINGLE PLAYER LIST
    singleList = (not is2P) and singleList or nil,
    
    -- TWO PLAYER COLUMNS (POSITIONAL ONLY)
    column1 = is2P and {
      words = column1Words or {}
    } or nil,
    
    column2 = is2P and (
      complete
      and { words = column2Words or {} }
      or  { words = {}, isWaitingCard = true, waitingText = waitingWords and table.concat(waitingWords, "\n") or "waiting for opponent\nto play" }
    ) or nil,
    
    totals = {
      line1 = line1,
      line2 = line2,
      color = Color.tileText or color(40,80,60,255)
    },
    
    button = {
      -- label = is2P and "Play Another Match" or playAgainLabel,
      label = is2P and nil or playAgainLabel,
      action = function()
        if is2P then
          -- hook later
        else
          rotatePlayAgainLabel()
          currentQMatch = nil
          startRoundFromCurrentSettings()
        end
      end
    },
    
    commentUI = {
      canCompose = canComposeComment,
      placeholder = placeholderText,
      localComment = canComposeComment
        and ((endScreenCommentDraft ~= "" and endScreenCommentDraft) or placeholderText)
        or localComment,
      opponentComment = opponentComment,
      showBalloons = endScreenSpeechBalloonsVisible,
      hasAnyComment = (localComment ~= "" or opponentComment ~= "" or canComposeComment),
      suppressLocalText   = canComposeComment,
      localFillOverride   = (canComposeComment and not composingActive) and composingOffFill   or nil,
      localStrokeOverride = (canComposeComment and not composingActive) and composingOffStroke or nil,
    },

    rematch = rematchInfo,
  }
end

function drawEndScreenFP()
  scrollListCol1 = scrollListCol1 or ScrollList.new()
  scrollListCol2 = scrollListCol2 or ScrollList.new()
  -- Animate card snap toward 0 (exponential decay)
  if endCardAnimPx and math.abs(endCardAnimPx) > 0.5 then
    endCardAnimPx = endCardAnimPx * 0.72
  else
    endCardAnimPx = 0
  end
  -- Reset card state when the match changes
  local qid = currentQMatch and currentQMatch.id
  if endScreenLastMatchId ~= qid then
    endScreenLastMatchId     = qid
    endCardIndex             = 1
    endCardAnimPx            = 0
    endCardDragPx            = 0
    endScreenHighlightedPath = nil
    endScreenHighlightedWord = nil
    endScreenCurrentCardWords = {}
    if endCardScrollLists then
      for i = 1, #endCardScrollLists do
        endCardScrollLists[i].scroll = 0
        endCardScrollLists[i].vel    = 0
      end
    end
    clearMissedWordsJob()
  end
  ensureEndScreenLayout()
  -- Must run BEFORE buildEndScreenModel() so this frame's just-typed text
  -- feeds this frame's balloon sizing (not next frame's).
  enforceEndScreenCommentDraft(endScreenLayout)
  local model = buildEndScreenModel()
  syncEndScreenCommentState(model)
  drawEndScreenWith(model, endScreenLayout)
end

-- Builds the ordered list of swipeable cards from the end-screen model.
-- Always: card 1 = yours. 2P adds theirs as card 2. Missed appended when available.
function buildEndScreenCards(model)
  local cards = {}
  if model.singleList ~= nil then
    cards[1] = { label = "Your Words", words = model.singleList }
  else
    cards[1] = { label = "Your Words", words = (model.column1 and model.column1.words) or {} }
    if model.column2 then
      local lbl = (model.headers and model.headers.column2 ~= "" and model.headers.column2) or "Theirs"
      cards[2] = { label = lbl, words = model.column2.words, isWaiting = model.column2.isWaitingCard, waitingText = model.column2.waitingText }
    end
  end
  if model.missedWords then
    cards[#cards + 1] = { label = "Missed", words = model.missedWords }
  elseif model.missedWordsPending then
    cards[#cards + 1] = { label = "Missed", words = {}, isMissedPlaceholder = true }
  end
  return cards
end

local function drawMissedCardActivityIndicator(rect)
  if not rect then return end
  local cx = rect.x + rect.w * 0.5
  local cy = rect.y + rect.h * 0.56
  local ringR = math.min(rect.w, rect.h) * 0.12
  local dotR = math.max(4, ringR * 0.16)
  local phase = ElapsedTime * 2.8
  local accent = Color.uiAccent or color(40, 80, 60, 255)
  local textCol = Color.tileText or accent

  pushStyle()
  ellipseMode(CENTER)
  noStroke()
  for i = 1, 8 do
    local a = phase + (i - 1) * (math.pi * 0.25)
    local alpha = math.floor(45 + 210 * (i / 8))
    fill(accent.r, accent.g, accent.b, alpha)
    ellipse(cx + math.cos(a) * ringR, cy + math.sin(a) * ringR, dotR * 2, dotR * 2)
  end

  fill(textCol)
  textAlign(CENTER)
  textMode(CENTER)
  font("Helvetica")
  fontSize(math.max(20, rect.h * 0.065))
  text("Finding missed words", cx, cy - ringR - rect.h * 0.10)
  popStyle()
end

-- Shared panel backdrop: real sprite (baked per-season, see rebuildOverlayPanelsForSeason)
-- when available, else a flat rounded rect. Used by both the production end screen and
-- the balloon mockup so the two never visually drift apart.
function drawEndScreenPanelBackground(layout)
  local C = Color
  local panelSprite = overlayPanelEnd
  if panelSprite then
    pushStyle()
    spriteMode(CENTER)
    tint(255,255,255,(C.panelBG and C.panelBG.a) or 255)
    sprite(panelSprite, layout.panelX, layout.panelY, layout.panelW, layout.panelH)
    popStyle()
  else
    local bg = C.panelBG or color(245,242,232,255)
    drawRoundedRect(
    layout.panelX, layout.panelY,
    layout.panelW, layout.panelH,
    layout.cornerRadius,
    bg, bg
    )
  end
end

function drawEndScreenWith(model, layout)
  local C = Color
  
  -- dim overlay
  if model.dimColor then
    pushStyle()
    fill(model.dimColor)
    noStroke()
    rectMode(CORNER)
    rect(0,0,WIDTH,HEIGHT)
    popStyle()
  end
  
  -- panel
  drawEndScreenPanelBackground(layout)
  
  -- top row
  drawEndTopRowContent(
  layout.boardCX, layout.boardCY, layout.boardSide,
  layout.rightCX, layout.rightW,
  layout.msgCY, layout.msgH,
  layout.scoreCY, layout.scoreH,
  model
  )
  ------------------------------------------------------------
  -- cards (swipeable word lists: yours / theirs / missed)
  ------------------------------------------------------------

  local cards    = buildEndScreenCards(model)
  local numCards = #cards
  endCardCount   = numCards
  if endCardIndex > numCards then endCardIndex = numCards end
  if endCardIndex < 1        then endCardIndex = 1        end
  endScreenCurrentCardWords = (cards[endCardIndex] and cards[endCardIndex].words) or {}
  pumpMissedWordsJobIfNeeded(cards[endCardIndex])

  -- Card header: centered label + word count for the currently visible card
  if layout.cardHeaderCY and numCards > 0 then
    local card = cards[endCardIndex]
    if card then
      pushStyle()
      textAlign(CENTER)
      textMode(CENTER)
      fontSize(layout.cardHeaderH * 0.44)
      fill(model.headers and model.headers.color or (Color.tileText or color(40,80,60,255)))
      local headerLabel = card.isWaiting and card.label or (card.label .. " (" .. #card.words .. ")")
      text(headerLabel, layout.panelX, layout.cardHeaderCY)
      popStyle()
    end
  end

  -- Cards (clipped to list area, offset by swipe/drag)
  if layout.cardListRect then
    local lr  = layout.cardListRect
    local cw  = layout.cardW or lr.w
    local off = (endCardAnimPx or 0) + (endCardDragPx or 0)

    -- Card backgrounds drawn BEFORE clip so rounded corners aren't scissored off
    -- drawRoundedRect internally forces strokeWidth = r*2, so we draw fill and
    -- the 1px border as two separate passes.
    local cardBG     = Color.panelBG    or color(245, 242, 232, 255)
    local cardBorder = Color.tileStroke or color(180, 160, 140, 255)
    for i = 1, numCards do
      local xOff = (i - endCardIndex) * cw + off
      if math.abs(xOff) < cw * 1.5 then
        local cx2 = lr.x + xOff + lr.w * 0.5
        local cy2 = lr.y + lr.h * 0.5
        local cw2 = lr.w - 6
        local ch2 = lr.h - 6
        -- filled rounded shape (stroke same as fill so drawRoundedRect's thick
        -- internal stroke is invisible)
        drawRoundedRect(cx2, cy2, cw2, ch2, 14, cardBG, cardBG)
        -- 1px border as a plain rect on top
        pushStyle()
        noFill()
        stroke(cardBorder)
        strokeWidth(1)
        rectMode(CENTER)
        rect(cx2, cy2, cw2, ch2)
        popStyle()
      end
    end

    local padV = layout.cardPadV or 0
    clip(lr.x, lr.y, lr.w, lr.h)
    for i = 1, numCards do
      local xOff = (i - endCardIndex) * cw + off
      if math.abs(xOff) < cw * 1.5 then
        local cr = { x = lr.x + xOff, y = lr.y + padV, w = lr.w, h = lr.h - 2 * padV }
        if cards[i].isMissedPlaceholder then
          drawMissedCardActivityIndicator(cr)
        elseif cards[i].isWaiting then
          pushStyle()
          fill(model.headers and model.headers.color or (Color.tileText or color(40,80,60,255)))
          textAlign(CENTER)
          textMode(CENTER)
          fontSize(math.max(16, cr.h * 0.09))
          text(cards[i].waitingText or "waiting for opponent", cr.x + cr.w * 0.5, cr.y + cr.h * 0.5)
          popStyle()
        else
          renderList(endCardScrollLists[i], cr, cards[i].words, model)
        end
      end
    end
    clip()
  end

  -- Page dots
  if layout.cardDotsY then
    drawCardPageDots(layout, numCards, endCardIndex)
  end
  
  ------------------------------------------------------------
  -- totals (pure text)
  ------------------------------------------------------------
  
  if model.totals then
    pushStyle()
    fill(model.totals.color)
    textAlign(CENTER)
    textMode(CENTER)
    
    local cy = layout.oppStatsCY
    
    if model.totals.line1 then
      fontSize(22)
      text(model.totals.line1, layout.panelX, cy + 10)
    end
    
    if model.totals.line2 then
      fontSize(16)
      text(model.totals.line2, layout.panelX, cy - 14)
    end
    
    popStyle()
  end
  
  ------------------------------------------------------------
  -- button (rematch — occupies the rect the old comment field used to sit
  -- in; the composer itself now lives inside the local speech balloon below)
  ------------------------------------------------------------

  if endScreenReturnToRecords then
    -- Viewing a historical match from the records list: a rematch offer doesn't belong
    -- here — replace it with a Back button that closes the same way the × does (the dispose
    -- intercept returns to the records match list). Shown for complete AND incomplete views.
    drawEndScreenButton(layout.playAgainRect, "Back", disposeEndScreenAndReturnToMenu)
  elseif model.rematch and model.rematch.canOffer then
    drawEndScreenButton(layout.playAgainRect, model.rematch.label, offerEndScreenRematch)
  else
    endScreen2PButtonRect = nil
    endScreenButtonAction = nil
  end

  drawEndScreenSpeechBalloons(model, layout)

  -- Native comment UITextView + placeholder, positioned over the local
  -- balloon's rect (set as a side effect inside drawEndScreenSpeechBalloons
  -- above). Same shared field code the dev mockup uses — see
  -- positionEndScreenCommentField() near drawBalloonMockupOverlay.
  positionEndScreenCommentField(model, layout)

  ------------------------------------------------------------
  -- close button
  ------------------------------------------------------------

  pushStyle()
  ellipseMode(CENTER)
  noStroke()
  fill(Color.uiAccent)
  ellipse(layout.closeX, layout.closeY, layout.closeSize, layout.closeSize)
  
  fill(255)
  textAlign(CENTER)
  textMode(CENTER)
  fontSize(layout.closeSize * 0.75)
  text("×", layout.closeX, layout.closeY + 2)
  popStyle()
end

-- Draws page-position dot indicators for the card carousel.
function drawCardPageDots(layout, numCards, activeIndex)
  if numCards <= 1 or not layout.cardDotsY then return end
  local dotR  = 5
  local gap   = 16
  local totalW = (numCards - 1) * gap
  local startX = layout.panelX - totalW * 0.5
  local y      = layout.cardDotsY
  local C      = Color
  pushStyle()
  ellipseMode(CENTER)
  noStroke()
  for i = 1, numCards do
    local x = startX + (i - 1) * gap
    if i == activeIndex then
      fill(C.uiAccent or color(40, 80, 60, 255))
    else
      fill(180, 180, 180, 200)
    end
    ellipse(x, y, dotR * 2, dotR * 2)
  end
  popStyle()
end

function makeRowRenderer(entries, model)
  return function(row, y, x)
    local e = entries[row]
    local textValue, pts, shared

    if type(e) == "table" then
      textValue = e.word or ""
      pts = e.points
      shared = e.shared
    else
      textValue = tostring(e or "")
    end

    local label = textValue
    if pts and pts > 0 then
      label = string.format("%s  (+%d)", textValue, pts)
    end
    local selected = (endScreenHighlightedWord and textValue ~= "" and textValue == endScreenHighlightedWord)
    local textColor = selected and (Color.uiAccent2 or Color.uiAccent) or (model.wordColor or Color.uiAccent)

    pushStyle()
    textAlign(LEFT)
    textMode(CORNER)
    fontSize(24)
    fill(textColor)
    text(label, x, y)
    if shared and label ~= "" then
      local tw, th = textSize(label)
      stroke(textColor)
      strokeWidth(2)
      line(x, y + th * 0.58, x + tw, y + th * 0.58)
    end
    popStyle()
  end
end

function renderList(listObject, rect, entries, model)
  local padT, padB, lineH = 6, 10, 28  
  if not rect or not entries then return end
  
  local r = {
    x = rect.x,
    y = rect.y + padB,
    w = rect.w,
    h = rect.h - padT - padB
  }
  
  listObject:draw(r, #entries, lineH, makeRowRenderer(entries, model), r.x + rect.w * 0.25)
end

function drawEndScreenButton(rect, label, action)
  endScreen2PButtonRect = rect
  
  drawRoundedRect(
  rect.x + rect.w*0.5,
  rect.y + rect.h*0.5,
  rect.w,
  rect.h,
  22,
  Color.uiAccent,
  Color.uiAccent
  )
  
  pushStyle()
  fill(255)
  textAlign(CENTER)
  textMode(CENTER)
  fontSize(rect.h * 0.32)
  text(label, rect.x + rect.w*0.5, rect.y + rect.h*0.5)
  popStyle()
  
  endScreenButtonAction = action
end

function keyboard(key)
  if not (state == STATE_END and endScreenCommentUIActive and shouldShowFinalCommentComposer and shouldShowFinalCommentComposer()) then
    return
  end
  
  local keyString = tostring(key or "")
  if key == BACKSPACE or key == "\b" or keyString == "BACKSPACE" then
    endScreenCommentDraft = string.sub(endScreenCommentDraft or "", 1, math.max(0, #(endScreenCommentDraft or "") - 1))
    return
  end
  
  if key == RETURN or key == "\n" or keyString == "RETURN" then
    -- Return only ever dismisses text entry — it must never submit the
    -- comment or close the end screen (that's the ×/rematch buttons' job).
    return
  end
  
  if type(key) ~= "string" or #key ~= 1 then return end
  if key:match("[%c]") then return end
  endScreenCommentDraft = normalizeCommentDraft((endScreenCommentDraft or "") .. key)
end
