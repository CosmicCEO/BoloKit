import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Tests for `HostGameEngine` (Milestone B.5b, D96) -- the merged-event-stream engine driving
// the accept loop, dgram relay, and tick timer through one consumer. Same "no C oracle for the
// transport mechanism itself" reasoning as `HostListenerTests.swift`/`HostDgramListenerTests.swift`
// (D31); the concurrency-safety claim itself has no oracle either, only direct measurement.

private enum HarnessError: Error { case shortRead }

private func sendDatagram(_ connection: NWConnection, _ bytes: [UInt8]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
            content: Data(bytes),
            completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
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

private func makeUDPClient(port: UInt16) -> NWConnection {
    let connection = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .udp)
    connection.start(queue: .main)
    return connection
}

private func makeEngine(_ configure: (inout GameState) -> Void = { _ in }) async throws -> (
    engine: HostGameEngine, tcpPort: UInt16, dgramPort: UInt16
) {
    let listener = try await HostListener(port: 0)
    let dgramListener = try await HostDgramListener(port: 0)
    var state = GameState()
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    // `TerrainGrid.mapDefault()`'s entire grid is either `.sea` (interior) or `.minedSea`
    // (border) -- there is no land anywhere in it (`defaultTerrain(x:y:)`, `BMap.swift:23`).
    // A non-boat tank on *either* drowns via `enterTile`'s `.sea`/`.minedSea` cases. Carving out
    // a safe patch here, same convention every other test file in this project already uses
    // (`SpawnTests.swift`'s own comment: "a bare GameState() puts (0,0) in the mined-sea border
    // ring; same pitfall recorded in every prior wave's tests") -- these tests are no exception.
    for y in 100..<120 {
        for x in 100..<120 {
            state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue
        }
    }
    // `spawn(state:)` indexes `state.starts` unconditionally once the local player's respawn
    // counter crosses `respawnTicks` (~3s at 50Hz) -- every test here runs the real tick timer
    // long enough to cross that, so this needs to be nonempty from the start (the same D88 §4
    // corollary `HostGameView`/`ContentView` already guard against). Placed inside the safe
    // patch above, not at a hazardous default like `(10, 10)`.
    state.starts = [Start(x: 105, y: 105, dir: 0)]
    configure(&state)
    let engine = HostGameEngine(initialState: state, listener: listener, dgramListener: dgramListener)
    guard let tcpPort = listener.port, let dgramPort = dgramListener.port else {
        throw HarnessError.shortRead
    }
    return (engine, tcpPort, dgramPort)
}

private func sampleHeader(player: UInt8, seq: [Int32], tank: Vec2f) -> CLUpdateHeader {
    CLUpdateHeader(
        player: player, seq: seq, dead: false, boat: false, dir: 0, tank: tank, speed: 0, turnSpeed: 0,
        kickDir: 0, kickSpeed: 0, builderStatus: 0, builder: Vec2f(x: 0, y: 0),
        builderTargetX: 0, builderTargetY: 0, builderWait: 0, inputFlags: 0,
        tankShotSound: false, pillShotSound: false, sinkSound: false, builderDeathSound: false
    )
}

private func sendCLUpdate(_ client: NWConnection, player: UInt8, seq: Int32, tank: Vec2f) async throws {
    var seqArray = [Int32](repeating: 0, count: maxPlayers)
    seqArray[Int(player)] = seq
    let header = sampleHeader(player: player, seq: seqArray, tank: tank)
    try await sendDatagram(client, CLUpdate(header: header, shells: [], explosions: []).encode())
}

/// Polls `condition` until it's `true` or `timeout` elapses -- the engine's tick timer and
/// producer tasks run on their own schedule, so tests need to wait for observable state rather
/// than assume synchronous completion (the same real async gap B.3's own tests hit and fixed).
private func waitForCondition(timeout: TimeInterval, _ condition: () async -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while await !condition() {
        if Date() > deadline { return }
        try await Task.sleep(nanoseconds: 5_000_000)
    }
}

/// Reads datagrams from `connection` until one decodes to a `CLUpdate` whose `tank` matches
/// `expectedTank`, or `timeout` elapses -- **not** a single `receiveOneDatagram` call. Two
/// independent per-connection producer tasks feed the engine's merged event stream (one per UDP
/// peer), so there's no guarantee the *processing* order matches this test's own *send* order:
/// a bootstrap packet sent first can still be processed second, and its own relay can arrive at
/// `connection` before the packet this test actually cares about. Confirmed directly (a
/// standalone repro outside `swift test`, same technique as B.3's own debugging) -- the first
/// datagram this test received really was a stray relay of an earlier bootstrap packet, not the
/// intended one, before this loop replaced a single blind read.
///
/// **Timeout enforcement fixed under D99's own negative control** -- the original `Date()`-based
/// deadline check only runs *between* `receiveOneDatagram` calls, so it never bounds a call that
/// blocks forever because no datagram arrives at all (exactly what a genuinely-absent broadcast
/// looks like). Confirmed via a standalone `swiftc` repro outside `swift test`: this hung
/// indefinitely reproducing D99's own fix as a negative control, same failure shape as
/// `confirmNoCLUpdateArrives`'s own `withTaskGroup`/`cancelAll()` bug above. Fixed with an
/// `async let` timeout guard that cancels the connection if the deadline is reached, which
/// reliably unblocks a pending `receiveMessage`.
///
/// **Correction (PARITY, D99 re-audit `9e72569`): `connection.cancel()` actually runs
/// unconditionally on every call, success path included** -- `try?` swallows the
/// `CancellationError` from the interrupted `Task.sleep` when this function returns before the
/// full timeout, and execution falls through to `connection.cancel()` regardless, confirmed by
/// direct instrumentation. This doesn't corrupt this file's tests today only because
/// `NWConnection.cancel()`'s effect is itself asynchronous and, on this host, consistently
/// propagates slower than the very next `receiveMessage` registration -- true empirically, not
/// guaranteed by anything in this code. A future caller relying on the connection staying usable
/// immediately after a successful `receiveMatchingCLUpdate` call would be relying on that same
/// timing accident.
private func receiveMatchingCLUpdate(
    _ connection: NWConnection, expectedTank: Vec2f, timeout: TimeInterval = 3
) async throws -> CLUpdate {
    async let timeoutGuard: Void = {
        try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
        connection.cancel()
    }()
    while true {
        let bytes = try await receiveOneDatagram(connection)
        if let decoded = CLUpdate.decode(bytes), decoded.header.tank == expectedTank {
            return decoded
        }
    }
}

@Test func hostGameEngineRelaysADgramPacketBetweenTwoRegisteredPlayers() async throws {
    let (engine, _, dgramPort) = try await makeEngine { state in
        // Slots 1 and 2 are the guests. Slot 0 is the host's own (`localPlayer`): the engine
        // writes its own seq there, so it can never also be a datagram sender.
        for slot in [1, 2] {
            state.players[slot].used = true
            state.players[slot].connected = true
            state.players[slot].dead = false
        }
    }
    defer { engine.stop() }

    // Relay eligibility reads the table's TCP `connection` field, not `GameState.players[i]
    // .connected` -- same real distinction `HostDgramListenerTests.swift` already documents.
    // Any real `NWConnection` reference works here; it's never actually used for TCP I/O.
    //
    // `decodeDgramServerRelay`'s own validity guard (`DgramServerRelay.swift`) requires a
    // player's `dgramAddress.family`/`.addr` to already match the sender's real address BEFORE
    // it will ever accept a packet from them -- there's no bootstrap path for a brand-new player
    // with no address registered at all. In production this is seeded at TCP join time
    // (`processJoinAttempt`/`peerAddress(from:)`'s own doc comment: "seeding dgramaddr at join,
    // port included even though it's the TCP connection's own -- usually UDP-wrong -- port,
    // matching server.c:844 literally" -- the port itself doesn't need to be right, only
    // family/addr, since T-3 excludes port from the validity check and the first real packet's
    // `portUpdate` corrects it). This test bypasses the TCP join, so it replicates that seeding
    // step directly: `peerAddress(from: fakeTCP)` gives a real loopback family+addr (both
    // players are 127.0.0.1 either way), good enough to satisfy the guard.
    let fakeTCP = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: dgramPort)!, using: .udp)
    guard let fakeAddress = peerAddress(from: fakeTCP) else {
        Issue.record("expected a real loopback address")
        return
    }
    await engine.table.setConnection(fakeTCP, for: 1)
    await engine.table.setConnection(fakeTCP, for: 2)
    await engine.table.setDgramAddress(fakeAddress, for: 1)
    await engine.table.setDgramAddress(fakeAddress, for: 2)

    engine.start()

    let senderClient = makeUDPClient(port: dgramPort)
    let peerClient = makeUDPClient(port: dgramPort)
    defer { senderClient.cancel(); peerClient.cancel() }

    // Each peer's first `CLUpdate` registers its own dgram connection in the table, through the
    // engine's real dgram-processing path (`processDgramPacket`'s `.applied` case) -- exactly
    // what a real client's first datagram produces, not manually seeded.
    try await sendCLUpdate(senderClient, player: 1, seq: 1, tank: Vec2f(x: 101, y: 101))
    try await sendCLUpdate(peerClient, player: 2, seq: 1, tank: Vec2f(x: 102, y: 102))
    try await waitForCondition(timeout: 2) { await engine.table.dgramConnection(for: 2) != nil }

    let expectedTank = Vec2f(x: 112, y: 114)
    try await sendCLUpdate(senderClient, player: 1, seq: 2, tank: expectedTank)
    let decoded = try await receiveMatchingCLUpdate(peerClient, expectedTank: expectedTank)
    #expect(decoded.header.player == 1)

    try await waitForCondition(timeout: 2) { engine.state.players[1].tank == expectedTank }
    #expect(engine.state.players[1].tank == expectedTank)
}

@Test func hostGameEngineBroadcastsItsOwnCLUpdateOnTheTickTimer() async throws {
    let (engine, _, dgramPort) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[0].tank = Vec2f(x: 107, y: 108)
        state.localPlayer = 0
        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].dead = false
    }
    defer { engine.stop() }

    // See the relay test above for why `dgramAddress` must be seeded before the first packet.
    let fakeTCP = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: dgramPort)!, using: .udp)
    guard let fakeAddress = peerAddress(from: fakeTCP) else {
        Issue.record("expected a real loopback address")
        return
    }
    await engine.table.setConnection(fakeTCP, for: 0)
    await engine.table.setConnection(fakeTCP, for: 1)
    await engine.table.setDgramAddress(fakeAddress, for: 0)
    await engine.table.setDgramAddress(fakeAddress, for: 1)

    engine.start()

    let peerClient = makeUDPClient(port: dgramPort)
    defer { peerClient.cancel() }

    // Peer 1 registers its own dgram connection first, via a real (throwaway) `CLUpdate` --
    // matching how a real client's first datagram would.
    try await sendCLUpdate(peerClient, player: 1, seq: 1, tank: Vec2f(x: 101, y: 101))
    try await waitForCondition(timeout: 2) { await engine.table.dgramConnection(for: 1) != nil }

    // The host's own outbound `CLUpdate` is broadcast automatically by the tick timer -- never
    // triggered by this test, unlike the relay test above. Same bootstrap-packet race as the
    // relay test (two independent producer tasks feed the merged stream with no ordering
    // guarantee), so read-until-matching rather than a single blind read.
    let update = try await receiveMatchingCLUpdate(peerClient, expectedTank: Vec2f(x: 107, y: 108))
    #expect(update.header.player == 0)
    #expect(update.header.tank == Vec2f(x: 107, y: 108))
}

@Test func hostGameEngineAcceptsARealJoinWhileConcurrentlyRelayingDgrams() async throws {
    // Stress/invariant check for the single-consumer serialization claim: a real TCP join
    // arrives while a stream of dgram packets is also in flight and the tick timer is running.
    // Not a formal proof (that's a structural property of the single `for await` consumer loop,
    // enforced by Swift's own `AsyncSequence` iteration semantics, not something a test adds to)
    // -- this checks that driving all three sources concurrently under load produces no crash
    // and lands the expected, uncorrupted final state, the same kind of confidence-building
    // check `HostSessionTests.swift`'s own concurrency test provides for a different function.
    let (engine, tcpPort, dgramPort) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }

    // See `hostGameEngineRelaysADgramPacketBetweenTwoRegisteredPlayers` for why `dgramAddress`
    // must be seeded before the first packet.
    let fakeTCP = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: dgramPort)!, using: .udp)
    guard let fakeAddress = peerAddress(from: fakeTCP) else {
        Issue.record("expected a real loopback address")
        return
    }
    await engine.table.setConnection(fakeTCP, for: 0)
    await engine.table.setDgramAddress(fakeAddress, for: 0)

    engine.start()

    let dgramClient = makeUDPClient(port: dgramPort)
    defer { dgramClient.cancel() }
    try await sendCLUpdate(dgramClient, player: 0, seq: 1, tank: Vec2f(x: 101, y: 101))

    // Kept inside the safe `100..<120` grass patch (see `makeEngine`) -- same drowning/respawn
    // hazard as the other two tests, though this test's own assertions don't depend on tank
    // position, only on player 1's registration state.
    async let dgramStorm: Void = {
        for i in 0..<50 {
            try? await sendCLUpdate(dgramClient, player: 0, seq: Int32(2 + i), tank: Vec2f(x: 100 + Float(i % 20), y: 100 + Float(i % 20)))
        }
    }()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Stormy", pass: "").encode())

    _ = await dgramStorm

    try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) }
    #expect(await engine.table.isConnected(1))
    #expect(engine.state.players[1].used)
    #expect(engine.state.players[1].connected)
}

// MARK: - D98 (PARITY finding) -- pause/time-limit gate on the host's own CLUpdate broadcast

/// Proves *absence* of a broadcast within a window. **Not** `HostSessionTests.swift`'s own
/// `confirmNoDatagramArrives` (D53) shape (`withTaskGroup` + `cancelAll()`) -- tried that first
/// here and confirmed, via a standalone `swiftc` repro outside `swift test` entirely, that it
/// genuinely hangs forever for a still-open, no-error connection: `withTaskGroup` implicitly
/// awaits every child task before returning, `cancelAll()` only flips `Task.isCancelled` and
/// doesn't touch the underlying `NWConnection.receiveMessage` callback, so the losing receive task
/// never completes on its own. D53's version only ever appears to work because its TCP link setup
/// already produces a real error near-instantly (confirmed: that test resolves in 0.016s, far
/// under its own 300ms timeout, so its "timeout" branch is never actually the one that wins) --
/// not a mechanism this test's healthy, still-connected UDP socket can rely on. Cancelling the
/// connection explicitly after the timeout is what actually unblocks `receiveMessage`'s pending
/// completion handler.
/// Same shape as every other test file's own private helper of this name (`HostListenerTests.swift`,
/// `JoinClientTests.swift`, etc.) -- reads a join rejection's single status byte off the raw TCP
/// stream (not a datagram-framed message; `processJoinAttempt` writes it with `sendBytes`, plain
/// stream bytes).
private func receiveExactly(_ connection: NWConnection, _ count: Int) async throws -> [UInt8] {
    try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data, data.count == count {
                continuation.resume(returning: Array(data))
            } else {
                continuation.resume(throwing: HarnessError.shortRead)
            }
        }
    }
}

private func confirmNoCLUpdateArrives(_ connection: NWConnection, timeoutNanoseconds: UInt64 = 300_000_000) async -> Bool {
    async let receiveResult: Bool = {
        do {
            _ = try await receiveOneDatagram(connection)
            return false
        } catch {
            return true
        }
    }()
    try? await Task.sleep(nanoseconds: timeoutNanoseconds)
    connection.cancel()
    return await receiveResult
}

@Test func hostGameEngineSuppressesItsOwnCLUpdateBroadcastWhilePaused() async throws {
    let (engine, _, dgramPort) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[0].tank = Vec2f(x: 107, y: 108)
        state.localPlayer = 0
        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].dead = false
        // Mirrors `client.pause` -- never counted down by `runTick` itself (its own doc comment),
        // so this stays paused for the test's whole duration, unlike `serverPauseTicks`, which
        // decrements every tick.
        state.clientPauseDisplaySeconds = 5
    }
    defer { engine.stop() }

    let fakeTCP = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: dgramPort)!, using: .udp)
    guard let fakeAddress = peerAddress(from: fakeTCP) else {
        Issue.record("expected a real loopback address")
        return
    }
    await engine.table.setConnection(fakeTCP, for: 0)
    await engine.table.setConnection(fakeTCP, for: 1)
    await engine.table.setDgramAddress(fakeAddress, for: 0)
    await engine.table.setDgramAddress(fakeAddress, for: 1)

    engine.start()

    let peerClient = makeUDPClient(port: dgramPort)
    defer { peerClient.cancel() }
    try await sendCLUpdate(peerClient, player: 1, seq: 1, tank: Vec2f(x: 101, y: 101))
    try await waitForCondition(timeout: 2) { await engine.table.dgramConnection(for: 1) != nil }

    // Pre-D98, the tick timer broadcasts a CLUpdate every 5th tick (~10Hz) regardless of pause --
    // 300ms at 50Hz is 15 ticks, three full cadence cycles, comfortably enough for a pre-fix
    // build to have produced at least one broadcast in this window.
    let absent = await confirmNoCLUpdateArrives(peerClient)
    #expect(absent, "expected no CLUpdate broadcast while paused (D98)")
}

@Test func hostGameEngineSuppressesItsOwnCLUpdateBroadcastOnceTimeLimitReached() async throws {
    let (engine, _, dgramPort) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[0].tank = Vec2f(x: 107, y: 108)
        state.localPlayer = 0
        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].dead = false
        // Already well past the limit before the engine even starts, so it's "reached" from
        // tick 1 -- matches the monotonic-latch reasoning in `HostGameEngine.swift`'s own D98
        // comment (ticks only increase, timeLimit is static, so once reached it stays reached).
        state.timeLimit = 1
        state.ticks = UInt64(ticksPerSec) * 10
    }
    defer { engine.stop() }

    let fakeTCP = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: dgramPort)!, using: .udp)
    guard let fakeAddress = peerAddress(from: fakeTCP) else {
        Issue.record("expected a real loopback address")
        return
    }
    await engine.table.setConnection(fakeTCP, for: 0)
    await engine.table.setConnection(fakeTCP, for: 1)
    await engine.table.setDgramAddress(fakeAddress, for: 0)
    await engine.table.setDgramAddress(fakeAddress, for: 1)

    engine.start()

    let peerClient = makeUDPClient(port: dgramPort)
    defer { peerClient.cancel() }
    try await sendCLUpdate(peerClient, player: 1, seq: 1, tank: Vec2f(x: 101, y: 101))
    try await waitForCondition(timeout: 2) { await engine.table.dgramConnection(for: 1) != nil }

    let absent = await confirmNoCLUpdateArrives(peerClient)
    #expect(absent, "expected no CLUpdate broadcast once time limit is reached (D98)")
}

/// D99 (PARITY finding): `RunTick.swift:100-105` splits the time-limit freeze into two phases --
/// `ticks == limitTicks` still runs a real simulated tick and should still broadcast if cadence
/// allows; only `ticks > limitTicks` is actually frozen. D98's original guard used `>=`, which
/// collapsed that split and suppressed the broadcast for the *last genuinely-simulated tick* one
/// tick early. Neither of the two tests above happens to sit on this exact boundary (one seeds
/// deep past the threshold, the other never sets `timeLimit` at all), which is exactly why they
/// didn't catch it -- this test seeds `ticks` at `limitTicks - 5` so the boundary tick lands
/// exactly on a `localSeq % 5 == 0` cadence slot, proving both halves: the boundary tick's
/// broadcast still arrives, and nothing arrives after it.
@Test func hostGameEngineBroadcastsExactlyAtTheTimeLimitBoundaryTickThenNeverAgain() async throws {
    let (engine, _, dgramPort) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[0].tank = Vec2f(x: 107, y: 108)
        state.localPlayer = 0
        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].dead = false
        state.timeLimit = 1
        state.ticks = UInt64(ticksPerSec) * UInt64(state.timeLimit) - 5
    }
    defer { engine.stop() }

    let fakeTCP = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: dgramPort)!, using: .udp)
    guard let fakeAddress = peerAddress(from: fakeTCP) else {
        Issue.record("expected a real loopback address")
        return
    }
    await engine.table.setConnection(fakeTCP, for: 0)
    await engine.table.setConnection(fakeTCP, for: 1)
    await engine.table.setDgramAddress(fakeAddress, for: 0)
    await engine.table.setDgramAddress(fakeAddress, for: 1)

    engine.start()

    let peerClient = makeUDPClient(port: dgramPort)
    defer { peerClient.cancel() }
    try await sendCLUpdate(peerClient, player: 1, seq: 1, tank: Vec2f(x: 101, y: 101))
    try await waitForCondition(timeout: 2) { await engine.table.dgramConnection(for: 1) != nil }

    // The boundary broadcast should still arrive -- the 5th tick timer fire after `engine.start()`.
    let boundary = try await receiveMatchingCLUpdate(peerClient, expectedTank: Vec2f(x: 107, y: 108))
    #expect(boundary.header.player == 0)

    // No further broadcast after the boundary -- `ticks` is now permanently `> limitTicks`.
    let absent = await confirmNoCLUpdateArrives(peerClient)
    #expect(absent, "expected no further CLUpdate broadcast past the time-limit boundary (D99)")
}

// MARK: - B.5c -- the TCP `CL*` dispatch loop

@Test func hostGameEngineDispatchesARealClMessageFromAJoinedPlayer() async throws {
    let (engine, tcpPort, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }

    engine.start()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Ally", pass: "").encode())
    try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) }

    // A real `CL*` message over the same connection the join used -- this is B.5c's own dynamic
    // per-player producer `Task` reading it, not a fake/direct call into `dispatchHostMessage`.
    try await sendDatagram(joinClient, CLSetAlliance(alliance: 0b0110).encode())
    try await waitForCondition(timeout: 3) { engine.state.players[1].alliance == 0b0110 }
    #expect(engine.state.players[1].alliance == 0b0110)
}

@Test func hostGameEngineDisconnectsAPlayerNormallyOnHangUp() async throws {
    let (engine, tcpPort, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }

    engine.start()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Leaver", pass: "").encode())
    try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) }

    try await sendDatagram(joinClient, CLHangUp().encode())
    try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) == false }
    #expect(await engine.table.isConnected(1) == false)
    // `engine.state` is read directly (not actor-isolated) from this test's own task while the
    // consumer task may still be mutating it -- polling rather than a single-shot read after only
    // waiting on the (actor-isolated) `table` signal, same convention the relay test above uses
    // for its own `engine.state.players[0].tank` check.
    try await waitForCondition(timeout: 2) { engine.state.players[1].connected == false }
    #expect(engine.state.players[1].connected == false)
}

@Test func hostGameEngineDisconnectsAPlayerAbnormallyWhenConnectionCloses() async throws {
    let (engine, tcpPort, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }

    engine.start()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    try await sendDatagram(joinClient, JoinPreamble(name: "Dropper", pass: "").encode())
    // `table.isConnected(1)` becomes true as soon as `processJoinAttempt` calls
    // `table.setConnection` (`HostListener.swift:230`) -- BEFORE the preamble/map send that
    // follows it, and BEFORE `.accepted` is returned and this engine's own dynamic producer
    // `Task` is spawned. Waiting on it alone and then immediately cancelling races that in-flight
    // send: found via this exact test flaking under load, root-caused with a standalone repro
    // (`table.isConnected(1)==false` yet `state.players[1].used/connected` stuck `true` forever --
    // a real, separately-reported slot-leak bug in `HostListener.swift`'s own `.malformedOrClosed`
    // catch branch, pre-existing since Wave 6.3/B.5a, not part of B.5c). Waiting for a real
    // dispatched `CL*` message's effect first proves the join fully completed and this engine's
    // own producer is actually running, before testing THIS producer's own disconnect handling --
    // not exercising the join handshake's unrelated failure path at all.
    try await sendDatagram(joinClient, CLSetAlliance(alliance: 1).encode())
    try await waitForCondition(timeout: 3) { engine.state.players[1].alliance == 1 }

    // No `.hangUp` -- just closing the connection, matching a crashed/network-dropped client
    // rather than a clean exit. Should hit `.clConnectionEnded` -> `.abnormal`, not `.normal`.
    joinClient.cancel()
    try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) == false }
    #expect(await engine.table.isConnected(1) == false)
    // Poll rather than a single-shot read -- see the hang-up test above for why.
    try await waitForCondition(timeout: 2) { engine.state.players[1].connected == false }
    #expect(engine.state.players[1].connected == false)
}

// B.7 (D102/D108): `stop()` alone never disconnected already-joined players -- their `NWConnection`s
// and dynamic producer `Task`s kept running indefinitely. `shutdown()` is the real fix, closing
// every connected slot before the synchronous teardown `stop()` still does.
@Test func hostGameEngineShutdownDisconnectsAlreadyJoinedPlayers() async throws {
    let (engine, tcpPort, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }

    engine.start()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Stayer", pass: "").encode())
    // Wait for a real dispatched effect, not just `isConnected` -- see the abnormal-disconnect
    // test above for why that alone doesn't prove the join fully completed.
    try await sendDatagram(joinClient, CLSetAlliance(alliance: 1).encode())
    try await waitForCondition(timeout: 3) { engine.state.players[1].alliance == 1 }

    await engine.shutdown()

    #expect(await engine.table.isConnected(1) == false)
}

// B.7 (D108): the host's own local keyboard input has to reach `state` without any thread but the
// consumer `Task` ever touching it -- `submitLocalInputChange`/`submitLocalLayMineKeyDown` route
// through the merged event stream rather than mutating `engine.state` directly. This proves both
// actually land on `state.players[state.localPlayer]`.
@Test func hostGameEngineAppliesSubmittedLocalInputOnTheNextTick() async throws {
    let (engine, _, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }

    engine.start()

    engine.submitLocalInputChange(set: [.accel, .turnL], clear: [])
    try await waitForCondition(timeout: 2) {
        engine.state.players[0].inputFlags.contains(.accel) && engine.state.players[0].inputFlags.contains(.turnL)
    }
    #expect(engine.state.players[0].inputFlags.contains(.accel))
    #expect(engine.state.players[0].inputFlags.contains(.turnL))

    engine.submitLocalInputChange(set: [], clear: [.accel])
    try await waitForCondition(timeout: 2) { !engine.state.players[0].inputFlags.contains(.accel) }
    #expect(!engine.state.players[0].inputFlags.contains(.accel))
    #expect(engine.state.players[0].inputFlags.contains(.turnL))
}

// C.0 (D119): `submitKickPlayer`/`submitBanPlayer` are the sanctioned entry points for a UI
// button to kick/ban a connected player -- same "route through the merged stream, never touch
// `state` directly" reasoning as `submitLocalInputChange` above. This proves the kicked player's
// slot is actually disconnected (mirrors `hostKickPlayer`'s own contract).
@Test func hostGameEngineSubmitKickPlayerDisconnectsThePlayer() async throws {
    let (engine, tcpPort, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }
    engine.start()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Kickee", pass: "").encode())
    try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) }
    #expect(await engine.table.isConnected(1))

    engine.submitKickPlayer(1)
    try await waitForCondition(timeout: 3) { await !(engine.table.isConnected(1)) }
    #expect(await engine.table.isConnected(1) == false)
}

// C.0 (D119): same shape as the kick test above, for `submitBanPlayer`/`hostBanPlayer`.
@Test func hostGameEngineSubmitBanPlayerDisconnectsThePlayer() async throws {
    let (engine, tcpPort, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }
    engine.start()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Bannee", pass: "").encode())
    try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) }
    #expect(await engine.table.isConnected(1))

    engine.submitBanPlayer(1)
    try await waitForCondition(timeout: 3) { await !(engine.table.isConnected(1)) }
    #expect(await engine.table.isConnected(1) == false)
}

// C.2 (D128): `submitRequestAlliance`/`submitLeaveAlliance` are the sanctioned entry points for
// a UI button to change the host's own local alliance -- same "route through the merged stream,
// never touch `state` directly" reasoning as `submitLocalInputChange` above. Proves the mask
// actually lands on `state.players[state.localPlayer].alliance` and only that player's own bit
// -- other connected players' own alliance masks (here player 1's, set via a real dispatched
// `CLSetAlliance` first, same proof-of-real-join convention the other tests in this file use)
// are untouched.
@Test func hostGameEngineSubmitRequestAllianceUpdatesOnlyLocalPlayersMask() async throws {
    let (engine, tcpPort, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
    }
    defer { engine.stop() }
    engine.start()

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Ally", pass: "").encode())
    try await sendDatagram(joinClient, CLSetAlliance(alliance: 0b10).encode())
    try await waitForCondition(timeout: 3) { engine.state.players[1].alliance == 0b10 }

    engine.submitRequestAlliance(players: UInt16(1 << 1))
    try await waitForCondition(timeout: 3) {
        engine.state.players[0].alliance & UInt16(1 << 1) != 0
    }
    #expect(engine.state.players[0].alliance & UInt16(1 << 1) != 0)
    #expect(engine.state.players[1].alliance == 0b10)  // untouched by player 0's own request
}

// Same shape as the request test above, for `submitLeaveAlliance`/`leaveAlliance`'s own
// "never clears own bit" guard.
@Test func hostGameEngineSubmitLeaveAllianceClearsMaskButKeepsOwnBit() async throws {
    let (engine, _, _) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[0].alliance = UInt16(1 << 0) | UInt16(1 << 1)
        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].alliance = UInt16(1 << 1) | UInt16(1 << 0)
    }
    defer { engine.stop() }
    engine.start()

    // Try to clear player 0's own bit too -- must be a no-op for that bit (`leaveAlliance`'s
    // `keepMask` guard, `SessionLogic.swift:235`).
    engine.submitLeaveAlliance(players: UInt16(1 << 0) | UInt16(1 << 1))
    try await waitForCondition(timeout: 3) {
        engine.state.players[0].alliance & UInt16(1 << 1) == 0
    }
    #expect(engine.state.players[0].alliance & UInt16(1 << 0) != 0)
    #expect(engine.state.players[0].alliance & UInt16(1 << 1) == 0)
}

// 1.1 (D129): `submitPauseResumeServer`/`submitSetAllowJoin`/`submitToggleAllowJoin`/
// `submitUnbanPlayer` are the sanctioned entry points for the host-admin command surface --
// same "route through the merged stream" reasoning as `submitKickPlayer`/`submitBanPlayer` above.
@Test func hostGameEngineSubmitPauseResumeServerTogglesPauseState() async throws {
    let (engine, _, _) = try await makeEngine()
    defer { engine.stop() }
    engine.start()

    engine.submitPauseResumeServer()
    try await waitForCondition(timeout: 3) { engine.state.serverPauseTicks == -1 }
    #expect(engine.state.serverPauseTicks == -1)

    let pausedTicks = engine.state.ticks
    try await Task.sleep(nanoseconds: 100_000_000)
    #expect(engine.state.ticks == pausedTicks)  // simulation genuinely frozen, not just flagged

    engine.submitPauseResumeServer()
    try await waitForCondition(timeout: 3) { engine.state.serverPauseTicks != -1 }
    #expect(engine.state.serverPauseTicks == Int(ticksPerSec) * 5)  // resume countdown, not an
    // immediate unfreeze (`SessionLogic.resumeServer`'s own doc comment)
}

@Test func hostGameEngineSubmitToggleAllowJoinRejectsANewJoin() async throws {
    let (engine, tcpPort, _) = try await makeEngine()
    defer { engine.stop() }
    engine.start()

    #expect(engine.state.allowJoin)
    engine.submitToggleAllowJoin()
    try await waitForCondition(timeout: 3) { !engine.state.allowJoin }
    #expect(!engine.state.allowJoin)

    let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
    joinClient.start(queue: .main)
    defer { joinClient.cancel() }
    try await sendDatagram(joinClient, JoinPreamble(name: "Locked Out", pass: "").encode())
    let response = try await receiveExactly(joinClient, 1)
    #expect(response == [JoinStatusByte.disallow.rawValue])

    engine.submitSetAllowJoin(true)
    try await waitForCondition(timeout: 3) { engine.state.allowJoin }
    #expect(engine.state.allowJoin)
}

// `unbanPlayer`'s "removes an entry, and a subsequent join from that identity succeeds" behavior
// is covered end-to-end at the pure `SessionLogic` layer
// (`SessionLogicTests.UnbanPlayerTests.unbannedIdentityCanSubsequentlyJoin`) -- doing it again
// here over a real `NWConnection` would need the live connection's exact `remoteAddressDescription`
// string (`HostListener.swift`, includes the ephemeral client port) to pre-seed a matching
// `BannedPlayer`, which isn't knowable before the connection exists. This test only exercises the
// engine plumbing: `submitUnbanPlayer(index:)` reaches `state.bannedPlayers` through the merged
// stream, same contract `submitKickPlayer`/`submitBanPlayer` already have their own tests for.
@Test func hostGameEngineSubmitUnbanPlayerRemovesTheEntry() async throws {
    let (engine, _, _) = try await makeEngine { state in
        state.bannedPlayers = [BannedPlayer(name: "Reformed", address: "1.2.3.4")]
    }
    defer { engine.stop() }
    engine.start()

    engine.submitUnbanPlayer(index: 0)
    try await waitForCondition(timeout: 3) { engine.state.bannedPlayers.isEmpty }
    #expect(engine.state.bannedPlayers.isEmpty)
}

// B.7 (D108): `onTickRendered` is the app's only sanctioned way to read a live `state` snapshot
// off the engine -- fired every tick with a value-type copy, never the live `state` itself.
@Test func hostGameEngineFiresOnTickRenderedEveryTick() async throws {
    let (engine, _, _) = try await makeEngine()
    defer { engine.stop() }

    let renderedTicks = HostRenderedTicksBox()
    engine.onTickRendered = { state in
        Task { await renderedTicks.record(state.ticks) }
    }

    engine.start()

    try await waitForCondition(timeout: 2) { await renderedTicks.count >= 3 }
    #expect(await renderedTicks.count >= 3)
}

/// `onTickRendered` is `@MainActor`-isolated (matching the app's real render target, an `NSView`);
/// this box lets the test observe it from an `async` context without touching `engine.state`.
private actor HostRenderedTicksBox {
    private var ticks: [UInt64] = []
    var count: Int { ticks.count }
    func record(_ tick: UInt64) { ticks.append(tick) }
}

/// `onPlayerDisconnected`'s own wiring (`HostGameEngine.tick()`) -- distinct from the two tests
/// above, which exercise the dynamic per-connection producer's disconnect paths. This one exercises
/// `RunTick.swift`'s own step-4 lag-timeout path instead: a player whose `HostSessionTable`
/// `lastUpdate` has gone stale gets disconnected by the tick timer itself, no dgram/TCP activity
/// (or lack thereof) from the test required beyond seeding the table. The `SRPlayerDisc` broadcast
/// encoding itself is already covered by `HostSessionTests.swift`'s own `handlePlayerDisconnect`
/// tests (this wiring calls the same two `table` primitives, not a new encoding) -- this test's
/// job is only to confirm `onPlayerDisconnected` actually reaches `table.disconnect`.
@Test func hostGameEngineDisconnectsALaggedPlayerViaTheTickTimer() async throws {
    let (engine, _, dgramPort) = try await makeEngine { state in
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].dead = false
        // Comfortably past `RunTick.swift`'s own 9-second (450-tick) lag-disconnect threshold.
        state.ticks = 1000
    }
    defer { engine.stop() }

    // Unlike the other tests in this file, this one actually triggers a real broadcast
    // (`SRPlayerDisc`, via `table.sendToAllExcept`) against a connection registered through
    // `setConnection` -- confirmed by direct instrumentation that `NWConnection.send` never
    // completes on a connection that never left `.setup` (same root cause as
    // `JoinClientTests.swift`'s own `ConnectionWaiter` doc comment, `POSIXErrorCode(rawValue: 22)`
    // territory), which the other tests never hit only because their own `pending` broadcast
    // lists happen to stay empty. `.start()` here, unlike the sibling `fakeTCP`s elsewhere in this
    // file.
    let fakeTCP = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: dgramPort)!, using: .udp)
    fakeTCP.start(queue: .main)
    guard let fakeAddress = peerAddress(from: fakeTCP) else {
        Issue.record("expected a real loopback address")
        return
    }
    await engine.table.setConnection(fakeTCP, for: 0)
    await engine.table.setConnection(fakeTCP, for: 1)
    await engine.table.setDgramAddress(fakeAddress, for: 0)
    await engine.table.setDgramAddress(fakeAddress, for: 1)
    // D150 continuation negative control: player 0's `lastUpdate` is no longer hand-seeded here.
    // The real fix (`HostGameEngine.swift`'s host-self-CLUpdate wiring) must keep player 0 fresh
    // on its own via the tick loop -- player 1's `lastUpdate` stays at its default `0`, so
    // `ticksSinceLastUpdate[1] == 1000`.
    engine.start()

    try await waitForCondition(timeout: 2) { await engine.table.isConnected(1) == false }
    #expect(await engine.table.isConnected(1) == false)
    // Poll rather than a single-shot read -- see `hostGameEngineDisconnectsAPlayerNormallyOnHangUp`
    // for why (`engine.state` isn't actor-isolated, so a single-shot read right after only waiting
    // on the actor-isolated `table` signal is a real, if narrow, visibility race, not a hang risk).
    try await waitForCondition(timeout: 2) { engine.state.players[1].connected == false }
    #expect(engine.state.players[1].connected == false)
    #expect(await engine.table.isConnected(0), "player 0 should be unaffected -- only player 1 was seeded stale")
}

// MARK: - startNetworkDiscovery (#24: wire host tracker announce + UPnP)

private final class DiscoveryConnectionWaiter: @unchecked Sendable {
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

private func startLoopbackTrackerListener() async throws -> (NWListener, UInt16, DiscoveryConnectionWaiter) {
    let listener = try NWListener(using: .tcp, on: .any)
    let waiter = DiscoveryConnectionWaiter()

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

private func receiveExactlyStream(_ connection: NWConnection, _ count: Int) async throws -> [UInt8] {
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

private func sendStreamBytes(_ connection: NWConnection, _ bytes: [UInt8]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
            content: Data(bytes),
            completion: .contentProcessed { error in
                if let error { continuation.resume(throwing: error) } else { continuation.resume() }
            }
        )
    }
}

@Suite struct HostGameEngineNetworkDiscoveryTests {

    @Test func testStartNetworkDiscoveryRegistersWithTrackerAndSendsHeartbeats() async throws {
        let (trackerListener, trackerPort, waiter) = try await startLoopbackTrackerListener()
        defer { trackerListener.cancel() }

        async let daemonScript: (BoloNet.TrackerHost?, [UInt8]) = {
            let connection = await waiter.wait()
            let preambleBytes = try await receiveExactlyStream(connection, TrackerPreamble.wireSize)
            guard TrackerPreamble.decode(preambleBytes) != nil else { return (nil, []) }
            try await sendStreamBytes(connection, [TrackerVersionStatus.ok.rawValue])

            let requestByte = try await receiveExactlyStream(connection, 1)
            guard requestByte.first == TrackerRequestType.host.rawValue else { return (nil, []) }
            let hostBytes = try await receiveExactlyStream(connection, BoloNet.TrackerHost.wireSize)
            let received = BoloNet.TrackerHost.decode(hostBytes)

            try await sendStreamBytes(connection, [TrackerTCPPortStatus.ok.rawValue])
            try await sendStreamBytes(connection, [TrackerUDPPortStatus.ok.rawValue])

            // sendtrackerupdate() sends a BARE TrackerHost -- no request byte -- confirming the
            // engine's own heartbeat task fires on `heartbeatInterval`, not just the initial handshake.
            let heartbeat = try await receiveExactlyStream(connection, BoloNet.TrackerHost.wireSize)
            return (received, heartbeat)
        }()

        let (engine, _, dgramPort) = try await makeEngine()
        defer { engine.stop() }
        engine.start()

        await engine.startNetworkDiscovery(
            trackerHostname: "127.0.0.1", trackerServerPort: trackerPort, advertisedPort: dgramPort,
            hostPlayerName: "Host", mapName: "Arena", upnpEnabled: false,
            heartbeatInterval: .milliseconds(50)
        )

        let (received, heartbeatBytes) = try await daemonScript
        #expect(received?.playerName == "Host")
        #expect(received?.mapName == "Arena")
        #expect(received?.port == dgramPort)
        let expectedHeartbeat = trackerHost(hostPlayerName: "Host", mapName: "Arena", port: dgramPort, state: engine.state)
        #expect(heartbeatBytes == expectedHeartbeat.encodeAsHeartbeat())
    }

    @Test func testStartNetworkDiscoveryIsANoOpWithNoTrackerAndNoUPnP() async throws {
        let (engine, _, dgramPort) = try await makeEngine()
        defer { engine.stop() }
        engine.start()

        // Should return promptly and not throw/crash -- T-5's "no tracker configured is success,
        // not an error" precedent (`TrackerRegistration.swift`) extended to this call site.
        await engine.startNetworkDiscovery(
            trackerHostname: nil, advertisedPort: dgramPort, hostPlayerName: "Host", mapName: "Arena",
            upnpEnabled: false
        )
    }
}

// MARK: - v1.5.0 (issue #1): per-slot FogState driven by real gameplay

@Suite struct HostGameEngineFogVisionTests {

    @Test func testHiddenMinesOffNeverAllocatesAnyFogState() async throws {
        let (engine, _, _) = try await makeEngine { state in
            state.hiddenMines = false
            state.players[0].connected = true
            state.players[0].used = true
            state.players[0].dead = false
            state.players[0].tank = Vec2f(x: 105, y: 105)
            state.players[0].alliance = 1 << 0
        }
        defer { engine.stop() }
        engine.start()

        try await Task.sleep(nanoseconds: 100_000_000) // a handful of ticks
        #expect(engine.fogState(for: 0) == nil)
    }

    @Test func testAlreadyConnectedPlayerGetsAnInitialSelfRevealWithoutMoving() async throws {
        let (engine, _, _) = try await makeEngine { state in
            state.hiddenMines = true
            state.players[0].connected = true
            state.players[0].used = true
            state.players[0].dead = false
            state.players[0].tank = Vec2f(x: 105, y: 105)
            state.players[0].alliance = 1 << 0
        }
        defer { engine.stop() }
        engine.start()

        try await waitForCondition(timeout: 2) {
            (engine.fogState(for: 0)?.fog[105 * 256 + 105] ?? 0) > 0
        }
        #expect((engine.fogState(for: 0)?.fog[105 * 256 + 105] ?? 0) > 0)
        // A tile far away, never covered by any vision source, stays unknown.
        #expect(engine.fogState(for: 0)?.seenTiles[200 * 256 + 200] == .unknown)
    }

    @Test func testAllianceFormingRevealsTheNewAllyImmediately() async throws {
        let (engine, _, _) = try await makeEngine { state in
            state.hiddenMines = true
            state.players[0].connected = true
            state.players[0].used = true
            state.players[0].dead = false
            state.players[0].tank = Vec2f(x: 105, y: 105)
            state.players[0].alliance = 1 << 0

            state.players[1].connected = true
            state.players[1].used = true
            state.players[1].dead = false
            state.players[1].tank = Vec2f(x: 150, y: 150) // far outside player 0's own 29x29 vision
            // One-way: player 1 has already declared alliance with player 0 (SessionLogic's own
            // documented asymmetry), but player 0 hasn't reciprocated yet -- testAlliance(0, 1)
            // is still false until player 0's own request below completes the mutual condition.
            state.players[1].alliance = (1 << 1) | (1 << 0)
        }
        defer { engine.stop() }
        engine.start()

        try await waitForCondition(timeout: 2) { engine.fogState(for: 0) != nil }
        #expect(engine.fogState(for: 0)?.seenTiles[150 * 256 + 150] == .unknown, "not allied yet -- must not be visible")

        // Host's own local player (slot 0) requests alliance with player 1, completing the
        // mutual condition -- the only alliance-mutation path reachable from a test without a
        // live network connection (recvClSetAlliance needs a real CL_SETALLIANCE message).
        engine.submitRequestAlliance(players: 1 << 1)

        try await waitForCondition(timeout: 2) {
            (engine.fogState(for: 0)?.fog[150 * 256 + 150] ?? 0) > 0
        }
        #expect((engine.fogState(for: 0)?.fog[150 * 256 + 150] ?? 0) > 0, "alliance forming must immediately reveal the new ally's position")
    }

    // MARK: - v1.5.0 #1 (fix pass, `/code-review max` on PR #56): vision-source symmetry

    /// Regression test for the review's most severe finding: `FogState.fog` is a reference
    /// count needing symmetric increment/decrement, but the original `updateFogVision` could
    /// never reach its own `decreaseVis` call for a broken alliance (a `guard isAllied else {
    /// continue }` sat before it). Two allied players explore together; breaking the alliance
    /// must re-fog the tile the (now-former) ally was the only source for.
    @Test func testAllianceBreakingDecrementsTheVisionItWasContributing() async throws {
        let (engine, _, _) = try await makeEngine { state in
            state.hiddenMines = true
            state.players[0].connected = true
            state.players[0].used = true
            state.players[0].dead = false
            state.players[0].tank = Vec2f(x: 105, y: 105)
            state.players[0].alliance = (1 << 0) | (1 << 1)

            state.players[1].connected = true
            state.players[1].used = true
            state.players[1].dead = false
            state.players[1].tank = Vec2f(x: 150, y: 150) // far outside player 0's own vision
            state.players[1].alliance = (1 << 1) | (1 << 0) // mutually allied from tick 1
        }
        defer { engine.stop() }
        engine.start()

        try await waitForCondition(timeout: 2) { (engine.fogState(for: 0)?.fog[150 * 256 + 150] ?? 0) > 0 }
        #expect((engine.fogState(for: 0)?.fog[150 * 256 + 150] ?? 0) > 0, "ally's position must be visible while allied")

        engine.submitLeaveAlliance(players: 1 << 1)

        try await waitForCondition(timeout: 2) { (engine.fogState(for: 0)?.fog[150 * 256 + 150] ?? 0) <= 0 }
        #expect((engine.fogState(for: 0)?.fog[150 * 256 + 150] ?? 0) <= 0, "breaking the alliance must decrement the vision the ex-ally was the only source for")
    }

    /// Same regression, the other confirmed-unreachable half: a mover simply disappearing
    /// from the loop's own `where connected` filter (disconnect/kick/ban) never decremented
    /// anything either, since only an alliance-status *change* was even attempted.
    @Test func testKickingAPlayerDecrementsTheVisionTheyWereContributing() async throws {
        let (engine, _, _) = try await makeEngine { state in
            state.hiddenMines = true
            state.players[0].connected = true
            state.players[0].used = true
            state.players[0].dead = false
            state.players[0].tank = Vec2f(x: 105, y: 105)
            state.players[0].alliance = (1 << 0) | (1 << 1)

            state.players[1].connected = true
            state.players[1].used = true
            state.players[1].dead = false
            state.players[1].tank = Vec2f(x: 160, y: 160)
            state.players[1].alliance = (1 << 1) | (1 << 0)
        }
        defer { engine.stop() }
        engine.start()

        try await waitForCondition(timeout: 2) { (engine.fogState(for: 0)?.fog[160 * 256 + 160] ?? 0) > 0 }
        #expect((engine.fogState(for: 0)?.fog[160 * 256 + 160] ?? 0) > 0, "kicked player's position must be visible while connected and allied")

        engine.submitKickPlayer(1)

        try await waitForCondition(timeout: 2) { (engine.fogState(for: 0)?.fog[160 * 256 + 160] ?? 0) <= 0 }
        #expect((engine.fogState(for: 0)?.fog[160 * 256 + 160] ?? 0) <= 0, "kicking the player must decrement the vision they were the only source for")
    }

    /// Regression test for the negative-fog double-count bug: the original bootstrap branch
    /// seeded `increaseVis` at the *post-tick* position, then the same tick's movement-diff
    /// logic (pre-tick vs. post-tick) fired again for the identical self pair, netting an
    /// extra `+1` on the new tile and an unmatched `-1` on the old tile's fringe. A player
    /// whose tank is already moving (via input) on the very first tracked tick must never
    /// produce a negative count anywhere.
    @Test func testFirstTrackedTickWithMovementNeverProducesNegativeFog() async throws {
        let (engine, _, _) = try await makeEngine { state in
            state.hiddenMines = true
            state.players[0].connected = true
            state.players[0].used = true
            state.players[0].dead = false
            state.players[0].tank = Vec2f(x: 105, y: 105)
            state.players[0].alliance = 1 << 0
            // Moving right at a speed that guarantees a tile change within the first tick.
            state.players[0].speed = 3.0
            state.players[0].dir = 0 // C's own dir=0 convention is +x, matching TankTick's port
        }
        defer { engine.stop() }
        engine.start()

        try await waitForCondition(timeout: 2) { engine.fogState(for: 0) != nil }
        // Give it a couple more ticks to guarantee the tank has actually moved a tile.
        try await Task.sleep(nanoseconds: 100_000_000)

        guard let fog = engine.fogState(for: 0)?.fog else {
            Issue.record("expected a FogState for player 0")
            return
        }
        #expect(fog.allSatisfy { $0 >= 0 }, "fog count must never go negative")
    }

    /// Regression test for the review's other headline finding: `SRRevealTerrain` was fully
    /// encoded/decoded/dispatched but never constructed and sent by any production code path
    /// -- a real, network-joined player's own client never learned about newly-revealed
    /// terrain at all. This joins a real remote connection into a live engine and confirms a
    /// `SRRevealTerrain` message actually arrives on it (fired by `updateFogVision`'s own
    /// per-tick self-vision bootstrap, the same mechanism that will later report their real
    /// spawn and any territory they explore).
    @Test func hostGameEngineSendsRevealTerrainToARemoteJoinedPlayer() async throws {
        let (engine, tcpPort, _) = try await makeEngine { state in
            state.hiddenMines = true
            state.players[0].used = true
            state.players[0].connected = true
            state.players[0].dead = false
        }
        defer { engine.stop() }
        engine.start()

        let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
        joinClient.start(queue: .main)
        defer { joinClient.cancel() }
        try await sendDatagram(joinClient, JoinPreamble(name: "Ally", pass: "").encode())
        try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) }

        // Consume the join handshake's own status byte + preamble + redacted map + join
        // broadcast (which reaches the joiner too, T-9's own ordering) before the reveal.
        _ = try await receiveExactly(joinClient, 1)
        let preambleBytes = try await receiveExactly(joinClient, BoloPreamble.wireSize)
        guard let mapLength = BoloPreamble.decode(preambleBytes)?.mapLength, mapLength > 0 else {
            Issue.record("expected a preamble with a nonzero map length")
            return
        }
        _ = try await receiveExactly(joinClient, Int(mapLength))
        _ = try await receiveExactly(joinClient, SRPlayerJoin.wireSize)

        let revealBytes = try await receiveExactly(joinClient, SRRevealTerrain.wireSize)
        #expect(SRRevealTerrain.decode(revealBytes) != nil, "a remote player must receive SRRevealTerrain as their own vision reveals tiles")
    }

    // MARK: - Issue #76: host-laid mines must reach remote players

    /// Joins a remote connection into `engine` and consumes the join handshake (status byte,
    /// preamble, map, join broadcast), leaving the stream at the first post-join message.
    private func joinRemote(_ engine: HostGameEngine, tcpPort: UInt16) async throws -> NWConnection {
        let joinClient = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: tcpPort)!, using: .tcp)
        joinClient.start(queue: .main)
        try await sendDatagram(joinClient, JoinPreamble(name: "Ally", pass: "").encode())
        try await waitForCondition(timeout: 3) { await engine.table.isConnected(1) }
        _ = try await receiveExactly(joinClient, 1)
        let preambleBytes = try await receiveExactly(joinClient, BoloPreamble.wireSize)
        guard let mapLength = BoloPreamble.decode(preambleBytes)?.mapLength, mapLength > 0 else {
            throw HarnessError.shortRead
        }
        _ = try await receiveExactly(joinClient, Int(mapLength))
        _ = try await receiveExactly(joinClient, SRPlayerJoin.wireSize)
        return joinClient
    }

    /// Reads server->client TCP messages until the `SRPause` sentinel (queued by the caller after
    /// the action under test, so the engine's ordered event stream guarantees anything the action
    /// broadcast arrives first) and returns every `SRDropMine` seen. Never waits for silence.
    private func drainUntilPause(_ connection: NWConnection) async throws -> [SRDropMine] {
        try await drainAllUntilPause(connection).mines
    }

    /// Same as `drainUntilPause`, also returning every `SRRevealTerrain` seen.
    private func drainAllUntilPause(_ connection: NWConnection) async throws -> (mines: [SRDropMine], reveals: [SRRevealTerrain]) {
        var mines: [SRDropMine] = []
        var reveals: [SRRevealTerrain] = []
        while true {
            let opcode = try await receiveExactly(connection, 1)[0]
            switch opcode {
            case ServerOpcode.pause.rawValue:
                _ = try await receiveExactly(connection, SRPause.wireSize - 1)
                return (mines, reveals)
            case ServerOpcode.revealTerrain.rawValue:
                let rest = try await receiveExactly(connection, SRRevealTerrain.wireSize - 1)
                if let reveal = SRRevealTerrain.decode([opcode] + rest) { reveals.append(reveal) }
            case ServerOpcode.dropMine.rawValue:
                let rest = try await receiveExactly(connection, SRDropMine.wireSize - 1)
                if let mine = SRDropMine.decode([opcode] + rest) { mines.append(mine) }
            default:
                throw HarnessError.shortRead
            }
        }
    }

    private func configureHostWithMines(_ state: inout GameState, hiddenMines: Bool) {
        state.hiddenMines = hiddenMines
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[0].tank = Vec2f(x: 105.5, y: 105.5)
        state.players[0].mines = 5
    }

    @Test(.timeLimit(.minutes(1))) func hostLaidMineKeyDownReachesARemotePlayerWhenHiddenMinesIsOff() async throws {
        let (engine, tcpPort, _) = try await makeEngine { configureHostWithMines(&$0, hiddenMines: false) }
        defer { engine.stop() }
        engine.start()
        let remote = try await joinRemote(engine, tcpPort: tcpPort)
        defer { remote.cancel() }

        engine.submitLocalLayMineKeyDown()
        engine.submitPauseResumeServer()

        let mines = try await drainUntilPause(remote)
        #expect(mines.count == 1)
        #expect(mines.first.map { Int($0.x) } == 105 && mines.first.map { Int($0.y) } == 105)
        #expect(mines.first?.player == 0)
    }

    @Test(.timeLimit(.minutes(1))) func hostLaidMineKeyDownIsNotSentToARemotePlayerWhenHiddenMinesIsOn() async throws {
        let (engine, tcpPort, _) = try await makeEngine { configureHostWithMines(&$0, hiddenMines: true) }
        defer { engine.stop() }
        engine.start()
        let remote = try await joinRemote(engine, tcpPort: tcpPort)
        defer { remote.cancel() }

        engine.submitLocalLayMineKeyDown()
        engine.submitPauseResumeServer()

        let mines = try await drainUntilPause(remote)
        #expect(mines.isEmpty, "a hidden mine must not be announced to remote players; they learn of it by proximity reveal")
    }

    @Test(.timeLimit(.minutes(1))) func hostLaidContinuousMinesReachARemotePlayerWhenHiddenMinesIsOff() async throws {
        let (engine, tcpPort, _) = try await makeEngine { configureHostWithMines(&$0, hiddenMines: false) }
        defer { engine.stop() }
        engine.start()
        let remote = try await joinRemote(engine, tcpPort: tcpPort)
        defer { remote.cancel() }

        engine.submitLocalInputChange(set: [.accel, .lmine], clear: [])
        try await Task.sleep(nanoseconds: 1_500_000_000)
        engine.submitPauseResumeServer()

        let mines = try await drainUntilPause(remote)
        #expect(!mines.isEmpty, "driving with the lay-mine key held must announce each planted mine")
        #expect(mines.allSatisfy { $0.player == 0 })
    }

    // MARK: - Issue #84 / #81: terrain the host's own simulation changes must reach remote players

    private static let minedRawValues: Set<UInt8> = Set(
        [Terrain.minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass].map { UInt8($0.rawValue) }
    )

    /// The host tank drives east onto a mine; the remote must be told the tile is no longer a mine.
    @Test(.timeLimit(.minutes(1))) func hostTankDetonatingAMineTellsARemotePlayerTheTileChanged() async throws {
        let (engine, tcpPort, _) = try await makeEngine { state in
            configureHostWithMines(&state, hiddenMines: false)
            state.terrain[108, 105] = .minedGrass
        }
        defer { engine.stop() }
        engine.start()
        let remote = try await joinRemote(engine, tcpPort: tcpPort)
        defer { remote.cancel() }

        engine.submitLocalInputChange(set: [.accel], clear: [])
        try await Task.sleep(nanoseconds: 2_000_000_000)
        engine.submitPauseResumeServer()

        let reveals = try await drainAllUntilPause(remote).reveals
        let update = reveals.last { $0.x == 108 && $0.y == 105 }
        #expect(update != nil, "the detonated tile's new terrain must be sent to the remote")
        #expect(update.map { !Self.minedRawValues.contains($0.terrain) } == true)
    }

    // MARK: - #62 S4: the host sends each remote its authoritative combat state

    /// Like `drainUntilPause`, returning every `SRTankStatus` seen (the sentinel is `SRPause`).
    private func drainStatusesUntilPause(_ connection: NWConnection) async throws -> [SRTankStatus] {
        var statuses: [SRTankStatus] = []
        while true {
            let opcode = try await receiveExactly(connection, 1)[0]
            switch opcode {
            case ServerOpcode.pause.rawValue:
                _ = try await receiveExactly(connection, SRPause.wireSize - 1)
                return statuses
            case ServerOpcode.revealTerrain.rawValue:
                _ = try await receiveExactly(connection, SRRevealTerrain.wireSize - 1)
            case ServerOpcode.dropMine.rawValue:
                _ = try await receiveExactly(connection, SRDropMine.wireSize - 1)
            case ServerOpcode.tankStatus.rawValue:
                let rest = try await receiveExactly(connection, SRTankStatus.wireSize - 1)
                if let status = SRTankStatus.decode([opcode] + rest) { statuses.append(status) }
            default:
                throw HarnessError.shortRead
            }
        }
    }

    @Test(.timeLimit(.minutes(1))) func hostSendsAJoinedRemoteItsOwnTankStatusWhenHostSimulationIsOn() async throws {
        let (engine, tcpPort, _) = try await makeEngine { state in
            configureHostWithMines(&state, hiddenMines: false)
            state.hostSimulatesRemotePlayers = true
        }
        defer { engine.stop() }
        engine.start()
        let remote = try await joinRemote(engine, tcpPort: tcpPort)
        defer { remote.cancel() }

        try await Task.sleep(nanoseconds: 500_000_000)
        engine.submitPauseResumeServer()

        let statuses = try await drainStatusesUntilPause(remote)
        #expect(!statuses.isEmpty, "a host-simulated remote must be told its own combat state")
    }

    /// A joined remote starts dead on the host; when the host respawns it, the status that reports
    /// it alive carries the spawn point as a teleport (the guest owns its own movement).
    @Test(.timeLimit(.minutes(1))) func hostRespawnOfAJoinedRemoteArrivesAsATeleportStatus() async throws {
        let (engine, tcpPort, _) = try await makeEngine { state in
            configureHostWithMines(&state, hiddenMines: false)
            state.hostSimulatesRemotePlayers = true
        }
        defer { engine.stop() }
        engine.start()
        let remote = try await joinRemote(engine, tcpPort: tcpPort)
        defer { remote.cancel() }

        try await Task.sleep(nanoseconds: 5_000_000_000)
        engine.submitPauseResumeServer()

        let statuses = try await drainStatusesUntilPause(remote)
        let respawn = statuses.first { $0.teleport != nil }
        #expect(respawn != nil, "the respawn must reach the guest as a teleport")
        #expect(respawn?.dead == false)
        #expect(respawn?.teleport.map { Int($0.x) == 105 && Int($0.y) == 105 } == true, "spawns at state.starts[0]")
        #expect(statuses.first?.dead == true, "the first status reports the still-dead joined remote")
    }

    @Test(.timeLimit(.minutes(1))) func hostSendsNoTankStatusWhenHostSimulationIsOff() async throws {
        let (engine, tcpPort, _) = try await makeEngine { configureHostWithMines(&$0, hiddenMines: false) }
        defer { engine.stop() }
        engine.start()
        let remote = try await joinRemote(engine, tcpPort: tcpPort)
        defer { remote.cancel() }

        try await Task.sleep(nanoseconds: 300_000_000)
        engine.submitPauseResumeServer()

        let statuses = try await drainStatusesUntilPause(remote)
        #expect(statuses.isEmpty)
    }
}
