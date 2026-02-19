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
      
      if a > 0 then
        
        local p = {}
        
        p.x = specsA.x - img.width/2 + x
        p.y = specsA.y - img.height/2 + y
        
        p.vx = P.direction * math.random(20,60) / 10
        + math.random(-10,10) / 10
        
        p.vy = math.random(0,15) / 10
        p.phase = math.random(0,628) / 100
        
        p.life = math.random(30,60)
        p.size = math.random(2,3)
        p.ground = p.y
        
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
  
  -- Update particles
  
  for _,p in ipairs(P.parts) do
    
    if p.life > 0 then
      
      alive = true
      
      p.vx = p.vx + (p.vx > 0 and 0.05 or -0.05)
      p.vx = p.vx + math.sin(t*2 + p.phase) * 0.03
      p.vy = p.vy + math.cos(t*1.5 + p.phase) * 0.02
      p.vy = p.vy - 0.08
      
      p.x = p.x + p.vx
      p.y = p.y + p.vy
      
      if p.y < p.ground then
        p.y = p.ground
        p.vy = -p.vy * 0.3
        p.vx = p.vx * 0.9
        if math.abs(p.vy) < 0.2 then p.vy = 0 end
      end
      
      p.vx = p.vx * 0.995
      p.vy = p.vy * 0.995
      
      fill(120,100,70,p.life * 3)
      rectMode(CENTER)
      rect(p.x,p.y,p.size,p.size)
      
      p.life = p.life - 1
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