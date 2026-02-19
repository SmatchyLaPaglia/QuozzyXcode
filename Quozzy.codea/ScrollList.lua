--############################################################
-- ScrollList: reusable clipped + inertial vertical list
--############################################################
ScrollList = ScrollList or {}
ScrollList.__index = ScrollList

function ScrollList.new()
    local o = {
        scroll      = 0,
        maxScroll   = 0,
        vel         = 0,
        dragId      = nil,
        dragStartY  = 0,
        dragStartS  = 0,
        prevY       = 0,
        prevT       = 0,
        dirtyAuto   = false,  -- if true, auto-snap to bottom when not dragging
    }
    return setmetatable(o, ScrollList)
end

-- Call when you add a row and want the list to jump to newest (bottom)
function ScrollList:markDirtyAuto()
    self.dirtyAuto = true
end

-- Draw a vertical list inside a viewport.
-- aRect = {x,y,w,h} is CORNER mode clip rect (bottom-left origin).
-- totalRows: integer
-- lineH: per-row vertical step (same as your old 26)
-- drawRowFn(rowIndex, yBaseline, baseX) does ALL styling/animation for that row.
function ScrollList:draw(aRect, totalRows, lineH, drawRowFn, baseX)
    local x0,y0,w,h,contentH,dt
    x0, y0, w, h = aRect.x, aRect.y, aRect.w, aRect.h
    contentH = totalRows * lineH
    dt = DeltaTime or 0
    
    -- if content fits: no scrolling at all
    if contentH <= h then
        self.scroll    = 0
        self.maxScroll = 0
        self.vel       = 0
        self.dragId    = nil
        self.dirtyAuto = false
        
        clip(x0, y0, w, h)
        local firstY = (y0 + h) - lineH
        for row = 1, totalRows do
            local y = firstY - (row - 1) * lineH
            drawRowFn(row, y, baseX)
        end
        clip()
        return
    end
    
    -- scrolling bounds
    self.maxScroll = math.max(0, contentH - h)
    
    -- auto snap to bottom (newest) when requested
    if (not self.dragId) and self.dirtyAuto then
        self.scroll    = self.maxScroll
        self.vel       = 0
        self.dirtyAuto = false
    elseif not self.dragId then
        self.scroll, self.vel = applyScrollInertia(self.scroll, self.vel, 0, self.maxScroll, dt)
    end
    
    if self.scroll < 0 then self.scroll = 0 end
    if self.scroll > self.maxScroll then self.scroll = self.maxScroll end
    
    clip(x0, y0, w, h)
    local firstY = (y0 + h) - lineH
    
    for row = 1, totalRows do
        local y = firstY - (row - 1) * lineH + self.scroll
        
        -- quick cull (same idea as your old code)
        if y > (y0 - lineH) and y < (y0 + h + lineH) then
            drawRowFn(row, y, baseX)
        end
    end
    
    clip()
end

-- Touch handling for the same rect used in :draw().
-- Returns true if it consumed the touch.
function ScrollList:touched(t, aRect)
    if self.maxScroll <= 0 then
        return false
    end
    
    if self.dragId and t.id ~= self.dragId then
        return false
    end
    
    local inRect = (t.x >= aRect.x and t.x <= aRect.x + aRect.w and
    t.y >= aRect.y and t.y <= aRect.y + aRect.h)
    
    if t.state == BEGAN then
        if inRect then
            self.dragId     = t.id
            self.dragStartY = t.y
            self.dragStartS = self.scroll
            self.prevY      = t.y
            self.prevT      = ElapsedTime
            self.vel        = 0
            return true
        end
        
    elseif t.state == MOVING and self.dragId == t.id then
        local dy = t.y - self.dragStartY
        local s  = self.dragStartS + dy
        
        if s < 0 then s = 0 end
        if s > self.maxScroll then s = self.maxScroll end
        self.scroll = s
        
        local now = ElapsedTime
        local dtMove = now - self.prevT
        if dtMove > 0 then
            self.vel = (t.y - self.prevY) / dtMove
        end
        self.prevY = t.y
        self.prevT = now
        
        return true
        
    elseif (t.state == ENDED or t.state == CANCELLED) and self.dragId == t.id then
        self.dragId = nil
        return true
    end
    
    return false
end