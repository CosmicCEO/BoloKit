import Testing
import BoloKit

private func connectedPlayer(dead: Bool = false, used: Bool = true) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.dead = dead
    p.used = used
    return p
}

private func makeState(players: [PlayerState], localPlayer: Int = 0) -> GameState {
    var state = GameState()
    state.players = players
    state.localPlayer = localPlayer
    state.terrain[50, 50] = .grass0
    return state
}

// MARK: - Player lifecycle

@Test func recvSrPlayerJoinSetsUsedConnectedAndSelfOnlyAlliance() {
    var state = makeState(players: [connectedPlayer(), PlayerState()])
    var notified: Int?
    recvSrPlayerJoin(player: 1, state: &state, onPlayerStatusChanged: { notified = $0 })
    #expect(state.players[1].used)
    #expect(state.players[1].connected)
    #expect(state.players[1].alliance == 1 << 1)
    #expect(notified == 1)
}

@Test func recvSrPlayerRejoinRefreshesOwnPillsOnlyWhenAboutTheLocalPlayer() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    state.players[0].alliance = 0b11
    state.players[1].alliance = 0b11
    state.pills = [Pill(x: 5, y: 5, armour: 10, owner: 1, speed: 10, counter: 0)]

    var pillNotified: [Int] = []
    recvSrPlayerRejoin(player: 1, state: &state, onPillStatusChanged: { pillNotified.append($0) })
    #expect(state.players[1].connected)
    #expect(pillNotified.isEmpty)  // rejoin was about player 1, not the local player (0)

    pillNotified = []
    recvSrPlayerRejoin(player: 0, state: &state, onPillStatusChanged: { pillNotified.append($0) })
    #expect(pillNotified == [0])  // rejoin about the local player refreshes allied pills
}

@Test func recvSrPlayerExitSetsDisconnected() {
    var state = makeState(players: [connectedPlayer()])
    var notified: Int?
    recvSrPlayerExit(player: 0, state: &state, onPlayerStatusChanged: { notified = $0 })
    #expect(!state.players[0].connected)
    #expect(notified == 0)
}

@Test func recvSrPlayerDiscSetsDisconnected() {
    var state = makeState(players: [connectedPlayer()])
    var notified: Int?
    recvSrPlayerDisc(player: 0, state: &state, onPlayerStatusChanged: { notified = $0 })
    #expect(!state.players[0].connected)
    #expect(notified == 0)
}

@Test func recvSrPlayerKickSetsDisconnected() {
    var state = makeState(players: [connectedPlayer()])
    var notified: Int?
    recvSrPlayerKick(player: 0, state: &state, onPlayerStatusChanged: { notified = $0 })
    #expect(!state.players[0].connected)
    #expect(notified == 0)
}

@Test func recvSrPlayerBanSetsDisconnected() {
    var state = makeState(players: [connectedPlayer()])
    var notified: Int?
    recvSrPlayerBan(player: 0, state: &state, onPlayerStatusChanged: { notified = $0 })
    #expect(!state.players[0].connected)
    #expect(notified == 0)
}

// MARK: - Terrain broadcasts

@Test func recvSrDamagePillDirectHitDecrementsArmourAndHeatsButNeverResetsAnyCounter() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 5, y: 5, armour: 3, owner: 1, speed: 20, counter: 7, coolCounter: 9)]
    recvSrDamage(player: 0, x: 5, y: 5, terrain: .grass0, state: &state)
    #expect(state.pills[0].armour == 2)
    #expect(state.pills[0].speed == 10)
    // Named regression: client.c's recvsrdamage resets neither counter,
    // unlike its server-side sibling recvcldamage (ported as heatPill).
    #expect(state.pills[0].counter == 7)
    #expect(state.pills[0].coolCounter == 9)
}

@Test func recvSrDamageBaseHitHeatsAlliedPillsWithinRangeOnly() {
    var players = [connectedPlayer(), connectedPlayer()]
    players[0].alliance = 0b11
    players[1].alliance = 0b11
    var state = makeState(players: players)
    state.bases = [Base(x: 10, y: 10, armour: UInt8(minBaseArmour), owner: 1, shells: 5, mines: 5)]
    state.pills = [
        Pill(x: 12, y: 10, armour: 20, owner: 0, speed: 20, counter: 0),  // allied, in range
        Pill(x: 200, y: 200, armour: 20, owner: 0, speed: 20, counter: 0),  // allied, out of range
    ]
    var baseNotified: Int?
    recvSrDamage(player: 0, x: 10, y: 10, terrain: .grass0, state: &state, onBaseStatusChanged: { baseNotified = $0 })
    #expect(state.bases[0].armour == 0)
    #expect(state.pills[0].speed == 10)
    #expect(state.pills[1].speed == 20)
    #expect(baseNotified == 0)
}

@Test func recvSrDamageAppliesGivenTerrainDirectlyAndCreatesExplosionForRemotePlayer() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[20, 20] = .grass0
    recvSrDamage(player: 1, x: 20, y: 20, terrain: .damagedWall2, state: &state)
    #expect(state.terrain[20, 20] == .damagedWall2)
    #expect(state.explosions.count == 1)
}

@Test func recvSrDamageBySelfDoesNotCreateExplosion() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 3)
    state.terrain[20, 20] = .grass0
    recvSrDamage(player: 3, x: 20, y: 20, terrain: .grass1, state: &state)
    #expect(state.explosions.isEmpty)
}

@Test func recvSrGrabTreesTurnsForestToGrassOrMinedForestToMinedGrass() {
    var state = makeState(players: [])
    state.terrain[20, 20] = .forest
    recvSrGrabTrees(x: 20, y: 20, state: &state)
    #expect(state.terrain[20, 20] == .grass0)

    state.terrain[21, 20] = .minedForest
    recvSrGrabTrees(x: 21, y: 20, state: &state)
    #expect(state.terrain[21, 20] == .minedGrass)
}

@Test func recvSrBuildAppliesGivenTerrainDirectly() {
    var state = makeState(players: [])
    state.terrain[20, 20] = .grass0
    recvSrBuild(x: 20, y: 20, terrain: .wall, state: &state)
    #expect(state.terrain[20, 20] == .wall)
}

@Test func recvSrGrowTurnsGrowableTerrainToForestOrMinedForest() {
    var state = makeState(players: [])
    state.terrain[20, 20] = .rubble2
    recvSrGrow(x: 20, y: 20, state: &state)
    #expect(state.terrain[20, 20] == .forest)

    state.terrain[21, 20] = .minedRoad
    recvSrGrow(x: 21, y: 20, state: &state)
    #expect(state.terrain[21, 20] == .minedForest)

    state.terrain[22, 20] = .wall
    recvSrGrow(x: 22, y: 20, state: &state)
    #expect(state.terrain[22, 20] == .wall)  // ungrowable terrain: no-op
}

@Test func recvSrFloodAlwaysSetsRiverUnconditionally() {
    var state = makeState(players: [])
    state.terrain[20, 20] = .crater
    recvSrFlood(x: 20, y: 20, state: &state)
    #expect(state.terrain[20, 20] == .river)
}

@Test func recvSrPlaceMineAndDropMineMineifyTerrainIdentically() {
    var state1 = makeState(players: [])
    state1.terrain[20, 20] = .grass2
    recvSrPlaceMine(x: 20, y: 20, state: &state1)
    #expect(state1.terrain[20, 20] == .minedGrass)

    var state2 = makeState(players: [])
    state2.terrain[20, 20] = .grass2
    recvSrDropMine(x: 20, y: 20, state: &state2)
    #expect(state2.terrain[20, 20] == .minedGrass)
}

@Test func recvSrDropBoatTurnsRiverToBoatOnly() {
    var state = makeState(players: [])
    state.terrain[20, 20] = .river
    recvSrDropBoat(x: 20, y: 20, state: &state)
    #expect(state.terrain[20, 20] == .boat)

    state.terrain[21, 20] = .grass0
    recvSrDropBoat(x: 21, y: 20, state: &state)
    #expect(state.terrain[21, 20] == .grass0)
}

// MARK: - Pill broadcasts

@Test func recvSrRepairPillSetsGivenArmour() {
    var state = makeState(players: [])
    state.pills = [Pill(x: 5, y: 5, armour: 0, owner: 1, speed: 20, counter: 0)]
    var notified: Int?
    recvSrRepairPill(pill: 0, armour: 15, state: &state, onPillStatusChanged: { notified = $0 })
    #expect(state.pills[0].armour == 15)
    #expect(notified == 0)
}

@Test func recvSrCoolPillIncrementsSpeedUnclamped() {
    var state = makeState(players: [])
    state.pills = [Pill(x: 5, y: 5, armour: 20, owner: 1, speed: 20, counter: 0)]
    recvSrCoolPill(pill: 0, state: &state)
    #expect(state.pills[0].speed == 21)
}

@Test func recvSrCapturePillSetsOwnerAndOnboardState() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 5, y: 5, armour: 0, owner: playerNeutral, speed: 20, counter: 0)]
    state.players[0].tank = Vec2f(x: 100, y: 100)  // not standing on the pill
    var notified: Int?
    recvSrCapturePill(pill: 0, owner: 0, state: &state, onPillStatusChanged: { notified = $0 })
    #expect(state.pills[0].owner == 0)
    #expect(state.pills[0].armour == pillOnboard)
    #expect(state.pills[0].speed == UInt8(maxTicksPerShot))
    #expect(notified == 0)
}

@Test func recvSrCapturePillLocalTankOnBoatTileRequestsGrabTileNotDirectMutation() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 20, counter: 0)]
    state.terrain[50, 50] = .boat
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    var requested: Pointi?
    recvSrCapturePill(pill: 0, owner: 0, state: &state, onRequestGrabTile: { requested = $0 })
    #expect(requested == Pointi(x: 50, y: 50))
    #expect(state.terrain[50, 50] == .boat)  // not mutated directly
}

@Test func recvSrCapturePillLocalTankOnSeaWithoutBoatDrownsDirectly() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 20, counter: 0)]
    state.terrain[50, 50] = .sea
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.players[0].boat = false
    state.players[0].dead = false
    state.local.respawnCounter = 0
    recvSrCapturePill(pill: 0, owner: 0, state: &state)
    #expect(state.players[0].dead)  // drown() killed the local tank directly
}

@Test func recvSrBuildPillSetsPositionArmourAndMaxSpeed() {
    var state = makeState(players: [])
    state.pills = [Pill(x: 0, y: 0, armour: 0, owner: playerNeutral, speed: 0, counter: 0)]
    var notified: Int?
    recvSrBuildPill(pill: 0, x: 30, y: 40, armour: 20, state: &state, onPillStatusChanged: { notified = $0 })
    #expect(state.pills[0].x == 30 && state.pills[0].y == 40)
    #expect(state.pills[0].armour == 20)
    #expect(state.pills[0].speed == UInt8(maxTicksPerShot))
    #expect(notified == 0)
}

@Test func recvSrDropPillSetsPositionZeroArmourAndMaxSpeed() {
    var state = makeState(players: [])
    state.pills = [Pill(x: 0, y: 0, armour: 5, owner: 0, speed: 0, counter: 0)]
    recvSrDropPill(pill: 0, x: 60, y: 70, state: &state)
    #expect(state.pills[0].x == 60 && state.pills[0].y == 70)
    #expect(state.pills[0].armour == 0)
    #expect(state.pills[0].speed == UInt8(maxTicksPerShot))
}

// MARK: - Base broadcasts

@Test func recvSrReplenishBaseIncrementsAllThreeResourcesClamped() {
    var state = makeState(players: [])
    state.bases = [Base(x: 5, y: 5, armour: UInt8(maxBaseArmour), owner: 0, shells: UInt8(maxBaseShells), mines: 3)]
    var notified: Int?
    recvSrReplenishBase(base: 0, state: &state, onBaseStatusChanged: { notified = $0 })
    #expect(state.bases[0].armour == UInt8(maxBaseArmour))  // clamped
    #expect(state.bases[0].shells == UInt8(maxBaseShells))  // clamped
    #expect(state.bases[0].mines == 4)
    #expect(notified == 0)
}

@Test func recvSrCaptureBaseFromNeutralFillsResourcesToMax() {
    var state = makeState(players: [])
    state.bases = [Base(x: 5, y: 5, armour: 0, owner: playerNeutral, shells: 0, mines: 0)]
    recvSrCaptureBase(base: 0, owner: 2, state: &state)
    #expect(state.bases[0].owner == 2)
    #expect(state.bases[0].armour == UInt8(maxBaseArmour))
    #expect(state.bases[0].shells == UInt8(maxBaseShells))
    #expect(state.bases[0].mines == UInt8(maxBaseMines))
}

@Test func recvSrCaptureBaseFromHostileZeroesResources() {
    var state = makeState(players: [])
    state.bases = [Base(x: 5, y: 5, armour: 20, owner: 1, shells: 20, mines: 20)]
    recvSrCaptureBase(base: 0, owner: 2, state: &state)
    #expect(state.bases[0].owner == 2)
    #expect(state.bases[0].armour == 0)
    #expect(state.bases[0].shells == 0)
    #expect(state.bases[0].mines == 0)
}

@Test func recvSrRefuelSubtractsGivenAmountsUnclamped() {
    var state = makeState(players: [])
    state.bases = [Base(x: 5, y: 5, armour: 40, owner: 0, shells: 40, mines: 40)]
    recvSrRefuel(base: 0, armour: 10, shells: 5, mines: 3, state: &state)
    #expect(state.bases[0].armour == 30)
    #expect(state.bases[0].shells == 35)
    #expect(state.bases[0].mines == 37)
}

@Test func recvSrGrabBoatSetsLocalBoatOnlyForLocalPlayerAndClearsTerrain() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    state.terrain[20, 20] = .boat
    recvSrGrabBoat(player: 1, x: 20, y: 20, state: &state)
    #expect(!state.players[0].boat)  // grab was about player 1, not local
    #expect(state.terrain[20, 20] == .river)

    state.terrain[21, 20] = .boat
    recvSrGrabBoat(player: 0, x: 21, y: 20, state: &state)
    #expect(state.players[0].boat)
}

// MARK: - Local acks

@Test func recvSrMineAckRefundsMineOnlyOnFailure() {
    var state = makeState(players: [connectedPlayer()])
    state.local.mines = 5
    recvSrMineAck(success: true, state: &state)
    #expect(state.local.mines == 5)

    recvSrMineAck(success: false, state: &state)
    #expect(state.local.mines == 6)
}

@Test func recvSrBuilderAckRoutesEachTaskToItsOwnResourceFieldAndTransitionsToWait() {
    var state = makeState(players: [connectedPlayer()])
    state.players[0].builderStatus = .work
    state.local.builderTask = .buildPill
    state.players[0].builderWait = 99
    recvSrBuilderAck(mines: 7, trees: 3, pill: 2, state: &state)
    #expect(state.local.builderTrees == 3)
    #expect(state.local.builderPill == 2)
    #expect(state.players[0].builderStatus == .wait)
    #expect(state.players[0].builderWait == 0)
}

@Test func recvSrBuilderAckPlaceMineRoutesToBuilderMinesNotTrees() {
    var state = makeState(players: [connectedPlayer()])
    state.players[0].builderStatus = .work
    state.local.builderTask = .placeMine
    recvSrBuilderAck(mines: 7, trees: 3, pill: 2, state: &state)
    #expect(state.local.builderMines == 7)
    #expect(state.players[0].builderStatus == .wait)
}

@Test func recvSrBuilderAckIgnoredOutsideWorkStatus() {
    var state = makeState(players: [connectedPlayer()])
    state.players[0].builderStatus = .goto
    state.local.builderTask = .buildPill
    recvSrBuilderAck(mines: 7, trees: 3, pill: 2, state: &state)
    #expect(state.players[0].builderStatus == .goto)  // untouched
}

// MARK: - Explosions

@Test func recvSrSmallBoomTurnsTerrainToCraterUnlessSeaOrMinedSea() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.players[0].tank = Vec2f(x: 200.5, y: 200.5)  // far from the blast, no damage cross-talk
    state.terrain[20, 20] = .grass0
    recvSrSmallBoom(player: 0, x: 20, y: 20, state: &state)
    #expect(state.terrain[20, 20] == .crater)

    state.terrain[21, 20] = .sea
    recvSrSmallBoom(player: 0, x: 21, y: 20, state: &state)
    #expect(state.terrain[21, 20] == .sea)
}

@Test func recvSrSmallBoomCreatesExplosionOnlyWhenNotCausedByLocalPlayer() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.players[0].tank = Vec2f(x: 200.5, y: 200.5)  // far from the blast, no damage cross-talk
    state.terrain[20, 20] = .grass0
    recvSrSmallBoom(player: 0, x: 20, y: 20, state: &state)
    #expect(state.explosions.isEmpty)

    recvSrSmallBoom(player: 1, x: 20, y: 20, state: &state)
    #expect(state.explosions.count == 1)
}

@Test func recvSrSmallBoomDamagesLocalTankWithinRadiusAndEscalates() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.local.armour = 5
    state.local.mines = 0
    state.local.shells = 0
    recvSrSmallBoom(player: 1, x: 50, y: 50, state: &state)
    #expect(state.local.armour == 0)
    #expect(state.players[0].dead)  // no mines/shells left: escalates to killTank
}

@Test func recvSrSmallBoomOutsideRadiusDoesNotDamageLocalTank() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 200.5, y: 200.5)
    state.local.armour = 5
    recvSrSmallBoom(player: 1, x: 50, y: 50, state: &state)
    #expect(state.local.armour == 5)
}

@Test func recvSrSuperBoomTurnsAllFourTilesToCraterExceptSea() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.players[0].tank = Vec2f(x: 200.5, y: 200.5)  // far from the blast, no damage cross-talk
    state.terrain[20, 20] = .grass0
    state.terrain[21, 20] = .sea
    state.terrain[20, 21] = .grass1
    state.terrain[21, 21] = .grass2
    recvSrSuperBoom(player: 0, x: 20, y: 20, state: &state)
    #expect(state.terrain[20, 20] == .crater)
    #expect(state.terrain[21, 20] == .sea)
    #expect(state.terrain[20, 21] == .crater)
    #expect(state.terrain[21, 21] == .crater)
}

@Test func recvSrSuperBoomDamagesLocalTankWithinRadiusAndEscalates() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 51] = .grass0
    state.terrain[51, 51] = .grass0
    state.players[0].tank = Vec2f(x: 51.0, y: 51.0)
    state.local.armour = 5
    state.local.mines = 0
    state.local.shells = 0
    recvSrSuperBoom(player: 1, x: 50, y: 50, state: &state)
    #expect(state.local.armour == 0)
    #expect(state.players[0].dead)
}

@Test func recvSrHitTankAppliesKickAndDamageEscalatingToKillTank() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 3
    state.players[0].boat = true
    recvSrHitTank(dir: 1.5, state: &state)
    #expect(state.players[0].kickDir == 1.5)
    #expect(state.players[0].kickSpeed == kickForce)
    #expect(!state.players[0].boat)
    #expect(state.local.armour == 0)
    #expect(state.players[0].dead)
}

@Test func recvSrHitTankSurvivesWhenArmourStaysPositive() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 20
    recvSrHitTank(dir: 0.0, state: &state)
    #expect(state.local.armour == 15)
    #expect(!state.players[0].dead)
}

// MARK: - Alliance / pause

@Test func recvSrSetAllianceAcceptedFiresStatusCallbacksForOwnedBasesAndPills() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    state.players[0].alliance = 1 << 1  // I've already allied with player 1
    state.bases = [Base(x: 1, y: 1, armour: 10, owner: 1, shells: 0, mines: 0)]
    state.pills = [Pill(x: 2, y: 2, armour: 10, owner: 1, speed: 10, counter: 0)]

    var playerNotified: Int?
    var baseNotified: Int?
    var pillNotified: Int?
    recvSrSetAlliance(
        player: 1, alliance: 1 << 0, state: &state,
        onPlayerStatusChanged: { playerNotified = $0 },
        onBaseStatusChanged: { baseNotified = $0 },
        onPillStatusChanged: { pillNotified = $0 }
    )
    #expect(state.players[1].alliance == 1 << 0)
    #expect(playerNotified == 1)
    #expect(baseNotified == 0)
    #expect(pillNotified == 0)
}

@Test func recvSrSetAllianceLeftRequestsLeaveAllianceRatherThanMutatingDirectly() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    state.players[0].alliance = 1 << 1  // I had allied with player 1
    state.players[1].alliance = 1 << 0  // they had allied back

    var leaveRequested: UInt16?
    recvSrSetAlliance(
        player: 1, alliance: 0, state: &state,  // their new alliance clears my bit
        onShouldLeaveAlliance: { leaveRequested = $0 }
    )
    #expect(state.players[1].alliance == 0)
    #expect(leaveRequested == (1 << 1))
    #expect(state.players[0].alliance == 1 << 1)  // not mutated directly here
}

@Test func recvSrSetAllianceRequestOnlyFiresNoStatusCallback() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    state.players[0].alliance = 0  // I have not allied with player 1
    var playerNotified: Int?
    recvSrSetAlliance(player: 1, alliance: 1 << 0, state: &state, onPlayerStatusChanged: { playerNotified = $0 })
    #expect(playerNotified == nil)
}

@Test func recvSrSetAllianceIgnoresChangeWhenMyOwnBitDidNotFlip() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    state.players[1].alliance = 1 << 2  // some other player's bit
    recvSrSetAlliance(player: 1, alliance: (1 << 2) | (1 << 3), state: &state)
    #expect(state.players[1].alliance == (1 << 2) | (1 << 3))  // still applied verbatim
}

@Test func recvSrPauseTranslatesSentinel255ToIndefiniteAndOthersLiterally() {
    var state = makeState(players: [])
    recvSrPause(pause: 255, state: &state)
    #expect(state.pause == -1)

    recvSrPause(pause: 10, state: &state)
    #expect(state.pause == 10)

    recvSrPause(pause: 0, state: &state)
    #expect(state.pause == 0)
}
