-- RippleShader: screen-surface water-ripple distortion. No color, no fading of pixels — the
-- finished frame is rendered into an image and redrawn through a mesh whose fragment shader
-- only displaces the texture lookup (radial sine wave travelling outward from the tap point),
-- so the screen looks like a still pool disturbed by a fingertip. The wave dies out by its
-- amplitude going to zero, not by any alpha.
--
-- startScreenRipple(x, y, r)   -- begin a ripple at (x, y); waves are born at radius r (the badge rim)
-- screenRippleActive()         -- true while a ripple is animating
-- drawFrameWithRipple(drawFn)  -- called from draw(): renders drawFn into an image, then
--                                 draws that image distorted. Caller falls back to plain
--                                 drawFn() when no ripple is active.
-- NOTE: time uniform must not be named uTime (Codea ignores it) — see STRUCTURE.md.

-- Live-tunable via the debug overlay (RipplePicker.lua steppers). Copy final values into defaults.
rippleTuneDefs = {
  { key = "speed",    label = "Speed",    def = 140, step = 40,  min = 60,  max = 1200 },  -- points/second the wavefront travels
  { key = "wavelen",  label = "Wavelen",  def = 22,  step = 6,   min = 8,   max = 200  },  -- points between crests
  { key = "amp",      label = "Amp",      def = 9,   step = 2,   min = 0,   max = 60   },  -- max texture displacement, points
  { key = "trail",    label = "Trail",    def = 25,  step = 25,  min = 25,  max = 800  },  -- points of wave train behind the front
  { key = "rim",      label = "Rim r",    def = 42,  step = 4,   min = 0,   max = 200  },  -- radius the waves are born at (badge rim)
  { key = "delay",    label = "Delay",    def = 0.0,  step = 0.05, min = 0, max = 1.5  },  -- seconds after the badge appears before the ripple fires
  { key = "duration", label = "Duration", def = 0.8, step = 0.4, min = 0.8, max = 10   },  -- seconds until the surface is flat
}
rippleTune = rippleTune or {}
for _, d in ipairs(rippleTuneDefs) do
  if rippleTune[d.key] == nil then rippleTune[d.key] = d.def end
end

function rippleTuneNudge(key, dir)
  for _, d in ipairs(rippleTuneDefs) do
    if d.key == key then
      local v = rippleTune[key] + dir * d.step
      rippleTune[key] = math.floor(math.max(d.min, math.min(d.max, v)) * 100 + 0.5) / 100
      print("rippleTune." .. key .. " = " .. rippleTune[key])
    end
  end
end

function rippleTuneReset()
  for _, d in ipairs(rippleTuneDefs) do rippleTune[d.key] = d.def end
end

local vs = [[
uniform mat4 modelViewProjection;
attribute vec4 position;
attribute vec2 texCoord;
varying highp vec2 vTexCoord;
void main() {
  vTexCoord = texCoord;
  gl_Position = modelViewProjection * position;
}
]]

local fs = [[
precision highp float;
uniform lowp sampler2D texture;
uniform highp vec2 uSize;
uniform highp vec2 uOrigin;
uniform highp float uStartR;
uniform highp float uRippleTime;
uniform highp float uSpeed;
uniform highp float uWaveLen;
uniform highp float uAmp;
uniform highp float uTrail;
uniform highp float uDuration;
varying highp vec2 vTexCoord;

void main() {
  vec2 p = vTexCoord * uSize - uOrigin;
  float d = length(p);
  vec2 dir = d > 0.001 ? p / d : vec2(0.0);

  float front = uStartR + uSpeed * uRippleTime;   // wave is born at the rim, not the centre
  float x = d - front;                       // <0 behind the wavefront
  // sharp leading edge, long decaying wave train behind it
  float env = x > 0.0 ? exp(-(x * x) / 144.0) : exp(x / uTrail);
  float spread = 1.0 / sqrt(1.0 + d / 120.0);          // energy spreads out with distance
  float calm = 1.0 - smoothstep(0.55, 1.0, uRippleTime / uDuration);  // surface settles
  float outside = smoothstep(uStartR - 2.0, uStartR, d);   // nothing is disturbed inside the rim
  float disp = sin(x * 6.2831853 / uWaveLen) * env * spread * calm * outside * uAmp;

  vec2 uv = vTexCoord + dir * disp / uSize;
  gl_FragColor = texture2D(texture, clamp(uv, 0.001, 0.999));
}
]]

local rippleStart  = nil
local rippleOrigin = vec2(0, 0)
local rippleStartR = 0
local rippleMesh   = nil
local rippleMeshFailed = false
local rippleImg    = nil

function startScreenRipple(x, y, startRadius)
  rippleStartR = startRadius or 0
  rippleStart  = ElapsedTime
  rippleOrigin = vec2(x, y)
end

function screenRippleActive()
  if rippleMeshFailed then return false end
  return rippleStart ~= nil and (ElapsedTime - rippleStart) < rippleTune.duration
end

local function getMesh()
  if rippleMesh then return rippleMesh end
  local ok, m = pcall(function()
    local mm = mesh()
    mm:addRect(0, 0, 1, 1)
    mm.shader = shader(vs, fs)
    return mm
  end)
  if ok and m and m.shader then rippleMesh = m return m end
  rippleMeshFailed = true
  print("RippleShader: shader failed to build", tostring(m))
  return nil
end

function drawFrameWithRipple(drawFn)
  local m = getMesh()
  if not m then drawFn() return end
  if not rippleImg or rippleImg.width ~= WIDTH or rippleImg.height ~= HEIGHT then
    rippleImg = image(WIDTH, HEIGHT)
  end
  setContext(rippleImg)
  local ok, err = pcall(drawFn)
  setContext()
  if not ok then error(err, 0) end

  local sh = m.shader
  sh.uSize        = vec2(WIDTH, HEIGHT)
  sh.uOrigin      = rippleOrigin
  sh.uStartR      = rippleStartR
  sh.uRippleTime  = ElapsedTime - rippleStart
  sh.uSpeed       = rippleTune.speed
  sh.uWaveLen     = rippleTune.wavelen
  sh.uAmp         = rippleTune.amp
  sh.uTrail       = rippleTune.trail
  sh.uDuration    = rippleTune.duration
  m.texture = rippleImg
  m:setRect(1, WIDTH * 0.5, HEIGHT * 0.5, WIDTH, HEIGHT)
  pushStyle()
  noClip()
  m:draw()
  popStyle()
end
