-- Notification trial harness: which GameKit sends show the other player a banner?
-- Load with DBG_DEVICE=<id> tools/dbg.sh -f tools/notify_trial.lua, then QT.mute() first.
-- Callbacks only handOff (CLAUDE.md hard rule); results land in QT.log (QT.dump()).
-- Never add a notification-settings/delivered query here: those froze the app (XCODE_CODEA.md).
QT = QT or {}
QT.log = QT.log or {}

local function L(...)
  local t = {}
  for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
  QT.log[#QT.log + 1] = os.date("%H:%M:%S") .. " " .. table.concat(t, " ")
end
local function cnt(a)
  if a == nil then return 0 end
  if type(a) == "table" then return #a end
  local ok, n = pcall(function() return tonumber(a.count) or a:count() end)
  return ok and n or -1
end
local function get(a, i)
  if type(a) == "table" then return a[i] end
  local ok, v = pcall(function() return a:objectAtIndex_(i - 1) end)
  return ok and v or nil
end
local function s(v) if v == nil then return "nil" end local ok, r = pcall(tostring, v) return ok and r or "?" end
local function err(e) if not e then return "ok" end return "ERR " .. s(e.localizedDescription) .. " (code " .. s(e.code) .. ")" end
local function myId() return objc.GKLocalPlayer.localPlayer.gamePlayerID end
local function data(t) return tbm:_dataTableToNSData(t) end

-- The app's own handlers would enter the test match or auto-reply (an extra banner).
function QT.mute()
  QT.saved = QT.saved or {
    rt = tbm._onReceivingTurn, sc = tbm._onSettingCurrentMatch, te = tbm._onTurnEnded,
    xr = tbm._onReceivedExchangeRequest, xp = tbm._onReceivedExchangeReplies,
  }
  tbm._onReceivingTurn = function(m) L("event: turn", m and s(m.matchID)) end
  tbm._onSettingCurrentMatch = function(m) end
  tbm._onTurnEnded = function(m) L("event: turnEnded") end
  tbm._onReceivedExchangeRequest = function(m, ex) L("event: exchange request") end
  tbm._onReceivedExchangeReplies = function(m, ex) L("event: exchange replies") end
  return "muted"
end
function QT.unmute()
  if not QT.saved then return "not muted" end
  tbm._onReceivingTurn, tbm._onSettingCurrentMatch, tbm._onTurnEnded =
    QT.saved.rt, QT.saved.sc, QT.saved.te
  tbm._onReceivedExchangeRequest, tbm._onReceivedExchangeReplies = QT.saved.xr, QT.saved.xp
  QT.saved = nil
  return "unmuted"
end

-- Sends this app to the background (private UIApplication method; dev test only)
-- so the next notification is presented as a banner instead of swallowed.
function QT.background()
  objc.UIApplication.sharedApplication:suspend()
  return "backgrounded"
end

function QT.describe()
  local m = QT.m
  if not m then return "no match" end
  local out = { "match " .. s(m.matchID) .. " status=" .. s(m.status) }
  local cp = m.currentParticipant
  out[#out + 1] = "current=" .. (cp and cp.player and s(cp.player.alias) or "nil")
  for i = 1, cnt(m.participants) do
    local p = get(m.participants, i)
    out[#out + 1] = string.format("  p%d %s status=%s outcome=%s", i,
      p.player and s(p.player.alias) or "(open slot)", s(p.status), s(p.matchOutcome))
  end
  out[#out + 1] = "active=" .. cnt(m.activeExchanges) .. " completed=" .. cnt(m.completedExchanges)
  return table.concat(out, "\n")
end

function QT.findB(alias)
  QT.B = nil
  objc.GKLocalPlayer.localPlayer:loadFriendPlayersWithCompletionHandler_(function(o__players, o__err)
    handOff(function(o__players, o__err)
      if o__err then L("friends", err(o__err)) return end
      for i = 1, cnt(o__players) do
        local p = get(o__players, i)
        if p and s(p.alias) == alias then QT.B = p end
      end
      L("findB", QT.B and ("found " .. s(QT.B.alias)) or ("not found among " .. cnt(o__players)))
    end, o__players, o__err)
  end)
  return "loading friends"
end

function QT.create()
  local req = objc.GKMatchRequest()
  req.minPlayers, req.maxPlayers = 2, 2
  req.recipients = { QT.B }
  objc.GKTurnBasedMatch:findMatchForRequest_withCompletionHandler_(req, function(o__match, o__err)
    handOff(function(o__match, o__err)
      if o__err or not o__match then L("create", err(o__err)) return end
      QT.m, QT.matchID = o__match, s(o__match.matchID)
      L("created", QT.matchID)
    end, o__match, o__err)
  end)
  return "creating"
end

function QT.acceptById(matchID)
  objc.GKTurnBasedMatch:loadMatchWithID_withCompletionHandler_(matchID, function(o__match, o__err)
    handOff(function(o__match, o__err)
      if o__err or not o__match then L("load for accept", err(o__err)) return end
      o__match:acceptInviteWithCompletionHandler_(function(o__m2, o__e2)
        handOff(function(o__m2, o__e2)
          if o__e2 or not o__m2 then L("accept", err(o__e2)) return end
          QT.m, QT.matchID = o__m2, s(o__m2.matchID)
          L("accepted", QT.matchID)
        end, o__m2, o__e2)
      end)
    end, o__match, o__err)
  end)
  return "accepting " .. tostring(matchID)
end

function QT.reload()
  objc.GKTurnBasedMatch:loadMatchWithID_withCompletionHandler_(QT.matchID, function(o__match, o__err)
    handOff(function(o__match, o__err)
      if o__err then L("reload", err(o__err)) return end
      QT.m = o__match
      L("reloaded\n" .. QT.describe())
    end, o__match, o__err)
  end)
  return "reloading"
end

function QT.others()
  local me, list = myId(), {}
  for i = 1, cnt(QT.m.participants) do
    local p = get(QT.m.participants, i)
    if not (p.player and s(p.player.gamePlayerID) == s(me)) then list[#list + 1] = p end
  end
  return list
end

function QT.passTurn(message)
  if message then QT.m.message = message end
  QT.m:endTurnWithNextParticipants_turnTimeout_matchData_completionHandler_(
    QT.others(), 0, data({ qt = "turn", at = os.time() }), function(o__err)
      handOff(function(o__err) L("passTurn", err(o__err)) end, o__err)
    end)
  return "passing turn"
end

function QT.sendEx(key)
  QT.m:sendExchangeToParticipants_data_localizableMessageKey_arguments_timeout_completionHandler_(
    QT.others(), data({ qt = "exchange", key = key, at = os.time() }), key, {}, 600,
    function(o__exchange, o__err)
      handOff(function(o__exchange, o__err) L("sendEx " .. key, err(o__err)) end, o__exchange, o__err)
    end)
  return "sending exchange " .. key
end

function QT.replyAll(key)
  local active = QT.m.activeExchanges
  local n = cnt(active)
  for i = 1, n do
    local ex = get(active, i)
    ex:replyWithLocalizableMessageKey_arguments_data_completionHandler_(
      key, {}, data({ qt = "reply", at = os.time() }), function(o__err)
        handOff(function(o__err) L("reply " .. key, err(o__err)) end, o__err)
      end)
  end
  return "replying to " .. n .. " exchange(s) with " .. key
end

function QT.merge()
  local done = QT.m.completedExchanges
  QT.m:saveMergedMatchData_withResolvedExchanges_completionHandler_(
    data({ qt = "merged", at = os.time() }), done or {}, function(o__err)
      handOff(function(o__err) L("merge " .. cnt(done), err(o__err)) end, o__err)
    end)
  return "merging " .. cnt(done)
end

function QT.saveTurn()
  QT.m:saveCurrentTurnWithMatchData_completionHandler_(data({ qt = "saved", at = os.time() }), function(o__err)
    handOff(function(o__err) L("saveTurn", err(o__err)) end, o__err)
  end)
  return "saving"
end

function QT.reminder(key)
  QT.m:sendReminderToParticipants_localizableMessageKey_arguments_completionHandler_(
    QT.others(), key, {}, function(o__err)
      handOff(function(o__err) L("reminder " .. key, err(o__err)) end, o__err)
    end)
  return "sending reminder " .. key
end

-- outcomes: GKTurnBasedMatchOutcome 2=won 3=lost 4=tied
function QT.endMatch(message)
  if message then QT.m.message = message end
  local me = myId()
  for i = 1, cnt(QT.m.participants) do
    local p = get(QT.m.participants, i)
    p.matchOutcome = (p.player and s(p.player.gamePlayerID) == s(me)) and 2 or 3
  end
  QT.m:endMatchInTurnWithMatchData_completionHandler_(data({ qt = "ended", at = os.time() }), function(o__err)
    handOff(function(o__err) L("endMatch", err(o__err)) end, o__err)
  end)
  return "ending"
end


function QT.dump(n)
  n = n or 25
  return table.concat(QT.log, "\n", math.max(1, #QT.log - n + 1), #QT.log)
end

return "QT loaded"
