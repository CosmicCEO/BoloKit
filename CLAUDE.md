IMPLEMENTER Bootstrap

[ADMINISTRATIVE CONVENTIONS SECTION]

> **Read this first, then `git log --oneline -5 && git status`, before anything else.** This file
> can lag reality. For full wave status/decisions text: `docs/PLAN.md`. For the latest events:
> the tail of `docs/AGENT_NOTES.md`. Other agent bootstraps are available for partner context: `docs/PARITY.md`, `docs/PLANNER.md`.

## Your role

Write Swift, own `DifferentialTests`, commit to `main`. You do NOT edit `docs/PLAN.md` or assign
waves — that's PLANNER agent's role. You DO own detailed code-level planning for your own waves: read the relevant source yourself, write your own pre-brief into `docs/AGENT_NOTES.md` before coding, same rigor PARITY audits you on. Never declare a wave "done" or change architecture unilaterally — wait for PLANNER's GO. Log ambiguous calls as a question for PLANNER rather than resolving solo.

## Git workflow (non-negotiable)

1. Write → build → test.
2. `git add <specific files>` — never `-A`.
3. `git commit -m "Wave X.Y: <description>"`.
4. Append your completion report / pre-brief to `docs/AGENT_NOTES.md`, commit that too — even a planning-only session with no Swift written. A report that lives only in chat doesn't exist for PLANNER or PARITY until committed.
5. When prompted by user, you are able to authenticate to GitHub by  `gh auth status` confirms a logged-in `CosmicCEO` token (`repo`/`workflow` scope) and `origin`
   is `github.com/CosmicCEO/BoloKit.git`. We will reconcile GITHUB only after major coding milestone defined by PLANNER.

## Coding conventions

- No `import Foundation` in `BoloKit` sources; `import Darwin` is fine for C-library primitives.
- Copy float literals from C exactly (`0.70711219`, never `Float(sqrt(2)/2)`).
- D18: Float everywhere for position/physics/trig, never `Double`/`CGFloat`.
- D28: no test/doc coverage shrinks without a stated replacement; report before/after test counts.
- Physics constants: `Physics.swift`, tabulated against C macro names in `PLAN.md`'s Wave 5.0 section — don't re-derive.

### Licensing — read this before touching `Reference/c`

`Reference/c` (xbolo, the C oracle this whole project ports from) is **MIT-licensed** (see `Reference/c/LICENSE`; D1/D13). You may read, port, and directly transcribe/adapt its `.m`/`.h` source — including the UI layer (`GSXBoloController.m`, 4,037 lines; `GSBoloView.m`, 600 lines) 

**D25/D33's clean-room restriction applies only to
WinBolo (GPL v2), not to Reference/c.

**art/sound assets** bundled in xbolo (referenced via `images.h`) are Stuart Cheshire's original
copyrighted material — never copy those bytes; project must regenerate everything from permissive sources instead.


[PLANNER PRIVIDED INSTRUCTIONS SECTION]

## Current scope: Wave 7 — UI / app phase, v1 vertical-slice cut (D60)

**You're picking this up fresh.** Wave 6 (all of networking, 6.0–6.6) is closed and PARITY-PASS.
Jerod ruled the post-Wave-6 fork: build the UI next, but scoped to a single-process, single-player
playable slice first — not the full multiplayer/HUD/polish scope. Read `docs/PLAN.md`'s Wave 7 row
and D60 for the authoritative text; this is a working summary.

**Coding-GO'd now — sub-waves 7.0 through 7.3, in dependency order:**

- **7.0 — Asset pipeline.** `Sources/BoloGlyphs` is currently a one-line stub, but the parse step
  isn't — `Sources/BoloKit/Images.swift` already has all 290 `images.h` constants and both
  `mapimage()` overloads, ported and tested in an earlier wave. Build the sheet writer on those;
  don't re-parse `images.h`. **Corrected 2026-09-04 (D62/D63, PARITY factual audit — the old
  "297 indices/one sheet" text below was wrong):** `images.h` is two independent index spaces for
  two sheets (`GSBoloView.m` loads `"Tiles"` and `"Sprites"` separately as distinct `NSImage`s),
  each resetting to `0x00` — **tiles: 177 names, dense `0x00`–`0xb0`**; **sprites: 113 names,
  sparse `0x00`–`0x91`** (177+113=290; index collisions across the two spaces, e.g. `0x08` =
  `WALL38IMAGE` in tiles vs. `PTKB08IMAGE` in sprites, are normal — the spaces are never compared).
  Emit two 256×256 sheets, not one. **Pick and document one sheet row-0 convention in your
  pre-brief (D64):** the C original never sets `isFlipped` on `GSBoloView`, so its
  `row = idx >> 4` math is implicitly bottom-left-origin — you have no fidelity obligation to keep
  that for freshly-generated sheets, but whichever you pick, 7.2 must consume the same one. `-1` is
  a "no image" sentinel in the reference, never a valid sheet index. Generate everything from
  **permissive sources only** (OFL fonts, synthesized sounds) — see licensing note below. Do not
  touch or reference the original art/sound bytes.
- **7.1 — Xcode app target.** No `.xcodeproj` exists; the project is SPM-only (`Package.swift`:
  BoloKit, CXBolo, BoloNet, BoloGlyphs, BoloKitTests, DifferentialTests). This wave creates the
  actual macOS app shell wrapping the SPM package. Blocks 7.2 and 7.3.
- **7.2 — Game rendering.** The draw loop replicating `GSBoloView.m`'s role (600 lines): terrain +
  tanks from a live `GameState`. **SwiftUI Canvas/TimelineView vs. AppKit `NSView`/`CALayer` via
  `NSViewRepresentable` is your call to prototype and propose in your pre-brief** — not something
  requiring Jerod's ruling up front. PLANNER reviews whichever approach you propose against D41's
  tick-timing discipline before the coding GO on this sub-wave stands. **Fog-of-war scope, ruled
  2026-09-04 (D65):** the reference draws from three display-side arrays the C client computes —
  `client.images[y][x]`, `isMinedTile(client.seentiles, …)`, `client.fog[y][x]` — none of which this
  port has ever modeled (`Sources/BoloKit/BMap.swift` says so in its own comments). Out of scope for
  v1: treat every tile as fully visible, populate the sheet index straight from `mapimage()` per
  tile, no `seentiles`/`fog` layer needed. Real fog-of-war/seen-tiles display is deferred scope for
  a later wave, not a v1 blocker.
- **7.3 — Input + tick loop.** Single-process only, no networking wiring in this slice.

**Pre-built hooks already in place from Wave 6** (don't rebuild these): `TCPSession.swift` and
`HostSession.swift` already expose `onPlayerStatusChanged`, `onPillStatusChanged`,
`onBaseStatusChanged`, `onTankStatusChanged`, `onMineExplosion`, `onSuperboomTerrain`,
`onDropPills`, and others — these are the exact hook points `GSXBoloController.m`'s C callbacks
(`setplayerstatus`, `setpillstatus`, `settankstatus`, etc.) map onto.

