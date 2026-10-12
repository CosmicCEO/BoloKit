# v1.6.10 — Tick budget and guest accuracy

Prepared 2026-10-12 from the Improve phase of the host/client benchmark project
([PR #195](https://github.com/CosmicCEO/BoloKit/pull/195)).

## Summary

Patch on top of `v1.6.9`. Four changes, each chosen because the benchmark measured a cause and
a baseline for it: the sound player no longer decodes audio on the main thread, remote tanks are
smoothed on a guest, a guest no longer gets a carried mine refunded, and a guest refreshes its
fog memory when the host reveals a tile it has already seen. No wire change: the five files that
fix the byte layout of every message are identical to `v1.6.9`. A game with one `v1.6.10` and
one `v1.6.9` player was not played live for this release.

The numbers come from 90 pair runs and 20 sweep runs, none invalid, compared with the frozen
`v1.6.9` baseline. The proof session ran on macOS 27.0.1 and the baseline on 27.0; see
"Found, not fixed".

## Changed since v1.6.9

- **Sound player (Improve 2D).** `SoundPlayer.play` read and decoded each sound from disk on the
  main thread, 19 to 26 ms at the 95th percentile on ticks that play a sound, and the host's
  50 Hz tick waits for that thread. Sounds are now preloaded into memory and played through an
  `AVAudioEngine` with a pool of player nodes. A play now costs about 0.1 ms.
  - Host tick, 95th percentile: 14 to 8 ms in the soak, 17 to 9 ms at 2 players, 19 to 10 ms at 4,
    28 to 10 ms at 16.
  - Ticks later than 25 ms: 2.3% to 0.3% in the soak, 3.5% to 0.3% at 2 players, 3.9% to 0.6% at 4.
  - Jerod playtested the sound on 2026-10-12 and found it on target.
- **Remote tank smoothing (Improve 1A).** The smoother was keyed on `state.ticks`, which never
  advances on a guest, so it always snapped. It is now driven by a counter the view owns, and it
  still snaps on a respawn or a jump of more than 4 tiles. The host tank's drawn step on the
  guest fell from a median of 100 ms to 25 to 32 ms in moving scenarios.
- **Mine refund (Improve 3B).** A guest spends a mine when its builder launches, but the host
  spends its own only when the builder arrives. A status message sent during the walk wrote the
  host's pre-launch count over the guest's. `recvSrTankStatus` now subtracts the mine the
  builder is carrying. Mine-count differences between host and guest in the soaks: 10 episodes to 1.
- **Fog memory on a reveal (Improve 4B).** When the host reveals a mined tile the guest has
  already seen, the guest now refreshes its memory of it. Before, a tile that fell back into fog
  was drawn from the stale plain-ground snapshot. `TCPSession` has a new
  `onTerrainRevealed` callback and `GameSession` applies it.

## Testing

- `BoloKitTests`: 666 pass in 15 suites. The two known-issue tests recorded for 3B and 4B in the
  Analyze phase are now plain passing tests.
- `Bolo 2026Tests`: a new `SoundPlayerPlayTimingTests` check measures the main-thread cost of a
  play (20.9 ms before, 0.1 ms after).
- Two new `RemotePositionSmoother` tests; ten pass.
- The Release app builds. The Improve wire check passes: the five byte-layout files are identical
  to `v1.6.9`.
- Benchmark: `Bench/data/improve/candidate1-2d-1a-4b-3b/` (frozen, tag
  `improve/candidate1-2d-1a-4b-3b`). Reading: `Bench/4-improve/RESULTS.md`.

## Found, not fixed

- **The proof session ran on a newer macOS than the baseline** (27.0.1 against 27.0). Simulation
  code none of these changes touch is 36 to 48% slower in medians, so medians moved with the
  machine. The tail gains above are much larger than that shift. A same-OS control run of the
  old build is [#197](https://github.com/CosmicCEO/BoloKit/issues/197).
- **4B is not shown by the soak.** Its signature is nearly absent in both sessions. The fog
  memory faults that remain are mostly tiles one side has seen and the other has not. Open as
  part of [#198](https://github.com/CosmicCEO/BoloKit/issues/198).
- **1A reaches 25 to 32 ms, not the 20 ms target**, which is the floor at 50 frames a second.
  Also in [#198](https://github.com/CosmicCEO/BoloKit/issues/198).
- **Three shell-count episodes** (guest 3 above the host for 0.5 to 0.7 s) appear in the new
  soaks and none in the baseline. Nothing in this release touches shells. Also in
  [#198](https://github.com/CosmicCEO/BoloKit/issues/198).
- The two flaky timing test classes named in `docs/STATUS.md` are unchanged.

## Benchmark tooling in this release

Everything below is development tooling and is off in play. The recorder is compiled in and runs
only when `BOLO_BENCH` is set.

- Host/client measurement system and the frozen `v1.6.9` baseline
  ([PR #185](https://github.com/CosmicCEO/BoloKit/pull/185)), the Analyze phase
  ([PR #186](https://github.com/CosmicCEO/BoloKit/pull/186),
  [#192](https://github.com/CosmicCEO/BoloKit/pull/192),
  [#193](https://github.com/CosmicCEO/BoloKit/pull/193)) and the Improve phase
  ([PR #194](https://github.com/CosmicCEO/BoloKit/pull/194),
  [#195](https://github.com/CosmicCEO/BoloKit/pull/195)).
- `run-baseline.sh` moves a finished session's raw logs to the archive disk.
- `check-no-wire-change.sh` has an `improve` mode that fails only on a change to one of the five
  byte-layout files.
