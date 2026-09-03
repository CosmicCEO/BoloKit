# BoloKit & Bolo 2026 (Modern Swift Port of XBolo)

A modern Swift port of [XBolo](https://github.com/bananazon/xbolo), a Cocoa clone of Stuart
Cheshire's classic multiplayer tank game *Bolo*. This project is designed as an engine-forward platform (built as the **BoloKit** framework package) supporting future expansions, mods, and AI agents, with the playable Mac app target built on top named **Bolo 2026**.

This repository exists to learn modern Xcode, Swift, on-device AI (FoundationModels), and multiplayer networking, and to end up with a Bolo engine you can play natively on modern macOS (macOS 26+ / Darwin 27+).

Bolo is not otherwise unmaintained — [WinBolo 2](https://store.steampowered.com/app/4672140/WinBolo/) shipped in 2026 with native Mac support.
This project is a personal learning vehicle, not a competing distribution.

## Status

Phase 3 (incremental Swift port, C oracle as spec) is well underway. Waves 1-5 -- leaf utilities,
terrain/tiles, BMAP, and the full simulation core (tank/shell/builder/pillbox physics, mine
chains and explosions, spawn/respawn, tree growth) -- are complete and PARITY-verified against the
C reference. Wave 6 (networking) is in progress: the wire codec, tick orchestrator, and
`recvsr*` broadcast handlers (6.0-6.2) are complete and PARITY-passed; server session logic --
join/kick/ban/alliance (6.3) -- is code-complete and awaiting PARITY audit; transport (6.4) and
tracker/NAT-PMP (6.5) are forward-planned but not yet started. 445 differential + unit tests
passing as of the latest commit. See `docs/PLAN.md` for the full wave-by-wave status and
decisions log.

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
- **Claude CLI:** Architectural Reviewer, Advisor, and Quality Assurance partner.
- **Gemini CLI:** (deprecated due to reliability) Autonomous Implementation Partner, Swift Specialist, and Code Generator.

**Parallel Implementer agents:** running multiple Xcode Implementer agents at once on unrelated,
independently-scoped waves (separate git worktrees/branches) has been proven possible and
beneficial for this project. An earlier attempt appeared to fail from the approach itself, but
was later confirmed to be an unrelated Claude API server-side issue, since resolved -- the
parallel-agent approach itself is sound. Worth doing whenever the Director can afford the
additional AI credits/time it costs to run more than one agent concurrently.

## Licensing

This repository is MIT-licensed — see `LICENSE`, which retains the original XBolo
copyright notice as required by its terms.

XBolo itself bundles a separate dependency, TCMPortMapper, under the GPLv3, used for
UPnP/NAT-PMP port mapping. **That dependency is not used here.** Any NAT-traversal
functionality in this port will use a permissively-licensed alternative or manual port
forwarding, specifically to avoid GPL-encumbering this codebase.
