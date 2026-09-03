import Testing
import BoloKit
import BoloNet

// Tests for `applyBoloPreamble` (Wave 6.4a extension, D45) -- the
// missing client-side preamble-application function PARITY's audit
// flagged.

private func samplePlayerEntries() -> [BoloPreamble.PlayerEntry] {
    (0..<maxPlayers).map { i in
        BoloPreamble.PlayerEntry(
            used: i < 2, connected: i < 2, seq: 0, name: i < 2 ? "Player\(i)" : "", host: "", alliance: UInt16(i)
        )
    }
}

private func encodedMap(with starts: [Start]) -> [UInt8] {
    var bytes: [UInt8] = Array("BMAPBOLO".utf8)
    bytes.append(1)  // version
    bytes.append(0)  // npills
    bytes.append(0)  // nbases
    bytes.append(UInt8(starts.count))
    for s in starts {
        bytes += [s.x, s.y, s.dir]
    }
    var y = 0
    var x = 0
    let grid = TerrainGrid.mapDefault()
    while true {
        let (run, data, isLast) = readRun(grid: grid, y: &y, x: &x)
        bytes += [run.datalen, run.y, run.startx, run.endx]
        if isLast { break }
        bytes += data
    }
    return bytes
}

@Test func applyBoloPreambleInitializesLocalPlayerAndSpawns() {
    let mapData = encodedMap(with: [Start(x: 128, y: 128, dir: 0)])
    let preamble = BoloPreamble(
        player: 1, hiddenMines: 1, pause: 255, dominationType: 1, baseControl: 60,
        players: samplePlayerEntries(), mapLength: UInt32(mapData.count)
    )
    var state = GameState()
    var playerNotified: [Int] = []

    let ok = applyBoloPreamble(preamble, mapData: mapData, state: &state, onPlayerStatusChanged: { playerNotified.append($0) })

    #expect(ok)
    #expect(state.localPlayer == 1)
    #expect(state.hiddenMines)
    #expect(state.clientPauseDisplaySeconds == -1)  // 255 sentinel
    #expect(state.dominationType == .tournament)
    #expect(state.players.count == maxPlayers)
    #expect(state.players[0].used)
    #expect(state.players[0].name == "Player0")
    #expect(state.players[0].builderStatus == .ready)
    #expect(!state.players[2].used)
    #expect(playerNotified.count == maxPlayers)
    #expect(!state.players[1].dead)  // spawn() ran -- local tank is alive
}

@Test func applyBoloPreambleFiniteAndZeroPauseTranslateLiterally() {
    let mapData = encodedMap(with: [Start(x: 128, y: 128, dir: 0)])
    var state = GameState()

    let finitePreamble = BoloPreamble(
        player: 0, hiddenMines: 0, pause: 10, dominationType: 0, baseControl: 0,
        players: samplePlayerEntries(), mapLength: UInt32(mapData.count)
    )
    applyBoloPreamble(finitePreamble, mapData: mapData, state: &state)
    #expect(state.clientPauseDisplaySeconds == 10)

    let zeroPreamble = BoloPreamble(
        player: 0, hiddenMines: 0, pause: 0, dominationType: 0, baseControl: 0,
        players: samplePlayerEntries(), mapLength: UInt32(mapData.count)
    )
    applyBoloPreamble(zeroPreamble, mapData: mapData, state: &state)
    #expect(state.clientPauseDisplaySeconds == 0)
}

@Test func applyBoloPreambleReturnsFalseOnMalformedMap() {
    var state = GameState()
    let preamble = BoloPreamble(
        player: 0, hiddenMines: 0, pause: 0, dominationType: 0, baseControl: 0,
        players: samplePlayerEntries(), mapLength: 3
    )
    #expect(!applyBoloPreamble(preamble, mapData: [1, 2, 3], state: &state))
}

@Test func applyBoloPreambleFiresPillAndBaseCallbacksAfterMapLoad() {
    var bytes: [UInt8] = Array("BMAPBOLO".utf8)
    bytes.append(1)
    bytes.append(1)  // npills
    bytes.append(1)  // nbases
    bytes.append(1)  // nstarts
    bytes += [20, 20, 1, 10, 40]  // pill: x,y,owner,armour,speed
    bytes += [30, 30, 0, 50, 10, 10]  // base: x,y,owner,armour,shells,mines
    bytes += [128, 128, 0]  // start
    var y = 0
    var x = 0
    let grid = TerrainGrid.mapDefault()
    while true {
        let (run, data, isLast) = readRun(grid: grid, y: &y, x: &x)
        bytes += [run.datalen, run.y, run.startx, run.endx]
        if isLast { break }
        bytes += data
    }

    let preamble = BoloPreamble(
        player: 0, hiddenMines: 0, pause: 0, dominationType: 0, baseControl: 0,
        players: samplePlayerEntries(), mapLength: UInt32(bytes.count)
    )
    var state = GameState()
    var pillNotified: [Int] = []
    var baseNotified: [Int] = []
    applyBoloPreamble(
        preamble, mapData: bytes, state: &state,
        onPillStatusChanged: { pillNotified.append($0) },
        onBaseStatusChanged: { baseNotified.append($0) }
    )
    #expect(pillNotified == [0])
    #expect(baseNotified == [0])
}
