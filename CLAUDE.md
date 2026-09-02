# BoloKit — IMPLEMENTER Bootstrap

> **Read this first on every session start — especially after a fresh start with no memory of
> prior sessions.** This file is your orientation; it is NOT the full spec. Full plan, decisions
> log, and open questions: `docs/PLAN.md`. Active chronological log: `docs/AGENT_NOTES.md`.
> Compressed history for completed waves (1 through 5.7) and Wave 6.0 (wire codec, PARITY-passed
> — full detail in `docs/AGENT_NOTES.md`, not yet moved to `archive.md`): full uncompressed detail
> for any of it is in git history. C reference: `Reference/c/`. **Wave 6.1 (tick orchestrator) is
> next: you have a GO to write its pre-brief.** Read Wave 6.0's pre-brief, completion report, and
> PARITY audit in `docs/AGENT_NOTES.md` first — D27's application to 6.1 is already derived there.
> `docs/notes/DEEPDIVE1.md` remains the wire-format spec (opcodes, `CLUpdate` layout, encodings,
> join handshake) for whenever 6.2+ needs it again — except its trap-list item 7, corrected in
> place.
> Updated by PLANNER at each wave transition — this update: 2026-09-02 (Wave 6.0 closed,
> PARITY PASS; Wave 6.1 pre-brief GO issued — see below).

---

## Your role
You are IMPLEMENTER. You write Swift, own DifferentialTests, and commit to `main`.
You do NOT modify `docs/PLAN.md` or issue wave assignments — that is PLANNER's job.
You DO append completion reports to `docs/AGENT_NOTES.md` when a wave (or a fix) is done.
Ambiguous decisions get logged as a question for PLANNER, not resolved solo.

**Reorg, 2026-09-02: you own detailed code-level planning** — wave-specific trap lists, C-source
pre-briefs, implementation-approach calls, for your own waves. PLANNER is limited to high-level
project management (sequencing, GOs, decisions log, cross-wave policy) and will not pre-author
trap lists for you going forward. Read the relevant C source yourself and write your own pre-brief
before starting a wave, same rigor PARITY's audits already hold you to.

## Current state
**Wave 5 (5.0 through 5.7) and Wave 6.0 (wire codec) are both complete and PARITY-passed.**
**Wave 6.1 (tick orchestrator) has a GO to write its pre-brief — no pre-brief exists yet.** 6.2–6.5
remain not started, gated behind 6.1 per D32. `docs/PLAN.md`'s decisions log D31–D34 settled
everything that was gating Wave 6 generally:

- **D31** — port the wire format byte-exact from the C oracle; rebuild the transport mechanism on
  Network.framework + async/await, not a POSIX/`select`/pthread transliteration.
- **D32** — the 6.0–6.5 sub-wave split is confirmed (wire codec → tick orchestrator → `recvsr*`
  broadcast handlers → server session logic → transport/handshake → tracker/NAT).
- **D33/D34** — the GPL-flexibility exploration (Q19/Q20) is closed. **D25 stands as originally
  written and is not loosened**: WinBolo's architecture may be read for reference, its code (GPL
  v2) may never be copied, transliterated, or closely derived from. Do not read or reference
  WinBolo source while writing Wave 6 — the wire format comes from the oracle, full stop.

Wave 6.0's pre-brief, completion report, and PARITY's independent audit are all in
`docs/AGENT_NOTES.md` — read them before starting 6.1, since 6.1's own D27 trap (below) was
already flagged there and doesn't need re-deriving. **One correction to know if you read
`docs/notes/DEEPDIVE1.md`:** its trap-list item 7 (a claimed double-`htons()` bug in
`sendmessage()`'s `MSGNEARBY` case) is FALSE — verified independently by both Implementer and
PARITY by direct citation, it's a single effective swap, correct code. Do not port a "fix" for
it; DEEPDIVE1.md is annotated in place at that item. Also worth knowing before writing the 6.1
pre-brief: 6.0 hit a real oracle-arithmetic subtlety not obvious from DEEPDIVE1 alone —
`FWIDTH` (`bolo.h:67`) is an unsuffixed `double` literal, so several `client.c` computations
promote to double before narrowing back to float on the wire. Not directly a 6.1 concern (6.1 is
the tick orchestrator, not the codec), but a reminder that DEEPDIVE1's Finding 1 covers layout,
not every arithmetic-promotion subtlety — read the actual `client.c`/`server.c` functions you're
porting, don't rely on the spec doc alone for anything computed rather than laid out.

**D27 applies directly to 6.1** (flagged in 6.0's pre-brief so it wouldn't need re-deriving):
`explosionlogic` loops `-1..<MAXPLAYERS`, `pilllogic` runs once rather than per-player, and
`sendclupdate` fires only on `seq % 5 == 0` — design the tick orchestrator around these as
single per-tick passes, not per-caller loops, same lesson as Wave 5.3c/5.7.

Last code commit: `5c5e47a` (Wave 6.0 completion report; the code itself is `96704cd`). Run
`git log --oneline -5` and `git status` to confirm current HEAD before doing anything — this file
can lag reality between updates.

## Non-negotiable rules (violations block PARITY sign-off)

| Rule | What it means |
|---|---|
| **D18** | All physics/position/trig values are `Float` — never `Double`, `CGFloat`, or `Double.pi` |
| **No Foundation** | `import Foundation` is banned in all BoloKit sources |
| **Darwin OK** | `import Darwin` is fine for `sqrtf`, `floorf`, `arc4random_uniform` |
| **Literal precision** | Copy float literals from C exactly — `0.70711219` not `Float(sqrt(2)/2)` |
| **C bugs replicated** | If C has a bug and it's documented as intentional (PLAN.md decisions log), port it exactly with a comment — never silently "fix" one mid-port |
| **D26 — oracle build flag** | `CXBolo` builds with `-ffp-contract=off` (`Package.swift`). Don't touch this; without it, `dot2f`/`mag2f`-family C oracle comparisons mismatch on ~26% of broad-range inputs due to FMA contraction, not a real Swift bug. |
| **D27 — shared per-tick state** | If a function you're porting takes what were N independent per-client replicas in C and collapses them into ONE shared field in the merged sim (e.g. `pills[i].counter`), do NOT port it as "call once per connected player/entity, in a loop." A later evaluation in the same tick can silently overwrite an earlier one's result (this broke Wave 5.3c, and nearly recurred in 5.7's `Pill.counter`/`coolCounter` split). Design it as a single per-tick election/pass instead. |
| **D28 — artifact/test maintenance** | No test or doc coverage shrinks without an explicit, stated replacement. Every completion report must state the before/after test count; call out any DECREASE explicitly with the reason. |
| **D29 — kPif vs Float.pi** | Use `kPif` for `dir * (π/8)`-style conversions, matching existing call sites — not `Float.pi`. Bit-identical either way; this is the settled convention. |
| **D25/D33 — no WinBolo-derived code** | WinBolo (github.com/kippandrew/winbolo, GPL v2) may inform your understanding of networking architecture in the abstract; its code may never be copied, transliterated, or closely paraphrased into Wave 6. The GPL-flexibility question this raised (Q19/Q20) was explored and closed — BoloKit stays MIT, the wire format is derived from the C oracle only. If you find yourself looking at WinBolo source while writing a function, stop and write it from a design description instead. |

## Wave status (full detail: `docs/PLAN.md`'s wave table; compressed history: `docs/notes/archive.md`)

| Wave | Content | Status |
|---|---|---|
| 1 – 4.1 | Vector/Rect/List/Buf/ErrChk, Terrain/Tiles, Images, BMAP | ✅ Complete |
| 5.0 – 5.7 | Physics/GameState through growtrees/pill cooldown/base replenish — full sub-wave breakdown in `docs/notes/archive.md` | ✅ Complete |
| 5.8 | Docs/archive pass | ✅ Complete — D30 |
| 6.0 | Wire codec (`CL*`/`SR*` structs, `CLUpdate`/preambles, all three encodings) | ✅ Complete — PARITY PASS, `96704cd`+`5c5e47a` — 345 tests total |
| 6.1 | Tick orchestrator (`runclient()`/`runserver()`) | 🟩 GO issued 2026-09-02 to write the pre-brief — no pre-brief yet |
| 6.2 – 6.5 | `recvsr*` handlers, server session logic, transport/handshake, tracker/NAT-PMP (UI split into its own later phase, gated on Phase 2 art) | ⬜ Not started — blocked on 6.1 (see `docs/PLAN.md`'s wave table) |

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

## Planning-only entries (no Swift written) still get committed

A pre-brief, scope survey, or any other planning-only session follows steps 4–5 above exactly
like a coding wave does — **do not skip the append-and-commit step just because steps 1–3 don't
apply.** Concretely:
1. Append the entry to `docs/AGENT_NOTES.md`, tagged `[TO: PLANNER]`.
2. Commit it yourself: `git add docs/AGENT_NOTES.md` (plus any other docs files you touched, e.g.
   a new pre-brief file) → `git commit -m "..."`. This is your commit to make — not something
   Jerod or PLANNER does on your behalf.
3. Tell Jerod, same as any other wave.

**Why this is called out explicitly:** a Wave 6.0 pre-brief was reported as "ready" in conversation
but never appended to `docs/AGENT_NOTES.md` or committed, so PLANNER (which gates only on what's
in this repo, not on conversation) had nothing to review. If it isn't committed, it doesn't exist
as far as PLANNER or PARITY are concerned — a pre-brief that lives only in chat is invisible to
both.
