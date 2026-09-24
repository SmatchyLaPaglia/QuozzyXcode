# Simultaneous-Play Relay/Comment/Badge — Test Plan

Covers the redesign discussed for: match sending (handshake + relay legs), match
ending (two-gate model), commenting (window + timeout), badging, and notification
(badge-count) suppression. Write this alongside the implementation — check items
off as they land, don't treat it as a doc to write once and forget.

## Design recap (for whoever picks this up cold)

Two independent gates:
- **Gate 1 (local "it's over")**: unlocked the instant a device has both players'
  scores. Drives `STATE_END` display. Never depends on GameKit's own match state.
- **Gate 2 (GameKit's own "it's over")**: unlocked once both players have had a
  comment opportunity (typed, explicitly blank, or timed out). Drives the actual
  `localPlayerWon/Lost/Tied` finalize call.

**Revised, simpler relay than originally sketched**: score and comment always
travel together in ONE send per player — never a bare score followed later by
a separate comment leg. That collapses the relay to **at most 3 network legs**:
1. Handshake: creator → opponent, board only, sent before/at the ready screen.
2. Whichever player decides first (finishes playing AND locks in their comment
   — see below) sends their combined score+comment the moment they can (i.e.
   the moment they hold the turn — immediately if they already do, or as soon
   as it arrives if not) → turn to the other player.
3. The other player, once they've likewise finished and decided, sends their
   own combined score+comment. Since the first player's leg always arrives
   already fully decided (bundled), this second leg has everything needed to
   also finalize the match for GameKit's purposes in the same send.

Per-player decision logic (implemented as the pure function
`computeNextOwedLeg` in `qMatch_qPlayer.lua`): send only once **both**
`didPlay` and `commentDecided` are true for me — never send a bare score
ahead of a comment decision, and never invent a decision on the player's
behalf just because the turn arrived. `commentDecided` becomes true via the
UI (screen close, blank or not) or via the timeout below.

Both original open design questions are now resolved:
- **Comment timeout**: self-enforced only. Whichever player is sitting on an
  undecided comment locks it in as blank themselves, on their own next
  foreground/launch, once `COMMENT_WINDOW_SECONDS` has elapsed since they
  finished (`applyCommentTimeoutIfExpired`). The other player's device never
  enforces it on their behalf — since score+comment are always bundled, the
  other player never even learns this match exists (from GK's perspective)
  until the silent player's own device eventually sends it. If that device
  never reopens, the match simply never resolves — an accepted limitation,
  not a bug to route around.
- **Badges**: two distinct badges, not one graduated indicator — "game ended"
  and "opponent commented" (§4 below).

## Implementation status

**Built, wired live, and unit-tested** (`tests/run_tests.lua`, 84 assertions,
real source files loaded through a stub Codea/GameKit environment — see that
file's header):
- `ensureQMatchPlayers` slot defaults extended: `commentDecided`,
  `commentWindowStartedAt`, `resultSent`.
- `computeNextOwedLeg(q, myId, now)` — pure relay decision (handshake /
  result / finalize / nothing), `qMatch_qPlayer.lua`.
- `applyCommentTimeoutIfExpired(q, myId, now, windowSeconds)` — pure
  self-timeout check, `qMatch_qPlayer.lua` (not yet called from anywhere —
  see below).
- `endGameRound` stamps `commentWindowStartedAt` once, on first finish.
- `enterQMatch`'s merge-guard extended to protect `STATE_END` (item 1.6).
- `attemptLegSend(q)` / `attemptPendingLegSend(matchId)` — the generalized
  send path (renamed from the handshake-only `attemptHandshakeSend`),
  dispatching handshake/result relays through `tbm:endTurnWithDataTable` and
  `finalize` through the existing `finalizeCompletedTurnBasedMatch`.
- `decideComment(commentText)` — the new entry point for "the player closed
  their comment box" (blank or not); `submitFinalCommentFromEndScreen` is now
  a thin wrapper over it. Replaces the old direct, retry-less
  `tbm:endTurnWithDataTable` call in the first-to-play branch — that leg now
  gets the same backoff/retry the handshake always had.
- `onLegSendSucceeded(matchId)` — the success-side counterpart, called from
  `Main.lua`'s `tbm:onTurnEnded` callback (the only place a send's success is
  actually observable — see hazard #2 below).
- `enterQMatch` restructured (`enterQMatch_inner` + a thin outer wrapper) so
  `attemptLegSend` runs after every exit path, not just the fallthrough —
  e.g. a merge that just brought in the opponent's resolution can now
  trigger an immediate finalize.

All three wiring hazards identified while designing this are resolved and
covered by tests, not just noted:
1. **Board-tiles-validity timing** — solved via the explicit
   `q.needsInitialHandshake` flag, computed once from the raw incoming
   payload and stored on the object before local board generation can mask
   the signal.
2. **Async success detection** — solved by keeping `onLegSendSucceeded` a
   separate function from the send attempt itself, called only from
   `tbm:onTurnEnded`. Verified with a test that deliberately checks the flag
   is *not* yet cleared right after a "successful" (no-`onError`) send, and
   only clears once `onLegSendSucceeded` is invoked separately — catching
   the exact synchronous-vs-asynchronous trap this hazard was about.
3. **Stale-incoming-payload vs. a pending local decision** — solved by
   restoring `currentQMatch.players[myId]` from any frozen
   `pendingTurnSendsByMatchId[q.id]` entry immediately after
   `ensureQMatchPlayers` runs, before any downstream branch reads it.

**Comment-timeout hook — done.** Wiring this up surfaced a real persistence
gap, now fixed too: `endGameRound` previously only mutated the in-memory
`currentQMatch` — nothing was written to disk until *after* a comment was
decided, so a kill between finishing a round and deciding on a comment lost
the entire result, not just its send. Fixed with a new persisted table,
`finishedAwaitingDecisionByMatchId` (`qMatch_qPlayer.lua`, same
persist/load-on-disk pattern as `pendingTurnSendsByMatchId`):
- `endGameRound` writes into it the instant a round finishes, before any
  decision exists.
- `decideComment` keeps the disk copy in sync while a decision is pending.
- `onLegSendSucceeded` clears it once the resulting send actually lands.
- `checkFinishedMatchesForCommentTimeout(now)` sweeps it and applies
  `applyCommentTimeoutIfExpired` to each entry — pure, tested with a
  simulated-restart test that clears the in-memory table, reloads purely
  from the persisted disk copy, and confirms the result (score, words,
  didPlay) survives intact.
- `retryPendingHandshakeSends` (`Main.lua`, already the foreground/launch
  retry hook) now runs this sweep first, then attempts to send anything a
  timeout just unblocked using the same "load matches, confirm I hold the
  turn, then send" dance it already used for `pendingTurnSendsByMatchId`.

**Composer UI gate — loosened.** `shouldShowFinalCommentComposer` no longer
requires `tbm.isMyTurn`/`tbm.currentMatch` at all — it now shows the composer
whenever `me.didPlay and not me.commentDecided and not q.recordOutcomeApplied`.
This closes the exact original gap: the real CTBM clears `tbm.currentMatch`
the instant a turn-end succeeds, which happens to the match creator right
after their own handshake, before they've played — under the old gate they
could never see the composer at all. `recordOutcomeApplied` (already set by
`finalizeCompletedTurnBasedMatch`, and explicitly set by
`openHistoricalMatchEndScreen` for a reconstructed Records view) does double
duty excluding both an already-finalized match and a historical replay —
important because the historical reconstruction never populates
`commentDecided` at all, so that field alone wouldn't have excluded it.
Verified with a test that specifically reproduces the post-handshake
creator's state (`isMyTurn=false`, `currentMatch=nil`) and confirms the
composer is now available.

**Badges — done: "game ended" and "opponent commented", two distinct dots**
(not one graduated indicator, per your call):
- `opponentRecords.lua` gained the pure predicate layer — `matchNeedsEndedBadge`,
  `matchNeedsCommentBadge`, `findMatchHistoryEntry`, `computeMatchBadges` — all
  unit-tested, including a test that records a snapshot (simulating "already
  viewed"), confirms both badges clear, then confirms a *different* later
  opponent comment re-surfaces the comment badge even though the match itself
  stays "already seen complete".
- Key realization while designing this: `matchHistoryByOpponent` only ever
  gains/updates an entry when a match's end screen has actually been shown
  (`recordMatchSnapshot`'s only caller is `buildEndScreenModel`) — so a
  stored entry's mere presence, and the comment text it holds, *is* "what the
  player has already seen". Badge state is a diff between that and the
  freshest live GameKit data, not something `matchHistoryByOpponent` could
  track by itself.
- `Badges.lua` gained `refreshMatchStoryBadges`, polling *every* match (not
  just ones where it's currently my turn — a match can be fully finished
  while GameKit still lists it open, waiting only on the comment/finalize
  leg), decoding each via the same `_matchWithNSDataToDataTable` path already
  used elsewhere, and populating `endedMatchBadgeIds`/`commentMatchBadgeIds`.
  Wired into the same menu-entry/periodic triggers the existing "come play"
  badge already uses.
- `RecordsUI.lua` draws both dots on each match row and an aggregate dot on
  the opponent row (before drilling in). `recordMatchSnapshot` clears both
  badges for a match immediately on viewing, rather than waiting for the next
  GameKit poll to notice.
- **Not independently verifiable** without a device: the actual on-screen
  rendering. The polling/decoding/predicate logic is unit-tested; the drawing
  code follows this file's existing conventions closely (same helpers,
  `_drawRowCard`-style) but hasn't been screenshotted or run.
- **Not done**: no aggregate indicator at the menu level (e.g. on the Records
  button itself) — scoped out to avoid touching `HaikuMenu.lua`'s
  animation-heavy layout code without the ability to verify it.

## Test environment

- Two distinct Game Center sandbox accounts are required for anything beyond
  pure state-machine logic — per the original handshake commit (`4501f46`),
  simulator-to-simulator GK auth is unreliable; use one simulator + one real
  device (or two real devices), same as before.
- Log reading: `xcrun simctl spawn $SIM log show --predicate 'process == "Quozzy"'`
  for the simulator side; Xcode console or on-device capture for the real
  device (per `XCODE_CODEA.md`).
- Force-quit is manual (no touch-injection tool available per `HANDOFF.md`
  §20) — `xcrun simctl terminate` works for the simulator side; physical
  app-switcher kill on the real device.
- Add a debug-only override for the comment timeout (e.g. a constant settable
  to 30s in a debug build) — do not plan to actually wait 24 hours per test
  pass.

## 1. Match sending (handshake + relay legs)

- [ ] 1.1 Fresh match creation: opponent receives board immediately, before
      creator even reaches the ready screen.
- [ ] 1.2 Both players can start playing independently of who created the
      match and of current GK turn ownership (regression on existing behavior).
- [ ] 1.3 Opponent finishes first: their score-relay leg fires immediately on
      finishing (not gated on closing the screen), turn transfers to creator.
- [ ] 1.4 Creator finishes first (before receiving the opponent's leg): result
      persists locally immediately; no send attempted, no error/retry-loop
      spam from trying to send without holding the turn.
- [ ] 1.5 Collision: opponent's leg arrives while creator is actively in
      `STATE_READY`/`STATE_PLAY` — existing merge-guard applies, creator's
      round is not reset.
- [x] 1.6 Collision: opponent's leg arrives while creator is sitting on
      `STATE_END`, already finished but not yet sent — merge-guard extended
      in `enterQMatch` (`GameCenter.lua`) to also protect this case, matching
      1.5's behavior for `STATE_READY`/`STATE_PLAY`. Covered by
      `tests/run_tests.lua`.
- [ ] 1.7 Handshake send failure: airplane mode at match creation — verify
      existing `HANDSHAKE_MAX_ATTEMPTS`/`HANDSHAKE_RETRY_DELAYS` backoff fires,
      and it sends once connectivity returns (foreground retry).
- [ ] 1.8 Force-quit immediately after finishing a round, before any network
      attempt completes — relaunch — persisted score is found and sent as
      soon as it's legally possible (immediately if turn already held, or
      once the turn arrives later).

## 2. Ending (two-gate model)

- [ ] 2.1 Gate 1 fires from local score presence alone, in both finish
      orderings (finish first / finish second) — regardless of GK's own
      match-ended status.
- [ ] 2.2 Audit every end-screen/records string for GK-state-derived language
      ("waiting for turn," "in progress," etc.) that could surface the
      gate-1/gate-2 disalignment to the player. Should find none.
- [ ] 2.3 `localPlayerWon`/`Lost`/`Tied` (gate 2) fires only after BOTH players
      have had their comment opportunity resolved — not merely once both
      scores exist.
- [ ] 2.4 RecordsUI / `opponentRecords` snapshot reflects "complete" at gate 1,
      independent of gate 2 — no UI path blocks waiting on gate 2.
- [ ] 2.5 Both players decline to comment quickly: gate 2 finalizes promptly,
      not delayed by the timeout window (timeout is a ceiling, not a floor).

## 3. Commenting (window + timeout)

- [ ] 3.1 Comment composer is enterable even before the local player holds the
      turn (UI gating change from today's `isMyTurn`-only gate) — typed draft
      caches locally regardless of send-eligibility.
- [ ] 3.2 A typed-but-unsent draft survives an app kill and gets sent the next
      time this device can legally send (persisted on close, not only on
      successful network completion).
- [ ] 3.3 Closing with an empty draft takes the exact same code path as a real
      comment — no separate "declined" branch to verify independently.
- [ ] 3.4 With the debug-shortened window: a player who never reopens the app
      has their comment resolved to blank once the *other* player's device
      times it out (per the open design question above) — confirm this does
      NOT depend on the silent player's device ever running again.
- [ ] 3.5 A player who returns and comments just under the wire (window not
      yet expired) is not pre-empted by the timeout logic.

## 4. Badging

Two existing systems (`Badges.lua`, `Main.lua:880-973`), both currently driven
by `_isMyTurnOpenMatch` — true for ANY non-GK-ended match where it's your
turn, with no concept of gate 1/2:

- [ ] 4.1 `_isMyTurnOpenMatch`/`refreshPendingMatchesForBadge` excludes
      matches that are gate-1-complete (both scores in), even while GK still
      lists you as `currentParticipant` for a silent relay/comment leg — the
      bouncing menu badge and home-screen count must not nag "come play" for
      a match with nothing left to play.
- [ ] 4.2 New records-list badge appears on a match row once it reaches gate 1
      and the player hasn't yet opened it.
- [ ] 4.3 That badge reappears/updates when a new comment arrives via a
      background leg, even on a match already viewed once.
- [ ] 4.4 Opening a match's detail/end screen clears only that match's badge,
      not others.
- [ ] 4.5 Existing `matchBadgeSuppressed()` overlay-suppression (badge
      shouldn't float over other open panels) still applies correctly to any
      new records-list badge surfaces.

## 5. Notification (badge-count) sending

- [ ] 5.1 Confirm current scope stays accurate: only `applicationIconBadgeNumber`
      + a badge-only `UNUserNotificationCenter` permission request exist today
      — no push/local notification banners are wired up anywhere in the
      codebase. Re-check this before assuming richer suppression work exists
      to do.
- [ ] 5.2 `refreshHomeScreenBadgeFromGCMatches`'s count gets the same gate-1
      exclusion as 4.1 — this is the concrete redundant-signal bug: today it
      inflates the home-screen number for matches sitting in the silent
      comment-relay phase.
- [ ] 5.3 (Not testable today, flag only) If real push notifications are ever
      added, note that GameKit's own system "it's your turn" push is tied
      directly to `endTurnWithNextParticipants` and isn't selectively
      suppressible per-call — a platform constraint to design around later,
      not a bug to chase now.
