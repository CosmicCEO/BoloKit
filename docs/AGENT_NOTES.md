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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, Wave 6.0–6.3, the D39 fix, Wave 6.6, and Wave 6.4 (6.4a/6.4b/6.4c) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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

## Active Log (post-6.4c)

> **Archived 2026-09-03:** the D39 `GameState.pause`-split fix and its PARITY re-audit, Wave
> 6.6 (the `recvcl*` server handlers, D40's bug-for-bug ruling), and the full Wave 6.4 family —
> 6.4a (client transport, D42/D44, extended under D45/D46), 6.4b (host transport, D47/D48/D49),
> and 6.4c (live UDP wiring, D50/D51/D52/D53) — through Wave 6.4c's close, compressed into
> `docs/notes/archive.md`. Full uncompressed text preserved in git history per D28. The active
> log below continues from the Wave 6.5 pre-brief GO entry.

### [PLANNER] 2026-09-03 — Wave 6.4c closed (PARITY PASS, D53 fix confirmed); Wave 6.5 pre-brief GO issued

**Type:** planning — close-out + GO
**Phase:** Wave 6.4c close / Wave 6.5 open
**Blocks:** nothing — Wave 6.5 is available to start now

Reviewed PARITY's re-audit (`999dbde`) of the D53 fix (`534aa57`+`172a1d0`). Verdict: **PASS**.
The fix is the minimal correct change (`.normal` now calls `table.sendToAll`, `.abnormal` provably
untouched, re-read in full not just diffed); both named regression tests were independently
assessed as sound, including a specific trace of *why* the new negative-assertion
(`confirmNoDatagramArrives`) test pattern resolves correctly rather than merely happening to pass
— PARITY traced the counterfactual (what would happen if `.abnormal`'s self-exclusion were
accidentally removed) and confirmed the test would actually catch it, not just that it currently
passes. One generic, low-probability caveat noted for the record (a sufficiently starved scheduler
could in principle let a timeout-race negative test false-pass) — not specific to this test, not
blocking.

**Wave 6.4c is closed — PARITY PASS.** Full chain, six commits from pre-brief to close:
`091c364` → `bc34c95` (D51/D52) → `5fdb1bc`+`b3d6c8a` → `7ead213` → `5bab7c1` (D53 found) →
`534aa57`+`172a1d0` (fixed) → `999dbde` (confirmed). This is the second wave in the 6.4 family to
need a post-ship fix before closing (6.4a needed three rounds via D45/D46; 6.4c needed one via
D53) — both times the standard fix→test→re-audit sequence caught and closed the gap correctly
before anything shipped uncorrected.

**Wave 6.5 pre-brief GO issued.** D50's sequencing condition (6.4c closes before 6.5 starts) is
satisfied. Per Jerod's plan to archive the current Implementer session to conserve read
requirements, the next Implementer session picking this up should start from
`docs/notes/WAVE65_BOOTSTRAP.md` (prepared and committed ahead of time, `3a5c58f`) rather than
reconstructing context from this file's full history — that document already covers scope, wire-
format facts, the licensing constraint, decisions to carry forward, and what still needs real
research. This entry is the formal trigger that bootstrap document was gated on.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Wave 6.4c row marked complete (PARITY PASS); Wave 6 summary row updated; Wave
  6.5 row marked pre-brief GO'd, pointing to the bootstrap doc.

[TO: IMPLEMENTER] Wave 6.4c is closed — no action needed on it. **Wave 6.5 is GO'd for pre-brief.**
If you are a freshly-started session, read `docs/notes/WAVE65_BOOTSTRAP.md` first, then this
file's tail and `docs/PLAN.md`'s Wave 6.5 row and cited decisions, then begin your own research
against `Reference/c/` per the bootstrap's process section. Write your pre-brief before any coding.
[TO: PARITY] No action needed yet — nothing new shipped this entry. D53 is closed on your side too.

### [PLANNER] 2026-09-03 — Admin agent: archive pass through Wave 6.4c close

**Type:** admin/process — archive/compression pass
**Phase:** repo housekeeping (Admin agent)
**Blocks:** nothing

Admin agent compressed everything from the D39 `GameState.pause`-split fix through Wave 6.4c's
close (D39 fix, Wave 6.6, Wave 6.4a/6.4b/6.4c — decisions D39 through D53) into
`docs/notes/archive.md`, matching the existing per-wave summary format and level of detail
(commit hashes, key findings, decision cross-references). Full uncompressed text remains in git
history per D28. `AGENT_NOTES.md`'s active log now starts from the Wave 6.4c close/Wave 6.5
pre-brief GO entry (renamed header to `## Active Log (post-6.4c)`); the index table and archived
note updated to match. Committed at `92a6298`, explicit pathspec (`docs/AGENT_NOTES.md
docs/notes/archive.md` only — verified `git status --short` showed only these two files before
staging, no concurrent-session work present).

A stale `.git/index.lock` blocked the initial commit attempt; requested and received delete
permission for the repo root, removed the lock, reconfirmed a clean two-file diff before
committing.

No action needed from any of the three rotation roles.
