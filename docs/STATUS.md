# Status

**Current drop:** `v1.1.0-beta.1` (build 5). **`v1.0.0` shipped.**

The C-oracle port (simulation core, networking, v1 UI slice) is complete. **Bolo 2026** is playable host-and-join multiplayer: HUD (build-tool selector, resource gauges, player/pill/base status, bottom event-log bar), bundled default map or imported `.map`, keyboard- and mouse-driven tank, click-to-command builder, 50 Hz tick over a live network session.

Host/Join UI, join-side outbound protocol (movement, tile-entry, builder-task, shell-impact), HUD/kick-ban, key remap, alliance panel, messages panel, procedural sound (24 effects; several wired), preferences, zoom/scroll, and the terrain/HUD chrome/event-log visual pass are all in.

**Tests (as of the `v1.1.0-beta.1` housekeeping pass):** 774 SwiftPM (554 BoloKitTests + 220 DifferentialTests) + 40 `Bolo 2026Tests`. One pre-existing flaky timing test is documented; isolated rerun is the check, not a full-suite flake of that class.

**Signing:** permanently out of scope. Apple Development-signed, not notarized.

**Known environment issue:** on some machines `Network.framework` listener creation fails (`NWListener` EINVAL). The app falls back to local-only play with an on-screen notice. Root cause not found (ruled out: beta-OS-only, ad-hoc signing). Do not reopen an unbounded investigation.

Wave-by-wave history and the retired four-role process live at git tag `legacy-agent-process` (`docs/PLAN.md` at that tag). Do not restore those files to the working tree.

## Open product backlog

Not scheduled; do not invent a wave/GO protocol around them.

- **Win/loss UI** — simulation already computes the condition (`onTimeLimitWarning` / `onBaseControlWarning`); nothing presents it except event-log lines.
- **`hiddenmines`-style fog-of-war** — never modeled (`seentiles` / `fog` / `increasevis` / `decreasevis`). Alliance currently has no vision-merge side effect. Default is fully visible.
- **Q14 — explosions-list attribution** — C uses two irreconcilable owner rules (shell-list owner vs hardcoded `client.player`). Swift uses `state.players[shell.owner].explosions`. Cosmetic list today; still unresolved.
- **Q23 — two one-line threading gaps** — `RunTick.swift`'s `tankMoveTick(...)` call site may still omit forwarding `onMineExplosion` / `onSuperboomTerrain` / `onDropPills` (dead-tumble timeout will not scatter onboard pills). `RecvSR.swift` `smallboom`/`superboom` sites may omit one of the three closures (rare second-level splash from a broadcast receive no-ops). Not a current regression; apply when next touching those files. Verify the call sites before treating this as still open.
- **D155(2) — fire while standing on a captured base** — reported, traced as matching C's three-term fire gate (input / cooldown / shells). Unconfirmed; do not "fix" without a live repro.
- **Host-admin command surface** — pause/resume, allow-join toggle, unban. Kick/ban exists. `lockserver`/`unlockserver` are C pthread serialization and have no Swift equivalent (single-consumer actor). See `docs/ORACLE_COVERAGE.md` and verify against `Sources/` — some 2026-09-09 snapshot rows have since landed (`sendsrflood`, `serverloadmap`).
