endScreenMissedWordsJob = endScreenMissedWordsJob or nil
endScreenMissedWordsJobMatchId = endScreenMissedWordsJobMatchId or nil

local function clearMissedWordsJob()
  endScreenMissedWordsJob = nil
  endScreenMissedWordsJobMatchId = nil
end

local function beginMissedWordsJob(q)
  if not q or not q.boardTiles or not createIncrementalBoardWordSolver then return end
  local n = q.boardSize or inferBoardSizeFromTiles(q.boardTiles) or 4
  local solver = createIncrementalBoardWordSolver(q.boardTiles, n, q.minWordLen or MIN_WORD_LEN)
  if not solver then return end

  ensureWordPathsForPlayers(q)

  endScreenMissedWordsJobMatchId = q.id
  endScreenMissedWordsJob = coroutine.create(function()
    while not solver.done do
      solver:step(250)
      coroutine.yield(false)
    end

    local allWords, wordPaths = solver:getResults()
    local foundSet = {}
    if q.players then
      for _, p in pairs(q.players) do
        for _, entry in ipairs((p and p.words) or {}) do
          local w = type(entry) == "table" and entry.word or tostring(entry or "")
          if w ~= "" then
            foundSet[string.upper(w)] = true
          end
        end
      end
    end

    local missed = {}
    for i = 1, #allWords do
      local entry = allWords[i]
      if not foundSet[entry.word] then
        missed[#missed + 1] = entry
      end
    end

    q.wordPaths = wordPaths
    q.missedWords = missed
    coroutine.yield(true)
  end)
end

local function pumpMissedWordsJobIfNeeded(activeCard)
  local q = currentQMatch
  if not q or not activeCard or not activeCard.isMissedPlaceholder then return end
  if q.missedWords then
    clearMissedWordsJob()
    return
  end
  if endScreenMissedWordsJobMatchId ~= q.id or not endScreenMissedWordsJob then
    clearMissedWordsJob()
    beginMissedWordsJob(q)
  end
  if not endScreenMissedWordsJob then return end
  if coroutine.status(endScreenMissedWordsJob) == "dead" then
    clearMissedWordsJob()
    return
  end
  local ok = coroutine.resume(endScreenMissedWordsJob)
  if not ok then
    clearMissedWordsJob()
  end
end

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
  
  local isSinglePlayer = (not otherId)
  local matchComplete = complete or isSinglePlayer

  if q and matchComplete and ensureWordPathsForPlayers then
    ensureWordPathsForPlayers(q)
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
    missedWords = q and q.missedWords or nil,
    missedWordsPending = matchComplete and (q ~= nil) and not (q and q.missedWords),

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
      label = is2P and nil or playAgainLabel,
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
  -- Animate card snap toward 0 (exponential decay)
  if endCardAnimPx and math.abs(endCardAnimPx) > 0.5 then
    endCardAnimPx = endCardAnimPx * 0.72
  else
    endCardAnimPx = 0
  end
  -- Reset card state when the match changes
  local qid = currentQMatch and currentQMatch.id
  if endScreenLastMatchId ~= qid then
    endScreenLastMatchId     = qid
    endCardIndex             = 1
    endCardAnimPx            = 0
    endCardDragPx            = 0
    endScreenHighlightedPath = nil
    endScreenHighlightedWord = nil
    endScreenCurrentCardWords = {}
    if endCardScrollLists then
      for i = 1, #endCardScrollLists do
        endCardScrollLists[i].scroll = 0
        endCardScrollLists[i].vel    = 0
      end
    end
    clearMissedWordsJob()
  end
  ensureEndScreenLayout()
  local model = buildEndScreenModel()
  drawEndScreenWith(model, endScreenLayout)
end

-- Builds the ordered list of swipeable cards from the end-screen model.
-- Always: card 1 = yours. 2P adds theirs as card 2. Missed appended when available.
function buildEndScreenCards(model)
  local cards = {}
  if model.singleList ~= nil then
    cards[1] = { label = "Your Words", words = model.singleList }
  else
    cards[1] = { label = "Your Words", words = (model.column1 and model.column1.words) or {} }
    if model.column2 then
      local lbl = (model.headers and model.headers.column2 ~= "" and model.headers.column2) or "Theirs"
      cards[2] = { label = lbl, words = model.column2.words }
    end
  end
  if model.missedWords then
    cards[#cards + 1] = { label = "Missed", words = model.missedWords }
  elseif model.missedWordsPending then
    cards[#cards + 1] = { label = "Missed", words = {}, isMissedPlaceholder = true }
  end
  return cards
end

local function drawMissedCardActivityIndicator(rect)
  if not rect then return end
  local cx = rect.x + rect.w * 0.5
  local cy = rect.y + rect.h * 0.56
  local ringR = math.min(rect.w, rect.h) * 0.12
  local dotR = math.max(4, ringR * 0.16)
  local phase = ElapsedTime * 2.8
  local accent = Color.uiAccent or color(40, 80, 60, 255)
  local textCol = Color.tileText or accent

  pushStyle()
  ellipseMode(CENTER)
  noStroke()
  for i = 1, 8 do
    local a = phase + (i - 1) * (math.pi * 0.25)
    local alpha = math.floor(45 + 210 * (i / 8))
    fill(accent.r, accent.g, accent.b, alpha)
    ellipse(cx + math.cos(a) * ringR, cy + math.sin(a) * ringR, dotR * 2, dotR * 2)
  end

  fill(textCol)
  textAlign(CENTER)
  textMode(CENTER)
  font("Helvetica")
  fontSize(math.max(20, rect.h * 0.065))
  text("Finding missed words", cx, cy - ringR - rect.h * 0.10)
  popStyle()
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
  -- cards (swipeable word lists: yours / theirs / missed)
  ------------------------------------------------------------

  local cards    = buildEndScreenCards(model)
  local numCards = #cards
  endCardCount   = numCards
  if endCardIndex > numCards then endCardIndex = numCards end
  if endCardIndex < 1        then endCardIndex = 1        end
  endScreenCurrentCardWords = (cards[endCardIndex] and cards[endCardIndex].words) or {}
  pumpMissedWordsJobIfNeeded(cards[endCardIndex])

  -- Card header: centered label + word count for the currently visible card
  if layout.cardHeaderCY and numCards > 0 then
    local card = cards[endCardIndex]
    if card then
      pushStyle()
      textAlign(CENTER)
      textMode(CENTER)
      fontSize(layout.cardHeaderH * 0.44)
      fill(model.headers and model.headers.color or (Color.tileText or color(40,80,60,255)))
      local headerLabel = card.label .. " (" .. #card.words .. ")"
      text(headerLabel, layout.panelX, layout.cardHeaderCY)
      popStyle()
    end
  end

  -- Cards (clipped to list area, offset by swipe/drag)
  if layout.cardListRect then
    local lr  = layout.cardListRect
    local cw  = layout.cardW or lr.w
    local off = (endCardAnimPx or 0) + (endCardDragPx or 0)

    -- Card backgrounds drawn BEFORE clip so rounded corners aren't scissored off
    -- drawRoundedRect internally forces strokeWidth = r*2, so we draw fill and
    -- the 1px border as two separate passes.
    local cardBG     = Color.panelBG    or color(245, 242, 232, 255)
    local cardBorder = Color.tileStroke or color(180, 160, 140, 255)
    for i = 1, numCards do
      local xOff = (i - endCardIndex) * cw + off
      if math.abs(xOff) < cw * 1.5 then
        local cx2 = lr.x + xOff + lr.w * 0.5
        local cy2 = lr.y + lr.h * 0.5
        local cw2 = lr.w - 6
        local ch2 = lr.h - 6
        -- filled rounded shape (stroke same as fill so drawRoundedRect's thick
        -- internal stroke is invisible)
        drawRoundedRect(cx2, cy2, cw2, ch2, 14, cardBG, cardBG)
        -- 1px border as a plain rect on top
        pushStyle()
        noFill()
        stroke(cardBorder)
        strokeWidth(1)
        rectMode(CENTER)
        rect(cx2, cy2, cw2, ch2)
        popStyle()
      end
    end

    local padV = layout.cardPadV or 0
    clip(lr.x, lr.y, lr.w, lr.h)
    for i = 1, numCards do
      local xOff = (i - endCardIndex) * cw + off
      if math.abs(xOff) < cw * 1.5 then
        local cr = { x = lr.x + xOff, y = lr.y + padV, w = lr.w, h = lr.h - 2 * padV }
        if cards[i].isMissedPlaceholder then
          drawMissedCardActivityIndicator(cr)
        else
          renderList(endCardScrollLists[i], cr, cards[i].words, model)
        end
      end
    end
    clip()
  end

  -- Page dots
  if layout.cardDotsY then
    drawCardPageDots(layout, numCards, endCardIndex)
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

-- Draws page-position dot indicators for the card carousel.
function drawCardPageDots(layout, numCards, activeIndex)
  if numCards <= 1 or not layout.cardDotsY then return end
  local dotR  = 5
  local gap   = 16
  local totalW = (numCards - 1) * gap
  local startX = layout.panelX - totalW * 0.5
  local y      = layout.cardDotsY
  local C      = Color
  pushStyle()
  ellipseMode(CENTER)
  noStroke()
  for i = 1, numCards do
    local x = startX + (i - 1) * gap
    if i == activeIndex then
      fill(C.uiAccent or color(40, 80, 60, 255))
    else
      fill(180, 180, 180, 200)
    end
    ellipse(x, y, dotR * 2, dotR * 2)
  end
  popStyle()
end

function makeRowRenderer(entries, model)
  return function(row, y, x)
    local e = entries[row]
    local textValue, pts

    if type(e) == "table" then
      textValue = e.word or ""
      pts = e.points
    else
      textValue = tostring(e or "")
    end

    local label    = pts and string.format("%s  (+%d)", textValue, pts) or textValue
    local selected = (endScreenHighlightedWord and textValue ~= "" and textValue == endScreenHighlightedWord)

    pushStyle()
    textAlign(LEFT)
    textMode(CORNER)
    fontSize(24)
    if selected then
      fill(Color.uiAccent2 or Color.uiAccent)
    else
      fill(model.wordColor or Color.uiAccent)
    end
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
  
  listObject:draw(r, #entries, lineH, makeRowRenderer(entries, model), r.x + rect.w * 0.25)
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
