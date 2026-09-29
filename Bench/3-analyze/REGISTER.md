# Analyze register

**Status: accepted 2026-09-29 (A5).** Replaces `KT.md` as the gate register.
`KT.md` keeps the historical Musts/Wants scores. Do not treat those ranks as the live list.

Musts unchanged: M1 bench can prove, M2 no 1.* wire change, M3 `AGENTS.md`.

Y: UX. Weights: Responsiveness 45, tick-budget 30, player-visible correctness 25.

## Prerequisites

| Item | Needed by | Status |
|---|---|---|
| P0a fogSeen only when not visible; drop `join_to_alive` as a target; re-read into `data/analyze/` | Correctness scorecard | Spec only (A2) |
| P0b digest `mines + builderMines`; optional finer peer position | 3B numeric baseline | Spec only. New runs |
| P1 drawn-position probe + one soak | 1A | Design only (A4) |
| `mainHopWait` vs `mainHopWork` | Any 2B patch | Named (A3). Not instrumented |
| 3B test: `recvSrTankStatus` refund | Keep or drop 3B | Design only (A4) |
| 4B test: reveal vs `seenTiles` / `fogTileFor` | Keep or drop 4B | Design only (A4) |

## 1.* after the gate

| Item | Status | UX family | Enter Improve when |
|---|---|---|---|
| 1A view-owned smoother clock | Hold for P1 | Responsiveness 45 | Probe + baseline soak exist |
| 2C engine publishes, view pulls | Architecture choice | Tick-budget 30 + host frames | Jerod accepts 2C and Analyze is closed |
| 2B snapshot, do not wait | Expedient only | Tick-budget 30 | Wait/work split shows wait dominates and Jerod accepts host-frame-drop |
| 2A hops after send | Rejected | — | Never |
| 3B status minus `builderMines` | Hold | Visible correctness 25 | Failing unit test on v1.6.9, then Analyze closed |
| 4B refresh memory on reveal | Hold | Visible correctness 25 | Failing unit test on v1.6.9, then Analyze closed |
| Speed up position send | Hold behind 2C/2B | Tick-budget | After hop is off the send path |
| Relay positions / 8–16 | Drop 1.* / watch | Cost | 2.* or watch |
| Diagonal pill | Hold | Correctness | Reproduce in a test |
| Terrain change tracking, fog copies, clock, join-off-consumer | Drop 1.* | Not UX | — |

## 2.* parked depth

| Item | Note |
|---|---|
| Resync / checksum | Authority-model fix for "host changed state without telling guests." M2. Named depth, not dropped |
| Shots off reliable / batch reveals | Traffic; control-only at 2–4 |
| 3C guest reports builder launch | Wire. Alternative to 3B at 2.* |

## Top pair

**1A** (responsiveness) and **2C** (tick / host-frame architecture). 2B is not the default.

Nothing in this register is Improve-ready. Analyze stays open.
