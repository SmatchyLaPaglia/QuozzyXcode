-- BoardSolver.lua
-- Finds all valid words reachable by Boggle paths on a given board.
-- Depends on globals: DICT, PREFIXES, MIN_WORD_LEN, scoreForWordLength,
--                     inferBoardSizeFromTiles

local function buildBoardMatrixFromTiles(tiles, n)
    local b = {}
    local idx = 1
    for r = 1, n do
        b[r] = {}
        for c = 1, n do
            b[r][c] = string.upper(tiles[idx] or "?")
            idx = idx + 1
        end
    end
    return b
end

-- Finds a valid Boggle path for a specific target word on the board.
-- Matches tile strings character-by-character (handles multi-char tiles like "QU").
-- Returns a path array {{r,c},...} or nil if not found.
-- No DICT or length validation — if the word is on a list, find its path.
local function findPathForWord(b, n, targetWord)
    local tlen = #targetWord

    local function dfsWord(r, c, pos, visited, path)
        local tile = b[r][c]
        local tileLen = #tile
        if targetWord:sub(pos, pos + tileLen - 1) ~= tile then return nil end
        local nextPos = pos + tileLen
        local depth = #path + 1
        path[depth] = {r = r, c = c}
        if nextPos > tlen then
            local result = {}
            for i = 1, depth do result[i] = {r = path[i].r, c = path[i].c} end
            path[depth] = nil
            return result
        end
        visited[r][c] = true
        for r2 = math.max(1, r - 1), math.min(n, r + 1) do
            for c2 = math.max(1, c - 1), math.min(n, c + 1) do
                if not (r2 == r and c2 == c) and not visited[r2][c2] then
                    local result = dfsWord(r2, c2, nextPos, visited, path)
                    if result then
                        visited[r][c] = false
                        path[depth] = nil
                        return result
                    end
                end
            end
        end
        visited[r][c] = false
        path[depth] = nil
        return nil
    end

    local visited = {}
    for r = 1, n do visited[r] = {} end
    for r = 1, n do
        for c = 1, n do
            local result = dfsWord(r, c, 1, visited, {})
            if result then return result end
        end
    end
    return nil
end

-- Ensures q.wordPaths contains paths for every word currently shown in player lists.
-- This supports end-screen word tapping without having to solve the full board.
function ensureWordPathsForPlayers(q)
    if not q or not q.boardTiles then return {} end

    local n = q.boardSize or inferBoardSizeFromTiles(q.boardTiles) or 4
    local b = buildBoardMatrixFromTiles(q.boardTiles, n)

    local wordPaths = q.wordPaths or {}

    if q.players then
        for _, p in pairs(q.players) do
            for _, entry in ipairs((p and p.words) or {}) do
                local w = type(entry) == "table" and entry.word or tostring(entry or "")
                if w ~= "" then
                    local wu = string.upper(w)
                    if not wordPaths[wu] then
                        wordPaths[wu] = findPathForWord(b, n, wu)
                    end
                    if type(entry) == "table" and entry.path == nil then
                        entry.path = wordPaths[wu]
                    end
                end
            end
        end
    end

    q.wordPaths = wordPaths
    return wordPaths
end

local function shallowCopyWordEntry(entry)
    if type(entry) == "table" then
        local copy = {}
        for k, v in pairs(entry) do copy[k] = v end
        copy.word = copy.word or ""
        return copy
    end
    return { word = tostring(entry or "") }
end

local function normalizedWordValue(entry)
    local w = type(entry) == "table" and entry.word or tostring(entry or "")
    return string.upper(w or "")
end

local function endWordEntrySort(a, b)
    local aShared = not not (a and a.shared)
    local bShared = not not (b and b.shared)
    if aShared ~= bShared then return aShared end
    local aw = string.upper((a and a.word) or "")
    local bw = string.upper((b and b.word) or "")
    if #aw ~= #bw then return #aw > #bw end
    return aw < bw
end

function buildSortedEndWordEntries(entries)
    local out = {}
    for i = 1, #(entries or {}) do
        local copy = shallowCopyWordEntry(entries[i])
        local w = normalizedWordValue(copy)
        copy.word = w
        copy.points = scoreForWordLength(#w)
        out[#out + 1] = copy
    end
    table.sort(out, endWordEntrySort)
    return out
end

function reconcileCompetitiveWordResults(wordsA, wordsB)
    local shared = {}
    local seenB = {}
    for i = 1, #(wordsB or {}) do
        local w = normalizedWordValue(wordsB[i])
        if w ~= "" then seenB[w] = true end
    end
    for i = 1, #(wordsA or {}) do
        local w = normalizedWordValue(wordsA[i])
        if w ~= "" and seenB[w] then
            shared[w] = true
        end
    end

    local function decorate(entries)
        local out = {}
        local total = 0
        for i = 1, #(entries or {}) do
            local copy = shallowCopyWordEntry(entries[i])
            local w = normalizedWordValue(copy)
            copy.word = w
            copy.shared = (w ~= "" and shared[w]) or false
            copy.points = copy.shared and 0 or scoreForWordLength(#w)
            if not copy.shared then
                total = total + copy.points
            end
            out[#out + 1] = copy
        end
        table.sort(out, endWordEntrySort)
        return out, total
    end

    local entriesA, scoreA = decorate(wordsA)
    local entriesB, scoreB = decorate(wordsB)
    return {
        shared = shared,
        entriesA = entriesA,
        entriesB = entriesB,
        scoreA = scoreA,
        scoreB = scoreB,
    }
end

