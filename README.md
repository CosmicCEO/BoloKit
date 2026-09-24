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

**Current tagged drop:** [`v1.5.0`](https://github.com/CosmicCEO/BoloKit/releases/tag/v1.5.0) — Hidden-mines fog-of-war. Playable host-and-join two-player LAN, with a live-play fix pass (guest fire/range/drown/mines, alliances, name sync — [#62](https://github.com/CosmicCEO/BoloKit/issues/62)/[#92](https://github.com/CosmicCEO/BoloKit/issues/92)/[#85](https://github.com/CosmicCEO/BoloKit/issues/85)) already merged to `main` and pending its `v1.5.1` tag once the remaining known issues close (see [`docs/STATUS.md`](docs/STATUS.md): [#77](https://github.com/CosmicCEO/BoloKit/issues/77), [#79](https://github.com/CosmicCEO/BoloKit/issues/79), [#107](https://github.com/CosmicCEO/BoloKit/issues/107), [#114](https://github.com/CosmicCEO/BoloKit/issues/114); [#105](https://github.com/CosmicCEO/BoloKit/issues/105) is fixed on `claude/coding-session-a9s35l` and waiting on a two-Mac check). Apple Development–signed, not notarized (right-click → Open). The app's fixed-port `NWListener` EINVAL is fixed; a bare bind can still fail on some machines and fall back to local-only play.

The C-oracle port is done. Open work lives on GitHub, not in wave numbers. Conventions: issue [#43](https://github.com/CosmicCEO/BoloKit/issues/43). Live board: [`docs/STATUS.md`](docs/STATUS.md).

| Layer | Role |
|-------|------|
| **Issue** | One unit of work (`CosmicCEO/BoloKit`). Types: Feature, Bug, Task. |
| **Milestone** | Time box. `v1.x.0` = **release** (tag when every issue closes). `v1.x.y` = **patch** between planned sprints. `Decide:` = **ruling, no code**. |
| **Sprint** | Two weeks, Monday start, due Friday of week 2. Skip US federal holidays. |
| **Project** | Grouping only. [1.\*](https://github.com/users/CosmicCEO/projects/1) = path to 2.0.0. [2.\*](https://github.com/users/CosmicCEO/projects/2) = Decide items. |

**Current patch:** [v1.5.1 Live play fixes](https://github.com/CosmicCEO/BoloKit/milestone/19), in flight. **Next release sprint:** [v1.6.0 Metal renderer](https://github.com/CosmicCEO/BoloKit/milestone/4), then v1.7 gameplay packs, v1.8 LAN/WAN discovery. **2.0.0** is the tag when that path is done.

Engineering rules: `docs/CONSTRAINTS.md`. Wave history: git tag `legacy-agent-process`.

## Playing

Host or join over LAN from the app's Host/Join screens. Cmd-N opens a second window (macOS
tabs it automatically); each window runs its own independent game session, so you can host in
one tab and join in another on the same Mac -- a convenient way to drive two tanks solo, no
second machine required. See [#144](https://github.com/CosmicCEO/BoloKit/issues/144) for
follow-up on formalizing this into a supported mode.

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
