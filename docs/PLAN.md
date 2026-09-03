# Plan: Swift port of XBolo — a faithful, distributable Mac Bolo

> **Convention:** every question gets a permanent ID, never reused or renumbered. Answered
> questions move to the Decisions log keeping their ID. Questions live only in these two
> sections — never in prose elsewhere.
>
> This document is the durable home for the plan (see D17) — it lives in the repo, not just in
> assistant-side session state, so it survives a dropped session. This doc + `docs/AGENT_NOTES.md`
> are the two common references for all three roles — status and decisions here, chronological
> log there. Role-specific instructions live separately, one file per role, and deliberately don't
> restate anything from either of these two: `CLAUDE.md` (IMPLEMENTER), `docs/PARITY.md`
> (PARITY), `docs/PLANNER.md` (PLANNER).

## Open questions

| ID | Question | Blocks | Priority |
| --- | --- | --- | --- |
| **Q10** | Keep the C code in-tree permanently as a test oracle, or delete it once the port completes? Recommend keeping it until Phase 5 ends, then removing it (it stays in git history) | Phase 6 | Low |
| **Q14** | `explosions`-list attribution semantics: C has two different, irreconcilable rules for which player's `explosions` list a given entry lands in (shell-list owner for the range-expiry phase; hardcoded `client.player` — the local process's own identity, meaningless in a merged simulation — for collision/tank-hit phases). IMPLEMENTER's uniform `state.players[shell.owner].explosions` choice is internally consistent but matches neither C rule exactly. PARITY found no mechanical gameplay consumer of this list today (only `explosionlogic`'s cosmetic counter-decay-and-remove) — if that holds, this is a Wave-6 UI-layer decision, not a Phase-3 parity gate. Needs a ruling (or an explicit defer-to-Wave-6 note) before Wave 6 starts; does not block 5.3b. | Wave 6 | Medium |
| **Q18** | `docs/PLAN.md`'s phase order (Phase 2 art before Phase 3 port) no longer matches reality — Phase 3 ran to completion and Phase 2 never started. Phase 2's verify step calls for a git-history rewrite to strip original assets, which only gets more expensive with every commit made before it happens. No specific resequencing proposed yet, just flagging the cost curve. | None code-blocking; resequencing decision | Low |
| **Q22** | Runtime question: does the port need a standalone dedicated/headless server binary, or does the future "Bolo 2026" app hosting in-process (per the original's own "Host a Game" panel) cover it? Research on other Bolo implementations logged in `docs/notes/HOSTMODELS.md`: our own oracle (xbolo) ships BOTH — the Cocoa client hosts in-process (`GSXBoloController.m`) AND a separate headless `Dedicated Host` CLI binary exists, both thin wrappers over the same `server.c`. WinBolo/LinBolo show the same pattern (dedicated `WinBoloDS` predates it, client-hosting added in v1.14, both kept). `BoloKit`/`BoloNet`'s existing headless design makes either or both cheap — no architecture is forced. Not code-blocking for Wave 6.2-6.5; relevant once session-management (6.3)/transport (6.4) land or the app-UI phase starts. | None code-blocking; product/scope decision for the app-UI phase and/or a possible dedicated-host companion target | Medium |

## Decisions log

Closed questions, newest last. IDs are permanent.

| ID | Question | Decision |
| --- | --- | --- |
| **D1** | Engine / platform | Native macOS, not Godot |
| **D2** | Build from scratch or fork? | ~~Fork and drive to fidelity~~ → **superseded by D13.** Now: Swift port using xbolo as reference implementation |
| **D3** | Fidelity target version | Mac Bolo **0.99.7bv** — the replay-log tooling decodes this version |
| **D4** | Network interop | Self-contained, you and friends. No protocol archaeology, no WinBolo interop |
| **D5** | Copyrighted original assets | Recreate clean-room replacements before any distribution |
| **D6** | Who draws the art | ~~You draw~~ → **superseded by D10** (generated glyphs, nobody draws) |
| **D7** | Sprite basis | Unicode / ASCII glyphs |
| **D8** | Upstream relationship | ~~Contribute fixes back~~ → **revised by D13.** Swift patches can't go to a C project. Contribute *bug reports and fidelity findings* instead |
| **D9** | Source of fidelity data | **No existing logs.** Emulation is the sole source; the measurement rig is its own gating phase |
| **D10** | Art style | **ASCII / unicode glyphs for all graphics.** Not a placeholder — this *is* the art |
| **D11** | Upstream courtesy | Open an issue flagging intent, framed on the learning goals (Xcode, AI / Apple Intelligence, networking). **Draft reviewed before posting** |
| **D12** | Project home | Take over the blank Xcode project slot; delete the SwiftUI stub (verified boilerplate) |
| **D13** | Language | **Full port to Swift, simulation included.** Legally clean: xbolo is MIT, which permits derivatives provided the original copyright notice is retained |
| **D14** | Location | Move out of Xcode's `UntitledProjects` scratch area to `~/Developer/XBolo` |
| **D15** | Name | Keep `XBolo` for now; revisit if/when a hard fork is declared |
| **D16** | Minimum macOS target (was Q9) | **macOS 26+** — required for FoundationModels (Apple Intelligence learning goal), and the dev machine is already on 27. Implemented: `Package.swift:7` declares `.macOS(.v26)` |
| **D17** | Where the plan document lives | **`docs/PLAN.md`, version-controlled in the repo** — supersedes the Xcode assistant's session-local plans directory, which is not durable across dropped sessions |
| **D18** | Numeric representation | **Use 32-bit floats (`Float` in Swift) for position, physics, and trig.** The reference C code directly uses float values (e.g., `Vec2f tank`, `Vec2f builder`) and trig/sqrt operations. Custom integer/fixed-point math would break bit-identical differential testing. |
| **D19** | Package manifest tools version | **Align `Package.swift` tools version with platform targets.** Tools version `6.0` does not support `.macOS(.v26)` (introduced in PackageDescription 6.2). Update `Package.swift` to declare tools-version `6.4` to support current system SDK features correctly. |
| **D20** | Test Harness & Socket Coupling | **Isolate and mock simulation code for unit test bridging.** The C code in `client.c` and `server.c` is tightly coupled with low-level POSIX sockets and pipe multiplexing. We must isolate pure state logic or wrap C entry points to avoid launching network services in differential tests. |
| **D21** | Project Renaming (was Q11) | **Adopt the engine-first architecture.** Rename the core simulation framework to `BoloKit` (supporting future expansion such as mods, plugins, and AI agents), and name the primary application `Bolo 2026`. |
| **D22** | Q12 resolution — mine-chain/flood + pill-scatter subsystem | **Split Wave 5.5 into two sub-waves rather than folding silently.** 5.5a = the producers (`explosionAt`, `superboomAt`, `chain`, `flood`, `droppills`) — the genuinely new, undesigned subsystem Wave 5.2b surfaced. 5.5b = the consumer (`explosionTick`, the per-tick pass that drains the **explosion particle lists** — `client.explosions`/`client.players[i].explosions` — *not* the chain-reaction ring buffers, which 5.5a's `chain()`/`flood()` drain themselves) plus `forestvis`, since it cannot be meaningfully tested until 5.5a's state exists. Both wire into the `onMineExplosion`/`onSuperboomTerrain`/`onDropPills` injection points Wave 5.2b already added. **Correction (2026-09-02, PARITY finding on Wave 5.5b audit):** the original text here said 5.5b "drains the chain list," which is wrong — that's 5.5a's job. Also, `forestvis` was subsequently moved out of 5.5b into Wave 5.3c per D23, before 5.5b was ever implemented — 5.5b as actually built (see the wave table) is `explosionTick` alone. |
| **D23** | Wave 5.3 phasing (raised by IMPLEMENTER's readiness check, agreed by Jerod due to cost) | **Wave 5.3 as tabled ("shellTick, builderTick, pillTick" in one row, ~1000 lines of C across three unrelated server.c handler families) is too large a unit of work/review — split into 5.3a (shellTick: `shelllogic`, `shellcollisiontest`, `recvcldamage`, `recvcltouch`, plus `killTank` — see below), 5.3b (builderTick: `builderlogic` + the server-side build/repair/mine/grab-trees handlers merged in per the Wave 5.1 scope note — absorbs the former Wave 5.4's `buildercollision` line item, since `tankCollision`/`testAlliance`/`findPill`/`findBase` already shipped in 5.1/5.2a), and 5.3c (pillTick: `pilllogic` + `forestvis`, moved out of 5.5b — pillTick's firing condition needs `forestvis` directly, so it must exist before 5.3c, not after). **Wave 5.4 is retired as a standalone line item** — its scope is now fully absorbed into 5.1 (testAlliance/findPill/findBase), 5.2a (tankCollision), and 5.3b (buildercollision). |
| **D24** | `recvclbuildroad`'s tautological tree-sufficiency guard (`if (trees >= trees)`, always true — flagged by IMPLEMENTER, blocked 5.3b start) | **Replicate bug-for-bug, do not correct.** Same discipline already applied to the dead-tank terrain-enum mismatch (Wave 5.1/5.2a) and `growtrees`' outer guard checking `(x,y)` instead of `(growx,growy)` (Wave 5.7 pre-brief): Phase 3 is behaviour-preserving, bug-for-bug; fidelity fixes belong to Phase 5, not discovered ad hoc mid-port. This is not a Swift memory-safety concern (unlike the `writeRun` x<256 guard, which was a genuine safety deviation), so there's no countervailing reason to deviate. Requires a named regression test documenting the tautology is intentional, matching the pattern already used for the other two replicated bugs. Unblocks Wave 5.3b. |
| **D25** | Q15 resolution — WinBolo as a Wave 6 networking reference | **Read-only, clean-room policy: WinBolo's architecture may inform Wave 6, its code may not.** Confirmed via github.com/kippandrew/winbolo: classic WinBolo/LinBolo source (client & server), GPL v2, "copyright 1998-2008 John Morrison." GPL v2 is copyleft — copying or closely deriving Wave 6 networking code from it would pull GPL obligations onto BoloKit, conflicting with staying MIT (D13). Permitted: reading WinBolo's server/ for architectural understanding (session lifecycle, NAT traversal approach, protocol framing) to inform design decisions. Not permitted: copying, transliterating, or closely paraphrasing its code — any function/algorithm it inspires must be written independently from a design description, not composed while looking at the source (mirrors D5's clean-room precedent for art assets). At the Wave 6 pre-brief, IMPLEMENTER documents which specific design choices (if any) were informed by WinBolo, so PARITY can audit for accidental over-similarity rather than discovering it after the fact. |
| **D26** | C oracle build flag — `-ffp-contract` | **`CXBolo` target now builds with `cSettings: [.unsafeFlags(["-ffp-contract=off"])]` in `Package.swift`.** Wave 5.3b's broad-range fuzzing (not Wave 1's narrow 9-value grid) found `dot2f`/`mag2f` mismatching the C oracle on ~15-26% of random inputs (PARITY independently confirmed 26.5% via direct assembly A/B and traced it to Clang's default `-ffp-contract=on` fusing `v.x*v.x + v.y*v.y` into a single `fmadd` on arm64 — one rounding — versus Swift's never-contracting `+`/`*` — two roundings). This is a C-compiler code-generation gap in the **oracle**, not a Swift-side bug, and affects nearly every differential test that transitively calls `mag2f`/`dot2f` (tank physics, shell physics, collision — effectively all of Wave 1 onward). The flag is a pure fix: re-running the full existing suite (31 differential + 199 unit tests as of 5.3b) after applying it required zero changes to any prior wave's expected values — it closes a latent gap without invalidating any already-verified result. Recorded here with its own ID (not folded into the 5.3b wave-status note) because it changes what "the C oracle" computes for every future wave, not just this one — anyone reasoning about oracle behavior from here on should know this flag is in effect. |
| **D27** | Wave 5.3c FAIL/fix — shared per-tick mutable state under a per-player-call convention | **Established pattern: when N independent per-player replicas in C all mutate what becomes ONE shared field in the merged simulation, a naive "call once per connected player, in index order" loop is not equivalent — a later bystander's call can silently overwrite an earlier target's result within the same tick.** Caught by PARITY on `pillTick` (`state.pills[i].counter` reset by every non-target player's call after the real target's), not caught by the original test suite (no test exercised a same-tick multi-player sweep). Fixed by rewriting to a single per-tick election over all players at once — gather eligible candidates, compute the argmin (ties survive together and all fire, since tied replicas are independently deterministic and would all cross threshold together in the real distributed game), apply exactly one state transition per shared field per tick. Also surfaced a freeze-vs-reset distinction ("no alive connected player" leaves the field untouched, vs. "alive players exist but none eligible" explicitly resets it) that isn't obvious from the ordering bug alone. **Recorded as a decision, not just a bug-fix note, because Wave 5.5a/5.5b's mine-chain/flood/explosionTick work involves the same shape of shared per-tick state (chain lists) and should be designed as an election/single-pass model from the start, not discovered the same way twice.** |
| **D28** | Project artifact maintenance policy (raised by Jerod) | **No project artifact — docs, source, or tests — shrinks without an explicit, on-record replacement.** Formalizes the pattern already followed in practice (e.g. Wave 5.3c's 26→28 pillTick tests when the design changed): a test/doc/module CAN be rewritten or replaced when scope or design genuinely changes, but coverage or content can never just silently disappear. Concretely: (1) IMPLEMENTER's wave-completion reports already state before/after test counts — that continues, and going forward any DECREASE in a wave's test count vs. the prior wave's total must be called out explicitly with the reason (not left for PLANNER/PARITY to notice by diffing numbers); (2) PARITY's audits already check for coverage gaps case by case — this makes it a standing checklist item, not incidental; (3) the running test count is now tracked directly in this table's Notes column per wave (see rows above/below) so a regression is visible at a glance across the whole project, not just within one wave's report; (4) Wave 5.8's docs/archive pass (Q13) is extended to cover WHY superseded tests were replaced, not just that PLAN.md/AGENT_NOTES.md got compressed — archive.md entries for Wave 5+ should note test-count deltas and the reason, same granularity already used for code findings. |
| **D29** | Wave 5.6 `kPif` vs `Float.pi` for the post-spawn dir conversion | **Keep `kPif`, override the original Wave 5.6 trap note.** The trap note's `Float.pi` suggestion was a consistency preference with no behavioral basis (bit-identical either way, per D18). IMPLEMENTER observed every other shipped call site doing this exact `dir * (π/8)` conversion — `killBuilder` (5.2b), `roundDir` (5.0), `Vector.swift`'s dir-to-radians helpers — already uses `kPif`. Matching existing codebase convention is the stronger consistency argument; introducing a second spelling of the same constant for one call site would be the actual inconsistency. No change requested. |
| **D30** | Q13 resolution — Wave 5.8 docs/archive pass | **Executed as originally scoped, 2026-09-02.** `docs/AGENT_NOTES.md`'s Wave 5 chronological log (5.0–5.7, ~3700 lines) compressed into `docs/notes/archive.md` following the existing Waves 1–4 convention — commit hashes, key findings (D26 fp-contract fix, the Wave 5.3c FAIL/fix cycle behind D27, the Wave 5.7 Pill.counter/coolCounter catch), full uncompressed text preserved in git history per D28. `AGENT_NOTES.md` trimmed to its format/index scaffolding plus a fresh active log — a sanctioned exception to its own append-only convention, noted inline. `CLAUDE.md` rewritten to drop stale line-specific cross-references and reflect Wave 5's completion. Project memory (plan-status.md/roles-workflow.md/project-overview.md) refreshed to match. **One sub-item not resolvable by Claude directly:** the project-instructions config (a Cowork project setting, not a repo file) is still stale — no tool exists to edit it programmatically; replacement text was drafted and handed to Jerod to paste in manually. |
| **D31** | Q16 resolution — Wave 6 transport approach | **Port the wire format byte-exact from the C oracle; rebuild the transport mechanism on Network.framework + async/await.** D4 (no interop requirement) places no fidelity obligation on the mechanism itself, and transliterated POSIX/`select`/pthread glue isn't differentially testable, so there's no countervailing reason to port it bug-for-bug. DEEPDIVE1's protocol map (`docs/notes/DEEPDIVE1.md`) already specifies the wire format to the level of a usable 6.0 spec — 20 client→server / 34 server→client opcodes, the 113-byte `CLUpdate` header, all three encodings (raw BE float, 1/256 fixed-point, 8-bit brads), the join handshake, and eight cataloged oracle bugs for the trap list — so 6.0 is transcription plus differential tests from here, not discovery. |
| **D32** | Q17 resolution — Wave 6 sub-wave split confirmed | **6.0 wire codec (derived from the oracle per D31/D33) → 6.1 tick orchestrator (`runclient`/`runserver`) → 6.2 `recvsr*` broadcast handlers → 6.3 server session logic (join/kick/ban/alliance) → 6.4 transport + join handshake (Network.framework, per D31) → 6.5 tracker/NAT-PMP.** 6.5 carries a licensing constraint independent of D13/D25/D33: `README.md:42-45` already commits on the record that XBolo's GPLv3 `TCMPortMapper` dependency is not used here, and NAT traversal will use a permissively-licensed alternative or manual port forwarding — that public statement governs 6.5's design, not just the general MIT posture. |
| **D33** | Q19 resolution — GPL flexibility explored, decision: stay clean-room and MIT | **D13 (BoloKit stays MIT) and D25 (WinBolo is read-only/clean-room reference, never copied or adapted) are reaffirmed, not loosened.** Jerod's big-picture call (2026-09-02): fidelity is maintained via the oracle-derived path, and the server side can be designed without derivative code using a modern architecture — so there's no longer an open question to trade GPL exposure for time savings. This also settles a practical point DEEPDIVE1 raised: even a byte-identical WinBolo match would only have saved transcription, since an adapted codec would still need the same field-by-field validation against the oracle that deriving it directly already required — and D31 shows that derivation is done. Resolves the tension DEEPDIVE1 flagged with `README.md:42-45`'s existing public GPL-avoidance commitment: no reconciliation needed, the public statement stands as written and this decision confirms it rather than superseding it. |
| **D34** | Q20 resolution — WinBolo-server substitution not pursued | **Not pursued, for the same reason as D33.** PLANNER's confirmation against `server.c:620-687` established that the oracle's server is a thin, trusting relay for tank/builder physics (client-asserted position, blind-forwarded, no recomputation) but an authority for shared arbitrated state (pill contests, tree growth, spawn, base repair, pillbox firing) — and the Wave 5 benchmarks already document a known-bad WinBolo case in exactly that layer (pillbox range). Building BoloKit's own server-side logic under D31/D32 avoids that risk entirely rather than accepting it in exchange for licensing convenience that D33 no longer needs. |
| **D35** | Wave 6.1 PARITY findings ruling | **Both findings get fixed before Wave 6.2 opens, not deferred like Wave 5.9.** Finding 1 (`server.c:1192-1197`'s `pauseonplayerexit` → `server.pause = -1` side effect, missing from `GameState`/`RunTick.swift`) is a real gap inside the exact function Wave 6.1 claims to fully port — add a `pauseOnPlayerExit` field and wire the mutation. Finding 2 (`client.c:451`'s `seq != 0` move-tank gate, undisclosed) needs only a one-line disclosure matching the existing `timelimitreached`/`basecontrolreached` note. Unlike Wave 5.9's mine-cascade gap, neither is independent of 6.2+, so both close before 6.2's coding GO rather than becoming tracked debt. IMPLEMENTER to plan and execute directly — see `docs/AGENT_NOTES.md`, 2026-09-03. |
| **D36** | Wave 6.4 scope gap — `dgramclient()`'s post-decode application logic (list mutation, sound hooks, vis updates, dead-reckoning) had no assigned sub-wave | **Assigned to Wave 6.4.** Wave 6.0's pre-brief deferred this to "6.1/6.2," but neither landed wave actually claims it — 6.1 shipped as `runclient()`/`runserver()`'s own tick state machines only, 6.2 is TCP `recvsr*` handlers only (a different wire channel from UDP `CLUpdate`). 6.4's pre-brief should split `dgramclient()`'s pure application logic (differentially testable against 6.0's `clupdate_decode_oracle`) from the UDP-receive mechanism, mirroring 6.3's `joinplayerserver()` split. Not folded into 6.2 despite the matching "apply a given value" shape — 6.2 already has a coding GO in flight, and changing its scope mid-wave risks the drift D28/D35 exist to prevent. The dead-reckoning bound (`client.c:1446-1454`) is a `writeRun`-class Swift-side safety deviation, not a fidelity fix — 6.4 should bound it, not port it unbounded or omit it. Also: the tracker reachability echo (zeroed `CLUpdate`, `player == 255`) must be implemented in the **server's** UDP receive path as part of 6.4, even though it's only exercised once 6.5's tracker client exists — see `docs/AGENT_NOTES.md`, 2026-09-03. |
| **D37** | Wave 6.2 PARITY findings ruling (2 new findings + Q21 confirmed) | **All three fixed before Wave 6.3's coding GO, same precedent as D35.** Finding 1 (real bug): `recvSrSuperBoom` (`RecvSR.swift`) applies local-tank splash damage unconditionally; `recvsrsuperboom()` (`client.c:2737-2851`) nests that entire check inside `player != client.player` — gate `RecvSR.swift`'s damage-check block the same way. `recvSrSmallBoom`'s lack of that gate is correct (its C twin's damage check is a genuine sibling `if`, brace-depth-verified) and must NOT change. Finding 2 (missing UI hook): add `onTankStatusChanged` firing to `recvSrSmallBoom`/`recvSrSuperBoom` when local-tank damage is applied, matching `client.c`'s unconditional `settankstatus()` calls and the existing pattern in `recvSrHitTank`/`recvSrMineAck`. **`MineChain.swift`'s `applySplashDamage` (Wave 5.5a) does NOT get the same fix** — ruled as correctly mirroring `server.c`'s `explosionat()`/`superboomat()`, which have no `settankstatus` analog at all (confirmed by grep), so its omission is a considered match to the authoritative role, not a gap. Q21: confirmed bug, one-line fix — `ShellTick.swift:73`'s `.counter = 0` → `.coolCounter = 0`. Named regression tests required for all three (D28), including the previously-uncovered `recvSrSuperBoom(player: state.localPlayer, ...)` case PARITY flagged as silently untested. IMPLEMENTER to plan and execute directly — see `docs/AGENT_NOTES.md`, 2026-09-03. |

---

## Context

Bolo (Stuart Cheshire, 1987/1993) is a top-down networked tank game with an RTS layer:
tile-based island map, capturable refuelling bases, hostile pillbox turrets, and a Little Green
Man engineer who harvests trees to build roads, walls, boats and mines. The original is a
68k/PPC Mac app and cannot run on modern macOS.

Note that Bolo is no longer unmaintained: [WinBolo 2](https://store.steampowered.com/app/4672140/WinBolo/)
shipped June 2026 with native Mac support and modern netcode. This project is therefore
explicitly a **learning vehicle** — Xcode, Swift, Apple Intelligence, and networking
infrastructure — rather than the only way to get a playable Bolo. That framing is what makes a
full rewrite a reasonable choice instead of a wasteful one.

**Reference implementation:** [bananazon/xbolo](https://github.com/bananazon/xbolo) — MIT,
native Cocoa, ~500 KB of C + Objective-C, builds on Apple Silicon.

## What the port must preserve, and what it may fix

The inherited code has a structural flaw worth fixing: `client.c` (201 KB) and `server.c`
(112 KB) each contain their own copy of the simulation. The port unifies them into one
`BoloCore` module consumed by both roles. This is the strongest argument for rewriting rather
than forking.

**Discipline: port and fix are separate activities.** Porting changes language; fixing changes
behaviour. Doing both at once produces bugs nobody can attribute. So the port is
*behaviour-preserving* — bug-for-bug — and fidelity fixes come afterwards, in Phase 5.

## The spine: differential testing with C as the oracle

We have no replay logs (D9), so the C code is the only executable specification of Bolo
behaviour we possess. Discarding it before the port is verified would be throwing away the
only thing to check against.

So: **keep the C code compiling in the same target throughout the port.** Swift imports C
directly, but in SPM this requires defining a dedicated C target (e.g. `CXBolo`) or setting up
proper bridging headers/module maps. Note that for each module we want to call the C function 
and the Swift function in one process, on identical inputs, and assert identical results.

**Critical Test Implementation Notes:**
1. **Isolate POSIX Coupling:** Many reference files (like `client.c`, `server.c`) intertwine pure simulation state machine logic with socket initialization (`socket()`), select loops (`select()`), and Unix pipes. To prevent differential unit tests from spinning up network processes, you must mock out or isolate these network descriptors, or modularize the C simulation logic.
2. **Floats and Precision:** The C reference utilizes 32-bit floats (`float`) and trig functions for position and movement vectors (`Vec2f tank`, `Vec2f builder`). Do *not* try to enforce an integer or custom fixed-point position system in Swift; you must match C's float calculations precisely to achieve bit-identical test outputs.

```
for each module, leaf-first:
    1. write Swift implementation
    2. fuzz/enumerate inputs; run C and Swift side by side
    3. assert bit-identical outputs
    4. only then switch callers to Swift
```

This converts "risky 500 KB rewrite" into "verified incremental port," and it is the single
technique that makes D13 tractable.

**Port order — leaf modules first,** both because they're independently testable and because
they're a gentler Swift on-ramp:

| Wave | Modules | Why first |
| --- | --- | --- |
| 1 | `vector`, `rect`, `list`, `buf`, `errchk` | Pure utilities, tiny, trivially fuzzable |
| 2 | `terrain` (360 B), `tiles` (4.9 KB) | Pure enums + predicates, no state |
| 3 | `images` (`mapimage` autotiling) | Pure function of neighbours → tile index; exhaustively testable |
| 4 | `bmap` | File format; round-trip tests against real `.bmap` files |
| 5 | Simulation: shells → tank → LGM → pillbox → base | The fidelity-critical core. Unify client/server here |
| 6 | Networking, then the Cocoa UI layer | Largest and least pure; do last |

## Target architecture

```
~/Developer/XBolo/
  Package.swift            # BoloCore, BoloNet as SPM targets
  Sources/
    BoloCore/              # pure sim. NO AppKit. deterministic. one copy for client+server
    BoloNet/               # transport, session lifecycle
    BoloGlyphs/             # glyph sheet generator (CLI tool, Swift + CoreText)
  Tests/
    BoloCoreTests/         # Swift Testing framework
    DifferentialTests/     # C-vs-Swift oracle comparisons
  XBolo.xcodeproj          # app target: AppKit UI, links BoloCore/BoloNet
  Reference/c/             # inherited C/ObjC, kept as oracle until Phase 5 ends (Q10)
  LICENSE                  # original MIT notice retained + our copyright
```

The original ran a **50 Hz tick** — a hard fidelity fact already extracted from the
replay-log format notes. (Note: Per D18, we will use Float rather than fixed-point to maintain
bit-fidelity with the C reference math).

---

## Division of Labor (Multi-Agent Workflow)

To maintain maximum velocity, prevent file conflicts, and enforce high architectural standards, we use a structured multi-agent collaboration model:

1. **IMPLEMENTER (Xcode Claude agent):** Full read/write on the workspace. Writes Swift, owns DifferentialTests, commits. **As of 2026-09-02: also owns detailed code-level planning** — wave-specific trap lists, C-source pre-briefs, and implementation-approach decisions — rather than receiving them pre-authored by PLANNER/PARITY.
2. **PLANNER (Claude.ai, this role):** High-level project management only, as of 2026-09-02 — wave sequencing, stage-gate GOs, the decisions/open-questions log, cross-wave policy (D26-D28 style), and routing PARITY's findings. Does not author detailed code-level trap lists or pre-briefs going forward; that's IMPLEMENTER's own responsibility now.
3. **PARITY (Claude.ai, adversarial):** Independent post-commit audit against the C source. Reports findings only, does not write fixes.

---

## Phases

Reordered from earlier drafts because D10 made the art nearly free and D13 made the test
harness a prerequisite rather than a nicety.

### Phase 0 — Take over the project slot (gate)

**Status: Step 0.1 complete, verified against the repo. Step 0.2 not started — see below.**

**Surveyed state (original):** `~/Developer` did not exist. Xcode was not running (so a move
was safe). The stub was not a git repo and contained only `Untitled Project.xcodeproj`, one
boilerplate `ContentView.swift`, and a `.DS_Store`.

**Revision to D12's implementation — replace, don't rename.** Renaming an Xcode project properly
means editing `project.pbxproj`: target `MyApp`, scheme names, product name, bundle ID. That is
fiddly and error-prone, and preserves nothing (verified: the stub is Hello World). Creating
fresh at the right path serves the same intent with less risk.

**Also: start SPM-only, add the `.xcodeproj` later.** Xcode opens a `Package.swift` directly, so
no Xcode project is needed until there's UI to show (Phase 2). This sidesteps `pbxproj` surgery
entirely *and* avoids a confusing name collision with the reference clone's own
`XBolo.xcodeproj` inside `Reference/c/`.

**Step 0.1 — Local file work — done. (PARTIALLY BROKEN — Action Required):**

| Sub-item | State |
| --- | --- |
| `~/Developer/XBolo`, `git init` | Done — repo present, `main` branch, clean tree |
| Scaffold dirs | Done — `Sources/{BoloCore,BoloNet,BoloGlyphs}/`, `Tests/{BoloCoreTests,DifferentialTests}/` present |
| `Package.swift` | **Broken:** The tools-version is declared as `6.0` but uses `.macOS(.v26)` which requires tools-version `6.2` or above. This must be corrected immediately. |
| `.gitignore` | Present, tracked |
| `LICENSE` | Present, tracked |
| `README.md` | Present, tracked |
| `Reference/c` as git submodule | Done — `.gitmodules` points at `https://github.com/bananazon/xbolo.git`, pinned at `51c3cbc`, working tree populated including nested `TCMPortMapper` submodule |
| Delete `UntitledProjects` stub | Done — directory empty/absent |
| Initial commit | Done — `7bca0d7 Scaffold Swift port of XBolo`, tree clean |

**Step 0.2 — Prove the oracle builds — VERIFIED (RESOLVED):**

- **Status:** Verified. Running `xcodebuild -project Reference/c/XBolo.xcodeproj -target "Mac OS X" -configuration Development build` succeeds cleanly (`** BUILD SUCCEEDED **`) on Darwin 27. The oracle is ready.

**Step 0.3 — Housekeeping — not started.**

- Draft the upstream courtesy issue (D11) for your review before anything is posted.

**Verify:** `swift build` and `swift test` succeed on the package; C XBolo launches and a
game starts; `git log` shows a clean history.

### Phase 1 — Differential test harness

- Bridge the C code into a Swift test target; helpers to invoke both implementations on one input.
- State digest over terrain grid + entity table.
- **Verify:** a trivial module (`vector`) passes C-vs-Swift equality on fuzzed input.

### Phase 2 — Glyph art (unblocks distribution, first real Swift target)

- `BoloGlyphs` CLI: parse `images.h` → manifest → render 256×256 RGBA sheets of 16×16 cells.
- Layout stays byte-identical to the originals so no game-code changes are needed. Verified: index decodes as `row = idx >> 4`, `col = idx & 0xF`.
- Geometric/box-drawing glyphs from an **OFL font** (Noto Sans Symbols, DejaVu) — colour emoji are illegible at 16 px, and Apple Color Emoji is proprietary and non-redistributable.
- 16 tank headings have no 16 legible glyph equivalents: render **one** directional glyph rotated to 16 angles.
- Delete the © Cheshire art and sounds; synthesize simple replacement sounds.
- **Verify:** sheet validator passes; game renders and is playable with glyph art; no original assets remain in git history (needs history rewrite, not just deletion).

### Phase 3 — Incremental port

Waves 1–6 above. Each module: Swift implementation → differential test green → switch callers.
Behaviour-preserving only; log suspected fidelity bugs rather than fixing them here.

### Phase 4 — Measurement rig + fidelity spec

- Stand up [Infinite Mac](https://infinitemac.org) (browser/WASM, bundles Bolo, has a shared folder for file transfer). Confirm Bolo runs and **can write log files we can extract** — unverified, and the main risk here. Fallback: screen recording with frame counting.
- Run controlled experiments (hold accelerate across swamp; time a wall build; sit under a pillbox), extract logs, parse with [rooklift/ancient_bolo_parser](https://github.com/rooklift/ancient_bolo_parser) as an *external instrument only* — it has no licence, so we run it, never copy from it.
- Write `docs/FIDELITY.md`: terrain × speeds/buildability/destruction, LGM action costs and timings, pillbox fire-rate escalation curve, base refuel rates, tank handling. Every row cites its evidence; unknowns marked.
- **Verify:** one parsed original log prints a sane 50 Hz event stream.

### Phase 5 — Close the fidelity gaps

Now, and only now, change behaviour. Each gap: failing test → fix in `BoloCore` → green. One
place to fix, not two — the payoff from unifying client/server.

### Phase 6 — Networking

Self-contained (D4). Port the transport, LAN then internet via UPnP/NAT-PMP. Resolve Q10.

### Phase 7 — Ship

Universal binary, signing, notarization, DMG.

**Candidate later phase:** Bolo's AI "brains" via FoundationModels — directly serves the Apple
Intelligence learning goal, and `GSRobot.m` shows the reference had a bot API to model on.

---

## Verification

- **Build:** `BuildProject` MCP tool against `XBolo.xcodeproj`; `XcodeRefreshCodeIssuesInFile` for fast Swift diagnostics during the port.
- **Port correctness:** differential C-vs-Swift tests, per module, in CI.
- **Determinism:** identical inputs ⇒ identical state digest across runs.
- **Fidelity:** measured values from parsed emulator logs vs the Swift build's telemetry.
- **Visual:** `device-interaction` skill screenshots; contact sheets for glyph review.
- **Multiplayer:** two local clients + dedicated host; then macOS **Network Link Conditioner** at 100 ms / 2% loss baseline, 300 ms / 5% degraded.

## Risks, honestly

1. **SDK breakage on macOS 27** — blocks Phase 0 entirely. Most likely near-term failure. Still unresolved as of this writing (Step 0.2 not attempted).
2. **Scope.** A 500 KB behaviour-preserving port is the largest thing in this plan by an order of magnitude. Phases 0–2 deliver a legally clean, playable game *before* the port begins, so there's standing value even if the port stalls.
3. **Emulator may not yield extractable logs** (Phase 4). Fallback is frame counting — cruder, slower.
4. **Differential testing only proves agreement with xbolo, not with Bolo.** xbolo was itself written without the original source, so it has its own inaccuracies. That's exactly what Phase 4/5 exist to catch — don't mistake green tests for fidelity.

---

## Wave implementation status (updated 2026-09-01 by PLANNER — planner handoff, see AGENT_NOTES.md)

| Wave | Content | Status |
|---|---|---|
| Wave 1 | Vector, Rect, List, Buf, ErrChk | ✅ Complete — b729781 |
| Wave 2 | Terrain enum, Tiles enum, TileGrid, 8 predicates | ✅ Complete — 9695275 |
| Wave 3 | Image constants, mapimage autotiling | ✅ Complete — db747b2 |
| Wave 3.1 | Physics constants, TerrainGrid, terrain speed functions | ✅ Complete — 24d7ae0 (PARITY Findings 1+2 resolved: 6580e2a, 20e156d) |
| Wave 4 | terrainToTile, defaultTerrain/Tile, BMAP format structs | ✅ Complete — 8044fb0 (35 tests green) |
| Wave 4.1 | BMAP RLE codec — readRun/writeRun, nibble helpers | ✅ Complete — 7298d2c |
| Wave 5.0 | Physics constants additions, roundDir, maxSpeed/maxTurnSpeed w/ pill/base overrides | ✅ Complete — e2636fb (PARITY PASS, F4 deferred) |
| Wave 5.1 | GameState model (tanks, pills, bases, shells, builders) | ✅ Complete — a3126c6 (76 tests: 26 diff + 50 unit) |
| Wave 5.2a | tankMoveTick — tank physics tick | ✅ Complete — a752a77 (101 tests: 27 diff + 74 unit) |
| Wave 5.2b | tanklocallogic/enter() — local player input, mine/boat/refuel/fire | ✅ Complete — see AGENT_NOTES (scope note: mine-chain/flood propagation and pill-scatter placement deferred, injection points added) |
| Wave 5.3a | shellTick — shelllogic, shellcollisiontest, recvcldamage, recvcltouch, `killTank` (pulled forward from 5.6 — hidden dependency, armour-zero on shell hit calls it) | ✅ Complete — PARITY PASS (Q14 open, non-blocking) — 151+28 tests |
| Wave 5.3b | builderTick — builderlogic + server-side build/repair/mine/grab-trees handlers merged into the unified tick; absorbs former Wave 5.4's buildercollision | ✅ Complete — PARITY PASS, 27a76d3 (D24 applied; D26 fp-contract fix, cross-cutting) — 199+31 tests |
| Wave 5.3c | pillTick — pilllogic + forestvis (moved from 5.5b, needed by pillTick's firing condition) | ✅ Complete — PARITY PASS after FAIL/fix cycle, 03d56b3 (shared-counter ordering bug, see D27) — 227+33 tests, no coverage lost (D28) |
| ~~Wave 5.4~~ | ~~tankcollision, buildercollision, testAlliance, findPill/findBase~~ | ⏹ Retired (D23) — absorbed into 5.1/5.2a/5.3b |
| Wave 5.5a | explosionAt/superboomAt/chain/flood (mine-detonation cascade), droppills (pill-scatter placement) | ✅ Complete — PARITY PASS, d99815e (D27 held throughout, no repeat of 5.3c FAIL pattern) — 257+33 tests, no coverage lost (D28) |
| Wave 5.5b | explosionTick (drains the explosion *particle* lists — visual-effect duration counters — not the chain-reaction ring buffers, which 5.5a already drains) | ✅ Complete — PARITY PASS, 08c6e85 (D22 phrasing corrected above) — 267+33 tests, no coverage lost (D28) |
| Wave 5.6 | spawn() — two-pass weighted selection; drown | ✅ Complete — PARITY PASS, a3f9540 (D29 applied) — 274 tests total, one LOW doc-only finding (dangling arc4random_uniform comment xref) |
| Wave 5.7 | growtrees (C bug replicated), pill cooldown, base replenish | ✅ Complete — PARITY PASS, 221ba97 (Pill.counter/coolCounter split confirmed genuine, no D27 hazard) — 296 tests total |

| Wave 5.8 | Docs/archive pass — PLAN.md, AGENT_NOTES.md → archive.md, project memory, project-instructions reconciliation (Q13) | ✅ Complete — AGENT_NOTES.md compressed to docs/notes/archive.md, project memory refreshed; project-instructions reconciliation pending Jerod pasting updated text (Claude cannot edit that setting directly) |
| Wave 5.9 | **New 2026-09-02 (Wave 6.1 finding):** wire the mine-cascade injection points (`onMineExplosion`/`onSuperboomTerrain`/`onDropPills`) into their actual trigger sites — `enterTile`, `grabTile`, `tankMoveTick`'s dead-tumble, `smallboom`/`superboom` — with correct causer-player attribution. Every trigger site has left these as documented no-ops since Wave 5.2b; the engine functions themselves (`explosionAt`/`superboomAt`/`chain`/`flood`) already shipped in 5.5a. This is unfinished Phase 3 port work (behaviour-preserving, design already settled by 5.5a/D22), not a Phase 5 fidelity fix and not Wave 6 networking — numbered 5.9 rather than folded into 6.x. Confirmed independent of Wave 6.2–6.5 (which only apply already-decided values, never re-trigger cascades), so it does not block networking's sequence. | ⬜ Not started — no pre-brief yet; sequencing relative to 6.2+ is Jerod's call if he wants it prioritized differently |

| Wave 6 | Networking — summary row; see 6.0–6.5 below for the D32 sub-wave split (UI split out to its own phase per IMPLEMENTER's 2026-09-02 scope survey — see AGENT_NOTES.md) | 🟨 In progress — 6.0/6.1 complete; 6.2 code complete (`0d44f30`+`a5e84b0`) 2026-09-03, sent to PARITY, not yet closed; 6.3 pre-brief reviewed and banked; 6.4/6.5 forward-planned (D36) but not started |
| Wave 6.0 | Wire codec — `CL*`/`SR*` structs, `CLUpdate`, all three encodings (raw BE float, 1/256 fixed-point, 8-bit brads), derived byte-exact from the C oracle. **Correction 2026-09-02 (Wave 6.3 pre-brief finding):** preambles were never built despite this row originally claiming them — no `Preamble` type exists in `Sources/BoloNet/`; reassigned to Wave 6.3 below, not reopening 6.0. | ✅ Complete — PARITY PASS, `96704cd`+`5c5e47a` (FWIDTH-double finding independently re-derived by PARITY) — 345 tests total (+16) |
| Wave 6.1 | Tick orchestrator — `runclient()`/`runserver()`; new pause/timelimit/domination-basecontrol state machines | ✅ Complete — PARITY PASS, `d0a9834`+`b028bf8` (orig) then `1e0cbe6`+`91c4a8d` (D35 fix) then `3d4563a` (PARITY re-audit PASS) — 363 tests total (+18 net) |
| Wave 6.2 | **30** (not 33 — `sendmesg`/`timelimit`/`basecontrol` have no `GameState` mutation, confirmed on read) `recvsr*` client broadcast handlers (apply-given-value state application, a distinct category from Wave 5's authoritative tick functions — not a thin wiring layer). New callback surfaces for later waves: `onRequestGrabTile` (6.4, network send), `onShouldLeaveAlliance` (6.3, real `leavealliance()`). | 🟨 PARITY audit found 2 findings + confirmed Q21 (`1bc2b90`) — **D37 fix required before close**, same precedent as D35 |
| Wave 6.3 | Server session logic — join/kick/ban/alliance; **now also the three preamble structs** (`JOIN_Preamble`/`BOLO_Preamble`/`TRACKER_Preamble`) reassigned from Wave 6.0's corrected row above | 🟨 Pre-brief reviewed and banked 2026-09-02 — coding GO follows once 6.2 closes, per D32's order |
| Wave 6.4 | Transport + join handshake — Network.framework + async/await (D31); builds on `Buf.swift`'s existing `sendbuf`/`recvbuf`/`cntlsend`/`cntlrecv`. **Per D36 (2026-09-03), also owns `dgramclient()`'s post-decode CLUpdate-application logic (split pure state-application from the receive mechanism, mirroring 6.3's `joinplayerserver()` split) and the server-side tracker reachability echo (`player == 255` sentinel).** | ⬜ Not started — blocked on 6.0–6.3 |
| Wave 6.5 | Tracker/NAT-PMP — permissive alternative to `TCMPortMapper` per `README.md:42-45`'s existing GPLv3-avoidance commitment (D32). **Trap flagged 2026-09-03: `TrackerHost`/`TrackerHostList` (`tracker.h:36-56`) are the one wire struct family that is NOT `__attribute__((__packed__))` — reproduce the padding deliberately, don't assume Swift's default struct layout matches.** | ⬜ Not started — deferrable per D4; blocked on 6.4 |


## Wave 5 behavioral benchmarks (PARITY audit, 2026-08-31)

Critical behaviors where XBolo must match original Bolo 0.99.7 — NOT WinBolo:

- **Wall friction:** Original applies substantial friction halting momentum. WinBolo is "like ice." Port the C collision response in `client.c` exactly — do not simplify.
- **Tank deceleration:** Original brakes precisely. WinBolo overshoots. Float-precision tick accumulation (D18) is the correct safeguard.
- **Boat-to-land transition:** Original applies resistance forces at the water/land boundary. WinBolo treats it as a plain speed-zone change. This is NOT captured by `terrainMaxSpeed` — must be ported separately in Wave 5.
- **Mine self-damage:** Original does NOT damage the laying tank on detonation. WinBolo does. Wave 5 mine handler must explicitly skip the owner.
- **Mine self-damage asymmetry (confirmed Wave 5.5a, PARITY):** `smallboom`'s tank-damage check is independent of the self-caused gate — a smallboom CAN damage the tank that caused it. `superboom`'s damage check is nested inside the self-caused gate — a superboom you caused yourself never damages you. Not symmetric; do not assume one implies the other in any future wave touching these paths.
- **Builder retrieval:** Original retrieves stranded builders by proximity. WinBolo requires killing them first. Wave 5 builder-retrieval logic must match the original proximity-only check.
- **Pillbox range:** WinBolo fires ~0.5 squares too far. Use only the C oracle constant — never a WinBolo source.
- **Tick rate:** 50 Hz confirmed in both original and WinBolo. ✅ Consistent with `ticksPerSec` in Physics.swift.

## Three-bot team structure (effective 2026-08-31)

- **IMPLEMENTER** (Xcode Claude agent) — writes Swift, owns DifferentialTests, commits
- **PLANNER** (Claude.app Cowork) — owns this file + AGENT_NOTES.md, issues wave assignments
- **PARITY AUDITOR** (Claude.app, adversarial) — independent behavioral parity review, updates this file         

Communication: all handoffs via AGENT_NOTES.md with explicit [TO: X] tags.

## Wave 5.0 — Physics constants reference (pre-read complete 2026-08-31)

All constants to be added to `Physics.swift` in Wave 5.0. Values from `bolo.h`.

| Swift name | Value | C macro |
|---|---|---|
| tankRadius | 0.375 | TANKRADIUS |
| builderRadius | 0.125 | BUILDERRADIUS |
| shellVelocity | 7.0 | SHELLVEL |
| maxShellRange | 7.0 | MAXRANGE |
| kickForce | 3.125 | KICKFORCE |
| explosionTicks | 24 | EXPLOSIONTICKS *(particle display)* |
| explodeTicks | 45 | EXPLODETICKS *(death animation)* |
| respawnTicks | 150 | RESPAWN_TICKS |
| maxShells | 40 | MAXSHELLS |
| maxMines | 40 | MAXMINES |
| maxArmour | 40 | MAXARMOUR |
| maxTrees | 40 | MAXTREES |
| roadTrees | 2 | ROADTREES |
| wallTrees | 2 | WALLTREES |
| boatTrees | 20 | BOATTREES |
| pillTrees | 4 | PILLTREES |
| maxPlayers | 16 | MAXPLAYERS |
| maxStarts | 16 | MAX_STARTS |
| pillOnboard | UInt8(0xff) | ONBOARD |
| playerNeutral | UInt8(0xff) | NEUTRAL |
| noPill | UInt8(0xff) | NOPILL |
| minBaseArmour | 5 | MINBASEARMOUR |

**Distinguishing `explosionTicks` vs `explodeTicks`:**
- `explosionTicks (24)` — how long an `Explosion` particle effect renders before removal from the list
- `explodeTicks (45)` — how long the dead-tank explosion animation plays before `spawn()` is eligible (`respawncounter > EXPLODETICKS`)
