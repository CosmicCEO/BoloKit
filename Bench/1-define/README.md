# Define phase

**Status: closed.**

## Problem

The host/client architecture was not designed up front and has been corrected piecemeal. In the
four weeks before v1.6.9, the "host changed state without telling guests" fault was fixed three
separate times, resource accounting three times, and fog about five times. Every recent defect
was guest-only and was found in live play.

## Goal

A numeric benchmark of v1.6.9's host/client play, so that later changes are judged against data.

## Scope

| In | Out |
|---|---|
| Host and guest of the shipped app, on one Mac | Two-machine and impaired-network play |
| One host and one guest; host cost to 16 players | Guest experience beyond two players |
| Measuring | Fixing anything |

## Critical to quality

Weighted equally.

| | Question |
|---|---|
| Correctness | Do host and guest agree on the game? |
| Responsiveness | How long until a player sees it? |
| Cost | What does it take from the machine? |

## Decisions

| Decision | By | Date |
|---|---|---|
| Correctness, responsiveness and cost, equal weight | Jerod | 2026-09-28 |
| Baseline on a branch cut from `v1.6.9`, measurement code only, no wire or behaviour change | Jerod | 2026-09-28 |
| Everything on the one M1 MacBook Pro | Jerod | 2026-09-28 |
| Scripted scenarios plus a seeded soak; nobody driving | Jerod | 2026-09-28 |
| Full scorecard at two players; host-cost sweep at 2, 4, 8 and 16 | Jerod | 2026-09-28 |
| Instrumentation always compiled, recording off by default | Jerod | 2026-09-28 |
| The `Float` rule in `AGENTS.md` covers the simulation; the benchmark's steering stays in `Double` | Jerod | 2026-09-28 |
