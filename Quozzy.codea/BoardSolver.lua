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

function createIncrementalBoardWordSolver(tiles, n, minLen)
    if not DICT or not PREFIXES then return nil end
    if not tiles or #tiles ~= n * n then return nil end

    local b = buildBoardMatrixFromTiles(tiles, n)
    local neighborsByIndex = {}
    for r = 1, n do
        for c = 1, n do
            local idx = (r - 1) * n + c
            local neighbors = {}
            for r2 = math.max(1, r - 1), math.min(n, r + 1) do
                for c2 = math.max(1, c - 1), math.min(n, c + 1) do
                    if not (r2 == r and c2 == c) then
                        neighbors[#neighbors + 1] = { r = r2, c = c2 }
                    end
                end
            end
            neighborsByIndex[idx] = neighbors
        end
    end

    local solver = {
        n = n,
        b = b,
        minLen = minLen or MIN_WORD_LEN,
        found = {},
        wordPaths = {},
        visited = {},
        stack = {},
        rootIndex = 1,
        done = false,
    }
    for r = 1, n do solver.visited[r] = {} end

    function solver:_recordCurrentWord(word)
        if not DICT[word] then return end
        if not self.wordPaths[word] then
            local p = {}
            for i = 1, #self.stack do
                local frame = self.stack[i]
                p[i] = { r = frame.r, c = frame.c }
            end
            self.wordPaths[word] = p
        end
        if #word >= self.minLen then
            self.found[word] = true
        end
    end

    function solver:_tryPush(r, c, wordSoFar)
        local newWord = wordSoFar .. self.b[r][c]
        if not PREFIXES[newWord] and not DICT[newWord] then return false end
        self.visited[r][c] = true
        self.stack[#self.stack + 1] = {
            r = r,
            c = c,
            idx = (r - 1) * self.n + c,
            word = newWord,
            nextNeighbor = 1,
        }
        self:_recordCurrentWord(newWord)
        return true
    end

    function solver:_pop()
        local frame = self.stack[#self.stack]
        if not frame then return end
        self.visited[frame.r][frame.c] = false
        self.stack[#self.stack] = nil
    end

    function solver:step(maxNodes)
        if self.done then return true end
        local budget = math.max(1, math.floor(maxNodes or 1))
        local processed = 0

        while processed < budget do
            if #self.stack == 0 then
                if self.rootIndex > self.n * self.n then
                    self.done = true
                    return true
                end
                local idx = self.rootIndex
                self.rootIndex = self.rootIndex + 1
                local r = math.floor((idx - 1) / self.n) + 1
                local c = ((idx - 1) % self.n) + 1
                self:_tryPush(r, c, "")
                processed = processed + 1
            else
                local frame = self.stack[#self.stack]
                local neighbors = neighborsByIndex[frame.idx]
                if frame.nextNeighbor > #neighbors then
                    self:_pop()
                else
                    local nb = neighbors[frame.nextNeighbor]
                    frame.nextNeighbor = frame.nextNeighbor + 1
                    if not self.visited[nb.r][nb.c] then
                        self:_tryPush(nb.r, nb.c, frame.word)
                    end
                    processed = processed + 1
                end
            end
        end

        return self.done
    end

    function solver:getResults()
        local result = {}
        for word, _ in pairs(self.found) do
            result[#result + 1] = {
                word = word,
                points = scoreForWordLength(#word),
                path = self.wordPaths[word],
            }
        end
        table.sort(result, function(a, b) return a.word < b.word end)
        return result, self.wordPaths
    end

    return solver
end

-- Returns array of {word=STRING, points=INT, path={{r,c},...}} sorted alphabetically.
-- tiles: flat array of tile strings (length n*n)
-- n:     board dimension (4 or 5)
-- minLen: minimum word length to record (defaults to global MIN_WORD_LEN)
function solveBoardAllWords(tiles, n, minLen)
    local solver = createIncrementalBoardWordSolver(tiles, n, minLen)
    if not solver then return {} end
    while not solver.done do
        solver:step(2000)
    end
    return solver:getResults()
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
    local b = buildBoardMatrixFromTiles(q.boardTiles, n)

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
