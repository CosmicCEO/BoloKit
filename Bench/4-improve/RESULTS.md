# Improve: candidate 1 results

Candidate: branch `improve/2d-sound-player` at a61b08f, which carries 2D, 1A, 4B and 3B.
Data: `../data/improve/candidate1-2d-1a-4b-3b/` (frozen). Baseline: `../data/analyze/v1.6.9-analyze-session2/`.
Session: 90 pair runs and 20 sweep runs, none invalid. Raw logs are on the archive disk.
Reproduce the numbers below with `python3 Bench/4-improve/readout.py <mode>` (modes `2d`, `1a`,
`runs <metric>...`).

**One condition differs from the baseline.** macOS moved from 27.0 (26A428) to 27.0.1 (26A434)
between the two sessions. Hardware, binary settings and conditions are otherwise the same. The
pure simulation step `host.tick_ms.runTick.p50`, which none of the four changes touch, is 36 to
48% slower in eight of nine scenarios, and the guest's whole tick is 12 to 63% slower. So the
sub-millisecond medians shifted by the machine, not the candidate. The tail measures below move
by 40 to 99%, far more than that shift, but a same-OS control of the old build has not been run.

## Verdict by item

| Item | Target | Result | Verdict |
|---|---|---|---|
| 2D sound player | Whole tick 10 ms; late ticks 1%; sound hop 1 ms | Sound hop 19 to 26 ms to 0.03 to 0.05 ms in every tier. Whole tick p95 8.7 ms at 2 players, 10.4 at 4, 6.5 to 7.9 in the soaks. Late ticks 0.3% at 2 and 0.6% at 4 | **Met.** The 4-player whole tick misses 10 ms by 0.4 |
| 1A smoother | Drawn step median 20 ms, 95th percentile 40 ms | Median 100 ms to 25 to 32 ms in moving scenarios (s2, s5, soaks) and 66 to 67 ms in s1, s3, s4, s6, s7. 95th percentile 52 to 98 ms in the moving scenarios, 640 to 830 ms in the others, unchanged | **Partly met.** Passes the 25% rule on the median in all nine scenarios; target not reached |
| 3B status refund | Mine faults 0 | Mine-count episodes 10 to 1, persistent ones 2 to 0 (soaks, 20 runs each side) | **Met on its own signature.** See the shell and armour note |
| 4B fog memory on reveal | Fog memory faults 0 of 10 runs | 5 of 10 runs in both sessions | **Not shown.** The measured residue is mostly another fault |

## 2D, tick budget

| Tier | Whole tick p95, before to after | Late ticks (over 25 ms), before to after | Sound hop p95 |
|---|---|---|---|
| Soak, Hidden Mines | 14.2 to 7.9 ms | 2.3% to 0.3% | 19.1 to 0.05 ms |
| Soak, open | 13.7 to 6.5 ms | 2.3% to 0.1% | 21.8 to 0.05 ms |
| 2 players | 17.1 to 8.7 ms | 3.5% to 0.3% | 20.5 to 0.04 ms |
| 4 players | 19.3 to 10.4 ms | 3.9% to 0.6% | 19.0 to 0.04 ms |
| 8 players | 22.0 to 9.6 ms | 5.2% to 1.3% | 19.4 to 0.04 ms |
| 16 players | 27.5 to 10.1 ms | 10.5% to 3.3% | 25.9 to 0.03 ms |

The render hop's work, `renderHopWork` p95, fell from 9 to 18 ms to 0.5 to 0.8 ms, so the hop is
now cleared and 2B or 2C need no revisit. The whole-tick median rose 6 to 117% in the same
tiers. That matches the machine-wide shift above, not the candidate, but only a control run can
say how much of it is the new audio engine. Audible parity of the new sounds is untested.

## 1A, drawn step of the host tank on the guest

| Scenario | Median before to after | 95th percentile before to after |
|---|---|---|
| s2 pill pickup | 100 to 32 ms | 233 to 117 ms |
| s5 death and respawn | 100 to 25 ms | 104 to 53 ms |
| s8 soak, Hidden Mines | 100 to 30 ms | 133 to 85 ms |
| s8 soak, open | 100 to 31 ms | 126 to 98 ms |
| s1, s3, s4, s6, s7 | 100 to 66 to 67 ms | 750 to 800 ms, unchanged |

The 95th percentile of 750 to 830 ms in the five scripted scenarios is a tank that stands still
and then moves, and it is identical in the baseline. It is not a smoothing result.

## 3B and 4B, by what each fault looks like

The aggregate counters hide both signatures, so the episodes were split by element and value.

Fog episodes count tiles, so one run can contribute dozens. Resource episodes count lasting
differences. Both sessions have 20 soak runs (10 Hidden Mines, 10 open).

| Signature | Baseline | Candidate |
|---|---|---|
| Mine count off, guest above host (3B) | 10 episodes in 5 runs, 2 persistent | 1 episode in 1 run, 0 persistent |
| Mined tile remembered as plain ground (4B) | 3 tiles in 2 runs | 1 tile in 1 run |
| Tile unseen on the guest, seen on the host (neither item) | 7 tiles in 3 runs | 67 tiles in 3 runs |
| Tile seen on the guest, unseen on the host (neither item) | 0 | 29 tiles in 1 run |
| Shells off, guest above host by 3 | 0 | 3 episodes in 3 runs |
| Armour off by 10 | 1 episode, guest below host | 1 episode, guest above host |

What this says:

- **3B works on the mine count.** The episodes it targets fell from 10 to 1. The aggregate
  `resources.slow` stayed flat (5 runs of 20 each side) only because shell and armour episodes
  took its place.
- **4B is not proven by the soak.** The mined-tile signature is nearly absent in both sessions,
  so the soak has no power to show it. The unit test shows the mechanism. The 5 of 10 runs come
  from a different fault: the host holds fog memory of tiles the guest never saw, or the reverse.
  One candidate run has 29 tiles in a single row where the guest remembers sea and the host
  remembers nothing. That is the guest and host vision areas disagreeing, a separate defect that
  was in the baseline and is not part of 4B. It is not worse than the baseline in the number of
  runs affected (3 of 20 both sessions), but the tile counts are larger.
- **Shell episodes are new and unexplained.** Three runs show shells 3 above the host for 0.5 to
  0.7 s. No change here touches shells. They may be timing, since ticks are now faster. They need a
  second session before anyone calls them a regression or noise.

## What to decide

1. Whether to run a same-OS control of the frozen Analyze build on the soak and the 4-player
   sweep (about 40 minutes of machine time) to separate the OS shift from the candidate.
2. Whether 4B stays in Improve with a corrected proof metric (the mined-tile signature, which
   needs a purpose-built scenario), or is accepted on the unit test and the fog-vision mismatch
   is opened as its own item.
3. Whether 1A's targets stay at 20 and 40 ms. At 50 frames a second the floor for a drawn step is
   20 ms, and the moving scenarios sit at 25 to 32 ms.
