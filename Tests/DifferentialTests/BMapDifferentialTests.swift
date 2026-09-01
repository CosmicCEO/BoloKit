import Testing
import BoloKit
import CXBolo

@Suite struct BMapDifferentialTests {

    // MARK: - terraintotile

    @Test func testTerrainToTile() {
        // IMPORTANT: only valid terrain raw values (0–29) may be passed to the
        // C oracle — its default branch is `assert(0)`, which aborts in debug
        // builds (PARITY Finding B). Invalid values are covered Swift-only in
        // BMapTests.terrainToTileRawOverload.
        for terrain in Terrain.allCases {
            let c = CXBolo.terraintotile(terrain.rawValue)
            let s = BoloKit.terrainToTile(terrain.rawValue)
            #expect(c == s, "terraintotile mismatch for raw \(terrain.rawValue) (\(terrain))")
        }
    }

    // MARK: - defaultterrain / defaulttile

    @Test func testDefaultTerrainAndTile() {
        // Boundary cross-product covering all four edges of the mine zone
        // [10, 245]² plus corners and center.
        let coords: [Int32] = [0, 9, 10, 11, 128, 244, 245, 246, 255]
        for y in coords {
            for x in coords {
                let cTerrain = CXBolo.defaultterrain(x, y)
                let sTerrain = BoloKit.defaultTerrain(x: x, y: y).rawValue
                #expect(cTerrain == sTerrain, "defaultterrain mismatch at (\(x), \(y))")

                let cTile = CXBolo.defaulttile_oracle(x, y)
                let sTile = BoloKit.defaultTile(x: x, y: y).rawValue
                #expect(cTile == sTile, "defaulttile mismatch at (\(x), \(y))")
            }
        }
    }

    // MARK: - kWorldRect / kSeaRect

    @Test func testWorldAndSeaRects() {
        #expect(CXBolo.kWorldRect.origin.x == BoloKit.worldRect.origin.x)
        #expect(CXBolo.kWorldRect.origin.y == BoloKit.worldRect.origin.y)
        #expect(CXBolo.kWorldRect.size.width == BoloKit.worldRect.size.width)
        #expect(CXBolo.kWorldRect.size.height == BoloKit.worldRect.size.height)

        #expect(CXBolo.kSeaRect.origin.x == BoloKit.seaRect.origin.x)
        #expect(CXBolo.kSeaRect.origin.y == BoloKit.seaRect.origin.y)
        #expect(CXBolo.kSeaRect.size.width == BoloKit.seaRect.size.width)
        #expect(CXBolo.kSeaRect.size.height == BoloKit.seaRect.size.height)
    }

    // MARK: - TerrainGrid.mapDefault vs C defaultterrain

    @Test func testMapDefaultGridMatchesOracle() {
        let grid = TerrainGrid.mapDefault()
        for y in 0..<256 {
            for x in 0..<256 {
                let c = CXBolo.defaultterrain(Int32(x), Int32(y))
                #expect(
                    grid.storage[y * 256 + x] == c,
                    "mapDefault mismatch at (\(x), \(y))"
                )
            }
        }
    }

    // MARK: - readRun / writeRun (Wave 4.1)

    /// Builds a flat 65,536-cell terrain array seeded from the C oracle's
    /// `defaultterrain`, with three hand-placed patches exercising both
    /// nibble-encoding branches: a "like tiles" run (identical canonical
    /// tiles), a "different tiles" run (distinct adjacent tiles), and a
    /// minimal single-tile run. Only canonical/no-variant terrain values
    /// are used (grass3, wall, road, forest, river) so that a
    /// terrainToTile → tileToTerrain round trip is lossless (see the
    /// variant-collapse finding in BMap.swift's `tileToTerrain` doc).
    private func buildFixtureTerrainArray() -> [Int32] {
        var terrain = [Int32](repeating: 0, count: 65536)
        for y in 0..<256 {
            for x in 0..<256 {
                terrain[y * 256 + x] = CXBolo.defaultterrain(Int32(x), Int32(y))
            }
        }
        // Row 20: a "like tiles" run — 4 identical grass3 cells
        for x in 30...33 { terrain[20 * 256 + x] = Terrain.grass3.rawValue }
        // Row 20: a "different tiles" run — 3 distinct, non-matching cells
        terrain[20 * 256 + 50] = Terrain.wall.rawValue
        terrain[20 * 256 + 51] = Terrain.road.rawValue
        terrain[20 * 256 + 52] = Terrain.forest.rawValue
        // Row 100: a minimal single-tile "different tiles" run (len = 1)
        terrain[100 * 256 + 200] = Terrain.river.rawValue
        return terrain
    }

    private func fixtureTerrainGrid(from flat: [Int32]) -> TerrainGrid {
        var grid = TerrainGrid()
        grid.storage = flat
        return grid
    }

    /// Runs the C oracle's `readrun_flat` to exhaustion over `terrain`,
    /// collecting every real run's header and nibble data.
    private func collectOracleRuns(_ terrain: [Int32]) -> [(run: CXBolo.BMAP_Run, data: [UInt8])] {
        var terrain = terrain
        var runs: [(run: CXBolo.BMAP_Run, data: [UInt8])] = []
        var cy = 0
        var cx = 0

        while true {
            var run = CXBolo.BMAP_Run(datalen: 0, y: 0, startx: 0, endx: 0)
            var dataBuf = [UInt8](repeating: 0, count: 64)
            let retval = withUnsafeMutablePointer(to: &cy) { yp in
                withUnsafeMutablePointer(to: &cx) { xp in
                    withUnsafeMutablePointer(to: &run) { rp in
                        dataBuf.withUnsafeMutableBytes { dbuf in
                            terrain.withUnsafeMutableBufferPointer { tbuf in
                                CXBolo.readrun_flat(yp, xp, rp, dbuf.baseAddress, tbuf.baseAddress)
                            }
                        }
                    }
                }
            }
            if retval == 1 {
                #expect(run.y == 0xff && run.startx == 0xff && run.endx == 0xff && run.datalen == 4)
                break
            }
            let byteCount = Int(run.datalen) - 4
            runs.append((run, Array(dataBuf[0..<byteCount])))
        }
        return runs
    }

    @Test func testReadRunMatchesOracle() {
        let terrainFlat = buildFixtureTerrainArray()
        let swiftGrid = fixtureTerrainGrid(from: terrainFlat)

        let cRuns = collectOracleRuns(terrainFlat)

        var swiftRuns: [(run: BMapRun, data: [UInt8])] = []
        var sy = 0
        var sx = 0
        while true {
            let (run, data, isLast) = BoloKit.readRun(grid: swiftGrid, y: &sy, x: &sx)
            if isLast {
                #expect(run.y == 0xff && run.startx == 0xff && run.endx == 0xff && run.datalen == 4)
                break
            }
            swiftRuns.append((run, data))
        }

        #expect(cRuns.count == swiftRuns.count, "run count mismatch")
        for (i, pair) in zip(cRuns, swiftRuns).enumerated() {
            let (c, s) = pair
            #expect(c.run.y == s.run.y, "run \(i) y mismatch")
            #expect(c.run.startx == s.run.startx, "run \(i) startx mismatch")
            #expect(c.run.endx == s.run.endx, "run \(i) endx mismatch")
            #expect(c.run.datalen == s.run.datalen, "run \(i) datalen mismatch")
            #expect(c.data == s.data, "run \(i) nibble data mismatch")
        }
    }

    @Test func testWriteRunMatchesOracle() {
        let terrainFlat = buildFixtureTerrainArray()
        let oracleRuns = collectOracleRuns(terrainFlat)

        // Decode via the C oracle into a fresh default-seeded terrain array
        var cDecoded = [Int32](repeating: 0, count: 65536)
        for y in 0..<256 {
            for x in 0..<256 {
                cDecoded[y * 256 + x] = CXBolo.defaultterrain(Int32(x), Int32(y))
            }
        }
        for (run, data) in oracleRuns {
            var dataCopy = data
            let retval = dataCopy.withUnsafeMutableBytes { dbuf in
                cDecoded.withUnsafeMutableBufferPointer { tbuf in
                    CXBolo.writerun_flat(run, dbuf.baseAddress, tbuf.baseAddress)
                }
            }
            #expect(retval == 0, "C writerun_flat rejected a run it should accept")
        }

        // Decode the SAME oracle-produced runs via Swift writeRun into a
        // fresh mapDefault() grid
        var swiftDecoded = TerrainGrid.mapDefault()
        for (run, data) in oracleRuns {
            let swiftRun = BMapRun(datalen: run.datalen, y: run.y, startx: run.startx, endx: run.endx)
            let ok = BoloKit.writeRun(swiftRun, data: data, into: &swiftDecoded)
            #expect(ok, "Swift writeRun rejected a run it should accept")
        }

        #expect(cDecoded == swiftDecoded.storage, "decoded grids differ between C and Swift")
    }

    @Test func testReadWriteRunSwiftRoundTrip() {
        // Canonical-variant-only fixture (see buildFixtureTerrainArray doc)
        // so terrainToTile -> tileToTerrain is lossless for this grid.
        let original = fixtureTerrainGrid(from: buildFixtureTerrainArray())

        var y = 0
        var x = 0
        var runs: [(run: BMapRun, data: [UInt8])] = []
        while true {
            let (run, data, isLast) = BoloKit.readRun(grid: original, y: &y, x: &x)
            if isLast { break }
            runs.append((run, data))
        }

        var rebuilt = TerrainGrid.mapDefault()
        for (run, data) in runs {
            #expect(BoloKit.writeRun(run, data: data, into: &rebuilt))
        }

        #expect(rebuilt.storage == original.storage)
    }
}
