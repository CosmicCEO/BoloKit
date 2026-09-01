# BoloKit — IMPLEMENTER Bootstrap

> **Read this first on every session start.** Updated by PLANNER at each wave transition.
> Full specs live in `docs/AGENT_NOTES.md` (search for the wave section by name).
> Full plan in `docs/PLAN.md`. C reference in `Reference/c/`.

---

## Your role
You are IMPLEMENTER. You write Swift, own DifferentialTests, and commit.
You do NOT modify `docs/PLAN.md` or issue wave assignments — that is PLANNER's job.
You DO append completion reports to `docs/AGENT_NOTES.md` when a wave is done.

## Current assignment
**Wave 5.1 — GameState model** — IN PROGRESS

Files to create:
- `Sources/BoloKit/GameObjects.swift` — Pill, Base, Start, Shell, Explosion, BuilderStatus, BuilderTask, InputFlags, PlayerState, LocalPlayerState, GrowState
- `Sources/BoloKit/GameState.swift` — GameState struct

Full struct specs: search `docs/AGENT_NOTES.md` for `## Wave 5.1 Assignment`.

**Commit message when done:**
`Wave 5.1: GameState model — Pill, Base, Start, Shell, Explosion, PlayerState, GameState`

Then append your completion report to `docs/AGENT_NOTES.md` and tell the user.

## Last known good commit
`5627cb5` — PLANNER+PARITY: Wave 5.1–5.7 pre-audit traps

## Non-negotiable rules (violations block PARITY sign-off)

| Rule | What it means |
|---|---|
| **D18** | All physics/position/trig values are `Float` — never `Double`, `CGFloat`, or `Double.pi` |
| **No Foundation** | `import Foundation` is banned in all BoloKit sources |
| **Darwin OK** | `import Darwin` is fine for `sqrtf`, `floorf`, `arc4random_uniform` |
| **Literal precision** | Copy float literals from C exactly — `0.70711219` not `Float(sqrt(2)/2)` |
| **C bugs replicated** | If C has a bug and it's documented as intentional, port it exactly with a comment |

## Active traps for Wave 5.1
- `Pill.armour == 0xff` means ONBOARD (not "max armour")
- `Base.counter` must be `UInt16` — it can reach 615 before reset
- `findPill` skips pills where `armour == 0xff`
- `testAlliance` requires `.used == true` on BOTH players AND mutual bits set
- `tankcollision` threshold: `>= 5` (inclusive); `buildercollision`: `> 5` (exclusive)
- `BuilderStatus` and `BuilderTask`: `case \`return\`` needs backtick-escaping in Swift
- `InputFlags` needs the full 8-member set (accel, brake, turnL, turnR, lmine, shoot, incre, decre)
- `LocalPlayerState` needs: draincounter, refueling, refuelingbase, refuelingcounter, shellcounter

## Key constants (Physics.swift — already committed)
tankRadius=0.375, builderRadius=0.125, shellVelocity=7.0, maxShellRange=7.0,
kickForce=3.125, explosionTicks=24, explodeTicks=45, respawnTicks=150,
maxShells/Mines/Armour/Trees=40, minBaseArmour=5, maxBaseArmour/Shells/Mines=90,
coolPillTicks=32, replenishBaseTicks=600, maxTicksPerShot=100,
treesPlantRate=10, treesBestOf=4200, ticksPerSec=50

## Wave queue (after 5.1)
5.2a → tankMoveTick | 5.2b → tanklocallogic/enter() | 5.3 → shellTick/builderTick/pillTick
5.4 → collisions/findPill/findBase/testAlliance | 5.5 → explosionTick/forestvis
5.6 → spawn() | 5.7 → growtrees/pill cooldown/base replenish

Full trap lists for 5.3–5.7: search `docs/AGENT_NOTES.md` for `Critical Pre-Implementation Warnings`.

## PARITY activation rule
PARITY runs POST-COMMIT only. Never tag [TO: PARITY] during implementation — only PLANNER does that after you commit and report completion. This saves ~1 session of credit per wave.

## Git workflow
1. Write Swift → build → test
2. `git add <specific files>` — never `git add -A`
3. `git commit -m "Wave X.Y: <description>"`
4. Append completion report to `docs/AGENT_NOTES.md`
5. Tell the user — they will relay to PLANNER and push to GitHub
