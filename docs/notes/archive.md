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


## Wave 6.6, D39 fix (2026-09-03)

- **D39 fix** (`029c8fc`, re-audit `b1efc12`): split the unified `GameState.pause` field into
  `serverPauseTicks` (mirrors `server.pause`, tick-domain, decremented by `runTick`) and
  `clientPauseDisplaySeconds` (mirrors `client.pause`, wire-domain seconds, never decremented,
  written only by `recvSrPause`) — closing the Wave 6.3-flagged hazard where unifying `client`/
  `server` state onto one `GameState` had merged two variables written in different units by two
  different waves. Real regression avoided, not just a rename: the `RunTick.swift` pause gate had
  to gain an explicit `||` union of both fields, since the old unified field was accidentally
  covering both `runserver()`'s tri-state early-return (`server.c:1088-1099`) and `runclient()`'s
  truthy early-exit (`client.c:430`) at once. PARITY re-derived the gate against both C functions
  independently and traced the exact clobber scenario D39 exists to prevent (a received `SRPause`
  on a non-hosting client writing wire-seconds into a field the countdown logic would misread as
  ticks). Tests 445→447 (+2). ✅
- **Wave 6.6** (`ebb8fe4`, PARITY PASS at `f31413a`): 18 `recvcl*` server TCP-receive handlers (of
  the ~19 unassigned by D38; `recvclsendmesg` correctly dropped as a stateless relay with no
  `GameState` effect, matching Wave 6.2's precedent for `sendmesg`/`timelimit`/`basecontrol`). Four
  of the nineteen turned out to be thin wrappers around already-shipped engine functions
  (`recvcldamage`→`applyDamage`, `recvclsmallboom`/`recvclsuperboom`→`explosionAt`/`superboomAt`);
  nine new sites wire `explosionAt`/`superboomAt` directly, independent of Wave 5.9's still-open
  gap. **D40** ruled `recvclbuildroad`'s `clbuildroad->trees >= clbuildroad->trees` self-comparison
  replicated bug-for-bug (deterministic, well-defined — not the `pills[-1]` class of UB
  `applyDamage` correctly declined to replicate), including its second-order effect that the
  leftover-trees ack can go negative, passed through un-truncated as Wave 6.4's concern. Caught and
  disclosed mid-coding, not silently absorbed: `recvClTouch` actually calls `explosionAt` directly
  (not `touchTile` as the pre-brief assumed, revising 9 trigger sites to 10), and
  `explosionAt`/`superboomAt` have no broadcast-trigger callback of their own — worked around by
  re-deriving the same `detonated` terrain-membership predicate at each of the 10 call sites rather
  than reopening Wave 5.5a's already-shipped `MineChain.swift`, after confirming a closure-based
  route through `applyDamage`'s existing callback isn't expressible under Swift's exclusivity rules
  (SE-0176, two overlapping `inout` accesses to the same `state`). PARITY independently hand-counted
  `explosionAt`'s 29-item `detonated` case list (28 main-switch terrains + `.minedSea`'s standalone
  case) against `server.c:4120-4176`/`4192-4249` and confirmed it agrees exactly with
  `MineChain.swift`'s own internal predicate — two independently-written copies matching, not
  assumed. Also confirmed a genuine asymmetry: `explosionat()`'s broadcast is terrain-gated and
  always `NEUTRAL`; `superboomat()`'s is unconditional with the real causer. Tests 447→487 (+40). ✅

**Cross-cutting:** D28's coverage discipline held (447→487 across this span, all additions). The
"complete the whole C function a wave already claims, don't leave a partial slice" precedent (first
applied Wave 5.9/6.3/6.6) recurred again inside Wave 6.6 itself (`recvClTouch`'s correction). Full
uncompressed entries (both pre-briefs, the D39 fix/re-audit cycle, the full Wave 6.6 PARITY audit)
preserved in git history per D28.

## Wave 6.4 (2026-09-03)

Wave 6.4 is BoloKit's first genuinely non-porting wave — real `Network.framework` design, not
transcription of pure C decision logic — and split repeatedly as real, separable scope kept
surfacing under audit. Split first into **6.4a** (client transport) and **6.4b** (host transport)
per **D43** (same precedent as D23's Wave 5.3 split: two architecturally distinct roles, too much
bundled work for one coding pass), then **6.4c** was opened afterward per **D50** to close three
disclosed gaps in 6.4b's own scope boundary. **D42** confirmed `Buf.swift`'s POSIX socket half
(`sendbuf`/`recvbuf`/`cntlsend`/`cntlrecv`) stays unused per D31 — only its socket-agnostic
byte-queue half (`initbuf`/`writebuf`/`readbuf`) is reused; all real I/O goes through
`NWConnection`/`NWListener`. **D44** approved a named `maxDeadReckoningExtrapolationTicks =
Int(ticksPerSec) * 3` bound on `dgramclient()`'s unbounded extrapolation loop, a Swift-side safety
deviation (D36's `writeRun`-class), not a fidelity fix.

- **Wave 6.4a** (`e4ca245`, extended `8296346`+`810d9b2`, PARITY PASS at `0e6d714`): client-side
  transport — `applyRemotePlayerUpdate` (`dgramclient()`'s post-decode apply, `DgramClientApply.swift`)
  and `joinClient` (the wire-protocol join handshake, `JoinClient.swift`, built on the modern
  `withNetworkConnection` API). First wave with real system-design work: `explosionTick` (Wave 5.5b)
  couldn't be reused inside the dead-reckoning loop without over-aging every other player's
  explosion list, so the per-player drain was inlined instead. **PARITY's first audit
  (`60d5059`) found the wave incomplete, not incorrect** — everything written matched the C, but
  `joinclient()`'s back half (`client.c:690-750`, turning a received `BoloPreamble` into an
  initialized `GameState`: player index, roster, pause/gametype, spawn) had no Swift home anywhere,
  traced to the original pre-brief mis-citing server-side functions
  (`evaluateJoinRequest`/`applyJoin`/`assembleBoloPreamble`) as covering a joining client's own
  state init — a mix-up that slipped past both Planner's formal ruling and PARITY's own earlier
  stand-in assessment. **D45** ruled this a real, in-scope extension of 6.4a (not new/deferred
  scope), same precedent as completing whole C functions rather than partial slices. The extension
  (`8296346`) delivered `applyBoloPreamble` (mirroring D39's pause-sentinel translation for the
  client's own field, reusing Wave 5.6's `spawn()`), plus persistent `UDPSession`/`TCPSession`
  receive loops, plus a third self-found gap: `clientloadmap()`/`serversavemap()` (full BMAP file
  orchestration) had never been ported past the row-level primitives — shipped `decodeBMap`,
  leaving `encodeBMap` to 6.4b. **PARITY's second audit (`515429f`) found one more real bug: the
  extension never wrote `state.baseControlThreshold` from `preamble.baseControl`**
  (`client.c:713`), silently breaking the domination base-control win-timer for any client that
  joined this way — not caught by the extension's own tests, which had constructed the right
  non-default preamble value and simply never asserted on it. **D46** ruled the same as D45: fix
  now. Fixed at `810d9b2`, re-audited clean at `0e6d714`. Three rounds of real "actually finished"
  scrutiny on one sub-wave. Tests 487→502→521 (+34 net). ✅
- **Wave 6.4b** (`b26ee69`, PARITY PASS at `11d792c`): host-side transport — `HostListener`
  (`NWListener` accept loop, `evaluateJoinRequest`→`applyJoin`→`assembleBoloPreamble`+`encodeBMap`),
  `HostSession`/`HostSessionTable` (per-player TCP receive loop dispatching all 20 `CL*` opcodes to
  Wave 6.6's `recvCl*` handlers; the `sendsr*` broadcast fan-out — `sendToAll`/`sendToAllExcept`/
  `sendToMask` — mirroring `sendtoall`/`sendtoallex`/`sendtoone` per site), `DgramServerRelay.swift`
  (`dgramserver()`'s pure decision core). Pre-brief's own D45-mandated check (does Wave 6.3 have the
  mirror-image server-side gap?) came back clean — the C server's player struct is genuinely
  thinner than the client's, no state-mutating function was missing. Four real gaps the original
  `docs/PLAN.md` row didn't name were found and folded in: `encodeBMap` (G-1, promoted from an
  existing test helper, not new logic), the `sendsr*` fan-out itself (G-2, ruled in-scope by
  **D47** rather than split into a 6.4c — same D45 principle, "a host that can't broadcast is not a
  working host"), `wireSize` on all 20 `CL*` structs (G-3, mirroring 6.4a's `SR*` precedent), and a
  public `removePlayer` entry point (G-4). **D48** corrected D36's text: `dgramserver()`'s tracker
  echo (verbatim byte reply, no zeroing) is a genuinely different mechanism from
  `registerserver()`'s (explicit `bzero` + `player=255`), not the same one D36 originally described
  — 6.4b owns the former, 6.5 the latter. **D49** ruled `joinplayerserver()`'s single-pending-joiner
  serialization gets replicated via a real async mutex, not relaxed, per D41's standing "preserve
  the invariant a C timing behavior protected" principle. Implementation found the pre-brief's own
  per-connection-`Task` sketch was unsound under Swift's exclusivity law (`state: inout GameState`
  can't be held by two concurrent Tasks regardless of a mutex on top) — fixed by draining accepted
  connections through a single sequential `AsyncStream` consumer instead. Six already-shipped Wave
  6.6 `recvCl*` callback signatures needed extending (`onShouldBroadcastBuild`/`Damage`/
  `CapturePill`/`CaptureBase`/`BuildPill`/`RepairPill`) since the real `sendsr*` C functions each
  read one more field off already-mutated state that a caller-side closure couldn't re-read under
  the same exclusivity constraint — fixed by having each `recvCl*` read its own extra field
  immediately post-mutation and pass it through. Three real gaps disclosed but deliberately left
  unfixed as out of this wave's own scope, tracked for 6.4c: `dropPills` has no broadcast
  (pre-existing Wave 5.5a gap, exposed not created), the live UDP listener driving
  `DgramServerRelay.swift` was never wired, and `dgramaddr` was seeded as a zeroed placeholder
  rather than the joining connection's real address. PARITY's audit independently confirmed all
  three C citations for the six extended callbacks, the `CLSendMesg` masked-relay special case
  (`sendsrsendmesg()`'s own inlined loop, not a generic `sendtoall*` call), and the `HostListener`
  exclusivity fix, catching only a cosmetic citation-line typo (`server.c:817`→`:844`). Tests
  521→560 (+39). ✅ **D50** bundled all three disclosed gaps into a new Wave 6.4c, sequenced before
  Wave 6.5 (whose own tracker-echo work also touches the UDP receive path).
- **Wave 6.4c** (`5fdb1bc`, D53 fix `534aa57`, PARITY PASS at `999dbde`): live UDP wiring, real
  `dgramaddr`, and the `SRDropPill` broadcast. **D51** put the new UDP accept loop
  (`HostDgramListener.swift`) in its own file, matching the established one-listener-per-file
  convention. **D52** bounded the same per-peer-`NWConnection` growth hazard `NWListener`+UDP
  reintroduces (one connection per remote 4-tuple, unlike the C's single `recvfrom()` socket) by
  connection lifecycle rather than an arbitrary cap: `HostSessionTable.dgramConnection` tracks one
  live flow per slot (bounded by `maxPlayers`), explicitly canceling a slot's superseded connection
  on a port-mismatch swap rather than merely dropping the reference. `peerAddress(from:)` extracts
  a real IPv4 `family`/`addr`/`port` from an accepted `NWConnection`'s endpoint, matching
  `server.c:844`'s literal `dgramaddr` assignment port-included (confirmed the C's own
  seed-wrong-then-correct-via-first-packet design is intentional, not a bug to route around) —
  caught a real native-endian-load-of-network-order-bytes trap along the way (`127.0.0.1` reads as
  `0x0100007F`, not the "obvious" `0x7F000001`), disclosed rather than left as a silent trap.
  `SRDropPill` wired via a new `onShouldBroadcastDropPill` callback threaded through
  `dropPillSearch` (`MineChain.swift`), firing on the *search cell's* `x`/`y` — not the outer scatter
  origin, a real trap (**T-17**) confirmed by direct read of `dr()`/`sendsrdroppill()`'s
  post-mutation field read. Correctly preserved a genuine C asymmetry: `kickplayer()`/`banplayer()`
  send their own broadcast *before* `removeplayer()`, while the socket-close disconnect path calls
  `removeplayer()` *before* its broadcast — the opposite order — replicated via two different
  accumulator strategies, not one shared shortcut. **PARITY's audit found one real, confirmed bug:**
  `handlePlayerDisconnect`'s `.normal` case broadcast `SRPlayerExit` via `sendToAllExcept`, dropping
  the departing player from the recipient set — but `sendsrplayerexit()` is not one `sendtoallex`
  call, it's a best-effort `sendtoone` to the departing player *first* (EPIPE-tolerant, the socket
  may be half-closed), *then* `sendtoallex` to everyone else, so the departing player receives their
  own exit notice too. (`.abnormal`/`SRPlayerDisc` was already correct — a genuine single
  `sendtoallex`, no self-send.) Notably, the function's own header comment already described the
  correct combined behavior; the code beneath it simply hadn't been wired to match — a real slip,
  not a disclosed simplification. **D53** ruled the standard fix-before-close (same precedent as
  D35/D37/D39/D45/D46): switched to `table.sendToAll` for the `.normal` case, left `.abnormal`
  untouched, added named regression tests including a timeout-race negative-assertion pattern new
  to this project's test suite — PARITY specifically traced the counterfactual (what happens if
  `.abnormal`'s exclusion were accidentally removed) to confirm the test would actually catch it,
  not just that it currently passes. Tests 560→571→572 (+12 net). ✅

**Cross-cutting:** D28's coverage discipline held throughout (487→502→521→560→571→572, every
delta an addition). This is the first wave family where the standard post-code audit itself became
the primary scope-completion mechanism rather than a correctness check alone — 6.4a needed three
audit rounds (D45, D46) and 6.4c needed one (D53) before closing, each catching real, previously
undisclosed gaps in a wave's own already-claimed scope, none of them cosmetic. The
"replicate the invariant a C timing/ordering behavior protects, not its literal mechanism" principle
(first established Wave 5.9's **D41**, on the dead-flag ordering hazard `smallboom`/`superboom`
introduce once client/server timing collapses into one synchronous process) recurred directly in
Wave 6.4b's **D49** ruling on join serialization. Full uncompressed entries (all three sub-waves'
pre-briefs, completion reports, and PARITY audits, including the ad hoc pre-code PARITY assessments
Jerod requested for 6.4 and 6.4b) preserved in git history per D28.


## Wave 6.5 (2026-09-03 – 2026-09-04)

Wave 6.5 split into **6.5a** (tracker protocol — register/heartbeat/browse, oracle-testable) and
**6.5b** (NAT-PMP/UPnP mapping — no C oracle possible) per **D55**, same grounds as D23/D43 (two
units of work with different verification stories). **D54** approved
`DNSServiceNATPortMappingCreate` (`import dnssd`) as the NAT-traversal mechanism — a system API in
`libSystem`, covering the same NAT-PMP/UPnP union `TCMPortMapper` did, satisfying `README.md`'s
GPLv3-avoidance commitment. **D56** ruled the pre-brief's two adjacent `TrackerHost` findings get
opposite treatment: the heartbeat's missing `htonl()` on `timelimit` (`server.c:1577`) is
deterministic — D24/D40 bug-for-bug replication applies — while the struct's un-`bzero`'d pad/tail
bytes are genuine UB — the D40 `pills[-1]`-class exception (zero-fill, disclosed Swift-safety
deviation) applies instead. Jerod directed both sub-waves run simultaneously rather than
sequenced (exercising D55's "or concurrent" clause); they landed cleanly against disjoint file
lists without incident. Q26 opened (not ruled): whether this port ships the tracker *daemon*
binary (`tracker.c`) at all — adjacent to Q22, deferred to Jerod as a product-scope call once the
app/distribution phase starts.

- **Wave 6.5b** (`a250c57`, build-fix `cdff28d`, PARITY PASS): `PortMapping.swift` wraps
  `DNSServiceNATPortMappingCreate` (D54) as an `AsyncStream`, same pattern as D49/D52's two prior
  listeners, boxing the stream continuation through `Unmanaged`/`UnsafeMutableRawPointer` since
  `dnssd`'s callback is a C function pointer that can't capture Swift state directly — a new
  mechanism shape for this codebase. `decodePortMappingReply` factored out as pure decision logic
  per the D31/D36/D42 split, independently PARITY-verified (`kDNSServiceErr_NoError`/
  `kDNSServiceErr_DoubleNAT` the only accepted codes, `UInt16(bigEndian:)` swap hand-checked).
  `doubleNAT` modeled as a successful update with a flag, matching the API's own
  state-change-callback shape. Live NAT round-trip correctly disclosed as D55's non-goal, not
  silently skipped — 5 tests, all but one against the pure decision function (`cancel()`
  idempotency legitimately touches the live `mDNSResponder` daemon). Two mechanical build errors
  (`decodePortMappingReply` wrongly `internal`; `PortMappingUpdate` missing a public memberwise
  init; `dns_sd.h`'s untyped `Int` error constants needing explicit casts) found and fixed
  separately (`cdff28d`) once 6.5a unblocked the shared build — zero behavioral change. No PARITY
  findings. Tests 572→577 (+5). ✅
- **Wave 6.5a** (`a23d49d`, PARITY audit `c9e37ef` — one real finding, D57 fix `6cbec85`+
  `f7b0528`, re-audit `7f1a9ee` PASS): tracker protocol. `Tracker.swift` — `TrackerHost`/
  `TrackerHostList` wire structs (`tracker.h:41-56`, 60/64 bytes, offset-51 pad byte confirmed by
  a new `tracker_layout_oracle()`), zero-filling the pad byte and `strncpy`-boundary bytes on
  encode per D56/T-3. `TrackerRegistration.swift` — `TrackerSession` (persistent `NWConnection`,
  same shape as `TCPSession`/`UDPSession`) plus `registerWithTracker(...)`, porting
  `registerserver()`'s nine-step handshake (`server.c:1259-1509`) and the previously-undocumented
  60-second `sendtrackerupdate()` heartbeat (`server.c:1569-1588`, `TRACKERUPDATESECONDS`).
  `TrackerBrowser.swift` — `listTrackerGames(...)`, porting `listtracker()` (`bolo.c:346-450`) via
  the `withNetworkConnection` one-shot pattern. **D56's bug-pairing landed and independently
  re-derived at the source by PARITY:** `encode()` correctly `htonl`'s `timeLimit`
  (`server.c:1383`); `encodeAsHeartbeat()` reproduces the missing-`htonl` bug bit-for-bit
  (`server.c:1577`), with a named test asserting the two encodings differ *only* there. T-8's
  reuse of `HostDgramListener`'s existing UDP echo (Wave 6.4b/6.4c) in place of
  `registerserver()`'s own inline echo was traced byte-for-byte against both C functions and the
  tracker daemon's own trigger check (`tracker.c:225-267`) and confirmed content-identical by
  construction — a sound mechanism substitution, not a completeness gap; disclosed as an
  orchestration dependency this wave doesn't own. Browse path decode (`bolo.c:438,446-447`)
  confirmed exact, including that the heartbeat's byte-order bug correctly propagates to a
  listing client with no special-casing. T-4 (tri-state `registerserver()` return) disclosed as a
  mechanism substitution (Swift `Task` cancellation covers the "closed by main thread" case
  cooperatively) rather than a third enum case; T-10 (heartbeat cadence/back-pressure) disclosed
  as scoped out, deferred to whichever future wave owns a tracker scheduling loop, same boundary
  as `UDPSession.sendLocalUpdate`. **D57 — real finding, fix required before close:**
  `trackerHost()` built `timeLimit: UInt32(state.timeLimit)`, which **traps** on a negative
  `GameState.timeLimit` (an already-anticipated state per `RunTick.swift`'s own `> 0` guard,
  mirroring `server.c:1102`), where the C's implicit `int`→`uint32_t` conversion inside `htonl()`
  never crashes — a crash-safety divergence, not a wire-format bug, and new to this codebase (no
  other site shares the pattern). Latent (no caller yet constructs a negative `timeLimit`), but
  ruled fixed now, not deferred, per the D45/D53 precedent. Fixed at `6cbec85`:
  `UInt32(truncatingIfNeeded: state.timeLimit)`, matching C's actual bit-pattern-reinterpret
  behavior exactly (hand-verified: `-300` → `0xFFFF_FED4`, both via two's-complement math and via
  the regression test). Re-audit (`7f1a9ee`) confirmed the fix's semantic correctness (not just
  trap-avoidance), scope minimality (2 files touched), and no regression for any previously-passing
  non-negative input. Tests 572→591 (6.5a's own 19) →596 (+6.5b's 5, full suite) →**597** (+1, D57
  regression test). ✅

**Wave 6.5 (6.5a+6.5b combined) is closed** — both halves PARITY PASS, no open findings on either
side. 572→597 tests across the wave, no coverage lost (D28).

### Wave 6 close-out

**Wave 6 (networking, 6.0–6.6 in full) is closed.** Every sub-wave from the wire codec through the
tracker/NAT client is PARITY PASS with no open findings: 6.0 (codec) → 6.1 (tick orchestrator) →
6.2 (broadcast handlers) → 6.3 (session logic + preambles) → 6.4a/6.4b/6.4c (transport, join
handshake, live UDP wiring) → 6.5a/6.5b (tracker protocol + NAT-PMP) → 6.6 (server receive
handlers). **Nine real PARITY findings across the whole wave — D35, D37, D39, D45, D46, D48's
correction, D50, D53, D57 — were each fixed and independently re-confirmed before their sub-wave
closed; none left open or silently accepted.** This is the largest single phase of the project
closed to date. No next wave is currently GO'd: `docs/PLAN.md`'s Phase 4/5 (fidelity measurement
and gap-closing) has never been started, the UI/app phase (D38) has never been scoped, and Q22
(dedicated host binary vs. in-process) and Q26 (tracker daemon binary) both remain open, gated on
whichever of those directions Jerod picks next — a genuine product-scope fork, not a call PLANNER
can make from `docs/PLAN.md` alone.

**Cross-cutting:** D28's coverage discipline held throughout this span (572→577→596→597, every
delta an addition or a disclosed, reasoned replacement). The simultaneous-sub-wave-execution
pattern (Jerod's direct sequencing call, exercising D55's "or concurrent" clause) ran cleanly
against genuinely disjoint file lists without a shared-log-commit collision, though the intended
Wave 5.9 worktree-isolation mechanism wasn't actually used (both sessions worked one checkout) —
noted for future parallel waves, not a problem this time. The fix→re-audit precedent established
across Wave 6 (D35/D37/D39/D45/D46/D50/D53) recurred once more cleanly with D57's own
fix→re-audit cycle, including PARITY explicitly re-verifying the regression test's own arithmetic
by hand rather than trusting the commit message. Full uncompressed entries (both pre-briefs, the
6.5a/6.5b fold-in and simultaneous-execution directive, the full PARITY audit and D57 fix/re-audit
cycle, and Wave 6's formal close-out ruling) preserved in git history per D28.

## Wave 7 (2026-09-04)

**Pre-wave ruling:** Jerod resolved Q22/Q26 directly before picking Wave 7's direction — **D58**:
support both in-process hosting and a separate headless Dedicated Host binary; **D59**: no
self-hosted tracker daemon, manual IP connection only (Wave 6.5a's tracker client code remains
useful against any third-party tracker). Neither touches shipped Wave 6 code. Separately in this
span, **D61** ruled Q10: `Reference/c` stays in-tree as an actively-consulted oracle until the port
is done referencing it (no earlier than Milestone D), not removed now.

Wave 7 (UI/app phase) opened and was initially pre-brief GO'd at full scope (menus, HUD, networking
UI), but Jerod flagged that as too large a step with no clear ship path. Re-scoped to a
single-process, single-player **v1 vertical slice** — **D60**: no menus, no networking UI, no HUD,
split into four coding-GO'd sub-waves (7.0 asset pipeline → 7.1 Xcode app target → 7.2 rendering →
7.3 input/tick loop); Milestones B (multiplayer UI)/C (HUD/prefs/chat/sound)/D (polish, signing,
Q18's git-history rewrite) explicitly deferred, not GO'd. An ad hoc pre-code PARITY audit of the
Wave 7.0/7.2 briefing numbers (retroactively covered) found the brief's own arithmetic wrong before
any code landed: **D62** corrected `images.h` to two independent index spaces (tiles 177/256
cells, sprites 113/256 cells), not one 256-cell sheet; **D63** narrowed 7.0's scope to the sheet
renderer only, since the constants+`mapimage()` parse was already done in
`Sources/BoloKit/Images.swift`; **D64** settled that sheet row-0 origin has no fidelity obligation
but 7.0/7.2 must agree on one convention, and `-1` is always a "no image" sentinel; **D65** ruled
fog-of-war/`seentiles` display out of scope for v1 — every tile renders fully visible, straight
from `mapimage()`.

- **Wave 7.0 — asset pipeline** (`618bedf`, PARITY PASS `79840b1`). `BoloGlyphsCore` (library,
  split from a bare `BoloGlyphs` executable per **D68**) derives all tile/sprite glyph semantics by
  sweeping `mapimage()` across 256 8-neighbor configurations rather than hand-transcribing
  `images.c`'s case labels — self-checking (fails loudly if the count doesn't land on exactly
  177/113). **D66**: top-left row-0 sheet origin, binding on 7.0 and 7.2. **D67**: procedural
  raw-pixel-buffer glyphs, no vendored OFL font — the cleaner-provenance call, shipped even simpler
  than the "CoreGraphics paths" pre-briefed (pure RGBA buffer manipulation; CoreGraphics/ImageIO
  only in the thin executable, for PNG encode). Test count 597→605 (+8). PARITY's post-commit audit
  independently re-derived every per-family variant count (wall 47/river 16/forest 10/crater
  16/road 31/boat 8/sea 9 = 137, +8 flat +32 pill = 177 tile cells; 113 sprite cells) directly from
  `images.c`/`images.h` — clean, but surfaced a real mismatch (not a 7.0 defect, a 7.2
  prerequisite): the shipped `drawTank` pointed heading-0 screen-north, clockwise, while `BoloKit`'s
  own `dir2vec` has heading-0 = screen-east, counterclockwise — a full mismatch, not an offset.
  **D70** ruled: fix the generator to match `dir2vec` exactly (call it directly rather than
  re-deriving an equivalent angle formula), not carry a translation layer forever. Fixed at
  `dd064dc` (608 tests, +3, three named regression tests including a parametric all-16-heading
  check), re-audited clean at `c4da9e0`. Wave 7.0 formally closed on the `79840b1` PASS before D70
  even landed (D70 was scoped as a 7.2 prerequisite, not a 7.0 defect). Separately during this
  stretch: an out-of-band governance finding (uncommitted `docs/PARITY.md` edits adding self-modify
  language, plus a "Director" identity — confirmed by Jerod to be himself) was raised, not acted on
  unilaterally; the self-modify grant was ultimately replaced with a narrower propose-then-adopt
  model (**D71**, superseded same day) — PARITY drafts proposed rule changes tagged
  `[TO: PLANNER]`, PLANNER rules on adoption. `CLAUDE.md` was also restructured into an
  administrative section (durable) plus a PLANNER-editable instructions section.

- **Wave 7.1 — Xcode app target** (`426c6a4`; D75/D76 follow-up `6e060e9`; PARITY final-state audit
  `a03aa07`; D77/D79/F5 fix `72d880f`; closed on `a03aa07`'s PASS per the D74-D80 rulings). Native
  Cocoa App target (`Bolo 2026`, per **D73** — corrected from the pre-brief's invented "BoloApp"
  name, and no `BoloNet` dependency anywhere in 7.1-7.3, matching D73's single-process/no-networking
  scope) built via `XcodeNewProject` (not the GO'd `XcodeNewTarget`, which cannot target-add to an
  SPM-synthesized workspace — a disclosed mechanical deviation). Sheet delivery via a build-time Run
  Script invoking the built `BoloGlyphs` executable, wired as an explicit target dependency (**D72**,
  approved as proposed) — sheets never committed to git. Placeholder app icon generated (not
  copied) from `BoloGlyphsCore`'s own glyph primitives, licensing-checked by md5 against every
  `Reference/c` image file (zero overlap). Entitlements delivered as template-synthesized build
  settings (App Sandbox on, no network entitlement of any kind) rather than a literal
  `.entitlements` file. **D74**: all four disclosed deviations (tool substitution, a hard-prerequisite
  `Package.swift` `products:` block addition, entitlements-as-settings, two hand-edited `.pbxproj`
  sections since no MCP tool covers package refs/script phases) accepted, no rework. **D75**:
  `MACOSX_DEPLOYMENT_TARGET` brought down from the template's 27.0 to 26.0 (D16's floor) on the
  target (project-level default left at 27.0, a disclosed, deliberately-deferred residual). **D76**:
  a shared `.xcscheme` committed (was previously autocreated/per-user), verified no scheme
  duplication. Bundle identifier `com.cosmicceo.Bolo-2026` stands provisionally — **Q27**, still
  open, Jerod's call, not blocking. Test count 608→612 (+4 icon tests); two Xcode crashes and a
  failed 27.1-beta reinstall were reported mid-wave but confirmed to have left no half-written
  project state (verified before resuming). PARITY's final-state audit (`a03aa07`) was the project's
  first fully execution-verified audit (Swift toolchain confirmed present and used throughout —
  `docs/PARITY.md`'s "no toolchain" claim was stale; **D80** adopted PARITY's proposed amendment
  requiring a per-session tooling check and execution-vs-hand-trace disclosure) and found: **F1/D77**
  — a confirmed PNG-premultiply defect inherited from Wave 7.0's own `writePNG` (declared
  `.premultipliedLast` context fed straight-alpha buffers, so partial-alpha pixels shipped wrong —
  measured 2,548 mispainted pixels in `Tiles.png`, invisible to any existing test since none decoded
  an emitted PNG); ruled required before Wave 7.2's coding GO (same precedent as D45/D53/D57), fixed
  at `72d880f` by premultiplying before the `CGContext` copy, with new tests that decode the emitted
  PNG and lock in the exact byte values. **F2** — Run Script sandboxing rationale corrected
  (declared inputs/outputs buy dependency-analysis/incremental correctness, not sandbox legality —
  tested both ways). **F3/D78** — corrected D74's text: `ENABLE_OUTGOING_NETWORK_CONNECTIONS`/
  `ENABLE_INCOMING_NETWORK_CONNECTIONS` don't exist as keys at all (absence, not an explicit `NO`);
  Milestone B will need to add them, not flip them. **F4/D79** — `Bolo 2026`'s Swift language mode
  was still 5 while `BoloKit` builds under 6; raised to Swift 6 before Wave 7.2's coding GO (fixed
  at `72d880f` alongside D77/F5, clean build from deleted DerivedData). **F5** — trivial dead-branch
  comment/behavior mismatch in `AppIcon.swift`, fixed opportunistically (`preconditionFailure` now
  matches its own comment). Test count 612→614 (+2, the D77 PNG round-trip tests).

- **Wave 7.2 — game rendering** (`9a8b328`+`6e76aea`; PARITY audit `3dfabff`; D86 fix
  `3e03137`+`e5fccee`; re-audit PASS `07974bd`; closed). Pre-brief measured two disposable
  prototypes (SwiftUI `Canvas`/`TimelineView` vs. AppKit `NSView`/`NSViewRepresentable`) live
  against real sheets/`mapimage()`/tank sprites at two viewport sizes; AppKit won at v1's realistic
  window size (6.7ms/7.3ms p95 vs. 7.8ms/9.3ms) with a real Canvas-favoring crossover only at
  near-full-map viewports (out of v1's zoom/scroll-less scope). **D81**: AppKit `NSView` via
  `NSViewRepresentable`, coding GO'd — also chosen for safety under D41's tick-timing discipline,
  since a `Canvas`+`TimelineView` gotcha was found and documented (SwiftUI silently stops
  compositing when drawn content is byte-identical frame to frame, no error). **D82**: own file for
  the view (matches D51's one-concern-per-file precedent), redraw-trigger wiring deferred entirely
  to 7.3 (7.2 accepts a `GameState` snapshot and redraws on demand only). Confirmed independent of
  the mechanism choice: `BoloKit`'s own `Vec2f`/grid convention is already +y-down, so no C-style
  `255-y` flip is needed anywhere in the renderer (`isFlipped = true` on the `NSView`) — verified
  against real rendered output via two, later three (PARITY's own), independent
  off-screen-rendering techniques, not just accepted from `Vector.swift`'s doc comment. The
  implementation needed one piece of scope the pre-brief hadn't named: **D83** ratified
  `tileFor`/`displayTileGrid` (`BMap.swift`) — pills/bases must overlay terrain before `mapimage()`
  can autotile correctly, ported faithfully from `client.c`'s `tilefor()`, with an O(n) fast-path
  rewrite (measured ~122ms/call naive → 8.4ms debug/0.115ms release) locked to the literal port via
  an exhaustive 256×256-cell equivalence test. Building the actual renderer also surfaced a real
  Wave 7.0 art defect: **D84** ratified a fix for checkerboard-transparent diagonal corners on any
  adjacently-tiled non-wall connective family (sea/river/forest/crater/boat never had real diagonal
  data to begin with, but `drawConnective` left their corners unconditionally transparent) —
  inferred each corner from its two adjacent orthogonal bits instead, `.wall`'s real diagonal data
  explicitly left untouched. Test count 614→626 (+12, including the project's first
  `@Test(arguments:)` parameterized case). PARITY's audit confirmed `tileFor`/`displayTileGrid`
  line-for-line against `client.c:6106-6141`, independently reproduced the no-y-flip claim with a
  third technique (self-caught and corrected an inverted first attempt from an unverified
  raw-buffer-layout assumption before reporting), and confirmed all four smaller judgment calls
  (global/unattributed explosions drawn; `GameState.ticks` substituting for a missing per-player
  `seq`; the always-1.0 `fraction` parameter dropped; a `ScrollView` demo wrapper) — but found one
  real regression in the corner-fill fix itself: `.road` should have gotten the same diagonal-data
  exemption `.wall` did (its own `deriveRoadConnectivity()` sweeps real diagonal data, confirmed by
  `mapimage()`'s road branch genuinely disambiguating on diagonals), but the fix lumped it in with
  the five no-diagonal-data families, silently collapsing 26 of road's 31 autotile images into 9
  distinct renders. **D86** ruled this a same-wave-introduced regression (not inherited debt like
  D77/D84), required before Wave 7.2 closes. Fixed at `3e03137`+`e5fccee` (widened the exemption to
  `.wall || .road`, new regression test, verified against a real decoded `Tiles.png`: 31 road images
  now resolve to 21 distinct rendered groups, the 10 residual identical pairs confirmed to share the
  same `(ortho,diag)` value pre-existing under D64's no-fidelity-obligation rule, not a residual
  defect). Test count 626→627 (+1). Re-audited clean at `07974bd` (independently re-derived all four
  check-points from a fresh harness, including the exact 10 index pairs).

- **Wave 7.3 — input + tick loop** (pre-brief `70e72b9`; `82d2c08`+`6fa224c`; PARITY audit
  `4eb483f`; D89 fix `2a53299`+`28b00ee`; re-audit PASS `a2f1779`; closed `8172aa1`). **D87**
  granted auto-mode for this sub-wave's Implementer→Planner→Parity loop (ended automatically once
  7.3 hit a clean PASS; D85's standing yes/no subagent-dispatch gate resumed). `GameSession` (new,
  `@MainActor`) drives `runTick` via a `DispatchSourceTimer` at 50Hz (measured, not assumed, per
  D41: ~20.05-20.08ms average, 3.4-8.7ms worst-case jitter across three runs), calling
  `GameRenderView.render(_:)` after each tick. Keyboard capture extends `GameRenderView` itself
  (reopening the already-PARITY-passed Wave 7.2 file, disclosed openly) mirroring `GSBoloView.m`'s
  own first-responder architecture, with the literal default keymap ported byte-for-byte from
  `DefaultPreferences.plist` (including the `autoSlowdownBool==true` default, under which the Brake
  key is intentionally dead code). Tracing the actual C reference surfaced two real,
  previously-unnamed gaps, both ruled in-scope under **D88**: **§3** — `keyevent()`'s LMINE branch
  plants a mine immediately on key-down regardless of tile change, a different mechanism from the
  existing tile-change-gated `.lmine` flag handling; ported as a new `layMineOnKeyDown` function.
  **§4** — `onSpawn` was still an unwired pass-through (confirmed by grep: `spawn()` was never
  called from anywhere), meaning a dead local player could never revive, contradicting the wave's
  own "driven by the actual physics engine" charter; fixed by calling `spawn(state:)` directly
  inside `tankMoveTick`'s own `inout` binding (mirroring Wave 5.9's exclusivity-safe callback
  pattern), plus ensuring the initial demo `GameState` carries a nonempty `starts` array. Test count
  627→639 (+12). Integration-verified end-to-end via a harness driving real synthesized `NSEvent`s
  and a live timer against the real compiled `BoloKit`/generated sheets. PARITY's audit confirmed
  the `spawn()` exclusivity fix, the keyboard-capture architecture, and the byte-for-byte keymap all
  clean, but found one real, confirmed defect: **D89** — `layMineOnKeyDown` unconditionally
  decremented `state.local.mines` *before* checking terrain minability, where `keyevent()` only
  spends a mine inside its terrain switch's 15 matched minable cases — pressing Lay-Mine on
  sea/wall/river/boat/damaged-wall silently wasted a mine, and the shipped test
  (`layMineOnKeyDownNoopsOnUnminableTerrain`) had encoded the bug as its own expected value. Ruled
  required before Wave 7.3 (and the whole v1 slice) closes, same precedent as D86. Fixed at
  `2a53299`+`28b00ee` — gave `plantMine` a `Bool` "did it actually plant" return, gated the
  decrement on `true`, corrected and parameterized the regression test over the five named
  unminable terrains. Test count 639→639 (0 removed — an existing test corrected/expanded, not new
  coverage). Re-audited clean at `a2f1779`, which went beyond the sampled terrains to exhaustively
  sweep every `Terrain.allCases` value against the fix.

### Wave 7 close-out

**Wave 7 — the entire v1 vertical slice D60 scoped — is closed** as of `8172aa1`. All four
sub-waves (7.0 asset pipeline, 7.1 Xcode app target, 7.2 rendering, 7.3 input/tick loop) carry a
PARITY PASS. D60's literal cut-line is delivered exactly as scoped: a window opens, renders a real
map from real build-time-generated assets, and lets a player drive a tank via the actual ported
physics engine, keyboard-controlled, tick-driven at 50Hz, single-process, no networking wired in.
**Six real regressions/gaps were found and fixed across the wave, every one via the same
fix→re-audit→close discipline this project has run since Wave 5, none left as unrouted debt**: D70
(tank-heading convention mismatch vs. `dir2vec`), D77 (PNG premultiply corruption, inherited from
Wave 7.0, closed out at Wave 7.1), D84/D86 (Wave 7.0's corner-fill art defect, then D86's own
road-diagonal regression introduced by that very fix), D88 §3/§4 (LMINE immediate-plant and
dead-player-never-revives gaps found by tracing the actual C source rather than assuming the wave's
one-line scope text), and D89 (mine-waste on unminable terrain). Test count ran
597→605→608→612→614→626→627→639 across the wave, every delta an addition or a disclosed, reasoned
correction (D28 compliant throughout). Explicitly still deferred, not reopened by this close:
Milestone B (multiplayer Host/Join UI wired to Wave 6's networking, per D58), Milestone C (HUD, key
remap, alliance/chat panels, sound), Milestone D (zoom/scroll polish, signing/notarization, and
Q18's git-history rewrite of the original copyrighted assets) — none GO'd, all still gated on a
fresh PLANNER/Jerod ruling. D87's auto-mode grant for Wave 7.3's workflow ended automatically on
the clean PASS; D85's standing yes/no gate before dispatching to an Implementer subagent resumed.
Governance side-notes from this span, recorded for continuity rather than because they're wave
content: the "Director" identity was confirmed to be Jerod himself; `docs/PARITY.md`'s attempted
self-modify grant was replaced with a propose-then-adopt model (D71, superseded same day) and later
amended again (D80) to require a per-session tooling check now that this project's PARITY host is
confirmed to have a working Swift toolchain; repeated Xcode toolchain instability (two crashes, a
failed 27.1-beta reinstall, a stray 23MB `-Xcc` index-store artifact, and a reproducible Run Script
subprocess-launch hang) was logged throughout but never left any actual defect in committed project
state, each time verified by direct inspection rather than assumed. Full uncompressed entries
(every pre-brief, completion report, and PARITY audit in this range, plus the ad hoc pre-code
numeric audit and the governance thread) preserved in git history per D28.

## Post-Wave-7 process (D90–D93) and Milestone B: B.0–B.5b, plus B.5c's pre-brief (2026-09-05)

**Pre-Milestone-B rulings, direct from Jerod/PLANNER, no code:** **D90** closed Q27 — bundle
identifier confirmed `com.cosmicceo.Bolo-2026`, aligning with the GitHub org. **D91** removed D85's
standing yes/no subagent-dispatch gate, superseded by this environment's own Auto Mode (PLANNER
acts directly on PARITY/Implementer/Admin handoffs; Jerod's authority over genuinely ambiguous or
high-stakes product/scope calls is untouched). **D92** (a parallel Implementer-lens + Parity-lens
pre-plan of Milestones B/C/D) closed **Q18**: `Reference/c` is a git submodule, not vendored
content, and no copyrighted asset bytes exist anywhere in this project's own git history —
independently re-derived by the Parity-lens pass — so removing it at Milestone D is a plain `git
submodule deinit`, not a destructive history rewrite, meaningfully de-risking Milestone D. The same
pass corrected two of its own earlier claims (Milestone C's key remap needs a real remappable
model, only 6/14 reference bindings wired today; Milestone C's sound is sample-based `.aiff`+
`NSSound` round-robin pools, not procedural synthesis, opening **Q28** sound-asset licensing),
flagged a new fidelity risk (the alliance system's vision-merge and fog-of-war aren't independently
scopable — both unmodeled, per D65), and surfaced a Milestone B protocol gap (the reference's
`joinprogress()` dispatches 19/21 `kJoin*` codes through one callback; `JoinClient` modeled only 6
protocol-rejection cases with no progress-callback mechanism at all). **D93**: Jerod GO'd Milestone
B first, execute B→C→D in alphabetical order; assigned B.0.

- **B.0 — package/entitlement plumbing** (`27c200c`+`89fadd4`, PARITY PASS `63b58c0`). Exported
  `BoloNet` as a real SPM library product (`Package.swift`), wired the `BoloKit`-shaped three-part
  `.pbxproj` target dependency (not `BoloGlyphs`'s build-order-only shape), added
  `ENABLE_INCOMING_/OUTGOING_NETWORK_CONNECTIONS` (D78 — added, not flipped; neither key existed at
  all before this commit). Verified beyond the pre-brief's own bar: a real `xcodebuild`, `codesign`
  confirming both new entitlements synthesize to `network.client`/`network.server`, and an `nm`
  check confirming 5,283 `BoloNet` symbols actually linked into the debug dylib, not just declared.
  No behavior change; tests 639→639. **Process incident, logged plainly rather than silently
  fixed:** the PARITY audit subagent, scoped only to append a `[PARITY]` entry, also wrote and
  committed a `[PLANNER]`-tagged entry (`c79243f`) closing B.0 and issuing B.1's coding GO on its
  own authority — unauthorized, but substantively correct on independent review (ratified, no
  rework, no rollback). Root cause: the dispatch prompt forbade touching other files but didn't
  forbid writing a different *tag* within the file it could touch; corrected going forward
  ("append only a `[<ROLE>]`-tagged entry; do not close a wave or issue a coding GO — report and
  stop"). ✅
- **B.1 — navigation shell** (`0948f26`+`b116ac3`, PARITY PASS `8b78e84`). Single-window
  `AppRootView`/`AppScreen` state switch replacing the reference's three literal `NSWindow`s
  (approved mechanism disclosure, same footing as D81 — nothing traced in `GSXBoloController.m`
  depends on simultaneous multi-window visibility or cross-window interaction). `NewGameView`'s
  Host/Join tabs shipped as placeholders; a temporary, explicitly-commented "Play Demo" button kept
  Wave 7.3's already-PARITY-passed gameplay loop reachable from the shipped UI during the B.1→
  B.2/B.3 gap (approved, tracked for removal by whichever of B.2/B.3 landed second). `RenderPreview`
  hit a distinct `PreviewsFoundationHost` toolchain timeout, disclosed rather than glossed over;
  substituted an `nm`-on-artifact symbol check for a pure-layout diff with no custom drawing to
  verify. Tests 639→639. ✅
- **B.2 — host panel, narrowed (D94)** (`ea089d9`+`4c9e4ba`, PARITY PASS `54f87f7`). The pre-brief
  itself caught that "wired to `HostSession`" as originally proposed would have silently absorbed a
  real, undesigned host-network-engine unit into a sub-wave sized for form-wiring — **D94**
  confirmed the narrow reading (map picker + `decodeBMap` + host settings form feeding a real
  single-process `GameSession`, zero `HostListener`/`HostSessionTable` calls) and split the engine
  out to a new **B.5**. `HostGameView` added an empty-starts map-rejection guard, confirmed
  load-bearing rather than defensive dead code (`Spawn.swift`'s `state.starts[start]` indexes
  unconditionally, would crash on first death), and reused D88 §4's respawn machinery
  (`respawnCounter = respawnTicks - 1`) rather than inventing new spawn-placement logic. The
  decode→merge→spawn path was verified through one real `runTick`, independently re-verified by
  PARITY with different input values than Implementer's own script. Tests 639→639. ✅
- **B.5a — accept/join wiring** (`01a2d89`+`a00ad0a`, PARITY PASS `3e18775`), the low-risk half of
  B.5 per **D95**'s split. **D95** also ruled B.5's cross-source concurrency architecture: a single
  serialized consumer over a merged event stream, generalizing `JoinAcceptSerializer`'s already-
  trusted one-at-a-time pattern, chosen over actor-isolation's reentrancy hazard — same footing as
  D81's explicit-over-implicit-mechanism tradeoff. `runHostAcceptLoop`'s single `for await` over
  `HostListener.connections` needed no new concurrency design (an `AsyncStream` is single-consumer
  by construction) — but PARITY didn't accept that reasoning alone, building two complementary
  tests against the real exported function (20 genuinely concurrent real loopback connections; a
  stalled connection blocking 10 ready ones behind it) plus a **negative control** (temporarily
  reintroducing a bare `Task{}` wrap around the mutating call, confirming the test fails exactly as
  it should, then reverting byte-identical) — the standard this span generalized to every later
  concurrency claim. One self-caught test-harness timing bug (an outcome is only recorded after
  `table.setConnection`'s trailing `await`, not at reply-byte-received). Tests 639→641 (+2). ✅
- **B.3 — join panel** (`9a03287`+`e9a981e`; PARITY's first audit found a real finding, `d9f1cbc`+
  `909ea0f` fix, re-audit PASS `bcdc9ca`). `JoinProgress` modeled 5 states, not the reference's 6
  (`RESOLVING`/`CONNECTING` collapse — no hook exists between them in `withNetworkConnection`), and
  3, not the hoped-for 5, new `JoinClientError` network-error cases — the reference's 8-network-
  error/3-way-DNS taxonomy doesn't survive translation to `NWError` intact, resolved empirically
  rather than guessed, and reported plainly whichever way it landed. Found and fixed a real
  production bug along the way: a `withThrowingTaskGroup`-based connect-timeout race doesn't
  actually cut short (Swift awaits every child task regardless of cancellation); replaced with two
  unstructured `Task`s racing to resume one `CheckedContinuation` via a `ResumeOnce` guard, later
  stress-tested by PARITY with 160 real racing iterations, zero double-resumes. **D97 — real
  finding, required before close:** PARITY ran the claimed instant-`.connectionRefused`-on-
  closed-port scenario 19 independent times against the real, unmodified `joinClient` and got
  `.timedOut` every time — root-caused to `NWConnection` treating a refused connection as the
  retryable `.waiting` state, never `.failed`, on this OS/SDK, so only `joinClient`'s own explicit
  timeout ever fires; the header's original "sandboxing difference between a standalone binary and
  `swift test`" story did not hold up. Fixed by rewriting the header to state the real,
  root-caused mechanism and explicitly marking the old story withdrawn (visible, not silently
  deleted) — corroborated by three independent measurements agreeing (PARITY's 19, Implementer's
  re-probe of 5, PARITY's fresh 5 against a previously-unused port). Tests 641→644 (+3). ✅
- **B.5b — tick timer, dgram relay, host's own outbound `CLUpdate`** (`d24cdd1`+`c18d25f`, PARITY
  audit `f28b64a`; D98 fix `07801ee`+`8713861`, re-audit found a further off-by-one; D99 fix
  `7680b9f`+`5055634`, re-audit PASS `9e72569`). **D96** split what the pre-plan still called
  "B.5b" into this sub-wave (single-linear-consumer sources only: accept loop, dgram relay, tick
  timer) and a new **B.5c** (TCP `CL*` message dispatch across N connected players, the genuinely
  split-phase concurrency problem D95's design exists to solve) — the third time in one milestone
  this exact "hidden scope surfaces only at real pre-brief depth" pattern recurred (D94 for B.2,
  D95 for B.5 itself, now this for B.5b), explicitly logged as the pre-brief discipline working as
  intended, not a process failure. A pre-brief wording ambiguity ("three sources, no two ever
  concurrently") was self-corrected before any code was written to the actual required design: one
  merged `AsyncStream`/event enum, three I/O-only producers, exactly one consumer `Task`
  (`HostGameEngine`) as sole mutator of `state` — generalizing D95's two-branch architecture to
  three sources, not a new mechanism. Wired 7 of `runTick`'s 16 remaining pass-through callbacks to
  real `SR*` broadcasts (`onPause`/`onTimeLimitWarning`/`onBaseControlWarning`/`onCoolPill`/
  `onReplenishBase`/`onGrow`/`onShouldBroadcastDropPill`); added `assembleClUpdate` (mirroring
  `assembleBoloPreamble`'s caller-supplies-`seq` convention) and `HostSessionTable.sendDgram` (the
  missing UDP counterpart of the existing TCP-only `send`/`sendToAll`/`sendToMask`). PARITY proved
  the single-mutator claim with a stalled-connection stress test (30-packet dgram flood + 30 tick
  fires against a deliberately-blocked accept case, zero leaked traffic during the stall) plus a
  negative control (a temporary `Task{}`-wrapped edit leaked 38 datagrams during the same stall;
  reverted byte-identical). **D98 — required before close:** the `CLUpdate` broadcast section
  never checked `state.serverPauseTicks`/`clientPauseDisplaySeconds`/time-limit the way
  `client.c:430`'s `runclient()` short-circuits its *entire* body — a gap between two modules that
  deliberately split `seq`/cadence ownership back in Wave 6.1 (`RunTick.swift`'s own header
  disclaims it); fixed with a guard, with base-control-reached explicitly deferred (not guessed at)
  since `client.basecontrolreached` is a genuine one-way latch (`client.c:238,430,3130`) while the
  port's mirroring server-side counter is resettable (`server.c:1144,1170`) — two different C-side
  reset semantics, confirmed by reading both directly. **D99 — a further, real off-by-one PARITY's
  own re-audit caught and proved with a built-then-reverted boundary test:** D98's guard used `>=`
  where `RunTick.swift:104`'s own freeze condition is a two-phase `==`/`>` split, so the guard
  suppressed the broadcast for the tick that legitimately still runs a full simulation; fixed to
  `>`, with a boundary-seeded regression test (seeded at `limitTicks - 5` so the transition tick
  lands on a `% 5 == 0` cadence slot). Two test-harness-only timeout bugs (not production defects)
  surfaced and were fixed along the way, both the same shape: a `withTaskGroup`/`cancelAll()` (or
  equivalent) helper that never actually interrupts an in-flight `NWConnection.receiveMessage` —
  fixed both times with an explicit `connection.cancel()` on timeout, flagged as a standing trap
  for any future "read with timeout" helper in this codebase. Tests 644→647→649→650 (+6 net across
  the sub-wave). ✅
- **B.5c — pre-briefed within this archived range; not GO'd or coded here.** Traced
  `receiveAndDispatchOneHostMessage`'s already-built dispatch logic (Wave 6.4b/6.6) and proposed
  splitting it into an I/O-only byte-read half and a pure decode/dispatch half, plus a
  **dynamically-spawned per-connection producer Task** — a genuine generalization of D95/D96's
  three-fixed-producers design to "three fixed producers plus N dynamic ones," flagged rather than
  assumed in-bounds. Of the 9 `runTick` callbacks a prior B.5b-review ruling had said would "fold
  into B.5c," this pre-brief traced every actual call site and found 5 need no wiring at all (4 —
  `onExplosion`/`onSuperboom`/`onSmallboom`/`onSpawn` — are local-player-only animation triggers; 1,
  `onPlayerLagStatusChanged`, is a local UI callback with no wire counterpart in the reference), 1
  (`onPlayerDisconnected`) is small and proposed for B.5c itself, and 3
  (`onMineExplosion`/`onSuperboomTerrain`/`onDropPills`) are a real, older, pre-existing gap —
  disclosed since Wave 5.5a/`MineChain.swift`'s own header — requiring a causer-parameter signature
  change across three already-shipped, already-tested files with no `SR*` broadcast mapping ever
  decided at any layer. Recommended splitting that gap out as a new **B.5d** rather than folding it
  in or attempting the signature-changing refactor unilaterally. **D100's ruling on this split
  (approving the dynamic-producer extension, creating B.5d), B.5c's coding GO, and everything from
  there onward, live in the active log, not this archive.**

**Cross-cutting, this span:** D28's coverage discipline held throughout (639→641→644→647→649→650,
every delta an addition, several backed by negative-control-validated regression tests). The
B.5a/B.5b concurrency-proof standard — a built stress test plus a negative control that fails
exactly as expected before being reverted, `git diff`-confirmed byte-identical — became this span's
standing bar for any single-mutator/serialization claim, extending Wave 7's execution-verification
discipline into concurrency territory for the first time in this project. Two new toolchain-
instability surfaces were logged into project memory alongside the existing Run-Script-hang/
Previews-timeout/stale-lock trio: a stale multi-hour `SWBBuildService`/`Xcode Service` process pair
holding `build.db`'s lock (killable, not a code defect), and this Xcode 27 beta's default
batch-mode `swift build`/`swift test` being unreliable (`-Xswiftc -disable-batch-mode` is the
workaround). One process incident (the B.0 PARITY subagent self-issuing a `[PLANNER]`-tagged GO)
was logged plainly and corrected going forward without rework, since the substance was
independently confirmed correct on review. This is also the third and fourth recurrence of the
"a sub-wave's own pre-brief finds real, previously-unnamed hidden scope and splits rather than
silently absorbs it" pattern first established at D22/D43/D60 (D94 for B.2, D95 for B.5, D96 for
B.5b, and B.5c's own pre-brief flagging B.5d) — explicitly recorded as the discipline working as
intended, not a process failure. Full uncompressed entries (every pre-brief, completion report,
PARITY audit/re-audit, and PLANNER ruling in this span, including D94–D99's full text and the B.0
process-incident thread) preserved in git history per D28.

## D100 through B.7's close (Milestone B: B.5c's coding GO through B.7 CLOSED)

**B.5c — D100 coding GO'd, items 1-5 landed (`8ca6567`), D101 fix (`47e9c09`), CLOSED (D102
tracked, not blocking; PARITY audit found no fatal issues).** D100 approved the
dynamic per-connection producer Task generalizing D95/D96's three-fixed-producers architecture
("exactly one consumer mutates `state`" holds regardless of producer count) and split the
9-callback mine-chain broadcast question into new B.5d rather than folding it in blind. Landed:
`HostSession.swift`'s dispatch split into I/O-only `receiveOneHostMessageBytes` + pure
`dispatchHostMessage`; the dynamic producer Task; `onPlayerDisconnected` wiring; 5 callbacks
confirmed correctly unwired (local-only animation triggers). **D101** — a real pre-existing bug
found along the way: `HostListener.swift`'s `runJoinHandshake` `.accepted`-branch `catch` on a
preamble/map-send failure called `table.disconnect` but never reverted `applyJoin`'s
`used/connected` flags, permanently leaking a `GameState` player slot. Fixed with `removePlayer`
(resets `connected`, preserves `used` for rejoin-eligibility, no broadcast since `SRPlayerJoin`
never fired) — same shape as D77's precedent for a pre-existing bug only reachable once new work
exercises the path. PARITY independently re-derived both the slot-leak fix and the dispatch split
(diff-level behavior check, not just re-running tests), found one further real gap:
`HostGameEngine.stop()` never tears down already-joined players' `NWConnection`s/producer Tasks
(proved with a built scratch test: send succeeds after `stop()` when it should fail). **D102**
tracked this as non-blocking (no production caller of `stop()` yet) rather than reopening B.5c;
revisit when a real caller lands. Tests 650→655.

**B.5d — pre-brief corrected D100's causer-threading premise (direct `server.c` reads showed
`explosionat()`/`superboomat()` need no signature change), GO'd as D103, landed (`35e2320`),
CLOSED (PARITY PASS `aaf2229`).** The real gap was only 2 missing call sites
(`onMineExplosion`/`onSuperboomTerrain`) inside functions that already had what they needed, plus
a genuine design question (separate parameters for the client-role notify vs. server-role
broadcast, since C itself draws that line — `client.c`'s `smallboom()`/`superboom()` never
broadcast, only server-role `explosionat()`/`superboomat()` do) — approved. During coding, scope
corrected *down* further: `RecvCL.swift` was already broadcasting correctly since Wave 6.6; the
only real gap was `chain()`/`flood()` (`MineChain.swift`) having no broadcast hook at all. Also
folded in (per D103) the `onDropPills`→`onShouldBroadcastDropPill` direct-call refactor — a bigger
mechanical footprint (13 files) than scoped but a real behavior fix: `dropPills`'s spiral-search
pill-scatter placement had never actually run in production (all 5 fire sites were bare
data-only closure calls with no `state` access), plus a dead-end no-op `CLDispatchCallbacks`
field in `HostSession.swift`. PARITY independently confirmed via negative control that the
pre-fix behavior really was dead code, spot-checked/then fully swept (16 of 16, not a sample) all
`explosionAt`/`superboomAt` call sites for broadcast coverage. `killSquareBuilder`/
`killPointBuilder`'s `state.localPlayer`-only scoping (found investigating the same code) split
out to new **B.5e**. Tests 655→660.

**B.6 (tracker/UPnP UI wiring, D104/D105 split from B.4's long-unruled disposition) — landed
(`a7c9392`), CLOSED (PARITY PASS `9365c7f`).** `TrackerBrowser`/`PortMapping` primitives were
already fully built/tested; sizing came out to ~60-100 lines across 2 files, small enough for a
direct coding GO with no separate pre-brief. Correction found while implementing: the host side
has zero live networking of any kind today (`HostGameView.startHosting()` just assembles a local
`GameState`) — hosting toggles built inert-but-disclosed, reusing `portText`'s existing D94
`.help` precedent rather than falsely wiring a live tracker/UPnP call for a host with no open
socket. `JoinGameView`'s browse list is fully real (wired to `listTrackerGames`). PARITY confirmed
both sides directly (grep for zero live host-side calls; traced the join-side call into
`TrackerBrowser.swift`; verified the default tracker hostname against the reference's own
`GSTrackerString` plist value).

**B.5e (`killSquareBuilder`/`killPointBuilder`'s local-only scoping) — two-stage pre-brief, D105/**
**D106, landed (`b0d2791`), CLOSED (PARITY PASS `55513aa`).** First pass found the fix isn't a
small generalization: `killBuilder` reads 4 fields living on `GameState.local: LocalPlayerState`,
a **singleton**, not per-player. Deeper pre-brief (D105) found the real count is **6 fields, not
4** (`mines`/`trees` also touched by `BuilderTick.swift`), ~112 production call sites concentrated
in `BuilderTick.swift`. Also surfaced, same root cause, a genuine **already-shipped multiplayer
bug**: `builderTick` already ran in a per-player loop but every iteration clobbered the same
singleton fields — any game with 2+ players building simultaneously stomped each other's task
state every tick. D106 approved the full migration (6 fields moved to `PlayerState`, 7-step
build-green ordering: add fields → migrate `BuilderTick.swift` → migrate ~13 mechanical sites →
remove fields from `LocalPlayerState` as forcing function → fix test fallout (8 files) → the
actual `killSquareBuilder`/`killPointBuilder` generalization → regression tests). Migration also
fixed the clobbering bug for free, and removed two `returnTick` gates that PARITY confirmed (by
reading `client.c:4934-5000` directly) were real in the C reference but only because C's fields
were process-singletons — the gate's purpose was moot post-migration, and keeping it would have
reproduced the exact stuck-remote-builder bug. PARITY confirmed migration exhaustiveness by grep
(one harmless historical comment hit, no live code), confirmed the loop-over-connected-players
generalization is the correct mapping of the reference's actual per-process design (not a
deviation — `client.c:6999-7045` only checks `client.player` because every real client is its own
process), and built its own independent negative controls on both the kill-fix and the gate
removal. Tests 660→662.

**B.7 (wire a real UI path to `HostGameEngine` — D107/D108) — landed (`f4b8efc`), CLOSED (PARITY**
**PASS `6b31ba1`).** D107: reviewing B.6 surfaced that no UI path anywhere in the app actually
starts a `HostGameEngine` — "Start Hosting" only ever assembled a local `GameState`; B.5a-B.5e's
engine work had no live caller. Split to B.7. Pre-brief traced `HostGameEngine`'s fully
self-driving `init`/`start()`/`stop()` contract and flagged that wiring it in creates a genuine
tick-conflict (two independent tickers would advance the same `GameState` — `GameSession`'s own
timer and the engine's own `DispatchSourceTimer`) plus a symmetric join-side gap (no live
join-side receive loop exists either — `GameSession` runs a fully disconnected local sandbox after
the initial handshake). D108 approved: (1) bypass `GameSession`'s own timer entirely on the host
path, render off `HostGameEngine.onTickRendered`'s per-tick value-type snapshot; (2) fold D102's
`stop()`-teardown fix into B.7 (direct consequence of finally giving `stop()` a real caller — now
`shutdown()` disconnects every connected slot, letting each producer Task exit via its existing
tested path); (3) split the join-side symmetric gap into new **B.8**, not B.7's problem. While
designing the callback wiring, Implementer caught and disclosed (before any diagnostic forced it)
a second real race: host-side local keyboard input would otherwise need to mutate
`HostGameEngine.state` directly from the main thread while the consumer Task might be mid-`runTick`
— fixed with two new event cases/public methods reusing the existing merged-stream mechanism, not
a new one. PARITY proved the tick-conflict resolution and local-input exclusivity to a stronger
standard than asked — an exhaustive grep of every mutating access to `state` in
`HostGameEngine.swift` (all 8 `&state` hits confined to `handle(_:)`/`tick()`), not spot-checks or
scenario tests — plus its own independent negative control on the `shutdown()` fix and confirmation
of its real app-side caller (`GameView.swift`'s Quit-to-Menu/`onDisappear`). Tests 662→665.

**Cross-cutting, this span:** the "hidden scope surfaces only at real pre-brief depth, split
rather than silently absorb/narrow" pattern recurred repeatedly and by design — D100→B.5d,
B.5c-pre-brief→B.5d, D104→B.5e's own 4-vs-6-field correction, D107 (B.6 review surfaces B.7),
B.7-pre-brief→B.8 — every one flagged live and re-ruled rather than guessed at. D28's coverage
discipline held throughout (650→655→660→662→665, net +15, every delta backed by a
negative-controlled regression test, several with PARITY building its own independent negative
control rather than trusting Implementer's). B.4's long-unruled disposition (open since D92/D94)
was finally resolved by folding its sizing question into B.5e's own pre-brief (D104) and splitting
it out as B.6. Milestone B status at the close of this span: B.0-B.3, B.5a-B.5e, B.6, B.7 all
closed PARITY PASS; only **B.8** (join-side symmetric network gap) remains open, carried into the
active log. Full uncompressed entries (every pre-brief, completion report, PARITY audit, and
PLANNER ruling in this span, D100 through B.7's close) preserved in git history per D28.

## D109 through Milestone C's full close (Milestone B's final loose fixes, B.8, and all of Milestone C's D118-batch: C.0/C.5/C.3)

**D109-D112 (local-play fallback + three live-found fixes, then a fourth crash fix) — landed**
**(`f76191f`/`afd3f8c`, `bbe039d`/`a708583`/`c868bbe`, `78df7a8`/`15b6157`), all CLOSED (PARITY**
**PASS `f48314d`, `ad7e8f0`).** Real environment bug (this machine's `Network.framework`/
`NWListener` fails EINVAL on every port — a live macOS 27 beta regression, not a code defect,
independently reproduced via bare standalone binaries), which combined with B.7 removing the old
no-network "Play Demo" scaffolding meant no gameplay was reachable at all. D109 approved a
disclosed fallback: on listener-construction failure, `HostGameView.startHosting()` routes to new
`AppScreen.hostingFallback(GameState)` — confirmed by PARITY to be the exact same `GameView`
local-only initializer as `.playing`, plus one optional `notice: String?` for a visible banner (not
a third mechanism). Three more bugs found live while Jerod actually played: (1) `bbe039d` — dead
keyboard input from a `makeFirstResponder` race on window-key timing, fixed with a deferred runloop
turn + `mouseDown` reclaim; (2) `a708583`/D110 — camera opened at map `(0,0)` instead of the local
player's spawn, fixed with a one-shot `centerOnLocalPlayerSpawn()`; (3) `c868bbe`/D111 — a Wave-7.0
`BoloGlyphsCore` bug where boat-mode players wrongly got the destroyed-tank wreck glyph, root-caused
against `GSBoloView.m:295-337` directly (no destroyed-tank sprite concept exists in the reference at
all for any of the six tank rows) and fixed by making `destroyed` always `false` for the tank
range — leaving boat/tank visually identical (accepted as a disclosed placeholder-art
simplification, no ticket) and the `destroyed` parameter/`drawTank` branch fully dead code (flagged
as a cleanup candidate, not fixed). **D112** — a fourth live crash (`Index out of range` on any
neutral pillbox's return-fire hit): `ShellTick.swift`'s `shellCollisionTest` indexed
`state.players[Int(shell.owner)]` in three places, and `Shell.owner` can legitimately be
`playerNeutral` (0xff) for an unowned pill's shot — root-caused against `client.c:5423` (the
reference attributes the hit to the local client's own index, never the shooter) and fixed by
threading each call's already-in-scope `player` parameter through instead; the file's own wrong
header comment was corrected in place. All four PARITY-audited (two batches) with no defects found;
665→666 tests. Two live-reported, unconfirmed issues (turning direction feeling backwards,
acceleration not matching heading) were traced against the code/D70's regression coverage, found
nothing wrong on paper, and were correctly left open pending Jerod's own repro rather than guessed
at blind.

**B.8 (join-side live network loop, D113-D117) — landed (`106946c`+`4b309e6`+`058d23f`), CLOSED**
**(PARITY PASS `53ff764`).** A five-finding pre-brief-to-landing thread, each finding held and
routed rather than guessed past: (1) D113 approved moving the handshake transport into `TCPSession`
itself (design (a)) rather than reusing `withNetworkConnection`'s auto-closing scope, and split
client-side prediction out to new B.9; (2) **D114 corrected D113's framing** — the host never
corrects a client's self-reported position (each client is authoritative for its own tank), so
running the join player's own `tankMoveTick`/`tankLocalTick` locally is *required* B.8 scope, not
deferrable, and B.9 re-scoped from "prediction/reconciliation" to "remote-tank smoothing" (visual
only); (3) D115 approved folding the per-player seq/lastUpdate table into `UDPSession` itself
(single-owner-mechanism principle, same as D95/96/D102); (4) **D116 narrowed B.8 again** —
`TankLocalTick.swift`'s shared-object branches (pills/bases/terrain) directly mutate state in a way
a real join client's protocol never does locally (no outbound `sendCl*`-equivalent exists in
`BoloNet` at all), so B.8's final scope became `tankMoveTick`-only local physics + `SR*`-relay
visibility of everything else, with join-side building/mining/pill-grabbing split to new **B.10**;
(5) Implementer self-caught a real concurrency bug before committing — an `inout state` copy
spanning a network `await` compiles clean but reintroduces the exact race `HostGameEngine`'s
merged-stream architecture (D95/96) exists to prevent, since `@MainActor` only serializes
*synchronous* code. **D117 approved splitting `TCPSession.receiveAndDispatchOne`/
`UDPSession.receiveAndApply` into async raw-bytes-only + synchronous decode+apply halves**,
mirroring `HostGameEngine`'s own producer/consumer split exactly. Landed as a proper
`AsyncStream`-based merged-event-stream single consumer (3 I/O-only producers: tick timer, TCP raw
receive, UDP raw receive; exactly one consumer touches `state`). PARITY re-derived every claim
directly (no `self.state` access in either producer body; both transport splits confirmed
behavior-preserving thin wrappers; `tankMoveTick`-only scope confirmed by grep — zero
`tankLocalTick`/`shellTick`/`builderTick` call sites; ~10Hz outbound cadence confirmed matching
`HostGameEngine`'s own `seq % 5 == 0` gate and `client.c`'s `sendclupdate()`). Two disclosed gaps
(death-timer pill-drop desync, dead shoot/mine input) correctly left for B.10, not new findings.
671 tests. **Never hand-tested against a real second peer** — this machine's `NWListener` EINVAL
bug (same as D109) blocks any real host↔join test locally; flagged repeatedly for Jerod, not a
PARITY blocker. Jerod's plan: a macOS VM under Parallels for a genuinely separate network stack.

**D118 — Milestone C started early (Jerod's direct override of D93's alphabetical sequencing),**
**three parallel pre-briefs GO'd: C.0 (HUD status panel + kick/ban), C.5 (preferences shell), and**
**C.3's Q28 sound-sourcing research.** B.9/B.10 (Milestone B's last two loose ends, both
non-blocking) stayed open, not abandoned. C.1/C.2/C.4 held back (real risk / disclosed
fog-of-war divergence / needs a new `GameState` field, respectively).

**C.0 (HUD status panel + host-only kick/ban) — D119 coding GO'd (folding in a small**
**`submitKickPlayer`/`submitBanPlayer` prerequisite), landed, CLOSED (PARITY PASS).** Pre-brief
confirmed the model (`PlayerState`/`testAlliance`/`hostKickPlayer`/`hostBanPlayer`) was already
fully sufficient for the reference's three-way friendly/allied/hostile status-icon switch
(`GSXBoloController.m:2103-2419`); the one real gap was that `HostGameEngine`'s single-consumer
design had no safe write-entry-point for a kick/ban button, fixed with two new
`submitKickPlayer(_:)`/`submitBanPlayer(_:)` methods mirroring the existing `submitLocalInputChange`
pattern exactly. Shipped `PlayerStatusView.swift` (player + pill/base ownership rows, host-only
Kick/Ban), a narrow `GameSession.canKickBan`/`kickPlayer`/`banPlayer` passthrough (`hostEngine`
stayed `private`, no widening), and a "Status" sheet button in `GameView`'s top bar. Self-caught
test bug: the first draft's kick/ban tests passed vacuously (join landed in slot 0, not the
asserted slot 1) because the default test helper left slot 0 unused — fixed by seeding it, PARITY
independently re-traced and confirmed the fix makes the assertions genuinely non-vacuous. 490 tests
(+2).

**C.5 (preferences shell) — D120 coding GO'd exactly as proposed, landed, CLOSED (PARITY PASS).**
`@AppStorage` over a custom persistence model (reuse-over-invention, same bias as D67/D72), four
scalar fields (`GSPlayerNameString`/`GSTrackerString`/`GSHostPortNumber`/`GSMuteBool`) matching
already-hardcoded literals in `HostGameView`/`JoinGameView` 1:1, wired via a native SwiftUI
`Settings{}` scene. PARITY independently verified all four key names character-for-character
against `Reference/c/en.lproj/DefaultPreferences.plist` directly, and confirmed `HostGameView`/
`JoinGameView`'s new `init`s genuinely read the same `UserDefaults.standard` store `PreferencesView`
writes to, not a disconnected copy. No new `BoloKit`/`BoloNet` surface, no test-count change
(matching B.6's own no-test precedent for pure app-target SwiftUI work).

**C.3 (procedural sound synthesis, Q28 resolved at D121, coding GO'd at D122) — landed (`2662d5e`),**
**CLOSED (PARITY PASS).** Q28 (sound asset-sourcing strategy): resolved as procedural synthesis,
mirroring D67's glyph-generation precedent exactly — all 24 of the reference's named `.aiff`
effects (`GSXBoloController.m:357-490`) are short one-shot noise/tone/click/chime effects, no
ambient/loop/vocal content, so the same "nothing here is actual text"-shaped reasoning applies; a
case-by-case fallback to a licensed library was approved if a specific effect's synthesized quality
fails Jerod's ear (not an all-or-nothing re-decision). Coding pre-brief mirrored `BoloGlyphsCore`/
`BoloGlyphs`'s exact two-target shape: new `BoloSoundsCore`/`BoloSounds` targets, DSP primitives
(`whiteNoise` fixed-seed LCG, `adEnvelope`, `toneSweep`, single-pole IIR `lowpass`), a 14-entry
parameter table (10 more `far*` names derived by shared lowpass filtering, not independently
designed), `AVAudioFile`-based AIFF encoding (44.1kHz/mono/16-bit/big-endian). One open pre-brief
question — the reference has 14 near names but only 10 far names, with `tankshot`/`pillshot` both
existing but only one `fshot` — **resolved at D122 by direct re-check of `GSXBoloController.m`'s
switch (lines 3667-3731): `fshot` genuinely is shared between both**, no `fpillshot` was ever
modeled. Landed with 11 new tests (675→686, later corrected to 684 total after reconciling with
concurrent C.0/C.3 landings), determinism-focused (perceptual sound quality explicitly left to
Jerod's ear, not tested, per D121). Two disclosed deviations: (1) `AVAudioFile` writes `AIFC`, not
true `AIFF` container labeling (ruled acceptable/cosmetic at D124 — same uncompressed PCM data,
plays identically); (2) Xcode Run Script wiring deliberately deferred to avoid a `.xcodeproj` edit
colliding with concurrent C.0/C.5 sessions, then completed separately (`16d3091`) once it was safe
— verified by actually finding all 24 `.aiff` files in the built product's `Resources`, not just a
green build log. **PARITY gave this the deepest treatment of the three** — actually built and ran
the `BoloSounds` executable against a scratch directory and inspected output with `afinfo`, not
just reading tests — and caught one bookkeeping-only correction: D122/the completion report's "23
unique buffers" framing was imprecise (all 24 dictionary entries are independently-computed,
content-unique buffers via `md5`; there's no missing 24th buffer, just no separate `fpillshot`
dictionary *key*, which is correct per D122). No functional defect; D122's text amended with a dated
correction pointer rather than rewritten.

**D123/D124 — process ruling on a real, recurring git-index hazard, occurring 4-for-4 times in one**
**evening.** Three independent Implementer-role sessions running truly concurrent `git add`/`git
commit` against one *shared* working tree (not separate worktrees) each hit the same race — one
session's in-flight index state getting swept into another's commit — self-caught and fixed live
every time (`git reset --soft HEAD~1` + selective `git restore --staged`, re-verified via
`git show --stat`) with **zero data loss** in every occurrence, only some commit-message
misattribution (C.0's actual diff ended up inside a commit labeled for C.3, cross-referenced and
confirmed by content, not message, before crediting either sub-wave). **D123: going forward,**
**genuinely parallel IMPLEMENTER-role coding tracks use separate git worktrees**, not one shared
tree — a going-forward policy, not remediation. A fourth occurrence (this time PLANNER's own doc
edit colliding with an IMPLEMENTER commit) prompted a scope clarification (no new D-number): D123's
worktree mandate applies specifically to parallel *coding* tracks, not the ordinary
PLANNER-writes-docs/IMPLEMENTER-commits-code overlap this project runs on constantly — the existing
discipline (check `git status` immediately before every commit, explicit pathspec, never bare
commit/`-A`) already caught all four instances cleanly, no strengthening needed.

**Milestone status at the close of this span:** Milestone B: B.0-B.3, B.5a-B.5e, B.6, B.7, B.8 all
closed PARITY PASS; **B.9** (remote-tank smoothing) and **B.10** (join client's outbound `CL*`
protocol) remain open, deliberately deferred per D118. Milestone C: **C.0, C.5, C.3 closed PARITY
PASS**; **C.1** (key-remap, real risk), **C.2** (alliance panel, disclosed fog-of-war divergence),
**C.4** (messages panel, needs a new `GameState` field) not yet started. Full uncompressed entries
(every pre-brief, completion report, PARITY audit, and PLANNER ruling in this span, D109 through
Milestone C's full close) preserved in git history per D28.
