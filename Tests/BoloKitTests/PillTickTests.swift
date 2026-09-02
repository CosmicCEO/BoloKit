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

/// `old == current tank` for every player — the common case in these
/// tests, where velocity-lead targeting isn't what's under test.
private func stationaryOldPositions(_ state: GameState) -> [Vec2f] {
    state.players.map(\.tank)
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

@Test func pillTickNoAliveConnectedPlayerFreezesCounter() {
    // Nobody is running any code this tick at all — every private
    // replica (in the distributed model) is untouched. Distinct from the
    // "alive players exist but are all allied" reset case below.
    var player = connectedPlayer(dead: true)
    player.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 3)
}

@Test func pillTickOnboardPillIsIgnoredAndCounterReset() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: pillOnboard, owner: 0, speed: 5, counter: 3)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 0)
}

@Test func pillTickDeadPillCounterReset() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 0)
}

@Test func pillTickAllAliveCandidatesAlliedResetsCounter() {
    // At least one alive connected player exists, but every one of them
    // is allied with the pill's owner — each of their own clients would
    // explicitly zero their own counter, so the shared reconstruction
    // resets too (distinct from the "nobody's alive" freeze case above).
    // Owner is given a self-alliance bit so the (real, separately
    // documented) self-targeting quirk in testAlliance doesn't make the
    // owner an unintended eligible candidate for their own pill.
    var owner = connectedPlayer()
    owner.alliance = 0b11  // self (bit 0) + allied with player 1 (bit 1)
    var ally = connectedPlayer()
    ally.alliance = 0b01  // allied with player 0
    ally.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [owner, ally])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: 0, speed: 5, counter: 3)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 0)
}

@Test func pillTickOutOfRangePillLeavesCounterUntouched() {
    // No `else` branch in C when every eligible candidate is simply out
    // of range/visibility — the counter is neither reset nor incremented.
    var player = connectedPlayer()
    player.tank = Vec2f(x: 100.5, y: 50.5)  // far from the pill
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 3)
}

@Test func pillTickInRangeHostilePillIncrementsCounter() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 1)
}

@Test func pillTickVisibleThroughForestBeyondTwoSquares() {
    // mag > 2.0 but forestVis(tank) > 0.25 (open terrain, forestVis==1)
    // should still count as "visible."
    var player = connectedPlayer()
    player.tank = Vec2f(x: 55.5, y: 50.5)  // distance ~5 from the pill
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 1)
}

@Test func pillTickBeyondEightSquaresNeverFiresRegardlessOfVisibility() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 59.5, y: 50.5)  // distance 9 from the pill
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 3)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 3)
}

// MARK: - pillTick: closest-hostile election

@Test func pillTickClosestPlayerAloneWinsElectionAndFires() {
    var far = connectedPlayer()
    far.tank = Vec2f(x: 55.5, y: 50.5)
    var near = connectedPlayer()
    near.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(players: [far, near])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 1, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 0)  // fired and reset
    #expect(state.players[0].shells.isEmpty)  // far did not receive a shot
    #expect(state.players[1].shells.count == 1)  // near did
}

@Test func pillTickTiedDistanceIncrementsCounterOnceNotOncePerTiedPlayer() {
    // C's disqualification requires STRICTLY closer — an exact tie
    // disqualifies neither. A shared counter that reaches threshold once
    // per tick (not once per tied player) is the faithful reconstruction,
    // since tied players' independent replicas move in lockstep in the
    // distributed model.
    var a = connectedPlayer()
    a.tank = Vec2f(x: 51.5, y: 50.5)  // distance 1.0 from the pill center
    var b = connectedPlayer()
    b.tank = Vec2f(x: 49.5, y: 50.5)  // also distance 1.0 — genuine tie
    var state = makeState(players: [a, b])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 1)
}

@Test func pillTickTiedDistanceFiresAtBothTiedPlayers() {
    var a = connectedPlayer()
    a.tank = Vec2f(x: 51.5, y: 50.5)
    var b = connectedPlayer()
    b.tank = Vec2f(x: 49.5, y: 50.5)
    var state = makeState(players: [a, b])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 1, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 0)
    #expect(state.players[0].shells.count == 1)
    #expect(state.players[1].shells.count == 1)
}

@Test func pillTickAlliedCompetitorDoesNotDisqualify() {
    // A closer player who is ALLIED with the pill's owner doesn't count
    // as a competing hostile target — the farther, genuinely hostile
    // player should still win the election despite someone else being
    // closer.
    var owner = connectedPlayer()
    owner.alliance = 0b011  // self (bit 0) + allied with player 1 (bit 1)
    var closeAlly = connectedPlayer()
    closeAlly.alliance = 0b001  // allied with player 0 (the pill's owner)
    closeAlly.tank = Vec2f(x: 50.1, y: 50.5)  // very close to the pill
    var hostile = connectedPlayer()
    hostile.tank = Vec2f(x: 52.5, y: 50.5)  // farther, but not allied
    var state = makeState(players: [owner, closeAlly, hostile])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: 0, speed: 5, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 1)
}

// MARK: - pillTick: the PARITY Wave 5.3c regression — shared-counter order-dependence

@Test func pillTickMultiPlayerSweepDoesNotEraseClosestTargetsProgress() {
    // Direct regression test for the PARITY-flagged Wave 5.3c FAIL: the
    // first cut of pillTick was called once per player, all mutating one
    // shared counter — a farther bystander processed after the real
    // target in player-index order unconditionally reset the shared
    // counter, erasing the target's progress every tick. pillTick is now
    // a single whole-state call per tick, so this must climb monotonically
    // across ticks with the bystander present throughout, then fire only
    // at the real (lower-index) target.
    var target = connectedPlayer()
    target.tank = Vec2f(x: 51.5, y: 50.5)  // distance 1.0 — the real target
    var bystander = connectedPlayer()
    bystander.tank = Vec2f(x: 55.5, y: 50.5)  // distance ~5, farther, still hostile
    var state = makeState(players: [target, bystander])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 4, counter: 0)]

    for tick in 1...3 {
        pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))
        #expect(state.pills[0].counter == tick, "counter should climb monotonically at tick \(tick)")
    }

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 0)  // fired and reset
    #expect(state.players[0].shells.count == 1)  // the real target (index 0) was hit
    #expect(state.players[1].shells.isEmpty)  // the bystander (index 1) was not
}

@Test func pillTickMultiPlayerSweepAlliedBystanderDoesNotAffectRealTarget() {
    // Same shape as above, but the bystander is an ALLY of the pill's
    // owner rather than a farther hostile — confirms an allied bystander
    // (who would explicitly zero their own private counter in the
    // distributed model) doesn't leak into the shared reconstruction
    // either, since they're excluded from `eligible` entirely. Owner is
    // allied with the bystander (player 2, bit 2) and self (bit 0), but
    // NOT with the target (player 1) — the target must remain hostile.
    var owner = connectedPlayer()
    owner.alliance = 0b101  // self (bit 0) + allied with player 2 (bit 2)
    var target = connectedPlayer()
    target.tank = Vec2f(x: 51.5, y: 50.5)
    var alliedBystander = connectedPlayer()
    alliedBystander.alliance = 0b001  // allied with player 0
    alliedBystander.tank = Vec2f(x: 50.6, y: 50.5)  // even closer than target
    var state = makeState(players: [owner, target, alliedBystander])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: 0, speed: 2, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))
    #expect(state.pills[0].counter == 1)

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))
    #expect(state.pills[0].counter == 0)  // fired and reset

    #expect(state.players[1].shells.count == 1)  // target was hit
    #expect(state.players[2].shells.isEmpty)  // allied bystander was not
}

// MARK: - pillTick: firing

@Test func pillTickFiresWhenCounterReachesSpeedAndResetsToZero() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 52.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 1, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

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

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    // The shell is appended to the TARGET's (player 1's) shell list, but
    // its `owner` field is the pill's owner (player 0), not the target.
    // Owner (player 0, at the default (0,0) position) is out of range and
    // does not affect the election, despite the self-targeting quirk
    // making them nominally eligible for their own pill (alliance == 0,
    // no self-bit set) — see testAlliance's documented lack of a
    // self-alliance special case.
    #expect(state.players[1].shells.count == 1)
    #expect(state.players[1].shells[0].owner == 0)
}

@Test func pillTickDoesNotFireBelowSpeedThreshold() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 52.5, y: 50.5)
    var state = makeState(players: [player])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 5, counter: 0)]

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

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

    pillTick(state: &state, oldTankPositions: stationaryOldPositions(state))

    #expect(state.pills[0].counter == 0)
    #expect(state.players[0].shells.isEmpty)
}
