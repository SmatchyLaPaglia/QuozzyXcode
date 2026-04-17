-- ScoreSheets.lua
_keyboardVisible = false
_keyboardHeight  = 0

ScoreSheets = class()

function ScoreSheets:init(makeTeams)
  self._scrollTween = nil
  self.makeTeams = makeTeams or self._defaultTeams
  self.tables    = {}
  self.scrollY   = 0
  self._kbShiftY = 0
  self._kbTween = nil
  self.notchTracker = newNotchTracker()
  self.archiveExporter = ArchiveExporter()
  self.archiveBrowser = ArchiveBrowser()
  self._archiveWasActive = false
  self._archiveLoading = false
  self._archiveLoadStage = nil  -- nil / 0 / 1
  
  -- padding knobs for the whole UI/table stack
  self.safePad      = 5
  self.notchPad     = 5
  self.insetPad     = 0
  self._archivingStage = nil -- nil/0/1
  
  -- Two-finger scroll UX
  self.twoFingerScroll = true
  self._activeTouches = {}
  self._touchCount = 0
  self._inScrollMode = false
  
  self._gameOver = false
  self._winningTeam = nil   -- 1 or 2
  self._winningMode = nil   -- "SPADES" or "HEARTS"
  self._gameEndingScore = 600
  
  -- One-time hint overlay (appears when scrolling first becomes possible)
  self._scrollHintAlpha = 0
  self._scrollHintActive = false
  self._scrollHintDismissOnTouch = false
  self._scrollHintStartedAt = nil
  function self:_effectiveScrollY()
    return (self.scrollY or 0) + (self._kbShiftY or 0)
  end
  -- Start with ONE table
  table.insert(self.tables, ScoreTable(self.makeTeams(1)))
  
  -- Scroll sensor (whole screen)
  self.scroll = {
    sensor   = Sensor{ parent = {x = WIDTH/2, y = HEIGHT/2, w = WIDTH, h = HEIGHT}, xywhMode = CENTER },
    mode     = "idle",
    startY   = 0,
    startSY  = 0
  }
  local DRAG_THRESH = 10
  self.scroll.sensor:onTouched(function(ev)
    local t = ev.touch
    if t.state == BEGAN then
      -- cancel any in-flight scroll tween so the user takes control
      if self._scrollTween then tween.stop(self._scrollTween); self._scrollTween = nil end
      self.scroll.mode   = "maybe-drag"
      self.scroll.startY = t.y
      self.scroll.startSY= self.scrollY
      self.scroll.sensor.doNotInterceptTouches = true
    elseif t.state == MOVING and self.scroll.mode ~= "idle" then
      local dy = t.y - self.scroll.startY
      if self.scroll.mode == "maybe-drag" and math.abs(dy) > DRAG_THRESH then
        self.scroll.mode = "dragging"
        self.scroll.sensor.doNotInterceptTouches = false
      end
      if self.scroll.mode == "dragging" then
        self.scrollY = self.scroll.startSY + dy
        self:_clampScroll()
      end
    elseif t.state == ENDED or t.state == CANCELLED then
      self.scroll.mode = "idle"
      self.scroll.sensor.doNotInterceptTouches = true
    end
  end)
  
  -- Meanness toggle (scrolls with first sheet, lives where Reset All used to be)
  self.tzBtn = {
    w = 140, h = 34,
    sensor = Sensor{ parent = {x=0, y=0, w=140, h=34}, xywhMode = CORNER }
  }
  
  self.tzBtn.isWest = false
  self.tzBtn.sensor:onTap(function()
    self.tzBtn.isWest = not self.tzBtn.isWest
    
  end)
  
  -- New Game (scrolls with first sheet, right side)
  self.newGameBtn = {
    w = self.tzBtn.w, h = self.tzBtn.h,
    sensor = Sensor{ parent = {x=0, y=0, w=self.tzBtn.w, h=self.tzBtn.h}, xywhMode = CORNER }
  }
  
  -- Archives (scrolls with first sheet, right side)
  self.archiveBtn = {
    w = self.tzBtn.w, h = self.tzBtn.h,
    sensor = Sensor{ parent = {x=0, y=0, w=self.tzBtn.w, h=self.tzBtn.h}, xywhMode = CORNER }
  }
  
  self.newGameBtn.sensor:onTap(function()
    self:_presentNewGameConfirm()
  end)
  
  self.archiveBtn.sensor:onTap(function()
    if not self.archiveBrowser then return end
    
    self:_setNameFieldsEnabled(false)
    
    self._archiveLoading   = true
    self._archiveLoadStage = 0
  end)
  
  -- New Hand button (fixed UI)
  self.newBtn = {
    w = self.tzBtn.w, h = self.tzBtn.h * 1.25,
    x = WIDTH - 140, y = 22,
    sensor = Sensor{ parent = {x = WIDTH - 80, y = 44, w = 120, h = 44}, xywhMode = CENTER }
  }
  self.newBtn.sensor:onTap(function()
    self:_addHand()
  end)
  
  -- Get layout from the first table
  local firstTable = self.tables[1]
  firstTable:layout()
  local m = firstTable.metrics
  local selfProxy = self
  -- Player name origins and models
  local nameFields = {}
  local nameData = {
    { y = m.t1_row1, team = 1, player = 1 },
    { y = m.t1_row2, team = 1, player = 2 },
    { y = m.t2_row1, team = 2, player = 1 },
    { y = m.t2_row2, team = 2, player = 2 },
  }
  self._nameData = nameData
  
  for i, entry in ipairs(nameData) do       
    local y = entry.y
    local slotTeam = entry.team
    local slotPlayer = entry.player
    local model = self.tables[1].teams[slotTeam].players[slotPlayer]
    local tf = objc.UITextField:alloc():init( )
    tf.tag = i
    objc.viewer.view.subviews[1]:addSubview_(tf)
    tf.borderStyle = objc.enum.UITextBorderStyle.none
    tf.textColor = color(0,0)
    tf.backgroundColor = color(0,0)
    tf.tintColor = color(0,0)
    tf.font = objc.UIFont:fontWithName_size_("HelveticaNeue-Bold", m.leftRowH * 0.42)
    tf.frame = codeaToUIKitRect(m.innerX, y, m.wName, m.leftRowH)
    tf.textAlignment = objc.enum.NSTextAlignment.center
    tf.contentVerticalAlignment = objc.enum.UIControlContentVerticalAlignment.center
    local Delegate = objc.delegate("UITextFieldDelegate")
    function Delegate:textFieldShouldReturn_(oTF)
      oTF:resignFirstResponder_()
      return true
    end
    
    function Delegate:textFieldShouldBeginEditing_(oTF)
      local i = tonumber(oTF.tag or 0) or 0
      i = math.floor(i + 0.5)
      local ph = "Player "..tostring(i)
      
      if tostring(oTF.text or "") == ph then
        oTF.text = ""
        selfProxy:_onNameFieldChanged(oTF)
      end
      
      _G.activeTextField = oTF
      return true
    end
    
    function Delegate:textFieldDidEndEditing_(oTF)
      local i = tonumber(oTF.tag or 0) or 0
      i = math.floor(i + 0.5)
      local ph = "Player "..tostring(i)
      
      local txt = tostring(oTF.text or "")
      if txt == "" then
        oTF.text = ph
        selfProxy:_onNameFieldChanged(oTF)
        return
      end
      
      -- normal propagation for real names
      local entry = selfProxy._nameData[i]
      if not entry then return end
      
      local slotTeam   = entry.team
      local slotPlayer = entry.player
      
      for ti = 1, #selfProxy.tables do
        local t = selfProxy.tables[ti]
        local p = t
        and t.teams
        and t.teams[slotTeam]
        and t.teams[slotTeam].players
        and t.teams[slotTeam].players[slotPlayer]
        
        if p then p.name = txt end
      end
    end
    
    -- Install one shared change handler (create once)
    if not self._nameChangeHandler then
      local ChangeHandler = objc.class("NameChangeHandler")
      function ChangeHandler:nameChanged_(oSender)
        local owner = self._luaOwner
        if owner then owner:_onNameFieldChanged(oSender) end
      end
      self._nameChangeHandler = ChangeHandler()
      self._nameChangeHandler._luaOwner = self
    end
    
    tf:addTarget_action_forControlEvents_(
    self._nameChangeHandler,
    objc.selector("nameChanged:"),
    objc.enum.UIControlEvents.editingChanged
    )
    
    tf.delegate = Delegate()
    
    local ph = "Player "..tostring(i)
    tf.text = ph
    model.name = ph
    
    -- propagate placeholder to all tables (so everything matches Codea-side)
    for ti = 1, #selfProxy.tables do
      local t = selfProxy.tables[ti]
      local p = t and t.teams and t.teams[slotTeam] and t.teams[slotTeam].players and t.teams[slotTeam].players[slotPlayer]
      if p then p.name = ph end
    end
    
    nameFields[i] = tf
  end
  self._rawNameFields = nameFields
  
  self.kb = KeyboardHandler()
  
  self.kb:start()
  
  self.kbAvoider = KeyboardAvoider(self.kb)
  self.kbAvoider:registerFields(table.unpack(nameFields))
  
  -- Animate the *whole Codea view* like the demo (no Codea tween)
  local hv = (objc.viewer.view.subviews and objc.viewer.view.subviews[1]) or objc.viewer.view
  local base = hv.frame
  
  self.kbAvoider:setAvoidanceDelegate(function(shiftY, animated)
    local dy = shiftY or 0
    
    local function setFrame()
      hv.frame = objc.rect(
      base.origin.x,
      base.origin.y - dy,
      base.size.width,
      base.size.height
      )
    end
    
    if animated then
      objc.UIView:animateWithDuration_animations_(self.kbAvoider.animDuration or 0.25, setFrame)
    else
      setFrame()
    end
  end)
  
  self.kbAvoider:start()
  self:_loadLocalGame()
end

function ScoreSheets:draw()
  self._inDraw = true
  
  local ab = self.archiveBrowser
  if ab then
    if ab.active and not self._archiveWasActive then
      self:_setNameFieldsEnabled(false)
    elseif (not ab.active) and self._archiveWasActive then
      self:_setNameFieldsEnabled(true)
    end
    self._archiveWasActive = ab.active
  end
  
  
  if self.archiveBrowser and self.archiveBrowser.active then
    self.archiveBrowser:draw()
    return
  end
  
  background(35)
  
  local uiInset = 10  -- tune to taste; this is the “accidental” margin you circled
  local notchOnLeft, notchOnRight = self.notchTracker:update(DeltaTime)
  self.notchOnLeft  = notchOnLeft
  self.notchOnRight = notchOnRight
  
  local leftPad, rightPad = self.notchTracker:computePads(self.safePad, self.notchPad, self.insetPad)
  self.leftPad  = leftPad
  self.rightPad = rightPad
  
  self:_syncTeamsFromAllTables()
  
  -- ONE source of truth: ledger computes ALL table snapshots in order
  self.ledger = self.ledger or ScoreLedger(ScoreRules, nil)
  local snaps = self.ledger:computeSnapshotsForTables(self.tables)
  
  for hi = 1, #self.tables do
    for ti = 1, 2 do
      local dst = self.tables[hi].teams[ti]
      local src = snaps[hi][ti]
      dst.spadesScore = src.spadesScore
      dst.heartsScore = src.heartsScore
      dst.handBags    = src.handBags
      
      dst.spadesTotal = src.spadesTotal
      dst.heartsTotal = src.heartsTotal
      dst.allBags     = src.allBags
      dst.gameTotal   = src.gameTotal
    end
  end
  
  -- Game over detection:
  -- Trigger: any team's heartsTotal or spadesTotal >= 600
  -- Winner: team with higher gameTotal (tie => nil / "TIE")
  if not self._gameOver then
    local last = self.tables[#self.tables]
    if last and last.teams and last.teams[1] and last.teams[2] then
      local t1 = last.teams[1]
      local t2 = last.teams[2]
      
      local trig =
      (t1.spadesTotal and t1.spadesTotal >= self._gameEndingScore) or
      (t1.heartsTotal and t1.heartsTotal >= self._gameEndingScore) or
      (t2.spadesTotal and t2.spadesTotal >= self._gameEndingScore) or
      (t2.heartsTotal and t2.heartsTotal >= self._gameEndingScore)
      
      if trig then
        self._gameOver = true
        
        local g1 = tonumber(t1.gameTotal) or 0
        local g2 = tonumber(t2.gameTotal) or 0
        
        if g1 > g2 then
          self._winningTeam = 1
        elseif g2 > g1 then
          self._winningTeam = 2
        else
          self._winningTeam = nil  -- tie
        end
        
        self._winningMode = "TOTAL" -- label only; keep or ignore
      end
    end
  end
  
  -- Draw all tables with vertical offset & scroll
  do
    local stepH, gapH = self:_stackMetrics()
    local d = stepH + gapH
    local sy = self:_effectiveScrollY()
    for i = 1, #self.tables do
      pushMatrix()
      -- first hand at scrollY==0 is centered; later hands are drawn LOWER (negative offset)
      translate(0, - (i-1) * d + sy)
      
      -- Hand labels 
      local m = self.tables[i].metrics
      if m then
        pushStyle()
        font("Chalkduster")  -- fallback: "ChalkboardSE-Bold"
        fontSize(24)
        fill(120)
        textAlign(LEFT)
        textMode(CORNER)
        
        -- we're in this table's translated space already
        local centerY = HEIGHT/2
        local topY    = centerY + stepH/2
        local lx      = m.innerX + uiInset
        local ly      = topY
        
        text("HAND "..tostring(i)..":", lx, ly)
        popStyle()
      end
      self.tables[i]:draw()
      self.tables[i]._scrollY = -((i - 1) * d) + sy
      popMatrix()
    end
  end
  
  local sy = self:_effectiveScrollY()
  do
    local t = self.tables[1]
    local m = t and t.metrics
    if m then
      local topY = m.innerY + m.tablesH
      
      pushStyle()
      font("Chalkduster") -- fallback if unavailable: "ChalkboardSE-Bold"
      fontSize(60)
      fill(255, 255, 255, 220)
      textAlign(CENTER)
      textMode(CENTER)
      
      -- this y is in “table space”, then we add sy so it scrolls with the sheet
      local spY = topY + (m.leftRowH * 1.85) + sy
      text("SPARTS", WIDTH/2, spY)
      self._spartsHit = {
        x = WIDTH/2,
        y = spY,
        r = 90    -- tune if needed, but start here
      }
      
      fontSize(18)
      fill(120)
      textAlign(CENTER)
      textMode(CENTER)
      text(os.date("%B %d, %Y"), WIDTH/2, spY - 44)
      
      popStyle()
    end
  end
  
  -- Top controls (timezone toggle + New Game + Archives), scroll with first sheet
  local meanBtnW, meanBtnH = 120, 44
  do
    local t = self.tables[1]
    if t and t.metrics then
      local m = t.metrics
      local bw, bh = 120, 44
      
      -- Anchor to the first table’s left edge; sit higher above the header.
      local baseX = m.innerX
      local baseY = m.innerY + m.tablesH + (m.leftRowH * 0.75) + 8
      
      local tableW = m.tablesW or m.tableW or (WIDTH - m.innerX*2)
      local baseX_left  = m.innerX
      rightEdge = m.innerX + tableW
      
      local topY = m.innerY + m.tablesH
      local gap  = 9
      local baseX_left  = m.innerX
      local tableW = m.tablesW or (WIDTH - m.innerX*2)
      local rightEdge = m.innerX + tableW
      
      -- Date + timezone toggle where Reset All USED to be (left side)
      do
        local dx = baseX_left
        
        -- toggle (white, black text), just above the table with a small gap
        local tw, th = self.tzBtn.w, self.tzBtn.h
        local tx = dx
        local ty = topY + gap + self.scrollY          -- this stays the LOWER row (Archives / Hand label row)
        local tyNewGame  = ty + th + gap              -- this is the UPPER row (New Game / Coast toggle row)
        
        self.tzBtn.sensor:setParent{
          parent = { x = tx, y = tyNewGame, w = tw, h = th },
          xywhMode = CORNER
        }
        
        pushStyle()
        fill(50)
        stroke(70)
        strokeWidth(3)
        rect(tx, tyNewGame, tw, th, 10)
        
        fill(140)
        font("Chalkduster") 
        fontSize(18)
        textAlign(CENTER)
        textMode(CENTER)
        local label = self.tzBtn.isWest and "WEST COAST" or "EAST COAST"
        text(label, tx + tw/2, tyNewGame + th/2)
        popStyle()
        
        -- Right side buttons: Archives aligns vertically with East/West (same ty)
        do
          local tw, th = self.tzBtn.w, self.tzBtn.h  -- same size as East/West
          local txR = rightEdge - tw - uiInset
          local tyArchives = ty
          local tyNewGame  = ty + th + gap
          
          
          -- ARCHIVES (bottom one, same vertical placement as East/West)
          self.archiveBtn.sensor:setParent{
            parent = { x = txR, y = tyArchives, w = tw, h = th },
            xywhMode = CORNER
          }
          drawRoundedRect(
          txR + tw/2,
          tyArchives + th/2,
          tw,
          th,
          15,
          color(255,140,0,235),
          color(255,140,0,235)
          )
          
          pushStyle()
          fill(255)
          font("Chalkduster")
          fontSize(18)
          textAlign(CENTER)
          text("ARCHIVES", txR + tw/2, tyArchives + th/2)
          popStyle()
          
          -- NEW GAME (above Archives, small gap)
          self.newGameBtn.sensor:setParent{
            parent = { x = txR, y = tyNewGame, w = tw, h = th },
            xywhMode = CORNER
          }
          drawRoundedRect(
          txR + tw/2,
          tyNewGame + th/2,
          tw,
          th,
          15,
          color(255,140,0,235),
          color(255,140,0,235)
          )
          
          pushStyle()
          fill(255)
          font("Chalkduster")
          fontSize(18)
          textAlign(CENTER)
          text("NEW GAME", txR + tw/2, tyNewGame + th/2)
          popStyle()
        end
        
      end
      
      popStyle()
    end
  end
  
  -- “New Hand” button (pinned just below the most recently added table, and scrolls with it)
  if not self._gameOver then
    do
      local t = self.tables[1]
      local m = t and t.metrics
      if m then
        local tableW = m.tablesW or m.tableW or (WIDTH - m.innerX*2)
        local rightEdge = m.innerX + tableW
        
        self.newBtn.x = rightEdge - self.newBtn.w
        
        local stepH, gapH = self:_stackMetrics()
        local d  = stepH + gapH
        local sy = self:_effectiveScrollY()
        
        local i = #self.tables
        local tableCenterY = (HEIGHT/2) + ( - (i-1) * d + sy )
        local tableBottomY = tableCenterY - (stepH/2)
        
        local pad = 15
        self.newBtn.y = tableBottomY - pad - self.newBtn.h
        
        -- keep the sensor aligned with the drawn rect
        self.newBtn.sensor:setParent{
          parent = { x = self.newBtn.x, y = self.newBtn.y, w = self.newBtn.w, h = self.newBtn.h },
          xywhMode = CORNER
        }
        
        drawRoundedRect(
        self.newBtn.x + self.newBtn.w/2,
        self.newBtn.y + self.newBtn.h/2,
        self.newBtn.w,
        self.tzBtn.h,
        16,
        color(70,180,255),
        color(70,180,255)
        )
        
        pushStyle()
        fill(255)
        font("Chalkduster")
        fontSize(18)
        textAlign(CENTER)
        text("NEW HAND",
        self.newBtn.x + self.newBtn.w/2,
        self.newBtn.y + self.newBtn.h/2)
        popStyle()
      end
    end
  elseif self._gameOver == true then
    -- Game Over banner (replaces New Hand)
    local t = self.tables[1]
      local m = t and t.metrics
      if m then
        local tableW = m.tablesW or m.tableW or (WIDTH - m.innerX*2)
        local rightEdge = m.innerX + tableW
        
        local stepH, gapH = self:_stackMetrics()
        local d  = stepH + gapH
        local sy = self:_effectiveScrollY()
        
        local i = #self.tables
        local tableCenterY = (HEIGHT/2) + ( - (i-1) * d + sy )
        local tableBottomY = tableCenterY - (stepH/2)
        
        local pad = 18
        local cx = rightEdge - (self.newBtn.w / 2)
        local cy = tableBottomY - pad - (self.tzBtn.h * 0.6)
        
        pushStyle()
        font("Chalkduster")
        fontSize(35)
        fill(220, 136, 60)
        textAlign(CENTER)
        textMode(CENTER)
        
      local label
      if self._winningTeam then
        label = "GAME OVER - TEAM " .. tostring(self._winningTeam) .. " WINS!"
      else
        label = "GAME OVER - TIE GAME"
      end
      text(label, WIDTH / 2, cy)
        popStyle()
      end
    end
  
  
  -- Scroll-mode visual indicator (very slight darkening)
  self:_drawNonInteractiveOverlay(self._inScrollMode, "")         -- scroll mode wash
  
  -- activity indicator during archiving
  local busy = (self._archivingStage ~= nil)
  or (self.archiveExporter and self.archiveExporter.pending)
  or self._archiveLoading
  
  local msg
  if self._archiveLoading then
    msg = "LOADING ARCHIVES…"
  elseif busy then
    msg = "ARCHIVING…"
  end
  
  self:_drawNonInteractiveOverlay(busy, msg)
  
  -- Force one full frame where the overlay is visible before doing the heavy export
  if self._archivingStage == 0 then
    self._archivingStage = 1
    self:_syncNameFieldFrames()
    self._inDraw = false
    return
  end
  
  -- Force one full frame before loading archives
  if self._archiveLoadStage == 0 then
    self._archiveLoadStage = 1
    self._inDraw = false
    return
  end
  
  -- Perform the actual archive load
  if self._archiveLoadStage == 1 then
    self.archiveBrowser:open()   -- this runs loadIndex()
    self._archiveLoadStage = nil
    self._archiveLoading  = false
  end
  
  -- One-time hint overlay
  if self._scrollHintActive and (self._scrollHintAlpha or 0) > 0 then
    local a = self._scrollHintAlpha or 0
    
    -- fade down gradually
    local dt = DeltaTime or 0
    self._scrollHintAlpha = math.max(0, a - (dt * 55)) -- tune fade speed here
    
    pushStyle()
    rectMode(CORNER)
    
    -- subtle dark veil so text reads, but still "semitransparent"
    fill(0, 0, 0, math.min(90, self._scrollHintAlpha * 0.45))
    rect(0, 0, WIDTH, HEIGHT)
    
    fill(255, 255, 255, self._scrollHintAlpha)
    font("Chalkduster")
    fontSize(26)
    textAlign(CENTER)
    textMode(CENTER)
    
    local cx, cy = WIDTH/2, HEIGHT/2
    text("SWIPE WITH TWO FINGERS\nTO SCROLL", cx, cy)
    
    -- arrows (text)
    fontSize(44)
    text("↑", cx, cy + 84)
    text("↓", cx, cy - 84)
    
    if self._scrollHintAlpha <= 0 then
      self._scrollHintActive = false
      self._scrollHintDismissOnTouch = false
    end
  end
  self:_syncNameFieldFrames()
  
  if self.archiveExporter and self._archivingStage == 1 then
    self.archiveExporter:update(self)
    self._archivingStage = nil
    if self._resetAfterArchive then
      self._resetAfterArchive = false
      self:_resetAll()
      
    end
  end
  
  self._inDraw = false
end

function ScoreSheets:touched(t)
  
  if self.archiveExporter and self.archiveExporter.pending then
    return true
  end
  
  if self.archiveBrowser and self.archiveBrowser.active then
    return self.archiveBrowser:touched(t)
  end
  
  if self._scrollHintDismissOnTouch and t.state == BEGAN then
    self._scrollHintAlpha = 0
    self._scrollHintActive = false
    self._scrollHintDismissOnTouch = false
  end
  
  ------------------------------------------------------------
  -- Ensure tracking tables exist
  ------------------------------------------------------------
  self._activeTouches = self._activeTouches or {}   -- id -> {x,y}
  self._touchOrder    = self._touchOrder    or {}   -- deterministic ordering
  self._scroll2       = self._scroll2       or { mode="idle", startAvgY=0, startSY=0 }
  
  self._futile = self._futile or {}  -- per-touch start point + one-shot flag
  ------------------------------------------------------------
  -- Helpers
  ------------------------------------------------------------
  local function ensureInOrder(id)
    for i = 1, #self._touchOrder do
      if self._touchOrder[i] == id then return end
    end
    table.insert(self._touchOrder, id)
  end
  
  local function removeFromOrder(id)
    for i = #self._touchOrder, 1, -1 do
      if self._touchOrder[i] == id then
        table.remove(self._touchOrder, i)
        break
      end
    end
  end
  
  local function activeCount()
    local n = 0
    for _ in pairs(self._activeTouches) do n = n + 1 end
    return n
  end
  
  local function firstTwoIds()
    local id1 = self._touchOrder[1]
    local id2 = self._touchOrder[2]
    if not id1 or not id2 then return nil, nil end
    if not self._activeTouches[id1] or not self._activeTouches[id2] then return nil, nil end
    return id1, id2
  end
  
  local function avgYFor(id1, id2)
    local p1 = self._activeTouches[id1]
    local p2 = self._activeTouches[id2]
    if not p1 or not p2 then return nil end
    return (p1.y + p2.y) * 0.5
  end
  
  local function forwardTouchToTables(ttouch)
    local stepH, gapH = self:_stackMetrics()
    local d = stepH + gapH
    
    for i = 1, #self.tables do
      local tt = {
        id       = ttouch.id,
        state    = ttouch.state,
        tapCount = ttouch.tapCount,
        x        = ttouch.x,
        y        = ttouch.y - ( - (i-1)*d + self.scrollY ),
        deltaX   = ttouch.deltaX,
        deltaY   = ttouch.deltaY
      }
      
      local centerY = HEIGHT/2
      local topY    = centerY + stepH/2
      local botY    = centerY - stepH/2
      
      if tt.y >= botY and tt.y <= topY then
        if self.tables[i]:touched(tt) then return true end
      end
    end
    return false
  end
  
  local function cancelOwnedTouch(id)
    local owners = IncrementingCell and IncrementingCell._owners
    if owners and owners[id] then
      -- push a synthetic CANCELLED through normal routing so press visuals clear
      local p = self._activeTouches[id]
      if p then
        forwardTouchToTables({
          id = id,
          state = CANCELLED,
          tapCount = 0,
          x = p.x, y = p.y,
          deltaX = 0, deltaY = 0
        })
      end
      owners[id] = nil
    end
  end
  
  local function showScrollHintAgain()
    self._scrollHintActive = true
    self._scrollHintDismissOnTouch = true
    self._scrollHintStartedAt = ElapsedTime
    self._scrollHintAlpha = 220
  end
  
  ------------------------------------------------------------
  -- 1) Track touches FIRST (never miss cleanup)
  ------------------------------------------------------------
--[[
  if t.state == BEGAN and self._spartsHit then
    local dx = t.x - self._spartsHit.x
    local dy = t.y - self._spartsHit.y
    if (dx*dx + dy*dy) <= (self._spartsHit.r * self._spartsHit.r) then
      videoPlayer:showAndAutoplayMOV(asset.OverheadWaves)
      return true
    end
  end
]]
  
  if t.state == BEGAN then
    self._futile[t.id] = { x = t.x, y = t.y, shown = false }
    self._activeTouches[t.id] = { x = t.x, y = t.y }
    ensureInOrder(t.id)
    
  elseif t.state == MOVING then
    local v = self._activeTouches[t.id]
    if v then
      v.x, v.y = t.x, t.y
    else
      self._activeTouches[t.id] = { x = t.x, y = t.y }
      ensureInOrder(t.id)
    end
    -- Futile scroll hint: 1-finger vertical swipe attempt (when scrolling is possible)
    do
      local rec = self._futile[t.id]
      if rec and not rec.shown
      and self.twoFingerScroll == true
      and not self._inScrollMode
      and (self._scroll2 and self._scroll2.mode == "idle")
      and self._touchCount == 1
      and ElapsedTime > (self._ignoreFutileUntil or 0)
      and (self:_contentSpan() > 0) then
        
        local dx = t.x - rec.x
        local dy = t.y - rec.y
        
        -- vertical intent: big enough + mostly vertical
        if math.abs(dy) > 18 and math.abs(dy) > math.abs(dx) * 1.5 then
          rec.shown = true
          showScrollHintAgain()
        end
      end
    end
  elseif t.state == ENDED or t.state == CANCELLED then
    self._activeTouches[t.id] = nil
    removeFromOrder(t.id)
    self._futile[t.id] = nil
  end
  
  self._touchCount = activeCount()
  
  ------------------------------------------------------------
  -- 2) Two-finger scroll mode: EXACTLY TWO touches, always swallow
  --    and NEVER allow cells to activate while in this mode.
  ------------------------------------------------------------
  local twoFinger = (self.twoFingerScroll == true)
  local inScrollNow = false
  
  if twoFinger and self._touchCount == 2 then
    local id1, id2 = firstTwoIds()
    local avgY = (id1 and id2) and avgYFor(id1, id2) or nil
    
    if id1 and id2 and avgY then
      inScrollNow = true
      
      -- Entering scroll mode this frame?
      if not self._inScrollMode then
        self._scroll2.lastAvgY, self._scroll2.lastT, self._scroll2.vel = avgY, ElapsedTime, 0
        self._inScrollMode = true
        
        -- cancel any in-flight tween so fingers take control
        if self._scrollTween then tween.stop(self._scrollTween); self._scrollTween = nil end
        
        -- IMPORTANT: if a cell grabbed ownership on the first finger,
        -- cancel it immediately so we don't get "stuck pressed" cells.
        cancelOwnedTouch(id1)
        cancelOwnedTouch(id2)
        
        self._scroll2.mode = "maybe-drag"
        self._scroll2.startAvgY = avgY
        self._scroll2.startSY   = self.scrollY
      end
      
      -- Update scrolling only on MOVING (baseline is stable = not poppy)
      if t.state == MOVING then
        local dy = avgY - (self._scroll2.startAvgY or avgY)
        
        if self._scroll2.mode == "maybe-drag" and math.abs(dy) > 10 then
          self._scroll2.mode = "dragging"
        end
        
        if self._scroll2.mode == "dragging" then
          self.scrollY = (self._scroll2.startSY or self.scrollY) + dy
          self:_clampScroll()
          local now = ElapsedTime
          local dt  = now - (self._scroll2.lastT or now)
          if dt > 0 then self._scroll2.vel = (avgY - (self._scroll2.lastAvgY or avgY)) / dt end
          self._scroll2.lastAvgY, self._scroll2.lastT = avgY, now
        end
      end
      
      -- Swallow EVERYTHING while exactly 2 touches are down.
      return true
    end
  end
  
  -- If we drop out of exactly-two, turn scroll mode OFF immediately
  if self._inScrollMode and not inScrollNow then
    self._inScrollMode = false
    self._scroll2.mode = "idle"
    self._ignoreFutileUntil = ElapsedTime + 0.25
    local v = self._scroll2.vel or 0
    if math.abs(v) > 20 then
      local decel = 0.998 -- UIScrollViewDecelerationRateNormal-style behavior  [oai_citation:1‡Medium](https://medium.com/%40esskeetit/how-uiscrollview-works-e418adc47060)
      local projected = (v / 1000) * decel / (1 - decel) -- Apple’s projection approximation  [oai_citation:2‡Medium](https://medium.com/%40esskeetit/how-uiscrollview-works-e418adc47060)
      local span = self:_contentSpan()
      local target = math.max(0, math.min(span, self.scrollY + projected))
      local thresh = 20
      local tms = math.log(thresh / math.abs(v)) / math.log(decel)
      local dur = math.max(0.12, math.min(1.2, math.abs(tms) / 1000))
      if self._scrollTween then tween.stop(self._scrollTween) end
      self._scrollTween = tween(dur, self, { scrollY = target }, tween.easing.quadOut, function() self._scrollTween = nil end)
    end
  end
  
  ------------------------------------------------------------
  -- 3) If an IncrementingCell owns this touch id, ALWAYS forward
  --    (so it can release ownership on ENDED/CANCELLED)
  ------------------------------------------------------------
  if IncrementingCell and IncrementingCell._owners and IncrementingCell._owners[t.id] then
    forwardTouchToTables(t)
    return true
  end
  
  ------------------------------------------------------------
  -- 4) Keyboard avoider
  ------------------------------------------------------------
  if self.kbAvoider and self.kbAvoider:handleTouch(t) then
    return true
  end
  
  ------------------------------------------------------------
  -- 5) Fixed buttons
  ------------------------------------------------------------
  if self.newBtn and self.newBtn.sensor and self.newBtn.sensor:touched(t) then return true end
  if self.tzBtn  and self.tzBtn.sensor  and self.tzBtn.sensor:touched(t)  then return true end
  if self.newGameBtn and self.newGameBtn.sensor and self.newGameBtn.sensor:touched(t) then return true end
  if self.archiveBtn and self.archiveBtn.sensor and self.archiveBtn.sensor:touched(t) then return true end
  
  ------------------------------------------------------------
  -- 6) Normal routing
  ------------------------------------------------------------
  if forwardTouchToTables(t) then return true end
  return false
end

function ScoreSheets:_trackTouch(t)
  local a = self._activeTouches
  if t.state == BEGAN then
    if not a[t.id] then
      a[t.id] = true
      self._touchCount = (self._touchCount or 0) + 1
    end
  elseif t.state == ENDED or t.state == CANCELLED then
    if a[t.id] then
      a[t.id] = nil
      self._touchCount = math.max(0, (self._touchCount or 1) - 1)
    end
  end
end
