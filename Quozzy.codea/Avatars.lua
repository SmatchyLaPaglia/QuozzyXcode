local DEFAULT_AVATAR_SIZE = 128

function defineAvatars()
  
  ------------------------------------------------------------
  -- DEFAULTS FIRST (instant, no blocking)
  ------------------------------------------------------------
  
  localPlayerAvatar  = unknownPlayerAvatar(256, Color.uiAccent)
  otherPlayerAvatar  = unknownPlayerAvatar(256, Color.uiAccent)
  
  ------------------------------------------------------------
  -- LOCAL PLAYER (async)
  ------------------------------------------------------------
  
  local GKLocalPlayer = objc.GKLocalPlayer
  local lp = GKLocalPlayer and GKLocalPlayer.localPlayer
  
  if lp and lp.authenticated then
    loadPlayerPhoto(lp, function(photo)
      if photo then
        localPlayerAvatar = photo   -- square UIImage proxy
      end
    end)
  end
  
  ------------------------------------------------------------
  -- OTHER PLAYER (async)
  ------------------------------------------------------------
  
  local gkMatch = tbm and tbm.currentMatch
  local pl = gkMatch and firstNonLocalParticipant(gkMatch)
  
  if pl then
    local oppId = pl.gamePlayerID or pl.playerID or currentOpponentID
    local oppAlias = pl.alias or pl.displayName or opponentAlias
    loadPlayerPhoto(pl, function(photo)
      if photo then
        otherPlayerAvatar = photo   -- square UIImage proxy
        if saveOpponentAvatarForRecord then
          saveOpponentAvatarForRecord(oppId, oppAlias, photo)
        end
        print("otherPlayerAvatar = photo")
      else 
        print("loadPlayerPhoto for otherPlayer failed")
      end
    end)
  end  
end

function unknownPlayerAvatar(size, bgColor)
  size = math.max(16, math.floor(size or 128))
  bgColor = bgColor or color(120, 90, 60, 255)
  
  local img = image(size, size)
  local cx, cy = size * 0.5, size * 0.5
  
  setContext(img)
  pushStyle()
  
  background(bgColor)   -- FULL SQUARE BACKGROUND
  
  smooth()
  noStroke()
  
  ------------------------------------------------------------
  -- BIG semi-transparent "?" with soft drop shadow
  ------------------------------------------------------------
  
  local fs = size * 0.88
  
  textAlign(CENTER)
  textMode(CENTER)
  font("HelveticaNeue-BoldItalic")
  fontSize(fs)
  
  -- shadow
  fill(0, 42)
  text("?", cx + size * 0.045, cy - size * 0.045)
  
  -- main glyph
  fill(255, 107)
  text("?", cx, cy)
  
  popStyle()
  setContext()
  
  return img
end

avatarCircleCache = avatarCircleCache or {}

function drawAvatarCircle(img, cx, cy, size, fallbackInitial)
  
  if not img then
    img = unknownPlayerAvatar(size, Color.uiAccent)
  end
  
  ------------------------------------------------------------
  -- BORDER (same style as before)
  ------------------------------------------------------------
  
  pushStyle()
  
  ellipseMode(CENTER)
  
  noStroke()
  fill(0,0,0,25)
  ellipse(cx, cy, size * 1.08)
  
  fill(0,0,0,40)
  ellipse(cx, cy, size * 1.09)
  
  ------------------------------------------------------------
  -- CIRCULAR AVATAR VIA SHADER
  ------------------------------------------------------------
  
  avatarMesh.texture = img
  
  avatarMesh:setRect(
  1,
  cx,
  cy,
  size,
  size
  )
  
  avatarMesh.shader.circleSize = 0.5
  
  avatarMesh:draw()
  
  popStyle()
end

function defineAvatarsAfterMicrodelay()
  
  local lp = objc.GKLocalPlayer.localPlayer
  if not lp then return end
  
  if not lp.authenticated then
    print("Avatar: not authenticated yet")
    return
  end
  
  -- Defer one frame — VERY important
  tween.delay(0.2, function()
    defineAvatars()
  end)
  
end

function buildDefaultAvatarImage(initial)
  print("[STUB] buildDefaultAvatarImage")
end

function ensureAvatarForOpponent(oppId, alias)
  print("[STUB] ensureAvatarForOpponent")
end

function loadAvatarsForOpponents()
  print("[STUB] loadAvatarsForOpponents")
end

function refreshQPlayerAvatarFromGK(qp, gkPlayer)
  print("[STUB] refreshQPlayerAvatarFromGK")
end

GCPlayerPhotosById     = GCPlayerPhotosById     or {}
GCPlayerPhotoLoadingById = GCPlayerPhotoLoadingById or {}

-- player: GKPlayer proxy from GameKit
-- onReady(photo) is called on the main thread with:
--   photo = UIImage proxy or nil if it failed.
function loadPlayerPhoto(player, onReady)
    if not player then
        if onReady then onReady(nil) end
        return
    end
    
    -- Try to get a stable id
    local pid = player.gamePlayerID
    or player.playerID
    or player.displayName
    or player.alias
    
    if not pid then
        if onReady then onReady(nil) end
        return
    end
    
    -- Already cached?
    local cached = GCPlayerPhotosById[pid]
    if cached ~= nil then
        if onReady then onReady(cached) end
        return
    end
    
    -- Already in-flight? Just enqueue the callback.
    local waiting = GCPlayerPhotoLoadingById[pid]
    if waiting then
        table.insert(waiting, onReady)
        return
    end
    
    GCPlayerPhotoLoadingById[pid] = { onReady }
    
    local GKPhotoSize = objc.enum.GKPhotoSize
    local sizeEnum    = GKPhotoSize.normal   -- could choose .small / .large later
    
    player:loadPhotoForSize_withCompletionHandler_(sizeEnum, function(oImage, oError)
        -- This callback might not be on the main thread; hop back if needed.
        objc.async(function()
            local callbacks = GCPlayerPhotoLoadingById[pid]
            GCPlayerPhotoLoadingById[pid] = nil
            
            local photo = nil
            if oError ~= nil then
                print("GC avatar error for", pid, oError.localizedDescription)
            else
                photo = oImage
                GCPlayerPhotosById[pid] = photo   -- cache UIImage proxy
            end
            
            if callbacks then
                for _, cb in ipairs(callbacks) do
                    if cb then cb(photo) end
                end
            end
        end)
    end)
end

localPlayerAvatar = localPlayerAvatar or nil  -- UIImage proxy (or nil)

function loadLocalPlayerAvatar()
    local GKLocalPlayer = objc.GKLocalPlayer
    local lp = GKLocalPlayer.localPlayer
    
    if not lp then
        print("GC TEST: GKLocalPlayer.localPlayer is nil")
        return
    end
    
    if not lp.authenticated then
        print("GC TEST: local player not authenticated yet")
        return
    end
    
    print("GC TEST: requesting local player avatar...")
    
    loadPlayerPhoto(lp, function(photo)
        if not photo then
            print("GC TEST: no avatar photo returned (nil)")
            return
        end
        
        localPlayerAvatar = photo
        
        -- Try to log dimensions if the proxy exposes .size
        if photo.width and photo.height then
            print(string.format(
            "GC TEST: got avatar %.0fx%.0f",
            photo.width,
            photo.height
            ))
        else
            print("GC TEST: got avatar (no size info on proxy)")
        end
    end)
    print(localPlayerAvatar)
end

function drawLocalAvatarDebug()
  print("[STUB] drawLocalAvatarDebug")
end

-- shaders below
CircleS = {
  vertexShader = [[
  uniform mat4 modelViewProjection;
  
  attribute vec4 position;
  attribute vec4 color;
  attribute vec2 texCoord;
  
  varying lowp vec4 vColor;
  varying highp vec2 vTexCoord;
  void main()
  {
    vColor = color;
    vTexCoord = texCoord;
    gl_Position = modelViewProjection * position;
  }
]],
fragmentShader = [[
precision highp float;

uniform lowp sampler2D texture;
uniform lowp float circleSize;

varying lowp vec4 vColor;
varying highp vec2 vTexCoord;

void main()
{
highp vec4 col;
lowp float dis = distance(vTexCoord,vec2(0.5,0.5)); //get the distance from the texCoord to the center

if (dis < circleSize) { //circleSize is the size of the circle.
  //Turning a rectangular texture into a circle won't actually be that hard. All we have to do is remove
    //the pixels that are distant from the center. It's really that simple!
    col = texture2D(texture, vTexCoord); //sample the pixel in texture at the position vTexCoord
  }
else {col = vec4(0,0,0,0);} //remove this pixel
  gl_FragColor = col;
}
]]
}
