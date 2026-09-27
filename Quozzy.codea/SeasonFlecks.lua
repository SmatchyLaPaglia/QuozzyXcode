------------------------------------------------------------
-- SEASON FLECKS
-- Ambient particles drifting behind the menu season word — meant to read as
-- snow / leaves / sand / pollen blowing in a steady wind: they enter from one
-- edge of the SCREEN, drift the full width, and exit off the other edge,
-- rather than radiating outward from the word itself (that was the previous
-- design, changed 2026-09-27 per feedback — it read as a "poof" centered on
-- the text, not wind). Per-frame motion, matching TextGoPoof's frame-based
-- style (no DeltaTime) for a consistent feel.
--
-- Usage (from drawMenu, STATE_MENU only):
--   initFlecks(bandCy, bandH)               -- lazily / on season change
--   updateFlecks(bandCy, bandH, recycle)    -- once per frame
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
seasonFleckWindDir = seasonFleckWindDir or 1    -- +1 = drifts left->right, -1 = right->left;
                                                 -- re-rolled each time initFlecks runs

local POOL   = 80
local MARGIN = 60   -- how far past each screen edge a fleck spawns/despawns, in points

local function _buildFleck(x, bandCy, bandH)
  local dir = seasonFleckWindDir
  return {
    x         = x,
    y         = bandCy + (math.random() - 0.5) * bandH * 0.9,
    windSpeed = dir * (0.8 + math.random() * 0.8),   -- px/frame; ~9-19s to cross a ~900pt screen
    lPhase    = math.random() * math.pi * 2,
    lFreq     = 0.004 + math.random() * 0.006,
    lAmp      = bandH * (0.04 + math.random() * 0.10),  -- gentle vertical wander, scaled to the band
    fPhase    = math.random() * math.pi * 2,
    fFreq     = 0.008 + math.random() * 0.013,
    fAmp      = 6     + math.random() * 18,
    ePhase    = math.random() * math.pi * 2,
    eFreq     = 0.003 + math.random() * 0.005,
    size      = 1.2   + math.random() * 2.2,
    delay     = math.floor(math.random() * 60),
    born      = false,
  }
end

-- Spawns right at the entry edge — used for respawns, so ongoing flow reads as a
-- continuous stream entering from one side.
local function newFleckAtEdge(bandCy, bandH)
  local startX = (seasonFleckWindDir > 0) and -MARGIN or (WIDTH + MARGIN)
  return _buildFleck(startX, bandCy, bandH)
end

-- Spawns anywhere along the full travel path — used only to build the initial pool, so the
-- band is already populated on first load / season change instead of empty until flecks
-- drift in from the edge over several seconds.
local function newFleckAnywhere(bandCy, bandH)
  local startEdge = (seasonFleckWindDir > 0) and -MARGIN or (WIDTH + MARGIN)
  local pathLen = WIDTH + MARGIN * 2
  local x = startEdge + seasonFleckWindDir * math.random() * pathLen
  return _buildFleck(x, bandCy, bandH)
end

function initFlecks(bandCy, bandH)
  seasonFleckWindDir = (math.random() < 0.5) and 1 or -1
  seasonFlecks = {}
  for i = 1, POOL do
    seasonFlecks[i] = newFleckAnywhere(bandCy, bandH)
  end
end

-- recycle: when true, flecks that have exited respawn at the entry edge. Pass false
-- during the swipe sweep so the pool naturally empties as the haiku takes over.
function updateFlecks(bandCy, bandH, recycle)
  seasonFleckT = seasonFleckT + 1
  local t = seasonFleckT
  local dir = seasonFleckWindDir

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
      p.x = p.x + p.windSpeed
      p.y = p.y + math.sin(p.lFreq * t + p.lPhase) * p.lAmp * 0.02
                + math.sin(p.fFreq * t + p.fPhase) * p.fAmp * 0.04 * envelope

      local exited = (dir > 0 and p.x > WIDTH + MARGIN) or (dir < 0 and p.x < -MARGIN)
      if exited and recycle then
        seasonFlecks[i] = newFleckAtEdge(bandCy, bandH)
      end
    end
  end
end

-- fade: overall opacity multiplier (1 idle, ramps to 0 during the sweep).
function drawFlecks(seasonName, fade)
  if fade <= 0 then return end
  local c = FLECK_COLOR[seasonName] or FLECK_COLOR.Winter
  local t = seasonFleckT
  local dir = seasonFleckWindDir
  local startEdge = (dir > 0) and -MARGIN or (WIDTH + MARGIN)
  local pathLen = WIDTH + MARGIN * 2

  pushStyle()
  ellipseMode(CENTER)
  noStroke()

  for i = 1, #seasonFlecks do
    local p = seasonFlecks[i]
    if p.born then
      local envelope = 0.7 + 0.3 * math.sin(p.eFreq * t + p.ePhase)
      -- Fade in/out near the two ends of the travel path (entry/exit), not by age, so a
      -- fleck's visibility only ever depends on where it is on screen.
      local progress = math.abs(p.x - startEdge) / pathLen
      local fadeIn   = math.max(0, math.min(1, progress / 0.06))
      local fadeOut  = math.max(0, math.min(1, (1 - progress) / 0.06))
      local alpha    = fadeIn * fadeOut * (0.55 + 0.45 * envelope) * fade
      if alpha > 0 then
        fill(c.r, c.g, c.b, alpha * 255)
        ellipse(p.x, p.y, p.size * envelope * 2)
      end
    end
  end

  popStyle()
end
