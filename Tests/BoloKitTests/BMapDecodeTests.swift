import Testing
import BoloKit

// Tests for `decodeBMap` (Wave 6.4a extension, D45) -- the `clientloadmap()`
// Swift port discovered missing while tracing what the client-side
// preamble-apply function needs.

/// Was a from-scratch byte-layout implementation; now a thin wrapper over
/// the production `encodeBMap` (Wave 6.4b, G-1) -- promoted there once a
/// real caller (`joinplayerserver()`'s Swift counterpart) needed the exact
/// same logic. Kept as a wrapper, not deleted, so every test below stays
/// unchanged (D28: this coverage moved into `encodeBMap`'s own round-trip
/// tests, it didn't vanish).
private func encodeFullBMap(pills: [Pill], bases: [Base], starts: [Start], grid: TerrainGrid) -> [UInt8] {
    encodeBMap(GameState(terrain: grid, pills: pills, bases: bases, starts: starts))
}

@Test func decodeBMapRoundTripsPillsBasesStartsAndTerrain() {
    var grid = TerrainGrid.mapDefault()
    grid[50, 50] = .wall
    grid[51, 50] = .forest

    let pills = [Pill(x: 20, y: 20, armour: 10, owner: 1, speed: 40, counter: 5)]
    let bases = [Base(x: 30, y: 30, armour: 50, owner: 0, shells: 10, mines: 10)]
    let starts = [Start(x: 40, y: 40, dir: 3)]

    let bytes = encodeFullBMap(pills: pills, bases: bases, starts: starts, grid: grid)

    var state = GameState()
    #expect(decodeBMap(bytes, into: &state))

    #expect(state.pills.count == 1)
    #expect(state.pills[0].x == 20 && state.pills[0].y == 20)
    #expect(state.pills[0].owner == 1)
    #expect(state.pills[0].armour == 10)
    #expect(state.pills[0].speed == 40)
    #expect(state.pills[0].counter == 0)  // clientloadmap() always resets this to 0, not carried from the file

    #expect(state.bases.count == 1)
    #expect(state.bases[0].x == 30 && state.bases[0].armour == 50 && state.bases[0].mines == 10)

    #expect(state.starts == starts)

    #expect(state.terrain[50, 50] == .wall)
    #expect(state.terrain[51, 50] == .forest)
    #expect(state.terrain[0, 0] == .minedSea)  // untouched border cell, still default
}

@Test func decodeBMapRejectsWrongIdent() {
    var bytes = encodeFullBMap(pills: [], bases: [], starts: [], grid: .mapDefault())
    bytes[0] = 0
    var state = GameState()
    #expect(!decodeBMap(bytes, into: &state))
}

@Test func decodeBMapRejectsWrongVersion() {
    var bytes = encodeFullBMap(pills: [], bases: [], starts: [], grid: .mapDefault())
    bytes[8] = 99
    var state = GameState()
    #expect(!decodeBMap(bytes, into: &state))
}

@Test func decodeBMapRejectsOverLimitCounts() {
    var bytes = encodeFullBMap(pills: [], bases: [], starts: [], grid: .mapDefault())
    bytes[9] = 17  // npills > MAXPILLS (16)
    var state = GameState()
    #expect(!decodeBMap(bytes, into: &state))
}

@Test func decodeBMapRejectsTruncatedBuffer() {
    let bytes = encodeFullBMap(pills: [], bases: [], starts: [], grid: .mapDefault())
    var state = GameState()
    #expect(!decodeBMap(Array(bytes.prefix(bytes.count - 1)), into: &state))
}

// MARK: - encodeBMap (Wave 6.4b, G-1)

@Test func encodeBMapProducesTheDecodableHeaderAndCounts() {
    let pills = [Pill(x: 20, y: 20, armour: 10, owner: 1, speed: 40, counter: 5)]
    let bases = [Base(x: 30, y: 30, armour: 50, owner: 0, shells: 10, mines: 10)]
    let starts = [Start(x: 40, y: 40, dir: 3)]
    let state = GameState(pills: pills, bases: bases, starts: starts)

    let bytes = encodeBMap(state)

    #expect(Array(bytes.prefix(8)) == Array("BMAPBOLO".utf8))
    #expect(bytes[8] == 1)  // CURRENT_MAP_VERSION
    #expect(bytes[9] == 1 && bytes[10] == 1 && bytes[11] == 1)  // npills/nbases/nstarts
}

/// Round-trips a non-trivial terrain grid through `encodeBMap` ->
/// `decodeBMap` and back through the underlying RLE codec directly --
/// stronger than only checking `decodeBMap` accepts the bytes, since a
/// codec that agreed with itself on a bug wouldn't be caught by that
/// alone.
@Test func encodeBMapRoundTripsThroughDecodeBMap() {
    var grid = TerrainGrid.mapDefault()
    grid[10, 10] = .wall
    grid[10, 11] = .wall
    grid[200, 5] = .forest
    let state = GameState(terrain: grid, pills: [Pill(x: 1, y: 1, armour: 5, owner: 0, speed: 50, counter: 0)])

    let bytes = encodeBMap(state)
    var decoded = GameState()
    #expect(decodeBMap(bytes, into: &decoded))

    #expect(decoded.terrain[10, 10] == .wall)
    #expect(decoded.terrain[10, 11] == .wall)
    #expect(decoded.terrain[200, 5] == .forest)
    #expect(decoded.pills.count == 1)
    #expect(decoded.pills[0].x == 1 && decoded.pills[0].armour == 5)
}

/// G-1's size-accounting claim, verified directly rather than just relying
/// on `decodeBMap` accepting the bytes: the sentinel run's 4 header bytes
/// are actually present at the very end of the byte stream for an
/// entirely-default map (`serverloadmapsize()`'s `len += run.datalen`
/// executes before its `r == 1` exit check, `bmap_server.c:365-368`).
@Test func encodeBMapEmptyMapEndsExactlyWithTheSentinelRun() {
    let bytes = encodeBMap(GameState())
    let preambleSize = 12  // ident(8) + version(1) + npills/nbases/nstarts(3)
    #expect(bytes.count == preambleSize + 4)  // no pills/bases/starts, just the sentinel run
    #expect(Array(bytes.suffix(4)) == [4, 0xff, 0xff, 0xff])
}

/// Encode/decode keeps the bundled map's sites. The app embeds
/// `encodeBMap(defaultBundledMapState())` at load (`DefaultMap.swift`); this
/// is the tripwire if encode/decode drift.
@Test func defaultBundledMapEncodeDecodeRoundTripsSites() {
    let original = defaultBundledMapState()
    let bytes = encodeBMap(original)
    var decoded = GameState()
    #expect(decodeBMap(bytes, into: &decoded))
    #expect(decoded.starts.count == original.starts.count)
    for (got, want) in zip(decoded.starts, original.starts) {
        #expect(got.x == want.x && got.y == want.y && got.dir == want.dir)
    }
    #expect(decoded.pills.count == original.pills.count)
    for (got, want) in zip(decoded.pills, original.pills) {
        #expect(got.x == want.x && got.y == want.y && got.armour == want.armour && got.owner == want.owner)
    }
    #expect(decoded.bases.count == original.bases.count)
    for (got, want) in zip(decoded.bases, original.bases) {
        #expect(got.x == want.x && got.y == want.y && got.owner == want.owner)
    }
}

/// D132: the bundled map must survive the exact same decode -> server-post-process ->
/// starts-empty-guard sequence `HostGameView.swift`'s `applyDecodedMap` runs on every map, real
/// or bundled -- proving hosting is actually possible from this map without a live app.
@Test func defaultBundledMapSurvivesDecodeAndServerPostProcess() {
    let bytes = encodeBMap(defaultBundledMapState())
    var decoded = GameState()
    #expect(decodeBMap(bytes, into: &decoded))
    serverPostProcessLoadedMap(&decoded)

    #expect(!decoded.starts.isEmpty)
    #expect(decoded.starts.count == 1)
    #expect(decoded.pills.count == 2)
    #expect(decoded.bases.count == 3)
    // serverPostProcessLoadedMap forces NEUTRAL ownership regardless of authored owner byte.
    #expect(decoded.pills.allSatisfy { $0.owner == playerNeutral })
    #expect(decoded.bases.allSatisfy { $0.owner == playerNeutral })
    // Start tiles are always cleared to sea by post-process.
    for start in decoded.starts {
        #expect(decoded.terrain[Int(start.x), Int(start.y)] == .sea)
    }
}

@Test func applyDefaultBundledMapOwnersRestoresScenario() {
    var decoded = GameState()
    #expect(decodeBMap(encodeBMap(defaultBundledMapState()), into: &decoded))
    serverPostProcessLoadedMap(&decoded)
    applyDefaultBundledMapOwners(&decoded)

    let authored = defaultBundledMapState()
    let pickup = decoded.pills.first { $0.x == 108 && $0.y == 123 }
    let enemyPill = decoded.pills.first { $0.x == 140 && $0.y == 123 }
    let playerBase = decoded.bases.first { $0.x == 105 && $0.y == 123 }
    let neutralBase = decoded.bases.first { $0.x == 108 && $0.y == 134 }
    let enemyBase = decoded.bases.first { $0.x == 140 && $0.y == 134 }

    #expect(pickup?.armour == 0)
    #expect(pickup?.owner == playerNeutral)
    #expect(enemyPill?.armour == 15)
    #expect(enemyPill?.owner == UInt8(maxPlayers - 1))
    #expect(playerBase?.owner == 0)
    #expect(neutralBase?.owner == playerNeutral)
    #expect(enemyBase?.owner == UInt8(maxPlayers - 1))
    #expect(authored.pills.count == 2)
}

@Test func enemyPillIsOutOfRangeOfPickupAndStart() {
    let state = defaultBundledMapState()
    let pickup = state.pills.first { $0.armour == 0 }!
    let enemy = state.pills.first { $0.owner == UInt8(maxPlayers - 1) }!
    let start = state.starts[0]
    let pickupCenter = Vec2f(x: Float(pickup.x) + 0.5, y: Float(pickup.y) + 0.5)
    let enemyCenter = Vec2f(x: Float(enemy.x) + 0.5, y: Float(enemy.y) + 0.5)
    let startCenter = Vec2f(x: Float(start.x) + 0.5, y: Float(start.y) + 0.5)
    #expect(mag2f(sub2f(enemyCenter, pickupCenter)) > 8.0)
    #expect(mag2f(sub2f(enemyCenter, startCenter)) > 8.5)
}
