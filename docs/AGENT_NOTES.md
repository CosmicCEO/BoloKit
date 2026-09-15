# Agent Notes — Shared Running Log

> **Purpose:** Durable scratchpad shared between Claude Xcode API (implementer) and Claude.ai (reviewer and planner).
> High-level decisions belong in `PLAN.md`.
> This file is for implementation-level continuity: what was tried, what broke, what was resolved, and flags between agents.
>
> **Convention:** Always append — never edit or rewrite earlier entries, EXCEPT during an explicit
> periodic archive/compression pass (a Wave 5.8-style docs pass), which is the sanctioned exception
> to this rule. Pull before reading.

---

## Format

Each entry uses this block:

```
### [AGENT] YYYY-MM-DD — short title

Body — a few lines. Be concrete. No filler.

> **→ Parity:** action item or handoff note (omit if not applicable)
> **→ Planner:** item for review or question (omit if not applicable)
> **→ Implementer:** instructions for the xcode agent, coding environment (omit if not applicable)
```

Types:
- **[PLANNER]** — wave assignments, sign-offs, architectural decisions
- **[IMPLEMENTER]** — coding, completion reports, build results, deviations from spec
- **[PARITY]** — audit findings, behavioral verification, sign-offs
- **[ADMIN]** — repository housekeeping, archive passes, documentation and process coordination

---

## Index

| Archive | Content |
|---|---|
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, all of Wave 6, all of Wave 7 (the full v1 vertical slice, D58–D89), Milestone B's D90–D93 through B.0–B.7, D109 through Milestone C's full close (B.8, B.9/B.10 deferrals, C.0/C.3/C.5), the D123/D124 git-worktree-race ruling, D125 through D149 (path-to-v1.0, v1.0.0 ship, 1.1 backlog first wave), **and now also D150 through D165**: visual-parity sweep (D150), scope reduction (D151), crosshair & base glyph (D152), sprite-flip bug (D153), Cheshire Bolo 0.9 visuals & Event Log Waves 1–3 (D154), player alliance fix (D155), mine/shell-touch detonation (D156), build-tool chrome & scroll-keys fix (D157), Milestone D.0 zoom/scroll (D160–D162), `v1.1.0-beta.1` ship, and D165 light-track cleanup — up to and including D165. Compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

**PARITY activation rule:** PARITY runs **post-commit only**. PARITY is activated exclusively by a `[TO: PARITY]` tag in a PLANNER sign-off after IMPLEMENTER commits. PARITY does NOT run during planning phases.

**Role split (2026-09-02 reorg):** IMPLEMENTER owns detailed code-level planning (trap lists, C-source pre-briefs, implementation-approach calls) for its own waves. PLANNER is limited to high-level project management (sequencing, GOs, the decisions/open-questions log, cross-wave policy) and does not pre-author trap lists.

**Commit discipline (all three roles):** an entry only exists once it is appended here AND
committed — never leave it sitting in a chat session as "done" or "ready." This has already
bitten the project twice: a Wave 6.0 pre-brief reported "ready" in conversation with nothing
committed, and a Wave 6.0 PARITY audit relayed by Jerod with nothing committed either. Whoever
writes an entry commits it themselves, in the same sitting — `git add docs/AGENT_NOTES.md` (plus
any other file touched) → `git commit`. This applies identically to IMPLEMENTER, PLANNER, and
PARITY; none of the three can push to `github.com/CosmicCEO/BoloKit` (Jerod pushes after
relaying), but all three can and must commit locally. If you're about to say something is done and
you haven't run `git commit` yet, it isn't done yet.

**Role bootstraps (read at session start, each is instructions-only — no wave status lives in
them):** `docs/IMPLEMENTER.md` (IMPLEMENTER), `docs/PARITY.md` (PARITY), `CLAUDE.md` / `docs/PLANNER.md` (PLANNER), `docs/ADMIN.md` (ADMIN). Wave
status and decisions live only in `docs/PLAN.md`; this file is the chronological log.

---

## Active Log (post-D165)

### [ADMIN] 2026-09-15 — Housekeeping, doc pointer reconciliation, and D150–D165 archive pass

Executed project housekeeping pass following `v1.1.0-beta.1` release:
1. **Doc pointers reconciled**: Pointed partner bootstraps to `docs/IMPLEMENTER.md` and `CLAUDE.md` / `docs/PLANNER.md` across `CLAUDE.md`, `docs/IMPLEMENTER.md`, `docs/ADMIN.md`, and `docs/PLAN.md`. Added symlink `docs/PLANNER.md -> ../CLAUDE.md`.
2. **Compiler warnings resolved**: Handled unused immutable variable in `CLUpdateCodec.swift:86` and added `@retroactive` to `BuilderCommandKind: CaseIterable` in `GameHUDViews.swift:204`.
3. **README test count synced**: Updated app-target test count from 39 to 40 (`Bolo 2026Tests`).
4. **Archive pass completed**: Compressed D150 through D165 (~4,200 lines) into `docs/notes/archive.md`. Active log trimmed and reset post-D165.

Tests: 774 SPM (554 BoloKitTests + 220 DifferentialTests) + 40 Xcode UI-hosting tests green.

[TO: PLANNER]
