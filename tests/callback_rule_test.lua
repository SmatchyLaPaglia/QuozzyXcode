-- Static check for the CLAUDE.md hard rule: an Objective-C callback may only
-- hand data over (deferToDraw / plain assignment / return); the real work runs
-- in draw(). Doing work inside a callback froze the app (render thread wedged
-- when a block was delivered mid-bridge-call, 2026-10-10).
--
-- Callbacks are found by the hard rule's own convention: objc callback params
-- must be type-prefixed (o__x, oErr, bOk, sName, iCount, fValue). Run:
--   lua tests/callback_rule_test.lua   (exit 1 + file:line list on violations)

local ROOT = arg[0]:match("(.*)/tests/callback_rule_test%.lua$") or "."
local SRC = ROOT .. "/Quozzy.codea/"

local function listLua()
  local p = io.popen('ls "' .. SRC .. '"*.lua')
  local out = {}
  for f in p:lines() do out[#out + 1] = f end
  p:close()
  return out
end

-- Strip comments and string contents (keep newlines so line numbers survive).
local function strip(src)
  -- outer capture so the callback gets the whole match (with only the inner
  -- (=*) capture, gsub passes just that and the replaced text loses its newlines)
  src = src:gsub("(%-%-%[(=*)%[.-%]%2%])", function(s) return (s:gsub("[^\n]", " ")) end)
  src = src:gsub("%-%-[^\n]*", "")
  src = src:gsub("(%[(=*)%[.-%]%2%])", function(s) return (s:gsub("[^\n]", " ")) end)
  src = src:gsub('"[^"\n]*"', '""'):gsub("'[^'\n]*'", "''")
  return src
end

local PREFIXED = "^%s*(o__%w+)" -- first param forms below
local function isCallbackParams(params)
  for p in params:gmatch("[%w_]+") do
    if p:match("^o__") or p:match("^[obsif]%u") then return true end
  end
  return false
end

-- Find the matching `end` for a `function` starting at pos (after its params).
local OPEN = { ["function"] = true, ["if"] = true, ["do"] = true, ["repeat"] = true }
local function bodyRange(src, startPos)
  local depth, pos = 1, startPos
  while true do
    local s, e, word = src:find("([%a_][%w_]*)", pos)
    if not s then return nil end
    local prev = s > 1 and src:sub(s - 1, s - 1) or " "
    if not prev:match("[%w_%.:]") then
      if word == "function" or word == "if" or word == "repeat" then depth = depth + 1
      elseif word == "do" then
        -- `while ... do` / `for ... do` open one block, counted here at `do`
        depth = depth + 1
      elseif word == "end" or word == "until" then
        depth = depth - 1
        if depth == 0 then return startPos, s - 1 end
      end
    end
    pos = e + 1
  end
end

-- A statement is "handover only" if it is a deferToDraw(...) call, a plain
-- assignment whose right side makes no calls, or a bare return/end.
local function bodyIsHandoverOnly(body)
  local b = body:gsub("handOff%s*%b()", ""):gsub("deferToDraw%s*%b()", ""):gsub("%s+", " ")
  -- any remaining call is work: name( or :method( or nested function
  if b:find("[%w_%]%)]%s*%(") then return false end
  if b:find("function") then return false end
  if b:find("[%w_%]%)]%s*:%s*[%w_]+") then return false end
  return true
end

local violations = {}
for _, path in ipairs(listLua()) do
  local f = io.open(path); local raw = f:read("a"); f:close()
  local src = strip(raw)
  local fname = path:match("([^/]+)$")
  local delegateObjects = {}
  for obj in src:gmatch("local%s+([%w_]+)%s*=%s*objc%.delegate%s*%(") do delegateObjects[obj] = true end
  for obj in src:gmatch("local%s+([%w_]+)%s*=%s*objc%.class%s*%(") do delegateObjects[obj] = true end
  local pos = 1
  while true do
    -- anonymous `function(...)` AND named methods on objc delegate objects,
    -- `function Listener:method_(...)` -- possibly split across lines.
    local s, e, name, params = src:find("function([%w_%.:%s]-)%(([^%)]*)%)", pos)
    if not s then break end
    local prev = s > 1 and src:sub(s - 1, s - 1) or " "
    local owner = name:match("^%s*([%w_]+)%s*[:%.]")
    local namedNonDelegate = owner and not delegateObjects[owner]
    local namedPlain = name:match("%S") and not owner
    local before = src:sub(math.max(1, s - 40), s - 1)
    local handedOff = before:find("handOff%s*%(%s*$") or before:find("deferToDraw%s*%(%s*$")
    local isDelegateMethod = owner and delegateObjects[owner]
    if not prev:match("[%w_]") and not namedNonDelegate and not namedPlain
       and (isDelegateMethod or isCallbackParams(params)) and not handedOff then
      local bs, be = bodyRange(src, e + 1)
      if bs and not bodyIsHandoverOnly(src:sub(bs, be)) then
        local line = select(2, src:sub(1, s):gsub("\n", "")) + 1
        violations[#violations + 1] = fname .. ":" .. line
      end
    end
    pos = e + 1
  end
  -- objc.async anywhere except the Main.lua safety-net wrapper definition
  for line_no, line in (function() local i = 0; local it = src:gmatch("([^\n]*)\n?")
      return function() local l = it(); if l == nil then return nil end; i = i + 1; return i, l end end)() do
    if line:find("objc%.async%s*%(") and not line:find("nativeAsync") then
      violations[#violations + 1] = fname .. ":" .. line_no .. " (objc.async)"
    end
  end
end

if #violations == 0 then
  print("callback rule: OK")
else
  print("callback rule: " .. #violations .. " violation(s)")
  for _, v in ipairs(violations) do print("  " .. v) end
  os.exit(1)
end
