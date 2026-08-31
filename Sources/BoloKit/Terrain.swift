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
