------------------------------------------------------------
-- MENU PANELS (2026-10-10)
-- Semi-transparent rounded panels on the main menu: a plate behind the season name, and
-- "board", "min. letters" and "game types" labels (replacing the loose text that used to sit
-- beside/below the board and dice). Designed in the Menu Panel Studio artifact; the values in
-- menuPanelDefaults are the look chosen there, and every one can be tuned live from
-- Debug Menu > Plate Placement (drawPlatePlacementOverlay, below). Tuned values persist via
-- saveLocalData (MENU_PANEL_KEY) and "Copy" exports them in the studio's paste format.
--
-- PLACEMENT: sizes and positions come from MenuLayout.lua (ratios anchored on the game board), not
-- from this file; fonts and line widths scale with the board (plateScale). Only the LOOK (fill,
-- line, shadow, text, tilt, stacking) is configured here. Tilt is degrees, clockwise-positive.
--
-- DRAWING: every shape is a mesh with per-vertex alpha (fill fan, inner-line ring, outer
-- hairline ring, soft shadow ring). drawRoundedRect can't be used for translucent shapes: it
-- builds the shape from overlapping thick lines, which double-blend. Meshes are cached by
-- size + look + resolved colors, so a season change or a tuning tweak rebuilds only what moved.
--
-- LAYERS: drawMenuPanelsLayer("back") runs right after the flecks (before the season name and
-- every menu element); ("front") runs after the last menu section. Each panel's z setting
-- ("front" | "behind" | "plateBehind" = plate behind, text in front) picks where its plate and
-- its text go.
------------------------------------------------------------

MENU_PANEL_KEY = "MenuPanelCfg"

menuPanelDefaults = {
  showSeason = true, showBoard = true, showDice = true, showGame = true, showDifficulty = true,
  zSeason = "behind", zBoard = "front", zDice = "front", zGame = "front", zDifficulty = "front",
  fillRole = "white", fillAlpha = 90, radius = 15,
  strokeRole = "ink", strokeAlpha = 95, strokeWidth = 1.3, strokeInset = 4,
  hairAlpha = 43, shadow = 18,
  textRole = "ink", labelSize = 14, numSize = 32, layout = "stack", gap = 4,
  diceLabel = "min. letters", gameLabel = "game types", gameSize = 20,
  haikuPlate = "fade",
  btilt = 0, stilt = 0, gtilt = 0, dtilt = 0.5,
}

local _cfg = nil

function menuPanelCfg()
  if _cfg then return _cfg end
  local cfg = {}
  for k, v in pairs(menuPanelDefaults) do cfg[k] = v end
  local raw = readLocalData(MENU_PANEL_KEY)
  if type(raw) == "string" and raw ~= "" then
    local ok, saved = pcall(json.decode, raw)
    if ok and type(saved) == "table" then
      for k, v in pairs(saved) do
        if menuPanelDefaults[k] ~= nil and type(v) == type(menuPanelDefaults[k]) then cfg[k] = v end
      end
    end
  end
  _cfg = cfg
  return cfg
end

function saveMenuPanelCfg()
  local ok, s = pcall(json.encode, menuPanelCfg())
  if ok and s then saveLocalData(MENU_PANEL_KEY, s) end
end

function resetMenuPanelCfg()
  _cfg = nil
  saveLocalData(MENU_PANEL_KEY, "")
  menuPanelCfg()
end

-- Colors are picked by ROLE so a look carries across seasons (Color is the active palette).
local function roleColor(role)
  if role == "white"  then return color(255, 255, 255, 255) end
  if role == "black"  then return color(0, 0, 0, 255) end
  if role == "accent" then return Color.uiAccent end
  if role == "accent2" then return Color.uiAccent2 end
  if role == "paper"  then return Color.tileFill end
  return Color.tileText   -- "ink"
end

function menuPanelShown(id)
  local c = menuPanelCfg()
  if id == "season" then return c.showSeason end
  if id == "board"  then return c.showBoard end
  if id == "dice"   then return c.showDice end
  if id == "game"   then return c.showGame end
  return false
end

-- Codea-space center of the season plate, or nil when the plate is off. The season name and
-- haiku are centered on this so the name sits in its plate wherever the plate is moved.
function menuPanelSeasonCenter()
  local c = menuPanelCfg()
  if not c.showSeason then return nil end
  local Lay = menuLayout(menuHasReplay())
  return Lay.season.cx, Lay.season.cy
end

------------------------------------------------------------
-- Meshes
------------------------------------------------------------

local function roundedPath(hw, hh, r, segs)
  r = math.max(0, math.min(r, hw, hh))
  local pts = {}
  local corners = {
    { hw - r,  hh - r, 0 }, { -(hw - r),  hh - r, 90 },
    { -(hw - r), -(hh - r), 180 }, { hw - r, -(hh - r), 270 },
  }
  for _, c in ipairs(corners) do
    for i = 0, segs do
      local a = math.rad(c[3] + 90 * i / segs)
      pts[#pts + 1] = { x = c[1] + r * math.cos(a), y = c[2] + r * math.sin(a), nx = math.cos(a), ny = math.sin(a) }
    end
  end
  return pts
end

-- A band along `pts`, from offset o1 (color c1) to offset o2 (color c2) along each point's normal.
local function addRing(V, C, pts, o1, o2, c1, c2, dy)
  dy = dy or 0
  local n = #pts
  for i = 1, n do
    local a, b = pts[i], pts[i % n + 1]
    local a1 = vec2(a.x + a.nx * o1, a.y + a.ny * o1 + dy)
    local a2 = vec2(a.x + a.nx * o2, a.y + a.ny * o2 + dy)
    local b1 = vec2(b.x + b.nx * o1, b.y + b.ny * o1 + dy)
    local b2 = vec2(b.x + b.nx * o2, b.y + b.ny * o2 + dy)
    V[#V + 1], C[#C + 1] = a1, c1
    V[#V + 1], C[#C + 1] = a2, c2
    V[#V + 1], C[#C + 1] = b2, c2
    V[#V + 1], C[#C + 1] = a1, c1
    V[#V + 1], C[#C + 1] = b2, c2
    V[#V + 1], C[#C + 1] = b1, c1
  end
end

local function addFan(V, C, pts, col)
  local n = #pts
  for i = 1, n do
    local a, b = pts[i], pts[i % n + 1]
    V[#V + 1], C[#C + 1] = vec2(0, 0), col
    V[#V + 1], C[#C + 1] = vec2(a.x, a.y), col
    V[#V + 1], C[#C + 1] = vec2(b.x, b.y), col
  end
end

local function withAlpha(c, a)
  return color(c.r, c.g, c.b, math.max(0, math.min(255, a)))
end

local function buildPanelMeshes(W, H, u, cfg, alphaMul)
  local hw, hh = W * 0.5, H * 0.5
  local r = math.min(cfg.radius * u, hh)
  local segs = 8
  local fillC   = roleColor(cfg.fillRole)
  local strokeC = roleColor(cfg.strokeRole)
  local out = {}

  local outline = roundedPath(hw, hh, r, segs)

  -- soft shadow: a ring fading from the edge outward, centered on the plate. (It used to be
  -- nudged down 3*u, which left a ~3u-wide gap between the plate's bottom edge and the ring.)
  if cfg.shadow > 0 then
    local V, C = {}, {}
    local blur = 12 * u
    addRing(V, C, outline, 0, blur,
      color(0, 0, 0, 255 * cfg.shadow / 100 * 0.55 * alphaMul), color(0, 0, 0, 0))
    local m = mesh(); m.vertices = V; m.colors = C
    out.shadow = m
  end

  do -- fill
    local V, C = {}, {}
    addFan(V, C, outline, withAlpha(fillC, 255 * cfg.fillAlpha / 100 * alphaMul))
    local m = mesh(); m.vertices = V; m.colors = C
    out.fill = m
  end

  if cfg.strokeAlpha > 0 and cfg.strokeWidth > 0 then -- thin line just inside the edge
    local sw = cfg.strokeWidth * u
    local ins = cfg.strokeInset * u + sw * 0.5
    local path = roundedPath(hw - ins, hh - ins, r - ins, segs)
    local V, C = {}, {}
    local col = withAlpha(strokeC, 255 * cfg.strokeAlpha / 100 * alphaMul)
    addRing(V, C, path, -sw * 0.5, sw * 0.5, col, col)
    local m = mesh(); m.vertices = V; m.colors = C
    out.stroke = m
  end

  if cfg.hairAlpha > 0 then -- hairline just outside the edge
    local V, C = {}, {}
    local col = withAlpha(strokeC, 255 * cfg.hairAlpha / 100 * alphaMul)
    addRing(V, C, outline, 0, math.max(1, u), col, col)
    local m = mesh(); m.vertices = V; m.colors = C
    out.hair = m
  end
  return out
end

local meshCache = {}
local meshCacheCount = 0

local function panelMeshes(W, H, u, cfg, alphaMul)
  local fc, sc = roleColor(cfg.fillRole), roleColor(cfg.strokeRole)
  local key = table.concat({
    math.floor(W * 10), math.floor(H * 10), math.floor(u * 100),
    cfg.radius, cfg.fillAlpha, cfg.strokeAlpha, cfg.strokeWidth, cfg.strokeInset, cfg.hairAlpha, cfg.shadow,
    fc.r, fc.g, fc.b, sc.r, sc.g, sc.b, math.floor(alphaMul * 12),
  }, ":")
  local e = meshCache[key]
  if not e then
    if meshCacheCount > 60 then meshCache, meshCacheCount = {}, 0 end  -- tuning sweeps make many keys
    e = buildPanelMeshes(W, H, u, cfg, math.floor(alphaMul * 12) / 12)
    meshCache[key] = e
    meshCacheCount = meshCacheCount + 1
  end
  return e
end

------------------------------------------------------------
-- Panel drawing
------------------------------------------------------------

local function panelSpecs()
  local c = menuPanelCfg()
  local Lay = menuLayout(menuHasReplay())
  local u = Lay.plateScale
  return {
    { id = "season", show = c.showSeason, z = c.zSeason, r = Lay.season, u = u, tilt = c.stilt,
      fades = (c.haikuPlate == "fade") },   -- fades via TextGoPoof_quickFade (see drawMenuPanelsLayer)
    { id = "board", show = c.showBoard, z = c.zBoard, r = Lay.boardPlate, u = u, tilt = c.btilt,
      label = "board", num = boardSize .. " × " .. boardSize },
    { id = "dice", show = c.showDice, z = c.zDice, r = Lay.dicePlate, u = u, tilt = c.dtilt,
      label = c.diceLabel, num = tostring(MIN_WORD_LEN) },
    { id = "diffEasy", show = c.showDifficulty, z = c.zDifficulty, r = Lay.difficultyPlates.easy, u = u, tilt = 0,
      label = "Easy", lsize = 15, selected = ((rerollDifficulty or "normal") == "easy"), hitKey = "diffEasy" },
    { id = "diffNormal", show = c.showDifficulty, z = c.zDifficulty, r = Lay.difficultyPlates.normal, u = u, tilt = 0,
      label = "Normal", lsize = 15, selected = ((rerollDifficulty or "normal") == "normal"), hitKey = "diffNormal" },
    { id = "diffHard", show = c.showDifficulty, z = c.zDifficulty, r = Lay.difficultyPlates.hard, u = u, tilt = 0,
      label = "Hard", lsize = 15, selected = ((rerollDifficulty or "normal") == "hard"), hitKey = "diffHard" },
    { id = "game", show = c.showGame, z = c.zGame, r = Lay.gamePlate, u = u, tilt = c.gtilt,
      label = c.gameLabel, lsize = c.gameSize },
  }
end

local function drawPlate(sp, alphaMul)
  local c = menuPanelCfg()
  local cx, cy, W, H, u = sp.r.cx, sp.r.cy, sp.r.w, sp.r.h, sp.u
  local m = panelMeshes(W, H, u, c, alphaMul)
  pushMatrix()
  translate(cx, cy)
  rotate(-sp.tilt)
  if m.shadow then m.shadow:draw() end
  m.fill:draw()
  if m.stroke then m.stroke:draw() end
  if m.hair then m.hair:draw() end
  popMatrix()
end

local function drawPanelText(sp, alphaMul)
  if not (sp.label or sp.num) then return end
  local c = menuPanelCfg()
  local cx, cy, u = sp.r.cx, sp.r.cy, sp.u
  local tc = roleColor(c.textRole)
  local lsz = (sp.lsize or c.labelSize) * u
  local nsz = c.numSize * u
  local gap = c.gap * u

  pushStyle()
  pushMatrix()
  translate(cx, cy)
  rotate(-sp.tilt)
  textMode(CENTER)
  textAlign(CENTER)
  fill(tc.r, tc.g, tc.b, 255 * alphaMul)

  if sp.label and sp.num and c.layout == "inline" then
    font("Georgia-Italic"); fontSize(lsz)
    local lw = textSize(sp.label)
    font("Georgia-Bold"); fontSize(nsz)
    local nw = textSize(sp.num)
    local total = lw + gap + nw
    font("Georgia-Italic"); fontSize(lsz)
    text(sp.label, -total * 0.5 + lw * 0.5, 0)
    font("Georgia-Bold"); fontSize(nsz)
    text(sp.num, total * 0.5 - nw * 0.5, 0)
  elseif sp.label and sp.num then
    local total = lsz + gap + nsz
    font("Georgia-Italic"); fontSize(lsz)
    text(sp.label, 0, total * 0.5 - lsz * 0.5)
    font("Georgia-Bold"); fontSize(nsz)
    text(sp.num, 0, -(total * 0.5 - nsz * 0.5))
  else
    font("Georgia-Italic"); fontSize(lsz)
    text(sp.label, 0, 0)
  end
  popMatrix()
  popStyle()
end

function drawMenuPanelsLayer(layer)
  for _, sp in ipairs(panelSpecs()) do
    if sp.show then
      local am = 1
      if sp.fades and TextGoPoof_quickFade then am = TextGoPoof_quickFade(0.10) end
      if sp.selected == false then am = am * 0.55 end  -- dim the non-active difficulty buttons
      if am > 0.01 then
        local z = sp.z
        if layer == "back" then
          if z == "behind" or z == "plateBehind" then drawPlate(sp, am) end
          if z == "behind" then drawPanelText(sp, am) end
        else
          if z == "front" then drawPlate(sp, am) end
          if z == "front" or z == "plateBehind" then drawPanelText(sp, am) end
        end
      end
      -- Hit rects for tappable plates (difficulty buttons): registered on the
      -- "front" pass, which runs after drawMenu()'s menuHitRects = {} reset.
      if layer == "front" and sp.hitKey then
        menuHitRects[sp.hitKey] = { cx = sp.r.cx, cy = sp.r.cy, w = sp.r.w, h = sp.r.h }
      end
    end
  end
end

------------------------------------------------------------
-- Export (same format the Menu Panel Studio produces, so values can be pasted back)
------------------------------------------------------------

local function fmtNum(v)
  if v == math.floor(v) then return string.format("%d", v) end
  return string.format("%.1f", v)
end

function menuPanelExportText()
  local c = menuPanelCfg()
  local L = { "-- Plate Placement (" .. tostring(seasons and seasons[seasonIndex] or "?") .. " shown; colors are roles, resolved per season)" }
  local keys = { "showSeason", "showBoard", "showDice", "showGame", "zSeason", "zBoard", "zDice", "zGame",
    "fillRole", "fillAlpha", "radius", "strokeRole", "strokeAlpha", "strokeWidth", "strokeInset", "hairAlpha", "shadow",
    "textRole", "labelSize", "numSize", "layout", "gap", "diceLabel", "gameLabel", "gameSize", "haikuPlate" }
  for _, k in ipairs(keys) do
    local v = c[k]
    if type(v) == "string" then v = '"' .. v .. '"' elseif type(v) == "number" then v = fmtNum(v) else v = tostring(v) end
    L[#L + 1] = "panel." .. k .. " = " .. v
  end
  L[#L + 1] = string.format("tilts: board=%s season=%s game=%s dice=%s   (placement comes from MenuLayout.lua)",
    fmtNum(c.btilt), fmtNum(c.stilt), fmtNum(c.gtilt), fmtNum(c.dtilt))
  return table.concat(L, "\n")
end

------------------------------------------------------------
-- PLATE PLACEMENT OVERLAY (opened from the Debug Menu)
-- A translucent control sheet over the live menu. One tab at a time keeps the sheet short; it
-- docks to the half of the screen away from whatever the tab is moving, and can be hidden.
------------------------------------------------------------

platePlacementOverlay = platePlacementOverlay or false
local ppTab = 1
local ppHidden = false
local ppDock = nil           -- nil = auto, true = top, false = bottom
local ppDrag = nil           -- { item, row } while a slider is being dragged
local ppRows = {}            -- hit rects rebuilt each frame
local ppButtons = {}
local ppTabRects = {}
local ppStatus = nil

local ROLE_OPTS  = { "ink", "accent", "accent2", "paper", "white", "black" }
local Z_OPTS     = { "front", "behind", "plateBehind" }

local PP_TABS = {
  { name = "Show", items = {
    { k = "showSeason", t = "bool", label = "Season plate" },
    { k = "showBoard",  t = "bool", label = "Board panel" },
    { k = "showDice",   t = "bool", label = "Min. letters panel" },
    { k = "showGame",   t = "bool", label = "Game types label" },
    { k = "haikuPlate", t = "cycle", label = "While haiku shows", opts = { "fade", "stay" } } } },
  { name = "Stack", items = {
    { k = "zSeason", t = "cycle", label = "Season plate", opts = Z_OPTS },
    { k = "zBoard",  t = "cycle", label = "Board panel", opts = Z_OPTS },
    { k = "zDice",   t = "cycle", label = "Min. letters", opts = Z_OPTS },
    { k = "zGame",   t = "cycle", label = "Game types", opts = Z_OPTS } } },
  { name = "Fill", items = {
    { k = "fillRole", t = "cycle", label = "Fill color", opts = ROLE_OPTS },
    { k = "fillAlpha", t = "slider", label = "Fill opacity", min = 0, max = 100, step = 1, u = "%" },
    { k = "radius", t = "slider", label = "Corner radius", min = 0, max = 44, step = 1, u = "pt" },
    { k = "shadow", t = "slider", label = "Drop shadow", min = 0, max = 40, step = 1, u = "%" },
    { k = "hairAlpha", t = "slider", label = "Outer hairline", min = 0, max = 100, step = 1, u = "%" } } },
  { name = "Line", items = {
    { k = "strokeRole", t = "cycle", label = "Line color", opts = ROLE_OPTS },
    { k = "strokeAlpha", t = "slider", label = "Line opacity", min = 0, max = 100, step = 1, u = "%" },
    { k = "strokeWidth", t = "slider", label = "Line width", min = 0.5, max = 3, step = 0.1, u = "pt" },
    { k = "strokeInset", t = "slider", label = "Inset", min = 2, max = 12, step = 0.5, u = "pt" } } },
  { name = "Text", items = {
    { k = "textRole", t = "cycle", label = "Text color", opts = ROLE_OPTS },
    { k = "layout", t = "cycle", label = "Arrangement", opts = { "stack", "inline" } },
    { k = "diceLabel", t = "cycle", label = "Dice wording", opts = { "min. letters", "minimum length", "min. word length" } },
    { k = "labelSize", t = "slider", label = "Label size", min = 9, max = 24, step = 1, u = "pt" },
    { k = "numSize", t = "slider", label = "Number size", min = 14, max = 56, step = 1, u = "pt" },
    { k = "gap", t = "slider", label = "Label-number gap", min = 0, max = 16, step = 1, u = "pt" } } },
  { name = "Tilt", items = {
    { k = "btilt", t = "slider", label = "Board plate", min = -10, max = 10, step = 0.5, u = "°" },
    { k = "dtilt", t = "slider", label = "Min. letters", min = -10, max = 10, step = 0.5, u = "°" },
    { k = "stilt", t = "slider", label = "Season plate", min = -10, max = 10, step = 0.5, u = "°" },
    { k = "gtilt", t = "slider", label = "Game types", min = -10, max = 10, step = 0.5, u = "°" } } },
  { name = "Game text", items = {
    { k = "gameSize", t = "slider", label = "Text size", min = 12, max = 34, step = 1, u = "pt" } } },
}

function openPlatePlacementOverlay()
  platePlacementOverlay = true
  ppHidden = false
  ppDrag = nil
  ppStatus = nil
end

local function ppClose()
  platePlacementOverlay = false
  ppDrag = nil
  saveMenuPanelCfg()
end

local function ppValueText(it, v)
  if it.t == "bool" then return v and "on" or "off" end
  if it.t == "cycle" then return tostring(v) end
  return fmtNum(v) .. (it.u or "")
end

local function ppSetSlider(it, v)
  local c = menuPanelCfg()
  v = math.max(it.min, math.min(it.max, v))
  v = math.floor(v / it.step + 0.5) * it.step
  c[it.k] = math.floor(v * 100 + 0.5) / 100
end

local function ppCycle(it)
  local c = menuPanelCfg()
  local cur, idx = c[it.k], 1
  for i, o in ipairs(it.opts) do if o == cur then idx = i end end
  c[it.k] = it.opts[idx % #it.opts + 1]
  saveMenuPanelCfg()
end

local function ppButton(x, y, w, h, label, active)
  pushStyle()
  rectMode(CORNER)
  noStroke()
  if active then fill(255, 255, 255, 70) else fill(255, 255, 255, 28) end
  rect(x, y, w, h)
  fill(255, 255, 255, 235)
  font("HelveticaNeue-Bold")
  fontSize(13)
  textMode(CENTER); textAlign(CENTER)
  text(label, x + w * 0.5, y + h * 0.5)
  popStyle()
end

local function ppHit(r, x, y)
  return r and x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function ppSheetLayout()
  local tab = PP_TABS[ppTab]
  local barH, tabH, rowH, pad = 44, 32, 40, 8
  local sheetW = WIDTH - 16
  local rows = #tab.items
  local h = barH + pad
  if not ppHidden then h = h + tabH * 2 + pad + rows * rowH + pad end
  -- Dock away from the panel being moved, unless overridden with the Dock button.
  local top = ppDock
  if top == nil then
    top = false
  end
  local x = 8
  local y
  if top then
    y = (getTopSafeY and getTopSafeY() or HEIGHT) - 4 - h
  else
    y = 8
  end
  return { x = x, y = y, w = sheetW, h = h, barH = barH, tabH = tabH, rowH = rowH, pad = pad, top = top }
end

function drawPlatePlacementOverlay()
  if not platePlacementOverlay then return end
  local L = ppSheetLayout()
  local tab = PP_TABS[ppTab]
  local c = menuPanelCfg()

  pushStyle()
  rectMode(CORNER)
  noStroke()
  fill(12, 22, 24, 205)
  rect(L.x, L.y, L.w, L.h)
  fill(255, 255, 255, 60)
  rect(L.x, L.y + (L.top and 0 or L.h - 1), L.w, 1)

  ppButtons, ppTabRects, ppRows = {}, {}, {}

  -- top bar: Hide / Dock / Copy / Reset / Done
  local bw = (L.w - 6 * 4) / 5
  local by = L.y + L.h - L.barH + 6
  local defs = {
    { id = "hide",  label = ppHidden and "Show" or "Hide" },
    { id = "dock",  label = "Dock " .. (ppDock == nil and "auto" or (ppDock and "top" or "bottom")) },
    { id = "copy",  label = "Copy" },
    { id = "reset", label = "Reset" },
    { id = "done",  label = "Done" },
  }
  for i, d in ipairs(defs) do
    local bx = L.x + 4 + (i - 1) * (bw + 4)
    ppButton(bx, by, bw, L.barH - 12, d.label, false)
    ppButtons[#ppButtons + 1] = { id = d.id, x = bx, y = by, w = bw, h = L.barH - 12 }
  end
  if ppStatus then
    fill(255, 255, 255, 200)
    font("HelveticaNeue")
    fontSize(11)
    textMode(CENTER); textAlign(CENTER)
    text(ppStatus, L.x + L.w * 0.5, by - 6)
  end

  if not ppHidden then
    -- tabs, two rows of five
    local tw = (L.w - 8) / 5
    local ty0 = L.y + L.h - L.barH - L.pad - L.tabH
    for i, t in ipairs(PP_TABS) do
      local col, row = (i - 1) % 5, math.floor((i - 1) / 5)
      local tx = L.x + 4 + col * tw
      local ty = ty0 - row * L.tabH
      ppButton(tx + 1, ty + 1, tw - 2, L.tabH - 2, t.name, i == ppTab)
      ppTabRects[#ppTabRects + 1] = { i = i, x = tx, y = ty, w = tw, h = L.tabH }
    end

    -- rows
    local rowTop = ty0 - L.tabH - L.pad
    for i, it in ipairs(tab.items) do
      local ry = rowTop - i * L.rowH
      local v = c[it.k]
      fill(255, 255, 255, 225)
      font("HelveticaNeue")
      fontSize(13)
      textMode(CORNER); textAlign(LEFT)
      text(it.label, L.x + 10, ry + L.rowH * 0.5 - 7)
      local labelW = 118
      local rect_ = { x = L.x, y = ry, w = L.w, h = L.rowH, it = it }
      if it.t == "slider" then
        local minusX = L.x + labelW + 4
        local nb = 28
        local plusX = L.x + L.w - 56 - nb
        local trackX0, trackX1 = minusX + nb + 6, plusX - 6
        ppButton(minusX, ry + 6, nb, L.rowH - 12, "-", false)
        ppButton(plusX, ry + 6, nb, L.rowH - 12, "+", false)
        local f = (v - it.min) / (it.max - it.min)
        local ty = ry + L.rowH * 0.5
        stroke(255, 255, 255, 90); strokeWidth(2); lineCapMode(ROUND)
        line(trackX0, ty, trackX1, ty)
        stroke(255, 255, 255, 230)
        line(trackX0, ty, trackX0 + (trackX1 - trackX0) * f, ty)
        noStroke(); fill(255, 255, 255, 255)
        ellipse(trackX0 + (trackX1 - trackX0) * f, ty, 16)
        fill(255, 255, 255, 235)
        font("HelveticaNeue-Bold"); fontSize(12)
        textMode(CORNER); textAlign(LEFT)
        text(ppValueText(it, v), plusX + nb + 4, ry + L.rowH * 0.5 - 6)
        rect_.minus = { x = minusX, y = ry + 6, w = nb, h = L.rowH - 12 }
        rect_.plus  = { x = plusX,  y = ry + 6, w = nb, h = L.rowH - 12 }
        rect_.trackX0, rect_.trackX1 = trackX0, trackX1
      else
        local bx = L.x + labelW + 4
        ppButton(bx, ry + 5, L.w - labelW - 14, L.rowH - 10, ppValueText(it, v), it.t == "bool" and v or false)
        rect_.toggle = { x = bx, y = ry + 5, w = L.w - labelW - 14, h = L.rowH - 10 }
      end
      ppRows[#ppRows + 1] = rect_
    end
  end
  popStyle()
end

local function ppRowAt(x, y)
  for _, r in ipairs(ppRows) do
    if x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h then return r end
  end
  return nil
end

local function ppDragTo(r, x)
  local it = r.it
  local f = (x - r.trackX0) / (r.trackX1 - r.trackX0)
  ppSetSlider(it, it.min + (it.max - it.min) * math.max(0, math.min(1, f)))
end

function handlePlatePlacementTouch(t)
  if not platePlacementOverlay then return false end
  local c = menuPanelCfg()

  if t.state == BEGAN then
    local r = ppRowAt(t.x, t.y)
    if r and r.it.t == "slider" then
      if ppHit(r.minus, t.x, t.y) then
        ppSetSlider(r.it, c[r.it.k] - r.it.step); saveMenuPanelCfg()
      elseif ppHit(r.plus, t.x, t.y) then
        ppSetSlider(r.it, c[r.it.k] + r.it.step); saveMenuPanelCfg()
      elseif t.x >= r.trackX0 - 12 and t.x <= r.trackX1 + 12 then
        ppDrag = r
        ppDragTo(r, t.x)
      end
    end
  elseif t.state == MOVING then
    if ppDrag then ppDragTo(ppDrag, t.x) end
  elseif t.state == ENDED or t.state == CANCELLED then
    if ppDrag then
      ppDragTo(ppDrag, t.x)
      ppDrag = nil
      saveMenuPanelCfg()
      ppStatus = "Saved (kept across launches)"
      return true
    end
    if t.state == ENDED then
      for _, b in ipairs(ppButtons) do
        if ppHit(b, t.x, t.y) then
          if b.id == "hide" then ppHidden = not ppHidden
          elseif b.id == "dock" then
            if ppDock == nil then ppDock = true elseif ppDock == true then ppDock = false else ppDock = nil end
          elseif b.id == "copy" then
            local txt = menuPanelExportText()
            print(txt)
            local ok = pcall(function() pasteboard.copy(txt) end)
            ppStatus = ok and "Copied values to the clipboard (also in the log)" or "Clipboard unavailable; values are in the log"
          elseif b.id == "reset" then
            resetMenuPanelCfg()
            ppStatus = "Reset to the saved design defaults"
          elseif b.id == "done" then
            ppClose()
          end
          return true
        end
      end
      for _, tr in ipairs(ppTabRects) do
        if ppHit(tr, t.x, t.y) then ppTab = tr.i; return true end
      end
      local r = ppRowAt(t.x, t.y)
      if r and r.toggle and ppHit(r.toggle, t.x, t.y) then
        if r.it.t == "bool" then
          c[r.it.k] = not c[r.it.k]; saveMenuPanelCfg()
        else
          ppCycle(r.it)
        end
      end
    end
  end
  return true   -- the sheet eats every touch while it's open; the menu behind is just a live preview
end
