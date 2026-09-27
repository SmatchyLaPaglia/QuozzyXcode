-- RippleDemo: a STANDALONE demonstration of the water-ripple shader that could not be made
-- to render once wired into the real quick-start badge (Badges.lua drawQuickStart / the old
-- RippleShader.lua — see STRUCTURE.md "Match-ready badge ripple" for the full account).
--
-- This is a deliberately isolated proof that the shader itself is correct: its own mesh,
-- its own shader object, its own draw call, with NO connection to quickStart/vsHasActionable
-- or anything else in Badges.lua. It runs continuously (not gated on any match state) purely
-- to show the effect is real and working, concurrently with the shipped CPU-based ripple on
-- the actual badge (Badges.lua drawWaterRipple) — see which one you like, and if this one
-- keeps working reliably here, it's a candidate to eventually replace the CPU version.
--
-- Not wired into any button, touch handler, or game state on purpose. Delete this file (and
-- its one call site, drawRippleDemo() in Main.lua's draw()) whenever it's no longer wanted.

local RippleDemoS = {
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
  -- Same math as the reverted RippleShader.lua, with the one confirmed real fix: the time
  -- uniform is named uRippleTime, NOT uTime — Codea silently ignores a uniform literally
  -- named "uTime" (no error; it just always reads 0). Ring count is a fixed GLSL constant
  -- (4), not a uniform-compared dynamic loop bound.
  fragmentShader = [[
  precision highp float;
  uniform highp vec2 uSize;
  uniform highp float uRippleTime;
  uniform highp float uMaxRadius;
  uniform highp vec4 uColor;
  uniform highp float uRingSpeed;
  uniform highp float uRingSpacing;
  uniform highp float uRingWidth;
  varying highp vec2 vTexCoord;

  void main() {
    vec2 p = (vTexCoord - 0.5) * uSize;
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

local _demoMesh = nil
local _demoMeshFailed = false

local function _getDemoMesh()
  if _demoMesh then return _demoMesh end
  if _demoMeshFailed then return nil end
  local ok, m = pcall(function()
    local mm = mesh()
    mm:addRect(0, 0, 1, 1)
    mm.shader = shader(RippleDemoS.vertexShader, RippleDemoS.fragmentShader)
    return mm
  end)
  if ok and m and m.shader then
    _demoMesh = m
    return m
  end
  _demoMeshFailed = true
  print("RippleDemo: shader failed to build", tostring(m))
  return nil
end

RIPPLE_DEMO_RADIUS = 42    -- matches quickStart.radius, so it's a fair visual comparison
RIPPLE_DEMO_CYCLE  = 3.0   -- seconds per loop of the demo's own continuous animation

function drawRippleDemo()
  if state ~= STATE_MENU then return end

  local m = _getDemoMesh()
  local cx = WIDTH - 70
  local cy = HEIGHT - 130
  local r = RIPPLE_DEMO_RADIUS
  local maxRadius = r * 3.2
  local t = ElapsedTime % RIPPLE_DEMO_CYCLE

  pushStyle()

  if m then
    local side = maxRadius * 2.3
    local sh = m.shader
    sh.uSize        = vec2(side, side)
    sh.uRippleTime  = t
    sh.uMaxRadius   = maxRadius
    sh.uColor       = color(40, 120, 230, 255)   -- blue, to visually distinguish from the real (red) badge
    sh.uRingSpeed   = 130
    sh.uRingSpacing = 34
    sh.uRingWidth   = 10
    m:setRect(1, cx, cy, side, side)
    m:draw()
  end

  noStroke()
  fill(40, 120, 230, 255)
  ellipseMode(CENTER)
  ellipse(cx, cy, r * 2, r * 2)

  fill(255, 255, 255, 255)
  textMode(CENTER)
  textAlign(CENTER)
  fontSize(11)
  font("Baskerville-SemiBold")
  text("SHADER", cx, cy + 6)
  text("DEMO", cx, cy - 6)

  fill(40, 120, 230, 200)
  fontSize(11)
  font("HelveticaNeue-Italic")
  text(m and "(live)" or "(fallback: shader failed)", cx, cy - r - 16)

  popStyle()
end
