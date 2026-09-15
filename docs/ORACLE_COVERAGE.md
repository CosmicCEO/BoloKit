# Function-level coverage: `Reference/c` → Swift

Point-in-time snapshot (2026-09-09): every top-level C function in `client.c` / `server.c` / support files was enumerated and grepped in `Sources/`. Completeness check (was anything silently missed?), not a defect review.

**Some rows have landed since the snapshot.** In particular `sendsrflood` (`onShouldBroadcastFlood` in `MineChain.swift` / `HostGameEngine.swift`) and `serverloadmap` (`serverPostProcessLoadedMap` in `BMap.swift`) are present in tree. Verify against `Sources/` before treating a row as still open. `lockserver`/`unlockserver` are C pthread serialization around a global `server` struct; the Swift host's single-consumer actor already covers that — no port.

## Totals (as of 2026-09-09)

| Source | Functions | Ported | Deferred (logged decision) | Unaccounted |
|---|---|---|---|---|
| `client.c` | 109 | 79 direct + 13 architectural-equivalent + 2 UI-chrome-noted | 15 (mostly later 1.1 work) | 0 |
| `server.c` | 103 | 82 | 10 (9× socket/thread mechanics, 1× in-code) | 11 |
| support files (`bmap*.c`, `tiles.c`, `bolo.c`, `tracker.c`, `images.c`) | ~35 | 34 | 4 (fog ×2, tracker-daemon ×2) | 6 |
| **Total** | **~247** | **~230** | **29** | **17** |

`client.c` came back clean — the only true gap-with-no-paper-trail there is `clearchangedtiles` (client.c:6310), pure screen-redraw dirty-list bookkeeping with zero game-state effect.

## Remaining gaps worth checking

### Host-admin command surface

`bolo.c` wrappers and `server.c` implementations were missing together at snapshot time:

- Manual pause/resume: `pauseresumegame` (bolo.c:100) → `pauseresumeserver` (server.c:387), `togglejoingame` (bolo.c:104) → `togglejoinserver` (server.c:427), plus `getpauseserver`/`pauseserver`/`resumeserver` (server.c:369/373/380)
- Allow-join toggle: `allowjoinserver` (bolo.c:52) → `getallowjoinserver`/`setallowjoinserver` (server.c:419/423)
- Unban: `unbanplayer` (server.c:550) — `bannedPlayers` is append-only in the Swift port; ban exists (`SessionLogic.swift`) but nothing removes an entry
- `initbolo` (bolo.c:70) — orchestrating init; callees `initserver`/`initclient` are separately accounted

Kick/ban UI exists. Confirm pause/join-toggle/unban against current `Sources/` before starting work.

### Deferred on purpose

- `sendcl*` build/damage/mine/boat/pill/refuel/hittank family — much of this later landed on the join path (B.10 and follow-ons). Grep before treating as missing.
- POSIX socket/thread lifecycle in `server.c` (`initserver`, `setupserver`, `startserverthread`, …) — not portable bug-for-bug; replaced by Network.framework idioms.
- Fog-of-war: `fogvis`, `calcvis`, `decreasevis`, `increasevis`, `testhiddenmine`, `fogtilefor` — never modeled; still deferred. See `docs/STATUS.md`.
- `main` / `child` in `tracker.c` — standalone tracker-daemon binary, not shipped.

### Judgment calls (not forced into a bucket)

- `refresh` (client.c:6272), `clearchangedtiles` (client.c:6310) — UI-chrome / dirty-region bookkeeping, no game-state effect
- 13 `client.c` lifecycle functions marked "ported (architectural)" — replaced by Network.framework session types rather than line-cited
- `recvclsendmesg` (server.c:2059) — port's own inline comment (zero GameState effect, pure broadcast relay)
