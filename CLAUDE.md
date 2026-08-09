When I ask a question without a clear task, discuss it conversationally before proposing any plan or action.

## Code Analysis
`STRUCTURE.md` (repo root) — use as first stop before searching. Contains: auth/GC flow, state machine transitions, key function→file index. Read it before grepping.
Before searching or asking about code structure, architecture, or file locations, read STRUCTURE.md first. It is a living index of the codebase written to save you analysis time. Treat it as ground truth until you find evidence it's outdated, then update it. When you discover architectural facts through investigation, add them to STRUCTURE.md immediately, in the same terse format.

**Before debugging file I/O or other platform quirks:** read `XCODE_CODEA.md` (repo root). It documents what works and doesn't for `saveText`/`readText`/`saveImage`/`readImage` across `Documents:` and `asset.documents` paths in the Xcode-exported Codea runtime. Saves hours of confusion.

## Codea Drawing Rules — read before touching ANY draw code

Codea uses OpenGL-style **y-up** coordinates. Origin (0,0) is **bottom-left**.

**CORNER = BOTTOM-LEFT. Always.** `rectMode(CORNER)`, `textMode(CORNER)`, `ellipseMode(CORNER)` — all of them. The given (x, y) is the bottom-left corner.

**Text in CORNER mode: anchored at bottom-left, flows UPWARD.** This is the opposite of CSS/web (y-down, top-left). If you don't actively think about this before every `text()` call, you will get it wrong.

**Before any `rect(`, `text(`, `ellipse(`, `sprite(` call, ask yourself: "Am I assuming top-left right now?"** If yes, stop and flip your Y.

## Project Overview

**Kotoba** is a Boggle-style word game for iOS written in **Lua for the [Codea](https://codea.io) iPad environment**. It supports single-player timed rounds and asynchronous turn-based multiplayer via GameCenter. The current build is `#11 (version 1)` (`CURRENT_PROJECT_VERSION` / `MARKETING_VERSION` in `Quozzy.xcodeproj/project.pbxproj`).

> **Name split:** The app is branded **Kotoba** to users (home-screen `CFBundleDisplayName` + the in-game loading screen). Everything internal is still **Quozzy** and stays that way: the Xcode target/scheme (`Quozzy`), the Codea bundle (`Quozzy.codea`), the executable/process name (`Quozzy` — so `log show ... process == "Quozzy"` is correct), and the bundle ID (`com.jessewonderclark.quozzyseasons`). Don't "fix" internal `Quozzy` references to `Kotoba` — it would break diagnostics and orphan App Store/GameCenter identity. The static launch-screen PNG (`Loading_QuozzySeasons`) still shows "Quozzy" baked into the art; regenerating it is a separate art task.

## Running the Project

- **On device**: Open `Quozzy.codea` in the Codea app on iPad — it runs immediately in the editor.
- **As an iOS app**: Export from Codea to Xcode via `Quozzy.xcodeproj`, then build/run via Xcode.
- There are no build scripts, linters, or test runners.

## Architecture

### Codea Game Loop

All Lua files in `Quozzy.codea/` are loaded at startup as globals — there are no imports or modules. The entry point is `Main.lua`, which defines the standard Codea callbacks:

```lua
setup()    -- called once; initializes dictionary, GameCenter, themes, board
draw()     -- called every frame (~60fps); routes to the current state's draw function
touched(t) -- called on touch events; routes to the current state's touch handler
```

### State Machine

Four states, defined as constants in `Main.lua`:

| State | Description |
|-------|-------------|
| `STATE_MENU` | Main menu with 6-section layout: title/season, board area, min dice, play modes (solo/vs/robot), records/info, disclaimer |
| `STATE_READY` | Pre-game countdown; shows board and opponent name |
| `STATE_PLAY` | Active gameplay: timer, board interaction, word discovery |
| `STATE_END` | Results screen: scores, found words, missed words, win/loss |

### Key Files

| File | Responsibility |
|------|---------------|
| `Main.lua` | Game loop, state machine, settings persistence, GameCenter bootstrap |
| `qMatch_qPlayer.lua` | `qMatch` data structure, GameCenter match conversion (`makeQMatchFromGK`), turn serialization |
| `Board.lua` | Dice definitions, tile generation, board rendering, `scoreForWordLength()`, `inferBoardSizeFromTiles()` |
| `WordLogic.lua` | Touch-driven word path: `areAdjacent()`, `finalizeWord()`, scoring, duplicate detection |
| `Dictionary.lua` | SOWPODS loading/caching; `buildDictionaryFromString()` builds `DICT` + `PREFIXES` globals |
| `BoardSolver.lua` | Post-game board solver: `solveBoardAllWords()`, `solveBoardMissedWords()` |
| `EndScreen.lua` | End screen constants, layout calculation, touch handling, scroll list globals |
| `EndScreenFP.lua` | `buildEndScreenModel()`, `drawEndScreenWith()`, `drawMissedWordsTab()` |
| `GameCenter.lua` | Game flow transitions: `enterQMatch()`, `endGameRound()` |
| `CodeaTurnBasedMatches.lua` | GameCenter ObjC bridge wrapper (turn lifecycle, callbacks) |
| `Themes.lua` | Seasonal color palettes; `Color` global table populated per season |
| `ScrollList.lua` | Reusable inertial scroll list component used throughout UI |
| `HaikuMenu.lua` | Main menu draw (6-section proportional layout) and touch handling |
| `Helpers.lua` | `ensureMyWordStore()`, `currentFoundWords()`, `drawBoardPreview()`, `pointInRect()` |

### Core Data Structures

**`qMatch`** — the central game object, lives in `currentQMatch`:
```lua
{
  id, source, boardSize,
  boardTiles,   -- flat array of uppercase tile strings, e.g. {"A","QU","N",...}; length 16 (4×4) or 25 (5×5)
  players = {
    [playerId] = { score, words = {{word="CAT", points=1}, ...}, didPlay }
  },
  outcome, status, lastUpdated,
  missedWords   -- populated lazily on end screen by BoardSolver
}
```

**Board**: `board[row][col]` is a 2D table (1-indexed). The Q die is stored as `"QU"`. Tiles are always uppercase.

**Dictionary**: `DICT[word] = true` — global hash set, O(1) lookup. `PREFIXES[prefix] = true` is built alongside `DICT` by `buildDictionaryFromString()` for DFS pruning in the board solver.

### Global State

Heavy use of globals shared across files — idiomatic Codea Lua. Key ones:

- `state` — current game state
- `currentQMatch` — active match object
- `board`, `boardSize`, `tileRects` — board data and screen layout
- `score`, `foundWordsSet` — in-progress gameplay
- `DICT`, `PREFIXES`, `MIN_WORD_LEN` — dictionary and validation
- `useTurnBased` — false for single-player, true for GameCenter matches
- `Color` — current season's palette table (populated by `Themes.lua`)
- `endScreenShowMissed`, `endScreenMissedTabRect` — end screen missed-words tab state
- `menuHitRects` — hit rects for interactive menu elements (populated each frame by drawMenu)
- `pressedButton`, `pressedInside` — button press state tracking

### End Screen Architecture

The end screen has two rendering paths. **Only the FP path is active** — the original `drawEndScreen()` body is dead code behind `if true then drawEndScreenFP() return end`:

- `drawEndScreenFP()` → `buildEndScreenModel()` → `drawEndScreenWith(model, layout)` every frame
- Layout is cached in `endScreenLayout`; recalculated only on screen size change (`ensureEndScreenLayout()`)
- `buildEndScreenModel()` lazily calls `solveBoardMissedWords(q)` and caches result on `q.missedWords`
- Touch handling lives in `handleEndScreenTouch()` in `EndScreen.lua`

### Persistence

- `readLocalData(key)` / `saveLocalData(key, val)` — Codea's built-in key-value store (backed by `NSUserDefaults`, writable to `Library/Preferences/<bundle-id>.plist`)
- `readText(path)` / `saveText(path, text)` — file I/O for SOWPODS caching
- `opponentRecords` — win/loss history persisted as JSON via `saveLocalData`

### Diagnostic Logging

All `print()` and `devLog()` output reaches three channels:

| Channel | Mechanism | How to read from outside simulator |
|---------|-----------|-------------------------------------|
| Codea console | native `print()` | Not accessible outside app |
| System log | `objc.log("🧑‍💻 " .. msg)` | `xcrun simctl spawn $SIM_ID log show --last Ns --predicate 'process == "Quozzy"'` |
| Ring buffer | `saveLocalData("DevLogBuffer", json.encode(buffer))` | `plutil -p <container>/Library/Preferences/<bundle-id>.plist \| grep DevLogBuffer` |

- `print` is redefined to `devLog`, so both functions reach all three channels
- Ring buffer holds last 200 lines, flushed to `saveLocalData` every 1 second
- Buffer cleared at each launch (`saveLocalData("DevLogBuffer", "[]")` in `setup()`)
- For crash forensics: stale buffer from previous session is overwritten on first flush (~1s into new session)
- See `Main.lua:~49` for the implementation (`_nativePrint`, `_appendToLogBuffer`, `_flushLogBuffer`)

### GameCenter / ObjC Bridge

GameCenter is accessed through Codea's `objc` global. All GC calls are wrapped in `pcall()`. Async events arrive via `objc.async()` callbacks. The `CTBM` class in `CodeaTurnBasedMatches.lua` manages the full turn-based lifecycle.

### Native UI via ObjC Bridge

Some UI elements are **UIKit objects managed through the ObjC bridge**, not Codea drawing primitives. The comment text field on the end screen is the primary example:

- Created with `objc.UITextField:alloc():init()` and added via `addSubview_`
- Keyboard avoidance is handled **entirely through the ObjC bridge** (see KeyboardAvoider project in repo root)
- **Do not mix Codea's native keyboard handling API with ObjC keyboard handling** — they conflict
- Cleanup requires explicit `removeFromSuperview_()` — the field does not disappear when Codea stops drawing

### State Transition Timing Trap

When the end screen is dismissed, `state` does **not** immediately change to `STATE_MENU`. `startSeasonTransition()` begins a **0.7-second color animation**, and `state = STATE_MENU` is only set inside `updateSeasonTransition()` after the fade completes.

During those 0.7 seconds, `draw()` continues calling `drawEndScreenFP()` every frame. Any teardown that happens before the transition completes will be undone on the next frame if the draw path can recreate what was torn down. Guard against this with an explicit boolean flag — do not rely on nil checks alone.

## Versioning

In comments for git commits, use the language 'Excecuted by <Claude model>' to credit yourself instead of 'Co-authored-by <Claude model>.

