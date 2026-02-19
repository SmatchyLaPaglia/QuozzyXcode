--############################################################
-- Match Ready Badge (menu overlay)
--############################################################

matchBadge = matchBadge or {
  active          = false,
  x               = 0,
  y               = 0,
  
  -- core size
  radius          = 42,      -- <<< size of button
  
  phase           = "hidden",
  phaseTime       = 0,
  
  -- timing
  visibleDuration = 4.4,     -- <<< time on-screen before hop (incl. shrink)
  hiddenDuration  = 0.005,     -- time off-screen between hops
  appearDuration  = 0.25,    -- pop / bounce in
  disappearDuration = 0.25,  -- shrink-away out
  
  -- animation tuning
  maxScale        = 1.15,    -- <<< size of bounce
  rippleCount     = 4,       -- <<< number of ripples
  rippleWidth     = 4,       -- <<< width of ripples
  rippleDuration  = 3,     -- <<< how long ripples stay visible (sec)
  rippleSpeed     = 7,    -- <<< outward speed (pixels per second)
  
  permanentRippleOffset = 8,  -- <<< size of “permanent ripple”
  permanentRippleWidth  = 7, -- <<< stroke width of permanent ripple
  
  minHopDistance  = 140,            -- <<< min distance between hops (pixels)
  -- area to avoid (buttons block)
  -- menu button block avoidance (updated layout)
  avoidOrigin = vec2(WIDTH/2, HEIGHT/2 + 20),
  avoidW            = 320,
  avoidH            = 300,
  showDebugRect    = false,
  
  -- internal last position (for minHopDistance)
  lastX           = nil,
  lastY           = nil,
  
  rotationDegRange = 40,     -- <<< max random tilt in degrees
  rotation        = 0,       -- set per hop
  rotationDir     = 1,       -- +1 or -1; alternates each hop
}

pendingMatchCount = pendingMatchCount or 0

function pointInsideAvoidRect(px, py)
  local o   = matchBadge.avoidOrigin
  local hw  = (matchBadge.avoidW or 0) * 0.5
  local hh  = (matchBadge.avoidH or 0) * 0.5
  
  return (px >= o.x - hw and px <= o.x + hw
  and py >= o.y - hh and py <= o.y + hh)
end

function pickMatchBadgePosition()
  local mb   = matchBadge
  local r    = mb.radius
  local pad  = 20
  
  local safeTop = getTopSafeY()
  local safeBot = getBottomSafeY()
  
  local minX = r + pad
  local maxX = WIDTH  - r - pad
  local minY = safeBot + r + pad
  local maxY = safeTop - r - 80
  
  -- last position memory
  local lastX = mb.x
  local lastY = mb.y
  
  -- minimum hop distance before accepting a new location
  local minHopDist = r * 2 + 10
  
  -- Try multiple times to find a valid point
  for _ = 1, 40 do
    local x = math.random(minX, maxX)
    local y = math.random(minY, maxY)
    
    -- avoid rect check
    if not pointInsideAvoidRect(x, y) then
      -- not too close to last spot
      if lastX == 0 and lastY == 0 then
        -- first run, accept
        mb.x, mb.y = x, y
        break
      else
        local dx = x - lastX
        local dy = y - lastY
        if dx*dx + dy*dy >= minHopDist * minHopDist then
          mb.x, mb.y = x, y
          break
        end
      end
    end
  end
  
  -- alternating tilt: right, left, right, left...
  local range = mb.rotationDegRange or 0
  if range > 0 then
    -- which side this hop should lean to
    local dir = mb.rotationDir or 1      -- +1 = right, -1 = left
    
    -- random magnitude on that side only
    local mag = (math.random(1000) / 1000) * range
    
    -- avoid “almost straight” angles
    local minMag = range * 0.35
    if mag < minMag then
      mag = minMag
    end
    
    mb.rotation   = dir * mag
    mb.rotationDir = -dir                -- flip for next hop
  else
    mb.rotation   = 0
    mb.rotationDir = 1
  end
end

function activateMatchBadge()
  matchBadge.active    = true
  matchBadge.phase     = "visible"
  matchBadge.phaseTime = 0
  pickMatchBadgePosition()
end

function deactivateMatchBadge()
  matchBadge.active    = false
  matchBadge.phase     = "hidden"
  matchBadge.phaseTime = 0
end

-- Call this from your Game Center layer whenever the number of
-- pending turn-based matches changes.
-- list of stored turn-based matches waiting for you
pendingTurnMatches = pendingTurnMatches or {}  -- each entry = qMatch or summary

function updateMatchBadge(dt)
  -- Only show/hop the badge on the menu
  if state ~= STATE_MENU then
    deactivateMatchBadge()
    return
  end
  
  -- See if there are any pending matches
  local hasAny = pendingTurnMatches and #pendingTurnMatches > 0
  
  if not hasAny then
    -- No matches → make sure badge is off and bail.
    deactivateMatchBadge()
    return
  end
  
  -- We *do* have matches. If badge wasn't active, start it up.
  if not matchBadge.active then
    activateMatchBadge()
  end
  
  -- === existing animation logic below this stays the same ===
  matchBadge.phaseTime = matchBadge.phaseTime + dt
  
  if matchBadge.phase == "visible" then
    if matchBadge.phaseTime >= matchBadge.visibleDuration then
      matchBadge.phase = "hidden"
      matchBadge.phaseTime = 0
    end
  else -- "hidden"
    if matchBadge.phaseTime >= matchBadge.hiddenDuration then
      matchBadge.phase = "visible"
      matchBadge.phaseTime = 0
      pickMatchBadgePosition()
    end
  end
end

function drawMatchBadge()
  if state ~= STATE_MENU then return end
  if not matchBadge.active then return end
  if matchBadge.phase ~= "visible" then return end
  
  local mb = matchBadge
  local x, y = mb.x, mb.y
  local r    = mb.radius
  
  -- <<< DEBUG: draw avoid rect in world space (no rotation) >>>
  if mb.showDebugRect == true then
    pushStyle()
    rectMode(CENTER)
    noFill()
    stroke(255, 255, 0, 150)
    strokeWidth(8)
    rect(mb.avoidOrigin.x, mb.avoidOrigin.y, mb.avoidW, mb.avoidH)
    popStyle()
  end
  
  local t          = mb.phaseTime or 0
  local appear     = mb.appearDuration or 0.25
  local disappear  = mb.disappearDuration or 0.25
  local visibleDur = mb.visibleDuration or (appear + disappear + 0.2)
  
  local maxScale   = mb.maxScale or 1.25
  local scale      = 1.0
  local alpha      = 255
  
  -- phase: pop-in, steady, shrink-out
  if t < appear then
    -- pop / bounce
    local a = math.min(t / appear, 1.0)
    scale = maxScale - (maxScale - 1.0) * a
  elseif t > visibleDur - disappear then
    -- shrink-away
    local d = math.min((t - (visibleDur - disappear)) / disappear, 1.0)
    scale = 1.0 - d
    if scale < 0.0 then scale = 0.0 end
    alpha = 255 * (1.0 - d)
  else
    scale = 1.0
  end
  
  pushStyle()
  pushMatrix()
  
  translate(x, y)
  rotate(matchBadge.rotation or 0)   -- Codea rotate() uses degrees
  
  ------------------------------------------------
  -- Ripple rings (expand + fade, lifetime-based)
  ------------------------------------------------
  
  do
    if t < visibleDur - disappear then 
      local rippleCount = mb.rippleCount or 0
      local duration    = mb.rippleDuration or 0.6   -- sec
      local rWidth      = mb.rippleWidth or 3
      local speed       = mb.rippleSpeed or 90.0     -- px / sec
      
      if rippleCount > 0 then
        -- stagger start times so ripples chase each other
        local stepDelay = duration / math.max(rippleCount, 1)
        
        for i = 1, rippleCount do
          local startTime = (i - 1) * stepDelay
          local age       = t - startTime
          
          if age > 0 and age < duration then
            local rr    = r + age * speed
            local fade  = 1.0 - (age / duration)
            local aRip  = 220 * fade
            
            noFill()
            stroke(230, 40, 40, aRip)
            strokeWidth(rWidth)
            ellipse(0, 0, rr * 2, rr * 2)
          end
        end
      end
    end
  end
  
  ------------------------------------------------
  -- Permanent thin ripple around the badge
  ------------------------------------------------
  do
    local off   = mb.permanentRippleOffset or 12
    local width = mb.permanentRippleWidth or 1.0
    noFill()
    stroke(230, 40, 40, alpha * 0.55)
    strokeWidth(width)
    ellipse(0, 0, (r + off) * 2 * scale, (r + off) * 2 * scale)
  end
  
  ------------------------------------------------
  -- Main badge (ellipse) with bounce + shrink
  ------------------------------------------------
  noStroke()
  fill(230, 40, 40, alpha)
  ellipse(0, 0, r * 2 * scale, r * 2 * scale)
  
  ------------------------------------------------
  -- Text (singular/plural)
  ------------------------------------------------
  local matchCount = pendingTurnMatches and #pendingTurnMatches or 0
  local label
  if matchCount <= 1 then
    label = "MATCH\nREADY\nTAP HERE"
  else
    label = "MATCHES\nREADY\nTAP HERE"
  end
  
  fill(255, 255, 255, alpha)
  textMode(CENTER)
  textAlign(CENTER)
  fontSize(14 * scale)
  font("Baskerville-SemiBold")   -- adjust if Codea wants a slightly different name
  text(label, 0, 0)
  
  popMatrix()
  popStyle()
end

function handleMatchBadgeTouch(t)
  if state ~= STATE_MENU then return false end
  if not matchBadge.active then return false end
  if matchBadge.phase ~= "visible" then return false end
  if recordsOverlay then return false end
  if t.state ~= BEGAN then return false end
  
  local dx = t.x - matchBadge.x
  local dy = t.y - matchBadge.y
  local r  = matchBadge.radius
  
  if dx*dx + dy*dy <= r*r then
    -- Delegate selection back to Game Center
    if tbm and tbm.showMatchmaker then
      tbm:showMatchmaker()
    end
    return true
  end
  
  return false
end