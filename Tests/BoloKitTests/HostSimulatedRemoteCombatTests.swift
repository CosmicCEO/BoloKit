import Testing
import BoloKit

// #62 stage S2: with `hostSimulatesRemotePlayers` on, `runTick` runs the local-player combat code
// for every connected remote player (under `withSimulatedPlayer`), so the host is the source of
// truth for a remote tank's firing, mines, drowning, damage and respawn.

private func alivePlayer(x: Float, y: Float) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.used = true
    p.dead = false
    p.boat = false
    p.tank = Vec2f(x: x, y: y)
    return p
}

/// Two connected players on a grass patch: host (local, slot 0) far from the remote (slot 1).
private func twoPlayerState() -> GameState {
    var state = GameState()
    for y in 20..<70 { for x in 20..<70 { state.terrain[x, y] = .grass0 } }
    state.players = [alivePlayer(x: 30.5, y: 30.5), alivePlayer(x: 50.5, y: 50.5)]
    state.localPlayer = 0
    state.hostSimulatesRemotePlayers = true
    state.starts = [Start(x: 40, y: 40, dir: 0)]
    for p in 0..<2 {
        state.localStats[p].shells = 20
        state.localStats[p].armour = maxArmour
        state.localStats[p].range = 5.0
        state.localStats[p].shellCounter = shellFireThresholdTicks + 10
        state.players[p].mines = 10
    }
    return state
}

private func tick(_ state: inout GameState) {
    runTick(state: &state, ticksSinceLastUpdate: [0, 0])
}

// MARK: (a) firing and range

@Test func remotePlayerShootCreatesAShellAndSpendsItsOwnShellsOnly() {
    var state = twoPlayerState()
    state.players[1].inputFlags = [.shoot]
    tick(&state)
    #expect(state.players[1].shells.count == 1)
    #expect(state.localStats[1].shells == 19)
    #expect(state.localStats[0].shells == 20, "the host's own shells must be untouched")
    #expect(state.players[0].shells.isEmpty)
}

@Test func remotePlayerRangeKeysChangeItsOwnRangeOnly() {
    var state = twoPlayerState()
    state.players[1].inputFlags = [.incre]
    tick(&state)
    #expect(state.localStats[1].range > 5.0)
    #expect(state.localStats[0].range == 5.0)

    state.players[1].inputFlags = [.decre]
    let raised = state.localStats[1].range
    tick(&state)
    #expect(state.localStats[1].range < raised)
}

@Test func remoteSimulationIsOffByDefault() {
    var state = twoPlayerState()
    state.hostSimulatesRemotePlayers = false
    state.players[1].inputFlags = [.shoot]
    tick(&state)
    #expect(state.players[1].shells.isEmpty, "with the gate off, a remote's shoot flag does nothing on the host")
    #expect(state.localStats[1].shells == 20)
}
