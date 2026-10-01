# Specifications

**Status: proposed 2026-09-30 for Jerod's approval.** Supersedes the 2026-09-29 draft; the
withdrawn rows are gone. Scope 2 to 4 players. Y is player experience (Define, amended).

Sources: pacing, cost and traffic from `../data/measure/v1.6.9-baseline/` (frozen, 218 runs);
correctness from `../data/analyze/p0a-fog-join/` (the same runs, re-read with fog memory compared
only in fog); the drawn remote step from the P1 soak (`../data/analyze/p1-drawn-step/`).

## Page 1: player-experience targets

A release is judged on these. "Judge on" names the scenarios where the benchmark can prove a
25% change; elsewhere the metric is reported only.

| CTQ | Metric | Judge on | v1.6.9 | Target | Met |
|---|---|---|---|---|---|
| Responsiveness 45 | Drawn step of the host's tank on the guest screen, median (`guest.drawn_remote_step_ms.p50`) | Soak | 100 ms median, 132 ms at the 95th percentile, 0.2 tiles a step (one run) | 20 ms | No |
| Responsiveness 45 | Guest key press to frame, 95th percentile | All | 31 to 32 ms | 40 ms | Yes |
| Responsiveness 45 | Guest frame interval, 95th percentile | All | 33 ms | 35 ms | Yes |
| Tick budget 30 | Host ticks over 25 ms apart | Soak, sweep | 2.3% to 2.6% at 2; 4.4% at 4 | 1% | No |
| Tick budget 30 | Host tick, 95th percentile | Soak, 4-player sweep | 13.5 ms at 2; 20.0 ms at 4 | 10 ms | No |
| Tick budget 30 | Host render hop, 95th percentile, split into wait and work | Soak, 4-player sweep | 12.9 ms at 2; 17.8 ms at 4 (whole). Split, one run: work 9.0 ms, wait 2.4 ms | 5 ms | No |
| Tick budget 30 | Host and guest tick interval, 95th percentile | All | 20.9 ms; 23.7 ms at 4 | 25 ms | Yes; marginal at 4 |
| Visible correctness 25 | Fog memory wrong while in fog, tiles at end of run (`correctness.fogSeen.terminal`) | Soak, Hidden Mines | 13 of 19 runs; median 29, max 75 | 0 | No |
| Visible correctness 25 | Fog memory wrong while in fog, over 2 s (`correctness.fogSeen.persistent`) | Soak, Hidden Mines | 12 of 19 runs; median 2, max 59 | 0 | No |
| Visible correctness 25 | Terrain wrong over 250 ms | Soak, Hidden Mines | 3 of 19 runs | 0 | No |
| Visible correctness 25 | Mine count wrong over 250 ms, excluding the builder's carried mine | Soak | 8 of 39 runs (uncorrected; P0b pending) | 0 | No |
| Visible correctness 25 | Lasting faults in pills, bases, own status, visibility, peers | All | 0 | 0 | Yes |

Correctness targets are pass or fail. Proving an intermittent fault gone needs about 20 clean
soak runs.

## Page 2: provisional tripwires

Control limits: mean plus three standard deviations of the pooled run values, about 20 values
per metric, not bell-shaped. A release above a tripwire has got worse and is held for a look. They
are provisional until a third session exists.

| Metric | v1.6.9 | Tripwire |
|---|---|---|
| Host tick interval, 95th percentile | 20.9 ms at 2; 23.7 ms at 4 | 22.4 ms at 2; 25.0 ms at 4 |
| Guest tick interval, 95th percentile | 20.9 ms | 21.2 ms |
| Guest key press to frame, 95th percentile | 31 to 32 ms | 38.5 ms |
| Reliable message sent to applied, 95th percentile | 45 ms | 54.8 ms |
| Guest joined to alive | 2,010 to 2,030 ms | 2,133 ms |
| Longest host tick during a join | 21 ms at 2 | 27.4 ms at 2; 35.0 ms sweep |
| Guest tick, 95th percentile | 0.3 to 0.6 ms | 0.9 ms |
| Host CPU, share of one core | 32% to 34% at 2; 43% at 4 | 42.7% at 2; 45.0% at 4 |
| Guest CPU, share of one core | 29% to 31% | 42.6% |
| Memory, peak | 125 to 157 MB | 178 MB |
| Host reliable traffic | 6.1 kB/s at 2; 19.0 kB/s at 4 | 7.9 kB/s at 2; 22.9 kB/s at 4 |
| Host position traffic | 1.2 kB/s at 2; 9.5 kB/s at 4 | 1.2 kB/s at 2; 9.8 kB/s at 4 |
| UDP loss, unpaired reliable messages, rejects, invariant violations | 0 | 0 |

## Removed from the 2026-09-29 draft

| Row | Why |
|---|---|
| Fog memory, about 300 tiles | Compared visible tiles, which are drawn from live terrain. P0a removed it; what survives is on page 1 |
| Builder-placed mine wrong for 1.3 s | The builder's carried mine was not counted. Replaced by the mine-count row pending P0b |
| Host's tank moving every 141 to 400 ms | Counted whole-tile changes, which depend on tank speed. Replaced by the drawn step |
| Position delay host to guest | Not repeatable; reported only |
| Everything at 8 and 16 players | Watch items outside scope |
