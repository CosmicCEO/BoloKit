# BoloKit & Bolo 2026 (Modern Swift Port of XBolo)

A modern Swift port of [XBolo](https://github.com/bananazon/xbolo), a Cocoa clone of Stuart
Cheshire's classic multiplayer tank game *Bolo*. This project is designed as an engine-forward platform (built as the **BoloKit** framework package) supporting future expansions, mods, and AI agents, with the playable Mac app target built on top named **Bolo 2026**.

This repository exists to learn modern Xcode, Swift, on-device AI (FoundationModels), and multiplayer networking, and to end up with a Bolo engine you can play natively on modern macOS (macOS 26+ / Darwin 27+).

Bolo is not otherwise unmaintained — [WinBolo 2](https://store.steampowered.com/app/4672140/WinBolo/) shipped in 2026 with native Mac support.
This project is a personal learning vehicle, not a competing distribution.

## Oracle & Attribution

This is a derivative Swift port of **[XBolo](https://github.com/bananazon/xbolo)** (MIT-licensed),
itself a clone of Stuart Cheshire's original *Bolo*. `Reference/c` holds XBolo's C/Objective-C
source in-tree as a git submodule — kept there permanently, not as a historical artifact pending
removal, because it's a live, executable oracle: every ported module is checked against it with
differential tests. See `LICENSE` for the full attribution chain and license terms.

## Status

Phase 3 (incremental Swift port, C oracle as spec) is complete. Waves 1-5 -- leaf utilities,
terrain/tiles, BMAP, and the full simulation core (tank/shell/builder/pillbox physics, mine
chains and explosions, spawn/respawn, tree growth) -- Wave 6 (networking: wire codec, tick
orchestrator, broadcast/session handlers, transport, tracker protocol + NAT-PMP) -- and Wave 7's
v1 vertical slice (asset pipeline, an Xcode app target, game rendering, and the input/tick loop)
are all complete and verified against the C reference. **`v1.0.0` shipped** (real,
non-prerelease GitHub release). Current drop is **`v1.2.3`** (build 10). 795
SwiftPM tests (BoloKitTests + DifferentialTests) plus 66 app-target tests (`Bolo 2026Tests`)
are passing (one pre-existing, documented flaky timing test excluded from that count's
stability claim -- see `docs/STATUS.md`). **`Bolo 2026` is playable, host-and-join
multiplayer**: a window opens with an always-visible HUD (build-tool selector, resource gauges,
player/pill/base status, bottom event-log bar), renders a real bundled default map (or an imported one) from generated
assets, and drives a tank via the actual physics engine, keyboard- and mouse-controlled
(click-to-command the builder, matching the original's own unlimited-range design) and
tick-driven, over a real live network session. **Milestone B** (Host/Join UI wired to the
networking layer) is fully closed, including B.10's full join-side outbound protocol (movement,
tile-entry, builder-task, and shell-impact reporting). **Milestone C** is closed -- HUD
status panel + kick/ban (C.0), key remap (C.1), the alliance panel (C.2), messages panel (C.4),
procedural sound synthesis (C.3, 24 effects generated, several wired to gameplay events including
cannon fire and tree harvest), and the preferences shell (C.5). **Milestone D.0** (zoom/scroll)
and **D154** (terrain/HUD chrome/event-log visual pass) are closed. Signing/notarization is out
of scope permanently (no paid Apple Developer Program enrollment), so the app ships with real
Apple Development code signing, not notarized, and a fresh download needs a one-time right-click
→ Open to bypass Gatekeeper's warning. A known, unresolved
environment issue on some machines causes `Network.framework`'s listener creation to fail; the
app falls back automatically to local-only play in that case, with an on-screen notice -- root
cause not found despite investigation (ruled out: beta-OS-specific, ad-hoc signing), deliberately
not under active investigation to avoid further escalation-of-commitment cost. Win/loss overlay and host-admin pause/allow-join/unban are in `v1.1.0`.
Still filed: a `hiddenmines`-style fog-of-war mode ([#1](https://github.com/CosmicCEO/BoloKit/issues/1)).
See `docs/STATUS.md` for current state and open backlog, `docs/CONSTRAINTS.md` for standing engineering rules. Wave history is in git at tag `legacy-agent-process`.

## Approach

- `Reference/` holds the original xbolo C/Objective-C source as a git submodule. It is
  kept building throughout the port and used as an executable oracle: every ported
  module is checked against it with differential tests before its callers switch over.
- `Sources/BoloKit` is the target: a pure Swift simulation with no AppKit dependency,
  shared by both the client and server roles (the original kept two separate copies).
- Fidelity to the original 1993 Macintosh Bolo (version 0.99.7bv) is tracked in
  `docs/CONSTRAINTS.md`, against the C oracle — not from other GPL-licensed Bolo
  implementations, to keep this project's license clean.
- All sprite/tile art is generated from Unicode/ASCII glyphs rather than reproduced from
  the original's copyrighted assets.

## Contributors

Human + AI pair-programming. Project instructions for agents are in `AGENTS.md`.

## Licensing

This repository is MIT-licensed — see `LICENSE`, which retains the original XBolo
copyright notice as required by its terms.

XBolo itself bundles a separate dependency, TCMPortMapper, under the GPLv3, used for
UPnP/NAT-PMP port mapping. **That dependency is not used here.** Any NAT-traversal
functionality in this port will use a permissively-licensed alternative or manual port
forwarding, specifically to avoid GPL-encumbering this codebase.
