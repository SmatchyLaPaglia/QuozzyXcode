opponentRecords = {}

function loadOpponentRecords()
  local jsonStr = readLocalData("OpponentRecords")
  if jsonStr then
    local ok, decoded = pcall(json.decode, jsonStr)
    if ok and type(decoded) == "table" then
      opponentRecords = decoded
    end
  end
end

loadOpponentRecords()

function saveOpponentRecords()
  local jsonStr = json.encode(opponentRecords)
  saveLocalData("OpponentRecords", jsonStr)
end

function setTurnBasedEnabled(on)
  useTurnBased = on and true or false
  
  if useTurnBased and not currentOpponentID then
    -- default fake opponent when testing without real GC
    currentOpponentID = "LOCAL_COMPUTER"
    opponentAlias     = "Computer"
    
    local rec = opponentRecords[currentOpponentID]
    if not rec then
      opponentRecords[currentOpponentID] = {
        wins   = 0,
        losses = 0,
        ties   = 0,
        alias  = opponentAlias
      }
      saveOpponentRecords()
    end
  end
end

-- ensure the default fake opponent has an entry
if currentOpponentID and not opponentRecords[currentOpponentID] then
  opponentRecords[currentOpponentID] = {
    wins   = 0,
    losses = 0,
    ties   = 0,
    alias  = opponentAlias
  }
  saveOpponentRecords()
end

function updateOpponentRecord(result)
  if not useTurnBased or not currentOpponentID then
    return
  end
  
  local rec = opponentRecords[currentOpponentID]
  if not rec then
    rec = { wins = 0, losses = 0, ties = 0, alias = opponentAlias }
  end
  rec.alias   = rec.alias or opponentAlias
  rec.wins    = rec.wins   or 0
  rec.losses  = rec.losses or 0
  rec.ties    = rec.ties   or 0
  
  if result == "win" then
    rec.wins = rec.wins + 1
  elseif result == "loss" then
    rec.losses = rec.losses + 1
  else
    rec.ties = rec.ties + 1
  end
  rec.updatedAt = os.time()
  
  opponentRecords[currentOpponentID] = rec
  saveOpponentRecords()
end

local function _int0(v)
  v = math.floor(tonumber(v) or 0)
  if v < 0 then v = 0 end
  return v
end

function normalizedOpponentRecord(oppId, alias)
  if not oppId then return nil end
  local rec = opponentRecords[oppId] or {}
  rec.wins = _int0(rec.wins)
  rec.losses = _int0(rec.losses)
  rec.ties = _int0(rec.ties)
  if alias and alias ~= "" then
    rec.alias = alias
  else
    rec.alias = rec.alias or opponentAlias or "Opponent"
  end
  rec.updatedAt = _int0(rec.updatedAt)
  opponentRecords[oppId] = rec
  return rec
end

local function projectedRecordFromResult(rec, result)
  local out = {
    wins = _int0(rec and rec.wins),
    losses = _int0(rec and rec.losses),
    ties = _int0(rec and rec.ties),
  }
  if result == "win" then
    out.wins = out.wins + 1
  elseif result == "loss" then
    out.losses = out.losses + 1
  elseif result == "tie" then
    out.ties = out.ties + 1
  end
  return out
end

function buildRecordSyncForOpponent(oppId, alias, senderId, result)
  local rec = normalizedOpponentRecord(oppId, alias)
  if not rec then return nil end
  local projected = projectedRecordFromResult(rec, result)
  local stamp = os.time()
  return {
    senderId = senderId,
    opponentId = oppId,
    alias = rec.alias,
    wins = projected.wins,
    losses = projected.losses,
    ties = projected.ties,
    updatedAt = stamp,
    final = (result == "win" or result == "loss" or result == "tie") and true or false,
  }
end

function mergeOpponentRecordFromTurnData(gkMatch, dataTable)
  if type(dataTable) ~= "table" then return false end
  local rs = dataTable.recordSync
  if type(rs) ~= "table" then return false end
  
  local localId = localPID()
  local senderId = rs.senderId
  if (not senderId or senderId == "") and firstNonLocalParticipant and gkMatch then
    local pl = firstNonLocalParticipant(gkMatch)
    senderId = pl and (pl.gamePlayerID or pl.playerID) or nil
  end
  if not senderId or senderId == localId then return false end
  
  local rec = normalizedOpponentRecord(senderId, rs.alias)
  if not rec then return false end
  
  -- Payload is sender-perspective; invert for local perspective.
  local remoteWins = _int0(rs.losses)
  local remoteLosses = _int0(rs.wins)
  local remoteTies = _int0(rs.ties)
  local remoteUpdatedAt = _int0(rs.updatedAt)
  
  local localTotal = _int0(rec.wins) + _int0(rec.losses)
  local remoteTotal = remoteWins + remoteLosses
  local localUpdatedAt = _int0(rec.updatedAt)
  
  local shouldAdopt = false
  if remoteTotal > localTotal then
    shouldAdopt = true
  elseif remoteTotal == localTotal and remoteUpdatedAt > localUpdatedAt then
    if remoteWins ~= rec.wins or remoteLosses ~= rec.losses or remoteTies ~= rec.ties then
      shouldAdopt = true
    end
  end
  
  if not shouldAdopt then return false end
  
  rec.wins = remoteWins
  rec.losses = remoteLosses
  rec.ties = remoteTies
  rec.updatedAt = remoteUpdatedAt
  if rs.alias and rs.alias ~= "" then
    rec.alias = rs.alias
  end
  opponentRecords[senderId] = rec
  saveOpponentRecords()
  devLog("Record sync adopted", "opponent=", senderId, "wins=", rec.wins, "losses=", rec.losses, "ties=", rec.ties, "final=", tostring(rs.final))
  return true
end

--####################################################################
-- PER-MATCH HISTORY (populates matchHistoryByOpponent, used by the
-- records UI's opponent -> matches drill-down)
--####################################################################
-- opponentRecords (above) only keeps aggregate W/L totals. This adds a
-- separate store of individual completed/in-progress match snapshots, keyed
-- by opponent id, newest first. Nothing here existed before 2026-08-09 —
-- matchHistoryByOpponent was a dangling reference (RecordsUI.lua) until now,
-- so history is FORWARD-ONLY (matches finished before this shipped were never
-- captured and cannot appear). Snapshots are captured wherever a full match
-- record lands on the device and the local player has played it: primarily
-- buildEndScreenModel (EndScreenFP.lua), which fires whenever the end screen
-- shows a match — covering a fresh finish, an opponent-finished match opened
-- from Game Center, AND an initiator examining their own in-progress game
-- before the opponent has moved (recorded incomplete, then upserted to
-- complete when the finished version is later viewed).

matchHistoryByOpponent = matchHistoryByOpponent or {}
MATCH_HISTORY_KEY = "MatchHistoryV1"
MATCH_HISTORY_CAP_PER_OPP = 50

function loadMatchHistory()
  local raw = readLocalData(MATCH_HISTORY_KEY)
  if raw and raw ~= "" then
    local ok, decoded = pcall(json.decode, raw)
    if ok and type(decoded) == "table" then
      matchHistoryByOpponent = decoded
    end
  end
end

loadMatchHistory()

function saveMatchHistory()
  local ok, s = pcall(json.encode, matchHistoryByOpponent)
  if ok and s then saveLocalData(MATCH_HISTORY_KEY, s) end
end

-- Content signature for change-detection: recordMatchSnapshot runs every frame
-- the end screen is up (via buildEndScreenModel), so we must NOT hit disk unless
-- something actually changed, or we'd re-encode+write the whole history table 60x
-- a second.
local function _matchSnapSig(m)
  return string.format("%s|%s|%s|%s|%s|%s|%s|%s|%s",
    tostring(m.complete), tostring(m.outcome),
    tostring(m.localScore or 0), tostring(m.oppScore or 0),
    tostring(#(m.localWords or {})), tostring(#(m.oppWords or {})),
    tostring(m.localComment or ""), tostring(m.oppComment or ""),
    tostring(m.endedAt or 0))
end

-- Upsert by match id. Replaces an existing entry only when the incoming snapshot
-- is "at least as complete and at least as recent" (a completed version wins over
-- an earlier in-progress one; a same-completeness newer one wins), and only writes
-- to disk when the stored content actually differs. Returns true if it persisted.
function recordMatchSnapshot(m)
  if not m or not m.id or not m.oppId then return false end

  local list = matchHistoryByOpponent[m.oppId]
  if not list then list = {}; matchHistoryByOpponent[m.oppId] = list end

  local idx = nil
  for i, e in ipairs(list) do
    if e.id == m.id then idx = i break end
  end

  if idx then
    local existing = list[idx]
    local newerOrCompleter =
      (m.complete and not existing.complete) or
      (m.complete == existing.complete and (m.endedAt or 0) >= (existing.endedAt or 0))
    if not newerOrCompleter then return false end
    if _matchSnapSig(existing) == _matchSnapSig(m) then return false end
    list[idx] = m
  else
    table.insert(list, 1, m)
  end

  table.sort(list, function(a, b) return (a.endedAt or 0) > (b.endedAt or 0) end)
  while #list > MATCH_HISTORY_CAP_PER_OPP do table.remove(list) end

  saveMatchHistory()
  return true
end

function matchesForOpponent(oppId)
  if not oppId then return {} end
  local list = matchHistoryByOpponent[oppId]
  return (type(list) == "table") and list or {}
end
