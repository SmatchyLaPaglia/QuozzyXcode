-- RippleShader: live, direct-to-screen water-ripple shader for the "match ready" quick-
-- start badge (Badges.lua drawQuickStart).
--
-- History: an earlier version of this exact file was tried, its math verified correct in
-- isolation, but the app's own cached mesh never rendered once wired into the real badge —
-- reverted in favor of a CPU-drawn ripple (Badges.lua drawWaterRipple). A fresh, completely
-- independent rebuild of the identical shader (RippleDemo.lua) was then added as an always-
-- on standalone demo to prove the effect still worked, and it did — confirmed animating
-- correctly over multiple frames via DevRemote screenshots. This file is that same proven
-- build, promoted from demo to the real badge. See STRUCTURE.md "Match-ready badge ripple"
-- and "RippleDemo.lua" for the full account. RippleDemo.lua and its standalone corner badge
-- are removed now that this has taken its place — this file is the one used in production.
--
-- drawShaderRipple(originX, originY, t, maxRadius, ripColor) -> true if it drew, false if
-- the shader isn't available (caller should fall back to drawWaterRipple, the CPU version).
-- The mesh always covers the full WIDTH x HEIGHT screen (the badge is a droplet hitting a
-- pond that's the whole menu, not just a small disc around itself); originX/originY is the
-- droplet's impact point in absolute screen coordinates, and distance is computed per-pixel
-- from that point, not from the quad's center.

local RippleS = {
  vertexShader = [[
  uniform mat4 modelViewProjection;
  attribute vec4 position;
  attribute vec2 texCoord;
  varying highp vec2 vTexCoord;
  void main() {
    vTexCoord = texCoord;
    gl_Position = modelViewProjection * position;
  }
]],
  -- The time uniform MUST NOT be named uTime — Codea silently ignores a uniform literally
  -- named "uTime" (no error, it just always reads 0). Confirmed by bisecting with DevRemote
  -- (isolated offscreen renders, sampling raw pixel colors) on 2026-09-27; uRippleTime
  -- fixed it completely. Ring count is a fixed GLSL constant (4), not a uniform-compared
  -- dynamic loop bound (harmless either way, but keeping it fixed avoids the question).
  fragmentShader = [[
  precision highp float;
  uniform highp vec2 uSize;
  uniform highp vec2 uOrigin;
  uniform highp float uRippleTime;
  uniform highp float uMaxRadius;
  uniform highp vec4 uColor;
  uniform highp float uRingSpeed;
  uniform highp float uRingSpacing;
  uniform highp float uRingWidth;
  varying highp vec2 vTexCoord;

  void main() {
    vec2 p = vTexCoord * uSize - uOrigin;
    float angle = atan(p.y, p.x);
    float wobble = 1.0 + 0.035 * sin(angle * 5.0 + uRippleTime * 1.3)
                       + 0.02  * sin(angle * 9.0 - uRippleTime * 0.8);
    float dist = length(p) / wobble;

    float cycle = uMaxRadius + uRingSpacing * 4.0;
    float alpha = 0.0;
    for (int i = 0; i < 4; i++) {
      float phase = mod(uRippleTime * uRingSpeed - float(i) * uRingSpacing, cycle);
      float d = dist - phase;
      float ring = exp(-(d * d) / (uRingWidth * uRingWidth));
      float fade = clamp(1.0 - phase / uMaxRadius, 0.0, 1.0);
      fade = fade * fade;
      alpha += ring * fade;
    }
    alpha = clamp(alpha, 0.0, 1.0);
    gl_FragColor = vec4(uColor.rgb, uColor.a * alpha);
  }
]]
}

local _rippleMesh = nil
local _rippleMeshFailed = false

local function _getRippleMesh()
  if _rippleMesh then return _rippleMesh end
  if _rippleMeshFailed then return nil end
  local ok, m = pcall(function()
    local mm = mesh()
    mm:addRect(0, 0, 1, 1)
    mm.shader = shader(RippleS.vertexShader, RippleS.fragmentShader)
    return mm
  end)
  if ok and m and m.shader then
    _rippleMesh = m
    return m
  end
  _rippleMeshFailed = true
  print("RippleShader: shader failed to build, caller should fall back", tostring(m))
  return nil
end

function drawShaderRipple(originX, originY, t, maxRadius, ripColor, ringSpeed, ringSpacing)
  local m = _getRippleMesh()
  if not m then return false end

  local w, h = WIDTH, HEIGHT
  local sh = m.shader
  sh.uSize        = vec2(w, h)
  sh.uOrigin      = vec2(originX, originY)
  sh.uRippleTime  = t
  sh.uMaxRadius   = maxRadius
  sh.uColor       = ripColor
  sh.uRingSpeed   = ringSpeed or 130
  sh.uRingSpacing = ringSpacing or 34
  sh.uRingWidth   = 10
  m:setRect(1, w * 0.5, h * 0.5, w, h)
  m:draw()
  return true
end
