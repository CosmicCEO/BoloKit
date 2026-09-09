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

    // MARK: - serverPostProcessLoadedMap (D129)

    @Test func testServerNormalizeSiteTerrainMatchesOracle() {
        for terrain in Terrain.allCases {
            let c = CXBolo.serverloadmap_normalize_terrain_oracle(terrain.rawValue)
            let s = BoloKit.serverNormalizeSiteTerrain(terrain).rawValue
            #expect(c == s, "serverloadmap terrain normalization mismatch for \(terrain)")
        }
    }

    @Test func testServerPillSpeedRescaleMatchesOracle() {
        for raw in 0...255 {
            let c = CXBolo.serverloadmap_pillspeed_oracle(Int32(raw))
            let s = Int32(BoloKit.serverPillSpeedRescaled(UInt8(raw)))
            #expect(c == s, "serverloadmap pill speed rescale mismatch for raw \(raw)")
        }
    }

    /// Non-NEUTRAL owner in the file must be forced to NEUTRAL on the
    /// server's own load path -- `bmap_server.c:79,94` ("ignore
    /// pill/base owner") -- unlike `decodeBMap`/`clientloadmap()`, which
    /// keeps the stored owner byte verbatim.
    @Test func testServerPostProcessForcesNeutralOwner() {
        var state = GameState()
        state.terrain = .mapDefault()
        state.pills = [Pill(x: 20, y: 20, armour: 2, owner: 3, speed: 10, counter: 0)]
        state.bases = [Base(x: 30, y: 30, armour: 5, owner: 4, shells: 1, mines: 1)]

        serverPostProcessLoadedMap(&state)

        #expect(state.pills[0].owner == playerNeutral)
        #expect(state.bases[0].owner == playerNeutral)
    }

    /// A pill/base sitting on a "mined" terrain variant at load time must
    /// have that mine cleared -- `bmap_server.c:139-252` -- with no
    /// counterpart in `decodeBMap`. Also proves the `.minedRubble` ->
    /// `.grass0` fallthrough-bug result (`167-169`), not `.rubble0`.
    @Test func testServerPostProcessClearsMinesUnderPillsAndBases() {
        var state = GameState()
        state.terrain = .mapDefault()
        state.terrain[20, 20] = .minedRubble
        state.terrain[30, 30] = .minedSwamp
        state.pills = [Pill(x: 20, y: 20, armour: 2, owner: playerNeutral, speed: 0, counter: 0)]
        state.bases = [Base(x: 30, y: 30, armour: 5, owner: playerNeutral, shells: 1, mines: 1)]

        serverPostProcessLoadedMap(&state)

        #expect(state.terrain[20, 20] == .grass0)
        #expect(state.terrain[30, 30] == .swamp0)
    }

    /// Start locations clear to sea BEFORE pill/base normalization runs
    /// (`bmap_server.c:134-137` precedes `139-252`), so a pill sitting on
    /// a start tile normalizes from sea (a no-op, stays `.sea`... but sea
    /// is itself in the "clear to grass" bucket per the switch, so the
    /// observable result is `.grass0`), not from whatever was painted
    /// there before the start-clear ran.
    @Test func testServerPostProcessClearsStartsBeforeNormalizingPills() {
        var state = GameState()
        state.terrain = .mapDefault()
        state.terrain[15, 15] = .wall
        state.starts = [Start(x: 15, y: 15, dir: 0)]
        state.pills = [Pill(x: 15, y: 15, armour: 2, owner: playerNeutral, speed: 0, counter: 0)]

        serverPostProcessLoadedMap(&state)

        #expect(state.terrain[15, 15] == .grass0)
    }
}
