-- GameKit exchange/timeout trial harness. Load into the running app with:
--   DBG_SIM=<udid> tools/dbg.sh -f tools/xchg_trial.lua
-- then drive it with one-line calls, e.g. tools/dbg.sh 'return XT.create()'.
-- Callbacks only record data into XT.log (no Codea/UIKit work inside them);
-- read results with 'return XT.dump()'. See MULTIPLAYER_DESIGN.md (exchange trial).
XT = XT or {}
XT.log = XT.log or {}

local function L(...)
  local t = {}
  for i = 1, select('#', ...) do t[#t + 1] = tostring((select(i, ...))) end
  local line = os.date("%H:%M:%S") .. " " .. table.concat(t, " ")
  XT.log[#XT.log + 1] = line
  if devLog then devLog("XT " .. table.concat(t, " ")) end
end
XT.L = L

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
local function err(e) if not e then return nil end return s(e.localizedDescription) .. " (code " .. s(e.code) .. ")" end

local function myId() return objc.GKLocalPlayer.localPlayer.gamePlayerID end
local function payload(t) return objc.string(json.encode(t)):dataUsingEncoding_(4) end

-- Keep the app's own turn handler from entering the test match.
function XT.muteApp()
  if not XT.savedOnReceivingTurn then XT.savedOnReceivingTurn = tbm._onReceivingTurn end
  tbm._onReceivingTurn = function(m, d) L("app turn event (muted)", m and s(m.matchID)) end
  return "muted"
end
function XT.unmuteApp()
  if XT.savedOnReceivingTurn then tbm._onReceivingTurn = XT.savedOnReceivingTurn; XT.savedOnReceivingTurn = nil end
  return "unmuted"
end

function XT.describe(m)
  m = m or XT.m
  if not m then return "no match" end
  local out = { "match " .. s(m.matchID) .. " status=" .. s(m.status) }
  local cp = m.currentParticipant
  out[#out + 1] = "current=" .. (cp and cp.player and s(cp.player.alias) or "nil")
  local ps = m.participants
  for i = 1, cnt(ps) do
    local p = get(ps, i)
    out[#out + 1] = string.format("  p%d %s status=%s outcome=%s timeout=%s", i,
      p.player and s(p.player.alias) or "(open slot)", s(p.status), s(p.matchOutcome), s(p.timeoutDate))
  end
  out[#out + 1] = "exchanges=" .. cnt(m.exchanges) .. " active=" .. cnt(m.activeExchanges) .. " completed=" .. cnt(m.completedExchanges)
  local ex = m.exchanges
  for i = 1, cnt(ex) do
    local e = get(ex, i)
    out[#out + 1] = string.format("  ex%d id=%s status=%s sender=%s replies=%s timeout=%s", i, s(e.exchangeID), s(e.status),
      e.sender and e.sender.player and s(e.sender.player.alias) or "?", cnt(e.replies), s(e.timeoutDate))
  end
  local d = m.matchData
  out[#out + 1] = "matchData len=" .. (d and s(d.length) or "nil")
  return table.concat(out, "\n")
end

function XT.findB(alias)
  XT.B = nil
  objc.GKLocalPlayer.localPlayer:loadFriendPlayersWithCompletionHandler_(function(o__players, o__err)
    objc.async(function()
      if o__err then L("friends error", err(o__err)) return end
      for i = 1, cnt(o__players) do
        local p = get(o__players, i)
        if p and s(p.alias) == alias then XT.B = p end
      end
      L("findB", XT.B and ("found " .. s(XT.B.alias)) or ("not found among " .. cnt(o__players)))
    end)
  end)
  return "loading friends"
end

function XT.create()
  local req = objc.GKMatchRequest()
  req.minPlayers = 2
  req.maxPlayers = 2
  req.recipients = { XT.B }
  objc.GKTurnBasedMatch:findMatchForRequest_withCompletionHandler_(req, function(o__match, o__err)
    objc.async(function()
      if o__err or not o__match then L("create error", err(o__err)) return end
      XT.m = o__match
      XT.matchID = s(o__match.matchID)
      L("created", XT.matchID)
    end)
  end)
  return "creating"
end

function XT.others(m)
  m = m or XT.m
  local me, list = myId(), {}
  for i = 1, cnt(m.participants) do
    local p = get(m.participants, i)
    if not (p.player and s(p.player.gamePlayerID) == s(me)) then list[#list + 1] = p end
  end
  return list
end

function XT.passTurn(timeout, tbl)
  XT.m:endTurnWithNextParticipants_turnTimeout_matchData_completionHandler_(
    XT.others(), timeout, payload(tbl or { xt = "turn", at = os.time() }), function(o__err)
      objc.async(function() L("passTurn timeout=" .. s(timeout), o__err and err(o__err) or "ok") end)
    end)
  return "passing"
end

function XT.reload()
  objc.GKTurnBasedMatch:loadMatchWithID_withCompletionHandler_(XT.matchID, function(o__match, o__err)
    objc.async(function()
      if o__err then L("reload error", err(o__err)) return end
      XT.m = o__match
      L("reloaded\n" .. XT.describe(o__match))
    end)
  end)
  return "reloading"
end

function XT.sendEx(timeout, recips)
  XT.m:sendExchangeToParticipants_data_localizableMessageKey_arguments_timeout_completionHandler_(
    recips or XT.others(), payload({ xt = "comment", text = "hello from exchange", at = os.time() }),
    "XT_EXCHANGE", {}, timeout or 60, function(o__exchange, o__err)
      objc.async(function()
        XT.ex = o__exchange
        L("sendEx", o__err and err(o__err) or ("ok id=" .. s(o__exchange and o__exchange.exchangeID)))
      end)
    end)
  return "sending exchange"
end

function XT.merge(tbl)
  local done = XT.m.completedExchanges
  XT.m:saveMergedMatchData_withResolvedExchanges_completionHandler_(
    payload(tbl or { xt = "merged", at = os.time() }), done or {}, function(o__err)
      objc.async(function() L("merge (" .. cnt(done) .. " exchanges)", o__err and err(o__err) or "ok") end)
    end)
  return "merging"
end

function XT.saveTurn(tbl)
  XT.m:saveCurrentTurnWithMatchData_completionHandler_(payload(tbl or { xt = "saved", at = os.time() }), function(o__err)
    objc.async(function() L("saveCurrentTurn", o__err and err(o__err) or "ok") end)
  end)
  return "saving"
end

-- outcomes: GKTurnBasedMatchOutcome 2=won 3=lost 4=tied
function XT.endMatch(myOutcome, otherOutcome)
  local me = myId()
  for i = 1, cnt(XT.m.participants) do
    local p = get(XT.m.participants, i)
    if p.player and s(p.player.gamePlayerID) == s(me) then p.matchOutcome = myOutcome or 2
    else p.matchOutcome = otherOutcome or 3 end
  end
  XT.m:endMatchInTurnWithMatchData_completionHandler_(payload({ xt = "ended", at = os.time() }), function(o__err)
    objc.async(function() L("endMatch", o__err and err(o__err) or "ok") end)
  end)
  return "ending"
end

function XT.dump(n)
  n = n or 20
  local from = math.max(1, #XT.log - n + 1)
  return table.concat(XT.log, "\n", from, #XT.log)
end

return "XT loaded"
