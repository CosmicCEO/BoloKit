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
directly, so for each module we can call the C function and the Swift function in one process,
on identical inputs, and assert identical results.

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

Determinism matters for the differential tests: use integer or fixed-point positions, not
floats. The original ran a **50 Hz tick** — a hard fidelity fact already extracted from the
replay-log format notes.

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

**Step 0.1 — Local file work — done. Verified state:**

| Sub-item | State |
| --- | --- |
| `~/Developer/XBolo`, `git init` | Done — repo present, `main` branch, clean tree |
| Scaffold dirs | Done — `Sources/{BoloCore,BoloNet,BoloGlyphs}/`, `Tests/{BoloCoreTests,DifferentialTests}/` present |
| `Package.swift` | Done — declares `BoloCore`, `BoloNet` (deps on `BoloCore`), `BoloGlyphs` executable, 2 test targets; `.macOS(.v26)` per D16 |
| `.gitignore` | Present, tracked |
| `LICENSE` | Present, tracked |
| `README.md` | Present, tracked |
| `Reference/c` as git submodule | Done — `.gitmodules` points at `https://github.com/bananazon/xbolo.git`, pinned at `51c3cbc`, working tree populated including nested `TCMPortMapper` submodule |
| Delete `UntitledProjects` stub | Done — directory empty/absent |
| Initial commit | Done — `7bca0d7 Scaffold Swift port of XBolo`, tree clean |

**Step 0.2 — Prove the oracle builds — NOT STARTED. Biggest open risk in the whole plan.**

- Build the C reference: `xcodebuild -project Reference/c/XBolo.xcodeproj -target "Mac OS X" -configuration Development build`, then `Reference/c/fix_framework.sh`.
- **Live risk:** this machine is Darwin 27; xbolo was modernized against early-2026 Xcode. SDK breakage is the likeliest blocker in the whole plan. If it won't build, fixing that *is* Phase 0 — and without a working oracle the differential-testing spine collapses, so this cannot be skipped.
- No `Reference/c/build/` output exists yet — confirms this has not been attempted.

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
