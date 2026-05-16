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

## Versus Button Flow

```
HaikuMenu.lua: handleMenuButtonTap() key=="versus"
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
| versus tap | HaikuMenu.lua | handleMenuButtonTap() key=="versus" |
| play again tap | HaikuMenu.lua | handleMenuButtonTap() key=="playAgain" |
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

## pointInRect

- Helpers.lua:24 — expects CENTER coordinates: pointInRect(px, py, cx, cy, w, h)
- checks: px in [cx-w/2, cx+w/2] and py in [cy-h/2, cy+h/2]
- ALWAYS store hit rects as {cx, cy, w, h} — passing corner coords silently halves the hit area
