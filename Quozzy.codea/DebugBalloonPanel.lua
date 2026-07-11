BALLOON_DEBUG = BALLOON_DEBUG or true

if not BALLOON_DEBUG then
  function drawDebugBalloonPanel() end
  function handleDebugBalloonTouch(t) return false end
  return
end

dbgBalloon = {
  topBalloonY  = 0,
  botBalloonY  = 0,
  topBalloonX  = 0,
  botBalloonX  = 0,
  topTailBase  = 25,
  botTailBase  = 29,
}

local activeKey  = nil   -- "topY","botY","topX","botX","topTB","botTB"
local prevTouchY = 0
local prevTouchX = 0

local function panelRect()
  local pw = math.min(WIDTH * 0.72, 340)
  local ph = 270
  return { cx = WIDTH * 0.5, cy = HEIGHT * 0.38, w = pw, h = ph }
end

function drawDebugBalloonPanel()
  local pr = panelRect()
  local bg = color(30, 30, 30, 210)
  drawRoundedRect(pr.cx, pr.cy, pr.w, pr.h, 18, bg, bg)

  local leftCX   = pr.cx - pr.w * 0.25
  local rightCX  = pr.cx + pr.w * 0.25
  local labelY   = pr.cy + 109
  local yNumY    = pr.cy + 59
  local xNumY    = pr.cy - 11
  local tbLabelY = pr.cy - 63
  local tbNumY   = pr.cy - 103

  pushStyle()
  noStroke()
  textAlign(CENTER); textMode(CENTER)

  fill(255, 200, 50, 180)
  fontSize(15)
  font("HelveticaNeue")
  text("Top",    leftCX,  labelY)
  text("Bottom", rightCX, labelY)

  fontSize(54)
  font("HelveticaNeue-Bold")
  fill(activeKey == "topY" and color(255, 235, 120) or color(255, 200, 50))
  text(string.format("%.0f", dbgBalloon.topBalloonY), leftCX, yNumY)
  fill(activeKey == "botY" and color(255, 235, 120) or color(255, 200, 50))
  text(string.format("%.0f", dbgBalloon.botBalloonY), rightCX, yNumY)

  fill(activeKey == "topX" and color(255, 235, 120) or color(255, 200, 50))
  text(string.format("%.0f", dbgBalloon.topBalloonX), leftCX, xNumY)
  fill(activeKey == "botX" and color(255, 235, 120) or color(255, 200, 50))
  text(string.format("%.0f", dbgBalloon.botBalloonX), rightCX, xNumY)

  fill(255, 200, 50, 180)
  fontSize(13)
  font("HelveticaNeue")
  text("Tail Base", leftCX,  tbLabelY)
  text("Tail Base", rightCX, tbLabelY)

  fontSize(54)
  font("HelveticaNeue-Bold")
  fill(activeKey == "topTB" and color(255, 235, 120) or color(255, 200, 50))
  text(string.format("%.0f", dbgBalloon.topTailBase), leftCX, tbNumY)
  fill(activeKey == "botTB" and color(255, 235, 120) or color(255, 200, 50))
  text(string.format("%.0f", dbgBalloon.botTailBase), rightCX, tbNumY)

  popStyle()
end

function handleDebugBalloonTouch(t)
  if activeKey then
    if t.state == MOVING then
      if activeKey == "topY" then
        dbgBalloon.topBalloonY = dbgBalloon.topBalloonY + (t.y - prevTouchY)
      elseif activeKey == "botY" then
        dbgBalloon.botBalloonY = dbgBalloon.botBalloonY + (t.y - prevTouchY)
      elseif activeKey == "topX" then
        dbgBalloon.topBalloonX = dbgBalloon.topBalloonX + (t.x - prevTouchX)
      elseif activeKey == "botX" then
        dbgBalloon.botBalloonX = dbgBalloon.botBalloonX + (t.x - prevTouchX)
      elseif activeKey == "topTB" then
        dbgBalloon.topTailBase = math.max(4, dbgBalloon.topTailBase + (t.y - prevTouchY))
      elseif activeKey == "botTB" then
        dbgBalloon.botTailBase = math.max(4, dbgBalloon.botTailBase + (t.y - prevTouchY))
      end
      prevTouchY = t.y
      prevTouchX = t.x
      return true
    elseif t.state == ENDED or t.state == CANCELLED then
      activeKey = nil
      return true
    end
    return true
  end

  local pr = panelRect()
  if not pointInRect(t.x, t.y, pr.cx, pr.cy, pr.w, pr.h) then return false end

  if t.state == BEGAN then
    local isLeft = t.x < pr.cx
    if t.y > pr.cy + 24 then
      activeKey = isLeft and "topY" or "botY"
    elseif t.y > pr.cy - 57 then
      activeKey = isLeft and "topX" or "botX"
    else
      activeKey = isLeft and "topTB" or "botTB"
    end
    prevTouchY = t.y
    prevTouchX = t.x
    return true
  end

  return true
end
