import Testing
import BoloKit

private func makeState(
    starts: [Start],
    bases: [Base] = [],
    pills: [Pill] = [],
    dominationType: DominationType = .open
) -> GameState {
    var state = GameState()
    // Safe default square — a bare GameState() puts (0,0) in the mined-sea
    // border ring; same pitfall recorded in every prior wave's tests.
    state.terrain[50, 50] = .grass0
    state.starts = starts
    state.bases = bases
    state.pills = pills
    var local = PlayerState()
    local.used = true
    local.connected = true
    local.dead = true
    state.players = [local]
    state.localPlayer = 0
    state.dominationType = dominationType
    return state
}

// MARK: - Field assignments

@Test func spawnResetsTankFieldsAndForcesBoatRegardlessOfTerrain() {
    // Start sits on land (grass0, not water) — `boat = true` is set
    // unconditionally by C's spawn(), regardless of the start's terrain.
    var state = makeState(starts: [Start(x: 20, y: 30, dir: 4)])
    state.terrain[20, 30] = .grass0

    spawn(state: &state)

    let p = state.players[0]
    #expect(p.dead == false)
    #expect(p.tank == Vec2f(x: 20.5, y: 30.5))
    #expect(p.dir == Float(4) * (kPif / 8.0))
    #expect(p.speed == 0)
    #expect(p.turnSpeed == 0)
    #expect(p.kickSpeed == 0)
    #expect(p.kickDir == 0)
    #expect(p.boat == true)
    #expect(state.local.range == maxShellRange)
    #expect(state.local.spawned == true)
}

// MARK: - Resource init by dominationType

@Test func spawnOpenGameMaxesAllResources() {
    var state = makeState(starts: [Start(x: 20, y: 30, dir: 0)], dominationType: .open)

    spawn(state: &state)

    #expect(state.local.shells == maxShells)
    #expect(state.local.mines == maxMines)
    #expect(state.local.armour == maxArmour)
    #expect(state.local.trees == maxTrees)
}

@Test func spawnTournamentGameShellsCountTwicePerNeutralBase() {
    var state = makeState(
        starts: [Start(x: 20, y: 30, dir: 0)],
        bases: [
            Base(x: 1, y: 1, armour: 5, owner: playerNeutral, shells: 0, mines: 0),
            Base(x: 2, y: 2, armour: 5, owner: playerNeutral, shells: 0, mines: 0),
            Base(x: 3, y: 3, armour: 5, owner: playerNeutral, shells: 0, mines: 0),
            Base(x: 4, y: 4, armour: 5, owner: 7, shells: 0, mines: 0),
        ],
        dominationType: .tournament
    )

    spawn(state: &state)

    #expect(state.local.shells == 6)
    #expect(state.local.mines == 0)
    #expect(state.local.armour == maxArmour)
    #expect(state.local.trees == 0)
}

@Test func spawnStrictGameZeroesEverythingButArmour() {
    var state = makeState(starts: [Start(x: 20, y: 30, dir: 0)], dominationType: .strict)

    spawn(state: &state)

    #expect(state.local.shells == 0)
    #expect(state.local.mines == 0)
    #expect(state.local.armour == maxArmour)
    #expect(state.local.trees == 0)
}

// MARK: - Weighted selection

@Test func spawnNeverPicksStartZeroedByHostilePill() {
    // Start A sits next to a pill owned by a player with no alliance to
    // the local player — Pass 1 zeroes its weight. Start B is clear.
    var state = makeState(
        starts: [Start(x: 20, y: 20, dir: 0), Start(x: 200, y: 200, dir: 0)],
        pills: [Pill(x: 21, y: 20, armour: 5, owner: 5, speed: 10, counter: 0)]
    )

    for _ in 0..<40 {
        state.players[0].dead = true
        spawn(state: &state)
        #expect(state.players[0].tank == Vec2f(x: 200.5, y: 200.5))
    }
}

@Test func spawnPass2DropsPillPenaltyWhenAllStartsAreSpiked() {
    // Both starts sit next to a hostile pill — Pass 1 sums to weight 0 for
    // every start, so Pass 2 must recompute ignoring the pill-penalty loop
    // entirely, restoring both starts to equal nonzero weight. If Pass 2
    // instead kept the pill penalty, `spawn()` would deterministically
    // resolve to the same single start every time (the last index in the
    // cumulative-sum scan, since every weight is 0).
    var state = makeState(
        starts: [Start(x: 20, y: 20, dir: 0), Start(x: 200, y: 200, dir: 0)],
        pills: [
            Pill(x: 21, y: 20, armour: 5, owner: 5, speed: 10, counter: 0),
            Pill(x: 201, y: 200, armour: 5, owner: 5, speed: 10, counter: 0),
        ]
    )

    var sawStartA = false
    var sawStartB = false
    for _ in 0..<60 {
        state.players[0].dead = true
        spawn(state: &state)
        if state.players[0].tank == Vec2f(x: 20.5, y: 20.5) { sawStartA = true }
        if state.players[0].tank == Vec2f(x: 200.5, y: 200.5) { sawStartB = true }
    }

    #expect(sawStartA)
    #expect(sawStartB)
}

@Test func spawnNeutralBaseCountsSafeButNeutralPillCountsHostile() {
    // Start A sits next to a NEUTRAL-owned base — neutral bases count as
    // safe (`owner == playerNeutral ||` in the base-boost loop), so A
    // keeps a nonzero weight. Start B sits next to a NEUTRAL-owned pill —
    // `testAlliance` returns false for the out-of-range `playerNeutral`
    // sentinel, so a neutral pill is treated as hostile and zeroes B's
    // weight. This is the asymmetry the two loops are built around.
    var state = makeState(
        starts: [Start(x: 20, y: 20, dir: 0), Start(x: 200, y: 200, dir: 0)],
        bases: [Base(x: 21, y: 20, armour: 5, owner: playerNeutral, shells: 0, mines: 0)],
        pills: [Pill(x: 201, y: 200, armour: 5, owner: playerNeutral, speed: 10, counter: 0)]
    )

    for _ in 0..<40 {
        state.players[0].dead = true
        spawn(state: &state)
        #expect(state.players[0].tank == Vec2f(x: 20.5, y: 20.5))
    }
}
