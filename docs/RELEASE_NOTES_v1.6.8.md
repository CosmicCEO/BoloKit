# v1.6.8 — Guest spawn, camera, and pill sync

Tagged 2026-09-27 on merge commit `30c39a5` ([PR #168](https://github.com/CosmicCEO/BoloKit/pull/168)).

## Summary

Patch on top of `v1.6.7`. Two live-play reports from Jerod, both guest-only: the guest's screen
stayed on the wrong part of the map after joining, with base icons showing in unexplored fog;
and a guest that died carrying pills could not pick them back up, then died at once driving onto
the centre one, which the host showed as a damaged live pillbox. Both were reproduced with a
real host and a real join client in one test process before anything was changed.

## Fixed since v1.6.7

- **Guest spawned twice.** `applyBoloPreamble` spawns the guest locally at a random start; the
  host, which simulates guest tanks, then picks its own start and teleports the guest there
  (`SRTankStatus`). The camera centred once on the first pick and never moved, and the first
  pick counted as a fog vision source.
  - **Fix:** the join path starts the local player dead until the host places it
    (`joinPathInitialState`, `GameSession.swift`). `GameRenderView` re-centres whenever the
    local player goes dead -> alive, matching `refresh:`'s `client.spawned` check in the
    reference (`GSXBoloController.m:2574-2598`). Host and solo respawns re-centre too.
- **Own-pill pickups were never reported.** The host's per-tick capture broadcast was keyed on
  a pill's owner changing. A guest re-collecting pills it already owned changed only
  ground -> onboard, so the guest never saw them leave the ground.
  - **Fix:** the diff in `HostGameEngine.tick()` also reports ground -> onboard.
- **Guest counted pill damage twice.** A join client's dead-reckoning ran `shellTick` for
  remote shells against its own world, damaging pills locally on top of the host's `SRDamage`.
  The guest's armour ran low, so a pill the host held at armour 1 looked destroyed; driving
  onto it made the host `superboom` the guest.
  - **Fix:** `applyRemotePlayerUpdate` takes `extrapolationMutatesWorld`; `UDPSession` passes
    `false`, keeping player state and discarding pill, base, and terrain changes.
- **Stale fog test.** `aLivePlayerWithinItsOwnVisionRectResolvesLive` left its player dead and
  had been failing since `cb1f456`. The player is now alive.

## Testing

Nine new tests in `Bolo 2026Tests`: `SpawnRecenterTests` (4), `JoinPathSpawnTests` (2),
`PillDesyncReproTests` (2), and one camera test in `GameViewFocusRoutingTests`. App suite is
162 tests. Each new test fails with its fix removed.

Live-verified by Jerod on the 1.6.8 Desktop build, 2026-09-27: every previously observed
issue is gone and nothing new appeared.

Known, not resolved in this release:

- The two `PillDesyncReproTests` and the older
  `guestRequestingAndLeavingAnAllianceUpdatesItsOwnState` pass when their suite runs alone and
  fail inside the full app run, parallel or serial. The alliance test fails the same way
  without this release's changes. Cause not found.
- `swift test` hung twice during this work and was stopped. Of the package tests that ran,
  `dispatchBuildRoadTerrainByteMatchesTheNewTerrainD40` failed, including before any package
  source was changed.

## Found, not fixed

- A guest builder's pill repair costs no trees: the host never deducts them.
- A guest builder killed while carrying a pill drops it locally only (from code reading).
- No tank-follow scrolling; the reference re-centres near the view edge
  (`GSXBoloController.m:2600-2619`).

## Docs

`HOSTMODELS.md` moved out of `docs/notes/`; the two-Mac fog script, its run notes, and
`U.S.A.map` removed, with references updated.
