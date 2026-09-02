import Testing
import BoloKit

private func connectedPlayer(dead: Bool = false, boat: Bool = false, used: Bool = true) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.dead = dead
    p.boat = boat
    p.used = used
    return p
}

private func makeState(players: [PlayerState], localPlayer: Int = 0, local: LocalPlayerState = LocalPlayerState()) -> GameState {
    var state = GameState()
    state.players = players
    state.localPlayer = localPlayer
    state.local = local
    // Safe default square — a bare GameState() puts (0,0) in the mined-sea
    // border ring, same pitfall recorded in TankLocalTickTests/ShellTickTests.
    state.terrain[50, 50] = .grass0
    return state
}

// MARK: - tankTest / tankOnABoatTest

@Test func tankTestFindsAliveConnectedTankOnSquare() {
    var p = connectedPlayer()
    p.tank = Vec2f(x: 5.5, y: 5.5)
    let state = makeState(players: [p])
    #expect(tankTest(x: 5, y: 5, state: state))
    #expect(!tankTest(x: 6, y: 6, state: state))
}

@Test func tankTestIgnoresDeadTank() {
    var p = connectedPlayer(dead: true)
    p.tank = Vec2f(x: 5.5, y: 5.5)
    let state = makeState(players: [p])
    #expect(!tankTest(x: 5, y: 5, state: state))
}

@Test func tankOnABoatTestRequiresBoat() {
    var p = connectedPlayer(boat: true)
    p.tank = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(players: [p])
    #expect(tankOnABoatTest(x: 5, y: 5, state: state))
    state.players[0].boat = false
    #expect(!tankOnABoatTest(x: 5, y: 5, state: state))
}

// MARK: - circleSquare

@Test func circleSquareInsideSquareIsTrue() {
    #expect(circleSquare(point: Vec2f(x: 5.5, y: 5.5), radius: builderRadius, square: Pointi(x: 5, y: 5)))
}

@Test func circleSquareFarAwayIsFalse() {
    #expect(!circleSquare(point: Vec2f(x: 50.5, y: 50.5), radius: builderRadius, square: Pointi(x: 5, y: 5)))
}

@Test func circleSquareOverlappingCornerIsTrueWithinRadius() {
    // Just outside the square's corner but within `radius` of it.
    let point = Vec2f(x: 5.0 - 0.05, y: 5.0 - 0.05)
    #expect(circleSquare(point: point, radius: builderRadius, square: Pointi(x: 5, y: 5)))
}

// MARK: - builderSpeed / builderTargetSpeed

@Test func builderSpeedArmedPillBlocks() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 0)]
    let speed = builderSpeed(x: 50, y: 50, player: 0, terrain: .grass0, pills: state.pills, bases: state.bases, players: state.players)
    #expect(speed == 0.0)
}

@Test func builderSpeedDeadPillAllowsFullSpeed() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 40, counter: 0)]
    let speed = builderSpeed(x: 50, y: 50, player: 0, terrain: .grass0, pills: state.pills, bases: state.bases, players: state.players)
    #expect(speed == builderMaxSpeed)
}

@Test func builderSpeedHostileResourcedBaseBlocks() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 1, shells: 0, mines: 0)]
    let speed = builderSpeed(x: 50, y: 50, player: 0, terrain: .grass0, pills: state.pills, bases: state.bases, players: state.players)
    #expect(speed == 0.0)
}

@Test func builderSpeedDeadBaseAllowsFullSpeed() {
    // builderSpeed accepts a dead (armour == 0) hostile base as passable —
    // unlike tankCollision, which has no such exception.
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: 0, owner: 1, shells: 0, mines: 0)]
    let speed = builderSpeed(x: 50, y: 50, player: 0, terrain: .grass0, pills: state.pills, bases: state.bases, players: state.players)
    #expect(speed == builderMaxSpeed)
}

@Test func builderTargetSpeedWallIsFullSpeedUnlikeTerrainBuilderSpeed() {
    let speed = builderTargetSpeed(x: 50, y: 50, terrain: .wall, pills: [], bases: [])
    #expect(speed == builderMaxSpeed)
}

@Test func builderTargetSpeedSeaIsImpassable() {
    let speed = builderTargetSpeed(x: 50, y: 50, terrain: .sea, pills: [], bases: [])
    #expect(speed == 0.0)
}

// MARK: - builderCollision

@Test func builderCollisionArmedPillBlocksUnlessRepairTarget() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 0)]
    let square = Pointi(x: 50, y: 50)

    let blockedForRoad = builderCollision(target: square, task: .buildRoad, owner: 0, state: state)
    #expect(blockedForRoad(square))

    let passableForRepair = builderCollision(target: square, task: .repairPill, owner: 0, state: state)
    #expect(!passableForRepair(square))
}

@Test func builderCollisionDeadPillNeverBlocks() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 40, counter: 0)]
    let collision = builderCollision(target: Pointi(x: 0, y: 0), task: .doNothing, owner: 0, state: state)
    #expect(!collision(Pointi(x: 50, y: 50)))
}

@Test func builderCollisionWallBlocksUnlessBuildWallTarget() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .wall
    let square = Pointi(x: 50, y: 50)

    let blocked = builderCollision(target: Pointi(x: 0, y: 0), task: .buildWall, owner: 0, state: state)
    #expect(blocked(square))

    let passable = builderCollision(target: square, task: .buildWall, owner: 0, state: state)
    #expect(!passable(square))
}

@Test func builderCollisionRiverBlocksUnlessBuildBoatOrRoadTarget() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .river
    let square = Pointi(x: 50, y: 50)

    #expect(builderCollision(target: Pointi(x: 0, y: 0), task: .buildBoat, owner: 0, state: state)(square))
    #expect(!builderCollision(target: square, task: .buildBoat, owner: 0, state: state)(square))
    #expect(!builderCollision(target: square, task: .buildRoad, owner: 0, state: state)(square))
    #expect(builderCollision(target: square, task: .buildWall, owner: 0, state: state)(square))
}

@Test func builderCollisionSeaAlwaysBlocks() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .sea
    let square = Pointi(x: 50, y: 50)
    #expect(builderCollision(target: square, task: .buildRoad, owner: 0, state: state)(square))
}

// MARK: - builderTick: ready → goto (resource checks)

@Test func readyGetTreeAlwaysStartsRegardlessOfResources() {
    var local = LocalPlayerState()
    local.builderTask = .getTree
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .goto)
    #expect(state.local.builderTrees == 0)
    #expect(state.local.builderPill == noPill)
}

@Test func readyBuildRoadFailsWithoutEnoughTreesAndDiscardsOrder() {
    var local = LocalPlayerState()
    local.builderTask = .buildRoad
    local.trees = roadTrees - 1
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .ready)
    #expect(state.local.builderTask == .doNothing)
    #expect(state.local.trees == roadTrees - 1)
}

@Test func readyBuildRoadSucceedsAndDeductsTrees() {
    var local = LocalPlayerState()
    local.builderTask = .buildRoad
    local.trees = 10
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .goto)
    #expect(state.local.trees == 10 - roadTrees)
    #expect(state.local.builderTrees == roadTrees)
}

@Test func readyBuildPillFailsWithoutFreeOnboardPill() {
    var local = LocalPlayerState()
    local.builderTask = .buildPill
    local.trees = 10
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)
    // No onboard pill owned by player 0.

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .ready)
    #expect(state.local.builderTask == .doNothing)
    #expect(state.local.trees == 10)
}

@Test func readyBuildPillReservesOnboardPill() {
    var local = LocalPlayerState()
    local.builderTask = .buildPill
    local.trees = 10
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)
    state.pills = [Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 40, counter: 0)]

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .goto)
    #expect(state.local.builderPill == 0)
    #expect(state.local.trees == 10 - pillTrees)
}

@Test func readyRepairPillComputesNeededTreesFromGroundTruthArmour() {
    var local = LocalPlayerState()
    local.builderTask = .repairPill
    local.trees = 20
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)
    // armour=3 -> needed = (15-3+3)/4 = 3 (integer division)
    state.pills = [Pill(x: 55, y: 55, armour: 3, owner: playerNeutral, speed: 40, counter: 0)]

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .goto)
    #expect(state.local.builderTrees == 3)
    #expect(state.local.trees == 20 - 3)
}

@Test func readyRepairPillWithNoPillAtTargetNeedsZeroTrees() {
    var local = LocalPlayerState()
    local.builderTask = .repairPill
    local.trees = 20
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.local.builderTrees == 0)
    #expect(state.local.trees == 20)
}

@Test func readyPlaceMineFailsWithoutMines() {
    var local = LocalPlayerState()
    local.builderTask = .placeMine
    local.mines = 0
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .ready)
    #expect(state.local.builderTask == .doNothing)
}

@Test func readyPlaceMineSucceedsAndReservesOneMine() {
    var local = LocalPlayerState()
    local.builderTask = .placeMine
    local.mines = 5
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 55, y: 55)
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .goto)
    #expect(state.local.builderMines == 1)
    #expect(state.local.mines == 4)
}

@Test func readyDoNothingIsNoOp() {
    var state = makeState(players: [connectedPlayer()])
    builderTick(player: 0, state: &state)
    #expect(state.players[0].builderStatus == .ready)
}

// MARK: - builderTick: goto (movement and arrival)

@Test func gotoMovesTowardTargetOnOpenTerrain() {
    var local = LocalPlayerState()
    local.builderTask = .getTree
    var player = connectedPlayer()
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderTarget = Pointi(x: 55, y: 50)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    for x in 50...56 { state.terrain[x, 50] = .grass0 }

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builder.x > 50.5)
    #expect(state.players[0].builderStatus == .goto)
}

@Test func gotoSnapsToCenterOnFinalStep() {
    var local = LocalPlayerState()
    local.builderTask = .getTree
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    // Extremely close, but not within the 0.00001 "arrived" epsilon.
    player.builder = Vec2f(x: 50.5001, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builder == Vec2f(x: 50.5, y: 50.5))
}

@Test func gotoArrivalOnGetTreeHarvestsForestAndTransitionsToWait() {
    var local = LocalPlayerState()
    local.builderTask = .getTree
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    state.terrain[50, 50] = .forest

    builderTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .grass3)
    #expect(state.local.builderTrees == forestTreeYield)
    #expect(state.players[0].builderStatus == .wait)
    #expect(state.players[0].builderWait == 0)
}

@Test func gotoArrivalOnGetTreeOverMinedTerrainTriggersExplosionInsteadOfHarvest() {
    var local = LocalPlayerState()
    local.builderTask = .getTree
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    state.terrain[50, 50] = .minedGrass

    var exploded: Pointi?
    builderTick(player: 0, state: &state, onMineExplosion: { exploded = $0 })

    #expect(exploded == Pointi(x: 50, y: 50))
    #expect(state.local.builderTrees == 0)
    #expect(state.players[0].builderStatus == .wait)
}

@Test func gotoArrivalOnBuildRoadTautologyAlwaysSucceedsGivenAnyPositiveTrees() {
    // D24 (PLANNER-ruled): C's `if (trees >= trees)` in recvclbuildroad is
    // a tautology — always true regardless of how few trees are held. This
    // regression test documents that intentionally-replicated shape: even
    // a single tree (below roadTrees=2) still "succeeds" once work begins,
    // because the real gate already happened at READY time. Guards against
    // anyone "fixing" this to a real `trees >= roadTrees` check later.
    var local = LocalPlayerState()
    local.builderTask = .buildRoad
    local.builderTrees = 1
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    state.terrain[50, 50] = .grass0

    builderTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .road)
    #expect(state.local.builderTrees == 1 - roadTrees)
}

@Test func gotoArrivalOnBuildRoadBlockedByBoatedTankSkipsWorkWithoutRefund() {
    var local = LocalPlayerState()
    local.builderTask = .buildRoad
    local.builderTrees = roadTrees
    var blocker = connectedPlayer(boat: true)
    blocker.tank = Vec2f(x: 50.5, y: 50.5)
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player, blocker], local: local)
    state.terrain[50, 50] = .grass0

    builderTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .grass0)
    #expect(state.local.builderTrees == roadTrees)
    #expect(state.players[0].builderStatus == .wait)
}

@Test func gotoArrivalOnBuildWallBlockedByAnyTank() {
    var local = LocalPlayerState()
    local.builderTask = .buildWall
    local.builderTrees = wallTrees
    var blocker = connectedPlayer()  // not even boated — tankTest doesn't care
    blocker.tank = Vec2f(x: 50.5, y: 50.5)
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player, blocker], local: local)
    state.terrain[50, 50] = .grass0

    builderTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .grass0)
    #expect(state.local.builderTrees == wallTrees)
}

@Test func gotoArrivalOnBuildPillPlacesReservedPillAndRefundsExcessTrees() {
    var local = LocalPlayerState()
    local.builderTask = .buildPill
    local.builderTrees = 10
    local.builderPill = 0
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    state.terrain[50, 50] = .grass0
    state.pills = [Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 40, counter: 0)]

    builderTick(player: 0, state: &state)

    #expect(state.pills[0].x == 50)
    #expect(state.pills[0].y == 50)
    #expect(state.pills[0].owner == 0)
    #expect(state.pills[0].armour == UInt8(maxPillArmour))
    // 10 trees * 4 = 40 armour, clamped to 15, refund (40-15)/4 = 6.
    #expect(state.local.builderTrees == 6)
}

@Test func gotoArrivalOnRepairPillAddsArmourAndRefundsExcess() {
    var local = LocalPlayerState()
    local.builderTask = .repairPill
    local.builderTrees = 5
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    state.terrain[50, 50] = .grass0
    state.pills = [Pill(x: 50, y: 50, armour: 5, owner: playerNeutral, speed: 40, counter: 0)]

    builderTick(player: 0, state: &state)

    // 5 + 5*4 = 25, clamped to 15, refund (25-15)/4 = 2.
    #expect(state.pills[0].armour == UInt8(maxPillArmour))
    #expect(state.local.builderTrees == 2)
}

@Test func gotoArrivalOnPlaceMineMinesTerrainAndAlwaysZeroesMinesEvenOnFailure() {
    var local = LocalPlayerState()
    local.builderTask = .placeMine
    local.builderMines = 1
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    state.terrain[50, 50] = .grass0

    builderTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .minedGrass)
    #expect(state.local.builderMines == 0)
}

@Test func gotoArrivalOnPlaceMineOnUnmineableTerrainStillZeroesMines() {
    var local = LocalPlayerState()
    local.builderTask = .placeMine
    local.builderMines = 1
    var player = connectedPlayer()
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .goto
    var state = makeState(players: [player], local: local)
    state.terrain[50, 50] = .wall  // not mineable — no-op terrain-wise

    builderTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .wall)
    #expect(state.local.builderMines == 0)
}

// MARK: - builderTick: wait

@Test func waitTransitionsToReturnAfterBuilderBuildTimeUsingPostIncrementSemantics() {
    var player = connectedPlayer()
    player.builderStatus = .wait
    player.builderWait = builderBuildTime  // old value == threshold: not yet > threshold
    var state = makeState(players: [player])

    builderTick(player: 0, state: &state)
    #expect(state.players[0].builderStatus == .wait)
    #expect(state.players[0].builderWait == builderBuildTime + 1)

    builderTick(player: 0, state: &state)
    #expect(state.players[0].builderStatus == .return)
}

// MARK: - builderTick: return

@Test func returnEntersTankAndRefundsLeftoverResourcesForLocalPlayer() {
    var local = LocalPlayerState()
    local.builderTask = .buildRoad
    local.builderTrees = 3
    local.builderMines = 1
    local.trees = 10
    local.mines = 10
    var player = connectedPlayer()
    player.tank = Vec2f(x: 50.5, y: 50.5)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderTarget = Pointi(x: 60, y: 60)
    player.builderStatus = .return
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .ready)
    #expect(state.players[0].builderTarget == Pointi(x: 0, y: 0))
    #expect(state.local.builderTask == .doNothing)
    #expect(state.local.trees == 13)
    #expect(state.local.mines == 11)
    #expect(state.local.builderTrees == 0)
    #expect(state.local.builderMines == 0)
}

@Test func returnRefundClampsToMaxTreesAndMines() {
    var local = LocalPlayerState()
    local.builderTrees = maxTrees
    local.builderMines = maxMines
    local.trees = maxTrees
    local.mines = maxMines
    var player = connectedPlayer()
    player.tank = Vec2f(x: 50.5, y: 50.5)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderStatus = .return
    var state = makeState(players: [player], local: local)

    builderTick(player: 0, state: &state)

    #expect(state.local.trees == maxTrees)
    #expect(state.local.mines == maxMines)
}

@Test func returnRemotePlayerEntersTankWithoutTouchingLocalResourcePools() {
    var local = LocalPlayerState()
    local.trees = 5
    local.mines = 5
    var remote = connectedPlayer()
    remote.tank = Vec2f(x: 50.5, y: 50.5)
    remote.builder = Vec2f(x: 50.5, y: 50.5)
    remote.builderStatus = .return
    let localPlayer = connectedPlayer()
    var state = makeState(players: [localPlayer, remote], localPlayer: 0, local: local)

    builderTick(player: 1, state: &state)

    #expect(state.players[1].builderStatus == .ready)
    // No LocalPlayerState pool to refund into for a remote player.
    #expect(state.local.trees == 5)
    #expect(state.local.mines == 5)
}

@Test func returnDeadPlayerIsNoOp() {
    var player = connectedPlayer(dead: true)
    player.builderStatus = .return
    player.builder = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [player])

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .return)
}

@Test func returnMovesTowardTankWhenFar() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 55.5, y: 50.5)
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builderStatus = .return
    var state = makeState(players: [player])
    for x in 50...56 { state.terrain[x, 50] = .grass0 }

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builder.x > 50.5)
    #expect(state.players[0].builderStatus == .return)
}

// MARK: - builderTick: parachute

@Test func parachuteDescendsTowardTarget() {
    var player = connectedPlayer()
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderTarget = Pointi(x: 60, y: 50)
    player.builderStatus = .parachute
    var state = makeState(players: [player])

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builder.x > 50.5)
    #expect(state.players[0].builderStatus == .parachute)
}

@Test func parachuteArrivalTransitionsToReturn() {
    var player = connectedPlayer()
    player.builder = Vec2f(x: 50.5, y: 50.5)
    player.builderTarget = Pointi(x: 50, y: 50)
    player.builderStatus = .parachute
    var state = makeState(players: [player])

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .return)
    #expect(state.players[0].builderTarget == Pointi(x: 0, y: 0))
}

// MARK: - builderTick: connected/work guards

@Test func builderTickDisconnectedPlayerIsNoOp() {
    var player = connectedPlayer()
    player.connected = false
    player.builderStatus = .goto
    var state = makeState(players: [player])
    let before = state.players[0]

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builder == before.builder)
    #expect(state.players[0].builderStatus == before.builderStatus)
}

@Test func builderTickWorkStatusIsNoOp() {
    // Unreachable in this port (see file header) but kept for
    // switch-exhaustiveness; verify it's genuinely inert if ever entered.
    var player = connectedPlayer()
    player.builderStatus = .work
    var state = makeState(players: [player])

    builderTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .work)
}
