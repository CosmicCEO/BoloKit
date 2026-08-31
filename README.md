# BoloKit & Bolo 2026 (Modern Swift Port of XBolo)

A modern Swift port of [XBolo](https://github.com/bananazon/xbolo), a Cocoa clone of Stuart
Cheshire's classic multiplayer tank game *Bolo*. This project is designed as an engine-forward platform (built as the **BoloKit** framework package) supporting future expansions, mods, and AI agents, with the playable Mac app target built on top named **Bolo 2026**.

This repository exists to learn modern Xcode, Swift, on-device AI (FoundationModels), and multiplayer networking, and to end up with a Bolo engine you can play natively on modern macOS (macOS 26+ / Darwin 27+).

Bolo is not otherwise unmaintained — [WinBolo 2](https://store.steampowered.com/app/4672140/WinBolo/)
shipped in 2026 with native Mac support. This project is a personal learning vehicle,
not a competing distribution.

## Status

Phase 1 (Differential Test Harness) and Waves 1 & 2 (Leaf utilities + Terrain and Tile grids) are fully completed, with 15/15 robust differential tests passing side-by-side with the C reference oracle. See `docs/PLAN.md` for upcoming phases.

## Approach

- `Reference/` holds the original xbolo C/Objective-C source as a git submodule. It is
  kept building throughout the port and used as an executable oracle: every ported
  module is checked against it with differential tests before its callers switch over.
- `Sources/BoloKit` is the target: a pure Swift simulation with no AppKit dependency,
  shared by both the client and server roles (the original kept two separate copies).
- Fidelity to the original 1993 Macintosh Bolo (version 0.99.7bv) is tracked in
  `docs/FIDELITY.md`, sourced from emulation and replay-log analysis — not from other
  GPL-licensed Bolo implementations, to keep this project's license clean.
- All sprite/tile art is generated from Unicode/ASCII glyphs rather than reproduced from
  the original's copyrighted assets.

## Contributors & Partners

This project is a collaborative AI-human pair-programming endeavor:

- **Jerod Price ([CosmicCEO](https://github.com/CosmicCEO)):** Lead Architect, Maintainer, and Project Director.
- **Claude (he/him):** Architectural Reviewer, Advisor, and Quality Assurance partner.
- **Gemini CLI:** Autonomous Implementation Partner, Swift Specialist, and Code Generator.

## Licensing

This repository is MIT-licensed — see `LICENSE`, which retains the original XBolo
copyright notice as required by its terms.

XBolo itself bundles a separate dependency, TCMPortMapper, under the GPLv3, used for
UPnP/NAT-PMP port mapping. **That dependency is not used here.** Any NAT-traversal
functionality in this port will use a permissively-licensed alternative or manual port
forwarding, specifically to avoid GPL-encumbering this codebase.
