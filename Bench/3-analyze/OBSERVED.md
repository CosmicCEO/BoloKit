# Review of the observed findings from Measure

**2026-09-29.** Measure handed over findings and hypotheses that came from observation and code
reading, not from the benchmark's numbers. This reviews each for overlap with `PROPOSALS.md` and
for whether it could move a KPI by 25%, the smallest gain the benchmark must prove.

Shares below are of the median, from the frozen benchmark. Medians of phases do not add up
exactly, so shares are estimates. No experiment was run.

## Overlap with the proposals

| Observed finding | Overlaps | Note |
|---|---|---|
| Remote smoothing never engages on the guest | Proposal 1A | Same fault |
| Host tick waits on main-thread rendering | Proposal 2B | Same fault |
| A mine near spawn is sometimes never revealed (test fails 1 in 12) | Proposal 4B | Likely the same fault; inferred |
| No resync or checksum exists | Proposals 3B and 4B | Those fix two causes; a resync would cover unknown ones. Changes the wire format |
| Batch per-recipient sends | Proposal 2B | Follow-on. Only matters once the render wait is gone |
| Pill shell on an exact diagonal damages the pill, unreported | None | New. See below |
| Dropped-datagram log reads the wrong byte | None | Diagnostics only |
| Four app tests fail on the untouched tag; `swift test` can hang | None | Test health |
| Join handshake runs inside the host's consumer | None | Measured: nothing to gain |

## Could it deliver a 25% gain?

| Hypothesis | KPI | Evidence | 25% gain | In 2 to 4 player scope |
|---|---|---|---|---|
| Render wait out of the host tick | Host tick, 95th percentile | Render wait is 12.2 of 13.5 ms | Yes, about 60% to 90% | Yes |
| Let guest smoothing engage | Drawn step of remote tank | 100 ms to 20 ms | Yes, about 80% | Yes |
| Tank shots off the reliable channel, or deltas | Host reliable traffic | 85% to 99% of bytes wherever shots are fired | Yes | Traffic is control-only |
| Batch terrain reveals | Host reliable traffic | 95% to 98% of bytes in scenarios without firing; 8% in the soak | Yes in quiet play; no in the soak | Traffic is control-only |
| Relay positions less wastefully | Host position traffic | Grows with the square of players | Yes at 4 and above; no at 2 | Partly |
| Terrain comparison replaced by change tracking | Host tick, median | 21% to 30% of the median at 2 players; 11% at 4 | Borderline at 2; no at 4 | Not a spec metric |
| Speed up the position send | Host tick, after proposal 2B | 2.2 to 3.2 ms median, 5 to 7 ms at the 95th percentile, every fifth tick | Likely, once 2B is in | Yes |
| Reduce fog array copies | Host tick, median | 3% to 8% of the median | No | No |
| Join handshake off the consumer | Longest host tick during a join | Handshake 1 to 2 ms; stall equals one normal tick | No | Yes |
| Drift-corrected clock | Tick interval, 95th percentile | 20.9 ms against 20.0 ms; timer delay 0.05 ms | No, under 5% available | Yes |
| Periodic checksum or resync | Lasting faults | Counts are small after proposal 0 | Pass or fail, not a percentage | Yes |

## What this changes

| Item | Change |
|---|---|
| Ranking of proposals 1A, 2B, 4B, 3B | None |
| Position send | Added as a follow-on to 2B. It becomes the largest host tick cost once the render wait is gone |
| Terrain comparison | The largest steady share of the host's median tick, but the median is 0.35 ms of a 20 ms budget. No benefit the player can see |
| Tank shots and terrain reveals | The two largest traffic gains. Hold until the player count in scope rises above 4 |
| Join handshake, drift-corrected clock, fog copies | Drop. The benchmark shows little to gain |

## The diagonal pill shell

| | |
|---|---|
| Observation | A pill firing along an exact diagonal damaged itself and did not report it |
| Seen | Once, in the validation harness, not in any benchmark scenario |
| KPI | None moves today: pills never diverged in 218 runs |
| Gap | No scenario covers it. The benchmark cannot see this fault |
| Recommendation | Reproduce in a test first. If real, it is a correctness fault of the "unreported change" kind and the benchmark needs a scenario for it |
