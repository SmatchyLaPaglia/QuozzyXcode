# Multiplayer Turn Relay — Design (2-player)

The agreed design for how a 2-player GameKit turn-based match moves between
devices so that **both players can play at the same time**, **nobody's result is
lost if they close the app**, and **both players still get to comment**.

Source: Jesse's decisions in the "Vivaldi-ku" Claude Code session, 2026-09-23
(17:07–19:10). This doc is the spec. `MULTIPLAYER_TEST_PLAN.md` was written
against a different version (see "Current code vs. this design" below) and needs
updating to match before it's used.

## The one hard constraint

GameKit only lets the **current turn holder** write match data, pass the turn, or
end the match. A device that doesn't hold the turn can only save locally and wait.
Everything below is shaped by that.

## Rules

1. **Handshake at creation.** When P1 creates a match, the board goes to P2
   immediately — before P1 even sees the ready screen. From then on both players
   can start playing whenever they want, regardless of who holds the turn.
2. **Scores go out immediately.** The instant a player's round ends — *before*
   their end screen appears — their score is sent if they hold the turn. If they
   don't hold it, the score is saved to disk at once and sent the moment the turn
   arrives. A score never waits on a comment.
   > "As soon as they finish, their match gets sent back to player one before
   > player two even sees the end screen." / "Leg 3 has to immediately return the
   > P1 score."
3. **Comments travel separately, later.** A locked comment (text, or blank) goes
   out on a later send by whichever player holds the turn. If the player doesn't
   hold the turn when it locks, it's cached on disk and sent the next time their
   device holds the turn.
   > "If their comment isn't ready, that means at some point the turn needs to
   > return to them to see if they made one."
4. **One comment per player, locked after seeing the full result.** A player can
   type and edit their comment any time — including on the "waiting" screen —
   until they **close the end screen showing both scores**, or **press enter in
   the comment balloon on that screen**. Then it's locked for good. Closing with
   the balloon empty locks a blank comment.
   - Last finisher: that screen is the one right after their round.
   - First finisher: it's when they open the match themselves (from the "game
     ended" badge) after the second score arrives.
   - Closing the "waiting" screen (only one score in) locks nothing.
   - A send never fires while the player's comment balloon is open; it waits
     until the comment locks.
5. **Two gates.**
   - **Gate 1 — the players see the match as over** once both scores are on their
     device (and they've had a chance to see the result). Drives the end screen.
     Never depends on GameKit's match state.
   - **Gate 2 — GameKit sees the match as over** only once both players have had
     their chance to comment (decided, blank or not). Only then does the holder
     call `localPlayerWon/Lost/Tied`.
6. **24-hour comment clock, on the turn holder only after the match is over for
   players.** The send that delivers the **second score** passes the turn with a
   24-hour GameKit `turnTimeout`; so does each comment send that passes the turn.
   Unfinished matches get no special timeout — leave GameKit's own policy alone
   for every other send.
   - When the clock runs out, GameKit moves the turn to the other player. That
     device, next time the app runs, records the silent player's comment as blank
     and **ends the match** (or, if its own comment isn't locked yet, waits for
     it as usual).
   - The silent player's device, on its next run, sees it no longer holds the
     turn and locks its comment box — that comment can no longer be sent.
   - Accepted consequence: a player whose comment is locked but still cached
     (they didn't hold the turn when it locked) loses it if they don't open the
     app within 24 hours of the turn being sent back to them. GameKit gives no
     way to send it sooner.
   - The clock always counts from the moment of the **send**, set by the sender
     via `turnTimeout` — never from when the receiver's app notices the turn.
   - Accepted: if both players go silent the match stays open in GameKit. Players
     already see it as finished, so nothing visible is wrong.
7. **The UI never shows Game Center's view of the match.** The gap between "over
   for players" (gate 1) and "over for GameKit" (gate 2) is invisible to them.
8. **Incoming turns are handled in the background.** A player never lands in a
   game session or end screen they didn't open themselves. When a turn arrives,
   the app merges the data, sends whatever this device owes, and updates badges —
   without changing screens.

## The sequence

P1 = creator, P2 = invitee. "→" is a turn send; the turn moves with it.

**Leg 1 — handshake.** P1 → P2: board only. Turn: P2.

**Legs 2–3 — scores** (order depends on who finishes first):

| P2 finishes first | P1 finishes first |
|---|---|
| P2 holds the turn, so the moment P2's round ends: **P2 → P1, P2's score.** | P1 doesn't hold the turn: P1's score is saved locally and waits. |
| P1 plays whenever; the moment P1's round ends: **P1 → P2, P1's score.** | The moment P2's round ends: **P2 → P1, P2's score.** |
| | The moment the turn reaches P1's device (when P1's app next runs): **P1 → P2, P1's score.** Until then P2 waits, with no timeout — P1's score exists only on P1's device. |

Leg 3 delivers the second score: **gate 1 is open for both players**, the turn is
with P2, and **P2's 24-hour comment clock starts.**

**Legs 4+ — comments.** Whoever holds the turn:
- has a newly locked comment and the other player's isn't in the match data yet
  → **sends it and passes the turn** (24-hour clock on the receiver);
- has a newly locked comment and the other player's is already in → **ends the
  match** (gate 2) instead of passing, carrying both comments;
- hasn't locked their comment yet → **keeps the turn** until they do or time out.

Typical case: handshake, score, score, comment, end = 5 sends. It always
terminates because each send carries something new and each player locks
exactly one comment.

## Badges and notifications (from the same session)

- Two badges: **game ended** (gate 1 reached, not yet seen) and **opponent
  commented**. Both appear on the match in the vs list and in Records.
- Hide any Game Center badge or notification that duplicates something the player
  has already been shown — the silent comment/relay sends must not light up the
  home-screen badge.

- A comment arriving after the player has seen the result never reopens the end
  screen; it shows the "opponent commented" badge (rule 8).

## Decisions log (2026-10-07)

- Comment clock starts on the second-score send, not on round end; GameKit
  `turnTimeout` passes the turn back when it expires (rule 6).
- Leave GameKit's timeout policy alone for unfinished matches.
- Backgrounding the app does not lock a comment; only closing the full-result
  screen or pressing enter in its balloon does (rule 4).
- One comment per player, editable until it locks (rule 4).
- Late comments → badge, never an automatic screen change (rule 8).
- The 24h clock stays (rule 6): needed so a silent player can't leave the match
  open in Game Center forever, and so Game Center ends up with the correct
  won/lost result. It counts from the moment of the send, not receipt.
- `MULTIPLAYER_TEST_PLAN.md` describes the bundled score+comment version; it is
  to be rewritten (or deleted) to match this design before the code is changed.
- ~~Code to delete/replace: `COMMENT_WINDOW_SECONDS` / `applyCommentTimeoutIfExpired`
  self-enforced timeout~~ — **superseded, see "Decision" below (2026-10-08):** the
  2026-10-07 plan assumed GameKit's own `turnTimeout` would replace this. The
  exchange trial showed `turnTimeout` doesn't observably work, so this
  self-enforced code is **kept**, not deleted. The `enterQMatch` jump on an
  incoming turn (`tbm:onReceivingTurn` in `Main.lua`) should still change to a
  background-only send, independent of this.

**Proposed, NOT confirmed by Jesse:** update the local win/loss record the moment
both scores are in (today it only updates when the match ends in Game Center via
`finalizeCompletedTurnBasedMatch`, so a never-commenting opponent means the win
never counts). Also unconfirmed: posting a win total to a classic Game Center
leaderboard (permanent; one number per player) as a separate feature.

## Still to verify on device

- What the current `turnTimeout` of `0` in `CTBM:endTurn…`
  (`CodeaTurnBasedMatches.lua`) actually means to GameKit, and that a 24-hour
  (and a short debug) `turnTimeout` really moves the turn when it expires.

## Current code vs. this design (as of 2026-10-07, branch `merge-laptop-work`)

Implemented in `642c99a` and kept through the laptop merge, but built on a
version of the design Claude substituted during implementation:

| Design | Current code |
|---|---|
| Score sent the instant the round ends | Score waits until the player closes the end screen; `computeNextOwedLeg` (`qMatch_qPlayer.lua`) requires `didPlay` **and** `commentDecided`, so score and comment always go out together |
| Comment on a separate later leg | No separate comment leg (at most 3 sends total) |
| Whoever opens the app after 24h ends the match | 24h window exists (`COMMENT_WINDOW_SECONDS`, `applyCommentTimeoutIfExpired`) but only the silent player's own device checks it — if they never reopen, the match never ends |
| Handshake before P1's ready screen | Handshake fires from `enterQMatch` while the ready screen is up; P1 can start without waiting for it |
| Comment locks on closing the full-result screen | Comment locks on closing the end screen, whether or not both scores are in |
| 24h `turnTimeout` on the second-score and comment sends | Every send passes `turnTimeout` `0` |
| Incoming turns handled in the background | `tbm:onReceivingTurn` (`Main.lua`) calls `enterQMatch`, which jumps the player into the match — and is also what triggers the automatic send |

Reusable as-is: the pending-send queue with retry and disk persistence
(`attemptLegSend`, `pendingTurnSendsByMatchId`, `finishedAwaitingDecisionByMatchId`),
the `STATE_END` merge-guard in `enterQMatch`, `decideComment`, and the
foreground retry sweep (`retryPendingHandshakeSends`).

## Later: 3+ players (decided 2026-09-24, not started)

Build only after the 2-player version works on real devices.

- Points leaderboard (1st/2nd/3rd…), no win/lose wording; 1st places not tallied.
- A word found by 2+ players is crossed out for all of them.
- Turn flow is a relay ring P1→P2→P3→P4; each hop automatic. "Both" in the gates
  becomes "all".
- iOS Messages-style avatar cluster wherever opponent avatars appear; comment
  balloons labeled "Handle: text", scrollable, tails alternating left/right;
  in-game header reads "Opponent: Multiple".
- Multi-select opponent picker built on the existing `MatchSelection.lua` friend
  list (Files-app-style selection circles).
- Each exact set of opponents gets its own record; doesn't count toward
  head-to-head records.
- Mockups: https://claude.ai/artifact/12caW8uMRzhmKxRu8y6PVb (picker drawn before
  the laptop merge — reconcile with the real `MatchSelection.lua` screen).

## GameKit exchange trial — complete (2026-10-08)

**Why:** a comment locked while not holding the turn waits on the phone and can be
lost to the 24h clock. GameKit *exchanges* (`sendExchange…`) let a player without
the turn send data to the match immediately; the turn holder merges it
(`saveMergedMatchData`) before passing the turn or ending the match (Apple: an
unmerged completed exchange makes endTurn/endMatch error). If exchanges work, a
comment can leave the phone the moment it locks, the turn only needs to move for
scores, and the comment-loss problem goes away.

**Harness:** `tools/xchg_trial.lua` — load with
`tools/dbg.sh -f tools/xchg_trial.lua` (or `DBG_SIM=<udid>` for a simulator), then
call `XT.muteApp()`, `XT.findB(alias)`, `XT.create()`, `XT.acceptById(matchID)`,
`XT.passTurn(seconds)`, `XT.sendEx(seconds)`, `XT.reply()`, `XT.merge()`,
`XT.saveTurn()`, `XT.endMatch(myOutcome, otherOutcome)`, `XT.reload()`,
`XT.describe()`, `XT.dump()`. Callbacks only record to `XT.log` (no Codea work in
objc callbacks). **Always `XT.reload()` immediately before any turn-affecting call**
(`passTurn`/`endMatch`) — a stale local match object fails with "the specified
participant does not have the required turn state" (code 23), a harness artifact
seen repeatedly tonight, not a GameKit behavior. The same staleness risk applies to
`tbm.currentMatch` in the real app, not just this harness.

**Run on real hardware** (iPad "Jesse on iPad of Rosie" = Gnostic Pan, iPhone XR
= GameySonata, both physically connected, both already signed in — no simulator
involved this time):

- **Confirmed working, adopt into the design:**
  - `acceptInviteWithCompletionHandler_` accepts an invite with zero system UI —
    confirmed end to end (invite created on one device, accepted on the other,
    both ways verified via a from-scratch reload showing both participants
    `status=Active`).
  - A non-turn-holder sending an exchange works on a fully **accepted** (not just
    invited) participant — resolves the open question from the earlier
    simulator-only trial.
  - Exchange reply → completion is real and visible on both sides, exactly per
    Apple's docs: the turn holder's `completedExchanges` populates (count 1) once
    the recipient replies; the *sender's* `completedExchanges` correctly stays
    empty (that list is turn-holder-only, per Apple's header comment) but the
    sender's own `exchanges` array shows `replies=1`, which is the practical
    signal a sender needs.
  - `saveMergedMatchData:withResolvedExchanges:` works — merged data lands in
    `matchData`, the resolved exchange disappears from the match entirely.
  - `endMatchInTurnWithMatchData:` is genuinely **blocked** while a completed
    exchange sits unmerged — confirmed via a real error (code 3, generic "error
    communicating with the server" — not a specific/identifiable error code, so
    the real implementation must proactively check for unresolved exchanges
    before calling end, not rely on catching a distinguishable error).
  - `saveCurrentTurnWithMatchData:` writes data without ending the turn, confirmed.

- **Confirmed NOT working — do not rely on this:**
  - **`turnTimeout` does not produce an observable `timeoutDate`, at any value.**
    Tried 65 (int), 65.0 (float, to rule out a Lua integer/float bridging bug),
    and 86400 (24h, the design's real intended value) — `timeoutDate` read back
    `nil` every time, immediately and on every subsequent reload.
  - **The turn did not auto-transfer back after the timeout window elapsed.**
    Passed a 65s timeout, waited a full 2 minutes past it (well past the window),
    reloaded repeatedly — `currentParticipant` never moved. One full real-time
    trial was run to completion; the `nil` `timeoutDate` symptom was independently
    reproduced 3 more times across different values without a further full wait.
  - This directly answers the open "still to verify" item from the first trial
    commit: the production code's `turnTimeout` of `0` isn't silently broken
    relative to some working nonzero value — **nonzero values don't work either**,
    at least not via this objc bridge call path, on real hardware, in this GameKit
    environment. Root cause (bridge marshaling bug vs. a GameKit/account-type
    limitation) is not established — only the practical result is.
  - **`matchOutcome` cannot be pre-staged.** Setting `p.matchOutcome` in Lua and
    calling `saveCurrentTurnWithMatchData:` (which takes no participant array)
    does not persist the outcome — confirmed by reload showing `outcome=0` after
    a successful save. Outcome must be set immediately before the actual
    `endTurnWithNextParticipants…` or `endMatchInTurnWithMatchData…` call that
    consumes it.
  - **Not reached / moot:** "overwriting a time-expired outcome" was impossible to
    test — no time-expired state is ever reached if the timeout mechanism itself
    doesn't fire. 3-player ring + multi-recipient exchange — not attempted
    tonight, blocked on the 2-player result first per the existing "build only
    after 2-player works" ordering.

### Decision: adopt exchanges for score/comment delivery; drop GameKit's own turnTimeout as the Gate-2 enforcement mechanism

Rules 1–5, 7, 8 above stand. **Rule 6 is revised**: GameKit's `turnTimeout`
cannot be the thing that returns the turn after 24 hours — it doesn't observably
do that. This is not a new problem: it only affects Gate 2 (GameKit's own formal
close), and only in the already-accepted edge case where the turn-holding
player's device never reopens — exactly the limitation `MULTIPLAYER_TEST_PLAN.md`
already called "an accepted limitation, not a bug to route around" for the
*current* (pre-exchange) design. Exchanges don't make that edge case worse, and
they fix the much more common problem this trial was actually for: with scores
and comments both delivered via exchange the instant they're ready — regardless
of who currently holds the GameKit turn — Gate 1 (what players actually see)
opens immediately and reliably for both players every time, with no dependency
on turn position at all. Gate 2 falls back to the existing, already-proven
self-enforced sweep (`COMMENT_WINDOW_SECONDS` / `applyCommentTimeoutIfExpired` /
`retryPendingHandshakeSends`) rather than a new GameKit-enforced one — keep that
code rather than deleting it as the 2026-10-07 decisions log suggested.

**Revised rule 6:** A player who hasn't locked a comment within 24 hours of
finishing locks a blank one automatically, the next time their own device runs
(unchanged from current production behavior). Once both comments exist in the
match data (delivered via ordinary turn-pass or exchange, whichever applies),
*whoever next holds the turn* — naturally, not via any timeout-forced transfer —
merges any pending exchanges and calls the final end. No turn-holder enforcement
beyond that; this matches today's shipped behavior's risk profile exactly, not a
regression.

**Addon fallback** (not needed — exchanges worked via the plain objc bridge, no
native addon required): Sparts Scoresheet's `addon-bridge-demo` branch
(`~/Documents/Xcode/SpartsScoresheet`) shows Lua↔native calls via `lua_register` +
`unsafeRunLuaBlock:` if ever needed for something the objc bridge can't reach;
Quozzy already has the stock `Quozzy/Addon/ProjectAddon.mm` scaffolding.

## Implementation status (2026-10-08) — cutover complete, live-verified

Production fully cut over to the exchange-aware relay tonight, with a live
integration test on real hardware (not just the unit suite) — see below for
exactly what that did and didn't cover.

**Landed:**
- `computeNextOwedAction` replaces `computeNextOwedLeg` (deleted) as what
  `attemptLegSend` (`GameCenter.lua`) calls. A score goes out the instant
  `didPlay` is true, independent of comment status; `via="turn"` if
  `tbm.isMyTurn`, `via="exchange"` otherwise. Finalize-eligibility is checked
  *before* the individual score/comment checks (a real priority bug, caught by
  the existing `decideComment` finalize test: becoming the second side to
  fully resolve was sending one redundant comment leg before ever reaching
  finalize).
- `attemptPendingLegSend` merges any completed exchanges before every
  turn-passing send, not just finalize — confirmed live that GameKit really
  does error on endTurn/endMatch with an unmerged completed exchange sitting
  on the match.
- `onExchangeDataReceived`/`onExchangeRepliesReceived` (`GameCenter.lua`),
  wired via two new `CTBM` listener callbacks (`CodeaTurnBasedMatches.lua`):
  an incoming exchange is applied to the local model and replied to
  immediately, independent of turn position; the two exchange listeners
  update `currentMatch`/`isMyTurn` directly rather than via `_setCurrentMatch`,
  so a background exchange can never jump the screen to `STATE_END`.
- `applyIncomingPlayersPatch` extracted from `makeQMatchFromGK` and reused for
  exchange-received data — also fixed `commentDecided` never actually being
  relayed in the patch, a pre-existing gap that would have silently broken
  finalize detection under the new per-field sent-tracking.
- `scoreSent`/`commentSent` replace the combined `resultSent`.
- `endGameRound` now calls `attemptLegSend` itself (previously only persisted
  to disk and waited for some other trigger).
- 133/133 unit tests passing (rewrote ~10 that hard-coded the old leg-based
  model; added a regression test for the finalize-priority fix).

**Live integration test** (real app rebuilt via `xcodebuild` and redeployed —
not the Lua source alone; see "Rebuild/redeploy note" below): iPad = Gnostic
Pan running the new code throughout; iPhone XR = GameySonata could not be
updated (see note) so stood in via `tools/xchg_trial.lua`'s raw GameKit calls,
which exercise the identical Apple APIs a second updated device would. Wired a
real match into the actual `enterQMatch`/`attemptLegSend` production path (not
a synthetic call) by hand via `dbg.sh`:
1. Real handshake send via turn-pass — confirmed the full chain
   `enterQMatch → attemptLegSend → computeNextOwedAction → merge (no-op) →
   endTurnWithDataTable → onTurnEnded → onLegSendSucceeded` end to end.
2. Simulated the iPad finishing its round while *not* holding the turn (turn
   was with GameySonata after the handshake) — **first attempt failed every
   retry**: `endTurnWithDataTable`'s success path deliberately nils
   `tbm.currentMatch` (other code relies on that signal), and
   `sendExchangeWithDataTable` assumed it was still valid. A real integration
   bug the unit suite's stubs couldn't catch, since `FakeTBM` mirrors the same
   nil-on-success behavior but no existing test chained a handshake success
   into a subsequent exchange attempt.
3. Fixed with `CTBM:ensureCurrentMatch(matchId, onReady)` — reloads fresh from
   GameKit when `currentMatch` is nil or stale, wrapped around
   `attemptPendingLegSend`'s dispatch. Rebuilt, reinstalled, reran step 2:
   score sent via exchange successfully, `scoreSent` marked true, pending
   entry cleared, confirmed as a real `GKTurnBasedExchange` on the match
   (`exchanges=1`, correct sender, 762-byte payload).
4. Recipient side (GameySonata via the harness) saw the exchange, replied,
   and — separately — sent its own exchange *back* to the iPad. The iPad's
   real production listener fired **automatically, unprompted** (genuine
   push-driven GameKit callback, not a manual invocation): ring buffer shows
   `onExchangeDataReceived: replied to 1 exchange(s)`, and `state` was
   unchanged before and after (no screen jump — rule 8 holds).
5. Match closed cleanly via the harness (merge + `endMatchInTurn`), both
   participants correctly `Done` with matching outcomes.

**Update (2026-10-08, ~5:45am–5:55am): the XR provisioning blocker is
resolved** — Jesse fixed it (Xcode GUI / developer.apple.com, exact mechanism
not visible from here) and asked for a full two-updated-device retest before
going back to sleep. Rebuilt and reinstalled on the XR
(`xcodebuild -allowProvisioningUpdates` now succeeds; new provisioning profile
`dc2a00d4-...` includes it). Reran the full scenario with **both devices
running the real, current production code** — no harness standing in for
either side's app logic this time, only for match creation/invite-accept
(`tools/xchg_trial.lua`'s raw GameKit calls, same as any matchmaking UI would
use):

1. Handshake: iPad creates, sends — **GameySonata's real `onReceivingTurn`
   fired automatically** (no manual wiring), correctly decoded the board and
   set up `currentQMatch`/`useTurnBased`/`tbm.isMyTurn` from scratch.
2. iPad finishes first (not holding the turn) → sent via exchange, confirmed
   via `scoreSent=true`. **GameySonata's real `onReceivedExchangeRequest`
   fired automatically**, applied the patch (`didPlay=true, score=42,
   words=[...]` all correct on GameySonata's own `currentQMatch`), and
   auto-replied — all unprompted, zero manual invocation.
3. GameySonata then finished (now holding the turn, with a real completed
   exchange sitting unmerged) → **the exact previously-untested integration
   edge**: `attemptPendingLegSend`'s `via=="turn"` branch had to merge first.
   Confirmed directly, not inferred: a fresh reload after GameySonata's send
   showed `exchanges=0` (resolved) and the turn correctly passed back to the
   iPad — the merge-before-turn-pass path works for real, through the actual
   production dispatch, not just the raw harness.
4. Comments: iPad decided first (holding the turn, comment sent via turn-pass)
   — GameySonata's real code received it with **`commentDecided=true`
   correctly set**, confirming that specific fix (the patch-application gap
   found earlier tonight) holds under real incoming data, not just a
   unit-test fixture. GameySonata then decided its own comment — both sides
   now fully resolved, GameySonata holding the turn — and **computeNextOwedAction
   correctly took the finalize branch** (not a redundant comment send, the
   exact priority bug fixed earlier).
5. **Real finalize, both devices, zero harness involvement**: reload after
   GameySonata's `decideComment` call showed `status=2.0` (Ended),
   `current=nil`, both participants `status=5.0` (Done) with matching
   `outcome=4.0` (tied — a function of the arbitrary test word lists summing
   to equal scores under the real scoring formula, not a bug; what matters is
   both sides agree).

Every item in the "not covered" list above is now directly confirmed on real
hardware, real production code, both sides: the merge-before-turn-pass edge,
the `commentDecided` relay fix under live conditions, and a full two-device
finalize. Nothing in this design remains unverified at the integration level.

**Rebuild/redeploy note, for next time:** editing `Quozzy.codea/*.lua` on disk
has zero effect on an already-installed app — Codea bundles the whole
`Quozzy.codea` folder as a build-time resource (confirmed: `lastKnownFileType
= wrapper` in `project.pbxproj`, copied fresh each build, not a one-time
export snapshot), so a real code change requires `xcodebuild -project
Quozzy.xcodeproj -scheme Quozzy -configuration Debug -destination
'generic/platform=iOS' build`, then `xcrun devicectl device install app
--device "<name>" <path-to>/Quozzy.app`, then `devicectl device process
launch`. The build is unattended-friendly: existing signing identity and
provisioning profile are picked up automatically, no Xcode GUI needed — this
held for both devices once the XR's provisioning was fixed.

## Two more findings (2026-10-08, ~9:40am), from Jesse double-checking the design directly

**Q: "The instant a GKMatch is complete (both scores, both comments), is it
ended by whichever handset detects this first?"** Tracing the code surfaced a
real gap, then a second real bug, both fixed and live-verified:

- `onExchangeDataReceived` applied the opponent's data and replied, but never
  re-checked `attemptLegSend` afterward. A turn-pass receipt gets that check
  for free via `enterQMatch`'s own `attemptLegSend` call; an exchange receipt
  had no equivalent. Concretely: if I already hold the turn and have fully
  finished my own side, and the opponent's last missing piece (say, their
  comment) arrives via exchange because they didn't hold the turn — nothing
  would notice I could now finalize until something unrelated happened to
  call `attemptLegSend` again. Fixed: `attemptLegSend` now runs inside
  `replyToActiveExchanges`'s own completion callback (after the reply
  round-trips, so a finalize's merge step sees the exchange as genuinely
  resolved), gated on `tbm.isMyTurn`.
- Live-testing that fix surfaced a second, independent bug: the exchange send
  failed every retry with **"the requested operation could not be completed
  because the match data was too large."** Exchanges have their own GameKit
  data-size limit, smaller than the regular matchData limit a turn-pass uses
  — the full-state payload (both players, board data) that sends fine via
  turn-pass exceeded it. Fixed: an exchange now only carries the sender's own
  player slot, not the opponent's, and omits board data the recipient already
  has from the handshake.
- **Both fixes confirmed together, live, two real devices**: engineered the
  exact scenario (one side fully done and idle holding the turn, the other's
  final piece — a comment — arriving via exchange) and watched the match
  reach `status=2.0` (Ended), both participants `Done`, matching outcome —
  entirely automatically, zero manual trigger after the exchange landed.

**So: yes, this is now the case** — for the 2-player design, with both fixes
in place. The one remaining caveat (not a bug, a GameKit constraint): "whoever
detects it first" must also currently **hold the turn** — GameKit only lets
the turn holder write data or end a match. If the detecting device doesn't
hold the turn, it has nothing to do but wait for its own next turn-pass or
exchange-reply cycle to pick this up (which, per everything above, now
happens automatically and promptly in practice).

**Q: "What are the non-turn-holder's options for forcing a match end?"**
Tested live rather than assumed from Apple's docs. Apple's only documented
API for this is `participantQuitOutOfTurnWithOutcome:withCompletionHandler:`
("abandon the match when it is not the current participant's turn... no
update to matchData and no need to set nextParticipant"). Called it live from
the non-turn-holder and confirmed exactly what the terse doc comment implies,
with no surprises and no silver lining:

- Only the **caller's own** participant status/outcome changes (confirmed
  `Done`/`Quit`) — the match's overall `status` stayed `Open`, and the turn
  holder's own participant record was completely untouched.
- No matchData update occurs, confirmed (`matchData len=0` unchanged) — so
  this app's relay logic, which only ever reads/writes the matchData JSON
  blob (never GameKit's native `participant.status`/`matchOutcome` fields
  directly), has **no awareness this happened at all**. A player who quits
  out-of-turn today doesn't get interpreted by this code as "resolved" in any
  way — `computeNextOwedAction` would keep seeing whatever stale data was
  last actually relayed about them.
- No GKLocalPlayerListener callback appears to fire on the turn holder's side
  as a result (checked for any observable side effect on the turn holder's
  device; found none — though note the verbose CTBM-internal matchmaking-event
  log is simulator-gated, so this isn't as airtight as the two confirmations
  above). Apple's listener protocol has no event type that matches "a
  participant quit out of turn" — the closest, `wantsToQuitMatch:`, is
  documented as firing only for the player who **currently holds the turn**.

**Bottom line: a non-turn-holder cannot force the match to end.** Their only
unilateral action marks themselves done without affecting the match's overall
status, isn't visible to the turn holder in any automatic way, and isn't even
understood by this app's own relay logic today. This confirms (more strongly
than before) that the "both players went silent, match stays open forever"
edge case genuinely has no non-turn-holder-side escape hatch — closing the
match always requires the turn holder's own device to eventually act, whether
promptly (now automatic, per the fixes above) or, in the silent-forever case,
never.

### Follow-ups (nothing blocking — the design is now fully verified)

1. 3+ players (decided 2026-09-24, not started) — explicitly gated on the
   2-player version working first; it now does, on real hardware, both sides.
2. The test matches created tonight (several, across both trial sessions)
   are real GameKit matches against real accounts — harmless (all between
   Jesse's own Gnostic Pan/GameySonata/Smatchy LaPaglia accounts), but worth
   a glance in Game Center's match history if any look confusingly stale.
3. Consider whether `participantQuitOutOfTurnWithOutcome:` is worth wiring in
   anyway as a user-facing "forfeit" button for the non-turn-holder — it
   wouldn't close the match, but it would at least record that player's own
   intent, visible to them locally and to GameKit's own records for that
   participant, which today isn't captured anywhere if they just walk away.

## The "silent player never reopens" problem — solved (2026-10-08, ~10:15am–11:00am)

The one real gap left after everything above: a comment-timeout candidate
sitting on a device that never gets reopened could never resolve, because
the self-enforced sweep only ran from `draw()`'s per-frame foreground check.
Looked for a workaround; found a real one.

**`GKTurnBasedMatch.sendReminderToParticipants:localizableMessageKey:
arguments:completionHandler:`** — a plain GameKit API, sends via Apple's own
Game Center push infrastructure, no server of ours needed. Verified live,
directly, not assumed from the header comment:

- **Not turn-gated** — callable by the non-turn-holder, like exchanges.
- **Rate-limited** — a second reminder sent ~2 minutes after the first failed
  with "the requested operation could not be completed because it would
  exceed the maximum number of sessions" (code 21). Exact cooldown/quota
  unknown; not spammable, which is reassuring for a "don't annoy the
  opponent" feature but means this can't be fired on every foreground check —
  it needs to be deliberate (see "still open" below).
- **Wakes a fully-terminated app in the background, confirmed via process ID**
  (not inferred): force-killed the app via `devicectl device process
  terminate`, confirmed the process gone, sent one reminder from the other
  device, polled `devicectl device info processes` until a new PID appeared
  on its own. It did, within under a minute, with zero user interaction.
- The real (unmuted) `onReceivingTurn` production handler fires during that
  background wake and correctly loads fresh match data — this part was
  already confirmed earlier to be foreground-independent.

**But the self-timeout sweep specifically wasn't reaching that path** — it
only ran from a foreground-gated per-frame check, so a background-only wake
delivered data but never resolved this device's own stuck comment. Fixed:
`retryPendingHandshakeSends` (which runs the sweep) now also gets called
directly from inside `onReceivingTurn`, not only from `draw()`.

**That fix immediately surfaced a second, independent bug**: `retryPendingHandshakeSends`'s
resend loop had `if tbm.isMyTurn == true then ... end` guarding whether to even
attempt a resend — a leftover from before exchanges existed, when sending
without the turn was impossible. Now that exchanges work regardless of turn
position, this gate would skip the comment-timeout candidate entirely
whenever the device didn't hold the turn — exactly the common case. Removed;
`attemptPendingLegSend`/`attemptLegSend` already decide turn-pass vs.
exchange correctly on their own (confirmed: `endTurnWithDataTable` already
no-ops safely if not holding the turn).

**Live-testing those two fixes surfaced a third, independent bug**:
`onLegSendSucceeded` cleared the `finishedAwaitingDecisionByMatchId` disk
snapshot — the thing `checkFinishedMatchesForCommentTimeout` sweeps — on
*any* successful non-handshake send, including a score-only one. Correct
under the old bundled design (score and comment always went out together);
wrong now that they're independent, since it permanently blinds the sweep to
a still-undecided comment the moment the score alone goes out. A live test
caught this directly: backdated a match's `commentWindowStartedAt`
immediately after its score-via-exchange send had already succeeded, and
found the snapshot already gone. Fixed: only clears once `commentSent` is
actually true.

**Full chain confirmed working end to end, real hardware, zero remaining
manual steps:** backdated a fresh match's comment window by 25 simulated
hours, force-terminated the app, sent one reminder from the other device.
Polled for the process to reappear (it did, autonomously). Foregrounded it to
inspect: `finishedAwaitingDecisionByMatchId` entry was gone — meaning the
comment had been decided blank *and sent* — confirmed independently via the
other device reloading the real GameKit match: a completed, already-replied
`GKTurnBasedExchange` from the terminated device, matching data length
consistent with a real comment payload. Neither device needed any further
manual action after the single reminder — the other side's real production
`onExchangeDataReceived` auto-replied on its own, exactly as already proven
earlier tonight.

This survived an actual interruption too: the laptop running these tests
shut down and restarted mid-poll. The physical devices are independent
hardware — none of the above depends on the laptop staying on, only on
`dbg.sh` access to inspect results, which simply resumed once devicectl
reconnected.

### What's still open

1. **Who calls `sendReminderToParticipants`, and when?** Not wired into the
   app at all yet — tonight only proved the mechanism via the raw trial
   harness. The natural shape: the *waiting* player's device notices (on its
   own foreground, looking at a specific match) that the opponent has been
   stuck a while and sends a reminder — either automatically past some
   threshold, or via an explicit "nudge" UI action. Given the rate limit,
   probably shouldn't be automatic-on-every-foreground; more likely a
   deliberate action or a once-per-some-long-interval background check.
2. Exact rate limit parameters (cooldown duration, whether it's per-match or
   per-account) are unknown — only know empirically that back-to-back calls
   within ~2 minutes fail.
3. Whether a background wake reliably has enough time/opportunity to
   complete a multi-step async chain (sweep → lock comment → send → merge)
   before iOS suspends the background-launched process again — it worked in
   this test, but background execution time after a push-triggered launch is
   not unlimited, and a slower network path could behave differently.
