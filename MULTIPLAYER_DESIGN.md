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
- Code to delete/replace: `COMMENT_WINDOW_SECONDS` / `applyCommentTimeoutIfExpired`
  self-enforced timeout; the `enterQMatch` jump on an incoming turn
  (`tbm:onReceivingTurn` in `Main.lua`) — keep only the background send.

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

## GameKit exchange trial (2026-10-07) — in progress

**Why:** a comment locked while not holding the turn waits on the phone and can be
lost to the 24h clock. GameKit *exchanges* (`sendExchange…`) let a player without
the turn send data to the match immediately; the turn holder merges it
(`saveMergedMatchData`) before passing the turn or ending the match (Apple: an
unmerged completed exchange makes endTurn/endMatch error). If exchanges work, a
comment can leave the phone the moment it locks, the turn only needs to move for
scores, and the comment-loss problem goes away. **Not yet adopted in the rules
above** — pending this trial.

**Harness:** `tools/xchg_trial.lua` — load with
`DBG_SIM=<udid> tools/dbg.sh -f tools/xchg_trial.lua`, then call `XT.muteApp()`,
`XT.findB(alias)`, `XT.create()`, `XT.passTurn(seconds)`, `XT.sendEx(seconds)`,
`XT.reload()`, `XT.merge()`, `XT.saveTurn()`, `XT.endMatch()`, `XT.describe()`,
`XT.dump()`. Callbacks only record to `XT.log` (no Codea work in objc callbacks).

**Results so far** (simulator signed in as Gnostic Pan, invited Smatchy LaPaglia):
- The objc bridge can call `sendExchange` — no native addon needed.
- A non-turn-holder can send an exchange to an *invited-not-yet-accepted* player;
  it appears in `match.exchanges`.
- A 60s `turnTimeout` and a 60s exchange timeout did NOT fire within 3.5 min while
  the recipient was only invited (timeoutDate stayed nil). Retest with a recipient
  who has accepted.

**Still to test** (needs a second real account — iPhone XR, GameySonata):
exchange reply + completion visible to sender; merge by turn holder; endMatch
blocked while an exchange is unmerged; turn timeout actually returning the turn;
`saveCurrentTurn`; whether a result can be set before the match ends; overwriting
"time expired" outcome; 3-player ring + multi-recipient exchange. The existing
`turnTimeout` passed by `CTBM:endTurn…` is `0` — meaning unknown.

**Rig state:** iPhone 17 simulator `1BB18035-952E-4B35-81B0-D8CD4124591D` is
signed in as Gnostic Pan with the app installed. Test match
`6759465984:e742845b-f496-4981-8fba-766d156591f8` (Gnostic Pan → Smatchy) is still
open on Smatchy's turn; quit it when done. iPhone XR ("Testing iPhone XR",
CoreDevice `C1F748A5-36C2-595C-AFF4-A74BF6C748AA`, Xcode id
`00008020-001D382C1402002E`) is connected but the app isn't installed: Xcode
needs the Apple Program License Agreement accepted at developer.apple.com before
it can add the XR to the provisioning profile; then Run from Xcode.

**Addon fallback:** Sparts Scoresheet's `addon-bridge-demo` branch
(`~/Documents/Xcode/SpartsScoresheet`, pushed to SpartsScoresheetXcode) shows
Lua↔native calls via `lua_register` + `unsafeRunLuaBlock:`; Quozzy already has the
stock `Quozzy/Addon/ProjectAddon.mm` scaffolding.
