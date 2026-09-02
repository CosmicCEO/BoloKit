# BoloKit — IMPLEMENTER Bootstrap

> **Read this first on every session start — especially after a fresh start with no memory of
> prior sessions.** This file is your orientation; it is NOT the full spec. Full plan, decisions
> log, and open questions: `docs/PLAN.md`. Active chronological log: `docs/AGENT_NOTES.md`.
> Compressed history for completed waves (1 through 5.7): `docs/notes/archive.md` — full
> uncompressed detail for any of it is in git history. C reference: `Reference/c/`. **Wave 6 wire
> protocol map (opcodes, `CLUpdate` layout, all three encodings, join handshake, oracle bug list):
> `docs/notes/DEEPDIVE1.md`** — read that before writing the 6.0 pre-brief; don't re-derive it.
> Updated by PLANNER at each wave transition — this update: 2026-09-02 (Wave 6 unblocked, D31-D34;
> added the planning-only-entries reminder below after a pre-brief went uncommitted).

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
**Wave 5 (5.0 through 5.7) is fully complete and PARITY-passed. Wave 5.8 (docs/archive pass) is
closed.** **Wave 6 (networking only — UI was split out to its own phase, gated on Phase 2 art
landing first) has no pre-brief yet, but is unblocked and ready for one.** `docs/PLAN.md`'s
decisions log D31–D34 settled everything that was gating it:

- **D31** — port the wire format byte-exact from the C oracle; rebuild the transport mechanism on
  Network.framework + async/await, not a POSIX/`select`/pthread transliteration.
- **D32** — the 6.0–6.5 sub-wave split is confirmed (wire codec → tick orchestrator → `recvsr*`
  broadcast handlers → server session logic → transport/handshake → tracker/NAT).
- **D33/D34** — the GPL-flexibility exploration (Q19/Q20) is closed. **D25 stands as originally
  written and is not loosened**: WinBolo's architecture may be read for reference, its code (GPL
  v2) may never be copied, transliterated, or closely derived from. Do not read or reference
  WinBolo source while writing Wave 6 — the wire format comes from the oracle, full stop.

Your starting point for the 6.0 pre-brief is `docs/notes/DEEPDIVE1.md`'s protocol map (opcodes,
`CLUpdate` layout, the three position/direction encodings, the join handshake, and eight cataloged
oracle bugs) — it's already at spec level; write your pre-brief against it rather than re-reading
`client.c`/`server.c` from scratch.

Last commits: `221ba97` (Wave 5.7, last code commit) → docs-only commits through `0ce198a`
(Q16/17/19/20 ruling) on top. Run `git log --oneline -5` and `git status` to confirm current HEAD
before doing anything — this file can lag reality between updates.

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
| 6 | Networking (UI split into its own later phase, gated on Phase 2 art) | ⬜ Not started — unblocked (D31-D34), no pre-brief written yet; write one against `docs/notes/DEEPDIVE1.md` before any GO |

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
