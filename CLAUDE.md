# BoloKit — IMPLEMENTER Bootstrap

> **Read this first, then `git log --oneline -5 && git status`, before anything else.** This file
> can lag reality. For full wave status/decisions text: `docs/PLAN.md`. For the latest events:
> the tail of `docs/AGENT_NOTES.md`. Other bootstraps: `docs/PARITY.md`, `docs/PLANNER.md`.

## Your role

Write Swift, own `DifferentialTests`, commit to `main`. You do NOT edit `docs/PLAN.md` or assign
waves — that's PLANNER's. You DO own detailed code-level planning for your own waves: read the
relevant source yourself, write your own pre-brief into `docs/AGENT_NOTES.md` before coding,
same rigor PARITY audits you on. Never declare a wave "done" or change architecture unilaterally
— wait for PLANNER's GO. Log ambiguous calls as a question for PLANNER rather than resolving solo.

## Git workflow (non-negotiable)

1. Write → build → test.
2. `git add <specific files>` — never `-A`.
3. `git commit -m "Wave X.Y: <description>"`.
4. Append your completion report / pre-brief to `docs/AGENT_NOTES.md`, commit that too — even a
   planning-only session with no Swift written. A report that lives only in chat doesn't exist to
   PLANNER or PARITY.
5. Tell Jerod — he relays and pushes (your sandbox can't authenticate to GitHub; expected).

PARITY activation (`[TO: PARITY]`) is PLANNER's call, not yours.

## Coding conventions

- No `import Foundation` in `BoloKit` sources; `import Darwin` is fine for C-library primitives.
- Copy float literals from C exactly (`0.70711219`, never `Float(sqrt(2)/2)`).
- D18: Float everywhere for position/physics/trig, never `Double`/`CGFloat`.
- D28: no test/doc coverage shrinks without a stated replacement; report before/after test counts.
- Physics constants: `Physics.swift`, tabulated against C macro names in `PLAN.md`'s Wave 5.0
  section — don't re-derive.

---

## Current scope: Wave 7 — UI / app phase, v1 vertical-slice cut (D60)

**You're picking this up fresh.** Wave 6 (all of networking, 6.0–6.6) is closed and PARITY-PASS.
Jerod ruled the post-Wave-6 fork: build the UI next, but scoped to a single-process, single-player
playable slice first — not the full multiplayer/HUD/polish scope. Read `docs/PLAN.md`'s Wave 7 row
and D60 for the authoritative text; this is a working summary.

**Coding-GO'd now — sub-waves 7.0 through 7.3, in dependency order:**

- **7.0 — Asset pipeline.** `Sources/BoloGlyphs` is currently a one-line stub. `Reference/c/images.h`
  defines 297 `#define ...IMAGE` indices (roughly `0x00`–`0x91`), fitting one 256-cell (16×16) sheet
  — matches the old Phase 2 assumption. Generate sprite/tile sheets from **permissive sources only**
  (OFL fonts, synthesized sounds) — see licensing note below. Do not touch or reference the original
  art/sound bytes.
- **7.1 — Xcode app target.** No `.xcodeproj` exists; the project is SPM-only (`Package.swift`:
  BoloKit, CXBolo, BoloNet, BoloGlyphs, BoloKitTests, DifferentialTests). This wave creates the
  actual macOS app shell wrapping the SPM package. Blocks 7.2 and 7.3.
- **7.2 — Game rendering.** The draw loop replicating `GSBoloView.m`'s role (600 lines): terrain +
  tanks from a live `GameState`. **SwiftUI Canvas/TimelineView vs. AppKit `NSView`/`CALayer` via
  `NSViewRepresentable` is your call to prototype and propose in your pre-brief** — not something
  requiring Jerod's ruling up front. PLANNER reviews whichever approach you propose against D41's
  tick-timing discipline before the coding GO on this sub-wave stands.
- **7.3 — Input + tick loop.** Single-process only, no networking wiring in this slice.

**Pre-built hooks already in place from Wave 6** (don't rebuild these): `TCPSession.swift` and
`HostSession.swift` already expose `onPlayerStatusChanged`, `onPillStatusChanged`,
`onBaseStatusChanged`, `onTankStatusChanged`, `onMineExplosion`, `onSuperboomTerrain`,
`onDropPills`, and others — these are the exact hook points `GSXBoloController.m`'s C callbacks
(`setplayerstatus`, `setpillstatus`, `settankstatus`, etc.) map onto.

**NOT GO'd — do not start without a fresh GO from PLANNER:** Milestone B (multiplayer UI —
host/join panels, join-progress), Milestone C (full HUD, preferences, chat, sound), Milestone D
(polish/ship, including Q18's git-history rewrite to purge original asset bytes before any public
push — destructive, must be raised explicitly before ever executing).

### Licensing — read this before touching `Reference/c`

`Reference/c` (xbolo, the C oracle this whole project ports from) is **MIT-licensed** (see
`Reference/c/LICENSE`; D1/D13). You may read, port, and directly transcribe/adapt its `.m`/`.h`
source — including the UI layer (`GSXBoloController.m`, 4,037 lines; `GSBoloView.m`, 600 lines) —
same as every Phase 3 engine wave has done. **D25/D33's clean-room restriction applies only to
WinBolo (GPL v2), not to Reference/c.** The actual constraint for Wave 7 is different: the
**art/sound assets** bundled in xbolo (referenced via `images.h`) are Stuart Cheshire's original
copyrighted material — never copy those bytes; 7.0 must regenerate everything from permissive
sources instead.
