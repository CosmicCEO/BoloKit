# v1.6.5 — Visual & Play Parity Arc

Tagged 2026-09-24.

## Summary

Bundles everything that landed on `main` since `v1.6.0`: the visual-polish milestone (`v1.6.1`,
#137/#140/#110) and the full four-theme visual/play parity arc Jerod scoped on 2026-09-23 --
one theme per release in name (`v1.6.2` man, `v1.6.3` tank, `v1.6.4` boat, `v1.6.5` sound) but
none tagged individually as they landed, so all four ship together here -- plus #139, a real
host-engine crash fix found via a live crash-log audit, not a parity item.

## Fixed / added since v1.6.0

**Visual polish (`v1.6.1`, milestone 21):**
- #137 -- black seam lines in the live Metal terrain overlay, fixed at the geometry level
  (quad padding in `MetalTileRenderer.swift`).
- #140 -- a joined guest's `connectionAge(for:)` had no data for other players, so lag-tint
  staleness coloring silently disappeared on the client's own HUD; host/guest panels now match.
- #110 -- all 7 procedural terrain families (sea, grass, swamp, forest, river, boat, crater,
  road) now have distinct autotiled textures instead of flat fills; still 100% procedural, no
  imported art (hard constraint).

**Man parity (`v1.6.2`, milestone 23):**
- #146 -- the builder ("little green man") had no visual identity at all, a placeholder growing
  square for every frame; now a walking-figure silhouette (BUILD0/BUILD1) and a parachute-canopy
  silhouette (BUILD2).
- #145 -- tank-crush-builder, a disclosed new mechanic (real memory of the original, not shown
  in the `Reference/c` oracle): a tank overlapping an enemy builder's tile now kills it, reusing
  the existing `killBuilder` respawn-as-parachute path.

**Tank parity (`v1.6.3`, milestone 24):**
- #147 -- a boated tank rendered pixel-identical to a land tank; `GlyphRole.tank` had no `boat`
  parameter, so the already-correct sprite-row selection never actually changed anything on
  screen. Added a distinct hull silhouette.

**Boat parity (`v1.6.4`, milestone 25):**
- #148 -- boarding a boat never set `player.boat = true` on the host's authoritative state,
  under any connection topology -- the root cause of a live "boats don't look like boats"
  report, and the reason #147's new hull sprite had no live trigger until this fixed it.

**Sound parity (`v1.6.5`, milestone 26):**
- #149 -- a real networked host and a joined guest played **zero** gameplay sound; `SoundPlayer`
  was only ever reachable from the single-process/solo tick loop. Added
  `HostGameEngine.onShouldPlaySound`, wired the same way the existing render/message callbacks
  are, plus the join path's local-prediction call sites.
- #150 -- sound played "near" unconditionally regardless of distance. Fixed for the host path
  whenever Hidden Mines is on, reusing the existing `FogState`/`isFog` machinery. The larger,
  always-on vision-system extension needed for full parity on every mode/path is a real, known
  gap but was explicitly ruled out of scope for solo play (this port's primary mode has no
  second listener for a far-sound distinction to matter to) -- parked in the `Decide: Oracle
  parking lot` milestone, not silently dropped.

**Host-engine crash fix (#139, not a parity item, milestone 20):**
- A hosted session left running for hours crashed with `SIGABRT` -- corrupted `Array` refcounts
  on `GameState.local`. Root cause: `GameSession`'s `adminState`/`liveState` read
  `HostGameEngine.state` directly, a plain stored property mutated off-main by the engine's own
  tick-loop `Task`, racing that mutation from the `@MainActor` HUD/admin-panel read path. Fixed
  by caching the already-safe value-type snapshot `HostGameEngine` hands to `onTickRendered`
  (the one sanctioned way to get `state` off the tick loop) instead of reading the live property.

## Testing

Every fix above has its own regression test. Full `swift test` (956 SwiftPM tests) and
`xcodebuild test -scheme "Bolo 2026" -destination "platform=macOS"` (146 tests) both green at
merge, modulo the documented pre-existing real-clock/port-contention flakes under full parallel
runs (`hostGameEngineSubmitPauseResumeServerTogglesPauseState`,
`hostGameEngineBroadcastsExactlyAtTheTimeLimitBoundaryTickThenNeverAgain`,
`aSimulatedGuestDrivingOntoAMineDetonatesItAndLosesArmour`), each individually confirmed
unrelated and passing in isolation.

See `docs/STATUS.md` for the full milestone-by-milestone detail this summary condenses.
