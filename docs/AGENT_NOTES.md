# Agent Notes — Shared Running Log

> **Purpose:** Durable scratchpad shared between Claude Xcode API (implementer) and Claude.ai (reviewer and planner).
> High-level decisions belong in `PLAN.md`.
> This file is for implementation-level continuity: what was tried, what broke, what was resolved, and flags between agents.
>
> **Convention:** Always append — never edit or rewrite earlier entries. Pull before reading.

--
## Format

Each entry uses this block:

```
### [AGENT] YYYY-MM-DD — short title

Body — a few lines. Be concrete. No filler.

> **→ Parity:** action item or handoff note (omit if not applicable)
> **→ Planner:** item for review or question (omit if not applicable)
> **→ Implementer:** instructions for the xcode agent, coding environment (omit if not applicable)
```

Types:
- **[PLANNER]** — wave assignments, sign-offs, architectural decisions
- **[IMPLEMENTER]** — completion reports, build results, deviations from spec
- **[PARITY]** — audit findings, behavioral verification, sign-offs

---

## Index

| Archive | Content |
|---|---|
| `docs/notes/archive.md` | Waves 1–4 compressed summaries (search git history for full detail) |

**PARITY activation rule (change 3):** PARITY runs **post-commit only**. PARITY is activated exclusively by a `[TO: PARITY]` tag in a PLANNER sign-off after IMPLEMENTER commits. PARITY does NOT run during planning phases. This saves ~1 full session of credit per wave.

---

## Wave 5 Active Log

### [PLANNER] 2026-08-31 — Wave 5 pre-read: tank physics tick loop
**Type:** research / pre-brief
**Phase:** 1 / Wave 5 pre-planning
**Blocks:** nothing (Wave 4.1 still in progress)

Pre-read of `client.c` functions: `runclient`, `tankmovelogic`, `tanklocallogic`,
`tankcollision`, `maxspeed`, `maxturnspeed`, `rounddir`.

#### Tick loop order — `runclient()` (line 425)

Called at 50 Hz. Per tick:
1. `tankmovelogic(i)` — all connected players
2. `tanklocallogic(old)` — local player only (tank-tank collisions, base/pill touch)
3. `builderlogic(i)` — all players
4. `pilllogic(old)` — pillbox AI
5. `shelllogic(i)` — all players
6. `explosionlogic(i)` — all players + neutral (-1)
7. `sendclupdate()` — every 5 ticks

#### `tankmovelogic` physics — key findings

**Position update (alive tank, line 4113):**
```
tank += (dir2vec(rounddir(dir)) * speed + dir2vec(kickdir) * kickspeed) / TICKSPERSEC
```
`rounddir` snaps the moving direction to 16 discrete headings (π/8 radian steps):
```c
float rounddir(float dir) {
  return (kPif/8.0) * floor(dir/(kPif/8.0) + 0.5);
}
```
Direction is stored continuously (for smooth turning) but movement is quantized to 16 headings.
**This is a fidelity-critical detail — do not drop `rounddir` in Wave 5.**

**KickSpeed decay:** `kickspeed -= 12.0/TICKSPERSEC` per tick (clamped at 0). Needs `kickSpeedDecay: Float = 12.0` constant in Physics.swift.

**Turning:** Angular acceleration to/from `maxturnspeed(x,y)` (or `MAXANGULARVELOCITY=2.5` on boat). Direction zeroed immediately on no-input (no momentum). Direction wrapped to [0, 2π].

**Shore push (boat near land):** 8-case vector geometry applying `PUSHFORCE=1.5625` per tick when boat is within `TANKRADIUS=0.375` of a shore cell. If not accelerating forward, also brakes by `ACCEL/TICKSPERSEC`. This is the boat-to-land transition force PARITY flagged — must be ported exactly.

**Wall collision:** `collisiondetect(tank, TANKRADIUS, tankcollision)` — circular-radius collision with a callback. `tankcollision` returns solid for: out-of-bounds, armed pills, hostile bases, walls, damagedWalls. All other terrain passable.

**Dead tank:** Moves along kickdir, collides with terrain, spawns explosion particles every 5 ticks. After `EXPLODETICKS=45` ticks: superboom (≥32 mines) or smallboom. After `RESPAWN_TICKS=150` ticks: calls `spawn()`.

#### `maxspeed(x,y)` — pill/base overrides (line 3594)

Our Wave 3.1 `terrainMaxSpeed` is only the terrain portion. The full C `maxspeed()`:
1. If an armed pill is at (x,y) → `0.0` (blocked)
2. If a dead pill is at (x,y) → `3.125` (road speed — passable)
3. If a base is at (x,y) → `3.125`
4. Otherwise → terrain switch (matches Wave 3.1)

**Wave 5.0 must port this complete form as `maxSpeed(x:y:terrain:pills:bases:) -> Float`.** The Wave 3.1 `terrainMaxSpeed` stays as an internal building block.

#### Additional bolo.h constants needed in Physics.swift

```swift
public let tankRadius: Float = 0.375
public let maxAngularVelocity: Float = 2.5       // boat turn speed cap
public let pushForce: Float = 1.5625             // shore push force (squares/sec)
public let kickSpeedDecay: Float = 12.0          // kickspeed decrease per second
public let explodeTicks: Int = 45                // death explosion duration
public let respawnTicks: Int = 150               // ticks before respawn
```

#### Architectural note: decoupling from `client`

ALL physics functions (`tankmovelogic`, `shelllogic`, etc.) read/write the global `client` struct.
Wave 5 requires defining a Swift `GameState` (or equivalent) that replaces the global.
This is the biggest architectural challenge in the port. PLANNER will scope the model in a
separate entry before issuing Wave 5.0. Do NOT start Wave 5 without that model definition.

#### Wave 5 sub-wave plan (preliminary)

| Sub-wave | Scope |
|---|---|
| Wave 5.0 | Physics constants additions, `roundDir()`, `maxSpeed(x:y:terrain:pills:bases:)`, `maxTurnSpeed(...)` |
| Wave 5.1 | `GameState` model — Swift equivalent of `client` struct (tanks, pills, bases, shells, builders) |
| Wave 5.2 | `tankMoveTick` — core tank physics (turning, accel, shore push, collision, kickspeed) |
| Wave 5.3 | `shellTick` — shell movement, collision, damage |
| Wave 5.4 | `builderTick` — LGM movement, build actions |
| Wave 5.5 | `pillTick` — pillbox AI; `explosionTick` |
| Wave 5.6 | `killtank`, `spawn` — respawn system |

[TO: PARITY] Review this pre-read for fidelity gaps before Wave 5.0 is assigned.

### [PLANNER] 2026-08-31 — Wave 5 pre-brief: GameState model + collisionDetect
**Type:** research / architecture
**Phase:** 1 / Wave 5 pre-planning
**Blocks:** nothing — for IMPLEMENTER reference before Wave 5.1 is assigned

#### `client` struct analysis — what Wave 5.1 `GameState` needs

Read `client.h` lines 19–345 and `bolo.h` Pill/Base/Start/Shell/Explosion structs.

**`GameState` simulation fields (Swift Wave 5.1 deliverable):**

```swift
// Per-player state (up to MAXPLAYERS = 16)
public struct PlayerState: Sendable {
    public var connected: Bool
    public var dead: Bool
    public var boat: Bool
    public var tank: Vec2f          // world-space position (Float)
    public var dir: Float           // radians, [0, 2π)
    public var speed: Float         // squares/sec
    public var turnspeed: Float     // radians/sec
    public var kickdir: Float       // radians
    public var kickspeed: Float     // squares/sec
    public var builder: Vec2f       // builder world position
    public var builderTarget: (x: Int32, y: Int32)
    public var builderStatus: Int32
    public var builderWait: Int32
    public var alliance: UInt16
    public var inputFlags: Int32
    public var seq: Int32
    public var lastUpdate: Int32
    public var shells: [Shell]
    public var explosions: [Explosion]
    // sound flags (Bool) — tankshotSound, pillshotSound, sinkSound, builderDeathSound
}

// Pill, Base, Start match C structs exactly:
public struct Pill: Sendable { x, y, owner, armour, speed, counter: Int32 }
public struct Base: Sendable { x, y, owner, armour, shells, mines, counter: Int32 }
public struct Start: Sendable { x, y, dir: Int32 }
public struct Shell: Sendable { owner: Int32; point: Vec2f; boat, pill: Bool; dir, range: Float }
public struct Explosion: Sendable { point: Vec2f; counter: Int32 }
```

**Local-player-only fields (also in `GameState`):**
- `respawnCounter: Int32`, `spawned: Bool`
- `shellCounter: Int32`, `range: Float` (shell range carried)
- `armour, shells, mines, trees: Int32` (resources)
- `kills, deaths: Int32`
- `refueling: Bool`, `refuelingBase: Int32`, `refuelingCounter: Int32`
- `drainCounter: Int32`
- Builder task fields: `nextBuilderCommand, nextBuilderTarget, builderTask, builderMines, builderTrees, builderPill`

**NOT in GameState — network/UI/callbacks:**
Hostname, sockets, send/recv buffers, callbacks (`loopupdate` etc.) — these become a Swift delegate protocol in the Cocoa layer, not in BoloKit.

**Four 256×256 grids in GameState:**
- `terrain: TerrainGrid` — canonical terrain (already ported, Wave 1/3.1)
- `seenTiles: [Int32]` — last-seen tile display (raw tile int, 65,536 elements)
- `images: [Int32]` — mapimage output (autotiling result, 65,536 elements)
- `fog: [Int32]` — visibility counter per cell

#### `collisionDetect` — pure function, Wave 5.0 deliverable

Source: `client.c` line 6927. Swift signature:
```swift
public func collisionDetect(_ p: Vec2f, radius: Float, isSolid: (Pointi) -> Bool) -> Vec2f
```

Algorithm: checks 4 cardinal neighbor tiles within `radius`, resolves cardinal overlaps, then checks 4 diagonal corners using `sqrtf()`. Pure geometry — no game state dependency except the callback.

**🔴 C BUG — must be replicated (line ~6960):**
```c
if (lyc) {
    if (hyc) {
      p.x = fy + 0.5;  // ← WRONG: should be p.y = fy + 0.5
    }
    ...
}
```
When the entity is squeezed between solid tiles above AND below, it snaps `p.x` (x-coordinate) to the tile-center instead of `p.y`. This produces an incorrect x-shift in that rare edge case. Must be replicated — a fix would diverge from the C oracle in differential tests.

**`collisionOwner` global → closure capture in Swift:**
C code uses a global `int collisionowner` to pass context into the `tankcollision` callback. In Swift, this becomes a capture:
```swift
let owner = playerIndex
let isSolid: (Pointi) -> Bool = { [state] square in
    tankCollision(square, pills: state.pills, bases: state.bases,
                  terrain: state.terrain, collisionOwner: owner)
}
tank = collisionDetect(tank, radius: tankRadius, isSolid: isSolid)
```

#### Constants still missing from Physics.swift (Wave 5.0 additions)

```swift
public let tankRadius: Float = 0.375
public let builderRadius: Float = ...  // need to check bolo.h
public let maxAngularVelocity: Float = 2.5
public let pushForce: Float = 1.5625
public let kickSpeedDecay: Float = 12.0
public let explodeTicks: Int32 = 45
public let respawnTicks: Int32 = 150
```

[TO: PARITY] Flag the `collisiondetect` p.x/p.y bug for your Wave 5.0 audit checklist — differential tests should hit this path.
[TO: IMPLEMENTER] This entry is reference for Wave 5.1 model design. No action until PLANNER issues the Wave 5.0 assignment.

---
## [PLANNER] Wave 5 Pre-Read — Part 2: Shell/Builder/Pill/Spawn (complete)
**Date:** 2026-08-31  **Status:** PRE-READ COMPLETE

### Constants — bolo.h (all needed in Physics.swift Wave 5.0 additions)
| C macro | Value | Swift name |
|---|---|---|
| TANKRADIUS | 0.375 | tankRadius *(already in pre-brief)* |
| BUILDERRADIUS | 0.125 | builderRadius |
| SHELLVEL | 7.0 | shellVelocity |
| MAXRANGE | 7.0 | maxShellRange |
| KICKFORCE | 3.125 | kickForce *(= boatMaxSpeed, coincidence)* |
| EXPLOSIONTICKS | 24 | explosionTicks *(particle display limit)* |
| EXPLODETICKS | 45 | explodeTicks *(death anim before respawn)* |
| RESPAWN_TICKS | 150 | respawnTicks |
| MAXSHELLS | 40 | maxShells |
| MAXMINES | 40 | maxMines |
| MAXARMOUR | 40 | maxArmour |
| MAXTREES | 40 | maxTrees |
| ROADTREES | 2 | roadTrees |
| WALLTREES | 2 | wallTrees |
| BOATTREES | 20 | boatTrees |
| PILLTREES | 4 | pillTrees |
| MAXPLAYERS | 16 | maxPlayers |
| MAX_STARTS | 16 | maxStarts |
| NEUTRAL | 0xff | playerNeutral |
| ONBOARD | 0xff | pillOnboard |
| NOPILL | 0xff | noPill |
| MINBASEARMOUR | 5 | minBaseArmour |

**IMPLEMENTER NOTE — Wave 5.0 Physics.swift additions:** Add ALL constants above as `public let` in Physics.swift. Group separately from existing speed/accel constants with a `// MARK: - Game Object Constants` comment.

### Shell struct fields (Wave 5.1 GameState — Shell type)
```c
struct Shell {
  Vec2f point;    // world position
  float dir;      // direction (radians)
  float range;    // remaining range (starts at MAXRANGE or less)
  int   owner;    // player index or NEUTRAL
  int   boat;     // 1 = fired from water (boat shell)
  int   pill;     // 1 = fired by pillbox
};
```
Swift `Shell` struct: `point: Vec2f, dir: Float, range: Float, owner: UInt8, boat: Bool, pill: Bool`

### shelllogic — Wave 5.3 scope
- Per tick: advance `point` by `shellVelocity/ticksPerSec` in `dir`, reduce `range` by same
- Last step: advance only `range` remainder if `range < shellVelocity/ticksPerSec`
- Collision test via `shellcollisiontest` (pills, bases, terrain, tanks)
- Tank hit: `kickdir = shell.dir`, `kickspeed = kickForce (3.125)`, armour -= 5
- Range ≤ 0: create Explosion at shell.point, remove shell
- **Explosion struct:** `point: Vec2f, counter: Int` — counter increments each tick; remove when `counter > EXPLOSIONTICKS (24)`
- **NOTE:** shelllogic iterates `client.players[client.player].shells` for tank-hit test against `client.players[player]` — local player's shells test against other players. In pure-simulation Swift this becomes: each player's shells test against each other player's tank.

### builderlogic — Wave 5.4 scope
- `BUILDERRADIUS = 0.125`, `TANKRADIUS - BUILDERRADIUS = 0.25` — close-range capture threshold
- Builder initial placement formula (repeated for all task types):
  ```
  if dist ≤ 0.25: builder = Vec2f(target.x+0.5, target.y+0.5)
  else:           builder = tank + diff * (0.25 / dist)
  ```
- Builder movement uses `collisionDetect(builder + diff, radius: BUILDERRADIUS, isSolid: builderCollision)`
- Builder speed: `BUILDERRADIUS`-based (read `builderlogic` lines 4894–5000 for full movement tick)
- State machine: `kBuilderReady → kBuilderGoto → kBuilderWork/Return` (full enum in bolo.h)
- Wave 5.4 is complex — IMPLEMENTER should read builderlogic lines 4531–5033 in full before implementing

### pilllogic — Wave 5.5 scope
- Firing condition: `(dist ≤ 2.0 OR forestvis(tank) > 0.25) AND dist ≤ 8.0`
- Closest-hostile check: pill only fires if local player is closer than any other hostile
- Counter increments each tick; fire when `counter >= pill.speed` (speed = reload rate from bolo.h)
- Shell spawned at `pill_center + diff * (0.70711219 / dist)` — ≈ √2/2 offset into cell
- Shell `range = 8.5 - 0.70711219 ≈ 7.793`, `pill = true`, `owner = pill.owner`
- Shell dir: velocity component math uses `compi + compj` (lead-target, partially)
- **NOTE:** `0.70711219` is the exact C constant — use this literal float in Swift for parity

### spawn() — confirmed matches PARITY audit
Two-pass weighted selection (verbatim from C):
1. **Pass 1:** For each start: weight=1; friendly base < 8.5 → weight=3; friendly base < 17 → weight=2; hostile pill < 8.5 → weight=0
2. **If range==0** (all spiked): re-run base weights only (no pill penalty)
3. `index = random() % range`; select start by cumulative weight scan
4. Post-spawn state: `dead=0, tank=start+0.5, dir=start.dir*(π/8.0), speed=0, turnspeed=0, kickspeed=0, kickdir=0, range=MAXRANGE(7.0), boat=1`
5. Resource init: game-type branched (domination open/tournament/strict). In open: shells=40, mines=40, armour=40, trees=40

**Swift:** `spawn()` belongs in `Spawn.swift` (Wave 5.6). Takes `inout GameState`, uses `arc4random_uniform` (not `random()`) for determinism on Apple platforms — **PARITY NOTE: document this divergence.**

### Wave 5 pre-read: COMPLETE
All sub-waves 5.0–5.7 are scoped. IMPLEMENTER can begin Wave 4.1 then proceed sequentially through Wave 5 sub-waves when ready.


---
## [PLANNER → IMPLEMENTER] Wave 5.0 Assignment (STAGED — post after Wave 4.1 sign-off)
**Status:** DRAFT — do not begin until PLANNER posts "[TO: IMPLEMENTER] Wave 5.0 — GO"

### Wave 5.0: Physics constants + roundDir + maxSpeed/maxTurnSpeed + collisionDetect

**Files to create/modify:**
- `Sources/BoloKit/Physics.swift` — add constants
- `Sources/BoloKit/Physics.swift` or new `Sources/BoloKit/PhysicsOps.swift` — add pure functions
- `Tests/BoloKitTests/PhysicsOpsTests.swift` — unit tests (NEW)
- `Tests/DifferentialTests/PhysicsOpsDifferentialTests.swift` — differential tests (NEW)
- `Sources/CXBolo/` — C oracle wrappers for roundDir, maxSpeed if needed

---

#### Part A — Physics.swift constants additions

Add under `// MARK: - Game Object Constants`:

```swift
public let builderRadius: Float = 0.125         // BUILDERRADIUS
public let shellVelocity: Float = 7.0           // SHELLVEL
public let maxShellRange: Float = 7.0           // MAXRANGE
public let kickForce: Float = 3.125             // KICKFORCE
public let explosionTicks: Int = 24             // EXPLOSIONTICKS (particle display)
public let explodeTicks: Int = 45               // EXPLODETICKS (death animation gate)
public let respawnTicks: Int = 150              // RESPAWN_TICKS
public let maxShells: Int = 40                  // MAXSHELLS
public let maxMines: Int = 40                   // MAXMINES
public let maxArmour: Int = 40                  // MAXARMOUR
public let maxTrees: Int = 40                   // MAXTREES
public let roadTrees: Int = 2                   // ROADTREES
public let wallTrees: Int = 2                   // WALLTREES
public let boatTrees: Int = 20                  // BOATTREES
public let pillTrees: Int = 4                   // PILLTREES
public let maxPlayers: Int = 16                 // MAXPLAYERS
public let maxStarts: Int = 16                  // MAX_STARTS
public let pillOnboard: UInt8 = 0xff            // ONBOARD
public let playerNeutral: UInt8 = 0xff          // NEUTRAL
public let noPill: UInt8 = 0xff                 // NOPILL
public let minBaseArmour: Int = 5               // MINBASEARMOUR
```

Also add (already in pre-brief, confirm present):
```swift
public let tankRadius: Float = 0.375            // TANKRADIUS
public let maxAngularVelocity: Float = 2.5      // from tankmovelogic
public let pushForce: Float = 1.5625            // shore push from tankmovelogic
public let kickSpeedDecay: Float = 12.0         // per-tick decay from tankmovelogic
```

**Test:** add `physicsObjectConstantsMatchBoloH` to PhysicsOpsTests — spot-check a representative sample against known bolo.h values.

---

#### Part B — `roundDir(_ dir: Float) -> Float`

C source (`client.c:6765`):
```c
return (kPif/8.0)*floor(dir/(kPif/8.0) + 0.5);
```

Swift:
```swift
public func roundDir(_ dir: Float) -> Float {
    let step = Float.pi / 8.0
    return step * floor(dir / step + 0.5)
}
```

**D18:** All `Float`, never `Double`. `Float.pi` not `Double.pi`.

**Differential test:** fuzz with 1000 random dirs in [0, 2π]; compare against C oracle `rounddir_oracle` exposed from CXBolo.

---

#### Part C — `maxSpeed(x:y:terrain:pills:bases:) -> Float`

C source (`client.c:3594`) — pill/base overrides happen BEFORE terrain switch:
```c
// armed pill at (x,y) → 0.0
// dead pill OR base at (x,y) → road speed (3.125)
// else → terrainMaxSpeed(terrain)
```

Swift signature:
```swift
public func maxSpeed(
    x: Int, y: Int,
    terrain: Terrain,
    pills: [Pill],      // Pill defined in Wave 5.1 — stub as empty array for now
    bases: [Base]       // Base defined in Wave 5.1 — stub as empty array for now
) -> Float
```

**Wave 5.0 compromise:** implement the full pill/base override logic but accept `pills` and `bases` as empty arrays for now. Wave 5.1 will fill them in with real GameState. Test with empty arrays (falls through to terrain) — that's sufficient for 5.0; Wave 5.2 adds the pill/base integration tests.

**maxTurnSpeed:** same pattern — `maxTurnSpeed(x:y:terrain:pills:bases:) -> Float`

---

#### Part D — `collisionDetect(_ p: Vec2f, radius: Float, isSolid: (Pointi) -> Bool) -> Vec2f`

C source (`client.c:6927`) — replicate the C bug exactly for parity:
```c
// In the lyc && hyc branch:
// BUG: p.x = fy + 0.5  (should be p.y = fy + 0.5)
// MUST replicate this bug — do NOT fix it
```

Swift:
```swift
public func collisionDetect(
    _ p: Vec2f,
    radius: Float,
    isSolid: (Pointi) -> Bool
) -> Vec2f {
    // ... port verbatim including the p.x/p.y swap bug ...
}
```

Add a comment above the bug line: `// BUG: replicates C source p.x/p.y swap for behavioral parity`

**Test:** unit test the known C-bug scenario: enter with position where `lyc && hyc` fires, confirm x is modified instead of y (matching the C bug).

---

#### Commit message
```
Wave 5.0: Physics constants, roundDir, maxSpeed/maxTurnSpeed, collisionDetect (with C bug)
```


---
## [PLANNER] Wave 5.7 Pre-Read — growtrees, pill cooldown, base replenish (server.c)
**Date:** 2026-08-31  **Status:** PRE-READ COMPLETE

### Architecture note
Wave 5.7 logic lives in **server.c**, not client.c. The client only receives and applies server packets:
- `growtrees()` → server sends `SRGrow` → client `recvsrgrow()` applies terrain change
- Pill cooldown and base replenish are server-only; client receives `SRCoolPill` / `SRReplenishBase`

For BoloKit's standalone simulation, both sides must be ported.

### Constants (all to be added to Physics.swift Wave 5.0):
| Swift name | Value | C macro | Notes |
|---|---|---|---|
| coolPillTicks | 32 | COOLPILLTICKS | Reload-speed cooldown interval |
| replenishBaseTicks | 600 | REPLENISHBASETICKS | Base replenish interval (counter scaled by nplayers) |
| treesPlantRate | 10 | TREESPLANTRATE | Used in growtrees iteration count |
| treesbestOf | 4200 | TREESBESTOF | Best-of window; must be multiple of TREESPLANTRATE*TICKSPERSEC |
| maxTicksPerShot | 100 | MAXTICKSPERSHOT | Pill reload speed cap (higher = slower) |
| maxBaseArmour | 90 | MAXBASEARMOUR | |
| maxBaseShells | 90 | MAXBASESHELLS | |
| maxBaseMines | 90 | MAXBASEMINES | |

### Pill cooldown — Wave 5.7 scope
- Per tick (server, all placed pills): `pill.counter++`
- When `counter >= COOLPILLTICKS (32)`:
  - `pill.speed++` (capped at `MAXTICKSPERSHOT = 100`)
  - `pill.counter = 0`
- **CRITICAL:** `pill.speed` is the RELOAD INTERVAL in ticks — higher = slower, NOT armour.
- Pill armour is only restored by LGM (builder) repair, never by the server tick.
- `pill.speed` starts low (fast fire) and degrades toward 100 over time.

### Base replenish — Wave 5.7 scope
- Per tick (server, all bases): `base.counter += nplayers` (player-count-scaled — confirmed PARITY)
- When `counter >= REPLENISHBASETICKS (600)`:
  - `base.armour = min(base.armour + 1, MAXBASEARMOUR=90)`
  - `base.mines  = min(base.mines  + 1, MAXBASEMINES=90)`
  - `base.shells = min(base.shells + 1, MAXBASESHELLS=90)`
  - `base.counter = 0`
- All three resources replenish simultaneously in one event.

### growtrees — Wave 5.7 scope
- Iterations per tick: `nplayers * (TREESBESTOF / (TREESPLANTRATE * TICKSPERSEC))`
  = `nplayers * (4200 / (10 * 50))` = `nplayers * 8` (integer division)
- Each iteration: sample random cell (x,y); if `treescore(growx,growy) < treescore(x,y)` → update `(growx,growy) = (x,y)`; increment `growbestof`
- When `growbestof >= TREESBESTOF (4200)`:
  - **C BUG (replicate):** outer guard checks `findpill(x,y)` and `findbase(x,y)` — the last-sampled random cell, NOT the winning candidate `(growx,growy)`. Inner guard correctly checks `(growx,growy)`. Must replicate both checks verbatim.
  - Grows tree at `(growx,growy)` if eligible; sends `SRGrow`
  - Resets: `growx,growy = random()%(WIDTH*WIDTH)` new start; `growbestof = 0`
- `server.growx`, `server.growy`, `server.growbestof` are persistent server state between ticks

### recvsrgrow — client apply (Wave 5.7)
- On receive `SRGrow(x,y)`: set `terrain[y][x]` = `.forest` (or `.minedForest` if currently mined non-forest) for grass, rubble, crater, swamp, road variants. All others: no-op.
- Swift: `func applyGrow(x: Int, y: Int, grid: inout TerrainGrid)`

### Wave 5 pre-read: ALL SUB-WAVES COMPLETE ✅
All C source has been read for 5.0–5.7. IMPLEMENTER can proceed through sub-waves sequentially after Wave 4.1.


---

### [IMPLEMENTER] 2026-08-31 — Wave 4.1 complete: BMAP RLE codec (readRun/writeRun)
**Type:** build
**Phase:** 1 / Wave 4.1
**Blocks:** nothing

Wave 4.1 executed per the [TO: IMPLEMENTER] assignment. Committed as `7298d2c` with the
mandated message. All 45 tests green (22 differential + 23 BoloKitTests).

**Delivered (`Sources/BoloKit/BMap.swift`):**
- `readRun(grid:y:x:) -> (run: BMapRun, data: [UInt8], isLast: Bool)` and `writeRun(_:data:into:) -> Bool`, plus private `readNibble`/`writeNibble`/`terrainToTileFlatAt`/`tileToTerrain` helpers, mechanically transcribed from `readrun`/`writerun`/`readnibble`/`writenibble` in `Reference/c/bmap.c`.
- `tileToTerrain` is a pure-Swift port of `tiletoterrain` (server.c:4301) — needed directly since BoloKit doesn't depend on CXBolo, distinct from the CXBolo verbatim extract added in Wave 4 for the C oracle's own linking needs.

**API deviation (flagged for sign-off):** `readRun` returns a non-optional `(run, data, isLast: Bool)` tuple rather than the `(BMapRun, [UInt8])?` originally proposed. An `Optional` and "returns the sentinel run" are two different contracts — the C reference's actual behavior is the latter (retval 0/1, always populating `run`). `isLast` mirrors that literally and stays diffable against the oracle call-for-call.

**Two C-quirk findings, both resolved with documented, deliberate choices:**

1. **Row-spillover in the do-while re-check.** C's `int terrain[256][256]` is one contiguous block, so `terrain[y][256]` aliases `terrain[y+1][0]` for `y<255` — a real, reproducible behavior, not UB. Implemented via flat-index arithmetic (`terrainToTileFlatAt`) so this reproduces automatically. Only `row==255, col==256` (flat index 65536) is genuinely one cell past the whole grid — true UB in C with no reproducible oracle value to match — clamped to "matches its own default terrain" so the loop terminates safely instead of crashing. Verified via manual trace that no other code path can push a column index past 256.

2. **Lossy tile round-trip.** `terrainToTile`/`tileToTerrain` collapse/expand variant terrains asymmetrically: swamp0–3/rubble0–3/grass0–3/damagedWall0–3 all encode to one tile, but always decode back to variant **3** specifically — never 0/1/2. This is a real property of the original format (confirmed against `tiletoterrain` in server.c), not a bug. Differential/round-trip test fixtures use only canonical-variant terrain (grass3, wall, road, forest, river) to get true bit-identical round trips; documented inline on `tileToTerrain`.

**One safety addition beyond the literal port:** `writeRun` guards `x < 256` before every grid write. Corrupt input that passes the `datalen` validation but encodes a run/repeat-count reaching past column 256 would cause C's `terrain[run.y][x++]` to silently overrun into adjacent row memory (or crash outright at the true grid edge) — Swift arrays can't do that safely, so this path fails closed (`false`) instead. Verified unreachable for any output produced by `readRun` itself; only reachable via deliberately malformed input, which is exactly what `writeRunGuardsAgainstOverrunPastColumn256` constructs and exercises.

**One planned test dropped as unreachable:** the "invalid tile nibble → corrupt data" case from the plan doesn't actually exist as a reachable path. `readNibble` only ever returns 0–15 (4-bit range), and `Tile` raw values 0–15 are *all* handled by `tileToTerrain` with defined terrain mappings — so `tileToTerrain(readNibble(...))` can never return -1 in `writeRun`'s actual usage. The `terrainValue != -1` guard is kept as defensive/faithful dead code (mirroring the equally-unreachable C `serverTileType==-1` check), but no test claims to exercise it. Replaced with two reachable corrupt-data cases: truncated `datalen` (fails the leading check) and overstated `datalen` (fails the trailing check).

**Verification approach:** built a fixture grid (via `mapDefault()` + three hand-placed patches: a 4-tile "like tiles" run, a 3-tile "different tiles" run, and a minimal 1-tile run) and diffed Swift's `readRun`/`writeRun` against `readrun_flat`/`writerun_flat` run-by-run — every header field and nibble byte matched on the first build, including hand-traced expected byte values (`0xA7`, `0x10`/`0x40`) for the two encoding branches. `size_t*` confirmed to import as `UnsafeMutablePointer<Int>` (no surprises).

[TO: PLANNER] Wave 4.1 done and verified. Please sign off on the `isLast: Bool` API deviation, the row-spillover clamp, and the dropped invalid-nibble test (replaced with two reachable corrupt-data cases). Ready for Wave 5.0 whenever PLANNER posts the GO.
[TO: PARITY] New commit to audit: `7298d2c`. The row-spillover clamp (row==255,col==256) and the writeRun x<256 safety guard are both C-behavior deviations worth independent verification — neither has a reproducible C oracle value to diff against, so they're argued from first principles in the commit message and above, not verified against a live C run.

---
## [PLANNER] Wave 4.1 Sign-Off
**Date:** 2026-09-01  **Commit:** 7298d2c

**All three flagged items approved:**

1. **`isLast: Bool` API** ✅ — Mirrors C's 0/1 return literally; Optional would lose the "sentinel run always populated" contract. Differential testing call-for-call is the right safeguard.

2. **Row-spillover clamp (row=255, col=256, flat index 65536)** ✅ — Flat-index arithmetic reproduces the C aliasing behavior for all 65,535 reachable grid-edge cases. The one true-UB case (index 65536) has no reproducible oracle value; failing closed is correct and the only safe choice.

3. **Dropped invalid-nibble test** ✅ — Unreachable because `readNibble` is 4-bit bounded and all tile values 0–15 map to defined terrain. The two replacement corrupt-data tests (truncated datalen, overstated datalen) are strictly better coverage.

Wave 4 and 4.1 are fully complete. ✅

---
## [TO: IMPLEMENTER] Wave 5.0 — GO
**Date:** 2026-09-01

**Wave 5.0: Physics constants + roundDir + maxSpeed/maxTurnSpeed + collisionDetect**

The full assignment spec is in the "Wave 5.0 Assignment (STAGED)" section above. Key summary:

**Part A — Physics.swift constants** (`// MARK: - Game Object Constants`)  
Add ALL constants from the pre-read (two sections above): builderRadius, shellVelocity, maxShellRange, kickForce, explosionTicks(24), explodeTicks(45), respawnTicks, maxShells/Mines/Armour/Trees, roadTrees, wallTrees, boatTrees, pillTrees, maxPlayers, maxStarts, pillOnboard, playerNeutral, noPill, minBaseArmour, coolPillTicks, replenishBaseTicks, treesPlantRate, treesbestOf, maxTicksPerShot, maxBaseArmour/Shells/Mines.  
Also confirm presence of: tankRadius=0.375, maxAngularVelocity=2.5, pushForce=1.5625, kickSpeedDecay=12.0 (from prior pre-brief).

**Part B — `roundDir(_ dir: Float) -> Float`**  
```swift
public func roundDir(_ dir: Float) -> Float {
    let step = Float.pi / 8.0
    return step * floor(dir / step + 0.5)
}
```
Expose C oracle `rounddir_oracle` from CXBolo. Differential: 1000 random dirs in [0, 2π].

**Part C — `maxSpeed` and `maxTurnSpeed`**  
Signatures accept `pills: [Pill]` and `bases: [Base]` (stub types for now — define minimal structs `Pill(x:Int,y:Int,armour:UInt8,owner:UInt8)` and `Base(x:Int,y:Int)` in a new `GameObjects.swift`). Override order: armed pill → 0.0; dead pill or base → roadMaxSpeed; else → terrainMaxSpeed/terrainMaxTurnSpeed. Wave 5.1 will replace stubs with full GameState.

**Part D — `collisionDetect(_ p: Vec2f, radius: Float, isSolid: (Pointi) -> Bool) -> Vec2f`**  
Port verbatim from `client.c:6927`. Replicate the C bug: in the `lyc && hyc` branch write `p.x = fy + 0.5` (not `p.y`). Comment above that line: `// BUG: replicates C source p.x/p.y swap for behavioral parity`. Unit test must verify the bug fires correctly.

**Commit message:**  
`Wave 5.0: Physics constants, roundDir, maxSpeed/maxTurnSpeed, collisionDetect (with C bug)`

[TO: PARITY] Please audit Wave 5.0 when IMPLEMENTER commits: verify `roundDir` Float precision (D18), confirm `collisionDetect` C bug is replicated not fixed, and check that `maxSpeed` pill/base override order matches `client.c:3594` exactly.


---
## [PLANNER] Wave 5.1 Pre-Brief — GameState model (finalized)
**Date:** 2026-09-01

### findpill / findbase semantics
- `findpill(x,y)`: skips pills where `armour == ONBOARD (0xff)` — carried pills are invisible to all position lookups
- `findbase(x,y)`: no armour filter — bases always found at their position
- `testalliance(p1,p2)`: requires `players[p1].used && players[p2].used && mutual alliance bits` — both `used` fields needed in PlayerState

### tankcollision vs buildercollision base threshold difference
- **tankcollision:** base solid if `armour >= MINBASEARMOUR (5)` — inclusive
- **buildercollision:** base solid if `armour > MINBASEARMOUR (5)` — exclusive (strictly greater)
These differ by one — must replicate exactly.

### BuilderStatus and BuilderTask enums
```swift
public enum BuilderStatus: Int {
    case ready = 0, goto, work, wait, `return`, parachute
}
public enum BuilderTask: Int {
    case doNothing = 0, getTree, buildRoad, buildWall, buildBoat, buildPill, repairPill, placeMine
}
```

---
## [TO: IMPLEMENTER] Wave 5.1 Assignment (post after Wave 5.0 complete)
**Status:** DRAFT — PLANNER will post GO after Wave 5.0 sign-off

### Wave 5.1: GameState model

**New file: `Sources/BoloKit/GameObjects.swift`**

Remove the stub `Pill` and `Base` from Wave 5.0 and replace with the full types below. Add all types in a single file.

```swift
// MARK: - Pill
public struct Pill: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    public var armour: UInt8     // 0xff = ONBOARD (carried by tank)
    public var owner: UInt8      // 0xff = NEUTRAL
    public var speed: UInt8      // reload interval in ticks; higher = slower
    public var counter: UInt8    // ticks since last reload event

    public var isOnboard: Bool { armour == 0xff }
    public var isArmed:   Bool { armour != 0xff && armour > 0 }
    public var isDead:    Bool { armour != 0xff && armour == 0 }
}

// MARK: - Base
public struct Base: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    public var armour: UInt8
    public var owner: UInt8      // 0xff = NEUTRAL
    public var shells: UInt8
    public var mines: UInt8
    public var counter: UInt16   // max value before reset: REPLENISHBASETICKS(600)+nplayers-1; UInt16 sufficient
}

// MARK: - Start
public struct Start: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    public var dir: UInt8        // 0–15; multiply by (π/8) for radians
}

// MARK: - Shell
public struct Shell: Hashable, Sendable {
    public var point: Vec2f
    public var dir: Float
    public var range: Float
    public var owner: UInt8
    public var boat: Bool
    public var pill: Bool
}

// MARK: - Explosion (particle effect)
public struct Explosion: Hashable, Sendable {
    public var point: Vec2f
    public var counter: Int      // remove when counter > explosionTicks(24)
}

// MARK: - BuilderStatus / BuilderTask
public enum BuilderStatus: Int, Hashable, Sendable {
    case ready = 0, goto, work, wait, `return`, parachute
}
public enum BuilderTask: Int, Hashable, Sendable {
    case doNothing = 0, getTree, buildRoad, buildWall, buildBoat, buildPill, repairPill, placeMine
}

// MARK: - PlayerState
public struct PlayerState: Hashable, Sendable {
    // Tank physics
    public var tank: Vec2f
    public var dir: Float
    public var speed: Float
    public var turnspeed: Float
    public var kickdir: Float
    public var kickspeed: Float
    // Builder
    public var builder: Vec2f
    public var buildertarget: Pointi
    public var builderstatus: BuilderStatus
    // Status
    public var dead: Bool
    public var boat: Int         // 1 = on boat; keep as Int to match C
    public var connected: Bool
    public var used: Bool
    public var alliance: UInt16  // bitmask; bit j set = allied with player j
    // Projectiles
    public var shells: [Shell]
    public var explosions: [Explosion]
}

// MARK: - LocalPlayerState (fields from struct client, not players[])
public struct LocalPlayerState: Hashable, Sendable {
    public var armour: Int
    public var shells: Int
    public var mines: Int
    public var trees: Int
    public var range: Float      // remaining shell range for next shot
    public var respawncounter: Int
    public var buildertask: BuilderTask
    public var buildermines: Int
    public var buildertrees: Int
    public var builderpill: UInt8  // index or noPill(0xff)
    public var spawned: Bool
}

// MARK: - GrowState (server-side tree growth persistent state)
public struct GrowState: Hashable, Sendable {
    public var growx: Int
    public var growy: Int
    public var growbestof: Int
}
```

**New file: `Sources/BoloKit/GameState.swift`**

```swift
public struct GameState: Sendable {
    public var terrain: TerrainGrid
    public var pills: [Pill]           // max 16
    public var bases: [Base]           // max 16
    public var starts: [Start]         // max 16
    public var players: [PlayerState]  // maxPlayers (16) elements; index = player
    public var ticks: UInt64           // total ticks simulated
    // Local player
    public var localPlayer: Int        // index into players
    public var local: LocalPlayerState
    // Server grow state
    public var grow: GrowState
    // Global explosions (from server-level events like mine chains)
    public var explosions: [Explosion]
}
```

**Helper functions (also in GameObjects.swift):**

```swift
// Equivalent of findpill — excludes ONBOARD pills
public func findPill(x: Int, y: Int, pills: [Pill]) -> Int? {
    pills.indices.first { pills[$0].armour != 0xff && pills[$0].x == UInt8(x) && pills[$0].y == UInt8(y) }
}

// Equivalent of findbase
public func findBase(x: Int, y: Int, bases: [Base]) -> Int? {
    bases.indices.first { bases[$0].x == UInt8(x) && bases[$0].y == UInt8(y) }
}

// Equivalent of testalliance
public func testAlliance(_ p1: Int, _ p2: Int, players: [PlayerState]) -> Bool {
    guard p1 < players.count, p2 < players.count else { return false }
    let a = players[p1], b = players[p2]
    return a.used && b.used
        && (a.alliance & (1 << p2)) != 0
        && (b.alliance & (1 << p1)) != 0
}
```

**Update Wave 5.0 `maxSpeed` and `maxTurnSpeed` — replace stub `Pill`/`Base` with real types.**

**Update Wave 5.0 `tankcollision` closure and `buildercollision` closure — replace stubs:**

```swift
// tankcollision closure (Wave 5.2 will use this)
func makeTankCollision(state: GameState, owner: Int) -> (Pointi) -> Bool {
    return { square in
        guard square.x >= 0, square.x < 256, square.y >= 0, square.y < 256 else { return true }
        if let pi = findPill(x: Int(square.x), y: Int(square.y), pills: state.pills) {
            return state.pills[pi].armour > 0
        }
        if let bi = findBase(x: Int(square.x), y: Int(square.y), bases: state.bases) {
            let base = state.bases[bi]
            return base.owner != 0xff
                && !testAlliance(Int(base.owner), owner, players: state.players)
                && base.armour >= 5  // >= MINBASEARMOUR
        }
        switch state.terrain[Int(square.x), Int(square.y)] {
        case .wall, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3: return true
        default: return false
        }
    }
}

// buildercollision has more context (target, buildertask) — closure factory deferred to Wave 5.4
```

**Tests (`Tests/BoloKitTests/GameObjectsTests.swift`):**
- `pillIsOnboard`, `pillIsArmed`, `pillIsDead` — armour edge cases
- `findPillSkipsOnboard` — carried pill not found by position
- `findBaseAlwaysFound` — base always found regardless of armour
- `testAllianceRequiresMutual` — one-sided alliance bit is not an alliance
- `testAllianceRequiresUsed` — unused player is never allied

**No differential tests for Wave 5.1** — these are pure Swift data model types; the C structs are not individually callable. Differential coverage comes in Wave 5.2 when `tankmovelogic` is ported.

**Commit message:**
```
Wave 5.1: GameState model — Pill, Base, Start, Shell, Explosion, PlayerState, GameState
```


---
## [PLANNER] Wave 5.2 Pre-Brief — tankmovelogic (complete)
**Date:** 2026-09-01

### InputFlags
```swift
public struct InputFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public static let accel  = InputFlags(rawValue: 0x00000001)  // ACCELMASK
    public static let brake  = InputFlags(rawValue: 0x00000002)  // BRAKEMASK
    public static let turnL  = InputFlags(rawValue: 0x00000004)  // TURNLMASK
    public static let turnR  = InputFlags(rawValue: 0x00000008)  // TURNRMASK
}
```
Add `inputflags: InputFlags` to `PlayerState`. Add to `GameObjects.swift`.

### isshore
`func isShore(x: Int, y: Int, terrain: TerrainGrid, bases: [Base]) -> Bool`
- OOB → false (not shore — boat cannot be pushed by non-existent land)
- Any base at (x,y) → true (always shore, regardless of terrain type)
- Sea, River, MinedSea → false
- Everything else → true

### tankmovelogic — tick logic (Wave 5.2)

**Dead tank branch (player == localPlayer and dead):**
1. `respawncounter++`
2. If `respawncounter < EXPLODETICKS (45)`:
   - `tank += dir2vec(kickdir) * kickspeed / ticksPerSec`
   - `collisionDetect(tank, TANKRADIUS, tankCollision(...))` — still collides when dead
   - Every 5 ticks: if terrain at tank NOT sea/minedSea → create Explosion(point: tank, counter: 0), add to player.explosions
3. Else if `respawncounter == EXPLODETICKS`: superboom (mines≥32) or smallboom (mines>0 || shells>0)
4. Else if `respawncounter >= RESPAWN_TICKS (150)`: call spawn()

**Alive tank branch:**
```
// 1. TURNING
if turnL XOR turnR:
    max = boat ? maxAngularVelocity (2.5) : maxTurnSpeed(localTank.x, localTank.y, ...)
    // IMPORTANT: uses localPlayer tank position for both local and remote players
    if turning left (turnL):
        if turnspeed < 0: turnspeed = 0   // sign flip guard
        turnspeed approaches +max by angularAccel/ticksPerSec per tick
    if turning right (turnR):
        if turnspeed > 0: turnspeed = 0   // sign flip guard
        turnspeed approaches -max by angularAccel/ticksPerSec per tick
else:
    turnspeed = 0.0  // instant reset, not gradual

// 2. DIR UPDATE + WRAP
dir += turnspeed / ticksPerSec
// Wrap to [0, 2π) using floorf — replicate exactly:
if dir > 2π: dir -= 2π * floor(dir / 2π)
else if dir < 0: dir += 2π * floor(dir / -2π + 1.0)

// 3. ACCELERATION
max = boat ? boatMaxSpeed (3.125) : maxSpeed(localTank.x, localTank.y, ...)
if accel XOR brake:
    if accel: speed approaches max (up or down) by ACCEL/ticksPerSec
    if brake: speed -= ACCEL/ticksPerSec, clamp to 0
else if speed > max:  // no input but overspeed (e.g. entered slower terrain)
    speed -= ACCEL/ticksPerSec, clamp to max

// 4. POSITION UPDATE (fidelity-critical — all Float)
tank += (dir2vec(roundDir(dir)) * speed + dir2vec(kickdir) * kickspeed) / ticksPerSec

// 5. KICKSPEED DECAY
kickspeed -= kickSpeedDecay (12.0) / ticksPerSec
kickspeed = max(0, kickspeed)

// 6. SHORE PUSH (boat only)
// isshore check on 4 cardinal + 4 diagonal neighbors using TANKRADIUS threshold
// 8-case push vector selection (see C source lines 4138–4188)
// if mag(push) > 0.00001:
//   speed component along push < PUSHFORCE → tank += unit(push) * PUSHFORCE/ticksPerSec
//   if NOT (accel and not brake) → speed -= ACCEL/ticksPerSec, clamp 0

// 7. COLLISION
collisionDetect(tank, tankRadius, tankCollision(state, owner: player))
```

**D18 reminder:** All Float, all trig via Float.pi, `floor` via `Foundation.floorf` or Swift's `floor` — confirm Float overload is called not Double.

**`maxturnspeed`/`maxspeed` use `localPlayer` tank position for both local and remote tanks** — this is faithful to C and must NOT be "fixed".

### Wave 5.2 scope
New function: `func tankMoveTick(player: Int, state: inout GameState)` in `Sources/BoloKit/TankTick.swift`
Helpers: `isShore(x:y:terrain:bases:)`, `InputFlags` (in GameObjects.swift)
Tests: `Tests/BoloKitTests/TankTickTests.swift` — turn wrap, kickspeed decay, shore push vector cases
Differential tests: `Tests/DifferentialTests/TankTickDifferentialTests.swift` — fuzz against `tankmovelogic` oracle in CXBolo



---
## [PARITY] Wave 4 / 4.1 Audit Report — CLEAN PASS
**Date:** 2026-09-01
**Commits audited:** 8044fb0 (Wave 4), 7298d2c (Wave 4.1)
**Files reviewed:** `BMap.swift` (full), cross-referenced against `bmap.c`, `bmap.h`, `server.c`

### Scope
Wave 4: `terrainToTile`, `defaultTerrain/defaultTile`, BMAP structs (`BMapPreamble`, `BMapPillInfo`, `BMapBaseInfo`, `BMapStartInfo`, `BMapRun`), `TerrainGrid.mapDefault()`.
Wave 4.1: `readNibble`/`writeNibble`, `terrainToTileFlatAt`, `readRun`/`writeRun`, `tileToTerrain`.

### Verdict: PASS — no parity issues found

#### `terrainToTile(_ terrain: Terrain) -> Tile`
Exhaustive 30-case switch, no `default` arm. All mappings confirmed correct against C oracle. No issues.

#### `terrainToTile(_ terrain: Int32) -> Int32` (raw overload)
Returns -1 for out-of-range input. Matches C `assert(0); return -1` behavior under valid input; Swift replaces the assert with a safe -1 return. Acceptable deviation — assert traps are not observable behavior.

#### `defaultTerrain(x:y:)` / `defaultTile(x:y:)`
Boundary constants `xMinMine=10, yMinMine=10, xMaxMine=245, yMaxMine=245` match `X_MIN_MINE/X_MAX_MINE/Y_MIN_MINE/Y_MAX_MINE` in `bmap.h`. Border ring logic `[10,245]` inclusive is correct. Confirmed.

#### `TerrainGrid.mapDefault()`
Fills grid via `defaultTerrain(x:y:)` — correctly produces `.minedSea` border ring, `.sea` interior. Pre-empts the Wave 4 pre-audit finding (A) that was flagged before implementation.

#### `tileToTerrain(_ tile: Int32) -> Int32`
Lossy inverse: swamp/rubble/grass/damagedWall variants all collapse to variant 3. `.unknown → .minedSea`. Cross-checked against C oracle `tiletoterrain()` — Swift matches exactly, including the `kUnknownTile → kMinedSeaTerrain` mapping which was initially uncertain. Confirmed correct.

#### `readNibble` / `writeNibble`
High-nibble-first, XOR-based. Zero-initialized buffer precondition documented and required by callers. Codec is symmetric and correct.

#### `terrainToTileFlatAt`
Reproduces C row-spillover UB (`terrain[y][256]` aliases `terrain[y+1][0]`) via flat index arithmetic. Edge case `y=255, col=256` clamped to default tile — safe termination of the `do-while` loop. This is the correct and only safe way to reproduce this behavior in Swift. Confirmed.

#### `writeRun` — `x < 256` guard
C `writerun()` would write past the 256-column boundary into the next row's memory. Swift adds `guard x < 256` to prevent memory corruption. This is a **safe deviation**: the C behavior is undefined and exploitable; the Swift guard produces identical output for all well-formed BMAP data. A DifferentialTest covering a run that terminates exactly at column 256 is recommended when the full encode/decode round-trip test suite is written.

#### `readRun` sentinel
Returns correct 4-field sentinel `(run: nil, data: nil, isLast: true)` to signal end-of-map. Confirmed.

### Carry-forward finding
**Finding 3 (LOW — still open):** `import Darwin` is unused in `Physics.swift` and `Terrain.swift`. No behavioral impact. IMPLEMENTER may clean up at convenience.

### Wave 5 audit scope (upcoming)
When IMPLEMENTER reports Wave 5.2 complete (`TankTick.swift`), PARITY will audit:
- `isShore` OOB and base-override cases
- `roundDir` rounding at exact half-steps (e.g. `dir = π/16`)
- `tankmovelogic` sign-flip guard, wrap arithmetic, kickspeed decay
- `maxSpeed`/`maxTurnSpeed` local-player position coupling (must NOT be "fixed")
- Shore push vector selection — all 8 cardinal/diagonal cases
- DifferentialTest coverage of the `growtrees` C BUG (outer pill guard checks last random candidate, not winner) — flag if no test exists for this when Wave 5.7 lands

[TO: PLANNER] Wave 4 / 4.1 audit closed. CLEAN PASS. No blocking findings. Wave 5 audit pending IMPLEMENTER completion of Wave 5.2 (`TankTick.swift`). Finding 3 (`import Darwin`) remains open, low severity.

---
## [PLANNER] Wave 5.2 Pre-Brief Addendum — tanklocallogic, enter(), tick loop order
**Date:** 2026-09-01

### Tick loop order (runclient — confirmed)
```
1. tankmovelogic(i)   — all players, physics only
2. tanklocallogic(old) — local player only (enter, push, refuel, fire, mine)
3. builderlogic(i)    — all players
4. pilllogic(old)     — uses old Vec2f (local player's pre-tick position)
5. shelllogic(i)      — all players
6. explosionlogic(i)  — all players + i=-1 (global explosions)
7. sendclupdate()     — every 5 ticks (network, deferred)
```

### InputFlags — add to GameObjects.swift (complete set)
```swift
public struct InputFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public static let accel  = InputFlags(rawValue: 0x00000001)  // ACCELMASK
    public static let brake  = InputFlags(rawValue: 0x00000002)  // BRAKEMASK
    public static let turnL  = InputFlags(rawValue: 0x00000004)  // TURNLMASK
    public static let turnR  = InputFlags(rawValue: 0x00000008)  // TURNRMASK
    public static let lmine  = InputFlags(rawValue: 0x00000010)  // LMINEMASK
    public static let shoot  = InputFlags(rawValue: 0x00000020)  // SHOOTMASK
    public static let incre  = InputFlags(rawValue: 0x00000040)  // INCREMASK
    public static let decre  = InputFlags(rawValue: 0x00000080)  // DECREMASK
}
```
Add `inputflags: InputFlags` to `PlayerState`.

### New constants for Physics.swift Wave 5.0 additions
| Swift name | Value | C macro |
|---|---|---|
| drainTicks | 15 | DRAINTICKS |
| refuelArmourTicks | 46 | REFUELARMOURTICKS |
| refuelShellsTicks | 7 | REFUELSHELLSTICKS |
| refuelMinesTicks | 7 | REFUELMINESTICKS |
| minBaseShells | 1 | MINBASESHELLS |
| minBaseMines | 1 | MINBASEMINES |
| shellRate | 4 | SHELLRATE |
| dRange | Float(50)/6.0 | DRANGE (= TICKSPERSEC/6.0 = 50/6 ≈ 8.333) |
| minRange | 1.0 | MINRANGE |

**Note:** `DRANGE = TICKSPERSEC / 6.0`. In Swift: `let dRange: Float = Float(ticksPerSec) / 6.0`. Since TICKSPERSEC is 50, dRange ≈ 8.333.

### tanklocallogic scope
`func tankLocalTick(old: Pointi, state: inout GameState)` — local player only.

**Part 1: Tank-tank push**
- For each other connected, alive player: if `dist < tankRadius*2.0` → push local tank to `TANKRADIUS*2.0` distance
- If dist < 0.00001 (coincident): random direction via `tan2f((random()%16)*(π/8))*TANKRADIUS*2.0`

**Part 2: enter(new, old)**
`func enter(new: Pointi, old: Pointi, state: inout GameState)`

Trigger: called with current and previous tile square. Key behaviors:

| Condition | Effect |
|---|---|
| Armed pill (armour>0) at new | superboom |
| Dead pill (armour==0) at new | grab (server handles pickup); drop boat if on land |
| Base at new, moved (new≠old) | grab if neutral or non-allied; always drop boat |
| Wall/damagedWall at new | superboom |
| Sea at new, no boat | drown() |
| Forest at new, dead tank, moved | damage + explosion (burning forest) |
| Land at new, have boat, moved | drop boat at old |
| Land at new, LMINEMASK, alive | plant mine at new |
| BoatTerrain at new, have boat, moved | damage+explosion (boat collision) |
| BoatTerrain at new, no boat, moved | grab (pick up boat) |
| MinedSea at new, moved | grab + drown() |
| Mined land at new, moved | grab (mine detonation server-side) |

**NOTE:** `sendcl*` network calls → in pure simulation, replace with direct state mutations:
- `sendclgrabtile` → server applies the terrain/pill/base change; in standalone sim, fire `onGrabTile` callback
- `sendcldropboat` → `terrain[old.y][old.x] = .boat`
- `sendcldropmine` → `terrain[new.y][new.x] = mined variant`

**Part 3: Refueling** (alive, on base, stationary)
- Start: enter base square → `refueling=true, refuelingbase=base, refuelingcounter=0`
- Tick: if `new == old` (stationary): `refuelingcounter++`
  - Armour: if `armour < MAXARMOUR` AND `base.armour > MINBASEARMOUR` AND counter >= 46 → transfer `MIN(MAXARMOUR-armour, MIN(base.armour-5, 5))` points
  - Shells: if `shells < MAXSHELLS` AND `base.shells >= 1` AND counter >= 7 → transfer batch
  - Mines: if `mines < MAXMINES` AND `base.mines >= 1` AND counter >= 7 → transfer batch
- Cancel: if tank moves (`new ≠ old`) → `refueling=false`

**Part 4: Shell range (alive)**
- `incre XOR decre`: range ± `dRange/ticksPerSec` per tick, clamped to [MINRANGE, MAXRANGE]

**Part 5: Shell firing (alive)**
- `shoot` flag AND `shellcounter > TICKSPERSEC/SHELLRATE (50/4=12)` AND `shells > 0`
- Create shell: `point = tank + dir2vec(dir)*0.5`, `range = client.range - 0.5`, `dir = player.dir`, `boat = player.boat`, `pill = false`
- `shells--`, `shellcounter = 0`
- Always: `shellcounter++` each tick

### Wave 5.2 revised scope
Split into two commits for clean isolation:

**Wave 5.2a — `tankMoveTick`** (physics only, differential-testable against C oracle):
- `Sources/BoloKit/TankTick.swift`: `tankMoveTick(player:state:)`
- Helpers: `isShore`, `InputFlags` in GameObjects.swift
- `Tests/DifferentialTests/TankTickDifferentialTests.swift`: fuzz physics

**Wave 5.2b — `tankLocalTick` + `enter`** (state mutations, no C differential — network calls replaced by callbacks):
- `enter(new:old:state:)` in TankTick.swift
- `tankLocalTick(old:state:)` in TankTick.swift
- Callbacks: `onGrabTile`, `onDropBoat`, `onDropMine` as `GameState` delegate or closure properties
- Tests: `Tests/BoloKitTests/TankLocalTickTests.swift` — unit test each enter() branch

### Additional LocalPlayerState fields (add to Wave 5.1 GameState)
```swift
// Add to LocalPlayerState:
public var draincounter: Int
public var refueling: Bool
public var refuelingbase: Int   // index or -1
public var refuelingcounter: Int
public var shellcounter: Int
public var range: Float          // already listed
```


---
## [TO: PARITY] Wave 5 Full Audit — run after all sub-waves 5.0–5.7 committed
**Date:** 2026-09-01  **From:** PLANNER

Run this as a single comprehensive audit after IMPLEMENTER commits Wave 5.7. Each item below is an independently verifiable behavioral claim. Mark each PASS / FAIL / N/A with a one-line note.

---
### 5.0 — Physics constants, roundDir, maxSpeed, collisionDetect

**Constants (D18 — all Float, no Double):**
- [ ] All bolo.h values reproduced exactly; spot-check: tankRadius=0.375, builderRadius=0.125, shellVelocity=7.0, kickForce=3.125, explosionTicks=24, explodeTicks=45, respawnTicks=150, coolPillTicks=32, replenishBaseTicks=600, maxTicksPerShot=100, dRange=Float(50)/6.0
- [ ] `explosionTicks (24)` and `explodeTicks (45)` are distinct named constants — not aliased to each other
- [ ] No physics constant declared as `Double` or inferred as Double

**roundDir:**
- [ ] Uses `Float.pi` (not `Double.pi`, not `M_PI`)
- [ ] Uses Swift `floor` dispatched to the Float overload — confirmed by checking call site type
- [ ] Differential test covers full [0, 2π] range with ≥1000 random values

**maxSpeed:**
- [ ] Pill check: `armour > 0` (not `armour != 0`, not `armour >= MINBASEARMOUR`) — armed pill → 0.0
- [ ] Dead pill: `armour == 0` → road speed (3.125), not 0.0
- [ ] Base present → road speed (3.125) regardless of armour or owner
- [ ] Pill check runs BEFORE base check (order matters)
- [ ] Terrain fallthrough matches C switch exactly — kBoatTerrain returns road speed

**maxTurnSpeed:**
- [ ] Same pill/base override order as maxSpeed

**collisionDetect:**
- [ ] The C bug is present: in the `lyc && hyc` branch, `p.x` is written (not `p.y`)
- [ ] A unit test exercises this branch and asserts that `x` is modified, not `y`
- [ ] Comment above the bug line: "BUG: replicates C source p.x/p.y swap for behavioral parity"

---
### 5.1 — GameState model

**Pill:**
- [ ] `armour == 0xff` means ONBOARD — pill is carried by a tank, not on the map
- [ ] `isOnboard`, `isArmed`, `isDead` computed properties present and correct
- [ ] `findPill(x:y:pills:)` skips pills where `armour == 0xff` (ONBOARD) — carried pills are invisible to position lookups

**Base:**
- [ ] `counter` is wide enough for `REPLENISHBASETICKS (600) + maxPlayers (16) - 1 = 615` — UInt16 or larger

**testAlliance:**
- [ ] Requires `players[p1].used && players[p2].used` — unused player is never allied with anyone
- [ ] Requires mutual bits: `p1.alliance has bit p2` AND `p2.alliance has bit p1`
- [ ] One-sided alliance (only one bit set) → returns false

**tankcollision vs buildercollision base threshold:**
- [ ] `tankcollision` equivalent: base solid if `armour >= 5` (≥ MINBASEARMOUR — inclusive)
- [ ] `buildercollision` equivalent: base solid if `armour > 5` (> MINBASEARMOUR — exclusive)
- [ ] These two thresholds differ by exactly one — this is intentional and must not be "unified"

---
### 5.2a — tankMoveTick (physics)

**Turning:**
- [ ] When no turn input: `turnspeed = 0.0` instantly (NOT gradual decay)
- [ ] Sign flip guard: if turning left and `turnspeed < 0`, reset to 0 first; vice versa for right
- [ ] `maxAngularVelocity (2.5)` used on boat; `maxTurnSpeed(...)` used on land
- [ ] `maxturnspeed` reads localPlayer's tank position (not the moving player's) — faithful to C

**Direction wrap:**
- [ ] `dir > 2π`: uses `floorf(dir / 2π)` — not `fmod`, not integer division
- [ ] `dir < 0`: uses `floorf(dir / -2π + 1.0)` — exact C formula

**Acceleration:**
- [ ] `maxSpeed` reads localPlayer's tank position (not the moving player's) — same C behavior
- [ ] Brake: speed decreases but clamps at 0 (never negative)
- [ ] Overspeed (terrain change): decelerates to max, not instant clamp

**Position update:**
- [ ] Uses `roundDir(dir)` for movement direction (not raw `dir`)
- [ ] kickspeed component added in same expression: `(dir2vec(roundDir(dir))*speed + dir2vec(kickdir)*kickspeed) / ticksPerSec`

**kickspeed decay:**
- [ ] Decays by `12.0 / ticksPerSec` per tick (literal 12.0, matches `kickSpeedDecay` constant)
- [ ] Clamped to 0 (never negative)

**Shore push:**
- [ ] Only applied when `boat == 1`
- [ ] Magnitude threshold: `> 0.00001` (not `> 0`, not `>= 0.00001`)
- [ ] Push amount: `PUSHFORCE/ticksPerSec` in the push direction
- [ ] Speed deceleration during push: skipped if player is actively accelerating (accel flag, no brake flag)

**D18:**
- [ ] No `Double` in any physics computation in TankTick.swift — confirm by searching for `Double` in file

---
### 5.2b — tankLocalTick / enter()

**Tank-tank push:**
- [ ] Distance threshold: `TANKRADIUS * 2.0` (= 0.75) — collision of two tank radii
- [ ] Coincident tanks (dist < 0.00001): random direction push, not zero vector

**enter() — key behavioral branches:**
- [ ] Armed pill at new square → superboom (not just damage)
- [ ] Sea terrain, no boat → drown() called
- [ ] Sea terrain, have boat → no drown (boat protects)
- [ ] MinedSea → grab tile AND drown() (both, unconditionally)
- [ ] Land terrain, have boat, moved → boat dropped at OLD square (not new)
- [ ] BoatTerrain, have boat, moved → damage + explosion (not pickup)
- [ ] BoatTerrain, no boat, moved → pick up boat (boat=1)
- [ ] Mine plant: only if `new ≠ old` AND alive AND `lmine` flag AND `mines > 0`
- [ ] Dead tank entering forest (moved) → damage + explosion on that forest cell

**Refueling:**
- [ ] Refueling only ticks when stationary (`new == old`)
- [ ] Priority: armour first, then shells, then mines (not concurrent)
- [ ] Refueling cancelled on any movement (`new ≠ old`)
- [ ] Armour transfer limited by `MIN(MAXARMOUR-armour, MIN(base.armour-5, 5))`

**Shell firing:**
- [ ] Shell point: `tank + dir2vec(dir) * 0.5` (not tank center)
- [ ] Shell range: `local.range - 0.5` (not `MAXRANGE`)
- [ ] `shellcounter` resets to 0 on fire, increments every tick regardless
- [ ] Fire rate: `shellcounter > TICKSPERSEC/SHELLRATE` = `> 12` (strictly greater, not >=)

---
### 5.3 — shellTick

- [ ] Per-tick advance: `shellVelocity/ticksPerSec` (= 0.14 exactly)
- [ ] Last partial step: advance only remaining range when `range < shellVelocity/ticksPerSec`
- [ ] Tank hit: `kickspeed = kickForce (3.125)`, `armour -= 5`
- [ ] Explosion particle: `counter` starts at 0; removed when `counter > explosionTicks (24)` — strictly greater
- [ ] `explosionTicks (24)` used here — NOT `explodeTicks (45)` which is death animation

---
### 5.4 — builderTick

- [ ] `builderRadius = 0.125` (not tankRadius=0.375)
- [ ] Close-range capture threshold: `tankRadius - builderRadius = 0.25`
- [ ] `buildercollision` closure captures `target` and `buildertask` — base threshold `> 5` (exclusive)
- [ ] Builder movement uses `collisionDetect` with `builderRadius`, not `tankRadius`

---
### 5.5 — pillTick, explosionTick

**pillTick:**
- [ ] Firing condition: `(dist ≤ 2.0 OR forestvis(tank) > 0.25) AND dist ≤ 8.0`
- [ ] Closest-hostile check runs BEFORE firing — pill passes if no closer hostile
- [ ] Shell offset from pill center: literal `0.70711219` (not computed `Float(sqrt(2))/2`) — parity critical
- [ ] Shell range: `8.5 - 0.70711219` (not `MAXRANGE = 7.0`)

**explosionTick:**
- [ ] `counter > EXPLOSIONTICKS (24)` → remove (strictly greater, not >=)

---
### 5.6 — spawn()

- [ ] Pass 1 weights: friendly base < 8.5 → 3, < 17 → 2, else 1; hostile pill < 8.5 → 0
- [ ] Pass 2 (all-zero fallback): pill penalties dropped; only base weights recomputed
- [ ] `arc4random_uniform(range)` used (not `random()%range`) — document as KNOWN DIVERGENCE from C
- [ ] Post-spawn: `boat = 1` always
- [ ] Post-spawn: `dir = starts[i].dir * (Float.pi / 8.0)` (not degrees, not raw dir)
- [ ] Post-spawn: `speed = 0, turnspeed = 0, kickspeed = 0, kickdir = 0`

---
### 5.7 — growtrees, pill cooldown, base replenish

**growtrees C bug (critical):**
- [ ] Outer pill/base guard checks the last-sampled random cell `(x, y)` — NOT `(growx, growy)`
- [ ] Inner guard (inside the switch) correctly checks `(growx, growy)` — both checks present
- [ ] Iterations per tick: `nplayers * 8` (integer arithmetic: `4200 / (10*50) = 8`)

**applyGrow:**
- [ ] Mined grass/rubble/crater/swamp/road → `.minedForest` (not plain `.forest`)
- [ ] Plain grass/rubble/crater/swamp/road → `.forest`
- [ ] All other terrain: no-op (wall, sea, forest, etc.)

**Pill cooldown:**
- [ ] `pill.speed++` (reload interval grows toward 100) — NOT `pill.armour++`
- [ ] Only placed pills (`armour != ONBOARD`) are cooled
- [ ] Counter resets to 0 on each cooldown event

**Base replenish:**
- [ ] `base.counter += nplayers` (NOT += 1) — player-count-scaled
- [ ] All three resources (armour, shells, mines) increment in the SAME replenish event
- [ ] Each capped at its max (90) independently
- [ ] Counter resets to 0 after replenish

---
### Cross-cutting D18 check (entire Wave 5)
- [ ] Search `Sources/BoloKit/` for any use of `Double`, `CGFloat`, `M_PI`, `Double.pi` — zero hits expected in physics files

### Known intentional divergences from C (document, not flag)
- [ ] `arc4random_uniform` instead of `random()%range` in spawn() — Apple platform determinism
- [ ] `collisionDetect` C bug replicated intentionally — documented with comment
- [ ] growtrees C bug replicated intentionally — documented with comment


---

### [IMPLEMENTER] 2026-09-01 — Wave 5.0 complete: Physics constants, roundDir, maxSpeed/maxTurnSpeed, collisionDetect
**Type:** build
**Phase:** 1 / Wave 5.0
**Blocks:** nothing

Wave 5.0 executed per the [TO: IMPLEMENTER] Wave 5.0 GO. Committed as `e2636fb` (an earlier
attempt, `acd0a04`, had a shell-quoting-mangled commit message from unescaped backticks —
amended immediately, before any push; no content was lost). All 63 tests green (26
differential + 37 unit), reconfirmed stable across many repeated runs.

**Delivered:**
- `Sources/BoloKit/Physics.swift` (extended): all Part A constants plus `tankRadius`/
  `maxAngularVelocity`/`pushForce`/`kickSpeedDecay` (all four were genuinely absent, not just
  needing "confirmation" as the assignment implied), plus the Wave 5.7 pre-read constants
  already tabled here (`coolPillTicks`, `replenishBaseTicks`, `treesPlantRate`, `treesBestOf`,
  `maxTicksPerShot`, `maxBaseArmour/Shells/Mines`) — all cross-checked directly against
  `Reference/c/bolo.h` in this session.
- `Sources/BoloKit/GameObjects.swift` (new): minimal `Pill`/`Base` stubs exactly as specified.
  Confirmed against the later-staged Wave 5.1 pre-brief in this file — it explicitly says to
  replace these, so the stub design was correct and intentional.
- `Sources/BoloKit/PhysicsOps.swift` (new): `roundDir`, `maxSpeed`, `maxTurnSpeed`,
  `collisionDetect`.
- `Sources/CXBolo/physicsops.c` (new) + `CXBolo.h` declarations: `rounddir_oracle`,
  `collisiondetect_oracle` — permanent verbatim extracts (client.c will never be bridged
  wholesale, unlike the Wave 4.1 `tiletoterrain` shim).

**Verified against the C reference directly (not just the staged summary) before writing any code:**
- `maxspeed`/`maxturnspeed` (`client.c:3594`/`3659`): confirmed their terrain-switch branches
  are an *exact* match for the already-shipped Wave 3.1 `terrainMaxSpeed`/`terrainMaxTurnSpeed`
  — same groupings, same values. `maxSpeed`/`maxTurnSpeed` are thin pill/base-override wrappers,
  not new terrain logic.
- `rounddir` (`client.c:6765`): used `kPif` (already defined in `Vector.swift`, used in the
  identical `kPif/8.0` idiom elsewhere) instead of `Float.pi` as the assignment suggested — more
  consistent with the existing codebase; bit-identical to `Float.pi` in practice either way.
- `collisiondetect` (`client.c:6927`, full body read): confirmed the `p.x`/`p.y` bug exactly as
  described. **New finding:** this branch (`lyc && hyc`) only fires when `radius > 0.5` — no
  radius constant in the codebase exceeds 0.5 (`tankRadius=0.375`, `builderRadius=0.125`), so
  the bug is currently dormant in real gameplay, reachable only via a synthetic test radius
  (used 0.6 in both the differential and unit tests).

**Real bug found and fixed during differential testing (not flagged as a "finding," actually fixed):**
`collisionDetect`'s initial port used pure-Float arithmetic for lines like `hx = 1.0 - lx` and
`p.x = fx + (1.0 - radius)`. In C, the untyped `1.0`/`0.5` literals are `double`, so these
expressions implicitly promote to double precision and truncate to float only at assignment.
Swift infers a bare `1.0` as `Float` when the target type is `Float`, silently skipping that
intermediate double-precision rounding step — a divergence from C's actual behavior. This
surfaced as an intermittent fuzz-test failure (~10-20% of runs); root-caused by capturing the
exact failing input, reproducing deterministically, and tracing the arithmetic by hand before
concluding it was a real precision gap (not a logic error) and fixing every affected site with
explicit `Double(...)` promotion matching C's exact operation order.

**Residual 1-ULP divergence, NOT fixed (correctly, by design):** even after the precision fix,
the four diagonal-corner branches (`radius / sqrtf(sqr)` feeding a multiply-add) can still differ
from the C oracle by exactly 1 ULP on some inputs. Captured a case (p=(7.276611, 15.311005),
radius=0.6) where the x result matched the oracle exactly and only y differed; a bit-pattern dump
confirmed the two y values were `0x41772c5b` vs `0x41772c5c` — adjacent floats, one ULP apart.
This is an FMA-contraction difference between how clang and swiftc independently compile the
identical `a + b*c` pattern — a known, unavoidable cross-compiler floating-point non-portability
class, not a translation error (confirmed by the x value in the same case matching bit-for-bit).
The fuzz differential test uses a documented `1e-4` tolerance for this reason; every other
collisionDetect test (single-axis push, the bug-branch case, no-collision) involves no
`sqrtf`/multiply-add and keeps exact equality, since there's no contraction risk there.

**`maxSpeed`/`maxTurnSpeed` have no C oracle by design** — matches the Wave 3.1
`terrainMaxSpeed` precedent (the C equivalent lives inside stateful functions with no isolated
oracle to call). Tested Swift-only against hand-built `Pill`/`Base` arrays; PLANNER's own
compromise text defers pill/base integration testing to Wave 5.2.

**Housekeeping:** found `docs/AGENT_NOTES.md` and my own new source files already staged by
another agent's concurrent `git add` mid-session, which caused my first commit attempt to sweep
in PLANNER's staged Wave 5.1/5.2 pre-brief content under my commit message. Split this into two
correctly-attributed commits (`dfb61ee` for the PLANNER content, `e2636fb`/`acd0a04` for my Wave
5.0 work) — nothing was lost, just re-organized for accurate attribution.

[TO: PLANNER] Wave 5.0 done and verified. Please sign off on: the `kPif`-vs-`Float.pi` choice,
the dormant-bug-branch finding (radius > 0.5 required), and the 1-ULP FMA-contraction tolerance
in the fuzz test (vs. the real precision bug, which was fixed outright, not tolerance-papered).
Ready for Wave 5.1 whenever PLANNER posts the GO — noting the Wave 5.1 pre-brief in this file
already correctly anticipates replacing the Wave 5.0 `Pill`/`Base` stubs.
[TO: PARITY] New commits to audit: `e2636fb` (Wave 5.0) and `dfb61ee` (PLANNER's own staged
pre-brief content, committed as part of this session's housekeeping). The `roundDir` Float
precision, the `collisionDetect` bug replication, and the `maxSpeed` pill/base override order
were all specifically requested for your audit in the original assignment — the precision-bug
fix and the 1-ULP tolerance above are the two items most worth independent scrutiny.

---
## [PLANNER] Wave 5.0 Sign-Off
**Date:** 2026-09-01  **Commits:** e2636fb (Wave 5.0), dfb61ee (PLANNER pre-brief housekeeping)

**All three flagged items approved:**

1. **`kPif` vs `Float.pi`** ✅ — `kPif` is already defined in Vector.swift and is bit-identical to `Float.pi`. More consistent with the existing codebase than introducing `Float.pi` as a new idiom. Approved.

2. **Dormant C bug branch (radius > 0.5)** ✅ — Correct finding. The `lyc && hyc` bug in `collisionDetect` only fires when `radius > 0.5`. Since `tankRadius=0.375` and `builderRadius=0.125` are both below that threshold, the bug is unreachable in real gameplay. Using synthetic `radius=0.6` in tests to exercise the branch is the right approach. **PARITY note appended below.**

3. **1-ULP FMA-contraction tolerance** ✅ — The precision bug (C's implicit double promotion via untyped `1.0`/`0.5` literals) was correctly identified, root-caused, and fixed. The residual 1-ULP divergence in diagonal-corner branches is a known FMA-contraction cross-compiler artifact — not a translation error. `1e-4` tolerance in fuzz test is appropriate. This finding is a model of how to distinguish a real precision gap from unavoidable floating-point non-portability.

**PARITY update — collisionDetect bug is dormant in production:**
The `p.x`/`p.y` swap bug requires `radius > 0.5` to fire. All game radii (tankRadius=0.375, builderRadius=0.125) are < 0.5. The bug is replicated correctly and tested with synthetic radius=0.6, but it will never trigger in actual gameplay. PARITY should note this in the Wave 5 audit — check 5.0 `collisionDetect` item as PASS (bug replicated) with annotation "dormant in production — radius never exceeds 0.375 in game use."

Wave 5.0 is fully complete and clean. ✅

---
## [TO: IMPLEMENTER] Wave 5.1 — GO
**Date:** 2026-09-01

The full spec is in the "Wave 5.1 Assignment" section above. The Wave 5.0 stubs (`Pill`, `Base`) are already in `GameObjects.swift` — replace them with the full types. Key reminders:

- `Pill.armour == 0xff` = ONBOARD — not "max armour"
- `Base.counter: UInt16` — must hold up to 615 before reset
- `findPill` skips ONBOARD pills — `armour != 0xff` guard in the loop
- `testAlliance` requires `used` on BOTH players AND mutual bits
- `tankcollision` base threshold: `>= 5`; `buildercollision` base threshold: `> 5` — they differ
- Add `inputflags: InputFlags` to `PlayerState` (full InputFlags set is in the Wave 5.2 addendum above)
- Add missing `LocalPlayerState` fields from the Wave 5.2 addendum: `draincounter`, `refueling`, `refuelingbase`, `refuelingcounter`, `shellcounter`
- `BuilderStatus` and `BuilderTask` enums: `case \`return\`` needs backtick-escaping in Swift

No C differential tests for 5.1 — data model only. Unit tests cover `isOnboard`/`isArmed`/`isDead`, `findPill` skipping ONBOARD, `findBase` always finding, `testAlliance` mutual/used edge cases.

**Commit message:**
`Wave 5.1: GameState model — Pill, Base, Start, Shell, Explosion, PlayerState, GameState`



---
## [PARITY] Wave 5.0 Audit Report — PASS (1 low finding)
**Date:** 2026-09-01
**Commits audited:** `e2636fb` (Wave 5.0), `dfb61ee` (PLANNER pre-brief housekeeping)
**Files reviewed:** `Physics.swift` (extended), `PhysicsOps.swift` (new), `GameObjects.swift` (new); cross-referenced `bolo.h`, `client.c`, `vector.c`

### Physics constants — all verified against `bolo.h` / `client.c`
Every constant confirmed. Notable items:

- `kickSpeedDecay = 12.0` — not a named macro in `bolo.h`; confirmed as literal `12.0` at `client.c:4116` (`kickspeed -= 12.0/TICKSPERSEC`). Swift naming correct.
- `shellVelocity = 7.0` — `SHELLVEL = 7.0` in `bolo.h:70`. ✓
- `maxShellRange = 7.0` — `MAXRANGE = 7.0` in `bolo.h:75`. ✓
- `explosionTicks = 24` — `EXPLOSIONTICKS = 24`. ✓
- All pre-tabled Wave 5.7 constants (`coolPillTicks`, `replenishBaseTicks`, `treesPlantRate`, `treesBestOf`, `maxTicksPerShot`, `maxBaseArmour/Shells/Mines`) match their `bolo.h` defines exactly. ✓

### `roundDir`
`kPif` in `Vector.swift` is `3.14159265358979` — byte-for-byte identical to `vector.c`'s definition. `roundDir` uses `kPif/8.0` exactly as C does. Confirmed correct.

PLANNER sign-off requested on `kPif` vs `Float.pi`: PARITY concurs with IMPLEMENTER's choice. `kPif` is the correct constant here — it is what the C code uses, it is already in the codebase for `dir2vec`/`vec2dir`, and consistency is more important than the theoretical equivalence of `Float.pi`. ✓

### `maxSpeed` / `maxTurnSpeed`
Override order matches C exactly: armed pill → 0.0, dead pill → road speed, any base → road speed, else terrain. `findPill` excludes `pillOnboard` sentinel correctly, iterates in index order (matching C's `findpill` loop). Terrain fallthrough delegates to Wave 3.1 `terrainMaxSpeed`/`terrainMaxTurnSpeed` — previously audited, confirmed correct. ✓

No C oracle needed here (and IMPLEMENTER's justification is sound): these functions wrap stateful C client globals that cannot be isolated.

### `collisionDetect` — C bug replication
The `lyc && hyc` branch assigns `p.x = Float(Double(fy) + 0.5)` — correctly replicates C's `p.x = fy + 0.5` typo (should be `p.y`). Bug confirmed present in C source at the expected line. Replication is correct. ✓

PLANNER sign-off requested on dormant bug branch (radius > 0.5): PARITY confirms the analysis. `tankRadius = 0.375` and `builderRadius = 0.125` cannot trigger this branch in real gameplay. Differential test with synthetic radius = 0.6 is the correct approach. ✓

### `collisionDetect` — Double promotion

Most Double-promotion sites are correct. However:

**FINDING 4 (LOW) — diagonal corner promotion order:** Four sites in the diagonal corner branches use the pattern `Double(sca * hx)` or `Double(sca * hy)`:

```swift
// Example — !hxc && !lyc branch:
p.x = Float(Double(fx) + (1.0 - Double(sca * hx)))
```

C writes `fx + (1.0 - sca*hx)`. Because `1.0` is a `double` literal, C's usual arithmetic conversions individually promote `sca` and `hx` to `double` before the multiplication — i.e., C computes `Double(sca) * Double(hx)`. Swift's `Double(sca * hx)` instead performs the multiplication in `Float` first, then widens the result. These are not identical: the intermediate Float multiplication can round, and the widened value diverges from the double-precision product.

The fix is `Double(sca) * Double(hx)` (and `Double(sca) * Double(hy)`) at those four sites. This tightens parity beyond the current 1e-4 tolerance. It does not change the qualitative behavior and the existing differential test would remain valid (likely passing at exact equality for many more inputs).

**On the IMPLEMENTER's characterization (FMA contraction):** The 1-ULP divergences are real and the tolerance approach is reasonable. The root cause PARITY identifies is promotion order, not FMA contraction — FMA contraction would be indeterministic and compiler-flag-dependent; promotion order is systematic and reproducible. The practical effect (≤ 1 ULP) is the same, so the tolerance defense still holds. Recommend correcting the four `Double(sca * x)` sites for maximum fidelity; the IMPLEMENTER may disagree on severity.

PLANNER sign-off requested on 1-ULP tolerance in fuzz test: PARITY concurs it is acceptable for now, but recommends the promotion fix in a follow-up to tighten the differential. The real precision bug (not just contraction) that the IMPLEMENTER found and fixed outright — the `hx`/`hy` and `0.5`/`1.0-radius` promotions — was correctly identified and correctly fixed. ✓

### Finding 3 carry-forward
`import Darwin` unused in `Physics.swift` and `Terrain.swift`. Still open, still low. `PhysicsOps.swift` also imports Darwin — `sqrtf` and `floor` live in Darwin, so this import is required there and is correct.

### Wave 5.0 verdict: PASS
One low finding (F4). No blocking parity issues. All constants verified. `roundDir`, `maxSpeed`, `maxTurnSpeed`, and `collisionDetect` (bug inclusive) match C behavior within documented tolerance.

[TO: PLANNER] Wave 5.0 audit closed. PASS. Finding 4 (LOW): four diagonal corner sites use `Double(sca * hx/hy)` where C promotes individually — recommend `Double(sca) * Double(hx/hy)` for tighter parity. Three sign-offs confirmed (kPif choice ✓, dormant-bug radius ✓, 1-ULP tolerance ✓). Ready to audit Wave 5.1 / 5.2 when IMPLEMENTER reports completion.

---
## [PLANNER] PARITY Wave 5.0 Audit — Acknowledged
**Date:** 2026-09-01

PASS accepted. Three sign-offs confirmed (kPif ✓, dormant-bug radius ✓, 1-ULP tolerance ✓).

**Finding 4 (LOW) — disposition: DEFERRED to Wave 5 cleanup pass.**

PARITY's analysis is correct: `Double(sca * hx)` performs the Float multiply first then widens, whereas C's `1.0` literal individually promotes `sca` and `hx` before multiplying. The fix `Double(sca) * Double(hx/hy)` at four diagonal-corner sites is the right repair. However, IMPLEMENTER is already executing 5.1–5.7. Inserting a 5.0 re-open now interrupts momentum for a LOW finding with no gameplay impact.

**Action:** After IMPLEMENTER commits Wave 5.7, PLANNER will issue a Wave 5.0-fixup ticket as the first item in the post-Wave-5 cleanup wave. PARITY to re-verify those four sites only and confirm exact-match promotion order.

Finding 3 carry-forward (`import Darwin` unused in `Physics.swift`, `Terrain.swift`) also deferred to cleanup wave.

IMPLEMENTER is planning 5.1–5.7 from the pre-briefs. No additional spec work needed from PLANNER at this time — standing by to monitor completion reports.


---
## [PARITY] Wave 5.1–5.7 Pre-Audit Framework
**Date:** 2026-09-01
**Scope:** Independent quality evaluation against D3/D13/D18 goals, cross-referenced with PLANNER checklist and C oracle. Written before implementation — IMPLEMENTER should treat any item marked ⚠ as a known PARITY trap.

---
### Goals baseline
- **D3:** Fidelity target = Mac Bolo 0.99.7bv. All parity decisions reference `Reference/c/` directly.
- **D13:** Full Swift port, MIT license. No C runtime dependencies in BoloKit.
- **D18:** All physics values `Float` (32-bit). No `Double` in physics files. No `Foundation` import anywhere in BoloKit.

---
### WAVE 5.1 — GameState model

**Confirmed correct in PLANNER spec:**
- `Pill.armour == 0xff` = ONBOARD. `isOnboard`/`isArmed`/`isDead` computed properties correct.
- `Base.counter: UInt16` — max needed value is 600 + 15 = 615 (≤ UInt16.max). ✓
- `BuilderStatus` / `BuilderTask` raw values must exactly match C enum integer order in `bolo.h`.

**⚠ PARITY TRAP — Shell.owner type:** C declares `shell.owner` as `int`. In C, `NEUTRAL = 0xff = 255u`, but a signed `int` comparison `owner != NEUTRAL` fails if `owner` holds a signed `-1`. Swift `Shell.owner: UInt8` stores 0xff = 255 correctly, but any code that compares `owner` to a signed sentinel must be verified. If `playerNeutral = UInt8(0xff)` is used consistently, this is safe — but if any site does `Int(owner)` and compares to `-1`, it will always be false (255 ≠ -1). Check every `owner` comparison site in shellTick and pillTick.

**⚠ PARITY TRAP — testAlliance:** C's `testalliance(p1, p2)` requires:
1. `players[p1].used` (p1 is an active slot)
2. `players[p2].used` (p2 is an active slot)
3. `players[p1].alliance` has bit p2 set
4. `players[p2].alliance` has bit p1 set

A one-sided alliance (p1 allied to p2, but p2 not allied to p1) returns false. An unused player slot is never allied with anyone. Both conditions on `.used` are required — PARITY will verify this is not simplified to just the alliance bits.

**⚠ PARITY TRAP — tankcollision vs buildercollision base threshold:** These differ by exactly one:
- `tankcollision`: `armour >= MINBASEARMOUR (5)` — inclusive (≥)
- `buildercollision`: `armour > MINBASEARMOUR (5)` — exclusive (>)

This asymmetry is real C behavior, not a typo. PARITY will verify both closure/function forms use the correct operator and that no "cleanup" unifies them.

**⚠ PARITY TRAP — GrowState:** `GrowState.growx` and `GrowState.growy` in C are flat indices into `terrain` (`int growx, growy` in `struct server` — actually they're the winning coordinates, not flat indices based on reading). PARITY will verify GrowState coordinate representation matches how `growtrees` uses them.

---
### WAVE 5.2a — tankMoveTick (physics)

**⚠ CRITICAL PARITY TRAP — local player position coupling:** `maxSpeed` and `maxTurnSpeed` use `localPlayer`'s tank position for ALL players' terrain lookups — including remote players being ticked. This is C's behavior from `tankmovelogic` and is NOT a bug. If IMPLEMENTER "fixes" this to use each player's own position, PARITY will FAIL this item.

**⚠ PARITY TRAP — turnspeed instant reset:** When neither or both turn keys are pressed, `turnspeed = 0.0` instantly — NOT gradual. PARITY will check for any deceleration code in the no-input path.

**⚠ PARITY TRAP — dir wrap arithmetic:** C uses:
```c
if (dir > 2*kPif) dir -= 2*kPif * floorf(dir / (2*kPif));
else if (dir < 0)  dir += 2*kPif * floorf(dir / (-2*kPif) + 1.0);
```
This is NOT `fmod`. The specific `floorf` formula must be replicated exactly. PARITY will verify the exact expression, including the `+ 1.0` in the negative branch.

**⚠ PARITY TRAP — D18 in TankTick.swift:** Search for `Double` in the file. Zero hits expected. `floor` must dispatch to `Foundation.floorf` or the `Darwin.floorf` float overload — not the `Foundation.floor` double overload. Verify the float overload is called by checking the argument type.

**Shore push — 8-case vector:** PARITY will verify all 8 cardinal + diagonal neighbors are checked, that the push vector accumulates (not just takes first), and that the magnitude threshold `> 0.00001` is used exactly.

---
### WAVE 5.2b — tankLocalTick / enter()

**⚠ PARITY TRAP — enter() MinedSea:** MinedSea triggers BOTH grab (tile pickup for detonation credit) AND `drown()`. Both must fire unconditionally, regardless of boat status. C source: `sendclgrabtile` + `drown()` both called for kMinedSeaTerrain.

**⚠ PARITY TRAP — boat drop location:** Boat is dropped at OLD square, not new. C writes `terrain[old.y][old.x] = kBoatTerrain`. PARITY will verify old coordinates are used.

**⚠ PARITY TRAP — shellcounter:** `shellcounter` increments every tick regardless of whether a shell is fired. It resets to 0 only when a shell is fired. Fire condition is `shellcounter > 12` (strictly greater than, not ≥). PARITY will verify the increment runs unconditionally, outside the fire-condition branch.

**⚠ PARITY TRAP — refuel priority:** Armour, shells, mines are NOT refueled concurrently per tick — C checks each in sequence with its own counter threshold. Each transfer resets `refuelingcounter` to 0, so only one resource refuels per 46/7/7 ticks. PARITY will check for concurrent transfer logic.

---
### WAVE 5.3 — shellTick

**⚠ PARITY TRAP — shell advance precision:** `shellVelocity / ticksPerSec = 7.0 / 50.0`. In C, `SHELLVEL/TICKSPERSEC` where both are float macros — this is float division, result ≈ 0.14. Swift must use `shellVelocity / ticksPerSec` (both `Float`) — not a Double intermediate. Confirm D18 holds here.

**⚠ PARITY TRAP — explosion particle counter:** `counter` starts at 0, increments each tick, removed when `counter > EXPLOSIONTICKS (24)` — that's 25 frames of display (0 through 24 inclusive). Using `>= 24` would remove one frame early. PARITY will verify the strictly-greater comparison.

**⚠ PARITY TRAP — self-hit:** In C, `shellcollisiontest` for tank hits checks `i != client.player` — a player's own shells cannot kill themselves. Swift equivalent must exclude the shell owner from tank-hit testing. PARITY will check for the owner exclusion.

**⚠ PARITY TRAP — pill shell tank-hit exclusion:** Pill shells (`shell.pill == true`) use `NEUTRAL` as owner. The tank-hit check must handle this correctly — a pill shell owned by `NEUTRAL` should be able to hit any player including the local player? Check C's `shellcollisiontest` for `shell.pill` handling.

---
### WAVE 5.4 — builderTick

**⚠ PARITY TRAP — builderRadius in collisionDetect:** Builder uses `builderRadius = 0.125`, not `tankRadius = 0.375`. Passing the wrong radius is a silent bug (no compile error).

**⚠ PARITY TRAP — buildercollision base threshold:** Uses `armour > 5` (exclusive). Distinct from tankcollision's `armour >= 5`. Must not be unified.

**⚠ COMPLEXITY FLAG:** PLANNER notes builderlogic is the most complex sub-wave. PARITY will read `client.c:4531–5033` directly when auditing this wave. State machine transitions (`kBuilderReady → kBuilderGoto → kBuilderWork/Wait/Return`) must all be present.

---
### WAVE 5.5 — pillTick, explosionTick

**⚠ PARITY TRAP — literal `0.70711219`:** The shell offset from pill center uses this exact float literal, not `Float(sqrt(2.0)/2.0)`. These differ slightly (sqrt(2)/2 ≈ 0.70710678). PARITY will grep for `0.70711219` in the source and fail if a computed equivalent is used instead.

**⚠ PARITY TRAP — pill shell range `8.5 - 0.70711219`:** Not `maxShellRange (7.0)`. A pill fires slightly farther than a tank can shoot directly. PARITY will verify this literal.

**⚠ PARITY TRAP — forestvis check:** `forestvis(tank) > 0.25` — the C function computes fractional forest visibility. The Swift equivalent must match its interpolation logic. PARITY will verify this function is ported, not approximated.

---
### WAVE 5.6 — spawn()

**⚠ PARITY TRAP — arc4random_uniform modulo bias:** C uses `random() % range` which has modulo bias for large ranges. `arc4random_uniform(range)` is unbiased. This is a KNOWN INTENTIONAL DIVERGENCE (Apple platform determinism + quality improvement). Must be documented with a comment at the call site. PARITY will verify the comment exists and the right RNG is used.

**⚠ PARITY TRAP — post-spawn boat:** `boat = 1` always after spawn. The tank spawns on water (boat terrain) or land, but always has boat status = 1. PARITY will verify this.

**⚠ PARITY TRAP — Pass 2 fallback:** When all starts have weight 0 (all hostile-pill-spiked), C reruns with base weights only (ignoring pill proximity). PARITY will verify the two-pass structure exists and that Pass 2 drops pill penalties specifically.

**⚠ PARITY TRAP — dir conversion:** `start.dir` is stored 0–15 (C `uint8_t`). Post-spawn `dir = start.dir * (π/8)`. Must use `Float.pi` (D18), not `kPif` (either is bit-identical for this purpose but consistency matters). PARITY will verify `Float`.

---
### WAVE 5.7 — growtrees, pill cooldown, base replenish

**⚠ CRITICAL — growtrees C BUG must be replicated:** The outer pill/base guard in C checks `(x, y)` — the last randomly-sampled cell — not `(growx, growy)` — the tournament winner. Inner guard correctly checks `(growx, growy)`. BOTH checks must be present in exactly this form. PARITY will verify:
1. Outer: `findPill(x:y:)` and base lookup use `x, y`
2. Inner: the actual grow action uses `growx, growy`
3. A DifferentialTest exercises this case (pill/base at last-sampled position only, winner clear)

**⚠ CRITICAL — integer division:** `treesBestOf / (treesPlantRate * Int(ticksPerSec))` = `4200 / 500 = 8`. Must be integer division. If `ticksPerSec` is used as `Float` here, the result becomes `8.4` which truncates to 8 — same answer, but the path is wrong. PARITY will verify `Int` arithmetic throughout growtrees.

**⚠ PARITY TRAP — pill cooldown is `speed++`, NOT `armour++`:** Pill armour is never auto-restored. Only `pill.speed` (reload interval) degrades. A confusion here produces a pill that silently restores health over time, which has zero behavioral foundation in C. PARITY will verify the field name at the increment site.

**⚠ PARITY TRAP — base replenish counter:** `base.counter += nplayers` per tick. If IMPLEMENTER uses `+= 1`, the replenish rate is wrong by a factor of `nplayers`. This is a subtle scaling bug. PARITY will verify the counter increment.

**⚠ PARITY TRAP — applyGrow mined variants:** Mined terrain (minedGrass, minedRubble, etc.) must grow to `.minedForest`, not `.forest`. Plain terrain variants grow to `.forest`. Sea, wall, existing forest, and all others: no-op. PARITY will verify the full switch table including mined cases.

---
### Cross-cutting checks (all of Wave 5)

**D18 sweep:** `grep -n "Double\|CGFloat\|M_PI\|Double\.pi" Sources/BoloKit/` — zero hits expected in any new physics file. A single `Double` in arithmetic invalidates D18 compliance for that file.

**Foundation import:** `grep -rn "import Foundation" Sources/BoloKit/` — zero hits expected. `arc4random_uniform` and `sqrtf`/`floorf` are available from Darwin without Foundation.

**Finding 3 resolution expected:** `import Darwin` unused in `Physics.swift` and `Terrain.swift`. With Wave 5 adding Darwin-dependent code in `PhysicsOps.swift` and `TankTick.swift`, the pattern is established. Clean up the two stale imports. PARITY will re-check at final audit.

**Test coverage floor:** Per PLANNER's established pattern:
- Each differential-testable function needs ≥1000 random fuzz inputs
- Each behavioral branch in enter() needs its own unit test case
- growtrees C BUG needs a dedicated differential test
- The pill-armour-vs-speed confusion needs a regression test

---
### Known intentional divergences (document, do not flag)
| Divergence | Location | Justification |
|---|---|---|
| `arc4random_uniform` vs `random()%range` | spawn() | Apple platform determinism, no modulo bias |
| collisionDetect `p.x`/`p.y` swap | PhysicsOps.swift | Replicates C bug for behavioral parity |
| growtrees outer guard on `(x,y)` not `(growx,growy)` | GrowTrees.swift | Replicates C bug for behavioral parity |
| `Double(sca * hx)` vs `Double(sca)*Double(hx)` | PhysicsOps.swift | F4 (LOW) — 1-ULP; covered by 1e-4 tolerance |
| `writeRun` x<256 guard | BMap.swift | Safe deviation; prevents C memory corruption |
| row-spillover y=255 col=256 clamp | BMap.swift | True UB in C; no oracle value to match |

[TO: PLANNER] Wave 5.1–5.7 pre-audit framework written. All ⚠ traps are PARITY's independent findings beyond the checklist — flag for IMPLEMENTER before they start each sub-wave. PARITY will execute the full audit checklist item-by-item when IMPLEMENTER reports Wave 5.7 complete, reading C source directly for each claim rather than relying solely on IMPLEMENTER's summary.

---
## [PLANNER] PARITY Pre-Audit Framework — Acknowledged
**Date:** 2026-09-01

PARITY's Wave 5.1–5.7 trap framework received and reviewed. The intentional-divergence table is the canonical record; IMPLEMENTER must document each at the call site with a `// C: <exact C form>` comment.

The following traps require IMPLEMENTER attention **before** coding begins on each sub-wave — forwarding now.

---
## [TO: IMPLEMENTER] Critical Pre-Implementation Warnings for Waves 5.3–5.7
**Date:** 2026-09-01

PARITY has independently reviewed the C source and flagged several traps beyond the pre-briefs. Read this before starting each sub-wave.

**Wave 5.3 — shelllogic / builderlogic / pilllogic:**
- The pill offset literal is **`0.70711219`** (exact C float literal) — NOT `Float(sqrt(2.0)/2.0)` (which produces `0.70710678`). These differ. Copy the literal exactly.
- Pill shell range is **`8.5 - 0.70711219`**, NOT `maxShellRange (7.0)`. Pills fire farther than tanks.
- `forestvis(tank) > 0.25` — this function must be ported in full, not approximated. If it's not already in BoloKit, port it from C.

**Wave 5.5 — tanklocallogic / enter():**
- All per-field logic is in the pre-brief above. No additional traps beyond what's already documented.

**Wave 5.6 — spawn():**
- Use `arc4random_uniform(range)` (not `random() % range`). Document at the call site: `// C uses random()%range — intentional divergence: unbiased, Apple-native RNG`.
- `boat = 1` **always** after spawn — regardless of spawn terrain.
- Two-pass structure is required: Pass 1 weights include pill proximity penalties; Pass 2 (all-zero fallback) drops pill penalties only, keeps base/hostile weights.
- `start.dir` (0–15) → post-spawn `dir = Float(start.dir) * (Float.pi / 8)` — use `Float.pi` (D18).

**Wave 5.7 — growtrees / pill cooldown / base replenish:**
- **CRITICAL BUG REPLICATION:** Outer guard in growtrees checks `(x, y)` (last random sample), NOT `(growx, growy)` (tournament winner). Inner guard uses `(growx, growy)`. Both forms required exactly as in C.
- Pill cooldown increments **`pill.speed`**, never `pill.armour`. Armour is builder-only.
- Base counter: **`base.counter += nplayers`** — scales with player count.
- Mined terrain grows to **`.minedForest`**, not `.forest`. Cover every mined variant in the switch.
- `treesBestOf / (treesPlantRate * Int(ticksPerSec))` must use **integer arithmetic** throughout.

**Cross-cutting (all sub-waves):**
- Zero `Double`, `CGFloat`, `M_PI`, or `Double.pi` in any physics/game-logic file. Use `Float` or `Float.pi` exclusively (D18).
- Zero `import Foundation` in any BoloKit source.
- While in `Physics.swift` / `Terrain.swift`: remove the stale `import Darwin` (Finding 3).

---

### [IMPLEMENTER] 2026-09-01 — Correction: PARITY Finding 4 is empirically wrong, do not apply
**Type:** correction
**Phase:** 1 / Wave 5.0 cleanup (pre-emptive)
**Blocks:** the deferred Wave 5.0 cleanup ticket

Before starting Wave 5.1, verified PARITY's Finding 4 (`Wave 5.0 Audit Report`) empirically rather than
taking it on trust, since it proposed changing already-shipped, already-tested code.

**Finding 4 claimed:** C's `fx + (1.0 - sca*hx)` individually promotes `sca` and `hx` to `double`
*before* multiplying (i.e. `Double(sca) * Double(hx)`), and that the current Swift
(`Double(sca * hx)` — multiply in Float, then widen) diverges from this.

**This is incorrect.** C's "usual arithmetic conversions" apply per-operator, not by lookahead
across a whole expression: `sca * hx` (both plain `float`) computes in Float precision first
(one rounding); the result only widens to `double` when it later combines with the `1.0` literal
in the subtraction. There is no mechanism in C by which an operator's conversions are influenced
by what the result will later be combined with.

**Verified by compiling the literal C expression** (`clang -O0`, matching `fx + (1.0 - sca*hx)`
exactly) and running 2000 randomized `(sca, hx, fx)` trials against both candidate Swift formulas:
- Current code, `Float(Double(fx) + (1.0 - Double(sca * hx)))`: **2000/2000 exact bit-pattern
  matches** against the compiled C reference.
- PARITY's suggested fix, `Float(Double(fx) + (1.0 - Double(sca) * Double(hx)))`: **1966/2000** —
  it would introduce 34 new divergences per 2000 trials that do not currently exist.

**Disposition:** Finding 4 is retracted. The four `Double(sca * hx)` / `Double(sca * hy)` sites in
`PhysicsOps.swift`'s diagonal-corner branches are already exactly correct and must NOT be changed
to `Double(sca) * Double(hx/hy)` in the deferred Wave 5.0 cleanup pass. Everything else in PARITY's
Wave 5.0 audit (kPif choice, dormant-bug-branch radius analysis, the real Double-promotion bug that
was actually fixed at the `hx`/`hy`/`0.5`/`1.0-radius` sites) remains correct and stands.

Also cross-checked the rest of PARITY's Wave 5.1–5.7 pre-audit trap framework against three parallel
direct reads of `client.c`/`server.c` (tankmovelogic, tanklocallogic, enter, shelllogic, builderlogic,
pilllogic, spawn, growtrees, pill cooldown, base replenish — all read in full, not skimmed). Every
other ⚠ trap in that framework checks out against the source. Proceeding with Wave 5.1 now.

[TO: PLANNER] Finding 4 retracted with empirical evidence above — please update the deferred Wave 5.0
cleanup ticket to drop that item. No action needed on the four `Double(sca * hx/hy)` sites.
[TO: PARITY] Your Wave 5.1–5.7 trap framework is otherwise fully corroborated by direct C source
research (see the upcoming Wave 5.1 report for additional findings your framework didn't cover:
a second real bug in the dead-tank explosion-skip enum check, and a scope correction to Wave 5.4
since `builderlogic`'s work state is a client-side no-op — all build mutation logic is server-side
and must be merged into the unified tick). Recommend re-verifying the Finding 4 retraction
independently if you'd like a second pair of eyes, but the bit-pattern evidence above is exact and
reproducible (`clang -O0` vs `swift`, both on this machine, same inputs).

---

### [IMPLEMENTER] 2026-09-01 — Wave 5.1 complete: GameState model
**Type:** build
**Phase:** 1 / Wave 5.1
**Blocks:** nothing

Wave 5.1 executed per the [TO: IMPLEMENTER] Wave 5.1 GO. Committed as `a3126c6`. 76 tests green
(26 differential + 50 unit).

**Delivered:** `GameObjects.swift` extended with the full `Pill`/`Base`/`Start`/`Shell`/`Explosion`/
`BuilderStatus`/`BuilderTask`/`InputFlags`/`PlayerState`/`LocalPlayerState`/`GrowState` types plus
`findPill`/`findBase`/`testAlliance` helpers; new `GameState.swift` unifying everything into one
authoritative model (no client/server split, since this is a standalone simulation).

**Deviation from the pre-brief, deliberate:** `Pill`/`Base` `x`/`y` changed from Wave 5.0's `Int`
stubs to `UInt8`, matching the actual C struct layout and the existing `BMapPillInfo`/`BMapBaseInfo`
precedent already shipped in `BMap.swift`. Updated `maxSpeed`/`maxTurnSpeed`'s lookups (now calling
the new public `findPill`/`findBase` rather than a private Wave-5.0-only helper) accordingly.
`goto`/`return` in `BuilderStatus` needed no/backtick escaping respectively — `goto` is not
reserved in Swift (no goto statement exists), only `return` needed `` `return` ``.

No C oracle for this wave — pure data model, matches PLANNER's own framing exactly.

Also did the direct-source verification pass covering ALL of Wave 5.1–5.7 before starting any
code (three parallel reads of `client.c`/`server.c` in full for every function involved). That
surfaced several things beyond what's in the existing pre-briefs/PARITY trap framework — filing
them now since they affect upcoming sub-waves, not just 5.1:

1. **A second real C bug** (dead-tank tumble explosion-skip in `tankmovelogic`): the "skip
   explosion" check compares a terrain-enum value against tile-enum constants (`kSeaTile`/
   `kMinedSeaTile` = 16/17), which in this codebase's terrain ordering actually correspond to
   grass1/grass2, not sea. Real sea/mined-sea tiles fall through and always spawn the explosion.
   Must be replicated bug-for-bug in Wave 5.2a (check `terrain.rawValue == 16 || == 17`, not
   `.sea`/`.minedSea`).
2. **Wave 5.4's scope is understated in the existing pre-brief.** `builderlogic`'s `kBuilderWork`
   state is a pure no-op on the client — every build cost and terrain mutation lives in server-side
   handlers (`recvclbuildroad/wall/boat/pill/repairpill/placemine`, `recvclgrabtrees`,
   server.c:2347-2802) triggered by a network ack that doesn't exist in a standalone simulation.
   Wave 5.4 will merge those handlers directly into the unified tick. One handler
   (`recvclbuildroad`) has a tautological tree-sufficiency guard (`if (trees >= trees)`, always
   true) — flagging for sign-off whether to replicate that specific bug or correct it when I get
   to 5.4; leaning replicate, since it's not a Swift memory-safety concern (unlike `writeRun`'s
   x<256 guard, which was a deliberate safety deviation for a different reason).
3. **Wave 5.5's "closest hostile" pillbox-firing check is per-network-client** in the original —
   every client independently asks "is anyone strictly closer to this pill than *me*". A single
   authoritative simulation has no "me"; I'll generalize by running the same eligibility check
   independently for every hostile player against each pillbox, which is what collecting every
   client's independent computation would produce (ties can fire on multiple players
   simultaneously — preserves the exact tie-break quirk).

**Also independently verified — and disproved — PARITY's Finding 4** before starting (see the
correction entry above, commit `c4d501b`): the diagonal-corner `Double(sca * hx)` sites in
`PhysicsOps.swift` are already exactly correct; PARITY's suggested fix would introduce new
divergences. Confirmed empirically (2000-trial bit-pattern comparison against compiled C).

[TO: PLANNER] Wave 5.1 done and verified. Proceeding to Wave 5.2a (tankMoveTick) next. Findings 1–3
above are new, beyond the existing pre-briefs — flagging now so they're on record before I write
the affected code, not discovered after.
[TO: PARITY] New commit to audit: `a3126c6`. Please also see the Finding-4 retraction (`c4d501b`)
and the three new findings above (dead-tank enum bug, Wave 5.4 server-merge scope, Wave 5.5
multi-target generalization) — these go beyond your existing trap framework and I'd value a second
look before I lock in the Wave 5.4/5.5 designs.

---

### [IMPLEMENTER] 2026-09-01 — Wave 5.2a complete: tankMoveTick
**Type:** build
**Phase:** 1 / Wave 5.2a
**Blocks:** nothing

Committed as `a752a77`. 101 tests green (27 differential + 74 unit).

**Delivered:** `dir2vec`/`vec2dir` added to `Vector.swift` (ported from bolo.c:327-337, using
already-shipped `k2Pif`/`tan2f`/`_atan2f`); `isShore`, `tankCollision`, `tankMoveTick` in new
`TankTick.swift`; a reduced-parameter oracle (`tankphysics_oracle`) in new `Sources/CXBolo/tankops.c`
for the core numeric transform (turning/wrap/accel/position/kickspeed decay — shore-push and
collision need pill/base/terrain lookups so they're Swift-only tested instead).

**Architectural decision — dead-branch stays gated to `state.localPlayer`:** C's tumble/boom/respawn
sequence reads `client.respawncounter`/`mines`/`shells` — fields that exist once per LOCAL client
instance, not once per player. Since `GameState.local` (Wave 5.1) models these once, not per player,
generalizing this sequence to every dead player simultaneously would need per-player resource
tracking that doesn't exist. Kept the `player == localPlayer` gate exactly as C has it. This is
different from the generalizations already flagged for Wave 5.5 (pillTick) and noted for Wave 5.3
(shellTick self-hit exclusion) — those operate on data every player already has in `PlayerState`;
this one depends on data that's currently singular. Flagging as a known gap: true multi-human
death/respawn simulation needs `LocalPlayerState` (or equivalent) to become per-player at some point.

**Confirmed the dead-tank enum-mismatch bug** flagged in the Wave 5.1 report: replicated exactly
(`terrain.rawValue == 16 || == 17`, i.e. grass1/grass2 in this port's ordering — not sea/minedSea).
Dedicated regression test (`tankMoveTickDeadTumbleSkipsExplosionOverGrass1AndGrass2Bug`) exercises
all five relevant terrain cases and would fail if anyone "fixes" this to check `.sea`/`.minedSea`.

**A second real precision bug, found via fuzzing and fixed (not just tolerance-papered):**
`kickspeed -= 12.0/TICKSPERSEC` in C computes the division in double precision, since `12.0` is an
untyped double literal — and `0.24` (12/50) is not exactly representable in either Float or Double,
so which precision does the division in actually changes the rounded result. My first port used
plain Float division and diverged by 1 ULP, caught immediately by the differential fuzz test (many
mismatches, not rare). Fixed with the same `Float(Double(a) - Double(b)/Double(c))` pattern already
established for `collisionDetect`. **Also verified, not just assumed:** `accel/ticksPerSec` and
`angularAccel/ticksPerSec` do NOT need the same treatment — stress-tested at 20,000 fuzz iterations
(temporarily, then reverted to 1000 for the committed suite) with zero divergence, because
`accel/ticksPerSec` happens to reduce to an exact power-of-2 fraction (25/512) that both Float and
Double division compute identically regardless of intermediate precision. Confirmed this empirically
rather than assuming symmetry with the kickspeed case.

**Test-fixture pitfall worth recording:** my first differential-test fixture set a single grass cell
at the tank's exact starting position to give `maxSpeed`/`maxTurnSpeed` something non-zero to return.
This backfired for `boat=true` cases: `isShore` treats ANY non-water terrain (including grass) as
shore, so that one cell became "shore" the moment the tank drifted into an adjacent tile mid-tick,
triggering shore-push side effects the reduced oracle (which doesn't model shore-push at all) has no
way to reproduce — 656 spurious failures on the first run. Fixed by leaving the grid fully default
(sea) for `boat=true` fuzz cases (boat physics bypasses the terrain-based speed lookup entirely, so
no land terrain is needed there) and only placing land terrain for `boat=false` cases (which never
run the shore-push block). Recording this because it's a subtle test-design trap, not a code bug —
worth being careful about in Wave 5.4/5.5's oracle fixtures too, since they'll also mix terrain
lookups with terrain-dependent side effects.

[TO: PLANNER] Wave 5.2a done and verified. Proceeding to Wave 5.2b (tankLocalTick + enter()) next.
[TO: PARITY] New commit to audit: `a752a77`. Please specifically check: the local-player dead-branch
gating decision (deliberate scope limitation vs. Wave 5.5's planned generalization — want a second
opinion on whether this asymmetry is the right call), the enum-mismatch bug replication, and the
kickspeed precision fix (same class as your Wave 5.0 Finding-4 discussion, but this one's a real bug
I found and fixed, not a false positive).

---

### [IMPLEMENTER] 2026-09-01 — Wave 5.2b complete: tankLocalTick / enterTile
**Type:** build
**Phase:** 1 / Wave 5.2b
**Blocks:** nothing

New file `Sources/BoloKit/TankLocalTick.swift` (`tankLocalTick`, `enterTile`, `grabTile`, `drown`,
`smallboom`, `superboom`, `killBuilder`, `killSquareBuilder`, `killPointBuilder`), plus new
constants in `Physics.swift` (`drainTicks`, `refuelArmourTicks/ShellsTicks/MinesTicks`,
`minBaseShells/Mines`, `minRange`, `explosionRadius`, `shellFireThresholdTicks`) and a `deaths`
counter added to `LocalPlayerState`. 46 new unit tests in `TankLocalTickTests.swift`. 119 tests
green in BoloKitTests + 27 in the differential/other targets — full suite green, no regressions.
No new CXBolo oracle: this wave is control-flow/RNG-heavy rather than numeric, matching the
precedent set for `GameState` (Wave 5.1, no oracle for a pure data model) and the `spawn()`
pre-brief's note that `arc4random_uniform`-based branches have no C-process oracle to diff against.

**Scope decision, made before writing any code, not discovered partway through:** read
`tanklocallogic()`/`enter()` in full plus everything they call transitively — `drown`, `smallboom`,
`superboom`, `killsquarebuilder`, `killpointbuilder`, `killbuilder`, and (via the server-side
`sendcl*`/`recvcl*` round trip that doesn't exist in a unified sim) `recvclgrabtile`,
`recvcldropboat`, `recvcldropmine`, `recvclsmallboom`/`recvclsuperboom` → `explosionat`/
`superboomat`/`chain`/`flood`, and `droppills`. The first group (drown/smallboom/superboom/
killbuilder/killsquarebuilder/killpointbuilder/grabtile's pill-and-base-capture-and-boat-pickup)
is fully self-contained given what Wave 5.1 already modeled (`PlayerState.builderStatus`/
`.builder`, `LocalPlayerState.builderPill/Task/Mines/Trees`) and is implemented completely, no
stubs. The second group — mine-chain/flood terrain propagation and the pill-scatter placement
search — is a genuinely separate, not-yet-designed subsystem with its own state (chain lists,
flood lists) that no current wave (5.0–5.7) actually covers despite Wave 5.5 sounding adjacent
("explosionTick"). Recorded as **Q12** in `PLAN.md` rather than silently absorbing or hand-waving
it. Surfaced as three no-op-by-default injection points — `onMineExplosion`, `onSuperboomTerrain`,
`onDropPills` — following the exact precedent `tankMoveTick` (Wave 5.2a) already set with
`onExplosion`/`onSuperboom`/`onSmallboom`/`onSpawn`. This wave is fully testable and behaviorally
complete for everything it does claim to do; nothing here is a half-finished stand-in.

**Also omitted, for an unrelated reason — no simulation state, not "deferred":** C's
`testhiddenmine` (only calls `refresh()`, a fog-of-war tile-cache invalidation for rendering) and
the `increasevis`/`decreasevis` visibility-radius bookkeeping after a tank moves. BoloKit's
simulation core has no fog-of-war/rendering state (per the Phase 3 architecture: `BoloCore`/
`BoloKit` has no AppKit surface), so there is nothing to port here, unlike the mine-chain/pill-drop
gap above which genuinely is unbuilt simulation logic.

**A structural finding worth flagging directly, not just noting in a comment:** `enter()`'s base
branch only ever sends the grab-tile message when the base is neutral or NOT allied with the
entering player — when already allied, C skips sending it entirely, so `recvclgrabtile`'s own
internal "ally handoff" branch (transfer ownership, leave resources untouched) is *unreachable*
from this call path. It can still fire in principle from other callers of grabtile server-side in
the original (build/repair actions elsewhere), so `grabTile` keeps that branch for structural
fidelity, but `enterTile` correctly never reaches it — walking onto an already-allied base is a
no-op, not a re-capture. Caught this via a test that initially asserted the wrong thing (expected
the ally branch to fire) and failed; traced it back to the C source rather than "fixing" the test
by loosening the assertion. Separately (and unrelated): walking onto **your own** base hits the
*hostile*-takeover branch and zeroes its resources, because C's alliance bitmask has no
self-alliance special case — replicated exactly, with a dedicated regression test
(`enterTileWalkingOntoOwnBaseZeroesResourcesLikeHostile`) so nobody "fixes" it later.

**Test-fixture pitfall worth recording (same category as Wave 5.2a's shore-push one):**
`TerrainGrid.mapDefault()` puts mined-sea in the border ring outside `[xMinMine, xMaxMine]²`
(roughly `[10, 245]`) and plain sea inside it — either way, a default `PlayerState.tank` of
`(0, 0)` or a test that doesn't explicitly set terrain will silently drown the player inside
`enterTile` before the assertion runs, since `boat` also defaults to `false`. This surfaced as
two outright crashes (`killBuilder` reached with an empty `state.starts` because a builder-kill
path fired unexpectedly under a bare default `GameState()`) before I traced it to this. Fixed by
standardizing on an explicit safe fixture (`tank = (50.5, 50.5)`, `terrain[50,50] = .grass0`) for
tests that don't care about position. Flagging because Wave 5.3+ fixtures will hit the exact same
trap the moment they use a bare `GameState()` with a moving/alive local player.

[TO: PLANNER] Wave 5.2b done and verified, commit follows this entry. Q12 (mine-chain/flood +
pill-scatter subsystem gap) recorded in PLAN.md's Open Questions — recommend deciding whether it's
its own wave or folds into 5.5 before that wave's pre-brief is finalized, since three functions in
this commit (`grabTile`, `smallboom`, `superboom`) already have the exact injection points it would
wire into. Proceeding to Wave 5.3 (shellTick/builderTick/pillTick) next unless redirected.
Note: per the new post-commit-only PARITY rule in the docs restructuring, I'm not tagging
[TO: PARITY] here — that's PLANNER's call to make after reviewing this report.

---

### [PLANNER] 2026-09-01 — Planner handoff; Q12 resolved as D22; Wave 5.3 assignment
**Type:** planning
**Phase:** 1 / Wave 5
**Blocks:** nothing

New planner session taking over from the prior PLANNER instance (chat-overhead reset, per Jerod).
Picked up state from `docs/PLAN.md` and this file rather than re-reviewing source — Wave 5.2b's
own report (tanklocallogic/enter, commit follows that entry) is taken at face value, consistent
with the existing pattern where PARITY does the independent behavioral check post-commit, not
PLANNER re-deriving it from the diff.

**Q12 resolved as D22** (full text in PLAN.md decisions log): Wave 5.5 splits into **5.5a**
(`explosionAt`/`superboomAt`/`chain`/`flood` mine-detonation cascade, `droppills` pill-scatter
placement — the genuinely new subsystem 5.2b surfaced) and **5.5b** (`explosionTick` — drains the
chain list 5.5a builds — plus `forestvis`). Reasoning: 5.5b cannot be meaningfully tested without
5.5a's chain-list state existing first, so treating them as one wave would force writing an
untestable consumer before its producer; splitting keeps each sub-wave independently gated. Both
wire into the `onMineExplosion`/`onSuperboomTerrain`/`onDropPills` injection points already added
in Wave 5.2b — no rework needed there.

[TO: IMPLEMENTER] Proceed to **Wave 5.3** (`shellTick`, `builderTick`, `pillTick`) as you proposed
in the 5.2b report — confirmed, no redirection. When you reach Wave 5.5, pre-brief 5.5a first
(mine cascade + pill-scatter) and land it before starting 5.5b (`explosionTick`/`forestvis`); the
wave table in PLAN.md now reflects this split.

[TO: PARITY] Wave 5.2b is ready for independent audit whenever you pick it up — flag in
particular the two structural findings the Implementer called out themselves: (1) `enter()`'s
ally-handoff branch in `recvclgrabtile` being unreachable from this call path (still kept for
other callers), and (2) walking onto your own base hitting the hostile-takeover branch and
zeroing resources (no self-alliance special case in the original bitmask — replicated on
purpose, regression-tested). Confirm both are correct C fidelity, not just internally consistent
Swift.

---

### [PLANNER] 2026-09-01 — Wave 5.8 added: end-of-Wave-5 docs/archive pass (Q13)
**Type:** planning
**Phase:** 1 / Wave 5
**Blocks:** Wave 6

Per Jerod's request, adding an explicit open item at the end of the Wave 5 sequence rather than
letting documentation upkeep happen implicitly. Logged as **Q13** in PLAN.md's open questions and
as **Wave 5.8** in the wave status table — a gate between Wave 5 finishing and Wave 6
(networking/UI) starting, not something to interrupt 5.3–5.7 for.

**Scope of Wave 5.8 (Q13), for whoever picks it up:**
1. Refresh `docs/PLAN.md` — confirm the wave table and decisions log are current once 5.3–5.7
   land, close out any Wave-5-scoped open questions.
2. Compress the Wave 5.x entries out of `docs/AGENT_NOTES.md` into `docs/notes/archive.md`,
   following the existing Waves 1–4 convention already in that file (short bullet per wave: commit
   hash, one-line scope, notable findings, ✅). AGENT_NOTES.md is pushing 2000 lines; Wave 5 alone
   is the bulk of that.
3. Refresh project memory (`plan-status.md`, `roles-workflow.md`, `project-overview.md`) to match
   wherever Wave 5 actually lands.
4. Reconcile the project-instructions config, which still describes a pre-Wave-5 state (Wave 1
   complete, defining Wave 2 scope) against the AGENT_NOTES.md/PLAN.md canonical record — flagged
   by this PLANNER session at handoff, not yet acted on.

[TO: IMPLEMENTER] No action needed now — this is queued behind 5.3–5.7, not a redirect. Flag it
back to PLANNER once Wave 5.7 lands so Wave 5.8 can be picked up before Wave 6 starts.

---

### [PARITY] 2026-09-01 — New Auditor session; Wave 5.2a holding items closed; Wave 5.2b audited
**Type:** audit
**Wave:** 5.2a (close), 5.2b (new)
**Verdict:** 5.2a — PASS (holding items resolved). 5.2b — PASS.

New PARITY AUDITOR instance succeeding the prior session (chat-overhead reset, per Jerod).
Picked up from `docs/AGENT_NOTES.md`/`docs/PLAN.md` state rather than re-reading the whole
codebase — targeted, source-verified checks only, per the surviving open items.

**Wave 5.2a — closing the two "READ — holding" items:**

1. **F4 retraction (`c4d501b`), verified independently.** Re-derived C's operator-conversion rule
   from first principles (per-operator "usual arithmetic conversions," not whole-expression
   lookahead): `sca * hx` with both operands `float` computes in Float precision, widening to
   `double` only at the later `1.0 - (...)` subtraction. This is exactly what the shipped
   `Double(sca * hx)` pattern does. IMPLEMENTER's empirical bit-pattern trial (2000/2000 vs C, vs
   1966/2000 for my original suggested fix) is consistent with this and I did not find a
   counter-argument. **Retraction confirmed — Finding 4 stays retracted, no further action.**

2. **Dead-tank enum-mismatch bug, verified against `tiles.h`/`terrain.h` directly**, not taken on
   report. `tankmovelogic` (`client.c:3995-3996`) switches on `client.terrain[...]` (a Terrain
   value) but its case labels are `kSeaTile`/`kMinedSeaTile` — Tile-enum constants. Confirmed
   `tiles.h`: `kSeaTile = 16`, `kMinedSeaTile = 17` (16 mined-terrain-preceding tile constants,
   0-indexed, then these two). Confirmed `terrain.h`: ordinal 16/17 in that enum are
   `kGrassTerrain1`/`kGrassTerrain2`. So the C switch genuinely never matches real sea/mined-sea
   terrain — it silently matches grass1/grass2 instead, meaning the "skip explosion over water"
   intent is broken in the original and the explosion fires over real sea/mined-sea while being
   incorrectly suppressed over two grass variants. Checked `Sources/BoloKit/TankTick.swift:109-121`
   against this: `Terrain` enum ordering in `Terrain.swift` reproduces the C ordinal layout exactly
   (`grass1.rawValue == 16`, `grass2.rawValue == 17`), and the hardcoded `terrainValue != 16 &&
   terrainValue != 17` check is bug-for-bug faithful, with a named regression test guarding it.
   **Confirmed correct — bug replicated exactly, not accidentally right.**

   Also spot-verified the companion kickspeed-decay double-precision fix in the same file
   (`TankTick.swift:246-253`): C's `kickspeed -= 12.0/TICKSPERSEC` forces double-precision division
   because `12.0` is an untyped double literal in C; the ported `Double(kickSpeed) -
   Double(kickSpeedDecay)/Double(ticksPerSec)` reproduces that promotion correctly. Consistent with
   the already-shipped `collisionDetect` pattern. No issue.

**Wave 5.2b (`71411b9`/`4c6ad1b`) — full read of `enter()` (client.c:5785-5967) and
`recvclgrabtile` (server.c:2271-2337) against `Sources/BoloKit/TankLocalTick.swift`:**

- **Structural finding 1 (ally-handoff branch unreachable) — CONFIRMED.** `enter()`'s base
  branch sends `sendclgrabtile` only when `base.owner == NEUTRAL || !testalliance(owner, player)`
  — i.e. only when the allied branch of `recvclgrabtile` could *not* fire. Checked every other
  `sendclgrabtile` call site in `client.c` (pill-capture side-effect branches at lines
  2288/2320/2330): all are keyed off `findpill` succeeding, and pill/base tiles don't coincide, so
  `findbase` is `-1` there and the base-ownership block in `recvclgrabtile` never executes for
  those sends either. The allied-transfer branch is unreachable from any real call path — keeping
  it in `grabTile` for structural fidelity (in case Wave 6 networking reintroduces other callers)
  is the right call, not dead code that should be deleted.
- **Structural finding 2 (own-base re-entry hits hostile-takeover, zeroes resources) —
  CONFIRMED.** Traced `testalliance(p1,p2)` (`client.c`): requires both directions of the alliance
  bitmask to have the other player's bit set. Confirmed alliance defaults to `0` at connect
  (`client.c:269`) and is only ever mutated by explicit `clsetalliance`/`srsetalliance` traffic —
  nothing sets a player's own bit in their own mask automatically. So `testalliance(player,
  player)` is false by default, meaning walking onto your own already-owned base takes the
  `else` (hostile) branch in `recvclgrabtile`, zeroing armour/shells/mines. Swift's `grabTile`
  (`TankLocalTick.swift:279-288`) reproduces the three-way owner/ally/hostile branch structure
  exactly, with `testAlliance` gating the ally branch the same way. **Confirmed correct — no
  self-alliance special case in the original, none introduced in the port.**
- Also checked the `.forest` case's C fallthrough (`client.c` terrain switch in `enter()`: the
  forest case has no `break` and falls into the swamp/crater/road/rubble/grass block). Swift
  (`TankLocalTick.swift:404-419`) uses an explicit `fallthrough` to reproduce this — correct, and
  correctly scoped (the dead-tank explosion-spawn logic runs only inside the forest case itself,
  the boat-drop/mine-plant logic that follows applies unconditionally to both forest and the
  shared block, matching C's shared post-fallthrough guard conditions line for line).
- Checked `.minedSea`'s unconditional `drown()` (fires regardless of `boat`, unlike plain `.sea`
  which checks `!boat` first) — C: `client.c` mined-sea case calls `drown()` unconditionally after
  the conditional `sendclgrabtile`. Swift matches, with an explanatory comment already in place.

No divergences found in either wave. Updating status table below.

[TO: PLANNER] Wave 5.2a's two holding items are now resolved (F4 retraction independently
confirmed; dead-tank enum bug independently confirmed against `tiles.h`/`terrain.h` raw values,
not just cross-checked against the report). Wave 5.2b: PASS, no findings — both structural
questions you flagged are correct C fidelity, confirmed via `testalliance`/`recvclgrabtile`
source, not just internal Swift consistency. Ready for Wave 5.3 audit whenever it lands; will
continue picking up post-commit per the established protocol rather than re-touring completed
waves.

| Wave | Status | Notes |
|---|---|---|
| 5.0 | CLOSED | F4 confirmed retracted (independent re-derivation, not just accepted) |
| 5.1 | CLOSED | Dead-tank enum bug independently confirmed against tiles.h/terrain.h raw values |
| 5.2a | CLOSED | Kickspeed double-precision decay fix confirmed correct |
| 5.2b | CLOSED | PASS — ally-handoff unreachability and own-base hostile-takeover both confirmed against testalliance/recvclgrabtile source |
| 5.3–5.7 | PENDING | Full audit at each commit, per protocol |

---

### [PLANNER] 2026-09-01 — Wave 5.3 phasing agreed (D23); tautology ruling (D24); readiness check acknowledged
**Type:** planning
**Phase:** 1 / Wave 5.3
**Blocks:** nothing — unblocks 5.3b

Jerod agreed with the 5.3a/b/c split from IMPLEMENTER's readiness check (bundling shellTick +
builderTick + pillTick — ~1000 lines across three unrelated server.c handler families — into one
wave was too large a unit of cost/review). Logged as **D23** in PLAN.md; wave table updated:

- **5.3a** (in progress) — shellTick: `shelllogic`, `shellcollisiontest`, `recvcldamage`,
  `recvcltouch`, plus `killTank` pulled forward from 5.6 (hidden dependency: the shell tank-hit
  path calls it at armour-zero; reuses `onboardPillMask` from 5.2b — correct call not to add
  another injection point for something this small and already-scoped-in).
- **5.3b** (queued) — builderTick, absorbing the former Wave 5.4's `buildercollision` line item
  (testAlliance/findPill/findBase shipped in 5.1, tankCollision shipped in 5.2a — Wave 5.4 is
  retired as a standalone row, not left dangling).
- **5.3c** (queued) — pillTick + `forestvis`, moved out of 5.5b. `forestvis` is needed by
  pillTick's firing condition (`dist ≤ 2.0 OR forestvis(tank) > 0.25`), so it has to exist before
  5.3c runs, not after — 5.5b now covers `explosionTick` only.

**D24 — `recvclbuildroad`'s `if (trees >= trees)` tautology: replicate bug-for-bug, do not
correct.** Same discipline as the dead-tank terrain-enum mismatch and growtrees' outer-guard bug —
Phase 3 is behaviour-preserving; Phase 5 is where fidelity gaps get fixed, not mid-port ad hoc.
Not a Swift memory-safety concern (unlike `writeRun`'s x<256 guard), so no countervailing reason
to deviate. Requires a named regression test documenting the tautology is intentional — same
pattern as the other two replicated bugs. **This unblocks Wave 5.3b.**

**Readiness-check items acknowledged, no further action:**
- The self-hit shell generalization (all-shells-vs-all-tanks, preserving the self-hit branch) —
  accepted, same reasoning already applied to pillTick's closest-hostile check. Reported
  after-the-fact per the established 5.1/5.2 pattern, which is the right call for this class of
  generalization.
- CLAUDE.md staleness ("Wave 5.1 — IN PROGRESS") and forestvis's old placement under 5.5b — both
  correctly deferred, not fixed ad hoc. forestvis's *placement* is now corrected here (D23,
  moved to 5.3c) since it was blocking a real dependency ordering, not just a documentation
  staleness issue; CLAUDE.md itself stays Wave 5.8 / Q13 territory as flagged.

[TO: IMPLEMENTER] Proceed with 5.3a as scoped (including `killTank`). D24 is ruled — replicate the
`trees >= trees` tautology with a regression test; 5.3b is unblocked whenever you get to it. No
change to the self-hit generalization call.

---

### [IMPLEMENTER] 2026-09-02 — Wave 5.3a complete: shellTick / shellCollisionTest / applyDamage / killTank

**Type:** build
**Phase:** 1 / Wave 5.3a
**Blocks:** nothing — unblocks 5.3b

Executed per D23/the `[TO: IMPLEMENTER] Proceed with 5.3a as scoped` GO above. New file
`Sources/BoloKit/ShellTick.swift` (`shellAdvance`, `heatPill`, `applyDamage`, `touchTile`,
`shellCollisionTest`, `killTank`, `shellTick`), plus a reduced-parameter oracle
(`shelladvance_oracle`) in new `Sources/CXBolo/shellops.c` for the move/range-advance numeric
core — collision resolution needs pill/base/terrain lookups so it's Swift-only tested instead,
same split `tankops.c` established in 5.2a. Two new `Physics.swift` constants: `shellDamage (5)`,
`minTicksPerShot (6)`. 32 new unit tests (`ShellTickTests.swift`), 1 new differential fuzz test
(`ShellTickDifferentialTests.swift`, 1000 iterations). Full suite: 151 BoloKitTests + 28
DifferentialTests, all green — no regressions against the 119+27 baseline from 5.2b.

**Precision, checked rather than assumed:** `SHELLVEL/TICKSPERSEC` hits the same double-promotion
trap as 5.2a's kickspeed decay (`SHELLVEL` is a double literal `7.0`; `TICKSPERSEC` is a bare int
literal `50` that promotes to double) — confirmed via the oracle fuzz (1000 iterations, exact
bit-pattern match) that this needs the `Double(a)/Double(b)` treatment, both for the step value
*and* the `range < step` comparison itself (which happens with `range` promoted UP to double, not
the step narrowed down first).

**Generalization from C's network-authority model, reported per the established 5.1/5.2 pattern
(not asked in advance):** every collision-resolution, damage-application, and builder-kill call
in `shellcollisiontest`/`shelllogic` is gated in C on `player == client.player` — a network
dedup (only the client owning a shell list submits its results; every other client would compute
the identical result independently). BoloKit has one authoritative simulation, so this port
drops that gate everywhere it appears: `shellCollisionTest`/`applyDamage`/`touchTile` always
apply, and per-player explosion attribution (`client.players[client.player].explosions`) becomes
`state.players[shell.owner].explosions`, since the gate's `client.player` always equals the
shell's owner at every site that reaches it. This matches the already-accepted self-hit
generalization exactly (same file, same reasoning).

**A second real bug found, not just replicated — and fixed for memory safety, not "corrected"
for behavior:** `recvcldamage`'s base-hit pill-heating loop clamps with `server.pills[pill].speed`
where `pill` is the *outer* scope's failed `findpill` result — always `-1` in this branch. This
is `pills[-1]`, an out-of-bounds C read/write (undefined behavior), not a deterministic,
well-defined bug like the dead-tank enum mismatch or `collisionDetect`'s p.x/p.y swap — both of
which get replicated exactly because C's behavior there is well-defined. UB has no meaningful
"faithful" Swift translation, and Swift arrays trap on invalid indices regardless, so
`applyDamage`'s base branch uses the evidently-intended `pills[i]` (the same pill just halved two
lines up in the C source) instead — same class of deviation as `writeRun`'s x<256 guard. Flagging
for PARITY to confirm this reasoning rather than treating it as a silent fix.

**Scope note — `killTank`'s tank-hit-loop caller stays gated to `state.localPlayer`, matching
`tankMoveTick`'s precedent exactly:** the armour decrement and `killTank()` call in the tank-hit
loop only fire `if target == state.localPlayer`, because `LocalPlayerState.armour` only exists
once. A hit on a remote player's tank still applies the kick and spawns the explosion (both live
in per-player `PlayerState`), but has no armour pool to decrement in this port — the same
singular-`LocalPlayerState` boundary Wave 5.2a already established and accepted for the
dead-tumble/respawn sequence, not a new architectural decision.

**Test-fixture note, same category as 5.2a/5.2b's:** every fixture in `ShellTickTests.swift`
explicitly sets `state.terrain[50, 50] = .grass0` via the shared `makeState` helper — a bare
`GameState()` still puts the origin in the mined-sea border ring.

[TO: PLANNER] Wave 5.3a done and verified, commit follows this entry. Proceeding to Wave 5.3b
(builderTick, including the D24-ruled `trees >= trees` tautology replication) next unless
redirected.
[TO: PARITY] New commit to audit. Please specifically check: the network-authority-gate
generalization applied throughout `shellCollisionTest`/`applyDamage`/`touchTile`/`shellTick`
(dropping `player == client.player` everywhere it appeared in the C source), the `pills[-1]`
UB-vs-memory-safety fix in `applyDamage`'s base branch, and the exhaustiveness of the boat-shell
terrain switch's `default: damage` branch (verified by hand against the 30-case `Terrain` enum in
the doc comment, but a second read would help). Per the post-commit-only PARITY rule, not tagging
further action here — that's PLANNER's call.

---

### [PARITY] 2026-09-02 — Wave 5.3a audit (`ff807ff`)
**Type:** audit
**Wave:** 5.3a
**Verdict:** PASS (findings) — one architecture question for PLANNER, one doc-comment nit. No blocking issues.

Read `shellcollisiontest`/`shelllogic` (client.c:5126-5497), `killtank` (client.c:5545), `recvcldamage`
(server.c:2804), `recvcltouch` (server.c:2236) in full against `Sources/BoloKit/ShellTick.swift`,
per IMPLEMENTER's three specific check requests.

**Confirmed correct, no issues:**

- **`pills[-1]` UB fix.** Verified `recvcldamage`'s base-hit pill-heating loop really does clamp
  with the outer `pill` variable (`server.pills[pill].speed = MAX(...)`) which is provably `-1` in
  that branch (only reached when the earlier `findpill` call returned `-1`). This is unindexable
  UB in C, not a well-defined replicable bug — IMPLEMENTER's substitution of the evidently-intended
  `pills[i]` (the same pill just halved two lines up) is the right call, same class as `writeRun`'s
  x<256 guard. Confirmed `heatPill(i, ...)` in `applyDamage`'s base branch uses `i`, not a stray
  `-1`-equivalent.
- **Network-authority-gate generalization, structurally sound.** Every `player == client.player`
  gate in the C source that guards network sends (`sendcldamage`/`sendcltouch`/`sendclhittank`)
  correctly has no Swift equivalent (no network layer exists), and the gates that guard actual
  state mutation (`killtank()`'s armour path) stay correctly gated to `state.localPlayer`, matching
  `tankMoveTick`'s precedent. Shell removal on tank-hit is unconditional in both C and Swift
  (`removelist`/`shells.remove(at:)` happen outside the local-only branch) — confirmed not
  accidentally gated.
- **`killTank` port.** Line-for-line match against `killtank()` (client.c:5545): onboard-pill
  bitmask scatter, `deaths++`, `dead=1`, `boat=0`, `respawncounter=0` — all present, correctly
  gated on `!dead` (C's `if (!client.players[client.player].dead)`).
- **Terrain-ladder exhaustiveness, both `applyDamage` switches.** Cross-checked every case
  transition in `recvcldamage`'s boat and non-boat switches (server.c) against `applyDamage`'s two
  switches — all transitions (`.swamp0→.river`, `.grass0→.swamp3`, `.damagedWall0→.rubble3`, etc.)
  match exactly, including the water-adjacency road-tile special case and its matching
  out-of-bounds-neighbor memory-safety deviation (`?? .wall` — correctly inert, since the mined-sea
  border ring makes a real road tile at the map edge unreachable).
- **`shellCollisionTest` terrain-switch exhaustiveness, verified by direct case enumeration, not
  just trusting the comment (see finding below for why).** C's boat-shell switch lists 4 no-damage
  cases + 1 special-cased `road` + 25 damage cases = 30, and its `default` is provably unreachable
  (every enum value already listed). Swift's boat-shell switch explicitly lists the same 4 no-damage
  cases + `road`, and folds the remaining 25 into `default: applyDamage`. Enumerated the 25-case set
  by hand against C's explicit damage list — exact match (includes `.boat`, all four `swamp`/
  `rubble`/`grass`/`damagedWall` variants, `forest`, and the six mined-non-sea variants). Same check
  for the non-boat switch: Swift's 7 explicit damage cases (`wall`, `forest`, 4×`damagedWall`,
  `boat`, `minedForest`) match C's explicit 8-case damage list... 

  **Correction while writing this up: recounted and Swift's non-boat switch explicit list is 7
  named cases covering 8 terrain values (`damagedWall0-3` is 4 cases within one case-list), which
  does match C's non-boat damage set exactly (`wall`, `forest`, `damagedWall0-3`, `boatTerrain`,
  `minedForest` = 8 terrain values). No discrepancy — flagging only because the arithmetic needs
  care here, see next item.**

**Finding (LOW, doc-only) — boat-shell switch's exhaustiveness comment miscounts.** The doc comment
above the boat-shell `default:` branch reads "4 handled above + this default's 26 = 30" — but the
switch explicitly handles 5 terrain values above the default (4 no-damage cases *plus* `road*,*
which is also explicit, not part of the default), so the default covers 25 cases, not 26 (25+5=30,
not 26+4=30). The underlying code is correct (verified above) — only the comment's arithmetic is
off by one in a way that could mislead someone re-deriving the count later. Recommend a one-line
comment fix in `ShellTick.swift` next time that file is touched; not worth a standalone commit.

**Finding (MEDIUM, architecture question — not asserting a bug) — per-player `explosions` list
attribution doesn't have a clean single-simulation equivalent, and the port's `shell.owner`-based
choice doesn't match either of C's two different attribution rules.** Traced every `addlist(...,
explosion)` call site touched by this wave:

- `recvcldamage`'s "expire due to range" phase (`shelllogic`, client.c:5474) attributes to
  `client.players[player].explosions` — `player` being the shell-list owner (the *correct* semantic
  owner).
- But `shellcollisiontest`'s pill/base/terrain-hit branches and `shelllogic`'s tank-hit-test phase
  (client.c:5148-5343, 5427) all hardcode `client.players[client.player].explosions` — the *local
  process's own* player, **regardless of whose shell or which target tank was involved.** This only
  makes sense in C's actual architecture: each connected human runs their own full copy of this
  code with `client.player` fixed to themselves, deterministically replicating everyone's shell
  physics locally, and stores the resulting visual-effect record in *their own* list because that's
  the only list their own screen/camera logic reads. There is no single "client.player" in a
  merged, single-authoritative simulation for this rule to generalize onto.
- Compounding this: pillbox-fired shells set `shell->owner = client.pills[i].owner` (client.c:5085)
  but are appended to `client.players[client.player].shells` (client.c:5090) — i.e., a pillbox
  shell's `.owner` field is its *damage/alliance attribution* (whose side it's on), not the shell
  list it lives in or the "local client" role C's explosion code actually keys off. So `shell.owner`
  isn't even the right generalization target for the `client.player`-hardcoded call sites above.

  IMPLEMENTER's uniform choice of `state.players[shell.owner].explosions` is a reasonable,
  internally-consistent pick, but it reproduces *neither* of C's two different rules exactly (it
  matches the "expire" phase only when `shell.owner == player`, which is always true there since
  that phase never mixes lists — but diverges from the collision/tank-hit phases' `client.player`
  rule whenever shell.owner ≠ shooter, i.e. every pillbox shell, and whenever a shell hits a
  *different* player's tank than would be "watching" it).

  **Have not found any mechanical consumer of `players[*].explosions` beyond `explosionlogic`'s
  counter-decay-and-remove (client.c ~5504-5530)** — no damage, no builder-kill, no other gameplay
  math reads from it; `killpointbuilder`/`killsquarebuilder` are called directly and
  unconditionally alongside the explosion append, never gated on which list received the entry.
  If that holds (worth PLANNER/IMPLEMENTER double-checking, since I did not exhaustively grep every
  future wave's planned consumers), this list is purely cosmetic effect-duration data with no
  differential-testable consequence today — which would make the exact attribution scheme a Wave-6
  UI-layer decision, not a Phase-3 parity gate. **Recommend:** PLANNER confirm this reading, and
  either (a) explicitly rule the current `shell.owner` choice acceptable-for-now with a note that
  Wave 6 may need to revisit it once there's an actual per-player UI consuming these lists, or (b)
  ask IMPLEMENTER to pick a different, explicitly-documented convention if some future wave will
  read these lists mechanically. Not blocking Wave 5.3b — flagging now so it isn't rediscovered
  cold at Wave 6.

[TO: PLANNER] Wave 5.3a: PASS overall, both specifically-requested memory-safety/generalization
items (`pills[-1]`, network-authority gate) confirmed correct. One LOW doc-comment fix queued
(non-blocking). One MEDIUM open question on `explosions`-list attribution semantics — needs a
ruling or at least a deferred-decision note in PLAN.md before Wave 6, not before 5.3b.

---

### [PLANNER] 2026-09-01 — Wave 5.3a closed (PARITY PASS); GO issued for Wave 5.3b
**Type:** planning
**Phase:** 1 / Wave 5.3
**Blocks:** nothing

PARITY's Wave 5.3a audit reviewed: **PASS overall**, both specifically-requested items confirmed
correct (`pills[-1]` memory-safety edge, network-authority gate on `killTank`'s dead-tank state
mutation staying `localPlayer`-scoped like `tankMoveTick`'s precedent). Two items came back with
it, neither blocking:

- **LOW, doc-only:** the boat-shell switch's exhaustiveness comment in `ShellTick.swift` miscounts
  (says "26" where the code and PARITY's hand-enumeration both show 25 default-handled cases,
  code itself is correct). Not worth a standalone commit — fix opportunistically next time that
  file is touched.
- **MEDIUM, logged as Q14:** `explosions`-list attribution has no clean single-simulation
  equivalent — C uses two different, mutually incompatible rules across different call sites (one
  keyed to the shooting player, one hardcoded to "whichever process is running this code," which
  doesn't exist in a merged sim). IMPLEMENTER's `shell.owner`-keyed choice is reasonable and
  internally consistent but matches neither C rule exactly. PARITY found no mechanical gameplay
  consumer of this list today — if that holds, it's cosmetic effect-duration data and the actual
  attribution scheme becomes a Wave-6 UI-layer call, not a Phase-3 parity gate. Logged as Q14
  rather than ruled now, since PARITY itself flagged it as "needs a ruling before Wave 6, not
  before 5.3b" — no reason to force a decision ahead of when it's needed.

Wave 5.3a marked ✅ Complete in PLAN.md's status table (PARITY PASS, Q14 open/non-blocking).

[TO: IMPLEMENTER] **GO for Wave 5.3b.** D24 already unblocks the `recvclbuildroad` tautology
(replicate bug-for-bug, regression test required). No other holds. Proceed.
[TO: PARITY] Q14 logged in PLAN.md, targeted at Wave 6 — flag again there if it hasn't been ruled
on by then. LOW doc-comment finding accepted, no fix scheduled separately (bundled into ordinary
next-touch cleanup).

---

### [PLANNER] 2026-09-02 — Q15 opened: WinBolo server-code precedent question (Wave 6)
**Type:** planning
**Phase:** 1 / Wave 6 (not yet started — no impact on current Wave 5.3b work)
**Blocks:** nothing right now; targeted at Wave 6 pre-brief

Jerod, while reviewing precedent work, found `server/` files in a WinBolo repo (on GitHub, so
almost certainly the classic open-source WinBolo, not the 2026 commercial "WinBolo 2" relaunch)
and asked whether benchmarking those against our plan is on the table before Wave 6 is
pre-briefed.

**Current plan doesn't call for it.** D3 (fidelity target = original Mac Bolo 0.99.7bv) and D4
(self-contained network, no WinBolo interop) both point away from WinBolo as a behavioral
reference, and the Wave 5 benchmarks table already treats several WinBolo gameplay/physics
behaviors as known divergences to avoid replicating (wall friction, tank deceleration, boat/land
transition, mine self-damage, builder retrieval, pillbox range). That's about fidelity, though —
Wave 6 (networking architecture) has no pre-brief yet either way.

**Checked the license before going further:** classic WinBolo (GitHub forks — milki/winbolo,
kippandrew/winbolo, etc., including `servercore.c`) is GPL v2 per winbolo.org's own wiki. That's
copyleft — copying or closely deriving Wave 6 networking code from it would pull GPL obligations
onto BoloKit, conflicting with staying MIT (D13, our retained LICENSE). Reading it purely for
architectural understanding (session handling, NAT traversal patterns) and then writing an
independent implementation is a different and much lower-risk activity, similar in spirit to D5's
clean-room approach for art — but that needs to be a deliberate choice, not assumed by default.

Logged as **Q15**, targeted at Wave 6, not ruled yet — waiting on the specific repo link from
Jerod to confirm which fork/license actually applies before recommending an approach.

[TO: IMPLEMENTER] No action — Wave 6 hasn't started, this doesn't touch 5.3b.
[TO: PARITY] FYI only, nothing to audit yet.

---

### [PLANNER] 2026-09-02 — Q15 resolved as D25: WinBolo clean-room reference policy for Wave 6
**Type:** planning
**Phase:** 1 / Wave 6 (not yet started — no impact on current Wave 5.3b work)
**Blocks:** nothing right now

Jerod confirmed the repo: github.com/kippandrew/winbolo. Verified directly — classic WinBolo/
LinBolo source (client & server, tracker, WBN, JBolo, WOME), "copyright 1998-2008 John Morrison,"
**GPL v2**. Includes the server code Jerod was reviewing.

**Ruled as D25: read-only, clean-room policy.** WinBolo's *architecture* may inform Wave 6; its
*code* may not.

- Permitted: reading WinBolo's server implementation to understand session lifecycle, NAT
  traversal approach, protocol framing — same kind of research already planned for the UPnP/
  NAT-PMP work in Phase 6.
- Not permitted: copying, transliterating, or closely paraphrasing WinBolo code into BoloKit.
  GPL v2 is copyleft; doing so would pull GPL obligations onto a project that stays MIT (D13).
- Process: whoever pre-briefs Wave 6 documents which specific design choices, if any, were
  informed by WinBolo, so PARITY can audit for accidental over-similarity deliberately rather
  than stumbling onto it later. Same spirit as D5's clean-room approach for art assets.

Q15 closed (moved out of Open Questions into the Decisions log as D25). No action needed from
IMPLEMENTER or PARITY today — this is scoped to whenever Wave 6 gets pre-briefed, well after
5.3b/5.3c/5.4-5.7.

[TO: IMPLEMENTER] No action.
[TO: PARITY] No action — flagged for you again once Wave 6 pre-brief lands, so the "informed by
WinBolo" disclosure has something to audit against.

---

### [IMPLEMENTER] 2026-09-02 — Wave 5.3b complete: builderTick, plus a cross-cutting `mag2f`/`dot2f` fidelity fix

**Type:** build
**Phase:** 1 / Wave 5.3b
**Blocks:** nothing — unblocks 5.3c

Executed per PLANNER's `[TO: IMPLEMENTER] GO for Wave 5.3b`. New file `Sources/BoloKit/BuilderTick.swift`
(`tankTest`, `tankOnABoatTest`, `circleSquare`, `builderSpeed`, `builderTargetSpeed`,
`builderCollision`, seven private work handlers, `builderTick` and its five private per-status
helpers), a reduced oracle (`builderops.c`) for the pure numeric transforms, two new `Physics.swift`
constants (`builderBuildTime`, `forestTreeYield`, `maxPillArmour`). 48 new unit tests
(`BuilderTickTests.swift`), 3 new differential fuzz tests (`BuilderTickDifferentialTests.swift`).
Full suite: 199 BoloKitTests + 31 DifferentialTests, all green — no regressions against the
151+28 baseline from 5.3a.

**Two scope cuts, made deliberately and documented in the file header, not discovered
mid-implementation:**

1. **`getbuildertaskforcommand()`/`client.nextbuildercommand`/`client.nextbuildertarget` are out
   of scope** — a fog-of-war/UI-input-layer concern (resolves a raw command + the `seentiles`
   fog cache into a `BuilderTask`), not core simulation, same category as Wave 5.2b's
   `testhiddenmine`/`increasevis`/`decreasevis` omissions. `builderTick`'s `.ready` case instead
   reads `state.local.builderTask` directly as an already-resolved one-shot order — the same
   contract `InputFlags` already has with `tankMoveTick`.
2. **`repairPill`'s "trees needed" is derived from ground-truth `Pill.armour`, not the fog-of-war
   tile cache** — `bmap_client.c:169` keeps `seentiles` permanently synced to
   `kFriendlyPill00Tile + armour` whenever a pill is in view, so reading `armour` directly is
   strictly more accurate and needs no rendering-tile model.

**D24 applied exactly as ruled:** `buildRoad(at:trees:state:onMineExplosion:)`'s `if trees >= trees`
replicates the tautology verbatim, with a named regression test
(`gotoArrivalOnBuildRoadTautologyAlwaysSucceedsGivenAnyPositiveTrees`) asserting the build succeeds
even with only 1 tree held (below `roadTrees = 2`), guarding against anyone "fixing" it later.

**Collapsed the network round trip:** C's `kBuilderGoto` arrival sends `sendcl<action>` and parks
in `kBuilderWork` (a pure placeholder — `case kBuilderWork: break;`) until the SERVER's
`recvcl<action>` mutates state and replies via `sendsrbuilderack`, whose client-side handler
(`recvsrbuilderack`) is what actually advances to `kBuilderWait`. With no client/server split,
`arriveAtTarget` performs the `recvcl<action>` mutation and the ack's consequence synchronously,
going straight to `.wait`. `.work` stays in the enum/switch for structural fidelity but is
unreachable in this port.

**A real off-by-one caught before shipping, not after:** `kBuilderWait`'s C guard is
`builderwait++ > BUILDERBUILDTIME` — POST-increment, so the OLD value is compared and the field
increments regardless. My first draft incremented first then compared the new value, which would
fire the `.return` transition one tick early. Fixed to compare-then-increment, with a dedicated
test (`waitTransitionsToReturnAfterBuilderBuildTimeUsingPostIncrementSemantics`) pinning the exact
tick boundary.

**Significant finding, well beyond this wave's scope — `mag2f`/`dot2f` themselves were not
bit-faithful, since Wave 1, for broadly-random inputs:**

While building the oracle for this wave's `diff * (speed / (ticksPerSec * mag2f(diff)))` movement
step, broad fuzzing (`Float.random(in: -5...5)`, not the 9-value "nice number" grid Wave 1's own
`VectorDifferentialTests` uses) turned up ~15-20% mismatches. Traced it to `dot2f` itself
(`v.x*v.x + v.y*v.y`) diverging from the C oracle *before any sqrt is involved* — confirmed by
isolating `dot2f` alone at the same fuzz range. Root cause: Clang's default `-ffp-contract=on`
fuses the multiply-add in `dot2f` into a single `fmaf` (one rounding) on arm64; Swift's `+`/`*`
never contract, so it always does two roundings. This is a compiler-flag issue, not a Swift
source-code issue — no amount of `Float(Double(...))` narrowing-pattern fixing (which I tried
first, and which made it *worse*, not better) touches it, since the divergence originates in the
**C oracle's** compiled instruction selection, not in Swift.

**Fix:** added `cSettings: [.unsafeFlags(["-ffp-contract=off"])]` to the `CXBolo` target in
`Package.swift`, forcing the C oracle to compute exactly what its source text says, with no
fusion. Verified: `dot2f`/`mag2f` now match bit-for-bit at 20,000 fuzzed iterations over the full
map coordinate range (`-256...256`), and reverted an unnecessary `Vector.swift` change I'd
tried first (`Float(sqrt(Double(...)))`) once the flag alone proved sufficient — `mag2f`'s source
is unchanged from Wave 1.

**Why this matters beyond today:** every existing differential test that transitively calls
`mag2f`/`dot2f` (which is nearly all of them — tank physics, shell physics, collision detection)
was previously exposed to this gap; none of them happened to fail because their fuzz ranges were
either narrow (Wave 1's own 9-value grid) or apparently didn't sample enough "unlucky" magnitudes
to trigger a mismatch in the number of iterations run. **Re-ran the full existing suite after
applying the flag: 31 differential + 199 unit tests, all still green — no prior test's *expected*
values needed to change.** This means the flag fix is a pure improvement (removes a latent gap
without altering any already-verified behavior), not a retroactive correction to any prior wave's
committed results.

[TO: PLANNER] Wave 5.3b done and verified, commit follows this entry. The `-ffp-contract=off` fix
is a build-configuration change with project-wide reach — recommend flagging it prominently rather
than treating it as routine wave content, since it changes what "the C oracle" computes for every
future wave too. Proceeding to Wave 5.3c (pillTick + forestvis) next unless redirected.
[TO: PARITY] New commit to audit. Specifically: (1) the `-ffp-contract=off` finding and fix —
recommend independently confirming the FMA-contraction root cause (e.g. by inspecting the
generated assembly for `dot2f` with/without the flag) rather than taking my empirical
fuzz-isolation as sufficient on its own, since this affects the validity of every prior wave's
oracle comparisons; (2) the two scope cuts (`getbuildertaskforcommand`, ground-truth-armour
`repairPill`); (3) the `builderwait++` post-increment fix. Per the post-commit-only PARITY rule,
not tagging further action here — that's PLANNER's call.

---

### [PARITY] 2026-09-02 — Wave 5.3b audit (`27a76d3`)
**Type:** audit
**Wave:** 5.3b
**Verdict:** PASS. FMA-contraction fix independently confirmed at the assembly level, not just accepted on fuzz evidence. No blocking issues; one low-severity note on unsigned-wraparound fidelity in the (unreachable) D24 tautology branch.

Read `builderlogic`/`buildercollision`/`getbuildertaskforcommand` (client.c:4531-4531+, 6540,
6831), `recvclbuildroad`/`recvclrepairpill`/`recvclgrabtrees` (server.c:2347-2680), and the
`bmap_client.c` fog-cache sync (line 169) against `Sources/BoloKit/BuilderTick.swift`, per
IMPLEMENTER's three specific check requests plus the cross-cutting fp-contract claim.

**`-ffp-contract=off` root cause — independently reproduced, not just trusted.** Compiled
`dot2f`'s literal source (`v1.x*v2.x + v1.y*v2.y`) at `-O2` on this machine's toolchain, with and
without the flag, and diffed the generated arm64 assembly directly:
- Default: `fmul s0, s0, s3` / `fmadd s0, s2, s1, s0` — the multiply-add is fused into one `fmadd`
  (single rounding).
- `-ffp-contract=off`: `fmul`/`fmul`/`fadd` — three separate instructions, two roundings.

Then ran a 500,000-iteration randomized comparison of the *same compiled function* built both
ways: **132,563/500,000 (~26.5%) produced different bit patterns** — a materially higher and more
alarming rate than even IMPLEMENTER's own reported ~15-20%, which only reinforces that this was a
real, frequently-triggered gap, not a rare edge case. Confirms the root cause exactly as reported:
this is a C-compiler code-generation difference for the **oracle**, not anything wrong with prior
Swift source. `Package.swift`'s `cSettings: [.unsafeFlags(["-ffp-contract=off"])]` on the `CXBolo`
target is the correct, minimal fix.

**Confirmed correct — the three specifically-requested items:**

1. **`getbuildertaskforcommand` scope cut.** Verified it reads `client.seentiles[...]`
   (`client.c:6546` etc.) — the fog-of-war UI cache populated by `bmap_client.c`'s rendering sync,
   not simulation ground truth. Legitimately a UI-input-resolution layer, same category as Wave
   5.2b's `testhiddenmine`/`increasevis`/`decreasevis` omissions. `state.local.builderTask` as an
   already-resolved one-shot order is a reasonable simulation-layer boundary, consistent with how
   `InputFlags` is already handled.
2. **`repairPill`'s ground-truth-armour claim.** Verified `bmap_client.c:169`:
   `seentiles[...] = kFriendlyPill00Tile + pills[i].armour` — the fog cache is *always* kept
   synced to raw `armour` whenever a pill is visible, and more importantly, **the actual resource
   mutation** (`recvclrepairpill`, server.c:2633) never reads the fog cache at all — it operates on
   `server.pills[pill].armour` directly. So reading `armour` in the port isn't merely
   "strictly more accurate," it's the actually-correct migration target; the fog cache was never
   part of this calculation's ground truth to begin with, only of the client-side task
   classification cut above. `repairPill`'s `+ trees*4` / clamp-to-`maxPillArmour` /
   refund-excess-trees logic matches `recvclrepairpill` line for line, including the terrain
   case set and the mined-terrain explosion branch.
3. **`builderwait++ > BUILDERBUILDTIME` post-increment fix.** Confirmed C's exact semantics
   (`client.c:4928`): post-increment, so the pre-increment value is compared and the field always
   advances. `BuilderTick.swift:795-797` (`let old = ...; ...= old + 1; if old > builderBuildTime`)
   reproduces this exactly. The regression test's name correctly documents the tick-boundary
   pinning.

**Also checked, unprompted, since D24 was cited:** `recvclbuildroad`'s `if (clbuildroad->trees >=
clbuildroad->trees)` tautology (server.c:2417) is confirmed always-true, and `buildRoad`
(`BuilderTick.swift:264`) replicates it verbatim per D24, including the un-clamped
`return trees - roadTrees` (matches C's un-clamped `clbuildroad->trees - ROADTREES` passed to
`sendsrbuilderack`).

**One low-severity note, not a finding requiring action — flagging for the record given D24's
"replicate verbatim" ruling:** C's `trees`/`SRBuilderAck.trees` fields are `uint8_t`
(`client.h:214`, `server.h:287`), so if this arithmetic ever executed with `trees < roadTrees`
(2), the subtraction would promote to signed `int` (`1 - 2 = -1`) but then truncate back to
`uint8_t` when written into the packed ack struct — wrapping to `255`, a genuinely game-breaking
outcome (255 trees from nothing) if it were ever reachable. `BuilderTick.swift`'s `builderTrees`
field is `Int` (`GameObjects.swift:238`), so if this branch were ever reached with insufficient
trees, the port would silently go *negative* instead of wrapping to *255* — a divergence from C's
actual (bad) behavior. IMPLEMENTER's comment states the earlier READY-state gate
(`state.local.trees >= roadTrees`) makes this unreachable in practice, which I did not find reason
to doubt from the code read here — but I did not independently trace every path into `.goto`/
`.work` to rule out a future wave reintroducing a way to skip that gate. Recommend no action now;
worth a one-line note in `BuilderTick.swift` (or a differential/unit test asserting the gate truly
makes `trees < roadTrees` unreachable at this call site) whenever that file is next touched, so
the `Int`-vs-`uint8_t` distinction doesn't quietly matter later.

No divergences found. Wave 5.3b: PASS.

[TO: PLANNER] Wave 5.3b: PASS. FMA-contraction root cause independently confirmed at the assembly
level (26.5% mismatch rate on direct A/B compilation, even higher than IMPLEMENTER's own fuzz
estimate) — recommend treating this fix as verified, not merely plausible. All three specifically-
requested items (scope cuts ×2, post-increment fix) confirmed correct against source. One
low-severity, non-blocking note logged above re: `uint8_t` wraparound vs. Swift `Int` in the
(currently unreachable) D24 tautology branch — no action needed unless a later wave changes the
READY-gate's reachability guarantee.

---

### [PLANNER] 2026-09-02 — Wave 5.3b closed (PARITY PASS); fp-contract fix logged as D26; GO issued for Wave 5.3c
**Type:** planning
**Phase:** 1 / Wave 5.3
**Blocks:** nothing

PARITY's Wave 5.3b audit (`27a76d3`) reviewed: **PASS**. All three specifically-requested items
confirmed against source — `getbuildertaskforcommand`'s scope cut (fog-of-war UI layer, correctly
excluded), `repairPill`'s ground-truth-armour read (verified `recvclrepairpill` itself never
touches the fog cache — this was the actually-correct migration target, not merely "more
accurate"), and the `builderwait++` post-increment fix (exact semantics match).

**The `-ffp-contract=off` fix is logged as its own decision, D26, per IMPLEMENTER's own
recommendation** not to bury it as routine wave content — it changes what the C oracle computes
project-wide, not just for this wave. PARITY independently reproduced the root cause at the
assembly level (26.5% mismatch rate on direct A/B compilation of `dot2f`, higher than
IMPLEMENTER's own fuzz estimate) rather than taking the fuzz evidence alone — confirmed as a real,
frequently-triggered gap in the C oracle's code generation, not a rare edge case, and confirmed as
a pure fix (zero prior test expectations needed to change after applying it).

**One low-severity note accepted, no action required:** PARITY flagged that if the D24 tautology
branch (`buildRoad`) were ever reached with `trees < roadTrees`, C's `uint8_t` arithmetic would
wrap to 255 while the Swift port (using `Int`) would go negative instead — a divergence from C's
actual buggy behavior, currently unreachable per the READY-state gate. Accepted as-is; worth a
one-line note or test next time `BuilderTick.swift` is touched, not a blocking item now.

Wave 5.3b marked ✅ Complete in PLAN.md (PARITY PASS, D24 applied, D26 cross-cutting fix logged).

[TO: IMPLEMENTER] **GO for Wave 5.3c** (pillTick + forestvis). No holds.
[TO: PARITY] Ready whenever 5.3c lands. Flagging in advance: `forestvis` is new port surface (not
audited before, since it was moved here from the old 5.5b placement per D23) — worth reading the
C source directly rather than assuming it's a simple port, same as your approach elsewhere.

---

### [IMPLEMENTER] 2026-09-02 — Wave 5.3c complete: pillTick, forestvis

**Type:** build
**Phase:** 1 / Wave 5.3c
**Blocks:** nothing — Wave 5.3 (5.3a/5.3b/5.3c) is now fully complete

Executed per PLANNER's `[TO: IMPLEMENTER] GO for Wave 5.3c`. New file `Sources/BoloKit/PillTick.swift`
(`isForest`, `forestVis`, `pillTick`), a reduced oracle (`pillops.c`) for `forestvis`'s
interpolation arithmetic and the shell lead-targeting math. 26 new unit tests
(`PillTickTests.swift`), 2 new differential fuzz tests (`PillTickDifferentialTests.swift`, 3000
and 2000 iterations). Full suite: 225 BoloKitTests + 33 DifferentialTests, all green — no
regressions against the 199+31 baseline from 5.3b.

**Generalization, same pattern as 5.3a/5.3b, reported per the established precedent:**
`pilllogic(old)` takes no player parameter in C at all — it hardcodes `client.player`, called
once per tick (not in a per-connected-player loop like `shelllogic`/`builderlogic`). Its inner
"am I the closest eligible target" loop only makes sense as "every client independently runs this
with their own identity" — so `pillTick(player:old:...)` is called once per connected player,
with `j != client.player` generalizing to `j != player`. This preserves the exact tie-break quirk
already flagged in the Wave 5.1 report and now has a dedicated regression test
(`pillTickTiedDistanceBothCountAsClosest`): two players at *exactly* equal distance from a pill
both independently pass the "no one is strictly closer than me" check, since the disqualification
requires strictly-less-than, not less-than-or-equal.

**A second C-source-acknowledged precision quirk, replicated not fixed:** the shell's lead-vector
computation does `sqrtf(fabsf((SHELLVEL*SHELLVEL) - dot2f(compi, compi)))` — `SHELLVEL*SHELLVEL`
is double (a double-literal squared), so the subtraction computes in double, then narrows to
`Float` when passed to `fabsf` specifically (not `fabs`) — narrowing *before* the absolute value,
not after. C's own comment flags this: `/* fabsf is a cludge */`. Replicated exactly
(`Float(Double(shellVelocity) * Double(shellVelocity) - Double(dot2f(compi, compi)))`, then
`fabsf`, then `sqrtf`) rather than "fixing" it to `fabs`.

**A third, larger precision finding, caught only by building and fuzzing the oracle — not
assumed from reading the source:** `forestvis`'s nested `MAX(x, y)` calls (`MAX` is
`((x)>(y))?(x):(y)`) each pit a `float` variable against the double literal `0.0` in a ternary.
C's conditional operator forces both branches of a ternary to a common type, so mixing
`double`/`float` promotes the *entire* ternary — including the float branch that's actually
selected — to `double`. This cascades through all three levels of MAX-of-MAX-of-MAX nesting, so
the whole interpolation tree computes in double precision, narrowing to `Float` only once, at
`forestvis`'s own `return`. Computing it in `Float` throughout (one narrowing per `max` call,
the naive Swift-idiomatic translation) diverged from the C oracle on ~48% of broadly-random
`(fx, fy, neighbor)` inputs — confirmed by building `forestvis_oracle` in `pillops.c` and fuzzing
before writing the "final" Swift version, not after. Fixed by carrying every intermediate value
as `Double` through the full nesting and narrowing exactly once at the end.

**A test-methodology trap worth recording for future oracle work:** my first differential-test
draft for `forestVis` generated random `fx`/`fy` in `[0, 1)`, built `v = Vec2f(x: 50+fx, y:
50+fy)`, and passed the *original* `fx`/`fy` to the C oracle while letting Swift's `forestVis`
*recompute* `fx = v.x - floorf(v.x)` internally — these aren't guaranteed to be bit-identical,
since `50.0 + fx` then `- 50.0` doesn't always round-trip exactly (adding to 50 can consume low
mantissa bits that represent the fraction). This produced ~48% "mismatches" that were entirely a
test artifact, not a `forestVis` bug — indistinguishable at first glance from the real MAX-nesting
finding above, since both produced small, inconsistent-looking diffs. Resolved by having the test
re-derive `fx`/`fy` from `v` itself (matching what `forestVis` will do) before calling the
oracle, rather than reusing the pre-embedding values. Recording this because the *symptom* (small
random-looking float mismatches) looks identical whether the bug is in the port or in the test
harness, and this wave hit both flavors back to back.

`shellCollisionTest` (Wave 5.3a) is reused directly and unmodified for the pill-fired shell's
immediate-collision check — no changes needed there.

[TO: PLANNER] Wave 5.3c done and verified, commit follows this entry. **Wave 5.3 (5.3a/5.3b/5.3c,
per D23's split) is now fully complete.** Per PLAN.md's wave table, next up is Wave 5.5a
(explosionAt/superboomAt/chain/flood, droppills) unless redirected — Wave 5.4 was already retired
into 5.1/5.2a/5.3b.
[TO: PARITY] New commit to audit. Specifically: (1) `forestvis`'s double-precision MAX-nesting
finding — recommend independently confirming the ternary-type-promotion reasoning against the C
standard's conditional-operator rules, since this is a different (and more surprising) mechanism
than the FMA-contraction finding from 5.3b, not a re-run of the same bug; (2) the pilllogic→
pillTick generalization and the tied-distance regression test; (3) the `fabsf`-narrows-before-abs
replication in the shell lead-targeting math. Per the post-commit-only PARITY rule, not tagging
further action here — that's PLANNER's call.

---

### [PARITY] 2026-09-02 — Wave 5.3c audit (`d2dfc71`)
**Type:** audit
**Wave:** 5.3c
**Verdict:** FAIL (one item) — the per-player generalization of `pillTick` mutates shared per-pill
state in an order-dependent way that can silently erase legitimate cooldown progress within a
single tick. Everything else (forestVis double-precision cascade, fabsf placement, tie-break)
independently confirmed correct.

Read `pilllogic`/`forestvis`/`isforest` (client.c:5034-5126, bolo.c:152-209) against
`Sources/BoloKit/PillTick.swift`, per IMPLEMENTER's three specific requests, plus traced the
full multi-player call pattern this function is designed for (since IMPLEMENTER's own header
states it's meant to be "called once per connected player," same convention as `shellTick`/
`builderTick`).

**Confirmed correct — the two numeric/logic items specifically requested:**

1. **`forestvis`'s double-precision MAX-nesting cascade — re-derived independently against the
   C standard's conditional-operator rule (C11 §6.5.15p5: both branches of `?:` undergo the usual
   arithmetic conversions to a common type when both are arithmetic), not just accepted on fuzz
   evidence.** Every leaf ternary in `forestvis` pits a `float` operand against the double literal
   `0.0` or `1.0`, which forces that entire ternary's result type to `double` — and since the
   nested `MAX` macro's own ternary then compares two already-`double` values, the promotion
   genuinely cascades through all three nesting levels with only ONE narrowing back to `Float`, at
   the final `return`. This is a different, more surprising mechanism than 5.3b's FMA-contraction
   finding (a language typing rule, not a compiler code-gen choice) and I confirmed it against the
   standard rather than by re-running IMPLEMENTER's fuzz test. `forestVis` (`PillTick.swift:90-111`)
   correctly threads `Double` through every intermediate (`edgeX`/`edgeY`/all four corners) and
   narrows exactly once at `return Float(result)`. Also verified `isForest`'s bounds/pill/base/
   terrain checks match `isforest` exactly, including the unconditional (non-owner-filtered) base
   check and the `armour != ONBOARD` pill-deployed check.
2. **`fabsf`-narrows-before-`abs` replication.** Confirmed C computes
   `(SHELLVEL*SHELLVEL) - dot2f(...)` in double (double-literal-squared triggers double promotion
   for the whole subtraction) and only narrows to `Float` at the `fabsf` call itself — narrowing
   before the absolute value, per the source's own `/* fabsf is a cludge */` comment. `PillTick.swift:177`
   (`Float(Double(shellVelocity) * Double(shellVelocity) - Double(dot2f(compi, compi)))`, then
   `fabsf`) reproduces this exactly.

**Confirmed correct — the tie-break generalization's mechanics in isolation:** the strict
less-than disqualification (`jDist < mag`, not `<=`) is ported correctly, and the two reset paths
(outer-guard-false → reset; in-range-but-disqualified → reset) vs. the one no-reset path
(out-of-range, left untouched — no `else` at that nesting level in C) all match `pilllogic`
exactly, case for case.

**FINDING (HIGH) — the per-connected-player sweep mutates a SHARED `pills[i].counter` field,
and the final value after one tick's sweep is order-dependent on which player is evaluated last
for that pill, not on which player is actually the closest hostile target.**

In the original, `pilllogic()` hardcodes `client.player` and is run once **per human's own client
process** — each process only ever mutates ITS OWN LOCAL replica of `client.pills[i].counter`.
Because every process runs the identical deterministic math, only the client whose own tank is
the genuinely-closest eligible hostile target ever sees its local counter climb toward firing;
every other client's local copy perpetually resets to 0 (either because the pill isn't hostile
from their alliance's perspective, or because someone else is closer) — but that's harmless
**because it's a private, un-synced local variable that never influences anyone else's copy or
the actual shot decision**, which is made unilaterally by whichever client fires and broadcasts
the resulting shell.

`pillTick`'s generalization collapses these N independent, non-interacting local variables into
ONE shared field (`state.pills[i].counter`) and calls the same reset/increment logic once per
connected player, in sequence, within the same tick — which is not equivalent. Concretely: if the
driver calls `pillTick(player: 0, ...)`, `pillTick(player: 1, ...)`, …, `pillTick(player: N, ...)`
in index order every tick (the stated design, matching `shellTick`/`builderTick`'s convention),
then for a hostile pillbox with a genuinely-closest hostile attacker at some index *k*, **every
other connected, non-dead player's call that tick — whether they're allied to the pill's owner
(fails the outer guard → reset to 0) or hostile-but-farther (fails the disqualification check →
reset to 0) — unconditionally resets `state.pills[i].counter` to 0 regardless of what the target's
own call just did.** If any such player has an index greater than *k*, their call runs after the
target's and wipes out the increment the target's call just made, in the very same tick. Across a
full tick's sweep, the pill's final counter value ends up reflecting whichever connected player
happens to be processed *last* for that pill, not "one tick closer to firing at the real target."
In a typical multi-tank engagement (several players near one pillbox, at most one truly eligible
attacker), this would make the counter oscillate near 0 far more often than intended, extending —
possibly indefinitely, in the worst ordering — how long it takes a pillbox to fire, or in other
orderings letting it fire prematurely if `speed` is reached during a lucky ordering window before
being reset. Either way this is an observable gameplay-timing divergence from the original, not
just an internal-consistency nicety.

**This gap was not caught by the existing test suite because no test exercises the actual
intended multi-player-per-tick call pattern.** `pillTickTiedDistanceBothCountAsClosest`
(`PillTickTests.swift:227-243`) calls `pillTick(player: 0, ...)` then **manually resets
`state.pills[0].counter = 0` before calling `pillTick(player: 1, ...)`** — sidestepping exactly
the interaction in question rather than testing it. `pillTickAlliedCompetitorDoesNotDisqualify`
only ever calls `pillTick` for the single hostile player (index 2), never for the allied players
also present in `state.players`, so it doesn't exercise their calls resetting the shared counter
either. I did not find a test anywhere in `PillTickTests.swift`/`PillTickDifferentialTests.swift`
that calls `pillTick` for every connected player in the same tick and checks the pill's counter
afterward.

**Recommend, for PLANNER to route to IMPLEMENTER:** `pillTick` needs a driver-level or
function-level fix before Wave 5.3 can be called fully closed — options include (a) computing
each pill's single closest-eligible-hostile target once per tick across all connected players
first, then applying exactly one increment/reset/fire decision per pill (closer to what the
distributed model's *emergent* behavior actually is), or (b) some other restructuring that avoids
a shared field being reset by every non-target evaluator in the same sweep. Whichever fix is
chosen, recommend a new differential/unit test that calls `pillTick` for every connected player
in realistic index order within one simulated tick (not resetting counter by hand in between) and
asserts the counter reflects the closest hostile's progress, not the last-processed player's
verdict.

[TO: PLANNER] Wave 5.3c: forestVis and the fabsf/tie-break items are all confirmed correct — solid
work, independently re-derived against the C standard, not just trusted. But I'm marking this
**FAIL, not PASS-with-findings**, on the shared-counter ordering issue above: it's a real
gameplay-timing divergence from the original in the exact multi-player scenario this
generalization exists to handle, and it's currently untested. Recommend holding Wave 5.3's
"fully complete" status and sending this back to IMPLEMENTER before proceeding to Wave 5.5a, since
5.5a's mine-cascade work doesn't depend on this being fixed first but a known-broken pillbox timing
model shouldn't sit uncorrected under a "✅ Complete" wave.
[TO: IMPLEMENTER] See the FINDING above — the per-connected-player sweep architecture for
`pillTick` needs a fix for the shared-counter-mutation-order problem, plus a test that actually
exercises calling it for multiple players in one tick without manually resetting state in between.

---

### [IMPLEMENTER] 2026-09-02 — Wave 5.3c FAIL fixed: pillTick rewritten as a single per-tick election

**Type:** fix
**Phase:** 1 / Wave 5.3c (re-opened)
**Blocks:** nothing — re-closes Wave 5.3c pending PARITY re-audit

Confirmed PARITY's diagnosis by independently re-tracing the exact call sequence against the
shipped code before touching anything: the per-player-loop design mutated one shared
`state.pills[i].counter`, so a bystander (allied, or hostile-but-farther) processed *after* the
genuine target in player-index order unconditionally reset the shared counter that same tick,
regardless of what the target's own call had just done. Agreed this is a real gameplay-timing
divergence, not a nicety.

**Rewrote `pillTick`'s signature and body entirely** (`Sources/BoloKit/PillTick.swift`) —
`pillTick(player:old:state:...)` → `pillTick(state:oldTankPositions:...)`, called **once per
tick for the whole state**, not once per player. Per pill: gather every alive-connected player,
partition into eligible (non-allied) and in-range, elect the argmin-mag set (ties survive
together), apply exactly one increment/freeze/reset/fire decision, and — for ties — fire at
*every* member of the elected set rather than an arbitrary winner (tied players' independent
replicas move in lockstep in the distributed model, so a shared counter reaching threshold and
firing at all of them is the faithful reconstruction PARITY's own option (a) pointed toward, not
an approximation of it). Net effect is also `O(pills × players)` for the whole tick, down from the
old code's `O(pills × players²)` (the closest-check inner loop re-ran once per outer player call).

**A second, more subtle case surfaced while rewriting, not present in PARITY's report:** C's
`pilllogic` early-returns entirely if `client.player` is dead — meaning a dead client's private
counter replica is simply never touched that tick (frozen), which is a *different* outcome from
"every alive candidate explicitly fails the alliance check" (reset, since each such client's
process does run and does zero its own counter). Collapsing both into one "no valid candidate →
reset" case, as my first fix attempt did, would have been wrong for the "nobody's alive at all"
case. `pillTick` now distinguishes them: `aliveConnected.isEmpty` → freeze (no client is running
any code); `aliveConnected` non-empty but `eligible` empty → reset (every existing client's own
process explicitly zeroes its counter). New test
(`pillTickNoAliveConnectedPlayerFreezesCounter`) pins the freeze case; the pre-existing allied-pill
test was adapted to `pillTickAllAliveCandidatesAlliedResetsCounter` to pin the reset case
separately.

**Two new regression tests reproduce PARITY's exact failure mode:**
`pillTickMultiPlayerSweepDoesNotEraseClosestTargetsProgress` calls `pillTick` once per tick across
three simulated ticks with a farther hostile bystander present throughout, asserting the counter
climbs monotonically (1, 2, 3) rather than oscillating, then fires only at the real target;
`pillTickMultiPlayerSweepAlliedBystanderDoesNotAffectRealTarget` does the same with an allied
bystander instead. Both would have failed under the old per-player-loop code (a bystander at a
higher index than the target would have reset the shared counter every tick).

**Incidental discovery while rewriting the test fixtures — `testAlliance` has no self-alliance
special case (already known from Wave 5.2b), which surfaces here too:** a pill's own owner, if
they don't have their own self-bit set in their alliance mask, is technically "eligible" as a
target for their own pill. This doesn't affect any test's outcome (the owner fixtures are always
either explicitly self-allied or positioned out of range), but I flagged it directly in the
`pillTickFiredShellUsesOwnerNotTargetPlayer` test's comment rather than silently relying on
position to mask it, since a future test author placing an owner near their own pill without
noticing this would get a confusing result.

225 → 227 unit tests (26 old pillTick tests replaced by 28 new ones), 33 differential tests
unchanged (`forestVis`/shell-lead-targeting math untouched — PARITY confirmed both correct).

[TO: PLANNER] Wave 5.3c's shared-counter FAIL is fixed, commit follows this entry. Wave 5.3
(5.3a/5.3b/5.3c) should be re-closeable once PARITY re-audits.
[TO: PARITY] New commit to audit. Specifically: (1) the election/tie-fire-at-all redesign against
your own option (a)/(b) framing; (2) the freeze-vs-reset distinction for "no alive players" vs
"alive but all allied," which your report didn't call out but I found necessary while fixing the
main issue; (3) the two new multi-player-per-tick regression tests actually exercise the failure
mode you described, not a restated version of it. Per the post-commit-only rule, not tagging
further action here — that's PLANNER's call.

---

### [PARITY] 2026-09-02 — Wave 5.3c FAIL re-audit (`03d56b3`): PASS, FAIL resolved

**Type:** audit
**Wave:** 5.3c (re-close)
**Verdict:** PASS. The shared-counter order-dependence is fixed and the fix is correct against C,
not merely against my own report's framing. Wave 5.3 (5.3a/5.3b/5.3c) can be marked fully complete.

Re-read `pilllogic` (client.c:5034) end to end against the rewritten `pillTick`
(`Sources/BoloKit/PillTick.swift`), specifically checking whether the once-per-tick election model
is actually equivalent to running the pairwise "am I disqualified by someone else" comparison
independently for every possible subject — not just whether it reads plausibly.

**Election model — verified equivalent to the pairwise original, not just re-styled.** C's inner
loop disqualifies a subject if some other player `j` is (a) alive/connected/hostile-eligible, (b)
strictly closer (`mag2f(j) < mag`), AND (c) `j` itself satisfies the range/visibility test
(`magJ <= 2.0 || forestvis(j) > 0.25`) — note C does **not** re-check `magJ <= 8.0` for `j`
explicitly, but this is implied for free since `magJ < mag <= 8.0`. The rewrite's `inRange` list
requires every candidate (including whoever ends up disqualifying someone else) to independently
pass that same combined range/visibility test before they can compete at all; `closestSet` is then
the argmin over that filtered pool. Since C's disqualifying player must *also* pass this test to
count, and the rewrite excludes anyone who fails it from `inRange` before computing the minimum,
a player who's geometrically closer but fails their own visibility check correctly does NOT
suppress the real target in either version — confirmed by hand-tracing both directions (a
non-passing closer player can't win the argmin since they're excluded from `inRange`, and can't
disqualify anyone either, matching C's requirement that the disqualifier itself pass the test).

**Freeze-vs-reset distinction — independently checked, and it's real, not overengineering.**
Confirmed `pilllogic`'s very first line (`if (client.players[client.player].dead) SUCCESS;`) is
an unconditional early return keyed to *that specific replica's own* player being dead — it says
nothing about other players. In the distributed model, a replica only mutates its own local
counter when its own owning human is alive; a dead-or-disconnected human's replica does nothing at
all that tick (freeze). The only way the merged reconstruction can be certain **nothing** would
have mutated the shared counter is if literally every connected player is dead (`aliveConnected.isEmpty`)
— if even one alive connected player exists, their own replica runs and produces either an
increment or a reset, so "some alive player exists" always yields a real, non-frozen outcome
(reset, if no eligible hostile among them). This is a correct and necessary refinement beyond what
my original FAIL report specified — I only flagged the ordering problem, not this freeze/reset
split, and it's good that IMPLEMENTER found it while fixing rather than collapsing both into one
case.

**Tie-fire-at-every-member design — accepted as a faithful reconstruction, not an approximation.**
Two tied-closest hostile players' independent replicas run identical deterministic math against
identical (eventually-synced) inputs and would cross the firing threshold on the same tick in the
distributed model — so both actually do fire in the original multiplayer game, not just one
arbitrary winner. Firing at every member of `closestSet` (each with their own independently
computed shell, since direction/velocity differ by target even when magnitude ties) is correct.

**New regression tests actually exercise the failure mode, confirmed by re-deriving expected
values, not just reading assertions.** For
`pillTickMultiPlayerSweepDoesNotEraseClosestTargetsProgress` (target at distance 1.0, hostile
bystander at distance ~5, `speed: 4`): re-derived by hand that under the OLD per-player-loop code,
calling `pillTick(player: 0)` then `pillTick(player: 1)` each tick would have had the bystander's
call (index 1, farther, still "eligible" but disqualified by the closer target) reset the shared
counter to 0 immediately after the target's own call incremented it — net effect frozen at 0
forever, never reaching `speed: 4` to fire. Under the new code this correctly climbs 1, 2, 3, then
fires only at player 0 on tick 4. Confirms this test would genuinely have caught the original bug,
not merely restated it. Spot-checked the allied-bystander variant the same way — same conclusion.

**Also confirmed the two smaller items from IMPLEMENTER's own request:** the tie-fire targeting
math correctly indexes `oldTankPositions[player]` per elected target (not a single shared `old`),
matching C's `pilllogic(old)` where `old` is always the calling replica's *own* prior position —
this is actually a cleaner generalization than the pre-fix version's single-`old` signature ever
allowed, since it now supports multiple simultaneous targets each with their own correct
lead-velocity term. No stale references to the old `pillTick(player:old:...)` signature remain
anywhere in `Sources/`/`Tests/`.

No new divergences found. Wave 5.3c: PASS. Wave 5.3 (5.3a/5.3b/5.3c) is fully closed.

[TO: PLANNER] Wave 5.3c's FAIL is resolved — verified the election-model rewrite is actually
equivalent to the original pairwise disqualification logic (not just plausible-looking), the
freeze-vs-reset split is a real and necessary distinction I hadn't called for but is correct, and
the tie-fire-at-all design is the faithful reconstruction rather than an approximation. Both new
regression tests genuinely reproduce the original failure mode (re-derived by hand what the old
code would have done — confirmed frozen-at-zero — versus the new code's correct monotonic climb).
Recommend marking Wave 5.3 fully ✅ Complete in PLAN.md and clearing this off Wave 6 pre-brief
concerns. No action needed from IMPLEMENTER — clear to proceed to Wave 5.5a.

---

### [PLANNER] 2026-09-02 — Wave 5.3 fully closed; FAIL/fix cycle logged as D27; GO issued for Wave 5.5a
**Type:** planning
**Phase:** 1 / Wave 5.3 → 5.5a
**Blocks:** nothing

Reviewed the full Wave 5.3c cycle end to end before signing off — not just the final PASS. PARITY's
original FAIL (`d2dfc71`) was real: `pillTick`'s per-connected-player loop mutated one shared
`state.pills[i].counter`, so any bystander processed after the genuine target in the same tick
unconditionally reset the counter the target's own call had just incremented — a real gameplay-
timing divergence (pillbox fire delay driven by call order, not by which player was actually
closest), and untested at the time (no test exercised a same-tick multi-player sweep). IMPLEMENTER's
fix (`03d56b3`) rewrote `pillTick` as a single per-tick election over all players — argmin over the
eligible/in-range pool, ties survive and all fire, plus a freeze-vs-reset distinction PARITY hadn't
called for but is independently correct. PARITY's re-audit verified the election model against C's
pairwise logic by hand-tracing both directions (not just re-reading it as plausible), verified the
freeze/reset split against `pilllogic`'s actual early-return semantics, and re-derived by hand what
the *old* code would have done on the new regression tests' fixtures (confirmed: frozen at 0
forever) to confirm the tests genuinely reproduce the original failure, not just restate it. That's
a properly closed loop, not a rubber-stamped fix.

**Logged as D27, not just closed as a bug-fix note**, because the underlying shape — N independent
per-replica mutations in C collapsing to one shared field in the merged sim — is going to recur.
Wave 5.5a/5.5b's mine-chain/flood/explosionTick work has the same shape (a chain list built and
drained across what were originally per-client replicas). Flagging this now so 5.5a is designed as
an election/single-pass model from the start rather than risking the same FAIL/fix cycle twice.

Wave 5.3 (5.3a/5.3b/5.3c) marked ✅ fully complete in PLAN.md.

**Confirmed ready for the next wave — yes, Wave 5.5a** (Wave 5.4 was already retired per D23; 5.5a
is explosionAt/superboomAt/chain/flood mine-detonation cascade + droppills pill-scatter placement,
per D22's split). Nothing else is outstanding: Q14 (explosions-list attribution) and Q15/D25
(WinBolo reference policy) are both scoped to Wave 6, not blocking here.

[TO: IMPLEMENTER] **GO for Wave 5.5a.** Read D27 before starting — design the chain/flood state as
a single per-tick pass over all affected entities rather than a per-caller loop that mutates shared
lists, given what Wave 5.3c's FAIL just cost.
[TO: PARITY] Heads-up for whenever 5.5a lands: worth checking early whether the chain/flood
implementation follows D27's election/single-pass shape, rather than only catching it after a full
audit cycle like last time.

---

### [PLANNER] 2026-09-02 — New standing policy: artifact/test maintenance (D28)
**Type:** planning
**Phase:** 1 / project-wide
**Blocks:** nothing — standing policy, effective immediately

Jerod asked that all project artifacts, tests included, be maintained going forward — no
preference on the specific mechanism, so I picked the combination with the most teeth rather than
the lightest one.

**D28, logged in PLAN.md:** no project artifact — docs, source, or tests — shrinks without an
explicit, on-record replacement. In practice:

1. IMPLEMENTER's wave-completion reports already state before/after test counts (every report so
   far has). Going forward, any DECREASE in a wave's test count vs. the prior wave's total needs
   the reason stated explicitly, not left for PLANNER/PARITY to notice by subtracting numbers.
2. PARITY's audits already check for coverage gaps case by case (e.g. flagging when a fix's test
   doesn't actually exercise the failure mode, as with 5.3c). This is now a standing checklist
   item rather than incidental — worth a line in future audit reports even when the answer is
   "no gap found."
3. The wave status table in PLAN.md now carries a running test count per wave (backfilled for
   5.1 through 5.3c) so a regression is visible at a glance across the whole project's history,
   not just within one wave's own report.
4. Wave 5.8's docs/archive pass (Q13) is extended: `archive.md` entries for Wave 5+ should note
   test-count deltas and the reason for any decrease, same granularity already used for code
   findings — not just compress the prose, also preserve why coverage changed shape.

This doesn't require anything different starting today — the pattern was already being followed
(5.3c's 26→28 replacement is exactly this policy in action, just not yet named). It just makes the
expectation explicit and durable rather than implicit good practice.

[TO: IMPLEMENTER] No change to how you're already reporting — keep stating before/after test
counts, and call out any decrease with its reason explicitly per D28.
[TO: PARITY] Add "no artifact/coverage silently shrank" as an explicit standing check in future
audits, per D28 — a one-line confirmation is enough when there's nothing to flag.

---

### [IMPLEMENTER] 2026-09-02 — Wave 5.5a complete: explosionAt, superboomAt, chain, flood, droppills

**Type:** build
**Phase:** 1 / Wave 5.5a
**Blocks:** nothing — unblocks Wave 5.5b (explosionTick, drains the chain list this wave builds)

Executed per PLANNER's GO, with D27 read first as instructed. New file `Sources/BoloKit/MineChain.swift`
(`clearTerrain`, `dropPillSearch`, `dropPills`, `floodTest`, `floodAt`, `flood`, `chainAt`, `chain`,
`explosionAt`, `superboomAt`, plus a private `applySplashDamage` shared by the last two). New
`GameState` fields `chains`/`floods` (ring buffers, 7 and 13 slots). Six new `Physics.swift`
constants. **Test count per D28: 227 → 257 BoloKitTests (+30, all additions), 33 → 33
DifferentialTests (unchanged — no new oracle needed, confirmed below). No decrease anywhere.**

**D27 checked explicitly against the actual shipped code, not just asserted from the plan:**
`chainAt`/`floodAt`/`floodTest` only append to ring-buffer slots (order-independent); `chain()`/
`flood()` are already single global no-player-parameter functions in C, structurally immune to
pillTick's per-caller-loop shape; `explosionAt`/`superboomAt` mutate their own specific tile
(idempotent on repeat); `dropPills` re-checks `findPill`/`findBase` per candidate square. Re-
verified this reasoning against the finished code, not just the pre-implementation plan — nothing
changed the analysis during implementation.

**No new C oracle needed, confirmed rather than assumed:** grepped the finished file for
`Double`/`CGFloat`/`Double.pi`/`import Foundation` — zero hits. Every function here is terrain-
switch/list/ring-buffer bookkeeping; the only float content (`mag2f(tank − point) ≤ radius`)
reuses the already-verified `mag2f`.

**A real crash risk caught before it shipped, not after:** C's ring-buffer write-slot index is
`(server.ticks - 1) % (N + 1)` where `server.ticks` is `uint32_t` — at `ticks == 0` (game start)
this underflows to `0xFFFFFFFF`, well-defined wrapping arithmetic in C. `GameState.ticks` is
`UInt64`; a literal `state.ticks - 1` in Swift traps at `ticks == 0` instead of wrapping, and
`&-` on the full `UInt64` range wraps to a *different* value than C's 32-bit wrap would (mod-7/13
of `UInt64.max` vs `UInt32.max` aren't guaranteed equal). Added a `writeSlot()` helper that
narrows to `UInt32` *before* the wrapping subtraction, reproducing C's exact wrapped value. Caught
by reasoning through the type before writing a single test, not by a test failure.

**A closure-threading gap found while implementing, not in the original plan:** `chainAt`/
`floodAt`/`chain`/`flood` only forwarded `onDropPills` to `explosionAt` in my first draft —
but `explosionAt`'s splash-damage escalation can call `smallboom`/`superboom` (Wave 5.2b), which
themselves need `onMineExplosion`/`onSuperboomTerrain`. Fixed by threading all three closures
through the full call chain (`chain`/`flood` → `chainAt`/`floodAt` → `explosionAt`); without this,
a local tank caught in a chain-reaction blast severe enough to trigger its own superboom would have
silently no-opped that superboom's own terrain effects instead of recursing correctly.

**A debugging detour worth recording, since it cost real time chasing the wrong hypothesis
first:** the new tests initially crashed ("Index out of range") in a way that looked exactly like
a data race — different "last-started" test shown each run, present under `--parallel` and
absent-seeming when isolated. Spent real effort testing the race hypothesis (`--no-parallel`,
individual-test isolation) before it actually *disproved* itself: `--no-parallel` still crashed,
deterministically, on a *specific* test every time. The real cause was two independent test-
fixture bugs, not a race at all: (1) `killBuilder()` (Wave 5.2b, already shipped) picks a random
respawn via `arc4random_uniform(state.starts.count)` then indexes `state.starts[start]` — my
`makeState` helper never populated `starts`, so any test reaching an active builder-kill crashed
on an empty array; (2) four tests used `players: []` while calling `explosionAt`/`superboomAt`
with a non-self-caused `player`, which unconditionally calls `killSquareBuilder`/
`killPointBuilder` — both index `state.players[state.localPlayer]` regardless of whether the array
is empty. Multiple *different* tests shared one or the other bug, so under parallel scheduling
whichever one happened to run last before the crash printed varied — real nondeterminism in
*which* symptom surfaced first, but each underlying bug was fully deterministic once isolated.
Fixed by populating `starts` in the shared fixture helper and giving the four affected tests a
real connected player. Flagging the debugging path itself, not just the fix, since the "looks like
a race, isn't" pattern is worth recognizing faster next time it comes up.

**Deferred, as flagged in the plan, not silently skipped:** the existing `onMineExplosion`/
`onSuperboomTerrain` closures shipped in `TankLocalTick.swift`/`ShellTick.swift`/
`BuilderTick.swift` are still unwired no-op defaults — nothing calls them with a real
implementation yet. Wiring them to these new functions requires threading the correct causer
through three already-shipped files, which only a real top-level tick driver (Wave 6) can supply
with full context.

[TO: PLANNER] Wave 5.5a done and verified, commit follows this entry. Proceeding to Wave 5.5b
(`explosionTick`, draining the particle list this wave's `state.explosions`/per-player lists feed)
next unless redirected.
[TO: PARITY] New commit to audit. Specifically: (1) the D27 structural analysis above, checked
against the finished code; (2) the `writeSlot` `uint32_t`-narrowing fix — worth confirming the
wraparound value independently, same rigor as the D26 fp-contract finding; (3) the smallboom-vs-
superboom damage-check nesting asymmetry (independent top-level `if` for smallboom, nested inside
the particle gate for superboom) — verify against `recvsrsmallboom`/`recvsrsuperboom` directly,
since it's easy to assume symmetry that isn't actually there. Per the post-commit-only rule, not
tagging further action here — that's PLANNER's call.
