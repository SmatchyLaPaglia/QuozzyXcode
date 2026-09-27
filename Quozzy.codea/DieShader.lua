-- DieShader: draws a die (rounded square) with a dark outline and a soft diffuse highlight
-- in the upper-right corner, like a light source shining from that direction.
--
-- drawDie(x, y, w, h, r, fillCol, angleDeg)   -- (x, y) is the CENTER, like drawRoundedRect
--   angleDeg: the rotation (Codea degrees, CCW positive) the caller has ALREADY applied via
--             rotate(); the highlight is counter-rotated so the light stays upper-right on
--             screen even when the die is tilted (menu dice, ready-screen jitter).
--
-- The outline is derived from the fill (fill * DIE_EDGE_DARKNESS) so it stays darker than the
-- die in every season theme, with a 1pt lighter hairline (fill lightened by DIE_RIM_LIGHTEN)
-- just inside it. Tune the DIE_* constants below; nothing else needs to change.
-- If the shader fails to build, drawDie falls back to the old flat drawRoundedRect look.

DIE_EDGE_DARKNESS      = 0.62   -- outline rgb = fill rgb * this (0 = black, 1 = same as fill)
DIE_EDGE_WIDTH_FRAC    = 0.045  -- outline width as a fraction of the die's shorter side
DIE_EDGE_WIDTH_MIN     = 1.5    -- ... but never thinner than this many points
DIE_RIM_WIDTH          = 1.0    -- hairline just inside the outline, in points
DIE_RIM_LIGHTEN        = 0.40   -- hairline color = fill lightened this much toward white (0..1)
DIE_HIGHLIGHT_STRENGTH = 0.24   -- peak white mixed in at the highlight center (0..1)
DIE_HIGHLIGHT_RADIUS   = 0.95   -- highlight falloff radius, fraction of die size
DIE_HIGHLIGHT_OFFSET   = 0.36   -- highlight center, fraction of die size from die center

DieS = {
  vertexShader = [[
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
  fragmentShader = [[
  precision highp float;

  uniform highp vec4 fillColor;
  uniform highp vec4 edgeColor;
  uniform highp vec2 sizePx;
  uniform highp float radiusPx;
  uniform highp float edgePx;
  uniform highp vec4 rimColor;
  uniform highp float rimPx;
  uniform highp float lightAngle;
  uniform highp float hlStrength;
  uniform highp float hlRadius;
  uniform highp float hlOffset;

  varying highp vec2 vTexCoord;

  void main()
  {
    // signed distance to the rounded rect, in points (negative inside)
    vec2 p = (vTexCoord - 0.5) * sizePx;
    vec2 q = abs(p) - (sizePx * 0.5 - vec2(radiusPx));
    float d = length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - radiusPx;

    float cover   = 1.0 - smoothstep(-0.75, 0.75, d);
    float edgeMix = smoothstep(-edgePx - 0.75, -edgePx + 0.75, d);
    vec3 base = mix(fillColor.rgb, edgeColor.rgb, edgeMix);

    // Light hairline just inside the dark outline: a rimPx-wide band ending at the outline's
    // inner boundary (d = -edgePx), leaving ~0.5pt so it doesn't blur into the dark edge.
    float rimD = abs(d + edgePx + 0.5 + rimPx * 0.5);
    float rim  = (1.0 - smoothstep(rimPx * 0.5 - 0.3, rimPx * 0.5 + 0.4, rimD)) * (1.0 - edgeMix);
    base = mix(base, rimColor.rgb, rim);

    // Highlight center: upper-right of the die in SCREEN space. The die is rotated by
    // lightAngle, so express that direction in the die's local frame (rotate by -angle).
    float ca = cos(lightAngle);
    float sa = sin(lightAngle);
    vec2 lc = vec2(hlOffset) * sizePx;
    lc = vec2(ca * lc.x + sa * lc.y, -sa * lc.x + ca * lc.y);
    float dist = length(p - lc) / (min(sizePx.x, sizePx.y) * hlRadius);
    float hl = pow(clamp(1.0 - dist, 0.0, 1.0), 1.7) * hlStrength;
    hl *= (1.0 - 0.7 * edgeMix);   // stay subtle over the dark outline

    vec3 col = mix(base, vec3(1.0), hl);
    gl_FragColor = vec4(col, cover * fillColor.a);
  }
]]
}

local _dieMesh = nil
local _dieMeshFailed = false

local function _getDieMesh()
  if _dieMesh then return _dieMesh end
  if _dieMeshFailed then return nil end
  local ok, m = pcall(function()
    local mm = mesh()
    mm:addRect(0, 0, 1, 1)
    mm.shader = shader(DieS.vertexShader, DieS.fragmentShader)
    return mm
  end)
  if ok and m and m.shader then
    _dieMesh = m
    return m
  end
  _dieMeshFailed = true
  print("DieShader: shader failed to build, using flat dice", tostring(m))
  return nil
end

local function _dieEdgeColor(fillCol)
  local k = DIE_EDGE_DARKNESS
  return color(fillCol.r * k, fillCol.g * k, fillCol.b * k, fillCol.a or 255)
end

function drawDie(x, y, w, h, r, fillCol, angleDeg)
  fillCol = fillCol or color(255)
  local m = _getDieMesh()
  if not m then
    drawRoundedRect(x, y, w, h, r, fillCol, _dieEdgeColor(fillCol))
    return
  end

  local sh = m.shader
  sh.fillColor    = fillCol
  sh.edgeColor    = _dieEdgeColor(fillCol)
  sh.sizePx       = vec2(w, h)
  sh.radiusPx     = math.min(r or 0, math.min(w, h) * 0.5)
  sh.edgePx       = math.max(DIE_EDGE_WIDTH_MIN, math.min(w, h) * DIE_EDGE_WIDTH_FRAC)
  local k = DIE_RIM_LIGHTEN
  sh.rimColor     = color(fillCol.r + (255 - fillCol.r) * k, fillCol.g + (255 - fillCol.g) * k,
                          fillCol.b + (255 - fillCol.b) * k, fillCol.a or 255)
  sh.rimPx        = DIE_RIM_WIDTH
  sh.lightAngle   = math.rad(angleDeg or 0)
  sh.hlStrength   = DIE_HIGHLIGHT_STRENGTH
  sh.hlRadius     = DIE_HIGHLIGHT_RADIUS
  sh.hlOffset     = DIE_HIGHLIGHT_OFFSET

  m:setRect(1, x, y, w, h)
  m:draw()
end
