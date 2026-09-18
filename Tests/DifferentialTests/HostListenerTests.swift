import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Tests for `processJoinAttempt`/`JoinAcceptSerializer` (Wave 6.4b). Same
// loopback-TCP harness shape as `HostSessionTests.swift`/`JoinClientTests.
// swift` (D31 -- no C oracle for the transport mechanism itself).

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

private struct FakeJoiner {
    let listener: NWListener
    let clientEnd: NWConnection
    let serverEnd: NWConnection
}

private func makeConnectedPair() async throws -> FakeJoiner {
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

    let clientEnd = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
    clientEnd.start(queue: .main)
    let serverEnd = await waiter.wait()

    return FakeJoiner(listener: listener, clientEnd: clientEnd, serverEnd: serverEnd)
}

private func makeState() -> GameState {
    var state = GameState()
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    return state
}

// MARK: - JoinAcceptSerializer (D49's core primitive)

/// The load-bearing property D49 requires: two concurrent critical
/// sections never overlap, even though each one suspends (`await`)
/// mid-section -- proving genuine serialization, not just "no data race
/// on a single synchronous statement."
@Test func joinAcceptSerializerNeverAllowsOverlappingCriticalSections() async {
    let serializer = JoinAcceptSerializer()
    actor Counter {
        var active = 0
        var maxObservedActive = 0
        var completed = 0
        func enter() {
            active += 1
            maxObservedActive = max(maxObservedActive, active)
        }
        func exit() {
            active -= 1
            completed += 1
        }
    }
    let counter = Counter()

    await withTaskGroup(of: Void.self) { group in
        for _ in 0..<20 {
            group.addTask {
                await serializer.acquire()
                await counter.enter()
                try? await Task.sleep(nanoseconds: 1_000_000)  // 1ms -- long enough to expose overlap if it existed
                await counter.exit()
                await serializer.release()
            }
        }
    }

    #expect(await counter.completed == 20)
    #expect(await counter.maxObservedActive == 1)
}

// MARK: - processJoinAttempt

@Test func processJoinAttemptRejectsBadVersion() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    var state = makeState()
    let table = HostSessionTable()
    let serializer = JoinAcceptSerializer()

    try await sendBytes(link.clientEnd, JoinPreamble(version: 99, name: "Bob", pass: "").encode())
    var fogStates: [Int: FogState] = [:]
    let outcome = await processJoinAttempt(connection: link.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)
    #expect(outcome == .rejected(.badVersion))

    let statusByte = try await receiveExactly(link.clientEnd, 1)
    #expect(statusByte == [JoinStatusByte.badVersion.rawValue])
}

// MARK: - peerAddress (Wave 6.4c, §1)

/// `127.0.0.1`'s raw bytes, reinterpreted as a `UInt32` the exact same way
/// `peerAddress(from:)` does (`IPv4Address.rawValue.withUnsafeBytes {
/// $0.load(as: UInt32.self) }`) -- deliberately not a hardcoded hex
/// literal, since that load is a *native*-endian reinterpretation of
/// network-order bytes (the same thing a real `sin_addr.s_addr` value
/// looks like on any given platform: consistent with itself, "backwards"
/// from dotted-decimal notation on a little-endian machine). What matters
/// is that both sides of every comparison derive the value the same way,
/// not that it matches a human-readable hex constant.
private let loopbackIPv4AsUInt32: UInt32 = {
    let bytes: [UInt8] = [127, 0, 0, 1]
    return bytes.withUnsafeBytes { $0.load(as: UInt32.self) }
}()

@Test func peerAddressExtractsRealLoopbackIPv4AddressAndPort() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    guard let extracted = peerAddress(from: link.serverEnd) else {
        Issue.record("expected a real IPv4 address from a loopback connection")
        return
    }
    #expect(extracted.family == 2)  // AF_INET
    #expect(extracted.addr == loopbackIPv4AsUInt32)
    #expect(extracted.port != 0)  // some real ephemeral client port
}

@Test func processJoinAttemptAcceptsNewPlayerAndSendsFullHandshake() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    var state = makeState()
    let table = HostSessionTable()
    let serializer = JoinAcceptSerializer()

    try await sendBytes(link.clientEnd, JoinPreamble(name: "Alice", pass: "").encode())
    var fogStates: [Int: FogState] = [:]
    let outcome = await processJoinAttempt(connection: link.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)
    #expect(outcome == .accepted(player: 0, rejoin: false))
    #expect(state.players[0].used)
    #expect(state.players[0].connected)
    #expect(state.players[0].name == "Alice")
    #expect(await table.isConnected(0))

    // Wave 6.4c, §1: `dgramaddr` is now seeded from the real TCP
    // connection address (server.c:844), not a zeroed placeholder.
    let seededDgramAddress = await table.dgramAddress(for: 0)
    #expect(seededDgramAddress.family == 2)
    #expect(seededDgramAddress.addr == loopbackIPv4AsUInt32)

    let status = try await receiveExactly(link.clientEnd, 1)
    #expect(status == [JoinStatusByte.sendingPreamble.rawValue])

    let preambleBytes = try await receiveExactly(link.clientEnd, BoloPreamble.wireSize)
    let preamble = BoloPreamble.decode(preambleBytes)
    #expect(preamble?.player == 0)
    // T-9: the joining player's own roster row in the preamble it
    // receives already reads `used`/`connected`, since `applyJoin` runs
    // (server.c:836-853's ordering) before `assembleBoloPreamble` is built.
    #expect(preamble?.players[0].used == true)
    #expect(preamble?.players[0].connected == true)
    #expect(preamble?.players[0].name == "Alice")

    guard let mapLength = preamble?.mapLength, mapLength > 0 else {
        Issue.record("expected a nonzero map length")
        return
    }
    let mapBytes = try await receiveExactly(link.clientEnd, Int(mapLength))
    #expect(Array(mapBytes.prefix(8)) == Array("BMAPBOLO".utf8))

    // Player join broadcast (`sendsrplayerjoin`'s `sendtoall`) reaches the
    // joining player itself too, per T-9's ordering.
    let joinBroadcast = try await receiveExactly(link.clientEnd, SRPlayerJoin.wireSize)
    #expect(SRPlayerJoin.decode(joinBroadcast) == SRPlayerJoin(player: 0, name: "Alice", host: ""))
}

/// v1.5.0 #1: the core security property the host-authoritative fog deviation exists for --
/// a joining player's own map send never contains true ground truth for a mine outside
/// their initial spawn reveal, and does substitute (not omit) a mine inside it, matching
/// `fogTileFor`'s own never-seen-before substitution rule.
/// v1.5.0 #1 (fix pass, `/code-review max` on PR #56): the original version of this test
/// asserted a mine near `state.players[0].tank` got a spawn-reveal at join time -- exactly
/// the bug the review caught: `applyJoin` never sets `tank` (spawn is `runTick`'s job, later),
/// so that reveal was always centered on the `(0, 0)` placeholder, not wherever the test
/// (or production) actually cared about. The fix removes the join-time reveal entirely, so
/// this test now asserts the correct replacement behavior: nothing is revealed at join at
/// all, and every mine -- regardless of proximity to the placeholder tank position --
/// crosses the wire as its never-seen default, never as real ground truth.
@Test func processJoinAttemptRevealsNothingAtJoinTime() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    var state = makeState()
    state.hiddenMines = true
    // Deliberately NOT set -- `state.players[0].tank` stays at its `(0, 0)` default, matching
    // what `applyJoin` actually leaves it at. A reveal computed "around the tank" here would
    // be a regression back to the bug being fixed.
    state.terrain[5, 5] = .minedGrass // near the (0,0) placeholder, if a reveal were wrongly computed there
    state.terrain[200, 200] = .minedGrass // far from anything
    let table = HostSessionTable()
    let serializer = JoinAcceptSerializer()

    try await sendBytes(link.clientEnd, JoinPreamble(name: "Eve", pass: "").encode())
    var fogStates: [Int: FogState] = [:]
    let outcome = await processJoinAttempt(connection: link.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)
    #expect(outcome == .accepted(player: 0, rejoin: false))

    _ = try await receiveExactly(link.clientEnd, 1) // status byte
    let preambleBytes = try await receiveExactly(link.clientEnd, BoloPreamble.wireSize)
    guard let mapLength = BoloPreamble.decode(preambleBytes)?.mapLength, mapLength > 0 else {
        Issue.record("expected a nonzero map length")
        return
    }
    let mapBytes = try await receiveExactly(link.clientEnd, Int(mapLength))

    var decoded = GameState()
    #expect(decodeBMap(mapBytes, into: &decoded))
    // Neither mine crosses the wire as real ground truth -- nothing was revealed at join.
    // (5, 5) is in the mined-sea border ring (mine zone is [10, 245]) -- its never-seen
    // default is `.minedSea` (static, always-known map geometry, `docs/CONSTRAINTS.md`), not
    // plain `.sea`; (200, 200) is in the interior, whose default *is* plain `.sea`.
    #expect(decoded.terrain[5, 5] != .minedGrass)
    #expect(decoded.terrain[200, 200] != .minedGrass)
    #expect(decoded.terrain[5, 5] == .minedSea)
    #expect(decoded.terrain[200, 200] == .sea)

    #expect(fogStates[0] != nil, "the join accept path must seed the joiner's own FogState")
    #expect(fogStates[0]?.fog.allSatisfy { $0 == 0 } == true, "nothing should be marked visible yet at join time")
}

/// Regression test for the review's stale-`FogState`-reuse finding: a slot's prior occupant
/// (or the same identity rejoining) must never carry forward into a fresh join. Player A
/// explores and reveals a mine while occupying slot 0; player B then joins into the same slot
/// (matching the real scenario -- a freed slot getting reused, or a straightforward rejoin)
/// and must start with zero prior vision, not inherit A's.
@Test func processJoinAttemptNeverReusesAPriorOccupantsFogState() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    var state = makeState()
    state.hiddenMines = true
    var fogStates: [Int: FogState] = [:]

    // Simulate player A having previously explored and revealed a mine at (50, 50).
    var priorOccupantFog = FogState()
    priorOccupantFog.fog[50 * 256 + 50] = 3
    priorOccupantFog.seenTiles[50 * 256 + 50] = .minedGrass
    fogStates[0] = priorOccupantFog

    let table = HostSessionTable()
    let serializer = JoinAcceptSerializer()
    try await sendBytes(link.clientEnd, JoinPreamble(name: "B", pass: "").encode())
    let outcome = await processJoinAttempt(connection: link.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)
    #expect(outcome == .accepted(player: 0, rejoin: false))

    #expect(fogStates[0]?.fog[50 * 256 + 50] == 0, "a fresh join must never inherit a prior occupant's fog count")
    #expect(fogStates[0]?.seenTiles[50 * 256 + 50] == .unknown, "a fresh join must never inherit a prior occupant's revealed tiles")
}

@Test func processJoinAttemptSendsFullGroundTruthWhenHiddenMinesIsOff() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    var state = makeState()
    state.hiddenMines = false
    state.terrain[200, 200] = .minedGrass
    let table = HostSessionTable()
    let serializer = JoinAcceptSerializer()

    try await sendBytes(link.clientEnd, JoinPreamble(name: "Frank", pass: "").encode())
    var fogStates: [Int: FogState] = [:]
    _ = await processJoinAttempt(connection: link.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)

    _ = try await receiveExactly(link.clientEnd, 1)
    let preambleBytes = try await receiveExactly(link.clientEnd, BoloPreamble.wireSize)
    guard let mapLength = BoloPreamble.decode(preambleBytes)?.mapLength, mapLength > 0 else {
        Issue.record("expected a nonzero map length")
        return
    }
    let mapBytes = try await receiveExactly(link.clientEnd, Int(mapLength))

    var decoded = GameState()
    #expect(decodeBMap(mapBytes, into: &decoded))
    #expect(decoded.terrain[200, 200] == .minedGrass, "D65 default must be unchanged: full ground truth when hiddenMines is off")
}

@Test func processJoinAttemptRejoinPreservesAllianceAndBroadcastsRejoin() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel(); link.clientEnd.cancel() }

    var state = makeState()
    state.players[0].used = true
    state.players[0].connected = false
    state.players[0].name = "Carol"
    state.players[0].alliance = 0b1010
    let table = HostSessionTable()
    // T-1: `joinplayerserver()`'s `seq = 0` line for the join path is
    // commented out in the C -- only `removeplayer()` resets it. A
    // rejoining player must inherit whatever seq the table already has
    // for that slot, not have it silently zeroed by the join itself.
    await table.setSeq(42, for: 0)
    let serializer = JoinAcceptSerializer()

    try await sendBytes(link.clientEnd, JoinPreamble(name: "Carol", pass: "").encode())
    var fogStates: [Int: FogState] = [:]
    let outcome = await processJoinAttempt(connection: link.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)
    #expect(outcome == .accepted(player: 0, rejoin: true))
    #expect(state.players[0].alliance == 0b1010)  // untouched, not reset to self-only
    #expect(await table.seq(for: 0) == 42)  // T-1: survives the rejoin, untouched

    _ = try await receiveExactly(link.clientEnd, 1)  // status byte
    _ = try await receiveExactly(link.clientEnd, BoloPreamble.wireSize)  // preamble
    // Empty default map: 12-byte preamble+counts + the 4-byte sentinel run
    // (no pills/bases/starts, no non-default terrain -- confirmed shape,
    // `encodeBMapEmptyMapEndsExactlyWithTheSentinelRun`, BMapDecodeTests.swift).
    let mapBytes = try await receiveExactly(link.clientEnd, 16)
    _ = mapBytes

    let rejoinBroadcast = try await receiveExactly(link.clientEnd, SRPlayerRejoin.wireSize)
    #expect(SRPlayerRejoin.decode(rejoinBroadcast)?.player == 0)
}

/// D49's other half: two joins resolve to distinct slots deterministically
/// -- run through the *same* `JoinAcceptSerializer` and `HostSessionTable`
/// a real accept loop would share across connections. Driven sequentially
/// here, matching this whole project's established calling convention for
/// every other `state: inout GameState`-taking async function (one
/// top-level driver awaits each call fully before the next; two calls
/// only ever run in true parallel if a caller deliberately shares the
/// same `inout` binding across concurrent tasks, which is a Swift
/// exclusivity violation regardless of this serializer's own discipline
/// -- `joinAcceptSerializerNeverAllowsOverlappingCriticalSections` above
/// already proves the mutex itself serializes genuinely concurrent
/// callers that protect their own shared state some other way).
@Test func twoSequentialJoinAttemptsResolveToDistinctSlots() async throws {
    let linkA = try await makeConnectedPair()
    let linkB = try await makeConnectedPair()
    defer {
        linkA.listener.cancel(); linkA.clientEnd.cancel()
        linkB.listener.cancel(); linkB.clientEnd.cancel()
    }

    var state = makeState()
    let table = HostSessionTable()
    let serializer = JoinAcceptSerializer()

    try await sendBytes(linkA.clientEnd, JoinPreamble(name: "A", pass: "").encode())
    try await sendBytes(linkB.clientEnd, JoinPreamble(name: "B", pass: "").encode())

    var fogStates: [Int: FogState] = [:]
    let outcomeA = await processJoinAttempt(connection: linkA.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)
    let outcomeB = await processJoinAttempt(connection: linkB.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)

    guard case .accepted(let playerA, _) = outcomeA, case .accepted(let playerB, _) = outcomeB else {
        Issue.record("expected both joins to be accepted, got \(outcomeA) and \(outcomeB)")
        return
    }
    #expect(playerA != playerB)
    #expect(Set([playerA, playerB]) == Set([0, 1]))
}

/// D101 (PARITY finding, PLANNER-approved `53c9d3c`): forces the preamble/map send inside the
/// `.accepted` branch to fail (by fully cancelling the peer -- waiting for real `.cancelled` state
/// first, not just calling `cancel()` and hoping the timing lines up) and confirms the fix keeps
/// `GameState` and `table` in sync, rather than leaking a permanently used+connected slot with no
/// real connection ever attached to it again.
@Test func processJoinAttemptOnSendFailureRevertsConnectedButPreservesUsed() async throws {
    let link = try await makeConnectedPair()
    defer { link.listener.cancel() }

    var state = makeState()
    let table = HostSessionTable()
    let serializer = JoinAcceptSerializer()

    try await sendBytes(link.clientEnd, JoinPreamble(name: "Ghost", pass: "").encode())

    // Wait for the peer to actually reach `.cancelled` -- not just calling `cancel()` and hoping
    // the timing works out -- so the subsequent send inside `processJoinAttempt` is guaranteed to
    // fail, not racing against it.
    await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
        nonisolated(unsafe) var resumed = false
        link.clientEnd.stateUpdateHandler = { state in
            guard !resumed, case .cancelled = state else { return }
            resumed = true
            continuation.resume()
        }
        link.clientEnd.cancel()
    }

    var fogStates: [Int: FogState] = [:]
    let outcome = await processJoinAttempt(connection: link.serverEnd, serializer: serializer, state: &state, table: table, fogStates: &fogStates)
    #expect(outcome == .malformedOrClosed)

    // The real bug (found via B.5c's own dynamic producer exposing it, not previously reachable):
    // `applyJoin` already set both fields `true` before the send failed -- without D101, `used`
    // and `connected` would both still read `true` here, forever, with no real connection able to
    // reach this slot again.
    #expect(state.players[0].used, "used should stay true -- matches the reference's rejoin-eligible-slot model, not a full revert")
    #expect(state.players[0].connected == false, "connected must be reset, or this slot leaks permanently")
    #expect(await table.isConnected(0) == false)
}
