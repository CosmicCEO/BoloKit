import Foundation
import Testing
import BoloKit
import BoloNet

// v1.5.0 #1 (issue #1) follow-up -- the loopback host+guest counterpart of
// `docs/TEST_TWO_MAC_FOG.md`'s step 3.4 (the still-unverified two-Mac hidden-mines session).
// Drives a REAL host (`HostListener` + `HostDgramListener` + `HostGameEngine`) against a REAL
// guest (`TCPSession.join` + `UDPSession`), exactly like `HostGuestRoundTripTests.swift`, but
// with `hiddenMines` on and a live TCP receive loop applying every `SR*` message the host
// sends -- `HostGuestRoundTripTests.swift`'s own guest never reads past the join handshake, so
// it could never have caught this: a mine within 2.0 units of a tank was substituted to its
// unmined equivalent instead of revealed (`FogState.swift`'s `revealNearbyHiddenMines` called
// the substituting `fogTileFor` instead of C's real `testhiddenmine`->`refresh`->`tilefor()`
// ground-truth path), and even a correctly-computed reveal was force-unmined a second time
// before it ever reached the wire (`HostGameEngine.updateFogVision`'s `queueReveals` always
// sent `unminedTerrain`, ignoring what the host's own `FogState` had just decided). Both fixed
// -- see `docs/CONSTRAINTS.md`'s "Fog-of-war" section for the full discovered-defect writeup.

private final class GuestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    init(_ state: GameState) { _state = state }
    var state: GameState { lock.lock(); defer { lock.unlock() }; return _state }
    func mutate(_ body: (inout GameState) -> Void) { lock.lock(); body(&_state); lock.unlock() }
}

private enum FogHarnessError: Error { case noPort }

/// A single shared spawn point with one mined tile 1.0 world unit from its center -- inside
/// `revealNearbyHiddenMines`'s 2.0-unit radius the moment either tank spawns there, matching
/// `docs/TEST_TWO_MAC_FOG.md`'s own training-map setup ("both players spawn on the same tile").
private let mineX = 105
private let mineY = 106

private func makeHiddenMinesHost() async throws -> (engine: HostGameEngine, port: UInt16) {
    for _ in 0..<8 {
        let port = UInt16.random(in: 49_152...65_000)
        let tcp: HostListener
        do { tcp = try await HostListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        let udp: HostDgramListener
        do { udp = try await HostDgramListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { tcp.cancel(); continue }

        // Same host setup `HostGameView.startHosting()` builds (mirrors
        // `HostGuestRoundTripTests.swift`'s `makeHost()`), plus `hiddenMines` and one mine.
        var state = GameState()
        state.hiddenMines = true
        var host = PlayerState()
        host.connected = true
        host.used = true
        host.dead = true
        host.alliance = UInt16(1 << 0)
        state.players = hostPlayerSlots(hostPlayer: host)
        state.localPlayer = 0
        state.local.respawnCounter = respawnTicks - 1
        for y in 100..<120 { for x in 100..<120 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
        state.terrain[mineX, mineY] = .minedGrass
        state.starts = [Start(x: 105, y: 105, dir: 0)]
        return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
    }
    throw FogHarnessError.noPort
}

private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
}

@Test func aMineNearSpawnIsRevealedToTheGuestOverTheWireAndLocallyToTheHost() async throws {
    let (engine, port) = try await makeHiddenMinesHost()
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

    // Guest's UDP receive/send loops, identical to `HostGuestRoundTripTests.swift` -- these
    // alone are what puts the guest's spawned tank position on the wire so the host can see it.
    let udpReceiver = Task {
        while !Task.isCancelled {
            guard let data = try? await udp.receiveOneRawDatagram() else { return }
            guest.mutate { state in _ = udp.apply(data, myOwnSeq: 0, state: &state) }
        }
    }
    let udpSender = Task {
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
    // The piece `HostGuestRoundTripTests.swift` never needed: a real TCP receive loop applying
    // every `SR*` message, matching `GameSession.swift`'s own join-path producer
    // (`tcpSession.receiveOneRawMessage()` -> dispatch) -- without this, `SRRevealTerrain`
    // (and every other post-join broadcast) is never read off the guest's own socket.
    let tcpReceiver = Task {
        while !Task.isCancelled {
            guard let message = try? await joined.session.receiveOneRawMessage() else { return }
            guest.mutate { state in _ = try? TCPSession.dispatch(message, state: &state) }
        }
    }
    defer { udpReceiver.cancel(); udpSender.cancel(); tcpReceiver.cancel() }

    // Both tanks spawn on `state.starts`' single point -- the guest immediately via
    // `applyBoloPreamble`'s own `spawn()` call, the host shortly after via its primed
    // `respawnCounter` -- putting both 1.0 unit from the mine at (mineX, mineY).
    try await waitFor(timeout: 8) {
        !engine.state.players[guestIndex].dead && !engine.state.players[0].dead
    }

    let mineIndex = mineY * 256 + mineX
    try await waitFor(timeout: 5) {
        engine.fogState(for: 0)?.seenTiles[mineIndex] == .minedGrass
            && guest.state.terrain[mineX, mineY] == .minedGrass
    }

    // The host's own local reveal (`revealNearbyHiddenMines`, no wire round-trip) -- confirms
    // the `fogTileFor` -> `tileFor` fix independent of anything crossing the network.
    #expect(engine.fogState(for: 0)?.seenTiles[mineIndex] == .minedGrass, "host's own proximity reveal must show the real mined tile")

    // The guest's copy, built entirely from real `SR*` wire traffic -- confirms the
    // `queueReveals` fix: the host's fog decision must actually cross the wire, not get
    // force-unmined again in `HostGameEngine.updateFogVision`.
    #expect(guest.state.terrain[mineX, mineY] == .minedGrass, "guest must receive the real mined terrain, not a force-unmined substitute")
}
