# Status

**Current tagged drop:** `v1.5.1`. [GitHub release](https://github.com/CosmicCEO/BoloKit/releases/tag/v1.5.1). **`v1.5.0`–`v1.2.0`, `v1.1.0`, and `v1.0.0` shipped.** Milestone [19](https://github.com/CosmicCEO/BoloKit/milestone/19) closed 2026-09-22: every issue closed, code merged to `main` (PRs [#117](https://github.com/CosmicCEO/BoloKit/pull/117), [#121](https://github.com/CosmicCEO/BoloKit/pull/121), [#123](https://github.com/CosmicCEO/BoloKit/pull/123)), and #105/#114 both live-confirmed on real two-Mac hardware (build `v151-test6 496999e`) before the tag. Release notes: `docs/RELEASE_NOTES_v1.5.1.md`.

**Bolo 2026** is playable host-and-join multiplayer: HUD, bundled training map or imported `.map`, keyboard-, mouse-, and game-controller-driven tank, click-to-command builder, 50 Hz tick over a live network session, `bolo://` join URLs, host tracker announce + UPnP port mapping, App Intents for Host/Join from Shortcuts and Spotlight, OSLog/`OSSignposter` instrumentation, and near-complete procedural sound. Training island: straight river, player/neutral/enemy bases, yellow pickable wreck, far red turret. Hostile pills duel at combat cadence.

**Tests (as of the `v1.5.1` tag, 2026-09-22):** 942 SwiftPM (637 BoloKitTests + 305 DifferentialTests) + 136 `Bolo 2026Tests`. Two pre-existing flaky `HostGameEngineTests` timing tests (`hostGameEngineSubmitPauseResumeServerTogglesPauseState`, `hostGameEngineBroadcastsExactlyAtTheTimeLimitBoundaryTickThenNeverAgain`) flake under the full parallel run; both pass in isolation, confirmed at this tag. Full `swift test` + `xcodebuild ... test -only-testing:"Bolo 2026Tests"` both green (0 unexpected failures) at tag.

**CI:** a `.github/workflows/test.yml` (GitHub Actions, `swift build`/`swift test` on `macos-15`) exists on a not-yet-merged branch. `Package.swift`'s `swift-tools-version` is `6.2` on `main`, matching what `macos-15`'s `latest-stable` (currently Xcode 26.3 / Swift 6.2.4) actually ships -- do not bump past that without checking the runner image first.

**Signing:** Apple Development-signed, not notarized. Gatekeeper: right-click → Open.

**Former "environment issue" (fixed):** hosting on any fixed port failed with `NWListener` EINVAL and the app fell back to local-only play with an on-screen notice. It was a bug in this port, not macOS: the listeners set the port twice (`requiredLocalEndpoint` and `NWListener(using:on:)`). Fixed on `fix-listener-einval`; regression test `HostListenerFixedPortTests`. The v1.8.0 issues below were blocked on it and can be picked up again.

Wave-by-wave history and the retired four-role process live at git tag `legacy-agent-process`. Do not restore those files.

## In flight — v1.6.0 Metal renderer (end of shift, 2026-09-22)

Milestone [4](https://github.com/CosmicCEO/BoloKit/milestone/4), scoped strictly to `#25` (hard
ceiling — no added scope, anything else goes to v1.6.1). Work lives on branch
`v160-metal-renderer`, [PR #128](https://github.com/CosmicCEO/BoloKit/pull/128) (open, not
merged). Milestone [20](https://github.com/CosmicCEO/BoloKit/milestone/20) `v1.5.2 — Rejoin
fix` is deliberately sequenced *after* v1.6.0 per direction this session, so v1.6.0 is the
active work.

**Increments 1-5 (baseline, `TileRenderer` extraction seam, offscreen pixel-diff parity
harness, Metal terrain path, Metal sprite/shell/explosion path) are done, tested, and
verified pixel-exact** against the existing CPU `CGContextTileRenderer` — see PR #128 for the
two real interpolation bugs found and fixed via the parity harness along the way. None of this
is wired into the live app yet; `MetalTileRenderer` exists but nothing in `GameSession.swift`
constructs a `GameRenderView` with it.

**Increment 6 (the real on-screen performance path — a `CAMetalLayer`-backed `MTKView`
floating behind `GameRenderView`'s scroll view, live camera tracking) landed as code but
found genuinely broken on first live evaluation.** Built an evaluation copy with the overlay
temporarily enabled (`Bolo 2026 (v160-metal-eval d49ca48).app`, not committed — the flag stays
off by default on `main`/the branch) and had it hand-tested: **terrain does not scale with
window resize while sprites/other elements do.** Working theory, not yet confirmed or fixed:
the overlay's `MTKView` tracks its size via legacy `autoresizingMask`
(`GameRenderView.installLiveMetalOverlayIfNeeded`), while this app's SwiftUI-hosted view
hierarchy likely drives sizing via Auto Layout constraints — mixing the two is a classic
source of exactly this "some things resize, some don't" symptom. **Next session: confirm that
theory and fix (likely: pin the `MTKView`'s edges to its superview with real constraints
instead of `autoresizingMask`), then re-evaluate live before touching increment 7.**

The two structural tests for increment 6 (`LiveMetalTerrainOverlayTests.swift`) are still
`.disabled` — they crash/misbehave in this session's specific sandboxed test-hosting
environment for reasons unrelated to the resize bug (tried and ruled out: app activation
policy, `MainActor`/`nonisolated` delegate isolation, shared vs. separate `MTLDevice`s, test
serialization). See that file's own header for the full account.

**Increment 7 (raise `tileCountBudget`, flip the default renderer to Metal) has not started**
— correctly blocked on increment 6 actually working, not just compiling.

**Also from today, flagged for awareness:** [PR #119](https://github.com/CosmicCEO/BoloKit/pull/119)
(a `#79` label-fog-gate regression test, `RemoteTankFogGateTests.swift`) was closed without
merging. The underlying `#79` fix it was testing is already live and separately
live-confirmed (see the `v1.5.1` shipped section below), so no behavior is at risk — only that
specific standalone regression test never landed on `main`. Worth a deliberate call next
session: re-open and merge it, or let it go.

### Update, 2026-09-22 (same day, follow-up session): increment 6 resize bug root-caused and fixed

The `autoresizingMask`-vs-Auto-Layout theory above was **wrong** — investigated further and
found the real cause: `installLiveMetalOverlayIfNeeded` sized the overlay's `MTKView` to
`scrollView.bounds` (the *whole* scroll view, including the fixed HUD-chrome `contentInsets`
this same file already measures elsewhere as top 48/left 56/right 228 + a bottom inset), while
`MetalTileRenderer.renderLiveTerrain`'s `scale = targetTexture.width / visibleRect.width` was
comparing that against `visibleRect`, the *inset-excluded* region the CPU sprite path already
uses correctly. The two rectangles disagreed by a fixed-point amount that's a larger fraction
of a narrow window than a wide one — exactly "elements scale with the window while the map
does not," worse on a small window.

**Fix (commit `8beea7d`, pushed to `v160-metal-renderer`):** size/position the `MTKView` to
`scrollView.contentView.frame` (the clip view — already inset-excluded) instead of
`scrollView.bounds`, resynced via explicit `frameDidChangeNotification`
(scroll view)/`boundsDidChangeNotification` (clip view) observers — the same mechanism
`configureZoom()`/`scrollViewFrameDidChange()` already prove reliable on this exact view
hierarchy — rather than `autoresizingMask`. Also extracted the scale/origin math into a pure
`nonisolated static func MetalTileRenderer.cameraTransform(...)`, with new headless unit tests
(`MetalTileRendererLiveTerrainTests.swift`) — increments 4-5's pixel-exact parity tests only
ever exercised the offscreen `draw(_:ctx:dirtyRect:)` path, never `renderLiveTerrain`, which is
exactly why this shipped uncaught. Full relevant suite green (`GameRenderViewZoomTests`,
`GameRenderViewTests`, `MetalTileRendererTests`, the new tests) — no regressions.

**Not yet done:** live re-evaluation. Built a fresh eval copy with the overlay enabled,
`Bolo 2026 (v160-metal-eval 8beea7d resize-fix).app` (not committed, same off-by-default
pattern as before), and a manual test script,
`Bolo 2026 Test Script (v160-metal-eval 8beea7d resize-fix).docx` (8 items — baseline
alignment, widen/narrow resize, zoom at multiple sizes, resize-during-pan, fullscreen toggle,
HUD-edge alignment, general play). Both on the Desktop. This test is single-Mac/role-agnostic —
the overlay is wired identically at all three `GameSession.swift` `GameRenderView` construction
sites (solo, host, guest), so it needs no second Mac. **Next session: run that script, then
either continue to increment 7 (if clean) or reopen the investigation (if not).**

### Update, 2026-09-23: live re-evaluation clean; increment 7 landed (commit `22292e0`)

User ran the full 8-item test script by hand (tracked-changes `.docx`, embedded screenshots).
All 8 items pass — no scale/alignment mismatch between terrain and sprites on resize, zoom,
resize-during-pan, fullscreen toggle, or HUD-edge alignment. The resize fix (`8beea7d`) is
confirmed working live, not just in the headless regression tests.

Two unrelated findings surfaced by the live play, triaged as seed issues (no code
investigation yet):
- [#137](https://github.com/CosmicCEO/BoloKit/issues/137) — intermittent black seam lines in
  the live Metal terrain overlay (sea-only, hard to reproduce). Filed under the existing
  `v1.6.1` milestone as an enhancement — not a `v1.6.0`/#25 blocker.
- [#138](https://github.com/CosmicCEO/BoloKit/issues/138) — builder movement after death looks
  unrouted, then snaps to a direct line. Filed under a new `v1.9.0 — Builder logic` milestone
  (22) as a bug — unrelated to the Metal renderer work.

**Increment 7 (commit `22292e0`):** `tileCountBudget = 9,000` calibrates the CPU
`CGContext` draw-cost ladder, but once `liveMetalOverlay` is live, `draw(_:)` skips the
expensive tile pass entirely (only sprites stay on CGContext). Applying the CPU floor to the
Metal path was an artifact, not a real cost constraint — made the floor renderer-dependent
(`liveMetalTileCountBudget = 256*256`, i.e. no practical ceiling) instead of raising the
budget globally, and flipped `GameSession`'s three `GameRenderView` construction sites to
default to the Metal renderer (`liveMetalTerrainRenderer: MetalTileRenderer()`).
`GameRenderViewZoomTests`' two tests coupled to `T=9,000` by premise now inject an explicit
`tileBudgetOverrideForTesting` instead of reading the production constant. Full suite:
146/146 passing.

**Not yet done:** a second live-play pass specifically confirming increment 7 (Metal now the
default renderer, no more visible tile-count ceiling at max zoom-out) — the same single-Mac
test approach as increment 6's re-evaluation. Once that's clean: merge PR #128, close
milestone #25, tag `v1.6.0`.

## Shipped (`v1.5.1` release, tagged 2026-09-22)

**[PR #117](https://github.com/CosmicCEO/BoloKit/pull/117)** ("bring the whole two-player stack into main", merged 2026-09-22): consolidated five stacked branches (45 commits) that had landed on neighbouring branches but not `main`. Fixed and **verified by code/doc read** (no Swift toolchain in the session that did this triage pass — a `swift test` run in Xcode is still owed before the v1.5.1 tag): guest can fire/adjust range/drown/lay mines and mines now trigger for it ([#62](https://github.com/CosmicCEO/BoloKit/issues/62)/[#91](https://github.com/CosmicCEO/BoloKit/issues/91), ruling [#59](https://github.com/CosmicCEO/BoloKit/issues/59)), host builder edits and mine terrain reach guests ([#84](https://github.com/CosmicCEO/BoloKit/issues/84)/[#81](https://github.com/CosmicCEO/BoloKit/issues/81)), host name shows on the guest ([#85](https://github.com/CosmicCEO/BoloKit/issues/85)), alliances work from both sides ([#92](https://github.com/CosmicCEO/BoloKit/issues/92)), Hidden Mines no longer announces a remote-laid mine at range ([#106](https://github.com/CosmicCEO/BoloKit/issues/106)), and a mine within 2.0 tiles of an observer's own tank correctly stays hidden-then-sticky-revealed ([#77](https://github.com/CosmicCEO/BoloKit/issues/77)'s first two parts). The umbrella issue [#61](https://github.com/CosmicCEO/BoloKit/issues/61) is closed as superseded; its two bullets with no fix (host hears no guest sounds; unexplained Mac B freeze, no repro) split to [#118](https://github.com/CosmicCEO/BoloKit/issues/118).

**Two-Mac run, 2026-09-22, build `v151-test5 9a58453`** (both Macs; host Mac A 192.168.86.176, guest Mac B): ran `docs/TEST_TWO_MAC_FOG.md` in full — results and handwritten notes in `docs/Test Result Two-Mac Fog Test Script (v1.5.1).pdf`, printed script in `docs/Two-Mac Fog Test Script (v1.5.1).docx`. Mostly pass. **Live-confirmed fixed and closed:** [#79](https://github.com/CosmicCEO/BoloKit/issues/79) (label fog-gate, step 3 check 9 PASS — also confirmed in code earlier the same day, PR [#119](https://github.com/CosmicCEO/BoloKit/pull/119)), [#107](https://github.com/CosmicCEO/BoloKit/issues/107) (host-quit disconnect message, step 13 PASS). **[#77](https://github.com/CosmicCEO/BoloKit/issues/77) closed:** its "own mine always visible at range" claim was actually the intended sticky-reveal design (step 3 check 4 PASS); the remaining builder-laid-mine render-refresh gap was closed per triage direction rather than re-tested. **New issue filed:** [#120](https://github.com/CosmicCEO/BoloKit/issues/120), alliance breaking doesn't re-fog the vision it granted (tank sprite disappears, revealed terrain doesn't recede) — moved to `v1.5.2 — Rejoin fix`, the focus of that milestone. **New detail added to existing issues:** [#113](https://github.com/CosmicCEO/BoloKit/issues/113) (rejoin — control loss now pinned to reaching the map border, not a fixed distance; a new-player-name rejoin still spawns at the guest's frozen position, contradicting `docs/RELEASE_NOTES_v1.5.1.md`'s prior "worked in testing" note), [#114](https://github.com/CosmicCEO/BoloKit/issues/114) (shells — angle-dependent visibility gaps, reproduces even with Hidden Mines off), [#93](https://github.com/CosmicCEO/BoloKit/issues/93) (first-join-fails-second-succeeds, reproduced again). **#105 closed** (see below) despite this run not re-exercising its exact scenario.

**[#114](https://github.com/CosmicCEO/BoloKit/issues/114) fixed, merged, and live-confirmed (PR [#123](https://github.com/CosmicCEO/BoloKit/pull/123)):** `headingColumn(shell.dir)` returns a 16-heading bucket, but the procedurally-generated sprite sheet only populated 6 of those 16 `SHELL` cells (`GlyphSource.swift`'s `.shell(frame:)` mistook them for animation-growth frames, not headings) — the other 10 buckets (`0x66-0x6f`) were an intentional transparent gap. Since a shell's `dir` never changes after firing, a shell fired toward one of those 10 headings was invisible for its whole flight, exactly the angle-dependent behavior the 2026-09-22 run reported. Fix: widened the shell range to all 16 headings and gave shells a constant-size directional streak instead of a growing circle; `headingColumn` moved to `PhysicsOps.swift` (public) for testability. New tests in `BoloGlyphsTests.swift` sweep every heading. **Live-confirmed 2026-09-22 on build `v151-test6 496999e`**: fired shells stationary, moving, rotating in place, and moving+firing — PASS, no vanishing shells at any tested heading/combination.

**[#105](https://github.com/CosmicCEO/BoloKit/issues/105) fixed, merged, and live-confirmed (PR [#121](https://github.com/CosmicCEO/BoloKit/pull/121)):** a host-simulated guest's key-down mine landed on the tile it already occupied, and `remoteLastTankPosition` was still one tile behind, so the next tick detonated it. `9a58453` (now on `main`) stamps the tank's current position when that drop is on its own tile. A snap onto a mine that was already there still detonates. Tests: `dispatchDropMineUnderAHostSimulatedTankDoesNotDetonateOnTheNextTick`, `hostSimulatedTankAlreadyOnAMineStillDetonatesWhenTheEntryStampIsBehind`. **Live-confirmed 2026-09-22 on build `v151-test6 496999e`**: guest's key-down mine no longer detonates under its own tank while continuously laying mines and driving. Pull requests [#95](https://github.com/CosmicCEO/BoloKit/pull/95) and [#109](https://github.com/CosmicCEO/BoloKit/pull/109) were closed as superseded by #117; [#71](https://github.com/CosmicCEO/BoloKit/issues/71) (stale README/hiddenMines comment) also merged and closed in the same PR #121.

**Moved out of v1.5.1** (not live-play regressions): pill/base as vision sources ([#72](https://github.com/CosmicCEO/BoloKit/issues/72)) → v1.7.0; sprite chrome polish ([#110](https://github.com/CosmicCEO/BoloKit/issues/110)) → [v1.6.1 — Increase Visual Appeal of Sprites](https://github.com/CosmicCEO/BoloKit/milestone/21), created after v1.6.0. **v1.6.0 is a hard ceiling** (Metal renderer only, [#25](https://github.com/CosmicCEO/BoloKit/issues/25)) — do not add scope to it; anything else that would attach to it goes to v1.6.1 instead. **Folded into `v1.5.2 — Rejoin fix`** (milestone [20](https://github.com/CosmicCEO/BoloKit/milestone/20), investigation-blocked, don't hold the v1.5.1 tag on these): guest rejoin ([#113](https://github.com/CosmicCEO/BoloKit/issues/113)), blue square artifact ([#87](https://github.com/CosmicCEO/BoloKit/issues/87)), intermittent first-join failure ([#93](https://github.com/CosmicCEO/BoloKit/issues/93)), slow guest terrain reveal ([#89](https://github.com/CosmicCEO/BoloKit/issues/89)), host-side sounds/Mac B freeze ([#118](https://github.com/CosmicCEO/BoloKit/issues/118)), alliance-break vision leak ([#120](https://github.com/CosmicCEO/BoloKit/issues/120), the focus of this milestone), controller input in a live session ([#101](https://github.com/CosmicCEO/BoloKit/issues/101)), custom key bindings in a live session ([#100](https://github.com/CosmicCEO/BoloKit/issues/100)).

The v1.8.0 issues [#14](https://github.com/CosmicCEO/BoloKit/issues/14)/[#21](https://github.com/CosmicCEO/BoloKit/issues/21)/[#6](https://github.com/CosmicCEO/BoloKit/issues/6) are unblocked (the `NWListener` fix landed pre-v1.5.0) and can be picked up any time.

No open v1.5.1 issues remain. Milestone [19](https://github.com/CosmicCEO/BoloKit/milestone/19) closed, tag `v1.5.1` cut, [GitHub release](https://github.com/CosmicCEO/BoloKit/releases/tag/v1.5.1) published, 2026-09-22.

**Next step:** `v1.5.2 — Rejoin fix` (milestone [20](https://github.com/CosmicCEO/BoloKit/milestone/20)), picking up #113, #120 (its focus), #89, #93, #100, #101, #87, #118 — all investigation-blocked or deferred, see "Moved out of v1.5.1" above.

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
| [v1.8.0 LAN/WAN discovery (env-blocked)](https://github.com/CosmicCEO/BoloKit/milestone/17) | none | Deferred from v1.3.0 (2026-09-17), all previously blocked on the `NWListener` EINVAL bug (now fixed, see the top of this file; live LAN verification still needs two Macs): [#14](https://github.com/CosmicCEO/BoloKit/issues/14) Bonjour (code landed, live LAN unverifiable), [#21](https://github.com/CosmicCEO/BoloKit/issues/21) AWDL, [#6](https://github.com/CosmicCEO/BoloKit/issues/6) dedicated host. Revisit now that hosting binds. |

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

**Manual two-peer session run 2026-09-20:** mixed result, see the top of this file; failures filed as [#75](https://github.com/CosmicCEO/BoloKit/issues/75)-[#79](https://github.com/CosmicCEO/BoloKit/issues/79) (v1.5.1).

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
