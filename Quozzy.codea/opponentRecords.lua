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
