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
  
  opponentRecords[currentOpponentID] = rec
  saveOpponentRecords()
end