# Plan: Swift port of XBolo — a faithful, distributable Mac Bolo

> **Convention:** every question gets a permanent ID, never reused or renumbered. Answered
> questions move to the Decisions log keeping their ID. Questions live only in these two
> sections — never in prose elsewhere.
>
> This document is the durable home for the plan (see D17) — it lives in the repo, not just in
> assistant-side session state, so it survives a dropped session.

## Open questions

| ID | Question | Blocks | Priority |
| --- | --- | --- | --- |
| **Q10** | Keep the C code in-tree permanently as a test oracle, or delete it once the port completes? Recommend keeping it until Phase 5 ends, then removing it (it stays in git history) | Phase 6 | Low |

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

1. **Gemini (Primary Implementer):** Runs the main project loop. Responsible for all file modifications (writing Swift code, updating configurations), running builds, executing tests, and managing local repository state.
2. **Claude (Architectural Reviewer & Advisor):** Operates in a read-only context. Serves as a peer programmer to review Gemini's commits/changes, verify conformance to Apple's design patterns, challenge architectural decisions, and answer complex questions regarding the original C reference codebase (specifically the POSIX networking/concurrency structures).

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

## Wave implementation status (updated 2026-08-31 by PLANNER)

| Wave | Content | Status |
|---|---|---|
| Wave 1 | Vector, Rect, List, Buf, ErrChk | ✅ Complete — b729781 |
| Wave 2 | Terrain enum, Tiles enum, TileGrid, 8 predicates | ✅ Complete — 9695275 |
| Wave 3 | Image constants, mapimage autotiling | ✅ Complete — db747b2 |
| Wave 3.1 | Physics constants, TerrainGrid, terrain speed functions | ✅ Complete — 24d7ae0 (PARITY Findings 1+2 resolved: 6580e2a, 20e156d) |
| Wave 4 | terrainToTile, defaultTerrain/Tile, BMAP format structs | ✅ Complete — 8044fb0 (35 tests green) |
| Wave 4.1 | BMAP RLE codec — readRun/writeRun, nibble helpers | 🔄 In progress — IMPLEMENTER assigned |
| Wave 5 | Tank simulation, LGM, shells, pills, bases | ⬜ Not started — see behavioral benchmarks below |
| Wave 6 | Networking + Cocoa UI | ⬜ Not started |


## Wave 5 behavioral benchmarks (PARITY audit, 2026-08-31)

Critical behaviors where XBolo must match original Bolo 0.99.7 — NOT WinBolo:

- **Wall friction:** Original applies substantial friction halting momentum. WinBolo is "like ice." Port the C collision response in `client.c` exactly — do not simplify.
- **Tank deceleration:** Original brakes precisely. WinBolo overshoots. Float-precision tick accumulation (D18) is the correct safeguard.
- **Boat-to-land transition:** Original applies resistance forces at the water/land boundary. WinBolo treats it as a plain speed-zone change. This is NOT captured by `terrainMaxSpeed` — must be ported separately in Wave 5.
- **Mine self-damage:** Original does NOT damage the laying tank on detonation. WinBolo does. Wave 5 mine handler must explicitly skip the owner.
- **Builder retrieval:** Original retrieves stranded builders by proximity. WinBolo requires killing them first. Wave 5 builder-retrieval logic must match the original proximity-only check.
- **Pillbox range:** WinBolo fires ~0.5 squares too far. Use only the C oracle constant — never a WinBolo source.
- **Tick rate:** 50 Hz confirmed in both original and WinBolo. ✅ Consistent with `ticksPerSec` in Physics.swift.

## Three-bot team structure (effective 2026-08-31)

- **IMPLEMENTER** (Xcode Claude agent) — writes Swift, owns DifferentialTests, commits
- **PLANNER** (Claude.app Cowork) — owns this file + AGENT_NOTES.md, issues wave assignments
- **PARITY AUDITOR** (Claude.app, adversarial) — independent behavioral parity review

Communication: all handoffs via AGENT_NOTES.md with explicit [TO: X] tags.
