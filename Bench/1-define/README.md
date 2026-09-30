# Define phase

**Status: closed.** Amended 2026-09-29 (Y and CTQ weights). Problem and measurement
scope are unchanged.

## Problem

The host/client architecture was not designed up front and has been corrected piecemeal. In the
four weeks before v1.6.9, the "host changed state without telling guests" fault was fixed three
separate times, resource accounting three times, and fog about five times. Every recent defect
was guest-only and was found in live play.

## Goal (Y)

The player-visible quality of host/client play: motion that looks continuous, ticks that do not
hitch, and disagreement only when the player can see or act on it.

A numeric benchmark of v1.6.9 is the Measure deliverable that serves this Y. It is not the Y.

## Scope

| In | Out |
|---|---|
| Host and guest of the shipped app, on one Mac | Two-machine and impaired-network play |
| One host and one guest; host cost to 16 players | Guest experience beyond two players |
| Measuring | Fixing anything |

Specs for Analyze/Improve judge 2 to 4 players. 8 and 16 stay watch items.

## Critical to quality

UX is the outcome. Weights are not equal.

| CTQ | Weight | Question | Counts when |
|---|---|---|---|
| Responsiveness | 45 | How long until a player sees it? | Drawn motion, input-to-frame, late ticks, hitching |
| Cost (tick budget) | 30 | What steals the 20 ms tick? | Render hop, host tick p95, work that makes ticks late |
| Correctness | 25 | Do host and guest agree on what the player can see? | Player-visible or player-actionable disagreement only |

Analyzer-only disagreement (separate fog memories, `mines` vs `mines + builderMines`, whole-tile
steps) is not this CTQ until P0 says otherwise.

CPU, memory, and traffic at 2–4 players are control/watch, not UX, unless they force late ticks.

## Player-visible vs analyzer-only

| Class | Meaning |
|---|---|
| Player-visible | A human watching the guest screen can see it or act on it (HUD count, drawn tank step, hitch, mine that should appear) |
| Analyzer-only | Host and guest logs differ by design or by a comparison that the screen does not show |

## Parked depth

Periodic state checksum or resync is the authority-model answer to "host changed state without
telling guests." It changes the wire format. It is parked for 2.* as named depth, not dropped.

## Decisions

| Decision | By | Date |
|---|---|---|
| Correctness, responsiveness and cost, equal weight | Jerod | 2026-09-28 |
| Equal weight superseded: 45 / 30 / 25, UX is the Y | Jerod | 2026-09-29 |
| Baseline on a branch cut from `v1.6.9`, measurement code only, no wire or behaviour change | Jerod | 2026-09-28 |
| Everything on the one M1 MacBook Pro | Jerod | 2026-09-28 |
| Scripted scenarios plus a seeded soak; nobody driving | Jerod | 2026-09-28 |
| Full scorecard at two players; host-cost sweep at 2, 4, 8 and 16 | Jerod | 2026-09-28 |
| Instrumentation always compiled, recording off by default | Jerod | 2026-09-28 |
| The `Float` rule in `AGENTS.md` covers the simulation; the benchmark's steering stays in `Double` | Jerod | 2026-09-28 |
| Wire format closed to 1.*; open at 2.* | Jerod | 2026-09-29 |
| Analyze stays open until P0 and one scorecard | Jerod | 2026-09-29 |
| Three Measure headlines quarantined until P0 | Jerod | 2026-09-29 |
| 2B vs 2C decided as architecture, not shipped as a patch | Jerod | 2026-09-29 |
| Resync parked for 2.* as named depth | Jerod | 2026-09-29 |
| A1 charter and A5 SPECS/register accepted onto this branch | Jerod | 2026-09-29 |
