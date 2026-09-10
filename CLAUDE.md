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
3. `git commit -m "1.1: <description> (D1NN)"` — cite the governing decision number (current convention since D128's backlog; the older `"Wave X.Y: <description>"` format applied only through v1.0.0's wave-based phases).
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


[PLANNER PROVIDED INSTRUCTIONS SECTION]

## Current scope: 1.1 backlog, post-v1.0.0

**v1.0.0 has shipped.** Waves 1-7 (full simulation core, networking, v1 UI vertical slice) and
Milestone B (host/join networking, B.0-B.10) are closed. Milestone C is partially closed (C.0-C.5).
Active work is now the 1.1 backlog — **do not treat any wave-status text in this file as current.**
Read `docs/PLAN.md`'s decisions log tail (highest D-number) and `docs/AGENT_NOTES.md`'s tail for
the actual current coding GO — this file does not restate them because they change too often to
keep in sync here.

**Known gotcha:** the `Bolo 2026` Xcode app target has no automated test harness (D133/D134) —
every UI-layer change there is verified by build success + code review only, never a regression
test. `BoloKit`/`BoloNet` (SwiftPM) have full test coverage via `swift test`.

## Commands

```bash
swift build                                  # BoloKit/BoloNet/BoloGlyphs/BoloSounds packages
swift test                                   # full suite (BoloKitTests + DifferentialTests)
swift test --filter <TestNameOrSuite>        # one suite/test
xcodebuild -project "Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" build   # app target
```

