# STRUCTURE

## GC Auth Flow

```
CTBM() init (CodeaTurnBasedMatches.lua:~10)
  → self.localPlayer = objc.GKLocalPlayer.localPlayer
  → self._listener = self:_makeLocalPlayerListener()   ← GKLocalPlayerListener delegate
  → self.localPlayer:registerListener_(self._listener)
  → self:_authenticate()

CTBM:_authenticate() (line ~730)
  → if already authenticated: fire _uponDetectingAuthentication() immediately
  → else: set localPlayer.authenticateHandler = fn(vc, err)
      vc non-nil  → presentModalViewController_(vc)  [shows GC login UI]
      vc nil, err nil → _uponDetectingAuthentication()
      err non-nil → silent fail

_uponDetectingAuthentication set in Main.lua:~854
  → defineAvatarsAfterMicrodelay()
  → requestHomeScreenBadgePermission()
  → refreshHomeScreenBadgeFromGCMatches()
  → requestAutoOpenFinishedMatchCheck()

Re-triggering auth on demand: NOT POSSIBLE via re-assigning authenticateHandler
  → bridge does not call the handler on re-assignment after initial auth cycle
  → GameKit only re-calls authenticateHandler when auth state changes (e.g. user signs in via Settings)
  → solution: openGCSignInOverlay() — shows tap-to-dismiss overlay; user signs in via Settings then taps versus again
```

## Versus / Play Again Auth Gate (unauthenticated)

```
Both buttons check tbm.localPlayer.authenticated == true (exact boolean, not truthy)
  authenticated → proceed normally
  not authenticated → openGCSignInOverlay(pendingAction)

openGCSignInOverlay (OverlayPanels.lua)
  → sets gcSignInOverlay=true
  → draws tap-to-dismiss panel (title + body only, no button)
  → dismisses on any tap; user taps versus/playAgain again once signed in

touch routing: handleGCSignInOverlayTouch (Main.lua touched(), before state handlers)
  → any ENDED/CANCELLED touch dismisses
```

## Play Again Flow

```
NOTE: The playAgain button has been removed from the main menu (HaikuMenu.lua) as of the 6-section redesign. Play again will be re-introduced elsewhere.

Legacy flow (still functional via startLastMatchReplayFromMenu in Main.lua):
  → getLastMatchReplaySettings()
  → authenticated? no  → openGCSignInOverlay()
  → authenticated? yes → startLastMatchReplayFromMenu()  [Main.lua]

startLastMatchReplayFromMenu()
  → getLastMatchReplaySettings()  ← reads lastMatchReplaySettings cache or disk (LAST_MATCH_REPLAY_KEY)
  → settings nil/false → returns (no-op, no matchmaker)
  → beginReplayMatchmakingBusy("matching...")  ← sets replayMatchmakingBusy=true
      !! this blocks ALL touches in touched() until cleared !!
      !! if async callback never fires, both buttons dead until app restart !!
  → _tryRematchForLastReplay(settings)

_tryRematchForLastReplay(settings)  [Main.lua]
  → uses settings.opponentPlayerID (deprecated playerID format e.g. "G:12345")
    with GKPlayer:loadPlayersForIdentifiers_withCompletionHandler_
  → IMPORTANT: gamePlayerID ("A:_..." / "G:..." modern format) returns 0 results
    from loadPlayersForIdentifiers — must use the deprecated playerID field
  → on success: GKTurnBasedMatch:findMatchForRequest_withCompletionHandler_
      with request.recipients = {gkOpponent}
  → on match created: endReplayMatchmakingBusy() → tbm:_setCurrentMatch() → enterQMatch()
  → all error paths call _showGenericMatchmaker() which also calls endReplayMatchmakingBusy()

Where opponentPlayerID comes from:
  makeQMatchFromGK() [qMatch_qPlayer.lua] stores q.opponentPlayerID = pl.playerID
  persistLastMatchReplaySettingsFromQMatch() [Main.lua] saves it to disk payload
  Call sites: finalizeCompletedTurnBasedMatch() [GameCenter.lua] — unconditional ✓
              enterQMatch() [GameCenter.lua] — guarded: only fires when tbm match is already ended
              (guard prevents open rematch from overwriting ended match's saved ID)
```

## Versus Button Flow

```
HaikuMenu.lua: handleMenuTouch() key=="vs"  (section 4 button)
  → tbm exists?  no → openGCMatchmakerErrorOverlay()
  → authenticated? yes → tbm:showMatchmaker()
                   no  → openGCSignInOverlay(function() tbm:showMatchmaker() end)

tbm:showMatchmaker() (CodeaTurnBasedMatches.lua:~603)
  → GKMatchRequest (minPlayers=maxPlayers=2)
  → GKTurnBasedMatchmakerViewController:initWithMatchRequest_(req)
  → sets vc.turnBasedMatchmakerDelegate = self._matchmakerDelegate
  → presentModalViewController_animated_(vc, true)

matchmakerDelegate callbacks (CodeaTurnBasedMatches.lua:~628)
  cancelled  → dismissModalViewControllerAnimated_ → _onMatchmakerCancelled()
  error      → dismissModalViewControllerAnimated_ → _onMatchmakerError()
  didFindMatch → dismissModalViewControllerAnimated_ (authoritative delivery via GKLocalPlayerListener)
```

## Turn Receipt Flow

```
GKLocalPlayerListener.player_receivedTurnEventForMatch_didBecomeActive_
  → thisCTBM:_onReceivingTurn(o__match, dataTable)

Main.lua tbm:onReceivingTurn callback (~862)
  → makeQMatchFromGK(gkMatch, dataTable)  [qMatch_qPlayer.lua]
  → enterQMatch(q)  [GameCenter.lua]
```

## State Machine

```
States: STATE_MENU, STATE_READY, STATE_PLAY, STATE_END  (Main.lua constants)

STATE_END → STATE_MENU: NOT immediate
  startSeasonTransition() begins 0.7s color animation
  state = STATE_MENU set inside updateSeasonTransition() only after fade completes
  → draw() keeps calling drawEndScreenFP() for 0.7s after dismiss
  → guard ObjC teardown with boolean flags (not nil checks)
```

## Ready-Screen Dice Rattle (Board.lua, 2026-08-08)

```
STATE_READY previously showed static "?" on every tile. Now shows randomly-changing
letters (readyRattleLetters[r][c], readyRattleNextFlip[r][c] — Board.lua, right before
generateBoardTiles()), like dice being shaken, updated by updateReadyRattle() which
Main.lua's draw() calls once/frame during STATE_READY (before drawBoard()).
Per-tile independent stagger: each cell flips to a new randomDiceLetter() at its own
ElapsedTime-based next-flip time (~0.12-0.30s apart), not synchronized — reads as a
rattle, not a synchronized blink.
DELIBERATELY disconnected from `board`: `board` (the real tiles) is generated by
generateBoard() inside startRoundFromCurrentSettings(), BEFORE state is even set to
STATE_READY. The rattle table is a separate global fed by randomDiceLetter(boardSize),
which just pulls a random face off a random die from DICE_4x4/5x5/6x6 — there is no
code path connecting what's showing at the moment of tap to the tiles STATE_PLAY reveals.
drawBoard()'s STATE_READY branch reads readyRattleLetters instead of board; the
STATE_PLAY branch (and everywhere else) is untouched, still reads board[r][c] directly.

Positional jitter (2026-08-09, drawBoard()'s tile-drawing loop): each STATE_READY tile also
wobbles a few % of tileSize around its resting spot — jx/jy computed per-tile from
sin/cos(ElapsedTime * freq + r*k1 + c*k2), phase seeded from (r,c) so neighbors don't move
in sync. Added to BOTH the tile's drawRoundedRect call and its text() call so the letter
stays glued to the tile. Purely cosmetic, drawn on top of the (also cosmetic) letter-flip —
neither touches tileRects (hit-testing/tap targets are unaffected).

Rotation tilt (2026-08-09, same loop): each tile also rotates ±7° on its own sin() phase
(different freq/phase multipliers than the position wobble, so they don't lock into one
simple back-and-forth). Rotation requires pushMatrix()/translate(x+jx,y+jy)/rotate(angle)/
popMatrix() with the tile drawn at LOCAL (0,0) inside that block — drawRoundedRect/text
take absolute coords normally, so this is a separate code path from the angle==0 case
(STATE_PLAY, or any tile that happens to roll a zero angle) which still draws directly at
(x+jx, y+jy) with no matrix push, cheaper for the common case.
```

## Info / About Overlay (OverlayPanels.lua, 2026-08-09)

```
Rewrote drawInfoOverlay() from a tiny centered popup (just the haiku attribution — now
redundant with HaikuMenu's own attribution line beneath the haiku) into a near-fullscreen
(WIDTH-32 x HEIGHT-110), scrollable About panel. Manual scroll (infoScrollY/
infoScrollTouchId/infoScrollPrevY + infoOverlayGeom), same hand-rolled pattern as
RecordsUI.lua's recordsScrollY (not the ScrollList class, which assumes uniform row
height — wrong fit for headers/paragraphs/bullets of different sizes).

ABOUT_CONTENT: array of {type="h1"|"p"|"bullet", text=, lead=} blocks — the actual copy.
buildAboutLines(wrapWidth) flattens it into display lines (word-wrapped via local
wrapTextLines()), cached in aboutLinesCache keyed by wrapWidth so it isn't rebuilt every
frame. Bullets render as a bold lead-in line ("• Lead:") followed by an indented normal
paragraph — Codea's text() can't mix bold/regular within one string, so inline markdown
bold is split into two lines instead of attempted as rich text.

SCROLL MATH GOTCHA (caught only by forcing infoScrollY=900 + a devLog dump before
shipping, NOT by the unscrolled screenshot which looked fine): cursorY must be
`bodyTop + infoScrollY`, not `bodyTop - infoScrollY`. With minus, any infoScrollY > 0
pushes every line below bodyBottom and the panel renders completely blank (the walk
never recovers since it only ever subtracts line heights going forward). The drag
handler mirrors this: dragging up (dy = t.y - prevY > 0) must ADD to infoScrollY, not
subtract. If touching this again, sanity-check with a forced non-zero infoScrollY +
devLog(totalH, bodyHeight, maxScroll) — the bug is invisible at infoScrollY=0.

openInfoOverlay()/closeInfoOverlay() reset scroll state; HaikuMenu's key=="info" calls
openInfoOverlay() (not showInfoOverlay=true directly, so scroll always starts at 0).
handleInfoOverlayTouch() wired into Main.lua touched() same tier as handleRecordsTouch().

drawMatchBadge() (Badges.lua) gated on `if showInfoOverlay then return end`, matching its
existing colorInspectorOverlay guard — needed once the panel went near-fullscreen (the old
tiny popup never overlapped the badge's screen position, so this was never an issue before).
NOTE: an iOS/GameKit system banner ("Welcome back <player>", the native Game Center
auth toast) can ALSO render on top of everything, including this panel, on a fresh
launch/re-auth — that one is OS chrome, not app-drawn, and not fixable from Lua; it clears
on its own after a few seconds and isn't a bug.
```

## ObjC UITextField Lifecycle (end screen comment field)

```
EndScreenFP.lua: ensureEndScreenNativeCommentField()
  → creates objc.UITextField, addSubview_
  → guarded by endScreenCommentFieldTornDown flag

teardownEndScreenCommentField()
  → resignFirstResponder_(), removeFromSuperview_()
  → sets endScreenCommentFieldTornDown = true
  → removes NSNotificationCenter KB observers

endScreenCommentFieldTornDown reset: syncEndScreenCommentState() on new match ID
```

## Comment Phase Gate

```
currentFinalCommentPhase()  [GameCenter.lua:~104]
  guard1: useTurnBased && q && q.players && tbm && tbm.currentMatch
  guard2: pid && me && me.didPlay   ← does NOT require opponent slot
  returns: { localCanCompose=(tbm.isMyTurn), opponentPlayed=(oppData~=nil && oppData.didPlay) }

shouldShowFinalCommentComposer() → info and info.localCanCompose

Initiator missing-field bug root: firstNonLocalParticipant() returns nil when
  opponent.remoteStatus="matching" (no .player object yet) → no oppData slot → guard2 failed
  Fix: guard2 no longer requires oppId/oppData
```

## Key File → Function Index

| concern | file | function |
|---|---|---|
| menu draw (6-section layout) | HaikuMenu.lua | drawMenu() |
| versus tap (section 4) | HaikuMenu.lua | handleMenuTouch() key=="vs" |
| solo tap (section 4) | HaikuMenu.lua | handleMenuTouch() key=="solo" |
| board size cycle (section 2) | HaikuMenu.lua | handleMenuTouch() key=="boardSize" |
| min word len cycle (section 3) | HaikuMenu.lua | handleMenuTouch() key=="minWordLen" |
| records tap (section 5) | HaikuMenu.lua | handleMenuTouch() key=="records" |
| info tap (section 5) | HaikuMenu.lua | handleMenuTouch() key=="info" |
| robot tap (section 4) | HaikuMenu.lua | handleMenuTouch() key=="robot" |
| GC auth | CodeaTurnBasedMatches.lua | CTBM:_authenticate() |
| unauthenticated gate | OverlayPanels.lua | openGCSignInOverlay(), drawGCSignInOverlay(), handleGCSignInOverlayTouch() |
| post-auth setup | Main.lua ~854 | tbm:uponDetectingAuthentication callback |
| matchmaker UI | CodeaTurnBasedMatches.lua | CTBM:showMatchmaker() |
| turn receipt | CodeaTurnBasedMatches.lua | _makeLocalPlayerListener() |
| qMatch build | qMatch_qPlayer.lua | makeQMatchFromGK() |
| enter match | GameCenter.lua | enterQMatch() |
| end game | GameCenter.lua | endGameRound() |
| comment gate | GameCenter.lua | currentFinalCommentPhase() |
| comment submit | GameCenter.lua | submitFinalCommentFromEndScreen() |
| finalize match | GameCenter.lua | finalizeCompletedTurnBasedMatch() |
| comment field ObjC | EndScreenFP.lua | ensureEndScreenNativeCommentField(), teardownEndScreenCommentField() |
| end screen draw | EndScreenFP.lua | drawEndScreenFP() → buildEndScreenModel() → drawEndScreenWith() |
| end screen touch | EndScreen.lua | handleEndScreenTouch() |
| avatars | Avatars.lua | loadLocalPlayerAvatar() |
| generic alert | HaikuMenu.lua | showGenericAlert(), drawGenericAlert(), dismissGenericAlert() |
| play-again tap (section 4) | HaikuMenu.lua | handleMenuTouch() key=="playAgain" |
| debug dialog tap | HaikuMenu.lua | handleMenuTouch() key=="debugDialog" |
| logging system | Main.lua ~49 | devLog(), print = devLog, ring buffer, _flushLogBuffer() |
| file I/O diagnostic | Main.lua ~862 | testTextSaves(), testImageSaves(), resetTestState() |
| platform gotchas | XCODE_CODEA.md | File I/O reference, path behavior matrix |

## ObjC Bridge: Key Patterns

- devLog() → objc.log() → Xcode console (🧑‍💻 prefix) ← USE THIS for debugging
- print() → Codea internal log only, NOT visible in Xcode
- CTBM:_major() → calls devLog() when available ← also visible in Xcode console
- CTBM:log() → uses print() ← NOT visible in Xcode
- ObjC method colons → underscores; trailing colon → trailing underscore: `openURL:options:completionHandler:` → `openURL_options_completionHandler_`
- Callback parameter names MUST have type prefix: b=bool, o=object, s=string, i=int, f=float
  e.g. `function(bSuccess)` not `function(success)` — unprefixed params receive nil
- NEVER call UIKit/Codea (or anything that touches Codea's draw cycle) from inside an objc
  callback/delegate — it can crash. Callbacks must ONLY set a Lua flag/var; do the real work in
  draw() when it detects the flag. (e.g. comment-balloon UITextViewDelegate sets F.focused
  only; text mutation + resignFirstResponder happen in draw() via enforceCommentFieldLineCap
  — EndScreenFP.lua, shared by the mockup and the production composer)
- openURL_options_completionHandler_(url, {}, nil) — empty table {} works as NSDictionary; nil ok for completion handler
- "app-settings:" opens app's own Settings.bundle page (not Game Center); requires Settings.bundle to show content
- Re-assigning authenticateHandler does NOT call the handler again — bridge ignores it after initial auth cycle
- GKPlayer ID formats: gamePlayerID = modern scoped ID ("A:_..." or "G:..." format); playerID = deprecated old format
  loadPlayersForIdentifiers only works with playerID — gamePlayerID returns 0 results (confirmed)
  Always store BOTH on qMatch: q.opponentId=gamePlayerID, q.opponentPlayerID=playerID
- GKPlayer objects cannot be persisted across app launches — must reconstruct via loadPlayersForIdentifiers(playerID)

## Seasonal Particle Engine (ConfettiEffectsEtc.lua)

```
Reusable seasonal-emoji particle system:
  spawnPathParticles(x,y)  → bursts SeasonConfettiEmoji[season] + generic emoji at (x,y),
                             tuned by Sparkler{} table (spawnFrequency/velocity/spin/size/fade)
  updatePathParticles(dt)  → Main.lua:1206 (every frame, all states)
  drawPathParticles()      → Main.lua:1219, ONLY inside `if STATE_READY or STATE_PLAY`
                             (⇒ pathParticles are invisible in the menu even if spawned there)

Current wiring: spawn is called ONLY from gameplay tile touches (WordLogic.lua:160, :226).
  There is NO season-name particle binding in the menu — not in HaikuMenu.lua, not in git
  history. Menu season name only has drawSeasonScatter() (8 static dots) + poof-on-swipe.
  To make particles burst around the menu season name, one would call spawnPathParticles at
  the title center AND move the drawPathParticles call outside the STATE_PLAY/READY guard.

Also here: startSeasonTransition()/updateSeasonTransition() (0.7s palette fade → STATE_MENU),
  confetti{} full-screen burst (updateConfetti/drawConfetti), SeasonConfettiEmoji table.
```

## Menu Season Word — Ambient Flecks + Poof (SeasonFlecks.lua + TextGoPoof.lua)

```
SeasonFlecks.lua (NEW tab — registered in Info.plist "Buffer Order"):
  Ambient dots drifting around the menu season word (leaves/seeds/snow feel).
  FLECK_COLOR[Spring/Summer/Autumn/Winter] — dedicated palette (NOT Color.uiAccent).
  initFlecks(cx,cy) / updateFlecks(cx,cy,recycle) / drawFlecks(seasonName, fade).
  Per-frame motion (no DeltaTime) to match TextGoPoof's style. Pool = 80.
  Driven from HaikuMenu.drawMenu() Section 1 (STATE_MENU only), centered on
  seasonRect.cx/cy, re-init when seasonIndex changes (seasonFlecksSeason guard).
  fade = TextGoPoof_flecksFade(): 1 in state A, ramps to 0 as haiku fades in
  (1 - alphaB/255), 0 in state B. recycle=false during the sweep so the pool empties.
  Replaced the old static drawSeasonScatter() 8-dot call (no longer drawn).

TextGoPoof.lua poof (swipe → haiku) reworked to DIRECTIONAL DRIFT:
  startPoof: keep only ~50% of lit pixels; per particle vx = P.direction*baseSpd,
    vy = lift (POSITIVE = up in Codea y-up; source brief was y-down), life counts
    UP to maxLife (90–150 frames), size 2–3 (unchanged).
  drawPoofingText ANIM: vx += P.direction*0.04 (drag 0.98), vy += sine float,
    color = P.specsA.color (season accent), full opacity to 40% of life then fade.
  No gravity/ground-bounce anymore. Word is NOT redrawn during ANIM (no word-fade).

Attribution sync (2026-08-09): TextGoPoof_attributionReady() used to gate on a separate
~1.1s timer (POOF_ATTRIB_DELAY) independent of the haiku's own fade — haiku would finish
fading in (~0.7s, P.alphaB ramps +6/frame to 255) and then attribution would pop in
~0.4s later, a visible stagger. Now TextGoPoof_attributionReady() is just `P.state ~= "A"`
(ready the instant the season name starts dissolving) AND HaikuMenu.lua's
drawMenuSeasonPoof() applies TextGoPoof_haikuAlpha() (new getter, mirrors P.alphaB) as
the attribution's own fill alpha — so it fades in on the EXACT same curve as the haiku,
not just an earlier pop-in threshold.
```

## Menu Dice Word Filter (HaikuMenu.lua, 2026-08-09)

```
Section 3's min-word-length dice (menuDiceDisplayWord) spell an actual random SOWPODS
word of length MIN_WORD_LEN, re-rolled every whole second (randomWordOfLength(n) pulls
from WORDS_BY_LENGTH[n], built from the real DICT). Since SOWPODS contains genuine slurs
and profanity as valid Scrabble words (confirmed: 87 exact matches against a standard
moderation blocklist, at lengths 3-6 — NIGGER, FAGGOT, KIKE, SPIC, CUNT, etc. are all
valid SOWPODS entries), this could display something offensive UNPROMPTED to anyone
glancing at the menu.

randomMenuDiceWord(n) wraps randomWordOfLength's list with a retry-away-from-
MENU_DICE_BLOCKLIST loop (25 attempts, then a one-time full-list filter as a fallback
that should never actually trigger). MENU_DICE_BLOCKLIST is the 3-6 letter single-word
subset of the LDNOOBW list (github.com/LDNOOBW/List-of-Dirty-Naughty-Obscene-and-
Otherwise-Bad-Words, MIT, originally Shutterstock's moderation blocklist) — 126 entries,
exact whole-word match only (NOT substring — avoids the Scunthorpe problem).

SCOPE, DELIBERATELY NARROW: this ONLY affects the menu dice display. randomWordOfLength()
itself, DICT, WORDS_BY_LENGTH, and all real gameplay word validation/scoring are
completely untouched — a player finding an off-color word during an actual round is a
different, accepted situation; this is specifically about words appearing unbidden on
the main menu. randomWordOfLength has exactly one caller (the dice display) as of this
writing — if a second caller is ever added, decide per-caller whether it wants the
filtered or unfiltered picker, don't assume.
```

## Menu Title/Season Band (HaikuMenu.lua)

```
drawMenu() Section 1 builds seasonRect spanning the band top→bottom minus a top safe-area
  inset (max(HEIGHT-getTopSafeY(), HEIGHT*0.035, 24)) and a small bottom pad, then calls
  drawMenuSeasonPoof(seasonRect).
drawMenuSeasonPoof(r): season name (specA) + haiku (specB) both CENTER mode + CENTER align
  at (r.cx, r.cy). Font sizes come from menuMeasureFitSize()/menuMaxHaikuFitSize() which
  measure textSize at ref=100 and scale to fill r; haiku size = size at which the season's
  LARGEST haiku fits. Cached in menuFitCache keyed by seasonIndex + floor(r.w)+floor(r.h).
  Season fit box capped to 500x248 so the poof raster image (512x256, TextGoPoof.startPoof)
  never clips.
showRowDividers (pink section boundary lines) default = false.
```

## pointInRect

- Helpers.lua:24 — expects CENTER coordinates: pointInRect(px, py, cx, cy, w, h)
- checks: px in [cx-w/2, cx+w/2] and py in [cy-h/2, cy+h/2]
- ALWAYS store hit rects as {cx, cy, w, h} — passing corner coords silently halves the hit area

## Global Default Font (Main.lua, 2026-08-09)

```
GLOBAL_UI_FONT ("HelveticaNeue-BoldItalic") is set once per frame at the very top of
draw() (right after background(Color.bg), before any state routing) — the deliberate
ambient default for the whole app. Anything that draws text() WITHOUT its own font()
call inherits this automatically (Codea's font() state is global/persistent, not scoped
to a function unless wrapped in pushStyle()/popStyle()).

Origin: this exact font used to be ONLY on the not-yet-typed speech-balloon placeholder
(EndScreenFP.lua positionCommentField()) — and it LEAKED into everything drawn after it
each frame because that call site never wrapped font() in pushStyle()/popStyle(). The
leak was fixed (positionCommentField now pushStyle()-wraps its placeholder draw) and the
font was simultaneously promoted to a deliberate, permanent default instead — same visual
effect, but consistent from frame 1 rather than only after a composer first ran.

EXCEPTIONS (each pins its own font() explicitly, so GLOBAL_UI_FONT never reaches them):
  - HaikuMenu.lua (the whole main menu) — every text() call already had its own font()
    (Georgia/Georgia-Bold/Georgia-Italic/HelveticaNeue-Bold) before this change.
  - OverlayPanels.lua drawInfoOverlay() (About panel) — same, already fully explicit.
  - EndScreenFP.lua drawSpeechBalloon() — the ACTUAL balloon text once typed/submitted;
    already pushStyle()-wrapped with its own font("HelveticaNeue"), independent of this.
  - Dice/tile letters — GLOBAL_UI_FONT_DICE ("Helvetica", i.e. what they rendered as
    before this change existed — none of these ever had an explicit font() call, so
    "Helvetica" is Codea's own engine default, now pinned explicitly instead of left
    implicit): Board.lua drawBoard(), Helpers.lua drawBoardPreview() (end-screen board
    thumbnail), RecordsUI.lua drawBoardThumbnailFromTiles() (records-overlay match
    thumbnails).
Everything ELSE (HUD, word list, ready-screen "tap to start" message, records overlay
non-thumbnail text, alerts, GC overlays, etc.) inherits GLOBAL_UI_FONT — this was a
deliberate, broad decision, not an oversight; verify with a fresh screenshot (not just
code read) before assuming any specific screen kept its old look.
```

## Gameplay Board Layout (computeGridLayout, Board.lua)

```
computeGridLayout() returns tileSize, startX, startY, boardGap, bgSize (4th/5th values
  added 2026-08-08). Each tile is drawn at 95% of its cell (drawBoard: w*0.95,h*0.95 —
  halved from 90% same day, "halve the dice-to-dice gap too"), so the OUTERMOST tiles sit
  0.025*tileSize inside their cell edge before any panel padding — ignoring this factor
  entirely was a first-pass bug caught only by screenshotting + pixel-measuring the actual
  render (the two gaps LOOKED plausible from the formula alone but measured 25px outer vs
  34px inner on device at the original 90%/0.1 setting). Fix: visibleGridWidth =
  boardSize*tileSize - 0.05*tileSize (span from leftmost tile's visible left edge to
  rightmost tile's visible right edge — what the eye reads as "the letters"). boardGap =
  (WIDTH - visibleGridWidth) / 4, bgSize = visibleGridWidth + 2*boardGap.
  drawBoard()/drawReadyMessage() set bgW=bgH=bgSize verbatim (no re-derivation) — this makes
  screen↔panel and panel↔letters both equal boardGap, algebraically, for every boardSize,
  regardless of whether width or height constrained tileSize.
  Width budget for tileSize itself uses a separate constant boardEdgeGap=4 (computeGridLayout
  local, NOT the global sideMargin=40 used elsewhere for HUD margins; halved from 8 same day
  as the 95% tile scale — keep both in sync, they were a single "halve every board gap"
  request) — this is the MINIMUM gap target, used only to size the grid as large as possible;
  boardGap (actual, returned) can come out larger than 4 if height (not width) ends up the
  binding constraint. Verified on-device (6x6): outer/inner both 15px (was 29px pre-halving),
  dice-to-dice gap ~10px (was ~18-20px).
  drawReadyMessage() must read bgSize from computeGridLayout(), not recompute it — must stay
  numerically identical to drawBoard()'s panel size or the "tap to start" panel misplaces.
```

## Diagnostic Logging

| concern | file | detail |
|---|---|---|
| logging system | Main.lua ~49 | `devLog()`, `print = devLog`, ring buffer, `_flushLogBuffer()` |
| ring buffer key | Main.lua | `DevLogBuffer` in `saveLocalData`, JSON array of last 200 lines |
| system log access | CLI | `xcrun simctl spawn $SIM log show --last Ns --predicate 'process == "Quozzy"'` |
| plist access | CLI | `plutil -p <container>/Library/Preferences/<bundle-id>.plist \| grep DevLogBuffer` |

## Turn-Based Comment Speech Balloons (EndScreenFP.lua)

```
drawEndScreenSpeechBalloons(model, layout)  ← end-screen comment overlay
  guard: return unless model.commentUI.hasAnyComment
  reads model.commentUI = { hasAnyComment, showBalloons, opponentComment, localComment }
  per-balloon guard: draws opponent balloon only if opponentComment~="" (same for local)
                     → NO balloon renders for a nil/empty comment (skipped turn)
  opponent balloon = TOP (originator), local balloon = BOTTOM (responder, stacked below)
  colors: fill=Color.uiAccent, outline=Color.tileText (dark seasonal ink), text=Color.panelBG
  tail direction: anchored to avatarLayout from getEndUpperRightAvatarLayout (EndScreenFuncs.lua)
    opponent tail → avatarLayout.opponentX/Y ; local tail → avatarLayout.localX/Y
    avatar order (getEndUpperRightAvatarLayout): originator/opponent = LEFT+higher+bigger,
      responder/local = RIGHT+lower+smaller  (so the responder tail is rightmost)
    local tail base shifted +18 right → sits at first balloon's right end (least text overlap)
    ui.localTailUsesOpponentSlot (2026-07-19, drawEndScreenSpeechBalloons model.commentUI
      flag, default false — existing callers unaffected): BOTH avatars always draw
      regardless of this flag (getEndUpperRightAvatarLayout/drawEndUpperRightAvatarsOnly
      take no visibility args — an earlier version of this fix hid the opponent avatar
      when true, which was wrong; the avatar circles never change, only the tail does).
      When true, the LOCAL balloon's tail X uses avatarLayout.opponentX (no +18) — the
      same X the opponent balloon's tail uses — instead of avatarLayout.localX + 18; Y
      stays avatarLayout.localY (balloon still sits in the normal bottom slot). This is
      what makes mockup scenario 1 (initiator composing, nobody has spoken yet, so the
      lone balloon reads as the FIRST word) visually distinct from scenario 3 (opponent
      played but stayed silent — a real reply-shaped silence) even though both show one
      grey placeholder balloon.
  both tails: tailBaseWidth=18, outlineWidth=7, cornerRadius=16, tailLength 43*(2/3)(opp)/
    40*(2/3)(local) — shortened to 2/3 of the original 43/40 on 2026-07-20, applies to EVERY
    balloon (mockup and production alike, not scenario-gated — this one's a real renderer change)
  height: each balloon is sized to its wrapped text (measureSpeechBalloonText), capped at
    maxBalloonLines=3 (then ellipsized). Opponent is TOP-anchored (y=boardBottom-14-bH — same
    "14" offset as the solo-local fallback below, 2026-07-19, was "-4" and sat visibly higher
    than a solo balloon; unified so the topmost balloon lands at the same height whether it's
    alone or has a second balloon stacked under it) so it GROWS DOWNWARD; local's
    y=oppRect.y-localGap-bH (localGap = 14 + ui.localGapExtra, default extra 0) sits below
    opponent's bottom, so it moves DOWN as opponent grows and itself grows downward. No manual
    restacking needed. ui.localGapExtra (2026-07-19, tuned down twice same day after review:
    16 → 16/3 → 16/6): mockup scenario 2 sets 16/6 (≈16.7 total, barely more than the default
    14) so its centered, tail-less composer reads as visually separate from the opponent's real
    comment above it rather than nearly touching at the default 14. Scenario 6 (both commented,
    normal staggered/tailed layout, 2026-07-20) sets the SAME 16/6 for visual consistency —
    only the gap matches between the two scenarios, not centering or tail suppression.
  ui.oppBodyXNudge / ui.localBodyXNudge (2026-07-20, default 0 each): shifts that balloon's
    BODY rect.x only, exploratory-only so far (mockup scenario 6: opp -8, local +8 — tuned down
    from an initial -10/+10 same day, "pull each balloon 2px back from the edge it was
    overflowing"). Deliberately does NOT touch the tail: opponent's tailAnchorOverrideX stays
    avatarLayout.opponentX and local's stays localTailX, both computed independently of rect.x,
    so the tail tip stays exactly where it was — only the body slides under it.
  ui.localTailXNudge (2026-07-20, default 0): shifts ONLY the local balloon's tail X (added to
    localTailX above), independent of ui.localBodyXNudge which shifts the body. Mockup scenario
    6 sets -9 — half of tailBaseWidth (18) — moving the lower balloon's tail left of its normal
    avatarLayout.localX+18 anchor. Scenario 5 (solo local balloon, real text, otherwise
    centered/untouched) also sets -9 so its tail lands at the exact same X as scenario 6's
    lower balloon — same base formula + same nudge, so it's identical by construction, not a
    visual approximation.
  solo centering: when only ONE balloon is visible (comment~="" AND its show flag on), it is
    horizontally centered (x=panelX-bubbleW/2); both visible → staggered left/right. Tail stays
    put across the shift (base anchored to avatar X, which is inside the body either way).
    ui.centerBothBalloons (2026-07-19, default false): overrides the above so BOTH balloons use
      the centered X regardless of how many are shown — a no-op for solo cases (already
      centered), only changes the "both shown" case. Used by mockup scenario 2 so the
      opponent's real comment reads as centered/standalone rather than staggered against an
      empty composer.
  ui.suppressLocalTail (2026-07-19, drawEndScreenSpeechBalloons model.commentUI flag, default
    false): local balloon draws as a plain rounded rect with NO tail triangle at all (see
    drawSpeechBalloon opts.noTail below). Used by mockup scenario 2's composer balloon —
    paired with centerBothBalloons so it reads as a plain centered input box under the
    opponent's (real, tailed) comment, rather than a second speech bubble competing for the
    same avatar-pointing visual language.

drawSpeechBalloon(rect, text, tailAnchorX, tailAnchorY, tailSide, fill, outline, opts)  ← single balloon
  opts.lines (precomputed, already ≤maxLines) is used for drawing; opts.maxLines only feeds the
  fallback wrap when opts.lines is absent. wrapSpeechBalloonText(txt,w,fs,maxLines) caps + ellipsizes.
  opts.noTail (2026-07-19, default false): skips ALL tail geometry (fill triangle, border tail
    mesh, tip cap circle) — just the body rounded-rect (fill) + expanded rounded-rect (border)
    + text. tailAnchorX/Y and tailSide are ignored when set.
  FILL: sharp-point tail triangle (P1,P2,tip) + body rounded-rect
  BORDER: two outward-offset side strips (uniform perpendicular width, any lean)
          + line-cap circle (radius=outlineW) at the sharp tip  ← rounds ONLY the outline
          + expanded rounded-rect (cr+outlineW). Border drawn behind fill (rim = stroke).
  baseY overlaps INTO body (rect.y+rect.h-2 / rect.y+2) so tail+balloon fills merge (no seam)
  NOTE: fill point stays sharp; only outline is rounded. No fill cap circle (that read as a "ball").
```

### drawEndScreenSpeechBalloons — model.commentUI fields

```
Optional overrides (used by the mockup; backward-compatible — callers that set
none keep the original single-toggle, single-fade, both-balloons behavior):
  suppressText        → opponent balloon draws shape only (transparent text color)
  suppressLocalText   → same for the local/bottom balloon
  fillOverride        → replaces Color.uiAccent for BOTH balloon fills (legacy shared)
  strokeOverride      → replaces Color.tileText for BOTH balloon outlines (legacy shared)
  oppFillOverride / oppStrokeOverride     → per-balloon; win over the shared override
  localFillOverride / localStrokeOverride → per-balloon; win over the shared override
  showOpponent / showLocal (default true) → per-balloon visibility, gated by showBalloons.
    Each fades independently: opp uses endScreenSpeechBalloonAlpha, local uses
    endScreenLocalBalloonAlpha. Both rects are still COMPUTED even at alpha 0, so
    hiding one balloon does NOT reposition the other (stacking stays stable).
  localTailUsesOpponentSlot (default false) → local balloon's tail X uses avatarLayout.opponentX
    instead of avatarLayout.localX+18. See "tail direction" above.
  centerBothBalloons (default false) → both balloons use the centered X regardless of how many
    show, instead of staggering when both are visible. See "solo centering" above.
  suppressLocalTail (default false) → local balloon draws with NO tail at all (drawSpeechBalloon
    opts.noTail). See "both tails" above.
  localGapExtra (default 0) → extra px added to the 14px stacking gap below the opponent
    balloon. See "height" above.
  oppBodyXNudge / localBodyXNudge (default 0 each) → shifts that balloon's BODY rect.x only,
    tail unaffected (tail anchors are computed independently of rect.x). See "solo centering" above.
  localTailXNudge (default 0) → shifts ONLY the local balloon's tail X, independent of
    localBodyXNudge. See "tail direction" above.
  All of the above default to their no-op value, so existing/production callers that set none
  of them are unaffected — every one is currently exercised only by BALLOON_MOCKUP_STATES
  entries (EndScreenFP.lua), not by production's buildEndScreenModel().
Side effects: sets globals endScreenOppBalloonRect / endScreenLocalBalloonRect =
  each balloon's screen rect (or nil when its comment is empty) so callers can
  position a native view over it.
```

### Dev mockup = comment-entry prototype (menu 🐛 button)

```
Panel + board + avatars (2026-07-19): drawBalloonMockupOverlay() used to hand-roll its
  own drawRoundedRect panel and an avatar-only draw (no board preview), which drifted
  visually from the real end screen. Fixed by extracting drawEndScreenPanelBackground(layout)
  (sprite-or-fallback panel bg, used by both) and having the mockup call the SAME
  drawEndTopRowContent() the real end screen uses (draws board preview + avatars in one
  shot) instead of a partial reimplementation. useTurnBased is force-set true for the
  duration of that one call (then restored) since avatars are gated on it inside
  drawEndTopRowContent and comments are a turn-based-only feature anyway — this also
  means the mockup no longer draws the single-player score line (correct: production
  doesn't either, in the 2P state comments actually appear in). Board preview pulls tiles
  from currentQMatch.boardTiles, falling back to the live `board` global (still populated
  at STATE_MENU from the menu's own board preview) — so it renders even with no match loaded.
  Panel geometry (layout.panelX/Y/W/H) was ALREADY numerically identical between mockup and
  production (both read the same cached endScreenLayout) — the visual mismatch was the
  panel's fill style + missing board/avatar chrome, not the size.

7-state scenario picker (2026-07-19, replaced the old 4-button free-toggle design):
  the old "show/hide balloon 1", "show/hide balloon 2", "turn on/off text entry" buttons
  were three INDEPENDENT toggles — 8 combinations, several of which the real game never
  produces (e.g. both balloons simultaneously grey/placeholder — the opponent balloon is
  NEVER live-typed or grey in production, it's only ever absent or an already-submitted
  themed comment). Replaced with BALLOON_MOCKUP_STATES, a fixed array of the 7 actual
  situations the end screen can be in (see "Turn-Based Comment Speech Balloons" above for
  the states themselves). Each entry is a COMPLETE valid snapshot (opponentComment string
  or nil, localComposing bool, localComment string or nil, plus optional per-entry overrides:
  placeholder (composer placeholder text, default "tap here to comment" (2026-08-09; was
  "tap to comment on this match") — scenario 2 uses "tap to reply"), localTailUsesOpponentSlot, centerBothBalloons, suppressLocalTail,
  localGapExtra — see drawEndScreenSpeechBalloons above for what each does) — picking one
  can't land on an impossible combination by construction. mockupScenarioIndex (global, 1-7) selects the
  active entry; drawn as 7 small numbered chips (mockupChipRects, direct-jump, not
  prev/next) so QA can A/B any two states in one tap each, plus a caption showing the
  active entry's label. Only entries with localComposing=true ever create/show the native
  UITextView (commentFields[2]) — historical entries (4/5/6) just pass canned text through
  suppressLocalText=false so the renderer draws it exactly like an already-submitted
  comment in production. commentFields[1] (opponent) is fully unused now — the opponent
  balloon is always plain model text via drawEndScreenSpeechBalloons, never a live field.

  scn.activeOverrides (2026-07-20, scenario 2 only): once real text has been typed into the
    composer (localDraft ~= "", not just focus), scenario 2's layout fields (suppressLocalTail,
    centerBothBalloons, oppBodyXNudge, localBodyXNudge, localTailXNudge) are swapped for the
    override table's values — currently set to exactly scenario 6's values, so the composer
    visibly "becomes" a real reply (tail back, both balloons shift to the staggered
    positions) the moment you type something. This is purely a function of the CURRENT
    frame's text content (drawBalloonMockupOverlay computes `eff` fresh every frame from
    scn's base fields, then overlays activeOverrides only if hasComment) — there's no
    separate "was previously typed" state to track, so clearing the field back to empty
    reverts automatically on the very next frame, the same code path as never having typed
    anything. Implemented via a local `eff` table (the merged/effective values) that the
    model construction reads instead of scn directly for those 5 fields.

drawBalloonMockupOverlay()  [EndScreenFP.lua] — REUSES drawEndScreenSpeechBalloons.
  real endScreenLayout (ensureEndScreenLayout is screen-size-only, safe on menu)
  + placeholder avatars (drawEndUpperRightAvatarsOnly, genericOpponentAvatar), same as
  production (see panel/board/avatar note above).

  For composing entries the local balloon has two visual states (active = the field is
  focused OR has text): OFF/placeholder = fill=light gray (214) opaque, outline=(168)
  opaque via localFillOverride/localStrokeOverride, shape-only with a Codea-drawn
  placeholder (Color.tileText @ 80%, bold italic) behind the empty view; ON/active =
  normal seasonal colors, the UITextView shows the typed text (Color.panelBG).

  Native UITextView (commentFields[2] — slot 3 is the production composer, see
    "Production Comment Composer" section below; slot 1 is unused, see above) shows the
    VISIBLE multi-line text with a real caret (a UITextField can't wrap). The balloon is
    drawn SHAPE-ONLY (suppressLocalText=true) while composing and sized to the typed
    text, so the shape grows to fit.
    - font = balloonFontSize (layout.cardHeaderH*0.44, matches the renderer) so native
      wrapping ≈ the balloon's measured wrapping → the shape fits the text; lineFragmentPadding=0
    - 3-LINE HARD CAP (enforceCommentFieldLineCap, runs in draw(), shared with production):
      each frame it re-measures the field text with wrapSpeechBalloonText(text, panelW-42,
      balloonFontSize); if it would wrap to a 4th line, tv.text is reverted to the field's
      last ≤3-line value (F.lastValid) — so a 4th line is blocked. ALSO blocks a near-full
      3rd line: when the wrap is exactly 3 lines and the last line's width is within ~5
      chars (textSize("nnnnn")) of wrapWidth, it is treated as overflow too. The native
      UITextView wraps slightly differently than this Lua measure, so a 3rd line filled to
      the edge (e.g. after adding an ellipsis) could sneak to a 4th line in the view while
      this check still counted 3; the 5-char margin keeps them in sync.
      On block F.flash is set to 0.22s, which turns the native text RED
      (color 224,48,48) until it decays. (scrollEnabled=true is left on but mostly moot now that
      input is capped.) Return-to-dismiss is also handled here: any "\n" stripped + resignFirstResponder
      (does NOT submit/close anything — see "Production Comment Composer" below).
    - ObjC-callback safety: the UITextViewDelegate callbacks (textViewDidBegin/EndEditing_) ONLY
      set the Lua F.focused flag. ALL UITextView mutation (text revert, newline strip,
      resignFirstResponder) is done in draw() via enforceCommentFieldLineCap — never from a
      callback (calling UIKit/Codea from an objc callback can crash the draw cycle). Params are
      type-prefixed (oTV). ONE shared delegate; dispatches per view via tv.tag (=2/3 now).
    - host view = objc.viewer.view.subviews[1]; frame via codeaToUIKitRect (y-flip), re-set
      each frame from the (growing) balloon rect
    - ASSIGN Codea color() DIRECTLY to UIColor props (tv.textColor/backgroundColor);
      objc.UIColor:colorWithRed_green_blue_alpha_ was unreliable for textColor here
    - no keyboard avoidance needed (balloons sit high; keyboard covers the bottom)
    - teardownMockupTextField() (global) called from Main.lua on close tears down slot 2 only
    - UITextView top-aligns its text (vs the renderer centering) — negligible while the shape
      is sized to the text; only shows as a little bottom slack at the balloon min-height

  Bottom controls (rects stored as globals, handled in Main.lua touched()):
    7 chips (mockupChipRects[1..7]) → mockupScenarioIndex = tapped index (direct-jump)
    "close debug screen" (mockupCloseBtnRect) → dismiss (teardown + balloonMockupOverlay=false)
    Tap-anywhere-to-dismiss was REMOVED; only "close debug screen" dismisses the OVERLAY.
    Tap-outside-to-unfocus (2026-07-20): any tap that isn't a chip or the close button, while
      commentFields[2].focused is true, calls tv:resignFirstResponder_() directly — same
      effect as hitting Return in enforceCommentFieldLineCap (unfocus only, doesn't submit or
      close anything). Safe to call directly here since touched() is a normal Codea callback,
      not an objc delegate callback (the "never call UIKit from an objc callback" rule doesn't
      apply). The native UITextView already eats its own taps via UIKit hit-testing before
      touched() ever sees them, so reaching this branch already means the tap landed outside
      the field's frame (br inset by 6px, so a tap in that 6px margin also unfocuses).

  Gating: BALLOON_MOCKUP_DEV (auto-opens at launch + forces Summer/teal palette + skips
    CTBM/GameCenter bootstrap so no GC modal over QA; FALSE in production, Main.lua:~114)
    and balloonMockupOverlay (menu 🐛 button, HaikuMenu key=="debugDialog", live season).
  SHOW_DEBUG_BUTTON (Main.lua:~115, FALSE in production): gates the 🐛 button itself — when
    false, HaikuMenu.lua never draws it and never sets menuHitRects.debugDialog, so it can't
    be tapped even by coordinate. Added 2026-08-08 for shipping: the button previously drew
    unconditionally on the live main menu with no flag at all. Flip to true locally for QA.
  (old interactive tuner DebugBalloonPanel.lua was DELETED — removed from Info.plist Buffer Order)
```

| concern | file | function |
|---|---|---|
| comment balloons draw | EndScreenFP.lua | drawEndScreenSpeechBalloons(), drawSpeechBalloon() |
| balloon dev mockup | EndScreenFP.lua | drawBalloonMockupOverlay() (menu 🐛 / BALLOON_MOCKUP_DEV) |
| end-screen avatar layout | EndScreenFuncs.lua | getEndUpperRightAvatarLayout(), drawEndUpperRightAvatarsOnly() |

## Production Comment Composer + End-Screen Rematch Button (2026-07-15)

```
The OLD single-line UITextField composer (sat over layout.playAgainRect, tap-to-focus
via Lua rect check, Return-to-submit) was REPLACED by a UITextView embedded directly
in the local player's speech balloon.

IMPORTANT (2026-07-15 correction): the first pass at this reimplemented the mockup's
field logic in parallel (its own ensure/update functions) instead of reusing it, and
the reimplementation silently dropped the placeholder-draw call and diverged in other
small ways — invisible "tap to comment" text, misaligned content. Fixed by GENERALIZING
the mockup's own functions in place and having BOTH the mockup and production call the
identical code — not two versions of the same logic. If this composer needs further
changes, edit the SHARED functions below; do not add a third parallel implementation.

commentFields (global table, [i] = {tv, focused, flash, lastValid}) [EndScreenFP.lua,
  right before drawBalloonMockupOverlay — must be after wrapSpeechBalloonText, which
  enforceCommentFieldLineCap calls]
  Slots 1/2 = dev mockup (opponent/local). Slot 3 = production end-screen local composer.
  Declared as a plain global (no `local`) specifically so teardownEndScreenCommentField()
  — defined earlier in the file, called cross-tab from EndScreen.lua — can reach it
  despite textual ordering (Codea cross-tab global pattern: locals are chunk-scoped,
  globals resolve at runtime regardless of definition order).

  Shared functions (all take a slot index `i`, so one code path serves every caller):
    ensureCommentFieldDelegate() / ensureCommentField(i, fontSize) — creates the UITextView
    updateCommentField(i, rect, shown, fontSize, textEntryEnabled) — shows/hides/positions
    enforceCommentFieldLineCap(i, fontSizeValue, wrapWidth) — 3-line hard cap + red flash
      (RETURN KEY: strips itself + resigns first responder ONLY — does NOT submit or close
      the end screen; changed 2026-07-15, previously Return == commit-and-exit)
    positionCommentField(i, balloonRect, shownFlag, activeFlag, placeholderText,
      fontSizeValue, textEntryEnabled, setHitRect) — positions the field AND draws the
      Codea placeholder (bold italic, tileText@80%, dead-centered) behind it when inactive
    teardownMockupTextField() — tears down ONLY slots 1/2 (loop is `for i=1,2`, not
      `#commentFields`, so it never touches slot 3)
    teardownEndScreenCommentField() — tears down ONLY slot 3

  Production entry points (called from drawEndScreenFP/drawEndScreenWith):
    enforceEndScreenCommentDraft(layout) — must run BEFORE buildEndScreenModel() so this
      frame's typed text feeds this frame's balloon sizing, not next frame's (the mockup
      avoids this ordering issue by doing enforce→build-model→draw inline in one function;
      production splits across drawEndScreenFP/drawEndScreenWith so needs the explicit split)
    positionEndScreenCommentField(model, layout) — called after drawEndScreenSpeechBalloons
      (needs endScreenLocalBalloonRect, which that call sets as a side effect)
    Both gated on `useTurnBased and not endScreenCommentFieldTornDown` — single-player end
    screens never touch slot 3 at all (no wasted UITextView creation).

buildEndScreenModel() commentUI, while composing (canComposeComment==true):
  localComment  = live draft (endScreenCommentDraft) or placeholder text (so the balloon
                  renders/grows even before any text exists)
  suppressLocalText = true (native UITextView draws the real text on top)
  localFillOverride/localStrokeOverride = grey "off" colors until focused or has text
                  (composingActive = commentFields[3].focused or draft~="")
  Once submitted, canComposeComment goes false and the SAME balloon flips back to normal
  rendering of the real persisted pLocal.comment — no separate code path.

  Also fixed here: commentInfo.isResponderTurn (referenced by the old placeholder-text
  ternary) never actually existed on currentFinalCommentPhase()'s return table — it returns
  `opponentPlayed`. Placeholder logic now reads commentInfo.opponentPlayed correctly.

  placeholderText derivation (2026-08-09 fix): commentInfo.opponentPlayed alone is NOT
  enough to justify "Add a reply to their comment" — the opponent may have played their
  turn and left NO comment, in which case there's nothing to reply to. Now gated on
  `commentInfo.opponentPlayed and opponentComment ~= ""` (hasOpponentComment); anything
  else (including the initiator's very first comment, and a responder whose opponent
  stayed silent) gets the generic "tap here to comment" instead.

BALLOON VISIBILITY TOGGLE (endScreenSpeechBalloonsVisible, EndScreen.lua): tapping
  g.topToggleRect (the avatar/board/message row, above where balloons render) OR tapping
  directly on a non-editable balloon toggles all balloons show/hide. "Non-editable" =
  the opponent balloon always, or the local balloon whenever it ISN'T the live composer
  (a live composer's native UITextView intercepts its own taps via normal UIKit hit-testing
  before they ever reach Codea's touched(), so no explicit exclusion code is needed beyond
  checking shouldShowFinalCommentComposer()). Gated on endScreenHasVisibleBalloons() (true
  once composing OR once either player has a persisted comment) so tapping does nothing
  when there's nothing to toggle.
  DELIBERATELY NOT reproduced in the debug mockup (2026-07-20 decision): this handler
  (handleEndScreenTouch) lives entirely inside the STATE_END-gated production touch path;
  drawBalloonMockupOverlay's touched() branch is a separate early-return block that has
  never called into it, before or after the 7-state picker rework. It gets real coverage
  from any actual 2P match reaching the end screen with comments, so there's no gap to
  backfill — and doing so in the mockup would mean either a second parallel implementation
  (the exact anti-pattern the 2026-07-15 composer fix above was written to avoid) or wiring
  the mockup into currentQMatch/STATE_END machinery it deliberately doesn't carry.

REMATCH BUTTON (occupies layout.playAgainRect, now freed since the composer moved into
the balloon): shown when is2P && complete && assignedOpponent (model.rematch.canOffer).
  offerEndScreenRematch() [EndScreenFP.lua] → force-persists replay settings from
  currentQMatch (so getLastMatchReplaySettings() can't be stale/from a different match)
  → confirmRematchAgainstLastOpponent(onConfirmed) [Main.lua, shared with the menu's "re"
  button — same message/avatar/record wording] → on "heck yeah": sets
  pendingRematchAfterEndScreenExit=true, then disposeEndScreenAndReturnToMenu()
  [EndScreen.lua — extracted from the old × handler, shared by both].

  RACE AVOIDED: startLastMatchReplayFromMenu() (the async GC matchmaking call) is NOT
  fired immediately on confirm. updateSeasonTransition() [ConfettiEffectsEtc.lua]
  unconditionally sets state=STATE_MENU ~0.7s after startSeasonTransition() — if
  matchmaking's enterQMatch() callback landed AFTER that but a naive implementation had
  already forced state=STATE_READY/PLAY, the transition's own completion would stomp it
  back to STATE_MENU underneath the freshly-started match. Fix: pendingRematchAfterEndScreenExit
  is only consumed (calling startLastMatchReplayFromMenu()) INSIDE updateSeasonTransition()
  right after it sets state=STATE_MENU — guaranteeing matchmaking never starts until the
  transition has fully settled. Same guard-flag pattern as the STATE_END transition trap.

GENERIC ALERT IS NOW STATE-INDEPENDENT (was menu-only): showGenericAlert()/drawGenericAlert()
used to only be drawn/hit-tested from inside drawMenu()/handleMenuTouch() (STATE_MENU only)
— calling it from STATE_END silently did nothing. Fixed by moving drawGenericAlert() to
Main.lua draw() (called from both the STATE_MENU branch and the shared tail for other
states) and extracting the touch-eating block into handleGenericAlertTouch() [HaikuMenu.lua],
now called from Main.lua touched() BEFORE state routing (same tier as colorInspectorOverlay/
showInfoOverlay). Required because the rematch confirmation dialog needs to work from the
end screen, not just the menu.
```

| concern | file | function |
|---|---|---|
| comment field mechanics (shared: mockup slots 1/2 + production slot 3) | EndScreenFP.lua | ensureCommentField(), updateCommentField(), enforceCommentFieldLineCap(), positionCommentField() |
| production composer entry points | EndScreenFP.lua | enforceEndScreenCommentDraft(), positionEndScreenCommentField() |
| end-screen rematch button | EndScreenFP.lua | offerEndScreenRematch() |
| rematch confirm dialog (shared) | Main.lua | confirmRematchAgainstLastOpponent() |
| end-screen disposal (shared by × and rematch) | EndScreen.lua | disposeEndScreenAndReturnToMenu() |
| deferred rematch trigger | ConfettiEffectsEtc.lua | updateSeasonTransition() — pendingRematchAfterEndScreenExit |
| generic alert touch (state-independent) | HaikuMenu.lua | handleGenericAlertTouch() |
| balloon visibility toggle (tap above/on balloon) | EndScreen.lua | endScreenHasVisibleBalloons(), handleEndScreenTouch() |
