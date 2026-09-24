--# Main
function setup()
    viewer.mode = FULLSCREEN
    
    kb = KeyboardHandler()
    kb:start()
    avoider = KeyboardAvoider(kb)
    avoider:start()
    
    topField, topMiddleField, bottomMiddleField, btmField = makeTextFields()
    avoider:registerFields(topField, topMiddleField, bottomMiddleField, btmField) -- or any number
end

function draw()
    background(31, 97, 117)
end

function touched(t)
    if avoider:handleTouch(t) then return true end
    return false
end

function makeTextFields()
    local w = WIDTH * 0.6
    
    local tfTop = objc.UITextField:alloc():initWithFrame_(
    objc.rect(WIDTH/2 - 160,HEIGHT*0.4,320,30))
    tfTop.backgroundColor = color(72, 72, 39)
    tfTop.placeholder = "text field 1"
    
    local tfTopMiddle = objc.UITextField:alloc():initWithFrame_(
    objc.rect(WIDTH/2 - 160,HEIGHT*0.5,320,30))
    tfTopMiddle.backgroundColor = color(72, 59, 39)
    tfTopMiddle.placeholder = "text field 2"
    
    local tfBottomMiddle = objc.UITextField:alloc():initWithFrame_(
    objc.rect(WIDTH/2 - 160,HEIGHT*0.65,320,30))
    tfBottomMiddle.backgroundColor = color(72, 41, 39)
    tfBottomMiddle.placeholder = "text field 3"
    
    local tfBottom = objc.UITextField:alloc():initWithFrame_(
    objc.rect(WIDTH/2 - 160,HEIGHT*0.75,320,30))
    tfBottom.backgroundColor = color(49, 36, 58)
    tfBottom.placeholder = "text field 4"
    
    objc.viewer.view:addSubview_(tfTop)
    objc.viewer.view:addSubview_(tfTopMiddle)
    objc.viewer.view:addSubview_(tfBottomMiddle)
    objc.viewer.view:addSubview_(tfBottom)
    return tfTop, tfTopMiddle, tfBottomMiddle, tfBottom
end
--# KeyboardHandler
--# KeyboardHandler
-- creates a hidden UITextField to enable manual control of showing/hiding the iOS keyboard

KeyboardHandler = class()

function KeyboardHandler:init()
    self._nc = objc.NSNotificationCenter.defaultCenter
    self._handler = nil
    self._delegate = nil
    self._tf = nil
    
    self._kbHeight = 0
    self._isShowing = false
    
    self._cbShown = nil
    self._cbHidden = nil
    self._cbText = nil
end

local function hostView()
    local v = objc.viewer.view
    return (v and v.subviews and v.subviews[1]) or v
end

local function safeToNumber(x)
    if x == nil then return nil end
    local n = tonumber(x)
    return n
end

local function nsvalueToLua(v)
    if not v then return nil end
    -- In Codea, some ObjC types (NSNumber / BOOL) often arrive as plain Lua numbers/booleans.
    local tv = type(v)
    if tv == "number" or tv == "string" or tv == "boolean" or tv == "nil" then
        return v
    end
    if tv ~= "userdata" and tv ~= "table" then
        return tostring(v)
    end
    -- Try CGRect / CGPoint / CGSize in the most Codea-friendly way
    if v.CGRectValue then
        local r = v:CGRectValue_()
        return {
            __type = "CGRect",
            origin = { x = safeToNumber(r.origin.x), y = safeToNumber(r.origin.y) },
            size   = { w = safeToNumber(r.size.width), h = safeToNumber(r.size.height) },
            raw = tostring(v)
        }
    end
    
    if v.CGPointValue then
        local p = v:CGPointValue_()
        return {
            __type = "CGPoint",
            x = safeToNumber(p.x),
            y = safeToNumber(p.y),
            raw = tostring(v)
        }
    end
    
    if v.CGSizeValue then
        local s = v:CGSizeValue_()
        return {
            __type = "CGSize",
            w = safeToNumber(s.width),
            h = safeToNumber(s.height),
            raw = tostring(v)
        }
    end
    
    -- Numbers / bools often convert via tonumber
    local n = safeToNumber(v)
    if n ~= nil then
        return n
    end
    
    -- Strings sometimes show up already as Lua strings; otherwise tostring fallback
    return tostring(v)
end

local function userInfoToLua(userInfo)
    local out = {}
    if type(userInfo) ~= "table" then
        out.__raw = tostring(userInfo)
        return out
    end
    
    for k,v in pairs(userInfo) do
        local ks = tostring(k)
        out[ks] = nsvalueToLua(v)
    end
    return out
end

local function notificationToLua(oNotification)
    local t = {
        __type = "NSNotification",
        raw = tostring(oNotification)
    }
    
    if not oNotification then
        t.nilNotification = true
        return t
    end
    
    -- These usually exist on NSNotification
    if oNotification.name then
        t.name = tostring(oNotification.name)
    end
    if oNotification.object then
        t.object = tostring(oNotification.object)
        if oNotification.object.class then
            t.objectClass = tostring(oNotification.object.class)
        end
    end
    if oNotification.userInfo then
        t.userInfo = userInfoToLua(oNotification.userInfo)
    end
    
    return t
end

function KeyboardHandler:_ensureHiddenTextField()
    if self._tf then return end
    
    local tf = objc.UITextField:alloc():initWithFrame_(objc.rect(-2000, -2000, 10, 10))
    tf.alpha = 0.00
    tf.tintColor = objc.UIColor.clearColor
    hostView():addSubview_(tf)
    self._tf = tf
    
    -- Delegate so Return hides keyboard
    local Del = objc.class("KBHiddenTFDelegate")
    function Del:textFieldShouldReturn_(oTF)
        oTF:resignFirstResponder_()
        return true
    end
    self._delegate = Del()
    self._tf.delegate = self._delegate
end

function KeyboardHandler:_installObjCHandler()
    if self._handler then return end
    
    local Handler = objc.class("KBNotificationHandlerFull")
    
    function Handler:keyboardWillShow_(oNotification)
        local owner = self._luaOwner
        if not owner then return end
        
        owner._isShowing = true
        
        local h = 0
        if oNotification and oNotification.userInfo then
            local v = oNotification.userInfo["UIKeyboardFrameEndUserInfoKey"]
            if v and v.CGRectValue then
                local r = v:CGRectValue_()
                h = safeToNumber(r.size.height) or 0
            end
        end
        owner._kbHeight = h
        
        if owner._cbShown then
            owner._cbShown(notificationToLua(oNotification))
        end
    end
    
    function Handler:keyboardWillHide_(oNotification)
        local owner = self._luaOwner
        if not owner then return end
        
        owner._isShowing = false
        owner._kbHeight = 0
        
        if owner._cbHidden then
            owner._cbHidden(notificationToLua(oNotification))
        end
    end
    
    function Handler:textChanged_(oSender)
        local owner = self._luaOwner
        if not owner then return end
        if owner._cbText then
            owner._cbText(tostring(oSender.text or ""))
        end
    end
    
    self._handler = Handler()
    self._handler._luaOwner = self
    
    -- Wire “editing changed” for text updates
    self._tf:addTarget_action_forControlEvents_(
    self._handler,
    objc.selector("textChanged:"),
    objc.enum.UIControlEvents.editingChanged
    )
end

-- Public API: callbacks
function KeyboardHandler:onShown(cb)   self._cbShown = cb end
function KeyboardHandler:onHidden(cb)  self._cbHidden = cb end
function KeyboardHandler:onTextChanged(cb) self._cbText = cb end

-- Public API: control
function KeyboardHandler:start()
    self:_ensureHiddenTextField()
    self:_installObjCHandler()
    
    self._nc:addObserver_selector_name_object_(
    self._handler,
    objc.selector("keyboardWillShow:"),
    "UIKeyboardWillShowNotification",
    nil
    )
    
    self._nc:addObserver_selector_name_object_(
    self._handler,
    objc.selector("keyboardWillHide:"),
    "UIKeyboardWillHideNotification",
    nil
    )
end

function KeyboardHandler:isShowing()
    return self._isShowing
end

function KeyboardHandler:stop()
    if self._handler then
        self._nc:removeObserver_(self._handler)
    end
    if self._tf then self._tf:removeFromSuperview() end
    self._handler = nil
    self._delegate = nil
    self._tf = nil
end

function KeyboardHandler:toggle()
    self:_ensureHiddenTextField()
    if self._tf.isFirstResponder then
        self._tf:resignFirstResponder_()
    else
        self._tf:becomeFirstResponder_()
    end
end

function KeyboardHandler:show()
    self:_ensureHiddenTextField()
    self._tf:becomeFirstResponder_()
end

function KeyboardHandler:hide()
    if self._tf then
        self._tf:resignFirstResponder_()
    end
end

function KeyboardHandler:currentKeyboardHeight()
    return self._kbHeight or 0
end
--# KeyboardAvoider
KeyboardAvoider = class()

function KeyboardAvoider:init(kbHandler)
    self.kb = kbHandler
    self.fields = {}
    self.baseFrames = {}
    self.shiftY = 0
    
    self.padding = 12
    self.animDuration = 0.25
    
    self._nc = objc.NSNotificationCenter.defaultCenter
    self._editHandler = nil
end

function KeyboardAvoider:setAvoidanceDelegate(fn)
    self.avoidanceDelegate = fn
end

-- Register any number of fields:
-- avoider:registerFields(tf1, tf2, tf3, ...)
function KeyboardAvoider:registerFields(...)
    local list = {...}
    for i = 1, #list do
        local tf = list[i]
        if tf then self:registerField(tf) end
    end
end

function KeyboardAvoider:registerField(tf)
    table.insert(self.fields, tf)
    self.baseFrames[tf] = tf.frame
end

function KeyboardAvoider:start()
    self:_installEditingObserver()
    self:_installKeyboardCallbacks()
end

function KeyboardAvoider:stop()
    if self._editHandler then
        self._nc:removeObserver_(self._editHandler)
        self._editHandler = nil
    end
end

-- Call from touched(t). Returns true if it handled the tap.
function KeyboardAvoider:handleTouch(t)
    if t.state ~= BEGAN then return false end
    
    -- Only dismiss; never show
    if self:tapIsOutsideRegisteredTextFields(t) then
        if (self.kb:currentKeyboardHeight() or 0) > 0 then
            self:dismissKeyboard()
            return true
        end
    end
    
    return false
end

function KeyboardAvoider:dismissKeyboard()
    objc.viewer.view:endEditing_(true)
end

function KeyboardAvoider:tapIsOutsideRegisteredTextFields(t)
    -- Codea -> UIKit coords
    local ux = t.x
    local uy = HEIGHT - t.y
    
    for i = 1, #self.fields do
        local f = self.fields[i].frame
        if ux >= f.origin.x and ux <= (f.origin.x + f.size.width)
        and uy >= f.origin.y and uy <= (f.origin.y + f.size.height) then
            return false
        end
    end
    return true
end

function KeyboardAvoider:_installKeyboardCallbacks()
    self.kb:onShown(function(note)
        -- match iOS keyboard animation timing
        local ui = note and note.userInfo
        local dur = ui and ui.UIKeyboardAnimationDurationUserInfoKey
        dur = tonumber(dur)
        if dur and dur > 0 then self.animDuration = dur end
        
        self:_shiftToAvoidKeyboard(self.kb:currentKeyboardHeight() or 0, true)
    end)
    
    self.kb:onHidden(function(note)
        local ui = note and note.userInfo
        local dur = ui and ui.UIKeyboardAnimationDurationUserInfoKey
        dur = tonumber(dur)
        if dur and dur > 0 then self.animDuration = dur end
        
        self:_shiftToAvoidKeyboard(0, true)
    end)
end

function KeyboardAvoider:_installEditingObserver()
    if self._editHandler then return end
    
    local Handler = objc.class("KeyboardAvoiderEditHandler")
    
    function Handler:textDidBegin_(oNotification)
        -- If keyboard already up (or coming up), re-evaluate shift for the new active field
        local owner = self._luaOwner
        if owner then
            owner:_shiftToAvoidKeyboard(owner.kb:currentKeyboardHeight() or 0, true)
        end
    end
    
    self._editHandler = Handler()
    self._editHandler._luaOwner = self
    
    self._nc:addObserver_selector_name_object_(
    self._editHandler,
    objc.selector("textDidBegin:"),
    "UITextFieldTextDidBeginEditingNotification",
    nil
    )
end

function KeyboardAvoider:_activeField()
    for i = 1, #self.fields do
        local tf = self.fields[i]
        if tf.isFirstResponder then return tf end
    end
    return nil
end

function KeyboardAvoider:_applyShift(shiftY, animated)
    self.shiftY = shiftY or 0
    
    if self.avoidanceDelegate then
        self.avoidanceDelegate(self.shiftY, animated)
        return
    end
    
    local function setFrames()
        for i = 1, #self.fields do
            local tf = self.fields[i]
            local base = self.baseFrames[tf]
            if base then
                tf.frame = objc.rect(
                base.origin.x, base.origin.y - self.shiftY,
                base.size.width, base.size.height
                )
            end
        end
    end
    
    if animated then
        objc.UIView:animateWithDuration_animations_(self.animDuration, setFrames)
    else
        setFrames()
    end
end

function KeyboardAvoider:_shiftToAvoidKeyboard(kh, animated)
    kh = kh or 0
    if kh <= 0 then
        self:_applyShift(0, animated)
        return
    end
    
    local active = self:_activeField()
    if not active then
        self:_applyShift(0, animated)
        return
    end
    
    -- Keyboard top in UIKit coords
    local keyboardTopY = HEIGHT - kh
    
    local f = self.baseFrames[active] or active.frame
    local activeMaxY = f.origin.y + f.size.height
    
    local overlap = activeMaxY - keyboardTopY
    if overlap > 0 then
        self:_applyShift(overlap + self.padding, animated)
    else
        self:_applyShift(0, animated)
    end
end

