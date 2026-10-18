------------------------------------------------------------
-- MENU LAYOUT (2026-10-11) — one pure function that places every main-menu element for any
-- phone screen. Design for RATIO, not pixels: every number below is a ratio measured on a
-- reference screen (390 x 844 ≈ iPhone 16e / 17, which are within 1% of each other) and applied
-- to the real WIDTH x HEIGHT.
--
-- The GAME BOARD is the anchor:
--   * bbox width = REF_BBOX_W_FRAC of the screen width (the board's rotated bounding box is
--     ~3/4 of the width on the reference), its bottom sits at a fixed fraction of the height,
--     its right edge keeps a fixed margin. If the season band above it would get too short for
--     a comfortable haiku (BAND_MIN_FRAC), the board shrinks until it fits.
--   * The "board" plate is a fixed ratio of the board's bbox, in size and in offset from the
--     bbox centre (it overlaps the bbox's left edge by the same amount as on the reference).
--     The "min. letters" plate is the SAME size; the "game types" plate is a fixed ratio of the
--     board plate. Fonts scale with the board bbox (see L.plateScale).
--   * The season plate fills the space between the safe-area top and the board's bbox top.
-- Everything below the board is a fixed fraction of the HEIGHT (MENU_ROWS, the same section
-- stack the menu always used); the min. letters plate is placed against the dice row and the
-- game types plate against the first play button, at the offsets measured on the reference.
--
-- Coordinates are Codea's (y up, origin bottom-left); every rect is {cx, cy, w, h} (centre-based).
------------------------------------------------------------

-- Section heights, fractions of HEIGHT, stacked bottom-up (disclaimer at the very bottom).
-- The title row (0.22) and board row (0.33) above them are gone: the board and season plate
-- are placed from the anchor below instead. HaikuMenu's getSectionBoundaries reads these.
MENU_ROWS = { disclaimer = 0.06, info = 0.07, play = 0.13, dice = 0.14 }

-- Reference measurements, taken on the 390 x 844 layout the plates were tuned on.
local REF_BBOX            = 282.4    -- board bbox side (5x5, 8° tilt), points
local REF_BBOX_W_FRAC     = 282.4 / 390
local REF_BBOX_BOT_FRAC   = 335.7 / 844     -- bbox bottom, fraction of H
local REF_BBOX_RIGHT_MARG = 7.8 / 390       -- gap from bbox right edge to screen edge, fraction of W

-- board plate, relative to the bbox centre; all in units of the bbox side
local PLATE_W   = 131 / REF_BBOX
local PLATE_H   = 88 / REF_BBOX
local BPLATE_DX = -139.5 / REF_BBOX
local BPLATE_DY = 84.1 / REF_BBOX
-- min. letters plate: same size; x as a fraction of W, y relative to the dice row centre
local DPLATE_X_FRAC = 268.5 / 390
local DPLATE_DY     = 8.54 / REF_BBOX
-- game types plate: size in bbox units; offset from the first play button, in button w / h
local GPLATE_W  = 137 / REF_BBOX
local GPLATE_H  = 47 / REF_BBOX
local GPLATE_DX = -48.91 / 75.58            -- / button width
local GPLATE_DY = 48.92 / 92.17             -- / button height
-- season plate
local SEASON_MARGIN_FRAC = 20 / 390         -- left/right margin, fraction of W
local SEASON_H_MAX       = 137 / REF_BBOX   -- max height, bbox units
local SEASON_FILL        = 0.766            -- plate height / space between safe top and bbox top
local SEASON_BELOW_SHARE = 0.68             -- share of the leftover that sits BELOW the plate
local BAND_MIN_FRAC      = 0.17             -- min space (fraction of H) between safe top and bbox top

local function rowBottoms()
  local r = MENU_ROWS
  local info  = r.disclaimer
  local play  = info + r.info
  local dice  = play + r.play
  local top   = dice + r.dice
  return { info = info, play = play, dice = dice, top = top }
end

-- W, H: screen size. topInset: points reserved at the top (notch / island / status bar).
-- tiltDeg: the board's static tilt. hasReplay: three play buttons instead of two.
function computeMenuLayout(W, H, topInset, tiltDeg, hasReplay)
  local L = { W = W, H = H }
  local rb = rowBottoms()

  -- BOARD (anchor)
  local ang = math.rad(math.abs(tiltDeg or 8))
  local k = math.cos(ang) + math.sin(ang)          -- bbox side / square side
  local bbBottom = REF_BBOX_BOT_FRAC * H
  local bbW = REF_BBOX_W_FRAC * W
  local topEdge = H - topInset                     -- y of the lowest thing allowed at the top
  local maxBBTop = topEdge - BAND_MIN_FRAC * H
  if bbBottom + bbW > maxBBTop then bbW = math.max(maxBBTop - bbBottom, 40) end
  local bcx = W - REF_BBOX_RIGHT_MARG * W - bbW * 0.5
  local bcy = bbBottom + bbW * 0.5
  L.board = { cx = bcx, cy = bcy, bbox = bbW, side = bbW / k, top = bbBottom + bbW, bottom = bbBottom }
  L.plateScale = bbW / REF_BBOX                    -- reference points -> screen points for plate sizes/fonts

  -- BOARD PLATE
  L.boardPlate = { cx = bcx + BPLATE_DX * bbW, cy = bcy + BPLATE_DY * bbW, w = PLATE_W * bbW, h = PLATE_H * bbW }

  -- SEASON PLATE + haiku band
  local avail = math.max(topEdge - L.board.top, 20)
  local sh = math.min(SEASON_H_MAX * bbW, avail * SEASON_FILL)
  local sBottom = L.board.top + (avail - sh) * SEASON_BELOW_SHARE
  L.season = { cx = W * 0.5, cy = sBottom + sh * 0.5, w = W * (1 - 2 * SEASON_MARGIN_FRAC), h = sh }
  L.haikuCy = (topEdge + L.board.top) * 0.5
  L.topEdge = topEdge

  -- DICE ROW + PLATE
  L.diceCy = rb.top * H - 0.06 * H
  L.diceZone = { yBot = rb.dice * H, yTop = rb.top * H }
  L.dicePlate = { cx = DPLATE_X_FRAC * W, cy = L.diceCy + DPLATE_DY * bbW, w = L.boardPlate.w, h = L.boardPlate.h }

  -- DIFFICULTY BUTTONS (Easy/Normal/Hard): midpoint between the board plate
  -- and the dice (min-letters) plate, same total footprint as one plate,
  -- split into 3 equal side-by-side buttons.
  do
    local midCx = (L.boardPlate.cx + L.dicePlate.cx) * 0.5
    local midCy = (L.boardPlate.cy + L.dicePlate.cy) * 0.5
    local totalW = L.boardPlate.w
    local gap = totalW * 0.05
    local btnW = (totalW - 2 * gap) / 3
    local btnH = L.boardPlate.h * 0.55
    L.difficultyPlates = {
      easy   = { cx = midCx - (btnW + gap), cy = midCy, w = btnW, h = btnH },
      normal = { cx = midCx,                cy = midCy, w = btnW, h = btnH },
      hard   = { cx = midCx + (btnW + gap), cy = midCy, w = btnW, h = btnH },
    }
  end

  -- PLAY BUTTONS (+ game types plate)
  local h4 = MENU_ROWS.play * H
  local bh = h4 * 0.84
  local bw = bh * 0.82
  local gap = W * 0.04
  local count = hasReplay and 3 or 2
  local totalW = count * bw + (count - 1) * gap
  local startX = (W - totalW) * 0.5 + bw * 0.5
  local btnCy = (rb.play + MENU_ROWS.play * 0.5) * H
  L.buttons = { w = bw, h = bh, r = bw * 0.18, gap = gap, cy = btnCy, startX = startX, count = count }
  L.gamePlate = { cx = startX + GPLATE_DX * bw, cy = btnCy + GPLATE_DY * bh, w = GPLATE_W * bbW, h = GPLATE_H * bbW }
  -- with a third (replay) button the first one moves left; keep the plate on screen
  L.gamePlate.cx = math.max(L.gamePlate.cx, L.gamePlate.w * 0.5 + 8)

  return L
end

-- Cached wrapper for the live screen. Rebuilt only when an input changes.
local _lay, _layKey = nil, nil
function menuLayout(hasReplay)
  local H = HEIGHT
  local topSafe = (getTopSafeY and getTopSafeY()) or H
  local inset = math.max(H - topSafe, H * 0.035, 24)
  local tilt = menuBoardTiltDegrees or 8
  local key = table.concat({ WIDTH, H, inset, tilt, hasReplay and 1 or 0 }, ":")
  if key ~= _layKey then
    _lay, _layKey = computeMenuLayout(WIDTH, H, inset, tilt, hasReplay), key
  end
  return _lay
end

-- True when the menu shows the third (replay-last-opponent) play button.
function menuHasReplay()
  local rs = getLastMatchReplaySettings and getLastMatchReplaySettings() or nil
  return (rs and rs.opponentId) and true or false
end
