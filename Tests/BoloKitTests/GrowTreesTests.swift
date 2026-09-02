import Testing
import BoloKit

private func makeState(connectedPlayers: Int = 1) -> GameState {
    var state = GameState()
    state.terrain[50, 50] = .grass0
    state.players = (0..<max(connectedPlayers, 0)).map { _ in
        var p = PlayerState()
        p.used = true
        p.connected = true
        return p
    }
    return state
}

// MARK: - treeScore / baseScore / adjacentScore

@Test func adjacentScoreIsOneForForestAndMinedForestOnly() {
    var state = makeState()
    state.terrain[10, 10] = .forest
    state.terrain[11, 10] = .minedForest
    state.terrain[12, 10] = .grass0

    #expect(adjacentScore(x: 10, y: 10, state: state) == 1)
    #expect(adjacentScore(x: 11, y: 10, state: state) == 1)
    #expect(adjacentScore(x: 12, y: 10, state: state) == 0)
}

@Test func adjacentScoreOutOfBoundsIsZero() {
    let state = makeState()
    #expect(adjacentScore(x: -1, y: 10, state: state) == 0)
    #expect(adjacentScore(x: 256, y: 10, state: state) == 0)
}

@Test func baseScoreZeroWhenPillOrBaseOccupiesSquare() {
    var state = makeState()
    state.terrain[10, 10] = .grass0
    state.pills = [Pill(x: 10, y: 10, armour: 10, owner: playerNeutral, speed: 50, counter: 0)]
    #expect(baseScore(x: 10, y: 10, state: state) == 0)

    state.pills = []
    state.bases = [Base(x: 10, y: 10, armour: 50, owner: playerNeutral, shells: 0, mines: 0)]
    #expect(baseScore(x: 10, y: 10, state: state) == 0)
}

@Test func baseScoreRanksTerrainTiersGrassHighestRoadLowest() {
    var state = makeState()
    state.terrain[10, 10] = .grass2
    state.terrain[11, 10] = .swamp1
    state.terrain[12, 10] = .crater
    state.terrain[13, 10] = .rubble3
    state.terrain[14, 10] = .road
    state.terrain[15, 10] = .minedGrass
    state.terrain[16, 10] = .sea

    #expect(baseScore(x: 10, y: 10, state: state) == 5)
    #expect(baseScore(x: 11, y: 10, state: state) == 4)
    #expect(baseScore(x: 12, y: 10, state: state) == 3)
    #expect(baseScore(x: 13, y: 10, state: state) == 2)
    #expect(baseScore(x: 14, y: 10, state: state) == 1)
    #expect(baseScore(x: 15, y: 10, state: state) == 5)
    #expect(baseScore(x: 16, y: 10, state: state) == 0)
}

@Test func treeScoreWeightsOrthogonalNeighborsDoubleDiagonal() {
    var state = makeState()
    state.terrain[10, 10] = .grass0
    // One orthogonal forest neighbor, no diagonals: 5 * (2*1) = 10.
    state.terrain[11, 10] = .forest
    #expect(treeScore(x: 10, y: 10, state: state) == 10)

    // Add one diagonal forest neighbor: 5 * (2*1 + 1) = 15.
    state.terrain[11, 11] = .minedForest
    #expect(treeScore(x: 10, y: 10, state: state) == 15)
}

@Test func treeScoreFullySurroundedByForestIsMaximal() {
    var state = makeState()
    let (wx, wy) = (100, 100)
    state.terrain[wx, wy] = .grass0
    for dx in -1...1 {
        for dy in -1...1 where !(dx == 0 && dy == 0) {
            state.terrain[wx + dx, wy + dy] = .forest
        }
    }
    // basescore(grass) = 5; 4 orthogonal * 2 + 4 diagonal = 12; 5*12 = 60.
    #expect(treeScore(x: wx, y: wy, state: state) == 60)
}

// MARK: - growTrees: integer arithmetic (D-trap: nplayers * (treesBestOf / (treesPlantRate * Int(ticksPerSec))))

@Test func growTreesIterationCountIsNplayersTimesEight() {
    var state = makeState(connectedPlayers: 1)
    state.grow = GrowState(growX: 50, growY: 50, growBestOf: 0)
    growTrees(state: &state)
    // 4200 / (10 * 50) = 8 exactly, via integer division.
    #expect(state.grow.growBestOf == 8)

    var state3 = makeState(connectedPlayers: 3)
    state3.grow = GrowState(growX: 50, growY: 50, growBestOf: 0)
    growTrees(state: &state3)
    #expect(state3.grow.growBestOf == 24)
}

@Test func growTreesWithNoConnectedPlayersDoesNothing() {
    var state = makeState(connectedPlayers: 0)
    state.grow = GrowState(growX: 50, growY: 50, growBestOf: 0)
    var grew = false
    growTrees(state: &state) { _, _ in grew = true }
    #expect(state.grow.growBestOf == 0)
    #expect(grew == false)
}

// MARK: - growTrees: applyGrow terrain table (deterministic — zero pills/bases
// anywhere means the (buggy) outer guard always passes, isolating the
// terrain-transition switch from the RNG-dependent outer-guard behavior).

@Test func growTreesPlainTerrainGrowsToForest() {
    var state = makeState(connectedPlayers: 1)
    let (wx, wy) = (60, 60)
    state.terrain[wx, wy] = .rubble2
    state.grow = GrowState(growX: wx, growY: wy, growBestOf: treesBestOf - 1)

    var grown: (Int, Int)?
    growTrees(state: &state) { x, y in grown = (x, y) }

    #expect(state.terrain[wx, wy] == .forest)
    #expect(grown?.0 == wx && grown?.1 == wy)
}

@Test func growTreesMinedTerrainGrowsToMinedForest() {
    var state = makeState(connectedPlayers: 1)
    let (wx, wy) = (60, 60)
    state.terrain[wx, wy] = .minedRoad
    state.grow = GrowState(growX: wx, growY: wy, growBestOf: treesBestOf - 1)

    var grown: (Int, Int)?
    growTrees(state: &state) { x, y in grown = (x, y) }

    #expect(state.terrain[wx, wy] == .minedForest)
    #expect(grown?.0 == wx && grown?.1 == wy)
}

@Test func growTreesNonGrowableTerrainIsNoOpAndFiresNoEvent() {
    var state = makeState(connectedPlayers: 1)
    let (wx, wy) = (60, 60)
    state.terrain[wx, wy] = .sea
    state.grow = GrowState(growX: wx, growY: wy, growBestOf: treesBestOf - 1)

    var grew = false
    growTrees(state: &state) { _, _ in grew = true }

    #expect(state.terrain[wx, wy] == .sea)
    #expect(grew == false)
}

@Test func growTreesInnerGuardBlocksWhenWinnerSquareIsOccupied() {
    var state = makeState(connectedPlayers: 1)
    let (wx, wy) = (60, 60)
    state.terrain[wx, wy] = .grass0
    state.bases = [Base(x: UInt8(wx), y: UInt8(wy), armour: 50, owner: playerNeutral, shells: 0, mines: 0)]
    state.grow = GrowState(growX: wx, growY: wy, growBestOf: treesBestOf - 1)

    var grew = false
    growTrees(state: &state) { _, _ in grew = true }

    #expect(state.terrain[wx, wy] == .grass0)
    #expect(grew == false)
}

// MARK: - growTrees: outer-guard C bug (checks the LAST-SAMPLED cell, not the
// tournament winner) — replicated intentionally, per docs/PLAN.md's known
// divergences table. Statistical test: the winner is fixed at maximal
// treescore (so the tournament comparison can never dislodge it) and left
// permanently clear of pills; ~25% of the *rest* of the board is
// pill-occupied. If the outer guard correctly checked the winner (bug
// fixed), growth would succeed every trial. Observing it blocked on *some*
// trials proves the guard is keying off the random last sample instead.
@Test func growTreesOuterGuardChecksLastSampledCellNotTheWinner() {
    let (wx, wy) = (128, 128)
    var base = GameState()
    base.terrain[wx, wy] = .grass0
    for dx in -1...1 {
        for dy in -1...1 where !(dx == 0 && dy == 0) {
            base.terrain[wx + dx, wy + dy] = .forest
        }
    }
    var player = PlayerState()
    player.used = true
    player.connected = true
    base.players = [player]

    var pills: [Pill] = []
    for y in 0..<256 {
        for x in 0..<256 {
            if x == wx && y == wy { continue }
            if (x * 7 + y * 13) % 4 == 0 {
                pills.append(Pill(x: UInt8(x), y: UInt8(y), armour: 10, owner: playerNeutral, speed: 50, counter: 0))
            }
        }
    }
    base.pills = pills

    var grewCount = 0
    var blockedCount = 0
    for _ in 0..<60 {
        var trial = base
        trial.grow = GrowState(growX: wx, growY: wy, growBestOf: treesBestOf - 1)
        var grew = false
        growTrees(state: &trial) { _, _ in grew = true }
        // The tournament winner's treescore (60) is the global maximum, so
        // the single sample this trial takes can never dislodge (wx, wy) —
        // the inner guard's target is guaranteed fixed and always clear.
        if grew {
            grewCount += 1
        } else {
            blockedCount += 1
        }
    }

    #expect(grewCount > 0)
    #expect(blockedCount > 0)
}

// MARK: - coolPills

@Test func coolPillsIgnoresOnboardPills() {
    var state = GameState()
    state.pills = [Pill(x: 10, y: 10, armour: pillOnboard, owner: 0, speed: 5, counter: 0, coolCounter: 0)]
    coolPills(state: &state)
    #expect(state.pills[0].coolCounter == 0)
    #expect(state.pills[0].speed == 5)
}

@Test func coolPillsAppliesToDeadPillsTooNoArmourGuard() {
    // C's cool-pills loop only checks `armour != ONBOARD` — a dead pill
    // (armour == 0) is not excluded, unlike pilllogic's firing path.
    var state = GameState()
    state.pills = [Pill(x: 10, y: 10, armour: 0, owner: 0, speed: 5, counter: 0, coolCounter: UInt8(coolPillTicks - 1))]
    coolPills(state: &state)
    #expect(state.pills[0].speed == 6)
    #expect(state.pills[0].coolCounter == 0)
}

@Test func coolPillsIncrementsSpeedAtThresholdAndResetsCounter() {
    var state = GameState()
    state.pills = [Pill(x: 10, y: 10, armour: 10, owner: 0, speed: 5, counter: 0, coolCounter: 0)]

    for _ in 0..<(coolPillTicks - 1) {
        coolPills(state: &state)
    }
    #expect(state.pills[0].coolCounter == UInt8(coolPillTicks - 1))
    #expect(state.pills[0].speed == 5)

    coolPills(state: &state)
    #expect(state.pills[0].coolCounter == 0)
    #expect(state.pills[0].speed == 6)
}

@Test func coolPillsClampsSpeedAtMaxTicksPerShotButStillResetsCounter() {
    var state = GameState()
    state.pills = [
        Pill(
            x: 10, y: 10, armour: 10, owner: 0, speed: UInt8(maxTicksPerShot), counter: 0,
            coolCounter: UInt8(coolPillTicks - 1)
        )
    ]
    coolPills(state: &state)
    #expect(state.pills[0].speed == UInt8(maxTicksPerShot))
    #expect(state.pills[0].coolCounter == 0)
}

@Test func coolPillsNeverTouchesTheFireCadenceCounter() {
    // Regression for the D27-shaped field split: `coolCounter` (server
    // reload-degrade tally) and `counter` (client fire-cadence tally,
    // owned by pillTick) must be fully independent fields.
    var state = GameState()
    state.pills = [Pill(x: 10, y: 10, armour: 10, owner: 0, speed: 5, counter: 17, coolCounter: 0)]

    for _ in 0..<100 {
        coolPills(state: &state)
    }

    #expect(state.pills[0].counter == 17)
}

// MARK: - replenishBases

@Test func replenishBasesCounterScalesWithConnectedPlayerCountNotFlatOne() {
    var state = makeState(connectedPlayers: 3)
    state.bases = [Base(x: 10, y: 10, armour: 50, owner: playerNeutral, shells: 10, mines: 10)]
    replenishBases(state: &state)
    #expect(state.bases[0].counter == 3)
}

@Test func replenishBasesNoConnectedPlayersNeverAccumulates() {
    var state = makeState(connectedPlayers: 0)
    state.bases = [Base(x: 10, y: 10, armour: 50, owner: playerNeutral, shells: 10, mines: 10, counter: 100)]
    replenishBases(state: &state)
    #expect(state.bases[0].counter == 100)
}

@Test func replenishBasesAtThresholdIncrementsAllThreeResourcesAndResets() {
    var state = makeState(connectedPlayers: 1)
    state.bases = [
        Base(
            x: 10, y: 10, armour: 50, owner: playerNeutral, shells: 10, mines: 10,
            counter: UInt16(replenishBaseTicks - 1)
        )
    ]
    var replenished = false
    replenishBases(state: &state) { _ in replenished = true }

    #expect(state.bases[0].armour == 51)
    #expect(state.bases[0].shells == 11)
    #expect(state.bases[0].mines == 11)
    #expect(state.bases[0].counter == 0)
    #expect(replenished == true)
}

@Test func replenishBasesClampsAtMaximums() {
    var state = makeState(connectedPlayers: 1)
    state.bases = [
        Base(
            x: 10, y: 10, armour: UInt8(maxBaseArmour), owner: playerNeutral,
            shells: UInt8(maxBaseShells), mines: UInt8(maxBaseMines),
            counter: UInt16(replenishBaseTicks - 1)
        )
    ]
    replenishBases(state: &state)

    #expect(state.bases[0].armour == UInt8(maxBaseArmour))
    #expect(state.bases[0].shells == UInt8(maxBaseShells))
    #expect(state.bases[0].mines == UInt8(maxBaseMines))
}
