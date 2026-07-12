------------------------------------------------------------
-- SEASON FLECKS
-- Ambient particles that drift gently around the menu season
-- word (leaves / seeds / blown snow). Per-frame motion, matching
-- TextGoPoof's frame-based style (no DeltaTime) for a consistent feel.
--
-- Usage (from drawMenu, STATE_MENU only):
--   initFlecks(cx, cy)                      -- lazily / on season change
--   updateFlecks(cx, cy, recycle)           -- once per frame
--   drawFlecks(seasonName, fade)            -- fade 1=idle, 0=hidden
------------------------------------------------------------

-- Dedicated fleck palette (keyed by capitalised season name, matching `seasons`)
FLECK_COLOR = {
  Spring = color(120, 170, 100),
  Summer = color(210, 160,  60),
  Autumn = color(160,  90,  40),
  Winter = color(160, 190, 210),
}

seasonFlecks       = seasonFlecks       or {}
seasonFleckT       = seasonFleckT       or 0    -- frame counter
seasonFlecksSeason = seasonFlecksSeason or nil  -- season index the pool was built for

local POOL = 80

local function newFleck(cx, cy)
  local spawnR  = 20 + math.random() * 60
  local spawnA  = math.random() * math.pi * 2
  local windDir = (math.random() < 0.7) and 1 or -1

  return {
    x         = cx + math.cos(spawnA) * spawnR,
    y         = cy + math.sin(spawnA) * spawnR * 0.45,
    windSpeed = windDir * (0.09 + math.random() * 0.21),
    lPhase    = math.random() * math.pi * 2,
    lFreq     = 0.006 + math.random() * 0.009,
    lAmp      = 0.15  + math.random() * 0.35,
    fPhase    = math.random() * math.pi * 2,
    fFreq     = 0.008 + math.random() * 0.013,
    fAmp      = 6     + math.random() * 18,
    ePhase    = math.random() * math.pi * 2,
    eFreq     = 0.003 + math.random() * 0.005,
    size      = 1.2   + math.random() * 2.2,
    maxAge    = 320   + math.random() * 240,
    age       = 0,
    delay     = math.floor(math.random() * 120),
    born      = false,
  }
end

function initFlecks(cx, cy)
  seasonFlecks = {}
  for i = 1, POOL do
    seasonFlecks[i] = newFleck(cx, cy)
  end
end

-- recycle: when true, dead particles are respawned from (cx,cy). Pass false
-- during the swipe sweep so the pool naturally empties as the haiku takes over.
function updateFlecks(cx, cy, recycle)
  seasonFleckT = seasonFleckT + 1
  local t = seasonFleckT

  for i = 1, #seasonFlecks do
    local p = seasonFlecks[i]

    if not p.born then
      if p.delay > 0 then
        p.delay = p.delay - 1
      else
        p.born = true
      end
    else
      local envelope = 0.7 + 0.3 * math.sin(p.eFreq * t + p.ePhase)
      p.x = p.x + p.windSpeed + math.sin(p.lFreq * t + p.lPhase) * p.lAmp
      p.y = p.y + math.sin(p.fFreq * t + p.fPhase) * p.fAmp * 0.04 * envelope
      p.age = p.age + 1

      local offscreen = (p.x < -20 or p.x > WIDTH + 20 or p.y < -20 or p.y > HEIGHT + 20)
      if (p.age >= p.maxAge or offscreen) and recycle then
        seasonFlecks[i] = newFleck(cx, cy)
      end
    end
  end
end

-- fade: overall opacity multiplier (1 idle, ramps to 0 during the sweep).
function drawFlecks(seasonName, fade)
  if fade <= 0 then return end
  local c = FLECK_COLOR[seasonName] or FLECK_COLOR.Winter
  local t = seasonFleckT

  pushStyle()
  ellipseMode(CENTER)
  noStroke()

  for i = 1, #seasonFlecks do
    local p = seasonFlecks[i]
    if p.born then
      local envelope = 0.7 + 0.3 * math.sin(p.eFreq * t + p.ePhase)
      local fadeIn   = math.min(1, p.age / 30)
      local fadeOut  = math.min(1, (p.maxAge - p.age) / 40)
      local alpha    = fadeIn * fadeOut * (0.55 + 0.45 * envelope) * fade
      if alpha > 0 then
        fill(c.r, c.g, c.b, alpha * 255)
        ellipse(p.x, p.y, p.size * envelope * 2)
      end
    end
  end

  popStyle()
end
