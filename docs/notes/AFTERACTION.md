# After-Action Notes (staging for a Final After-Action Review)

> **Purpose:** running collection of process-level observations about *how* the three-role
> (Implementer/Planner/Parity) workflow has actually operated, for synthesis into a final
> after-action review once the project reaches a natural close-out point (e.g. end of Phase 3,
> or project completion). Not a wave-status log — that's `docs/AGENT_NOTES.md`/`docs/PLAN.md`.
> Entries here are dated, never edited after the fact except to append a follow-up.

---

## 2026-09-03 — Confirmed loop patterns: planning vs. execution

Jerod's observation, recorded verbatim as the pattern that has held consistently across every
wave so far (Waves 1 through the current 6.x sequence):

**Planning loop** (pre-brief / scope stage, before a coding GO):
`Planner (GO) -> Implementer (Pre-Plan, Identify Gaps) -> Parity (Check for Gaps) -> Planner
(Incorporate Pre-Plan and Parity Feedback) -> Planner issues instructions`

**Execution loop** (coding stage, after the GO):
`Planner (GO) -> Implementer (Code, Identify Gaps) -> Parity (Adversarial Check, Gap Assessment,
Options and Recommendations) -> Planner (Incorporate Implementation and Parity Feedback) ->
Planner (issue, GO, other instructions, or escalate to Director)`

**Why this is worth recording now rather than only reconstructing it at close-out:** this is
exactly the shape D28's "log ambiguity as a question, don't resolve solo" discipline and the
D35/D37/D40-style "fix-before-next-wave-GO" rulings have converged on organically, wave over
wave, without ever being written down as a named process. It's held through pre-brief cycles
(6.1/6.2/6.3's batched review), fix/re-audit cycles (D35, D37, D39), and scope-gap discoveries
surfaced mid-wave and routed back through Planner rather than resolved solo (D36, D45). Worth
citing as evidence in the final review that the role-separation model (owns `PLAN.md`, roams
detailed planning, one adversarial pass) produced a repeatable loop rather than ad hoc handling
each time.

**Not yet observed / open for the final review to assess:** how often the loop's "escalate to
Director" branch actually fired (vs. Planner ruling directly), and whether loop latency
(wall-clock or session-count from GO to next GO) trended down as the pattern solidified across
waves — worth a pass over `docs/AGENT_NOTES.md`'s full history once Phase 3 closes.

## 2026-09-03 — Q24 (agent memory-logging policy): deferred to this review; draft recommendation parked

Jerod ruled Q24 (`docs/PLAN.md`) is deferred, not resolved now — to be settled as part of the
final after-action review rather than by a mid-project D-number ruling. The dedicated agent
mentioned in Q24's original entry has not been the source of this text; this is a Planner-drafted
recommendation, offered for that future review to accept, amend, or reject — **not adopted, not a
standing rule.**

**Draft recommendation (unadopted):**

Memory writes are justified only when a fact is durable across weeks/waves, isn't already the
natural payload of a commit that role makes anyway (decisions/wave-closes/audit findings stay
git-only), and saves a future session real cost reading the git doc directly. Decision-shaped
facts get a one-line index bump pointing at the git entry, never a restatement.

By role:
- **Implementer** writes memory only for repeatable environment/tooling gotchas, not project
  decisions.
- **Planner** updates memory's one-line indexes in the same sitting it commits the corresponding
  wave-close/decision in `PLAN.md` — never a fuller narrative.
- **Parity** essentially never writes memory directly; a reusable process pattern it surfaces
  goes through Planner into `roles-workflow.md`.
- **Deep-dive research** content stays in `docs/notes/*.md`; memory holds only the existing
  one-line pointer.
- **Admin/process rulings** (like this one, once actually ruled) get folded into
  `roles-workflow.md` as a compact operative rule, cross-referenced to its D-number — not before.

**When this review happens:** decide whether to adopt this recommendation as-is, amend it, or
replace it with whatever Jerod's dedicated Q24 agent produces in the meantime — then close Q24
in `docs/PLAN.md` with a real D-number ruling and fold the operative rule into
`roles-workflow.md` per the recommendation's own last bullet.
