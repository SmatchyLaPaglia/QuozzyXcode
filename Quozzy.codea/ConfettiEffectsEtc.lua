-- Season transition + confetti
seasonTransition = seasonTransition or nil
confetti         = confetti or {}
confettiActive   = confettiActive or false

CONFETTI_FALL_SCALE = 1.2  -- < 1.0 = slower, > 1.0 = faster

genericConfettiEmoji = { "🎉", "✨", "⭐️", "🎊", "💫" }

SeasonConfettiEmoji = {
    Spring = { "🌸", "🌷", "🌱", "🐣" },
    Summer = { "☀️", "🍉", "🌊", "🕶" },
    Autumn = { "🍂", "🍁", "🎃", "🌰" },
    Winter = { "❄️", "⛄️", "🎄", "🧣" },
}

-- Depth illusion for the season-change confetti burst, WITHOUT blur (dropped 2026-09-27 —
-- see STRUCTURE.md "Confetti depth-blur": two independent render-to-texture blur attempts
-- both misbehaved in this environment, one freezing the app for 90+ seconds). Depth reads
-- instead through size + fall speed varying together and continuously (not three fixed
-- tiers): each particle gets one random depth in [0,1], biased toward 0 (far) so a burst
-- has more small distant pieces than huge near ones, same way real depth scatter looks.
-- Bigger == nearer == falls (and drifts, spins) faster, a simple parallax cue. Particles
-- are sorted by depth once at spawn (never re-sorted; removal preserves relative order) so
-- nearer/bigger ones draw on top of farther/smaller ones without a per-frame sort.
CONFETTI_SIZE_MIN = 20
CONFETTI_SIZE_MAX = 150
CONFETTI_FALL_SPEED_MIN_SCALE = 0.55  -- far particles fall at this fraction of the base speed
CONFETTI_FALL_SPEED_MAX_SCALE = 2.0   -- near particles fall up to this many times as fast

local function drawDepthEmoji(ch, size, baseAlpha)
    fontSize(size)
    fill(255, 255, 255, baseAlpha)
    text(ch, 0, 0)
end

Sparkler = {
    spawnFrequency = 6.5,      -- particles per step
    spawnSize      = 32.77,     -- base emoji size (actual size varies ±)
    maxVelocity    = 629.6,    -- how fast sparkles can shoot
    maxSpin        = 10,    -- rotation speed range
    maxDistance    = 533.62,    -- how far they travel before drag kills velocity
    timeBeforeFade = 0.05,    -- delay before transparency starts decreasing
    fadeEaseOut    = 2.2,    -- exponent controlling fade curve (2 = smooth)
}

pathParticles = pathParticles or {}

function spawnPathParticles(x, y)
    local seasonName = seasons[seasonIndex] or "Spring"
    local seasonal   = SeasonConfettiEmoji[seasonName] or {}
    
    local pool = {}
    for _, v in ipairs(seasonal) do pool[#pool+1] = v end
    for _, v in ipairs(genericConfettiEmoji) do pool[#pool+1] = v end
    if #pool == 0 then pool[1] = "✨" end
    
    -- safety: make sure we loop an integer number of times
    local freq = math.max(0, math.floor(Sparkler.spawnFrequency or 0))
    if freq == 0 then return end
    
    -- integer versions of the tunables where needed
    local maxVelInt  = math.max(1, math.floor(Sparkler.maxVelocity or 1))
    local maxSpinInt = math.max(0, math.floor(Sparkler.maxSpin or 0))
    local baseSize   = Sparkler.spawnSize or 20
    local sizeJitter = math.max(0, math.floor(baseSize * 0.5))
    local maxDist    = Sparkler.maxDistance or 0  -- 0 = no clamp
    
    for i = 1, freq do
        local ch = pool[math.random(1, #pool)]
        
        -- random direction: angle in [0, ~2π]
        local angle = math.random(0, 6283) / 1000.0  -- 0..6.283
        
        -- speed limited by maxVelocity (int)
        local speed = math.random(1, maxVelInt)
        
        -- random lifetime (float 0..1)
        local rand01 = math.random(0, 1000) / 1000.0
        local maxLife = (Sparkler.timeBeforeFade or 0.4) + rand01 * 0.8
        
        -- optional clamp by maxDistance (roughly)
        if maxDist > 0 then
            local dist = speed * maxLife
            if dist > maxDist then
                local scale = maxDist / dist
                speed = speed * scale
            end
        end
        
        local vx = math.cos(angle) * speed
        local vy = math.sin(angle) * speed
        
        -- rotation + spin
        local rot  = math.random(0, 360)
        local vrot = 0
        if maxSpinInt > 0 then
            vrot = math.random(-maxSpinInt, maxSpinInt)
        end
        
        -- size with integer jitter
        local jitter = sizeJitter > 0 and math.random(0, sizeJitter) or 0
        local size   = baseSize + jitter
        
        pathParticles[#pathParticles+1] = {
            x       = x,
            y       = y,
            vx      = vx,
            vy      = vy,
            rot     = rot,
            vrot    = vrot,
            size    = size,
            life    = 0,
            maxLife = maxLife,
            char    = ch,
        }
    end
end

function updatePathParticles(dt)
    if #pathParticles == 0 then return end
    
    local drag = Sparkler.maxVelocity / Sparkler.maxDistance -- determines slowdown
    local gravity = 20 -- subtle downward drift
    
    for i = #pathParticles, 1, -1 do
        local p = pathParticles[i]
        p.life = p.life + dt
        
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt
        
        -- drag based on distance control
        local damp = math.max(0, 1 - drag * dt)
        p.vx = p.vx * damp
        p.vy = p.vy * damp - gravity * dt
        
        p.rot = p.rot + p.vrot * dt
        
        if p.life >= p.maxLife then
            table.remove(pathParticles, i)
        end
    end
end

function drawPathParticles()
    if #pathParticles == 0 then return end
    
    pushStyle()
    textMode(CENTER)
    
    for _, p in ipairs(pathParticles) do
        -- fade starts after timeBeforeFade
        local t = p.life
        local fadeT = 0
        
        if t > Sparkler.timeBeforeFade then
            fadeT = (t - Sparkler.timeBeforeFade) / (p.maxLife - Sparkler.timeBeforeFade)
            fadeT = math.min(1, fadeT)
        end
        
        -- ease-out fade curve
        local alpha = 255 * (1 - (fadeT ^ Sparkler.fadeEaseOut))
        
        pushMatrix()
        translate(p.x, p.y)
        rotate(p.rot)
        fontSize(p.size)
        fill(255, 255, 255, alpha)
        text(p.char, 0, 0)
        popMatrix()
    end
    
    popStyle()
end

function startSeasonTransition()
    if seasonTransition and seasonTransition.active then return end
    
    local fromIndex = seasonIndex
    local toIndex   = seasonIndex % #seasons + 1
    
    -- snapshot current effective palette as "from"
    local fromPalette = {}
    for k, v in pairs(Color) do
        if type(v) == "userdata" then  -- color in Codea
            fromPalette[k] = color(v.r, v.g, v.b, v.a)
        end
    end
    
    local toPalette = buildEffectivePaletteForSeason(toIndex)
    
    seasonTransition = {
        active       = true,
        t            = 0,
        duration     = 0.7,   -- fade time
        totalTime    = 1.6,   -- fade + confetti tail
        fromIndex    = fromIndex,
        toIndex      = toIndex,
        fromPalette  = fromPalette,
        toPalette    = toPalette,
        switched     = false,
        totalElapsed = 0,
    }
    
    -- build confetti
    confetti = {}
    confettiActive = true
    
    local seasonName = seasons[toIndex]
    local pool = {}
    local seasonal = SeasonConfettiEmoji[seasonName] or {}
    for i = 1, #seasonal do
        pool[#pool+1] = seasonal[i]
    end
    for i = 1, #genericConfettiEmoji do
        pool[#pool+1] = genericConfettiEmoji[i]
    end
    if #pool == 0 then
        pool = { "🎉" }
    end
    
    local count = 80
    local maxYOffset = math.floor(HEIGHT * 0.4)
    if maxYOffset < 0 then maxYOffset = 0 end
    for i = 1, count do
        local ch = pool[(i - 1) % #pool + 1]
        local depth = math.random() ^ 1.4  -- biased toward 0 (far/small) — see comment above
        local speedScale = CONFETTI_FALL_SPEED_MIN_SCALE
            + (CONFETTI_FALL_SPEED_MAX_SCALE - CONFETTI_FALL_SPEED_MIN_SCALE) * depth
        confetti[i] = {
            x     = math.random() * WIDTH,
            y     = HEIGHT + math.random(0, maxYOffset),
            vx    = (math.random() - 0.5) * 60 * speedScale,
            vy    = - (70 + math.random() * 100) * speedScale,
            rot   = math.random() * 360,
            vrot  = (math.random() - 0.5) * 180 * (0.7 + 0.6 * depth),
            size  = CONFETTI_SIZE_MIN + (CONFETTI_SIZE_MAX - CONFETTI_SIZE_MIN) * depth,
            depth = depth,
            char  = ch,
            life  = 0,
        }
    end
    -- Sort once, far-to-near, so drawConfetti can draw in table order (nearer/bigger pieces
    -- correctly overlap farther/smaller ones) with no per-frame sort. table.remove in
    -- updateConfetti shifts survivors down without reordering them, so this sort holds for
    -- the burst's whole life.
    table.sort(confetti, function(a, b) return a.depth < b.depth end)
    resetPoofingText()
end

function updateSeasonTransition(dt)
    if not seasonTransition or not seasonTransition.active then return end
    local tr = seasonTransition
    
    tr.t = tr.t + dt
    tr.totalElapsed = tr.totalElapsed + dt
    
    local t = tr.t / tr.duration
    if t > 1 then t = 1 end
    
    -- blend palette into Color
    for k, from in pairs(tr.fromPalette) do
        local to = tr.toPalette[k] or from
        Color[k] = color(
        from.r + (to.r - from.r) * t,
        from.g + (to.g - from.g) * t,
        from.b + (to.b - from.b) * t,
        from.a + (to.a - from.a) * t
        )
    end
    for k, to in pairs(tr.toPalette) do
        if not tr.fromPalette[k] then
            Color[k] = color(to.r, to.g, to.b, to.a)
        end
    end
    
    -- once colors are fully at the new palette, lock in season and go to menu
    if not tr.switched and t >= 1 then
        seasonIndex = tr.toIndex
        rebuildOverlayPanelsForSeason()
        saveSeasonIndex(seasonIndex)
        tr.switched = true
        nextHaiku()
        state = STATE_MENU

        -- Deferred rematch: the end-screen rematch button sets this flag and
        -- starts this same transition to dispose of itself. Matchmaking must
        -- not fire until state has actually settled on STATE_MENU, or the
        -- transition's own completion (right here) would stomp a freshly
        -- started match's state back to STATE_MENU underneath it.
        if pendingRematchAfterEndScreenExit then
            pendingRematchAfterEndScreenExit = false
            if startLastMatchReplayFromMenu then startLastMatchReplayFromMenu() end
        end
    end
    
    if tr.totalElapsed >= tr.totalTime then
        tr.active = false
    end
end

function updateConfetti(dt)
    if not confettiActive then return end
    
    for i = #confetti, 1, -1 do
        local p = confetti[i]
        p.life = p.life + dt
        p.x = p.x + p.vx * dt
        p.y = p.y + p.vy * dt * CONFETTI_FALL_SCALE
        p.rot = p.rot + p.vrot * dt
        
        if p.y < -50 then
            table.remove(confetti, i)
        end
    end
    
    if #confetti == 0 then
        confettiActive = false
    end
end

function drawConfetti()
    if not confettiActive then return end

    pushStyle()
    textMode(CENTER)

    -- Table order is already far-to-near (sorted once at spawn — see startSeasonTransition),
    -- so nearer/bigger pieces draw on top of farther/smaller ones with no per-frame sort.
    for i = 1, #confetti do
        local p = confetti[i]
        pushMatrix()
        translate(p.x, p.y)
        rotate(p.rot)
        drawDepthEmoji(p.char, p.size, 255)
        popMatrix()
    end

    popStyle()
end