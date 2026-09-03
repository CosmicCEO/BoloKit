import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Swift-only loopback tests for `joinClient` (Wave 6.4a) -- the first
// tests in this project that can't be differential against a C oracle
// by construction (per D31's own reasoning: the transport mechanism
// itself carries no fidelity obligation, so there's no oracle behavior
// to compare against). These stand up a minimal fake TCP server on
// loopback, using the classic completion-handler `NWListener`/
// `NWConnection` API (test scaffolding only -- the production code under
// test, `joinClient`, is the actual async/`NWConnection` implementation
// per D31/D42) that plays the server's side of the wire script exactly
// (`JoinPreamble` -> status byte -> `BoloPreamble` -> map bytes) and
// confirms `joinClient` parses it correctly end to end.

private enum HarnessError: Error {
    case shortRead
}

/// Buffers exactly one inbound connection so `newConnectionHandler` can be
/// installed *before* `NWListener.start(queue:)` runs -- installing it
/// afterward is rejected by this runtime (observed directly: doing so
/// produces `POSIXErrorCode(rawValue: 22)` on the listener's state
/// transition, alongside `nw_listener_start_block_invoke`'s own "Started
/// without setting either new connection handler..." warning).
private final class ConnectionWaiter: @unchecked Sendable {
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

    /// Synchronous only -- `NSLock.lock()`/`.unlock()` aren't callable
    /// directly from an `async` function body, so all locking happens in
    /// non-async helpers instead.
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

private func receiveExactly(_ connection: NWConnection, _ count: Int) async throws -> [UInt8] {
    try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            guard let data, data.count == count else {
                continuation.resume(throwing: HarnessError.shortRead)
                return
            }
            continuation.resume(returning: Array(data))
        }
    }
}

private func sendBytes(_ connection: NWConnection, _ bytes: [UInt8]) async throws {
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

/// Starts a loopback listener and returns it already `.ready`, plus the
/// port the system assigned it and a waiter for the one inbound
/// connection the caller expects.
private func startLoopbackListener() async throws -> (NWListener, UInt16, ConnectionWaiter) {
    let listener = try NWListener(using: .tcp, on: .any)
    let waiter = ConnectionWaiter()

    // Must be installed before `start(queue:)` -- see `ConnectionWaiter`'s
    // own doc comment for why.
    listener.newConnectionHandler = { connection in
        connection.start(queue: .main)
        waiter.deliver(connection)
    }

    let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
        // Both handlers on this listener run serially on the `.main`
        // queue passed to `start(queue:)` -- never truly concurrent --
        // but the compiler can't prove that for an arbitrary closure type.
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

private func samplePlayerEntries(localName: String) -> [BoloPreamble.PlayerEntry] {
    (0..<maxPlayers).map { i in
        BoloPreamble.PlayerEntry(
            used: i == 0, connected: i == 0, seq: 0, name: i == 0 ? localName : "", host: "", alliance: 0
        )
    }
}

@Test func joinClientCompletesFullHandshakeAgainstFakeServer() async throws {
    let (listener, port, waiter) = try await startLoopbackListener()
    defer { listener.cancel() }

    let mapBytes: [UInt8] = [1, 2, 3, 4, 5]

    async let serverScript: Void = {
        let connection = await waiter.wait()
        let joinBytes = try await receiveExactly(connection, JoinPreamble.wireSize)
        let join = JoinPreamble.decode(joinBytes)
        #expect(join?.name == "Alice")
        #expect(join?.pass == "secret")

        try await sendBytes(connection, [JoinStatusByte.sendingPreamble.rawValue])

        let preamble = BoloPreamble(
            player: 0, hiddenMines: 0, pause: 255, dominationType: 0, baseControl: 60,
            players: samplePlayerEntries(localName: "Alice"), mapLength: UInt32(mapBytes.count)
        )
        try await sendBytes(connection, preamble.encode())
        try await sendBytes(connection, mapBytes)
    }()

    let result = try await joinClient(host: "127.0.0.1", port: port, name: "Alice", pass: "secret")
    try await serverScript

    #expect(result.preamble.player == 0)
    #expect(result.preamble.pause == 255)
    #expect(result.preamble.players[0].name == "Alice")
    #expect(result.mapData == mapBytes)
}

@Test func joinClientThrowsSpecificErrorForEachRejectionStatus() async throws {
    let cases: [(JoinStatusByte, JoinClientError)] = [
        (.badVersion, .badVersion),
        (.disallow, .disallow),
        (.badPassword, .badPassword),
        (.serverFull, .serverFull),
        (.serverTimeLimitReached, .serverTimeLimitReached),
        (.bannedPlayer, .bannedPlayer),
    ]

    for (statusByte, expectedError) in cases {
        let (listener, port, waiter) = try await startLoopbackListener()
        defer { listener.cancel() }

        async let serverScript: Void = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, JoinPreamble.wireSize)
            try await sendBytes(connection, [statusByte.rawValue])
        }()

        do {
            _ = try await joinClient(host: "127.0.0.1", port: port, name: "Bob", pass: "")
            Issue.record("expected \(expectedError) for status byte \(statusByte)")
        } catch let error as JoinClientError {
            #expect(error == expectedError)
        }
        try await serverScript
    }
}

@Test func joinClientThrowsProtocolErrorForUnknownStatusByte() async throws {
    let (listener, port, waiter) = try await startLoopbackListener()
    defer { listener.cancel() }

    async let serverScript: Void = {
        let connection = await waiter.wait()
        _ = try await receiveExactly(connection, JoinPreamble.wireSize)
        try await sendBytes(connection, [255])  // not a real JoinStatusByte
    }()

    do {
        _ = try await joinClient(host: "127.0.0.1", port: port, name: "Bob", pass: "")
        Issue.record("expected serverProtocolError")
    } catch let error as JoinClientError {
        #expect(error == .serverProtocolError)
    }
    try await serverScript
}
