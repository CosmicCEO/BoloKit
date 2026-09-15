# Status

**Current drop:** `v1.1.0` (build 6). **`v1.0.0` shipped.**

The C-oracle port (simulation core, networking, v1 UI slice) is complete. **Bolo 2026** is playable host-and-join multiplayer: HUD (build-tool selector, resource gauges, player/pill/base status, bottom event-log bar), bundled default map or imported `.map`, keyboard- and mouse-driven tank, click-to-command builder, 50 Hz tick over a live network session.

Host/Join UI, join-side outbound protocol (movement, tile-entry, builder-task, shell-impact), HUD/kick-ban, key remap, alliance panel, messages panel, procedural sound (24 effects; several wired), preferences, zoom/scroll, and the terrain/HUD chrome/event-log visual pass are all in.

**Tests (as of the `v1.1.0` close-out pass):** 775 SwiftPM (555 BoloKitTests + 220 DifferentialTests) + 49 `Bolo 2026Tests`. One pre-existing flaky timing test is documented; isolated rerun is the check, not a full-suite flake of that class.

**Signing:** permanently out of scope. Apple Development-signed, not notarized.

**Known environment issue:** on some machines `Network.framework` listener creation fails (`NWListener` EINVAL). The app falls back to local-only play with an on-screen notice. Root cause not found (ruled out: beta-OS-only, ad-hoc signing). Do not reopen an unbounded investigation.

Wave-by-wave history and the retired four-role process live at git tag `legacy-agent-process` (`docs/PLAN.md` at that tag). Do not restore those files to the working tree.

## Next sprints

Tracked as GitHub issues. Do not invent a wave/GO protocol around them.

- [#4 Ship v1.1.0](https://github.com/CosmicCEO/BoloKit/issues/4) — **this drop.**
- [#1 Hidden-mines fog-of-war](https://github.com/CosmicCEO/BoloKit/issues/1) — `seentiles` / `increasevis` / `decreasevis` / `testhiddenmine`; alliance vision merge. Default stays fully visible.
- [#6 Dedicated headless host](https://github.com/CosmicCEO/BoloKit/issues/6) — SPM executable over `HostGameEngine`. See `docs/notes/HOSTMODELS.md`.

## Parking lot

Non-blocking; not in the three sprints.

- [#5 Q14 explosions-list owner](https://github.com/CosmicCEO/BoloKit/issues/5) — C disagrees with itself; cosmetic.
- [#7 D155(2) fire on captured base](https://github.com/CosmicCEO/BoloKit/issues/7) — unconfirmed; do not “fix” without a live repro.
- [#8 Wire remaining procedural sounds](https://github.com/CosmicCEO/BoloKit/issues/8)
- [#3 Join-side connection lag tint](https://github.com/CosmicCEO/BoloKit/issues/3)
- [#9 Standalone tracker daemon](https://github.com/CosmicCEO/BoloKit/issues/9) — not the dedicated game host.
- [#2 Refresh ORACLE_COVERAGE.md snapshot](https://github.com/CosmicCEO/BoloKit/issues/2)

## Landed this close-out (`v1.1.0` sprint)

- **Win/loss UI** — `MatchEndOverlay` latches on `EventLogText.timeLimitReached` / `baseControlReached` already written to `GameSession.messages`. Display-only; no new `GameState` flag.
- **Host-admin surface** — pause/resume and allow-join on the host top bar; unban on the status grid. Engine submit APIs were already in (`HostGameEngine` D129).
- **Q23** — `runTick` now forwards `onMineExplosion` / `onSuperboomTerrain` into `tankMoveTick` (dead-tumble superboom). `recvSrSmallBoom` / `recvSrSuperBoom` nested `smallboom`/`superboom` now pass all three closures. `onDropPills` was already replaced by `onShouldBroadcastDropPill` (B.5d).
