import Testing
import BoloKit

private func connectedPlayer(dead: Bool = false, connected: Bool = true) -> PlayerState {
    var p = PlayerState()
    p.connected = connected
    p.dead = dead
    p.used = true
    return p
}

private func makeState(players: [PlayerState]) -> GameState {
    var state = GameState()
    state.players = players
    return state
}

// MARK: - Global explosion list

@Test func explosionTickIncrementsGlobalExplosionCounter() {
    var state = makeState(players: [])
    state.explosions = [Explosion(point: Vec2f(x: 50.5, y: 50.5), counter: 0)]

    explosionTick(state: &state)

    #expect(state.explosions.count == 1)
    #expect(state.explosions[0].counter == 1)
}

@Test func explosionTickRemovesGlobalExplosionStrictlyAfterThreshold() {
    var state = makeState(players: [])
    // counter == explosionTicks exactly: after increment, becomes
    // explosionTicks + 1, which IS > explosionTicks — removed.
    state.explosions = [Explosion(point: Vec2f(x: 50.5, y: 50.5), counter: explosionTicks)]

    explosionTick(state: &state)

    #expect(state.explosions.isEmpty)
}

@Test func explosionTickKeepsGlobalExplosionAtExactBoundary() {
    var state = makeState(players: [])
    // counter == explosionTicks - 1: after increment, becomes
    // explosionTicks exactly, which is NOT > explosionTicks — kept.
    state.explosions = [Explosion(point: Vec2f(x: 50.5, y: 50.5), counter: explosionTicks - 1)]

    explosionTick(state: &state)

    #expect(state.explosions.count == 1)
    #expect(state.explosions[0].counter == explosionTicks)
}

@Test func explosionTickFiltersMixedAgesInGlobalList() {
    var state = makeState(players: [])
    state.explosions = [
        Explosion(point: Vec2f(x: 1, y: 1), counter: 0),
        Explosion(point: Vec2f(x: 2, y: 2), counter: explosionTicks),  // will be removed
        Explosion(point: Vec2f(x: 3, y: 3), counter: 10),
    ]

    explosionTick(state: &state)

    #expect(state.explosions.count == 2)
    #expect(state.explosions.map(\.counter) == [1, 11])
}

// MARK: - Per-player explosion lists

@Test func explosionTickIncrementsConnectedPlayerExplosionCounter() {
    var player = connectedPlayer()
    player.explosions = [Explosion(point: Vec2f(x: 10, y: 10), counter: 5)]
    var state = makeState(players: [player])

    explosionTick(state: &state)

    #expect(state.players[0].explosions.count == 1)
    #expect(state.players[0].explosions[0].counter == 6)
}

@Test func explosionTickRemovesPlayerExplosionStrictlyAfterThreshold() {
    var player = connectedPlayer()
    player.explosions = [Explosion(point: Vec2f(x: 10, y: 10), counter: explosionTicks)]
    var state = makeState(players: [player])

    explosionTick(state: &state)

    #expect(state.players[0].explosions.isEmpty)
}

@Test func explosionTickLeavesDisconnectedPlayerExplosionsUntouched() {
    var player = connectedPlayer(connected: false)
    player.explosions = [Explosion(point: Vec2f(x: 10, y: 10), counter: explosionTicks)]
    var state = makeState(players: [player])

    explosionTick(state: &state)

    // Would have been removed (counter > explosionTicks after increment)
    // if this player were connected — frozen instead, matching C's
    // `if (client.players[player].connected)` guard.
    #expect(state.players[0].explosions.count == 1)
    #expect(state.players[0].explosions[0].counter == explosionTicks)
}

@Test func explosionTickDrainsMultiplePlayersIndependently() {
    var a = connectedPlayer()
    a.explosions = [Explosion(point: Vec2f(x: 1, y: 1), counter: 0)]
    var b = connectedPlayer()
    b.explosions = [Explosion(point: Vec2f(x: 2, y: 2), counter: explosionTicks)]
    var state = makeState(players: [a, b])

    explosionTick(state: &state)

    #expect(state.players[0].explosions.count == 1)
    #expect(state.players[0].explosions[0].counter == 1)
    #expect(state.players[1].explosions.isEmpty)
}

@Test func explosionTickGlobalAndPerPlayerListsAreIndependent() {
    var player = connectedPlayer()
    player.explosions = [Explosion(point: Vec2f(x: 10, y: 10), counter: 0)]
    var state = makeState(players: [player])
    state.explosions = [Explosion(point: Vec2f(x: 50, y: 50), counter: 0)]

    explosionTick(state: &state)

    #expect(state.explosions.count == 1)
    #expect(state.explosions[0].counter == 1)
    #expect(state.players[0].explosions.count == 1)
    #expect(state.players[0].explosions[0].counter == 1)
}

@Test func explosionTickNoOpOnEmptyLists() {
    var state = makeState(players: [connectedPlayer()])
    explosionTick(state: &state)
    #expect(state.explosions.isEmpty)
    #expect(state.players[0].explosions.isEmpty)
}
