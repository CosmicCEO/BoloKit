import Darwin

// MARK: - Terrain Enum

@frozen public enum Terrain: Int32, CaseIterable, Sendable {
    case sea = 0, boat, wall, river
    case swamp0, swamp1, swamp2, swamp3
    case crater, road, forest
    case rubble0, rubble1, rubble2, rubble3
    case grass0, grass1, grass2, grass3
    case damagedWall0, damagedWall1, damagedWall2, damagedWall3
    // mined
    case minedSea, minedSwamp, minedCrater, minedRoad, minedForest, minedRubble, minedGrass
}

// MARK: - Predicates

public func isWaterLikeTerrain(_ terrain: Terrain) -> Int32 {
    switch terrain {
    case .river, .sea, .minedSea, .boat:
        return 1
    default:
        return 0
    }
}

public func isWaterLikeTerrain(_ terrain: Int32) -> Int32 {
    guard let t = Terrain(rawValue: terrain) else {
        return 0
    }
    return isWaterLikeTerrain(t)
}

// MARK: - TerrainGrid

/// A 256×256 grid of terrain values, stored as a flat [Int32].
/// Indexing: storage[y * 256 + x]
/// Mirrors TileGrid — same layout, terrain raw values instead of tile raw values.
public struct TerrainGrid: Sendable {
    public var storage: [Int32]

    public init() {
        self.storage = [Int32](repeating: Terrain.sea.rawValue, count: 256 * 256)
    }

    public subscript(x: Int, y: Int) -> Terrain? {
        get {
            Terrain(rawValue: storage[y * 256 + x])
        }
        set {
            storage[y * 256 + x] = newValue?.rawValue ?? Terrain.sea.rawValue
        }
    }
}

// MARK: - Terrain Speed Functions

/// Maximum tank forward speed for a given terrain type (squares per second).
///
/// Ported from `maxspeed()` in Reference/c/client.c — pure terrain mapping only.
/// The full `maxspeed(x, y)` with findbase/findpill overrides (which can raise
/// speed to roadMaxSpeed regardless of terrain) is implemented in Wave 5.
///
/// Speed tiers (road : grass : forest : rubble = 5.33 : 4 : 2 : 1):
///   road / boat / minedRoad          → roadMaxSpeed   (3.125)
///   grass0–3 / minedGrass            → grassMaxSpeed  (2.34375)
///   forest / minedForest             → forestMaxSpeed (1.171875)
///   river / swamp0–3 / crater /
///     rubble0–3 / minedSwamp /
///     minedCrater / minedRubble      → rubbleMaxSpeed (0.5859375)
///   sea / wall / damagedWall0–3 /
///     minedSea                       → 0.0 (impassable)
public func terrainMaxSpeed(_ terrain: Terrain) -> Float {
    switch terrain {
    case .road, .boat, .minedRoad:
        return roadMaxSpeed
    case .grass0, .grass1, .grass2, .grass3, .minedGrass:
        return grassMaxSpeed
    case .forest, .minedForest:
        return forestMaxSpeed
    case .river,
         .swamp0, .swamp1, .swamp2, .swamp3,
         .crater,
         .rubble0, .rubble1, .rubble2, .rubble3,
         .minedSwamp, .minedCrater, .minedRubble:
        return rubbleMaxSpeed
    default:
        // sea, wall, damagedWall0–3, minedSea
        return 0.0
    }
}

/// Maximum tank turn rate for a given terrain type (radians per second).
///
/// Ported from `maxturnspeed()` in Reference/c/client.c — pure terrain mapping only.
/// The full version with pill/base overrides comes in Wave 5.
///
/// Note: grass turns at full rate even though forward speed is reduced.
///
///   road / boat / grass0–3 / minedRoad / minedGrass   → 2.5
///   forest / minedForest                               → 1.25
///   river / swamp0–3 / crater / rubble0–3 /
///     minedSwamp / minedCrater / minedRubble           → 0.625
///   sea / wall / damagedWall0–3 / minedSea             → 0.0
public func terrainMaxTurnSpeed(_ terrain: Terrain) -> Float {
    switch terrain {
    case .road, .boat, .minedRoad,
         .grass0, .grass1, .grass2, .grass3, .minedGrass:
        return 2.5
    case .forest, .minedForest:
        return 1.25
    case .river,
         .swamp0, .swamp1, .swamp2, .swamp3,
         .crater,
         .rubble0, .rubble1, .rubble2, .rubble3,
         .minedSwamp, .minedCrater, .minedRubble:
        return 0.625
    default:
        // sea, wall, damagedWall0–3, minedSea
        return 0.0
    }
}

/// Pure terrain-based builder (LGM) movement speed (squares per second).
///
/// Ported from the terrain switch in `builderspeed()` in Reference/c/client.c.
/// The full version with pill/base/alliance checks comes in Wave 5.
///
///   road / boat / grass0–3 / minedRoad / minedGrass    → builderMaxSpeed (3.125)
///   forest / minedForest                               → builderMaxSpeed × 0.5
///   swamp0–3 / crater / rubble0–3 /
///     minedSwamp / minedCrater / minedRubble           → builderMaxSpeed × 0.25
///   sea / wall / damagedWall0–3 / river / minedSea     → 0.0
public func terrainBuilderSpeed(_ terrain: Terrain) -> Float {
    // C reference: builderspeed() in client.c lines 3749-3784
    // grass moves at FULL builder speed (= road), NOT at 0.5x like forest.
    switch terrain {
    case .road, .boat, .minedRoad,
         .grass0, .grass1, .grass2, .grass3, .minedGrass:
        return builderMaxSpeed
    case .forest, .minedForest:
        return builderMaxSpeed * 0.5
    case .swamp0, .swamp1, .swamp2, .swamp3,
         .crater,
         .rubble0, .rubble1, .rubble2, .rubble3,
         .minedSwamp, .minedCrater, .minedRubble:
        return builderMaxSpeed * 0.25
    default:
        // sea, wall, damagedWall0-3, river, minedSea -> impassable for builder
        return 0.0
    }
}
