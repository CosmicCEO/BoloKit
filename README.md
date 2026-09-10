# BoloKit & Bolo 2026 (Modern Swift Port of XBolo)

A modern Swift port of [XBolo](https://github.com/bananazon/xbolo), a Cocoa clone of Stuart
Cheshire's classic multiplayer tank game *Bolo*. This project is designed as an engine-forward platform (built as the **BoloKit** framework package) supporting future expansions, mods, and AI agents, with the playable Mac app target built on top named **Bolo 2026**.

This repository exists to learn modern Xcode, Swift, on-device AI (FoundationModels), and multiplayer networking, and to end up with a Bolo engine you can play natively on modern macOS (macOS 26+ / Darwin 27+).

Bolo is not otherwise unmaintained — [WinBolo 2](https://store.steampowered.com/app/4672140/WinBolo/) shipped in 2026 with native Mac support.
This project is a personal learning vehicle, not a competing distribution.

## Status

Phase 3 (incremental Swift port, C oracle as spec) is complete. Waves 1-5 -- leaf utilities,
terrain/tiles, BMAP, and the full simulation core (tank/shell/builder/pillbox physics, mine
chains and explosions, spawn/respawn, tree growth) -- Wave 6 (networking: wire codec, tick
orchestrator, broadcast/session handlers, transport, tracker protocol + NAT-PMP) -- and Wave 7's
v1 vertical slice (asset pipeline, an Xcode app target, game rendering, and the input/tick loop)
are all complete and PARITY-verified against the C reference. **`v1.0.0` shipped** (real,
non-prerelease GitHub release), and active work has since moved to a 1.1 release cycle. 756
SwiftPM tests (BoloKitTests + DifferentialTests) plus 19 app-target tests (`Bolo 2026Tests`,
added in the 1.1 cycle) are passing (one pre-existing, documented flaky timing test excluded from
that count's stability claim -- see `docs/PLAN.md`). **`Bolo 2026` is playable, host-and-join
multiplayer**: a window opens with an always-visible HUD (build-tool selector, resource gauges,
player/pill/base status), renders a real bundled default map (or an imported one) from generated
assets, and drives a tank via the actual physics engine, keyboard- and mouse-controlled
(click-to-command the builder, matching the original's own unlimited-range design) and
tick-driven, over a real live network session. **Milestone B** (Host/Join UI wired to the
networking layer) is fully closed, including B.10's full join-side outbound protocol (movement,
tile-entry, builder-task, and shell-impact reporting). **Milestone C** is partially done -- HUD
status panel + kick/ban (C.0), key remap (C.1), the alliance panel (C.2), messages panel (C.4),
procedural sound synthesis (C.3, 24 effects generated, several wired to gameplay events including
cannon fire and tree harvest), and the preferences shell (C.5) are closed. **Milestone D**
(zoom/scroll polish, full notarization) remains deferred -- the app ships with real Apple
Development code signing but not notarized (no paid Developer Program enrollment yet), so a fresh
download needs a one-time right-click → Open to bypass Gatekeeper's warning. A known, unresolved
environment issue on some machines causes `Network.framework`'s listener creation to fail; the
app falls back automatically to local-only play in that case, with an on-screen notice -- root
cause not found despite investigation (ruled out: beta-OS-specific, ad-hoc signing), deliberately
not under active investigation to avoid further escalation-of-commitment cost. Filed but not yet
scheduled: an always-visible event/capture-message log bar, win/loss UI presentation (the
simulation already computes the underlying condition), and a `hiddenmines`-style fog-of-war mode.
See `docs/PLAN.md` for the full wave-by-wave status and decisions log.

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

This project is a collaborative AI-human pair-programming endeavor, currently run as one human
plus a structured multi-agent team using macos command line tools for xcode which are driven by claude code agent and subagents at the command line:

Learning arc:
- began with one claude agent and claude chat in xcode.app
- learned more about claude and integrated claude.app with a planner and quality agent, everything manually passed between three agents
-- developed understanding of cost of long workflows, long logs, repeat read and write
-- developed a clean process of plan do check and act, based around a single agent notes scratch pad
-- developed a bootstrapping process for agents so that I could archive the xcode agent and restart where I left; did the same thing for planner, quality agents in the app
-- developed a better understanding of cost of documents, began archiving completed agent notes.md at close of each wave, maintaining a constant plan.md for open questions, decisions and etc.
- learned more about agents and multi-agents, deployed the claude command line interface
-- using existing bootstraps, exported skills from planner, quality, admin, and xcode coder imported into claude cli
-- initiated same 4 agent paradigm in 4 terminal windows for one wave
-- initiated one terminal window claude agent planner and asked her to spawn sub-agents as needed for quality, coding, admin; planner agent picks up the memories and bootstrap skills from previously imported baseline
-- initially defined gating for my intervention at all waves, but quickly removed
-- learned more about claude cli commands and began requesting planner to spawn subagents to tasks based on agent model complexity rather than always using sonnet high, for example sonnet low for admin agent doing product cleanup and archival duties.

Current state:

Claude Planner
-- subagent coder uses xcode mcp
-- subagent quality uses memories and skills developed in first 75% of project
-- subagent admin uses memories and skill developed in middle of project
Human Director is hands off except for pre-planning /plan command and /exit-plan commands
-- human director monitors progress and is briefed at each stage gate

To do:

- implement additional token saving ideas into skill sets or figure out how to adopt pre-formed skills from claude website
- adopt a more visual mode for monitoring progress (dashboard GUI)
- finish the project and archive my learning in github

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
