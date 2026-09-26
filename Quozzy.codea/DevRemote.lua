-- DevRemote: run Lua sent from the Mac, without touching the phone.
--
-- Host side: tools/dbg.sh '<lua code>'  (pushes Documents/dbg_cmd.txt, pulls dbg_out.txt)
-- App side:  devRemotePoll() runs from draw(); every 0.5s it reads Documents:dbg_cmd.txt.
--            First line must be "--id <n>"; a new id runs the chunk once. print() output,
--            return values and errors go to Documents:dbg_out.txt, prefixed with "--id <n>".
--
-- Helpers usable inside a command:
--   dbgDump(v [,depth])        pretty-print a value (tables recursively, default depth 2)
--   dbgTap(x, y)               fake a BEGAN+ENDED touch at (x, y) through touchedFrame()
--   dbgImage(img, name)        save img to Documents/dbg_<name>.png for pulling to the Mac
--
-- Set DEV_REMOTE_ENABLED = false to disable (e.g. for App Store builds).

DEV_REMOTE_ENABLED = true

local CMD_PATH = "Documents:dbg_cmd.txt"
local OUT_PATH = "Documents:dbg_out.txt"
local POLL_INTERVAL = 0.5

local _lastPollTime = 0
local _lastRunId = nil
local _primed = false
local _outLines = nil
local _dbgTouchId = 900000

local function _fmt(v, depth, indent, seen)
  depth = depth or 2
  indent = indent or ""
  seen = seen or {}
  if type(v) ~= "table" then
    if type(v) == "string" then return string.format("%q", v) end
    return tostring(v)
  end
  if seen[v] then return "<cycle " .. tostring(v) .. ">" end
  if depth <= 0 then return tostring(v) end
  seen[v] = true
  local keys = {}
  for k in pairs(v) do keys[#keys + 1] = k end
  table.sort(keys, function(a, b) return tostring(a) < tostring(b) end)
  local parts = {}
  for _, k in ipairs(keys) do
    parts[#parts + 1] = indent .. "  " .. tostring(k) .. " = " .. _fmt(v[k], depth - 1, indent .. "  ", seen)
  end
  seen[v] = nil
  if #parts == 0 then return "{}" end
  return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
end

function dbgDump(v, depth)
  print(_fmt(v, depth))
end

function dbgTap(x, y)
  _dbgTouchId = _dbgTouchId + 1
  local base = { id = _dbgTouchId, x = x, y = y, prevX = x, prevY = y,
    deltaX = 0, deltaY = 0, tapCount = 1, type = DIRECT, timestamp = ElapsedTime }
  local began, ended = {}, {}
  for k, v in pairs(base) do began[k] = v; ended[k] = v end
  began.state = BEGAN
  ended.state = ENDED
  touchedFrame(began)  -- already inside draw(), so skip the CODEA_RENDER_PASS wrapper
  touchedFrame(ended)
  return "tapped " .. x .. "," .. y
end

function dbgImage(img, name)
  if not img then return "dbgImage: nil image" end
  local okSize, w, h = pcall(function() return img.width, img.height end)
  if not okSize then return "dbgImage: not a Codea image (" .. tostring(img) .. ")" end
  local ok, err = pcall(function() saveImage("Documents:dbg_" .. name, img) end)
  if not ok then return "dbgImage failed: " .. tostring(err) end
  return "saved dbg_" .. name .. ".png (" .. tostring(w) .. "x" .. tostring(h) .. ")"
end

local function _runChunk(id, src)
  _outLines = {}
  local prevPrint = print
  print = function(...)
    local n = select("#", ...)
    local t = {}
    for i = 1, n do t[i] = tostring((select(i, ...))) end
    _outLines[#_outLines + 1] = table.concat(t, "\t")
  end

  local fn, compileErr = load(src, "=dbg_cmd", "t")
  if not fn then
    _outLines[#_outLines + 1] = "COMPILE ERROR: " .. tostring(compileErr)
  else
    local results = table.pack(xpcall(fn, debug.traceback))
    if results[1] then
      for i = 2, results.n do
        _outLines[#_outLines + 1] = "=> " .. _fmt(results[i])
      end
    else
      _outLines[#_outLines + 1] = "RUNTIME ERROR: " .. tostring(results[2])
    end
  end

  print = prevPrint
  saveText(OUT_PATH, "--id " .. id .. "\n" .. table.concat(_outLines, "\n") .. "\n")
  _outLines = nil
end

function devRemotePoll()
  if not DEV_REMOTE_ENABLED then return end
  if ElapsedTime - _lastPollTime < POLL_INTERVAL then return end
  _lastPollTime = ElapsedTime

  local ok, src = pcall(readText, CMD_PATH)
  if not ok then src = nil end
  local id = src and src:match("^%-%-id%s+(%S+)")
  if not _primed then
    -- First poll after launch: whatever command is sitting there already ran last session.
    _primed = true
    _lastRunId = id
    return
  end
  if not id or id == _lastRunId then return end
  _lastRunId = id
  _runChunk(id, src)
end
