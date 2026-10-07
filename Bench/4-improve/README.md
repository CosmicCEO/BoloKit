# Improve phase

**Status: open 2026-10-02.** Decided by Jerod on closing Analyze. Four items, each with a
demonstrated cause and a measured, repeatable baseline.

| Item | Implemented | Unit proof | Session proof |
|---|---|---|---|
| 2D sound player | Yes, branch `improve/2d-sound-player` | `play()` 20.9 ms to 0.1 ms on the main thread | Waiting: one session for all four items |
| 1A smoother | Yes, same branch | Two new smoother tests, ten pass | Same |
| 4B fog memory on reveal | Yes, 2026-10-07: `refreshFogMemoryForRevealedTile`, called from `GameSession` after a reveal | The 4B test is now a plain passing test | Same |
| 3B status refund | Yes, 2026-10-07: `recvSrTankStatus` subtracts `builderMines` | The 3B test is now a plain passing test | Same |

**Blocker for the session proof:** `run-baseline.sh` runs `check-no-wire-change.sh`, which
fails on any edited BoloKit file, and 1A, 4B and 3B each edit one. M2 itself holds: the five
byte-layout files are identical to v1.6.9. Jerod decides how the check is relaxed.

| Rule | |
|---|---|
| Baselines | `../data/analyze/v1.6.9-analyze-session2/` (frozen) for every timing and drawn-step metric; `../data/analyze/p0a-fog-join/` and session 2 for correctness |
| Proof | A candidate build runs the same session (`run-baseline.sh improve <name>`) and is compared with `BoloBench compare`. A change counts only on the metrics named for the item, at the 25% rule, under the conditions in `../2-measure/SYSTEM.md` plus: screensaver off, still wallpaper, frame rate about 50 in the warm-up |
| Musts | No wire change in 1.*; `AGENTS.md`; the item's own failing test flips to passing |
| Data | `../data/improve/<name>/`, tagged `improve/<name>` when frozen |

## Items, in proposed order

| Order | Item | Change | Judged on | Baseline | Target |
|---|---|---|---|---|---|
| 1 | 2D fix the sound player | `SoundPlayer`: load each sound into memory once (or a preloaded `AVAudioPlayer` pool), so `play()` no longer decodes from disk on the main thread | `host.tick_ms.whole.p95` and `host.tick_interval_ms.over_25_pct` in the soak and 4-player sweep; `host.tick_ms.hopSound.p95` reported | Whole tick 14 ms at 2, 19 ms at 4; late ticks 2.3% and 3.9%; sound hop 19 to 26 ms | Whole tick 10 ms; late ticks 1%; sound hop 1 ms |
| 2 | 1A smooth the remote tank | A tick counter owned by the view drives `RemotePositionSmoother`, so it interpolates instead of snapping; keep the snap on respawn | `guest.drawn_remote_step_ms.p50` and `.p95`, every scenario | 100 ms; 126 to 133 ms in the soak | 20 ms; 40 ms |
| 3 | 4B refresh fog memory on reveal | The guest refreshes `seenTiles` for a tile when a reveal arrives for it, without un-hiding mines through other terrain messages | `correctness.fogSeen.persistent` and `.terminal`, Hidden Mines soak; the existing reveal test | 5 of 10 runs | 0 of 10; the test passes 12 of 12 |
| 4 | 3B stop the status refund | The guest applies a status message's mine count less `builderMines` while the builder is out, minding the builder-death refund | `correctness.resources.slow` and `.persistent`, both soaks | 1 of 10 and 4 of 10 | 0 of 10 |

Why this order: 2D is the smallest change with the largest tick-budget gain and no simulation
risk; 1A is the player's most visible gain; 4B and 3B are correctness fixes whose proof needs
about 20 clean soak runs each.

## Items held

| Item | Reason |
|---|---|
| 2B or 2C, host render hop | Revisit only if the hop is still over 5 ms after 2D |
| Position send (2.4 ms median every fifth tick) | After 2D, if the whole-tick target is still missed |
| Resync or checksum, cheaper tank shots, batched reveals, builder-launch message | Wire changes; 2.* |

## Decisions

| Decision | By | Date |
|---|---|---|
| 2D accepted as the tick-budget item, superseding the 2B-versus-2C choice | Jerod | 2026-10-02 |
| Analyze closed; Improve opened with 1A, 2D, 4B and 3B | Jerod | 2026-10-02 |
