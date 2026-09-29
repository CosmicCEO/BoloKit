# Measure phase: close-out

The Measure phase of the host/client DMAIC pass is closed. v1.6.9 now has a frozen, numeric
benchmark to improve on and to control variation against.

| | |
|---|---|
| Frozen baseline | `Bench/data/measure/v1.6.9-baseline/` |
| Tag | `measure/v1.6.9-baseline` |
| Made from | Two sessions a day apart, pooled: 218 valid runs |
| Machine | MacBook Pro 13-inch M1 (`MacBookPro17,1`), 8 cores, 16 GB, macOS 27.0 (`26A428`) |
| Conditions | AC power, Low Power Mode off, unattended, both instances on this Mac |
| Decided by | Jerod, 2026-09-29 |

How the system works and how to run it: `SYSTEM.md`. Each session in detail: the `SUMMARY.md` in
`../data/measure/v1.6.9-baseline-session1/` and `-session2/`. What Analyze starts from:
`../3-analyze/README.md`.

## Decisions that closed the phase

| Decision | Detail |
|---|---|
| Freeze both sessions together | The pooled spread includes how much the numbers move from one day to the next |
| The data is the benchmark | It is what later versions are improved from and controlled against |
| Confidence is sufficient for this level of work | The intervals and limits the data gives are good enough to proceed |
| The measurement system carries into Analyze | Its between-session variation is studied there, not before |
| Specifications are built in Analyze | Control limits and targets are derived from this data then |

## What the benchmark is

Figures are the median across runs, with the 95% interval of that median in brackets. An
asterisk marks a metric that was not repeatable; it is reported and never compared.

### Correctness

| Scenario | In flight | Slow | Persistent | Terminal |
|---|---|---|---|---|
| s1-join-and-spawn | 1,527 | 0 | 0 | 302 |
| s3-mine-laying | 2,683 | 1 | 1 | 301 |
| s5-death-and-respawn | 4,511 | 20 * | 343 | 3 |
| s7-sustained-fire | 2,292 | 2 * | 0 | 316 |
| s8-soak-hidden | 17,840 | 53 | 584 | 31 * |
| s4-building, s8-soak-open (Hidden Mines off) | Present | Rare | 0 | 0 |

Pills, bases, own status and visibility never diverged past in-flight in a scripted scenario.

### Responsiveness (one host, one guest)

| Metric | Baseline |
|---|---|
| Tick interval, 95th percentile, host | 20.8 to 21.0 ms |
| Tick interval, 95th percentile, guest | 20.8 to 20.9 ms |
| Scripted key press to frame, guest | 16.5 to 19.2 ms |
| Reliable message sent to applied, median | 3 to 33 ms, by scenario |
| Reliable message sent to applied, 95th percentile | 42 to 45 ms with Hidden Mines on |
| Guest update acknowledged by host | 61 to 82 ms |
| Host update acknowledged by guest | 28 to 62 ms |
| Host's tank moving on the guest's screen | Every 141 to 400 ms |
| Guest joined to alive | About 2,010 ms * |
| UDP loss | 0% |

### Cost (one host, one guest)

| Metric | Host | Guest |
|---|---|---|
| Tick, median | 0.34 to 0.44 ms | 0.088 to 0.098 ms |
| Tick, 95th percentile | 3.0 to 3.4 ms scripted; 13.4 ms soak | |
| CPU, share of one core | 31.8% to 33.7% | 29.5% to 31.1% |
| Memory | 128 to 135 MB | 125 to 131 MB |
| Reliable traffic sent | 202 B/s to 6,055 B/s | |
| Position updates sent | 672 to 1,150 B/s | 1,088 to 1,258 B/s |

### Host cost by player count

| Metric | 2 | 4 | 8 | 16 |
|---|---|---|---|---|
| Tick, median (ms) | 0.55 | 0.96 * | 2.46 * | 3.57 |
| Tick, 95th percentile (ms) | 15.0 * | 20.0 | 22.4 | 28.9 |
| Render hop, 95th percentile (ms) | 13.5 * | 17.8 | 19.2 | 21.8 |
| Fog, median (ms) | 0.017 | 0.080 | 0.171 | 0.292 |
| Simulation (`runTick`), median (ms) | 0.050 | 0.058 | 0.071 | 0.080 |
| Tick interval, 95th percentile (ms) | 21.9 | 23.7 | 25.6 | 32.1 |
| Ticks over 25 ms apart | 3.4% | 4.4% * | 5.5% * | 11.1% * |
| Tick rate (per second) | 49.80 | 49.76 | 49.64 | 49.05 |
| CPU, share of one core | 42.0% | 43.0% | 44.2% | 50.0% |
| Reliable traffic sent (B/s) | 7,296 | 18,972 | 42,439 | 87,825 |
| Position updates sent (B/s) | 1,204 | 9,539 | 49,723 | 221,596 |

## How good the measurement system is

| Property | Result |
|---|---|
| Accuracy | Analyzer matched a direct comparison of final states in 20 of 20 real runs; 6 of 6 planted defects detected |
| Observer effect | Recording changed CPU use by at most 1.8% (limit 3%) |
| Records dropped | 0 in 218 runs |
| Valid runs | 218 of 220 |
| Repeatability, scripted scenarios | 88% to 93% of judged metrics |
| Repeatability, soak | 70% to 75% |
| Repeatability, sweep | 61% to 69% |
| Reproducibility between sessions | Correctness, traffic and errors reproduce; durations moved 9% to 25% |
| Each session against the pooled baseline | 0 of about 2,760 metrics read as changed |

The last row is what makes the pooled baseline usable: a session of unchanged code does not read
as a change.

## Known limits

- **One machine, loopback.** Link delays are a floor. Timing-dependent faults are less likely to
  appear than in two-Mac play.
- **The two sessions were launched differently.** Session 1 honoured saved window state and
  session 2 ignored it. Whether that contributes to the duration shift is not known.
- **The observer effect was checked on CPU only**, not on signpost durations.
- **Candidate fault classes are heuristic.** Most fog episodes are labelled `doubleDecision`,
  which is unlikely to be right.
- **Raw logs are not in the repository.** About 4.6 GB, kept in `Bench/runs/` on the benchmark
  machine.
