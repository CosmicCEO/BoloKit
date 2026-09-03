import Testing
import BoloKit

private func makeAliveState(player: PlayerState) -> GameState {
    var state = GameState()
    state.players = [player]
    state.localPlayer = 0
    return state
}

private func connectedPlayer(dead: Bool = false) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.dead = dead
    return p
}

// MARK: - isShore

@Test func isShoreOutOfBoundsIsFalse() {
    let grid = TerrainGrid.mapDefault()
    #expect(!isShore(x: -1, y: 0, terrain: grid, bases: []))
    #expect(!isShore(x: 256, y: 0, terrain: grid, bases: []))
    #expect(!isShore(x: 0, y: -1, terrain: grid, bases: []))
    #expect(!isShore(x: 0, y: 256, terrain: grid, bases: []))
}

@Test func isShoreBaseAlwaysTrueRegardlessOfTerrain() {
    let grid = TerrainGrid.mapDefault()  // (50,50) is sea by default
    let bases = [Base(x: 50, y: 50, armour: 0, owner: 0, shells: 0, mines: 0)]
    #expect(isShore(x: 50, y: 50, terrain: grid, bases: bases))
}

@Test func isShoreWaterTerrainIsFalse() {
    var grid = TerrainGrid.mapDefault()
    grid[50, 50] = .sea
    #expect(!isShore(x: 50, y: 50, terrain: grid, bases: []))
    grid[50, 50] = .river
    #expect(!isShore(x: 50, y: 50, terrain: grid, bases: []))
    grid[50, 50] = .minedSea
    #expect(!isShore(x: 50, y: 50, terrain: grid, bases: []))
}

@Test func isShoreLandTerrainIsTrue() {
    var grid = TerrainGrid.mapDefault()
    grid[50, 50] = .grass3
    #expect(isShore(x: 50, y: 50, terrain: grid, bases: []))
    grid[50, 50] = .forest
    #expect(isShore(x: 50, y: 50, terrain: grid, bases: []))
    grid[50, 50] = .boat
    #expect(isShore(x: 50, y: 50, terrain: grid, bases: []))
}

// MARK: - tankCollision

@Test func tankCollisionOutOfBoundsIsSolid() {
    let state = makeAliveState(player: connectedPlayer())
    let isSolid = tankCollision(owner: 0, state: state)
    #expect(isSolid(Pointi(x: -1, y: 0)))
    #expect(isSolid(Pointi(x: 256, y: 0)))
}

@Test func tankCollisionArmedPillIsSolid() {
    var state = makeAliveState(player: connectedPlayer())
    state.pills = [Pill(x: 5, y: 5, armour: 10, owner: 0, speed: 50, counter: 0)]
    let isSolid = tankCollision(owner: 0, state: state)
    #expect(isSolid(Pointi(x: 5, y: 5)))
}

@Test func tankCollisionDeadPillIsPassable() {
    var state = makeAliveState(player: connectedPlayer())
    state.pills = [Pill(x: 5, y: 5, armour: 0, owner: 0, speed: 50, counter: 0)]
    let isSolid = tankCollision(owner: 0, state: state)
    #expect(!isSolid(Pointi(x: 5, y: 5)))
}

@Test func tankCollisionHostileBaseAtThresholdIsSolid() {
    // Inclusive >= minBaseArmour(5), contrast buildercollision's exclusive >.
    var state = makeAliveState(player: connectedPlayer())
    state.bases = [Base(x: 5, y: 5, armour: UInt8(minBaseArmour), owner: 1, shells: 0, mines: 0)]
    let isSolid = tankCollision(owner: 0, state: state)
    #expect(isSolid(Pointi(x: 5, y: 5)))
}

@Test func tankCollisionNeutralBaseIsPassable() {
    var state = makeAliveState(player: connectedPlayer())
    state.bases = [Base(x: 5, y: 5, armour: 90, owner: playerNeutral, shells: 0, mines: 0)]
    let isSolid = tankCollision(owner: 0, state: state)
    #expect(!isSolid(Pointi(x: 5, y: 5)))
}

@Test func tankCollisionWallIsSolidWaterIsNot() {
    var state = makeAliveState(player: connectedPlayer())
    state.terrain[5, 5] = .wall
    state.terrain[6, 6] = .sea
    let isSolid = tankCollision(owner: 0, state: state)
    #expect(isSolid(Pointi(x: 5, y: 5)))
    #expect(!isSolid(Pointi(x: 6, y: 6)))
}

// MARK: - tankMoveTick: dead-tank branch

@Test func tankMoveTickIgnoresDisconnectedPlayer() {
    var player = connectedPlayer(dead: true)
    player.connected = false
    var state = makeAliveState(player: player)
    let before = state.players[0]
    tankMoveTick(player: 0, state: &state)
    #expect(state.players[0].tank == before.tank)
    #expect(state.local.respawnCounter == 0)
}

@Test func tankMoveTickDeadBranchOnlyDrivesLocalPlayer() {
    // player == localPlayer is required — a dead non-local player is a no-op.
    var p0 = connectedPlayer(dead: true)
    p0.tank = Vec2f(x: 10, y: 10)
    var p1 = connectedPlayer(dead: true)
    p1.tank = Vec2f(x: 20, y: 20)
    var state = makeAliveState(player: p0)
    state.players.append(p1)
    state.localPlayer = 0

    tankMoveTick(player: 1, state: &state)
    #expect(state.players[1].tank == Vec2f(x: 20, y: 20))
    #expect(state.local.respawnCounter == 0)
}

@Test func tankMoveTickDeadTumbleAdvancesRespawnCounterAndMoves() {
    var player = connectedPlayer(dead: true)
    player.tank = Vec2f(x: 128, y: 128)
    player.kickDir = 0  // dir2vec(0) = (1, 0)
    player.kickSpeed = 5.0
    var state = makeAliveState(player: player)
    state.local.respawnCounter = 0

    tankMoveTick(player: 0, state: &state)

    #expect(state.local.respawnCounter == 1)
    // tank += dir2vec(0) * (5.0/50) = (0.1, 0)
    #expect(abs(state.players[0].tank.x - 128.1) < 0.0001)
    #expect(abs(state.players[0].tank.y - 128.0) < 0.0001)
}

@Test func tankMoveTickDeadTumbleSkipsExplosionOverGrass1AndGrass2Bug() {
    // BUG (replicated): the C explosion-skip check compares against tile
    // enum values 16/17, which are grass1/grass2 in this port's Terrain
    // raw-value ordering — NOT sea/minedSea. Real sea/minedSea always
    // spawn the explosion; only these two grass variants suppress it.
    for (terrain, shouldSkip) in [
        (Terrain.grass1, true),
        (Terrain.grass2, true),
        (Terrain.sea, false),
        (Terrain.minedSea, false),
        (Terrain.grass3, false),
    ] {
        var player = connectedPlayer(dead: true)
        player.tank = Vec2f(x: 128, y: 128)
        player.kickSpeed = 0
        var state = makeAliveState(player: player)
        state.terrain[128, 128] = terrain
        state.local.respawnCounter = 4  // next tick makes it 5, triggers the every-5-ticks check

        tankMoveTick(player: 0, state: &state)

        let explosionSpawned = !state.players[0].explosions.isEmpty
        #expect(explosionSpawned == !shouldSkip, "terrain=\(terrain) shouldSkip=\(shouldSkip)")
    }
}

@Test func tankMoveTickExplodeTicksBoundarySuperboom() {
    var player = connectedPlayer(dead: true)
    var state = makeAliveState(player: player)
    state.local.respawnCounter = explodeTicks - 1  // next tick == explodeTicks exactly
    state.local.mines = 32
    var superboomFired = false
    tankMoveTick(player: 0, state: &state, onSuperboom: { superboomFired = true })
    #expect(superboomFired)
    _ = player
}

// Wave 5.9: the explodeTicks boundary now also calls the real superboom(),
// which detonates the 2x2 tile area under the tank via superboomAt.
@Test func tankMoveTickDeadTumbleSuperboomDetonatesTerrain() {
    var player = connectedPlayer(dead: true)
    player.tank = Vec2f(x: 50.6, y: 50.6)  // frac >= 0.5, origin stays (50, 50)
    var state = makeAliveState(player: player)
    state.local.respawnCounter = explodeTicks - 1
    state.local.mines = 32
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 51] = .grass0
    state.terrain[51, 51] = .grass0

    tankMoveTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .crater)
    #expect(state.terrain[51, 50] == .crater)
    #expect(state.terrain[50, 51] == .crater)
    #expect(state.terrain[51, 51] == .crater)
}

@Test func tankMoveTickExplodeTicksBoundarySmallboom() {
    var player = connectedPlayer(dead: true)
    var state = makeAliveState(player: player)
    state.local.respawnCounter = explodeTicks - 1
    state.local.mines = 0
    state.local.shells = 1
    var smallboomFired = false
    var superboomFired = false
    tankMoveTick(player: 0, state: &state, onSuperboom: { superboomFired = true }, onSmallboom: { smallboomFired = true })
    #expect(smallboomFired)
    #expect(!superboomFired)
    _ = player
}

// Wave 5.9: same as above for the real smallboom()/explosionAt path.
@Test func tankMoveTickDeadTumbleSmallboomDetonatesTerrain() {
    var player = connectedPlayer(dead: true)
    player.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeAliveState(player: player)
    state.local.respawnCounter = explodeTicks - 1
    state.local.mines = 0
    state.local.shells = 1
    state.terrain[50, 50] = .minedGrass

    tankMoveTick(player: 0, state: &state)

    #expect(state.terrain[50, 50] == .crater)
}

// Wave 5.9: the periodic corpse-explosion sub-branch (every 5 ticks) now
// also kills a builder in range, matching client.c:4002's direct
// killpointbuilder(explosion->point) call.
@Test func tankMoveTickDeadTumbleExplosionKillsPointBuilder() {
    var player = connectedPlayer(dead: true)
    player.tank = Vec2f(x: 128, y: 128)
    player.kickSpeed = 0
    player.builderStatus = .work
    player.builder = Vec2f(x: 128, y: 128)
    var state = makeAliveState(player: player)
    state.starts = [Start(x: 10, y: 20, dir: 0)]
    state.local.respawnCounter = 4  // next tick makes it 5, triggers the every-5-ticks check

    tankMoveTick(player: 0, state: &state)

    #expect(state.players[0].builderStatus == .parachute)
}

@Test func tankMoveTickExplodeTicksBoundaryNeitherBoomFires() {
    var player = connectedPlayer(dead: true)
    var state = makeAliveState(player: player)
    state.local.respawnCounter = explodeTicks - 1
    state.local.mines = 0
    state.local.shells = 0
    var anyBoomFired = false
    tankMoveTick(
        player: 0, state: &state,
        onSuperboom: { anyBoomFired = true }, onSmallboom: { anyBoomFired = true }
    )
    #expect(!anyBoomFired)
    _ = player
}

@Test func tankMoveTickDeadZoneDoesNothing() {
    var player = connectedPlayer(dead: true)
    player.tank = Vec2f(x: 128, y: 128)
    var state = makeAliveState(player: player)
    state.local.respawnCounter = explodeTicks  // next tick lands in (explodeTicks, respawnTicks)
    var effectsFired = false
    tankMoveTick(
        player: 0, state: &state,
        onExplosion: { _ in effectsFired = true },
        onSuperboom: { effectsFired = true },
        onSmallboom: { effectsFired = true },
        onSpawn: { effectsFired = true }
    )
    #expect(!effectsFired)
    #expect(state.players[0].tank == Vec2f(x: 128, y: 128))
}

@Test func tankMoveTickRespawnTicksBoundaryCallsSpawn() {
    var player = connectedPlayer(dead: true)
    var state = makeAliveState(player: player)
    state.local.respawnCounter = respawnTicks - 1
    var spawnFired = false
    tankMoveTick(player: 0, state: &state, onSpawn: { spawnFired = true })
    #expect(spawnFired)
    _ = player
}

// MARK: - tankMoveTick: alive branch, turning

@Test func tankMoveTickTurnSpeedInstantResetOnNoInput() {
    var player = connectedPlayer()
    player.turnSpeed = 2.0
    player.inputFlags = []
    var state = makeAliveState(player: player)
    tankMoveTick(player: 0, state: &state)
    #expect(state.players[0].turnSpeed == 0.0)
}

@Test func tankMoveTickTurnSpeedInstantResetOnBothPressed() {
    var player = connectedPlayer()
    player.turnSpeed = 2.0
    player.inputFlags = [.turnL, .turnR]
    var state = makeAliveState(player: player)
    tankMoveTick(player: 0, state: &state)
    #expect(state.players[0].turnSpeed == 0.0)
}

@Test func tankMoveTickTurnSignFlipGuard() {
    // Turning left while turnSpeed is still negative (from a prior right
    // turn) snaps to 0 before accelerating, rather than decelerating
    // through zero gradually.
    var player = connectedPlayer()
    player.turnSpeed = -1.0
    player.inputFlags = [.turnL]
    player.boat = true  // bypass maxTurnSpeed terrain lookup, use maxAngularVelocity directly
    var state = makeAliveState(player: player)
    tankMoveTick(player: 0, state: &state)
    // Started from 0 (post-snap), accelerated by angularAccel/ticksPerSec, positive.
    #expect(state.players[0].turnSpeed > 0)
}

// MARK: - tankMoveTick: shore push

@Test func tankMoveTickShorePushLeftPushesRight() {
    // Boat sitting with a shore tile immediately to the left, nothing
    // else nearby — should be pushed away from it (positive x direction).
    var player = connectedPlayer()
    player.boat = true
    player.tank = Vec2f(x: 100.1, y: 100.5)
    player.speed = 0
    player.dir = 0
    var state = makeAliveState(player: player)
    state.terrain[99, 100] = .grass3  // shore to the left

    tankMoveTick(player: 0, state: &state)

    #expect(state.players[0].tank.x > 100.1)
}

@Test func tankMoveTickShorePushNoNeighborsNoPush() {
    var player = connectedPlayer()
    player.boat = true
    player.tank = Vec2f(x: 128.5, y: 128.5)
    player.speed = 0
    var state = makeAliveState(player: player)
    // Entire neighborhood remains default sea.

    tankMoveTick(player: 0, state: &state)

    #expect(abs(state.players[0].tank.x - 128.5) < 0.0001)
    #expect(abs(state.players[0].tank.y - 128.5) < 0.0001)
}
