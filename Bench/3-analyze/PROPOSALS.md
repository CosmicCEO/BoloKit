# Improvement proposals

**Status: proposed 2026-09-29, for Jerod's decision.** High level only: no design, no code
changed. Scope is 2 to 4 players. Decision charts follow the Kepner-Tregoe method: options must
pass every must, then are scored on weighted wants, then checked for adverse consequences.

## Evidence and its strength

| Source | Strength |
|---|---|
| Frozen benchmark, 218 runs | Measured |
| Code reading of the four areas, with file and line | Read, not executed. Five claims spot-checked a second time |
| Root causes marked "inferred" below | Reasoned, not demonstrated |

No experiment was run for this document. Every root cause needs a failing test before its fix.

## Correction to the first readout

The first readout ranked four areas from the numbers alone. Reading the code shows three of the
four numbers were partly produced by how the benchmark compares, not by the game.

| Area | First readout | After code reading |
|---|---|---|
| Guest fog memory | About 300 tiles wrong, rank 1 | Not visible to the player. Host and guest each keep their own memory and it is never sent. One real edge case remains: a hidden mine that is never revealed |
| Host's tank on guest's screen | Moves every 400 ms | The metric counted whole-tile changes; a tank at top speed on grass takes 427 ms a tile. The real fault is that the tank is drawn in 100 ms steps because smoothing never engages |
| Builder-placed mine count | Wrong for 1.3 s | Guest spends the mine when the builder leaves, host when it arrives. Guest `mines + builderMines` agrees throughout. One real fault remains: a status message during the walk refunds the mine on the guest |
| Render hop | 12.9 to 17.8 ms | Stands. The cost is waiting for the main thread, not drawing |

The accuracy check in Measure did not catch this. It proved the analyzer agrees with a direct
comparison, and both used the same definition of "should agree".

## Proposal 0: correct the measurement system (prerequisite)

| | |
|---|---|
| Scope | Analyzer and digest only. No game code. Frozen data untouched |
| Changes | Compare fog memory only where the tile is in fog. Compare guest `mines + builderMines`. Measure remote movement below tile level (the logs already hold position to a sixteenth of a tile). Judge join time by a relative rule |
| Output | A re-analysis of the existing raw logs into `data/analyze/`, so no new runs are needed |
| Cost | Small: about 40 lines, 3 files, plus tests |
| Risk | Low. The raw logs exist on one machine only and are not backed up |
| Effect | Lasting-fault counts fall to the real faults; targets in `SPECS.md` become meaningful |

## Musts

Every option must pass all three.

| | Must |
|---|---|
| M1 | The benchmark can prove the result, or the same change makes it able to |
| M2 | No change to the wire format, so v1.6.9 hosts and guests still play together |
| M3 | Complies with `AGENTS.md`: `Float` simulation, 50 Hz tick, no licensed code |

M2 is an assumption made for this document. Removing it admits one more option (3C).

## Wants and weights

| | Want | Weight |
|---|---|---|
| W1 | Benefit the player can see | 10 |
| W2 | Size of the gain against the target | 8 |
| W3 | Low risk of breaking something | 8 |
| W4 | Ease of proving it on the benchmark | 7 |
| W5 | Low effort | 5 |

Scores are 1 to 10. The highest possible total is 380.

## Proposal 1: smooth the remote tank on the guest

| | |
|---|---|
| Fault | `state.ticks` never advances on a guest, so the smoother always snaps. Remote tanks are drawn in 10 steps a second |
| Indicator | New: step interval of the drawn remote tank. Today about 100 ms; target 20 ms |
| Must do first | Add a probe for the drawn position. Smoothing is in the view, which the benchmark does not record today |

| Option | M1 | M2 | M3 | W1 | W2 | W3 | W4 | W5 | Total |
|---|---|---|---|---|---|---|---|---|---|
| 1A. Give the smoothers a tick counter owned by the view | Pass | Pass | Pass | 9 | 8 | 8 | 4 | 9 | **291** |
| 1B. Advance `state.ticks` in the guest tick | Pass | Pass | Pass | 9 | 8 | 3 | 4 | 10 | 256 |
| 1C. Step remote tanks every guest tick | Pass | Pass | Pass | 8 | 8 | 3 | 6 | 6 | 240 |

| Option | Size | Adverse consequence | Likelihood | Seriousness |
|---|---|---|---|---|
| 1A | About 10 lines, 1 file | Remote tanks drawn 100 ms late; must still snap on respawn | High | Low |
| 1B | 1 to 3 lines | `ticks` also drives the time limit and animation on the guest | Medium | High |
| 1C | About 15 lines | Rubber-banding; movement counted twice with the existing extrapolation | Medium | Medium |

**Recommend 1A.**

## Proposal 2: take the render wait out of the host tick

| | |
|---|---|
| Fault | Each host tick waits for the main thread twice, for drawing and for sounds. Median 0.15 ms, 95th percentile 12 to 18 ms, longest about 130 ms |
| Indicators | Host tick 95th percentile: 13.5 ms at 2, 20.0 ms at 4; target 10 ms. Late ticks: 2.3% to 4.4%; target 1% |
| Side effects found | Host position updates are sent after the wait, so they inherit its jitter. The draw reads fog state on the main thread while the engine changes it on another |
| Not known | What occupies the main thread. Drawing itself takes under 1 ms |

| Option | M1 | M2 | M3 | W1 | W2 | W3 | W4 | W5 | Total |
|---|---|---|---|---|---|---|---|---|---|
| 2A. Move both waits to after the position send | Pass | Pass | Pass | 3 | 2 | 9 | 6 | 9 | 205 |
| 2B. Hand the snapshot to the main thread without waiting, keeping only the latest | Pass | Pass | Pass | 6 | 9 | 6 | 9 | 7 | **278** |
| 2C. Engine publishes the latest snapshot; the view pulls it each frame | Pass | Pass | Pass | 7 | 9 | 4 | 9 | 4 | 257 |

| Option | Size | Adverse consequence | Likelihood | Seriousness |
|---|---|---|---|---|
| 2A | About 10 lines moved | Ticks still late; only the send jitter goes | High | Low |
| 2B | About 25 lines, 2 files | Host's own screen drops frames under load; sounds must never be dropped | Medium | Medium |
| 2C | About 50 lines, 3 files | Display cadence moves to frame rate; smoothing and the status display change with it | Medium | Medium |

**Recommend 2B,** passing the fog state with the snapshot, which also closes the unsafe read.

## Proposal 3: stop the status message refunding a mine

| | |
|---|---|
| Fault | While the builder walks, a host status message carries the old mine count and overwrites the guest's |
| Indicator | Resources wrong over 250 ms in the soak: 8 of 39 runs; target 0. Needs about 20 clean soak runs to prove |

| Option | M1 | M2 | M3 | W1 | W2 | W3 | W4 | W5 | Total |
|---|---|---|---|---|---|---|---|---|---|
| 3B. Guest applies the status count less `builderMines` | Pass | Pass | Pass | 4 | 7 | 6 | 8 | 9 | **245** |
| 3C. Guest reports the launch, host spends then | Pass | **Fail** | Pass | | | | | | Out |

| Option | Size | Adverse consequence | Likelihood | Seriousness |
|---|---|---|---|---|
| 3B | About 5 lines, 1 file | Interacts with the refund when a builder dies | Medium | Medium |

**Recommend 3B.** Whether it explains all 8 runs is inferred, not shown.

## Proposal 4: refresh the guest's fog memory on reveal

| | |
|---|---|
| Fault (inferred, medium confidence) | The host reveals a mined tile by proximity. If the guest has moved away when it arrives, the guest's own memory stays unmined and the mine is hidden |
| Indicators | Existing fog reveal test fails about 1 run in 12. Terrain wrong in the soak: 3 of 19 runs; target 0 |

| Option | M1 | M2 | M3 | W1 | W2 | W3 | W4 | W5 | Total |
|---|---|---|---|---|---|---|---|---|---|
| 4B. Guest refreshes its memory of a tile on each reveal | Pass | Pass | Pass | 6 | 7 | 6 | 7 | 8 | **253** |
| 4C. Guest stops hiding mines itself; the host already does | Pass | Pass | Pass | 6 | 7 | 4 | 7 | 8 | 237 |

| Option | Size | Adverse consequence | Likelihood | Seriousness |
|---|---|---|---|---|
| 4B | About 20 lines, 2 files | Could reveal mines through other terrain messages | Low | High |
| 4C | About 10 lines | Single-player shares the function and would need a switch | Medium | Medium |

**Recommend 4B, after the cause is reproduced in a test.**

## Ranking across proposals

| Order | Proposal | Total | Family | Effort |
|---|---|---|---|---|
| First | 0. Correct the measurement system | Prerequisite | All | Small |
| 1 | 1A. Smooth the remote tank | 291 | Responsiveness | Small, plus a new probe |
| 2 | 2B. Render wait out of the host tick | 278 | Cost, responsiveness | Medium |
| 3 | 4B. Refresh fog memory on reveal | 253 | Correctness | Small |
| 4 | 3B. Mine refund | 245 | Correctness | Small |

### Sensitivity of the ranking

| Weights | Order |
|---|---|
| As above | 1A, 2B, 4B, 3B |
| All wants equal | 1A, 2B, then 4B and 3B level |
| Provability doubled | 2B, 1A, 4B, 3B |
| Visible benefit halved | 1A and 2B within 2%, then 3B and 4B within 2% |

Proposals 1A and 2B are the top pair under every weighting; their order between them is not
robust. The same holds for 4B and 3B as the lower pair.

## Not proposed

| Idea | Reason |
|---|---|
| Periodic state checksum or resync | Changes the wire format. Revisit if faults remain after proposals 3 and 4 |
| Tank shots off the reliable channel | 88% of reliable traffic, but traffic is within limits at 2 to 4 players |
| Position relay cost | A cost at 8 and 16 players only |
| Position send taking 2.4 ms median | Not investigated. Worth a look once proposal 2 is measured |

## Challenges to expect

| Challenge | Answer | Standing |
|---|---|---|
| The first readout ranked a measurement artifact first | True, corrected above within the same day. Proposal 0 fixes the comparison | Conceded |
| Scores and weights are judgement | True. The sensitivity table shows what does and does not depend on them | Partly conceded |
| Root causes were read, not demonstrated | True. Each proposal needs a failing test first | Conceded |
| The 25% detection test scaled existing values | True. A real change can alter the spread as well as the level | Conceded |
| Control limits assume a bell curve on about 20 values | True. Treat them as provisional until more sessions exist | Conceded |
| Nobody knows what occupies the main thread | True. 2B removes the wait either way, but the host's own screen may still stutter | Open |
| Proposal 1 cannot be measured today | True. The probe comes first, under must M1 | Answered |
| One machine, no real network | Stated limit of the benchmark since Define | Answered |
| Effort figures are line counts from reading | True. They exclude tests and benchmark sessions of about 2 hours each | Conceded |
