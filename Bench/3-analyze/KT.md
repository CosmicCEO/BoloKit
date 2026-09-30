# Improvement register (Kepner-Tregoe)

**Status: proposed 2026-09-29, for audit and for Jerod's decision.** Every improvement suggested
in Define, Measure or Analyze, scored one way and sorted. Not a plan: translation into sprints
or backlog is a later discussion.

| | |
|---|---|
| Benchmark | `measure/v1.6.9-baseline` (tag), 218 valid runs, one M1 MacBook Pro, loopback |
| Scope | 2 to 4 players |
| Smallest gain the benchmark must prove | About 25% |
| Detail per proposal | `PROPOSALS.md`, `OBSERVED.md` |
| Evidence grade | **Measured:** from the benchmark. **Read:** seen in code, not executed. **Inferred:** reasoned only |

## Method

An item must pass all three musts. Items that pass are scored 1 to 10 on each want; the total is
the sum of score times weight, out of 380. Scores are the analyst's judgement.

| Must | |
|---|---|
| M1 | The benchmark can prove the result, or the same change makes it able to |
| M2 | No change to the wire format in a 1.* release (decided by Jerod, 2026-09-29) |
| M3 | Complies with `AGENTS.md` |

| Want | | Weight |
|---|---|---|
| W1 | Benefit the player can see | 10 |
| W2 | Size of the gain against the target | 8 |
| W3 | Low risk of breaking something | 8 |
| W4 | Ease of proving it on the benchmark | 7 |
| W5 | Low effort | 5 |

## Prerequisites (not scored)

| | Item | Needed by | Size |
|---|---|---|---|
| P0 | Correct the measurement system and re-analyse the raw logs | Every correctness target; items 3 and 4 | About 40 lines, no new runs |
| P1 | Probe for the drawn position of remote tanks | Item 1 | Small |
| P2 | Scenario that fires a pill along an exact diagonal | Item 7 | Small |

## Register, sorted by score

| Rank | Item | Musts | W1 | W2 | W3 | W4 | W5 | Total | KPI, baseline to target | Evidence | Risk |
|---|---|---|---|---|---|---|---|---|---|---|---|
| 1 | Smooth the remote tank on the guest (1A) | Pass | 9 | 8 | 8 | 4 | 9 | **291** | Drawn step 100 ms to 20 ms | Read | Low |
| 2 | Render wait out of the host tick (2B) | Pass | 6 | 9 | 6 | 9 | 7 | **278** | Host tick 95th percentile 13.5 to 20.0 ms, to 10 ms; late ticks 2.3% to 4.4%, to 1% | Measured and read | Medium |
| 3 | Guest refreshes fog memory on reveal (4B) | Pass | 6 | 7 | 6 | 7 | 8 | **253** | Terrain faults in 3 of 19 soak runs, to 0; test failing 1 in 12, to 0 | Inferred | Medium |
| 4 | Status message no longer refunds a mine (3B) | Pass | 4 | 7 | 6 | 8 | 9 | **245** | Resource faults in 8 of 39 soak runs, to 0 | Read; reach inferred | Medium |
| 5 | Speed up the host's position send | Pass | 4 | 6 | 6 | 8 | 5 | **217** | 2.2 to 3.2 ms median every fifth tick; no target yet | Measured; cause not investigated | Medium |
| 6 | Relay positions less wastefully | Pass in 1.* only if no wire change | 2 | 5 | 5 | 10 | 4 | 190 | Position traffic 9.5 kB/s at 4 players | Measured | Medium |
| 7 | Diagonal pill shell damages the pill | Pass with P2 | 5 | 4 | 4 | 3 | 5 | 160 | None today; pills never diverged | Seen once | Medium |
| 8 | Terrain comparison by change tracking | Pass | 1 | 3 | 5 | 7 | 5 | 148 | Host tick median 0.35 ms; 21% to 30% of it | Measured | Medium |
| 9 | Reduce fog array copies | Pass | 1 | 2 | 6 | 6 | 6 | 146 | 3% to 8% of host tick median | Measured | Low |
| 10 | Drift-corrected clock | Pass | 2 | 1 | 4 | 8 | 5 | 141 | Tick interval 20.9 ms; under 5% available | Measured | Medium |
| 11 | Join handshake off the host consumer | Pass | 1 | 1 | 4 | 8 | 4 | 126 | Join stall 21 ms, one normal tick | Measured | Medium |

## Decisions

| Decision | By | Date |
|---|---|---|
| The wire format is closed to 1.* releases and open to 2.* releases | Jerod | 2026-09-29 |
| Backward compatibility is expected to arise at 2.0.* in any case | Jerod | 2026-09-29 |
| The audit is carried out on GitHub, on this file | Jerod | 2026-09-29 |

## Held for 2.* releases

These change the wire format, so they fail M2 for any 1.* release. They are candidates for 2.*,
scored on the same wants.

| Item | Fails in 1.* | W1 | W2 | W3 | W4 | W5 | Score for 2.* | KPI |
|---|---|---|---|---|---|---|---|---|
| Tank shots off the reliable channel, or deltas | M2 | 2 | 9 | 4 | 10 | 4 | 214 | 85% to 99% of reliable bytes when firing |
| Periodic state checksum or resync | M2 | 5 | 7 | 4 | 8 | 2 | 204 | Lasting faults from unknown causes |
| Batch terrain reveals | M2 | 2 | 6 | 5 | 10 | 5 | 203 | 95% to 98% of reliable bytes in quiet play |
| Guest reports builder launch (3C) | M2 | | | | | | Not scored | Alternative to item 4 |

## Alternatives not chosen

| Item | For | Total | Why not |
|---|---|---|---|
| Engine publishes snapshot, view pulls (2C) | Item 2 | 257 | Larger change for the same gain |
| Advance `state.ticks` on the guest (1B) | Item 1 | 256 | `ticks` also drives the time limit and animation |
| Step remote tanks every guest tick (1C) | Item 1 | 240 | Rubber-banding |
| Guest stops hiding mines itself (4C) | Item 3 | 237 | Shares a function with single-player |
| Move the waits after the position send (2A) | Item 2 | 205 | Ticks still late |

## Housekeeping (no KPI, not scored)

| Item | Note |
|---|---|
| Dropped-datagram log reads byte 1; the slot is byte 0 | `HostDgramListener.swift` |
| Four app tests fail on the untouched tag | Listed in `../2-measure/SYSTEM.md` |
| `swift test` can hang when several suites run together | Run suites one at a time |

## Audit pack for the top five

Each claim is stated so that it can be shown false.

| Item | Claim to test | Where | How to refute it |
|---|---|---|---|
| 1 | `state.ticks` advances only in `runTick`, which a guest never calls, so the smoother always snaps | `RunTick.swift:162,205,217`; `GameSession.swift:709-904`; `RemotePositionSmoother.swift:43-50` | Find a guest path that advances `ticks`, or show interpolated positions being drawn |
| 1 | The 400 ms figure in Measure was whole-tile changes, not update rate | `RunAnalysis.swift:337,351-360`; `Physics.swift:21` | Show sub-tile changes arriving slower than 10 a second |
| 2 | The host tick awaits the main thread twice, and the wait is 12.2 of the 13.5 ms | `HostGameEngine.swift:931-943`; `host.tick_ms.renderHop.p95` | Show another phase at the 95th percentile on the same ticks |
| 2 | Drawing itself is under 1 ms, so the cost is waiting | `host.draw_ms.*.p95`, `host.tile_grid_rebuild_ms.p95` | Show main-thread work inside the hop that the recorder does not time |
| 2 | Late ticks are caused by the wait | Correlation 0.45 to 0.67 across runs | Moderate only. Late ticks with a short wait would refute it |
| 3 | The guest snapshots fog memory from its own terrain before the reveal arrives, and the reveal never refreshes it | `FogState.swift:164-172,205-214`; `RecvSR.swift:200-202`; `GameSession.swift:893` | Show the reveal path writing `seenTiles` |
| 3 | This explains the hidden mine that is never revealed | `HostGameEngine.swift:1242-1250` | **Weakest claim.** Not reproduced. A failing test with another cause refutes it |
| 4 | The guest spends the mine at launch, the host on arrival, and a status message in between restores the old count | `BuilderTick.swift:606-607`; `HostSession.swift:903-905`; `RecvSR.swift:223` | Show the soak resource faults occurring with no builder out |
| 5 | The position send is the largest host tick cost once the render wait is gone | `host.tick_ms.updateSend` | Cause unknown. It may be waiting on the network stack, which a code change cannot shorten |

## Known weaknesses of this register

| Weakness | Effect |
|---|---|
| Scores are one analyst's judgement | Items 1 and 2 swap if provability is weighted double; items 3 and 4 are level |
| No root cause has been demonstrated by a test | Every item needs a failing test before work starts |
| Gains are what is available if a cost were removed entirely | Actual gains will be smaller |
| Item 1 has no measured baseline | The 100 ms step is derived from the 10 a second update rate |
| Items 3 and 4 depend on P0 | Their baselines may change after re-analysis |
| One machine, loopback, 2 sessions | Timing faults are under-represented; control limits are provisional |
| Risk is a single grade here | Likelihood and seriousness are separate in `PROPOSALS.md` |
