-- Minimal JSON encode/decode, just enough to round-trip the plain
-- string/number/boolean/table structures this project persists
-- (pendingTurnSendsByMatchId, opponentRecords, etc). Not a general-purpose
-- parser — stands in for Codea's built-in `json` global in tests only.

local json = {}

local function encodeValue(v, out)
  local t = type(v)
  if t == "nil" then
    out[#out+1] = "null"
  elseif t == "boolean" then
    out[#out+1] = v and "true" or "false"
  elseif t == "number" then
    out[#out+1] = tostring(v)
  elseif t == "string" then
    out[#out+1] = string.format("%q", v)
  elseif t == "table" then
    -- Decide array vs object: array if keys are a dense 1..n integer run.
    local n = 0
    local isArray = true
    for k, _ in pairs(v) do
      if type(k) ~= "number" then isArray = false end
      n = n + 1
    end
    if isArray then
      for i = 1, n do
        if v[i] == nil then isArray = false break end
      end
    end
    if isArray and n > 0 then
      out[#out+1] = "["
      for i = 1, n do
        if i > 1 then out[#out+1] = "," end
        encodeValue(v[i], out)
      end
      out[#out+1] = "]"
    else
      out[#out+1] = "{"
      local first = true
      for k, val in pairs(v) do
        if not first then out[#out+1] = "," end
        first = false
        out[#out+1] = string.format("%q", tostring(k))
        out[#out+1] = ":"
        encodeValue(val, out)
      end
      out[#out+1] = "}"
    end
  else
    error("json_mini: cannot encode type " .. t)
  end
end

function json.encode(v)
  local out = {}
  encodeValue(v, out)
  return table.concat(out)
end

-- Tiny recursive-descent decoder.
local function skipWs(s, i)
  while i <= #s and s:sub(i,i):match("%s") do i = i + 1 end
  return i
end

local parseValue

local function parseString(s, i)
  i = i + 1 -- skip opening quote
  local buf = {}
  while true do
    local c = s:sub(i,i)
    if c == '"' then return table.concat(buf), i + 1 end
    if c == "\\" then
      local nx = s:sub(i+1,i+1)
      local map = { n="\n", t="\t", r="\r", ['"']='"', ["\\"]="\\", ["/"]="/" }
      buf[#buf+1] = map[nx] or nx
      i = i + 2
    else
      buf[#buf+1] = c
      i = i + 1
    end
  end
end

local function parseNumber(s, i)
  local j = i
  while j <= #s and s:sub(j,j):match("[%d%.%-%+eE]") do j = j + 1 end
  return tonumber(s:sub(i, j-1)), j
end

parseValue = function(s, i)
  i = skipWs(s, i)
  local c = s:sub(i,i)
  if c == '"' then
    return parseString(s, i)
  elseif c == "{" then
    local obj = {}
    i = skipWs(s, i+1)
    if s:sub(i,i) == "}" then return obj, i+1 end
    while true do
      i = skipWs(s, i)
      local key
      key, i = parseString(s, i)
      i = skipWs(s, i)
      assert(s:sub(i,i) == ":", "json_mini: expected ':'")
      i = skipWs(s, i+1)
      local val
      val, i = parseValue(s, i)
      obj[key] = val
      i = skipWs(s, i)
      local d = s:sub(i,i)
      if d == "," then i = i + 1
      elseif d == "}" then return obj, i + 1
      else error("json_mini: expected ',' or '}'") end
    end
  elseif c == "[" then
    local arr = {}
    i = skipWs(s, i+1)
    if s:sub(i,i) == "]" then return arr, i+1 end
    while true do
      local val
      val, i = parseValue(s, i)
      arr[#arr+1] = val
      i = skipWs(s, i)
      local d = s:sub(i,i)
      if d == "," then i = i + 1
      elseif d == "]" then return arr, i + 1
      else error("json_mini: expected ',' or ']'") end
    end
  elseif s:sub(i,i+3) == "true" then
    return true, i+4
  elseif s:sub(i,i+4) == "false" then
    return false, i+5
  elseif s:sub(i,i+3) == "null" then
    return nil, i+4
  else
    return parseNumber(s, i)
  end
end

function json.decode(s)
  if not s or s == "" then return nil end
  local v = parseValue(s, 1)
  return v
end

return json
