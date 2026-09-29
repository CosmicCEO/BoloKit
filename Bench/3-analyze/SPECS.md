# Proposed specifications and standards

**Status: accepted 2026-09-29 (A5).** Built from Measure freeze
`../data/measure/v1.6.9-baseline/` plus Analyze packets A1–A4.
Reproduce freeze figures with `python3 Bench/scripts/capability.py`.

Y: player-visible UX. Weights: Responsiveness 45, tick-budget 30,
player-visible correctness 25.

## Basis

| Decision | Answer |
|---|---|
| Smallest improvement the benchmark must prove | About 25% |
| Player count these specs cover | 2 to 4 |
| Player-visible correctness | Disagreement the player can see or act on |
| Three Measure headlines | Quarantined until P0a/P0b/P1 say otherwise |

## Quarantined (not targets)

| Row | Until |
|---|---|
| `correctness.fogSeen.*` (~300 tiles) | P0a scorecard |
| Builder-mine 1.3 s / s3 `resources.slow` as that story | P0b or a failing 3B test |
| `guest.remote_move_interval_ms` (141–400 ms tile-step) | P1 baseline of `guest.drawn_remote_step_ms` |

Do not print control limits or "Met today: No" for these rows.

## Tripwires (release fails if it exceeds these)

From the freeze. CPU, memory, traffic stay control-only.

| Metric | Judge on | v1.6.9 | Control limit |
|---|---|---|---|
| Lasting faults pills, bases, own status, visibility, peers | Pair | 0 | 0 |
| UDP loss, unpaired reliable, rejects, invariants | Pair | 0 | 0 |
| Host tick interval p95 | All | 20.9 ms at 2; 23.7 ms at 4 | 22.4 ms at 2; 25.0 ms at 4 |
| Guest tick interval p95 | All | 20.9 ms | 21.2 ms |
| Guest key-to-frame p95 | All | 31–32 ms | 38.5 ms |
| Guest frame interval p95 | All | 33 ms | 35.1 ms |
| Reliable send-to-applied p95 | Scripted | 45 ms | 54.8 ms |
| Host join stall | All | 21 ms at 2 | 27.4 ms at 2 |
| Host CPU / guest CPU / memory / reliable traffic / position traffic | 2–4 | See freeze | Freeze +3σ |

`guest.join_to_alive_ms` (~2.0 s) is the scripted spawn wait. Informational. Not a tripwire.

## UX targets (not met is allowed)

| Metric | Judge on | v1.6.9 | Target | Met |
|---|---|---|---|---|
| Host ticks over 25 ms apart | Soak, 4p sweep | 2.3–2.6% at 2; 4.4% at 4 | 1% | No |
| Host tick p95 | Soak, 4p sweep | 13.5 ms at 2; 20.0 ms at 4 | 10 ms | No |
| Host render hop p95 | Soak, 4p sweep | 12.9 ms at 2; 17.8 ms at 4 | Split wait vs work before a hop target | No |
| `guest.drawn_remote_step_ms` | Soak, after P1 probe | not measured (~100 ms expected) | 20 ms | No probe |

Soak `resources.slow` (8/39) and Hidden Mines `terrain.slow` (3/19) stay **holds**, not targets, until the 3B/4B tests exist.

8- and 16-player traffic stay watch. Out of these specs.
