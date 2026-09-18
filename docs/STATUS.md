# Status

**Current drop:** `v1.5.0`. [GitHub release](https://github.com/CosmicCEO/BoloKit/releases/tag/v1.5.0). **`v1.4.0`–`v1.2.0`, `v1.1.0`, and `v1.0.0` shipped.**

**Bolo 2026** is playable host-and-join multiplayer: HUD, bundled training map or imported `.map`, keyboard-, mouse-, and game-controller-driven tank, click-to-command builder, 50 Hz tick over a live network session, `bolo://` join URLs, host tracker announce + UPnP port mapping, App Intents for Host/Join from Shortcuts and Spotlight, OSLog/`OSSignposter` instrumentation, and near-complete procedural sound. Training island: straight river, player/neutral/enemy bases, yellow pickable wreck, far red turret. Hostile pills duel at combat cadence.

**Tests (as of the `v1.3.0` pass):** 826 SwiftPM (232 BoloKitTests + 594 DifferentialTests) + 107 `Bolo 2026Tests`. One pre-existing flaky timing test is documented; isolated rerun is the check. Confirmed with `swift test` at tag (0 failures).

**CI:** a `.github/workflows/test.yml` (GitHub Actions, `swift build`/`swift test` on `macos-15`) exists on a not-yet-merged branch. `Package.swift`'s `swift-tools-version` is `6.2` on `main`, matching what `macos-15`'s `latest-stable` (currently Xcode 26.3 / Swift 6.2.4) actually ships -- do not bump past that without checking the runner image first.

**Signing:** Apple Development-signed, not notarized. Gatekeeper: right-click → Open.

**Known environment issue:** on some machines `NWListener` EINVAL. The app falls back to local-only play with an on-screen notice. Do not reopen an unbounded investigation.

Wave-by-wave history and the retired four-role process live at git tag `legacy-agent-process`. Do not restore those files.

## How we track work

Source of truth: issue [#43](https://github.com/CosmicCEO/BoloKit/issues/43) and skill `.grok/skills/bolokit-github-boards/`. Do not invent a wave/GO protocol. Do not restore a Planner / Implementer / Parity split.

| Layer | What it is |
|-------|------------|
| **Issue** | One unit of work in `CosmicCEO/BoloKit`. Do not clone the list onto a new board. GitHub types: Feature, Bug, Task. |
| **Milestone** | Time box + kind. See below. |
| **Sprint** | Two weeks, Monday start, due Friday of week 2. Skip any window that contains a US federal holiday (OPM). A release milestone may span one or more sprints. |
| **Project** | Grouping only. User-owned, **linked** to the repo so they show on the [Projects tab](https://github.com/CosmicCEO/BoloKit/projects). |

### Milestone kinds

| Kind | Title shape | When it closes |
|------|-------------|----------------|
| **Release** | `v1.x.0 — …` | Every issue closed → tag `v1.x.0`, GitHub release, update this file. |
| **Patch** | `v1.x.y — …` (`y ≥ 1`) | Ship-between-sprints work (playability, display, hotfixes). Tag `v1.x.y`, GitHub release. Does not replace the next `v1.x.0` sprint. |
| **Decide** | `Decide: …` | Written ruling, **no code**. Then `not_planned` or move the issue to a future release milestone. Due **3 May 2027**. |

New v1.* work: **issue** → release or patch **milestone** → add to [project 1](https://github.com/users/CosmicCEO/projects/1). New Decide work → Decide milestone → [project 2](https://github.com/users/CosmicCEO/projects/2). GitHub MCP `projects_*` may 403; `gh project item-add` is the fallback.

**2.0.0** is the tag when the 1.* path is done. It is not a milestone yet.

## Path to 2.0.0 — [project 1](https://github.com/users/CosmicCEO/projects/1)

Current sprint target: **[v1.6.0 Metal renderer](https://github.com/CosmicCEO/BoloKit/milestone/4)** (due 5 Mar 2027).

| Milestone | Due | Issues |
|-----------|-----|--------|
| ~~v1.3.0 Find and share games~~ | shipped | **Closed and tagged `v1.3.0`.** [#20](https://github.com/CosmicCEO/BoloKit/issues/20) `bolo://`, [#24](https://github.com/CosmicCEO/BoloKit/issues/24) tracker+UPnP, [#26](https://github.com/CosmicCEO/BoloKit/issues/26) Quick Look — all closed |
| ~~v1.4.0 Controls, HUD, sound~~ | shipped | **Closed and tagged `v1.4.0`.** [#17](https://github.com/CosmicCEO/BoloKit/issues/17) controller, [#3](https://github.com/CosmicCEO/BoloKit/issues/3) lag tint, [#8](https://github.com/CosmicCEO/BoloKit/issues/8) remaining sounds, [#23](https://github.com/CosmicCEO/BoloKit/issues/23) Observable HUD, [#22](https://github.com/CosmicCEO/BoloKit/issues/22) App Intents, [#16](https://github.com/CosmicCEO/BoloKit/issues/16) OSLog — all closed |
| ~~v1.5.0 Hidden-mines fog~~ | shipped | **Closed and tagged `v1.5.0`.** [#1](https://github.com/CosmicCEO/BoloKit/issues/1) fog-of-war — closed |
| [v1.6.0 Metal renderer](https://github.com/CosmicCEO/BoloKit/milestone/4) | 5 Mar 2027 | [#25](https://github.com/CosmicCEO/BoloKit/issues/25) |
| [v1.7.0 Gameplay packs](https://github.com/CosmicCEO/BoloKit/milestone/11) | 2 Apr 2027 | [#34](https://github.com/CosmicCEO/BoloKit/issues/34) contract, [#32](https://github.com/CosmicCEO/BoloKit/issues/32) Pelagic, [#35](https://github.com/CosmicCEO/BoloKit/issues/35) strings, [#37](https://github.com/CosmicCEO/BoloKit/issues/37) author guide, [#38](https://github.com/CosmicCEO/BoloKit/issues/38) pack id, [#39](https://github.com/CosmicCEO/BoloKit/issues/39) load sheets |
| [v1.8.0 LAN/WAN discovery (env-blocked)](https://github.com/CosmicCEO/BoloKit/milestone/17) | none | Deferred from v1.3.0 (2026-09-17), all blocked on the same `NWListener` EINVAL environment issue: [#14](https://github.com/CosmicCEO/BoloKit/issues/14) Bonjour (code landed, live LAN unverifiable), [#21](https://github.com/CosmicCEO/BoloKit/issues/21) AWDL, [#6](https://github.com/CosmicCEO/BoloKit/issues/6) dedicated host. Revisit once the environment issue lifts or a field Mac is available — do not grind on them in the meantime. |

Shipped on this path: **v1.2.0** (milestone 1) plus patches **v1.2.1**–**v1.2.3**, and **v1.3.0**/**v1.4.0**/**v1.5.0** (milestones 2/8/3).

## Decide — [project 2](https://github.com/users/CosmicCEO/projects/2)

Not coding work until a ruling or a release milestone says so.

| Milestone | Issues |
|-----------|--------|
| [Decide: WAN directory](https://github.com/CosmicCEO/BoloKit/milestone/5) | [#9](https://github.com/CosmicCEO/BoloKit/issues/9) standalone tracker |
| [Decide: P2P beyond Bonjour+AWDL](https://github.com/CosmicCEO/BoloKit/milestone/6) | [#29](https://github.com/CosmicCEO/BoloKit/issues/29) Wi-Fi Aware |
| [Decide: Apple Developer Program](https://github.com/CosmicCEO/BoloKit/milestone/7) | [#10](https://github.com/CosmicCEO/BoloKit/issues/10) discovery/invite, [#27](https://github.com/CosmicCEO/BoloKit/issues/27) Game Center, [#28](https://github.com/CosmicCEO/BoloKit/issues/28) SharePlay, [#30](https://github.com/CosmicCEO/BoloKit/issues/30) CloudKit lobby |
| [Decide: Foundation Models](https://github.com/CosmicCEO/BoloKit/milestone/9) | [#31](https://github.com/CosmicCEO/BoloKit/issues/31) coach |
| [Decide: Oracle parking lot](https://github.com/CosmicCEO/BoloKit/milestone/10) | [#5](https://github.com/CosmicCEO/BoloKit/issues/5) Q14 explosions owner, [#7](https://github.com/CosmicCEO/BoloKit/issues/7) D155(2) fire on captured base |
| [Decide: Physics](https://github.com/CosmicCEO/BoloKit/milestone/12) | [#40](https://github.com/CosmicCEO/BoloKit/issues/40) worthwhile?, [#41](https://github.com/CosmicCEO/BoloKit/issues/41) blockers, [#42](https://github.com/CosmicCEO/BoloKit/issues/42) combat context |

[#43](https://github.com/CosmicCEO/BoloKit/issues/43) is board documentation, not a sprint item.

## Shipped (`v1.5.0` release)

[#1](https://github.com/CosmicCEO/BoloKit/issues/1) **closed**, PR [#56](https://github.com/CosmicCEO/BoloKit/pull/56) merged. Hidden-mines fog-of-war, opt-in (fully visible stays the default). Fog algorithm (`FogState`, `fogVis`/`calcVis`) differentially tested against `Reference/c`; host-authoritative per-slot tracking, fog rendering + sprite fade, and wire redaction (initial map, terrain broadcasts, new `SRRevealTerrain`). Host-authoritative redaction is a deliberate deviation from the C oracle's client-side filter: see `docs/CONSTRAINTS.md` "Fog-of-war".

**Known gap, deferred:** pill/base state transitions (capture, build, deploy) don't yet act as their own 15×15 vision sources. Completeness gap only; tiles still resolve once any other vision source crosses them.

**Not verified:** manual two-peer hidden-mines session (needs a second Mac; same environment limit as the v1.8.0 issues).

**Tests (as of the `v1.5.0` pass):** 268 BoloKitTests + 595 DifferentialTests + 107 `Bolo 2026Tests`. Two `HostGameEngineTests` timing tests (`hostGameEngineSubmitPauseResumeServerTogglesPauseState`, `hostGameEngineBroadcastsExactlyAtTheTimeLimitBoundaryTickThenNeverAgain`) flake under the full parallel run, on `main` as well; both pass in isolation.

No open v1.5.0 issues remain. Milestone closed, tag `v1.5.0` cut.

## Shipped (`v1.3.0` release)

[#20](https://github.com/CosmicCEO/BoloKit/issues/20) and [#26](https://github.com/CosmicCEO/BoloKit/issues/26) closed via PR #47 (merged to `main`).

- [#24](https://github.com/CosmicCEO/BoloKit/issues/24) **closed**, PR [#55](https://github.com/CosmicCEO/BoloKit/pull/55) merged. Wire host tracker announce + UPnP — `HostGameEngine.startNetworkDiscovery` calls the already-shipped `registerWithTracker`/`PortMapping` (Wave 6.5) right after `engine.start()`, both best-effort (never blocks hosting). Tracker heartbeats every `TRACKERUPDATESECONDS` (60s) with a freshly rebuilt `TrackerHost`; UPnP drains `PortMapping`'s updates into the existing `com.cosmicceo.Bolo-2026`/`net` `Logger`. `HostGameView`'s "Announce on Tracker"/"UPnP" toggles now have live effect. 826/826 SwiftPM tests (+2 new) + 107/107 app tests pass.

**Ruling (2026-09-17):** [#14](https://github.com/CosmicCEO/BoloKit/issues/14) (Bonjour, code landed, live LAN unverifiable), [#21](https://github.com/CosmicCEO/BoloKit/issues/21) (AWDL), and [#6](https://github.com/CosmicCEO/BoloKit/issues/6) (dedicated headless host) all require binding a `Network.framework` listener locally to write or verify — the same `NWListener` EINVAL block. Rather than leave v1.3.0 open indefinitely, moved all three to the new [v1.8.0 LAN/WAN discovery (env-blocked)](https://github.com/CosmicCEO/BoloKit/milestone/17) milestone (no due date) and closed/tagged v1.3.0 with just #20/#24/#26. Do not grind on the three deferred issues until the environment issue lifts or a field Mac is available.

No open v1.3.0 issues remain. Milestone closed, tag `v1.3.0` cut.

## Shipped (`v1.4.0` release)

All 6 milestone issues landed, closed, tagged `v1.4.0`:

- [#16](https://github.com/CosmicCEO/BoloKit/issues/16) **closed**, PR [#48](https://github.com/CosmicCEO/BoloKit/pull/48) merged. OSLog / `OSSignposter` intervals on `runTick`, `GameRenderView.draw(_:)`, and host `clUpdate` send. Subsystem `com.cosmicceo.Bolo-2026`, categories `tick` / `render` / `net`. `DispatchSourceTimer` unchanged.
- [#23](https://github.com/CosmicCEO/BoloKit/issues/23) **closed**, PR [#49](https://github.com/CosmicCEO/BoloKit/pull/49) merged. Observable HUD snapshot -- `HUDSnapshot`, a display-only `@MainActor @Observable` projection of `GameState` (the first `@Observable` type in this codebase), populated from `GameSession`'s tick path. `ResourceGaugesPanel`/`PlayerStatusGrid` read it directly instead of polling `session.state` on a `TimelineView`; `GameSession.state` itself is still not `ObservableObject`.
- [#3](https://github.com/CosmicCEO/BoloKit/issues/3) **closed**, PR [#50](https://github.com/CosmicCEO/BoloKit/pull/50) merged. Join-side connection lag tint -- closed the disclosed gap in `GameSession.connectionAge(for:)`: the join path now derives an age from `UDPSession`'s own per-peer freshness table (new `lastUpdate(for:)` accessor) minus this session's `localSeq`, the same `currentTick - lastUpdate` shape the host path already gets from `HostSessionTable.allTicksSinceLastUpdate`. `PlayerStatusView.staleness(forPlayer:)` needed no changes. New test: `udpSessionLastUpdateReflectsCallersOwnSeqAtApplyTime` in `UDPSessionTests.swift`. Full toolchain test pass confirmed at merge.
- [#22](https://github.com/CosmicCEO/BoloKit/issues/22) **closed**, PR [#51](https://github.com/CosmicCEO/BoloKit/pull/51) merged. App Intents for "Host a Game" / "Join Last Host" (Shortcuts/Spotlight, no Game Center) -- `HostGameIntent`/`JoinLastHostIntent` (`AppIntents.swift`) route through `@MainActor @Observable` singleton `AppIntentRouter`. `HostGameView`/`JoinGameView`/`NewGameView` observe the router. `LastJoinedHostStore` persists the last join target (`GSLastJoinHostString`/`GSLastJoinPortNumber`) via `UserDefaults.standard` (`nonisolated` for Swift 6 safety). Serialized test suite (`AppIntentsTests.swift`) verified with 89/89 tests passing.
- [#17](https://github.com/CosmicCEO/BoloKit/issues/17) **closed**, PR [#53](https://github.com/CosmicCEO/BoloKit/pull/53) merged. Game Controller mapping to InputFlags. `InputKeymap.swift` action-keyed `inputFlagsChange(forAction:isDown:)`. `GameControllerInput.swift` maps `GCExtendedGamepad` onto 10 of the 14 `InputAction`s. `GameRenderView.performViewAction(_:)` shared across keyboard and controller. `GCSupportsControllerUserInteraction` in `Info.plist`. 100/100 tests pass.
- [#8](https://github.com/CosmicCEO/BoloKit/issues/8) **closed**, PR [#54](https://github.com/CosmicCEO/BoloKit/pull/54) merged. Wire remaining procedural sounds (`hittank`, `hitterrain`, `hittree`, `mine`, `pillshot`, `build`, `builderdeath`, `sink`, `bubbles`) via BoloKit callback threading (`RunTick`, `ShellTick`, `PillTick`, `BuilderTick`, `TankTick`) and connected to `SoundPlayer.shared.play(...)` in `GameSession.swift`. 824/824 SwiftPM tests (+19 new) + 86/86 app tests pass.

No open v1.4.0 issues remain. Milestone closed, tag `v1.4.0` cut.

## Previous (`v1.2.3` patch)

[#46](https://github.com/CosmicCEO/BoloKit/issues/46) Pill-vs-pill combat cadence (`minTicksPerShot`) so a calm map turret returns fire.

## Previous (`v1.2.2` patch)

[#45](https://github.com/CosmicCEO/BoloKit/issues/45) Hostile pills acquire hostile pills. XBolo `pilllogic()` is tank-only.

## Previous (`v1.2.1` patch)

[#44](https://github.com/CosmicCEO/BoloKit/issues/44) Unowned pills draw yellow (`NPIL`). Training-map pickup at `(108, 123)`.

## Previous (`v1.2.0` sprint)

Mac-native chrome. Training island replaced Alabama after the tag.

- [#12](https://github.com/CosmicCEO/BoloKit/issues/12) PrivacyInfo.xcprivacy
- [#13](https://github.com/CosmicCEO/BoloKit/issues/13) Game Mode, Full Screen
- [#11](https://github.com/CosmicCEO/BoloKit/issues/11) `com.cosmicceo.bolo-map` UTI
- [#15](https://github.com/CosmicCEO/BoloKit/issues/15) Icon Composer `AppIcon.icon`
- [#18](https://github.com/CosmicCEO/BoloKit/issues/18) Game/View Commands
- [#19](https://github.com/CosmicCEO/BoloKit/issues/19) VoiceOver HUD
- [#2](https://github.com/CosmicCEO/BoloKit/issues/2) ORACLE_COVERAGE snapshot
