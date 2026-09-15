# BoloKit / Bolo 2026

Swift port of [XBolo](https://github.com/bananazon/xbolo) (MIT), itself a clone of Stuart Cheshire's *Bolo*. Engine is the **BoloKit** Swift package; the playable Mac app is **Bolo 2026**. macOS 26+.

This repo is a product and a Swift/Xcode/networking learning vehicle. It is not a lab for multi-agent workflows. Do not restore a Planner / Implementer / Parity / Admin split, wave GOs, or an `AGENT_NOTES.md` scratchpad.

## Oracle and license

- `Reference/c` is a git submodule of xbolo. Keep it. It is the live, executable spec: differential tests run C and Swift side by side.
- You may read, port, and adapt xbolo's MIT `.m`/`.h` (including `GSXBoloController.m` / `GSBoloView.m`).
- Stuart Cheshire's original art and sound bytes (via `images.h`) are copyrighted. Never copy them. Glyphs and sounds in this repo are generated.
- WinBolo / LinBolo is GPL v2. Read-only clean-room only: no copying, transliterating, or importing its architecture. Fidelity target is Mac Bolo **0.99.7bv**, not WinBolo. No WinBolo network interop.
- Do not add TCMPortMapper or any other GPL NAT/UPnP helper.

## Standing constraints

- `Float` for position, physics, and trig. Never `Double` or `CGFloat`.
- No `import Foundation` in `BoloKit`. `import Darwin` is fine for C primitives.
- Copy C float literals exactly (`0.70711219`, never `Float(sqrt(2)/2)`).
- `CXBolo` must keep `-ffp-contract=off` (`Package.swift`). Do not remove it.
- Do not shrink tests or docs without a named replacement. Report before/after test counts.
- Physics constants live in `Physics.swift`. Values are tabulated in `docs/CONSTRAINTS.md` against `bolo.h` macros — do not re-derive.
- Simulation tick is 50 Hz (`ticksPerSec`).
- Port is behaviour-preserving against the C oracle (including known C bugs) unless a constraint here already documents a deviation.
- No paid Apple Developer Program: the app ships Apple Development-signed, not notarized. Gatekeeper needs a one-time right-click → Open. Do not add signing/notarization work.
- `NWListener` EINVAL on some machines is a known environment issue. The app already falls back to local-only play with an on-screen notice. Do not reopen an unbounded investigation.

Match existing code. Prefer `swift test` / `xcodebuild` over claims.

## Commands

```bash
swift build
swift test
swift test --filter <TestNameOrSuite>
xcodebuild -project "Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" build
xcodebuild -project "Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" \
  -only-testing:"Bolo 2026Tests" test
```

## Current ship

`v1.1.0` (build 6). Playable host-and-join. 775 SwiftPM tests (BoloKitTests + DifferentialTests) plus 49 `Bolo 2026Tests`. One pre-existing flaky timing test exists; do not treat a single isolated flake of that class as a new regression.

Open product work: GitHub issues (summary in `docs/STATUS.md`). Next sprints: #1 fog-of-war, #6 dedicated host.

## Further reading

- `docs/STATUS.md` — current state and open backlog
- `docs/CONSTRAINTS.md` — fidelity benchmarks and physics constants
- `docs/ORACLE_COVERAGE.md` — C-function coverage snapshot (verify against `Sources/` before treating a row as still open)
- `docs/notes/HOSTMODELS.md` — in-process host vs dedicated server research
- Wave history and the old four-role process: `git show legacy-agent-process:docs/PLAN.md`
