# Standing constraints

Product law that survives the retired decision log. Provenance IDs in parentheses refer to `docs/PLAN.md` at git tag `legacy-agent-process`.

## License and oracle

- Native macOS Swift port of MIT-licensed xbolo. Keep the original copyright notice (`LICENSE`). (D1, D13)
- `Reference/c` stays in-tree permanently as a live oracle. (D151, superseding D61)
- Fidelity target: Mac Bolo **0.99.7bv**, not WinBolo. (D3)
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
- **Display:** unowned, not-onboard pills render as `neutralPill00…15` / `NPIL00…15` (yellow, matching `neutralBase`). C `tilefor()` has no NPIL family and paints them hostile. Sim and `serverPostProcessLoadedMap` are unchanged. (v1.2.1)
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
