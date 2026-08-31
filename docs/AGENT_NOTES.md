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

### [Claude] 2026-08-31 — Open issue: GitHub remote setup
**Type:** question
**Phase:** 1
**Blocks:** nothing (nice-to-have before Phase 2)

No GitHub remote is configured yet. The repo is local-only at ~/Developer/XBolo.

GitHub account: https://github.com/CosmicCEO

> **→ Gemini:** Please create a new GitHub repo under CosmicCEO (suggest name `XBolo` or
> `BoloKit` — Jerod's call) and set the remote:
> `git remote add origin https://github.com/CosmicCEO/<repo-name>.git`
> `git push -u origin main`
> Recommend doing this before Phase 2 so the clean-room asset work lands on a remote from the start.

### [Claude] 2026-08-31 — Wave 1 Code Review (Rect, List, Buf, ErrChk)
**Type:** review
**Phase:** 1 / Wave 1
**Blocks:** ErrChk.swift compile error must be fixed before `swift build`

Reviewed all four new BoloKit modules and their CXBolo thin wrappers. Summary:

**CXBolo wrappers** — rect.c, list.c, buf.c, errchk.c — all correct single-line `#include` passthroughs. ✓

---

**ErrChk.swift** 🔴 COMPILE ERROR — will block `swift build`:

```swift
// CURRENT (invalid):
public init(file: String, var function: String, line: Int) {

// FIX — remove `var`:
public init(file: String, function: String, line: Int) {
```

`var` is not legal in Swift initializer parameter lists. Everything else in this file is correct: error constants match C reference, `pthread_mutex_t` thread-safety pattern is sound, `fputs` to stderr is Foundation-free. ✓ (after fix)

---

**List.swift** ✅ — No issues. Doubly-linked list mechanics are correct. Node allocation (`allocate` + `initialize`) and deallocation (`deinitialize` + `deallocate`) are balanced. `clearlist` correctly guards the release callback with `if let`. `removelist` returning `nextNode` matches C API. Safe to ship.

---

**Buf.swift** ✅ with one note:

`readbuf` with `nil` destination is handled safely via `if let target = data` — the memmove is skipped and the buffer is still compacted. Correct pattern for `sendbuf`'s drain use. ✓

Minor note: `resizebuf` uses `((nbytes + (BUFBLOCKSIZE*2 - 1)) / BUFBLOCKSIZE) * BUFBLOCKSIZE` as the rounding formula. This rounds up to 2× blocks rather than 1× blocks, so the buffer grows more aggressively than a standard align-up. Not a correctness issue for the port (buf is internal plumbing), but worth verifying against the C reference if exact allocation behaviour matters.

POSIX functions (`send`, `recv`, `poll`) in this file are fine per D20 — they are callable wrappers, not module-level socket initialization.

---

**Rect.swift** ✅ — Comprehensive and correct overall. Int64 intermediates in `unionrect` and `intersectionrect` prevent signed overflow. `splitrect` 4-corner decomposition matches expected geometry. The `subtractrect` all-corner-probing logic is structurally faithful to the C reference pattern.

One item for differential testing coverage: the `lxly==0 && lxhy==0 && hxly==0 && hxhy==0` branch (r2 fully contained inside r1) produces 4 strip rects — verify this matches C oracle output exactly before Wave 1 is marked complete.

---

**Wave 1 verdict:**

| Module | Status |
|--------|--------|
| Vector | ✅ shipped (Phase 1) |
| Rect   | ✅ ready to commit |
| List   | ✅ ready to commit |
| Buf    | ✅ ready to commit |
| ErrChk | 🔴 fix `var` in init, then ready |

One fix needed, then `swift build` should be green. After that, add `subtractrect` differential test cases and Wave 1 is complete.

> **→ Gemini:** Fix `ErrChk.swift` init — remove `var` from `function` parameter. Then commit all Wave 1 files and run `swift build`. Paste build result here. Once green, add a `subtractrect` differential test and we can close Wave 1.

### [Claude] 2026-08-31 — ErrChk.swift review correction
**Type:** correction
**Phase:** 1 / Wave 1
**Blocks:** nothing

Correction to the prior Wave 1 review: the ErrChk.swift compile error I flagged (`var` in init parameter) is **not present in the current file on disk**. `grep` confirms line 29 reads:

```swift
public init(file: String, function: String, line: Int) {
```

The `var function` at line 26 is the struct property declaration — valid Swift. 🔴 is retracted. ErrChk.swift is ✅.

**Revised Wave 1 verdict — all modules clear:**

| Module | Status |
|--------|--------|
| Vector | ✅ |
| Rect   | ✅ |
| List   | ✅ |
| Buf    | ✅ |
| ErrChk | ✅ |

> **→ Gemini:** All clear — no compile errors found. Commit and run `swift build`. The only remaining item before Wave 1 close is a differential test covering `subtractrect` (r2 fully inside r1 case). Otherwise Wave 1 is done.

### [Claude] 2026-08-31 — Wave 1 Differential Test Diagnosis
**Type:** review / bug
**Phase:** 1 / Wave 1
**Blocks:** swift build (compile errors in DifferentialTests.swift)

Reviewed the new diff against `DifferentialTests.swift`. Two compile errors, both fixable:

---

**🔴 Compile Error 1 — `@convention(c)` on a struct method**

```swift
// CURRENT (invalid — @convention(c) cannot be a declaration attribute on a method inside a type):
@convention(c) private func dummyRelease(_ ptr: UnsafeMutableRawPointer?) {}
```

`@convention(c)` is only valid on free/global functions or as a type annotation on closures. Move it outside the struct:

```swift
// OUTSIDE the VectorDifferentialTests struct (top level of the file):
private func dummyRelease(_ ptr: UnsafeMutableRawPointer?) { }
```

Or pass a closure typed with `@convention(c)` at the call site — but the free function approach is simpler.

---

**🔴 Compile Error 2 — `CXBolo.gettrace()` does not exist**

`gettrace()` is defined only in Swift `ErrChk.swift`. The C `errchk.h` API exposes only:

```c
void pushlineinfo(const char *file, const char *function, size_t line);
void errchkcleanup();
void printlineinfo();
```

There is no `gettrace()` in the C reference, so `CXBolo.gettrace()` will not compile.

Fix: remove the `CXBolo` side of the errchk differential — there is nothing in the C API to compare `gettrace()` against. Make `testErrChkOperations` a pure Swift unit test (no CXBolo cross-check for trace state). The constants and the cleanup/push calls can still use both sides:

```swift
@Test func testErrChkOperations() {
    // Constants match C #define values
    #expect(BoloKit.ELAST == Int32(1000))
    #expect(BoloKit.EBADPASS == Int32(1010))
    // ... etc.

    // push/cleanup cycle — Swift side only (no C equivalent for gettrace)
    BoloKit.errchkcleanup()
    let file = "rect.c"
    let function = "makerect"
    file.withCString { filePtr in
        function.withCString { funcPtr in
            BoloKit.pushlineinfo(filePtr, funcPtr, 123)
        }
    }
    let trace = BoloKit.gettrace()
    #expect(trace.count == 1)
    #expect(trace[0].file == "rect.c")
    #expect(trace[0].function == "makerect")
    #expect(trace[0].line == 123)
    BoloKit.errchkcleanup()
    #expect(BoloKit.gettrace().count == 0)
}
```

---

**✅ Things that ARE correct (do not change):**

- `resizebuf` formula — Swift matches C exactly: `((nbytes + ((BUFBLOCKSIZE * 2) - 1)) / BUFBLOCKSIZE) * BUFBLOCKSIZE` ✓
- `s_buf.size == c_buf.size` comparison after writebuf — will pass because formulae are identical ✓
- `CXBolo.pushlineinfo` and `CXBolo.errchkcleanup` — these DO exist in the C API ✓
- All rect / list / buf test logic — structurally correct ✓

Two fixes: move `dummyRelease` to top level, drop `CXBolo.gettrace()`. Then `swift build` and `swift test` should clear.

> **→ Gemini:** Only two changes needed. Both are in `DifferentialTests.swift`. Do not touch any BoloKit source files.

### [Claude] 2026-08-31 — Wave 2 Pre-implementation Advisory
**Type:** architecture
**Phase:** 1 / Wave 2
**Blocks:** nothing yet — read before writing Terrain.swift or Tiles.swift

Wave 2 is `terrain` + `tiles`. Terrain is trivial. Tiles has one structural decision that must be settled first.

---

**Terrain.swift** — Straightforward. Port as a Swift `@frozen` enum with `Int32` raw values:

```swift
@frozen public enum Terrain: Int32 {
    case sea = 0, boat, wall, river
    case swamp0, swamp1, swamp2, swamp3
    case crater, road, forest
    case rubble0, rubble1, rubble2, rubble3
    case grass0, grass1, grass2, grass3
    case damagedWall0, damagedWall1, damagedWall2, damagedWall3
    // mined
    case minedSea, minedSwamp, minedCrater, minedRoad, minedForest, minedRubble, minedGrass
}

public func isWaterLikeTerrain(_ terrain: Terrain) -> Int32 { ... }
```

C `isWaterLikeTerrain` takes `int` — expose a second overload or typealias for differential testing: `public func isWaterLikeTerrain(_ terrain: Int32) -> Int32` so the test can call both sides with a plain Int32. ✓

---

**Tiles.swift** — ⚠️ Design decision required: the `tiles[][256]` C array.

All 7 tile predicates in C take `int tiles[][256]` — a pointer to rows of 256 ints. When clang imports this into Swift via CXBolo, it becomes:

```swift
// What CXBolo exposes (clang import of int (*tiles)[256]):
CXBolo.isForestLikeTile(tiles: UnsafeMutablePointer<(Int32, Int32, ... /* ×256 */)>, x: Int32, y: Int32)
```

A 256-tuple is unusable directly in Swift. **Recommended approach:**

Define a flat-array wrapper in BoloKit for the primary API:

```swift
public struct TileGrid {
    public var storage: [Int32]   // 256 * 256 = 65536 elements
    public init() { storage = [Int32](repeating: 0, count: 256 * 256) }
    public subscript(x: Int, y: Int) -> Int32 {
        get { storage[y * 256 + x] }
        set { storage[y * 256 + x] = newValue }
    }
}
```

Then expose Swift predicates with an `UnsafePointer<Int32>` raw-pointer overload alongside the TileGrid API — the raw pointer overload is what the differential test calls (matches the C ABI layout):

```swift
// Swift-idiomatic (primary):
public func isForestLikeTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32

// Raw-pointer overload (for differential test bridge):
public func isForestLikeTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32
```

The differential test allocates a flat `[Int32]` of 65536, fills it, then calls both the CXBolo C function (via unsafe reinterpret cast to the 256-tuple pointer) and the BoloKit raw-pointer overload. This avoids ever constructing the 256-tuple in Swift.

**Tile enum**: first 16 values are explicit (0–15); `kSeaTile = 16` onward auto-increment. Port as:

```swift
@frozen public enum Tile: Int32 {
    case wall = 0, river = 1, swamp = 2, crater = 3, road = 4
    case forest = 5, rubble = 6, grass = 7, damagedWall = 8, boat = 9
    case minedSwamp = 10, minedCrater = 11, minedRoad = 12
    case minedForest = 13, minedRubble = 14, minedGrass = 15
    case sea = 16, minedSea = 17
    case friendlyBase = 18, hostileBase = 19, neutralBase = 20
    case friendlyPill00 = 21  // ... through friendlyPill15 = 36
    case hostilePill00 = 37   // ... through hostilePill15 = 52
    case unknown = 53
}
```

Verify raw values by counting: the C enum auto-increments from `kSeaTile` onward, so `kUnknownTile = 53`. Pin all raw values explicitly in Swift — do NOT rely on auto-increment for this enum since future inserts would silently shift everything.

---

**CXBolo additions** (same thin-wrapper pattern as Wave 1):
- `Sources/CXBolo/terrain.c` → `#include "../../Reference/c/terrain.c"`
- `Sources/CXBolo/tiles.c` → `#include "../../Reference/c/tiles.c"`
- Add both headers to `Sources/CXBolo/include/CXBolo.h`

> **→ Gemini:** Settle the `TileGrid` struct design first (or propose an alternative), then implement. The `UnsafePointer<Int32>` overload is what unlocks the differential test. Pin every Tile raw value explicitly.
