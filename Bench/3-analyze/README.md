# Analyze phase

**Status: in progress.** Not closed.

Gate register: `REGISTER.md`. Historical KT scores: `KT.md`.
Audit of that KT: `KT-audit-findings.md`. SPECS: `SPECS.md`.

A1 charter and A5 integrator accepted 2026-09-29. Improve is closed.

## Y and weights

UX. Responsiveness 45, tick-budget cost 30, player-visible correctness 25.
Define (amended) is the source. Equal weight is superseded.

## Quarantined until P0 / P1

These Measure headlines are not findings and not targets:

- Guest fog memory ~300 tiles
- Builder-placed mine wrong for 1.3 s
- Host tank on the guest screen every 141–400 ms (whole-tile)

## Still in force from Measure

Tick interval, late ticks, render hop, host tick p95, CPU, traffic.
Pills, bases, own status, visibility, peers: no lasting faults in scripted play.

## Parked depth

Resync / periodic checksum — 2.*, wire change, authority model.

## Open Analyze work

| Item | Status |
|---|---|
| P0a fogSeen filter + join target; re-read into `data/analyze/` | Spec in A2. Not executed |
| P0b digest `mines + builderMines` | Spec. Needs new runs |
| 2C architecture; 2B gated on wait/work split | A3 accepted as Analyze |
| P1 drawn-position probe; 3B/4B unit tests | Designed in A4. Not in the tree |

Improve is closed.
