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
