# v1.6.9 — Guest builder resource accounting

Tagged 2026-09-28.

## Summary

Patch on top of `v1.6.8`. Two guest-only accounting defects, both found while reproducing the
v1.6.8 pill desync with a real host and a real join client in one test process: a guest's
builder work cost it nothing, because the host's stale copy of the guest's resources was
pushed back onto the guest. Both were reproduced in that harness before anything was changed.

## Fixed since v1.6.8

- **Guest builder spends were refunded ([#171](https://github.com/CosmicCEO/BoloKit/issues/171),
  [PR #173](https://github.com/CosmicCEO/BoloKit/pull/173)).** A guest deducts trees locally
  when its builder launches (repair, road, wall, boat, pill) and carries them out. The host
  never learns of the spend, so its own count for the guest stays at the old value, and any
  later `SRTankStatus` (a fired shell, a hit, a refuel) put that count back on the guest while
  the builder still carried the spent trees. Repairs and builds were free, and harvested trees
  were wiped the same way. Wider than the issue's repair case: a road reproduced it too.
  - **Fix:** `recvSrTankStatus` applies the host's `trees` only with a respawn teleport, the one
    time the host really resets them (`Spawn.swift`). Trees belong to the guest, as in the
    reference, where the server keeps no tree count. No wire change.
- **Guest builder mine placement never cost the host a mine
  ([#174](https://github.com/CosmicCEO/BoloKit/issues/174),
  [PR #176](https://github.com/CosmicCEO/BoloKit/pull/176)).** Same shape, different fix. A
  guest's mine count is the host's (`SRTankStatus`, key-drop, base refuel), but its builder
  spends one locally at launch and the host never did: after one placement the guest read 39
  and the host 40, and any later status handed the mine back.
  - **Fix:** `HostSession` spends one of a host-simulated player's mines on `CLPlaceMine`,
    clamped at zero, mirroring the existing key-drop path. Spent whether or not the tile takes
    it; the reference never refunds a builder-placed mine. Without host simulation the guest
    still owns its count. Mines cannot be handed back to the guest the way trees were, since the
    host is authoritative for them. The reference server keeps no mine count either, so the
    deduction is port-only.

## Testing

- `BoloKitTests`: 650 to 652 (two new `recvSrTankStatus` tests; one existing test no longer
  pins the removed behaviour). `DifferentialTests`: four new `HostSessionTests` dispatch tests.
- `Bolo 2026Tests`: `PillDesyncReproTests` 2 to 5 tests. Three are new and parameterised (a
  guest pill repair, road, and mine placement, each with and without a shot mid-trip), real
  host and real guest. Without the fixes they fail in 5 of 16 case-runs (trees) and 2 of 2
  (mines); with them all six cases passed in each of 4 repeated iterations.
- `makeHost` in that suite gained a `hiddenMines` parameter (default unchanged): the builder
  tests turn Hidden Mines off, because fog-redacted tiles read as solid sea to a builder.

Live-verified by Jerod on two Macs, 2026-09-28, on a Desktop build of the #171 fix: the tree
cost stays paid after shots mid-trip and harvested trees survive. **The #174 mine-placement fix
is harness-verified only; it has not been checked in live two-Mac play.**

Known, not resolved in this release:

- The two original `PillDesyncReproTests` and the older
  `guestRequestingAndLeavingAnAllianceUpdatesItsOwnState` pass when their suite runs alone and
  can fail inside the full app run. Cause not found.
- `swift test` hangs at 0% CPU on real-socket dispatch tests and had to be stopped, twice this
  cycle. `dispatchBuildRoadTerrainByteMatchesTheNewTerrainD40` hangs when run alone, with and
  without this release's changes, and fails in a broader run.

## Found, not fixed

- A guest builder killed en route keeps its local mine or tree deduction until the next status
  (from code reading, not reproduced).
- A guest builder killed while carrying a pill drops it locally only (from code reading).
- No tank-follow scrolling ([#172](https://github.com/CosmicCEO/BoloKit/issues/172)); the
  reference re-centres near the view edge (`GSXBoloController.m:2600-2619`).

## Docs

The v1.5.1 two-Mac fog test artifacts (`.docx` and `.pdf` copies) and `docs/Small.map` were
removed ([PR #175](https://github.com/CosmicCEO/BoloKit/pull/175)); still in git history.
