import Testing
import BoloKit

private func connectedPlayer(alliance: UInt16 = 0) -> PlayerState {
    var p = PlayerState()
    p.used = true
    p.connected = true
    p.alliance = alliance
    return p
}

private func makeState(players: [PlayerState] = [PlayerState()]) -> GameState {
    var state = GameState()
    state.players = players
    state.terrain[50, 50] = .grass0
    return state
}

// MARK: - Boats and mines

@Test func recvClDropBoatConvertsRiverToBoatInsideSeaRectOnly() {
    var state = makeState()
    state.terrain[50, 50] = .river
    var broadcast: (Int, Int)?
    recvClDropBoat(x: 50, y: 50, state: &state, onShouldBroadcastDropBoat: { broadcast = ($0, $1) })
    #expect(state.terrain[50, 50] == .boat)
    #expect(broadcast?.0 == 50 && broadcast?.1 == 50)
}

@Test func recvClDropBoatOutsideSeaRectIsNoOp() {
    var state = makeState()
    state.terrain[5, 5] = .river
    recvClDropBoat(x: 5, y: 5, state: &state)
    #expect(state.terrain[5, 5] == .river)  // untouched: outside the [10,245] interior
}

@Test func recvClDropBoatOnNonRiverIsNoOp() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    recvClDropBoat(x: 50, y: 50, state: &state)
    #expect(state.terrain[50, 50] == .grass0)
}

@Test func recvClDropPillsRejectsRequestOwningAnyNonOwnedOrOffboardPill() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    state.pills = [
        Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0),
        Pill(x: 5, y: 5, armour: pillOnboard, owner: 1, speed: 10, counter: 0),  // not player 0's
    ]
    recvClDropPills(player: 0, x: 50.5, y: 50.5, pills: 0b11, state: &state)
    #expect(state.pills[0].armour == pillOnboard)  // whole request rejected, nothing dropped
    #expect(state.pills[1].armour == pillOnboard)
}

@Test func recvClDropPillsAcceptsValidOnboardOwnedRequest() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]
    recvClDropPills(player: 0, x: 50.5, y: 50.5, pills: 0b1, state: &state)
    #expect(state.pills[0].armour != pillOnboard)  // dropped
}

@Test func recvClDropPillsRejectsOutOfRangeCoordinates() {
    var state = makeState()
    state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]
    recvClDropPills(player: 0, x: 0, y: 50, pills: 0b1, state: &state)
    #expect(state.pills[0].armour == pillOnboard)  // x == 0 fails the strict `x > 0.0` check
}

@Test func recvClDropMineTerrainProgressionAndAcks() {
    let cases: [(Terrain, Terrain)] = [
        (.swamp0, .minedSwamp), (.crater, .minedCrater), (.road, .minedRoad),
        (.forest, .minedForest), (.rubble0, .minedRubble), (.grass0, .minedGrass),
    ]
    for (from, to) in cases {
        var state = makeState()
        state.terrain[50, 50] = from
        var acked: Bool?
        recvClDropMine(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastMineAck: { _, success in acked = success })
        #expect(state.terrain[50, 50] == to, "\(from) -> \(to)")
        #expect(acked == true)
    }
}

@Test func recvClDropMineOnUnmineableTerrainAcksFailure() {
    var state = makeState()
    state.terrain[50, 50] = .wall
    var acked: Bool?
    recvClDropMine(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastMineAck: { _, success in acked = success })
    #expect(state.terrain[50, 50] == .wall)
    #expect(acked == false)
}

// MARK: - Touch / grab

@Test func recvClTouchDetonatesMinedTerrainWithNeutralAttribution() {
    var state = makeState()
    state.terrain[50, 50] = .minedGrass
    var broadcast: (UInt8, Int, Int)?
    recvClTouch(player: 3, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { broadcast = ($0, $1, $2) })
    #expect(state.terrain[50, 50] == .crater)
    #expect(broadcast?.0 == playerNeutral)
}

@Test func recvClTouchOnNonMinedTerrainIsNoOp() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    var fired = false
    recvClTouch(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { _, _, _ in fired = true })
    #expect(state.terrain[50, 50] == .grass0)
    #expect(!fired)
}

@Test func recvClGrabTileCapturesOnboardsAndAcksPill() {
    var state = makeState()
    state.pills = [Pill(x: 50, y: 50, armour: 3, owner: playerNeutral, speed: 20, counter: 0)]
    var acked: Int?
    recvClGrabTile(player: 2, x: 50, y: 50, state: &state, onShouldBroadcastCapturePill: { acked = $0 })
    #expect(state.pills[0].owner == 2)
    #expect(state.pills[0].armour == pillOnboard)
    #expect(state.pills[0].speed == UInt8(maxTicksPerShot))
    #expect(acked == 0)
}

@Test func recvClGrabTileNeutralBaseIsCapturedWithFullResources() {
    var state = makeState()
    state.bases = [Base(x: 50, y: 50, armour: 0, owner: playerNeutral, shells: 0, mines: 0)]
    recvClGrabTile(player: 2, x: 50, y: 50, state: &state)
    #expect(state.bases[0].owner == 2)
    #expect(state.bases[0].armour == UInt8(maxBaseArmour))
    #expect(state.bases[0].shells == UInt8(maxBaseShells))
    #expect(state.bases[0].mines == UInt8(maxBaseMines))
}

@Test func recvClGrabTileMutuallyAlliedBaseHandsOffResourcesUntouched() {
    let players = [connectedPlayer(alliance: 1 << 2), connectedPlayer(), connectedPlayer(alliance: 1 << 0)]
    var state = makeState(players: players)
    state.bases = [Base(x: 50, y: 50, armour: 40, owner: 2, shells: 30, mines: 20)]
    recvClGrabTile(player: 0, x: 50, y: 50, state: &state)
    #expect(state.bases[0].owner == 0)
    #expect(state.bases[0].armour == 40)  // untouched, unlike the hostile-takeover branch
    #expect(state.bases[0].shells == 30)
    #expect(state.bases[0].mines == 20)
}

@Test func recvClGrabTileHostileBaseIsZeroedOnTakeover() {
    let players = [connectedPlayer(), connectedPlayer()]  // no alliance either direction
    var state = makeState(players: players)
    state.bases = [Base(x: 50, y: 50, armour: 40, owner: 1, shells: 30, mines: 20)]
    recvClGrabTile(player: 0, x: 50, y: 50, state: &state)
    #expect(state.bases[0].owner == 0)
    #expect(state.bases[0].armour == 0)
    #expect(state.bases[0].shells == 0)
    #expect(state.bases[0].mines == 0)
}

@Test func recvClGrabTileBoatTerrainBecomesRiver() {
    var state = makeState()
    state.terrain[50, 50] = .boat
    var broadcast: (Int, Int, Int)?
    recvClGrabTile(player: 1, x: 50, y: 50, state: &state, onShouldBroadcastGrabBoat: { broadcast = ($0, $1, $2) })
    #expect(state.terrain[50, 50] == .river)
    #expect(broadcast?.0 == 1)
}

@Test func recvClGrabTileMinedTerrainDetonates() {
    var state = makeState()
    state.terrain[50, 50] = .minedRoad
    var fired = false
    recvClGrabTile(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { _, _, _ in fired = true })
    #expect(state.terrain[50, 50] == .crater)
    #expect(fired)
}

@Test func recvClGrabTreesForestBecomesGrassAndAcksForestTreeYield() {
    var state = makeState()
    state.terrain[50, 50] = .forest
    var ack: (Int, Int, Int, Int)?
    recvClGrabTrees(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastBuilderAck: { p, m, t, pl in ack = (p, m, t, pl) })
    #expect(state.terrain[50, 50] == .grass3)
    #expect(ack?.2 == forestTreeYield)
}

@Test func recvClGrabTreesMinedForestIsHarvestedNotDetonated() {
    var state = makeState()
    state.terrain[50, 50] = .minedForest
    var detonated = false
    recvClGrabTrees(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { _, _, _ in detonated = true })
    #expect(state.terrain[50, 50] == .minedGrass)
    #expect(!detonated)
}

@Test func recvClGrabTreesOtherMinedTerrainDetonates() {
    var state = makeState()
    state.terrain[50, 50] = .minedGrass
    var detonated = false
    recvClGrabTrees(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { _, _, _ in detonated = true })
    #expect(state.terrain[50, 50] == .crater)
    #expect(detonated)
}

// MARK: - Construction

/// D40: the tautology bug is replicated bug-for-bug -- road building
/// always succeeds regardless of `trees`, including with `trees == 0`.
@Test func recvClBuildRoadAlwaysSucceedsRegardlessOfTreeCountD40() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    var built = false
    recvClBuildRoad(player: 0, x: 50, y: 50, trees: 0, state: &state, onShouldBroadcastBuild: { _, _ in built = true })
    #expect(state.terrain[50, 50] == .road)
    #expect(built)
}

/// D40's second-order effect: the leftover-trees ack can go negative when
/// `trees < roadTrees`, since the (always-true) success branch is the
/// only reachable one.
@Test func recvClBuildRoadLeftoverTreesCanGoNegativeD40() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    var leftover: Int?
    recvClBuildRoad(player: 0, x: 50, y: 50, trees: 0, state: &state, onShouldBroadcastBuilderAck: { _, _, t, _ in leftover = t })
    #expect(leftover == -roadTrees)
}

@Test func recvClBuildRoadOnMinedTerrainDetonatesInsteadOfBuilding() {
    var state = makeState()
    state.terrain[50, 50] = .minedGrass
    var detonated = false
    recvClBuildRoad(player: 0, x: 50, y: 50, trees: 5, state: &state, onShouldBroadcastSmallBoom: { _, _, _ in detonated = true })
    #expect(state.terrain[50, 50] == .crater)
    #expect(detonated)
}

@Test func recvClBuildWallRequiresRealThreshold() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    var built = false
    recvClBuildWall(player: 0, x: 50, y: 50, trees: wallTrees - 1, state: &state, onShouldBroadcastBuild: { _, _ in built = true })
    #expect(state.terrain[50, 50] == .grass0)  // insufficient trees: real gate, unlike buildroad
    #expect(!built)

    recvClBuildWall(player: 0, x: 50, y: 50, trees: wallTrees, state: &state, onShouldBroadcastBuild: { _, _ in built = true })
    #expect(state.terrain[50, 50] == .wall)
    #expect(built)
}

@Test func recvClBuildBoatHasNoThresholdGateAtAll() {
    var state = makeState()
    state.terrain[50, 50] = .river
    var built = false
    recvClBuildBoat(player: 0, x: 50, y: 50, trees: 0, state: &state, onShouldBroadcastBuild: { _, _ in built = true })
    #expect(state.terrain[50, 50] == .boat)
    #expect(built)
}

@Test func recvClBuildPillPlacesIntoGivenSlotAndCapsArmour() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    state.pills = [Pill(x: 0, y: 0, armour: 0, owner: playerNeutral, speed: 0, counter: 0)]
    var built: Int?
    var leftover: Int?
    recvClBuildPill(
        player: 1, x: 50, y: 50, trees: 10, pill: 0, state: &state,
        onShouldBroadcastBuildPill: { built = $0 },
        onShouldBroadcastBuilderAck: { _, _, t, _ in leftover = t }
    )
    #expect(state.pills[0].x == 50 && state.pills[0].y == 50)
    #expect(state.pills[0].owner == 1)
    #expect(state.pills[0].armour == UInt8(maxPillArmour))  // 10*4=40, capped at 15
    #expect(built == 0)
    #expect(leftover == (10 * pillTrees - maxPillArmour) / pillTrees)
}

@Test func recvClBuildPillOutOfRangeSlotIsIgnoredNotTrapped() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    state.pills = []
    recvClBuildPill(player: 0, x: 50, y: 50, trees: 10, pill: 5, state: &state)
    #expect(state.pills.isEmpty)  // guarded, no crash, no mutation
}

@Test func recvClBuildPillRefusesOccupiedSquare() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    state.pills = [Pill(x: 50, y: 50, armour: 5, owner: 0, speed: 10, counter: 0)]
    var ackedTrees: Int?
    recvClBuildPill(player: 1, x: 50, y: 50, trees: 10, pill: 0, state: &state, onShouldBroadcastBuilderAck: { _, _, t, _ in ackedTrees = t })
    #expect(ackedTrees == 10)  // rejected, trees refunded verbatim
}

@Test func recvClRepairPillAddsArmourAndCapsWithLeftoverTrees() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: 0, speed: 10, counter: 0)]
    var leftover: Int?
    recvClRepairPill(player: 0, x: 50, y: 50, trees: 3, state: &state, onShouldBroadcastBuilderAck: { _, _, t, _ in leftover = t })
    #expect(state.pills[0].armour == UInt8(maxPillArmour))  // 10 + 3*4=22, capped at 15
    #expect(leftover == (10 + 3 * pillTrees - maxPillArmour) / pillTrees)
}

@Test func recvClPlaceMineCostsNoTreesAndAlwaysAcksZero() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    var ack: (Int, Int, Int, Int)?
    recvClPlaceMine(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastBuilderAck: { p, m, t, pl in ack = (p, m, t, pl) })
    #expect(state.terrain[50, 50] == .minedGrass)
    #expect(ack?.2 == 0)
}

@Test func recvClPlaceMineOnMinedTerrainDetonatesInsteadOfDoubleMinng() {
    var state = makeState()
    state.terrain[50, 50] = .minedGrass
    var detonated = false
    recvClPlaceMine(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { _, _, _ in detonated = true })
    #expect(state.terrain[50, 50] == .crater)
    #expect(detonated)
}

// MARK: - Damage / combat

@Test func recvClDamagePillDirectHitFiresBroadcastRegardlessOfArmour() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    state.pills = [Pill(x: 50, y: 50, armour: 3, owner: playerNeutral, speed: 20, counter: 0)]
    var broadcast: (Int, Int, Int)?
    recvClDamage(player: 0, x: 50, y: 50, boat: false, state: &state, onShouldBroadcastDamage: { p, x, y in broadcast = (p, x, y) })
    #expect(state.pills[0].armour == 2)
    #expect(broadcast != nil)
}

@Test func recvClDamageNonBoatOnUnmatchedTerrainFiresNoBroadcast() {
    var state = makeState()
    state.terrain[50, 50] = .grass0  // grass has no non-boat progression case
    var fired = false
    recvClDamage(player: 0, x: 50, y: 50, boat: false, state: &state, onShouldBroadcastDamage: { _, _, _ in fired = true })
    #expect(state.terrain[50, 50] == .grass0)
    #expect(!fired)
}

@Test func recvClDamageBoatOnGrassFiresBroadcastUnlikeNonBoat() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    var fired = false
    recvClDamage(player: 0, x: 50, y: 50, boat: true, state: &state, onShouldBroadcastDamage: { _, _, _ in fired = true })
    #expect(state.terrain[50, 50] == .swamp3)
    #expect(fired)
}

@Test func recvClDamageMinedTerrainDetonatesWithNeutralAttributionNotDamage() {
    var state = makeState()
    state.terrain[50, 50] = .minedGrass
    var damageFired = false
    var smallBoomFired = false
    recvClDamage(
        player: 2, x: 50, y: 50, boat: false, state: &state,
        onShouldBroadcastDamage: { _, _, _ in damageFired = true },
        onShouldBroadcastSmallBoom: { _, _, _ in smallBoomFired = true }
    )
    #expect(state.terrain[50, 50] == .crater)
    #expect(!damageFired)
    #expect(smallBoomFired)
}

@Test func recvClSmallBoomDetonatesAndBroadcastsAsNeutral() {
    var state = makeState()
    state.terrain[50, 50] = .grass0
    var broadcast: (UInt8, Int, Int)?
    recvClSmallBoom(player: 3, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { broadcast = ($0, $1, $2) })
    #expect(state.terrain[50, 50] == .crater)
    #expect(broadcast?.0 == playerNeutral)
}

@Test func recvClSmallBoomOnSeaFiresNoBroadcast() {
    // `.sea` is the one terrain value excluded from explosionAt's own
    // detonation case list (matches server.c:4121-4171's switch having no
    // `kSeaTerrain` case at all) -- proves `detonated` tracks the real
    // predicate rather than firing unconditionally.
    var state = makeState()
    state.terrain[50, 50] = .sea
    var fired = false
    recvClSmallBoom(player: 0, x: 50, y: 50, state: &state, onShouldBroadcastSmallBoom: { _, _, _ in fired = true })
    #expect(state.terrain[50, 50] == .sea)
    #expect(!fired)
}

@Test func recvClSuperBoomAlwaysBroadcastsWithRealCauser() {
    var state = makeState()
    state.terrain[50, 50] = .sea  // explicitly excluded from conversion, but the broadcast still fires
    state.terrain[51, 50] = .sea
    state.terrain[50, 51] = .sea
    state.terrain[51, 51] = .sea
    var broadcast: (Int, Int, Int)?
    recvClSuperBoom(player: 4, x: 50, y: 50, state: &state, onShouldBroadcastSuperBoom: { broadcast = ($0, $1, $2) })
    #expect(state.terrain[50, 50] == .sea)  // untouched: sea is excluded from conversion
    #expect(broadcast?.0 == 4)  // real causer, not playerNeutral -- asymmetric with smallboom
}

@Test func recvClRefuelSubtractsUnclampedMatchingClientMirror() {
    var state = makeState()
    state.bases = [Base(x: 5, y: 5, armour: 40, owner: 0, shells: 40, mines: 40)]
    var broadcast: (Int, Int, UInt8, UInt8, UInt8)?
    recvClRefuel(player: 0, base: 0, armour: 10, shells: 5, mines: 3, state: &state, onShouldBroadcastRefuel: { p, b, a, s, m in broadcast = (p, b, a, s, m) })
    #expect(state.bases[0].armour == 30)
    #expect(state.bases[0].shells == 35)
    #expect(state.bases[0].mines == 37)
    #expect(broadcast != nil)
}

@Test func recvClRefuelOutOfRangeBaseIsIgnored() {
    var state = makeState()
    state.bases = []
    var fired = false
    recvClRefuel(player: 0, base: 0, armour: 1, shells: 0, mines: 0, state: &state, onShouldBroadcastRefuel: { _, _, _, _, _ in fired = true })
    #expect(!fired)
}

@Test func recvClHitTankRelaysValidPlayerOnly() {
    var relayed: (Int, Float)?
    recvClHitTank(player: 2, dir: 1.5, onShouldBroadcastHitTank: { p, d in relayed = (p, d) })
    #expect(relayed?.0 == 2)

    relayed = nil
    recvClHitTank(player: maxPlayers, dir: 1.5, onShouldBroadcastHitTank: { p, d in relayed = (p, d) })
    #expect(relayed == nil)
}
