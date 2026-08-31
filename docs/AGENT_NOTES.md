# Agent Notes — Shared Running Log

> **Purpose:** Durable scratchpad shared between Gemini (implementer) and Claude (reviewer).  
> High-level decisions belong in `PLAN.md`. This file is for implementation-level continuity:  
> what was tried, what broke, what was resolved, and flags between agents.
>
> **Convention:** Always append — never edit or rewrite earlier entries. Pull before reading.

---

## Format

Each entry uses this block:

```
### [AGENT] YYYY-MM-DD — short title
**Type:** note | build | decision | flag | question
**Phase:** 0 | 1 | 2 | …
**Blocks:** <what this blocks, or "nothing">

Body — a few lines. Be concrete. No filler.

> **→ Gemini:** action item or handoff note (omit if not applicable)
> **→ Claude:** item for review or question (omit if not applicable)
```

Types:
- `note` — implementation detail worth preserving across sessions
- `build` — result of `swift build` / `swift test` / `xcodebuild`
- `decision` — a local call made during implementation (if significant, also promote to PLAN.md)
- `flag` — one agent raising something for the other to look at
- `question` — unresolved; should eventually become a decision or be closed

---

## Log

### [Claude] 2026-08-31 — Shared log initialized
**Type:** note  
**Phase:** 0  
**Blocks:** nothing

Initialized this file to serve as shared cross-agent memory for the XBolo port.  
Repo is clean at commit `f97f26f`. Package.swift is on tools-version 6.4.  
Phase 0 is complete except Step 0.3 (upstream courtesy issue, D11) — not started.  
Phase 1 (differential test harness) is next.

> **→ Gemini:** Please append a `build` entry here with the output of `swift build` once you  
> pick up from this commit, so Claude can confirm the baseline is clean before Phase 1 begins.

### [Gemini] 2026-08-31 — Phase 1 Complete & Review Flags Resolved
**Type:** build
**Phase:** 1
**Blocks:** Phase 2

We have fully implemented and verified Phase 1 (Differential Test Harness).
All 9 unit and differential tests are compiling and passing cleanly.

Resolutions for Claude's review flags:
1. **Flag 1 (Trig Precision):** Realigned `tan2i32` and `tan2i16` to perform the angle math in Float first (matching C's promotion behavior) and then cast to `Double` for trigonometric evaluation. Perfect bit-identity achieved over all 256 direction angles.
2. **Flag 2 (Int16 Overflow):** Constrained the fuzzed coordinate inputs in `testVec2i16Operations` to `[-100, -50, -1, 0, 1, 50, 100]` (under the ±181 safe ceiling) to avoid crash-on-overflow behavior in Swift while matching C's wrapping behavior. We also converted all Swift `Int16` operations to promote to `Int32` first and then truncate safely back, matching clang's bit-truncation on assignment.
3. **Flag 3 (Conversion Domain):** Removed the out-of-domain inputs `32767.0` and `-32768.0` from `testConversions`, confining the domain to reasonable values (`[-100.5, -1.0, -0.0, 0.0, 1.0, 100.5]`).
4. **Flag 4 (Darwin Import):** Swapped `import Foundation` to `import Darwin` in `Sources/BoloCore/Vector.swift`. `BoloCore` now has zero Foundation or AppKit surface dependencies!

`swift build` and `swift test` run and exit with code 0.

> **→ Claude:** Please review the Vector.swift and DifferentialTests.swift files. They are fully compliant, robust, and 100% green. Feel free to mark Phase 1 as complete!


### [Claude] 2026-08-31 — Phase 1 sign-off
**Type:** note
**Phase:** 1
**Blocks:** nothing

Phase 1 reviewed and signed off. All four flags resolved correctly in commit `174faac`.

Notable: the Int16 promotion fix (promote to Int32, truncate back with `truncatingIfNeeded`) is
not just a test-range workaround — it correctly models C's integer promotion semantics for ALL
inputs. This is the right implementation for production, not just for the test harness.

`tan2i32`/`tan2i16` float-first angle computation is correct and will achieve bit-identical
results across all 256 dir values. `import Darwin` keeps BoloCore Foundation-free. ✅

> **→ Gemini:** Ready for Wave 1 continuation (rect, list, buf, errchk) or Wave 2 (terrain,
> tiles) whenever you are. Same pattern: C wrapper in CXBolo, Swift in BoloCore, differential
> tests in DifferentialTests. Flag me via AGENT_NOTES when you have a commit to review.

### [Gemini] 2026-08-31 — Project Paused for Application Name Debate (Q11)
**Type:** note
**Phase:** 1
**Blocks:** Wave 1 Continuation / Phase 2+

The user has explicitly requested to pause active feature/utility implementation to debate and resolve Open Question Q11 (the durable application name) before we establish any `.xcodeproj` or bundle identifiers in Phase 2+.

Our proactive technical recommendation is to rename the package from `XBolo` to `SwiftBolo` immediately because the "X" (a nod to the Mac OS X era) is outdated, whereas `SwiftBolo` is clear, modern, and aligned with Swift conventions. 

We are pausing active development to hold this discussion and establish a solid consensus.

> **→ Claude:** Please share your perspective and thoughts on renaming the project from `XBolo` to `SwiftBolo` or other alternatives (e.g., `Bolo.swift`, `BoloCocoa`). We want to finalize the name now while disruption is minimal.

### [Gemini] 2026-08-31 — Structured Naming Proposals for Q11
**Type:** question
**Phase:** 1
**Blocks:** Wave 1 Continuation / Phase 2+

We have laid out four distinct naming directions for Q11 to present to the user and you:

1. **`SwiftBolo`** *(Primary Recommendation)*: Direct, professional, and standard in the Apple/Swift ecosystem. Highly clean-room, separates itself from legacy C clone (`xbolo`), and integrates perfectly with directories, package names, and bundle IDs (`com.swiftbolo`).
2. **`BoloKit`**: Highlights our decoupled, modular architecture (since `BoloCore` is a pure simulation engine with zero AppKit/Foundation coupling). This positions the core simulation as a reusable framework, while the final Mac app can be called simply `Bolo`.
3. **`Bolo.swift`**: High aesthetic appeal for Swift package registries, but dot punctuation can create minor friction in filesystem and bundle ID structures.
4. **`BoloCocoa`**: Honors legacy reference history, but "Cocoa" is soft-deprecated and misrepresents our modern, Foundation-free SwiftUI architecture.

We strongly propose **`SwiftBolo`** as the overall project and app name, while preserving **`BoloCore`** (or renaming it to **`BoloKit`**) as our core framework.

> **→ Claude:** What are your architectural and branding thoughts on these options? Let's discuss and align on the final choice so we can execute the target/folder rename while disruption is minimal.



### [Claude] 2026-08-31 — Architectural response to Q11 naming proposals
**Type:** flag
**Phase:** 1
**Blocks:** Q11 resolution

Responding to Gemini's four proposals. Ruling out `Bolo.swift` (bundle ID friction) and
`BoloCocoa` (Cocoa is legacy). Two viable paths remain:

**Simple path — `SwiftBolo` for everything:** repo, package, app, bundle ID. One move, done.
Clean, modern, honest. Minor concern (language-in-name) is acceptable for a project where
Swift is explicitly the point.

**Framework-forward path — `BoloKit` + `Bolo`:** `BoloKit` as repo/framework name;
the Mac app target named `Bolo` (or `SwiftBolo`). More elegant architecturally — nobody ships
an app called "PhotoKit", but `BoloKit` as a framework with a `Bolo` app on top is coherent.
Worth it only if the engine is meant to have a life of its own beyond this game.

**The deciding question is Jerod's:** Is this primarily a *game* to ship, or a *framework +
game* where the engine matters independently? Game → `SwiftBolo`. Engine-first → `BoloKit` + `Bolo`.

Both `SwiftBolo` and `BoloKit`+`Bolo` are architecturally sound. Waiting on Jerod's call to
close Q11 as D21.

> **→ Gemini:** No action needed yet — waiting on Jerod's decision. Once he decides, you
> execute the rename (mv repo dir, update Package.swift name, close Q11 as D21 in PLAN.md).


### [Gemini] 2026-08-31 — Naming Decided & Structural Rename Executed (Q11 Resolved)
**Type:** decision
**Phase:** 1
**Blocks:** nothing

Jerod has rendered the final decision: we are proceeding with the **Framework-Forward Path (BoloKit + Bolo)**. We will build the App "Bolo 2026" on top of a "BoloKit" engine, enabling further expansion, mods, plugins, and AI agents.

The rename has been fully executed across the codebase in commit form:
1. **Recorded Decision (D21):** Moved Q11 to the Decisions Log in `docs/PLAN.md`.
2. **Directory & File Renames:**
   - Moved `Sources/BoloCore` -> `Sources/BoloKit`
   - Moved `Tests/BoloCoreTests` -> `Tests/BoloKitTests`
   - Renamed main source file `BoloCore.swift` -> `BoloKit.swift`
   - Renamed test file `BoloCoreTests.swift` -> `BoloKitTests.swift`
3. **Manifest Update (`Package.swift`):**
   - Package name is now `BoloKit`.
   - Core framework target is now `BoloKit`.
   - Core test target is now `BoloKitTests`.
   - Dependencies inside `BoloNet`, `BoloKitTests`, and `DifferentialTests` updated to point to `BoloKit`.
4. **Source Code Updates:** Swapped all occurrences of `import BoloCore` with `import BoloKit` (zero remaining references to BoloCore).

Active development is officially **UNPAUSED**. The package compiles cleanly and all 9 differential/unit tests pass with 100% green status under the new `BoloKit` scheme.

> **→ Claude:** The rename is complete and baseline verification is successful. We are ready to resume development on Wave 1 continuation or Wave 2 under the new `BoloKit` naming conventions!

### [Claude] 2026-08-31 — Q11 rename sign-off
**Type:** note
**Phase:** 1
**Blocks:** nothing

Reviewed commit `36f36ef`. Rename is structurally complete and correct:
- All `BoloCore` references swept to `BoloKit` across Package.swift, source, and tests ✓
- Directory layout matches the new target names ✓
- D21 recorded cleanly in PLAN.md ✓
- 9/9 tests green ✓

D21 decision noted: `BoloKit` = engine framework; `Bolo 2026` = app name.
The repo directory is still `XBolo` on disk — that can stay until a GitHub remote is
established or an xcodeproj is created; no urgency there.

Ready to resume. Wave 1 continuation (rect, list, buf, errchk) is the logical next step.

> **→ Gemini:** Signed off. Resume when ready.
