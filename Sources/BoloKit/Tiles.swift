import Darwin

// MARK: - Tile Enum

@frozen public enum Tile: Int32, CaseIterable, Sendable {
    case wall = 0
    case river = 1
    case swamp = 2
    case crater = 3
    case road = 4
    case forest = 5
    case rubble = 6
    case grass = 7
    case damagedWall = 8
    case boat = 9

    case minedSwamp = 10
    case minedCrater = 11
    case minedRoad = 12
    case minedForest = 13
    case minedRubble = 14
    case minedGrass = 15

    case sea = 16
    case minedSea = 17
    case friendlyBase = 18
    case hostileBase = 19
    case neutralBase = 20

    case friendlyPill00 = 21, friendlyPill01 = 22, friendlyPill02 = 23, friendlyPill03 = 24
    case friendlyPill04 = 25, friendlyPill05 = 26, friendlyPill06 = 27, friendlyPill07 = 28
    case friendlyPill08 = 29, friendlyPill09 = 30, friendlyPill10 = 31, friendlyPill11 = 32
    case friendlyPill12 = 33, friendlyPill13 = 34, friendlyPill14 = 35, friendlyPill15 = 36

    case hostilePill00 = 37, hostilePill01 = 38, hostilePill02 = 39, hostilePill03 = 40
    case hostilePill04 = 41, hostilePill05 = 42, hostilePill06 = 43, hostilePill07 = 44
    case hostilePill08 = 45, hostilePill09 = 46, hostilePill10 = 47, hostilePill11 = 48
    case hostilePill12 = 49, hostilePill13 = 50, hostilePill14 = 51, hostilePill15 = 52

    case unknown = 53
}

// MARK: - TileGrid Structure

public struct TileGrid: Sendable {
    public var storage: [Int32]
    
    public init() {
        self.storage = [Int32](repeating: 0, count: 256 * 256)
    }
    
    public subscript(x: Int, y: Int) -> Int32 {
        get {
            storage[y * 256 + x]
        }
        set {
            storage[y * 256 + x] = newValue
        }
    }
}

// MARK: - Tile Predicates

// 1. isForestLikeTile
public func isForestLikeTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.forest.rawValue, Tile.minedForest.rawValue, Tile.unknown.rawValue:
        return 1
    default:
        return 0
    }
}
public func isForestLikeTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isForestLikeTile(buf.baseAddress!, x, y)
    }
}

// 2. isCraterLikeTile
public func isCraterLikeTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.crater.rawValue, Tile.river.rawValue, Tile.sea.rawValue,
         Tile.minedCrater.rawValue, Tile.minedSea.rawValue, Tile.unknown.rawValue:
        return 1
    default:
        return 0
    }
}
public func isCraterLikeTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isCraterLikeTile(buf.baseAddress!, x, y)
    }
}

// 3. isRoadLikeTile
public func isRoadLikeTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.road.rawValue, Tile.minedRoad.rawValue,
         Tile.friendlyBase.rawValue, Tile.hostileBase.rawValue, Tile.neutralBase.rawValue:
        return 1
    case Tile.friendlyPill00.rawValue...Tile.friendlyPill15.rawValue:
        return 1
    case Tile.hostilePill00.rawValue...Tile.hostilePill15.rawValue:
        return 1
    case Tile.unknown.rawValue:
        return 1
    default:
        return 0
    }
}
public func isRoadLikeTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isRoadLikeTile(buf.baseAddress!, x, y)
    }
}

// 4. isWaterLikeToLandTile
public func isWaterLikeToLandTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.river.rawValue, Tile.boat.rawValue, Tile.sea.rawValue,
         Tile.minedSea.rawValue, Tile.unknown.rawValue:
        return 1
    default:
        return 0
    }
}
public func isWaterLikeToLandTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isWaterLikeToLandTile(buf.baseAddress!, x, y)
    }
}

// 5. isWaterLikeToWaterTile
public func isWaterLikeToWaterTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.road.rawValue, Tile.river.rawValue, Tile.boat.rawValue, Tile.sea.rawValue,
         Tile.crater.rawValue, Tile.minedRoad.rawValue, Tile.minedSea.rawValue, Tile.minedCrater.rawValue,
         Tile.friendlyBase.rawValue, Tile.hostileBase.rawValue, Tile.neutralBase.rawValue:
        return 1
    case Tile.friendlyPill00.rawValue...Tile.friendlyPill15.rawValue:
        return 1
    case Tile.hostilePill00.rawValue...Tile.hostilePill15.rawValue:
        return 1
    case Tile.unknown.rawValue:
        return 1
    default:
        return 0
    }
}
public func isWaterLikeToWaterTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isWaterLikeToWaterTile(buf.baseAddress!, x, y)
    }
}

// 6. isWallLikeTile
public func isWallLikeTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.rubble.rawValue, Tile.damagedWall.rawValue, Tile.wall.rawValue,
         Tile.minedRubble.rawValue, Tile.unknown.rawValue:
        return 1
    default:
        return 0
    }
}
public func isWallLikeTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isWallLikeTile(buf.baseAddress!, x, y)
    }
}

// 7. isSeaLikeTile
public func isSeaLikeTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.sea.rawValue, Tile.minedSea.rawValue, Tile.unknown.rawValue:
        return 1
    default:
        return 0
    }
}
public func isSeaLikeTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isSeaLikeTile(buf.baseAddress!, x, y)
    }
}

// 8. isMinedTile
public func isMinedTile(_ tiles: UnsafePointer<Int32>, _ x: Int32, _ y: Int32) -> Int32 {
    if x < 0 || x >= 256 || y < 0 || y >= 256 {
        return 1
    }
    let tile = tiles[Int(y) * 256 + Int(x)]
    switch tile {
    case Tile.minedSwamp.rawValue, Tile.minedCrater.rawValue, Tile.minedRoad.rawValue,
         Tile.minedForest.rawValue, Tile.minedRubble.rawValue, Tile.minedGrass.rawValue,
         Tile.minedSea.rawValue:
        return 1
    default:
        return 0
    }
}
public func isMinedTile(_ grid: TileGrid, _ x: Int32, _ y: Int32) -> Int32 {
    return grid.storage.withUnsafeBufferPointer { buf in
        isMinedTile(buf.baseAddress!, x, y)
    }
}
