# BoloKit — IMPLEMENTER Bootstrap

> **Read this first on every session start — especially after a fresh start with no memory of
> prior sessions (e.g. after a reboot).** This file is your orientation; it is NOT the full
> spec. Full plan, decisions log, and open questions: `docs/PLAN.md`. Full chronological history,
> completion reports, and wave pre-briefs/trap lists: `docs/AGENT_NOTES.md` (search for the wave
> name, e.g. `WAVE 5.7`). C reference: `Reference/c/`. Updated by PLANNER at each wave transition
> — this update: 2026-09-02, ahead of a planned macOS reboot.

---

## Your role
You are IMPLEMENTER. You write Swift, own DifferentialTests, and commit to `main`.
You do NOT modify `docs/PLAN.md` or issue wave assignments — that is PLANNER's job.
You DO append completion reports to `docs/AGENT_NOTES.md` when a wave (or a fix) is done.
Ambiguous decisions get logged as a question for PLANNER, not resolved solo.

## FIRST THING TO DO, before reading anything else below
Run `git status` and `git log --oneline -5`. **As of this bootstrap, Wave 5.6 (`spawn()`) is
implemented, tested, and has a completion report in `docs/AGENT_NOTES.md` (search `Wave 5.6
complete`) — but it is NOT YET COMMITTED.** `git status` should show:

- `Sources/BoloKit/Spawn.swift` — untracked, new
- `Tests/BoloKitTests/SpawnTests.swift` — untracked, new
- `Sources/BoloKit/GameObjects.swift` — modified (adds `DominationType` enum)
- `Sources/BoloKit/GameState.swift` — modified (adds `dominationType` field)

**If you see exactly this: your first action is to commit it**, not to re-implement or
second-guess it. Per the completion report: build, run the full test suite (should be 274/274,
up from 267 before this wave — 7 new tests, all additions, per D28), and if green, commit with
`git add Sources/BoloKit/Spawn.swift Sources/BoloKit/GameObjects.swift
Sources/BoloKit/GameState.swift Tests/BoloKitTests/SpawnTests.swift` then
`git commit -m "Wave 5.6: spawn() — two-pass weighted start selection"`. Then tell Jerod so he can
relay to PARITY (PARITY can't audit a wave with no commit hash) and push to GitHub.

**One open item from that report is already resolved — no action needed:** the report flagged
using `kPif` instead of the original trap note's `Float.pi` suggestion for the post-spawn dir
conversion. PLANNER ruled (`docs/PLAN.md`, decision **D29**): keep `kPif` — it's bit-identical to
`Float.pi` (D18) and matches every other shipped call site doing this same conversion
(`killBuilder`, `roundDir`, `Vector.swift`'s helpers). Nothing to change there.

If `git status` looks different from the above when you read this (e.g. already committed, or
different files) — trust what you see over this document and reconcile before proceeding;
this file may be slightly behind reality by the time you read it.

## Current assignment
**Wave 5.6 — `spawn()`** — implemented + tested + reported; **commit it, then hand off** (see
above). Full trap list: `docs/AGENT_NOTES.md`, search `WAVE 5.6`.

**Next up: Wave 5.7 — `growtrees`, pill cooldown, base replenish.** Do NOT start this until
PLANNER has reviewed PARITY's Wave 5.6 audit and issued an explicit `[TO: IMPLEMENTER]` GO in
`docs/AGENT_NOTES.md` — same protocol as every prior wave transition, no shortcuts for the
reboot. Wave 5.7's trap list is summarized below so you have it ready when the GO lands.

## Last known good commit
`4748631` — Planner: close Wave 5.5, fix D22 doc-consistency finding, GO for 5.6 (docs only).
`08c6e85` — Wave 5.5b: explosionTick — drains explosion particle lists (last **code** commit).
Wave 5.6's work sits uncommitted on top of these — see above.

## Non-negotiable rules (violations block PARITY sign-off)

| Rule | What it means |
|---|---|
| **D18** | All physics/position/trig values are `Float` — never `Double`, `CGFloat`, or `Double.pi` |
| **No Foundation** | `import Foundation` is banned in all BoloKit sources |
| **Darwin OK** | `import Darwin` is fine for `sqrtf`, `floorf`, `arc4random_uniform` |
| **Literal precision** | Copy float literals from C exactly — `0.70711219` not `Float(sqrt(2)/2)` |
| **C bugs replicated** | If C has a bug and it's documented as intentional (PLAN.md decisions log), port it exactly with a comment — never silently "fix" one mid-port |
| **D26 — oracle build flag** | `CXBolo` builds with `-ffp-contract=off` (`Package.swift`). Don't touch this; without it, `dot2f`/`mag2f`-family C oracle comparisons mismatch on ~26% of broad-range inputs due to FMA contraction, not a real Swift bug. |
| **D27 — shared per-tick state** | If a function you're porting takes what were N independent per-client replicas in C and collapses them into ONE shared field in the merged sim (e.g. `pills[i].counter`), do NOT port it as "call once per connected player, in index order" — a later bystander's call can silently overwrite an earlier target's result within the same tick (this is exactly what broke Wave 5.3c). Design it as a single per-tick election/pass over all players instead. Ask PLANNER if a wave you're starting has this shape and you're unsure. |
| **D28 — artifact/test maintenance** | No test or doc coverage shrinks without an explicit, stated replacement. Every completion report must state the before/after test count; call out any DECREASE explicitly with the reason. |
| **D29 — kPif vs Float.pi** | Use `kPif` for `dir * (π/8)`-style conversions, matching existing call sites — not `Float.pi`, despite what an older trap note in AGENT_NOTES.md may say. Bit-identical either way; this is the settled convention. |

## Wave status (full detail: `docs/PLAN.md`'s wave table)

| Wave | Content | Status |
|---|---|---|
| 1 – 4.1 | Vector/Rect/List/Buf/ErrChk, Terrain/Tiles, Images, BMAP | ✅ Complete |
| 5.0 – 5.1 | Physics constants, GameState model | ✅ Complete |
| 5.2a – 5.2b | tankMoveTick, tanklocallogic/enter() | ✅ Complete |
| 5.3a – 5.3c | shellTick, builderTick, pillTick (5.3c had a FAIL/fix cycle — see D27) | ✅ Complete |
| ~~5.4~~ | ~~tankcollision/buildercollision/testAlliance/findPill/findBase~~ | Retired — absorbed into 5.1/5.2a/5.3b |
| 5.5a – 5.5b | mine-chain/flood/droppills; explosionTick | ✅ Complete |
| **5.6** | **`spawn()`** | **🔶 Implemented/tested/reported — needs commit, then PARITY audit** |
| 5.7 | growtrees, pill cooldown, base replenish | ⬜ Queued next — needs explicit GO first |
| 5.8 | Docs/archive pass (PLAN.md/AGENT_NOTES.md → archive.md, project memory, this file) | ⬜ Queued, gates Wave 6 |
| 6 | Networking + Cocoa UI | ⬜ Not started — see PLAN.md's D25 (WinBolo reference: architecture OK to read, code is GPL v2, do not copy/derive) |

## Wave 5.7 trap list (for when GO is issued — read `docs/AGENT_NOTES.md` `WAVE 5.7` section in full first)

**growtrees C bug — must replicate exactly, not fix:**
- Outer pill/base guard checks the LAST-SAMPLED random cell `(x, y)` — NOT `(growx, growy)` (the
  tournament winner). Inner guard (inside the switch) correctly checks `(growx, growy)`. Both
  forms required, exactly as in C.
- Iterations per tick: `nplayers * 8` (integer arithmetic: `treesBestOf / (treesPlantRate *
  Int(ticksPerSec))` = `4200 / 500` = `8`). Watch for accidental `Float`/`Double` involvement
  changing which arithmetic path executes, even if the rounded answer matches.

**applyGrow terrain table:**
- Mined grass/rubble/crater/swamp/road → `.minedForest` (not plain `.forest`)
- Plain grass/rubble/crater/swamp/road → `.forest`
- All other terrain (wall, sea, existing forest, etc.): no-op

**Pill cooldown:** `pill.speed++` (reload interval grows toward 100) — **never** `pill.armour++`.
Armour is builder-repair-only; confusing the two silently gives pills auto-regenerating health,
with zero basis in the original.

**Base replenish:** `base.counter += nplayers` per tick, not `+= 1` — using `+= 1` makes the
replenish rate wrong by a factor of `nplayers`, a subtle scaling bug.

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
