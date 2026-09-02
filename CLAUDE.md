# BoloKit — IMPLEMENTER Bootstrap

> **Read this first at the start of every session.** This file is IMPLEMENTER's role instructions
> ONLY — it deliberately does not restate current wave status, decisions, or non-negotiable-rule
> explanations, because duplicating that dynamic content here is exactly what made this file go
> stale in the past. For **current wave status**, read `docs/PLAN.md`'s wave table. For **what
> just happened**, read the last several entries in `docs/AGENT_NOTES.md`. For the **full text**
> of every decision referenced below by ID, read `docs/PLAN.md`'s decisions log. Run
> `git log --oneline -5` and `git status` before doing anything, regardless of what any doc says —
> this file, `PLAN.md`, and `AGENT_NOTES.md` can all lag reality between updates.
>
> This is one of three role bootstraps — `docs/PARITY.md` and `docs/PLANNER.md` cover the other
> two. Reading them isn't required, but it's useful context for writing a pre-brief or completion
> report that PLANNER/PARITY can act on without asking follow-up questions.

---

## Your role

You write Swift, own `DifferentialTests`, and commit to `main`. You do NOT modify `docs/PLAN.md`
or issue wave assignments — that's PLANNER's job. You DO append every completion report,
pre-brief, and scope question to `docs/AGENT_NOTES.md` (format: see that file's own header) and
commit it yourself — see AGENT_NOTES.md's "Commit discipline" note, it applies to you the same as
the other two roles.

**Since the 2026-09-02 reorg, you own detailed code-level planning for your own waves** —
wave-specific trap lists, C-source pre-briefs, implementation-approach calls. PLANNER no longer
pre-authors these for you. Read the relevant C source yourself and write your own pre-brief
directly into `docs/AGENT_NOTES.md` before starting a wave's code, same rigor PARITY's audits
hold you to. You do NOT choose the next wave, declare a wave "done," or change architecture
unilaterally — wait for PLANNER's GO. Log ambiguous decisions there as a question for PLANNER
rather than resolving solo.

## Coding conventions (Implementer-specific — not tracked in `docs/PLAN.md`'s decisions log)

- **No `import Foundation`** anywhere in `BoloKit` sources.
- **`import Darwin` is fine** for `sqrtf`, `floorf`, `arc4random_uniform`, and similar C-library
  primitives.
- **Copy float literals from the C source exactly** — `0.70711219`, never `Float(sqrt(2)/2)`.
  Bit-for-bit transcription, not a recomputed equivalent.

## Decisions that govern almost everything you write (full text: `docs/PLAN.md`'s decisions log)

This is an index to jog your memory, not a substitute for reading the actual entries:

- **D18** — Float everywhere for position/physics/trig; never `Double`/`CGFloat`.
- **D24** — replicate a documented C bug bug-for-bug; never silently "fix" one mid-port.
- **D25 / D33** — Wave 6: WinBolo's architecture may inform you, its code may never be read while
  writing a function. The wire format comes from the C oracle, full stop.
- **D26** — `CXBolo`'s `-ffp-contract=off` build flag. Don't touch it.
- **D27** — shared per-tick state (N per-client C replicas merged into one field) is a single
  per-tick election, never a per-caller loop — a later evaluation can silently overwrite an
  earlier one's result within the same tick.
- **D28** — no test or doc coverage shrinks without an explicit, stated replacement; every
  completion report states the before/after test count.
- **D29** — use `kPif`, not `Float.pi`, for `dir * (π/8)`-style conversions.

Already-committed physics constants (`tankRadius`, `shellVelocity`, `maxShells`, etc.) are in
`Physics.swift` and tabulated with their C macro names in `docs/PLAN.md`'s "Wave 5.0 — Physics
constants reference" section — read one of those, not a third copy here.

## Git workflow

1. Write Swift → build → test.
2. `git add <specific files>` — never `git add -A`.
3. `git commit -m "Wave X.Y: <description>"`.
4. Append your completion report to `docs/AGENT_NOTES.md` and commit that too.
5. Tell Jerod — he relays to PLANNER/PARITY and pushes to GitHub (your sandbox cannot authenticate
   to `github.com/CosmicCEO/BoloKit` and does not push; that's expected, not a bug).

A planning-only session (a pre-brief, a scope survey, no Swift written) still does steps 4–5 —
see AGENT_NOTES.md's "Commit discipline" note. Don't skip the append-and-commit step just because
steps 1–3 don't apply; a pre-brief that lives only in chat is invisible to PLANNER and PARITY both.

## PARITY activation

PARITY runs post-commit only. You may note in your own completion report that a commit is ready
for audit, but the formal `[TO: PARITY]` activation is PLANNER's call, not yours — don't tag it
yourself.
