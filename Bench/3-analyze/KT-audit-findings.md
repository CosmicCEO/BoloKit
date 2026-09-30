# KT audit findings

**Status: gate, 2026-09-29.** Copy of `KT.md` with the adversarial audit on it.
`KT.md` is unchanged. This file does not close Analyze.

| | |
|---|---|
| Subject | `Bench/3-analyze/KT.md` on `bench/v1.6.9-baseline` |
| Also read | `PROPOSALS.md`, `OBSERVED.md`, `READOUT.md`, `SPECS.md`, `1-define/README.md`, `2-measure/README.md`, `2-measure/SYSTEM.md` |
| Auditor | Grok, gate auditor. Improve code is out of scope |
| Y | UX. Player-visible motion, hitching, and disagreement |
| CTQ weights used | Responsiveness 45. Tick-budget cost 30. Player-visible correctness 25 |
| Equal CTQ weight in Define | Rejected for this gate |

## Gate

| Phase | Verdict |
|---|---|
| Define | Conditional pass. Amend the Y and the weights |
| Measure | Conditional pass. Freeze stands for pacing and cost. Correctness family is quarantined until P0 |
| Analyze | Does not close |
| Improve | Stays closed |

## Decisions by Jerod, 2026-09-29

| Decision | Ruling |
|---|---|
| Analyze close | Stays open. P0, backup of raw logs, and one scorecard before any Improve work |
| Measure headlines | Quarantine all three until P0: `fogSeen` (~300 tiles), builder-mine 1.3 s, remote-tank 141–400 ms tile-step. Not targets, not KT ranks. Tick interval, late ticks, render hop, CPU/traffic still stand |
| 2B vs 2C | Decide architecture first. Find what blocks the main thread. Score host-frame-drop as UX risk. Do not ship 2B while that is open |
| Resync / checksum | Park for 2.*. Name it parked depth: the authority-model fix for "host changed state without telling guests." M2 stands. Not "unimportant" |

## What this file is

The tables under "Original register" are the analyst's scores, copied.
The tables under "Audit" are the gate. Scores in the original are not rewritten.
A row that still passes the musts can fail the gate because the cause is unproven, the KPI is an artifact, or the gain is not UX.

---

## Audit of the method

| Piece | Sound? | Finding |
|---|---|---|
| Musts M1–M3 | Yes for a 1.* line | M2 (no wire change) is a product constraint, not an analysis conclusion. Record resync as parked depth, not as "not important" |
| Wants W1–W5 | Partial | W1 matches the Y. W5 (low effort) and W2 (25% against a possibly artifactual baseline) can promote cheap invisible work. Under the UX stack, W1 and tick-budget effect dominate |
| Score = judgement × weight | Disclosed, still a weakness | Sensitivity table in `PROPOSALS.md` already shows 1A/2B and 3B/4B orders are not robust. Do not treat 291 vs 278 as a decision |
| Evidence grades | Sound | Measured / Read / Inferred is the right scale. Inferred items are not Improve-ready |
| "No experiment was run" | Disqualifies close | Line-numbered reading is not root cause. The audit pack on the top five is the right next work, not optional colour |
| 25% smallest gain | Sound for the instrument | Not the same as "worth doing for UX." A hitch the player feels can be in scope even when a median cannot prove 25% |
| Scope 2–4 players | Narrowed without reopening Define | Define swept to 16. Quadratic position traffic is the one cost curve that explodes. Parking it for 1.* is fine. Calling Cost analyzed is not |

## Audit of Define, as it feeds the register

| Claim in Define | Gate |
|---|---|
| Problem: piecemeal host/client, guest-only defects in live play | Accept. That is the problem the register should have gone deep on |
| Goal: a numeric benchmark | Reject as the Y. That is a Measure deliverable. The Y is UX |
| CTQs equal weight | Reject. Sponsor re-weight: UX via responsiveness and tick cost, then visible correctness |
| Out: two-machine play | Disclosed limit. It under-detects the problem statement. Do not close Analyze as if live two-Mac faults were in the data |
| Out: fixing | Honoured on the baseline branch. Analyze then wrote an Improve register anyway. That is allowed as a *candidate* list. It is not a closed Analyze |

## Audit of Measure, as it feeds the register

| Claim in Measure | Gate |
|---|---|
| 218 valid runs, 0 drops, 0 false alarms on unchanged code | Accept for pacing, traffic, CPU, memory |
| Analyzer accurate (20/20 final-state match, 6/6 planted) | Qualified fail for correctness. The check used the same "should agree" definition the analyzer uses. Three headline rows were later withdrawn as comparison artifacts |
| Fog 300 tiles, mine 1.3 s, tank every 400 ms | Quarantine. `SPECS.md` already withdraws them. `KT.md` still spends rank on 3 and 4 |
| Soak/sweep repeatability 61–75% | Accept as the reason 25% is the floor. Those are also the tiers SPECS uses to judge host tick p95 |
| Raw logs on one machine, not in git | Condition. `PROPOSALS.md` says they are not backed up. P0 cannot run if that disk dies |

---

## Original register (copied from KT.md)

Musts: M1 benchmark can prove it or the change makes it able to. M2 no 1.* wire change. M3 `AGENTS.md`.

Wants (analyst): W1 player-visible 10, W2 gain vs target 8, W3 low risk 8, W4 prove on bench 7, W5 low effort 5. Max 380.

### Prerequisites (not scored)

| | Item | Needed by | Size |
|---|---|---|---|
| P0 | Correct the measurement system and re-analyse the raw logs | Every correctness target; items 3 and 4 | About 40 lines, no new runs |
| P1 | Probe for the drawn position of remote tanks | Item 1 | Small |
| P2 | Scenario that fires a pill along an exact diagonal | Item 7 | Small |

### 1.* items, analyst order

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

### Held for 2.* (copied)

| Item | Fails in 1.* | Score for 2.* | KPI |
|---|---|---|---|
| Tank shots off the reliable channel, or deltas | M2 | 214 | 85% to 99% of reliable bytes when firing |
| Periodic state checksum or resync | M2 | 204 | Lasting faults from unknown causes |
| Batch terrain reveals | M2 | 203 | 95% to 98% of reliable bytes in quiet play |
| Guest reports builder launch (3C) | M2 | Not scored | Alternative to item 4 |

---

## Audit of each row

Gate column: **Ready** = may enter Improve after the named prerequisite. **Hold** = stays in Analyze. **Drop 1.*** = not worth a 1.* change. **Park 2.*** = real depth, wrong release.

### Prerequisites

| Item | Gate | Finding |
|---|---|---|
| P0 | **Do first. Blocks close** | This is the remaining Analyze work, not housekeeping. Until it runs, items 3 and 4 have no trustworthy KPI. Back up `Bench/runs/` before touching the analyzer. Write output to `data/analyze/`. Do not edit the frozen baseline |
| P1 | **Do before 1A work** | M1 is not actually passed for item 1 until this probe exists. Ranking 1A first without P1 is a method breach |
| P2 | Hold with item 7 | No benchmark KPI today. Test first, then decide if a scenario is needed |

### 1.* items

| Item | Analyst rank | Gate | UX family | Depth | Finding |
|---|---|---|---|---|---|
| 1A Smooth remote tank | 1 | **Hold for P1, then Ready** | Responsiveness | Almost | Right UX target. 1B/1C correctly rejected. Baseline 100 ms is derived from send rate, not measured drawn steps. W4=4 is the tell. Adverse "drawn 100 ms late" is an UX cost and was graded Low; revisit after the probe |
| 2B Render wait off host tick | 2 | **Hold one question, then Ready** | Tick-budget / hitching | Almost | Only cost item that can move what the player feels. Render hop 12–18 ms, draw <1 ms, stands. Correlation of late ticks to the wait is 0.45–0.67; the pack already says a late tick with a short wait refutes it. Open: what owns the main thread. Adverse "host screen drops frames" is an UX failure, scored W3=6. Rescore 2B vs 2C with that as UX risk, not engineering inconvenience |
| 4B Fog refresh on reveal | 3 | **Hold** | Visible correctness, maybe | Shallow until proven | Inferred. Own audit pack calls the hidden-mine link the weakest claim. `SPECS.md` withdrew the 300-tile fog row as not player-visible. Cannot keep rank 3 on a withdrawn metric plus an unreproduced 1-in-12 test. One failing test or drop from the 1.* register |
| 3B Status mine refund | 4 | **Hold** | Visible correctness, maybe | Shallow until proven | Read path is plausible. Reach across 8 of 39 soak runs is inferred. `SPECS.md` withdrew the 1.3 s builder-mine row because `mines + builderMines` already agrees. HUD-visible wrong count is the only UX case. Failing test that shows the soak faults with a builder out, or drop |
| Position send speed | 5 | **Hold behind 2B** | Tick-budget | Not analyzed | Cause unknown. May be waiting on the network stack. No target. Look only after 2B is measured |
| Relay positions | 6 | **Drop 1.* / watch 4p** | Cost, not UX at 2–4 | Out of 1.* Y | Measured quadratic growth. Material at 8–16, which SPECS parked. No player-visible gain at 2–4 inside traffic control limits |
| Diagonal pill | 7 | **Hold** | Correctness | Unknown | Seen once in the harness. Pills never diverged in 218 runs. Reproduce in a test. Do not Improve from a single observation |
| Terrain change tracking | 8 | **Drop 1.*** | Cost, not UX | Shallow | 21–30% of a 0.35 ms median. Player cannot see it. OBSERVED already said so |
| Fog array copies | 9 | **Drop 1.*** | Cost, not UX | Shallow | 3–8% of median tick. OBSERVED already dropped it |
| Drift-corrected clock | 10 | **Drop 1.*** | Responsiveness | Shallow | Under 5% available vs 20.9 ms. OBSERVED already dropped it |
| Join off consumer | 11 | **Drop 1.*** | Responsiveness | Shallow | Stall equals one normal tick. OBSERVED already dropped it |

### 2.* holds

| Item | Gate | Finding |
|---|---|---|
| Resync / checksum | **Park 2.*** This is the deep correctness item | Matches Define: host changed state without telling guests. M2 parks it. Do not let the 1.* register pretend correctness was taken to root cause |
| Shots off reliable / deltas | Park 2.* | Large traffic, traffic is control-only at 2–4 |
| Batch reveals | Park 2.* | Same |
| 3C guest reports builder launch | Park 2.* | Fair alternative to 3B once wire may change |

### Alternatives the analyst rejected

| Item | Analyst reason | Gate |
|---|---|---|
| 2C Engine publishes, view pulls | Larger change, same gain | Challenge. If 2B drops host frames, 2C is the deeper UX architecture, not the same gain. Rescore after the main-thread question |
| 1B Advance `state.ticks` on guest | Time limit and animation | Accept reject |
| 1C Step every guest tick | Rubber-banding | Accept reject |
| 4C Guest stops hiding mines | Shares single-player function | Accept reject pending the 4B test |
| 2A Move waits after position send | Ticks still late | Accept reject |

---

## Documents that disagree (must be one story before close)

| Document | Says | Conflict |
|---|---|---|
| `READOUT.md` §3 | Fog memory is rank 1 ripe work | Banner says corrected. Section 3 still sits there |
| `SPECS.md` | Fog memory, builder mine, tile-step interval withdrawn | Same file still prints control limits and "Met today: No" on those rows |
| `KT.md` | 4B and 3B are ranks 3 and 4 | Built on the withdrawn rows plus inferred reach |
| `3-analyze/README.md` | Findings list still leads with 300 tiles and 1.3 s | Stale handoff. The index on this branch says Analyze is in progress; this README still reads like Measure |

A closed Analyze has one scorecard.

## Depth vs the three CTQs (UX stack)

Define said the architecture was never designed. The register is mostly local patches.

| CTQ | Weight | Deep enough? | What would be deep |
|---|---|---|---|
| Responsiveness | 45 | Almost, item 1A only | Measured drawn-step KPI. Then decide if 10 Hz send plus a view-owned tick is the architecture you want |
| Tick-budget cost | 30 | Almost, item 2B only | What blocks the main thread. 2B vs 2C scored as UX (dropped host frames), not as line count |
| Player-visible correctness | 25 | No | P0 first. Then only faults a player can see or act on. The authority-model answer (resync) is parked by M2 and must stay visible as parked depth |

CPU, memory, and traffic at 2–4 players stay control/watch. They do not buy UX in this spec.

## What I would accept as a closed Analyze

1. Amend Define: UX is the Y; weights 45 / 30 / 25; operational definition of player-visible vs analyzer-only.
2. Back up raw logs. Run P0. Publish `data/analyze/` scorecards. Delete withdrawn rows from SPECS for good.
3. Ship P1. Put a measured 1A baseline on the scorecard.
4. One failing test each for 3B and 4B, or remove them from the 1.* register.
5. Answer what owns the main thread, or keep that as an open Analyze item. Rescore 2B vs 2C with host-frame-drop as UX.
6. SPECS in two pages: provisional tripwires, and UX targets that survive P0 (late ticks → 1%; host tick p95 on soak/4p → 10 ms; drawn remote step → 20 ms).
7. One register that matches SPECS. Expected top pair: 1A and 2B. Nothing else is Improve-ready.

## Decisions requested of Jerod

Four rulings are recorded above. One remains.

| Decision | Options |
|---|---|
| Accept the UX stack for the rest of DMAIC | 45 / 30 / 25 as used in this audit, or name other numbers |

## Housekeeping the register already had (no KPI)

Dropped-datagram log byte 1 vs 0. Four app tests fail on the tag. `swift test` can hang under full parallel. None of these close or block Analyze. Do not let them enter the ranked list.
