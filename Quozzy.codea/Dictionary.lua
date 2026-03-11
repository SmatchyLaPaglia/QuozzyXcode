function buildDictionaryFromString(str, label)
    DICT = {}
    PREFIXES = {}
    for line in str:gmatch("[^\r\n]+") do
        local word = line:match("^%s*(%S+)%s*$")
        if word then
            word = string.upper(word)
            -- Keep the full dictionary loaded once; runtime validation applies
            -- the current minimum word length without forcing rebuilds.
            if word:match("^[A-Z]+$") then
                DICT[word] = true
            end
        end
    end
    for word, _ in pairs(DICT) do
        for len = 1, #word - 1 do
            PREFIXES[string.sub(word, 1, len)] = true
        end
    end
    dictStatus = label
end

function tryLoadCachedSowpods()
    local ok, data = pcall(readText, SOWPODS_LOCAL_NAME)
    if ok and data and #data > 0 then
        buildDictionaryFromString(data, "SOWPODS")
        return true
    end
    return false
end

function startSowpodsDownload()
    http.request(
    SOWPODS_URL,
    function(data, status, headers)
        if status == 200 and data and #data > 0 then
            saveText(SOWPODS_LOCAL_NAME, data)
            buildDictionaryFromString(data, "SOWPODS (downloaded)")
        end
    end,
    function(err)
        -- silently ignore; fallback remains active
    end
    )
end

function initDictionary()
    if not tryLoadCachedSowpods() then
        -- use fallback immediately
        buildDictionaryFromString(FALLBACK_WORDS, "Fallback")
        -- start async download of SOWPODS
        startSowpodsDownload()
    end
end

function rebuildDictionaryForCurrentMinWordLen()
    return
end
