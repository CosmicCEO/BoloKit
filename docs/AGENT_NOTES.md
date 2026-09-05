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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, all of Wave 6 (6.0–6.3, the D39 fix, 6.6, 6.4a/6.4b/6.4c, 6.5a/6.5b, and the Wave 6 phase close-out), and all of Wave 7 (7.0–7.3, the full v1 vertical slice, D58–D89) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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
them):** `CLAUDE.md` (IMPLEMENTER), `docs/PARITY.md` (PARITY), `docs/PLANNER.md` (PLANNER). Wave
status and decisions live only in `docs/PLAN.md`; this file is the chronological log. Restructured
2026-09-02 from a single IMPLEMENTER-only `CLAUDE.md` into three role-specific files, specifically
to stop wave-status content from being duplicated (and going stale) across bootstrap files.

---

## Active Log (post-Wave-7)

> **Archived 2026-09-05:** Wave 7's entire v1 vertical slice (7.0 asset pipeline, 7.1 Xcode app
> target, 7.2 rendering, 7.3 input/tick loop — D58 through D89, including every pre-brief,
> completion report, and PARITY audit/re-audit in that span) has been compressed into
> `docs/notes/archive.md`. Full uncompressed entries preserved in git history per D28. The active
> log below now begins at the close of Wave 7's v1 vertical slice.

### [PLANNER] 2026-09-05 — D90 (Q27) and D91 (subagent-gating) ruled directly by Jerod

**Type:** two direct rulings, no code, no wave impact
**Phase:** post-Wave-7, pre-Milestone-B/C/D

**D90 — Q27 resolved: bundle identifier confirmed as `com.cosmicceo.Bolo-2026`**, aligning with
the GitHub org (`github.com/CosmicCEO/BoloKit`). Same shape as D58/D59: a direct ruling on a raised
question, adopted as final rather than provisional — no further action before Milestone D's
signing/notarization work. `docs/PLAN.md`'s Q-table and decisions log updated; the Wave 7.1 status
row's stale "still open" pointer corrected to point at D90.

**D91 — D85's standing yes/no subagent-dispatch gate is removed, superseded by this environment's**
**own built-in Auto Mode.** Same shape as D87 but permanent rather than scoped to one wave: PLANNER
no longer asks a yes/no question before spawning or handing work to a PARITY/Implementer/Admin
subagent — it acts directly, per Auto Mode's own standing guidance (proceed by default, redirect if
needed, still stop when genuinely blocked on a decision only Jerod can make). D85's and D87's text
both stand unmodified as the historical record; D91 supersedes the mechanism, not the reasoning.
This does not touch Jerod's decision authority over genuinely ambiguous/high-stakes product or
scope calls (architectural forks, Q-numbered questions) — only the routing checkpoint between role
handoffs is removed.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` (D90, D91, Q27 removed from open
questions, Wave 7.1 row correction).

[TO: IMPLEMENTER] No action needed — both rulings are process/product-identity, not code.
[TO: PARITY] No action needed.
