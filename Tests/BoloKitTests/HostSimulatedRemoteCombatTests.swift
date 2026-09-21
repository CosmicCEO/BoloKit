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

// MARK: (b)/(c) terrain entry: mines, drowning, boat

/// Drives the remote east (dir 0) with accel held until `until` says stop, or `maxTicks` pass.
private func driveRemoteEast(_ state: inout GameState, maxTicks: Int = 400, until: (GameState) -> Bool) {
    state.players[1].dir = 0
    state.players[1].inputFlags = [.accel]
    for _ in 0..<maxTicks {
        tick(&state)
        if until(state) { break }
    }
}

@Test func remotePlayerDrivingOntoAMineDetonatesItAndLosesArmourHostUntouched() {
    var state = twoPlayerState()
    state.terrain[52, 50] = .minedGrass
    driveRemoteEast(&state) { $0.terrain[52, 50] != .minedGrass }
    #expect(state.terrain[52, 50] == .crater, "the detonated tile must change on the host")
    #expect(state.localStats[1].armour == maxArmour - smallboomDamage, "the remote takes the splash damage")
    #expect(state.localStats[0].armour == maxArmour, "the host's own armour must be untouched")
    #expect(state.players[0].dead == false)
}

@Test func remotePlayerDrivingIntoDeepWaterDrowns() {
    var state = twoPlayerState()
    state.terrain[52, 50] = .sea
    driveRemoteEast(&state) { $0.players[1].dead }
    #expect(state.players[1].dead)
    #expect(state.localStats[1].respawnCounter == explodeTicks + 1)
    #expect(state.players[0].dead == false)
}

@Test func remotePlayerOnABoatLosesTheBoatFlagOnceItIsOnLand() {
    var state = twoPlayerState()
    state.players[1].boat = true
    state.players[0].boat = true
    driveRemoteEast(&state, maxTicks: 60) { !$0.players[1].boat }
    #expect(state.players[1].boat == false)
    #expect(state.players[0].boat == true, "the host tank was not moving and keeps its boat")
}

// MARK: (d) shell hits on a remote tank

private func shellAt(_ point: Vec2f, owner: UInt8) -> Shell {
    Shell(point: point, dir: 0, range: 3.0, owner: owner, boat: false, pill: false)
}

@Test func shellHitOnARemoteTankReducesTheRemotesArmourNotTheHosts() {
    var state = twoPlayerState()
    state.players[0].shells = [shellAt(state.players[1].tank, owner: 0)]
    tick(&state)
    #expect(state.localStats[1].armour == maxArmour - shellDamage)
    #expect(state.localStats[0].armour == maxArmour)
    #expect(state.players[0].shells.isEmpty, "the shell is consumed by the hit")
    #expect(state.players[1].kickSpeed > 0, "the hit kicks the remote tank")
}

@Test func shellHitKillsARemoteTankAtZeroArmour() {
    var state = twoPlayerState()
    state.localStats[1].armour = shellDamage - 1
    state.players[0].shells = [shellAt(state.players[1].tank, owner: 0)]
    tick(&state)
    #expect(state.players[1].dead)
    #expect(state.localStats[1].armour == 0)
    #expect(state.localStats[1].deaths == 1)
    #expect(state.localStats[0].deaths == 0)
    #expect(state.players[0].dead == false)
}

@Test func shellHitOnARemoteTankIsIgnoredWhenTheGateIsOff() {
    var state = twoPlayerState()
    state.hostSimulatesRemotePlayers = false
    state.players[0].shells = [shellAt(state.players[1].tank, owner: 0)]
    tick(&state)
    #expect(state.localStats[1].armour == maxArmour, "gate off: today's behaviour, no remote armour pool")
}

// MARK: (e) multi-victim explosion damage

@Test func oneExplosionDamagesEveryTankInRadiusIncludingRemotes() {
    var state = twoPlayerState()
    state.players[0].tank = Vec2f(x: 31.2, y: 30.5)
    state.players[1].tank = Vec2f(x: 31.9, y: 30.5)
    state.terrain[31, 30] = .minedGrass
    explosionAt(player: UInt8(playerNeutral), x: 31, y: 30, state: &state)
    #expect(state.localStats[0].armour == maxArmour - smallboomDamage)
    #expect(state.localStats[1].armour == maxArmour - smallboomDamage, "the remote in the blast radius takes damage too")
}

@Test func explosionDoesNotDamageARemoteOutsideTheRadius() {
    var state = twoPlayerState()
    state.players[0].tank = Vec2f(x: 31.2, y: 30.5)
    state.terrain[31, 30] = .minedGrass
    explosionAt(player: UInt8(playerNeutral), x: 31, y: 30, state: &state)
    #expect(state.localStats[0].armour == maxArmour - smallboomDamage)
    #expect(state.localStats[1].armour == maxArmour, "the remote is 20 tiles away")
}

@Test func explosionLeavesARemoteAloneWhenTheGateIsOff() {
    var state = twoPlayerState()
    state.hostSimulatesRemotePlayers = false
    state.players[0].tank = Vec2f(x: 31.2, y: 30.5)
    state.players[1].tank = Vec2f(x: 31.9, y: 30.5)
    state.terrain[31, 30] = .minedGrass
    explosionAt(player: UInt8(playerNeutral), x: 31, y: 30, state: &state)
    #expect(state.localStats[1].armour == maxArmour)
}

// MARK: (f) respawn, and speed caps from the player's own tile

@Test func deadRemoteRespawnsAtAStartWithFullStatsAndTheHostIsUntouched() {
    var state = twoPlayerState()
    state.players[1].dead = true
    state.localStats[1].armour = 0
    state.localStats[1].respawnCounter = respawnTicks - 1
    tick(&state)
    #expect(state.players[1].dead == false, "the remote must respawn on the host")
    #expect(state.players[1].tank == Vec2f(x: 40.5, y: 40.5))
    #expect(state.localStats[1].armour == maxArmour)
    #expect(state.localStats[0].armour == maxArmour)
    #expect(state.players[0].dead == false)
    #expect(state.players[0].tank == Vec2f(x: 30.5, y: 30.5), "the host tank must not move")
}

@Test func deadRemoteStaysDeadWhenTheGateIsOff() {
    var state = twoPlayerState()
    state.hostSimulatesRemotePlayers = false
    state.players[1].dead = true
    state.localStats[1].respawnCounter = respawnTicks - 1
    tick(&state)
    #expect(state.players[1].dead, "gate off: only the local player's death/respawn machinery runs")
}

@Test func remoteSpeedCapComesFromTheRemotesOwnTileNotTheHostsTile() {
    var state = twoPlayerState()
    state.terrain[30, 30] = .swamp0  // under the (stationary) host tank: slow terrain
    driveRemoteEast(&state, maxTicks: 80) { $0.players[1].speed > rubbleMaxSpeed + 0.5 }
    #expect(state.players[1].speed > rubbleMaxSpeed, "the remote is on grass; the host's swamp must not cap it")
}
