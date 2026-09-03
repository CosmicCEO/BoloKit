# BoloKit — Wave 5.9 Scoped Agent Bootstrap

> **Read this first, before touching anything.** You are a narrow-scope, temporary IMPLEMENTER
> spawned for exactly one thing: **Wave 5.9 — wiring the mine-cascade injection points into their
> real trigger sites.** You are not the project's main IMPLEMENTER and do not inherit its general
> authority. Read `docs/PLAN.md`'s Wave 5.9 row and D22 (both indexed below) for the full text of
> what you're building — this file does not restate it, only the rules around how you work.
>
> Run `git log --oneline -5` and `git status` before doing anything — this file can lag reality,
> and per the note below you should be on your own branch/worktree, not `main`.

---

## Your role and its boundary

You do exactly one thing: port `enterTile`, `grabTile`, `tankMoveTick`'s dead-tumble path, and
`smallboom`/`superboom` so they actually call the existing `onMineExplosion`/`onSuperboomTerrain`/
`onDropPills` callbacks instead of leaving them as documented no-ops, with correct causer-player
attribution at each site. That is the entire scope. You do not:

- Touch anything under Wave 6 (session logic, preambles, `recvsr*`/`recvcl*` handlers, transport).
  A separate, concurrent Implementer session is actively working Wave 6.6 right now — assume any
  file it might plausibly own is off-limits to you (see the file list below).
- Choose to expand scope, "while I'm in here" fix something adjacent, or reinterpret the design.
  The design is already settled (Wave 5.5a shipped `explosionAt`/`superboomAt`/`chain`/`flood` in
  `MineChain.swift`; the callback signatures already exist). This wave is wiring, not invention.
- Declare the wave done. Write your completion report (format below) and stop — PLANNER closes
  waves, PARITY audits them, same as every other wave in this project.
- Resolve an ambiguous call yourself. Log it as a question in your completion report instead,
  exactly like every other role in this project does.

## Non-negotiable project-wide rules (full text: `docs/PLAN.md`'s decisions log — this is an index)

- **D18** — Float everywhere for position/physics/trig, never `Double`/`CGFloat`.
- **D24** — if you find a C oracle bug at one of your trigger sites, replicate it bug-for-bug and
  flag it as a question. Never silently "fix" it — that's a Phase 5 decision, not yours to make.
- **D26** — the `CXBolo` oracle builds with `-ffp-contract=off`. Don't touch `Package.swift`.
- **D27** — if any of your trigger sites involve shared per-tick state that multiple callers could
  touch in one tick, it's a single per-tick election, never a per-caller loop.
- **D28** — no test count shrinks without an explicit, stated replacement; state your before/after
  test count in the completion report.
- **D29** — use `kPif`, not `Float.pi`, for any `dir * (π/8)`-style conversion you touch.
- No `import Foundation` anywhere in `BoloKit`. `import Darwin` is fine for C-library primitives.
- Copy float literals from the C source exactly — bit-for-bit transcription, never a recomputed
  equivalent.

## Isolation rules — you are running alongside another live coding session

The main Implementer session is concurrently working Wave 6.6 on `main`. To avoid both git lock
races (already a known issue on this repo — see `docs/AGENT_NOTES.md`'s process notes) and any
chance of two agents editing the same file at once:

1. **Work on your own branch, checked out in your own git worktree — not the shared working
   copy.** From the main checkout: `git worktree add ../XBolo-wave5.9 -b wave-5.9-mine-cascade`.
   Do all your work in that separate directory. This gives you a completely separate filesystem
   checkout, not just a different branch name, so there is no way to collide with the other
   session's uncommitted state or trip its lock files.
2. **Do not touch, and do not `git pull`/rebase onto, `main` mid-wave.** Branch off once at the
   start, do your work, and stop — Jerod/PLANNER will merge when your wave is reviewed and
   audited, at which point any rebase is a deliberate, separate step, not something you do
   unprompted.
3. **Files you should expect to touch:** wherever `enterTile`, `grabTile`, `tankMoveTick`, and
   `smallboom`/`superboom` actually live (Wave 5.x territory — `MineChain.swift` and whichever of
   `TankMoveTick.swift`/`BuilderTick.swift`/`ShellTick.swift`/`PillTick.swift` own those call
   sites; confirm exact locations yourself by reading the code, don't assume from this list).
4. **Files that are off-limits — Wave 6.x territory, do not edit even if a callsite looks
   related:** `Sources/BoloNet/**` (all of it), `Sources/BoloKit/RunTick.swift`,
   `Sources/BoloKit/RecvSR.swift`, `Sources/BoloKit/SessionLogic.swift`,
   `Sources/BoloKit/RecvCL.swift` (new file, actively being written by the other session right
   now). If your wiring genuinely needs something from one of these, that's a scope question for
   PLANNER, not something to resolve by editing them yourself.
5. **Do not edit `docs/AGENT_NOTES.md` or `docs/PLAN.md` on your branch.** Both are being actively
   edited on `main` by the Planner/Parity/Implementer rotation and will conflict. Instead, write
   your pre-brief and completion report to a new standalone file on your branch:
   **`docs/notes/WAVE59_REPORT.md`**. PLANNER will fold it into `docs/AGENT_NOTES.md` and
   `docs/PLAN.md` at merge time, same content, just relocated.

## Two-stage process (same pattern every wave in this project follows)

1. **Pre-brief first.** Read the actual C source for every trigger site (`chain()`/`flood()`'s
   callers in the oracle, wherever `explosionat`/`superboomat` get invoked from tank movement,
   tile entry, and grab logic) before writing any Swift. Write a pre-brief into
   `docs/notes/WAVE59_REPORT.md` covering: exact `file:line` for each trigger site in both the C
   oracle and the existing Swift port, the causer-player value each site should pass, and any
   trap or ambiguity you find. Commit it, then tell Jerod it's ready for review — same as every
   other wave's pre-brief GO gate. Don't start coding before that review comes back.
2. **Then code.** Build, run the full test suite, add named regression tests per behavior wired
   (D28) — one per trigger site is a reasonable default. Commit to your branch with a clear
   message (`Wave 5.9: wire <site> to <callback>`). Append your completion report to the same
   `docs/notes/WAVE59_REPORT.md` file (don't overwrite the pre-brief section — add to it) and
   commit that too.

## Completion report format

Match the header style used everywhere else in this project:

```
### [WAVE 5.9 AGENT] <date> — <what this entry covers>

**Type:** pre-brief | coding
**Phase:** Wave 5.9
**Blocks:** <what this gates, or "nothing">

<body — same rigor as any other role's entries: exact file:line citations, what you found, what
you decided, what you're flagging as a question rather than deciding solo>

[TO: PLANNER] <what you need from Planner>
```

## Test oracle

Same `Reference/c/` submodule (pinned `51c3cbc`) every other wave uses, same `CXBolo` target
(`-ffp-contract=off`, D26). Nothing special for this wave — no new oracle test scaffolding is
expected, since the engine functions and their differential tests already shipped in Wave 5.5a;
you're wiring callers, not adding new oracle-testable surface.

## When you're done

Stop. Tell Jerod your branch name and that `docs/notes/WAVE59_REPORT.md`'s completion report is
ready. Do not merge to `main` yourself, do not declare the wave closed, do not start another wave.
PLANNER reviews the report, PARITY audits the diff against the C oracle (same hand-trace process
as every other wave), and only after a PARITY PASS does PLANNER fold the report into
`docs/AGENT_NOTES.md`/`docs/PLAN.md` and merge your branch.
