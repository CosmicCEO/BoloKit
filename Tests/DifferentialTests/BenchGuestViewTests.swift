import Testing
import BoloKit
import BoloNet

// v1.6.9 baseline benchmark: the host's expected guest view must follow the same rule the host
// sends reveals by, or the analyzer would report the redaction itself as a divergence.

private let tile = 121 * 256 + 102

@Test func withoutFogTheExpectedViewIsTheRealTerrain() {
    var terrain = TerrainGrid.mapDefault()
    terrain.storage[tile] = Terrain.minedRoad.rawValue
    let view = expectedGuestTerrainView(terrain: terrain, fogState: nil)
    #expect(view == digestTerrainView(terrain))
    #expect(view[tile] == UInt64(Terrain.minedRoad.rawValue))
}

@Test func tilesOutsideVisionAreUnknownOnBothSides() {
    let terrain = TerrainGrid.mapDefault()
    let fog = FogState()
    #expect(expectedGuestTerrainView(terrain: terrain, fogState: fog).allSatisfy { $0 == digestUnknownTerrain })
    #expect(observedGuestTerrainView(terrain: terrain, fogState: fog).allSatisfy { $0 == digestUnknownTerrain })
}

@Test func aVisibleMineTheObserverHasNotSeenIsExpectedUnmined() {
    var terrain = TerrainGrid.mapDefault()
    terrain.storage[tile] = Terrain.minedRoad.rawValue
    var fog = FogState()
    fog.fog[tile] = 1
    fog.seenTiles[tile] = .road
    let view = expectedGuestTerrainView(terrain: terrain, fogState: fog)
    #expect(view[tile] == UInt64(Terrain.road.rawValue))
    #expect(view[tile + 1] == digestUnknownTerrain)
}

@Test func aVisibleMineTheObserverHasSeenIsExpectedMined() {
    var terrain = TerrainGrid.mapDefault()
    terrain.storage[tile] = Terrain.minedRoad.rawValue
    var fog = FogState()
    fog.fog[tile] = 1
    fog.seenTiles[tile] = terrainToTile(Terrain.minedRoad)
    #expect(
        expectedGuestTerrainView(terrain: terrain, fogState: fog)[tile] == UInt64(Terrain.minedRoad.rawValue)
    )
}

@Test func theObservedViewReportsWhatTheGuestHoldsWhereItCanSee() {
    var terrain = TerrainGrid.mapDefault()
    terrain.storage[tile] = Terrain.forest.rawValue
    var fog = FogState()
    fog.fog[tile] = 2
    let view = observedGuestTerrainView(terrain: terrain, fogState: fog)
    #expect(view[tile] == UInt64(Terrain.forest.rawValue))
    #expect(view.filter { $0 != digestUnknownTerrain }.count == 1)
}
