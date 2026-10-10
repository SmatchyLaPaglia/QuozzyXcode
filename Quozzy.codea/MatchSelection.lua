-- "vs" button UI: replaces the native GKTurnBasedMatchmakerViewController entirely.
-- Two modes on one overlay: "list" (open matches + finished-unviewed matches + New Game
-- button) and "friends" (pick a Game Center friend to start a new match against; no
-- automatch — see CLAUDE.md task notes). Visual language mirrors RecordsUI.lua (shared
-- _drawRowCard/_truncateWithEllipsis, promoted to global there for this reuse).

vsOverlay          = vsOverlay          or false
vsOverlayMode      = vsOverlayMode      or "list"   -- "list" | "friends"
vsListEntries      = vsListEntries      or {}
vsListLoading      = vsListLoading      or false
vsHasActionable    = vsHasActionable    or false    -- drives the vs-button red badge (playable or new result)
vsHasPlayable      = vsHasPlayable      or false    -- drives the quick-start badge (a round I can play)
-- Completed (both scores in -- the "apparent end") but not yet viewed. These live in
-- Records, not the vs list; they drive the records-button badge and Records row dots.
recordsUnseenEntries = recordsUnseenEntries or {}
recordsHasUnseen     = recordsHasUnseen     or false
vsFriendsEntries   = vsFriendsEntries   or {}
vsFriendsLoading   = vsFriendsLoading   or false
vsFriendsLoadError = vsFriendsLoadError or nil
vsNewGameBusy      = vsNewGameBusy      or false

vsScrollY        = vsScrollY        or 0
vsScrollTouchId  = vsScrollTouchId  or nil
vsScrollPrevY    = vsScrollPrevY    or 0
vsScrollPrevT    = vsScrollPrevT    or 0
vsScrollVel      = vsScrollVel      or 0
vsScrollMax      = vsScrollMax      or 0   -- recomputed each draw; used by touch handler's clamp
vsTouchMoved     = vsTouchMoved     or false
vsTouchStartX    = vsTouchStartX    or 0
vsTouchStartY    = vsTouchStartY    or 0
_VS_TAP_SLOP     = 10

vsRowRects   = vsRowRects   or {}   -- rebuilt each frame: {x,y,w,h, kind="newGame"|"match", entry}
vsOverlayGeom = vsOverlayGeom or nil

-- "Game ended" / "opponent commented" badge sets, keyed by match id. Read by
-- RecordsUI.lua's badge dots; cleared per-match by opponentRecords.lua once a
-- match's snapshot is recorded. Repopulated by refreshVsMatchesList from the
-- same GameKit load that builds the vs list (no second poll).
endedMatchBadgeIds   = endedMatchBadgeIds   or {}
commentMatchBadgeIds = commentMatchBadgeIds or {}

local function _vsSafeObjCString(v)
  if v == nil then return nil end
  local ok, s = pcall(function() return tostring(v) end)
  if not ok or not s or s == "" then return nil end
  return s
end

local function _vsSafeArrayCount(arr)
  if not arr then return 0 end
  if type(arr) == "table" then
    local ok, n = pcall(function() return #arr end)
    return (ok and type(n) == "number") and n or 0
  end
  local ok, n = pcall(function()
    if arr.respondsToSelector_ and arr:respondsToSelector_("count") then
      return tonumber(arr.count) or tonumber(arr:count()) or 0
    end
    return 0
  end)
  return (ok and type(n) == "number") and n or 0
end

local function _vsSafeArrayGet(arr, i)
  if not arr or i < 1 then return nil end
  if type(arr) == "table" then return arr[i] end
  local ok, v = pcall(function()
    if arr.respondsToSelector_ and arr:respondsToSelector_("objectAtIndex:") then
      return arr:objectAtIndex_(i - 1)
    end
    return nil
  end)
  return ok and v or nil
end

------------------------------------------------------------
-- "Already viewed" check.
------------------------------------------------------------
-- Was: presence of a COMPLETE snapshot in Records (recordMatchSnapshot,
-- opponentRecords.lua) — captured whenever the end screen actually builds. That snapshot
-- is only taken when the LOCAL player has played (pLocal.didPlay — see buildEndScreenModel,
-- EndScreenFP.lua), and its `complete` flag only tracks the OPPONENT's didPlay
-- (currentEndScreenState, EndScreen.lua) — neither matches what the vs list means by
-- "ended" (tbm._getEndStateFromMatch: GameKit considers the turn-based session itself
-- over, e.g. via resignation or time expiry, independent of either player's didPlay flag).
-- A match that GameKit ended without the local player ever submitting a turn would never
-- get a snapshot at all, so it could never clear from the list no matter how many times it
-- was opened. (2026-09-27: this was reported as finished matches never clearing.)
--
-- Now: a dedicated, directly-set marker (vsViewedMatchIds) — vsOpenMatchEntry marks a
-- match's id the moment an ended entry is opened, independent of what its snapshot ends up
-- looking like. The old snapshot check remains as a fallback, so matches already recorded
-- as complete under the old scheme (or viewed via Records instead of the vs list) still
-- count too.
------------------------------------------------------------

VS_VIEWED_MATCHES_KEY = VS_VIEWED_MATCHES_KEY or "QB_VS_VIEWED_MATCHES_V1"
vsViewedMatchIds = vsViewedMatchIds or nil   -- loaded dict: [matchId] = true

function loadVsViewedMatches()
  if vsViewedMatchIds ~= nil then return end
  local raw = readLocalData(VS_VIEWED_MATCHES_KEY)
  if raw and raw ~= "" then
    local ok, t = pcall(json.decode, raw)
    if ok and type(t) == "table" then vsViewedMatchIds = t; return end
  end
  vsViewedMatchIds = {}
end

function persistVsViewedMatches()
  if not vsViewedMatchIds then return end
  local ok, s = pcall(json.encode, vsViewedMatchIds)
  if ok and s then saveLocalData(VS_VIEWED_MATCHES_KEY, s) end
end

function markVsMatchViewed(matchId)
  if not matchId then return end
  loadVsViewedMatches()
  if vsViewedMatchIds[matchId] then return end
  vsViewedMatchIds[matchId] = true
  persistVsViewedMatches()
end

function vsMatchAlreadyViewed(matchId, oppId)
  if not matchId then return false end
  loadVsViewedMatches()
  if vsViewedMatchIds[matchId] then return true end

  if oppId and matchHistoryByOpponent then
    local list = matchHistoryByOpponent[oppId]
    if type(list) == "table" then
      for _, m in ipairs(list) do
        if m.id == matchId and m.complete then return true end
      end
    end
  end
  return false
end

function vsStatusTextForEntry(e)
  if e.ended or (e.localDidPlay and e.oppDidPlay) then return "Finished — tap to view" end
  if not e.localDidPlay then return "Your move" end
  return "Waiting for " .. (e.oppName or "opponent")
end

-- Pure predicate, pulled out of refreshVsMatchesList's per-entry loop so it
-- can be tested directly: a match needs my attention only if I haven't
-- played my own side yet (regardless of the opponent), or it's fully ended
-- in GameKit and I haven't viewed that ending yet. Once I've played my own
-- side, there's nothing new for me here until something actually changes on
-- the opponent's end -- a badge/"your move" label at that point would be
-- flagging information I already have, not new information.
function computeVsEntryNeedsAction(ended, localDidPlay, viewed, oppDidPlay)
  local playable, newInfo = computeVsEntryFlags(ended, localDidPlay, oppDidPlay, viewed)
  return playable or newInfo
end

-- Two separate signals, deliberately not merged:
--   playable -- I still have a round to play: the ONLY thing the quick-start
--               badge advertises.
--   newInfo  -- the result is in (both scores, i.e. gate 1 -- GameKit's own
--               "ended" only comes later, after both comments) and I haven't
--               opened it since: drives the vs-button dot and the row dot.
function computeVsEntryFlags(ended, localDidPlay, oppDidPlay, viewed)
  local finished = ended or (localDidPlay == true and oppDidPlay == true)
  local playable = (not ended) and not localDidPlay
  local newInfo = finished and not viewed
  return playable, newInfo
end

-- Recomputes the aggregate badge flags from vsListEntries. Called after every
-- list refresh, and directly when local state changes (vsNoteLocalRoundFinished)
-- so the badges don't show stale "match ready" until the next async refresh.
function recomputeVsBadgeFlags()
  vsHasActionable, vsHasPlayable = false, false
  for _, e in ipairs(vsListEntries or {}) do
    e.playable, e.newInfo = computeVsEntryFlags(e.ended, e.localDidPlay, e.oppDidPlay, e.viewed)
    e.needsAction = e.playable
    if e.playable then vsHasActionable = true; vsHasPlayable = true end
  end
  local kept = {}
  for _, e in ipairs(recordsUnseenEntries or {}) do
    if not e.viewed then kept[#kept + 1] = e end
  end
  recordsUnseenEntries = kept
  recordsHasUnseen = #kept > 0
end

-- Unseen completed matches for one opponent, shaped like matchHistoryByOpponent
-- entries (RecordsUI.lua draws them with the same row code), newest first.
-- unseenEntry is the live vs entry used to open the match.
function recordsUnseenMatchesFor(oppId)
  local out = {}
  for _, e in ipairs(recordsUnseenEntries or {}) do
    if e.oppId == oppId and not e.viewed then
      local q = e.q or {}
      local me = q.players and q.players[localPID()] or {}
      local opp = q.players and q.players[oppId] or {}
      out[#out + 1] = {
        id = e.id, oppId = oppId, complete = true, unseenEntry = e,
        localScore = tonumber(me.score) or 0, oppScore = tonumber(opp.score) or 0,
        endedAt = e.sortTs, boardTiles = q.boardTiles, boardSize = q.boardSize,
        localComment = me.comment or "", oppComment = opp.comment or "",
      }
    end
  end
  table.sort(out, function(a, b) return (a.endedAt or 0) > (b.endedAt or 0) end)
  return out
end

-- endGameRound calls this: the match I just finished is no longer playable,
-- whatever the last list refresh said.
function vsNoteLocalRoundFinished(matchId)
  for _, e in ipairs(vsListEntries or {}) do
    if e.id == matchId then e.localDidPlay = true end
  end
  recomputeVsBadgeFlags()
end

------------------------------------------------------------
-- Data refresh
------------------------------------------------------------
function refreshVsMatchesList(reason)
  if vsListLoading then return end
  local GKTurnBasedMatch = objc and objc.GKTurnBasedMatch
  if not (tbm and tbm.localPlayer and tbm.localPlayer.authenticated and GKTurnBasedMatch) then
    vsListEntries, vsHasActionable, vsHasPlayable = {}, false, false
    recordsUnseenEntries, recordsHasUnseen = {}, false
    return
  end
  vsListLoading = true
  local ok = pcall(function()
    GKTurnBasedMatch:loadMatchesWithCompletionHandler_(function(o__matches, o__err)
      objc.async(function()
        local okInner, errInner = pcall(function()
          vsListLoading = false
          if o__err then
            devLog("vs: loadMatches error", _vsSafeObjCString(o__err.localizedDescription) or "?")
            return
          end
          local list = {}
          local unseen = {}
          local liveMatches = {}  -- every decoded match, for computeMatchBadges
          local n = _vsSafeArrayCount(o__matches)
          for i = 1, n do
            local m = _vsSafeArrayGet(o__matches, i)
            if m then
              local dataTable = tbm._matchWithNSDataToDataTable and tbm:_matchWithNSDataToDataTable(m) or nil
              local q = makeQMatchFromGK and makeQMatchFromGK(m, dataTable) or nil
              if q then
                local pid = localPID()
                local me = q.players and q.players[pid]
                local oppId = q.opponentId
                local oppData = oppId and q.players and q.players[oppId]
                -- Badge input comes from EVERY match, not just the ones that
                -- survive into the vs list below: an already-viewed finished
                -- match can still get a new opponent comment, which
                -- matchNeedsCommentBadge detects by comparing comment text.
                if oppId and me and oppData then
                  liveMatches[#liveMatches + 1] = {
                    id = q.id,
                    oppId = oppId,
                    bothPlayed = (me.didPlay == true and oppData.didPlay == true),
                    oppComment = oppData.comment or "",
                  }
                end
                local endedState = tbm._getEndStateFromMatch and tbm:_getEndStateFromMatch(m) or nil
                local ended = endedState ~= nil
                local finished = ended or (me and me.didPlay == true and oppData and oppData.didPlay == true)
                local viewed = finished and vsMatchAlreadyViewed(q.id, oppId) or false
                if not (finished and viewed) then
                  local entry = {
                    id = q.id, gkMatch = m, dataTable = dataTable, q = q,
                    oppId = oppId, oppName = q.opponentName or "Opponent",
                    ended = ended,
                    localDidPlay = me and me.didPlay or false,
                    oppDidPlay = oppData and oppData.didPlay or false,
                    viewed = viewed,
                    sortTs = q.lastUpdated or 0,
                    avatar = nil,
                  }
                  if finished then
                    -- Completed matches belong to Records; only unseen ones are kept
                    -- here (for its badges and rows), viewed ones live in match history.
                    if not viewed then unseen[#unseen + 1] = entry end
                  else
                    list[#list + 1] = entry
                  end
                  -- entry.avatar is resolved in _drawVsMatchesList, NOT here: readImage inside
                  -- this GameKit callback returns a blank image (and caches it for good).
                end
              end
            end
          end
          table.sort(list, function(a, b) return (a.sortTs or 0) > (b.sortTs or 0) end)
          vsListEntries = list
          recordsUnseenEntries = unseen
          recomputeVsBadgeFlags()
          local ended, commented = {}, {}
          if computeMatchBadges then
            ended, commented = computeMatchBadges(liveMatches)
          end
          local endedSet, commentedSet = {}, {}
          for _, id in ipairs(ended or {}) do endedSet[id] = true end
          for _, id in ipairs(commented or {}) do commentedSet[id] = true end
          endedMatchBadgeIds = endedSet
          commentMatchBadgeIds = commentedSet
          devLog("vs: matches list refreshed", "count=", #list, "actionable=", vsHasActionable,
            "ended=", #(ended or {}), "commented=", #(commented or {}), "reason=", reason or "?")
        end)
        if not okInner then
          vsListLoading = false
          devLog("vs: refreshVsMatchesList crashed safely", tostring(errInner))
        end
      end)
    end)
  end)
  if not ok then vsListLoading = false end
end

------------------------------------------------------------
-- Opening / creating matches
------------------------------------------------------------
function openVsOverlay()
  vsOverlay = true
  vsOverlayMode = "list"
  vsScrollY, vsScrollVel = 0, 0
  refreshVsMatchesList("open")
end

function closeVsOverlay()
  vsOverlay = false
  vsScrollTouchId = nil
end

function vsOpenMatchEntry(entry)
  if not entry or not entry.gkMatch then return end
  closeVsOverlay()
  -- Mark it viewed the moment it's opened, independent of anything that happens after —
  -- see vsMatchAlreadyViewed above for why this can't just rely on a Records snapshot.
  if (entry.ended or (entry.localDidPlay and entry.oppDidPlay)) and markVsMatchViewed then
    markVsMatchViewed(entry.id)
    entry.viewed = true
    recomputeVsBadgeFlags()
  end
  if tbm and tbm._setCurrentMatch then
    tbm:_setCurrentMatch(entry.gkMatch, "vs-list-open")
  end
  local dataTable = entry.dataTable
  if not dataTable and tbm and tbm._matchWithNSDataToDataTable then
    dataTable = tbm:_matchWithNSDataToDataTable(entry.gkMatch)
  end
  local q = makeQMatchFromGK and makeQMatchFromGK(entry.gkMatch, dataTable) or nil
  if q and enterQMatch then enterQMatch(q) end
end

function vsOpenFriendPicker()
  vsOverlayMode = "friends"
  vsFriendsLoadError = nil
  vsScrollY, vsScrollVel = 0, 0
  vsLoadFriends()
end

function vsBackToList()
  vsOverlayMode = "list"
  vsScrollY, vsScrollVel = 0, 0
end

function vsLoadFriends()
  if vsFriendsLoading then return end
  local lp = tbm and tbm.localPlayer
  if not (lp and lp.loadFriendPlayersWithCompletionHandler_) then
    vsFriendsEntries, vsFriendsLoadError = {}, "Game Center friends aren't available on this device."
    return
  end
  vsFriendsLoading, vsFriendsLoadError = true, nil
  local ok = pcall(function()
    lp:loadFriendPlayersWithCompletionHandler_(function(o__players, o__err)
      objc.async(function()
        local okInner, errInner = pcall(function()
          vsFriendsLoading = false
          if o__err then
            vsFriendsEntries = {}
            vsFriendsLoadError = _vsSafeObjCString(o__err.localizedDescription) or "Couldn't load your Game Center friends."
            return
          end
          local list = {}
          local n = _vsSafeArrayCount(o__players)
          for i = 1, n do
            local p = _vsSafeArrayGet(o__players, i)
            if p then
              local entry = {
                player = p,
                oppId = p.gamePlayerID or p.playerID or nil,
                name = _vsSafeObjCString(p.alias) or _vsSafeObjCString(p.displayName) or "Player",
                avatar = nil,
              }
              list[#list + 1] = entry
              if loadPlayerPhoto then
                loadPlayerPhoto(p, function(img) entry.avatar = img end)
              end
            end
          end
          -- Most-recently-played first (same opponentLastActivity used to sort Records —
          -- opponentRecords.lua). Friends never played fall to the bottom, alphabetically.
          table.sort(list, function(a, b)
            local ta = (a.oppId and opponentLastActivity and opponentLastActivity(a.oppId)) or 0
            local tb = (b.oppId and opponentLastActivity and opponentLastActivity(b.oppId)) or 0
            if ta ~= tb then return ta > tb end
            return (a.name or "") < (b.name or "")
          end)
          vsFriendsEntries = list
          if #list == 0 then
            vsFriendsLoadError = "No Game Center friends found yet."
          end
        end)
        if not okInner then
          vsFriendsLoading = false
          devLog("vs: vsLoadFriends crashed safely", tostring(errInner))
        end
      end)
    end)
  end)
  if not ok then
    vsFriendsLoading = false
    vsFriendsLoadError = "Couldn't load your Game Center friends."
  end
end

function vsStartNewMatchWithFriend(friendEntry)
  if vsNewGameBusy or not (friendEntry and friendEntry.player) then return end
  local GKTurnBasedMatch = objc and objc.GKTurnBasedMatch
  if not (tbm and GKTurnBasedMatch) then return end
  vsNewGameBusy = true
  tbm.pendingRequestedBoardSize  = boardSize
  tbm.pendingRequestedMinWordLen = MIN_WORD_LEN
  local request = objc.GKMatchRequest()
  request.minPlayers = 2
  request.maxPlayers = 2
  request.recipients = { friendEntry.player }
  local ok = pcall(function()
    GKTurnBasedMatch:findMatchForRequest_withCompletionHandler_(request, function(o__match, o__err)
      objc.async(function()
        local okInner, errInner = pcall(function()
          vsNewGameBusy = false
          if o__err or not o__match then
            local msg = o__err and o__err.localizedDescription or "nil match"
            devLog("vs: new match creation failed", msg)
            if openGCMatchmakerErrorOverlay then
              openGCMatchmakerErrorOverlay("Couldn't start a new game with " .. (friendEntry.name or "that player") .. ". " .. tostring(msg))
            end
            return
          end
          devLog("vs: new match created", o__match.matchID or "?")
          closeVsOverlay()
          if tbm and tbm._setCurrentMatch then
            tbm:_setCurrentMatch(o__match, "vs-new-game")
          end
          local dataTable = tbm._matchWithNSDataToDataTable and tbm:_matchWithNSDataToDataTable(o__match) or nil
          local q = makeQMatchFromGK and makeQMatchFromGK(o__match, dataTable) or nil
          if q and enterQMatch then enterQMatch(q) end
        end)
        if not okInner then
          vsNewGameBusy = false
          devLog("vs: new-match callback crashed safely", tostring(errInner))
        end
      end)
    end)
  end)
  if not ok then vsNewGameBusy = false end
end

-- Deep-link to Apple's own Game Center friends UI. There is no API for a
-- third-party app to send a friend request programmatically (see CLAUDE.md
-- task notes) — this is the closest equivalent: hand the user off to the
-- real Game Center screen where they manage friends themselves.
function vsOpenNativeGameCenterFriends()
  if not (objc and objc.GKGameCenterViewController and tbm and tbm.viewController) then return end
  local ok = pcall(function()
    local vc = objc.GKGameCenterViewController:alloc():init()
    local stateEnum = objc.enum.GKGameCenterViewControllerState
    local viewState = 0
    if stateEnum then
      viewState = stateEnum.localPlayerFriendsList or stateEnum.default or 0
    end
    vc.viewState = viewState
    local Delegate = objc.class("VsGCFriendsDelegate")
    local vcRef = tbm.viewController
    function Delegate:gameCenterViewControllerDidFinish_(o__vc)
      vcRef:dismissModalViewControllerAnimated_(true, nil)
    end
    vc.gameCenterDelegate = Delegate()
    tbm.viewController:presentModalViewController_animated_(vc, true)
  end)
  if not ok then
    devLog("vs: failed to present native Game Center friends UI")
  end
end

------------------------------------------------------------
-- Draw
------------------------------------------------------------
local function _vsPanelGeom()
  local panelW = WIDTH - 16
  local panelH = HEIGHT * 0.9
  local panelX = WIDTH / 2
  local panelY = HEIGHT / 2
  panelY, panelH = clampPanelTopToSafeArea(panelY, panelH)

  local innerPadding = 10
  local innerLeft   = panelX - panelW/2 + innerPadding
  local innerRight  = panelX + panelW/2 - innerPadding
  local innerTop    = panelY + panelH/2 - innerPadding
  local innerBottom = panelY - panelH/2 + innerPadding
  local titleBandH  = 56
  local buttonBandH = 70
  return {
    panelX = panelX, panelY = panelY, panelW = panelW, panelH = panelH,
    innerLeft = innerLeft, innerRight = innerRight,
    innerTop = innerTop, innerBottom = innerBottom,
    listWidth = innerRight - innerLeft,
    listTop = innerTop - titleBandH,
    listBottom = innerBottom + buttonBandH,
  }
end

function drawVsOverlay()
  if not vsOverlay then return end

  pushStyle()
  fill(Color.panelDim)
  noStroke()
  rectMode(CORNER)
  rect(0, 0, WIDTH, HEIGHT)
  popStyle()

  local g = _vsPanelGeom()
  g.listHeight = g.listTop - g.listBottom

  pushStyle()
  rectMode(CENTER)
  noStroke()
  local pc = Color.panelBG or color(40, 40, 40, 255)
  drawRoundedRect(g.panelX, g.panelY, g.panelW, g.panelH, 22, color(pc.r, pc.g, pc.b, 255), color(pc.r, pc.g, pc.b, 255))
  popStyle()

  if vsOverlayMode == "friends" then
    _drawVsFriendsList(g)
  else
    _drawVsMatchesList(g)
  end

  vsOverlayGeom = g
end

-- textMode(CORNER) makes x the LEFT edge even with textAlign(CENTER); center by measuring.
local function _vsTextCentered(str, cx, y)
  local w = textSize(str)
  text(str, cx - w * 0.5, y)
end

-- Row hit rects are trimmed to the visible list viewport so a row scrolled out of view
-- (under the title or the bottom button) can't be tapped through.
local function _vsPushRowRect(r, viewBottom, viewTop)
  local y0 = math.max(r.y, viewBottom)
  local y1 = math.min(r.y + r.h, viewTop)
  if y1 <= y0 then return end
  r.y, r.h = y0, y1 - y0
  vsRowRects[#vsRowRects+1] = r
end

function _drawVsMatchesList(g)
  vsRowRects = {}
  pushStyle()
  textMode(CORNER)
  local tileText = Color.tileText or color(255)

  textAlign(CENTER)
  fill(tileText)
  font("Georgia-Bold")
  fontSize(24)
  _vsTextCentered("Games", g.panelX, g.innerTop - 26)

  local rowH = 84
  local gap = 10
  local newGameH = 60

  local totalH = newGameH + gap + #vsListEntries * (rowH + gap)
  local maxScroll = math.max(0, totalH - g.listHeight)
  vsScrollMax = maxScroll
  if not vsScrollTouchId then
    vsScrollY, vsScrollVel = applyScrollInertia(vsScrollY, vsScrollVel, 0, maxScroll, DeltaTime)
  end
  if vsScrollY < 0 then vsScrollY = 0 end
  if vsScrollY > maxScroll then vsScrollY = maxScroll end

  -- Pre-generate avatars + board thumbs BEFORE clip(): both render via setContext, which
  -- produces GPU garbage under an active clip scissor — and both are cached,
  -- so one bad render sticks for every later draw at that size (see RecordsUI, STRUCTURE.md).
  local entryAvatars, entryThumbs = {}, {}
  for i, e in ipairs(vsListEntries) do
    if not e.avatar and e.oppId then e.avatar = getOpponentRecordAvatar(e.oppId) end
    entryAvatars[i] = e.avatar or unknownPlayerAvatar(rowH - 16, Color.uiAccent)
    entryThumbs[i] = getRecordsBoardThumb(e.q, 64)
  end

  clip(g.innerLeft, g.listBottom, g.listWidth, g.listHeight)
  local cursorY = g.listTop + vsScrollY

  -- "+ New Game" is always the first row
  do
    local cardCy = cursorY - newGameH * 0.5
    if cardCy + newGameH*0.5 > g.listBottom and cardCy - newGameH*0.5 < g.listTop then
      local cardCx = g.innerLeft + g.listWidth * 0.5
      _drawRowCard(cardCx, cardCy, g.listWidth, newGameH, 16, Color.uiAccent, 2)
      textAlign(CENTER)
      fill(Color.uiAccent)
      font("HelveticaNeue-Bold")
      fontSize(22)
      _vsTextCentered("+ New Game", cardCx, cardCy - 8)
    end
    _vsPushRowRect({ x = g.innerLeft, y = cardCy - newGameH*0.5, w = g.listWidth, h = newGameH, kind = "newGame" }, g.listBottom, g.listTop)
    cursorY = cursorY - newGameH - gap
  end

  if vsListLoading and #vsListEntries == 0 then
    fill(tileText.r, tileText.g, tileText.b, 160)
    font("Georgia-Italic")
    fontSize(18)
    textAlign(CENTER)
    _vsTextCentered("Loading games…", g.panelX, (g.listTop + g.listBottom) * 0.5)
  elseif #vsListEntries == 0 then
    fill(tileText.r, tileText.g, tileText.b, 160)
    font("Georgia-Italic")
    fontSize(18)
    textAlign(CENTER)
    _vsTextCentered("No open games right now.", g.panelX, (g.listTop + g.listBottom) * 0.5 - 40)
  end

  for i, e in ipairs(vsListEntries) do
    local cardCy = cursorY - rowH * 0.5
    if cardCy + rowH*0.5 > g.listBottom and cardCy - rowH*0.5 < g.listTop then
      local cardCx = g.innerLeft + g.listWidth * 0.5
      local borderCol = e.needsAction and Color.uiAccent2 or (tileText and color(tileText.r, tileText.g, tileText.b, 70)) or color(255,255,255,70)
      _drawRowCard(cardCx, cardCy, g.listWidth, rowH, 16, borderCol, 2)

      local avatarSize = rowH - 16
      local avatarCx = g.innerLeft + 8 + avatarSize * 0.5
      drawAvatarCircle(entryAvatars[i], avatarCx, cardCy, avatarSize)

      -- Unseen result badge: every row still in this list with e.ended==true is, by
      -- construction, not yet viewed (an ended+viewed match is filtered out above) — so
      -- this is exactly the set of "unseen results" the vs-button's own red dot is warning
      -- about (vsHasActionable). "Your turn" rows (not ended) get their own accent border/
      -- text instead — a different signal, so no dot there.
      if e.newInfo and drawRedBadgeDot then
        local br = math.max(7, avatarSize * 0.14)
        drawRedBadgeDot(avatarCx + avatarSize * 0.5 - br * 0.6, cardCy + avatarSize * 0.5 - br * 0.6, br)
      end

      local thumb = entryThumbs[i]
      local textLeft = avatarCx + avatarSize * 0.5 + 12
      local textRight = g.innerRight - 8 - (thumb and 72 or 0)
      if thumb then
        spriteMode(CENTER)
        tint(255, 255)
        sprite(thumb, g.innerRight - 8 - 32, cardCy, 64, 64)
      end

      textAlign(LEFT)
      font("HelveticaNeue-Bold")
      fontSize(19)
      fill(tileText)
      local name = _truncateWithEllipsis(e.oppName or "Opponent", textRight - textLeft)
      text(name, textLeft, cardCy + 12)

      font("HelveticaNeue")
      fontSize(15)
      fill(e.needsAction and Color.uiAccent2 or color(tileText.r, tileText.g, tileText.b, 160))
      text(_truncateWithEllipsis(vsStatusTextForEntry(e), textRight - textLeft), textLeft, cardCy - 14)
    end
    _vsPushRowRect({ x = g.innerLeft, y = cardCy - rowH*0.5, w = g.listWidth, h = rowH, kind = "match", entry = e }, g.listBottom, g.listTop)
    cursorY = cursorY - rowH - gap
  end
  clip()

  local btnCy = g.innerBottom + 30
  drawButton(g.panelX, btnCy, g.listWidth, 60, "Close", false)
  popStyle()
end

function _drawVsFriendsList(g)
  vsRowRects = {}
  pushStyle()
  textMode(CORNER)
  local tileText = Color.tileText or color(255)

  textAlign(CENTER)
  fill(tileText)
  font("Georgia-Bold")
  fontSize(24)
  _vsTextCentered("New Game", g.panelX, g.innerTop - 26)

  -- Disclaimer, wrapped, just under the title
  font("Georgia-Italic")
  fontSize(14)
  fill(tileText.r, tileText.g, tileText.b, 190)
  textWrapWidth(g.listWidth - 20)
  local disclaimer = "Because Vivaldi-ku enables sending text to other players you may only play against existing Game Center friends."
  local _, discH = textSize(disclaimer)
  text(disclaimer, g.innerLeft + 10, g.innerTop - 56 - discH)
  textWrapWidth(0)

  local manageBtnH = 46
  local manageBtnY = g.innerTop - 56 - discH - 16 - manageBtnH * 0.5
  drawButton(g.panelX, manageBtnY, g.listWidth, manageBtnH, "Manage Game Center Friends", false)
  vsRowRects[#vsRowRects+1] = { x = g.innerLeft, y = manageBtnY - manageBtnH*0.5, w = g.listWidth, h = manageBtnH, kind = "manageFriends" }

  local listTop = manageBtnY - manageBtnH * 0.5 - 14
  local listBottom = g.listBottom
  local listHeight = listTop - listBottom

  local rowH = 72
  local gap = 10
  local totalH = #vsFriendsEntries * (rowH + gap)
  local maxScroll = math.max(0, totalH - listHeight)
  vsScrollMax = maxScroll
  if not vsScrollTouchId then
    vsScrollY, vsScrollVel = applyScrollInertia(vsScrollY, vsScrollVel, 0, maxScroll, DeltaTime)
  end
  if vsScrollY < 0 then vsScrollY = 0 end
  if vsScrollY > maxScroll then vsScrollY = maxScroll end

  -- Pre-generate placeholder avatars before clip() (setContext under clip = black texture).
  local friendAvatars = {}
  for i, e in ipairs(vsFriendsEntries) do
    friendAvatars[i] = e.avatar or unknownPlayerAvatar(rowH - 16, Color.uiAccent)
  end

  clip(g.innerLeft, listBottom, g.listWidth, listHeight)
  local cursorY = listTop + vsScrollY

  if vsFriendsLoading and #vsFriendsEntries == 0 then
    fill(tileText.r, tileText.g, tileText.b, 160)
    font("Georgia-Italic")
    fontSize(18)
    textAlign(CENTER)
    _vsTextCentered("Loading friends…", g.panelX, (listTop + listBottom) * 0.5)
  elseif vsFriendsLoadError then
    fill(tileText.r, tileText.g, tileText.b, 190)
    font("Georgia-Italic")
    fontSize(16)
    textAlign(CENTER)
    textWrapWidth(g.listWidth - 40)
    text(vsFriendsLoadError, g.panelX - (g.listWidth - 40) * 0.5, (listTop + listBottom) * 0.5)
    textWrapWidth(0)
  end

  for i, e in ipairs(vsFriendsEntries) do
    local cardCy = cursorY - rowH * 0.5
    if cardCy + rowH*0.5 > listBottom and cardCy - rowH*0.5 < listTop then
      local cardCx = g.innerLeft + g.listWidth * 0.5
      _drawRowCard(cardCx, cardCy, g.listWidth, rowH, 16, color(tileText.r, tileText.g, tileText.b, 70), 2)

      local avatarSize = rowH - 16
      local avatarCx = g.innerLeft + 8 + avatarSize * 0.5
      drawAvatarCircle(friendAvatars[i], avatarCx, cardCy, avatarSize)

      textAlign(LEFT)
      font("HelveticaNeue-Bold")
      fontSize(19)
      fill(tileText)
      text(_truncateWithEllipsis(e.name, g.innerRight - 8 - (avatarCx + avatarSize*0.5 + 12)), avatarCx + avatarSize*0.5 + 12, cardCy - 6)
    end
    _vsPushRowRect({ x = g.innerLeft, y = cardCy - rowH*0.5, w = g.listWidth, h = rowH, kind = "friend", entry = e }, listBottom, listTop)
    cursorY = cursorY - rowH - gap
  end
  clip()

  local btnCy = g.innerBottom + 30
  drawButton(g.panelX, btnCy, g.listWidth, 60, "Back", false)
  popStyle()
end

------------------------------------------------------------
-- Touch
------------------------------------------------------------
function handleVsOverlayTouch(t)
  if not vsOverlay then return false end
  local g = vsOverlayGeom
  if not g then
    if t.state == ENDED then closeVsOverlay() end
    return true
  end

  local btnCy = g.innerBottom + 30
  local bottomBtn = { cx = g.panelX, cy = btnCy, w = g.listWidth, h = 60 }

  if t.state == BEGAN then
    vsScrollTouchId, vsScrollPrevY = t.id, t.y
    vsScrollPrevT, vsScrollVel = ElapsedTime, 0
    vsTouchStartX, vsTouchStartY, vsTouchMoved = t.x, t.y, false
    return true
  elseif t.state == MOVING then
    if vsScrollTouchId and t.id == vsScrollTouchId then
      local dy = t.y - vsScrollPrevY
      vsScrollPrevY = t.y
      vsScrollY = vsScrollY + dy
      if vsScrollY < 0 then vsScrollY = 0 end
      if vsScrollY > vsScrollMax then vsScrollY = vsScrollMax end
      local now = ElapsedTime
      local dt = now - (vsScrollPrevT or now)
      if dt > 0 then vsScrollVel = dy / dt end
      vsScrollPrevT = now
      if math.abs(t.y - vsTouchStartY) > _VS_TAP_SLOP or math.abs(t.x - vsTouchStartX) > _VS_TAP_SLOP then
        vsTouchMoved = true
      end
    end
    return true
  elseif t.state == ENDED or t.state == CANCELLED then
    vsScrollTouchId = nil
    if vsTouchMoved or t.state == CANCELLED then return true end

    if pointInRect(t.x, t.y, bottomBtn.cx, bottomBtn.cy, bottomBtn.w, bottomBtn.h) then
      if vsOverlayMode == "friends" then vsBackToList() else closeVsOverlay() end
      return true
    end

    for _, r in ipairs(vsRowRects) do
      if t.x >= r.x and t.x <= r.x + r.w and t.y >= r.y and t.y <= r.y + r.h then
        if r.kind == "newGame" then
          vsOpenFriendPicker()
        elseif r.kind == "match" then
          vsOpenMatchEntry(r.entry)
        elseif r.kind == "manageFriends" then
          vsOpenNativeGameCenterFriends()
        elseif r.kind == "friend" then
          vsStartNewMatchWithFriend(r.entry)
        end
        return true
      end
    end
    return true
  end

  return true
end
