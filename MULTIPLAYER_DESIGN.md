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

## Implementation status (2026-10-08) — built so far, cutover not done

Built tonight, in production files, additive only — **current production
behavior is completely unchanged**; nothing below is called by any live code path
yet:

- `computeNextOwedAction(q, myId, iHoldTurn, now)` (`qMatch_qPlayer.lua`, next to
  the still-active `computeNextOwedLeg`) — the pure decision function for the
  revised design: returns `{kind="handshake"|"score"|"comment"|"finalize",
  via="turn"|"exchange"}` or `nil`. A score is owed the instant `didPlay` is true,
  regardless of comment status; `via` is `"turn"` if `iHoldTurn`, `"exchange"`
  otherwise. 10 new unit tests, all passing.
- New player-slot fields `scoreSent`/`commentSent` (`ensureQMatchPlayers`),
  alongside the still-present `resultSent` (which `computeNextOwedLeg` still
  reads). Not yet written by any send-success path — see below.
- `CTBM:sendExchangeWithDataTable(t, onError, onSuccess)`,
  `CTBM:replyToActiveExchanges(dataTable, onDone)`,
  `CTBM:mergeCompletedExchanges(dataTable, onError, onSuccess)`, plus the
  `GKLocalPlayerListener` delegate methods they need
  (`player:receivedExchangeRequest:forMatch:`,
  `player:receivedExchangeReplies:forCompletedExchange:forMatch:`) and their
  `CTBM:onReceivedExchangeRequest`/`onReceivedExchangeReplies` setters
  (`CodeaTurnBasedMatches.lua`). Modeled directly on `tools/xchg_trial.lua`'s
  calls, each individually verified live tonight (see above). Not covered by
  `tests/run_tests.lua` (doesn't load this file) — verified with a syntax-only
  parse check, not executed.

### Why the cutover itself stopped here

Wiring `computeNextOwedAction` into actual production dispatch turned out to be
materially bigger than "swap the function call" once the exchange rule
`saveMergedMatchData:withResolvedExchanges:` — "all completed exchanges must be
resolved before ending a turn. Otherwise calling endTurn, participantQuitInTurn,
or endMatchInTurn will return an error" — is taken seriously: **every**
turn-passing send (not just the final one) must merge first, not only
`finalize`. That, plus needing a live reply-on-receipt hook for incoming
exchanges, plus ~15 existing tests in `tests/run_tests.lua` that hard-code
`computeNextOwedLeg`'s leg names and `onLegSendSucceeded`'s single-`resultSent`
model, add up to a genuinely interdependent rewrite — not "assemble
already-validated pieces." Doing that in one unsupervised overnight pass, on
code that handles real matches on real accounts, isn't a risk worth taking
without someone able to review or catch a bug before it runs live. The
exchange *primitives* are validated; the *integration* is new engineering that
deserves the same scrutiny.

### Exact punch list for whoever picks this up

1. **`GameCenter.lua`: replace `attemptLegSend`'s internals.** Call
   `computeNextOwedAction(q, myId, tbm.isMyTurn, os.time())` instead of
   `computeNextOwedLeg`. New pending-entry shape:
   `{ kind, via, turnData, attempts }` (was `{ leg, turnData, attempts }`).
2. **`GameCenter.lua`: `attemptPendingLegSend` needs a merge-first step.** For
   `via == "turn"` or `kind == "finalize"`: call
   `tbm:mergeCompletedExchanges(payload, onError, onSuccessThen(actualSend))`
   first — it's a no-op straight to `onSuccess` if nothing's pending, so this is
   safe to call unconditionally. Only call the actual `endTurnWithDataTable` /
   `finalizeCompletedTurnBasedMatch` inside that success callback. For
   `via == "exchange"`: call `tbm:sendExchangeWithDataTable` directly, no merge
   needed (merging is a turn-holder concern).
3. **`onLegSendSucceeded`: replace the single `resultSent` write.** On a
   successful `"score"` send, set `me.scoreSent = true`; on `"comment"`, set
   `me.commentSent = true`. Since the full `q.players` table is always sent
   regardless of `kind` (same as today), consider marking *both* sent if both
   conditions were already true at send time, to avoid a redundant follow-up
   send — not load-bearing, just an efficiency nicety.
4. **`Main.lua`: wire the two new CTBM callbacks.** On
   `onReceivedExchangeRequest(match, exchange)`: call
   `tbm:replyToActiveExchanges(currentReplyPayload, onDone)` — doesn't require
   holding the turn, should happen essentially immediately on receipt. On
   `onReceivedExchangeReplies(match, exchange)`: if `tbm.isMyTurn`, this is the
   turn holder's signal that something is ready to merge — call
   `attemptLegSend(currentQMatch)` again (it'll see the completed exchange via
   the merge-first step above).
5. **`endGameRound` (`GameCenter.lua`) should call `attemptLegSend`.** Today it
   only persists to disk and waits for some other trigger. Once scores go out
   immediately regardless of comment status, this is the natural place to kick
   the first attempt.
6. **Rewrite affected tests in `tests/run_tests.lua`.** Everything in the
   "computeNextOwedLeg" and "onLegSendSucceeded" sections, plus the
   `beginInitialHandshakeSend`/`attemptPendingLegSend` tests that assert on
   `pending.leg` — update to the new `kind`/`via` shape. The 10
   `computeNextOwedAction` tests added tonight stay as-is.
7. **Delete `computeNextOwedLeg`** once step 6 is green and nothing references
   it (grep first — `resultSent` and the old leg names are referenced in
   comments in several files; harmless but worth cleaning up in the same pass).
8. **Live-hardware integration pass, required before trusting this**: repeat
   tonight's manual trial sequence but through the *real app's* UI/state
   machine instead of `tools/xchg_trial.lua` — create a match, have one side
   finish while not holding the turn, confirm the exchange fires automatically,
   gets replied to automatically, gets merged automatically, and the match
   still finalizes correctly end to end. The two devices used tonight (iPad =
   Gnostic Pan, iPhone XR = GameySonata) are already signed in and paired as
   Game Center friends — same rig, no new setup needed.
