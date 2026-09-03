import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Swift-only loopback test for `UDPSession` (Wave 6.4a extension, D45) --
// same "no C oracle for the transport mechanism itself" reasoning as
// `JoinClientTests.swift` (D31). Uses a classic-API `NWListener`/
// `NWConnection` fake peer (test scaffolding only) to both receive a sent
// `CLUpdate` and send one back, confirming `UDPSession` round-trips through
// `applyRemotePlayerUpdate` on the receiving side.

private enum HarnessError: Error {
    case shortRead
}

/// Buffers exactly one inbound UDP flow so `newConnectionHandler` can be
/// installed before `NWListener.start(queue:)` runs -- same constraint
/// `JoinClientTests.swift`'s `ConnectionWaiter` documents for TCP; UDP
/// listeners have the identical requirement.
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

private func startLoopbackUDPListener() async throws -> (NWListener, UInt16, UDPConnectionWaiter) {
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
    return (listener, port, waiter)
}

private func sampleHeader(player: UInt8, remoteSeqForLocal: Int32) -> CLUpdateHeader {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[Int(player)] = 5
    return CLUpdateHeader(
        player: player, seq: seq, dead: false, boat: false, dir: 1.5,
        tank: Vec2f(x: 100, y: 200), speed: 3, turnSpeed: 0, kickDir: 0, kickSpeed: 0,
        builderStatus: 0, builder: Vec2f(x: 0, y: 0),
        builderTargetX: 0, builderTargetY: 0, builderWait: 0, inputFlags: 0,
        tankShotSound: false, pillShotSound: false, sinkSound: false, builderDeathSound: false
    )
}

@Test func udpSessionSendsAndReceivesCLUpdateRoundTrip() async throws {
    let (listener, port, waiter) = try await startLoopbackUDPListener()
    defer { listener.cancel() }

    let session = try await UDPSession(host: "127.0.0.1", port: port)
    defer { session.cancel() }

    let outgoingHeader = sampleHeader(player: 1, remoteSeqForLocal: 0)
    let outgoing = CLUpdate(header: outgoingHeader, shells: [], explosions: [])
    try await session.sendLocalUpdate(outgoing.encode())

    let harnessConnection = await waiter.wait()
    let receivedBytes = try await receiveOneDatagram(harnessConnection)
    let decoded = CLUpdate.decode(receivedBytes)
    #expect(decoded?.header.player == 1)
    #expect(decoded?.header.tank.x == 100)

    let replyHeader = sampleHeader(player: 1, remoteSeqForLocal: 0)
    let reply = CLUpdate(header: replyHeader, shells: [], explosions: [])
    try await sendDatagram(harnessConnection, reply.encode())

    var state = GameState()
    state.localPlayer = 0
    state.players = (0..<maxPlayers).map { i in
        PlayerState(connected: i == 1, used: i == 1)
    }

    let result = try await session.receiveAndApply(
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
    )

    #expect(result?.seq == 5)
    #expect(state.players[1].tank.x == 100)
    #expect(state.players[1].tank.y == 200)
}
