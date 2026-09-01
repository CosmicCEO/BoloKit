import Testing
import BoloKit

// Wave 4 unit tests — terrainToTile / defaultTerrain / defaultTile / BMAP structs.
// Expected values pinned as independent tables against Reference/c/bmap.c.

// MARK: - terrainToTile (exhaustive, all 30 cases)

private let expectedTile: [Terrain: Tile] = [
    .sea: .sea,
    .boat: .boat,
    .wall: .wall,
    .river: .river,
    .swamp0: .swamp,
    .swamp1: .swamp,
    .swamp2: .swamp,
    .swamp3: .swamp,
    .crater: .crater,
    .road: .road,
    .forest: .forest,
    .rubble0: .rubble,
    .rubble1: .rubble,
    .rubble2: .rubble,
    .rubble3: .rubble,
    .grass0: .grass,
    .grass1: .grass,
    .grass2: .grass,
    .grass3: .grass,
    .damagedWall0: .damagedWall,
    .damagedWall1: .damagedWall,
    .damagedWall2: .damagedWall,
    .damagedWall3: .damagedWall,
    .minedSea: .minedSea,
    .minedSwamp: .minedSwamp,
    .minedCrater: .minedCrater,
    .minedRoad: .minedRoad,
    .minedForest: .minedForest,
    .minedRubble: .minedRubble,
    .minedGrass: .minedGrass,
]

@Test func terrainToTileExhaustive() throws {
    #expect(expectedTile.count == Terrain.allCases.count)
    for terrain in Terrain.allCases {
        let expected = try #require(expectedTile[terrain])
        #expect(terrainToTile(terrain) == expected, "tile mismatch for \(terrain)")
    }
}

@Test func terrainToTileRawOverload() {
    // Valid raw values delegate to the typed version
    for terrain in Terrain.allCases {
        #expect(terrainToTile(terrain.rawValue) == terrainToTile(terrain).rawValue)
    }
    // Out-of-range values return -1 (C default path; C's assert(0) is a
    // debug-only trap, not behavior)
    #expect(terrainToTile(Int32(-1)) == -1)
    #expect(terrainToTile(Int32(30)) == -1)
    #expect(terrainToTile(Int32(999)) == -1)
}

// MARK: - defaultTerrain / defaultTile boundaries

@Test func defaultTerrainBoundaries() {
    // Interior of the mine zone [10, 245]² → sea
    #expect(defaultTerrain(x: 10, y: 10) == .sea)
    #expect(defaultTerrain(x: 245, y: 245) == .sea)
    #expect(defaultTerrain(x: 128, y: 128) == .sea)
    #expect(defaultTerrain(x: 10, y: 245) == .sea)
    // Border ring → mined sea
    #expect(defaultTerrain(x: 9, y: 10) == .minedSea)
    #expect(defaultTerrain(x: 10, y: 9) == .minedSea)
    #expect(defaultTerrain(x: 246, y: 245) == .minedSea)
    #expect(defaultTerrain(x: 245, y: 246) == .minedSea)
    #expect(defaultTerrain(x: 0, y: 0) == .minedSea)
    #expect(defaultTerrain(x: 255, y: 255) == .minedSea)
}

@Test func defaultTileBoundaries() {
    #expect(defaultTile(x: 10, y: 10) == .sea)
    #expect(defaultTile(x: 245, y: 245) == .sea)
    #expect(defaultTile(x: 128, y: 128) == .sea)
    #expect(defaultTile(x: 9, y: 10) == .minedSea)
    #expect(defaultTile(x: 10, y: 9) == .minedSea)
    #expect(defaultTile(x: 246, y: 245) == .minedSea)
    #expect(defaultTile(x: 245, y: 246) == .minedSea)
    #expect(defaultTile(x: 0, y: 0) == .minedSea)
    #expect(defaultTile(x: 255, y: 255) == .minedSea)
}

@Test func worldAndSeaRects() {
    #expect(worldRect == Recti(origin: Pointi(x: 0, y: 0), size: Sizei(width: 256, height: 256)))
    #expect(seaRect == Recti(origin: Pointi(x: 10, y: 10), size: Sizei(width: 236, height: 236)))
}

// MARK: - TerrainGrid.mapDefault

@Test func terrainGridMapDefault() {
    let grid = TerrainGrid.mapDefault()
    // Border ring is mined sea
    #expect(grid[0, 0] == .minedSea)
    #expect(grid[9, 10] == .minedSea)
    #expect(grid[10, 9] == .minedSea)
    #expect(grid[246, 245] == .minedSea)
    #expect(grid[245, 246] == .minedSea)
    #expect(grid[255, 255] == .minedSea)
    // Interior is sea
    #expect(grid[10, 10] == .sea)
    #expect(grid[128, 128] == .sea)
    #expect(grid[245, 245] == .sea)
    // Exactly the 236×236 interior cells are sea
    let seaCount = grid.storage.count(where: { $0 == Terrain.sea.rawValue })
    #expect(seaCount == 236 * 236)
}

// MARK: - BMAP struct smoke tests

@Test func bmapStructRoundTrip() {
    let preamble = BMapPreamble(
        ident: Array("BMAPBOLO".utf8), version: 0, npills: 16, nbases: 16, nstarts: 16
    )
    #expect(preamble.ident.count == 8)
    #expect(preamble.version == 0)
    #expect(preamble.npills == 16)

    let pill = BMapPillInfo(x: 12, y: 34, owner: 0xFF, armour: 15, speed: 50)
    #expect(pill.owner == 0xFF)
    #expect(pill.armour == 15)

    let base = BMapBaseInfo(x: 56, y: 78, owner: 0xFF, armour: 90, shells: 90, mines: 90)
    #expect(base.mines == 90)

    let start = BMapStartInfo(x: 100, y: 200, dir: 15)
    #expect(start.dir == 15)

    // Run-stream termination sentinel: all four fields together
    let sentinel = BMapRun(datalen: 4, y: 0xFF, startx: 0xFF, endx: 0xFF)
    #expect(sentinel == BMapRun(datalen: 4, y: 0xFF, startx: 0xFF, endx: 0xFF))
    #expect(sentinel != BMapRun(datalen: 4, y: 0xFF, startx: 0xFF, endx: 0xFE))
}

// MARK: - readRun / writeRun (Wave 4.1)
//
// readNibble/writeNibble are file-private to BMap.swift; their packing
// order is verified indirectly through readRun's byte output below.

@Test func readRunExhaustedOnAllDefaultGridReturnsSentinel() {
    let grid = TerrainGrid.mapDefault()
    var y = 0
    var x = 0
    let (run, data, isLast) = readRun(grid: grid, y: &y, x: &x)
    #expect(isLast)
    #expect(data.isEmpty)
    #expect(run == BMapRun(datalen: 4, y: 0xff, startx: 0xff, endx: 0xff))
}

@Test func readRunEncodesLikeTilesRun() {
    // 4 identical grass3 cells — exercises the "like tiles" branch.
    var grid = TerrainGrid.mapDefault()
    for x in 20...23 { grid[x, 5] = .grass3 }

    var y = 0
    var x = 0
    let (run, data, isLast) = readRun(grid: grid, y: &y, x: &x)
    #expect(!isLast)
    #expect(run.y == 5)
    #expect(run.startx == 20)
    #expect(run.endx == 24)
    #expect(run.datalen == 5)  // 4-byte header + 1 data byte
    // nibble0 (high) = len+6 = 4+6 = 10 (0xA); nibble1 (low) = .grass tile (7)
    #expect(data == [UInt8(0xA7)])
}

@Test func readRunEncodesDifferentTilesRunHighNibbleFirst() {
    // 2 distinct, non-matching tiles — exercises the "different tiles"
    // branch and verifies high-nibble-first packing.
    var grid = TerrainGrid.mapDefault()
    grid[20, 5] = .wall
    grid[21, 5] = .road

    var y = 0
    var x = 0
    let (run, data, isLast) = readRun(grid: grid, y: &y, x: &x)
    #expect(!isLast)
    #expect(run.y == 5)
    #expect(run.startx == 20)
    #expect(run.endx == 22)
    #expect(run.datalen == 6)  // 4-byte header + 2 data bytes
    // byte0: header nibble (len-1=1) high, .wall tile (0) low -> 0x10
    // byte1: .road tile (4) high, unused low -> 0x40
    #expect(data == [UInt8(0x10), UInt8(0x40)])
}

@Test func readWriteRunRoundTripSingleLikeTilesRun() {
    var original = TerrainGrid.mapDefault()
    for x in 100...105 { original[x, 50] = .road }

    var y = 0
    var x = 0
    var rebuilt = TerrainGrid.mapDefault()
    while true {
        let (run, data, isLast) = readRun(grid: original, y: &y, x: &x)
        if isLast { break }
        #expect(writeRun(run, data: data, into: &rebuilt))
    }
    #expect(rebuilt.storage == original.storage)
}

@Test func writeRunRejectsTruncatedDatalen() {
    // Claims zero data bytes but a non-empty column span
    let run = BMapRun(datalen: 4, y: 5, startx: 20, endx: 22)
    var grid = TerrainGrid.mapDefault()
    #expect(!writeRun(run, data: [], into: &grid))
}

@Test func writeRunRejectsTrailingDatalenMismatch() {
    // Valid 2-tile "different tiles" encoding (see
    // readRunEncodesDifferentTilesRunHighNibbleFirst), but datalen
    // overstated (should be 6, not 7) — caught by the trailing check.
    let data: [UInt8] = [0x10, 0x40]
    let run = BMapRun(datalen: 7, y: 5, startx: 20, endx: 22)
    var grid = TerrainGrid.mapDefault()
    #expect(!writeRun(run, data: data, into: &grid))
}

@Test func writeRunGuardsAgainstOverrunPastColumn256() {
    // Corrupt "like tiles" run claiming 9 repeats (header nibble 15) from
    // a 2-column span starting near the grid edge — attempting to write
    // 9 tiles from column 250 would reach column 259. C's raw-pointer
    // `terrain[run.y][x++]` would silently overrun into adjacent row
    // memory in this scenario; Swift must fail closed instead of crashing
    // (this guard has no C equivalent — see writeRun's doc comment).
    let data: [UInt8] = [0xF0]  // header nibble 15 (len=9), tile nibble 0 (wall)
    let run = BMapRun(datalen: 5, y: 0, startx: 250, endx: 252)
    var grid = TerrainGrid.mapDefault()
    #expect(!writeRun(run, data: data, into: &grid))
}
