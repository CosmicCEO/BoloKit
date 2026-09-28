import BoloKit

// MARK: - Expected guest terrain view (v1.6.9 baseline benchmark)
//
// Measurement only. What the host believes one guest's terrain should hold right now, for
// comparison against what that guest actually holds. Lives here rather than in BoloKit's
// `StateDigest.swift` because it has to apply the same rule the host sends by, and that rule's
// `unminedTerrain` is this module's.

/// One value per tile for `StateDigestTracker.sampleTerrain`.
///
/// With Hidden Mines off (`fogState == nil`) the guest is sent everything, so this is the real
/// terrain. With it on, a tile outside the guest's current vision is `digestUnknownTerrain`:
/// the host stops reporting changes there by design, so a stale guest value is not a fault.
/// A visible tile follows `queueReveals` (`HostGameEngine.updateFogVision`) exactly: the real
/// terrain if that observer's `seenTiles` already shows it, else its unmined substitute.
public func expectedGuestTerrainView(terrain: TerrainGrid, fogState: FogState?) -> [UInt64] {
    guard let fogState else { return digestTerrainView(terrain) }
    let count = min(terrain.storage.count, fogState.fog.count, fogState.seenTiles.count)
    var view = [UInt64](repeating: digestUnknownTerrain, count: terrain.storage.count)
    for index in 0..<count where fogState.fog[index] > 0 {
        let real = Terrain(rawValue: terrain.storage[index]) ?? .sea
        let expected = fogState.seenTiles[index] == terrainToTile(real) ? real : unminedTerrain(real)
        view[index] = UInt64(UInt32(bitPattern: expected.rawValue))
    }
    return view
}

/// The guest's side of the same comparison: its own terrain, with tiles outside its own
/// current vision marked unknown so both logs leave out the same kind of tile.
public func observedGuestTerrainView(terrain: TerrainGrid, fogState: FogState?) -> [UInt64] {
    guard let fogState else { return digestTerrainView(terrain) }
    let count = min(terrain.storage.count, fogState.fog.count)
    var view = [UInt64](repeating: digestUnknownTerrain, count: terrain.storage.count)
    for index in 0..<count where fogState.fog[index] > 0 {
        view[index] = UInt64(UInt32(bitPattern: terrain.storage[index]))
    }
    return view
}
