# Function-level parity coverage: `Reference/c` → Swift

Standing artifact, filed by PLANNER via D129. Produced by 3 parallel PARITY-style audit
operatives (client.c / server.c / support files), each independently enumerating every
top-level C function and grepping `Sources/` for a citation, then cross-checking any
uncited function against `docs/PLAN.md`'s decisions log before calling it unaccounted. This
is a completeness check (was anything silently missed?), not a defect review — it does not
replace PARITY's normal post-commit behavioral audits.

**This is a point-in-time snapshot (2026-09-09).** Re-run per new wave/phase, not treated as
self-maintaining.

## Totals

| Source | Functions | Ported | Deferred (logged decision) | Unaccounted |
|---|---|---|---|---|
| `client.c` | 109 | 79 direct + 13 architectural-equivalent + 2 UI-chrome-noted | 15 (mostly D128 backlog) | 0 |
| `server.c` | 103 | 82 | 10 (9× D31/D42 socket/thread mechanics, 1× in-code) | 11 |
| support files (`bmap*.c`, `tiles.c`, `bolo.c`, `tracker.c`, `images.c`) | ~35 | 34 | 4 (D65 ×2, D59 ×2) | 6 |
| **Total** | **~247** | **~230** | **29** | **17** |

`client.c` came back clean — the only true gap-with-no-paper-trail there is `clearchangedtiles`
(client.c:6310), and that's pure screen-redraw dirty-list bookkeeping with zero game-state
effect, so it's noted as UI-chrome rather than a real finding.

## Unaccounted findings (the actual output of this audit)

These have no Swift citation anywhere in `Sources/` and no matching entry in `docs/PLAN.md`'s
decisions log. Two clusters, corroborating each other across files:

### 1. Host-admin command surface — entirely missing, both layers

`bolo.c`'s thin wrappers and `server.c`'s implementations are missing together, confirming
this isn't a citation-search miss but a real absent feature:

- Manual pause/resume: `pauseresumegame` (bolo.c:100) → `pauseresumeserver` (server.c:387),
  `togglejoingame` (bolo.c:104) → `togglejoinserver` (server.c:427), plus
  `getpauseserver`/`pauseserver`/`resumeserver` (server.c:369/373/380)
- Allow-join toggle: `allowjoinserver` (bolo.c:52) → `getallowjoinserver`/`setallowjoinserver`
  (server.c:419/423)
- Server lock: `lockserver`/`unlockserver` (server.c:454/465)
- Unban: `unbanplayer` (server.c:550) — `bannedPlayers` is append-only in the Swift port;
  ban exists (`SessionLogic.swift:171`) but nothing removes an entry
- `initbolo` (bolo.c:70) — the orchestrating init entry point itself has no cited counterpart,
  though its callees (`initserver`/`initclient`) are separately accounted for

C.0 (already-closed, kick/ban) explicitly did not claim this surface — it's a genuine gap,
not a scope violation of a closed wave.

### 2. `sendsrflood` — missing broadcast hook (server.c:3261)

`flood()`/`floodAt()` (`MineChain.swift:264-283`) execute the flood but have no
`onShouldBroadcastFlood`-shaped callback the way every sibling `sendsr*` operation does
(e.g. `onShouldBroadcastSmallBoom`). Clients would not be notified of a flood event over the
network. Distinct from any logged decision.

### 3. `serverloadmap` — distinct from the already-ported `clientloadmap` (bmap_server.c:21)

`decodeBMap`/`clientloadmap` is ported and cited, but `serverloadmap`'s NEUTRAL-owner-forcing
and mine-clearing-at-load logic (bmap_server.c:75-252) has no traced Swift counterpart. Every
existing citation of `decodeBMap` treats it as the port of `clientloadmap` only.

## Deferred (already covered by a logged decision — not new work)

- **D128** (1.1 backlog): `sendcl*` build/damage/mine/boat/pill/refuel/hittank family (12
  functions in client.c) — B.10's builder-task/shell-impact `CL*` follow-on; `printmessage`/
  `sendmessage` (C.4 messages panel); `requestalliance`/`leavealliance` (C.2); `keyevent`
  partial (C.1); fog-of-war family `decreasevis`/`increasevis`/`testhiddenmine`/`fogtilefor`
  (Milestone D / D65)
- **D31/D42**: POSIX socket/thread lifecycle mechanics in `server.c` (`initserver`,
  `setupserver`, `startserverthread`, `startserverthreadwithtracker`, `stopserver`,
  `discjoiningplayerserver`, `selectserver`, `recvplayerserver`, `cleanupserver`) — ruled
  not portable bug-for-bug, replaced by Network.framework idioms
- **D65**: `fogvis`, `calcvis` (bolo.c) — fog-of-war display layer, deferred to a later wave
- **D59**: `main`, `child` (tracker.c) — standalone tracker-daemon binary not shipped

## Judgment calls flagged for review, not forced into a bucket

- `refresh` (client.c:6272), `clearchangedtiles` (client.c:6310) — UI-chrome / dirty-region
  bookkeeping, no game-state effect
- 13 `client.c` lifecycle functions (`initclient` … `dgramclient` region) marked "ported
  (architectural)" — replaced wholesale by Network.framework session types rather than
  literally cited line-by-line; 6 of these 13 have no direct line-cite at all. Worth a second
  look if a stricter citation-only standard is wanted.
- `recvclsendmesg` (server.c:2059) — deferred by the port's own inline comment (zero
  GameState effect, pure broadcast relay), not by a PLAN.md D-number. Should probably get one.

## Next step

PLANNER to log a new decision (see `docs/PLAN.md` D129) filing the host-admin command surface
and `sendsrflood` as new 1.1-backlog items, and `serverloadmap` as a correctness gap to
investigate before any dedicated-host-focused work in 1.1.
