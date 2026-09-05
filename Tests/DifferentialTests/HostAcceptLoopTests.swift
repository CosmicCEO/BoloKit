import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Tests for `runHostAcceptLoop` (Milestone B.5a, D95). Complements
// `HostListenerTests.swift`'s per-call `processJoinAttempt` coverage by driving
// a *real* `HostListener` end to end through the loop itself, not the
// lower-level fake `NWListener` harness those tests use.

/// A plain reference-type box, mirroring `GameSession`'s own established pattern for handing
/// `&box.state` into an escaping `Task` closure -- `state` itself (a local `var`) can't be
/// captured by an escaping closure as an `inout`, but a class's stored property can be formed
/// as `&box.state` from inside the closure body at call time.
private final class StateBox: @unchecked Sendable {
    var state: GameState
    init(_ state: GameState) { self.state = state }
}

private final class OutcomeBox: @unchecked Sendable {
    var outcomes: [HostJoinOutcome] = []
}

private func makeState() -> GameState {
    var state = GameState()
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    return state
}

private func receiveExactly(_ connection: NWConnection, _ count: Int) async throws -> [UInt8] {
    try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            guard let data, data.count == count else {
                continuation.resume(throwing: HostSessionError.malformedMessage)
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

/// Receiving the handshake reply byte only proves `processJoinAttempt`'s *send* completed --
/// there's still a real, narrow async gap before the surrounding `for await` in
/// `runHostAcceptLoop` actually returns from that call and invokes `onJoinOutcome` (the accepted
/// path still has to `await table.setConnection(...)` after the send). Poll rather than assume
/// synchronous completion.
private func waitForOutcomeCount(_ box: OutcomeBox, _ expected: Int, timeout: TimeInterval = 2) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while box.outcomes.count < expected {
        if Date() > deadline { throw HostSessionError.malformedMessage }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

@Test func runHostAcceptLoopRegistersTwoRealJoinsThroughARealListener() async throws {
    let listener = try await HostListener(port: 0)
    guard let port = listener.port else {
        Issue.record("expected a real bound ephemeral port")
        return
    }

    let box = StateBox(makeState())
    let table = HostSessionTable()
    let outcomeBox = OutcomeBox()

    let loopTask = Task {
        await runHostAcceptLoop(
            listener: listener, state: &box.state, table: table,
            onJoinOutcome: { outcomeBox.outcomes.append($0) }
        )
    }
    defer { loopTask.cancel() }

    let clientA = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    clientA.start(queue: .main)
    try await sendBytes(clientA, JoinPreamble(name: "A", pass: "").encode())
    let statusA = try await receiveExactly(clientA, 1)
    #expect(statusA == [JoinStatusByte.sendingPreamble.rawValue])
    try await waitForOutcomeCount(outcomeBox, 1)  // see the helper's doc comment for why

    let clientB = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    clientB.start(queue: .main)
    try await sendBytes(clientB, JoinPreamble(name: "B", pass: "").encode())
    let statusB = try await receiveExactly(clientB, 1)
    #expect(statusB == [JoinStatusByte.sendingPreamble.rawValue])
    try await waitForOutcomeCount(outcomeBox, 2)

    clientA.cancel()
    clientB.cancel()
    listener.cancel()

    guard outcomeBox.outcomes.count == 2 else {
        Issue.record("expected exactly 2 outcomes, got \(outcomeBox.outcomes)")
        return
    }
    guard case .accepted(let playerA, _) = outcomeBox.outcomes[0],
        case .accepted(let playerB, _) = outcomeBox.outcomes[1]
    else {
        Issue.record("expected both real joins to be accepted, got \(outcomeBox.outcomes)")
        return
    }
    #expect(playerA != playerB)
    #expect(await table.isConnected(playerA))
    #expect(await table.isConnected(playerB))
}

@Test func runHostAcceptLoopRejectionClosesConnectionAndConsumesNoSlot() async throws {
    let listener = try await HostListener(port: 0)
    guard let port = listener.port else {
        Issue.record("expected a real bound ephemeral port")
        return
    }

    let box = StateBox(makeState())
    let table = HostSessionTable()
    let outcomeBox = OutcomeBox()

    let loopTask = Task {
        await runHostAcceptLoop(
            listener: listener, state: &box.state, table: table,
            onJoinOutcome: { outcomeBox.outcomes.append($0) }
        )
    }
    defer { loopTask.cancel() }

    let client = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    client.start(queue: .main)
    try await sendBytes(client, JoinPreamble(version: 99, name: "Bob", pass: "").encode())
    let statusByte = try await receiveExactly(client, 1)
    #expect(statusByte == [JoinStatusByte.badVersion.rawValue])

    client.cancel()
    listener.cancel()

    #expect(outcomeBox.outcomes == [.rejected(.badVersion)])
    #expect(!(await table.isConnected(0)))
}
