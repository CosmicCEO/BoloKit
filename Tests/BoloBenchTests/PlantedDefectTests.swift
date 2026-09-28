import Foundation
import Testing
import BoloKit
import BoloNet

@testable import BoloBenchCore

// v1.6.9 baseline benchmark: the instrument checked end to end against ground truth.
//
// A REAL host (`HostListener` + `HostDgramListener` + `HostGameEngine`) and a REAL guest
// connection (`TCPSession.join` + `UDPSession`), each with its own recorder. A defect is planted
// by changing the guest's state behind the game's back, and the analyzer must report it, in the
// right place, with the right values. And with nothing planted, what the analyzer says is still
// divergent at the end must be exactly what comparing the two final states directly says.
//
// The guest here is the soak test's shape, not the shipped `GameSession`. That the shipped
// guest logs what it holds is checked where it can be, in the app's own tests
// (`BenchGuestInstrumentationTests`): the analyzer cannot be linked into the app's test bundle
// without loading a second copy of BoloNet's types beside the app's.

private final class GuestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    private var _fog = FogVisionTracker()
    init(_ state: GameState) { _state = state }
    var state: GameState { lock.lock(); defer { lock.unlock() }; return _state }
    var fog: FogState { lock.lock(); defer { lock.unlock() }; return _fog.fogState }
    func mutate(_ body: (inout GameState) -> Void) { lock.lock(); body(&_state); lock.unlock() }
    func mutateFog(_ body: (inout FogState) -> Void) { lock.lock(); body(&_fog.fogState); lock.unlock() }
    /// One guest tick's worth of fog, then the state and fog as they stand.
    func tick(_ body: (inout GameState) -> Void) -> (GameState, FogState) {
        lock.lock(); defer { lock.unlock() }
        body(&_state)
        updateFogVisionTracker(&_fog, observer: _state.localPlayer, state: _state)
        return (_state, _fog.fogState)
    }
}

private enum PlantError: Error { case noPort }

private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
}

private func makeHost(hiddenMines: Bool) async throws -> (engine: HostGameEngine, port: UInt16) {
    for _ in 0..<8 {
        let port = UInt16.random(in: 49_152...65_000)
        let tcp: HostListener
        do { tcp = try await HostListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        let udp: HostDgramListener
        do { udp = try await HostDgramListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { tcp.cancel(); continue }

        var state = GameState()
        var host = PlayerState()
        host.connected = true
        host.used = true
        host.dead = true
        host.alliance = UInt16(1 << 0)
        state.players = hostPlayerSlots(hostPlayer: host)
        state.localPlayer = 0
        state.local.respawnCounter = respawnTicks - 1
        state.hostSimulatesRemotePlayers = true
        state.hiddenMines = hiddenMines
        // Fully grown grass, which is what a map decoded on the join path yields.
        for y in 100..<120 { for x in 100..<120 { state.terrain.storage[y * 256 + x] = Terrain.grass3.rawValue } }
        state.starts = [Start(x: 105, y: 105, dir: 0)]
        // A dead pill, so it fires at nobody, and off the diagonal from the spawn point: a pill
        // shell fired along an exact diagonal starts on the corner of the pill's own tile.
        state.pills = [Pill(x: 112, y: 108, armour: 0, owner: playerNeutral, speed: 50, counter: 0)]
        state.bases = [Base(x: 112, y: 112, armour: 90, owner: playerNeutral, shells: 40, mines: 40)]
        return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
    }
    throw PlantError.noPort
}

private struct Outcome {
    var host: BenchLog
    var guest: BenchLog
    var hostState: GameState
    var hostFog: FogState?
    var guestState: GameState
    var guestFog: FogState
    var me: Int
}

/// Hosts, joins, lets both settle, plants `defect` on the guest, waits `linger`, and stops.
private func play(
    hiddenMines: Bool, linger: UInt64 = 800_000_000, defect: (GuestBoxHandle) -> Void = { _ in }
) async throws -> Outcome {
    let directory = FileManager.default.temporaryDirectory
        .appendingPathComponent("bolo-bench-planted-\(UUID().uuidString)", isDirectory: true)
    defer { try? FileManager.default.removeItem(at: directory) }
    let hostURL = directory.appendingPathComponent("host.jsonl")
    let guestURL = directory.appendingPathComponent("join.jsonl")
    let hostRecorder = try BenchRecorder(url: hostURL, role: "host", runID: "planted")
    let guestRecorder = try BenchRecorder(url: guestURL, role: "join", runID: "planted")

    let (engine, port) = try await makeHost(hiddenMines: hiddenMines)
    engine.benchRecorder = hostRecorder
    engine.start()

    let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
    var initial = GameState()
    initial.players = (0..<maxPlayers).map { _ in PlayerState() }
    #expect(applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial))
    let me = initial.localPlayer
    let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
    let guest = GuestBox(initial)

    let udpReceiver = Task {
        while !Task.isCancelled {
            guard let data = try? await udp.receiveOneRawDatagram() else { return }
            guest.mutate { state in _ = udp.apply(data, myOwnSeq: 0, state: &state) }
        }
    }
    let tcpReceiver = Task {
        while !Task.isCancelled {
            guard let message = try? await joined.session.receiveOneRawMessage() else { return }
            guest.mutate { state in _ = try? TCPSession.dispatch(message, state: &state) }
        }
    }
    // The guest's tick: its own movement, its own fog, its update every fifth tick, and the
    // same state sample the shipped guest takes.
    let ticker = Task {
        var probe = BenchGuestStateProbe()
        var tick: UInt32 = 0
        var localSeq: Int32 = 0
        while !Task.isCancelled {
            tick &+= 1
            // As the shipped guest does, so the log runs to the end of what was observed and
            // not just to the last change.
            guestRecorder.record(.tick, id: tick)
            let (state, fog) = guest.tick { state in
                if !state.players[me].dead { tankMoveTick(player: me, state: &state) }
            }
            probe.sample(state: state, fogState: fog, tick: tick, recorder: guestRecorder)
            localSeq += 1
            if localSeq % 5 == 0 {
                var seqs = udp.allRemoteSeqsAsUInt32()
                seqs[me] = UInt32(bitPattern: localSeq)
                try? await udp.sendLocalUpdate(assembleClUpdate(player: me, state: state, seq: seqs).encode())
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }

    try await waitFor(timeout: 10) {
        !engine.state.players[me].dead && !guest.state.players[me].dead && guest.state.local.armour == maxArmour
    }
    // Both sides agreed and logged before anything is planted.
    try await Task.sleep(nanoseconds: 600_000_000)
    defect(GuestBoxHandle(box: guest, me: me))
    try await Task.sleep(nanoseconds: linger)

    engine.stop()
    try await Task.sleep(nanoseconds: 200_000_000)
    ticker.cancel()
    _ = await ticker.result
    udpReceiver.cancel()
    tcpReceiver.cancel()
    let outcome = (engine.state, engine.fogState(for: me), guest.state, guest.fog)
    udp.cancel()
    joined.session.cancel()
    hostRecorder.finish()
    guestRecorder.finish()

    return Outcome(
        host: try BenchLog(contentsOf: hostURL), guest: try BenchLog(contentsOf: guestURL), hostState: outcome.0,
        hostFog: outcome.1, guestState: outcome.2, guestFog: outcome.3, me: me
    )
}

/// What a planted defect may touch: the guest's state and fog, behind the game's back.
private struct GuestBoxHandle {
    let box: GuestBox
    let me: Int
    func state(_ body: (inout GameState) -> Void) { box.mutate(body) }
    func fog(_ body: (inout FogState) -> Void) { box.mutateFog(body) }
}

private struct Place: Hashable {
    var domain: CompareDomain
    var element: UInt32
}

/// Every element the two final states disagree on, found by comparing them directly.
private func directComparison(_ outcome: Outcome) -> Set<Place> {
    func values(_ state: GameState, terrain: [UInt64], fog: FogState?) -> [Place: UInt64?] {
        var tracker = StateDigestTracker(player: outcome.me)
        var changes: [DigestChange] = []
        tracker.sampleSmallDomains(state, into: &changes)
        tracker.sampleTerrain(view: terrain, into: &changes)
        if let fog { tracker.sampleFog(fog, into: &changes) }
        var result: [Place: UInt64?] = [:]
        for change in changes {
            for (domain, element, value) in comparableParts(domain: change.domain, element: change.element, value: change.value) {
                result[Place(domain: domain, element: element)] = value
            }
        }
        return result
    }
    let hiddenMines = outcome.hostState.hiddenMines
    let hostFog = hiddenMines ? outcome.hostFog : nil
    let guestFog = hiddenMines ? outcome.guestFog : nil
    let host = values(
        outcome.hostState, terrain: expectedGuestTerrainView(terrain: outcome.hostState.terrain, fogState: hostFog),
        fog: hostFog
    )
    let guest = values(
        outcome.guestState, terrain: observedGuestTerrainView(terrain: outcome.guestState.terrain, fogState: guestFog),
        fog: guestFog
    )
    var differing = Set<Place>()
    for (place, hostValue) in host {
        guard let hostValue, let guestValue = guest[place] ?? nil else { continue }
        if hostValue != guestValue { differing.insert(place) }
    }
    return differing
}

private func stillDivergent(_ outcome: Outcome) throws -> Set<Place> {
    let result = try #require(findDivergence(host: outcome.host, guest: outcome.guest))
    return Set(result.episodes.filter { $0.end == nil }.map { Place(domain: $0.domain, element: $0.element) })
}

// MARK: - Ground truth

/// Whatever the two sides disagree on at the end, the analyzer must name exactly that.
@Test(.timeLimit(.minutes(2)), arguments: [true, false])
func theAnalyzerAgreesWithADirectComparisonOfTheFinalStates(hiddenMines: Bool) async throws {
    for round in 1...10 {
        let outcome = try await play(hiddenMines: hiddenMines, linger: 300_000_000)
        let direct = directComparison(outcome)
        let analyzed = try stillDivergent(outcome)
        #expect(
            analyzed == direct,
            "round \(round): analyzer only \(analyzed.subtracting(direct).count), direct only \(direct.subtracting(analyzed).count)"
        )
    }
}

// MARK: - Planted defects

private func planted(_ domain: CompareDomain, _ element: Int, in outcome: Outcome) throws -> Episode {
    let result = try #require(findDivergence(host: outcome.host, guest: outcome.guest))
    return try #require(
        result.episodes.first { $0.domain == domain && $0.element == UInt32(element) && $0.end == nil },
        "no open \(domain.rawValue) episode at element \(element)"
    )
}

@Test(.timeLimit(.minutes(1))) func aGuestWithTheWrongArmourIsReported() async throws {
    let outcome = try await play(hiddenMines: true) { guest in guest.state { $0.local.armour = 25 } }
    let episode = try planted(.resources, DigestResource.armour.rawValue, in: outcome)
    #expect(episode.hostValue == UInt64(maxArmour))
    #expect(episode.guestValue == 25)
    #expect(episode.length == .terminal)
    #expect(try stillDivergent(outcome) == directComparison(outcome))
}

@Test(.timeLimit(.minutes(1))) func aGuestWithTheWrongPillArmourIsReported() async throws {
    let outcome = try await play(hiddenMines: true) { guest in guest.state { $0.pills[0].armour = 9 } }
    let episode = try planted(.pills, 0, in: outcome)
    #expect((episode.hostValue >> 16) & 0xff == 0)
    #expect((episode.guestValue >> 16) & 0xff == 9)
    #expect(episode.length == .terminal)
}

@Test(.timeLimit(.minutes(1))) func aGuestWithTheWrongBaseOwnerIsReported() async throws {
    let outcome = try await play(hiddenMines: true) { guest in guest.state { $0.bases[0].owner = 1 } }
    let episode = try planted(.bases, 0, in: outcome)
    #expect((episode.hostValue >> 16) & 0xff == UInt64(playerNeutral))
    #expect((episode.guestValue >> 16) & 0xff == 1)
}

// Not the boat flag: on land the guest's own movement code clears that within a tick, so it
// would be a defect the game corrects by itself.
@Test(.timeLimit(.minutes(1))) func aGuestThatThinksItIsDeadIsReported() async throws {
    let outcome = try await play(hiddenMines: true) { guest in guest.state { $0.players[guest.me].dead = true } }
    let episode = try planted(.selfStatus, 0, in: outcome)
    #expect(episode.hostValue & 1 == 0, "the host, which decides, has it alive")
    #expect(episode.guestValue & 1 == 1)
    #expect(episode.length == .terminal)
}

@Test(.timeLimit(.minutes(1)), arguments: [true, false])
func aGuestWithTheWrongTerrainInSightIsReported(hiddenMines: Bool) async throws {
    // Two tiles from the spawn point at (105, 105): inside the guest's vision either way.
    let tile = 105 * 256 + 107
    let outcome = try await play(hiddenMines: hiddenMines) { guest in
        guest.state { $0.terrain.storage[tile] = Terrain.crater.rawValue }
    }
    let episode = try planted(.terrain, tile, in: outcome)
    #expect(episode.hostValue == UInt64(Terrain.grass0.rawValue), "grass, whichever growth variant")
    #expect(episode.guestValue == UInt64(Terrain.crater.rawValue))
    #expect(episode.length == .terminal)
}

@Test(.timeLimit(.minutes(1))) func aGuestWithTheWrongTerrainOutOfSightIsNotAFault() async throws {
    // Far from anything the guest can see: the host does not expect it to know this tile.
    let tile = 200 * 256 + 200
    let outcome = try await play(hiddenMines: true) { guest in
        guest.state { $0.terrain.storage[tile] = Terrain.crater.rawValue }
    }
    let result = try #require(findDivergence(host: outcome.host, guest: outcome.guest))
    #expect(!result.episodes.contains { $0.domain == .terrain && $0.element == UInt32(tile) })
}

@Test(.timeLimit(.minutes(1))) func aDefectThatIsPutRightIsAnEpisodeThatEnded() async throws {
    let outcome = try await play(hiddenMines: true, linger: 1_500_000_000) { guest in
        guest.state { $0.pills[0].armour = 9 }
        Task {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guest.state { $0.pills[0].armour = 0 }
        }
    }
    let result = try #require(findDivergence(host: outcome.host, guest: outcome.guest))
    let episodes = result.episodes(in: .pills)
    #expect(episodes.count == 1)
    let episode = try #require(episodes.first)
    #expect(episode.end != nil)
    #expect(episode.length == .slow)
    let lasted = episode.duration(until: result.windowEnd).ms
    #expect(lasted > 500 && lasted < 800, "planted for 600 ms, measured \(lasted) ms")
}
