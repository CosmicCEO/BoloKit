# Standing constraints

Product law that survives the retired decision log. Provenance IDs in parentheses refer to `docs/PLAN.md` at git tag `legacy-agent-process`.

## License and oracle

- Native macOS Swift port of MIT-licensed xbolo. Keep the original copyright notice (`LICENSE`). (D1, D13)
- `Reference/c` stays in-tree permanently as a live oracle. (D151, superseding D61)
- Fidelity target: Mac Bolo **0.99.7bv** *player experience*, not WinBolo. (D3)
- XBolo (`Reference/c`) is the executable spec for what it implemented. It omitted physics, playability, and competition present in Cheshire's game. Documented overlays fill those gaps. Do not copy WinBolo to fill them.
- No WinBolo / network interop. Self-contained. (D4)
- Never copy Stuart Cheshire's original art or sound bytes. Glyphs are procedural (Unicode/ASCII). Sounds are generated. (D5, D10, D67)
- WinBolo/LinBolo (GPL v2, John Morrison) is read-only clean-room. Do not copy, transliterate, or closely paraphrase its code. (D25, D33)
- No TCMPortMapper or other GPL NAT/UPnP helper. (D32, D34)
- Signing and notarization are permanently out of scope. (D151)

## Engineering

- `Float` for position, physics, and trig. Never `Double` or `CGFloat`. (D18)
- No `import Foundation` in `BoloKit`. `import Darwin` is fine.
- Copy C float literals exactly (`0.70711219`, never `Float(sqrt(2)/2)`).
- `CXBolo` builds with `-ffp-contract=off`. Required for bit-identical `dot2f`/`mag2f` against the C oracle on arm64. (D26)
- No test or doc coverage shrink without a named replacement. Report before/after counts. (D28)
- Replicate documented C bugs unless a constraint here already records a safety deviation (e.g. bounds guards that prevent C memory corruption). Fidelity *fixes* are a separate activity from porting. (D24)
- **Invisible-bug exception to D24:** a documented C bug with no observable effect on rendered output or game-state transitions may be implemented as the evidently-intended behavior instead of replicated bug-for-bug, when the bug and the reasoning are recorded here. Anything with observable effect still needs bit-for-bit differential parity — this is a narrow carve-out, not a general license to drift from the oracle. (v1.5.0)
- **Display:** unowned, not-onboard pills render as `neutralPill00…15` / `NPIL00…15` (yellow, matching `neutralBase`). C `tilefor()` has no NPIL family and paints them hostile. Sim and `serverPostProcessLoadedMap` are unchanged. (v1.2.1)
- **Pills:** hostile armed pills acquire other hostile armed pills (same range/vis as tanks). XBolo `pilllogic()` is tank-only; this restores Cheshire-era turret duels so a placed pill can degrade an enemy pill for capture. (v1.2.2)
- **Pill duel cadence:** while the closest target is a hostile pill, fire at `minTicksPerShot` so both turrets open together. XBolo map `speed` (up to 100 ticks) is the calm tank-only reload; a faster shooter would otherwise melt a map pill before its first return shot. Speed 0 clamps to `minTicksPerShot`, not a machine gun. (v1.2.3)
- When N C per-player replicas mutate what becomes one shared Swift field, do not "call once per player in index order" — a later call can overwrite an earlier result in the same tick. Elect once per tick. (D27)
- Integer conversions from C's wrapping casts use `truncatingIfNeeded`, not trapping `UInt32(...)` / `Int16(...)`.
- Simulation tick is 50 Hz (`ticksPerSec` in `Physics.swift`).

## Fidelity vs WinBolo

XBolo must match original Bolo 0.99.7, **not** WinBolo:

- **Wall friction:** original applies substantial friction that halts momentum. WinBolo is "like ice." Port the C collision response in `client.c` exactly.
- **Tank deceleration:** original brakes precisely. WinBolo overshoots. Float tick accumulation (D18) is the safeguard.
- **Boat-to-land transition:** original applies resistance at the water/land boundary. WinBolo treats it as a plain speed-zone change. This is **not** captured by `terrainMaxSpeed`.
- **Mine self-damage:** original does **not** damage the laying tank on detonation. WinBolo does. Skip the owner.
- **Mine self-damage asymmetry:** `smallboom`'s tank-damage check is independent of the self-caused gate — a smallboom **can** damage the tank that caused it. `superboom`'s damage check is nested inside the self-caused gate — a superboom you caused yourself never damages you. Not symmetric.
- **Builder retrieval:** original retrieves stranded builders by proximity. WinBolo requires killing them first. Match the proximity-only check.
- **Pillbox range:** WinBolo fires ~0.5 squares too far. Use only the C oracle constant.
- **Tick rate:** 50 Hz in both original and WinBolo. Matches `ticksPerSec`.

## Fog-of-war (v1.5.0, issue #1)

- **Host-authoritative fog, not client-side rendering-only (deviation from `Reference/c`):**
  in the C oracle, fog is a pure client-side rendering filter — every client already holds
  full ground-truth terrain/mines locally over the wire; `fog`/`seentiles` only gate what
  gets drawn. This port's host instead tracks one `FogState` per connected player slot and
  redacts every terrain-affecting broadcast (including the initial map send) per
  recipient — a player who has never had a tile visible never receives its true data over
  the wire at all. Confirmed with the repo owner: a deliberate, documented deviation
  because it improves the security/trust model with no visible-output cost to a
  well-behaved client. The visibility *algorithm* (`increaseVis`/`decreaseVis`/
  `fogTileFor`/`revealNearbyHiddenMines`) stays bit-for-bit ported and differentially
  tested against `Reference/c`; only *where the state lives* and *what crosses the wire*
  differs.
- **Discovered-defect fix (loopback host+guest fog-reveal test):** `revealNearbyHiddenMines`
  previously called `fogTileFor` (the substituting, sticky-reveal-only-if-already-known
  variant) instead of C's real `testhiddenmine`→`refresh`→`tilefor()` path (ground truth,
  no substitution, `client.c:4462-4498,6272-6303`) — a mine within 2.0 units was never
  actually force-revealed, contradicting this section's own "bit-for-bit ported" claim
  above. Separately, `HostGameEngine.updateFogVision`'s `queueReveals` always sent
  `unminedTerrain(real)` over the wire regardless of what the host's own `FogState` had
  just decided, so even a correct local reveal never reached the guest. Both fixed; a mine
  within 2.0 units of an observer's tank (host or guest) now crosses the wire as its real
  mined terrain and stays that way (sticky), matching `docs/TEST_TWO_MAC_FOG.md` step 3.4.
- **`hiddenMines` gates the entire fog system**, not just mine-substitution as in C (where
  `fog`/`seentiles` tracking is always on and `hiddenmines` only gates `fogtilefor`'s
  mined-terrain substitution branch). Matches the issue's "fully visible remains default"
  requirement; zero added cost when the host doesn't enable it.
- **Pill/base ownership is never fog-redacted**, matching the oracle: `fogtilefor`'s
  pill/base branch reads live ownership unconditionally regardless of `hiddenmines`; only
  the mined-terrain branch is gated. `SRCapturePill`/`SRCaptureBase`/etc. stay
  unconditional broadcasts.
- **`increasevis`'s `insetrect(r, -1, -1)` second pass** (`client.c:3876-3921`) actually
  *grows* the reveal-recompute rect by 1 in each direction — a sign-convention artifact of
  `insetrect`, not a deliberate behavior, with no visible/gameplay consequence either way.
  Per the invisible-bug exception above: implemented as the evidently-intended behavior —
  re-snapshot `seenTiles` over exactly the same rect `fog` was incremented over, no
  separate inset pass.
- **`testhiddenmine`/`refresh`'s unbounded near-map-edge indexing** in C silently wraps to
  an adjacent row (row-major memory layout); a literal Swift `Array` port would trap. Real
  safety deviation, not an invisible-bug judgment call: bounds-clamp coordinates into
  `0..<256` before indexing.
- **Never-seen tiles cross the wire as ordinary `sea` terrain.** `BMap.swift`'s RLE nibble
  codec has no room for a real "unknown" sentinel. The client separately tracks which
  tiles it has actually received a reveal for (from the initial map plus subsequent reveal
  messages) and renders `Tile.unknown` for anything not yet revealed. No wire format
  change; costs nothing extra on the wire in the common case.
- **`fogVis`/`calcVis`** (`bolo.c:108-150,214-323`) are never called anywhere in
  `Reference/c` — confirmed by exhaustive grep, unlike `forestVis` (`bolo.c:174`), which
  *is* called (for pillbox target-acquisition line-of-sight, already ported at
  `PillTick.swift:86`, unrelated to fog). Working theory, confirmed with the repo owner:
  an unfinished Mac Bolo feature XBolo's own port left unwired, not a feature the real
  game lacked — this port's fidelity target is Mac Bolo 0.99.7bv, not XBolo specifically
  (D3). Ported bit-for-bit and differentially tested against `Reference/c`'s own (unused)
  functions, *and* wired into sprite rendering as a continuous per-sprite fade near the
  fog boundary. The math is oracle-verified; the wiring is a reconstruction with no
  oracle-exercised behavior to verify against.
- Vision-rectangle sizes have no `bolo.h` macro — hardcoded literals at each `client.c`
  call site: tank vision 29×29 tiles (`pos ± 14`), pill/base vision 15×15 tiles
  (`pos ± 7`), hidden-mine proximity 2.0 world units, `calcVis` self-visibility floor 3.0
  world units.

## Host is also a client (v1.5.0 live-hosting fixes)

The C server is a relay: `dgramserver()` stores only a sender's `tank.x`/`tank.y` (`server.c:670-672`)
and forwards the packet. In XBolo the human host is also a *client* that connects to its own server,
so it applies every guest's full update via `dgramclient()`. This port merges the two roles into one
process with one authoritative `GameState` (`HostGameEngine`), so the merged host must do both jobs.

- `processDgramPacket` still decides accept/drop/relay exactly like `dgramserver()` (T-2..T-8), but on
  accept it also applies the sender's full state with `applyRemotePlayerUpdate` (dead, dir, boat, speed,
  builder, input flags, shells, explosions). Tank-only application left every guest `dead == true`
  (`PlayerState.dead` defaults to true), so the host never drew, moved or hit it.
- Terrain and sound callbacks stay no-ops on that path. Terrain events reach the host through the TCP CL
  messages, so applying them from UDP as well would double-apply. Host-side sounds for guest actions are
  not wired (follow-up).
- The host's own outbound `CLUpdate` carries its own `localSeq` in its own slot of `header.seq`. The C
  host-client did this implicitly by being a real client; without it every guest rejected every host update
  as not newer.
- The 9-second lag eviction (`RunTick` step 4, `server.c:1188-1204`) is unchanged: a guest whose datagrams
  the host never accepts is evicted. That eviction closes the guest's TCP, so the resulting
  "connection ended" is ignored for a player already marked disconnected (one departure, one message).

## Host-simulated guest tanks (#59/#62)

A deliberate deviation from the C oracle, ruled by the owner on 2026-09-21 (#59). In C every client
simulates its own tank fully (`tankLocalTick`/`enter()`), then reports tile entries, mine detonations and
damage to the server (`CLGrabTile`, `CLDropBoat`, `CLTouch`, `CLDamage`, ...). The port's join-path guest is a
deliberately partial client (`GameSession`, D116/D139): it never ran that code, so a guest could not fire,
adjust range, drown, trigger mines or take damage. Rather than port the whole client protocol, the host now
runs that code for each remote player, from the player's input flags, and is the single source of truth for
combat state. Enabled by `GameState.hostSimulatesRemotePlayers`, set only for real network hosting
(`networkHostState(from:)`); solo/local-only play never sets it.

- **Authority split.** The guest owns its movement (`tank`, `dir`, `speed`, `turnSpeed`, `inputFlags`,
  builder fields), exactly as in C, so steering never waits on a round trip. The host owns `dead`, `boat`,
  shells, explosions, kick, that player's `localStats` (armour, shells, range, respawn) and its
  mines/trees counts; `applyRemotePlayerUpdate` does not overwrite them and the dead-reckoning extrapolation
  is skipped for simulated players (S3).
- **`SRTankStatus` (opcode 35, host -> guest, port-only, no C counterpart).** Carries the receiver's own
  armour, shells, mines, trees, range, dead, boat, kick and an optional respawn teleport. Sent on change
  (death, damage, firing, kick, refuel), never as a stream, and applied to the guest's own slot. Like
  `SRRevealTerrain`, an older build would not understand it; the guest keeps its old behaviour until the
  first status arrives (`GameSession.hostSimulatesMe`), so a newer guest against an older host degrades to
  the previous partial client.
- **Guest thinning.** Once told it is simulated, the guest stops sending tile-entry reports, `CLDamage` and
  running its own dead-tank respawn (`JoinTickThinning`). Movement, builder round trips, chat, alliances
  and the discrete key-down `CLDropMine` stay the guest's.
- **Tile entry uses the last evaluated tile.** A remote's position arrives as jumps between host ticks, so
  `runTick` compares the tile it last evaluated (`GameState.remoteLastTankPosition`) with the current one,
  not the tile at the start of the tick (which already includes the jump). Found by the loopback test; a
  jump across a boundary otherwise skipped the mine under it.
- **Not covered.** The guest still does not see its own shells (S5), and it does not see its own death
  explosion animation (the host keeps it in that player's `explosions`).

## Physics constants

From `bolo.h`. Live values belong in `Physics.swift`; do not re-derive.

| Swift name | Value | C macro |
|---|---|---|
| tankRadius | 0.375 | TANKRADIUS |
| builderRadius | 0.125 | BUILDERRADIUS |
| shellVelocity | 7.0 | SHELLVEL |
| maxShellRange | 7.0 | MAXRANGE |
| kickForce | 3.125 | KICKFORCE |
| explosionTicks | 24 | EXPLOSIONTICKS *(particle display)* |
| explodeTicks | 45 | EXPLODETICKS *(death animation)* |
| respawnTicks | 150 | RESPAWN_TICKS |
| maxShells | 40 | MAXSHELLS |
| maxMines | 40 | MAXMINES |
| maxArmour | 40 | MAXARMOUR |
| maxTrees | 40 | MAXTREES |
| roadTrees | 2 | ROADTREES |
| wallTrees | 2 | WALLTREES |
| boatTrees | 20 | BOATTREES |
| pillTrees | 4 | PILLTREES |
| maxPlayers | 16 | MAXPLAYERS |
| maxStarts | 16 | MAX_STARTS |
| pillOnboard | UInt8(0xff) | ONBOARD |
| playerNeutral | UInt8(0xff) | NEUTRAL |
| noPill | UInt8(0xff) | NOPILL |
| minBaseArmour | 5 | MINBASEARMOUR |

- `explosionTicks` (24) — how long an `Explosion` particle effect renders before removal from the list.
- `explodeTicks` (45) — how long the dead-tank explosion animation plays before `spawn()` is eligible (`respawncounter > EXPLODETICKS`).
