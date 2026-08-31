// MARK: - BMAP Module Constants
//
// Ported from Reference/c/bmap.c and bolo.h.

/// The full 256×256 map area. Mirrors C `kWorldRect`.
public let worldRect = Recti(origin: Pointi(x: 0, y: 0), size: Sizei(width: 256, height: 256))

/// The mine-able interior area [10, 245] × [10, 245]. Mirrors C `kSeaRect` {10, 10, 236, 236}.
public let seaRect = Recti(origin: Pointi(x: 10, y: 10), size: Sizei(width: 236, height: 236))

/// Mine-zone bounds from bolo.h. Coordinates outside this closed range default to mined sea.
public let xMinMine: Int32 = 10
public let yMinMine: Int32 = 10
public let xMaxMine: Int32 = 245
public let yMaxMine: Int32 = 245

// MARK: - Default Terrain / Tile

/// The terrain a map cell holds before any run data is applied.
///
/// Ported from `defaultterrain()` in Reference/c/bmap.c: `.sea` inside the
/// mine zone [10, 245] × [10, 245], `.minedSea` in the outer border ring.
public func defaultTerrain(x: Int32, y: Int32) -> Terrain {
    (y >= yMinMine && y <= yMaxMine && x >= xMinMine && x <= xMaxMine) ? .sea : .minedSea
}

/// The tile a map cell displays before any run data is applied.
///
/// Ported from `defaulttile()` in Reference/c/bmap.c — same boundary logic
/// as `defaultTerrain(x:y:)`, returning the tile equivalents.
public func defaultTile(x: Int32, y: Int32) -> Tile {
    (y >= yMinMine && y <= yMaxMine && x >= xMinMine && x <= xMaxMine) ? .sea : .minedSea
}

// MARK: - Terrain → Tile Translation

/// Converts a terrain value to its canonical display tile.
///
/// Ported from `terraintotile()` in Reference/c/bmap.c. Terrain variants
/// collapse to a single tile: swamp0–3 → .swamp, rubble0–3 → .rubble,
/// grass0–3 → .grass, damagedWall0–3 → .damagedWall.
public func terrainToTile(_ terrain: Terrain) -> Tile {
    switch terrain {
    case .sea:
        return .sea
    case .wall:
        return .wall
    case .river:
        return .river
    case .swamp0, .swamp1, .swamp2, .swamp3:
        return .swamp
    case .crater:
        return .crater
    case .road:
        return .road
    case .forest:
        return .forest
    case .rubble0, .rubble1, .rubble2, .rubble3:
        return .rubble
    case .grass0, .grass1, .grass2, .grass3:
        return .grass
    case .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        return .damagedWall
    case .boat:
        return .boat
    case .minedSea:
        return .minedSea
    case .minedSwamp:
        return .minedSwamp
    case .minedCrater:
        return .minedCrater
    case .minedRoad:
        return .minedRoad
    case .minedForest:
        return .minedForest
    case .minedRubble:
        return .minedRubble
    case .minedGrass:
        return .minedGrass
    }
}

/// Raw-value overload for differential testing against the C oracle.
///
/// Returns -1 for values outside the Terrain range, matching the C
/// `default: return -1` path (the C `assert(0)` is a debug-only trap,
/// not a behavioral contract — same divergence accepted for mapimage).
public func terrainToTile(_ terrain: Int32) -> Int32 {
    guard let t = Terrain(rawValue: terrain) else {
        return -1
    }
    return terrainToTile(t).rawValue
}

// MARK: - BMAP File Format Structs
//
// Pure data carriers mirroring the packed structs in Reference/c/bmap.h.
// Field order matches the on-disk .bolo map format byte-for-byte; the
// serialization codec (readrun/writerun) is deferred to a later wave.

/// Mirrors `struct BMAP_Preamble` (bmap.h): the .bolo file header.
public struct BMapPreamble: Hashable, Sendable {
    /// File identifier, 8 bytes: "BMAPBOLO"
    public var ident: [UInt8]
    /// Format version, currently 0
    public var version: UInt8
    /// Number of pillboxes (maximum 16)
    public var npills: UInt8
    /// Number of bases (maximum 16)
    public var nbases: UInt8
    /// Number of player starts (maximum 16)
    public var nstarts: UInt8

    public init(ident: [UInt8], version: UInt8, npills: UInt8, nbases: UInt8, nstarts: UInt8) {
        self.ident = ident
        self.version = version
        self.npills = npills
        self.nbases = nbases
        self.nstarts = nstarts
    }
}

/// Mirrors `struct BMAP_PillInfo` (bmap.h).
public struct BMapPillInfo: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// Should be 0xFF except in speciality maps
    public var owner: UInt8
    /// Range 0–15 (dead pillbox = 0, full strength = 15)
    public var armour: UInt8
    /// Typically 50. Time between shots, in 20ms units; lower values start the pillbox 'angry'
    public var speed: UInt8

    public init(x: UInt8, y: UInt8, owner: UInt8, armour: UInt8, speed: UInt8) {
        self.x = x
        self.y = y
        self.owner = owner
        self.armour = armour
        self.speed = speed
    }
}

/// Mirrors `struct BMAP_BaseInfo` (bmap.h).
public struct BMapBaseInfo: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// Should be 0xFF except in speciality maps
    public var owner: UInt8
    /// Initial stock, maximum 90
    public var armour: UInt8
    /// Initial stock, maximum 90
    public var shells: UInt8
    /// Initial stock, maximum 90
    public var mines: UInt8

    public init(x: UInt8, y: UInt8, owner: UInt8, armour: UInt8, shells: UInt8, mines: UInt8) {
        self.x = x
        self.y = y
        self.owner = owner
        self.armour = armour
        self.shells = shells
        self.mines = mines
    }
}

/// Mirrors `struct BMAP_StartInfo` (bmap.h).
public struct BMapStartInfo: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// Direction towards land from this start. Range 0–15
    public var dir: UInt8

    public init(x: UInt8, y: UInt8, dir: UInt8) {
        self.x = x
        self.y = y
        self.dir = dir
    }
}

/// Mirrors `struct BMAP_Run` (bmap.h): one RLE run header in the map data.
///
/// The run stream terminates with the sentinel
/// {datalen: 4, y: 0xFF, startx: 0xFF, endx: 0xFF} — all four fields must
/// be checked together when the codec is ported.
public struct BMapRun: Hashable, Sendable {
    /// Length of the data for this run, INCLUDING this 4-byte header
    public var datalen: UInt8
    /// Y coordinate of this run
    public var y: UInt8
    /// First square of the run
    public var startx: UInt8
    /// Last square of run + 1 (first deep-sea square after the run)
    public var endx: UInt8

    public init(datalen: UInt8, y: UInt8, startx: UInt8, endx: UInt8) {
        self.datalen = datalen
        self.y = y
        self.startx = startx
        self.endx = endx
    }
}
