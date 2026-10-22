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
| `saveProjectData(key, val)` / `readProjectData(key)` | ❌ | ❌ |

**`saveProjectData` does not persist in the exported app** (confirmed on a real iPad, 2026-10-09). A write is readable for the rest of that process, but after a relaunch `readProjectData` returns whatever was in the bundled `Quozzy.codea` project data at build time (stale dev values), not what was saved. Use `saveLocalData` for anything that has to survive a relaunch. The relay tables in `qMatch_qPlayer.lua` and the vs/Records "viewed" sets were moved to `saveLocalData` for this reason; `SEASON_KEY` (`Themes.lua`/`ConfettiEffectsEtc.lua`) still uses projectData.

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


## Objective-C bridge (LuaKit) — learned the hard way (2026-10-09/10)

- **Re-entrant callbacks wedge the render thread.** While the render thread waits on a
  bridge call (property read, method call), LuaKit may run a pending Lua callback block
  re-entrantly with a corrupted stack. It fails before the callback's body runs ("attempt
  to call a string value", "bad argument #-1 to 'async' (function expected, got string)")
  and the render thread never recovers: app frozen, taps ignored, no crash report. Any
  completion handler iOS answers almost instantly (UNUserNotificationCenter
  addNotificationRequest) must get `nil`, not a Lua function — even `function() end` froze it.
  All other callbacks only `handOff(...)` (see STRUCTURE.md "CALLBACK HAND-OFF").
  - Also froze (2026-10-22, iPad): `UNUserNotificationCenter
    getNotificationSettingsWithCompletionHandler_` with a callback that ONLY called
    `handOff`. Handing off doesn't help when iOS answers during the same bridge call. Any
    query whose answer is cached (notification settings, delivered notifications) is unsafe to
    ask from Lua at all; the XR survived the same call, so it's intermittent, not harmless.
- **Never `objc.NSString:alloc()`.** LuaKit converts every returned NSString to a Lua string,
  including the uninitialized placeholder from `alloc()`; the Objective-C exception that
  follows can't be caught by `pcall` (simulator: abort with a crash report; device: silently
  kills the render thread). Read NSData with `NSMutableData:dataWithData_(d)`,
  `m:increaseLengthBy_(1)`, `NSString:stringWithUTF8String_(m.bytes)`.
- **Lua errors from Codea itself go to stdout only** — not to devLog. Capture them with
  `xcrun devicectl device process launch --console --terminate-existing --device <id>
  com.jessewonderclark.quozzyseasons > console.txt`, or read the Xcode console.
- Simulator crashes leave `.ips` reports in `~/Library/Logs/DiagnosticReports/`
  (`lastExceptionBacktrace` holds the exception stack). Devices often leave none.
- `lldb` attach to a device app: only one debugger at a time (fails while Xcode is attached).
  `device select <id>` / `device process attach --pid N` then wait for the attach to finish
  before interrupting (python: poll `GetProcess().GetState()`).

## Device / Xcode practicalities

- Low Power Mode forces Auto-Lock to 30 s regardless of the setting; a locked iPad refuses
  app launch ("device was not, or could not be, unlocked"). For automated runs, set
  `objc.UIApplication.sharedApplication.idleTimerDisabled = true` via DevRemote.
- iPad can drain while "charging" from a laptop/hub port: the app redraws at 60 fps. Use a
  ≥20 W wall charger during long test sessions.
- Xcode stuck on "Connecting to <device>" while `devicectl list devices` says connected:
  restart the iPad; or `killall -9 CoreDeviceService remotepairingd`; or Devices and
  Simulators → untick "Connect via network" / Unpair and re-trust. (Untested which works.)
- Builds from Xcode have DevRemote off (source keeps `DEV_REMOTE_ENABLED = false`); to drive a
  device with tools/dbg.sh, build with it flipped on locally and don't commit the flip.
- **Deployment target is iOS 16.6** — the Runtime package's CraftKit/RuntimeKit binaries are built minos 16.6
  (`xcrun vtool -show-build`), so a lower app target would let devices install a build that can't load them.
- **Framework dSYMs ("Upload Symbols Failed")**: the Runtime package's five xcframeworks ship without dSYMs or DWARF.
  The Quozzy target's last build phase, "Generate Framework dSYMs", runs `dsymutil` on each embedded framework
  on archive only (`ACTION=install`) into the archive's dSYMs folder. No line numbers, but UUIDs match and the
  symbol tables give function names in crash reports.


## GameKit turn-based: who can send what, and what notifies whom (2026-10-20/22)

Details and history: MULTIPLAYER_DESIGN.md. Confirmed on two real devices (iPad + XR, raw
GameKit calls through the objc bridge, `tools/notify_trial.lua`):
- **Turn holder only:** `endTurnWithNextParticipants…` (passes the turn),
  `saveCurrentTurnWithMatchData…` and `saveMergedMatchData…withResolvedExchanges…` (write
  matchData, turn stays put), `endMatchInTurnWithMatchData…`. An unmerged *completed* exchange
  makes endTurn/endMatch fail with a generic code 3 — merge first.
- **Anyone, holder or not:** `sendExchangeToParticipants…`, the recipient's
  `replyWithLocalizableMessageKey…`, `sendReminderToParticipants…`,
  `acceptInviteWithCompletionHandler_` (no system UI). The non-holder's only way to put data
  into a match is an exchange.
- **What notifies:** every turn pass pushes the recipient a banner; the app only picks the text
  (`match.message`), not whether. Exchanges, exchange replies and reminders each carry a
  `localizableMessageKey` (+ `arguments`) that becomes the recipient's notification text. There
  is no "silent" variant of any of them.
- **The key is localized on the recipient's device**, from the app's own `Localizable.strings`.
  It has to sit in the app bundle (`Quozzy/en.lproj/Localizable.strings`, added to the Xcode
  project as a variant group) — files inside `Quozzy.codea` don't count. A key with no entry is
  shown raw (e.g. "XCHG_UPDATE"). The recipient needs a build that has the entry.
- **Still to confirm by eye:** whether a key mapped to `""` hides the banner or shows a blank one
  (likely a title-only "Vivaldi-ku"), and whether saves / match end show anything at all.

Testing notifications across two devices: `DBG_DEVICE=<id> tools/dbg.sh` per device;
`objc.UIApplication.sharedApplication:suspend()` (private, dev builds only) sends the app to the
home screen so the next notification is presented as a banner; `xcrun devicectl device process
launch --device <id> com.jessewonderclark.quozzyseasons` *without* `--terminate-existing` brings
it back with Lua state intact. Mute the app's own GameKit handlers first, or it auto-replies
to test exchanges (each reply is another notification).


## Fresh export won't start / draws nothing (learned in DoodleComic, 2026-10-21/22)

A newly exported Codea project can build and launch yet show a black or gray screen. Causes found, in the order hit:

- **Codea view has zero size.** `CodeaProjectViewController` must set `runtime.view.frame = view.bounds` in `viewDidLayoutSubviews()` (Quozzy's does; the stock export doesn't).
- **`viewer.mode = ...` fails** ("attempt to index nil 'parentViewController'") unless the Codea VC is embedded in a parent VC. SceneDelegate wraps it in a container VC and adds it as a child.
- **`shader(vs, fs)` at file load fails to compile** and the render thread dies silently. Create shaders from `setup()` (e.g. `makeCompositeShader()`), never at top level of a tab.
- **Lua errors reach stdout only.** Wrap `setup`/`draw`/`touched` in `xpcall(f, debug.traceback, ...)` and route to `devLog` (`objc.log("🧑‍💻 " .. msg)`). `devLog` isn't defined in a fresh export; add it. NSLog in Swift/ObjC shows up in the same stream.
- **Simulator can hang at launch** with the main thread stuck in `_UIConcretePasteboard` → XPC (looks like a Codea bug, isn't). Reboot the simulator. A pending Apple-ID sign-in alert on the simulator also covers the screen; dismiss it.
- Don't use `simctl launch --console*` in scripts: killing the console process kills the app. Use `--stdout=/--stderr=` (files land in the simulator's `data/tmp`) or `log show --predicate 'process == "App"'`.
- A one-line native `NSLog` at `didCreateLuaState`, `runtime.start` completion and `didFinishSetup` shows immediately how far startup got.

## Codea runtime facts

- **`image(w, h)` takes points**; raw pixels = w × `ContentScaleFactor`. For an exact-pixel buffer use `image(px/CSF, py/CSF)`, and draw into it with `pushMatrix(); resetMatrix(); scale(1/CSF)` to work in pixel units.
- **`clip()` takes points here; never call `setContext(img)` while a clip is active** (black texture). Render images first, clip afterwards.
- `readText("Documents:x.txt")` of a missing file logs "Invalid Asset Specified" every call; create the file once (`saveText`) so polling doesn't spam.
- `touched(t)` delivers each finger separately (use `t.id`); pinch/pan is done by tracking touches by id. Fake touches (tables with `id,x,y,state`) can be passed to `touched()` for unattended tests.
- Launch arguments (`-DCTest name`) are readable from Lua via `objc.NSUserDefaults.standardUserDefaults:stringForKey_("DCTest")` (argument domain). That makes a scripted test harness easy: a coroutine stepped from `draw()` that sends fake touches. `devicectl ... launch ... -- -DCTest name` needs the `--`.
- `saveLocalData`/`readLocalData` take strings fine; pack small prefs into one string.

## Native ⇄ Lua without a custom module

For most things `objc.*` from Lua is enough, with no Addon code:
- Calls: `objc.UIActivityViewController:alloc():initWithActivityItems_applicationActivities_({url}, nil)`, `objc.viewer:presentViewController_animated_completion_(vc, true, nil)`, `objc.UIAlertController...`.
- **Your own Swift/ObjC classes** are callable too if they're `@objc(Name) class X: NSObject` with `@objc static func f(_ a: String)`: `objc.Name:f_(a)` (colons → underscores; 2nd+ argument labels become part of the selector, e.g. `sendFile_comicId_`). This is how DoodleComic builds files and presents the Messages composer.
- **Native → Lua** hand-off that needs no callback into Lua: native writes a file (`Documents/incoming_comic.txt`), Lua polls it every ~20 frames. (The Sparts `PingPongModule` shows the direct `unsafeRunLuaBlock` route.)
- Alert/handler callbacks: only set a flag, do the work in `draw()` (see the re-entrancy note above).

## Exporting a comic as a PNG with hidden data; what Messages does with files (DoodleComic)

- **Messages won't open a custom file type.** Tapping a `.doodlecomic` attachment does nothing (Quick Look has no viewer; no "Open in" button), even with an exported UTI. Declaring the UTI as conforming to `public.png` made Messages show the image on the *sending* device but still not on the receiving one.
- **What works:** send a plain `.png`. Hide data in a private ancillary chunk (`dcMc`, before `IEND`, zlib payload; CRC over type+data). Messages preserved it. Receiver: tap the image → share button → either an app listed in the top row (a Share Extension) or the action list (an Action Extension). Declare the app for `public.png/jpeg/heic` with `LSHandlerRank = Alternate` in `CFBundleDocumentTypes`.
- **Share vs Action extensions** (both can coexist, using the same code):
  - Action (`com.apple.ui-services`, `NSExtensionServiceRoleTypeViewer`): appears in the list *under* the app row, enabled by default.
  - Share (`com.apple.share-services`): appears in the *top row*, but the user may have to add it via More.
  - Neither can officially open the host app. The extension copies the image into an **App Group** container (`group.<bundle id>`) and then walks the responder chain to `UIApplication` and calls `openURL:options:completionHandler:` on `doodlecomic://…`. The app also drains the App Group inbox in `sceneDidBecomeActive` as a fallback.
  - Extensions need their own bundle IDs (`<app>.open`, `<app>.share`), the same App Group entitlement as the app, and `SKIP_INSTALL = YES`. A synchronized-folder group can be shared by two extension targets.
- Share-sheet icons refresh by closing and reopening the share sheet. Action icons are drawn as one-colour templates; design with transparency in mind.
- **Sending to a remembered person:** `MFMessageComposeViewController` (`canSendText` + `canSendAttachments`), recipient picked once with `CNContactPickerViewController` (select a phone/email *property*), stored per comic in UserDefaults. Falls back to the share sheet where Messages can't send (simulator).
- Don't know the recipient from a share sheet: iOS never reports who the user picked.

## Signing, extensions, command-line builds

- `xcodebuild ... -allowProvisioningUpdates` registers new App IDs/App Groups on the first run. A transient "No Accounts" error happened once with the account signed in; simply retrying worked.
- Build + install to a device: `xcodebuild -destination 'generic/platform=iOS' ... build` then `xcrun devicectl device install app --device <CoreDevice UUID> App.app` (CoreDevice UUID from `devicectl list devices`, not the hardware UDID).
- Files can be copied into an app container with `devicectl device copy to --domain-type appDataContainer --domain-identifier <bundle id> --source ... --destination Documents/...`.
- Open a file in the simulator app: `xcrun simctl openurl <SIM> file:///...` (for a PNG the system's default image app wins; test file-handling with the app's own UTI or the share sheet instead).

## App Store submission checklist (Codea exports)

- **Deployment target must be ≥ 16.6** for app *and* extensions (the Runtime frameworks are `minos 16.6`; lower targets install and then crash on older iOS).
- **ITMS-90683 "Missing purpose string"**: RuntimeKit references camera, location, Bluetooth, (and microphone/motion/photos) APIs. Add `NSCameraUsageDescription`, `NSLocationWhenInUseUsageDescription`, `NSBluetoothAlwaysUsageDescription` (required by the upload) plus `NSMicrophoneUsageDescription`, `NSMotionUsageDescription`, `NSPhotoLibraryUsageDescription` to the app's Info.plist. Wording like "<App> does not use the camera." is enough (the app never requests them). The camera one *blocks* the upload; the others are only warnings.
- Add `PrivacyInfo.xcprivacy` (UserDefaults `CA92.1`, file timestamp `C617.1`; no tracking, no data collected) — the Codea frameworks ship no manifest.
- `ITSAppUsesNonExemptEncryption = false` in Info.plist avoids the export-compliance question on every upload.
- Remove unused test images from the `.codea` folder — everything in it ships in the app.
- Bump `CURRENT_PROJECT_VERSION` for every upload (a build that failed processing still burns its number).
- Info.plist `CFBundleIdentifier` must be `$(PRODUCT_BUNDLE_IDENTIFIER)`, not a hard-coded string that overrides the build setting (the stock export had one).
- Command-line export (`xcodebuild -exportArchive`) needs a distribution certificate; if the machine has none, use Xcode Organizer → Distribute App, which creates it. Organizer can show `DistributionAppRecordProviderError` right after the app record is created; retry after a few seconds.
- After a successful upload, processing takes 5–30+ minutes; an "Invalid Binary" email follows within minutes if it failed.
