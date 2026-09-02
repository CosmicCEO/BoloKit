// MARK: - Game Object Model (Wave 5.1)
//
// Ported from the struct definitions scattered across Reference/c/bolo.h
// and Reference/c/client.h. Field names use idiomatic Swift camelCase
// rather than mirroring C's flat lowercase names — these are in-memory
// simulation types, not binary-format structs (contrast BMapRun etc. in
// BMap.swift, which intentionally mirror the on-disk field names).

// MARK: - Pill

public struct Pill: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// 0xff (`pillOnboard`) means carried by a builder, not present on the map.
    public var armour: UInt8
    /// 0xff (`playerNeutral`) means unowned.
    public var owner: UInt8
    /// Reload interval in ticks — higher is slower/calmer. Not armour.
    public var speed: UInt8
    /// Ticks since the pill last fired (or was disqualified/reset). Mirrors
    /// C's `client.pills[i].counter` — the CLIENT-side fire-cadence tally
    /// `pillTick`/`pilllogic()` counts up toward `speed` before shooting.
    /// **Not** the same counter as `coolCounter` below — see that field's
    /// doc comment for why they had to be split (Wave 5.7 / D27).
    public var counter: UInt8
    /// Ticks since the pill's reload interval last degraded. Mirrors C's
    /// `server.pills[i].counter` — the SERVER-side cooldown tally that
    /// `coolPills` (Wave 5.7, `GrowTrees.swift`) counts up toward
    /// `coolPillTicks` before incrementing `speed`. In real distributed
    /// play `client.pills[]` and `server.pills[]` are separate array
    /// instances sharing one struct *definition*, so their `counter`
    /// fields are independent memory; this port merges every player's
    /// view into one `GameState`, so reusing a single field here would be
    /// exactly the D27 shared-per-tick-state hazard (two independent
    /// roles silently overwriting each other's tally every tick, since
    /// `pillTick` resets `counter` far more often than every 32 ticks).
    /// Split into its own field instead of reusing `counter`.
    public var coolCounter: UInt8

    public init(
        x: UInt8, y: UInt8, armour: UInt8, owner: UInt8, speed: UInt8, counter: UInt8,
        coolCounter: UInt8 = 0
    ) {
        self.x = x
        self.y = y
        self.armour = armour
        self.owner = owner
        self.speed = speed
        self.counter = counter
        self.coolCounter = coolCounter
    }

    public var isOnboard: Bool { armour == pillOnboard }
    public var isArmed: Bool { armour != pillOnboard && armour > 0 }
    public var isDead: Bool { armour != pillOnboard && armour == 0 }
}

// MARK: - Base

public struct Base: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    public var armour: UInt8
    /// 0xff (`playerNeutral`) means unowned.
    public var owner: UInt8
    public var shells: UInt8
    public var mines: UInt8
    /// Counter-points toward the next replenish event; increments by the
    /// connected-player count per tick (not a flat +1), so this must hold
    /// up to `replenishBaseTicks(600) + maxPlayers(16) - 1 = 615`.
    public var counter: UInt16

    public init(
        x: UInt8, y: UInt8, armour: UInt8, owner: UInt8, shells: UInt8, mines: UInt8, counter: UInt16 = 0
    ) {
        self.x = x
        self.y = y
        self.armour = armour
        self.owner = owner
        self.shells = shells
        self.mines = mines
        self.counter = counter
    }
}

// MARK: - Start

public struct Start: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// 0–15; multiply by (π/8) for radians (direction toward land from this start).
    public var dir: UInt8

    public init(x: UInt8, y: UInt8, dir: UInt8) {
        self.x = x
        self.y = y
        self.dir = dir
    }
}

// MARK: - Shell

public struct Shell: Hashable, Sendable {
    public var point: Vec2f
    public var dir: Float
    public var range: Float
    /// Player index, or `playerNeutral` for a shell with no attributable owner.
    public var owner: UInt8
    public var boat: Bool
    public var pill: Bool

    public init(point: Vec2f, dir: Float, range: Float, owner: UInt8, boat: Bool, pill: Bool) {
        self.point = point
        self.dir = dir
        self.range = range
        self.owner = owner
        self.boat = boat
        self.pill = pill
    }
}

// MARK: - Explosion (particle effect)

public struct Explosion: Hashable, Sendable {
    public var point: Vec2f
    /// Removed once `counter > explosionTicks (24)` — 25 displayed frames.
    public var counter: Int

    public init(point: Vec2f, counter: Int = 0) {
        self.point = point
        self.counter = counter
    }
}

// MARK: - BuilderStatus / BuilderTask
//
// Raw values pinned explicitly to match the C enum order in bolo.h.

public enum BuilderStatus: Int, Hashable, Sendable {
    case ready = 0
    case goto = 1
    case work = 2
    case wait = 3
    case `return` = 4
    case parachute = 5
}

public enum BuilderTask: Int, Hashable, Sendable {
    case doNothing = 0
    case getTree = 1
    case buildRoad = 2
    case buildWall = 3
    case buildBoat = 4
    case buildPill = 5
    case repairPill = 6
    case placeMine = 7
}

// MARK: - DominationType
//
// C's `client.game.domination.type` (Reference/c/bolo.h) — sub-mode of the
// only top-level game type this codebase ever implements (`kDominationGameType`;
// C's other top-level types — CTF/KOTH/Ball/Body — hit `assert(0)` in
// `spawn()` and were never finished in the reference source).

public enum DominationType: Sendable {
    case open
    case tournament
    case strict
}

// MARK: - InputFlags

public struct InputFlags: OptionSet, Sendable {
    public let rawValue: UInt32
    public init(rawValue: UInt32) { self.rawValue = rawValue }

    public static let accel = InputFlags(rawValue: 0x0000_0001)  // ACCELMASK
    public static let brake = InputFlags(rawValue: 0x0000_0002)  // BRAKEMASK
    public static let turnL = InputFlags(rawValue: 0x0000_0004)  // TURNLMASK
    public static let turnR = InputFlags(rawValue: 0x0000_0008)  // TURNRMASK
    public static let lmine = InputFlags(rawValue: 0x0000_0010)  // LMINEMASK
    public static let shoot = InputFlags(rawValue: 0x0000_0020)  // SHOOTMASK
    public static let incre = InputFlags(rawValue: 0x0000_0040)  // INCREMASK
    public static let decre = InputFlags(rawValue: 0x0000_0080)  // DECREMASK
}

// MARK: - PlayerState

public struct PlayerState: Sendable {
    // Tank physics
    public var tank: Vec2f
    public var dir: Float
    public var speed: Float
    public var turnSpeed: Float
    public var kickDir: Float
    public var kickSpeed: Float
    // Builder
    public var builder: Vec2f
    public var builderTarget: Pointi
    public var builderStatus: BuilderStatus
    public var builderWait: Int
    // Status
    public var dead: Bool
    public var boat: Bool
    public var connected: Bool
    public var used: Bool
    /// Bitmask; bit j set means allied with player j.
    public var alliance: UInt16
    public var inputFlags: InputFlags
    // Projectiles
    public var shells: [Shell]
    public var explosions: [Explosion]

    public init(
        tank: Vec2f = Vec2f(x: 0, y: 0),
        dir: Float = 0,
        speed: Float = 0,
        turnSpeed: Float = 0,
        kickDir: Float = 0,
        kickSpeed: Float = 0,
        builder: Vec2f = Vec2f(x: 0, y: 0),
        builderTarget: Pointi = Pointi(x: 0, y: 0),
        builderStatus: BuilderStatus = .ready,
        builderWait: Int = 0,
        dead: Bool = true,
        boat: Bool = false,
        connected: Bool = false,
        used: Bool = false,
        alliance: UInt16 = 0,
        inputFlags: InputFlags = [],
        shells: [Shell] = [],
        explosions: [Explosion] = []
    ) {
        self.tank = tank
        self.dir = dir
        self.speed = speed
        self.turnSpeed = turnSpeed
        self.kickDir = kickDir
        self.kickSpeed = kickSpeed
        self.builder = builder
        self.builderTarget = builderTarget
        self.builderStatus = builderStatus
        self.builderWait = builderWait
        self.dead = dead
        self.boat = boat
        self.connected = connected
        self.used = used
        self.alliance = alliance
        self.inputFlags = inputFlags
        self.shells = shells
        self.explosions = explosions
    }
}

// MARK: - LocalPlayerState
//
// Fields from the C `client` struct itself, not `client.players[]` — i.e.
// resources and per-tick bookkeeping that only exist for the locally
// simulated player.

public struct LocalPlayerState: Sendable {
    public var armour: Int
    public var shells: Int
    public var mines: Int
    public var trees: Int
    /// Remaining shell range for the next shot fired.
    public var range: Float
    public var respawnCounter: Int
    public var builderTask: BuilderTask
    public var builderMines: Int
    public var builderTrees: Int
    /// Index into `GameState.pills`, or `noPill` (0xff) if none reserved.
    public var builderPill: UInt8
    public var spawned: Bool
    public var drainCounter: Int
    public var refueling: Bool
    /// Index into `GameState.bases`, or -1 if not refueling.
    public var refuelingBase: Int
    public var refuelingCounter: Int
    public var shellCounter: Int
    /// Death count for the local player. C: `client.deaths` — write-only in
    /// the ported subsystems (scoreboard display is a UI concern), kept here
    /// for state fidelity.
    public var deaths: Int

    public init(
        armour: Int = 0,
        shells: Int = 0,
        mines: Int = 0,
        trees: Int = 0,
        range: Float = maxShellRange,
        respawnCounter: Int = 0,
        builderTask: BuilderTask = .doNothing,
        builderMines: Int = 0,
        builderTrees: Int = 0,
        builderPill: UInt8 = noPill,
        spawned: Bool = false,
        drainCounter: Int = 0,
        refueling: Bool = false,
        refuelingBase: Int = -1,
        refuelingCounter: Int = 0,
        shellCounter: Int = 0,
        deaths: Int = 0
    ) {
        self.armour = armour
        self.shells = shells
        self.mines = mines
        self.trees = trees
        self.range = range
        self.respawnCounter = respawnCounter
        self.builderTask = builderTask
        self.builderMines = builderMines
        self.builderTrees = builderTrees
        self.builderPill = builderPill
        self.spawned = spawned
        self.drainCounter = drainCounter
        self.refueling = refueling
        self.refuelingBase = refuelingBase
        self.refuelingCounter = refuelingCounter
        self.shellCounter = shellCounter
        self.deaths = deaths
    }
}

// MARK: - GrowState
//
// Server-side persistent tree-growth tournament state (Wave 5.7). growX/
// growY are the current best-of-N winning coordinates, not flat indices.

public struct GrowState: Hashable, Sendable {
    public var growX: Int
    public var growY: Int
    public var growBestOf: Int

    public init(growX: Int = 0, growY: Int = 0, growBestOf: Int = 0) {
        self.growX = growX
        self.growY = growY
        self.growBestOf = growBestOf
    }
}

// MARK: - Lookup helpers

/// Finds the pill occupying (x, y), if any. Mirrors client-side `findpill()`
/// (Reference/c/client.c:7089): matches by position, excluding pills with
/// `armour == pillOnboard` (the "carried by a builder" sentinel).
public func findPill(x: Int, y: Int, pills: [Pill]) -> Int? {
    pills.indices.first {
        pills[$0].armour != pillOnboard && Int(pills[$0].x) == x && Int(pills[$0].y) == y
    }
}

/// Finds the base occupying (x, y), if any. Mirrors `findbase()`
/// (Reference/c/client.c:7106): matches by position, no other filter.
public func findBase(x: Int, y: Int, bases: [Base]) -> Int? {
    bases.indices.first { Int(bases[$0].x) == x && Int(bases[$0].y) == y }
}

/// Mirrors `testalliance()` (Reference/c/client.c:7123): both players must
/// be active slots (`used`), and the alliance must be mutual — each side's
/// bitmask must have the other's bit set. A one-sided alliance is not an
/// alliance.
public func testAlliance(_ p1: Int, _ p2: Int, players: [PlayerState]) -> Bool {
    guard p1 >= 0, p1 < players.count, p2 >= 0, p2 < players.count else { return false }
    let a = players[p1]
    let b = players[p2]
    return a.used && b.used
        && (a.alliance & (1 << p2)) != 0
        && (b.alliance & (1 << p1)) != 0
}
