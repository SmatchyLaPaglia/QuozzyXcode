function buildEndScreenModel()
  local q = currentQMatch
  local localId = localPID()
  local otherId, pLocal, pOther
 
  if q and q.players then
    for pid,_ in pairs(q.players) do
      if pid ~= localId then otherId = pid break end
    end
  end
  
  pLocal = q and q.players and q.players[localId]
  pOther = q and q.players and otherId and q.players[otherId]
  
  if otherId then
    local qp = qPlayersById and qPlayersById[otherId]
    avatar2 = qp and qp.avatar
  end
  
  local endState = currentEndScreenState()
  local is2P     = (endState ~= END_STATE_SINGLE)
  local complete = (endState == END_STATE_2P_COMPLETE)
  local assignedOpponent = (otherId ~= nil and otherId ~= "")
  local rawOppName = (q and (q.otherName or q.opponentName)) or opponentAlias or ""
  local oppDisplayName = assignedOpponent and rawOppName or ""
  local opponentAvatarOverride = nil
  if not assignedOpponent and genericOpponentAvatar then
    opponentAvatarOverride = genericOpponentAvatar()
  end

  local waitingWords
  if not complete then
    if assignedOpponent then
      waitingWords = {
        "waiting for",
        "opponent",
        "to play",
      }
    else
      waitingWords = {
        "waiting for",
        "opponent",
      }
    end
  end
  
  local scoreA = (pLocal and pLocal.score) or (score or 0)
  local scoreB = (pOther and pOther.score) or 0
  
  local rec = opponentRecords and opponentRecords[otherId] or nil
  local wins   = rec and rec.wins or 0
  local losses = rec and rec.losses or 0
  
  local line1 = nil
  if complete then
    if scoreA > scoreB then
      line1 = string.format("You won %d to %d!", scoreA, scoreB)
    elseif scoreA < scoreB then
      line1 = string.format("You lost %d to %d!", scoreA, scoreB)
    else
      line1 = string.format("Tie game, %d all!", scoreA)
    end
  end

  -- Ensure W/L summary reflects the just-finished match even if persistence
  -- hasn't been updated yet.
  if complete and assignedOpponent then
    local alreadyCounted = false
    if q and q.recordOutcomeApplied then
      alreadyCounted = true
    else
      local recUpdatedAt = math.floor(tonumber(rec and rec.updatedAt) or 0)
      local matchUpdatedAt = math.floor(tonumber(q and q.lastUpdated) or 0)
      if matchUpdatedAt > 0 and recUpdatedAt >= matchUpdatedAt then
        alreadyCounted = true
      end
    end

    if not alreadyCounted then
      if scoreA > scoreB then
        wins = wins + 1
      elseif scoreA < scoreB then
        losses = losses + 1
      end
    end
  end
  
  local line2 = (complete and assignedOpponent)
  and string.format("Win/Loss vs This Player: %d / %d", wins, losses)
  or nil
  
  return {
    
    dimColor = Color.panelDim,
    
    headers = is2P and {
      column1 = "you",
      column2 = oppDisplayName,
      color   = Color.tileText or color(40,80,60,255)
    } or nil,
    opponentAvatar = opponentAvatarOverride,
    
    -- SINGLE PLAYER LIST
    singleList = (not is2P) and (currentFoundWords() or {}) or nil,
    
    -- TWO PLAYER COLUMNS (POSITIONAL ONLY)
    column1 = is2P and {
      words = (pLocal and pLocal.words) or {}
    } or nil,
    
    column2 = is2P and {
      words = complete
      and ((pOther and pOther.words) or {})
      or waitingWords
    } or nil,
    
    totals = {
      line1 = line1,
      line2 = line2,
      color = Color.tileText or color(40,80,60,255)
    },
    
    button = {
      -- label = is2P and "Play Another Match" or playAgainLabel,
      label == is2P and nil or playAgainLabel,
      action = function()
        if is2P then
          -- hook later
        else
          rotatePlayAgainLabel()
          currentQMatch = nil
          startRoundFromCurrentSettings()
        end
      end
    }
  }
end

function drawEndScreenFP()
  scrollListCol1 = scrollListCol1 or ScrollList.new()
  scrollListCol2 = scrollListCol2 or ScrollList.new()
  ensureEndScreenLayout()
  local model = buildEndScreenModel()
  drawEndScreenWith(model, endScreenLayout)
end

function drawEndScreenWith(model, layout)
  local C = Color
  
  -- dim overlay
  if model.dimColor then
    pushStyle()
    fill(model.dimColor)
    noStroke()
    rectMode(CORNER)
    rect(0,0,WIDTH,HEIGHT)
    popStyle()
  end
  
  -- panel
  local panelSprite = overlayPanelEnd
  if panelSprite then
    pushStyle()
    spriteMode(CENTER)
    tint(255,255,255,(C.panelBG and C.panelBG.a) or 255)
    sprite(panelSprite, layout.panelX, layout.panelY, layout.panelW, layout.panelH)
    popStyle()
  else
    local bg = C.panelBG or color(245,242,232,255)
    drawRoundedRect(
    layout.panelX, layout.panelY,
    layout.panelW, layout.panelH,
    layout.cornerRadius,
    bg, bg
    )
  end
  
  -- top row
  drawEndTopRowContent(
  layout.boardCX, layout.boardCY, layout.boardSide,
  layout.rightCX, layout.rightW,
  layout.msgCY, layout.msgH,
  layout.scoreCY, layout.scoreH,
  model
  )
  ------------------------------------------------------------
  -- headers
  ------------------------------------------------------------
  
  if model.headers then
    drawEndWordColumnHeaders{
      yourCX   = layout.yourWordsCX,
      theirCX  = layout.theirWordsCX,
      titlesCY = layout.titlesCY,
      oppName  = model.headers.column2,
      titleH   = layout.titleH,
      color    = model.headers.color
    }
  end
  
  ------------------------------------------------------------
  -- lists (neutral columns)
  ------------------------------------------------------------

  
  if model.singleList ~= nil then
    renderList(endWordList, layout.singleListRect, model.singleList, model)
  else
    if model.column1 then
      renderList(scrollListCol1, layout.yourListRect, model.column1.words, model)
    end
    
    if model.column2 then
      renderList(scrollListCol2, layout.theirListRect, model.column2.words, model)
    end
  end
  
  ------------------------------------------------------------
  -- totals (pure text)
  ------------------------------------------------------------
  
  if model.totals then
    pushStyle()
    fill(model.totals.color)
    textAlign(CENTER)
    textMode(CENTER)
    
    local cy = layout.oppStatsCY
    
    if model.totals.line1 then
      fontSize(22)
      text(model.totals.line1, layout.panelX, cy + 10)
    end
    
    if model.totals.line2 then
      fontSize(16)
      text(model.totals.line2, layout.panelX, cy - 14)
    end
    
    popStyle()
  end
  
  ------------------------------------------------------------
  -- button
  ------------------------------------------------------------
  
  if model.button and model.button.label then
    drawEndScreenButton(
    layout.playAgainRect,
    model.button.label,
    model.button.action
    )
  end
  
  ------------------------------------------------------------
  -- close button
  ------------------------------------------------------------
  
  pushStyle()
  ellipseMode(CENTER)
  noStroke()
  fill(Color.uiAccent)
  ellipse(layout.closeX, layout.closeY, layout.closeSize, layout.closeSize)
  
  fill(255)
  textAlign(CENTER)
  textMode(CENTER)
  fontSize(layout.closeSize * 0.75)
  text("×", layout.closeX, layout.closeY + 2)
  popStyle()
end

function makeRowRenderer(entries,
  model)
  return function(row, y, x)
    local e = entries[row]
    local textValue, pts
    
    if type(e) == "table" then
      textValue = e.word or ""
      pts = e.points
    else
      textValue = tostring(e or "")
    end
    
    local label = pts and string.format("%s  (+%d)", textValue, pts) or textValue
    
    pushStyle()
    textAlign(LEFT)
    textMode(CORNER)
    fontSize(24)
    fill(model.wordColor or Color.uiAccent)
    text(label, x, y)
    popStyle()
  end
end

function renderList(listObject, rect, entries, model)
  local padT, padB, lineH = 6, 10, 28  
  if not rect or not entries then return end
  
  local r = {
    x = rect.x,
    y = rect.y + padB,
    w = rect.w,
    h = rect.h - padT - padB
  }
  
  listObject:draw(r, #entries, lineH, makeRowRenderer(entries, model), r.x + 10)
end

function drawEndScreenButton(rect, label, action)
  endScreen2PButtonRect = rect
  
  drawRoundedRect(
  rect.x + rect.w*0.5,
  rect.y + rect.h*0.5,
  rect.w,
  rect.h,
  22,
  Color.uiAccent,
  Color.uiAccent
  )
  
  pushStyle()
  fill(255)
  textAlign(CENTER)
  textMode(CENTER)
  fontSize(rect.h * 0.32)
  text(label, rect.x + rect.w*0.5, rect.y + rect.h*0.5)
  popStyle()
  
  endScreenButtonAction = action
end
