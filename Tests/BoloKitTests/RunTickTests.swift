import Testing
import BoloKit

private func connectedPlayer(dead: Bool = false) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.dead = dead
    p.used = true
    return p
}

private func makeState(players: [PlayerState], localPlayer: Int = 0) -> GameState {
    var state = GameState()
    state.players = players
    state.localPlayer = localPlayer
    state.terrain[50, 50] = .grass0
    for p in state.players.indices {
        state.players[p].tank = Vec2f(x: 50.5, y: 50.5)
    }
    return state
}

// MARK: - Pause state machine

@Test func runTickIndefinitePauseSkipsEverything() {
    var state = makeState(players: [connectedPlayer()])
    state.pause = -1
    let ticksBefore = state.ticks
    runTick(state: &state, ticksSinceLastUpdate: [0])
    #expect(state.ticks == ticksBefore)
    #expect(state.pause == -1)
}

@Test func runTickPositivePauseCountsDownAndEmitsOnSecondBoundary() {
    var state = makeState(players: [connectedPlayer()])
    state.pause = Int(ticksPerSec) * 2  // 2 seconds

    // 49 silent decrements: 100 -> 51 (ticksPerSec == 50).
    for _ in 0..<(Int(ticksPerSec) - 1) {
        runTick(state: &state, ticksSinceLastUpdate: [0])
    }
    #expect(state.pause == Int(ticksPerSec) + 1)

    // One more: 51 -> 50, a second boundary, fires with 1 second remaining.
    var emitted: [Int] = []
    runTick(state: &state, ticksSinceLastUpdate: [0], onPause: { emitted.append($0) })
    #expect(state.pause == Int(ticksPerSec))
    #expect(emitted == [1])
}

@Test func runTickUnpausedTicksNormally() {
    var state = makeState(players: [connectedPlayer()])
    let ticksBefore = state.ticks
    runTick(state: &state, ticksSinceLastUpdate: [0])
    #expect(state.ticks == ticksBefore + 1)
}

// MARK: - Time-limit warnings

@Test func runTickFiresTimeLimitWarningsAtExactTickBoundaries() {
    var state = makeState(players: [connectedPlayer()])
    state.timeLimit = 10  // seconds
    state.ticks = UInt64(Int(ticksPerSec) * 10 - Int(ticksPerSec) * 5)  // 5s remaining

    var warnings: [Int] = []
    runTick(state: &state, ticksSinceLastUpdate: [0], onTimeLimitWarning: { warnings.append($0) })
    #expect(warnings == [5])
}

@Test func runTickReachedTimeLimitFiresZeroAndFreezesTicks() {
    var state = makeState(players: [connectedPlayer()])
    state.timeLimit = 1
    state.ticks = UInt64(ticksPerSec)  // exactly at the limit

    var warnings: [Int] = []
    runTick(state: &state, ticksSinceLastUpdate: [0], onTimeLimitWarning: { warnings.append($0) })
    #expect(warnings == [0])
    #expect(state.ticks == UInt64(ticksPerSec) + 1)  // one-time increment-then-stop

    // Next tick: past the limit, frozen forever, no further warnings.
    let frozenTicks = state.ticks
    warnings = []
    runTick(state: &state, ticksSinceLastUpdate: [0], onTimeLimitWarning: { warnings.append($0) })
    #expect(warnings.isEmpty)
    #expect(state.ticks == frozenTicks)
}

@Test func runTickNoWarningOffBoundaryTicksNormally() {
    var state = makeState(players: [connectedPlayer()])
    state.timeLimit = 100
    state.ticks = 3  // not on any warning boundary
    var warnings: [Int] = []
    runTick(state: &state, ticksSinceLastUpdate: [0], onTimeLimitWarning: { warnings.append($0) })
    #expect(warnings.isEmpty)
    #expect(state.ticks == 4)
}

// MARK: - Domination base-control

private func alliedPlayers(count: Int) -> [PlayerState] {
    (0..<count).map { i in
        var p = connectedPlayer()
        // Everyone mutually allied with everyone (all bits set).
        p.alliance = UInt16((1 << count) - 1)
        return p
    }
}

@Test func runTickIncrementsBaseControlWhileAllBasesHeldByAlliedOwners() {
    var state = makeState(players: alliedPlayers(count: 2))
    state.bases = [
        Base(x: 10, y: 10, armour: UInt8(minBaseArmour), owner: 0, shells: 0, mines: 0),
        Base(x: 20, y: 20, armour: UInt8(minBaseArmour), owner: 1, shells: 0, mines: 0),
    ]
    state.baseControlThreshold = 100
    runTick(state: &state, ticksSinceLastUpdate: [0, 0])
    #expect(state.baseControlCounter == 1)
}

@Test func runTickBaseControlWarningAtExactThresholdThenFreezes() {
    var state = makeState(players: alliedPlayers(count: 1))
    state.bases = [Base(x: 10, y: 10, armour: UInt8(minBaseArmour), owner: 0, shells: 0, mines: 0)]
    state.baseControlThreshold = 1  // 1 second
    state.baseControlCounter = Int(ticksPerSec) - 1  // one tick short of the threshold

    var warnings: [Int] = []
    runTick(state: &state, ticksSinceLastUpdate: [0], onBaseControlWarning: { warnings.append($0) })
    #expect(warnings == [0])
    let ticksAfterReach = state.ticks

    warnings = []
    runTick(state: &state, ticksSinceLastUpdate: [0], onBaseControlWarning: { warnings.append($0) })
    #expect(warnings.isEmpty)
    #expect(state.ticks == ticksAfterReach)  // frozen, no further ticking
}

/// The real trap from the Wave 6.1 pre-brief: if the *outer* condition
/// fails (base 0 not held / no bases), the counter is left **untouched**,
/// not reset to 0 — only the inner "all-other-bases" failure resets it.
@Test func runTickBaseControlUntouchedWhenBaseZeroNotHeld() {
    var state = makeState(players: alliedPlayers(count: 1))
    state.bases = [Base(x: 10, y: 10, armour: 0, owner: 0, shells: 0, mines: 0)]  // armour below minBaseArmour
    state.baseControlThreshold = 100
    state.baseControlCounter = 42

    runTick(state: &state, ticksSinceLastUpdate: [0])
    #expect(state.baseControlCounter == 42)  // untouched, not reset
}

@Test func runTickBaseControlResetWhenOtherBaseNotAllied() {
    var players = alliedPlayers(count: 2)
    players[1].alliance = 0  // player 1 is not allied with anyone, including player 0
    var state = makeState(players: players)
    state.bases = [
        Base(x: 10, y: 10, armour: UInt8(minBaseArmour), owner: 0, shells: 0, mines: 0),
        Base(x: 20, y: 20, armour: UInt8(minBaseArmour), owner: 1, shells: 0, mines: 0),
    ]
    state.baseControlThreshold = 100
    state.baseControlCounter = 42

    runTick(state: &state, ticksSinceLastUpdate: [0, 0])
    #expect(state.baseControlCounter == 0)  // inner failure: explicit reset
}

@Test func runTickBaseControlUntouchedWithNoBasesConfigured() {
    var state = makeState(players: [connectedPlayer()])
    state.baseControlCounter = 7
    runTick(state: &state, ticksSinceLastUpdate: [0])
    #expect(state.baseControlCounter == 7)
}

// MARK: - Disconnect-lagged-players

@Test func runTickDisconnectsStalePlayerAndDropsOnboardPills() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]

    var disconnected: [Int] = []
    runTick(
        state: &state,
        ticksSinceLastUpdate: [9 * UInt64(ticksPerSec), 0],
        onPlayerDisconnected: { disconnected.append($0) }
    )

    #expect(disconnected == [0])
    #expect(!state.players[0].connected)
    #expect(state.players[1].connected)
    // The onboard pill must have been dropped (no longer onboard) somewhere on the map.
    #expect(state.pills[0].armour != pillOnboard)
}

@Test func runTickDoesNotDisconnectPlayerBelowStaleThreshold() {
    var state = makeState(players: [connectedPlayer()])
    var disconnected: [Int] = []
    runTick(
        state: &state,
        ticksSinceLastUpdate: [9 * UInt64(ticksPerSec) - 1],
        onPlayerDisconnected: { disconnected.append($0) }
    )
    #expect(disconnected.isEmpty)
    #expect(state.players[0].connected)
}

/// D35 Finding 1: `server.pauseonplayerexit` (server.c:1192-1197) pauses
/// the game indefinitely, broadcasting the wire sentinel 255, whenever a
/// lagged player is disconnected.
@Test func runTickPauseOnPlayerExitPausesIndefinitelyOnDisconnect() {
    var state = makeState(players: [connectedPlayer()])
    state.pauseOnPlayerExit = true

    var pauseEvents: [Int] = []
    runTick(
        state: &state,
        ticksSinceLastUpdate: [9 * UInt64(ticksPerSec)],
        onPause: { pauseEvents.append($0) }
    )

    #expect(state.pause == -1)
    #expect(pauseEvents == [255])
}

@Test func runTickPauseOnPlayerExitDefaultFalseLeavesPauseUntouched() {
    var state = makeState(players: [connectedPlayer()])
    #expect(!state.pauseOnPlayerExit)

    runTick(state: &state, ticksSinceLastUpdate: [9 * UInt64(ticksPerSec)])

    #expect(state.pause == 0)
}

// MARK: - Lagged-status callback

@Test func runTickFiresLagStatusAtBothThresholdsButNotBetween() {
    var state = makeState(players: [connectedPlayer()])
    var fired = false
    runTick(state: &state, ticksSinceLastUpdate: [3 * UInt64(ticksPerSec)], onPlayerLagStatusChanged: { _ in fired = true })
    #expect(fired)

    state.ticks = 0
    fired = false
    runTick(state: &state, ticksSinceLastUpdate: [UInt64(ticksPerSec)], onPlayerLagStatusChanged: { _ in fired = true })
    #expect(fired)

    state.ticks = 0
    fired = false
    runTick(state: &state, ticksSinceLastUpdate: [UInt64(ticksPerSec) + 5], onPlayerLagStatusChanged: { _ in fired = true })
    #expect(!fired)
}

// MARK: - Full-tick sequencing smoke tests

@Test func runTickAdvancesGrowStateAndBaseReplenishConsistently() {
    var state = makeState(players: [connectedPlayer()])
    state.bases = [Base(x: 200, y: 200, armour: 10, owner: playerNeutral, shells: 0, mines: 0)]

    for _ in 0..<Int(replenishBaseTicks) {
        runTick(state: &state, ticksSinceLastUpdate: [0])
    }

    // With 1 connected player, the base's counter increments by 1/tick,
    // so it should have replenished at least once by replenishBaseTicks.
    #expect(state.bases[0].armour > 10 || state.bases[0].armour == UInt8(maxBaseArmour))
}

@Test func runTickDoesNotCrashWithMultiplePlayersAndPillsAndBases() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer(dead: true)])
    state.pills = [Pill(x: 60, y: 60, armour: 5, owner: playerNeutral, speed: 10, counter: 0)]
    state.bases = [Base(x: 70, y: 70, armour: 10, owner: playerNeutral, shells: 0, mines: 0)]
    state.terrain[60, 60] = .grass0
    state.terrain[70, 70] = .grass0

    for _ in 0..<10 {
        runTick(state: &state, ticksSinceLastUpdate: [0, 0])
    }

    #expect(state.ticks == 10)
}
