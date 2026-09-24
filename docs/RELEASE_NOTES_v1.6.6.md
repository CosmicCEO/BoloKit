# v1.6.6 — Visibility Parity

Tagged 2026-09-24.

## Summary

Fifth theme in the `1.6.x` visual + play parity arc (man/tank/boat/sound, `v1.6.5`) that Jerod's
original roadmap ruling missed: forest concealment. Live-observed and reported: a tank entering
forested terrain should become progressively less visible with distance and cover -- never
fully invisible up close, fading in as an observer approaches.

## Fixed since v1.6.5

- [#153](https://github.com/CosmicCEO/BoloKit/issues/153) -- forest concealment (`forestvis()`/
  `calcvis()`, `bolo.c:174`/`217-321`) was already a faithful, differentially-tested port
  (`Sources/BoloKit/CalcVis.swift`, `Sources/BoloKit/PillTick.swift`) and already wired into
  rendering (`GameRenderView.swift`'s `visFraction`) -- but gated behind `state.hiddenMines`
  being on *and* a `fogState` existing. Forest concealment is core, always-on oracle gameplay,
  unrelated to the separate Hidden Mines fog-of-war feature (#1); the default (`hiddenMines`
  off) meant it never fired at all.
- **Host/client asymmetry, confirmed live:** the host got concealment (when Hidden Mines was
  on), but a joined guest never did, in any mode -- `GameRenderView.render(_:fogState:)` defaults
  `fogState` to `nil`, and only the host render path ever supplied a real one. Forest
  concealment only ever needed `state.terrain` (already synced to guests), never `fogState`
  itself -- only the *fog* term did.
- **Fix:** `calcVis` now accepts `fogState: FogState?`; a missing one means "no fog
  contribution," not "skip forest concealment." `visFraction`'s tank/walking-builder path
  (matching the oracle's own per-sprite-kind `calcvis()` choice) always calls `calcVis` now.
  Fixes host, solo, and join uniformly through the same render call sites -- no join-path-
  specific change needed. The parachuting-builder state deliberately stays on plain `fogVis`
  (`GSBoloView.m:389` uses `fogvis`, not `calcvis`, for an airborne builder -- correct oracle
  behavior, not a gap).
- Softened the sea/river water textures (`applySeaShading`/`applyRiverFlow`,
  `GlyphSource.swift`) -- reported as too bold/high-contrast; halved each texture's color delta
  from its base fill.

## Testing

4 new differential unit tests (`FogDifferentialTests.swift`, `calcVis` with `fogState: nil`)
plus 2 new offscreen pixel-diff render tests (`VisibilityParityTests.swift`) confirming the
actual reported symptom: a forest-buried enemy tank renders differently than one in the open
with no `fogState` at all, and more visibly the closer the observer gets. 148/148 `Bolo
2026Tests` and 956/956 SwiftPM tests green (known pre-existing timing/port-contention flakes,
confirmed unrelated and passing in isolation).

See `docs/STATUS.md` for full detail.
