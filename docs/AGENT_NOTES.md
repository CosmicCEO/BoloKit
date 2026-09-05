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

### [PLANNER] 2026-09-05 — Milestone B/C/D pre-plan (D92), sized but not GO'd

**Type:** sizing/risk pre-plan, no coding GO issued
**Phase:** post-Wave-7, pre-Milestone-B/C/D
**Blocks:** nothing — this sizes and sequences, it does not authorize coding on any of B/C/D

Jerod asked for a pre-plan of Milestones B/C/D with help from Implementer/Parity subagents to
surface risks/gaps, dispatched directly under D91 (no yes/no gate needed). Two subagents ran in
parallel: an Implementer-lens pass (sizing + sub-wave splits, reading `Reference/c`'s actual
IBActions/IBOutlets and this project's existing `BoloNet`/`BoloKit` surface) and a Parity-lens pass
(independently verifying two claims from my own earlier read rather than taking them on faith, plus
hunting for fidelity gaps). Both came back clean on method — real file:line citations throughout,
no unverified assertions.

**D92 — closes Q18.** My own earlier read found `Reference/c` is a git submodule, not vendored
content, and that no copyrighted asset bytes exist anywhere in this project's own git history — the
Parity-lens agent independently re-derived all three sub-claims with fresh commands and confirmed
every one. Q18/D61's "git-history rewrite" premise doesn't hold: removing `Reference/c` at
Milestone D is a plain `git submodule deinit`, not a destructive rewrite. This meaningfully de-risks
Milestone D. D61's text corrected in place with a dated pointer, not rewritten; Q18 removed from
the open-questions table.

**Two corrections to my own earlier (unverified) framing, caught by the subagents rather than left
standing:**
1. Milestone C's key remap is not "expose already-shipped defaults for editing" — `InputKeymap.swift`
   is a hardcoded 7-case switch, only 6 of 14 reference bindings wired at all. C.1 must build the
   remappable model, not just a settings UI.
2. Milestone C's sound is not procedural synthesis — confirmed sample-based, 24 named `.aiff`
   effects via round-robin `NSSound` pools, zero DSP code in the reference. Smaller code footprint
   than I'd guessed, but needs licensed replacement assets (**Q28**, new) since the originals are
   Stuart Cheshire's copyrighted material.

**One new fidelity risk surfaced, inherited from D65 rather than new in kind:** the alliance system
and fog-of-war aren't independently scopable — `requestalliance()`/`leavealliance()` call
`increasevis()`/`decreasevis()` to merge shared vision, never modeled anywhere in this port
(already disclosed in `SessionLogic.swift`'s own header). Milestone C's alliance panel, built before
real fog-of-war exists, will functionally diverge from the reference (no vision reveal) — an
accepted, D65-consistent v1-shape gap the C.2 pre-brief should state explicitly. HUD status icons
were traced and confirmed independent of this — no equivalent risk there.

**One new gap surfaced for Milestone B:** the reference's `joinprogress()` dispatches 19 distinct
status codes (6 live progress states + 8 network-error cases) through one callback; `JoinClient.swift`
only models 6 protocol-rejection cases plus two framing catch-alls and has no progress-callback
mechanism at all. B.3's pre-brief will need new `JoinClient` surface area to replicate the
reference's live progress UI and per-failure messaging — not just app-side wiring.

**Sizing, relative to Wave 5 (10 sub-waves)/Wave 6 (11)/Wave 7 (4):** Milestone B (proposed B.0-B.4)
is closer to Wave 7's UI-wiring character — the hard networking work is done and tested in
`BoloNet`; the one new axis is this project's first `async`/`await` call across a SwiftUI/AppKit UI
boundary. Milestone C (proposed C.0-C.6) is the largest of the three by sub-wave count, but most
sub-waves are bind-existing-model-to-UI; C.1 (key remap) and C.3 (sound) are the two genuinely
harder pieces, with C.3 being the closest thing to a new engineering axis in either B or C (licensed
asset sourcing + new tick-loop hook plumbing, echoing Wave 7.0's asset-pipeline problem). Milestone D
is now the smallest and lowest-risk of the three post-D92, gated mostly on a non-engineering
dependency (Q29 — an Apple Developer Team ID for signing/notarization) rather than code complexity.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — D92 added; Q18 closed/removed;
Q28 (sound-asset licensing) and Q29 (signing Team ID) added; D61 and Wave 7's row corrected in
place; three new wave-table rows (Milestone B, C, D) added with proposed sub-wave splits, explicitly
**not GO'd**.

[TO: IMPLEMENTER] Nothing actionable yet — no coding GO issued on B, C, or D. When Jerod picks one
to GO, that milestone's first sub-wave gets a real pre-brief same as every prior wave; this entry is
sizing context, not a substitute for one.
[TO: PARITY] Nothing actionable yet, same reason. Your fidelity-risk findings (alliance/fog-of-war
non-independence, join-progress granularity gap) are recorded above for whichever sub-wave's
pre-brief eventually needs them.
