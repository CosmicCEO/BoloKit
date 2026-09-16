# Status

**Current drop:** `v1.2.2` (build 9). **`v1.2.1`, `v1.2.0`, `v1.1.0` and `v1.0.0` shipped.**

The C-oracle port (simulation core, networking, v1 UI slice) is complete. **Bolo 2026** is playable host-and-join multiplayer: HUD (build-tool selector, resource gauges, player/pill/base status, bottom event-log bar), bundled default map or imported `.map`, keyboard- and mouse-driven tank, click-to-command builder, 50 Hz tick over a live network session.

Host/Join UI, join-side outbound protocol (movement, tile-entry, builder-task, shell-impact), HUD/kick-ban, key remap, alliance panel, messages panel, procedural sound (24 effects; several wired), preferences, zoom/scroll, and the terrain/HUD chrome/event-log visual pass are all in.

**Tests (as of the `v1.2.2` pass):** 792 SwiftPM (572 BoloKitTests + 220 DifferentialTests) + 66 `Bolo 2026Tests`. One pre-existing flaky timing test is documented; isolated rerun is the check, not a full-suite flake of that class. Confirm with `swift test` at tag. BoloKitTests 562 → 572 this patch (pill-vs-pill).

**Signing:** permanently out of scope. Apple Development-signed, not notarized.

**Known environment issue:** on some machines `Network.framework` listener creation fails (`NWListener` EINVAL). The app falls back to local-only play with an on-screen notice. Root cause not found (ruled out: beta-OS-only, ad-hoc signing). Do not reopen an unbounded investigation.

Wave-by-wave history and the retired four-role process live at git tag `legacy-agent-process` (`docs/PLAN.md` at that tag). Do not restore those files to the working tree.

## Next sprints

Tracked as GitHub issues and milestones. Do not invent a wave/GO protocol around them. Board: [#43](https://github.com/CosmicCEO/BoloKit/issues/43).

- [v1.3.0 Find and share games](https://github.com/CosmicCEO/BoloKit/milestone/2) — #14 Bonjour, #21 AWDL, #20 `bolo://`, #24 tracker+UPnP, #6 dedicated host, #26 Quick Look (needs the v1.2 UTI).
- [v1.4.0 Controls, HUD, sound](https://github.com/CosmicCEO/BoloKit/milestone/8) — #17 controller, #3 lag tint, #8 remaining sounds, #23 Observable HUD, #22 App Intents, #16 OSLog.
- [v1.5.0 Hidden-mines fog](https://github.com/CosmicCEO/BoloKit/milestone/3) — [#1](https://github.com/CosmicCEO/BoloKit/issues/1).
- Later: v1.6 Metal (#25), v1.7 packs. Decide:* on [project 2](https://github.com/users/CosmicCEO/projects/2).

## Parking lot

Decide / later-milestone items. Not coding work until a ruling or a release milestone says so.

- [#5 Q14 explosions-list owner](https://github.com/CosmicCEO/BoloKit/issues/5) — Decide: Oracle parking lot.
- [#7 D155(2) fire on captured base](https://github.com/CosmicCEO/BoloKit/issues/7) — Decide: Oracle parking lot.
- [#9 Standalone tracker daemon](https://github.com/CosmicCEO/BoloKit/issues/9) — Decide: WAN directory.

## Landed this close-out (`v1.2.2` patch)

[#45](https://github.com/CosmicCEO/BoloKit/issues/45) Hostile armed pills acquire other hostile armed pills (same range/vis as tanks). XBolo `pilllogic()` is tank-only; this fills a Cheshire-era competition gap so a placed turret can degrade an enemy pill for capture. Allied pills still ignore each other. Training map unchanged.

## Previous close-out (`v1.2.1` patch)

[#44](https://github.com/CosmicCEO/BoloKit/issues/44) Unowned pills draw yellow (`neutralPill00…15` / `NPIL00…15`), matching `neutralBase`. C `tilefor()` still paints them hostile — documented product overlay, not a sim change. Dead (armour 0) pills get a visible wreck mound. Training-map pickup at `(108, 123)` is now readable as unowned.

## Previous close-out (`v1.2.0` sprint)

Mac-native chrome. No BoloKit physics changes.

- [#12](https://github.com/CosmicCEO/BoloKit/issues/12) PrivacyInfo.xcprivacy (UserDefaults CA92.1)
- [#13](https://github.com/CosmicCEO/BoloKit/issues/13) Game Mode, games category, Full Screen
- [#11](https://github.com/CosmicCEO/BoloKit/issues/11) `com.cosmicceo.bolo-map` UTI and Open With
- [#15](https://github.com/CosmicCEO/BoloKit/issues/15) Icon Composer `AppIcon.icon`
- [#18](https://github.com/CosmicCEO/BoloKit/issues/18) SwiftUI Game/View Commands
- [#19](https://github.com/CosmicCEO/BoloKit/issues/19) VoiceOver HUD labels
- [#2](https://github.com/CosmicCEO/BoloKit/issues/2) ORACLE_COVERAGE snapshot refresh
