-- Layout invariants for the main menu across phone screen shapes.  Run: lua tests/menu_layout_test.lua
local ROOT = arg[0]:match("(.*)/tests/menu_layout_test%.lua$") or "."
dofile(ROOT .. "/Quozzy.codea/MenuLayout.lua")

local fails, passes = {}, 0
local function check(name, cond, detail)
  if cond then passes = passes + 1 else fails[#fails + 1] = "FAIL: " .. name .. (detail and (" — " .. detail) or "") end
end
local function near(a, b, tol) return math.abs(a - b) <= tol end

-- 1. The reference screen reproduces the studio plate rects (top-left, y down; 390 x 844) within 1.5pt.
do
  local W, H = 390, 844
  local L = computeMenuLayout(W, H, 47, 8, false)
  local function studio(name, p, x, y, w, h)
    local cx, cy = x + w / 2, H - (y + h / 2)
    check("ref " .. name .. " cx", near(p.cx, cx, 1.5), p.cx .. " vs " .. cx)
    check("ref " .. name .. " cy", near(p.cy, cy, 1.5), p.cy .. " vs " .. cy)
    check("ref " .. name .. " w", near(p.w, w, 1.5), p.w .. " vs " .. w)
    check("ref " .. name .. " h", near(p.h, h, 1.5), p.h .. " vs " .. h)
  end
  studio("board plate", L.boardPlate, 36, 239, 131, 88)
  studio("game plate", L.gamePlate, 32, 607, 137, 47)
  studio("season plate", L.season, 20, 60, 350, 137)
  check("ref dice plate w equals board plate", near(L.dicePlate.w, L.boardPlate.w, 0.01))
  check("ref dice plate cx", near(L.dicePlate.cx, 268.5, 1.5), L.dicePlate.cx)
  check("ref dice plate cy", near(L.dicePlate.cy, H - 548.5, 2), L.dicePlate.cy)
end

-- 2. Real phones: nothing off-screen, season band comfortable, plates stay with their anchors.
local phones = {
  { "iPhone SE (16:9)", 375, 667, 24 },
  { "iPhone 13 mini",   360, 780, 50 },
  { "iPhone 16e",       390, 844, 47 },
  { "iPhone 17",        402, 874, 62 },
  { "iPhone 17 Pro Max", 440, 956, 62 },
}
for _, ph in ipairs(phones) do
  local name, W, H, inset = ph[1], ph[2], ph[3], ph[4]
  for _, replay in ipairs({ false, true }) do
    local L = computeMenuLayout(W, H, inset, 8, replay)
    local tag = name .. (replay and " (3 buttons)" or "")
    local function inside(label, r)
      check(tag .. ": " .. label .. " on screen",
        r.cx - r.w / 2 >= -0.5 and r.cx + r.w / 2 <= W + 0.5 and r.cy - r.h / 2 >= -0.5 and r.cy + r.h / 2 <= H + 0.5,
        string.format("cx=%.0f cy=%.0f w=%.0f h=%.0f", r.cx, r.cy, r.w, r.h))
    end
    inside("board plate", L.boardPlate); inside("dice plate", L.dicePlate)
    inside("game plate", L.gamePlate);   inside("season plate", L.season)
    inside("board bbox", { cx = L.board.cx, cy = L.board.cy, w = L.board.bbox, h = L.board.bbox })
    check(tag .. ": season plate clears the safe top", L.season.cy + L.season.h / 2 <= H - inset + 0.5)
    check(tag .. ": season plate sits above the board", L.season.cy - L.season.h / 2 >= L.board.top - 0.5)
    check(tag .. ": season band >= 0.13H", L.season.h >= 0.13 * H - 0.5, string.format("%.0f vs %.0f", L.season.h, 0.13 * H))
    check(tag .. ": board bbox <= 0.73W", L.board.bbox <= 0.7241 * W + 0.01)
    check(tag .. ": min letters plate matches board plate size", L.dicePlate.w == L.boardPlate.w and L.dicePlate.h == L.boardPlate.h)
    check(tag .. ": buttons fit the width", L.buttons.startX - L.buttons.w / 2 >= 0 and
      L.buttons.startX + (L.buttons.count - 1) * (L.buttons.w + L.buttons.gap) + L.buttons.w / 2 <= W)
    -- the board plate must stay left of the screen's right edge and overlap the bbox, not detach from it
    local bp = L.boardPlate
    check(tag .. ": board plate overlaps the board", bp.cx + bp.w / 2 > L.board.cx - L.board.bbox / 2)
    check(tag .. ": game plate overlaps the first play button", L.gamePlate.cx + L.gamePlate.w / 2 > L.buttons.startX - L.buttons.w / 2)
    if not replay then
      print(string.format("%-18s board %.0f(%.0f%%W) bottom %.0f | season h %.0f of band %.0f | plate %.0fx%.0f",
        name, L.board.bbox, 100 * L.board.bbox / W, L.board.bottom, L.season.h, L.topEdge - L.board.top, L.boardPlate.w, L.boardPlate.h))
    end
  end
end

for _, f in ipairs(fails) do print(f) end
print(string.format("menu layout: %d passed, %d failed", passes, #fails))
os.exit(#fails == 0 and 0 or 1)
