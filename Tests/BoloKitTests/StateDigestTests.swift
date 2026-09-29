import Testing
import BoloKit

// v1.6.9 baseline benchmark: the digests are the unit of comparison between host and guest, so
// each must change when (and only when) a field both sides are meant to agree on changes.

private func sampleState() -> GameState {
    var state = GameState(
        pills: [Pill(x: 108, y: 123, armour: 15, owner: playerNeutral, speed: 50, counter: 0)],
        bases: [Base(x: 100, y: 120, armour: 90, owner: playerNeutral, shells: 40, mines: 20)],
        players: Array(repeating: PlayerState(), count: maxPlayers),
        localPlayer: 1
    )
    state.players[0] = PlayerState(tank: Vec2f(x: 90.5, y: 80.5), dead: false, connected: true, used: true)
    state.players[1] = PlayerState(
        tank: Vec2f(x: 102.5, y: 121.5), mines: 4, trees: 8, dead: false, connected: true, used: true
    )
    state.localStats[1].armour = 40
    state.localStats[1].shells = 30
    return state
}

private func changes(_ tracker: inout StateDigestTracker, _ state: GameState) -> [DigestChange] {
    var out: [DigestChange] = []
    tracker.sampleSmallDomains(state, into: &out)
    return out
}

@Test func firstSampleReportsEveryElementAndAnUnchangedStateReportsNone() {
    let state = sampleState()
    var tracker = StateDigestTracker(player: 1)
    let first = changes(&tracker, state)
    #expect(first.filter { $0.domain == .pills }.count == 1)
    #expect(first.filter { $0.domain == .bases }.count == 1)
    #expect(first.filter { $0.domain == .selfStatus }.count == 1)
    #expect(first.filter { $0.domain == .resources }.count == DigestResource.allCases.count)
    #expect(first.filter { $0.domain == .peers }.count == maxPlayers)
    #expect(changes(&tracker, state).isEmpty)
}

@Test func pillArmourAloneChangesThePillDigest() {
    var state = sampleState()
    var tracker = StateDigestTracker(player: 1)
    _ = changes(&tracker, state)
    state.pills[0].armour = 14
    let out = changes(&tracker, state)
    #expect(out == [DigestChange(domain: .pills, element: 0, value: digestValue(state.pills[0]))])
}

@Test func perProcessPillAndBaseCountersAreNotCompared() {
    var state = sampleState()
    var tracker = StateDigestTracker(player: 1)
    _ = changes(&tracker, state)
    state.pills[0].speed = 6
    state.pills[0].counter = 9
    state.pills[0].coolCounter = 3
    state.bases[0].counter = 300
    #expect(changes(&tracker, state).isEmpty)
}

@Test func eachResourceIsItsOwnElement() {
    var state = sampleState()
    var tracker = StateDigestTracker(player: 1)
    _ = changes(&tracker, state)
    state.players[1].mines = 3
    #expect(
        changes(&tracker, state)
            == [DigestChange(domain: .resources, element: UInt32(DigestResource.mines.rawValue), value: 3)]
    )
    state.localStats[1].armour = 35
    #expect(
        changes(&tracker, state)
            == [DigestChange(domain: .resources, element: UInt32(DigestResource.armour.rawValue), value: 35)]
    )
}

@Test func movingWithinATileDoesNotChangeOwnStatusButCrossingOneDoes() {
    var state = sampleState()
    var tracker = StateDigestTracker(player: 1)
    _ = changes(&tracker, state)
    state.players[1].tank.x = 102.9
    #expect(changes(&tracker, state).isEmpty)
    state.players[1].tank.x = 103.1
    #expect(changes(&tracker, state).map(\.domain) == [.selfStatus])
}

@Test func aCarriedPillShowsInItsCarriersOwnStatus() {
    var state = sampleState()
    #expect(digestOnboardPillMask(player: 1, pills: state.pills) == 0)
    state.pills[0].armour = pillOnboard
    state.pills[0].owner = 1
    #expect(digestOnboardPillMask(player: 1, pills: state.pills) == 1)
    #expect(digestOnboardPillMask(player: 0, pills: state.pills) == 0)
}

@Test func ownSlotIsBlankedInThePeersDomain() {
    var state = sampleState()
    var tracker = StateDigestTracker(player: 1)
    _ = changes(&tracker, state)
    state.players[1].dead = true
    #expect(!changes(&tracker, state).contains { $0.domain == .peers })
    state.players[0].dead = true
    #expect(changes(&tracker, state).contains { $0.domain == .peers && $0.element == 0 })
}

@Test func directionWrapsIntoSixteenths() {
    #expect(digestSixteenth(0) == 0)
    #expect(digestSixteenth(kPif) == 8)
    #expect(digestSixteenth(2 * kPif) == 0)
    #expect(digestSixteenth(-kPif / 8) == 15)
    #expect(digestSixteenth(.nan) == 0)
}

@Test func terrainSamplingReportsOnlyTheChangedTile() {
    var terrain = TerrainGrid.mapDefault()
    var tracker = StateDigestTracker(player: 1)
    var out: [DigestChange] = []
    tracker.sampleTerrain(view: digestTerrainView(terrain), into: &out)
    #expect(out.count == 256 * 256)
    let before = tracker.hash(of: .terrain)

    out.removeAll()
    let index = 121 * 256 + 102
    terrain.storage[index] = Terrain.road.rawValue
    tracker.sampleTerrain(view: digestTerrainView(terrain), into: &out)
    #expect(
        out == [DigestChange(domain: .terrain, element: UInt32(index), value: UInt64(Terrain.road.rawValue))]
    )
    #expect(tracker.hash(of: .terrain) != before)
}

@Test func fogSamplingSeparatesVisibleFromSeen() {
    var fog = FogState()
    var tracker = StateDigestTracker(player: 1)
    var out: [DigestChange] = []
    tracker.sampleFog(fog, into: &out)
    out.removeAll()

    fog.fog[5] = 1
    fog.seenTiles[5] = .road
    tracker.sampleFog(fog, into: &out)
    #expect(out == [DigestChange(domain: .fog, element: 5, value: digestFogValue(fog: 1, seen: .road))])

    out.removeAll()
    fog.fog[5] = 0
    tracker.sampleFog(fog, into: &out)
    #expect(out == [DigestChange(domain: .fog, element: 5, value: digestFogValue(fog: 0, seen: .road))])
    #expect(digestFogValue(fog: 0, seen: .road) != digestFogValue(fog: 1, seen: .road))
}

@Test func digestHashIsStableAndOrderSensitive() {
    #expect(digestHash([]) == 0xcbf2_9ce4_8422_2325)
    #expect(digestHash([1, 2]) == digestHash([1, 2]))
    #expect(digestHash([1, 2]) != digestHash([2, 1]))
}
