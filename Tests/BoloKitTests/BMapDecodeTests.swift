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
