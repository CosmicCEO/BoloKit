# BoloKit — Agent Notes Archive: Waves 1–4

> Compressed summaries of completed waves. Full history in git.
> Active notes: `../AGENT_NOTES.md`.

---

## Waves 1–2 (2026-08-31)
- **Wave 1** (b729781): Vector, Rect, List, Buf, ErrChk ported to Swift. Differential tests green. Minor code-review findings resolved (ErrChk stub, List generic bounds). ✅
- **Wave 2** (9695275): Terrain enum, Tiles enum, TileGrid, 8 predicates. All differential tests green. PARITY signed off. ✅
- **Q11 resolved**: Project renamed BoloKit / Bolo 2026. README and Package.swift updated.
- **GitHub remote**: Configured and pushed.

## Wave 3 / 3.1 (2026-08-31)
- **Wave 3** (db747b2): Image constants, mapimage autotiling. Differential tests green. One design divergence (mapimage centering vs origin) noted and approved. ✅
- **Wave 3.1** (24d7ae0): Physics constants (D18 Float), TerrainGrid, terrain speed functions (terrainMaxSpeed, terrainMaxTurnSpeed, terrainBuilderSpeed). PARITY Findings 1+2 resolved (6580e2a, 20e156d). Finding 3 (stale `import Darwin` in Physics.swift + Terrain.swift) deferred. ✅
- **Behavioral benchmark**: XBolo must match Bolo 0.99.7, NOT WinBolo. Key divergences: wall friction, tank deceleration, boat-to-land transition, mine self-damage, builder retrieval, pillbox range.

## Wave 4 / 4.1 (2026-08-31)
- **Wave 4** (8044fb0): terrainToTile, defaultTerrain/Tile, BMAP format structs. 35 tests green. PARITY Finding A (mapDefault factory) approved. ✅
- **Wave 4.1** (7298d2c): BMAP RLE codec — readRun/writeRun + nibble helpers. Bit-identical round-trip against .bmap oracle. Two safe deviations: x<256 guard (prevents C memory corruption), y=255/col=256 clamp (C UB). ✅

## Three-agent team established (2026-08-31)
- **IMPLEMENTER** (Xcode Claude) — writes Swift, owns DifferentialTests, commits
- **PLANNER** (Claude Cowork) — owns PLAN.md + AGENT_NOTES.md, issues wave GOs
- **PARITY** (Claude adversarial) — post-commit audit only; activated by [TO: PARITY] tag

---

## Wave 5 (2026-08-31 – 2026-09-02)

Full pre-briefs, completion reports, and PARITY audits for every sub-wave below lived in
`docs/AGENT_NOTES.md` prior to this Wave 5.8 compression pass; full text is preserved in git
history (every commit through this point included the uncompressed file). Permanent decision IDs
(D18, D22–D29) and the Wave 5 status table live in `docs/PLAN.md`, the canonical source — not
duplicated here.

- **Wave 5.0** (`e2636fb`): Physics constants, `roundDir`, `maxSpeed`/`maxTurnSpeed` w/ pill/base
  overrides. PARITY PASS; Finding 4 initially flagged then independently retracted by IMPLEMENTER
  with empirical bit-pattern evidence (`c4d501b`) — PARITY corroborated. ✅
- **Wave 5.1** (`a3126c6`): `GameState` model — Pill/Base/Start/Shell/Explosion/BuilderStatus/
  BuilderTask/InputFlags/PlayerState/LocalPlayerState/GrowState, `findPill`/`findBase`/
  `testAlliance`. No C oracle (pure data model). IMPLEMENTER's pre-code source pass surfaced two
  real C bugs for later waves (dead-tank terrain-enum mismatch; a tautological build-cost guard,
  later D24) plus generalization notes for 5.4/5.5. ✅
- **Wave 5.2a** (`a752a77`): `tankMoveTick` — tank physics tick, `dir2vec`/`vec2dir`,
  `isShore`/`tankCollision`. Replicated the dead-tank enum-mismatch bug exactly; caught and fixed a
  second real double-precision bug in `kickspeed` decay. PARITY PASS, both holding items closed. ✅
- **Wave 5.2b** (`71411b9`/`4c6ad1b`): `tanklocallogic`/`enter()` — local-player input, mine/boat/
  refuel/fire. Surfaced Q12 (mine-chain/flood + pill-scatter subsystem, → D22 split into 5.5a/5.5b).
  Two structural findings (ally-handoff branch unreachable; own-base re-entry hits hostile-takeover)
  both independently confirmed correct by PARITY against `testalliance`/`recvclgrabtile`. ✅
- **Wave 5.3a** (`ff807ff`): `shellTick`/`shellCollisionTest`/`applyDamage`/`killTank` (killTank
  pulled forward from 5.6 per D23). PARITY PASS; one MEDIUM open item on `explosions`-list
  attribution deferred to Wave 6 (Q14). ✅
- **Wave 5.3b** (`27a76d3`): `builderTick` — builderlogic + server-side build/repair/mine/
  grab-trees handlers merged into the unified tick; D24 tautology replicated verbatim. **Found and
  fixed a project-wide C-oracle build bug (D26):** `-ffp-contract=off` added to `CXBolo`, since
  default FMA contraction made `dot2f`/`mag2f` mismatch the (mis-)compiled C oracle on ~15–26% of
  broad-range inputs — a compiler code-gen gap in the oracle, not a Swift bug. PARITY independently
  reproduced the root cause at the assembly level. Pure fix — no prior test's expected values
  changed. ✅
- **Wave 5.3c** (`d2dfc71`, fixed at `03d56b3`): `pillTick`/`forestVis` (forestVis moved here from
  the old 5.5b per D23). **PARITY FAIL → fix → PASS cycle, the origin of D27:** the initial
  per-connected-player-loop design mutated one shared `pills[i].counter`, so a bystander processed
  after the real target in the same tick silently erased its progress. Rewritten as a single
  per-tick election (argmin over eligible candidates, ties survive and all fire) plus a
  freeze-vs-reset distinction. Re-audit verified the election model against C's pairwise logic by
  hand-tracing both directions, not just re-reading it as plausible. Also caught a double-precision
  `MAX`-nesting cascade in `forestVis` (~48% mismatch if computed naively in `Float`) via oracle
  fuzzing, and a `fabsf`-narrows-before-abs precision quirk in shell lead-targeting, both replicated
  per C's source exactly. **D27 (shared per-tick state → single-pass election, not a per-caller
  loop) is the standing lesson from this wave** — re-applied successfully in Wave 5.7. ✅
- **Wave 5.4** — retired as a standalone wave per D23; its scope (`tankCollision`,
  `testAlliance`/`findPill`/`findBase`, `buildercollision`) was fully absorbed into 5.1, 5.2a, and
  5.3b as each was implemented.
- **Wave 5.5a** (`d99815e`): `explosionAt`/`superboomAt`/`chain`/`flood` (mine-detonation cascade),
  `droppills`. D27 checked against the finished code and held throughout — `chain()`/`flood()` are
  structurally global with no per-player-loop shape to begin with. Caught a real crash-risk
  `UInt32`-wraparound bug in the ring-buffer write-slot index before shipping (C's `uint32_t`
  underflow at `ticks==0` vs. Swift's `UInt64`), independently confirmed via a compiled C
  cross-check. Also confirmed a genuine, non-obvious asymmetry: smallboom can self-damage its
  causer, superboom cannot (added to PLAN.md's Wave 5 benchmarks table). PARITY PASS, no findings. ✅
- **Wave 5.5b** (`08c6e85`): `explosionTick` — drains the explosion *particle* lists (not the
  chain-reaction ring buffers, which 5.5a drains — PLAN.md's D22 text originally mis-described this
  and was corrected during this wave's audit). Smallest wave in the sequence; D27 doesn't apply
  (each of C's per-`i`-including-`-1` calls touches a disjoint list). PARITY PASS, no code
  findings. ✅
- **Wave 5.6** (`a3f9540`): `spawn()` — two-pass weighted start selection (Pass 2 drops pill
  penalties only), `arc4random_uniform` divergence documented, unconditional `boat=true`,
  domination-type (`open`/`tournament`/`strict`) resource-init switch (new scope, C's only
  finished game mode). **D29:** kept `kPif` over an older trap note's `Float.pi` suggestion —
  bit-identical under D18, matches every other shipped call site doing the same conversion. One
  LOW doc-only PARITY finding (dangling `arc4random_uniform` rationale cross-reference in
  `Spawn.swift`) routed to IMPLEMENTER, non-blocking. PARITY PASS. ✅
- **Wave 5.7** (`221ba97`): `growTrees`/`treeScore`/`baseScore`/`adjacentScore`, `coolPills`,
  `replenishBases`. Replicated the `growtrees` outer/inner-guard coordinate bug exactly (outer
  checks last-sampled `(x,y)`, inner checks tournament winner `(growX,growY)`). **A second genuine
  D27-class catch:** C's client/server split gives `client.pills[i].counter` (fire cadence) and
  `server.pills[i].counter` (cooldown) separate storage under one shared struct name — merging
  client+server into one `GameState` would have silently collided the two roles onto Wave 5.3c's
  existing `counter` field. Fixed by adding a dedicated `Pill.coolCounter`, confirmed genuine (not
  redundant) by PARITY against `bolo.h`/`client.h`/`server.h`. PARITY PASS on both this wave and
  the previously-outstanding Wave 5.6 audit (Jerod issued Wave 5.7's GO via direct override before
  5.6 was audited — both later passed, no issue resulted). ✅

**Cross-cutting, Wave 5:** D28 (no artifact/test coverage shrinks without an explicit, stated
replacement) adopted mid-wave and applied retroactively to the status table; test count ran
227→257→267→274→296 across 5.5a through 5.7, every delta an addition. **Reorg, 2026-09-02:**
IMPLEMENTER now owns detailed code-level planning (trap lists, C-source pre-briefs); PLANNER is
limited to high-level project management (sequencing, GOs, decisions log, cross-wave policy) from
this point forward.

## Wave 6.0–6.1 (2026-09-02 – 2026-09-03)

- **Pre-Wave-6 process work:** Wave 5.8's docs/archive pass closed (D30) with one sub-item left
  for Jerod (project-instructions text, not directly editable by Claude). IMPLEMENTER's Wave 6
  scope survey found the original single "Wave 6" table row was ~11,000 lines of C, unreviewable
  as one unit — split into 6.0–6.5 per D32, with UI carved out to its own phase. Q16–Q20 ruled
  (D31–D34): wire format ported byte-exact from the C oracle, transport mechanism rebuilt on
  Network.framework + async/await (no fidelity obligation on the mechanism itself, per D4);
  WinBolo usable as a read-only architectural reference only, never copied from (GPLv2 vs.
  BoloKit's MIT posture); WinBolo-server substitution and a bundled `TCMPortMapper` both rejected.
  **Cold-start restructure:** the single IMPLEMENTER-only `CLAUDE.md` was split into three
  role-specific bootstraps (`CLAUDE.md`, `docs/PARITY.md`, `docs/PLANNER.md`), with
  `docs/AGENT_NOTES.md`/`docs/PLAN.md` as the two common references — stops wave-status content
  from being duplicated (and going stale) across bootstrap files. A commit-discipline rule was
  added after two incidents of work reported "ready" in conversation with nothing committed.
- **Wave 6.0** (`96704cd`+`5c5e47a`): wire codec — all 54 `CL*`/`SR*` structs, `CLUpdate`, all
  three encodings (raw BE float, 1/256 fixed-point, 8-bit brads), derived byte-exact from the C
  oracle. IMPLEMENTER independently caught an `FWIDTH`-double issue before PARITY's audit, which
  PARITY then independently re-derived rather than taking the completion report's word for it.
  PARITY PASS, no findings. Test count 329→345 (+16). Preamble structs (`JOIN_Preamble`/
  `BOLO_Preamble`/`TRACKER_Preamble`) were originally claimed in this wave but never actually
  built — corrected and reassigned to Wave 6.3 without reopening 6.0.
- **Wave 6.1** (`d0a9834`+`b028bf8`, then D35 fix `1e0cbe6`+`91c4a8d`, then re-audit `3d4563a`):
  tick orchestrator — `runclient()`/`runserver()`, new pause/timelimit/domination-basecontrol
  state machines. First PARITY pass found two findings (D35): a missing `pauseonplayerexit` →
  `server.pause = -1` side effect (real gap inside the exact function this wave claims to fully
  port) and an undisclosed `seq != 0` move-tank gate. Jerod ruled both get fixed before the Wave
  6.2 GO rather than deferred as tracked debt (unlike Wave 5.9's mine-cascade gap, neither was
  independent of 6.2+). Both fixed, PARITY re-audited clean. Test count 345→363 (+18 net).
  Closed 2026-09-03; GO issued for Wave 6.2 coding.

**Cross-cutting:** D28's coverage-never-shrinks-silently discipline held throughout — every test
count delta across 6.0/6.1 was an addition or an explicit, reasoned replacement. Full
uncompressed entries (process history, both pre-briefs in full, the D35 finding/fix/re-audit
cycle) preserved in git history per D28.

## Wave 6.2–6.3 (2026-09-02 – 2026-09-03)

- **Wave 6.2** (`0d44f30`+`a5e84b0`, then D37 fix `682173a`+`3c180c7`, then re-audit `d2c8fb0`):
  the 30 `recvsr*` client broadcast handlers (34 `SR*` opcodes minus `SRHANGUP`/unused and three —
  `sendmesg`/`timelimit`/`basecontrol` — with no `GameState` mutation, confirmed by reading their
  bodies rather than trusting their names). Central finding: this category is not "wire the
  existing Wave 5 tick functions to incoming messages" — a receiving client applies an
  already-decided value directly (no re-invocation of e.g. `growTrees`, which would pick a
  different random winner locally and desync), so most handlers are new, terminal
  reimplementations with no Wave-5 counterpart to call. Two callback surfaces (`onRequestGrabTile`,
  `onShouldLeaveAlliance`) surfaced instead of inlining behavior that belongs to later waves — same
  discipline as the Wave 5.9 mine-cascade ruling. **PARITY's audit found two real bugs (D37):**
  `recvSrSuperBoom` applied local-tank splash damage unconditionally where the C nests that check
  inside `player != client.player` (a genuine structural asymmetry vs. `recvSrSmallBoom`, which is
  correctly unconditional — independently brace-traced both ways); and both smallboom/superboom
  handlers were missing the `onTankStatusChanged` UI hook `client.c` fires unconditionally. Also
  confirmed **Q21**: `heatPill` (Wave 5.3a) was resetting `Pill.counter` (fire-cadence tally)
  instead of `Pill.coolCounter` (cooldown tally) — a real, if narrow, pre-existing fidelity bug,
  independently re-derived by PARITY from four separate C call sites. All three fixed, tests
  413→413+5 (net 408→413), re-audit clean including hand-running the exact previously-uncovered
  regression scenario. `MineChain.swift`'s pre-existing, structurally similar
  `applySplashDamage` gap was explicitly ruled *not* a bug (its authoritative C role has no
  `settankstatus` analog at all, grep-confirmed) — recorded so the two omissions aren't confused.
  **Q22 opened** (not resolved) alongside this wave: whether the port needs a standalone dedicated
  headless server binary vs. in-process hosting only — research on xbolo/WinBolo/LinBolo/PyBolo
  logged in `docs/notes/HOSTMODELS.md`, deferred to Jerod as a product-scope call. ✅
- **Wave 6.3** (`388a8c1`, PARITY PASS at `f75e1f2`): server session logic (join/kick/ban/alliance)
  plus the three preamble structs (`JoinPreamble`/`BoloPreamble`/`TrackerPreamble`) reassigned from
  Wave 6.0's corrected row. `evaluateJoinRequest`/`applyJoin` port `joinplayerserver()`'s rejection
  order and slot-selection (rejoin-by-name > first-never-used > oldest-disconnected-eviction,
  strict-`<` tie-breaking toward the lower index) exactly; `kickPlayer`/`banPlayer` reuse Wave
  5.5a's `dropPills` for the onboard-pill drop and preserve the C's real asymmetry (`banPlayer` has
  a `cntlsock != -1` no-op guard, `kickPlayer` doesn't); `requestAlliance`/`leaveAlliance` are the
  real implementations Wave 6.2's `onShouldLeaveAlliance` callback was designed to wire into, not
  duplicate. PARITY independently re-derived every preamble struct offset (including the packed
  `BOLO_Preamble` per-player-entry layout) and reasoned through the one item flagged for extra
  scrutiny (`evictsOldestDisconnectedSlotOnATie`'s tie-breaking, corroborated by both stdlib
  semantics and the passing test) rather than trusting the completion report. No findings. Tests
  413→445 (+32). **Surfaced two items PLANNER ruled on at close (not fixed within 6.3 itself):**
  **D38** — ~19 more `recvcl*` server TCP-receive handlers (every `CL*` opcode except
  `CLSetAlliance`) had no assigned wave; same shape as D36 — assigned to new **Wave 6.6**,
  recommended (not mandated) to run before Wave 6.4 so 6.4's dispatch wiring has a complete
  handler table from day one. **D39** — a real, port-introduced hazard (not a C bug to replicate):
  unifying `client`/`server` into one `GameState` merged two genuinely separate C variables,
  `server.pause` (ticks, decremented by `runTick`) and `client.pause` (wire seconds, written
  verbatim by `recvsrpause()`, never decremented), onto one `GameState.pause` field written in two
  different units by Wave 6.1 and Wave 6.2. Ruled a real fix required before Wave 6.4's pre-brief
  GO (same precedent as D35) — split into two fields, fixed and re-audited clean at
  `029c8fc`/`b1efc12`. ✅

**Cross-cutting:** D28's coverage discipline held (test count only ever grew: 408→413→445 across
this span). The three-role loop pattern (Planner GO → Implementer pre-plan/code and self-report
gaps → Parity adversarial audit → Planner incorporates and issues next instructions) held
consistently through every fix/re-audit cycle in this span (D37, D38/D39) — later confirmed by
Jerod as the project's standing planning/execution loop, recorded in `docs/notes/AFTERACTION.md`.
Full uncompressed entries (both pre-briefs, the D37 fix/re-audit cycle, the full PARITY audits)
preserved in git history per D28.
