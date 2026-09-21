import Foundation
import Testing
import BoloKit
import BoloNet

// #62 S4 -- end-to-end: a REAL host (`HostListener` + `HostDgramListener` + `HostGameEngine`) with
// `hostSimulatesRemotePlayers` on, against a REAL guest (`TCPSession.join` + `UDPSession`) whose
// loops mirror `GameSession`'s join path (UDP send of its own `CLUpdate`, TCP receive applying
// every `SR*` message). The guest here does no combat of its own -- everything it learns about
// its armour, shells and respawn arrives as `SRTankStatus` from the host, which is the point.
// Shape borrowed from `HostGuestFogRevealTests.swift`.

private final class GuestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    init(_ state: GameState) { _state = state }
    var state: GameState { lock.lock(); defer { lock.unlock() }; return _state }
    func mutate(_ body: (inout GameState) -> Void) { lock.lock(); body(&_state); lock.unlock() }
}

private enum SimHarnessError: Error { case noPort }

private func waitFor(timeout: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
}

private func makeSimulatingHost(_ configure: (inout GameState) -> Void) async throws -> (engine: HostGameEngine, port: UInt16) {
    for _ in 0..<8 {
        let port = UInt16.random(in: 49_152...65_000)
        let tcp: HostListener
        do { tcp = try await HostListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        let udp: HostDgramListener
        do { udp = try await HostDgramListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { tcp.cancel(); continue }

        var state = GameState()
        var host = PlayerState()
        host.connected = true
        host.used = true
        host.dead = true
        host.alliance = UInt16(1 << 0)
        state.players = hostPlayerSlots(hostPlayer: host)
        state.localPlayer = 0
        state.local.respawnCounter = respawnTicks - 1
        state.hostSimulatesRemotePlayers = true
        for y in 100..<120 { for x in 100..<120 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
        state.starts = [Start(x: 105, y: 105, dir: 0)]
        configure(&state)
        return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
    }
    throw SimHarnessError.noPort
}

/// Runs `body` with a joined guest whose loops are live, cleaning everything up afterwards.
private func withHostedGuest(
    configure: (inout GameState) -> Void = { _ in },
    _ body: (HostGameEngine, GuestBox, Int) async throws -> Void
) async throws {
    let (engine, port) = try await makeSimulatingHost(configure)
    engine.start()
    defer { engine.stop() }

    let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
    var initial = GameState()
    initial.players = (0..<maxPlayers).map { _ in PlayerState() }
    #expect(applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial))
    let guestIndex = initial.localPlayer
    let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
    let guest = GuestBox(initial)
    defer { udp.cancel(); joined.session.cancel() }

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
    let tcpReceiver = Task {
        while !Task.isCancelled {
            guard let message = try? await joined.session.receiveOneRawMessage() else { return }
            guest.mutate { state in _ = try? TCPSession.dispatch(message, state: &state) }
        }
    }
    // The guest owns its own movement, as `GameSession`'s join `.tick` does (`tankMoveTick`),
    // skipping it while dead like the thinned guest.
    let mover = Task {
        while !Task.isCancelled {
            guest.mutate { state in
                if !state.players[guestIndex].dead { tankMoveTick(player: guestIndex, state: &state) }
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    defer { udpReceiver.cancel(); udpSender.cancel(); tcpReceiver.cancel(); mover.cancel() }

    try await body(engine, guest, guestIndex)
}

@Test(.timeLimit(.minutes(1))) func aSimulatedGuestIsRespawnedByTheHostAndTeleportedToTheSpawnPoint() async throws {
    try await withHostedGuest { engine, guest, guestIndex in
        // The guest starts wherever it likes; the host's authoritative respawn must move it.
        guest.mutate { $0.players[guestIndex].tank = Vec2f(x: 115.5, y: 115.5) }
        try await waitFor(timeout: 10) {
            !engine.state.players[guestIndex].dead
                && Int(guest.state.players[guestIndex].tank.x) == 105 && Int(guest.state.players[guestIndex].tank.y) == 105
        }
        let tank = guest.state.players[guestIndex].tank
        #expect(Int(tank.x) == 105 && Int(tank.y) == 105, "the respawn teleport must reach the guest")
        #expect(!guest.state.players[guestIndex].dead)
        #expect(guest.state.local.armour == maxArmour, "armour arrives via SRTankStatus")
    }
}

@Test(.timeLimit(.minutes(1))) func aSimulatedGuestsShotsSpendItsShellsAsReportedByTheHost() async throws {
    try await withHostedGuest { engine, guest, guestIndex in
        try await waitFor(timeout: 10) { !engine.state.players[guestIndex].dead && guest.state.local.shells == maxShells }
        #expect(guest.state.local.shells == maxShells)
        // Input flags are the guest's only way to ask for a shot; the host simulates the rest.
        guest.mutate { $0.players[guestIndex].inputFlags = [.shoot] }
        try await waitFor(timeout: 5) { guest.state.local.shells < maxShells }
        #expect(guest.state.local.shells < maxShells, "the host's shells count must arrive via SRTankStatus")
        #expect(engine.state.localStats[guestIndex].shells < maxShells, "and the host, not the guest, spent them")
    }
}

@Test(.timeLimit(.minutes(1))) func aSimulatedGuestDrivingOntoAMineDetonatesItAndLosesArmour() async throws {
    try await withHostedGuest(configure: { $0.terrain[108, 105] = .minedGrass }) { engine, guest, guestIndex in
        try await waitFor(timeout: 10) { !engine.state.players[guestIndex].dead && guest.state.local.armour == maxArmour }
        #expect(guest.state.local.armour == maxArmour)
        // The guest owns its movement: it drives east onto the mined tile; the host does the rest.
        guest.mutate {
            $0.players[guestIndex].tank = Vec2f(x: 105.5, y: 105.5)
            $0.players[guestIndex].dir = 0
            $0.players[guestIndex].inputFlags = [.accel]
        }
        try await waitFor(timeout: 5) { guest.state.local.armour < maxArmour }
        #expect(guest.state.local.armour < maxArmour, "the detonation's damage must arrive via SRTankStatus")
        #expect(engine.state.terrain[108, 105] != .minedGrass, "the host detonated the mine")
    }
}

// #62 S5 -- the guest sees its OWN shells and its own death explosion. Both live only on the host
// (it simulates the guest's tank); the host sends them as `SRTankShots` and the guest just
// applies them (this harness runs no `shellTick`/`explosionTick` of its own, like the thinned
// guest).

@Test(.timeLimit(.minutes(1))) func aSimulatedGuestSeesItsOwnShellInFlightAndThenSeesItGone() async throws {
    try await withHostedGuest { engine, guest, guestIndex in
        try await waitFor(timeout: 10) { !engine.state.players[guestIndex].dead && guest.state.local.shells == maxShells }
        #expect(guest.state.local.shells == maxShells)
        guest.mutate { $0.players[guestIndex].inputFlags = [.shoot] }
        try await waitFor(timeout: 5) { !guest.state.players[guestIndex].shells.isEmpty }
        #expect(!guest.state.players[guestIndex].shells.isEmpty, "the host's shell for this guest must reach it")
        #expect(guest.state.players[guestIndex].shells.allSatisfy { $0.owner == UInt8(guestIndex) })

        // Stop firing: once the last shell lands the host sends an empty list, clearing the guest's.
        guest.mutate { $0.players[guestIndex].inputFlags = [] }
        try await waitFor(timeout: 5) { guest.state.players[guestIndex].shells.isEmpty }
        #expect(guest.state.players[guestIndex].shells.isEmpty, "a landed shell must disappear from the guest too")
    }
}

@Test(.timeLimit(.minutes(1))) func aSimulatedGuestSeesItsOwnDeathExplosion() async throws {
    // A line of mines two tiles apart: each step east detonates one on its own (adjacent mines
    // would chain into a single explosion), and enough separate detonations kill the guest.
    try await withHostedGuest(configure: { state in
        for x in stride(from: 108, through: 118, by: 2) { state.terrain[x, 105] = .minedGrass }
    }) { engine, guest, guestIndex in
        try await waitFor(timeout: 10) { !engine.state.players[guestIndex].dead && guest.state.local.armour == maxArmour }
        guest.mutate {
            $0.players[guestIndex].tank = Vec2f(x: 105.5, y: 105.5)
            $0.players[guestIndex].dir = 0
            $0.players[guestIndex].inputFlags = [.accel]
        }
        try await waitFor(timeout: 8) { !guest.state.players[guestIndex].explosions.isEmpty }
        #expect(guest.state.players[guestIndex].dead, "the host killed the guest")
        #expect(!guest.state.players[guestIndex].explosions.isEmpty, "the guest's own death explosion must reach it")
    }
}
