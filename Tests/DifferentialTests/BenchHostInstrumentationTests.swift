import Foundation
import Testing
import BoloKit
import BoloNet

// v1.6.9 baseline benchmark: a REAL host with a recorder attached, against a REAL guest
// (`TCPSession.join` + `UDPSession`), to check that what the host logs is what the host did.
// Harness shape borrowed from `HostSimulatedGuestTests.swift`.

private final class GuestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    init(_ state: GameState) { _state = state }
    var state: GameState { lock.lock(); defer { lock.unlock() }; return _state }
    func mutate(_ body: (inout GameState) -> Void) { lock.lock(); body(&_state); lock.unlock() }
}

private enum BenchHarnessError: Error { case noPort }

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
        for y in 100..<120 { for x in 100..<120 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
        state.starts = [Start(x: 105, y: 105, dir: 0)]
        return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
    }
    throw BenchHarnessError.noPort
}

/// Hosts with a recorder attached, joins one guest, waits for the host to respawn it, and
/// returns what the host logged together with the host's final state.
private func recordedSession(hiddenMines: Bool) async throws -> (records: [BenchRecord], state: GameState, guest: Int) {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bolo-bench-host-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("host-0.jsonl")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "host", runID: "t")

    let (engine, port) = try await makeHost(hiddenMines: hiddenMines)
    engine.benchRecorder = recorder
    engine.start()

    let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
    var initial = GameState()
    initial.players = (0..<maxPlayers).map { _ in PlayerState() }
    #expect(applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial))
    let guestIndex = initial.localPlayer
    let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
    let guest = GuestBox(initial)

    let udpReceiver = Task {
        while !Task.isCancelled {
            guard let data = try? await udp.receiveOneRawDatagram() else { return }
            guest.mutate { state in _ = udp.apply(data, myOwnSeq: 0, state: &state) }
        }
    }
    let udpSender = Task {
        var localSeq: Int32 = 0
        while !Task.isCancelled {
            localSeq += 1
            if localSeq % 5 == 0 {
                var seqs = udp.allRemoteSeqsAsUInt32()
                seqs[guestIndex] = UInt32(bitPattern: localSeq)
                let update = assembleClUpdate(player: guestIndex, state: guest.state, seq: seqs)
                try? await udp.sendLocalUpdate(update.encode())
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    let tcpReceiver = Task {
        while !Task.isCancelled {
            guard let message = try? await joined.session.receiveOneRawMessage() else { return }
            guest.mutate { state in _ = try? TCPSession.dispatch(message, state: &state) }
        }
    }

    try await waitFor(timeout: 10) {
        !engine.state.players[guestIndex].dead && guest.state.local.armour == maxArmour
    }
    // Long enough for the 10 Hz grid sample and at least one more datagram each way.
    try await Task.sleep(nanoseconds: 400_000_000)

    engine.stop()
    // The consumer may be mid-tick when the timer stops; let it finish before reading the log.
    try await Task.sleep(nanoseconds: 100_000_000)
    let finalState = engine.state
    udpReceiver.cancel(); udpSender.cancel(); tcpReceiver.cancel()
    udp.cancel(); joined.session.cancel()
    recorder.finish()

    let text = try String(contentsOf: url, encoding: .utf8)
    return (text.split(separator: "\n").compactMap { BenchRecorder.parse($0) }, finalState, guestIndex)
}

private func latest(_ records: [BenchRecord], _ domain: DigestDomain, element: Int, view: Int) -> UInt64? {
    records.last {
        $0.kind == BenchKind.state.rawValue && $0.sub == domain.rawValue && $0.id == UInt32(element)
            && $0.v1 == UInt64(view)
    }?.v0
}

@Test func theHostEngineRecordsNothingByDefault() async throws {
    let (engine, _) = try await makeHost(hiddenMines: false)
    #expect(engine.benchRecorder == nil)
}

@Test(.timeLimit(.minutes(1))) func everyTickIsRecordedOnceWithItsPhases() async throws {
    let (records, _, _) = try await recordedSession(hiddenMines: true)

    let ticks = records.filter { $0.kind == BenchKind.tick.rawValue }.map(\.id)
    #expect(ticks.count > 25)
    #expect(ticks == Array(1...UInt32(ticks.count)), "tick ordinals must be consecutive from 1")
    #expect(records.filter { $0.kind == BenchKind.timerFire.rawValue }.count >= ticks.count)

    let phases = records.filter { $0.kind == BenchKind.phase.rawValue }
    let whole = phases.filter { $0.sub == BenchPhase.whole.rawValue }
    // The last tick may still have been running when the engine stopped.
    #expect(whole.count >= ticks.count - 1)
    for phase in [BenchPhase.prepare, .runTick, .terrainDiff, .status, .fog, .sendFlush, .renderHop, .digest] {
        #expect(phases.contains { $0.sub == phase.rawValue }, "missing phase \(phase)")
    }
    #expect(phases.contains { $0.sub == BenchPhase.updateSend.rawValue }, "the 10 Hz update must be timed")

    // The phases of a tick are parts of it, so they cannot add up to more than the whole.
    let tick = try #require(whole.dropFirst(5).first?.id)
    let parts = phases.filter { $0.id == tick && $0.sub != BenchPhase.whole.rawValue }.reduce(0) { $0 + $1.v0 }
    let total = try #require(whole.first { $0.id == tick }?.v0)
    #expect(parts <= total)
    #expect(total < 1_000_000_000)
}

@Test(.timeLimit(.minutes(1))) func theJoinAndTheGuestsDatagramsAreRecorded() async throws {
    let (records, _, guest) = try await recordedSession(hiddenMines: true)

    let joins = records.filter { $0.kind == BenchKind.join.rawValue }
    #expect(joins.map(\.sub) == [0, 1])
    #expect(joins.last?.id == UInt32(guest))
    #expect((joins.last?.v0 ?? 0) > 0)

    let received = records.filter {
        $0.kind == BenchKind.receive.rawValue && $0.sub == BenchChannel.udp.rawValue
    }
    #expect(received.count >= 2)
    #expect(received.allSatisfy { $0.v1 == UInt64(guest) && $0.v0 >= 113 })

    let sent = records.filter { $0.kind == BenchKind.datagram.rawValue && $0.sub == 0 }
    #expect(sent.count >= 2)
    #expect(sent.allSatisfy { $0.id == 0 && $0.v0 % 5 == 0 }, "the host sends its own update every 5th tick")
    #expect(!records.contains { $0.kind == BenchKind.invariant.rawValue })
}

@Test(.timeLimit(.minutes(1))) func theLastLoggedStateIsTheHostsFinalState() async throws {
    let (records, state, guest) = try await recordedSession(hiddenMines: true)

    #expect(latest(records, .selfStatus, element: 0, view: guest) == digestSelfStatus(player: guest, state: state))
    let resources = digestResources(player: guest, state: state)
    for resource in DigestResource.allCases {
        #expect(latest(records, .resources, element: resource.rawValue, view: guest) == resources[resource.rawValue])
    }
    #expect(resources[DigestResource.armour.rawValue] == UInt64(maxArmour))

    // The guest stands on grass at its spawn point, inside its own vision.
    let spawn = 105 * 256 + 105
    #expect(latest(records, .terrain, element: spawn, view: guest) == UInt64(Terrain.grass0.rawValue))
    #expect(latest(records, .fog, element: spawn, view: guest).map { $0 & 1 } == 1)
    // Far outside it, the host expects the guest to know nothing.
    #expect(latest(records, .terrain, element: 0, view: guest) == digestUnknownTerrain)
}

@Test(.timeLimit(.minutes(1))) func withHiddenMinesOffTheExpectedViewIsTheWholeMap() async throws {
    let (records, state, guest) = try await recordedSession(hiddenMines: false)

    #expect(latest(records, .terrain, element: 0, view: guest) == UInt64(UInt32(bitPattern: state.terrain.storage[0])))
    #expect(!records.contains { $0.kind == BenchKind.state.rawValue && $0.sub == DigestDomain.fog.rawValue })
    #expect(!records.contains { $0.kind == BenchKind.state.rawValue && $0.v0 == digestUnknownTerrain && $0.sub == DigestDomain.terrain.rawValue })
}
