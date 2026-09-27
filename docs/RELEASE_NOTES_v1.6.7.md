# v1.6.7 — Guest fog undraw + status-panel label scramble

Tagged 2026-09-27.

## Summary

Patch on top of `v1.6.6`. After the prior join-time fog fix ([#163](https://github.com/CosmicCEO/BoloKit/issues/163)), Jerod's continued live play surfaced three further ways the guest client's view diverged from the host's: stray pill/base icons in unexplored territory, the trailing edge of explored terrain reverting to plain ocean while moving, and the Status panel's Pillbox/Base rows showing each other's content (confirmed live via a side-by-side host/client screenshot). All three root-caused and fixed — see [#164](https://github.com/CosmicCEO/BoloKit/issues/164).

## Fixed since v1.6.6

- **Fog "undraw" race (also explains the residual pill/base leak).** `#159`'s join/solo client computes its own local fog (`updateFogVisionTracker`) the instant its vision rect covers a cell, but the host separately redacts and streams terrain over the wire (`SRRevealTerrain`) — a second, uncoordinated fog computation the C oracle never needed (one fog tracker per process, always full ground truth). If the local 0→1 snapshot raced ahead of the matching reveal packet, a stale placeholder got permanently baked into `seenTiles`; invisible while the cell stayed visible (the live-render branch masks it), it surfaced later as a bogus revert to ocean, or a stuck pill/base icon, once vision moved on.
  - **Fix:** `decreaseVis` (`Sources/BoloKit/FogState.swift`) now re-samples `seenTiles` from live ground truth at the exact moment a cell's `fog` count reaches 0 — a last-visible-moment refresh instead of trusting the (possibly stale) first-sight snapshot. Additive to the oracle's `decreasevis()` (which never touched `seentiles`); a no-op whenever there was no race. Threaded through all 8 call sites in `FogState.swift` and `Sources/BoloNet/HostGameEngine.swift`.
- **Scrambled Pillbox/Base status labels.** `PlayerStatusGrid.list(snapshot:)` (`Bolo 2026/Bolo 2026/PlayerStatusView.swift`) built one SwiftUI `List` with three `Section`s (Players, Pillboxes, Bases), each `ForEach` using plain, overlapping small-integer ids — `List` row-diffing operates over the whole list's identity space, not scoped per `Section`, so a pill at offset 0 and a base at offset 0 were indistinguishable to it. Confirmed live: the host's Pillboxes section showed Base names/status, the client's Bases section showed Pillbox names/status, each device scrambled differently.
  - **Fix:** every row now carries a globally-unique id (`"player-\(index)"` / `"pillbox-\(offset)"` / `"base-\(offset)"`).

## Testing

New regression test `testDecreaseVisRefreshesTheSnapshotFromLiveGroundTruthWhenVisionIsLost` (`Tests/DifferentialTests/FogDifferentialTests.swift`). `FogDifferentialTests` 43/43 green (was 42/42 — one net-new test). `HostGameEngineTests` 44/45 green plus 1 pre-existing, already-documented flaky timing test (`hostGameEngineBroadcastsExactlyAtTheTimeLimitBoundaryTickThenNeverAgain`, see `docs/STATUS.md`'s "Tests" line), confirmed passing in isolation and unrelated to this change. Live re-verified by Jerod on real host/join windows: trailing-edge fog draw and Status panel both confirmed fixed.

See `docs/STATUS.md` for full detail.
