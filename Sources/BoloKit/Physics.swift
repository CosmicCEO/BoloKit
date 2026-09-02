
// MARK: - Physics Constants
//
// Ported verbatim from Reference/c/bolo.h.
//
// D18: All physics values are Float (32-bit), matching the C reference code's
// use of float for Vec2f, tank position, trig, and physics calculations.
// Using Double here would create a type mismatch at every Wave 5 call site.

/// Simulation ticks per second. The fundamental time step of the engine.
public let ticksPerSec: Float = 50

/// Maximum tank speed on road or boat terrain (squares per second).
public let boatMaxSpeed: Float = 3.125

/// Maximum tank speed on road terrain (= boatMaxSpeed).
public let roadMaxSpeed: Float = boatMaxSpeed

/// Maximum tank speed on grass terrain (squares per second).
/// Ratio to road: 75%
public let grassMaxSpeed: Float = 2.34375

/// Maximum tank speed on forest terrain (squares per second).
/// Ratio to road: 37.5%
public let forestMaxSpeed: Float = 1.171875

/// Maximum tank speed on rubble/swamp/crater/river terrain (squares per second).
/// Ratio to road: ~18.75%
public let rubbleMaxSpeed: Float = 0.5859375

/// Number of ticks required for a tank at boatMaxSpeed to decelerate to zero.
public let ticksForCompleteStop: Float = 64

/// Tank linear acceleration (squares per second²).
/// = boatMaxSpeed × ticksPerSec / ticksForCompleteStop = 2.44140625
public let accel: Float = boatMaxSpeed * ticksPerSec / ticksForCompleteStop

/// Tank angular acceleration (radians per second²).
/// C value: 12.5663706143592 (≈ 4π). Stored as Float per D18.
public let angularAccel: Float = 12.5663706143592

/// Maximum LGM (builder) movement speed. Equal to roadMaxSpeed.
public let builderMaxSpeed: Float = roadMaxSpeed

/// Parachute descent speed. Equal to rubbleMaxSpeed.
public let parachuteSpeed: Float = rubbleMaxSpeed

// MARK: - Game Object Constants
//
// Ported verbatim from Reference/c/bolo.h (Wave 5.0).

/// LGM (builder) collision radius, in squares.
public let builderRadius: Float = 0.125

/// Tank collision radius, in squares.
public let tankRadius: Float = 0.375

/// Shell travel speed, squares per second.
public let shellVelocity: Float = 7.0

/// Maximum shell range, in squares.
public let maxShellRange: Float = 7.0

/// Tank max turn rate on a boat (radians per second).
public let maxAngularVelocity: Float = 2.5

/// Shore push force applied to a boat near land (squares per second, per tick).
public let pushForce: Float = 1.5625

/// Explosion "kick" force imparted to a destroyed tank/builder.
public let kickForce: Float = 3.125

/// Per-tick decay of kickspeed after an explosion (squares per second²).
public let kickSpeedDecay: Float = 12.0

/// Ticks an explosion particle animates for.
public let explosionTicks: Int = 24

/// Ticks after death before detonation (superboom/smallboom).
public let explodeTicks: Int = 45

/// Ticks after death before a respawn attempt begins.
public let respawnTicks: Int = 150

/// Maximum shells a tank can carry.
public let maxShells: Int = 40

/// Maximum mines a tank can carry.
public let maxMines: Int = 40

/// Maximum armour a tank can carry.
public let maxArmour: Int = 40

/// Maximum trees a builder can carry.
public let maxTrees: Int = 40

/// Trees required to build a road tile.
public let roadTrees: Int = 2

/// Trees required to build a wall tile.
public let wallTrees: Int = 2

/// Trees required to build a boat crossing.
public let boatTrees: Int = 20

/// Trees required to build a pillbox.
public let pillTrees: Int = 4

/// Maximum connected players.
public let maxPlayers: Int = 16

/// Maximum player start positions on a map.
public let maxStarts: Int = 16

/// Pill `armour` sentinel meaning "carried by a builder" (not a real armour value).
public let pillOnboard: UInt8 = 0xff

/// Owner sentinel meaning "no player" / neutral.
public let playerNeutral: UInt8 = 0xff

/// Sentinel meaning "no pill" for lookups that return an index.
public let noPill: UInt8 = 0xff

/// Minimum armour a base can be built with.
public let minBaseArmour: Int = 5

/// Ticks between pillbox reload-speed cooldown steps.
public let coolPillTicks: Int = 32

/// Counter-points between base resource replenish steps (counter increments by player count per tick).
public let replenishBaseTicks: Int = 600

/// Used in the tree-growth best-of iteration count.
public let treesPlantRate: Int = 10

/// Tree-growth best-of window; should stay a multiple of treesPlantRate * ticksPerSec.
public let treesBestOf: Int = 4200

/// Pillbox reload-speed cap in ticks (higher = slower fire rate).
public let maxTicksPerShot: Int = 100

/// Maximum base armour.
public let maxBaseArmour: Int = 90

/// Maximum base shells.
public let maxBaseShells: Int = 90

/// Maximum base mines.
public let maxBaseMines: Int = 90

// MARK: - Wave 5.2b constants (tanklocallogic / enter)

/// Ticks of standing on river terrain (below boat speed, off any pill/base)
/// before a resource is drained.
public let drainTicks: Int = 15

/// Ticks per point of armour transferred while refuelling at a base.
public let refuelArmourTicks: Int = 46

/// Ticks per transfer of shells while refuelling at a base.
public let refuelShellsTicks: Int = 7

/// Ticks per transfer of mines while refuelling at a base.
public let refuelMinesTicks: Int = 7

/// Minimum base shells required before a tank may draw from it.
public let minBaseShells: Int = 1

/// Minimum base mines required before a tank may draw from it.
public let minBaseMines: Int = 1

/// Minimum settable shell range.
public let minRange: Float = 1.0

/// Radius (squares) within which a point-based explosion kills a builder.
public let explosionRadius: Float = 0.5

/// Ticks a tank must wait between shots. C: `TICKSPERSEC/SHELLRATE`, integer
/// division on the int macros (50/4 = 12), not the Float `ticksPerSec`.
public let shellFireThresholdTicks: Int = 12

// MARK: - Wave 5.3a constants (shellTick / shellCollisionTest / applyDamage)

/// Armour lost by a tank hit by a shell.
public let shellDamage: Int = 5

/// Fastest a pill's reload interval (`Pill.speed`) can be heated to —
/// the floor `MAX()` clamps against after halving. C: `MINTICKSPERSHOT`.
public let minTicksPerShot: Int = 6

// MARK: - Wave 5.3b constants (builderTick / buildercollision)

/// Ticks a builder spends in `.wait` (mid-build, network-ack placeholder in
/// C) before giving up and returning to the tank regardless of outcome.
public let builderBuildTime: Int = 20

/// Trees yielded by harvesting one forest/mined-forest tile. C's own name
/// (`FORRESTTREES`, sic — the misspelling is in bolo.h, not this port).
public let forestTreeYield: Int = 4

/// Maximum pill armour a builder can build/repair up to (distinct from
/// `maxBaseArmour` — pills cap much lower). C: `MAXPILLARMOUR`.
public let maxPillArmour: Int = 15
