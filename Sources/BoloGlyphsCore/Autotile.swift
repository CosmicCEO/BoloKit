import BoloKit

// Derives, for every image index a connective terrain family can produce,
// the neighbor configuration that produces it -- by sweeping `mapimage()`
// itself (Sources/BoloKit/Images.swift:301) rather than hand-transcribing
// its 137 connective case labels. Self-checking by construction: if the
// sweep doesn't reproduce exactly the expected variant count for a family,
// a test fails before a wrong-looking sheet ships (Wave 7.0 pre-brief).

/// Neighbor bits, matching `mapimage()`'s own encoding exactly:
/// ortho L=1 (x-1,y), U=2 (x,y-1), R=4 (x+1,y), D=8 (x,y+1);
/// diag  NW=1 (x-1,y-1), NE=2 (x+1,y-1), SW=4 (x-1,y+1), SE=8 (x+1,y+1).
public struct Connectivity: Hashable, Sendable {
    public var ortho: UInt8
    public var diag: UInt8
}

public enum TileFamily: CaseIterable, Sendable {
    case wall, river, forest, crater, road, boat, sea
}

public struct ConnectiveGlyph: Sendable {
    public var family: TileFamily
    public var ortho: UInt8
    public var diag: UInt8
}

private let orthoOffsets: [(Int32, Int32)] = [(-1, 0), (0, -1), (1, 0), (0, 1)]
private let diagOffsets: [(Int32, Int32)] = [(-1, -1), (1, -1), (-1, 1), (1, 1)]

/// Probed at an interior coordinate deliberately: every `is*LikeTile`
/// predicate returns 1 out-of-bounds (Sources/BoloKit/Tiles.swift), so an
/// edge coordinate would fabricate phantom connections.
private let probeX: Int32 = 128
private let probeY: Int32 = 128

/// Every single-predicate family's "definitely not connected" filler.
/// `.grass` is outside all seven `is*LikeTile` predicate sets used by
/// `mapimage()` -- verified directly against each predicate's case list.
private let notConnected = Tile.grass

public func deriveConnectivity(family: TileFamily) -> [Int32: Connectivity] {
    if family == .road {
        return deriveRoadConnectivity()
    }

    let center: Tile
    let needsDiag: Bool
    switch family {
    case .wall: center = .wall; needsDiag = true
    case .river: center = .river; needsDiag = false
    case .forest: center = .forest; needsDiag = false
    case .crater: center = .crater; needsDiag = false
    case .boat: center = .boat; needsDiag = false
    case .sea: center = .sea; needsDiag = false
    case .road: fatalError("handled above")
    }

    var result: [Int32: Connectivity] = [:]
    let diagRange: [UInt8] = needsDiag ? Array(0..<16) : [0]
    for orthoMask: UInt8 in 0..<16 {
        for diagMask in diagRange {
            var grid = TileGrid()
            grid[Int(probeX), Int(probeY)] = center.rawValue
            for (i, offset) in orthoOffsets.enumerated() {
                let bit = (orthoMask >> i) & 1 == 1
                grid[Int(probeX + offset.0), Int(probeY + offset.1)] = (bit ? center : notConnected).rawValue
            }
            if needsDiag {
                for (i, offset) in diagOffsets.enumerated() {
                    let bit = (diagMask >> i) & 1 == 1
                    grid[Int(probeX + offset.0), Int(probeY + offset.1)] = (bit ? center : notConnected).rawValue
                }
            }
            let image = mapimage(grid, probeX, probeY)
            if image >= 0 {
                result[image] = Connectivity(ortho: orthoMask, diag: diagMask)
            }
        }
    }
    return result
}

/// Road's `mapimage()` branch reads three independent predicates over
/// neighbors -- `isRoadLikeTile` and `isWaterLikeToLandTile` on the four
/// orthogonal cells, plus `isRoadLikeTile` again on the four diagonals.
/// A single tile value can express both predicates at once only via
/// `.unknown` (the one member of both predicates' "true" sets), so each
/// orthogonal cell is swept across all four (road, water) combinations
/// independently rather than a single connected/disconnected bit.
private func deriveRoadConnectivity() -> [Int32: Connectivity] {
    var result: [Int32: Connectivity] = [:]
    for roadMask: UInt8 in 0..<16 {
        for waterMask: UInt8 in 0..<16 {
            for diagMask: UInt8 in 0..<16 {
                var grid = TileGrid()
                grid[Int(probeX), Int(probeY)] = Tile.road.rawValue
                for (i, offset) in orthoOffsets.enumerated() {
                    let roadBit = (roadMask >> i) & 1 == 1
                    let waterBit = (waterMask >> i) & 1 == 1
                    let t: Tile
                    switch (roadBit, waterBit) {
                    case (true, true): t = .unknown
                    case (true, false): t = .road
                    case (false, true): t = .river
                    case (false, false): t = .wall
                    }
                    grid[Int(probeX + offset.0), Int(probeY + offset.1)] = t.rawValue
                }
                for (i, offset) in diagOffsets.enumerated() {
                    let bit = (diagMask >> i) & 1 == 1
                    grid[Int(probeX + offset.0), Int(probeY + offset.1)] = (bit ? Tile.road : Tile.wall).rawValue
                }
                let image = mapimage(grid, probeX, probeY)
                if image >= 0 {
                    result[image] = Connectivity(ortho: roadMask, diag: diagMask)
                }
            }
        }
    }
    return result
}

public func deriveAllConnectivity() -> [Int32: ConnectiveGlyph] {
    var all: [Int32: ConnectiveGlyph] = [:]
    for family in TileFamily.allCases {
        for (image, conn) in deriveConnectivity(family: family) {
            all[image] = ConnectiveGlyph(family: family, ortho: conn.ortho, diag: conn.diag)
        }
    }
    return all
}
