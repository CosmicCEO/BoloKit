import Foundation
import Testing
import BoloKit
import BoloNet

@testable import BoloBenchCore

// v1.6.9 baseline benchmark: the analyzer's verdicts, checked against logs built by hand where
// the right answer is known. No sockets, no game.

let ms: UInt64 = 1_000_000
let second: UInt64 = 1_000_000_000
/// An arbitrary uptime for the start of every synthetic run.
let t0: UInt64 = 5_000 * second

func header(_ role: String, model: String = "MacBookPro17,1") -> BenchHeader {
    BenchHeader([
        "schema": BoloBench.schemaVersion, "role": role, "runId": "synthetic", "model": model, "osBuild": "26A428",
    ])
}

func state(_ domain: DigestDomain, _ element: Int, _ value: UInt64, at time: UInt64, view: Int = 1) -> BenchRecord {
    BenchRecord(time: t0 + time, kind: .state, sub: domain.rawValue, id: UInt32(element), v0: value, v1: UInt64(view))
}

func mark(at time: UInt64) -> BenchRecord {
    BenchRecord(time: t0 + time, kind: .mark, sub: BenchMark.custom.rawValue)
}

/// Both sides start agreed on `value`, and the run lasts `length`.
func pair(
    _ domain: DigestDomain, _ element: Int = 0, start value: UInt64, length: UInt64 = 10 * second,
    host: [BenchRecord] = [], guest: [BenchRecord] = []
) -> (BenchLog, BenchLog) {
    let opening = state(domain, element, value, at: 0)
    return (
        BenchLog(header: header("host"), records: [opening] + host + [mark(at: length)]),
        BenchLog(header: header("join"), records: [opening] + guest + [mark(at: length)])
    )
}

private func armour(_ value: Int) -> UInt64 { UInt64(value) }
private let armourElement = DigestResource.armour.rawValue

@Test func agreementThroughoutIsNoDivergence() throws {
    let (host, guest) = pair(.resources, armourElement, start: armour(40))
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes.isEmpty)
    #expect(result.guest == 1)
    #expect(result.window == 10 * second)
}

@Test(arguments: [
    (100, EpisodeLength.inFlight), (250, .inFlight), (251, .slow), (2_000, .slow), (2_001, .persistent),
])
func anEpisodeIsNamedByHowLongItLasted(duration: Int, expected: EpisodeLength) throws {
    let (host, guest) = pair(
        .resources, armourElement, start: armour(40),
        host: [state(.resources, armourElement, armour(35), at: 1 * second)],
        guest: [state(.resources, armourElement, armour(35), at: 1 * second + UInt64(duration) * ms)]
    )
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes.count == 1)
    let episode = try #require(result.episodes.first)
    #expect(episode.length == expected)
    #expect(episode.domain == .resources)
    #expect(episode.duration(until: result.windowEnd) == UInt64(duration) * ms)
    #expect(episode.hostValue == 35 && episode.guestValue == 40)
}

@Test func divergenceStillOpenAtTheEndIsTerminal() throws {
    let (host, guest) = pair(
        .resources, armourElement, start: armour(40),
        host: [state(.resources, armourElement, armour(35), at: 1 * second)]
    )
    let episode = try #require(findDivergence(host: host, guest: guest)?.episodes.first)
    #expect(episode.length == .terminal)
    #expect(episode.end == nil)
}

// A change made in the last moments may simply not have been delivered yet when the log ended.
@Test func divergenceThatOpenedJustBeforeTheEndIsStillInFlight() throws {
    let (host, guest) = pair(
        .resources, armourElement, start: armour(40),
        host: [state(.resources, armourElement, armour(35), at: 10 * second - 100 * ms)]
    )
    let episode = try #require(findDivergence(host: host, guest: guest)?.episodes.first)
    #expect(episode.length == .inFlight)
}

@Test func anEpisodeCarriesOnWhileTheTwoSidesStayApartOnNewValues() throws {
    let (host, guest) = pair(
        .resources, armourElement, start: armour(40),
        host: [
            state(.resources, armourElement, armour(35), at: 1 * second),
            state(.resources, armourElement, armour(30), at: 2 * second),
        ],
        guest: [
            state(.resources, armourElement, armour(35), at: 2 * second + 50 * ms),
            state(.resources, armourElement, armour(30), at: 4 * second),
        ]
    )
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes.count == 1, "one episode from 1 s to 4 s, not two")
    #expect(result.episodes.first?.length == .persistent)
    #expect(result.episodes.first?.duration(until: result.windowEnd) == 3 * second)
}

@Test func aTileOutsideVisionIsNeverDivergent() throws {
    let grass = UInt64(Terrain.grass0.rawValue)
    let road = UInt64(Terrain.road.rawValue)
    let (host, guest) = pair(
        .terrain, 500, start: grass,
        host: [
            // The guest drives away; the host stops expecting it to know this tile.
            state(.terrain, 500, digestUnknownTerrain, at: 1 * second),
        ],
        guest: [
            // The guest keeps its old value for the rest of the run. That is by design.
            state(.terrain, 500, road, at: 2 * second),
        ]
    )
    #expect(try #require(findDivergence(host: host, guest: guest)).episodes.isEmpty)
}

@Test func leavingVisionEndsAnEpisodeInsteadOfLeavingItOpen() throws {
    let grass = UInt64(Terrain.grass0.rawValue)
    let road = UInt64(Terrain.road.rawValue)
    let (host, guest) = pair(
        .terrain, 500, start: grass,
        host: [
            state(.terrain, 500, road, at: 1 * second),
            state(.terrain, 500, digestUnknownTerrain, at: 1 * second + 600 * ms),
        ]
    )
    let result = try #require(findDivergence(host: host, guest: guest))
    let terrain = result.episodes(in: .terrain)
    #expect(terrain.count == 1)
    #expect(terrain.first?.length == .slow)
    #expect(terrain.first?.end == t0 + 1 * second + 600 * ms)
}

// The map format does not carry growth variants, so a guest decodes grass as fully grown.
@Test func growthVariantsAreReportedButAreNotATerrainFault() throws {
    let host = BenchLog(
        header: header("host"),
        records: [state(.terrain, 500, UInt64(Terrain.grass0.rawValue), at: 0), mark(at: 10 * second)]
    )
    let guest = BenchLog(
        header: header("join"),
        records: [state(.terrain, 500, UInt64(Terrain.grass3.rawValue), at: 0), mark(at: 10 * second)]
    )
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes(in: .terrain).isEmpty)
    #expect(result.episodes(in: .terrainVariant).count == 1)
    #expect(result.episodes(in: .terrainVariant).first?.candidate == nil)
    #expect(CompareDomain.terrainVariant.isInformational)

    let metrics = result.metrics()
    #expect(metrics["correctness.all.terminal"] == 0, "informational domains never count as faults")
    #expect(metrics["correctness.terrainVariant.terminal"] == 1)
}

@Test func theGuestsOwnPositionIsSeparateFromItsHostOwnedStatus() throws {
    // Dead flag clear, tile (102, 121), facing east.
    let before = UInt64(102) << 8 | UInt64(121) << 16
    let moved = UInt64(103) << 8 | UInt64(121) << 16
    let (host, guest) = pair(
        .selfStatus, 0, start: before,
        host: [state(.selfStatus, 0, moved, at: 1 * second + 90 * ms)],
        guest: [state(.selfStatus, 0, moved, at: 1 * second)]
    )
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes(in: .selfStatus).isEmpty)
    #expect(result.episodes(in: .position).count == 1)
    #expect(result.episodes(in: .position).first?.length == .inFlight)

    // Death is the host's to decide, and is compared.
    let (host2, guest2) = pair(.selfStatus, 0, start: before, host: [state(.selfStatus, 0, before | 1, at: 1 * second)])
    #expect(try #require(findDivergence(host: host2, guest: guest2)).episodes(in: .selfStatus).count == 1)
}

// P0a: host and guest each keep their own memory of a fogged tile, and a visible tile is drawn
// from live terrain, so the memory is compared only while the tile is in fog.
@Test func fogMemoryIsIgnoredWhileTheTileIsVisible() throws {
    let visibleGrass = digestFogValue(fog: 1, seen: .grass)
    let visibleSea = digestFogValue(fog: 1, seen: .sea)
    let host = BenchLog(header: header("host"), records: [state(.fog, 9, visibleGrass, at: 0), mark(at: 10 * second)])
    let guest = BenchLog(header: header("join"), records: [state(.fog, 9, visibleSea, at: 0), mark(at: 10 * second)])
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes(in: .fogVisible).isEmpty)
    #expect(result.episodes(in: .fogSeen).isEmpty)
}

@Test func fogMemoryIsComparedOnlyWhileTheTileIsInFog() throws {
    let foggedGrass = digestFogValue(fog: 0, seen: .grass)
    let foggedSea = digestFogValue(fog: 0, seen: .sea)
    let host = BenchLog(header: header("host"), records: [state(.fog, 9, foggedGrass, at: 0), mark(at: 10 * second)])
    let guest = BenchLog(header: header("join"), records: [state(.fog, 9, foggedSea, at: 0), mark(at: 10 * second)])
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes(in: .fogVisible).isEmpty)
    #expect(result.episodes(in: .fogSeen).count == 1)
    #expect(result.episodes(in: .fogSeen).first?.hostValue == UInt64(Tile.grass.rawValue))
}

@Test func onlyTheViewOfThisGuestIsCompared() throws {
    let host = BenchLog(
        header: header("host"),
        records: [
            state(.resources, armourElement, armour(40), at: 0, view: 1),
            // Another guest's armour, which has nothing to do with this one.
            state(.resources, armourElement, armour(5), at: 0, view: 2),
            mark(at: 10 * second),
        ]
    )
    let guest = BenchLog(
        header: header("join"), records: [state(.resources, armourElement, armour(40), at: 0), mark(at: 10 * second)]
    )
    #expect(try #require(findDivergence(host: host, guest: guest)).episodes.isEmpty)
}

@Test func divergentTimeCountsOverlappingEpisodesOnce() throws {
    let host = BenchLog(
        header: header("host"),
        records: [
            state(.pills, 0, 10, at: 0), state(.pills, 1, 10, at: 0),
            state(.pills, 0, 11, at: 1 * second), state(.pills, 1, 11, at: 2 * second),
            mark(at: 10 * second),
        ]
    )
    let guest = BenchLog(
        header: header("join"),
        records: [
            state(.pills, 0, 10, at: 0), state(.pills, 1, 10, at: 0),
            state(.pills, 0, 11, at: 4 * second), state(.pills, 1, 11, at: 3 * second),
            mark(at: 10 * second),
        ]
    )
    let result = try #require(findDivergence(host: host, guest: guest))
    // Pill 0 is past in-flight from 1.25 s to 4 s; pill 1 from 2.25 s to 3 s, inside that.
    #expect(result.divergentTime(in: .pills, thresholds: DivergenceThresholds()) == 2_750 * ms)
    #expect(result.metrics()["correctness.pills.divergent_time_pct"] == 27.5)
}

// MARK: - Candidate classes

private func send(to guest: Int, at time: UInt64) -> BenchRecord {
    BenchRecord(time: t0 + time, kind: .send, sub: BenchChannel.tcp.rawValue, id: 35, v0: 31, v1: UInt64(guest))
}

@Test func aHostChangeNeverSentIsACandidateUnreportedChange() throws {
    let (host, guest) = pair(
        .pills, 0, start: 15 << 16, host: [state(.pills, 0, 14 << 16, at: 1 * second)]
    )
    #expect(try #require(findDivergence(host: host, guest: guest)).episodes.first?.candidate == .unreportedChange)
}

@Test func aHostChangeThatWasSentIsNotCalledUnreported() throws {
    let (host, guest) = pair(
        .pills, 0, start: 15 << 16,
        host: [state(.pills, 0, 14 << 16, at: 1 * second), send(to: 1, at: 1 * second + 2 * ms)]
    )
    #expect(try #require(findDivergence(host: host, guest: guest)).episodes.first?.candidate == .unclassified)
}

@Test func aSendToAnotherGuestDoesNotCount() throws {
    let (host, guest) = pair(
        .pills, 0, start: 15 << 16,
        host: [state(.pills, 0, 14 << 16, at: 1 * second), send(to: 2, at: 1 * second + 2 * ms)]
    )
    #expect(try #require(findDivergence(host: host, guest: guest)).episodes.first?.candidate == .unreportedChange)
}

// The pill-armour defect of v1.6.7: the guest stepped the host's shells itself and also applied
// the host's damage message.
@Test func aGuestStepTwiceTheHostsIsACandidateDoubleApplication() throws {
    let (host, guest) = pair(
        .pills, 0, start: 15 << 16,
        host: [state(.pills, 0, 14 << 16, at: 1 * second), send(to: 1, at: 1 * second)],
        guest: [state(.pills, 0, 13 << 16, at: 1 * second + 60 * ms)]
    )
    let episodes = try #require(findDivergence(host: host, guest: guest)).episodes
    #expect(episodes.count == 1)
    #expect(episodes.first?.candidate == .doubleApplication)
    #expect(episodes.first?.length == .terminal)
}

// #171: the guest's own report carrying an old count landed after the host had changed it.
@Test func aGuestGoingBackToTheHostsOlderValueIsACandidateStaleOverwrite() throws {
    let (host, guest) = pair(
        .resources, DigestResource.mines.rawValue, start: 40,
        host: [state(.resources, DigestResource.mines.rawValue, 39, at: 1 * second), send(to: 1, at: 1 * second)],
        guest: [
            state(.resources, DigestResource.mines.rawValue, 39, at: 1 * second + 40 * ms),
            state(.resources, DigestResource.mines.rawValue, 40, at: 1 * second + 900 * ms),
        ]
    )
    let lasting = try #require(findDivergence(host: host, guest: guest)).episodes.filter { $0.length != .inFlight }
    #expect(lasting.count == 1)
    #expect(lasting.first?.candidate == .staleOverwrite)
}

@Test func divergenceFromTheFirstComparisonIsACandidateOneShotWiring() throws {
    let host = BenchLog(header: header("host"), records: [state(.bases, 0, 7, at: 0), mark(at: 10 * second)])
    let guest = BenchLog(header: header("join"), records: [state(.bases, 0, 9, at: 20 * ms), mark(at: 10 * second)])
    let episode = try #require(findDivergence(host: host, guest: guest)?.episodes.first)
    #expect(episode.candidate == .oneShotWiring)
    #expect(episode.start == t0 + 20 * ms, "the window opens when both sides have logged")
}

@Test func aTileWrongJustAfterEnteringVisionIsACandidateMaskedMessage() throws {
    let road = UInt64(Terrain.road.rawValue)
    let crater = UInt64(Terrain.crater.rawValue)
    let host = BenchLog(
        header: header("host"),
        records: [
            state(.terrain, 500, digestUnknownTerrain, at: 0),
            state(.terrain, 500, crater, at: 3 * second),
            send(to: 1, at: 3 * second),
            mark(at: 10 * second),
        ]
    )
    let guest = BenchLog(
        header: header("join"),
        records: [
            state(.terrain, 500, digestUnknownTerrain, at: 0),
            state(.terrain, 500, road, at: 3 * second + 20 * ms),
            mark(at: 10 * second),
        ]
    )
    let terrain = try #require(findDivergence(host: host, guest: guest)).episodes(in: .terrain)
    #expect(terrain.count == 1)
    #expect(terrain.first?.candidate == .maskedMessage)
}

// Spawn point, builder landing: both sides chose for themselves, at the same moment.
@Test func bothSidesChangingTogetherToDifferentValuesIsACandidateDoubleDecision() throws {
    let (host, guest) = pair(
        .bases, 0, start: 1,
        host: [
            state(.bases, 0, 2, at: 1 * second), send(to: 1, at: 1 * second),
            state(.bases, 0, 5, at: 3 * second), send(to: 1, at: 3 * second),
        ],
        guest: [
            state(.bases, 0, 2, at: 1 * second + 30 * ms),
            state(.bases, 0, 6, at: 3 * second + 10 * ms),
        ]
    )
    let lasting = try #require(findDivergence(host: host, guest: guest)).episodes.filter { $0.length != .inFlight }
    #expect(lasting.count == 1)
    #expect(lasting.first?.candidate == .doubleDecision)
}

@Test func inFlightEpisodesAreCountedButNotGuessedAt() throws {
    let (host, guest) = pair(
        .pills, 0, start: 15 << 16,
        host: [state(.pills, 0, 14 << 16, at: 1 * second)],
        guest: [state(.pills, 0, 14 << 16, at: 1 * second + 40 * ms)]
    )
    let result = try #require(findDivergence(host: host, guest: guest))
    #expect(result.episodes.first?.candidate == nil)
    let metrics = result.metrics()
    #expect(metrics["correctness.pills.inFlight"] == 1)
    #expect(metrics["correctness.pills.convergence_ms.p50"] == 40)
    #expect(CandidateClass.allCases.allSatisfy { metrics["correctness.candidate.\($0.rawValue)"] == 0 })
}

@Test func terrainClassesCollapseVariantsOnly() {
    #expect(terrainClass(UInt64(Terrain.grass3.rawValue)) == UInt64(Terrain.grass0.rawValue))
    #expect(terrainClass(UInt64(Terrain.swamp2.rawValue)) == UInt64(Terrain.swamp0.rawValue))
    #expect(terrainClass(UInt64(Terrain.rubble1.rawValue)) == UInt64(Terrain.rubble0.rawValue))
    #expect(terrainClass(UInt64(Terrain.damagedWall3.rawValue)) == UInt64(Terrain.damagedWall0.rawValue))
    // A mine under grass is a different thing from grass.
    #expect(terrainClass(UInt64(Terrain.minedGrass.rawValue)) != terrainClass(UInt64(Terrain.grass0.rawValue)))
    #expect(terrainClass(UInt64(Terrain.road.rawValue)) == UInt64(Terrain.road.rawValue))
}
