# Quozzy Main Menu — Design Handoff for Codea

## Project Constants

These are consumed by the `xcode-orchestrator` skill and any CLI-based diagnostics.

| Constant   | Value |
|------------|-------|
| SCHEME     | `Quozzy` |
| BUNDLE_ID  | `com.jessewonderclark.quozzyseasons` |
| BUILD_PATH | `/tmp/quozzy-build` |
| SIM_ID     | `0EF8AE50-8899-40DD-A77E-359C06732886` (iPhone 16e — primary for this project) |
| SIM_ID_ALT | `1B48ACAA-0AE2-40C3-B28B-BFDB1A4A3044` (iPhone 17 — DO NOT USE for this project) |

> **Pending rename:** The app will be released as **Kotoba**. When the Xcode
> project is renamed, update SCHEME and BUNDLE_ID above, and the paths in
> `xcode-orchestrator.md` will pick them up transitively. The orchestrator
> file itself is project-agnostic — it reads these values from here.

### Diagnostic Log Access

| Channel | How to read from outside the simulator |
|---------|----------------------------------------|
| `devLog()` → system log | `xcrun simctl spawn $SIM_ID log show --last Ns --predicate 'process == "Quozzy"'` |
| `saveLocalData` ring buffer | `plutil -p $(xcrun simctl get_app_container $SIM_ID $BUNDLE_ID data)/Library/Preferences/com.jessewonderclark.quozzyseasons.plist \| grep DevLogBuffer` |

The ring buffer holds the last 200 `devLog()`/`print()` lines as a JSON array, flushed to disk every second.
It is cleared on each launch; stale data persists only until the first flush of the new session.

---

This document is the complete specification for the redesigned Quozzy main menu
and its associated animations, derived from an interactive React prototype.
All values are ready for translation into Codea/Lua (coordinate origin bottom-left,
y increases upward, 60fps draw loop, DeltaTime available).

---

## 1. COLOUR PALETTE

All colours are RGB 0–255.

| Token            | Hex       | color()                  | Usage                              |
|------------------|-----------|--------------------------|------------------------------------|
| BG               | #c8dce8   | color(200, 220, 232)     | Screen background                  |
| TEAL             | #4bc0b8   | color(75, 192, 184)      | Dice, board tiles, buttons         |
| TEAL_DARK        | #38a89e   | color(56, 168, 158)      | Dice during roll animation         |
| TEAL_LABEL       | #4abcb4   | color(74, 188, 180)      | Section label text                 |
| TEAL_SEASON      | #4bc8c0   | color(75, 200, 192)      | "Winter" / season name             |
| NAVY             | #1a2b5e   | color(26, 43, 94)        | "Quozzy", "SEASONS" text           |
| GREY_CAPTION     | #8aa0ae   | color(138, 160, 174)     | Disclaimer text                    |

---

## 2. LAYOUT — SIX VERTICAL SECTIONS

Proportions (tuned values, sum ≈ 99 → normalise to 100%):

| #  | Section         | %      | Height formula           |
|----|-----------------|--------|--------------------------|
| 1  | Title & Season  | 27.27% | HEIGHT * 0.2727          |
| 2  | Board area      | 32.32% | HEIGHT * 0.3232          |
| 3  | Min dice area   | 10.10% | HEIGHT * 0.1010          |
| 4  | Play modes      | 16.16% | HEIGHT * 0.1616          |
| 5  | Records / Info  | 8.08%  | HEIGHT * 0.0808          |
| 6  | Disclaimer      | 6.06%  | HEIGHT * 0.0606          |

### Section Y boundaries (Codea, y from bottom)

```lua
local s = {}
s[6] = { yBot = 0,                  yTop = HEIGHT * 0.0606 }
s[5] = { yBot = HEIGHT * 0.0606,    yTop = HEIGHT * 0.1414 }
s[4] = { yBot = HEIGHT * 0.1414,    yTop = HEIGHT * 0.3030 }
s[3] = { yBot = HEIGHT * 0.3030,    yTop = HEIGHT * 0.4040 }
s[2] = { yBot = HEIGHT * 0.4040,    yTop = HEIGHT * 0.7272 }
s[1] = { yBot = HEIGHT * 0.7272,    yTop = HEIGHT          }

-- Centre Y of each section:
local function midY(sec)
    return (s[sec].yBot + s[sec].yTop) * 0.5
end
```

Thin dividers (2px) sit at each section boundary. In production they are the
same colour as BG (invisible); during development draw them in a bright colour.

### Horizontal padding

```lua
local HPAD   = 24          -- px each side
local innerW = WIDTH - 48  -- usable inner width
```

---

## 3. SECTION 1 — TITLE & SEASON

Content centred horizontally and vertically within the band.

```
"Quozzy"        -- large serif bold
"SEASONS"       -- smaller, wide letter-spacing
"Winter"        -- italic, teal, slightly smaller than Quozzy
```

Font sizes scale with section height `h1 = HEIGHT * 0.2727`:

| Text      | Font                  | Size formula              | Max px | Color  |
|-----------|-----------------------|---------------------------|--------|--------|
| Quozzy    | Georgia Bold          | h1 * 0.34                 | 64     | NAVY   |
| SEASONS   | Georgia Bold          | h1 * 0.16, letter-spacing | 28     | NAVY   |
| Winter    | Georgia Italic        | h1 * 0.28                 | 52     | TEAL_SEASON |

Gap between the three items: `h1 * 0.06` (capped at 14px).

The "MATCH READY / TAP HERE" badge overlaps the Q and ASONS — that is a
live interactive element handled elsewhere in the codebase; do not replicate it here.

---

## 4. SECTION 2 — BOARD AREA

Tappable. Each tap cycles board size: 4×4 → 5×5 → 6×6 → 4×4.

### Column split

| Condition                  | Left col (text) | Right col (grid) |
|----------------------------|-----------------|------------------|
| Wide (default)             | 40% of innerW   | 60% of innerW    |
| Narrow (cell would be <6px)| 50% of innerW   | 50% of innerW    |

### Cell size

```lua
local h2        = HEIGHT * 0.3232
local GRID_GAP  = 5
local boardWideW = innerW * 0.6

-- Width-constrained cell
local cellFromW = (boardWideW - (boardSize - 1) * GRID_GAP) / boardSize

-- Height-constrained cell  
local cellFromH = h2 * 0.82 / boardSize

local isWide = math.min(cellFromW, cellFromH) >= 6
local colW   = isWide and boardWideW or (innerW * 0.5)
cellFromW    = (colW - (boardSize - 1) * GRID_GAP) / boardSize
local cellPx = math.max(4, math.floor(math.min(cellFromW, cellFromH)))
```

### Grid drawing

```lua
-- Grid is tilted +6° clockwise (positive rotation in standard maths, 
-- but in Codea rotate() is counter-clockwise, so use -6° or rotate(-6))
-- Grid centre sits in the right column, vertically centred in section 2.
local gridW = boardSize * cellPx + (boardSize - 1) * GRID_GAP
local gridH = gridW   -- square

-- Each tile:
--   rounded rect, radius = cellPx * 0.15
--   fill = TEAL  (or TEAL_DARK during roll)
--   no stroke
```

### Text (left column)

```lua
-- "Choose" and "Board Size" stacked, then large size number below
-- Font: Caveat Bold (or any handwritten/casual font available in Codea)
-- Fallback: use a rounded sans-serif

local labelSize  = math.max(9,  math.min(h2 * 0.10, 22))  -- "Choose / Board Size"
local numberSize = math.max(12, math.min(h2 * 0.15, 28))  -- "6 × 6"
-- Color: TEAL_LABEL
-- Aligned to left edge of left column
```

### Gentle rocking animation

The board grid rocks continuously:

```lua
-- Parameters (match the React prototype defaults):
local BOARD_ROCK_BASE    =  6.0   -- degrees tilt at rest
local BOARD_ROCK_AMP     =  2.5   -- degrees either side
local BOARD_ROCK_PERIOD  =  4.3   -- seconds per full cycle

-- In draw():
local boardAngle = BOARD_ROCK_BASE
    + BOARD_ROCK_AMP * math.sin((ElapsedTime / BOARD_ROCK_PERIOD) * math.pi * 2)
-- Apply as rotation when drawing the grid
```

---

## 5. SECTION 3 — MINIMUM DICE AREA

Tappable. Cycles minimum word length: 3 → 4 → 5 → 6 → 3.

### Die sizing rules (consistent-width constraint)

```lua
local h3      = HEIGHT * 0.1010
local DICE_GAP = 5
local diceColW = innerW * 0.6   -- reference column width

-- Die sizes at each minLen:
local die5 = (diceColW - 4 * DICE_GAP) / 5   -- fills column exactly
local die6 = (diceColW - 5 * DICE_GAP) / 6   -- fills column exactly
local die4 = die5                              -- same size as 5 → shorter row
local die3 = die4 * 1.13                      -- slightly larger than 4

-- Pick raw size for current minLen, then cap to section height:
local rawDie = ({ [3]=die3, [4]=die4, [5]=die5, [6]=die6 })[minLen]
local maxFromH = h3 * 0.72
local dicePx   = math.max(4, math.floor(math.min(rawDie, maxFromH)))

-- Actual row width (NOT always diceColW — 3 and 4 are narrower):
local diceRowW = minLen * dicePx + (minLen - 1) * DICE_GAP
```

### Layout

```
[dice row tilted -5°]  [gap 12px]  [text column width = min(diceRowW, remaining)]
```

Text column content centred:

```lua
local textColW  = math.min(diceRowW, innerW - diceRowW - 12)
-- "minimum / # letters"  labelSize = max(9, min(h3*0.12, 20))
-- "{minLen}"             numberSize = max(12, min(h3*0.18, 26))
-- Color: TEAL_LABEL, centred within textColW
```

### Gentle rocking

```lua
local DICE_ROCK_BASE    = -5.0
local DICE_ROCK_AMP     =  2.5
local DICE_ROCK_PERIOD  =  5.1

local diceAngle = DICE_ROCK_BASE
    + DICE_ROCK_AMP * math.sin((ElapsedTime / DICE_ROCK_PERIOD) * math.pi * 2)
```

---

## 6. SECTION 4 — PLAY MODES

Three tilted rounded-rectangle buttons, horizontally centred with ~4% of WIDTH gap.

### Button dimensions

```lua
local h4     = HEIGHT * 0.1616
local btnH   = h4 * 0.84
local btnW   = btnH * 0.82      -- aspect ratio 0.82
local btnR   = btnW * 0.18      -- corner radius
```

### Buttons

| Label      | Base tilt | Rock period |
|------------|-----------|-------------|
| "solo"     | −8°       | 3.7s        |
| "vs"       | +4°       | 4.9s        |
| 🤖 emoji   | −5°       | 5.5s        |

All share rock amplitude 2.5°. Formula:

```lua
local soloAngle  = -8.0 + 2.5 * math.sin((ElapsedTime / 3.7) * math.pi * 2)
local vsAngle    =  4.0 + 2.5 * math.sin((ElapsedTime / 4.9) * math.pi * 2)
local robotAngle = -5.0 + 2.5 * math.sin((ElapsedTime / 5.5) * math.pi * 2)
```

Button fill: TEAL. Label: white, Georgia or Caveat Bold.
Label font size: `math.min(btnH * 0.28, 30)`.

---

## 7. SECTION 5 — RECORDS / INFO

Two circular icon buttons, horizontally centred.

```lua
local h5   = HEIGHT * 0.0808
local pad  = math.max(5, math.min((h5 - 2) / 2, 10))  -- clamp 5–10px
local btnD = h5 - pad * 2    -- button diameter
-- Horizontal gap between centres: clamp(h5*0.5, 20, 60)
-- Fill: TEAL, icons white
-- Left button: records icon (📓 or notebook drawing)
-- Right button: info "i"
```

---

## 8. SECTION 6 — DISCLAIMER

```
"Seasons have no effect on gameplay"
"they're just pretty pretty"
```

```lua
local h6      = HEIGHT * 0.0606
local fontSize = math.max(8, math.min(h6 * 0.13, 14))
-- Color: GREY_CAPTION, centred, italic, lineHeight ~1.5
```

---

## 9. ANIMATION — DIE WOBBLE

Triggered on tap of any single die. Duration 550ms. Interpolate these keyframes:

| t (0–1) | scale | rotate (°) |
|---------|-------|------------|
| 0.00    | 1.00  |   0.0      |
| 0.12    | 1.22  | −11.0      |
| 0.26    | 1.14  |   8.0      |
| 0.40    | 1.07  |  −5.0      |
| 0.55    | 1.03  |   2.5      |
| 0.70    | 1.01  |  −1.0      |
| 0.85    | 1.00  |   0.4      |
| 1.00    | 1.00  |   0.0      |

```lua
-- Per-die state:
local wobbleTimer = 0          -- counts up from 0 to WOBBLE_DUR
local WOBBLE_DUR  = 0.55

-- In touched(): on tap, reset wobbleTimer = 0, set wobbling = true

-- Helper: linear interpolation through keyframe table
local KF_T   = {0, .12, .26, .40, .55, .70, .85, 1.0}
local KF_SC  = {1, 1.22, 1.14, 1.07, 1.03, 1.01, 1.00, 1.00}
local KF_ROT = {0, -11,  8,   -5,   2.5, -1,   0.4,  0}

local function kfLerp(t, values)
    for i = 1, #KF_T - 1 do
        if t <= KF_T[i+1] then
            local alpha = (t - KF_T[i]) / (KF_T[i+1] - KF_T[i])
            return values[i] + alpha * (values[i+1] - values[i])
        end
    end
    return values[#values]
end

-- In draw() per wobbling die:
if wobbling then
    wobbleTimer = wobbleTimer + DeltaTime
    local t   = math.min(wobbleTimer / WOBBLE_DUR, 1.0)
    local sc  = kfLerp(t, KF_SC)
    local rot = kfLerp(t, KF_ROT)
    -- pushMatrix(), translate to die centre, rotate(rot), scale(sc,sc)
    -- draw die, popMatrix()
    if t >= 1.0 then wobbling = false end
end
```

---

## 10. ANIMATION — BOARD ROLL

Three phases triggered by the Roll button.

### Phase 1 — SPINNING (1400ms)

- Every 55ms, randomise every die's displayed letter.
- Board container shakes:

```lua
-- Shake oscillates around the base 6° tilt
-- Two sine waves slightly offset to feel tumbled not just vibrating:
local shakeAngle = 6.0
    + 1.8 * math.sin(ElapsedTime * (2*math.pi / 0.33))
local shakeX     = 3.0 * math.sin(ElapsedTime * (2*math.pi / 0.33) + 0.8)
-- Apply as rotate + translate when drawing the whole grid
```

- Die fill colour: TEAL_DARK during spinning.
- Letter flashes: rapid opacity toggle (full → 0.15 → full every 90ms).

### Phase 2 — RESOLVING

- Begin immediately after 1400ms of spinning.
- Shuffle a list of all N×N die indices.
- Lock in each die one by one with 58ms stagger:
  - Set die letter to its final value.
  - Trigger die wobble animation on that die.
  - Return fill to TEAL.
- After all dice locked + 350ms: animation complete.

### Letter randomisation

```lua
local ROLL_LETTERS = "ABCDEEFGHIILMNNOOPRSSTU"
local function randLetter()
    return string.sub(ROLL_LETTERS,
        math.random(1, #ROLL_LETTERS), 
        math.random(1, #ROLL_LETTERS))
end
```

---

## 11. ANIMATION — EMOJI BURST

Triggered on touch of a die during gameplay. Canvas-space particle system.

### Season emoji sets

```lua
local SEASON_EMOJIS = {
    spring = {"🌸","🌺","🦋","🌿","🌼","🐝","🌱","🐛","💐","🌻"},
    summer = {"☀️","🌊","🌴","🍦","🦀","🌻","🍉","🏖️","🐚","🌈"},
    autumn = {"🍂","🍁","🍄","🌰","🦔","🍎","🌾","🎃","🐿️","🕯️"},
    winter = {"❄️","⛄","🌨️","🦌","🔔","🕯️","🧊","🐧","⭐","🌙"},
}
```

### Spawn (10 particles per burst, from touch point tx, ty)

```lua
local N = 10
for i = 1, N do
    -- Evenly spread angles with small jitter
    local angle = ((i-1) / N) * (2 * math.pi) + (math.random() - 0.5) * 0.5
    local spd   = 3.0 + math.random() * 5.0   -- px/frame at 60fps

    table.insert(particles, {
        x     = tx,
        y     = ty,
        vx    =  math.cos(angle) * spd,
        vy    =  math.sin(angle) * spd,   -- NOTE: Codea y-up, so flip sign vs canvas
        rot   = math.random() * math.pi * 2,
        rotV  = (math.random() - 0.5) * 0.32,  -- rad/frame
        scale = 1.0 + math.random() * 0.6,
        life  = 0,
        maxLife = 50 + math.floor(math.random() * 30),  -- frames at 60fps
        emoji = SEASON_EMOJIS[currentSeason][math.random(1, 10)],
        delay = math.floor(math.random() * 3),  -- frame delay before starting
    })
end
```

### Per-frame update (each particle p)

```lua
if p.delay > 0 then
    p.delay = p.delay - 1
else
    p.life = p.life + 1
    local progress = p.life / p.maxLife

    -- Physics
    p.vx = p.vx * 0.90
    p.vy = p.vy * 0.90
    p.vy = p.vy - 0.13    -- gravity (Codea: downward = subtract from vy)
    p.x  = p.x  + p.vx
    p.y  = p.y  + p.vy
    p.rot  = p.rot  + p.rotV
    p.rotV = p.rotV * 0.93

    -- Opacity: full for first 45% of life, then linear fade to 0
    local alpha
    if progress < 0.45 then
        alpha = 1.0
    else
        alpha = 1.0 - (progress - 0.45) / 0.55
    end

    -- Scale: shrinks 30% over lifetime
    local sc = p.scale * (1.0 - progress * 0.30)

    -- Draw: translate to p.x, p.y; rotate p.rot; draw emoji at size ~24*sc
    -- In Codea: use font(), fontSize(24*sc), fill(255,255,255,alpha*255)
    -- text(p.emoji, p.x, p.y)
    -- (emoji rendering in Codea: use fontSize and text(); no fill needed for emoji)

    -- Remove when done
    if p.life >= p.maxLife then
        -- remove from table
    end
end
```

---

## 12. SEASONAL COLOUR VARIANTS

The background and text tints shift per season (board and button teal stays constant):

| Season | BG hex  | BG color()              | Text hex | Text color()          |
|--------|---------|-------------------------|----------|-----------------------|
| spring | #e8f0e0 | color(232, 240, 224)    | #2a5a28  | color(42, 90, 40)     |
| summer | #f5edda | color(245, 237, 218)    | #7a4a10  | color(122, 74, 16)    |
| autumn | #f0e0cc | color(240, 224, 204)    | #6a2a08  | color(106, 42, 8)     |
| winter | #c8dce8 | color(200, 220, 232)    | #1a2b5e  | color(26, 43, 94)     |

(Board/button teal #4bc0b8 = color(75, 192, 184) is the same across all seasons.)

---

## 13. TYPEFACES

| Role              | React prototype   | Codea equivalent              |
|-------------------|-------------------|-------------------------------|
| Title / headings  | Georgia Bold      | "Georgia-Bold" or "Georgia"   |
| Season name       | Georgia Italic    | "Georgia-Italic"              |
| Section labels    | Caveat Bold       | "Futura-Medium" or similar handwritten-ish available in Codea; or just use Georgia-Italic at a lighter weight |
| Button labels     | Caveat Bold       | same as above                 |
| Disclaimer        | Georgia Italic    | "Georgia-Italic"              |

---

## 14. NOTES FOR CODEA IMPLEMENTATION

1. **Coordinate flip**: The React prototype uses CSS (y-down). Codea is y-up.
   All Y positions should be calculated as described in Section 2 (from bottom).
   For emoji burst, flip the vy gravity sign as noted.

2. **Rotation direction**: Codea `rotate()` is counter-clockwise positive.
   The board's +6° clockwise tilt = `rotate(-6)` in Codea (or negate all angles).

3. **DeltaTime physics**: The emoji burst physics are given in px/frame at 60fps.
   To be framerate-independent in Codea:
   ```lua
   -- Per-frame drag 0.90 at 60fps → per-second drag = 0.90^60 ≈ 0.001
   -- Framerate-independent: multiply by (0.90 ^ (60 * DeltaTime))
   p.vx = p.vx * (0.90 ^ (60 * DeltaTime))
   -- Or approximate: p.vx = p.vx * (1 - 6.0 * DeltaTime)  (valid for small dt)
   ```

4. **Emoji rendering**: In Codea, `text()` renders emoji natively. No fill colour
   needed. Use `fontSize()` to control size and `textMode(CENTER)` for positioning.

5. **Die rounded rects**: Use `rect(x, y, w, h, radius)` in Codea. Box shadow
   is not available — optionally draw a slightly larger darker rect behind as a shadow.

6. **The `key` trick for re-triggering CSS animations** does not apply in Codea —
   use a timer variable per die to track wobble state.
---

## 15. IMPLEMENTATION CHECKLIST

### Phase 1 — Menu Redesign (current focus)

- [x] 1. Colour palette — add TEAL, NAVY, GREY_CAPTION, TEAL_LABEL, TEAL_SEASON, TEAL_DARK, BG to Themes.lua
- [x] 2. Seasonal BG/text colour variants — spring green, summer cream, autumn tan, winter blue per §12
- [x] 3. Section 1 — Title & Season ("Quozzy" / "SEASONS" / season name) per §3
- [x] 4. Section 2 — Board Area with size cycling tap and continuous rocking animation per §4
- [x] 5. Section 3 — Minimum Dice Area with min-word-length cycling tap and rocking animation per §5
- [x] 6. Section 4 — Play Modes (solo / vs / robot) tilted rocking buttons per §6
- [x] 7. Section 5 — Records / Info circular icon buttons per §7
- [x] 8. Section 6 — Disclaimer text per §8
- [x] 9. Touch handling — all interactive elements wired per §4–§7
- [x] 10. Season transition integration — BG colour blends during season change
- [x] 11. Remove dead code — old drawTitleSection(), drawButtonGridSection(), drawFooterSection(), drawPlayAgainButton(), drawMenuLayout(), getButtonGridHitRects()

### Phase 2 — Animations (follow-up)

- [ ] 12. Die wobble animation on tap per §9
- [ ] 13. Board roll animation (spinning + resolving phases) per §10
- [ ] 14. Emoji burst particle system per §11

---

## 16. TROUBLESHOOTING

### Simulator Hangs (Black Screen on Launch)

**Symptoms:**
- App launches but shows only a black screen, never reaches the menu
- `xcrun simctl terminate` hangs/times out
- `xcrun simctl` commands become unresponsive

**Root Cause:** The CoreSimulator service and/or individual simulator processes enter a deadlocked state. This is common after repeated build/install/launch cycles or after an app crashes inside the simulator.

**Recovery Procedure:**

```bash
# Step 1: Force-kill all simulator processes
killall -9 "Simulator" 2>/dev/null
killall -9 "SimulatorTrampoline" 2>/dev/null

# Step 2: Shut down all simulator devices (may timeout if badly hung; proceed to step 3)
xcrun simctl shutdown all 2>/dev/null &

# Step 3: Kill the CoreSimulator service daemon
sudo killall -9 "com.apple.CoreSimulator.CoreSimulatorService" 2>/dev/null || \
  killall -9 "com.apple.CoreSimulator.CoreSimulatorService" 2>/dev/null

# Step 4: Wait for services to restart
sleep 5

# Step 5: Verify clean state (no booted simulators)
xcrun simctl list | grep Booted
# Should output nothing

# Step 6: Boot the target simulator
xcrun simctl boot <SIM_ID>

# Step 7: Wait for boot to complete
until xcrun simctl list | grep "<SIM_ID>" | grep -q Booted; do sleep 2; done

# Step 8: Clean rebuild (clear DerivedData to avoid stale cache)
rm -rf /tmp/quozzy-build
xcodebuild -scheme Quozzy \
  -destination "platform=iOS Simulator,id=<SIM_ID>" \
  -derivedDataPath /tmp/quozzy-build \
  -quiet build

# Step 9: Install and launch
xcrun simctl install <SIM_ID> /tmp/quozzy-build/Build/Products/Debug-iphonesimulator/Quozzy.app
xcrun simctl launch <SIM_ID> com.jessewonderclark.quozzyseasons
```

**SIM_ID for this project:**
- iPhone 17: `1B48ACAA-0AE2-40C3-B28B-BFDB1A4A3044`
- iPhone 16e (other project): `0EF8AE50-8899-40DD-A77E-359C06732886` -- DO NOT TOUCH
- Find current booted: `xcrun simctl list | grep Booted`

**Prevention:**
- Always terminate the app before rebuilding: `xcrun simctl terminate <SIM_ID> com.jessewonderclark.quozzyseasons`
- If terminate hangs (>10s), the simulator is already hung -- proceed to recovery
- Clean builds (`rm -rf /tmp/quozzy-build`) prevent stale binary caches after code changes

---

### Game Center Auth and "re" Button Activation

**How the "re" (play again) button appears:**

The button is conditional -- it only shows in Section 4 when `getLastMatchReplaySettings()` returns a valid `opponentId`. This data comes from a previously completed Game Center match.

**Data persistence flow:**
```
Game Center match completed
  -> finalizeCompletedTurnBasedMatch()         [GameCenter.lua:173]
    -> persistLastMatchReplaySettingsFromQMatch()  [Main.lua:177]
      -> saves {opponentId, opponentPlayerID, opponentName, boardSize, minWordLen}
        to LAST_MATCH_REPLAY_KEY via saveLocalData()
      -> saves opponent avatar to LAST_MATCH_REPLAY_AVATAR_KEY
```

**On subsequent app launch with GC auth:**
```
CTBM auth succeeds
  -> uponDetectingAuthentication callback      [Main.lua:870]
    -> requestAutoOpenFinishedMatchCheck("auth")  [Main.lua:378]
      -> sets finishedMatchAutoCheckPendingReason flag
  -> draw() loop                               [Main.lua:1021]
    -> maybeAutoOpenMostRecentFinishedMatch()  [Main.lua:438]
      -> loads GC matches, finds most recent ended one
      -> enterQMatch(q)                        [GameCenter.lua:238]
        -> persistLastMatchReplaySettingsFromQMatch() again  [line 275]
        -> opens end screen for finished match
```

**After auto-open end screen dismissed -> back to menu:**
```
drawMenu() -> Section 4                         [HaikuMenu.lua:531]
  -> getLastMatchReplaySettings()
    -> reads LAST_MATCH_REPLAY_KEY from persistent storage
    -> hasReplay = (replaySettings.opponentId ~= nil)
      -> true:  3 buttons (solo | vs | avatar+"re")
      -> false: 2 buttons (solo | vs only)
```

**The "re" button will NOT appear if:**
- No Game Center match has ever been completed on this device/account
- The opponent data in the replay settings has a nil/empty opponentId
- The simulator is not signed into Game Center (Settings -> Game Center)

**GC Auth state is independent of button visibility:**
- The button appears based on REPLAY DATA, not auth state
- If replay data exists but GC is not authenticated, the button STILL appears
- Tapping it when unauthenticated shows the "Something Ker-Flumped" sign-in overlay
- After signing in, tapping "re" shows the confirmation dialog ("heck yeah" / "nah")

**Verifying the flow from logs:**
```
# Auth startup
- CTBM | init start
- CTBM | _authenticate start | authenticated= | false/true

# Auth success
- CTBM | authentication succeeded; firing app callback

# Auto-open (if pending)
- Auto-opening finished match | match= | ...

# Button tap
- DBG_MENU playAgain tapped
```

**Cache behavior of getLastMatchReplaySettings():**
- First call: reads from persistent storage, caches result in `lastMatchReplaySettings`
- If no data found: caches `false` -> returns nil
- Later calls: returns cached value (avoids repeated disk reads)
- `persistLastMatchReplaySettingsFromQMatch()` updates the cache when it saves new data
- This means the button can appear mid-session after auto-open completes

---

## 17. HANDOFF STATE — 2026-07-02

### Simulator

**Primary simulator for this project:** iPhone 16e (`0EF8AE50-8899-40DD-A77E-359C06732886`)
- iPhone 17 (`1B48ACAA-0AE2-40C3-B28B-BFDB1A4A3044`) is used by a different project — DO NOT TOUCH

### Build command

```bash
rm -rf /tmp/quozzy-build
xcodebuild -scheme Quozzy \
  -destination "platform=iOS Simulator,id=0EF8AE50-8899-40DD-A77E-359C06732886" \
  -derivedDataPath /tmp/quozzy-build -quiet build
xcrun simctl install 0EF8AE50-8899-40DD-A77E-359C06732886 \
  /tmp/quozzy-build/Build/Products/Debug-iphonesimulator/Quozzy.app
xcrun simctl launch 0EF8AE50-8899-40DD-A77E-359C06732886 \
  com.jessewonderclark.quozzyseasons
```

### What's implemented

| Feature | Status | File(s) |
|---------|--------|---------|
| 6-section proportional layout | Done | HaikuMenu.lua |
| Seasonal palette colors (uiAccent/tileText) | Done | HaikuMenu.lua, Themes.lua |
| Section globals (titleRow, boardRow, etc.) | Done | HaikuMenu.lua |
| Row dividers (showRowDividers) | Done | HaikuMenu.lua |
| Board size cycling (Section 2 tap) | Done | HaikuMenu.lua |
| Min word length cycling (Section 3 tap) | Done | HaikuMenu.lua |
| Solo/VS/Re buttons (Section 4) | Done | HaikuMenu.lua |
| VS button → GC matchmaker + auth gate | Done | HaikuMenu.lua, Main.lua |
| Re button → conditional on last opponent | Done | HaikuMenu.lua |
| Re button → confirmation dialog (now generic alert) | Done | HaikuMenu.lua |
| Re button → opponent avatar display | Done | HaikuMenu.lua |
| Records/Info buttons (Section 5) | Done | HaikuMenu.lua |
| Disclaimer text (Section 6) | Done | HaikuMenu.lua |
| GC sign-in overlay (wired to draw+touch) | Done | Main.lua |
| Swipe-to-reveal haiku (poof system) | Done | HaikuMenu.lua |
| Board control globals (size%, tilt, xOffset, rocking amplitude) | Done | HaikuMenu.lua |
| Debug 🐛 button (triggers generic alert) | Done | HaikuMenu.lua |
| Generic alert system (showGenericAlert/drawGenericAlert) | Done | HaikuMenu.lua |
| Diagnostic logging (print→devLog, ring buffer, _flushLogBuffer) | Done | Main.lua |
| File I/O diagnostic tests (testTextSaves/testImageSaves) | Done | Main.lua |
| Platform gotchas reference | Done | XCODE_CODEA.md |
| Project-agnostic orchestrator skill | Done | xcode-orchestrator.md |

### Confirmation dialog → Generic alert (refactored 2026-07-02)

The play-again confirmation was refactored into `showGenericAlert(config)` / `drawGenericAlert()`.
Usage:
```lua
showGenericAlert({
  message = "Are you sure?",
  avatar  = someSpriteOrNil,
  buttons = {
    { text = "yes", callback = function() ... end, isPrimary = true },
    { text = "no",  callback = function() end },
  },
})
```
All colors come from the seasonal `Color` palette. Buttons auto-layout across the panel width.
The "re" button and debug 🐛 button both use it.

### Unresolved issues

1. **Generic alert text overflow** — text can render partially outside the alert panel boundaries.
   The fixed panel height (244px) doesn't adapt to message length. `textSize()` with `textWrapWidth()`
   was unreliable for layout in this runtime, but a dynamic approach is still needed.

2. **"re" button activation depends on GC match replay data** — `getLastMatchReplaySettings()` reads `LAST_MATCH_REPLAY_KEY` from `saveLocalData()`. The button won't appear until a GC match is completed and persisted.

3. **Simulator hangs** — after repeated build/install/launch cycles, the CoreSimulator service can deadlock. See §16 recovery procedure.

4. **Game Center auth in simulator** — requires signing into Settings → Game Center. Without auth, the "Something Ker-Flumped" overlay appears when tapping VS or Re buttons.
