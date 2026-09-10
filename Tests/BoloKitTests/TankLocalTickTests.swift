import Testing
import BoloKit

private func makeState(player: PlayerState, local: LocalPlayerState = LocalPlayerState()) -> GameState {
    var state = GameState()
    state.players = [player]
    state.localPlayer = 0
    state.local = local
    return state
}

private func connectedPlayer(dead: Bool = false, boat: Bool = false) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.dead = dead
    p.boat = boat
    return p
}

// MARK: - enterTile: pill branch

@Test func enterTileArmedPillTriggersSuperboom() {
    var state = makeState(player: connectedPlayer())
    state.pills = [Pill(x: 5, y: 5, armour: 10, owner: playerNeutral, speed: 50, counter: 0)]
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.players[0].dead)
    #expect(state.local.deaths == 1)
}

@Test func enterTileDeadPillCapturesAndDropsBoat() {
    var state = makeState(player: connectedPlayer(boat: true))
    state.pills = [Pill(x: 5, y: 5, armour: 0, owner: playerNeutral, speed: 0, counter: 0)]
    state.terrain[5, 5] = .grass0
    state.terrain[4, 5] = .river
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.pills[0].owner == 0)
    #expect(state.pills[0].armour == pillOnboard)
    #expect(!state.players[0].boat)
    #expect(state.terrain[4, 5] == .boat)
}

@Test func enterTileDeadPillNoCaptureWhenStationary() {
    // new == old: no grab, no boat-drop attempt (matches C's !isequalpoint guards).
    var state = makeState(player: connectedPlayer(boat: true))
    state.pills = [Pill(x: 5, y: 5, armour: 0, owner: playerNeutral, speed: 0, counter: 0)]
    state.terrain[5, 5] = .grass0
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 5, y: 5), state: &state)
    #expect(state.pills[0].owner == playerNeutral)
    #expect(state.players[0].boat)
}

// MARK: - enterTile: base branch

@Test func enterTileNeutralBaseIsCaptured() {
    var state = makeState(player: connectedPlayer())
    state.bases = [Base(x: 5, y: 5, armour: 0, owner: playerNeutral, shells: 0, mines: 0)]
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.bases[0].owner == 0)
    #expect(state.bases[0].armour == UInt8(maxBaseArmour))
}

@Test func enterTileHostileBaseCapturedAndZeroed() {
    var state = makeState(player: connectedPlayer())
    state.players.append(connectedPlayer())
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 1, shells: 50, mines: 50)]
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.bases[0].owner == 0)
    #expect(state.bases[0].armour == 0)
    #expect(state.bases[0].shells == 0)
    #expect(state.bases[0].mines == 0)
}

@Test func enterTileAlliedBaseIsLeftUntouched() {
    // C's `enter()` only sends the grab-tile message (which is what actually
    // transfers ownership) when `owner == NEUTRAL || !testalliance(...)` — an
    // already-allied base is walked over with no ownership change at all.
    // `grabTile`'s own internal ally-handoff branch (ownership transfers,
    // resources untouched) exists for structural fidelity with
    // `recvclgrabtile()` but is unreachable from this call path, exactly as
    // in C.
    var state = makeState(player: connectedPlayer())
    state.players.append(connectedPlayer())
    state.players[0].used = true
    state.players[1].used = true
    state.players[0].alliance = 1 << 1
    state.players[1].alliance = 1 << 0
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 1, shells: 50, mines: 50)]
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.bases[0].owner == 1)
    #expect(state.bases[0].armour == 50)
}

@Test func enterTileWalkingOntoOwnBaseZeroesResourcesLikeHostile() {
    // C has no "already mine" special case in recvclgrabtile: the alliance
    // bitmask check is between `owner` and `player`, and a player has no bit
    // set for itself by default, so re-entering your own (unallied-to-self)
    // base takes the hostile-takeover branch, zeroing its resources. This is
    // a faithful replication of that structure, not a design choice made here.
    var state = makeState(player: connectedPlayer(boat: true))
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 0, shells: 50, mines: 50)]
    state.terrain[4, 5] = .river
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(!state.players[0].boat)
    #expect(state.terrain[4, 5] == .boat)
    #expect(state.bases[0].armour == 0)
}

// MARK: - enterTile: plain terrain

@Test func enterTileWallTriggersSuperboom() {
    var state = makeState(player: connectedPlayer())
    state.terrain[5, 5] = .wall
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.players[0].dead)
}

@Test func enterTileSeaDrownsWithoutBoat() {
    var state = makeState(player: connectedPlayer(boat: false))
    state.terrain[5, 5] = .sea
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.players[0].dead)
}

@Test func enterTileSeaWithBoatSurvives() {
    var state = makeState(player: connectedPlayer(boat: true))
    state.terrain[5, 5] = .sea
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(!state.players[0].dead)
}

@Test func enterTileRiverIsNoOp() {
    var state = makeState(player: connectedPlayer())
    state.terrain[5, 5] = .river
    let before = state
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.players[0].dead == before.players[0].dead)
    #expect(state.players[0].boat == before.players[0].boat)
}

@Test func enterTileForestDeadTumbleSpawnsExplosionAndKillsBuilder() {
    var player = connectedPlayer(dead: true)
    player.builderStatus = .goto
    player.builder = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(player: player, local: LocalPlayerState(respawnCounter: 10))
    state.starts = [Start(x: 0, y: 0, dir: 0)]
    state.terrain[5, 5] = .forest
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.players[0].explosions.count == 1)
    #expect(state.players[0].builderStatus == .parachute)
}

@Test func enterTileForestFallsThroughToBoatDropAndMinePlant() {
    var player = connectedPlayer(boat: true)
    player.inputFlags = [.lmine]
    player.mines = 5
    var state = makeState(player: player)
    state.terrain[5, 5] = .forest
    state.terrain[4, 5] = .river
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(!state.players[0].boat)
    #expect(state.terrain[4, 5] == .boat)
    #expect(state.terrain[5, 5] == .minedForest)
    #expect(state.players[0].mines == 4)
}

@Test func enterTileGrassPlantsMineOnlyWhenMoved() {
    var player = connectedPlayer()
    player.inputFlags = [.lmine]
    player.mines = 5
    var state = makeState(player: player)
    state.terrain[5, 5] = .grass0
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 5, y: 5), state: &state)
    #expect(state.terrain[5, 5] == .grass0)
    #expect(state.players[0].mines == 5)
}

@Test func enterTileBoatTerrainRamWithBoatExplodesAndKillsBuilder() {
    var player = connectedPlayer(boat: true)
    player.builderStatus = .work
    player.builder = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(player: player)
    state.starts = [Start(x: 0, y: 0, dir: 0)]
    state.terrain[5, 5] = .boat
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.players[0].explosions.count == 1)
    #expect(state.players[0].builderStatus == .parachute)
}

@Test func enterTileBoatTerrainPickupWithoutBoat() {
    var state = makeState(player: connectedPlayer(boat: false))
    state.terrain[5, 5] = .boat
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.terrain[5, 5] == .river)
}

@Test func enterTileMinedSeaDrownsRegardlessOfBoat() {
    var state = makeState(player: connectedPlayer(boat: true))
    state.terrain[5, 5] = .minedSea
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.players[0].dead)
}

@Test func enterTileMinedLandTriggersMineExplosionCallback() {
    var state = makeState(player: connectedPlayer())
    state.terrain[5, 5] = .minedGrass
    var exploded: Pointi?
    enterTile(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == Pointi(x: 5, y: 5))
}

// MARK: - layMineOnKeyDown (D88 §3)

@Test func layMineOnKeyDownPlantsImmediatelyWithoutMovement() {
    var state = makeState(player: connectedPlayer())
    state.players[0].mines = 5
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = .grass0
    layMineOnKeyDown(state: &state)
    #expect(state.terrain[5, 5] == .minedGrass)
    #expect(state.players[0].mines == 4)
}

@Test func layMineOnKeyDownNoopsWhenNoMinesAvailable() {
    var state = makeState(player: connectedPlayer())
    state.players[0].mines = 0
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = .grass0
    layMineOnKeyDown(state: &state)
    #expect(state.terrain[5, 5] == .grass0)
}

@Test func layMineOnKeyDownNoopsWhileDead() {
    var state = makeState(player: connectedPlayer(dead: true))
    state.players[0].mines = 5
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = .grass0
    layMineOnKeyDown(state: &state)
    #expect(state.terrain[5, 5] == .grass0)
    #expect(state.players[0].mines == 5)
}

@Test func layMineOnKeyDownNoopsOnAPillTile() {
    var state = makeState(player: connectedPlayer())
    state.players[0].mines = 5
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = .grass0
    state.pills = [Pill(x: 5, y: 5, armour: 10, owner: playerNeutral, speed: 50, counter: 0)]
    layMineOnKeyDown(state: &state)
    #expect(state.terrain[5, 5] == .grass0)
    #expect(state.players[0].mines == 5)
}

@Test func layMineOnKeyDownNoopsOnABaseTile() {
    var state = makeState(player: connectedPlayer())
    state.players[0].mines = 5
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = .grass0
    state.bases = [Base(x: 5, y: 5, armour: 0, owner: playerNeutral, shells: 0, mines: 0)]
    layMineOnKeyDown(state: &state)
    #expect(state.terrain[5, 5] == .grass0)
    #expect(state.players[0].mines == 5)
}

@Test(arguments: [Terrain.sea, .wall, .river, .boat, .damagedWall0])
func layMineOnKeyDownNoopsOnUnminableTerrain(terrain: Terrain) {
    // D89: standing on unminable terrain must spend no mine -- `plantMine`'s
    // `Bool` return gates the decrement in `layMineOnKeyDown`, matching
    // `keyevent()`'s own terrain switch, which only decrements
    // `client.mines` inside its 15 matched minable cases (the original D88
    // §3 landing decremented unconditionally, wasting a mine here).
    var state = makeState(player: connectedPlayer())
    state.players[0].mines = 5
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = terrain
    layMineOnKeyDown(state: &state)
    #expect(state.terrain[5, 5] == terrain)
    #expect(state.players[0].mines == 5)
}

// MARK: - grabTile (direct)

@Test func grabTileAllyHandoffTransfersOwnershipWithoutResettingResources() {
    // Exercises the branch enterTile's gating condition keeps unreachable
    // from that call path (see enterTileAlliedBaseIsLeftUntouched) directly,
    // for structural-fidelity coverage of recvclgrabtile()'s three-way branch.
    var state = makeState(player: connectedPlayer())
    state.players.append(connectedPlayer())
    state.players[0].used = true
    state.players[1].used = true
    state.players[0].alliance = 1 << 1
    state.players[1].alliance = 1 << 0
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 1, shells: 50, mines: 50)]
    grabTile(at: Pointi(x: 5, y: 5), state: &state)
    #expect(state.bases[0].owner == 0)
    #expect(state.bases[0].armour == 50)
}

@Test func grabTilePicksUpBoatLeftByAnotherTank() {
    var state = makeState(player: connectedPlayer())
    state.terrain[5, 5] = .boat
    grabTile(at: Pointi(x: 5, y: 5), state: &state)
    #expect(state.terrain[5, 5] == .river)
}

// Wave 5.9: grabTile's mined-terrain case now really detonates via
// explosionAt, not just a no-op onMineExplosion callback.
@Test func grabTileMinedLandDetonatesTerrainAndSchedulesChain() {
    var state = makeState(player: connectedPlayer())
    state.terrain[50, 50] = .minedGrass
    grabTile(at: Pointi(x: 50, y: 50), state: &state)
    #expect(state.terrain[50, 50] == .crater)
}

// MARK: - drown / smallboom / superboom

// B.5d (D100/D103): `drown` now calls `dropPills` directly (the `onSpawn`-precedent fix) instead
// of firing a bare `(UInt16, Vec2f)` pass-through — `onShouldBroadcastDropPill` fires once per
// pill actually placed, with its real index, not the raw mask.
@Test func drownKillsAliveTankAndDropsOnboardPills() {
    var state = makeState(player: connectedPlayer(boat: true))
    state.pills = [Pill(x: 0, y: 0, armour: pillOnboard, owner: 0, speed: 0, counter: 0)]
    var broadcasts: [(Int, Int, Int)] = []
    drown(state: &state, onShouldBroadcastDropPill: { pill, x, y in broadcasts.append((pill, x, y)) })
    #expect(!state.players[0].boat)
    #expect(state.players[0].dead)
    #expect(state.local.deaths == 1)
    #expect(broadcasts.count == 1)
    #expect(broadcasts.first?.0 == 0)
    #expect(state.pills[0].armour == 0)
}

@Test func drownAlreadyDeadPastExplodeTicksIsNoOp() {
    var state = makeState(player: connectedPlayer(dead: true), local: LocalPlayerState(respawnCounter: explodeTicks + 5))
    drown(state: &state)
    #expect(state.local.deaths == 0)
    #expect(state.local.respawnCounter == explodeTicks + 5)
}

@Test func smallboomFiresMineExplosionAtOwnTile() {
    var state = makeState(player: connectedPlayer())
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    var exploded: Pointi?
    smallboom(state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == Pointi(x: 5, y: 5))
    #expect(state.players[0].dead)
}

@Test func superboomSpawnsNineExplosionsAndKillsDeaths() {
    var state = makeState(player: connectedPlayer())
    state.players[0].tank = Vec2f(x: 5.6, y: 5.6)  // frac >= 0.5, no down-shift
    var terrainHit: Pointi?
    superboom(state: &state, onSuperboomTerrain: { terrainHit = $0 })
    #expect(state.players[0].explosions.count == 9)
    #expect(terrainHit == Pointi(x: 5, y: 5))
    #expect(state.players[0].dead)
    #expect(state.local.deaths == 1)
}

@Test func superboomShiftsDownOnLowFraction() {
    var state = makeState(player: connectedPlayer())
    state.players[0].tank = Vec2f(x: 5.2, y: 5.2)  // frac < 0.5, shifts down/left
    var terrainHit: Pointi?
    superboom(state: &state, onSuperboomTerrain: { terrainHit = $0 })
    #expect(terrainHit == Pointi(x: 4, y: 4))
}

// Wave 5.9: smallboom now really detonates its own tile via explosionAt
// (deferred until after `dead` is set — see MineChain.swift's file header
// and docs/notes/WAVE59_REPORT.md §3), and must NOT apply a second,
// spurious splash-damage hit to the causer's own (already-dead) tank.
@Test func smallboomDetonatesOwnTileAndDoesNotDoubleDamageSelf() {
    var state = makeState(player: connectedPlayer(), local: LocalPlayerState(armour: 60))
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.terrain[50, 50] = .minedGrass
    smallboom(state: &state)
    #expect(state.terrain[50, 50] == .crater)
    #expect(state.local.armour == 60)
}

// Wave 5.9: same as above for superboom's 2x2 detonation.
@Test func superboomDetonatesTerrainAndDoesNotDoubleDamageSelf() {
    var state = makeState(player: connectedPlayer(), local: LocalPlayerState(armour: 60))
    state.players[0].tank = Vec2f(x: 50.6, y: 50.6)  // frac >= 0.5, origin stays (50, 50)
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 51] = .grass0
    state.terrain[51, 51] = .grass0
    superboom(state: &state)
    #expect(state.terrain[50, 50] == .crater)
    #expect(state.terrain[51, 50] == .crater)
    #expect(state.terrain[50, 51] == .crater)
    #expect(state.terrain[51, 51] == .crater)
    #expect(state.local.armour == 60)
}

// MARK: - killBuilder / killSquareBuilder / killPointBuilder

// B.5d (D100/D103): `killBuilder` now calls `dropPills` directly instead of firing a bare
// `(UInt16, Vec2f)` pass-through — `onShouldBroadcastDropPill` fires once, with the reserved
// pill's real index, not the raw mask.
@Test func killBuilderRespawnsAsParachuteAtAStart() {
    var player = connectedPlayer()
    player.builderStatus = .work
    player.builderPill = 2
    var state = makeState(player: player)
    state.starts = [Start(x: 10, y: 20, dir: 0)]
    state.pills = (0..<3).map { _ in Pill(x: 0, y: 0, armour: 0, owner: playerNeutral, speed: 0, counter: 0) }
    var broadcasts: [(Int, Int, Int)] = []
    killBuilder(player: 0, state: &state, onShouldBroadcastDropPill: { pill, x, y in broadcasts.append((pill, x, y)) })
    #expect(state.players[0].builderStatus == .parachute)
    #expect(state.players[0].builder == Vec2f(x: 10.5, y: 20.5))
    #expect(state.players[0].builderPill == noPill)
    #expect(broadcasts.count == 1)
    #expect(broadcasts.first?.0 == 2)
    #expect(state.pills[2].armour == 0)
}

@Test func killSquareBuilderIgnoresReadyAndParachuteStates() {
    var player = connectedPlayer()
    player.builderStatus = .ready
    player.builder = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(player: player)
    state.starts = [Start(x: 0, y: 0, dir: 0)]
    killSquareBuilder(at: Pointi(x: 5, y: 5), state: &state)
    #expect(state.players[0].builderStatus == .ready)
}

@Test func killSquareBuilderMatchesOnTileTruncation() {
    var player = connectedPlayer()
    player.builderStatus = .goto
    player.builder = Vec2f(x: 5.9, y: 5.9)
    var state = makeState(player: player)
    state.starts = [Start(x: 0, y: 0, dir: 0)]
    killSquareBuilder(at: Pointi(x: 5, y: 5), state: &state)
    #expect(state.players[0].builderStatus == .parachute)
}

@Test func killPointBuilderRequiresRadius() {
    var player = connectedPlayer()
    player.builderStatus = .wait
    player.builder = Vec2f(x: 5.0, y: 5.0)
    var state = makeState(player: player)
    state.starts = [Start(x: 0, y: 0, dir: 0)]
    killPointBuilder(at: Vec2f(x: 5.0 + explosionRadius + 0.1, y: 5.0), state: &state)
    #expect(state.players[0].builderStatus == .wait)
    killPointBuilder(at: Vec2f(x: 5.0 + explosionRadius - 0.1, y: 5.0), state: &state)
    #expect(state.players[0].builderStatus == .parachute)
}

// B.5e (D104/D105/D106): the real fix this sub-wave exists for — `killSquareBuilder`/
// `killPointBuilder` used to only ever check `state.localPlayer`'s own builder, even for an
// explosion caused by (and checked against) any player. A remote player's builder sitting on an
// exploding tile was never identified or killed at all before this fix.
@Test func killSquareBuilderKillsARemotePlayersBuilderNotJustLocalPlayers() {
    var localPlayer = connectedPlayer()
    localPlayer.builderStatus = .ready  // not on the exploding tile at all
    var remote = connectedPlayer()
    remote.builderStatus = .goto
    remote.builder = Vec2f(x: 5.5, y: 5.5)
    var state = GameState()
    state.players = [localPlayer, remote]
    state.localPlayer = 0
    state.starts = [Start(x: 0, y: 0, dir: 0)]

    killSquareBuilder(at: Pointi(x: 5, y: 5), state: &state)

    #expect(state.players[1].builderStatus == .parachute)
    #expect(state.players[0].builderStatus == .ready)  // untouched — was never on the tile
}

@Test func killPointBuilderKillsEveryConnectedPlayersBuilderWithinRadiusInOnePass() {
    var localPlayer = connectedPlayer()
    localPlayer.builderStatus = .wait
    localPlayer.builder = Vec2f(x: 5.0, y: 5.0)
    var remote = connectedPlayer()
    remote.builderStatus = .goto
    remote.builder = Vec2f(x: 5.2, y: 5.0)
    var state = GameState()
    state.players = [localPlayer, remote]
    state.localPlayer = 0
    state.starts = [Start(x: 0, y: 0, dir: 0)]

    killPointBuilder(at: Vec2f(x: 5.0, y: 5.0), state: &state)

    #expect(state.players[0].builderStatus == .parachute)
    #expect(state.players[1].builderStatus == .parachute)
}

// MARK: - tankLocalTick: collision push

@Test func tankLocalTickPushesOverlappingTanksApart() {
    var state = GameState()
    for x in 8...11 { state.terrain[x, 10] = .grass0 }
    var p0 = connectedPlayer()
    p0.tank = Vec2f(x: 10, y: 10)
    var p1 = connectedPlayer()
    p1.tank = Vec2f(x: 10.1, y: 10)
    state.players = [p0, p1]
    state.localPlayer = 0
    tankLocalTick(old: Pointi(x: 10, y: 10), state: &state)
    let diff = state.players[0].tank - state.players[1].tank
    #expect(mag2f(diff) >= tankRadius * 2.0 - 0.0001)
}

@Test func tankLocalTickOutOfBoundsOldIsNoOp() {
    var state = makeState(player: connectedPlayer())
    let before = state.local
    tankLocalTick(old: Pointi(x: -1, y: 0), state: &state)
    #expect(state.local.shellCounter == before.shellCounter)
}

@Test func tankLocalTickDisconnectedIsNoOp() {
    var player = connectedPlayer()
    player.connected = false
    var state = makeState(player: player)
    tankLocalTick(old: Pointi(x: 5, y: 5), state: &state)
    #expect(state.local.shellCounter == 0)
}

// MARK: - tankLocalTick: drain

@Test func tankLocalTickDrainsResourcesOnSlowRiver() {
    var player = connectedPlayer()
    player.speed = 0.1
    player.tank = Vec2f(x: 5.5, y: 5.5)
    player.mines = 10
    var state = makeState(player: player, local: LocalPlayerState(shells: 10, drainCounter: drainTicks - 1))
    state.terrain[5, 5] = .river
    tankLocalTick(old: Pointi(x: 5, y: 5), state: &state)
    #expect(state.local.drainCounter == 0)
    #expect(state.local.shells == 9)
    #expect(state.players[0].mines == 9)
}

@Test func tankLocalTickDrainResetsWhenFast() {
    var player = connectedPlayer()
    player.speed = rubbleMaxSpeed + 1.0
    player.tank = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(player: player, local: LocalPlayerState(drainCounter: 5))
    state.terrain[5, 5] = .river
    tankLocalTick(old: Pointi(x: 5, y: 5), state: &state)
    #expect(state.local.drainCounter == 0)
}

// MARK: - tankLocalTick: refuel

@Test func tankLocalTickStartsRefuelingOnEnteringBase() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(player: player)
    // Wave 5.9: (5,5) is outside the mine zone [10,245], so mapDefault()'s
    // border ring makes it mined-sea by default — grabTile's mine-detonation
    // branch is now wired for real, so an unrealistic base-on-mined-terrain
    // fixture would spuriously kill a zero-resource tank here. Set it to
    // ordinary land, matching how a base would actually be surrounded.
    state.terrain[5, 5] = .grass0
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 0, shells: 50, mines: 50)]
    tankLocalTick(old: Pointi(x: 4, y: 5), state: &state)
    #expect(state.local.refueling)
    #expect(state.local.refuelingBase == 0)
}

@Test func tankLocalTickRefuelsArmourAfterThreshold() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(
        player: player,
        local: LocalPlayerState(
            armour: 0, refueling: true, refuelingBase: 0, refuelingCounter: refuelArmourTicks - 1
        )
    )
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 0, shells: 50, mines: 50)]
    tankLocalTick(old: Pointi(x: 5, y: 5), state: &state)
    #expect(state.local.armour > 0)
    #expect(state.local.refuelingCounter == 0)
}

@Test func tankLocalTickRefuelFallsThroughToShellsWhenArmourFull() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 5.5, y: 5.5)
    var state = makeState(
        player: player,
        local: LocalPlayerState(
            armour: maxArmour, shells: 0, refueling: true, refuelingBase: 0,
            refuelingCounter: refuelShellsTicks - 1
        )
    )
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 0, shells: 50, mines: 50)]
    tankLocalTick(old: Pointi(x: 5, y: 5), state: &state)
    #expect(state.local.shells == minBaseShells)
    #expect(state.bases[0].shells == 50 - UInt8(minBaseShells))
}

@Test func tankLocalTickRefuelStopsWhenTankMoves() {
    var player = connectedPlayer()
    player.tank = Vec2f(x: 51.5, y: 50.5)
    var state = makeState(
        player: player, local: LocalPlayerState(refueling: true, refuelingBase: 0, refuelingCounter: 10)
    )
    state.terrain[50, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 0, shells: 50, mines: 50)]
    tankLocalTick(old: Pointi(x: 50, y: 50), state: &state)
    #expect(!state.local.refueling)
    #expect(state.local.refuelingBase == -1)
}

// MARK: - tankLocalTick: range and shell fire

// These five tests don't care about terrain, but the default (0,0) tank
// position falls in TerrainGrid.mapDefault()'s mined-sea border ring, which
// would drown the player inside enterTile before the assertions run. Parking
// on an explicit grass tile, stationary (new == old), sidesteps that.
private func safeStationaryState(player: PlayerState, local: LocalPlayerState) -> (GameState, Pointi) {
    var state = makeState(player: player, local: local)
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.terrain[50, 50] = .grass0
    return (state, Pointi(x: 50, y: 50))
}

@Test func tankLocalTickIncreasesRangeClampedToMax() {
    var player = connectedPlayer()
    player.inputFlags = [.incre]
    var (state, old) = safeStationaryState(player: player, local: LocalPlayerState(range: maxShellRange - 0.001))
    tankLocalTick(old: old, state: &state)
    #expect(state.local.range == maxShellRange)
}

@Test func tankLocalTickDecreasesRangeClampedToMin() {
    var player = connectedPlayer()
    player.inputFlags = [.decre]
    var (state, old) = safeStationaryState(player: player, local: LocalPlayerState(range: minRange + 0.001))
    tankLocalTick(old: old, state: &state)
    #expect(state.local.range == minRange)
}

@Test func tankLocalTickFiresShellAboveThreshold() {
    var player = connectedPlayer()
    player.inputFlags = [.shoot]
    player.dir = 0
    var (state, old) = safeStationaryState(
        player: player, local: LocalPlayerState(shells: 5, shellCounter: shellFireThresholdTicks + 1)
    )
    tankLocalTick(old: old, state: &state)
    #expect(state.players[0].shells.count == 1)
    #expect(state.local.shells == 4)
    #expect(state.local.shellCounter == 1)  // reset to 0, then unconditional +1
}

@Test func tankLocalTickDoesNotFireBelowThreshold() {
    var player = connectedPlayer()
    player.inputFlags = [.shoot]
    var (state, old) = safeStationaryState(
        player: player, local: LocalPlayerState(shells: 5, shellCounter: shellFireThresholdTicks)
    )
    tankLocalTick(old: old, state: &state)
    #expect(state.players[0].shells.isEmpty)
    #expect(state.local.shellCounter == shellFireThresholdTicks + 1)
}

@Test func tankLocalTickDoesNotFireWithoutShells() {
    var player = connectedPlayer()
    player.inputFlags = [.shoot]
    var (state, old) = safeStationaryState(
        player: player, local: LocalPlayerState(shells: 0, shellCounter: shellFireThresholdTicks + 1)
    )
    tankLocalTick(old: old, state: &state)
    #expect(state.players[0].shells.isEmpty)
}

@Test func tankLocalTickShellCounterIncrementsUnconditionally() {
    var (state, old) = safeStationaryState(player: connectedPlayer(), local: LocalPlayerState(shellCounter: 3))
    tankLocalTick(old: old, state: &state)
    #expect(state.local.shellCounter == 4)
}

@Test func tankLocalTickFiresOnTankShotCallbackWhenShellFires() {
    var player = connectedPlayer()
    player.inputFlags = [.shoot]
    player.dir = 0
    var (state, old) = safeStationaryState(
        player: player, local: LocalPlayerState(shells: 5, shellCounter: shellFireThresholdTicks + 1)
    )
    var fired = 0
    tankLocalTick(old: old, state: &state, onTankShot: { fired += 1 })
    #expect(state.players[0].shells.count == 1)
    #expect(fired == 1)
}

@Test func tankLocalTickDoesNotFireOnTankShotCallbackBelowThreshold() {
    var player = connectedPlayer()
    player.inputFlags = [.shoot]
    var (state, old) = safeStationaryState(
        player: player, local: LocalPlayerState(shells: 5, shellCounter: shellFireThresholdTicks)
    )
    var fired = 0
    tankLocalTick(old: old, state: &state, onTankShot: { fired += 1 })
    #expect(state.players[0].shells.isEmpty)
    #expect(fired == 0)
}

@Test func tankLocalTickDeadPlayerSkipsDrainRefuelFire() {
    var player = connectedPlayer(dead: true)
    player.inputFlags = [.shoot]
    var state = makeState(player: player, local: LocalPlayerState(shells: 5, shellCounter: 100))
    tankLocalTick(old: Pointi(x: 0, y: 0), state: &state)
    #expect(state.players[0].shells.isEmpty)
    #expect(state.local.shellCounter == 100)
}

// MARK: - detectJoinTileEntry / detectJoinLMineKeyDown (B.10, D127)
//
// These test the READ-ONLY detection function only: given a `GameState` and a
// tile transition, does it return the right message(s) without mutating
// `state`? Negative controls (asserting `state` is byte-for-byte unmutated)
// double as the read-only-ness proof the pre-brief called for.

@Test func detectJoinTileEntryUnownedPillReturnsGrabTile() {
    var state = makeState(player: connectedPlayer())
    state.pills = [Pill(x: 5, y: 5, armour: 0, owner: playerNeutral, speed: 0, counter: 0)]
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: state)
    #expect(result == [.grabTile(x: 5, y: 5)])
    // Read-only: the pill itself must be untouched (mutation is the host's SR* job).
    #expect(state.pills[0].owner == playerNeutral)
}

@Test func detectJoinTileEntryArmedPillReturnsNothing() {
    // Negative control: armed pills are `superboom()`'s branch (out of B.10 scope) — if the
    // armour gate were missing/wrong, this would wrongly return `.grabTile`.
    var state = makeState(player: connectedPlayer())
    state.pills = [Pill(x: 5, y: 5, armour: 10, owner: playerNeutral, speed: 50, counter: 0)]
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: state)
    #expect(result.isEmpty)
}

@Test func detectJoinTileEntryHostileBaseReturnsGrabTile() {
    var state = makeState(player: connectedPlayer())
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 1, shells: 50, mines: 50)]
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: state)
    #expect(result == [.grabTile(x: 5, y: 5)])
    // Read-only: base ownership/resources must be untouched.
    #expect(state.bases[0].owner == 1)
    #expect(state.bases[0].armour == 50)
}

@Test func detectJoinTileEntryAlliedBaseReturnsNothing() {
    var state = makeState(player: connectedPlayer())
    state.players.append(connectedPlayer())
    state.players[0].used = true
    state.players[1].used = true
    state.players[0].alliance = 1 << 1
    state.players[1].alliance = 1 << 0
    state.bases = [Base(x: 5, y: 5, armour: 50, owner: 1, shells: 50, mines: 50)]
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: state)
    #expect(result.isEmpty)
}

@Test func detectJoinTileEntryPillEntryWithBoatAlsoReturnsDropBoat() {
    var state = makeState(player: connectedPlayer(boat: true))
    state.pills = [Pill(x: 5, y: 5, armour: 0, owner: playerNeutral, speed: 0, counter: 0)]
    state.terrain[5, 5] = .grass0
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: state)
    #expect(result == [.grabTile(x: 5, y: 5), .dropBoat(x: 4, y: 5)])
    // Read-only: `boat` flag itself must be untouched (only `enterTile`'s real mutation clears it).
    #expect(state.players[0].boat)
}

@Test func detectJoinTileEntryGrassExitWithBoatReturnsDropBoatOnly() {
    var state = makeState(player: connectedPlayer(boat: true))
    state.terrain[5, 5] = .grass0
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: state)
    #expect(result == [.dropBoat(x: 4, y: 5)])
}

@Test func detectJoinTileEntryMinePlantOnMovedGrassWithLmineFlag() {
    var player = connectedPlayer()
    player.inputFlags = [.lmine]
    player.mines = 5
    var state = makeState(player: player)
    state.terrain[5, 5] = .grass0
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 4, y: 5), state: state)
    #expect(result == [.dropMine(x: 5, y: 5)])
    // Read-only: terrain and mine count must be untouched.
    #expect(state.terrain[5, 5] == .grass0)
    #expect(state.players[0].mines == 5)
}

@Test func detectJoinTileEntryMinePlantSkippedWhenStationary() {
    // Negative control: `enter()` gates the mine-plant branch on `new != old` — without that
    // guard this would wrongly fire every tick while the LMINE flag is held stationary.
    var player = connectedPlayer()
    player.inputFlags = [.lmine]
    player.mines = 5
    var state = makeState(player: player)
    state.terrain[5, 5] = .grass0
    let result = detectJoinTileEntry(new: Pointi(x: 5, y: 5), old: Pointi(x: 5, y: 5), state: state)
    #expect(result.isEmpty)
}

@Test func detectJoinLMineKeyDownReturnsDropMineOnMinableTerrain() {
    var state = makeState(player: connectedPlayer())
    state.players[0].mines = 5
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = .grass0
    let result = detectJoinLMineKeyDown(state: state)
    #expect(result == .dropMine(x: 5, y: 5))
    // Read-only: terrain/mine count untouched (unlike `layMineOnKeyDown`, which spends a mine).
    #expect(state.terrain[5, 5] == .grass0)
    #expect(state.players[0].mines == 5)
}

@Test func detectJoinLMineKeyDownNoopsOnAPillTile() {
    // Negative control: matches `layMineOnKeyDown`'s own pill guard.
    var state = makeState(player: connectedPlayer())
    state.players[0].mines = 5
    state.players[0].tank = Vec2f(x: 5.5, y: 5.5)
    state.terrain[5, 5] = .grass0
    state.pills = [Pill(x: 5, y: 5, armour: 10, owner: playerNeutral, speed: 50, counter: 0)]
    let result = detectJoinLMineKeyDown(state: state)
    #expect(result == nil)
}
