import Foundation
import Testing
import BoloKit
import BoloNet

// The first test in this project that runs a REAL host (`HostListener` + `HostDgramListener` +
// `HostGameEngine`) against a REAL guest (`TCPSession.join` + `UDPSession`), with no hand-built
// packets and no `dead = false` fixtures. Every other host test fakes one side of the wire, which
// is how the v1.5.0 two-Mac test found bugs no test could: hosting on a fixed port, a one-slot
// player table, the host rejecting every guest datagram (guest evicted after 9 s), the host never
// marking a guest alive, and the guest rejecting every host update (seq stuck at 0).

private final class GuestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    init(_ state: GameState) { _state = state }
    var state: GameState { lock.lock(); defer { lock.unlock() }; return _state }
    func mutate(_ body: (inout GameState) -> Void) { lock.lock(); body(&_state); lock.unlock() }
}

private func makeHost() async throws -> (engine: HostGameEngine, port: UInt16) {
    // A random dynamic port may be taken; EADDRINUSE is retried, anything else is a real failure.
    for _ in 0..<8 {
        let port = UInt16.random(in: 49_152...65_000)
        let tcp: HostListener
        do { tcp = try await HostListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        let udp: HostDgramListener
        do { udp = try await HostDgramListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { tcp.cancel(); continue }

        // Same host setup `HostGameView.startHosting()` builds.
        var state = GameState()
        var host = PlayerState()
        host.connected = true
        host.used = true
        host.dead = true
        host.alliance = UInt16(1 << 0)
        state.players = hostPlayerSlots(hostPlayer: host)
        state.localPlayer = 0
        state.local.respawnCounter = respawnTicks - 1
        for y in 100..<120 { for x in 100..<120 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
        state.starts = [Start(x: 105, y: 105, dir: 0)]
        return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
    }
    throw HarnessError.noPort
}

private enum HarnessError: Error { case noPort }

private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
}

@Test func realHostAndGuestSeeEachOtherAndTheGuestIsNotEvicted() async throws {
    let (engine, port) = try await makeHost()
    engine.start()
    defer { engine.stop() }

    // Real guest: TCP join, then the datagram channel, exactly as `JoinGameView` does it.
    let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
    var initial = GameState()
    initial.players = (0..<maxPlayers).map { _ in PlayerState() }
    #expect(applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial))
    let guestIndex = initial.localPlayer
    #expect(guestIndex == 1)
    let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
    let guest = GuestBox(initial)
    defer { udp.cancel(); joined.session.cancel() }

    // Guest's UDP receive loop (applies host updates) and 50 Hz send loop (every 5th tick).
    let receiver = Task {
        while !Task.isCancelled {
            guard let data = try? await udp.receiveOneRawDatagram() else { return }
            guest.mutate { state in _ = udp.apply(data, myOwnSeq: 0, state: &state) }
        }
    }
    let sender = Task {
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
    defer { receiver.cancel(); sender.cancel() }

    // The host's own tank spawns after ~3 s; give both directions time to settle.
    try await waitFor(timeout: 8) {
        !engine.state.players[guestIndex].dead && !guest.state.players[0].dead
    }
    let hostSeesGuest = engine.state.players[guestIndex]
    #expect(hostSeesGuest.connected)
    #expect(!hostSeesGuest.dead, "host must see the guest tank alive")
    #expect(hostSeesGuest.tank == guest.state.players[guestIndex].tank, "host must track the guest's tank")
    let guestSeesHost = guest.state.players[0]
    #expect(!guestSeesHost.dead, "guest must see the host tank alive")
    #expect(guestSeesHost.tank == engine.state.players[0].tank, "guest must track the host's tank")

    // Past the 9-second lag-eviction threshold: a guest whose datagrams are being accepted stays.
    try await Task.sleep(nanoseconds: 10_000_000_000)
    #expect(engine.state.players[guestIndex].connected, "guest must not be evicted while it is sending")
}

private final class MessageLog: @unchecked Sendable {
    private let lock = NSLock()
    private var _texts: [String] = []
    func add(_ text: String) { lock.lock(); _texts.append(text); lock.unlock() }
    var texts: [String] { lock.lock(); defer { lock.unlock() }; return _texts }
}

/// A guest that joins over TCP but never sends a datagram is evicted after 9 s. The eviction
/// closes the guest's TCP itself, which re-enters the engine as "connection ended"; the departure
/// must still be reported exactly once (the live two-Mac run showed it twice).
@Test func aSilentGuestIsEvictedAndItsDepartureIsReportedOnce() async throws {
    let (engine, port) = try await makeHost()
    let log = MessageLog()
    engine.onMessageReceived = { message in log.add(message.text) }
    engine.start()
    defer { engine.stop() }

    let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Ghost", pass: "")
    defer { joined.session.cancel() }

    try await waitFor(timeout: 14) { log.texts.contains { $0.hasSuffix("disconnected") } }
    // Let the TCP-closed echo (if any) arrive before counting.
    try await Task.sleep(nanoseconds: 1_500_000_000)

    #expect(!engine.state.players[1].connected)
    #expect(log.texts.filter { $0.hasSuffix("disconnected") }.count == 1, "\(log.texts)")
}
