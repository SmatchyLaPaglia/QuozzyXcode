When I ask a question without a clear task, discuss it conversationally before proposing any plan or action.

## Project Overview

**Quozzy** is a Boggle-style word game for iOS written in **Lua for the [Codea](https://codea.io) iPad environment**. It supports single-player timed rounds and asynchronous turn-based multiplayer via GameCenter. The current build is `#8 (1.0.8)`.

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
| `STATE_MENU` | Main menu with haiku, season selector, game mode buttons |
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

### End Screen Architecture

The end screen has two rendering paths. **Only the FP path is active** — the original `drawEndScreen()` body is dead code behind `if true then drawEndScreenFP() return end`:

- `drawEndScreenFP()` → `buildEndScreenModel()` → `drawEndScreenWith(model, layout)` every frame
- Layout is cached in `endScreenLayout`; recalculated only on screen size change (`ensureEndScreenLayout()`)
- `buildEndScreenModel()` lazily calls `solveBoardMissedWords(q)` and caches result on `q.missedWords`
- Touch handling lives in `handleEndScreenTouch()` in `EndScreen.lua`

### Persistence

- `readLocalData(key)` / `saveLocalData(key, val)` — Codea's built-in key-value store
- `readText(path)` / `saveText(path, text)` — file I/O for SOWPODS caching
- `opponentRecords` — win/loss history persisted as JSON via `saveLocalData`

### GameCenter / ObjC Bridge

GameCenter is accessed through Codea's `objc` global. All GC calls are wrapped in `pcall()`. Async events arrive via `objc.async()` callbacks. The `CTBM` class in `CodeaTurnBasedMatches.lua` manages the full turn-based lifecycle.
