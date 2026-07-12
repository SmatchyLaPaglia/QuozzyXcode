# Xcode Codea — Platform Gotchas

Running under Codea 3.x runtime, Xcode-exported, iOS Simulator. Add new sections as platform-specific quirks are discovered.

## File I/O

Verified with both `devLog` output and raw filesystem inspection (`ls`, `xxd`, `plutil`).

## Path summary

| API | Survives termination? | Survives reinstall? |
|-----|----------------------|---------------------|
| `saveImage("Documents:...")` / `readImage("Documents:...")` | ✅ | ✅ |
| `saveText("Documents:...txt")` / `readText("Documents:...txt")` | ✅ | ✅ |
| `saveText(asset.documents .. "...txt")` / `readText(asset.documents .. "...txt")` | ✅ | ❌ (bundle) |
| `saveImage(asset.documents .. "...")` / `readImage(asset.documents .. "...")` | ✅ | ❌ (bundle) |
| `saveLocalData(key, val)` / `readLocalData(key)` | ✅ | ✅ (NSUserDefaults) |

**`Documents:` writes to the data container** (`Data/.../Documents/`). Survives reinstalls.
**`asset.documents` writes to the app bundle** (`Quozzy.app/Assets/`). Lost on reinstall.

Xcode's Run button does build → install → launch, which reinstalls every time. Use `xcrun simctl launch` to test persistence without reinstalling.

## Diagnostic test

Drop these functions into any `.lua` file in a Codea Xcode project and call them from `setup()`. Use `devLog()` (not `print()`) to see output in the Xcode console.

```lua
function launchNumber()
  local n = (readLocalData("PIN_lc") or 0) + 1
  saveLocalData("PIN_lc", n)
  return n
end

function textsFoundByDocuments()
  local a = readText("Documents:_pin_str.txt")
  return a and ("'" .. a .. "'") or "nil"
end

function textsFoundByAssetDocuments()
  local a = readText(asset.documents .. "_pin_key.txt")
  return a and ("'" .. a .. "'") or "nil"
end

function saveTextsBothWays()
  saveText("Documents:_pin_str.txt", "hello")
  saveText(asset.documents .. "_pin_key.txt", "hello")
  return "saved"
end

function testTextSaves()
  devLog("PIN", "launch " .. launchNumber())
  devLog("PIN", "texts found by 'Documents:': " .. textsFoundByDocuments())
  devLog("PIN", "texts found by asset.documents: " .. textsFoundByAssetDocuments())
  devLog("PIN", saveTextsBothWays())
end

function imagesFoundByDocuments()
  local a = nil; pcall(function() a = readImage("Documents:_pin_str_img") end)
  return a and ("image " .. a.width .. "x" .. a.height) or "nil"
end

function imagesFoundByAssetDocuments()
  local a = nil; pcall(function() a = readImage(asset.documents .. "_pin_key_img") end)
  return a and ("image " .. a.width .. "x" .. a.height) or "nil"
end

function saveImagesBothWays()
  local r = image(32,32); setContext(r); background(255,0,0,255); setContext()
  saveImage("Documents:_pin_str_img", r)
  saveImage(asset.documents .. "_pin_key_img", r)
  return "saved"
end

function testImageSaves()
  devLog("PIN", "images found by 'Documents:': " .. imagesFoundByDocuments())
  devLog("PIN", "images found by asset.documents: " .. imagesFoundByAssetDocuments())
  devLog("PIN", saveImagesBothWays())
end

function resetTestState()
  saveLocalData("PIN_lc", 0)
  devLog("PIN", "reset done")
end
```

```lua
-- In setup():
testTextSaves()
testImageSaves()
-- resetTestState()  -- uncomment once to clear the counter, then comment back out
```

## Reading results from outside the simulator

```bash
SIM=0EF8AE50-8899-40DD-A77E-359C06732886
BUNDLE=com.jessewonderclark.quozzyseasons

# Lua output via system log
xcrun simctl spawn $SIM log show --last 10s --predicate 'process == "Quozzy"' | grep "🧑‍💻"

# Verify files on disk
xcrun simctl get_app_container $SIM $BUNDLE data   # data container (Documents:)
xcrun simctl get_app_container $SIM $BUNDLE app    # app bundle (asset.documents)
```

## Other things we learned

- `readText("Documents:name")` without a file extension silently returns nil even though `saveText` wrote the file to disk. Always use `.txt`.
- `saveImage` auto-appends `.png`, so images don't have this problem.
- `saveLocalData`/`readLocalData` writes to `NSUserDefaults`, backed by `Library/Preferences/<bundle-id>.plist` in the data container.
- `devLog()` calls `objc.log()` which shows up in the system log. `print()` only goes to the Codea internal console. This project redirects `print = devLog`.

## Text rendering

- `text()` silently **drops the en dash `–` (U+2013)** — it renders as nothing. The em dash `—` (U+2014) and the ASCII hyphen `-` render fine. Use `—` for attribution/quote dashes.
