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
  both tails: tailBaseWidth=18, outlineWidth=7, cornerRadius=16, tailLength 43(opp)/40(local)

drawSpeechBalloon(rect, text, tailAnchorX, tailAnchorY, tailSide, fill, outline, opts)  ← single balloon
  FILL: sharp-point tail triangle (P1,P2,tip) + body rounded-rect
  BORDER: two outward-offset side strips (uniform perpendicular width, any lean)
          + line-cap circle (radius=outlineW) at the sharp tip  ← rounds ONLY the outline
          + expanded rounded-rect (cr+outlineW). Border drawn behind fill (rim = stroke).
  baseY overlaps INTO body (rect.y+rect.h-2 / rect.y+2) so tail+balloon fills merge (no seam)
  NOTE: fill point stays sharp; only outline is rounded. No fill cap circle (that read as a "ball").
```

### drawEndScreenSpeechBalloons — model.commentUI fields

```
Optional overrides (used by the mockup; backward-compatible):
  suppressText    → opponent balloon draws shape only (transparent text color)
  fillOverride    → replaces Color.uiAccent for the balloon fill
  strokeOverride  → replaces Color.tileText for the balloon outline
Side effect: sets global endScreenOppBalloonRect = the opponent balloon's screen rect
  (or nil when not drawn) so callers can position a native view over it.
```

### Dev mockup = comment-entry prototype (menu 🐛 button)

```
drawBalloonMockupOverlay()  [EndScreenFP.lua] — REUSES drawEndScreenSpeechBalloons.
  Shows ONE balloon (first speaker / opponent slot) with a native UITextField inside
  for real typing. Placeholder text: "tap to comment on this match".
  real endScreenLayout (ensureEndScreenLayout is screen-size-only, safe on menu)
  + placeholder avatars (drawEndUpperRightAvatarsOnly, genericOpponentAvatar)

  Two visual states (active = field focused OR field has text):
    OFF/placeholder: balloon fill=light gray (214) opaque, outline=(168) opaque;
      Codea-drawn placeholder = Color.tileText @ 80% alpha, bold italic. suppressText hides
      the balloon's own text; the transparent field lets the Codea placeholder show through.
    ON/active: normal seasonal balloon colors; native typed text in Color.panelBG.
    Deselecting an empty field returns to OFF; with text it stays ON.

  Native UITextField (mockupTextField, transparent) — create/position/show-hide/teardown
    modeled on the end-screen comment field (ensureEndScreenNativeCommentField):
    - host view = objc.viewer.view.subviews[1]; frame via codeaToUIKitRect (y-flip)
    - ASSIGN Codea color() DIRECTLY to UIColor props (tf.textColor/backgroundColor);
      objc.UIColor:colorWithRed_green_blue_alpha_ was unreliable for textColor here
    - no keyboard avoidance needed (balloon sits high; keyboard covers the bottom)
    - teardownMockupTextField() (global) called from Main.lua on close

  Three bottom buttons (rects stored as globals, handled in Main.lua touched()):
    "show/hide"              → mockupBalloonShown  (hides balloon + field)
    "turn on/off text entry" → mockupTextEntryEnabled (tf.userInteractionEnabled)
    "close debug screen"     → dismiss (teardown + balloonMockupOverlay=false)
    Tap-anywhere-to-dismiss was REMOVED; only "close debug screen" dismisses.

  Gating: BALLOON_MOCKUP_DEV (auto-opens at launch + forces Summer/teal palette + skips
    CTBM/GameCenter bootstrap so no GC modal over QA; FALSE in production, Main.lua:~114)
    and balloonMockupOverlay (menu 🐛 button, HaikuMenu key=="debugDialog", live season).
  (old interactive tuner DebugBalloonPanel.lua was DELETED — removed from Info.plist Buffer Order)
```

| concern | file | function |
|---|---|---|
| comment balloons draw | EndScreenFP.lua | drawEndScreenSpeechBalloons(), drawSpeechBalloon() |
| balloon dev mockup | EndScreenFP.lua | drawBalloonMockupOverlay() (menu 🐛 / BALLOON_MOCKUP_DEV) |
| end-screen avatar layout | EndScreenFuncs.lua | getEndUpperRightAvatarLayout(), drawEndUpperRightAvatarsOnly() |
