import Testing
import BoloKit

private func connectedPlayer(dead: Bool = false) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.dead = dead
    p.used = true
    return p
}

private func makeState(players: [PlayerState], localPlayer: Int = 0, ticks: UInt64 = 100) -> GameState {
    var state = GameState()
    state.players = players
    state.localPlayer = localPlayer
    state.ticks = ticks
    // Safe default square — a bare GameState() puts (0,0) in the mined-sea
    // border ring; same pitfall recorded in every prior wave's tests.
    state.terrain[50, 50] = .grass0
    // killBuilder() (Wave 5.2b) picks a random respawn among state.starts
    // via arc4random_uniform(state.starts.count) — an empty starts array
    // crashes (indexes into an empty array) the moment any test's builder
    // gets killed via the "other player caused this explosion" path.
    state.starts = [Start(x: 50, y: 50, dir: 0)]
    return state
}

// MARK: - clearTerrain

@Test func clearTerrainFalseOutsideMineZone() {
    let state = makeState(players: [])
    #expect(!clearTerrain(x: 5, y: 50, state: state))
    #expect(!clearTerrain(x: 250, y: 50, state: state))
}

@Test func clearTerrainTrueAtMineZoneBoundary() {
    var state = makeState(players: [])
    state.terrain[mineZoneMin, 50] = .grass0
    state.terrain[mineZoneMax, 50] = .grass0
    #expect(clearTerrain(x: mineZoneMin, y: 50, state: state))
    #expect(clearTerrain(x: mineZoneMax, y: 50, state: state))
}

@Test func clearTerrainFalseForWallAndDamagedWall() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .wall
    #expect(!clearTerrain(x: 50, y: 50, state: state))
    state.terrain[50, 50] = .damagedWall2
    #expect(!clearTerrain(x: 50, y: 50, state: state))
}

@Test func clearTerrainFalseWhenPillOrBaseOccupies() {
    var state = makeState(players: [])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 0)]
    #expect(!clearTerrain(x: 50, y: 50, state: state))

    state.pills = []
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: playerNeutral, shells: 0, mines: 0)]
    #expect(!clearTerrain(x: 50, y: 50, state: state))
}

// MARK: - dropPills

@Test func dropPillsPlacesAtOriginWhenClear() {
    var state = makeState(players: [])
    state.pills = [Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 40, counter: 0)]

    dropPills(player: 0, x: 50.5, y: 50.5, pills: 0b1, state: &state)

    #expect(state.pills[0].x == 50)
    #expect(state.pills[0].y == 50)
    #expect(state.pills[0].armour == 0)
    #expect(state.pills[0].speed == UInt8(maxTicksPerShot))
}

@Test func dropPillsSpiralsOutwardWhenOriginOccupied() {
    var state = makeState(players: [])
    // A pill already sits at (50, 50); the second pill must land elsewhere.
    state.pills = [
        Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 0),
        Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 40, counter: 0),
    ]

    dropPills(player: 0, x: 50.5, y: 50.5, pills: 0b10, state: &state)

    #expect(!(state.pills[1].x == 50 && state.pills[1].y == 50))
    #expect(state.pills[1].armour == 0)
}

@Test func dropPillsMultipleBitsClaimDistinctSquares() {
    var state = makeState(players: [])
    state.pills = [
        Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 40, counter: 0),
        Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 40, counter: 0),
    ]

    dropPills(player: 0, x: 50.5, y: 50.5, pills: 0b11, state: &state)

    #expect(state.pills[0].armour == 0)
    #expect(state.pills[1].armour == 0)
    #expect(!(state.pills[0].x == state.pills[1].x && state.pills[0].y == state.pills[1].y))
}

// Note: deliberately no test drives `dropPills` with a starting point
// clamped to *outside* the mine zone (e.g. x < 0 or x >= 256, both of
// which clamp to a coordinate outside `[mineZoneMin, mineZoneMax]`). The
// outward spiral has no termination guarantee if the origin itself is
// unreachable from the placeable zone — a latent property of the
// original algorithm, not something this port needs to guard against
// beyond what C provides (a real death position is always within the
// playable island).

@Test func dropPillsNaNXClampsXButNotYReplicatingTheBug() {
    // C's copy-paste bug: checks `isnan(x)` for BOTH the x- and y-clamp
    // branches, never `isnan(y)` — but by the time the y-block's
    // `isnan(x)` check runs, the x-block above has ALREADY reassigned `x`
    // to 128.0, so it's no longer NaN. Net effect: x clamps to 128, y is
    // NEVER clamped via this path regardless of which axis was originally
    // NaN. Regression test documenting the bug is intentional — a naive
    // "fix" that clamps y too would be wrong.
    var state = makeState(players: [])
    state.pills = [Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 40, counter: 0)]
    state.terrain[128, 50] = .grass0

    dropPills(player: 0, x: Float.nan, y: 50.5, pills: 0b1, state: &state)

    #expect(state.pills[0].x == 128)
    #expect(state.pills[0].y == 50)
}

// MARK: - floodTest / floodAt / flood: ring-buffer delay

@Test func floodTestSchedulesWaterLikeTerrainAndFloodDrainsAfterExactDelay() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .river

    floodTest(x: 50, y: 50, state: &state)

    // Draining every tick up to (but not including) the delay should not
    // touch anything; the crater conversion downstream only happens once
    // flood() actually reaches the scheduled slot.
    state.terrain[49, 50] = .crater  // neighbor that floodAt would convert, to observe drain timing
    for _ in 0..<(floodTicks - 1) {
        state.ticks += 1
        flood(state: &state)
        #expect(state.terrain[49, 50] == .crater, "should not have drained yet")
    }
    state.ticks += 1
    flood(state: &state)
    // At the correct tick, flood() processes the scheduled (50,50) point's
    // neighbors — (49,50) among them — converting crater to river.
    #expect(state.terrain[49, 50] == .river)
}

@Test func floodTestNoOpForNonWaterTerrain() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .grass0
    floodTest(x: 50, y: 50, state: &state)
    #expect(state.floods.allSatisfy { $0.isEmpty })
}

@Test func floodAtConvertsCraterToRiverAndReschedules() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .crater
    floodAt(x: 50, y: 50, state: &state)
    #expect(state.terrain[50, 50] == .river)
    #expect(state.floods.contains { $0.contains(Pointi(x: 50, y: 50)) })
}

@Test func floodAtDetonatesMinedTerrain() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .minedGrass
    floodAt(x: 50, y: 50, state: &state)
    #expect(state.terrain[50, 50] == .crater)  // explosionAt converted it
}

// MARK: - chainAt / chain: ring-buffer delay

@Test func chainReactionDetonatesMinedNeighborAfterExactDelay() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .minedGrass  // will be the origin, already exploded
    state.terrain[51, 50] = .minedGrass  // neighbor, should chain-detonate

    // Schedule (50,50) directly into the chain ring (as explosionAt would).
    let slot = Int((UInt32(state.ticks) &- 1) % UInt32(chainTicks + 1))
    state.chains[slot].append(Pointi(x: 50, y: 50))

    for _ in 0..<(chainTicks - 1) {
        state.ticks += 1
        chain(state: &state)
        #expect(state.terrain[51, 50] == .minedGrass, "should not have chained yet")
    }
    state.ticks += 1
    chain(state: &state)
    #expect(state.terrain[51, 50] == .crater)
}

@Test func chainAtNoOpForNonMinedTerrain() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .grass0
    chainAt(x: 50, y: 50, state: &state)
    #expect(state.terrain[50, 50] == .grass0)
}

// MARK: - explosionAt: terrain switch

@Test func explosionAtConvertsMineableTerrainAndSchedulesChainAndFlood() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.terrain[50, 50] == .crater)
    #expect(state.chains.contains { $0.contains(Pointi(x: 50, y: 50)) })
}

@Test func explosionAtMinedSeaDetonatesWithoutTerrainChangeOrScheduling() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .minedSea

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.terrain[50, 50] == .minedSea)  // unchanged
    #expect(state.chains.allSatisfy { $0.isEmpty })  // no chain scheduled
}

@Test func explosionAtPlainSeaIsNoOp() {
    var state = makeState(players: [])
    state.terrain[50, 50] = .sea

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.terrain[50, 50] == .sea)
    #expect(state.explosions.isEmpty)
}

// MARK: - explosionAt: self vs. other gating

@Test func explosionAtCausedByLocalPlayerSkipsGlobalParticleAndBuilderCheck() {
    var player = connectedPlayer()
    var state = makeState(players: [player], localPlayer: 0)
    state.terrain[50, 50] = .grass0
    player.builder = Vec2f(x: 50.5, y: 50.5)
    state.players[0].builder = Vec2f(x: 50.5, y: 50.5)
    state.players[0].builderStatus = .work

    explosionAt(player: UInt8(state.localPlayer), x: 50, y: 50, state: &state)

    #expect(state.explosions.isEmpty)
    #expect(state.players[0].builderStatus == .work)  // not killed
}

@Test func explosionAtCausedByOtherCreatesParticleAndKillsBuilder() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.terrain[50, 50] = .grass0
    state.players[0].builder = Vec2f(x: 50.5, y: 50.5)
    state.players[0].builderStatus = .work

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.explosions.count == 1)
    #expect(state.players[0].builderStatus == .parachute)  // killed
}

// MARK: - explosionAt: splash damage escalation

@Test func explosionAtSplashDamagesNearbyAliveLocalTank() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 40
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)  // exactly at the explosion center

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.local.armour == 40 - smallboomDamage)
    #expect(!state.players[0].boat)
}

@Test func explosionAtSplashOutOfRadiusDoesNotDamage() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 40
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 60.5, y: 60.5)  // far away

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.local.armour == 40)
}

@Test func explosionAtSplashDoesNotDamageAlreadyDeadLocalTank() {
    // Confirms the self-caused case (already dead from its own smallboom())
    // is naturally excluded without needing a player-identity check here.
    var state = makeState(players: [connectedPlayer(dead: true)], localPlayer: 0)
    state.local.armour = 40
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.local.armour == 40)
}

@Test func explosionAtSplashLethalWithMinesEscalatesToSuperboom() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 5  // will go negative from 10 damage
    state.local.mines = 33  // > 32
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.local.armour == 0)
    #expect(state.players[0].dead)
    // superboom's 2x2 terrain mutation happened at the TANK's square via
    // onSuperboomTerrain, which defaults to a no-op here — but the local
    // player must be dead and deaths incremented, matching superboom()'s
    // own unconditional kill.
    #expect(state.local.deaths == 1)
}

@Test func explosionAtSplashLethalWithFewerMinesEscalatesToSmallboom() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 5
    state.local.mines = 10  // > 0 but not > 32
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.players[0].dead)
    #expect(state.local.deaths == 1)
}

@Test func explosionAtSplashLethalWithNoMinesOrShellsCallsKillTank() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 5
    state.local.mines = 0
    state.local.shells = 0
    state.terrain[50, 50] = .grass0
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)

    explosionAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.players[0].dead)
    #expect(state.local.deaths == 1)
    #expect(state.local.respawnCounter == 0)  // killTank's signature reset, not smallboom's
}

// MARK: - superboomAt

@Test func superboomAtConvertsAll4CellsExceptSea() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .wall
    state.terrain[50, 51] = .sea
    state.terrain[51, 51] = .minedSea

    superboomAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.terrain[50, 50] == .crater)
    #expect(state.terrain[51, 50] == .crater)  // wall IS converted
    #expect(state.terrain[50, 51] == .sea)  // sea excluded
    #expect(state.terrain[51, 51] == .minedSea)  // mined-sea excluded
}

@Test func superboomAtSchedulesFourChainEntriesOneForEachCell() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 51] = .grass0
    state.terrain[51, 51] = .grass0

    superboomAt(player: playerNeutral, x: 50, y: 50, state: &state)

    let scheduled = Set(state.chains.flatMap { $0 })
    #expect(scheduled.isSuperset(of: [
        Pointi(x: 50, y: 50), Pointi(x: 51, y: 50), Pointi(x: 50, y: 51), Pointi(x: 51, y: 51),
    ]))
}

@Test func superboomAtCausedByLocalPlayerSkipsParticlesAndDamage() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 40
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 51] = .grass0
    state.terrain[51, 51] = .grass0
    state.players[0].tank = Vec2f(x: 51.0, y: 51.0)

    superboomAt(player: UInt8(state.localPlayer), x: 50, y: 50, state: &state)

    #expect(state.explosions.isEmpty)
    #expect(state.local.armour == 40)
}

@Test func superboomAtCausedByOtherCreatesNineParticlesAndDamagesLocalTank() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 40
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 51] = .grass0
    state.terrain[51, 51] = .grass0
    state.players[0].tank = Vec2f(x: 51.0, y: 51.0)  // at the superboom's center

    superboomAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.explosions.count == 9)
    #expect(state.local.armour == 40 - superboomDamage)
}

@Test func superboomAtSplashOutOfRadiusDoesNotDamage() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.local.armour = 40
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 51] = .grass0
    state.terrain[51, 51] = .grass0
    state.players[0].tank = Vec2f(x: 60.5, y: 60.5)

    superboomAt(player: playerNeutral, x: 50, y: 50, state: &state)

    #expect(state.local.armour == 40)
}
