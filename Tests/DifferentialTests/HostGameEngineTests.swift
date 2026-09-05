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
/// `confirmNoCLUpdateArrives`'s own `withTaskGroup`/`cancelAll()` bug above. Fixed the same way --
/// an `async let` timeout guard that cancels the connection if the deadline is reached, which
/// reliably unblocks a pending `receiveMessage`; Swift implicitly cancels-and-awaits the unused
/// `async let` on the success path, so `connection.cancel()` never runs unless the timeout
/// actually elapses.
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
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].dead = false
        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].dead = false
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
    await engine.table.setConnection(fakeTCP, for: 0)
    await engine.table.setConnection(fakeTCP, for: 1)
    await engine.table.setDgramAddress(fakeAddress, for: 0)
    await engine.table.setDgramAddress(fakeAddress, for: 1)

    engine.start()

    let senderClient = makeUDPClient(port: dgramPort)
    let peerClient = makeUDPClient(port: dgramPort)
    defer { senderClient.cancel(); peerClient.cancel() }

    // Each peer's first `CLUpdate` registers its own dgram connection in the table, through the
    // engine's real dgram-processing path (`processDgramPacket`'s `.applied` case) -- exactly
    // what a real client's first datagram produces, not manually seeded.
    try await sendCLUpdate(senderClient, player: 0, seq: 1, tank: Vec2f(x: 101, y: 101))
    try await sendCLUpdate(peerClient, player: 1, seq: 1, tank: Vec2f(x: 102, y: 102))
    try await waitForCondition(timeout: 2) { await engine.table.dgramConnection(for: 1) != nil }

    let expectedTank = Vec2f(x: 112, y: 114)
    try await sendCLUpdate(senderClient, player: 0, seq: 2, tank: expectedTank)
    let decoded = try await receiveMatchingCLUpdate(peerClient, expectedTank: expectedTank)
    #expect(decoded.header.player == 0)

    try await waitForCondition(timeout: 2) { engine.state.players[0].tank == expectedTank }
    #expect(engine.state.players[0].tank == expectedTank)
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
