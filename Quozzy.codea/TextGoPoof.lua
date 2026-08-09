------------------------------------------------------------
-- INTERNAL STATE
------------------------------------------------------------

local P = {
  state = "A",       -- "A", "ANIM", "B"
  parts = {},
  specsA = nil,
  specsB = nil,
  alphaB = 0,
  touchStartX = nil,
  direction = 1
}

local DEFAULT_COLOR = color(60,40,20,255)

local function applyTextSpecs(s)
  font(s.font)
  fontSize(s.size)
  fill(s.color or DEFAULT_COLOR)
  textMode(s.mode or CENTER)
  textAlign(s.align or CENTER)
end

------------------------------------------------------------
-- RESET (optional external call)
------------------------------------------------------------

function resetPoofingText()
  P.state = "A"
  P.parts = {}
  P.alphaB = 0
end

------------------------------------------------------------
-- SWIPE DETECTION
------------------------------------------------------------

function didSwipeOnPoofingText(t)
  
  if t.state == BEGAN then
    P.touchStartX = t.x
  end
  
  if t.state == ENDED and P.touchStartX then
    
    local dx = t.x - P.touchStartX
    
    if math.abs(dx) > 40 and P.state == "A" then
      P.direction = (dx > 0) and 1 or -1
      
      if P.specsA and P.specsB then
        startPoof(P.specsA, P.specsB)
      end
    end
    
    P.touchStartX = nil
  end
end

------------------------------------------------------------
-- START ANIMATION
------------------------------------------------------------

function startPoof(specsA, specsB)

  P.parts = {}
  P.alphaB = 0
  P.animT = 0
  P.state = "ANIM"

  --------------------------------------------------------
  -- Rasterize A text
  --------------------------------------------------------
  
  local img = image(512,256)
  
  setContext(img)
  pushStyle()
  background(0,0,0,0)
  
  font(specsA.font)
  fontSize(specsA.size)
  fill(255)
  textAlign(CENTER)
  textMode(CENTER)
  text(specsA.text, img.width/2, img.height/2)
  
  popStyle()
  setContext()
  
  --------------------------------------------------------
  -- Spawn particles
  --------------------------------------------------------
  
  for x = 1, img.width, 3 do
    for y = 1, img.height, 3 do

      local _,_,_,a = img:get(x,y)

      -- Keep only ~50% of lit pixels for a sparser, driftier poof
      if a > 0 and math.random() < 0.50 then

        local p = {}

        p.x = specsA.x - img.width/2 + x
        p.y = specsA.y - img.height/2 + y

        -- Base drift in the swipe direction, small spread + upward lift.
        -- NOTE: Codea is y-up, so a positive vy floats the particle UPWARD
        -- (the source brief was y-down, where lift was negative).
        local baseSpd = 0.6 + math.random() * 1.2
        local spread  = (math.random() - 0.5) * 1.0
        local lift    = math.random() * 0.5

        p.vx = P.direction * baseSpd + spread * 0.3
        p.vy = lift + (math.random() - 0.5) * 0.4

        p.life    = 0
        p.maxLife = 90 + math.random(0, 60)
        p.size    = math.random(2, 3)          -- keep the existing poof dot size
        p.phase   = math.random() * math.pi * 2

        table.insert(P.parts, p)
      end
    end
  end
end

------------------------------------------------------------
-- DRAW
------------------------------------------------------------

function drawPoofingText(specA, specB)
  
  -- Cache latest specs every frame
  if specA then P.specsA = specA end
  if specB then P.specsB = specB end
  
  --------------------------------------------------------
  -- STATE A — static season text
  --------------------------------------------------------
  
  if P.state == "A" then
    if P.specsA then
      pushStyle()
      applyTextSpecs(P.specsA)
      text(P.specsA.text, P.specsA.x, P.specsA.y)
      popStyle()
    end
    return
  end
  
  --------------------------------------------------------
  -- STATE B — static haiku text
  --------------------------------------------------------
  
  if P.state == "B" then
    if P.specsB then
      pushStyle()
      applyTextSpecs(P.specsB)
      text(P.specsB.text, P.specsB.x, P.specsB.y)
      popStyle()
    end
    return
  end
  
  --------------------------------------------------------
  -- STATE ANIM — particles + fade-in B
  --------------------------------------------------------
  
  local alive = false
  local t = ElapsedTime

  P.animT = (P.animT or 0) + DeltaTime

  -- Fade in B text

  P.alphaB = math.min(255, P.alphaB + 6)
  
  if P.specsB then
    pushStyle()
    
    local c = P.specsB.color or DEFAULT_COLOR
    fill(c.r, c.g, c.b, P.alphaB)
    
    font(P.specsB.font)
    fontSize(P.specsB.size)
    textMode(P.specsB.mode or CENTER)
    textAlign(P.specsB.align or CENTER)
    
    text(P.specsB.text, P.specsB.x, P.specsB.y)
    
    popStyle()
  end
  
  -- Update particles — directional drift in the swipe direction + sine float.

  local pc = P.specsA and P.specsA.color or DEFAULT_COLOR

  for _,p in ipairs(P.parts) do

    p.life = p.life + 1
    local progress = p.life / p.maxLife

    if progress < 1 then

      alive = true

      -- Gentle acceleration in the swipe direction, mild drag
      p.vx = p.vx + P.direction * 0.04
      p.vx = p.vx * 0.98

      -- Sine float on y (spatially varied by p.x)
      p.vy = p.vy + math.sin(p.life * 0.14 + p.x * 0.01) * 0.03
      p.vy = p.vy * 0.98

      p.x = p.x + p.vx
      p.y = p.y + p.vy

      -- Full opacity for the first 40% of life, then linear fade to 0
      local alpha
      if progress < 0.4 then
        alpha = 255
      else
        alpha = 255 * (1 - (progress - 0.4) / 0.6)
      end

      fill(pc.r, pc.g, pc.b, alpha * 0.75)
      rectMode(CENTER)
      rect(p.x, p.y, p.size, p.size)
    end
  end
  
  -- Transition to B state when done
  
  if not alive then
    P.state = "B"
    P.parts = {}
  end
end

------------------------------------------------------------
-- STATUS CHECKS
------------------------------------------------------------

function TextGoPoof_isIdle()
  return P.state ~= "ANIM"
end

function TextGoPoof_state()
  return P.state
end

-- Ambient-fleck opacity multiplier: 1 while idle (state A), ramps to 0 during
-- the sweep as the haiku fades in, 0 once the haiku is showing (state B).
function TextGoPoof_flecksFade()
  if P.state == "A" then return 1 end
  if P.state == "B" then return 0 end
  return math.max(0, 1 - (P.alphaB / 255))
end

-- Whether the haiku attribution should be shown yet. True the instant the season
-- name starts dissolving (state ANIM or B) — same moment the haiku itself starts
-- fading in, so the two appear together instead of attribution trailing behind on
-- its own timer (2026-08-09: removed a ~1.1s extra delay that used to hold it back
-- even after the haiku had already fully faded in).
function TextGoPoof_attributionReady()
  return P.state ~= "A"
end

-- Haiku's own fade-in alpha (0-255): 0 in state A, ramping in state ANIM, 255 in
-- state B. Exposed so the attribution line can fade in on the EXACT same curve
-- (see drawMenuSeasonPoof, HaikuMenu.lua) rather than just popping in at full
-- opacity the instant TextGoPoof_attributionReady() flips true.
function TextGoPoof_haikuAlpha()
  if P.state == "B" then return 255 end
  if P.state == "ANIM" then return P.alphaB or 0 end
  return 0
end