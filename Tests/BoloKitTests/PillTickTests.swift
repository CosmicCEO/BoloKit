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
    // Safe default square — a bare GameState() puts (0,0) in the mined-sea
    // border ring; same pitfall recorded in TankLocalTick/ShellTick/
    // BuilderTick tests.
    state.terrain[50, 50] = .grass0
    return state
}

// MARK: - isForest

@Test func isForestTrueForForestAndMinedForest() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .forest
    #expect(isForest(x: 50, y: 50, state: state))
    state.terrain[50, 50] = .minedForest
    #expect(isForest(x: 50, y: 50, state: state))
}

@Test func isForestFalseForOtherTerrain() {
    let state = makeState(players: [])
    #expect(!isForest(x: 50, y: 50, state: state))
}

@Test func isForestFalseOutOfBounds() {
    let state = makeState(players: [])
    #expect(!isForest(x: -1, y: 50, state: state))
    #expect(!isForest(x: 256, y: 50, state: state))
}

@Test func isForestFalseWhenPlacedPillOccupiesSquare() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .forest
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 0)]
    #expect(!isForest(x: 50, y: 50, state: state))
}

@Test func isForestIgnoresOnboardPillAtSameCoordinates() {
    // An onboard (carried) pill's stale x/y shouldn't suppress a real
    // forest tile it no longer occupies.
    var state = makeState(players: [])
    state.terrain[50, 50] = .forest
    state.pills = [Pill(x: 50, y: 50, armour: pillOnboard, owner: 0, speed: 40, counter: 0)]
    #expect(isForest(x: 50, y: 50, state: state))
}

@Test func isForestFalseWhenBaseOccupiesSquare() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .forest
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: playerNeutral, shells: 0, mines: 0)]
    #expect(!isForest(x: 50, y: 50, state: state))
}

// MARK: - forestVis

@Test func forestVisOpenTerrainIsFullyVisible() {
    let state = makeState(players: [])
    #expect(forestVis(Vec2f(x: 50.5, y: 50.5), state: state) == 1.0)
}

@Test func forestVisDeepInForestIsZero() {
    var state = makeState(players: [])
    for dx in -1...1 {
        for dy in -1...1 {
            state.terrain[50 + dx, 50 + dy] = .forest
        }
    }
    #expect(forestVis(Vec2f(x: 50.5, y: 50.5), state: state) == 0.0)
}

@Test func forestVisAtForestEdgeIsPartial() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .forest
    // All neighbors non-forest: standing exactly at the center should
    // yield a positive, non-full visibility.
    let vis = forestVis(Vec2f(x: 50.5, y: 50.5), state: state)
    #expect(vis > 0.0 && vis < 1.0)
}

@Test func forestVisOutOfBoundsIsZero() {
    let state = makeState(players: [])
    #expect(forestVis(Vec2f(x: -1, y: 50), state: state) == 0.0)
    #expect(forestVis(Vec2f(x: 256, y: 50), state: state) == 0.0)
}

// MARK: - pillTick: eligibility and counter semantics

@Test func pillTickDeadPlayerIsEntirelyNoOp() {
    var player = connectedPlayer(dead: true)
    player.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 3)
}

@Test func pillTickOnboardPillIsIgnoredAndCounterReset() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: pillOnboard, owner: 0, speed: 5, counter: 3)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 0)
}

@Test func pillTickDeadPillCounterReset() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 0)
}

@Test func pillTickAlliedPillCounterReset() {
    var owner = connectedPlayer()
    owner.alliance = 0b10
    var ally = connectedPlayer()
    ally.alliance = 0b01
    var state = makeState(players: [owner, ally])
    ally.tank = Vec2f(x: 50.5, y: 50.5)
    state.players[1].tank = Vec2f(x: 50.5, y: 50.5)
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: 0, speed: 5, counter: 3)]

    pillTick(player: 1, old: state.players[1].tank, state: &state)

    #expect(state.pills[0].counter == 0)
}

@Test func pillTickOutOfRangePillLeavesCounterUntouched() {
    // No `else` branch in C when the eligible pill is simply out of
    // range/visibility — the counter is neither reset nor incremented.
    var player = connectedPlayer()
    player.tank = Vec2f(x: 100.5, y: 50.5)  // far from the pill
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 3)
}

@Test func pillTickInRangeHostilePillIncrementsCounter() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 1)
}

@Test func pillTickVisibleThroughForestBeyondTwoSquares() {
    // mag > 2.0 but forestVis(tank) > 0.25 (open terrain, forestVis==1)
    // should still count as "visible."
    var player = connectedPlayer()
    player.tank = Vec2f(x: 55.5, y: 50.5)  // distance ~5 from the pill
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 1)
}

@Test func pillTickBeyondEightSquaresNeverFiresRegardlessOfVisibility() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 59.5, y: 50.5)  // distance 9 from the pill
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 3)
}

// MARK: - pillTick: closest-hostile check

@Test func pillTickClosestHostileWinsCounterIncrement() {
    var far = connectedPlayer()
    far.tank = Vec2f(x: 55.5, y: 50.5)  // farther
    var near = connectedPlayer()
    near.tank = Vec2f(x: 51.5, y: 50.5)  // closer
    var state = makeState(players: [far, near])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(player: 0, old: far.tank, state: &state)

    // Player 0 (far) is not the closest — someone else (player 1) is
    // strictly closer, so player 0's check resets the counter.
    #expect(state.pills[0].counter == 0)
}

@Test func pillTickClosestPlayerIncrementsEvenWithFartherHostilePresent() {
    var far = connectedPlayer()
    far.tank = Vec2f(x: 55.5, y: 50.5)
    var near = connectedPlayer()
    near.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(players: [far, near])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(player: 1, old: near.tank, state: &state)

    #expect(state.pills[0].counter == 1)
}

@Test func pillTickTiedDistanceBothCountAsClosest() {
    // C's inner check requires STRICTLY closer to disqualify — an exact
    // tie disqualifies neither, so both players' independent computation
    // increments. Regression test for the documented tie-break quirk.
    var a = connectedPlayer()
    a.tank = Vec2f(x: 51.5, y: 50.5)  // distance 1.0 from the pill center
    var b = connectedPlayer()
    b.tank = Vec2f(x: 49.5, y: 50.5)  // also distance 1.0 — genuine tie
    var state = makeState(players: [a, b])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(player: 0, old: a.tank, state: &state)
    #expect(state.pills[0].counter == 1)

    state.pills[0].counter = 0
    pillTick(player: 1, old: b.tank, state: &state)
    #expect(state.pills[0].counter == 1)
}

@Test func pillTickAlliedCompetitorDoesNotDisqualify() {
    // A closer player who is ALLIED with the pill's owner doesn't count
    // as a competing hostile target — the farther, genuinely hostile
    // player should still increment despite someone else being closer.
    var owner = connectedPlayer()
    owner.alliance = 0b010  // allied with player 1
    var closeAlly = connectedPlayer()
    closeAlly.alliance = 0b001  // allied with player 0 (the pill's owner)
    closeAlly.tank = Vec2f(x: 50.1, y: 50.5)  // very close to the pill
    var hostile = connectedPlayer()
    hostile.tank = Vec2f(x: 52.5, y: 50.5)  // farther, but not allied
    var state = makeState(players: [owner, closeAlly, hostile])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: 0, speed: 5, counter: 0)]

    pillTick(player: 2, old: hostile.tank, state: &state)

    #expect(state.pills[0].counter == 1)
}

// MARK: - pillTick: firing

@Test func pillTickFiresWhenCounterReachesSpeedAndResetsToZero() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 52.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 1, counter: 0)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 0)
    #expect(state.players[0].shells.count == 1)
    let shell = state.players[0].shells[0]
    #expect(shell.pill)
    #expect(!shell.boat)
    #expect(shell.owner == playerNeutral)
}

@Test func pillTickFiredShellUsesOwnerNotTargetPlayer() {
    let owner = connectedPlayer()
    var target = connectedPlayer()
    target.tank = Vec2f(x: 52.5, y: 50.5)
    var state = makeState(players: [owner, target])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: 0, speed: 1, counter: 0)]

    pillTick(player: 1, old: target.tank, state: &state)

    // The shell is appended to the TARGET's (player 1's) shell list — C
    // always appends to client.players[client.player].shells, i.e. the
    // player being ticked, generalized here — but its `owner` field is
    // the pill's owner (player 0), not the target.
    #expect(state.players[1].shells.count == 1)
    #expect(state.players[1].shells[0].owner == 0)
}

@Test func pillTickDoesNotFireBelowSpeedThreshold() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 52.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 1)
    #expect(state.players[0].shells.isEmpty)
}

@Test func pillTickShellDiscardedOnImmediateCollisionButCounterStillResets() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 1, counter: 0)]
    // Wall immediately adjacent to the pill center in the firing
    // direction — the muzzle point itself may land on solid terrain.
    for x in 49...52 {
        for y in 49...52 {
            if !(x == 50 && y == 50) { state.terrain[x, y] = .wall }
        }
    }

    pillTick(player: 0, old: player.tank, state: &state)

    #expect(state.pills[0].counter == 0)
    #expect(state.players[0].shells.isEmpty)
}
