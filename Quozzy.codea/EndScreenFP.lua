endScreenMissedWordsJob = endScreenMissedWordsJob or nil
endScreenMissedWordsJobMatchId = endScreenMissedWordsJobMatchId or nil
endScreenCommentDraft = endScreenCommentDraft or ""
endScreenCommentMatchId = endScreenCommentMatchId or nil
endScreenCommentFocused = endScreenCommentFocused or false
endScreenSpeechBalloonsVisible = endScreenSpeechBalloonsVisible ~= false
endScreenCommentUIActive = endScreenCommentUIActive or false
endScreenSpeechBalloonAlpha = endScreenSpeechBalloonAlpha or 1
endScreenLocalBalloonAlpha = endScreenLocalBalloonAlpha or 1
endScreenNativeCommentField = endScreenNativeCommentField or nil
endScreenNativeCommentDelegate = endScreenNativeCommentDelegate or nil
endScreenNativeCommentHandler = endScreenNativeCommentHandler or nil
endScreenCommentFieldActivated = endScreenCommentFieldActivated or false
endScreenCommentFieldTornDown = endScreenCommentFieldTornDown or false
endScreenKeyboardHeight = endScreenKeyboardHeight or 0
endScreenKBObserver = endScreenKBObserver or nil
endScreenCommentLastShift = endScreenCommentLastShift or -1

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

local function setEndScreenCommentKeyboardVisible(visible)
  if endScreenNativeCommentField then
    if visible then
      endScreenNativeCommentField:becomeFirstResponder_()
    else
      endScreenNativeCommentField:resignFirstResponder_()
    end
    return
  end
end

local function syncEndScreenCommentState(model)
  local qid = currentQMatch and currentQMatch.id or nil
  if endScreenCommentMatchId ~= qid then
    devLog("COMMENT_DBG syncEndScreenCommentState: new match, resetting state. old=", tostring(endScreenCommentMatchId), "new=", tostring(qid), "tornDown was=", tostring(endScreenCommentFieldTornDown))
    endScreenCommentMatchId = qid
    endScreenCommentDraft = ""
    endScreenSpeechBalloonsVisible = true
    endScreenCommentFocused = false
    endScreenCommentFieldActivated = false
    endScreenCommentFieldTornDown = false
    endScreenKeyboardHeight = 0
    endScreenCommentLastShift = -1
  end

  local shouldActivate = model and model.commentUI and model.commentUI.canCompose or false
  if shouldActivate and not endScreenCommentFieldActivated then
    devLog("COMMENT_DBG syncEndScreenCommentState: activating field. tornDown=", tostring(endScreenCommentFieldTornDown))
    endScreenCommentFieldActivated = true
    -- Do NOT auto-focus here; keyboard appears only when user taps the field
  end
  endScreenCommentUIActive = shouldActivate or endScreenCommentFieldActivated
end

function teardownEndScreenCommentField()
  local tf = endScreenNativeCommentField
  if tf then
    tf:resignFirstResponder_()
    tf:removeFromSuperview_()
    endScreenNativeCommentField = nil
    endScreenNativeCommentDelegate = nil
    endScreenNativeCommentHandler = nil
  end
  if endScreenKBObserver then
    local ok, nc = pcall(function() return objc.NSNotificationCenter.defaultCenter end)
    if ok and nc then nc:removeObserver_(endScreenKBObserver) end
    endScreenKBObserver = nil
  end
  endScreenCommentFieldActivated = false
  endScreenCommentFieldTornDown = true
  endScreenKeyboardHeight = 0
  endScreenCommentLastShift = -1
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
  endScreenCommentFocused = false
  teardownEndScreenCommentField()
  startSeasonTransition()
  return true
end

local function codeaToUIKitRect(x, y, w, h)
  return objc.rect(x, HEIGHT - y - h, w, h)
end

_dbgEnsureFieldBlockedPrinted = _dbgEnsureFieldBlockedPrinted or false
local function ensureEndScreenNativeCommentField()
  if endScreenCommentFieldTornDown then
    if not _dbgEnsureFieldBlockedPrinted then
      _dbgEnsureFieldBlockedPrinted = true
      devLog("COMMENT_DBG ensureField: BLOCKED by endScreenCommentFieldTornDown=true")
    end
    return
  end
  _dbgEnsureFieldBlockedPrinted = false
  if endScreenNativeCommentField or not objc or not objc.UITextField then return end
  devLog("COMMENT_DBG ensureField: CREATING new UITextField")
  local hostView = (objc.viewer and objc.viewer.view and objc.viewer.view.subviews and objc.viewer.view.subviews[1])
    or (objc.viewer and objc.viewer.view)
  if not hostView then return end
  
  local tf = objc.UITextField:alloc():init()
  hostView:addSubview_(tf)
  if hostView.bringSubviewToFront_ then
    hostView:bringSubviewToFront_(tf)
  end
  tf.borderStyle = objc.enum.UITextBorderStyle.none
  tf.font = objc.UIFont:fontWithName_size_("HelveticaNeue", 18)
  tf.returnKeyType = objc.enum.UIReturnKeyType.send or objc.enum.UIReturnKeyType.default
  tf.clearButtonMode = objc.enum.UITextFieldViewMode.whileEditing
  tf.autocorrectionType = objc.enum.UITextAutocorrectionType.no
  tf.autocapitalizationType = objc.enum.UITextAutocapitalizationType.sentences
  tf.contentVerticalAlignment = objc.enum.UIControlContentVerticalAlignment.center
  tf.textAlignment = objc.enum.NSTextAlignment.left
  tf.textColor = color(20, 20, 20, 255)
  tf.backgroundColor = color(255, 255, 255, 255)
  tf.tintColor = Color.uiAccent or color(40, 80, 60, 255)
  tf.layer.cornerRadius = 22
  tf.layer.masksToBounds = true
  tf.layer.borderWidth = 1.5
  tf.layer.borderColor = (Color.uiAccent or color(40, 80, 60, 255)).obj
  -- Add left padding since borderStyle = none removes default text inset
  local leftPad = objc.UIView:alloc():initWithFrame_(objc.rect(0, 0, 14, 44))
  tf.leftView = leftPad
  tf.leftViewMode = objc.enum.UITextFieldViewMode.always
  
  local Delegate = objc.delegate("UITextFieldDelegate")
  function Delegate:textFieldShouldReturn_(oTF)
    endScreenCommentDraft = tostring(oTF.text or "")
    commitEndScreenCommentAndExit()
    oTF:resignFirstResponder_()
    return true
  end
  function Delegate:textFieldDidBeginEditing_(oTF)
    endScreenCommentFocused = true
  end
  function Delegate:textFieldDidEndEditing_(oTF)
    endScreenCommentFocused = false
    endScreenCommentDraft = tostring(oTF.text or "")
  end
  endScreenNativeCommentDelegate = Delegate()
  tf.delegate = endScreenNativeCommentDelegate
  
  local ChangeHandler = objc.class("EndScreenCommentChangeHandler")
  function ChangeHandler:textChanged_(oSender)
    endScreenCommentDraft = tostring(oSender.text or "")
  end
  endScreenNativeCommentHandler = ChangeHandler()
  tf:addTarget_action_forControlEvents_(
    endScreenNativeCommentHandler,
    objc.selector("textChanged:"),
    objc.enum.UIControlEvents.editingChanged
  )
  
  endScreenNativeCommentField = tf

  -- Register keyboard show/hide notifications to drive frame avoidance
  if not endScreenKBObserver then
    local KBObs = objc.class("EndScreenKBNotifObserver")
    function KBObs:keyboardWillShow_(oN)
      local h = 0
      if oN and oN.userInfo then
        local v = oN.userInfo["UIKeyboardFrameEndUserInfoKey"]
        if v and v.CGRectValue then
          local r = v:CGRectValue_()
          if type(r.size.height) == "number" then h = r.size.height end
        end
      end
      endScreenKeyboardHeight = h
    end
    function KBObs:keyboardWillHide_(_)
      endScreenKeyboardHeight = 0
    end
    endScreenKBObserver = KBObs()
    local nc = objc.NSNotificationCenter.defaultCenter
    nc:addObserver_selector_name_object_(
      endScreenKBObserver, objc.selector("keyboardWillShow:"),
      "UIKeyboardWillShowNotification", nil)
    nc:addObserver_selector_name_object_(
      endScreenKBObserver, objc.selector("keyboardWillHide:"),
      "UIKeyboardWillHideNotification", nil)
  end
end

local function updateEndScreenNativeCommentField(rect, ui)
  ensureEndScreenNativeCommentField()
  local tf = endScreenNativeCommentField
  if not tf then return end
  if not (state == STATE_END and ui and ui.canCompose and rect) then
    if state == STATE_END and endScreenCommentFieldActivated and not tf.hidden then
      return  -- latch: keep visible until explicit teardown
    end
    tf.hidden = true
    tf:resignFirstResponder_()
    return
  end

  tf.hidden = false
  tf.placeholder = ui.placeholder or ""
  if tostring(tf.text or "") ~= tostring(endScreenCommentDraft or "") then
    tf.text = endScreenCommentDraft or ""
  end
  if tf.superview and tf.superview.bringSubviewToFront_ then
    tf.superview:bringSubviewToFront_(tf)
  end

  -- Compute base UIKit frame (field at button position, no keyboard)
  -- HEIGHT is UIKit screen height; Codea y-from-bottom → UIKit y-from-top
  local baseX = rect.x
  local baseY = HEIGHT - rect.y - rect.h
  local fW, fH = rect.w, rect.h

  -- Shift up by however much the keyboard overlaps the field (KeyboardAvoider pattern)
  local kh = endScreenKeyboardHeight or 0
  local shiftY = 0
  if kh > 0 then
    local fieldBottom = baseY + fH
    local kbTop = HEIGHT - kh
    local overlap = fieldBottom - kbTop
    if overlap > 0 then
      shiftY = math.ceil(overlap + 12)
    end
  end

  -- Animate only when the shift amount changes (keyboard show/hide)
  if shiftY ~= endScreenCommentLastShift then
    endScreenCommentLastShift = shiftY
    local targetY = baseY - shiftY
    objc.UIView:animateWithDuration_animations_(0.25, function()
      tf.frame = objc.rect(baseX, targetY, fW, fH)
    end)
  end
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
  local tailBaseW  = opts.tailBaseWidth or (rect.w * 0.13)
  local tailLen    = opts.tailLength    or (rect.h * 0.36)
  local outlineW   = opts.outlineWidth  or 1.5

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
  local tipX = baseX
  local tipY = onTop and (baseY + tailLen) or (baseY - tailLen)
  if dist > 0.01 then
    local s = math.min(dist, tailLen) / dist
    tipX = baseX + dx * s
    tipY = baseY + dy * s
  end

  -- Tail geometry: the FILL comes to a SHARP point (tip); only the OUTLINE is
  -- rounded around that point, line-cap style (a small border cap circle).
  local halfB = tailBaseW * 0.5
  local P1x, P1y = baseX - halfB, baseY   -- left base
  local P2x, P2y = baseX + halfB, baseY   -- right base

  -- Border pass: dark, uniform-width outline around body AND tail.
  if outlineW > 0 then
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
    drawRoundedRect(
      rect.x + rect.w * 0.5, rect.y + rect.h * 0.5,
      rect.w + outlineW * 2,  rect.h + outlineW * 2,
      cr + outlineW, borderFill, borderFill
    )
  end

  -- Fill pass: sharp-pointed tail triangle (no rounded fill cap)
  local fm = mesh()
  fm.vertices = {
    vec2(P1x, P1y), vec2(P2x, P2y), vec2(tipX, tipY),
  }
  fm.colors = { bodyFill, bodyFill, bodyFill }
  fm:draw()
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
  local defFill         = Color.uiAccent or color(40, 80, 60, 255)
  local defStroke       = Color.tileText  or color(40, 80, 60, 255)
  local oppFill         = ui.oppFillOverride     or ui.fillOverride   or defFill
  local oppStroke       = ui.oppStrokeOverride   or ui.strokeOverride or defStroke
  local localFill       = ui.localFillOverride   or ui.fillOverride   or defFill
  local localStroke     = ui.localStrokeOverride or ui.strokeOverride or defStroke
  local bText           = Color.panelBG or color(245, 242, 232, 255)

  -- When only ONE balloon is visible, center it horizontally; when both show, keep
  -- the staggered left/right positions. The tail stays put across the shift because
  -- its base is anchored to the avatar X (tailAnchorOverrideX), not the body center.
  local oppShown   = (ui.opponentComment and ui.opponentComment ~= "" and ui.showOpponent ~= false)
  local localShown = (ui.localComment   and ui.localComment   ~= "" and ui.showLocal   ~= false)
  local centeredX  = layout.panelX - bubbleW * 0.5
  local oppRectX   = (oppShown   and not localShown) and centeredX or (panelLeft + 2)
  local localRectX = (localShown and not oppShown)   and centeredX or (panelRight - 2 - bubbleW)

  -- Opponent (originator) balloon — tail points at opponent avatar
  local oppRect = nil
  if ui.opponentComment and ui.opponentComment ~= "" then
    local measured = measureSpeechBalloonText(ui.opponentComment, bubbleW - 8, balloonFontSize, lineHeight, 4, insetY, maxBalloonLines)
    local bH = math.max(layout.boardSide * 0.16, measured.height)
    oppRect = {
      x = oppRectX,
      y = boardBottom - 4 - bH,
      w = bubbleW, h = bH,
    }
    drawSpeechBalloon(oppRect, ui.opponentComment,
      avatarLayout.opponentX, avatarLayout.opponentY, "up",
      oppFill, oppStroke, {
        fontSizeValue = balloonFontSize, lineHeight = lineHeight,
        cornerRadius  = 16,
        tailLength    = 43,
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

  -- Local (responder) balloon — stacked below opponent, tail points at local avatar
  if ui.localComment and ui.localComment ~= "" then
    local measured = measureSpeechBalloonText(ui.localComment, bubbleW - 8, balloonFontSize, lineHeight, 4, insetY, maxBalloonLines)
    local bH = math.max(layout.boardSide * 0.15, measured.height)
    local localRect = {
      x = localRectX,
      y = oppRect and (oppRect.y - 14 - bH) or (boardBottom - 14 - bH),
      w = bubbleW, h = bH,
    }
    drawSpeechBalloon(localRect, ui.localComment,
      avatarLayout.localX + 18, avatarLayout.localY, "up",
      localFill, localStroke, {
        fontSizeValue = balloonFontSize, lineHeight = lineHeight,
        cornerRadius  = 16,
        tailLength    = 40,
        tailBaseWidth = 18,
        textInsetX = 4, textInsetY = insetY,
        alphaMul = localAlpha,
        outlineWidth = 7,
        textColor = (ui.suppressLocalText and color(0, 0, 0, 0)) or bText,
        tailAnchorOverrideX = avatarLayout.localX + 18,
        lines = measured.lines,
        maxLines = maxBalloonLines,
      })
    endScreenLocalBalloonRect = localRect
  end
end

-- Native UITextViews that live inside the two mockup balloons for real typing.
-- A UITextView (not UITextField) so input wraps to multiple lines with a correctly
-- positioned caret. The view shows the VISIBLE text; the balloon is drawn shape-only
-- (suppressText) behind it and is sized to the typed text so it grows to match.
-- Slot 1 = balloon 1 (opponent/top), slot 2 = balloon 2 (local/bottom).
local mockupFields = { {}, {} }        -- [i] = { tv, focused }
local mockupFieldDelegate = nil        -- one shared delegate; dispatches by tv.tag

local function ensureMockupFieldDelegate()
  if mockupFieldDelegate then return mockupFieldDelegate end
  if not (objc and objc.delegate) then return nil end
  local Delegate = objc.delegate("UITextViewDelegate")
  -- Callbacks ONLY set Lua flags — never call UIKit/Codea from an objc callback (it can
  -- crash the draw cycle). Actual text mutation / resignFirstResponder happens in draw()
  -- (mockupEnforceLineCap), driven by these flags. Params use type-prefixed names (o=object).
  function Delegate:textViewDidBeginEditing_(oTV)
    local i = tonumber(oTV.tag) or 0
    if mockupFields[i] then mockupFields[i].focused = true end
  end
  function Delegate:textViewDidEndEditing_(oTV)
    local i = tonumber(oTV.tag) or 0
    if mockupFields[i] then mockupFields[i].focused = false end
  end
  mockupFieldDelegate = Delegate()
  return mockupFieldDelegate
end

local function ensureMockupField(i, fontSize)
  local F = mockupFields[i]
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
  tv.delegate = ensureMockupFieldDelegate()
  F.tv = tv
  F.focused = false
end

local function updateMockupField(i, rect, shown, fontSize)
  ensureMockupField(i, fontSize)
  local F = mockupFields[i]
  local tv = F.tv
  if not tv then return end
  if shown and rect then
    tv.hidden = false
    local enabled = (mockupTextEntryEnabled ~= false)
    tv.userInteractionEnabled = enabled
    if not enabled then
      tv:resignFirstResponder_()
      F.focused = false
    end
    -- visible native text in the balloon's seasonal text color — or RED while the
    -- line-cap flash timer is active (set when an over-limit keystroke was blocked).
    local tc = Color.panelBG or color(245, 242, 232, 255)
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

local function mockupFieldText(i)
  local tv = mockupFields[i].tv
  return tv and tostring(tv.text or "") or ""
end

-- Global: torn down from Main.lua when the mockup overlay is dismissed.
function teardownMockupTextField()
  for i = 1, #mockupFields do
    local F = mockupFields[i]
    if F.tv then
      F.tv:resignFirstResponder_()
      F.tv:removeFromSuperview_()
      F.tv = nil
    end
    F.focused = false
  end
  mockupFieldDelegate = nil
  mockupFieldRect = nil
  mockupField2Rect = nil
end

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

  -- Draw card backdrop
  drawRoundedRect(layout.panelX, layout.panelY, layout.panelW, layout.panelH, layout.cornerRadius or 18, Color.panelBG, Color.panelBG)

  -- Compute avatar area
  local topY = layout.msgCY + layout.msgH * 0.5
  local bottomY = layout.scoreCY - layout.scoreH * 0.5
  local areaCY = (topY + bottomY) * 0.5
  local areaH = math.max(1, topY - bottomY)

  -- Draw avatars
  drawEndUpperRightAvatarsOnly{
    rightCX = layout.rightCX,
    areaCY = areaCY,
    rightW = layout.rightW,
    areaH = areaH,
    opponentAvatar = genericOpponentAvatar()
  }

  -- Visual state per balloon: "active" once its OWN field is focused or has text;
  -- otherwise that balloon shows a greyed-out placeholder state. (Deselecting an
  -- empty field returns to placeholder; deselecting with text stays active.)
  local PLACEHOLDER = "tap to comment on this match"
  local shown1  = (mockupBalloonShown  ~= false)   -- balloon 1 = opponent/top
  local shown2  = (mockupBalloon2Shown ~= false)   -- balloon 2 = local/bottom

  -- Line cap: a balloon holds at most 3 lines. If a keystroke would wrap the text to a
  -- 4th line, revert it (block the input) and flash that balloon's text red. Measured
  -- with the SAME width/font the renderer uses so the check matches the balloon's own wrap.
  -- All UITextView mutation happens HERE in draw() (never in the objc callbacks).
  local balloonFontSize = layout.cardHeaderH * 0.44
  local wrapWidth = layout.panelW - 42            -- == bubbleW - 8 in the renderer
  local MAX_LINES = 3
  local function mockupEnforceLineCap(i)
    local F = mockupFields[i]
    F.flash = math.max(0, (F.flash or 0) - DeltaTime)
    local tv = F.tv
    if not tv then return "" end
    local s = tostring(tv.text or "")
    -- Return-to-dismiss: strip any newline (keeps the comment one wrapped paragraph) and
    -- drop the keyboard. Done here in draw(), not in a textViewDidChange callback.
    if s:find("\n") then
      s = (s:gsub("\n", ""))
      tv.text = s
      tv:resignFirstResponder_()
    end
    local lines = wrapSpeechBalloonText(s, wrapWidth, balloonFontSize)
    local overflow = #lines > MAX_LINES
    if not overflow and #lines == MAX_LINES then
      -- Reserve ~5 characters of headroom on the last line. The native UITextView
      -- measures slightly differently than this Lua wrap, so a 3rd line filled right to
      -- the edge (e.g. after tacking on an ellipsis) can wrap to a 4th line in the view
      -- even while this check still counts 3. Blocking a near-full last line early keeps
      -- the two in sync and avoids that edge case.
      pushStyle()
      font("HelveticaNeue"); fontSize(balloonFontSize)
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
  local txt1    = mockupEnforceLineCap(1)
  local txt2    = mockupEnforceLineCap(2)
  local active1 = mockupFields[1].focused or (txt1 ~= "")
  local active2 = mockupFields[2].focused or (txt2 ~= "")

  -- Draw both balloons via the EXISTING renderer, sized to the TYPED text so each
  -- balloon grows downward (up to 3 lines) as you type; balloon 2 re-stacks below.
  -- The balloon is drawn SHAPE-ONLY (suppressText); the native UITextView on top shows
  -- the wrapped multi-line text with a real caret. When a field is empty the balloon is
  -- sized to the placeholder and a Codea placeholder is drawn behind the (empty) view.
  local model = {
    commentUI = {
      hasAnyComment = true,
      showBalloons  = true,          -- master on; per-balloon toggled below
      showOpponent  = shown1,
      showLocal     = shown2,
      opponentComment = (txt1 ~= "" and txt1) or PLACEHOLDER,
      localComment    = (txt2 ~= "" and txt2) or PLACEHOLDER,
      suppressText      = true,      -- balloon shape only; UITextView renders the text
      suppressLocalText = true,
    }
  }
  local offFill   = color(214, 214, 214, 255)  -- off-state: light gray, opaque
  local offStroke = color(168, 168, 168, 255)  -- outline: a little darker
  if not active1 then
    model.commentUI.oppFillOverride   = offFill
    model.commentUI.oppStrokeOverride = offStroke
  end
  if not active2 then
    model.commentUI.localFillOverride   = offFill
    model.commentUI.localStrokeOverride = offStroke
  end
  drawEndScreenSpeechBalloons(model, layout)

  -- Native UITextView inside each balloon (real typing). Its font size (balloonFontSize,
  -- computed above to match the renderer's layout.cardHeaderH * 0.44) makes native wrapping
  -- ≈ the balloon's measured wrapping, keeping the shape sized to fit the text. When a field
  -- is empty, Codea draws the placeholder (bold italic) behind the (empty) view.
  local function positionMockupField(i, balloonRect, shownFlag, activeFlag, setHitRect)
    if shownFlag and balloonRect then
      local br = balloonRect
      local fRect = { x = br.x + 6, y = br.y + 6, w = br.w - 12, h = br.h - 12 }
      updateMockupField(i, fRect, true, balloonFontSize)
      setHitRect({ cx = fRect.x + fRect.w * 0.5, cy = fRect.y + fRect.h * 0.5, w = fRect.w, h = fRect.h })
      if not activeFlag then
        local pc = Color.tileText or color(40, 80, 60)
        fill(pc.r, pc.g, pc.b, 204)                       -- 20% transparent
        textMode(CENTER); textAlign(CENTER)
        font("HelveticaNeue-BoldItalic")
        fontSize(18)
        text(PLACEHOLDER, br.x + br.w * 0.5, br.y + br.h * 0.5)
      end
    else
      updateMockupField(i, nil, false)
      setHitRect(nil)
    end
  end
  positionMockupField(1, endScreenOppBalloonRect,   shown1, active1, function(r) mockupFieldRect  = r end)
  positionMockupField(2, endScreenLocalBalloonRect, shown2, active2, function(r) mockupField2Rect = r end)

  -- Bottom buttons (stacked): show/hide balloon 1, show/hide balloon 2,
  -- text-entry toggle, close.
  local mtBtnW = layout.panelW * 0.66
  local mtBtnH = 46
  local mtGap  = 10
  local mtBtnCX = layout.panelX
  local closeCY = (layout.panelY - layout.panelH * 0.5) + 18 + mtBtnH * 0.5
  local entryCY = closeCY + (mtBtnH + mtGap)
  local show2CY = closeCY + 2 * (mtBtnH + mtGap)
  local show1CY = closeCY + 3 * (mtBtnH + mtGap)
  local function mockupButton(cy, label, setRect)
    drawRoundedRect(mtBtnCX, cy, mtBtnW, mtBtnH, 20, Color.uiAccent, Color.uiAccent)
    pushStyle()
    fill(255)
    textMode(CENTER); textAlign(CENTER)
    font("HelveticaNeue-Bold")
    fontSize(17)
    text(label, mtBtnCX, cy + 1)
    popStyle()
    setRect({ cx = mtBtnCX, cy = cy, w = mtBtnW, h = mtBtnH })
  end
  mockupButton(show1CY, "show/hide balloon 1",     function(r) mockupShowHideBtnRect  = r end)
  mockupButton(show2CY, "show/hide balloon 2",     function(r) mockupShowHide2BtnRect = r end)
  mockupButton(entryCY, "turn on/off text entry",  function(r) mockupTextEntryBtnRect = r end)
  mockupButton(closeCY, "close debug screen",      function(r) mockupCloseBtnRect     = r end)

  -- Caption
  fill(255)
  textMode(CENTER)
  font("HelveticaNeue")
  fontSize(13)
  text("balloon mockup (dev)", WIDTH * 0.5, HEIGHT - 40)

  popStyle()
end

local function drawEndScreenCommentField(rect, ui)
  if not (rect and ui and ui.canCompose) then return end
  endScreen2PButtonRect = rect
  endScreenButtonAction = commitEndScreenCommentAndExit
  updateEndScreenNativeCommentField(rect, ui)
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
      placeholder = commentInfo and commentInfo.isResponderTurn
        and "Add a reply, then press return"
        or "Add a comment, then press return",
      localComment = localComment,
      opponentComment = opponentComment,
      showBalloons = endScreenSpeechBalloonsVisible,
      hasAnyComment = (localComment ~= "" or opponentComment ~= ""),
    }
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
  -- button
  ------------------------------------------------------------
  
  if model.commentUI and model.commentUI.canCompose then
    drawEndScreenCommentField(layout.playAgainRect, model.commentUI)
  else
    endScreen2PButtonRect = nil
    endScreenButtonAction = nil
    updateEndScreenNativeCommentField(nil, nil)
  end
  
  drawEndScreenSpeechBalloons(model, layout)

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
    commitEndScreenCommentAndExit()
    return
  end
  
  if type(key) ~= "string" or #key ~= 1 then return end
  if key:match("[%c]") then return end
  endScreenCommentDraft = normalizeCommentDraft((endScreenCommentDraft or "") .. key)
end
