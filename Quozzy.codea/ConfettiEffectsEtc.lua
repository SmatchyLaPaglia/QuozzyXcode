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

-- Fake depth-of-field for the season-change confetti burst: small+slightly-
-- blurred background, larger sharp midground (the nominal focal plane),
-- largest+most-blurred foreground. Sizes are today's original 24-36 range
-- for the background tier, doubled for midground, and 1.5x-2x of midground
-- for foreground.
CONFETTI_DEPTH_TIERS = {
    { sizeMin = 24, sizeMax = 36,  blur = 0.35 }, -- background
    { sizeMin = 48, sizeMax = 72,  blur = 0.0  }, -- midground, in focus
    { sizeMin = 72, sizeMax = 144, blur = 0.9  }, -- foreground, blurriest
}

-- Real 2D blur via a dense gaussian-weighted sample grid of plain text() copies — no
-- shader, no render target, nothing that can fail silently. blurAmount 0 draws a single
-- normal, fully-sharp copy via text(), same as before.
--
-- TWO different render-to-texture shader blurs were tried and dropped 2026-09-27 (see
-- STRUCTURE.md "Confetti depth-blur" for both, with comparison images):
--   1. A from-scratch two-pass separable gaussian shader — intermittently rendered fully
--      blank for some emoji/timing combinations with no error, and an early version froze
--      the app for 90+ seconds on both the Simulator and a real device.
--   2. The user's own proven "Double Choose" panel-blur shader (downsample-via-sprite()
--      then blur) — reliable for its actual job (blurring an OPAQUE full-screen
--      background), but produces visible colored fringing/noise around a small
--      transparent-edged glyph: confirmed via DevRemote that the artifacts are already
--      present in the plain sprite()-downsample step, before the blur shader even runs —
--      i.e. Codea's GPU minification of alpha-edged content on a freshly-baked texture,
--      not a bug in either shader's math.
-- Given TWO independent render-to-texture approaches both misbehaved in this environment,
-- treat "bake a small transient texture, then GPU-minify or shader it" as unreliable here
-- generally, not just unlucky — this per-draw sample-grid approach has no such step.
local function _buildBlurKernel()
    -- n=2 -> 13 samples (circular-masked 5x5 grid) reads just as convincingly blurred as
    -- n=4's 49 samples (compared side by side via DevRemote) at a quarter of the per-draw
    -- cost — worth keeping low since a burst can have ~50 blurred particles on screen at
    -- once, each needing its own set of text() draws every frame.
    local n = 2                -- samples per axis half-width -> up to (2n+1)^2 = 25 samples
    local sigma = 0.42        -- gaussian sigma, in units of "radius" (tuned by eye)
    local pts = {}
    local total = 0
    for iy = -n, n do
        for ix = -n, n do
            local fx, fy = ix / n, iy / n            -- -1..1
            local d2 = fx * fx + fy * fy
            if d2 <= 1.0 then                         -- circular kernel, not square
                local w = math.exp(-d2 / (2 * sigma * sigma))
                pts[#pts + 1] = { x = fx, y = fy, w = w }
                total = total + w
            end
        end
    end
    for _, p in ipairs(pts) do p.w = p.w / total end   -- normalize: weights sum to 1
    return pts
end
local _blurKernel = _buildBlurKernel()

local function drawDepthEmoji(ch, size, blurAmount, baseAlpha)
    fontSize(size)
    if not blurAmount or blurAmount <= 0 then
        fill(255, 255, 255, baseAlpha)
        text(ch, 0, 0)
        return
    end
    local radius = size * 0.22 * blurAmount
    -- Each sample is a full-glyph copy weighted by the kernel; alpha compositing ("over")
    -- isn't a true weighted average, so scale down overall and let overlap in the dense
    -- center naturally rebuild most of the coverage there — same per-particle alpha budget
    -- as the old ring hack (baseAlpha*0.8 total), just spread over a real 2D disc instead
    -- of a 1D ring.
    for _, p in ipairs(_blurKernel) do
        fill(255, 255, 255, baseAlpha * p.w * 0.8)
        text(ch, p.x * radius, p.y * radius)
    end
    fill(255, 255, 255, baseAlpha * 0.15)
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
    local count = 80
    for i = 1, count do
        local ch = pool[(i - 1) % #pool + 1]
        local depthLayer = math.random(1, 3)
        local tier = CONFETTI_DEPTH_TIERS[depthLayer]
        confetti[i] = {
            x    = math.random() * WIDTH,
            y    = HEIGHT + math.random(0, maxYOffset),
            vx   = (math.random() - 0.5) * 60,
            vy   = - (70 + math.random() * 100),
            rot  = math.random() * 360,
            vrot = (math.random() - 0.5) * 180,
            size = tier.sizeMin + math.random() * (tier.sizeMax - tier.sizeMin),
            blur = tier.blur,
            depthLayer = depthLayer,
            char = ch,
            life = 0,
        }
  end
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
        saveProjectData(SEASON_KEY, seasonIndex)
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

    -- Drawn back-to-front by depth layer (1=background, 3=foreground) so
    -- closer/larger/blurrier pieces correctly overlap farther ones, rather
    -- than in spawn order.
    for layer = 1, 3 do
        for i = 1, #confetti do
            local p = confetti[i]
            if (p.depthLayer or 1) == layer then
                pushMatrix()
                translate(p.x, p.y)
                rotate(p.rot)
                drawDepthEmoji(p.char, p.size, p.blur, 255)
                popMatrix()
            end
        end
    end

    popStyle()
end