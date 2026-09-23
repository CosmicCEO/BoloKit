# Target UI design — informed by the original XBolo Mac interface

Written 2026-09-23 to ground the v1.6.1 visual-polish milestone (#110/#137/#140) in the
original Stuart Cheshire/Robert Chrzanowski Mac interface (`Reference/c`), which this port
already treats as its behavioral oracle for game logic. This document extends that to the
**information hierarchy and semantics** of the original's HUD, not just its simulation code.

**Hard constraint carried over from `docs/CONSTRAINTS.md:12` (D5/D10/D67): never copy the
original's art or sound files.** Everything below describes *layout, semantics, and color
meaning* studied from `Reference/c/Mac OS X/GSXBoloController.m`'s `-refresh:`,
`-setPlayerStatus:`, `-setPillStatus:`, `-setBaseStatus:`, `-setTankStatusBars`, and
`GSStatusBar.m`/`GSStatusView.m`, plus the bundled `Reference/c/Images/*.png` icons (viewed for
layout reference only). BoloKit's target is to reproduce the *meaning*, generated procedurally
by `Sources/BoloGlyphsCore/GlyphSource.swift`, exactly as it already does for terrain/sprites.

## What the original actually shows

Three separate floating `NSPanel`s (`statusPanel`, `allegiancePanel`, `messagesPanel`), each
independently toggleable, not one integrated HUD:

**Status panel** (`GSStatusView` backdrop, `GSStatusBar` bars):
- Nearest-base gauge: 3 vertical bars (armour/shells/mines, plain green fill,
  `value = amount/max`) for the closest **mutually-allied** base within 8 tiles
  (`refresh:` lines 2656-2680) — zeroed out entirely if no such base is in range. BoloKit's
  own `nearestBase` gating in `GameHUDViews.swift`/`ResourceGaugesPanel` already matches this
  exactly (confirmed in an earlier session against a live "0 armor on a hostile base" report).
- Own-tank gauges: kills/deaths as text, 4 vertical bars (shells/mines/armour/**trees**,
  `setTankStatusBars`, lines 2551-2557). BoloKit already has all 4 (`GameHUDViews.swift:222-247`,
  the trees gauge landed as D150).
- Builder status icon: direction arrow while walking, distinct "ready" and "dead/parachuting"
  glyphs (`GSBuilderStatusView`, driven every other tick from `refresh:` lines 2623-2653).
  BoloKit renders builder state **in the world** on the tank/builder sprite itself
  (`GameRenderView.swift:561-580`) rather than as a separate abstract HUD icon — a different
  but equally legible approach; not a gap, a deliberate integration choice.
- **A 16-slot player-ownership grid, a 16-slot pill-ownership grid, and a 16-slot
  base-ownership grid** (hex-indexed `0`-`F`, `IBOutlet NSImageView *player0StatusImageView`
  ... `playerFStatusImageView`, same pattern for `pill*`/`base*`, `GSXBoloController.h:84-133`).
  Each cell is one small icon reflecting that slot's live ownership/alliance state, all 16
  visible at once, no scrolling. **BoloKit has no equivalent today** — see "Gap" below.

**Allegiance panel**: a table of connected players. Each row's name has a background color
encoding connection staleness (`setPlayerStatus:`, lines 2206-2214): green background =
updated within the last second, yellow = 1-3s stale, white-on-red = 3s+ stale. This is a
**separate signal** from the tiny ownership-grid icon (which only encodes
friendly/allied/hostile, not freshness). BoloKit's `PlayerStatusGrid`
(`PlayerStatusView.swift:146-168`) already implements this exact 3-tier green/yellow/red
staleness tint on its player rows — confirmed matching.

**Messages panel**: a scrolling log, color-coded by scope (`printmessage`,
`GSXBoloController.m:3739-3777`): default = everyone, purple = allies, red = nearby, blue =
game/system. BoloKit's `EventLogBar` (`GameHUDViews.swift:341-408`) is the equivalent.

## Icon/color semantic table (the vocabulary to reproduce procedurally)

| Element | States | Rule |
|---|---|---|
| Base/pill ownership icon | Neutral, Friendly (own), Friendly (allied), Hostile, Dead (`armour < MINBASEARMOUR` / pill destroyed) | Mutual-alliance bitwise check, same as BoloKit's `testAlliance` |
| Pill "in transit" icon | IntFriendly, IntAllied, IntHostile | Separate 3-state set for a pill riding onboard a tank vs. deployed (`ONBOARD` case, lines 2354-2369) |
| Player ownership icon | Friendly (self), AlliedFriendly, Hostile | No neutral state for players; only 3 variants, distinct from base/pill's richer set |
| Player row background (allegiance panel) | Green / Yellow / White-on-red | Connection staleness in ticks since last update, independent of the ownership icon above |
| Resource bar | Flat green fill, 0.0-1.0 of max | Same visual language for both own-tank and nearest-base gauges — no per-resource color coding (all green) |
| Chat message color | Default / purple / red / blue | Everyone / allies / nearby / game-system scope |

## Gap analysis against BoloKit's current HUD

**Already matches or deliberately, correctly diverges** (no action needed):
- Mutual-alliance-only nearest-base display — matches exactly.
- Player staleness tint (green/yellow/red) — matches exactly.
- Own-tank 4-gauge set including trees — matches.
- Chat scope coloring — equivalent, matches semantics.
- Single integrated overlay HUD vs. three separate floating panels — deliberate, sensible
  modernization for a single-window-per-Mac game; not a target to walk back.
- Builder state shown in-world on the sprite vs. a dedicated abstract icon — equivalent
  information, different (arguably clearer) presentation; not a gap.

**Genuine gap, not currently scoped in any open issue:**
- **No map-wide pill/base ownership overview.** The original's 16-slot grids let a player see
  every pill's and base's ownership state at a glance without panning the map. BoloKit has no
  equivalent — a player currently has to scroll/zoom out to see ownership across the map. This
  is a real, historically-present feature this port is missing, not an art-polish nit.

This gap is **out of scope for the current v1.6.1 milestone as written** (#110/#137/#140 are
scoped narrowly per `docs/STATUS.md`'s own MVP limits) and is not being filed as a new issue
automatically — flagging it here as a considered, deliberate omission pending a decision on
whether it's worth its own issue (it would be net-new HUD surface, not "chrome the sprites").

## How this informs the three in-flight issues

- **#110 (chrome the sprites):** the original's ownership icons are small, flat, single-color
  shapes (dot/square/diamond-style glyphs per the `BaseStat*`/`PillStat*`/`PlayerStat*` icons)
  — legible at 12-16px specifically *because* they're simple. The target for #110's terrain
  refinement is **legibility at a glance, not photorealism** — better bevels/shading on the 7
  terrain families (per the existing plan in this doc's companion section of `STATUS.md`),
  while keeping ownership glyphs (tank/pill/base) simple enough to read instantly during play.
  Don't let #110 drift toward busier, harder-to-read iconography in the name of "polish."
- **#137 (black seams):** no UI-semantics implication — purely a Metal geometry bug, plan
  unchanged (see `docs/STATUS.md`).
- **#140 (client info panels don't match host):** confirms the *target* is host/guest visual
  parity on the shared data (ownership icons, staleness tint, resource gauges) with host-only
  admin chrome (Kick/Ban, Banned list) as legitimate, intentional asymmetry — matching the
  original's own model of host-only vs. universal information. Reinforces the MVP scoping
  already written in `docs/STATUS.md`: fix the `connectionAge` guest data gap, don't try to
  hide or replicate host-only controls for guests.
