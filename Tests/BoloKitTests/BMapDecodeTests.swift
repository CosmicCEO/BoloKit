import Testing
import BoloKit

// Tests for `decodeBMap` (Wave 6.4a extension, D45) -- the `clientloadmap()`
// Swift port discovered missing while tracing what the client-side
// preamble-apply function needs.

private func encodeFullBMap(pills: [Pill], bases: [Base], starts: [Start], grid: TerrainGrid) -> [UInt8] {
    var bytes: [UInt8] = Array("BMAPBOLO".utf8)
    bytes.append(1)  // CURRENT_MAP_VERSION
    bytes.append(UInt8(pills.count))
    bytes.append(UInt8(bases.count))
    bytes.append(UInt8(starts.count))
    for p in pills {
        bytes += [p.x, p.y, p.owner, p.armour, p.speed]
    }
    for b in bases {
        bytes += [b.x, b.y, b.owner, b.armour, b.shells, b.mines]
    }
    for s in starts {
        bytes += [s.x, s.y, s.dir]
    }

    var y = 0
    var x = 0
    while true {
        let (run, data, isLast) = readRun(grid: grid, y: &y, x: &x)
        if isLast {
            bytes += [run.datalen, run.y, run.startx, run.endx]
            break
        }
        bytes += [run.datalen, run.y, run.startx, run.endx]
        bytes += data
    }
    return bytes
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
