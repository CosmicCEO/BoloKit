# Status

**Current drop:** `v1.2.3` (build 10). [GitHub release](https://github.com/CosmicCEO/BoloKit/releases/tag/v1.2.3). **`v1.2.2`–`v1.2.0`, `v1.1.0`, and `v1.0.0` shipped.**

**Bolo 2026** is playable host-and-join multiplayer: HUD, bundled training map or imported `.map`, keyboard- and mouse-driven tank, click-to-command builder, 50 Hz tick over a live network session. Training island: straight river, player/neutral/enemy bases, yellow pickable wreck, far red turret. Hostile pills duel at combat cadence.

**Tests (as of the `v1.2.3` pass):** 795 SwiftPM (575 BoloKitTests + 220 DifferentialTests) + 66 `Bolo 2026Tests`. One pre-existing flaky timing test is documented; isolated rerun is the check. Confirm with `swift test` at tag.

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

Current sprint target: **[v1.3.0 Find and share games](https://github.com/CosmicCEO/BoloKit/milestone/2)** (due 30 Oct 2026). Milestone stays open — do not tag `v1.3.0` until every issue closes.

| Milestone | Due | Issues |
|-----------|-----|--------|
| [v1.3.0 Find and share games](https://github.com/CosmicCEO/BoloKit/milestone/2) | 30 Oct 2026 | [#14](https://github.com/CosmicCEO/BoloKit/issues/14) Bonjour (code landed, live LAN environment-blocked), [#21](https://github.com/CosmicCEO/BoloKit/issues/21) AWDL, [#20](https://github.com/CosmicCEO/BoloKit/issues/20) `bolo://` **closed**, [#24](https://github.com/CosmicCEO/BoloKit/issues/24) tracker+UPnP, [#6](https://github.com/CosmicCEO/BoloKit/issues/6) dedicated host, [#26](https://github.com/CosmicCEO/BoloKit/issues/26) Quick Look **closed** |
| [v1.4.0 Controls, HUD, sound](https://github.com/CosmicCEO/BoloKit/milestone/8) | 11 Dec 2026 | [#17](https://github.com/CosmicCEO/BoloKit/issues/17) controller, [#3](https://github.com/CosmicCEO/BoloKit/issues/3) lag tint, [#8](https://github.com/CosmicCEO/BoloKit/issues/8) remaining sounds, [#23](https://github.com/CosmicCEO/BoloKit/issues/23) Observable HUD **closed** (early), [#22](https://github.com/CosmicCEO/BoloKit/issues/22) App Intents, [#16](https://github.com/CosmicCEO/BoloKit/issues/16) OSLog |
| [v1.5.0 Hidden-mines fog](https://github.com/CosmicCEO/BoloKit/milestone/3) | 5 Feb 2027 | [#1](https://github.com/CosmicCEO/BoloKit/issues/1) |
| [v1.6.0 Metal renderer](https://github.com/CosmicCEO/BoloKit/milestone/4) | 5 Mar 2027 | [#25](https://github.com/CosmicCEO/BoloKit/issues/25) |
| [v1.7.0 Gameplay packs](https://github.com/CosmicCEO/BoloKit/milestone/11) | 2 Apr 2027 | [#34](https://github.com/CosmicCEO/BoloKit/issues/34) contract, [#32](https://github.com/CosmicCEO/BoloKit/issues/32) Pelagic, [#35](https://github.com/CosmicCEO/BoloKit/issues/35) strings, [#37](https://github.com/CosmicCEO/BoloKit/issues/37) author guide, [#38](https://github.com/CosmicCEO/BoloKit/issues/38) pack id, [#39](https://github.com/CosmicCEO/BoloKit/issues/39) load sheets |

Shipped on this path: **v1.2.0** (milestone 1) plus patches **v1.2.1**–**v1.2.3**.

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

## This sprint (v1.3.0 in progress, not tagged)

Branch `issue-20-bolo-url`. Test counts on this branch (not a release tag): SwiftPM 802 (575 + 227) + 78 `Bolo 2026Tests` (77 pass + 1 pre-existing skip). Confirm before any tag.

- [#20](https://github.com/CosmicCEO/BoloKit/issues/20) `bolo://join?host=&port=` + ShareLink (password omitted)
- [#26](https://github.com/CosmicCEO/BoloKit/issues/26) Finder `.map` thumbnails (`QLThumbnailProvider`, generated tiles). Needs a logout once for the appex to attach. Chooser also accepts XBolo’s `com.gengasw.xbolo.map`
- [#14](https://github.com/CosmicCEO/BoloKit/issues/14) Bonjour advertise/browse/join-via-endpoint — **open**. Live two-peer LAN unverifiable: `NWListener` EINVAL on the physical Mac and Parallels guest, including a bare `swiftc` bind. Do not reopen that investigation.

[#21](https://github.com/CosmicCEO/BoloKit/issues/21) / [#24](https://github.com/CosmicCEO/BoloKit/issues/24) / [#6](https://github.com/CosmicCEO/BoloKit/issues/6) untouched this sprint; same bind block.

## Landed early (v1.4.0, no tag)

[#23](https://github.com/CosmicCEO/BoloKit/issues/23) Observable HUD snapshot -- `HUDSnapshot`, a display-only `@MainActor @Observable` projection of `GameState` (the first `@Observable` type in this codebase), populated from `GameSession`'s tick path. `ResourceGaugesPanel`/`PlayerStatusGrid` read it directly instead of polling `session.state` on a `TimelineView`; `GameSession.state` itself is still not `ObservableObject`. Branch `issue-23-hud-snapshot`. Test counts on this branch: 82 `Bolo 2026Tests` (81 pass + 1 pre-existing skip); no `BoloKit`/`BoloNet` sources touched, SwiftPM suite unaffected. Not a `v1.4.0` tag.

[#22](https://github.com/CosmicCEO/BoloKit/issues/22) App Intents for "Host a Game" / "Join Last Host" (Shortcuts/Spotlight, no Game Center) -- `HostGameIntent`/`JoinLastHostIntent` (`AppIntents.swift`) hand off through a new `@MainActor @Observable` singleton, `AppIntentRouter`, since an `AppIntent.perform()` is a fresh struct with no `Binding` into the live view hierarchy the way `Bolo_2026App`'s `onOpenURL` has for `pendingMapURL`/`pendingJoinURL`. `HostGameView`/`JoinGameView`/`NewGameView` observe the router and drive their own existing "Start Hosting"/"Join" entry points and tab selection -- no separate host/join code path. "Join Last Host" reads a new `LastJoinedHostStore` (`GSLastJoinHostString`/`GSLastJoinPortNumber` in `UserDefaults.standard`), written from `TCPSession.remoteHost`/`remotePort` on every successful join, LAN or manual. `AppRootView.returnToNewGame()` clears any pending router action on every "Quit to Menu" so an intent that fired mid-game can't dangle and fire stale once the user gets back to the menu. Branch `issue-22-app-intents`. No `BoloKit`/`BoloNet` source changed. **Toolchain note: this branch was written and committed without a Swift/Xcode toolchain available in-session (`which swift xcodebuild` found neither) -- it has not actually been built or run.** `AppIntentsTests.swift` adds 7 `@Test` functions (2 exercising `HostGameIntent`/`JoinLastHostIntent.perform()` directly, 5 on `LastJoinedHostStore`'s UserDefaults round-trip), bringing the statically-counted `Bolo 2026Tests` total from 82 to 89 `@Test` functions -- a source-level count, not a `swift test`/`xcodebuild` pass/fail result. Confirm with a real toolchain before trusting these numbers or tagging `v1.4.0`. Not a `v1.4.0` tag.

## Landed (`v1.2.3` patch)

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
