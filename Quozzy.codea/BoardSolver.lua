-- BoardSolver.lua
-- Finds all valid words reachable by Boggle paths on a given board.
-- Depends on globals: DICT, PREFIXES, MIN_WORD_LEN, scoreForWordLength,
--                     inferBoardSizeFromTiles

-- Returns array of {word=STRING, points=INT} sorted alphabetically.
-- tiles: flat array of tile strings (length n*n)
-- n:     board dimension (4 or 5)
function solveBoardAllWords(tiles, n)
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

    local found = {}
    local visited = {}
    for r = 1, n do visited[r] = {} end

    local nodeCount = 0
    local NODE_LIMIT = 2000000

    local function dfs(r, c, wordSoFar)
        if nodeCount > NODE_LIMIT then return end
        nodeCount = nodeCount + 1

        local newWord = wordSoFar .. b[r][c]

        -- Prune: if not a prefix of any dict word AND not a word itself, dead end
        if not PREFIXES[newWord] and not DICT[newWord] then return end

        -- Record valid complete word
        if #newWord >= MIN_WORD_LEN and DICT[newWord] then
            found[newWord] = true
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
    end

    for r = 1, n do
        for c = 1, n do
            dfs(r, c, "")
        end
    end

    local result = {}
    for word, _ in pairs(found) do
        result[#result + 1] = { word = word, points = scoreForWordLength(#word) }
    end
    table.sort(result, function(a, b) return a.word < b.word end)
    return result
end

-- Returns words on the board that no player found.
-- q: a qMatch object with boardTiles, boardSize, and players
function solveBoardMissedWords(q)
    if not q or not q.boardTiles then return {} end
    local n = q.boardSize or inferBoardSizeFromTiles(q.boardTiles) or 4

    local allWords = solveBoardAllWords(q.boardTiles, n)

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
