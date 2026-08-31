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
}
