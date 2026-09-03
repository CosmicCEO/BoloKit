import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Swift-only loopback test for `TCPSession`'s `SR*` dispatch loop (Wave
// 6.4a extension, D45) -- same "no C oracle for the transport mechanism
// itself" reasoning as `JoinClientTests.swift`/`UDPSessionTests.swift`
// (D31). Exercises a representative handful of opcodes (not all 34) --
// enough to confirm the dispatch table routes to the right `recvSr*`
// function with correctly-extracted fields, per the plan's own test-plan
// text for this piece.

private enum HarnessError: Error {
    case shortRead
}

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

private func startLoopbackTCPListener() async throws -> (NWListener, UInt16, ConnectionWaiter) {
    let listener = try NWListener(using: .tcp, on: .any)
    let waiter = ConnectionWaiter()

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

private func makeState() -> GameState {
    var state = GameState()
    state.localPlayer = 0
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    state.pills = [Pill(x: 20, y: 20, armour: 5, owner: 0, speed: 40, counter: 0)]
    state.bases = [Base(x: 30, y: 30, armour: 10, owner: 0, shells: 5, mines: 5)]
    state.terrain = .mapDefault()
    return state
}

@Test func tcpSessionDispatchesPlayerJoinAndBuildAndRepairPill() async throws {
    let (listener, port, waiter) = try await startLoopbackTCPListener()
    defer { listener.cancel() }

    let session = try await TCPSession(host: "127.0.0.1", port: port)
    defer { session.cancel() }

    let harness = await waiter.wait()
    var state = makeState()

    try await sendBytes(harness, SRPlayerJoin(player: 2, name: "Bob", host: "h").encode())
    var joinNotified: [Int] = []
    let op1 = try await session.receiveAndDispatchOne(
        state: &state, callbacks: SRDispatchCallbacks(onPlayerStatusChanged: { joinNotified.append($0) })
    )
    #expect(op1 == .playerJoin)
    #expect(state.players[2].used)
    #expect(state.players[2].connected)
    #expect(joinNotified == [2])

    try await sendBytes(harness, SRBuild(x: 10, y: 10, terrain: UInt8(Terrain.wall.rawValue)).encode())
    let op2 = try await session.receiveAndDispatchOne(state: &state)
    #expect(op2 == .build)
    #expect(state.terrain[10, 10] == .wall)

    try await sendBytes(harness, SRRepairPill(pill: 0, armour: 9).encode())
    var pillNotified: [Int] = []
    let op3 = try await session.receiveAndDispatchOne(
        state: &state, callbacks: SRDispatchCallbacks(onPillStatusChanged: { pillNotified.append($0) })
    )
    #expect(op3 == .repairPill)
    #expect(state.pills[0].armour == 9)
    #expect(pillNotified == [0])
}

@Test func tcpSessionDispatchesVariableLengthSendMesgCorrectly() async throws {
    let (listener, port, waiter) = try await startLoopbackTCPListener()
    defer { listener.cancel() }

    let session = try await TCPSession(host: "127.0.0.1", port: port)
    defer { session.cancel() }

    let harness = await waiter.wait()
    var state = makeState()

    try await sendBytes(harness, SRSendMesg(player: 1, to: 255, text: "hello world").encode())
    var received: (UInt8, UInt8, String)?
    let op = try await session.receiveAndDispatchOne(
        state: &state, callbacks: SRDispatchCallbacks(onSendMesg: { p, t, text in received = (p, t, text) })
    )
    #expect(op == .sendMesg)
    #expect(received?.0 == 1)
    #expect(received?.1 == 255)
    #expect(received?.2 == "hello world")

    // Confirm the stream cursor landed exactly after the NUL -- a
    // following message must still decode cleanly, proving no byte was
    // over- or under-consumed by the variable-length read.
    try await sendBytes(harness, SRCoolPill(pill: 0).encode())
    let op2 = try await session.receiveAndDispatchOne(state: &state)
    #expect(op2 == .coolPill)
}

@Test func tcpSessionRoutesTimeLimitAndBaseControlToPlainCallbacksNotState() async throws {
    let (listener, port, waiter) = try await startLoopbackTCPListener()
    defer { listener.cancel() }

    let session = try await TCPSession(host: "127.0.0.1", port: port)
    defer { session.cancel() }

    let harness = await waiter.wait()
    var state = makeState()

    try await sendBytes(harness, SRTimeLimit(timeRemaining: 42).encode())
    var timeLimitValue: UInt16?
    let op1 = try await session.receiveAndDispatchOne(
        state: &state, callbacks: SRDispatchCallbacks(onTimeLimit: { timeLimitValue = $0 })
    )
    #expect(op1 == .timeLimit)
    #expect(timeLimitValue == 42)

    try await sendBytes(harness, SRBaseControl(timeLeft: 7).encode())
    var baseControlValue: UInt16?
    let op2 = try await session.receiveAndDispatchOne(
        state: &state, callbacks: SRDispatchCallbacks(onBaseControl: { baseControlValue = $0 })
    )
    #expect(op2 == .baseControl)
    #expect(baseControlValue == 7)
}
