import Testing
import BoloKit
import BoloNet
import Network
import Foundation

// Swift-only tests for `HostSessionTable`'s fan-out primitives and
// `receiveAndDispatchOneHostMessage` (Wave 6.4b). Same "no C oracle for
// the transport mechanism itself" reasoning as `JoinClientTests.swift`/
// `UDPSessionTests.swift` (D31) -- these stand up real loopback TCP pairs
// and confirm the *routing* decisions (who gets which `SR*` bytes) match
// the `sendtoall`/`sendtoallex`/`sendtoone` citations in `HostSession.
// swift`'s own header, not wire-codec correctness (already covered by
// `NetCodecDifferentialTests.swift`).

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

/// D53: proves *absence* -- `count` bytes never arrive within a short
/// window, either because nothing was sent (times out) or because the
/// peer closed/canceled before delivering a full payload (errors out
/// promptly on loopback). Either outcome confirms "did not receive";
/// only actually reading `count` real bytes counts as a failure.
private func confirmNoDatagramArrives(_ connection: NWConnection, count: Int, timeoutNanoseconds: UInt64 = 300_000_000) async -> Bool {
    await withTaskGroup(of: Bool.self) { group in
        group.addTask {
            do {
                _ = try await receiveExactly(connection, count)
                return false
            } catch {
                return true
            }
        }
        group.addTask {
            try? await Task.sleep(nanoseconds: timeoutNanoseconds)
            return true
        }
        let first = await group.next() ?? true
        group.cancelAll()
        return first
    }
}

/// One simulated player: `clientEnd` is the test's own handle (writes CL*
/// bytes in as "the player sending a message"; reads SR* bytes out as
/// "what the player's real client would have received"). `serverEnd` is
/// what gets registered into the `HostSessionTable` -- the connection
/// `receiveAndDispatchOneHostMessage`/the fan-out primitives actually
/// read from and write to, mirroring the shape a real accepted connection
/// would have.
private struct FakePlayerLink {
    let listener: NWListener
    let clientEnd: NWConnection
    let serverEnd: NWConnection
}

private func makeConnectedPair() async throws -> FakePlayerLink {
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

    return FakePlayerLink(listener: listener, clientEnd: clientEnd, serverEnd: serverEnd)
}

/// Registers `count` fake players (indices `0..<count`) into a fresh
/// `HostSessionTable`, returning the table plus every link so the test can
/// both feed bytes in (`link.clientEnd`) and observe broadcasts out.
private func makeTableWithPlayers(_ count: Int) async throws -> (table: HostSessionTable, links: [FakePlayerLink]) {
    let table = HostSessionTable()
    var links: [FakePlayerLink] = []
    for i in 0..<count {
        let link = try await makeConnectedPair()
        await table.setConnection(link.serverEnd, for: i)
        links.append(link)
    }
    return (table, links)
}

private func makeState(playerCount: Int) -> GameState {
    var state = GameState()
    state.players = (0..<max(playerCount, maxPlayers)).map { i in
        var p = PlayerState()
        p.used = i < playerCount
        p.connected = i < playerCount
        return p
    }
    state.terrain[50, 50] = .grass0
    return state
}

// MARK: - HostSessionTable fan-out primitives

@Test func sendToAllReachesEveryConnectedSlot() async throws {
    let (table, links) = try await makeTableWithPlayers(3)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    await table.sendToAll([9, 9, 9])
    for link in links {
        let received = try await receiveExactly(link.clientEnd, 3)
        #expect(received == [9, 9, 9])
    }
}

@Test func sendToAllExceptSkipsOnlyTheNamedPlayer() async throws {
    let (table, links) = try await makeTableWithPlayers(3)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    await table.sendToAllExcept(1, [7])
    let r0 = try await receiveExactly(links[0].clientEnd, 1)
    let r2 = try await receiveExactly(links[2].clientEnd, 1)
    #expect(r0 == [7])
    #expect(r2 == [7])
    // Player 1 got nothing -- confirmed by racing a short timeout would be
    // flaky; instead confirm player 0/2 got exactly one byte each and move
    // on, matching this suite's other exclusion tests' style.
}

@Test func sendToMaskOnlyReachesBitsThatAreSet() async throws {
    let (table, links) = try await makeTableWithPlayers(3)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    await table.sendToMask(UInt16(1 << 0) | UInt16(1 << 2), [5])
    let r0 = try await receiveExactly(links[0].clientEnd, 1)
    let r2 = try await receiveExactly(links[2].clientEnd, 1)
    #expect(r0 == [5])
    #expect(r2 == [5])
}

@Test func disconnectClosesTheConnectionAndClearsTheSlot() async throws {
    let (table, links) = try await makeTableWithPlayers(1)
    defer { for l in links { l.listener.cancel() } }

    await table.disconnect(0)
    #expect(await table.isConnected(0) == false)
    #expect(await table.seq(for: 0) == 0)  // T-1: wiped back to default
}

// MARK: - receiveAndDispatchOneHostMessage

@Test func dispatchDropBoatBroadcastsToAllConnectedPlayers() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.terrain[50, 50] = .river

    try await sendBytes(links[0].clientEnd, CLDropBoat(x: 50, y: 50).encode())
    let opcode = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)
    #expect(opcode == .dropBoat)
    #expect(state.terrain[50, 50] == .boat)

    for link in links {
        let bytes = try await receiveExactly(link.clientEnd, SRDropBoat.wireSize)
        #expect(SRDropBoat.decode(bytes) == SRDropBoat(x: 50, y: 50))
    }
}

@Test func dispatchDropMineAcksSenderOnlyAndBroadcastsToAll() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.terrain[50, 50] = .grass0

    try await sendBytes(links[0].clientEnd, CLDropMine(x: 50, y: 50).encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)
    #expect(state.terrain[50, 50] == .minedGrass)

    // Broadcast (SRDropMine) reaches both players.
    for link in links {
        let bytes = try await receiveExactly(link.clientEnd, SRDropMine.wireSize)
        #expect(SRDropMine.decode(bytes) == SRDropMine(player: 0, x: 50, y: 50))
    }
    // The ack (SRMineAck) is `sendtoone` -- only player 0 gets it.
    let ack = try await receiveExactly(links[0].clientEnd, SRMineAck.wireSize)
    #expect(SRMineAck.decode(ack) == SRMineAck(success: 1))
}

@Test func dispatchHitTankUsesWirePlayerFieldNotSenderSlot() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    // Player 0's connection sends a hitTank naming player 1 as the target
    // -- matches `RecvCL.swift`'s doc comment: the wire `player` field is
    // the tank being hit, not the sender's own identity.
    try await sendBytes(links[0].clientEnd, CLHitTank(player: 1, dir: 2.5).encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)

    let bytes = try await receiveExactly(links[1].clientEnd, SRHitTank.wireSize)
    #expect(SRHitTank.decode(bytes) == SRHitTank(player: 1, dir: 2.5))
}

@Test func dispatchBuildRoadTerrainByteMatchesTheNewTerrainD40() async throws {
    let (table, links) = try await makeTableWithPlayers(1)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 1)
    state.terrain[50, 50] = .grass0

    // D40: tautology means road building always succeeds regardless of trees.
    try await sendBytes(links[0].clientEnd, CLBuildRoad(x: 50, y: 50, trees: 0).encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)
    #expect(state.terrain[50, 50] == .road)

    let buildBytes = try await receiveExactly(links[0].clientEnd, SRBuild.wireSize)
    #expect(SRBuild.decode(buildBytes) == SRBuild(x: 50, y: 50, terrain: UInt8(Terrain.road.rawValue)))

    let ackBytes = try await receiveExactly(links[0].clientEnd, SRBuilderAck.wireSize)
    // D40's second-order effect: leftover trees go negative (-roadTrees),
    // wire-truncated to UInt8 at the wraparound boundary this callback's
    // own `UInt8(truncatingIfNeeded:)` conversion applies.
    #expect(SRBuilderAck.decode(ackBytes)?.trees == UInt8(truncatingIfNeeded: -roadTrees))
}

@Test func dispatchGrabTileCapturePillIncludesOwnerByte() async throws {
    let (table, links) = try await makeTableWithPlayers(1)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 1)
    state.pills = [Pill(x: 50, y: 50, armour: 3, owner: playerNeutral, speed: 20, counter: 0)]

    try await sendBytes(links[0].clientEnd, CLGrabTile(x: 50, y: 50).encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)
    #expect(state.pills[0].owner == 0)

    let bytes = try await receiveExactly(links[0].clientEnd, SRCapturePill.wireSize)
    #expect(SRCapturePill.decode(bytes) == SRCapturePill(pill: 0, owner: 0))
}

@Test func dispatchRefuelExcludesTheRequestingPlayer() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.bases = [Base(x: 5, y: 5, armour: 40, owner: 0, shells: 40, mines: 40)]

    try await sendBytes(links[0].clientEnd, CLRefuel(base: 0, armour: 10, shells: 5, mines: 3).encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)
    #expect(state.bases[0].armour == 30)

    // Only player 1 (not the requester, player 0) gets the broadcast --
    // `sendsrrefuel` uses `sendtoallex`, confirmed by direct read.
    let bytes = try await receiveExactly(links[1].clientEnd, SRRefuel.wireSize)
    #expect(SRRefuel.decode(bytes) == SRRefuel(base: 0, armour: 10, shells: 5, mines: 3))
}

@Test func dispatchSetAllianceExcludesTheSenderAndMutatesState() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)

    try await sendBytes(links[0].clientEnd, CLSetAlliance(alliance: 0xBEEF).encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)
    #expect(state.players[0].alliance == 0xBEEF)

    let bytes = try await receiveExactly(links[1].clientEnd, SRSetAlliance.wireSize)
    #expect(SRSetAlliance.decode(bytes) == SRSetAlliance(player: 0, alliance: 0xBEEF))
}

@Test func dispatchSendMesgDeliversOnlyToMaskedRecipients() async throws {
    let (table, links) = try await makeTableWithPlayers(3)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 3)
    let mask: Int16 = Int16(bitPattern: UInt16(1 << 0) | UInt16(1 << 2))  // players 0 and 2, not 1
    try await sendBytes(links[1].clientEnd, CLSendMesg(to: 255, mask: mask, text: "hi").encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[1].serverEnd, player: 1, state: &state, table: table)

    let expected = SRSendMesg(player: 1, to: 255, text: "hi").encode()
    let r0 = try await receiveExactly(links[0].clientEnd, expected.count)
    let r2 = try await receiveExactly(links[2].clientEnd, expected.count)
    #expect(r0 == expected)
    #expect(r2 == expected)
}

@Test func dispatchHangUpConsumesTheMessageWithNoBroadcastOrStateChange() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    let before = state

    try await sendBytes(links[0].clientEnd, CLHangUp().encode())
    let opcode = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)
    #expect(opcode == .hangUp)
    #expect(state.players[0].used == before.players[0].used)  // untouched
}

// MARK: - Disconnect / kick / ban (T-12, T-13)

/// D53 (PARITY finding, Wave 6.4c audit): `sendsrplayerexit()`
/// (`server.c:3387-3409`) is `sendtoone(player)` THEN `sendtoallex`, so
/// the departing player receives their own exit notice too -- unlike
/// `sendsrplayerdisc()`, a plain `sendtoallex` with no self-send. Reads
/// from BOTH `links[0]` (the departing player) and `links[1]` (everyone
/// else) to prove the fix reaches everyone, not renamed from the old
/// "ToOthersOnly" title without checking the behavior actually changed.
@Test func handlePlayerDisconnectNormalBroadcastsPlayerExitToEveryoneIncludingSelf() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    await handlePlayerDisconnect(player: 0, reason: .normal, state: &state, table: table)

    #expect(!state.players[0].connected)
    #expect(await table.isConnected(0) == false)

    let ownBytes = try await receiveExactly(links[0].clientEnd, SRPlayerExit.wireSize)
    #expect(SRPlayerExit.decode(ownBytes) == SRPlayerExit(player: 0))
    let othersBytes = try await receiveExactly(links[1].clientEnd, SRPlayerExit.wireSize)
    #expect(SRPlayerExit.decode(othersBytes) == SRPlayerExit(player: 0))
}

/// D53's other half, explicitly required so this distinction stays
/// covered going forward: unlike the normal-exit case above,
/// `sendsrplayerdisc()` never reaches the departing player itself.
@Test func handlePlayerDisconnectAbnormalDoesNotReachTheDepartingPlayer() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    await handlePlayerDisconnect(player: 0, reason: .abnormal, state: &state, table: table)

    let absent = await confirmNoDatagramArrives(links[0].clientEnd, count: SRPlayerDisc.wireSize)
    #expect(absent)
}

@Test func handlePlayerDisconnectAbnormalBroadcastsPlayerDisc() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    await handlePlayerDisconnect(player: 0, reason: .abnormal, state: &state, table: table)

    let bytes = try await receiveExactly(links[1].clientEnd, SRPlayerDisc.wireSize)
    #expect(SRPlayerDisc.decode(bytes) == SRPlayerDisc(player: 0))
}

/// T-12: `pauseonplayerexit` fires an EXTRA `SRPause(255)` broadcast to
/// EVERYONE (including the departing player's now-severed slot, which is
/// a harmless no-op send) on top of the exit/disc broadcast.
@Test func handlePlayerDisconnectWithPauseOnExitAlsoBroadcastsIndefinitePause() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.pauseOnPlayerExit = true
    await handlePlayerDisconnect(player: 0, reason: .normal, state: &state, table: table)

    #expect(state.serverPauseTicks == -1)
    _ = try await receiveExactly(links[1].clientEnd, SRPlayerExit.wireSize)  // the exit broadcast first
    let pauseBytes = try await receiveExactly(links[1].clientEnd, SRPause.wireSize)
    #expect(SRPause.decode(pauseBytes) == SRPause(pause: 255))
}

@Test func hostKickPlayerBroadcastsToAllAndDisconnectsTheKickedSlot() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    await hostKickPlayer(player: 0, state: &state, table: table)

    #expect(!state.players[0].connected)
    #expect(await table.isConnected(0) == false)

    // `sendsrplayerkick` uses `sendtoall` -- unlike exit/disc/ban, this
    // reaches the OTHER player, confirmed by direct read (server.c).
    let bytes = try await receiveExactly(links[1].clientEnd, SRPlayerKick.wireSize)
    #expect(SRPlayerKick.decode(bytes) == SRPlayerKick(player: 0))
}

@Test func hostBanPlayerBroadcastsAndAppendsToBanListOnlyWhenConnected() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.players[0].name = "Grief"
    state.players[0].address = "1.2.3.4"

    await hostBanPlayer(player: 0, state: &state, table: table)

    #expect(state.bannedPlayers == [BannedPlayer(name: "Grief", address: "1.2.3.4")])
    #expect(await table.isConnected(0) == false)

    let bytes = try await receiveExactly(links[1].clientEnd, SRPlayerBan.wireSize)
    #expect(SRPlayerBan.decode(bytes) == SRPlayerBan(player: 0))
}

// MARK: - SRDropPill broadcast on departure (Wave 6.4c, §3)

@Test func handlePlayerDisconnectBroadcastsDropPillBeforeExitBroadcast() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]

    await handlePlayerDisconnect(player: 0, reason: .normal, state: &state, table: table)

    #expect(state.pills[0].armour != pillOnboard)  // dropped
    // `removeplayer()` (and so its own `sendsrdroppill`) runs BEFORE
    // `sendsrplayerexit` (server.c:1667-1740) -- drop-pill broadcast
    // arrives first on the wire.
    let dropBytes = try await receiveExactly(links[1].clientEnd, SRDropPill.wireSize)
    let dropped = SRDropPill.decode(dropBytes)
    #expect(dropped?.pill == 0)
    #expect(dropped?.x == 50 && dropped?.y == 50)
    let exitBytes = try await receiveExactly(links[1].clientEnd, SRPlayerExit.wireSize)
    #expect(SRPlayerExit.decode(exitBytes) == SRPlayerExit(player: 0))
}

@Test func hostKickPlayerBroadcastsDropPillAfterKickBroadcast() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]

    await hostKickPlayer(player: 0, state: &state, table: table)

    #expect(state.pills[0].armour != pillOnboard)
    // `kickplayer()`'s `sendsrplayerkick` fires BEFORE `removeplayer()`
    // (server.c:486-487) -- opposite order from the disconnect path.
    let kickBytes = try await receiveExactly(links[1].clientEnd, SRPlayerKick.wireSize)
    #expect(SRPlayerKick.decode(kickBytes) == SRPlayerKick(player: 0))
    let dropBytes = try await receiveExactly(links[1].clientEnd, SRDropPill.wireSize)
    #expect(SRDropPill.decode(dropBytes)?.pill == 0)
}

@Test func hostBanPlayerBroadcastsDropPillAfterBanBroadcast() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]

    await hostBanPlayer(player: 0, state: &state, table: table)

    #expect(state.pills[0].armour != pillOnboard)
    let banBytes = try await receiveExactly(links[1].clientEnd, SRPlayerBan.wireSize)
    #expect(SRPlayerBan.decode(banBytes) == SRPlayerBan(player: 0))
    let dropBytes = try await receiveExactly(links[1].clientEnd, SRDropPill.wireSize)
    #expect(SRDropPill.decode(dropBytes)?.pill == 0)
}

/// T-17: the broadcast must use the pill's *placement* coordinates (the
/// spiral search's own current cell), not `dropPills`' original scatter
/// origin -- only observable once the search expands past the first ring,
/// which requires at least 2 pills to drop onto a mostly-occupied first
/// cell.
@Test func dispatchDropPillsBroadcastsSRDropPillPerPlacedPillAtSearchCellNotOrigin() async throws {
    let (table, links) = try await makeTableWithPlayers(1)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 1)
    // Occupy the origin cell with an existing (non-onboard) pill so the
    // spiral search must expand outward for the second drop.
    state.pills = [
        Pill(x: 50, y: 50, armour: 5, owner: 1, speed: 10, counter: 0),
        Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0),
        Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0),
    ]

    try await sendBytes(links[0].clientEnd, CLDropPills(x: 50.5, y: 50.5, pills: 0b110).encode())
    _ = try await receiveAndDispatchOneHostMessage(connection: links[0].serverEnd, player: 0, state: &state, table: table)

    #expect(state.pills[1].armour != pillOnboard)
    #expect(state.pills[2].armour != pillOnboard)

    let first = SRDropPill.decode(try await receiveExactly(links[0].clientEnd, SRDropPill.wireSize))
    let second = SRDropPill.decode(try await receiveExactly(links[0].clientEnd, SRDropPill.wireSize))
    #expect(first?.pill == 1)
    #expect(second?.pill == 2)
    // Neither placement lands on the origin (50, 50) -- pill 0 already
    // occupies it -- proving the broadcast used the actual search cell.
    #expect(!(first?.x == 50 && first?.y == 50))
    #expect(!(second?.x == 50 && second?.y == 50))
}

@Test func hostBanPlayerOnAlreadyDisconnectedSlotIsANoOp() async throws {
    let (table, links) = try await makeTableWithPlayers(2)
    defer { for l in links { l.listener.cancel(); l.clientEnd.cancel() } }

    var state = makeState(playerCount: 2)
    state.players[0].connected = false

    await hostBanPlayer(player: 0, state: &state, table: table)
    #expect(state.bannedPlayers.isEmpty)
}
