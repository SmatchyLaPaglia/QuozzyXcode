-- BoardSolver.lua
-- Finds all valid words reachable by Boggle paths on a given board.
-- Depends on globals: DICT, PREFIXES, MIN_WORD_LEN, scoreForWordLength,
--                     inferBoardSizeFromTiles

-- Returns array of {word=STRING, points=INT, path={{r,c},...}} sorted alphabetically.
-- tiles: flat array of tile strings (length n*n)
-- n:     board dimension (4 or 5)
-- minLen: minimum word length to record (defaults to global MIN_WORD_LEN)
function solveBoardAllWords(tiles, n, minLen)
    if not DICT or not PREFIXES then return {} end
    if not tiles or #tiles ~= n * n then return {} end

    -- Build local 2D board from flat tiles
    local b = {}
    local idx = 1
    for r = 1, n do
        b[r] = {}
        for c = 1, n do
            b[r][c] = string.upper(tiles[idx] or "?")
            idx = idx + 1
        end
    end

    local found     = {}   -- word -> true
    local wordPaths = {}   -- word -> first path found (array of {r,c})
    local visited   = {}
    local path      = {}   -- current DFS path (grows/shrinks with recursion)
    for r = 1, n do visited[r] = {} end

    local effectiveMinLen = minLen or MIN_WORD_LEN

    local nodeCount = 0
    local NODE_LIMIT = 2000000

    local function dfs(r, c, wordSoFar)
        if nodeCount > NODE_LIMIT then return end
        nodeCount = nodeCount + 1

        local newWord = wordSoFar .. b[r][c]

        -- Prune: if not a prefix of any dict word AND not a word itself, dead end
        if not PREFIXES[newWord] and not DICT[newWord] then return end

        -- Push current tile onto path
        local pathLen = #path + 1
        path[pathLen] = {r = r, c = c}

        -- Store path for any DICT word (no length gate) so tapping any found
        -- word on the end screen can show its board path.
        if DICT[newWord] then
            if not wordPaths[newWord] then
                local p = {}
                for i = 1, pathLen do p[i] = {r = path[i].r, c = path[i].c} end
                wordPaths[newWord] = p
            end
            -- Only count toward missed-words if it meets the minimum length.
            if #newWord >= effectiveMinLen then
                found[newWord] = true
            end
        end

        -- Recurse to unvisited adjacent tiles (inlined for performance)
        visited[r][c] = true
        for r2 = math.max(1, r - 1), math.min(n, r + 1) do
            for c2 = math.max(1, c - 1), math.min(n, c + 1) do
                if not (r2 == r and c2 == c) and not visited[r2][c2] then
                    dfs(r2, c2, newWord)
                end
            end
        end
        visited[r][c] = false

        -- Pop current tile from path
        path[pathLen] = nil
    end

    for r = 1, n do
        for c = 1, n do
            dfs(r, c, "")
        end
    end

    local result = {}
    for word, _ in pairs(found) do
        result[#result + 1] = { word = word, points = scoreForWordLength(#word), path = wordPaths[word] }
    end
    table.sort(result, function(a, b) return a.word < b.word end)
    return result, wordPaths
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

-- Returns words on the board that no player found.
-- Also populates q.wordPaths (word -> path) for ALL board words so that
-- tapping any word on the end screen can show its board path.
-- q: a qMatch object with boardTiles, boardSize, and players
function solveBoardMissedWords(q)
    if not q or not q.boardTiles then return {} end
    local n = q.boardSize or inferBoardSizeFromTiles(q.boardTiles) or 4

    local matchMinLen = q.minWordLen or MIN_WORD_LEN
    local allWords, wordPaths = solveBoardAllWords(q.boardTiles, n, matchMinLen)

    -- Build local 2D board for targeted per-word path search
    local b = {}
    local idx = 1
    for r = 1, n do
        b[r] = {}
        for c = 1, n do
            b[r][c] = string.upper(q.boardTiles[idx] or "?")
            idx = idx + 1
        end
    end

    -- For every word on every player list, ensure a path exists.
    -- No DICT check, no length check — the word was validated during play.
    if q.players then
        for pid, p in pairs(q.players) do
            for _, entry in ipairs(p and p.words or {}) do
                local w = type(entry) == "table" and entry.word or tostring(entry)
                if w and w ~= "" then
                    local wu = string.upper(w)
                    if not wordPaths[wu] then
                        wordPaths[wu] = findPathForWord(b, n, wu)
                    end
                end
            end
        end
    end

    -- Cache word→path lookup on the match for tapping found words
    q.wordPaths = wordPaths

    -- Build set of all words found by any player
    local foundSet = {}
    if q.players then
        for pid, p in pairs(q.players) do
            for _, entry in ipairs(p and p.words or {}) do
                local w = type(entry) == "table" and entry.word or tostring(entry)
                if w then foundSet[string.upper(w)] = true end
            end
        end
    end

    local missed = {}
    for _, entry in ipairs(allWords) do
        if not foundSet[entry.word] then
            missed[#missed + 1] = entry
        end
    end
    return missed
end
