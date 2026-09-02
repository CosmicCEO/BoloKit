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

---

## Index

| Archive | Content |
|---|---|
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

**PARITY activation rule:** PARITY runs **post-commit only**. PARITY is activated exclusively by a `[TO: PARITY]` tag in a PLANNER sign-off after IMPLEMENTER commits. PARITY does NOT run during planning phases.

**Role split (2026-09-02 reorg):** IMPLEMENTER owns detailed code-level planning (trap lists, C-source pre-briefs, implementation-approach calls) for its own waves. PLANNER is limited to high-level project management (sequencing, GOs, the decisions/open-questions log, cross-wave policy) and does not pre-author trap lists.

---

## Active Log (post-Wave-5)

### [PLANNER] 2026-09-02 — Wave 5.8 executed: docs/archive compression pass
**Type:** planning
**Phase:** 1 / Wave 5.8
**Blocks:** nothing — gates Wave 6

Assigned by Jerod. Scope per Q13/D28: compress Wave 5's chronological log into `docs/notes/archive.md`,
refresh project memory, reconcile the stale project-instructions config, keep `docs/PLAN.md` current.

- **`docs/notes/archive.md`** extended with a full "Wave 5" section (5.0 through 5.7, every
  sub-wave, commit hashes, key findings including the D26 fp-contract fix, the Wave 5.3c FAIL/fix
  cycle that produced D27, and the Wave 5.7 `Pill.counter`/`coolCounter` D27-class catch). Nothing
  lost — full uncompressed prior text is in git history at every commit through this point.
- **This file (`docs/AGENT_NOTES.md`)** trimmed to its format/index scaffolding plus a fresh
  active log starting here. This is the sanctioned exception to the append-only convention (see
  the note above it), matching how Waves 1–4 were handled before this session.
- **`docs/PLAN.md`** — wave table and decisions log were already current going into this pass
  (maintained incrementally through Wave 5.7); no further changes needed there beyond what's
  already recorded.
- **Project memory / CLAUDE.md / project-instructions reconciliation** — see the follow-up entry
  below for what was and wasn't changed, and why.

[TO: IMPLEMENTER] No action needed. `CLAUDE.md`'s pointers to `docs/AGENT_NOTES.md` wave sections
by name (e.g. "search WAVE 5.7") no longer resolve here — that content now lives in
`docs/notes/archive.md`'s Wave 5 section, or in git history for full detail. Nothing about your
current work is affected.
[TO: PARITY] No action needed — nothing here changes any already-audited wave's verdict.

### [PLANNER] 2026-09-02 — Wave 5.8 closed (Q13 → D30); one sub-item needs Jerod's action
**Type:** planning
**Phase:** 1 / Wave 5.8 → 6
**Blocks:** the project-instructions config sub-item only (not code-blocking)

Wave 5.8 executed and closed per D30 (see `docs/PLAN.md`'s decisions log — Q13 resolved). All
code-adjacent scope done: `docs/notes/archive.md` compressed, this file trimmed, `CLAUDE.md`
refreshed, project memory refreshed. Wave 5 (5.0-5.7) marked ✅ in `docs/PLAN.md`'s wave table.

**Outstanding: the project-instructions config itself.** This is a Cowork project setting, not a
repo file — no tool available lets PLANNER edit it directly. Drafted replacement text and handed
it to Jerod in this session's reply for him to paste into the project settings. Not blocking any
code work; flagging so it doesn't get lost.

[TO: IMPLEMENTER] No action. Wave 6 has no pre-brief yet — nothing to start.
[TO: PARITY] No action needed.
