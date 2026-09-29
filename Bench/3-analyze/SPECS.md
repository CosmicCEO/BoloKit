# Proposed specifications and standards

**Status: proposed 2026-09-29, not yet approved by Jerod.** Built from the frozen benchmark
`../data/measure/v1.6.9-baseline/` (218 valid runs). Reproduce every figure with
`python3 Bench/scripts/capability.py`.

## Basis (decided by Jerod, 2026-09-29)

| Decision | Answer |
|---|---|
| Smallest improvement the benchmark must prove | About 25% |
| Player count the specifications cover | 2 to 4 |
| Correctness standard | Zero lasting faults: none over 2 s, none left at the end of a run |

## Two kinds of limit

| Limit | Meaning | Source |
|---|---|---|
| Control limit | A release that exceeds it has got worse. It fails the release | Mean plus three standard deviations of the pooled run values |
| Target | Where the game should be. v1.6.9 may not meet it yet | Engineering judgement against the 20 ms tick |

## Correctness

| Metric | v1.6.9 | Control limit | Target | Met today |
|---|---|---|---|---|
| Lasting faults in pills, bases, own status, visibility, peers | 0 | 0 | 0 | Yes |
| UDP loss, unpaired reliable messages, rejects, invariant violations | 0 | 0 | 0 | Yes |
| Guest fog memory, tiles wrong at end of run (`correctness.fogSeen.terminal`) | 3 to 316 | 481 | 0 | No |
| Guest fog memory, tiles wrong over 2 s (`correctness.fogSeen.persistent`) | 0 to 584 | 1,028 | 0 | No |
| Builder-placed mine, wrong count over 250 ms (`s3`, `correctness.resources.slow`) | 1 every run | 1 | 0 | No |
| Resources wrong over 250 ms, soak | 8 of 39 runs | 1 per run | 0 | No |
| Terrain wrong over 250 ms, soak with Hidden Mines | 3 of 19 runs | 1 per run | 0 | No |

Proving an intermittent fault is gone needs about 20 soak runs with none seen. At the baseline
rate of 3 in 19, a clean set of 20 happens by chance about 3 times in 100.

## Responsiveness

| Metric | Judge on | v1.6.9 | Control limit | Target | Met today |
|---|---|---|---|---|---|
| Host tick interval, 95th percentile | All | 20.9 ms at 2; 23.7 ms at 4 | 22.4 ms at 2; 25.0 ms at 4 | 25 ms | Yes at 2; marginal at 4 |
| Guest tick interval, 95th percentile | All | 20.9 ms | 21.2 ms | 25 ms | Yes |
| Host ticks over 25 ms apart | Soak, sweep | 2.3% to 2.6% at 2; 4.4% at 4 | 3.7% at 2; 5.2% at 4 | 1% | No |
| Guest key press to frame, 95th percentile | All | 31 to 32 ms | 38.5 ms | 40 ms | Yes |
| Guest frame interval, 95th percentile | All | 33 ms | 35.1 ms | 35 ms | Yes |
| Reliable message sent to applied, 95th percentile | Scripted | 45 ms | 54.8 ms | 55 ms | Yes |
| Host's tank moving on the guest's screen, median | Soak | 400 ms | 428 ms | 100 ms | No |
| Guest joined to alive | All | 2,010 to 2,030 ms | 2,133 ms | 2,150 ms | Yes |
| Longest host tick during a join | All | 21 ms at 2; 23 to 27 ms sweep | 27.4 ms at 2; 35.0 ms sweep | 40 ms | Yes |

## Cost

| Metric | Judge on | v1.6.9 | Control limit | Target | Met today |
|---|---|---|---|---|---|
| Host tick, 95th percentile | Soak, 4-player sweep | 13.5 ms at 2; 20.0 ms at 4 | 21.0 ms at 2; 21.7 ms at 4 | 10 ms | No |
| Host render hop, 95th percentile | Soak, 4-player sweep | 12.9 ms at 2; 17.8 ms at 4 | 22.3 ms at 2; 19.5 ms at 4 | 5 ms | No |
| Guest tick, 95th percentile | Scripted | 0.3 to 0.6 ms | 0.9 ms | 2 ms | Yes |
| Host CPU, share of one core | All | 32% to 34% at 2; 43% at 4 | 42.7% at 2; 45.0% at 4 | Control only | Yes |
| Guest CPU, share of one core | All | 29% to 31% | 42.6% | Control only | Yes |
| Memory, peak | All | 125 to 157 MB | 178 MB | Control only | Yes |
| Host reliable traffic | Soak, sweep | 6.1 kB/s at 2; 19.0 kB/s at 4 | 7.9 kB/s at 2; 22.9 kB/s at 4 | Control only | Yes |
| Host position traffic | Soak, sweep | 1.2 kB/s at 2; 9.5 kB/s at 4 | 1.2 kB/s at 2; 9.8 kB/s at 4 | Control only | Yes |

## Metrics kept out of the specification

| Metric | Reason |
|---|---|
| Position delay, host to guest (`link.position_delay_ms`) | Not repeatable in any scripted scenario |
| Host tick and render hop in scripted scenarios and the 2-player sweep | A 25% gain cannot be proven there; judge on the soak and 4-player sweep |
| Remote tank movement in scripted scenarios | A 25% gain is provable in 3 of 7 only; judge on the soak |
| Everything at 8 and 16 players | Outside the 2 to 4 player scope; kept as watch items |
