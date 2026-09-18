# Function-level coverage: `Reference/c` → Swift

Point-in-time snapshot (2026-09-15): re-grepped `Sources/` against `Reference/c`. Completeness check (was anything silently missed?), not a defect review.

`sendsrflood` (`onShouldBroadcastFlood` in `MineChain.swift` / `HostGameEngine.swift`), `serverloadmap` (`serverPostProcessLoadedMap` in `BMap.swift`), and the host-admin surface (`pauseResumeServer` / `setAllowJoin` / `togglejoinserver` / `unbanplayer` in `SessionLogic.swift` + `HostGameEngine` submit APIs + HUD) are in tree. `lockserver`/`unlockserver` are C pthread serialization around a global `server` struct; the Swift host's single-consumer actor already covers that — no port.

Brace-on-same-line function regex undercounts `client.c`/`server.c` versus the 2026-09-09 enumeration (many K&R / split signatures). Totals below are the 2026-09-09 census; the **Remaining gaps** list is what was re-verified against `Sources/` on 2026-09-15.

## Totals (census 2026-09-09; gaps re-verified 2026-09-15)

| Source | Functions | Ported | Deferred (logged decision) | Unaccounted |
|---|---|---|---|---|
| `client.c` | 109 | 79 direct + 13 architectural-equivalent + 2 UI-chrome-noted | 15 (mostly later 1.1 work) | 0 |
| `server.c` | 103 | 82 | 10 (9× socket/thread mechanics, 1× in-code) | 11 |
| support files (`bmap*.c`, `tiles.c`, `bolo.c`, `tracker.c`, `images.c`) | ~35 | 36 (fog landed, v1.5.0) | 2 (tracker-daemon ×2) | 6 |
| **Total** | **~247** | **~232** | **27** | **17** |

`client.c` came back clean — the only true gap-with-no-paper-trail there is `clearchangedtiles` (client.c:6310), pure screen-redraw dirty-list bookkeeping with zero game-state effect.

## Remaining gaps worth checking

### Host-admin command surface — landed

Confirmed in `Sources/` on 2026-09-15 (`SessionLogic.swift`, `HostGameEngine.swift` submit APIs, `GameSession` / HUD):

- Pause/resume: `pauseResumeServer` / `pauseServer` / `resumeServer` (`pauseresumegame` / `pauseresumeserver`)
- Allow-join: `setAllowJoin` / `togglejoinserver`
- Unban: `unbanPlayer` (`unbanplayer`) — no longer append-only
- Kick/ban UI was already present

`initbolo` remains an orchestrating init; callees `initserver`/`initclient` are architectural (Network.framework).

### Deferred on purpose

- `sendcl*` build/damage/mine/boat/pill/refuel/hittank family — much of this later landed on the join path (B.10 and follow-ons). Grep before treating as missing.
- POSIX socket/thread lifecycle in `server.c` (`initserver`, `setupserver`, `startserverthread`, …) — not portable bug-for-bug; replaced by Network.framework idioms.
- `main` / `child` in `tracker.c` — standalone tracker-daemon binary, not shipped.

### Fog-of-war — landed (v1.5.0, issue #1)

`fogvis`/`calcvis`/`decreasevis`/`increasevis`/`testhiddenmine`/`fogtilefor` are now ported
(`Sources/BoloKit/FogState.swift`, `Sources/BoloKit/CalcVis.swift`), differentially tested
against `Reference/c` (`Tests/DifferentialTests/FogDifferentialTests.swift`), and wired end
to end: host-side per-connected-player `FogState` tracking (`HostGameEngine.swift`),
host-local rendering (`GameRenderView.swift`), and wire-protocol redaction of both the
initial map send and subsequent terrain-affecting broadcasts (`HostListener.swift`/
`HostSession.swift`). See `docs/CONSTRAINTS.md`'s "Fog-of-war" section for the
host-authoritative deviation from the C oracle's client-side-only model, and `docs/STATUS.md`
for the one remaining known gap (pill/base state transitions don't yet act as their own
vision sources).

### Judgment calls (not forced into a bucket)

- `refresh` (client.c:6272), `clearchangedtiles` (client.c:6310) — UI-chrome / dirty-region bookkeeping, no game-state effect
- 13 `client.c` lifecycle functions marked "ported (architectural)" — replaced by Network.framework session types rather than line-cited
- `recvclsendmesg` (server.c:2059) — port's own inline comment (zero GameState effect, pure broadcast relay)
