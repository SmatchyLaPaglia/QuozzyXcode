function nextHaiku()
  local seasonName = seasons[seasonIndex]
  local key = seasonName and string.lower(seasonName) or nil
  local list = key and haikuBySeason[key] or nil

  if not list or #list == 0 then
    currentHaiku = nil
    return
  end

  currentHaiku = list[math.random(1, #list)]
end

function xPositionToCenterText(aText, fontName, fontSizeValue, centerX)
  pushStyle()

  if fontName then font(fontName) end
  if fontSizeValue then fontSize(fontSizeValue) end

  local w, h = textSize(aText)

  popStyle()

  return centerX - w * 0.5
end

------------------------------------------------------------
-- TEXT-FIT HELPERS (size text to fill a box without overflow)
------------------------------------------------------------

-- Largest font size at which `str` (may be multi-line) fits within availW x availH.
-- Font scaling is linear, so measure once at a reference size and scale.
function menuMeasureFitSize(str, fontName, availW, availH)
  if not str or str == "" or availW <= 0 or availH <= 0 then return 12 end
  local ref = 100
  pushStyle()
  font(fontName)
  fontSize(ref)
  local w, h = textSize(str)
  popStyle()
  if not w or w <= 0 or not h or h <= 0 then return 12 end
  return ref * math.min(availW / w, availH / h)
end

-- Largest font size at which EVERY haiku in `list` fits the box (the biggest one wins).
function menuMaxHaikuFitSize(list, fontName, availW, availH)
  if not list or #list == 0 or availW <= 0 or availH <= 0 then return 14 end
  local ref = 100
  local best = nil
  pushStyle()
  font(fontName)
  fontSize(ref)
  for _, s in ipairs(list) do
    if s and s ~= "" then
      local w, h = textSize(s)
      if w and w > 0 and h and h > 0 then
        local sz = ref * math.min(availW / w, availH / h)
        if not best or sz < best then best = sz end
      end
    end
  end
  popStyle()
  return best or 14
end

------------------------------------------------------------
-- ONE AND ONLY MENU POOF RENDERER
------------------------------------------------------------
function drawMenuSeasonPoof(r)

  ----------------------------------------------------------
  -- Fonts
  ----------------------------------------------------------

  local SEASON_FONT = "HelveticaNeue-LightItalic"
  local HAIKU_FONT  = "Helvetica-Oblique"  -- italic

  ----------------------------------------------------------
  -- Current-season haiku list (same lookup as nextHaiku)
  ----------------------------------------------------------

  local seasonName = seasons[seasonIndex]
  local key  = seasonName and string.lower(seasonName) or nil
  local list = key and haikuBySeason[key] or nil

  -- Reserve a strip at the bottom of the band for the attribution line, and
  -- lift the haiku so haiku + attribution together read as vertically centered.
  local attrZoneH  = r.h * 0.22
  local haikuAreaH = r.h - attrZoneH
  local haikuCy    = r.cy + attrZoneH * 0.5

  ----------------------------------------------------------
  -- Fit sizes, cached per season + area dimensions.
  -- Season name (1 line) fills r; the largest haiku fills the haiku area
  -- (r minus the attribution strip). The season box is capped to keep the
  -- poof raster (512x256) safe.
  ----------------------------------------------------------

  menuFitCache = menuFitCache or {}
  local sig = string.format("%d:%d:%d", seasonIndex or 0, math.floor(r.w), math.floor(r.h))
  local fit = menuFitCache[sig]
  if not fit then
    local seasonBoxW = math.min(r.w, 500)
    local seasonBoxH = math.min(r.h, 248)
    local seasonSize = menuMeasureFitSize(seasonName or "Season", SEASON_FONT, seasonBoxW, seasonBoxH)
    local haikuSize  = list and menuMaxHaikuFitSize(list, HAIKU_FONT, r.w, haikuAreaH) or (haikuAreaH * 0.19)
    fit = { season = math.floor(seasonSize), haiku = math.floor(haikuSize) }
    menuFitCache[sig] = fit
  end

  ----------------------------------------------------------
  -- Build specs.
  -- Season name: CENTER mode + CENTER align at r.cx, r.cy.
  -- Haiku: lines LEFT-justified, but the whole block centered on r.cx, r.cy
  --        via its measured bounds (CORNER anchor at block's bottom-left).
  ----------------------------------------------------------

  menuSpecA = {
    text  = seasonName,
    font  = SEASON_FONT,
    size  = fit.season,
    x     = r.cx,
    y     = r.cy,
    color = Color.uiAccent,
    mode  = CENTER,
    align = CENTER
  }

  local haikuText = (currentHaiku and currentHaiku ~= "" and currentHaiku)
                    or (list and list[1])
                    or "Still-song:\nLeaf alone, fluttering alas ...\nFloating down the wind"

  -- Measure the block so we can left-justify lines yet center the block onscreen
  pushStyle()
  font(HAIKU_FONT)
  fontSize(fit.haiku)
  local hbw, hbh = textSize(haikuText)
  popStyle()
  hbw = hbw or 0
  hbh = hbh or 0

  menuSpecB = {
    text  = haikuText,
    font  = HAIKU_FONT,
    size  = fit.haiku,
    x     = r.cx - hbw * 0.5,
    y     = haikuCy - hbh * 0.5,
    color = Color.menuText,
    mode  = CORNER,
    align = LEFT
  }

  ----------------------------------------------------------
  -- Draw
  ----------------------------------------------------------

  pushStyle()
  drawPoofingText(menuSpecA, menuSpecB)
  popStyle()
  -- (ambient motion around the word is now provided by SeasonFlecks;
  --  the old static drawSeasonScatter dots are no longer drawn)

  -- Generic attribution, beneath the haiku — fades in on the SAME curve as the haiku
  -- itself (TextGoPoof_haikuAlpha), so the two appear together instead of attribution
  -- trailing in on its own separate timer.
  if TextGoPoof_attributionReady() then
    local attrText = "— Japanese Haiku, 17th-19th c."
    local attrSize = math.max(11, math.floor(math.min(fit.haiku * 0.78, attrZoneH * 0.55)))
    pushStyle()
    font(HAIKU_FONT)
    fontSize(attrSize)
    textMode(CENTER)
    textAlign(CENTER)
    local aw, ah = textSize(attrText)
    ah = ah or attrSize
    local haikuBottom = haikuCy - hbh * 0.5
    local gap    = attrSize * 0.6
    local attrCy = haikuBottom - gap - ah * 0.5
    local minCy  = r.y + ah * 0.5 + 2            -- keep inside the band
    if attrCy < minCy then attrCy = minCy end
    local ts = Color.tileStroke
    fill(ts.r, ts.g, ts.b, TextGoPoof_haikuAlpha())
    text(attrText, r.cx, attrCy)
    popStyle()
  end
end

function drawSeasonScatter(r, seed)

  pushStyle()
  fill(Color.uiAccent)
  noStroke()

  local function seededUnit(s, i, salt)
    local v = math.sin((s or 0) * 12.9898 + i * 78.233 + salt * 37.719) * 43758.5453
    return v - math.floor(v)
  end

  local count = 8

  local yCenter = r.cy - r.h * 0.10
  local ySpread = r.h * 0.22
  local xSpread = r.w * 0.45

  for i = 1, count do
    local rx = seededUnit(seed, i, 1) * 2 - 1
    local ry = seededUnit(seed, i, 2) * 2 - 1

    local x = r.cx + rx * xSpread
    local y = yCenter + ry * ySpread

    local d = 2 + math.floor(seededUnit(seed, i, 3) * 4)
    ellipse(x, y, d, d)
  end

  popStyle()
end

-- Six named globals for section height fractions (Codea hot-reload safe with "or")
titleRow       = titleRow       or (0.22)   -- Section 1: Title & Season height fraction (3/4 of original 0.29)
boardRow       = boardRow       or (0.33)   -- Section 2: Board Area height fraction
minLettersRow  = minLettersRow  or (0.14)   -- Section 3: Minimum Dice Area height fraction (3/4 of previous 0.19)
startGameRow   = startGameRow   or (0.13)   -- Section 4: Play Modes height fraction
infoRow        = infoRow        or (0.07)   -- Section 5: Records / Info height fraction
disclaimerRow  = disclaimerRow  or (0.06)   -- Section 6: Disclaimer height fraction
showRowDividers = false  -- toggle pink section boundary lines (off in production)

-- Board preview controls for Section 2 (Codea hot-reload safe with "or")
menuBoardSizeAsPercentOfRow = menuBoardSizeAsPercentOfRow or 0.9   -- 0.0–1.0, fraction of row height the board fills
menuBoardTiltDegrees        = menuBoardTiltDegrees        or 8.0     -- static tilt angle in degrees
menuBoardXOffset            = menuBoardXOffset            or 0     -- horizontal pixel offset from default position
menuBoardRotationAnimationDegrees = menuBoardRotationAnimationDegrees or 1.4  -- rocking amplitude in degrees

-- Min-word-length dice controls for Section 3 (Codea hot-reload safe with "or")
menuDiceSizeAsPercentOfRow       = menuDiceSizeAsPercentOfRow       or 0.61  -- fraction of row height the dice fill
menuDiceTiltDegrees              = menuDiceTiltDegrees              or -5.0  -- static tilt angle in degrees
menuDiceXOffset                  = menuDiceXOffset                  or 0     -- horizontal pixel offset from default position
menuDiceRotationAnimationDegrees = menuDiceRotationAnimationDegrees or 2.5   -- rocking amplitude in degrees

function getSectionBoundaries()
  -- Compute section Y boundaries from the six globals (bottom-up stack)
  local dBottom = 0
  local dBot    = dBottom
  local dTop    = dBot + disclaimerRow
  local iBot    = dTop
  local iTop    = iBot + infoRow
  local sBot    = iTop
  local sTop    = sBot + startGameRow
  local mBot    = sTop
  local mTop    = mBot + minLettersRow
  local bBot    = mTop
  local bTop    = bBot + boardRow
  local tBot    = bTop

  local s = {}
  s[6] = { yBot = dBot * HEIGHT, yTop = dTop * HEIGHT }
  s[5] = { yBot = iBot * HEIGHT, yTop = iTop * HEIGHT }
  s[4] = { yBot = sBot * HEIGHT, yTop = sTop * HEIGHT }
  s[3] = { yBot = mBot * HEIGHT, yTop = mTop * HEIGHT }
  s[2] = { yBot = bBot * HEIGHT, yTop = bTop * HEIGHT }
  s[1] = { yBot = tBot * HEIGHT, yTop = HEIGHT          }
  return s
end

------------------------------------------------------------
-- GENERIC ALERT OVERLAY
-- Usage:
--   showGenericAlert({
--     message = "Are you sure?",
--     avatar  = someSpriteOrNil,
--     buttons = {
--       { text = "yes", callback = function() ... end, isPrimary = true },
--       { text = "no",  callback = function() end },
--     },
--   })
-- Buttons default to isPrimary=true when not specified.
-- All colours come from the seasonal Color palette.
------------------------------------------------------------

function showGenericAlert(config)
  genericAlertActive = true
  genericAlertConfig = config
  genericAlertRects = nil
end

function dismissGenericAlert()
  genericAlertActive = false
  genericAlertConfig = nil
  genericAlertRects = nil
end

function drawGenericAlert()
  if not genericAlertActive then return end

  local config = genericAlertConfig
  if not config or not config.message then
    genericAlertActive = false
    return
  end

  pushStyle()

  -- Dimmed background (seasonal)
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)

  -- Panel
  local margin  = 28
  local panelW  = math.min(WIDTH * 0.86, 560)
  local innerW  = panelW - margin * 2
  local panelX  = WIDTH / 2
  local panelY  = HEIGHT / 2

  local message    = config.message
  local buttons    = config.buttons or {}
  local avatar     = config.avatar
  local bodyFont   = config.bodyFont or 18
  local btnFont    = config.btnFont or 20
  local hasAvatar  = (avatar ~= nil)
  local avatarSize = hasAvatar and 60 or 0
  local avatarGap  = hasAvatar and 12 or 0

  -- Fixed generous panel height (don't rely on textSize for layout)
  local panelH = margin + 120 + 24 + 44 + margin  -- 120px for text+avatar, 44 for buttons

  local left       = panelX - panelW/2 + margin
  local printTop   = panelY + panelH/2 - margin      -- top of printable text area
  local printBot   = panelY + panelH/2 - margin - 120 -- bottom of printable text area

  -- Panel background (seasonal)
  rectMode(CENTER); noStroke()
  local solid = color(Color.panelBG.r, Color.panelBG.g, Color.panelBG.b, 255)
  drawRoundedRect(panelX, panelY, panelW, panelH, 22, solid, solid)

  -- Avatar vertically centered with text area (if provided)
  if hasAvatar then
    local avatarCY = printBot + 60  -- center of text rect
    if drawAvatarCircle then
      drawAvatarCircle(avatar, left + avatarSize/2, avatarCY, avatarSize, nil)
    else
      spriteMode(CENTER)
      sprite(avatar, left + avatarSize/2, avatarCY, avatarSize, avatarSize)
    end
  end

  -- Message text (sized and centered within printable area)
  local textLeft  = left + avatarSize + avatarGap
  local textAreaW = innerW - avatarSize - avatarGap
  fill(Color.tileText or color(255))
  font("Georgia")
  textMode(CENTER)
  textAlign(CENTER)
  textFitToRect(message, textLeft + textAreaW/2, printBot + 60, textAreaW, 120)

  -- Buttons
  local btnAreaTop = panelY - panelH/2 + margin + 44  -- buttons above bottom margin
  local numBtns    = math.max(1, #buttons)
  local gap        = 16
  local btnW       = (innerW - gap * (numBtns - 1)) / numBtns
  local btnH       = 44

  local newRects = {}

  for i, btn in ipairs(buttons) do
    local btnCx = panelX - innerW/2 + btnW/2 + (i - 1) * (btnW + gap)
    local btnCy = btnAreaTop - btnH/2
    local btnKey = "btn" .. i

    local isPrimary = (btn.isPrimary ~= false)
    local isPressed = (pressedButton == btnKey)

    -- Seasonal colours: primary uses uiAccent, secondary blends uiAccent2 toward panelBG
    local fillCol
    if isPrimary then
      fillCol = isPressed and Color.uiAccent2 or Color.uiAccent
    else
      if isPressed then
        fillCol = Color.uiAccent2
      else
        local a2 = Color.uiAccent2
        local bg = Color.panelBG
        fillCol = color(
          a2.r * 0.65 + bg.r * 0.35,
          a2.g * 0.65 + bg.g * 0.35,
          a2.b * 0.65 + bg.b * 0.35,
          255
        )
      end
    end

    drawRoundedRect(btnCx, btnCy, btnW, btnH, 12, fillCol, fillCol)
    fill(255, 255, 255, 255)
    font("Georgia-Bold")
    fontSize(btnFont)
    textMode(CENTER)
    textAlign(CENTER)
    text(btn.text or "", btnCx, btnCy)

    newRects[btnKey] = { cx = btnCx, cy = btnCy, w = btnW, h = btnH, index = i }
  end

  popStyle()

  genericAlertRects = newRects
end

------------------------------------------------------------
-- NEW MENU — 6-SECTION PROPORTIONAL LAYOUT
------------------------------------------------------------

function drawMenu()
  background(Color.bg)

  ------------------------------------------------------------
  -- LAYOUT CONSTANTS
  ------------------------------------------------------------

  local HPAD   = 24
  local innerW = WIDTH - 48

  -- Section Y boundaries from named globals
  local s = getSectionBoundaries()

  local function midY(sec)
    return (s[sec].yBot + s[sec].yTop) * 0.5
  end

  -- Initialize global hit rects for touch handling
  menuHitRects = {}

  ------------------------------------------------------------
  -- SECTION 1 — TITLE & SEASON (HANDOFF §3)
  ------------------------------------------------------------

  pushStyle()

  local h1  = HEIGHT * titleRow
  local cx  = WIDTH * 0.5

  -- The title/season band spans from the top of section 1 (HEIGHT) down to
  -- its bottom boundary. Reserve a safe-area inset at the top and a small
  -- pad at the bottom, then let the text fill what remains.
  local topSafeY  = (getTopSafeY and getTopSafeY()) or HEIGHT
  local topInset  = math.max(HEIGHT - topSafeY, HEIGHT * 0.035, 24)  -- notch/status-bar allowance
  local bottomPad = math.max(h1 * 0.06, 6)

  local areaTop = HEIGHT - topInset
  local areaBot = s[1].yBot + bottomPad
  local areaCy  = (areaTop + areaBot) * 0.5
  local areaH   = math.max(areaTop - areaBot, 8)

  -- Season name / haiku poof area (fills the band, minus insets)
  local seasonRect = {
    cx = cx,
    cy = areaCy,
    x  = cx - innerW * 0.5,
    y  = areaBot,
    w  = innerW,
    h  = areaH
  }

  -- Ambient season flecks, drifting around the word (behind it).
  -- Init lazily and rebuild whenever the season changes.
  if seasonFlecksSeason ~= seasonIndex or #seasonFlecks == 0 then
    initFlecks(seasonRect.cx, seasonRect.cy)
    seasonFlecksSeason = seasonIndex
  end
  local fleckRecycle = (TextGoPoof_state() == "A")
  updateFlecks(seasonRect.cx, seasonRect.cy, fleckRecycle)
  drawFlecks(seasons[seasonIndex], TextGoPoof_flecksFade())

  drawMenuSeasonPoof(seasonRect)

  popStyle()

  ------------------------------------------------------------
  -- SECTION 2 — BOARD AREA (HANDOFF §4)
  ------------------------------------------------------------

  pushStyle()

  local h2       = HEIGHT * boardRow
  local GRID_GAP = 5

  -- Grid center
  local gridCy = midY(2)

  -- Board grid fills the FULL row height (square)
  local gridW = h2 * menuBoardSizeAsPercentOfRow
  local gridH = h2

  -- Derive cell size
  local cellPx = math.max(4, math.floor((gridW - (boardSize - 1) * GRID_GAP) / boardSize))

  -- Recompute exact grid size from cell size
  gridW = boardSize * cellPx + (boardSize - 1) * GRID_GAP
  gridH = gridW

  -- Column split
  local colW       = gridW  -- right column matches grid width
  local leftColW    = innerW - colW
  local rightColCx  = HPAD + leftColW + colW * 0.5

  -- Draw grid preview (right column, with configurable transforms)
  pushMatrix()
  translate(rightColCx + menuBoardXOffset, gridCy)
  -- Board rocking animation: tilt base + sinusoidal rock
  local BOARD_ROCK_PERIOD = 4.3
  local boardAngle = menuBoardTiltDegrees + menuBoardRotationAnimationDegrees * math.sin((ElapsedTime / BOARD_ROCK_PERIOD) * math.pi * 2)
  if boardAngle ~= 0 then
    rotate(-boardAngle)  -- Codea rotate is CCW positive; negate for CW
  end

  -- Preview letters seeded by boardSize + elapsed seconds
  local previewSeed = boardSize * 1000 + math.floor(ElapsedTime)
  local function seededRand(s, i)
    local v = math.sin((s or 0) * 12.9898 + i * 78.233 + 37.719) * 43758.5453
    return v - math.floor(v)
  end

  local gridLeft = -gridW * 0.5
  local gridBot  = -gridH * 0.5

  for row = 1, boardSize do
    for col = 1, boardSize do
      local idx  = (row - 1) * boardSize + col
      local tx   = gridLeft + (col - 0.5) * (cellPx + GRID_GAP)
      local ty   = gridBot  + (row - 0.5) * (cellPx + GRID_GAP)
      local r    = cellPx * 0.15

      drawRoundedRect(tx, ty, cellPx, cellPx, r, Color.uiAccent, Color.uiAccent)

      -- Decorative letter
      local ltrIdx = math.floor(seededRand(previewSeed, idx) * 26) + 1
      local letter = string.sub("ABCDEFGHIJKLMNOPQRSTUVWXYZ", ltrIdx, ltrIdx)

      font("Georgia-Bold")
      fontSize(cellPx * 0.55)
      fill(255, 255, 255, 255)
      textMode(CENTER)
      textAlign(CENTER)
      text(letter, tx, ty)
    end
  end

  popMatrix()

  -- Left column text: "board" centered above "N x N"
  local labelSize  = math.max(9,  math.min(h2 * 0.10, 22))
  local numberSize = math.max(12, math.min(h2 * 0.15, 28))
  local textCx     = HPAD + leftColW * 0.5

  -- Shift whole unit up by its total height + 10px, narrow gap to ~1/3
  local textShift = labelSize + numberSize + 10
  local labelY    = gridCy + textShift + numberSize * 0.2 + 10  -- slight air above the number (+6 for the high-baseline "6" digit)
  local numberY   = gridCy + textShift - numberSize * 0.25

  font("Georgia-Italic")
  fontSize(labelSize)
  fill(Color.uiAccent)
  textMode(CENTER)
  textAlign(CENTER)
  text("board", textCx, labelY)

  font("Georgia-Bold")
  fontSize(numberSize)
  fill(Color.uiAccent)
  local numberStr = boardSize .. " x " .. boardSize
  text(numberStr, textCx, numberY)

  popStyle()

  ------------------------------------------------------------
  -- SECTION 3 — MINIMUM DICE AREA (HANDOFF §5)
  ------------------------------------------------------------

  pushStyle()

  local h3       = HEIGHT * minLettersRow
  local DICE_GAP = 5
  local DICE_TOP_OFFSET = 0.06  -- distance from section top to dice center (fraction of HEIGHT)
  local cy3      = s[3].yTop - DICE_TOP_OFFSET * HEIGHT

  -- Rocking constants (dice still rocks, just no padding constraint)
  local DICE_ROCK_BASE   = menuDiceTiltDegrees
  local DICE_ROCK_AMP    = menuDiceRotationAnimationDegrees
  local DICE_ROCK_PERIOD = 5.1

  -- Width constraint: full inner width (height cap controls max size)
  local diceColW = innerW
  local die5 = (diceColW - 4 * DICE_GAP) / 5
  local die6 = (diceColW - 5 * DICE_GAP) / 6
  local die4 = die5
  local die3 = die4 * 1.13
  local rawDie = ({ [3]=die3, [4]=die4, [5]=die5, [6]=die6 })[MIN_WORD_LEN]

  -- Height cap: limit die size to percentage of row height
  local maxFromH = h3 * menuDiceSizeAsPercentOfRow
  local dicePx = math.max(4, math.floor(math.min(rawDie, maxFromH)))
  local diceRowW = MIN_WORD_LEN * dicePx + (MIN_WORD_LEN - 1) * DICE_GAP

  -- Dice row rocking animation
  local diceAngle = DICE_ROCK_BASE + DICE_ROCK_AMP * math.sin((ElapsedTime / DICE_ROCK_PERIOD) * math.pi * 2)

  -- Layout: dice row (original centering with text column for balance)
  local textColW  = math.min(diceRowW, innerW - diceRowW - 12)
  local totalRowW = diceRowW + 12 + textColW
  local diceRowCx = HPAD + (innerW - totalRowW) * 0.5 + diceRowW * 0.5 + menuDiceXOffset

  -- Draw tilted dice row
  pushMatrix()
  translate(diceRowCx, cy3)
  rotate(diceAngle)  -- negative base means CW tilt in Codea coordinates

  -- Cycle to a new SOWPODS word in sync with the board preview letters
  -- (both reseed on each whole second of ElapsedTime).
  local diceWordSec = math.floor(ElapsedTime)
  if menuDiceWordSec ~= diceWordSec or not menuDiceDisplayWord or #menuDiceDisplayWord ~= MIN_WORD_LEN then
    menuDiceWordSec = diceWordSec
    menuDiceDisplayWord = randomMenuDiceWord(MIN_WORD_LEN)
  end

  local dieRowLeft = -(diceRowW * 0.5)
  for i = 1, MIN_WORD_LEN do
    local dx = dieRowLeft + (i - 0.5) * (dicePx + DICE_GAP)
    local r  = dicePx * 0.15

    drawRoundedRect(dx, 0, dicePx, dicePx, r, Color.uiAccent, Color.uiAccent)

    -- Letter from current SOWPODS word
    local letter = string.sub(menuDiceDisplayWord or string.rep("?", MIN_WORD_LEN), i, i)
    font("Georgia-Bold")
    fontSize(dicePx * 0.5)
    fill(255, 255, 255, 255)
    textMode(CENTER)
    textAlign(CENTER)
    text(letter, dx, 0)
  end

  popMatrix()

  -- Text: "minimum length" + number, vertically centered together
  local diceLabelSize  = math.max(9,  math.min(h3 * 0.12, 20))
  local diceNumberSize = math.max(12, math.min(h3 * 0.18, 26))

  local textX   = HPAD + 4
  local textPad = 6
  local textCY  = s[3].yBot + textPad + diceNumberSize * 0.5  -- vertical center

  -- Measure label first for positioning
  font("Georgia-Italic")
  fontSize(diceLabelSize)
  local labelW, _ = textSize("minimum length")

  -- Label: CENTER mode, positioned so left edge is at textX
  fill(Color.uiAccent)
  textMode(CENTER)
  text("minimum length", textX + labelW * 0.5, textCY)

  -- Number to the right, same vertical center
  font("Georgia-Bold")
  fontSize(diceNumberSize)
  fill(Color.uiAccent)
  textMode(CENTER)
  text(tostring(MIN_WORD_LEN), textX + labelW + 8 + diceNumberSize * 0.4, textCY)

  popStyle()

  ------------------------------------------------------------
  -- SECTION 4 — PLAY MODES (HANDOFF §6)
  ------------------------------------------------------------

  pushStyle()

  local h4     = HEIGHT * startGameRow
  local btnH   = h4 * 0.84
  local btnW   = btnH * 0.82
  local btnR   = btnW * 0.18
  local btnGap = WIDTH * 0.04

  -- Check for last opponent
  local replaySettings = getLastMatchReplaySettings and getLastMatchReplaySettings() or nil
  local hasReplay = replaySettings and replaySettings.opponentId

  -- 2 or 3 buttons
  local buttonCount = hasReplay and 3 or 2
  local totalW = buttonCount * btnW + (buttonCount - 1) * btnGap
  local startX = (WIDTH - totalW) * 0.5 + btnW * 0.5

  local soloCx   = startX
  local vsCx     = startX + btnW + btnGap
  local replayCx = hasReplay and (startX + 2 * (btnW + btnGap)) or nil
  local btn4Cy   = midY(4)

  -- Rocking angles
  local soloAngle   = -8.0 + 2.5 * math.sin((ElapsedTime / 3.7) * math.pi * 2)
  local vsAngle     =  4.0 + 2.5 * math.sin((ElapsedTime / 4.9) * math.pi * 2)
  local replayAngle = -5.0 + 2.5 * math.sin((ElapsedTime / 5.5) * math.pi * 2)

  local labelFontSize = math.min(btnH * 0.28, 30)

  -- Standard button drawing function (for solo and vs)
  local function drawModeButton(cx, cy, angle, label, key)
    pushMatrix()
    translate(cx, cy)
    rotate(angle)
    local fillCol = (pressedButton == key) and Color.uiAccent2 or Color.uiAccent
    drawRoundedRect(0, 0, btnW, btnH, btnR, fillCol, fillCol)
    font("Georgia-Bold")
    fontSize(labelFontSize)
    fill(255, 255, 255, 255)
    textMode(CENTER)
    textAlign(CENTER)
    text(label, 0, 0)
    popMatrix()
  end

  drawModeButton(soloCx, btn4Cy, soloAngle, "solo", "solo")
  drawModeButton(vsCx,   btn4Cy, vsAngle,   "vs",   "vs")

  menuHitRects.solo = { cx = soloCx, cy = btn4Cy, w = btnW, h = btnH }
  menuHitRects.vs   = { cx = vsCx,   cy = btn4Cy, w = btnW, h = btnH }

  if hasReplay then
    -- Avatar button
    pushMatrix()
    translate(replayCx, btn4Cy)
    rotate(replayAngle)

    local fillCol = (pressedButton == "playAgain") and Color.uiAccent2 or Color.uiAccent
    drawRoundedRect(0, 0, btnW, btnH, btnR, fillCol, fillCol)

    -- Draw opponent avatar (smaller, upper portion of the button)
    local avatar = getLastMatchReplayAvatar and getLastMatchReplayAvatar() or nil
    local avatarSize = btnH * 0.48
    local avatarCY   = btnH * 0.20
    if avatar then
      -- Use drawAvatarCircle if available, otherwise fall back to sprite
      if drawAvatarCircle then
        drawAvatarCircle(avatar, 0, avatarCY, avatarSize, nil)
      else
        spriteMode(CENTER)
        sprite(avatar, 0, avatarCY, avatarSize, avatarSize)
      end
    else
      -- Generic opponent placeholder
      if genericOpponentAvatar then
        local genAv = genericOpponentAvatar()
        if genAv and drawAvatarCircle then
          drawAvatarCircle(genAv, 0, avatarCY, avatarSize, nil)
        end
      end
    end

    -- Win/loss standing vs this opponent, as red circles (records-screen style),
    -- separated by a dash: wins - losses.
    local rec    = opponentRecords and opponentRecords[replaySettings.opponentId]
    local wins   = (rec and rec.wins)   or 0
    local losses = (rec and rec.losses) or 0

    local badgeR  = btnH * 0.13
    local sep     = badgeR * 1.5
    local badgesY = -btnH * 0.22
    local leftCx  = -(sep * 0.5 + badgeR)
    local rightCx =  (sep * 0.5 + badgeR)

    -- Win/loss numbers with a dash separator (no circles)
    font("HelveticaNeue-Bold")
    fontSize(badgeR * 1.05)
    fill(255, 255, 255, 255)
    textMode(CENTER)
    textAlign(CENTER)
    text(tostring(wins),   leftCx,  badgesY)
    text(tostring(losses), rightCx, badgesY)

    fontSize(badgeR * 1.5)
    text("-", 0, badgesY)

    popMatrix()

    menuHitRects.playAgain = { cx = replayCx, cy = btn4Cy, w = btnW, h = btnH }
  end

  popStyle()

  ------------------------------------------------------------
  -- SECTION 5 — RECORDS / INFO (HANDOFF §7)
  ------------------------------------------------------------

  pushStyle()

  local h5   = HEIGHT * infoRow
  local pad  = math.max(5, math.min((h5 - 2) * 0.5, 10))
  local btnD = h5 - pad * 2
  local hGap = math.min(math.max(h5 * 0.5, 20), 60)
  local midX = WIDTH * 0.5
  local leftBtnCx  = midX - hGap * 0.5
  local rightBtnCx = midX + hGap * 0.5
  local btn5Cy     = midY(5)

  -- Debug button (far left) — opens the balloon mockup overlay. Dev-only: gated by
  -- SHOW_DEBUG_BUTTON (Main.lua) so it never draws, and never registers a hit rect, in
  -- shipped builds.
  menuHitRects.debugDialog = nil
  if SHOW_DEBUG_BUTTON then
    local debugBtnD = btnD * 0.7
    local debugBtnCx = HPAD + debugBtnD * 0.6
    local debugBtnCy = btn5Cy
    local debugFill = (pressedButton == "debugDialog") and Color.uiAccent2 or Color.uiAccent
    ellipseMode(CENTER)
    fill(debugFill)
    noStroke()
    ellipse(debugBtnCx, btn5Cy, debugBtnD, debugBtnD)
    -- Bug emoji as icon
    fill(255, 255, 255, 255)
    font("Georgia-Bold")
    fontSize(debugBtnD * 0.55)
    textMode(CENTER)
    textAlign(CENTER)
    text("🐛", debugBtnCx, btn5Cy)

    menuHitRects.debugDialog = { cx = debugBtnCx, cy = btn5Cy, w = debugBtnD, h = debugBtnD }
  end

  -- Left button (records) — circular
  local recordsFill = (pressedButton == "records") and Color.uiAccent2 or Color.uiAccent
  ellipseMode(CENTER)
  fill(recordsFill)
  noStroke()
  ellipse(leftBtnCx, btn5Cy, btnD, btnD)

  -- Notebook icon inside left button
  pushMatrix()
  translate(leftBtnCx, btn5Cy)
  local iconH = btnD * 0.7
  local iconW = btnD * 0.55
  local ir    = iconW * 0.15
  drawRoundedRect(0, 0, iconW, iconH, ir, color(255, 255, 255, 255), color(255, 255, 255, 255))
  -- horizontal lines
  stroke(Color.uiAccent)
  strokeWidth(1.5)
  noFill()
  for i = 1, 3 do
    local ly = -iconH * 0.25 + (i - 1) * iconH * 0.25
    line(-iconW * 0.35, ly, iconW * 0.35, ly)
  end
  popMatrix()

  -- Right button (info) — circular
  local infoFill = (pressedButton == "info") and Color.uiAccent2 or Color.uiAccent
  fill(infoFill)
  ellipse(rightBtnCx, btn5Cy, btnD, btnD)

  -- "i" label
  fill(255, 255, 255, 255)
  font("Georgia-Bold")
  fontSize(btnD * 0.6)
  textMode(CENTER)
  textAlign(CENTER)
  text("i", rightBtnCx, btn5Cy)

  -- Store hit rects
  menuHitRects.records = { cx = leftBtnCx,  cy = btn5Cy, w = btnD, h = btnD }
  menuHitRects.info    = { cx = rightBtnCx, cy = btn5Cy, w = btnD, h = btnD }

  popStyle()

  ------------------------------------------------------------
  -- SECTION 6 — DISCLAIMER (HANDOFF §8)
  ------------------------------------------------------------

  pushStyle()

  -- Sized to fill the row (was capped at 14pt, leaving most of h6 as dead space, mostly
  -- ABOVE the text since the two lines centered on cy6 sit close to the bottom safe area).
  -- Anchored from the row's TOP edge instead of centered, so growing the font eats the
  -- padding that used to sit above it rather than pushing further into the bottom margin.
  local h6     = HEIGHT * disclaimerRow
  local ftSize = math.max(12, math.min(h6 * 0.30, 22))
  local cy6    = midY(6)
  local rowTop = cy6 + h6 * 0.5

  font("Georgia-Italic")
  fontSize(ftSize)
  fill(Color.tileText.r, Color.tileText.g, Color.tileText.b, 110)
  textMode(CENTER)
  textAlign(CENTER)

  local lineGap = ftSize * 0.15
  local topPad  = ftSize * 0.25
  local y1 = rowTop - topPad - ftSize * 0.5
  local y2 = y1 - ftSize - lineGap

  text("Seasons have no effect on gameplay", WIDTH * 0.5, y1)
  text("they're just pretty pretty",         WIDTH * 0.5, y2)

  popStyle()

  -- Draw row dividers (pink lines at section boundaries)
  if showRowDividers then
    pushStyle()
    stroke(255, 105, 180, 220)  -- pink
    strokeWidth(2)
    noFill()
    local s = getSectionBoundaries()
    -- Draw lines at each section boundary (the yBot of each section is the boundary)
    for sec = 5, 1, -1 do
      local y = s[sec].yBot  -- bottom of this section = top of section below it
      line(0, y, WIDTH, y)
    end
    -- Also draw y=0 (bottom) and y=HEIGHT (top) boundaries
    line(0, 0, WIDTH, 0)
    line(0, HEIGHT, WIDTH, HEIGHT)
    popStyle()
  end
end

pressedButton = pressedButton or nil
pressedInside = pressedInside or false
genericAlertActive = genericAlertActive or false
genericAlertConfig = genericAlertConfig or nil
genericAlertRects = genericAlertRects or nil

------------------------------------------------------------
-- GENERIC ALERT TOUCH HANDLING (state-independent — called from Main.lua
-- touched() before state routing, so it works from any screen, not just menu)
------------------------------------------------------------

function handleGenericAlertTouch(t)
  if t.state == BEGAN then
    -- Check which alert button was hit
    if genericAlertRects then
      for btnKey, rr in pairs(genericAlertRects) do
        if type(rr) == "table" and rr.cx and pointInRect(t.x, t.y, rr.cx, rr.cy, rr.w, rr.h) then
          pressedButton = btnKey
          pressedInside = true
          return
        end
      end
    end
    pressedButton = nil
    pressedInside = false
    return
  elseif t.state == MOVING then
    if pressedButton and genericAlertRects and genericAlertRects[pressedButton] then
      local rr = genericAlertRects[pressedButton]
      pressedInside = pointInRect(t.x, t.y, rr.cx, rr.cy, rr.w, rr.h)
    end
    return
  elseif t.state == ENDED then
    if pressedButton and pressedInside and genericAlertConfig and genericAlertConfig.buttons then
      -- Extract button index from key ("btn1" -> 1)
      local btnIdx = tonumber(string.match(pressedButton, "^btn(%d+)$"))
      if btnIdx then
        local btn = genericAlertConfig.buttons[btnIdx]
        if btn and btn.callback then
          dismissGenericAlert()
          pressedButton = nil
          pressedInside = false
          btn.callback()
          return
        end
      end
    end
    -- Tap outside buttons also dismisses
    dismissGenericAlert()
    pressedButton = nil
    pressedInside = false
    return
  end
end

------------------------------------------------------------
-- NEW TOUCH HANDLER — 6-SECTION HIT TESTING
------------------------------------------------------------

function handleMenuTouch(t)
  if t.state == ENDED then
    devLog("DBG_MENU handleMenuTouch ENDED: pressedButton=", tostring(pressedButton))
  end

  didSwipeOnPoofingText(t)

  -- Recompute section boundaries from named globals
  local HPAD = 24
  local s = getSectionBoundaries()

  local function pointInSection(x, y, sec)
    return x >= HPAD and x <= WIDTH - HPAD and
           y >= s[sec].yBot and y <= s[sec].yTop
  end

  -- Find which interactive element was hit
  local function hitKeyAt(x, y)
    -- Check named button rects from drawMenu() first
    if menuHitRects then
      for k, rr in pairs(menuHitRects) do
        if type(rr) == "table" and rr.cx and rr.cy and rr.w and rr.h then
          if pointInRect(x, y, rr.cx, rr.cy, rr.w, rr.h) then
            return k
          end
        end
      end
    end
    -- Check full-section taps
    if pointInSection(x, y, 2) then return "boardSize" end
    if pointInSection(x, y, 3) then return "minWordLen" end
    return nil
  end

  if t.state == BEGAN then
    pressedButton = hitKeyAt(t.x, t.y)
    pressedInside = (pressedButton ~= nil)
    return
  end

  if t.state == MOVING then
    if pressedButton then
      local hit = hitKeyAt(t.x, t.y)
      pressedInside = (hit == pressedButton)
    end
    return
  end

  if t.state ~= ENDED then return end

  local key = pressedButton
  local shouldFire = pressedInside

  pressedButton = nil
  pressedInside = false

  if not shouldFire then return end

  if key == "boardSize" then
    if boardSize == 4 then
      boardSize = 5
    elseif boardSize == 5 then
      boardSize = 6
    else
      boardSize = 4
    end
    if persistGameplaySettings then persistGameplaySettings() end

  elseif key == "minWordLen" then
    MIN_WORD_LEN = MIN_WORD_LEN + 1
    if MIN_WORD_LEN > 6 then MIN_WORD_LEN = 3 end
    if persistGameplaySettings then persistGameplaySettings() end

  elseif key == "solo" then
    setTurnBasedEnabled(false)
    startRoundFromCurrentSettings()

  elseif key == "vs" then
    devLog("DBG_MENU versus tapped: tbm=", tostring(tbm~=nil), "authenticated=", tostring(tbm and tbm.localPlayer and tbm.localPlayer.authenticated))
    if not (tbm and tbm.showMatchmaker) then
      openGCMatchmakerErrorOverlay("Game Center is unavailable in this build or environment.")
      return
    end

    if tbm.localPlayer and tbm.localPlayer.authenticated == true then
      local ok, err = pcall(function() tbm:showMatchmaker() end)
      if not ok then openGCMatchmakerErrorOverlay(err) end
    else
      openGCSignInOverlay()
    end

  elseif key == "playAgain" then
    devLog("DBG_MENU playAgain tapped")
    confirmRematchAgainstLastOpponent(function()
      if startLastMatchReplayFromMenu then startLastMatchReplayFromMenu() end
    end)

  elseif key == "records" then
    openRecordsOverlay()

  elseif key == "info" then
    openInfoOverlay()

  elseif key == "debugDialog" then
    -- Open the balloon mockup overlay, always starting on scenario 1. (The
    -- 10-scheme color picker used to pick the permanent "Grid Wash" balloon
    -- colors on 2026-08-11 is still available — see drawBalloonColorPickerOverlay,
    -- EndScreenFP.lua — just not wired to this button by default anymore.)
    balloonMockupOverlay = true
    mockupScenarioIndex = 1
  end
end

------------------------------------------------------------
-- SOWPODS WORD LOOKUP (for MWL dice display)
------------------------------------------------------------

function ensureWordsByLength()
  if WORDS_BY_LENGTH then return end
  WORDS_BY_LENGTH = {}
  for w, _ in pairs(DICT) do
    local n = #w
    if n >= 3 and n <= 6 then
      if not WORDS_BY_LENGTH[n] then WORDS_BY_LENGTH[n] = {} end
      table.insert(WORDS_BY_LENGTH[n], w)
    end
  end
end

function randomWordOfLength(n)
  ensureWordsByLength()
  local list = WORDS_BY_LENGTH[n]
  if not list or #list == 0 then return nil end
  return list[math.random(1, #list)]
end

------------------------------------------------------------
-- MENU DICE WORD FILTER — scope: ONLY the min-word-length dice preview
-- (Section 3, menuDiceDisplayWord above). Deliberately does NOT touch DICT,
-- WORDS_BY_LENGTH, or any actual gameplay word validation/scoring — players
-- finding an off-color word during a real round is unrelated and untouched.
-- This is specifically about words appearing UNPROMPTED on the main menu to
-- anyone glancing at the app.
--
-- Source: the 3-6 letter single-word entries from the LDNOOBW "List of Dirty,
-- Naughty, Obscene, and Otherwise Bad Words" (github.com/LDNOOBW/List-of-
-- Dirty-Naughty-Obscene-and-Otherwise-Bad-Words, en list, MIT-licensed,
-- originally curated by Shutterstock) — a widely-used, publicly maintained
-- moderation blocklist covering slurs, profanity, and explicit-content terms.
-- Cross-checked 2026-08-09: 87 of these are valid SOWPODS words (the rest
-- aren't in the dictionary at all, so are harmless no-ops to keep listed).
------------------------------------------------------------

MENU_DICE_BLOCKLIST = MENU_DICE_BLOCKLIST or (function()
  local words = {
    "ANAL","ANUS","ASS","BBW","BDSM","BEANER","BIMBOS","BITCH","BONER","BOOB",
    "BOOBS","BUSTY","BUTT","CIALIS","CLIT","COCK","COCKS","COON","COONS","CUM",
    "CUNT","DARKIE","DICK","DILDO","DOMMES","DVDA","ECCHI","EROTIC","ESCORT",
    "EUNUCH","FAG","FAGGOT","FECAL","FELCH","FELTCH","FEMDOM","FUCK","FUCKIN",
    "GOATCX","GOATSE","GOKKUN","GROPE","GURO","HENTAI","HONKEY","HOOKER",
    "HORNY","INCEST","JIZZ","JUGGS","KIKE","KINKY","LOLITA","MILF","MONG",
    "NAMBLA","NEGRO","NIGGA","NIGGER","NIPPLE","NSFW","NUDE","NUDITY","NUTTEN",
    "NYMPHO","ORGASM","ORGY","PAKI","PANTY","PENIS","PIKEY","POOF","POON",
    "PORN","PORNO","PTHC","PUBES","PUNANY","PUSSY","QUEAF","QUEEF","QUIM",
    "RAPE","RAPING","RAPIST","RECTUM","RIMJOB","SADISM","SCAT","SEMEN","SEX",
    "SEXCAM","SEXO","SEXUAL","SEXY","SHIT","SHITTY","SHOTA","SKEET","SLUT",
    "SMUT","SNATCH","SODOMY","SPIC","SPOOGE","SPUNK","SUCK","SUCKS","TIT",
    "TITS","TITTY","TOSSER","TRANNY","TUSHY","TWAT","TWINK","VAGINA","VIAGRA",
    "VOYEUR","VOYUER","VULVA","WANK","WHORE","XXX","YAOI","YIFFY",
  }
  local set = {}
  for _, w in ipairs(words) do set[w] = true end
  return set
end)()

-- Same as randomWordOfLength(), but retries away from MENU_DICE_BLOCKLIST.
-- Exact whole-word match only (not substring) — deliberately avoids the
-- "Scunthorpe problem" of an innocuous word getting rejected because a
-- shorter blocked word happens to appear inside it.
function randomMenuDiceWord(n)
  ensureWordsByLength()
  local list = WORDS_BY_LENGTH[n]
  if not list or #list == 0 then return nil end

  for _ = 1, 25 do
    local w = list[math.random(1, #list)]
    if not MENU_DICE_BLOCKLIST[w] then return w end
  end

  -- Pathological fallback (should never trigger in practice — the blocklist
  -- is a tiny fraction of any WORDS_BY_LENGTH bucket): filter once and pick.
  local clean = {}
  for _, w in ipairs(list) do
    if not MENU_DICE_BLOCKLIST[w] then clean[#clean + 1] = w end
  end
  if #clean == 0 then return nil end
  return clean[math.random(1, #clean)]
end

------------------------------------------------------------
-- GUIDE LINES (edit these until they match your screenshot)
-- 9 horizontals (top -> bottom), 4 verticals (left -> right)
------------------------------------------------------------

function getGuideLines()
  -- Fractions of screen; change these numbers only.
  local yShift = 0.04 -- move full menu stack upward by ~half a button height
  local xFrac = {
    0.125, -- v1
    0.175, -- v2
    0.825, -- v3
    0.875  -- v4
  }

  local yFrac = {
    0.873, -- h1 (near top)
    0.65, -- h2
    0.65, -- h3
    0.66, -- h4
    0.54, -- h5
    0.5, -- h6 -- buttons top?
    0.11, -- h7
    0.11, -- h8
    0.06  -- h9 (near bottom)
  }

  local x = {}
  for i = 1, 4 do x[i] = WIDTH * xFrac[i] end

  local y = {}
  for i = 1, 9 do
    y[i] = HEIGHT * math.min(1, yFrac[i] + yShift)
  end

  return x, y
end

------------------------------------------------------------
-- DEBUG DRAW: pink lines
------------------------------------------------------------

function drawPinkLines()
  local x, y = getGuideLines()

  pushStyle()
  stroke(255, 0, 200, 190)
  strokeWidth(3)
  noFill()

  -- verticals
  for i = 1, 4 do
    line(x[i], 0, x[i], HEIGHT)
  end

  -- horizontals
  for i = 1, 9 do
    line(0, y[i], WIDTH, y[i])
  end

  popStyle()
end

------------------------------------------------------------
-- DEBUG DRAW: purple boxes based on your constraints
------------------------------------------------------------

function drawBoxByGuides(x, y, hTop, hBot, vLeft, vRight)
  local left  = x[vLeft]
  local right = x[vRight]
  local top   = y[hTop]
  local bot   = y[hBot]

  -- assume y decreases downward? (Codea: y increases upward)
  -- We want a CORNER rect with bottom-left origin:
  local x0 = left
  local y0 = bot
  local w  = right - left
  local h  = top - bot

  rect(x0, y0, w, h)
end

function drawPurpleSquares()
  local x, y = getGuideLines()

  pushStyle()
  stroke(120, 60, 255, 210)
  strokeWidth(7)
  noFill()
  rectMode(CORNER)

  -- constraints you gave:

  -- horizontals 1-2, verticals 1-4
  drawBoxByGuides(x, y, 1, 2, 1, 4)

  -- horizontals 2-3, verticals 1-4
  drawBoxByGuides(x, y, 2, 3, 1, 4)

  -- horizontals 4-5, verticals 1-4
  drawBoxByGuides(x, y, 4, 5, 1, 4)

  -- horizontals 6-7, verticals 2-3
  drawBoxByGuides(x, y, 6, 7, 2, 3)

  -- horizontals 8-9, verticals 1-4
  drawBoxByGuides(x, y, 8, 9, 1, 4)

  popStyle()
end

------------------------------------------------------------
-- Get rectangle from guide indices
------------------------------------------------------------

function rectFromGuides(hTop, hBot, vLeft, vRight)
  local x, y = getGuideLines()

  local left  = x[vLeft]
  local right = x[vRight]
  local top   = y[hTop]
  local bot   = y[hBot]

  return {
    x = left,
    y = bot,
    w = right - left,
    h = top - bot,
    cx = (left + right) * 0.5,
    cy = (top + bot) * 0.5
  }
end

------------------------------------------------------------
-- LEGACY BUTTON HELPER (kept for backward compatibility)
------------------------------------------------------------

function drawMenuButton(x, y, w, h, label, id)
  pushStyle()

  rectMode(CENTER)
  textMode(CENTER)
  fontSize(22)

  local selected = (pressedButton == id)
  local fillCol  = selected and Color.uiAccent2 or Color.uiAccent

  drawRoundedRect(x, y, w, h, 10, fillCol, fillCol)

  fill(255,255,255,255) -- allowed exception
  text(label, x, y)

  popStyle()
end

menuSpecA = menuSpecA or {
  text  = currentSeasonName or "Autumn",
  font  = "Georgia-Italic",
  size  = 80,
  x     = WIDTH/2,
  y     = HEIGHT/2 + 40,
  color = color(177,114,51),
  mode  = CENTER,
  align = CENTER
}

menuSpecB = menuSpecB or {
  text  = currentHaiku or
  "A world of dew,\nand within every dewdrop\na world of struggle.",
  font  = "Helvetica-Bold",
  size  = 20,
  x     = WIDTH/2 - 120,
  y     = HEIGHT/2 - 40,
  color = color(222,151,75),
  mode  = CORNER,
  align = LEFT
}

menuSpecA = menuSpecA or nil
menuSpecB = menuSpecB or nil
