# Analyze phase

**Status: closed 2026-10-02 by Jerod.** Improve is open: `../4-improve/README.md`.
The Analyze reference data is `../data/analyze/v1.6.9-analyze-session2/` (frozen, tag
`analyze/v1.6.9-analyze-session2`).

Gate register: `REGISTER.md`. Historical KT scores: `KT.md`.
Audit of that KT: `KT-audit-findings.md`. SPECS: `SPECS.md`.

A1 charter and A5 integrator accepted 2026-09-29. Closing decisions in `REGISTER.md`.

## Y and weights

UX. Responsiveness 45, tick-budget cost 30, player-visible correctness 25.
Define (amended) is the source. Equal weight is superseded.

## Quarantine, resolved 2026-09-30

| Measure headline | Outcome |
|---|---|
| Guest fog memory ~300 tiles | Comparison artifact. After P0a: 0 in scripted play; median 29 tiles in fog at end of the Hidden Mines soak, 13 of 19 runs. That residue is a target |
| Builder-placed mine wrong for 1.3 s | Comparison artifact; the refund fault behind it is demonstrated by test. Baseline awaits P0b |
| Host tank on the guest screen every 141–400 ms | Whole-tile artifact. Replaced by the drawn step measured in the P1 soak |

## Still in force from Measure

Tick interval, late ticks, render hop, host tick p95, CPU, traffic.
Pills, bases, own status, visibility, peers: no lasting faults in scripted play.

## Parked depth

Resync / periodic checksum — 2.*, wire change, authority model.

## Open Analyze work

| Item | Status |
|---|---|
| P0a fogSeen filter; re-read into `data/analyze/p0a-fog-join/` | Done 2026-09-30 |
| P0b digest `mines + builderMines` | Spec. Needs new runs |
| 2C architecture; 2B gated on wait/work split | Split instrumented and measured in the P1 soak; choice open |
| P1 drawn-position probe; 3B/4B unit tests | In the tree 2026-09-30; see `REGISTER.md` |

Improve is closed.
