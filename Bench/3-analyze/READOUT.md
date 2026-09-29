# Analyze: first readout

**2026-09-29.** Answers three questions from the frozen benchmark. No new runs were made and no
game code was changed. Figures come from `python3 Bench/scripts/capability.py`.

## 1. Is the benchmark a reliable way to evaluate continuous improvement?

**Yes, at the 25% level Jerod set, with two exceptions.**

The test: scale each session's values down by 25%, as if the code had improved, and ask whether
the comparison rule declares a change against the pooled baseline. Both sessions must pass.

| Family | 25% gain proven | 10% gain proven | False alarms |
|---|---|---|---|
| Traffic | 100% | 100% | 0% |
| CPU and memory | 98% to 100% | 67% to 75% | 0% |
| Pacing (tick, frame intervals) | 86% to 93% | 67% to 76% | 0% |
| Durations (tick phases, apply, draw) | 76% to 84% | 10% to 27% | 0% |
| Link delays | 45% to 51% | 13% to 23% | 0% |

| Exception | Consequence |
|---|---|
| Link delays prove a 25% gain only half the time | Report them; do not judge a release on them |
| About 1 in 5 duration metrics cannot prove a 25% gain | Judge host tick cost on the soak and 4-player sweep, where it can |

The benchmark never raised a false alarm on unchanged code. It cannot support fine tuning: a 10%
gain in a duration is proven only 1 time in 10.

## 2. Can performance specifications and standards be defined now?

**Yes.** They are proposed in `SPECS.md`, for Jerod's approval.

| | Count |
|---|---|
| Standards v1.6.9 already meets, to be held by control limits | 15 |
| Targets v1.6.9 does not meet, to be improved | 9 |

## 3. What is ripe for optimization?

Ranked for 2 to 4 players against the proposed targets.

| Rank | Area | Gap | Benchmark can prove the fix |
|---|---|---|---|
| 1 | Guest fog memory | About 300 tiles wrong in every Hidden Mines run; over 99% of all lasting faults | Yes, every run |
| 2 | Host's tank on the guest's screen | Moves every 400 ms; target 100 ms | Yes, in the soak |
| 3 | Render hop inside the host tick | 12.9 to 17.8 ms of a 20 ms tick; makes 2.3% to 4.4% of ticks late | Yes, in the soak and 4-player sweep |
| 4 | Builder-placed mine count | Wrong for 1.3 s, every run | Yes, every run |
| 5 | Intermittent resource and terrain faults | 8 of 39 and 3 of 19 soak runs | Only with about 20 soak runs |

| Not ripe | Reason |
|---|---|
| Guest tick cost | 0.1 ms median; nothing to gain |
| CPU, memory, loss | Within any reasonable standard |
| Position and reliable traffic | A cost at 8 and 16 players only; watch item |

## Open before Improve starts

| Item | Why |
|---|---|
| Confirm the fog-memory fault is visible to the player | The analyzer compares against a modelled view. If the model is wrong, rank 1 is a measurement fault, not a game fault |
| Root cause for ranks 1 to 4 | This readout ranks gaps; it does not explain them |
| `guest.join_to_alive_ms` is marked not repeatable | Wrong rule: a 10 ms limit on a 2,000 ms value. It varies under 3% and proves a 25% gain in 9 of 9 scenarios |
| Cause of the 9% to 25% session shift | Not needed at the 25% level. Needed before any 10% claim |

## Recommended practice

Run the baseline build and the candidate build back to back in one session. Day-to-day drift
then affects both and cancels out.
