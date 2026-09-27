------------------------------------------------------------
-- RIPPLE PICKER (debug overlay, 2026-09-27)
-- Opened via the 🐛 debug button (SHOW_DEBUG_BUTTON, Main.lua). Shows 6 candidate
-- animations for the match-ready badge's "droplet hitting still water" entrance: instead of
-- the badge just appearing and THEN rippling, each variant here starts as a small point that
-- grows into the full badge, with the growth itself reading as the first wave — then once at
-- full size, ripples continue spreading outward exactly like the current shipped ripple.
--
-- CPU-drawn (the same layered-stroke technique as Badges.lua's drawWaterRipple), not the
-- shader — this is a fast-iteration comparison tool, not production code. Once a favorite is
-- picked, port its timing/easing into the real badge (Badges.lua drawQuickStart + either
-- drawWaterRipple or RippleShader.lua's drawShaderRipple).
------------------------------------------------------------

ripplePickerOverlay = ripplePickerOverlay or false

function openRipplePickerOverlay()
  ripplePickerOverlay = true
end

-- Easing functions: input/output both 0..1.
local function easeLinear(p) return p end
local function easeOutCubic(p) return 1 - (1 - p) ^ 3 end
local function easeInOutCubic(p)
  if p < 0.5 then return 4 * p * p * p end
  local f = -2 * p + 2
  return 1 - (f ^ 3) / 2
end
local function easeOutBack(p)
  local c1, c3 = 1.70158, 1.70158 + 1
  local f = p - 1
  return 1 + c3 * f * f * f + c1 * f * f
end

RIPPLE_PICKER_VARIANTS = {
  { name = "1. Linear",        desc = "Steady, constant growth",       growDuration = 0.45, ease = easeLinear,     prePulse = false, edgeGlow = false },
  { name = "2. Splash",        desc = "Fast out, settles at full size", growDuration = 0.50, ease = easeOutCubic,   prePulse = false, edgeGlow = false },
  { name = "3. Smooth",        desc = "Gradual, cinematic",              growDuration = 0.65, ease = easeInOutCubic, prePulse = false, edgeGlow = false },
  { name = "4. Surface\nTension", desc = "Overshoots, settles back",    growDuration = 0.50, ease = easeOutBack,    prePulse = false, edgeGlow = false },
  { name = "5. Pre-Flash",     desc = "Tiny flash, then splash-grows",   growDuration = 0.45, ease = easeOutCubic,   prePulse = true,  edgeGlow = false },
  { name = "6. Splash + Glow", desc = "Splash-grow with a soft edge",    growDuration = 0.55, ease = easeOutCubic,   prePulse = false, edgeGlow = true  },
}

RIPPLE_PICKER_LOOP = 3.2   -- seconds per demo loop (grow + a few ripple cycles, then restart)

local RIPPLE_PICKER_SOFT_LAYERS = {
  { -6, 3, 0.30 },
  {  0, 4, 1.00 },
  {  6, 3, 0.30 },
}

local function drawSoftRing(cx, cy, radius, ripColor, alphaFrac)
  if radius <= 0 or alphaFrac <= 0.01 then return end
  for _, layer in ipairs(RIPPLE_PICKER_SOFT_LAYERS) do
    local r2 = radius + layer[1]
    if r2 > 0 then
      strokeWidth(layer[2])
      stroke(ripColor.r, ripColor.g, ripColor.b, ripColor.a * alphaFrac * layer[3])
      ellipse(cx, cy, r2 * 2, r2 * 2)
    end
  end
end

-- Droplet-grow, then continuous outward ripples — see file header. r = the badge's full
-- (settled) radius; loopT = time since this demo's own loop restarted.
local function drawGrowingRipple(cx, cy, loopT, r, variant, ripColor)
  local maxRadius = r * 3.2

  pushStyle()
  noFill()
  lineCapMode(ROUND)
  ellipseMode(CENTER)

  if variant.prePulse and loopT < 0.12 then
    local p = loopT / 0.12
    drawSoftRing(cx, cy, r * 0.6 * p, ripColor, (1 - p) * 0.6)
  end

  local growStart = variant.prePulse and 0.10 or 0
  local growT = loopT - growStart
  local discR

  if growT < 0 then
    discR = 0
  elseif growT < variant.growDuration then
    local p = growT / variant.growDuration
    discR = r * math.max(0, variant.ease(p))
    if variant.edgeGlow then
      drawSoftRing(cx, cy, discR, ripColor, 0.7)
    end
  else
    discR = r
    local rippleT = growT - variant.growDuration
    local cycle = maxRadius + RIPPLE_RING_SPACING * RIPPLE_RING_COUNT
    for i = 0, RIPPLE_RING_COUNT - 1 do
      local phase = (rippleT * RIPPLE_RING_SPEED - i * RIPPLE_RING_SPACING) % cycle
      local fade = math.max(0, 1 - phase / maxRadius)
      fade = fade * fade
      drawSoftRing(cx, cy, phase, ripColor, fade)
    end
  end

  if discR > 0 then
    noStroke()
    fill(ripColor.r, ripColor.g, ripColor.b, 255)
    ellipse(cx, cy, discR * 2, discR * 2)
  end

  popStyle()
end

local ripplePickerGeom = nil

function drawRipplePickerOverlay()
  if not ripplePickerOverlay then return end

  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)
  popStyle()

  local panelW = WIDTH - 32
  local panelH = HEIGHT - 110
  local panelX = WIDTH * 0.5
  local panelY = HEIGHT * 0.5
  panelY, panelH = clampPanelTopToSafeArea(panelY, panelH)

  pushStyle()
  rectMode(CENTER)
  noStroke()
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)
  popStyle()

  local innerPadding = 20
  local innerLeft   = panelX - panelW / 2 + innerPadding
  local innerRight  = panelX + panelW / 2 - innerPadding
  local innerTop    = panelY + panelH / 2 - innerPadding
  local innerBottom = panelY - panelH / 2 + innerPadding
  local innerWidth  = innerRight - innerLeft

  pushStyle()
  local tileText = Color.tileText or color(255)

  fill(tileText)
  font("Georgia-Bold")
  fontSize(24)
  textMode(CORNER)
  textAlign(CENTER)
  local title = "Ripple Picker"
  text(title, panelX - textSize(title) * 0.5, innerTop - 26)

  local btnW, btnH = 200, 48
  local btnX = panelX
  local btnY = innerBottom + btnH / 2
  drawButton(btnX, btnY, btnW, btnH, "Close", false)

  local gridTop    = innerTop - 56
  local gridBottom = btnY + btnH / 2 + 16
  local gridHeight = gridTop - gridBottom
  local cols, rows = 2, 3
  local colW = innerWidth / cols
  local rowH = gridHeight / rows
  local ripColor = color(230, 40, 40, 255)
  local demoR = math.min(colW, rowH) * 0.16

  local t = ElapsedTime % RIPPLE_PICKER_LOOP

  for i, variant in ipairs(RIPPLE_PICKER_VARIANTS) do
    local col = (i - 1) % cols
    local row = math.floor((i - 1) / cols)
    local cx = innerLeft + colW * (col + 0.5)
    local cy = gridTop - rowH * (row + 0.35)

    drawGrowingRipple(cx, cy, t, demoR, variant, ripColor)

    fill(tileText)
    font("HelveticaNeue-Bold")
    fontSize(15)
    textMode(CENTER)
    textAlign(CENTER)
    text(variant.name, cx, cy - rowH * 0.34)

    fill(tileText.r, tileText.g, tileText.b, 170)
    font("HelveticaNeue-Italic")
    fontSize(12)
    text(variant.desc, cx, cy - rowH * 0.34 - 20)
  end

  popStyle()

  ripplePickerGeom = { btnX = btnX, btnY = btnY, btnW = btnW, btnH = btnH }
end

function handleRipplePickerTouch(t)
  if not ripplePickerOverlay then return false end
  if t.state == ENDED and ripplePickerGeom then
    local g = ripplePickerGeom
    if pointInRect(t.x, t.y, g.btnX, g.btnY, g.btnW, g.btnH) then
      ripplePickerOverlay = false
    end
  end
  return true
end
