# Merging `laptop-work` into `main` — brief

Written for whoever executes this merge (likely a fresh Opus session — this
doc exists so it doesn't have to rediscover any of this). Base: both branches
fork from `88eebfc`. `main` currently has two commits on top
(`642c99a` relay/comment/badge rework, `2213cf0` confetti depth effect).
`laptop-work` has four (below). Do NOT `git merge`/`git rebase` mechanically —
several of these conflicts are semantic (a target function no longer exists
in the shape a laptop-work diff expects), not just textual. Go file by file.

## Commit disposition

| Commit | Verdict |
|---|---|
| `876df86` Fix handshake lockout; rename to Vivaldiku | **Split** — see below, do not take or drop wholesale |
| `d59fbd1` Replace GC matchmaker with app-drawn vs overlay | **Keep**, adapting the badge hook (see Badges.lua) |
| `118d24b` Momentum scrolling, Quick Start, W/L sync on every turn | **Keep**, porting the record-sync fix's *intent* (see GameCenter.lua) |
| `566ea85` Document momentum/Quick Start/sync in HANDOFF.md | **Keep** as-is, pure docs |

`876df86` bundles four unrelated things — resist the urge to take-or-drop it
as a unit:
1. A `clearPendingHandshakeForMatch` helper + two call sites — **drop**.
   Superseded: `onLegSendSucceeded` (main's rework) already clears
   `pendingTurnSendsByMatchId[matchId]` generically on any successful send,
   handshake or otherwise, so the redundant-resend problem this guarded
   against can't occur in main's version.
2. Removing `if awaitingHandshakeSend then return end` from `touched()`'s
   `STATE_READY` branch in `Main.lua` — **keep**. Real, independent bug: it
   blocks the match creator from tapping to start (or quit) while their
   handshake is still sending. Main's rework never touched this gate, so
   it's still present and broken on `main` today. Not simultaneous-play
   *protocol* work — it's a UI-blocking bug — so it's not covered by
   "except the simultaneous-play stuff."
3. `tbm:setLogging(isRunningOnSimulator())` in `setup()` — **keep**. Turns on
   dormant verbose GameKit logging on the simulator only. Unrelated to
   either side's protocol work.
4. The Vivaldiku rename (display name, loading screen text, `CLAUDE.md`,
   `STRUCTURE.md`, `HANDOFF.md`) — **drop**. Keep "Vivaldi-ku" (hyphenated)
   everywhere these commits touch it.

## File-by-file

**No conflict — take laptop-work's version wholesale:**
`MatchSelection.lua` (new file), `HaikuMenu.lua`, `Helpers.lua`,
`EndScreen.lua`, `OverlayPanels.lua`, `CodeaTurnBasedMatches.lua` (removes
the now-dead native-matchmaker delegate; nothing on `main`'s side calls it).

**No conflict — keep main's version wholesale:**
`opponentRecords.lua`, `qMatch_qPlayer.lua`, `ConfettiEffectsEtc.lua`,
`tests/`, `MULTIPLAYER_TEST_PLAN.md`. None of these appear in any
laptop-work commit's file list — verified via `git show --stat` on all
three substantive commits, not assumed.

**`Badges.lua` — take laptop-work's rewrite wholesale, do NOT bring back
main's polling.** Laptop-work deletes the entire old
`matchBadge`/`refreshPendingMatchesForBadge`/`updateMatchBadgeStatus`/
`_isMyTurnOpenMatch`/`updateMatchBadge(dt)` apparatus that main's
`refreshMatchStoryBadges` (the "game ended"/"opponent commented" badges)
was built by extending. That whole mechanism is gone, replaced by a static
dot on the vs button + a `quickStart` component, both driven by
`MatchSelection.lua`'s `vsListEntries`/`vsHasActionable`. Do not re-add any
of the deleted functions. `main`'s `refreshMatchStoryBadges` function itself
should be **deleted** from `Badges.lua` — its logic moves into
`MatchSelection.lua` (next item), not merged here.

**Port the two-badges logic into `MatchSelection.lua`'s `refreshVsMatchesList`
instead of running a second poll.** This is the one real re-homing job.
`refreshVsMatchesList` (laptop-work) already does almost exactly what
`refreshMatchStoryBadges` (main) did independently: loads every GameKit
match, decodes it via `makeQMatchFromGK`, and computes `me`/`oppData`/`oppId`
per match. Running both would mean two redundant `loadMatchesWithCompletionHandler_`
calls that could disagree. Instead, inside `refreshVsMatchesList`'s per-match
loop (`Quozzy.codea/MatchSelection.lua`, the `for i = 1, n do ... end` block,
right where it currently builds `entry`), add a call to
`computeMatchBadges`-equivalent logic using the already-decoded `q`/`oppData`
— `q.id`, `oppId`, `me and oppData and me.didPlay and oppData.didPlay` for
`bothPlayed`, `oppData and oppData.comment` for the comment check — and set
`endedMatchBadgeIds[q.id]`/`commentMatchBadgeIds[q.id]` accordingly (those
two globals, and `matchNeedsEndedBadge`/`matchNeedsCommentBadge`/
`findMatchHistoryEntry`, are untouched in `opponentRecords.lua` — reuse them
directly, don't reimplement).

One correctness note: `refreshVsMatchesList` explicitly **excludes**
`ended and viewed` matches from `vsListEntries` (via `vsMatchAlreadyViewed`,
which only checks `m.complete`). That's fine for the vs-list's purpose, but
wrong for the comment badge: a match already marked complete in history can
still get a *new* opponent comment later, and `matchNeedsCommentBadge`
(main's function) correctly detects that by comparing comment *text*, not
just a viewed flag. Compute the badge sets from **every** decoded match, not
only the ones that survive into `vsListEntries`.

`RecordsUI.lua`'s badge-dot draw calls (in `drawRecordsOpponentsList` and
`drawRecordsMatchesList`, right after each `_drawRowCard(...)` call) don't
need to change — they already just read `endedMatchBadgeIds`/
`commentMatchBadgeIds` by match id, wherever those tables get populated from.

**`GameCenter.lua`:**
- Drop `876df86`'s `clearPendingHandshakeForMatch` (see above).
- Port `118d24b`'s intent, not its diff: it attaches `buildRecordSyncForOpponent`
  to the handshake leg (previously only the comment-pass/finalize legs carried
  it, so a match abandoned right after creation never synced). Its diff
  targets the old `beginInitialHandshakeSend`'s inline body, which no longer
  exists — main's version routes all leg-building through `attemptLegSend`,
  which currently only attaches `recordSync` for the `"result"` branch
  (search `elseif leg == "result" then` in `attemptLegSend`). Add the same
  `buildRecordSyncForOpponent(oppId, alias, myId, nil)` attachment to the
  `"handshake"` branch (`if leg == "handshake" then`) too.
- Everything else — `computeNextOwedLeg`/`attemptLegSend`/
  `attemptPendingLegSend`/`onLegSendSucceeded`/`decideComment`/the loosened
  `currentFinalCommentPhase`/the extended `enterQMatch` merge-guard and
  `needsInitialHandshake` flag threading — is untouched by any laptop-work
  commit. Keep all of it as-is.

**`Main.lua`:**
- Take the `touched()` STATE_READY fix and `tbm:setLogging(...)` from
  `876df86` (see above); drop its rename text changes.
- Take laptop-work's vs-button wiring wholesale (`openVsOverlay()` replacing
  `tbm:showMatchmaker()`, `drawVsOverlay()`, `handleVsOverlayTouch`,
  `updateQuickStart(DeltaTime)`, `drawVsButtonBadge(...)` in the draw loop) —
  this is the actual matchmaking-UI replacement the user wants kept.
- Merge the four GameKit callbacks by hand, since both sides touch them:
  - `uponDetectingAuthentication`: add laptop-work's `refreshVsMatchesList("auth")`
    alongside main's `requestPendingHandshakeResendCheck("auth")` — both stay.
  - `onReceivingTurn`: take laptop-work's version wholesale (adds debug
    logging, `mergeOpponentRecordFromTurnData`, `refreshVsMatchesList("receivingTurn")`
    around the same `makeQMatchFromGK`/`enterQMatch(q)` call main already has
    unchanged). No adaptation needed — main's `enterQMatch` already calls
    `attemptLegSend` internally, so nothing extra is required here for the
    relay logic.
  - `onTurnEnded`: **this is the one true line-level conflict.** Laptop-work
    adds `refreshHomeScreenBadgeFromGCMatches("turnEnded")` and
    `refreshVsMatchesList("turnEnded")` before the old inline
    `pendingTurnSendsByMatchId[mid] = nil; ...` cleanup block; main replaced
    that same block with a call to `onLegSendSucceeded(mid)`. Keep both
    additions, call `onLegSendSucceeded(mid)` in place of the old inline
    block:
    ```lua
    tbm:onTurnEnded(function(gkMatch, dataTable)
      refreshHomeScreenBadgeFromGCMatches("turnEnded")
      refreshVsMatchesList("turnEnded")
      local mid = gkMatch and gkMatch.matchID
      if mid then
        onLegSendSucceeded(mid)
      end
    end)
    ```
  - Foreground handler: add laptop-work's `refreshVsMatchesList("foreground")`
    alongside main's existing `requestPendingHandshakeResendCheck("foreground")`.
- Keep main's `retryPendingHandshakeSends`/`requestPendingHandshakeResendCheck`
  as-is — laptop-work never touched them, main's version (comment-timeout
  sweep + `attemptPendingLegSend`) is a strict superset.
- Re-add `loadFinishedAwaitingDecision()` next to `loadPendingTurnSends()` in
  `setup()` — pure addition from main, no laptop-work equivalent to conflict
  with.
- Drop the rename's three `"Vivaldi-ku"` → `"Vivaldiku"` text-literal changes
  in the loading-screen generator.

**`RecordsUI.lua`:**
Low actual overlap despite three-way file touches — verified by diff, not
assumed. Laptop-work's edits are `_truncateWithEllipsis`/`_drawRowCard`
(local→global) and a `clampPanelTopToSafeArea` call in `drawRecordsOverlay`
(`d59fbd1`), plus momentum-scroll variables and inertia application near the
`maxScroll` clamp at the *bottom* of `drawRecordsOpponentsList`/
`drawRecordsMatchesList` (`118d24b`). Main's badge-dot calls sit near the
*top* of the same two functions, right after each `_drawRowCard(...)` call
in the per-row loop. Take laptop-work's file as the base and re-apply main's
two badge-dot call sites plus the `_drawMatchStoryBadgeDots`/
`_opponentHasMatchStoryBadge` helper functions — they don't touch any line
laptop-work changed.

**`CLAUDE.md` / `Quozzy/Info.plist`:** Drop the rename, but don't revert
`Info.plist` wholesale — `876df86` also fills in a previously-empty
`NSGKFriendListUsageDescription` ("Vivaldiku shows your Game Center friends
so you can start a match against them."), which `d59fbd1`'s friends-picker
feature (`vsLoadFriends`/`vsOpenNativeGameCenterFriends`) likely needs
populated to avoid an iOS permission-prompt crash. Keep that string, just
say "Vivaldi-ku" instead of "Vivaldiku" in it.

**`STRUCTURE.md` / `HANDOFF.md`:** Docs, additive on both sides in different
sections. Take laptop-work's additions, re-apply `MULTIPLAYER_TEST_PLAN.md`-
adjacent notes if any were added to `STRUCTURE.md` by main's commits (check;
main's commits this session didn't touch `STRUCTURE.md` directly, so this is
likely a non-issue).

## Not yet checked — worth a quick look before or during execution

- `HaikuMenu.lua`'s exact vs-button touch handler (confirm it calls
  `openVsOverlay()` and nothing from the old matchmaker path survives there).
- Whether `118d24b`'s Quick Start re-implementation in `Badges.lua` has any
  dependency on the old `pendingTurnMatches` debug hook
  (`storePendingTurnMatch`/`removePendingMatchById`/`clearPendingMatches`
  still exist per the "legacy store" comment) that main's `GameCenter.lua`
  debug parameter actions rely on — low risk, quick to verify.

## Execution order suggestion

1. Rename revert + `876df86` split (small, mechanical, do first).
2. Take the wholesale-laptop-work files.
3. `GameCenter.lua` reconciliation (record-sync port).
4. `Main.lua` callback merge.
5. `Badges.lua` replacement + `MatchSelection.lua` badge port.
6. `RecordsUI.lua` re-apply.
7. Run `lua tests/run_tests.lua` after every step from #3 onward — it doesn't
   cover the new vs-overlay UI, but it will catch any regression to the
   relay/comment/badge logic the merge disturbs. 125 passing before you
   start; should still be 125 after, possibly plus new assertions for the
   ported record-sync-on-handshake behavior.
8. Two-device GameKit verification remains required regardless (see
   `MULTIPLAYER_TEST_PLAN.md`'s test environment section) — nothing here
   substitutes for that.
