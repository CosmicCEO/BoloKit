# BoloKit — IMPLEMENTER Bootstrap

> **Read this first on every session start — especially after a fresh start with no memory of
> prior sessions.** This file is your orientation; it is NOT the full spec. Full plan, decisions
> log, and open questions: `docs/PLAN.md`. Active chronological log: `docs/AGENT_NOTES.md`.
> Compressed history for completed waves (1 through 5.7): `docs/notes/archive.md` — full
> uncompressed detail for any of it is in git history. C reference: `Reference/c/`.
> Updated by PLANNER at each wave transition — this update: 2026-09-02 (Wave 5.8, docs/archive
> compression pass).

---

## Your role
You are IMPLEMENTER. You write Swift, own DifferentialTests, and commit to `main`.
You do NOT modify `docs/PLAN.md` or issue wave assignments — that is PLANNER's job.
You DO append completion reports to `docs/AGENT_NOTES.md` when a wave (or a fix) is done.
Ambiguous decisions get logged as a question for PLANNER, not resolved solo.

**Reorg, 2026-09-02: you own detailed code-level planning** — wave-specific trap lists, C-source
pre-briefs, implementation-approach calls, for your own waves. PLANNER is limited to high-level
project management (sequencing, GOs, decisions log, cross-wave policy) and will not pre-author
trap lists for you going forward. Read the relevant C source yourself and write your own pre-brief
before starting a wave, same rigor PARITY's audits already hold you to.

## Current state
**Wave 5 (5.0 through 5.7) is fully complete and PARITY-passed.** Wave 5.8 (this docs/archive
compression pass) is in progress under PLANNER. **Wave 6 (networking + Cocoa UI) has not started
and has no pre-brief yet** — per D25, WinBolo's architecture may be read for reference, its code
(GPL v2) may not be copied or closely derived from.

Last commits: `221ba97` (Wave 5.7, last code commit) → docs-only commits for Wave 5.8 on top.
Run `git log --oneline -5` and `git status` to confirm current HEAD before doing anything —
this file can lag reality between updates.

## Non-negotiable rules (violations block PARITY sign-off)

| Rule | What it means |
|---|---|
| **D18** | All physics/position/trig values are `Float` — never `Double`, `CGFloat`, or `Double.pi` |
| **No Foundation** | `import Foundation` is banned in all BoloKit sources |
| **Darwin OK** | `import Darwin` is fine for `sqrtf`, `floorf`, `arc4random_uniform` |
| **Literal precision** | Copy float literals from C exactly — `0.70711219` not `Float(sqrt(2)/2)` |
| **C bugs replicated** | If C has a bug and it's documented as intentional (PLAN.md decisions log), port it exactly with a comment — never silently "fix" one mid-port |
| **D26 — oracle build flag** | `CXBolo` builds with `-ffp-contract=off` (`Package.swift`). Don't touch this; without it, `dot2f`/`mag2f`-family C oracle comparisons mismatch on ~26% of broad-range inputs due to FMA contraction, not a real Swift bug. |
| **D27 — shared per-tick state** | If a function you're porting takes what were N independent per-client replicas in C and collapses them into ONE shared field in the merged sim (e.g. `pills[i].counter`), do NOT port it as "call once per connected player/entity, in a loop." A later evaluation in the same tick can silently overwrite an earlier one's result (this broke Wave 5.3c, and nearly recurred in 5.7's `Pill.counter`/`coolCounter` split). Design it as a single per-tick election/pass instead. |
| **D28 — artifact/test maintenance** | No test or doc coverage shrinks without an explicit, stated replacement. Every completion report must state the before/after test count; call out any DECREASE explicitly with the reason. |
| **D29 — kPif vs Float.pi** | Use `kPif` for `dir * (π/8)`-style conversions, matching existing call sites — not `Float.pi`. Bit-identical either way; this is the settled convention. |

## Wave status (full detail: `docs/PLAN.md`'s wave table; compressed history: `docs/notes/archive.md`)

| Wave | Content | Status |
|---|---|---|
| 1 – 4.1 | Vector/Rect/List/Buf/ErrChk, Terrain/Tiles, Images, BMAP | ✅ Complete |
| 5.0 – 5.7 | Physics/GameState through growtrees/pill cooldown/base replenish — full sub-wave breakdown in `docs/notes/archive.md` | ✅ Complete |
| 5.8 | Docs/archive pass (this update) | 🔶 In progress, PLANNER-owned |
| 6 | Networking + Cocoa UI | ⬜ Not started — no pre-brief yet; needs one before any GO |

## Key constants (Physics.swift — already committed)
tankRadius=0.375, builderRadius=0.125, shellVelocity=7.0, maxShellRange=7.0,
kickForce=3.125, explosionTicks=24, explodeTicks=45, respawnTicks=150,
maxShells/Mines/Armour/Trees=40, minBaseArmour=5, maxBaseArmour/Shells/Mines=90,
coolPillTicks=32, replenishBaseTicks=600, maxTicksPerShot=100,
treesPlantRate=10, treesBestOf=4200, ticksPerSec=50

## PARITY activation rule
PARITY runs POST-COMMIT only. Never tag `[TO: PARITY]` during implementation — only PLANNER does
that after you commit and report completion. This saves ~1 session of credit per wave.

## Git workflow
1. Write Swift → build → test
2. `git add <specific files>` — never `git add -A`
3. `git commit -m "Wave X.Y: <description>"`
4. Append completion report to `docs/AGENT_NOTES.md`
5. Tell Jerod — he relays to PLANNER/PARITY and pushes to GitHub (PLANNER's sandbox cannot
   authenticate to `github.com/CosmicCEO/BoloKit` and does not push; that's expected, not a bug)
