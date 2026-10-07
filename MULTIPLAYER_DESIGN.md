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
3. **Comments travel separately, later.** A comment decision (text, or blank)
   goes out on a later send by whichever player holds the turn. A player can type
   a comment without holding the turn; it's cached and attached the next time
   their device holds the turn.
   > "If their comment isn't ready, that means at some point the turn needs to
   > return to them to see if they made one."
4. **No comment = a blank comment.** Closing the comment box empty is a decision,
   same as typing one.
5. **Two gates.**
   - **Gate 1 — the players see the match as over** once both scores are on their
     device (and they've had a chance to see the result). Drives the end screen.
     Never depends on GameKit's match state.
   - **Gate 2 — GameKit sees the match as over** only once both players have had
     their chance to comment (decided, blank or not). Only then does the holder
     call `localPlayerWon/Lost/Tied`.
6. **24-hour comment timeout.** A player who hasn't decided on a comment within a
   day of finishing gets a blank comment. **Whoever opens the app after the
   timeout is up ends the match.**
7. **The UI never shows Game Center's view of the match.** The gap between "over
   for players" (gate 1) and "over for GameKit" (gate 2) is invisible to them.

## The sequence

P1 = creator, P2 = invitee. "→" is a turn send; the turn moves with it.

**Leg 1 — handshake.** P1 → P2: board only. Turn: P2.

**Legs 2–3 — scores** (order depends on who finishes first):

| P2 finishes first | P1 finishes first |
|---|---|
| P2 holds the turn, so the moment P2's round ends: **P2 → P1, P2's score.** | P1 doesn't hold the turn: P1's score is saved locally and waits. |
| P1 plays whenever; the moment P1's round ends: **P1 → P2, P1's score.** | The moment P2's round ends: **P2 → P1, P2's score.** |
| | The moment the turn reaches P1's device: **P1 → P2, P1's score** (plus P1's comment if already decided). |

After leg 3 both devices have both scores: **gate 1 is open for both players.**
The turn is with P2.

**Legs 4+ — comments.** Whoever holds the turn:
- has a new comment decision (typed or blank, possibly cached earlier) and the
  other player's isn't in yet → **sends it and passes the turn**;
- has a new decision and the other player's is already in → **ends the match**
  (gate 2) instead of passing, carrying both comments;
- hasn't decided yet → **keeps the turn** until they decide or time out.

Typical worst case: handshake, score, score, comment, end = 5 sends. It always
terminates because each send carries something new and there are only two
scores and two comment decisions.

## Badges and notifications (from the same session)

- Two badges: **game ended** (gate 1 reached, not yet seen) and **opponent
  commented**. Both appear on the match in the vs list and in Records.
- Hide any Game Center badge or notification that duplicates something the player
  has already been shown — the silent comment/relay sends must not light up the
  home-screen badge.

## Open questions

1. **Who can actually enforce the timeout.** Rule 6 says whoever opens the app
   ends the match, but only the turn holder can end it, and in the stuck case the
   holder is usually the player who went silent. Candidate fix: when passing the
   turn for a comment, use GameKit's `turnTimeout` (already passed through in
   `CodeaTurnBasedMatches.lua`'s `endTurn…` call) with the sender listed as next
   participant, so GameKit returns the turn when the window expires. Needs
   on-device verification.
2. **Per-player or shared 24h clock.** Claude suggested per-player (each from
   their own finish); not confirmed.
3. **Should backgrounding the app count as a comment decision?** Claude proposed
   it; not confirmed. Less important now that scores don't wait on comments.
4. **Do late comments reopen the end screen** or just appear (with the
   "opponent commented" badge) the next time the match is viewed? Claude leaned
   toward the latter; not confirmed.

## Current code vs. this design (as of 2026-10-07, branch `merge-laptop-work`)

Implemented in `642c99a` and kept through the laptop merge, but built on a
version of the design Claude substituted during implementation:

| Design | Current code |
|---|---|
| Score sent the instant the round ends | Score waits until the player closes the end screen; `computeNextOwedLeg` (`qMatch_qPlayer.lua`) requires `didPlay` **and** `commentDecided`, so score and comment always go out together |
| Comment on a separate later leg | No separate comment leg (at most 3 sends total) |
| Whoever opens the app after 24h ends the match | 24h window exists (`COMMENT_WINDOW_SECONDS`, `applyCommentTimeoutIfExpired`) but only the silent player's own device checks it — if they never reopen, the match never ends |
| Handshake before P1's ready screen | Handshake fires from `enterQMatch` while the ready screen is up; P1 can start without waiting for it |

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
