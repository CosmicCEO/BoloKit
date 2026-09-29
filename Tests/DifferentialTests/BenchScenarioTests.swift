import Foundation
import Testing
import BoloKit
import BoloNet

// v1.6.9 baseline benchmark: a scenario must read back as written, a seed must replay the same
// choices, and the steering must actually get a real tank to where the script says.

@Test func aScenarioReadsBackAsWritten() throws {
    let scenario = BenchScenario(
        name: "sample", hiddenMines: true, settleMs: 2_500,
        host: [.until(.peerAlive, timeoutMs: 10_000), .face(x: 110, y: 121, timeoutMs: 5_000), .keys(set: [.shoot], clear: [])],
        guest: [
            .until(.alive, timeoutMs: 10_000), .mark("start"), .driveTo(x: 108, y: 123, radius: 0.4, timeoutMs: 20_000),
            .until(.carryingAtLeast(pills: 1), timeoutMs: 5_000), .layMine, .builder(tool: .road, x: 110, y: 125),
            .until(.terrain(x: 110, y: 125, anyOf: [Terrain.road.rawValue]), timeoutMs: 20_000),
            .random(seed: 7, seconds: 3), .wait(ms: 250),
            .driveUntil(x: 115, y: 123, radius: 0.4, .dead, timeoutMs: 90_000),
        ]
    )
    let decoded = try JSONDecoder().decode(BenchScenario.self, from: scenario.encoded())
    #expect(decoded == scenario)
    // Sorted keys, so the same scenario is always the same bytes and hashes the same.
    #expect(try decoded.encoded() == scenario.encoded())
}

@Test func theSeededGeneratorIsSplitMix64() {
    var rng = BenchRNG(state: 0)
    #expect(rng.next() == 0xE220_A839_7B1D_CDAF)
    #expect(rng.next() == 0x6E78_9E6A_A1B9_65F4)
}

@Test func aSeedReplaysTheSameInputs() {
    var first = BenchRNG(state: 42)
    var second = BenchRNG(state: 42)
    var other = BenchRNG(state: 43)
    let a = (0..<200).map { _ in benchRandomInputs(&first).rawValue }
    let b = (0..<200).map { _ in benchRandomInputs(&second).rawValue }
    let c = (0..<200).map { _ in benchRandomInputs(&other).rawValue }
    #expect(a == b)
    #expect(a != c)
    #expect(Set(a).count > 8, "the mix should cover many key combinations")
}

@Test func randomPlayReplaysFromItsSeedAndStaysNearTheTank() {
    let tank = Vec2f(x: 102.5, y: 121.5)
    var first = BenchRNG(state: 9)
    var second = BenchRNG(state: 9)
    let a = (0..<500).map { _ in benchRandomAction(&first, tank: tank) }
    let b = (0..<500).map { _ in benchRandomAction(&second, tank: tank) }
    #expect(a == b)
    #expect(a.contains { $0.layMine })
    let orders = a.filter { $0.builder != nil }
    #expect(!orders.isEmpty)
    #expect(orders.allSatisfy { abs(Int($0.target.x) - 102) <= 4 && abs(Int($0.target.y) - 121) <= 4 })
}

@Test func headingErrorIsSignedTheWayTurnLeftTurns() {
    let tank = Vec2f(x: 100.5, y: 100.5)
    // Facing east (0). North on screen is smaller y, a quarter turn to the left.
    #expect(abs(benchHeadingError(from: tank, dir: 0, to: Vec2f(x: 100.5, y: 90.5)) - kPif / 2) < 0.001)
    #expect(abs(benchHeadingError(from: tank, dir: 0, to: Vec2f(x: 100.5, y: 110.5)) + kPif / 2) < 0.001)
    #expect(abs(benchHeadingError(from: tank, dir: 0, to: Vec2f(x: 110.5, y: 100.5))) < 0.001)
    // Just past a full turn is a small error, not nearly a whole turn.
    #expect(abs(benchHeadingError(from: tank, dir: 2 * kPif - 0.1, to: Vec2f(x: 110.5, y: 100.5)) - 0.1) < 0.001)
}

@Test func steeringTurnsOnTheSpotWhenFarOffAndDrivesWhenRoughlyAligned() {
    let tank = Vec2f(x: 100.5, y: 100.5)
    #expect(benchSteer(tank: tank, dir: 0, x: 110, y: 100, radius: 0.4).flags == [.accel])
    #expect(benchSteer(tank: tank, dir: 0, x: 100, y: 90, radius: 0.4).flags == [.turnL, .brake])
    #expect(benchSteer(tank: tank, dir: 0, x: 100, y: 110, radius: 0.4).flags == [.turnR, .brake])
    let arrived = benchSteer(tank: tank, dir: 0, x: 100, y: 100, radius: 0.4)
    #expect(arrived.arrived && arrived.flags == [.brake])
}

@Test func keyChangesTouchOnlyTheKeysTheyManage() {
    let steering: InputFlags = [.accel, .brake, .turnL, .turnR]
    #expect(benchKeyChange(from: [.shoot], to: [.accel], managed: steering) == KeyInputChange(set: [.accel], clear: []))
    #expect(
        benchKeyChange(from: [.shoot, .accel, .turnL], to: [.brake], managed: steering)
            == KeyInputChange(set: [.brake], clear: [.accel, .turnL])
    )
    #expect(benchKeyChange(from: [.shoot, .accel], to: [.accel], managed: steering) == nil)
}

private func openField() -> GameState {
    var state = GameState()
    for y in 80..<140 { for x in 80..<140 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    state.players[0] = PlayerState(tank: Vec2f(x: 100.5, y: 100.5), dead: false, connected: true, used: true)
    state.players[1] = PlayerState(tank: Vec2f(x: 120.5, y: 120.5), dead: false, connected: true, used: true)
    state.localPlayer = 0
    state.local.armour = maxArmour
    state.local.spawned = true
    return state
}

/// Drives the real movement code with the steering's own key choices, as the autopilot will.
private func drive(_ state: inout GameState, toX x: Int, y: Int, radius: Double, ticks: Int) -> Int? {
    let steering: InputFlags = [.accel, .brake, .turnL, .turnR]
    for tick in 0..<ticks {
        let me = state.players[0]
        let decision = benchSteer(tank: me.tank, dir: me.dir, x: x, y: y, radius: radius)
        if let change = benchKeyChange(from: me.inputFlags, to: decision.flags, managed: steering) {
            state.players[0].inputFlags.formUnion(change.set)
            state.players[0].inputFlags.subtract(change.clear)
        }
        if decision.arrived { return tick }
        tankMoveTick(player: 0, state: &state)
    }
    return nil
}

@Test(arguments: [(112, 100), (100, 88), (90, 112), (88, 92), (101, 101)])
func steeringGetsARealTankToItsTarget(x: Int, y: Int) {
    var state = openField()
    let ticks = drive(&state, toX: x, y: y, radius: 0.4, ticks: 50 * 30)
    #expect(ticks != nil, "never arrived at (\(x), \(y)); stopped at \(state.players[0].tank)")
    #expect(benchConditionHolds(.at(x: x, y: y, radius: 0.4), player: 0, state: state))
}

/// Turns the real tank on the spot with the aiming's own key choices, then holds still.
@Test(arguments: [(112, 100), (100, 88), (90, 112), (88, 92), (107, 101)])
func aimingSettlesOnTheTargetCloselyEnoughToHitIt(x: Int, y: Int) {
    var state = openField()
    let steering: InputFlags = [.accel, .brake, .turnL, .turnR]
    var settledFor = 0
    for _ in 0..<(50 * 20) {
        let me = state.players[0]
        let decision = benchFace(tank: me.tank, dir: me.dir, x: x, y: y)
        if let change = benchKeyChange(from: me.inputFlags, to: decision.flags, managed: steering) {
            state.players[0].inputFlags.formUnion(change.set)
            state.players[0].inputFlags.subtract(change.clear)
        }
        settledFor = decision.facing ? settledFor + 1 : 0
        if settledFor >= 50 { break }
        tankMoveTick(player: 0, state: &state)
    }
    #expect(settledFor >= 50, "never held its aim for a second")
    let me = state.players[0]
    let error = benchHeadingError(from: me.tank, dir: me.dir, to: Vec2f(x: Float(x) + 0.5, y: Float(y) + 0.5))
    #expect(abs(error) <= benchAimTolerance)
    #expect(Int(me.tank.x) == 100 && Int(me.tank.y) == 100, "aiming must not move the tank off its tile")
}

@Test func conditionsReadTheStateOfTheSideRunningTheScript() {
    var state = openField()
    #expect(benchPeer(of: 0, state: state) == 1)
    #expect(benchPeer(of: 1, state: state) == 0)
    #expect(benchConditionHolds(.alive, player: 0, state: state))
    #expect(benchConditionHolds(.peerAlive, player: 0, state: state))
    #expect(benchConditionHolds(.peerAt(x: 120, y: 120, radius: 0.1), player: 0, state: state))
    #expect(!benchConditionHolds(.at(x: 120, y: 120, radius: 0.1), player: 0, state: state))

    state.players[1].dead = true
    #expect(benchConditionHolds(.peerDead, player: 0, state: state))
    #expect(benchConditionHolds(.dead, player: 1, state: state))

    state.pills = [Pill(x: 105, y: 100, armour: 4, owner: playerNeutral, speed: 50, counter: 0)]
    #expect(benchConditionHolds(.pillArmourAtMost(pill: 0, armour: 4), player: 0, state: state))
    #expect(!benchConditionHolds(.pillOwnedByMe(pill: 0), player: 0, state: state))
    state.pills[0].owner = 0
    state.pills[0].armour = pillOnboard
    #expect(benchConditionHolds(.pillOwnedByMe(pill: 0), player: 0, state: state))
    #expect(benchConditionHolds(.carryingAtLeast(pills: 1), player: 0, state: state))
    #expect(!benchConditionHolds(.pillArmourAtMost(pill: 0, armour: 15), player: 0, state: state), "a carried pill has no armour")

    state.pills[0].armour = 15
    state.pills[0].x = 110
    state.pills[0].y = 121
    #expect(benchConditionHolds(.pillAt(pill: 0, x: 110, y: 121), player: 0, state: state))
    #expect(!benchConditionHolds(.pillAt(pill: 0, x: 105, y: 100), player: 0, state: state))

    #expect(!benchConditionHolds(.peerGone, player: 0, state: state))
    state.players[1].connected = false
    #expect(benchConditionHolds(.peerGone, player: 0, state: state))
    state.players[1].connected = true

    state.players[0].mines = 3
    #expect(benchConditionHolds(.minesAtMost(3), player: 0, state: state))
    #expect(!benchConditionHolds(.minesAtMost(2), player: 0, state: state))
    #expect(benchConditionHolds(.terrain(x: 100, y: 100, anyOf: [Terrain.grass0.rawValue]), player: 0, state: state))
    #expect(!benchConditionHolds(.terrain(x: 300, y: 100, anyOf: [Terrain.grass0.rawValue]), player: 0, state: state))
    #expect(benchConditionHolds(.builderReady, player: 0, state: state))
}
