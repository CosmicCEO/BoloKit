import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Swift-only tests for `processDgramPacket` (Wave 6.4c, §2/§4) -- same
// "no C oracle for the transport mechanism itself" reasoning as
// `UDPSessionTests.swift`/`HostListenerTests.swift` (D31). `decodeDgramServerRelay`
// itself is already complete and oracle-tested (`DgramServerRelayTests.swift`);
// these tests cover the *driver* around it: does it apply/advance/relay
// correctly given a real `NWConnection`, and does `HostSessionTable.
// setDgramConnection`'s D52 cancel-and-replace lifecycle actually hold.

private enum HarnessError: Error {
    case shortRead
}

private final class UDPConnectionWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingConnection: NWConnection?
    private var continuation: CheckedContinuation<NWConnection, Never>?

    func deliver(_ connection: NWConnection) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: connection)
        } else {
            pendingConnection = connection
            lock.unlock()
        }
    }

    private func takePending() -> NWConnection? {
        lock.lock()
        defer { lock.unlock() }
        if let pendingConnection {
            self.pendingConnection = nil
            return pendingConnection
        }
        return nil
    }

    private func register(_ continuation: CheckedContinuation<NWConnection, Never>) {
        lock.lock()
        if let pendingConnection {
            self.pendingConnection = nil
            lock.unlock()
            continuation.resume(returning: pendingConnection)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func wait() async -> NWConnection {
        if let connection = takePending() {
            return connection
        }
        return await withCheckedContinuation { continuation in
            register(continuation)
        }
    }
}

private func sendDatagram(_ connection: NWConnection, _ bytes: [UInt8]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
            content: Data(bytes),
            completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        )
    }
}

private func receiveOneDatagram(_ connection: NWConnection) async throws -> [UInt8] {
    try await withCheckedThrowingContinuation { continuation in
        connection.receiveMessage { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data {
                continuation.resume(returning: Array(data))
            } else {
                continuation.resume(throwing: HarnessError.shortRead)
            }
        }
    }
}

/// One simulated player's UDP flow: `clientEnd` is the test's own handle
/// (what a real player's own UDP socket would be); `serverEnd` is what
/// `HostDgramListener` would have handed `processDgramPacket` -- the
/// value under test always reads/writes through `serverEnd`, never
/// `clientEnd` directly (matching what a live listener actually provides).
private struct FakeUDPPlayerLink {
    let listener: NWListener
    let clientEnd: NWConnection
    let serverEnd: NWConnection
}

/// Starts a loopback UDP listener, connects a client, and sends one
/// throwaway datagram to make `NWListener` deliver the accepted
/// per-peer connection -- confirmed by direct API research (this file's
/// production counterpart's own header): `NWListener`+UDP only creates
/// the accepted-connection object once the first datagram from that peer
/// arrives. The throwaway byte is never read by anything in these tests
/// (`processDgramPacket` is always called with explicit bytes, never via
/// `serverEnd.receiveMessage`), so its content is irrelevant.
private func makeUDPLink() async throws -> FakeUDPPlayerLink {
    let listener = try NWListener(using: .udp, on: .any)
    let waiter = UDPConnectionWaiter()
    listener.newConnectionHandler = { connection in
        connection.start(queue: .main)
        waiter.deliver(connection)
    }

    let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
        nonisolated(unsafe) var resumed = false
        listener.stateUpdateHandler = { state in
            guard !resumed else { return }
            switch state {
            case .ready:
                resumed = true
                continuation.resume(returning: listener.port?.rawValue ?? 0)
            case .failed(let error):
                resumed = true
                continuation.resume(throwing: error)
            default:
                break
            }
        }
        listener.start(queue: .main)
    }

    let clientEnd = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .udp)
    clientEnd.start(queue: .main)
    try await sendDatagram(clientEnd, [0])
    let serverEnd = await waiter.wait()

    return FakeUDPPlayerLink(listener: listener, clientEnd: clientEnd, serverEnd: serverEnd)
}

private func sampleHeader(player: UInt8, seq: [Int32], tank: BoloKit.Vec2f = BoloKit.Vec2f(x: 0, y: 0)) -> CLUpdateHeader {
    CLUpdateHeader(
        player: player, seq: seq, dead: false, boat: false, dir: 0, tank: tank, speed: 0, turnSpeed: 0,
        kickDir: 0, kickSpeed: 0, builderStatus: 0, builder: BoloKit.Vec2f(x: 0, y: 0),
        builderTargetX: 0, builderTargetY: 0, builderWait: 0, inputFlags: 0,
        tankShotSound: false, pillShotSound: false, sinkSound: false, builderDeathSound: false
    )
}

private func makeState() -> GameState {
    var state = GameState()
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    return state
}

private func connectedPlayer() -> PlayerState {
    var p = PlayerState()
    p.used = true
    p.connected = true
    return p
}

// MARK: - processDgramPacket: applied

@Test func processDgramPacketAppliesTankAndAdvancesSeq() async throws {
    let link = try await makeUDPLink()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    let table = HostSessionTable()
    guard let address = peerAddress(from: link.serverEnd) else {
        Issue.record("expected a real loopback address")
        return
    }
    await table.setDgramAddress(address, for: 0)
    // `decodeDgramServerRelay`'s validity check reads `connected` from the
    // *table's* TCP `connection` field (`server.players[player].cntlsock
    // != -1`, mirrored by `dgramSessionSnapshot`), NOT `GameState.players
    // [i].connected` -- a real, easy-to-miss distinction, confirmed by
    // direct read of `HostSessionTable.dgramSessionSnapshot`.
    await table.setConnection(link.serverEnd, for: 0)

    var state = makeState()
    state.players[0] = connectedPlayer()

    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[0] = 7
    let header = sampleHeader(player: 0, seq: seq, tank: BoloKit.Vec2f(x: 42, y: 99))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()

    await processDgramPacket(bytes: bytes, from: link.serverEnd, state: &state, table: table)

    #expect(state.players[0].tank == BoloKit.Vec2f(x: 42, y: 99))
    #expect(await table.seq(for: 0) == 7)
    #expect(await table.dgramConnection(for: 0) === link.serverEnd)
}

@Test func processDgramPacketRelaysToRegisteredPeerAndSkipsUnregisteredOne() async throws {
    let senderLink = try await makeUDPLink()
    let peerLink = try await makeUDPLink()
    defer {
        senderLink.listener.cancel(); senderLink.clientEnd.cancel()
        peerLink.listener.cancel(); peerLink.clientEnd.cancel()
    }

    let table = HostSessionTable()
    guard let senderAddress = peerAddress(from: senderLink.serverEnd) else {
        Issue.record("expected a real loopback address")
        return
    }
    await table.setDgramAddress(senderAddress, for: 0)
    // `connected` (relay eligibility) comes from the table's TCP
    // `connection` field, not `GameState.players[i].connected` -- all
    // three players need it set for their intended roles below.
    await table.setConnection(senderLink.serverEnd, for: 0)
    await table.setConnection(peerLink.serverEnd, for: 1)
    await table.setConnection(peerLink.serverEnd, for: 2)  // relay-eligible, but...
    // ...player 1 already has a live UDP flow registered (simulating it
    // sent at least one packet before); player 2 has NOT, so it's
    // relay-eligible but has no live flow to relay through yet -- T-15's
    // real, disclosed limitation, exercised directly rather than assumed.
    await table.setDgramConnection(peerLink.serverEnd, for: 1)

    var state = makeState()
    state.players[0] = connectedPlayer()
    state.players[1] = connectedPlayer()
    state.players[2] = connectedPlayer()

    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[0] = 1
    let header = sampleHeader(player: 0, seq: seq, tank: BoloKit.Vec2f(x: 5, y: 5))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()

    await processDgramPacket(bytes: bytes, from: senderLink.serverEnd, state: &state, table: table)

    // T-8: the relay is the original bytes, unre-encoded.
    let relayed = try await receiveOneDatagram(peerLink.clientEnd)
    #expect(relayed == bytes)
    #expect(await table.dgramConnection(for: 2) == nil)  // never touched -- confirms it was skipped, not errored
}

@Test func processDgramPacketEchoesTrackerProbeVerbatim() async throws {
    let link = try await makeUDPLink()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    let table = HostSessionTable()
    var state = makeState()

    var probe = [UInt8](repeating: 0xAB, count: CLUpdateHeader.wireSize)
    probe[0] = 255  // player == 255, T-4/T-5

    await processDgramPacket(bytes: probe, from: link.serverEnd, state: &state, table: table)

    let echoed = try await receiveOneDatagram(link.clientEnd)
    #expect(echoed == probe)  // verbatim -- not zeroed, unlike registerserver()'s own echo (deferred to 6.5)
}

@Test func processDgramPacketStaleSeqDropsWithoutRefreshingAnything() async throws {
    let link = try await makeUDPLink()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    let table = HostSessionTable()
    guard let address = peerAddress(from: link.serverEnd) else {
        Issue.record("expected a real loopback address")
        return
    }
    await table.setDgramAddress(address, for: 0)
    await table.setConnection(link.serverEnd, for: 0)  // must be table-"connected" to reach the seq check at all
    await table.setSeq(10, for: 0)

    var state = makeState()
    state.players[0] = connectedPlayer()
    state.players[0].tank = BoloKit.Vec2f(x: 1, y: 1)

    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[0] = 5  // stale: 10 is already newer
    let header = sampleHeader(player: 0, seq: seq, tank: BoloKit.Vec2f(x: 99, y: 99))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()

    await processDgramPacket(bytes: bytes, from: link.serverEnd, state: &state, table: table)

    #expect(state.players[0].tank == BoloKit.Vec2f(x: 1, y: 1))  // untouched
    #expect(await table.seq(for: 0) == 10)  // untouched
    #expect(await table.dgramConnection(for: 0) == nil)  // never registered -- stale packets don't establish a flow
}

// MARK: - D52: cancel-and-replace connection lifecycle

@Test func setDgramConnectionCancelsThePreviousConnectionOnReplace() async throws {
    let table = HostSessionTable()
    let link1 = try await makeUDPLink()
    let link2 = try await makeUDPLink()
    defer {
        link1.listener.cancel(); link1.clientEnd.cancel()
        link2.listener.cancel(); link2.clientEnd.cancel()
    }

    await table.setDgramConnection(link1.serverEnd, for: 0)

    let canceled = await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
        nonisolated(unsafe) var resumed = false
        link1.serverEnd.stateUpdateHandler = { state in
            guard !resumed else { return }
            if case .cancelled = state {
                resumed = true
                continuation.resume(returning: true)
            }
        }
        Task {
            await table.setDgramConnection(link2.serverEnd, for: 0)
        }
    }

    #expect(canceled)
    #expect(await table.dgramConnection(for: 0) === link2.serverEnd)
}

/// D52's other half: an unresolved datagram (one that never reaches
/// `.applied`) must not have its connection retained anywhere past that
/// one packet -- confirmed directly, not just inferred from
/// `processDgramPacket`'s code shape.
@Test func processDgramPacketNeverRetainsConnectionForAnUnresolvedDatagram() async throws {
    let link = try await makeUDPLink()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    let table = HostSessionTable()
    var state = makeState()  // nobody used/connected -- guarantees .dropped

    let seq = [Int32](repeating: 0, count: maxPlayers)
    let header = sampleHeader(player: 0, seq: seq, tank: BoloKit.Vec2f(x: 1, y: 1))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()

    await processDgramPacket(bytes: bytes, from: link.serverEnd, state: &state, table: table)

    for i in 0..<maxPlayers {
        #expect(await table.dgramConnection(for: i) == nil)
    }
}
