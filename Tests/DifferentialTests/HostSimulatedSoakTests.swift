import Foundation
import Testing
import BoloKit
import BoloNet

// Reliability soak for the host-simulated guest model (#62). Real host (`HostListener` +
// `HostDgramListener` + `HostGameEngine`, `hostSimulatesRemotePlayers` on) against one real guest
// (`TCPSession.join` + `UDPSession`) over loopback; both sides play random inputs for a while,
// then everything is checked for consistency. Gated so normal suites never run it:
//
//   BOLO_SOAK=1 [BOLO_SOAK_SECONDS=60] [BOLO_SOAK_SEED=<n>] swift test --filter HostSimulatedSoakTests
//
// Two rounds (Hidden Mines off, then on), each BOLO_SOAK_SECONDS long. The seed drives every
// random choice made by the two players (real-time scheduling is still nondeterministic); it is
// printed on the first line so a failure can be replayed with BOLO_SOAK_SEED.

private let soakEnabled = ProcessInfo.processInfo.environment["BOLO_SOAK"] == "1"

private struct SoakRNG: RandomNumberGenerator {
    var state: UInt64
    mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

private final class SoakGuestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    init(_ state: GameState) { _state = state }
    var state: GameState { lock.lock(); defer { lock.unlock() }; return _state }
    func mutate(_ body: (inout GameState) -> Void) { lock.lock(); body(&_state); lock.unlock() }
}

private final class SoakCounters: @unchecked Sendable {
    private let lock = NSLock()
    private var _tcpMessages = 0
    private var _statusMessages = 0
    private var _shotsMessages = 0
    private var _revealMessages = 0
    private var _lastStatus = Date()
    private var _maxStatusGap: TimeInterval = 0

    func record(_ opcode: ServerOpcode) {
        lock.lock(); defer { lock.unlock() }
        _tcpMessages += 1
        switch opcode {
        case .tankStatus:
            _statusMessages += 1
            let now = Date()
            _maxStatusGap = max(_maxStatusGap, now.timeIntervalSince(_lastStatus))
            _lastStatus = now
        case .tankShots: _shotsMessages += 1
        case .revealTerrain: _revealMessages += 1
        default: break
        }
    }
    var snapshot: (tcp: Int, status: Int, shots: Int, reveals: Int, maxStatusGap: TimeInterval) {
        lock.lock(); defer { lock.unlock() }
        return (_tcpMessages, _statusMessages, _shotsMessages, _revealMessages, _maxStatusGap)
    }
}

private enum SoakError: Error { case noPort }

private struct SoakReport {
    var label: String
    var violations: [String] = []
    var notes: [String] = []
    var hostDeaths = 0
    var guestDeaths = 0
    var guestRespawns = 0
    var minGuestShells = maxShells
    var minHostArmour = maxArmour
    var minGuestArmour = maxArmour
    var messages: (tcp: Int, status: Int, shots: Int, reveals: Int, maxStatusGap: TimeInterval) = (0, 0, 0, 0, 0)
    var samples = 0
}

private let minedVariants: Set<Int32> = Set(
    [Terrain.minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass].map { $0.rawValue }
)

private func randomInputs(_ rng: inout SoakRNG) -> InputFlags {
    var flags: InputFlags = []
    if Double.random(in: 0..<1, using: &rng) < 0.70 { flags.insert(.accel) }
    if Double.random(in: 0..<1, using: &rng) < 0.10 { flags.insert(.brake) }
    let turn = Double.random(in: 0..<1, using: &rng)
    if turn < 0.20 { flags.insert(.turnL) } else if turn < 0.40 { flags.insert(.turnR) }
    if Double.random(in: 0..<1, using: &rng) < 0.30 { flags.insert(.shoot) }
    if Double.random(in: 0..<1, using: &rng) < 0.20 { flags.insert(.lmine) }
    if Double.random(in: 0..<1, using: &rng) < 0.10 { flags.insert(.incre) }
    if Double.random(in: 0..<1, using: &rng) < 0.10 { flags.insert(.decre) }
    return flags
}

private let allInputFlags: InputFlags = [.accel, .brake, .turnL, .turnR, .lmine, .shoot, .incre, .decre]

private func makeSoakHost(hiddenMines: Bool) async throws -> (engine: HostGameEngine, port: UInt16) {
    for _ in 0..<8 {
        let port = UInt16.random(in: 49_152...65_000)
        let tcp: HostListener
        do { tcp = try await HostListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        let udp: HostDgramListener
        do { udp = try await HostDgramListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { tcp.cancel(); continue }

        var state = GameState()
        state.hiddenMines = hiddenMines
        var host = PlayerState()
        host.name = "Host"
        host.connected = true
        host.used = true
        host.dead = true
        host.alliance = UInt16(1 << 0)
        state.players = hostPlayerSlots(hostPlayer: host)
        state.localPlayer = 0
        state.local.respawnCounter = respawnTicks - 1
        state.hostSimulatesRemotePlayers = true
        // Fully grown grass, which is what a map decoded on the join path yields (`grass0` would
        // differ from the guest's copy purely by growth-variant encoding).
        for y in 100..<120 { for x in 100..<120 { state.terrain.storage[y * 256 + x] = Terrain.grass3.rawValue } }
        // Deep water east of the start (drowning) and a small lake south of it.
        for y in 100..<120 { state.terrain[113, y] = .sea }
        for y in 112..<116 { for x in 100..<106 { state.terrain[x, y] = .sea } }
        state.starts = [Start(x: 105, y: 105, dir: 0)]
        return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
    }
    throw SoakError.noPort
}

private func nearIndices(around p: Vec2f, radius: Double) -> [Int] {
    var out: [Int] = []
    let cx = Int(p.x), cy = Int(p.y)
    let r = Int(radius.rounded(.up)) + 1
    for dy in -r...r {
        for dx in -r...r {
            let x = cx + dx, y = cy + dy
            guard x >= 0, x < 256, y >= 0, y < 256 else { continue }
            let ddx = Double(x) + 0.5 - Double(p.x), ddy = Double(y) + 0.5 - Double(p.y)
            if (ddx * ddx + ddy * ddy).squareRoot() <= radius { out.append(y * 256 + x) }
        }
    }
    return out
}

private func runSoakRound(hiddenMines: Bool, seconds: Double, seed: UInt64) async throws -> SoakReport {
    var report = SoakReport(label: hiddenMines ? "hidden-mines-ON" : "hidden-mines-OFF")
    let (engine, port) = try await makeSoakHost(hiddenMines: hiddenMines)
    engine.start()
    defer { engine.stop() }

    let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
    var initial = GameState()
    initial.players = (0..<maxPlayers).map { _ in PlayerState() }
    guard applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial) else {
        report.violations.append("guest could not apply the join preamble")
        return report
    }
    let g = initial.localPlayer
    let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
    let guest = SoakGuestBox(initial)
    let counters = SoakCounters()
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
                seqs[g] = UInt32(bitPattern: localSeq)
                let update = assembleClUpdate(player: g, state: guest.state, seq: seqs)
                try? await udp.sendLocalUpdate(update.encode())
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    let tcpReceiver = Task {
        while !Task.isCancelled {
            guard let message = try? await joined.session.receiveOneRawMessage() else { return }
            counters.record(message.opcode)
            guest.mutate { state in _ = try? TCPSession.dispatch(message, state: &state) }
        }
    }
    // The thinned guest owns only its movement (`GameSession`'s join `.tick`), and not while dead.
    let mover = Task {
        while !Task.isCancelled {
            guest.mutate { state in
                if !state.players[g].dead { tankMoveTick(player: g, state: &state) }
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    defer { udpReceiver.cancel(); udpSender.cancel(); tcpReceiver.cancel(); mover.cancel() }

    // Wait for the host to spawn the guest before any random play.
    let spawnDeadline = Date().addingTimeInterval(20)
    while engine.state.players[g].dead, Date() < spawnDeadline { try await Task.sleep(nanoseconds: 20_000_000) }
    if engine.state.players[g].dead { report.violations.append("guest never spawned within 20 s") }

    // Random players.
    let stop = ManagedFlag()
    let hostRNGSeed = seed ^ 0xA5A5_A5A5
    let guestRNGSeed = seed ^ 0x5A5A_5A5A
    let hostPlayer = Task {
        var rng = SoakRNG(state: hostRNGSeed)
        var current: InputFlags = []
        while !Task.isCancelled, !stop.isSet {
            let desired = randomInputs(&rng)
            engine.submitLocalInputChange(set: desired.subtracting(current), clear: current.subtracting(desired))
            current = desired
            if Double.random(in: 0..<1, using: &rng) < 0.15 { engine.submitLocalLayMineKeyDown() }
            if Double.random(in: 0..<1, using: &rng) < 0.10 {
                let t = engine.state.players[0].tank
                let kinds: [BuilderCommandKind] = [.tree, .road, .wall, .pill, .mine]
                let kind = kinds[Int.random(in: 0..<kinds.count, using: &rng)]
                let tx = Int(t.x) + Int.random(in: -4...4, using: &rng)
                let ty = Int(t.y) + Int.random(in: -4...4, using: &rng)
                if tx >= 1, tx < 255, ty >= 1, ty < 255 {
                    engine.submitLocalBuilderCommand(command: kind, target: Pointi(x: Int32(tx), y: Int32(ty)))
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    let guestPlayer = Task {
        var rng = SoakRNG(state: guestRNGSeed)
        while !Task.isCancelled, !stop.isSet {
            let desired = randomInputs(&rng)
            guest.mutate { $0.players[g].inputFlags = desired }
            if Double.random(in: 0..<1, using: &rng) < 0.10 {
                let s = guest.state
                if !s.players[g].dead {
                    let tx = Int(s.players[g].tank.x), ty = Int(s.players[g].tank.y)
                    if tx >= 0, tx < 256, ty >= 0, ty < 256 {
                        try? await joined.session.send(CLDropMine(x: UInt8(tx), y: UInt8(ty)).encode())
                    }
                }
            }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
    }
    defer { hostPlayer.cancel(); guestPlayer.cancel() }

    // Sampler: continuous invariants.
    var everNear = Set<Int>()
    var pendingMined: [Int: Int] = [:]
    var recorded = Set<Int>()
    var prevGuestDead = engine.state.players[g].dead
    var prevHostDead = engine.state.players[0].dead
    let deadline = Date().addingTimeInterval(seconds)
    while Date() < deadline {
        try await Task.sleep(nanoseconds: 50_000_000)
        let hs = engine.state
        let gs = guest.state
        report.samples += 1

        // Ranges (host truth).
        let hg = hs.localStats[g]
        if !(0...maxArmour).contains(hg.armour) { report.violations.append("guest armour out of range: \(hg.armour) tick \(hs.ticks)") }
        if !(0...maxShells).contains(hg.shells) { report.violations.append("guest shells out of range: \(hg.shells) tick \(hs.ticks)") }
        if !(0...maxMines).contains(Int(hs.players[g].mines)) { report.violations.append("guest mines out of range: \(hs.players[g].mines) tick \(hs.ticks)") }
        if !(0...maxArmour).contains(hs.local.armour) { report.violations.append("host armour out of range: \(hs.local.armour) tick \(hs.ticks)") }
        if !(0...maxShells).contains(hs.local.shells) { report.violations.append("host shells out of range: \(hs.local.shells) tick \(hs.ticks)") }
        if !(0...maxMines).contains(Int(hs.players[0].mines)) { report.violations.append("host mines out of range: \(hs.players[0].mines) tick \(hs.ticks)") }

        report.minGuestShells = min(report.minGuestShells, gs.local.shells)
        report.minHostArmour = min(report.minHostArmour, hs.local.armour)
        report.minGuestArmour = min(report.minGuestArmour, hg.armour)
        let gd = hs.players[g].dead, hd = hs.players[0].dead
        if gd && !prevGuestDead { report.guestDeaths += 1 }
        if !gd && prevGuestDead { report.guestRespawns += 1 }
        if hd && !prevHostDead { report.hostDeaths += 1 }
        prevGuestDead = gd; prevHostDead = hd

        // Fog invariants (host truth), Hidden Mines only.
        if hiddenMines {
            for (name, idx) in [("host", 0), ("guest", g)] {
                if let fog = hs.hiddenMines ? engine.fogState(for: idx)?.fog : nil, fog.contains(where: { $0 < 0 }) {
                    report.violations.append("negative fog count in \(name)'s FogState at tick \(hs.ticks)")
                }
            }
            // A mine may show on the guest only where its tank (as the host or the guest sees it) has
            // been within the 2.0-tile proximity reveal (2.0 plus slack for latency/sampling).
            for i in nearIndices(around: gs.players[g].tank, radius: 3.0) { everNear.insert(i) }
            for i in nearIndices(around: hs.players[g].tank, radius: 3.0) { everNear.insert(i) }
            var stillMined = Set<Int>()
            for (i, v) in gs.terrain.storage.enumerated() where minedVariants.contains(v) && !everNear.contains(i) {
                stillMined.insert(i)
                let n = (pendingMined[i] ?? 0) + 1
                pendingMined[i] = n
                if n >= 6, !recorded.contains(i) {
                    recorded.insert(i)
                    report.violations.append("mine visible on guest outside proximity at (\(i % 256),\(i / 256)) host tick \(hs.ticks)")
                }
            }
            pendingMined = pendingMined.filter { stillMined.contains($0.key) }
        }
    }

    // Quiesce and require eventual consistency.
    stop.set()
    engine.submitLocalInputChange(set: [], clear: allInputFlags)
    guest.mutate { $0.players[g].inputFlags = [] }
    try await Task.sleep(nanoseconds: 2_000_000_000)

    func divergence() -> String? {
        let hs = engine.state, gs = guest.state
        if hs.players[g].dead != gs.players[g].dead { return "dead flag differs: host \(hs.players[g].dead) guest \(gs.players[g].dead)" }
        if hs.localStats[g].armour != gs.local.armour { return "armour differs: host \(hs.localStats[g].armour) guest \(gs.local.armour)" }
        if hs.localStats[g].shells != gs.local.shells { return "shells differ: host \(hs.localStats[g].shells) guest \(gs.local.shells)" }
        if hs.players[g].mines != gs.players[g].mines { return "mines differ: host \(hs.players[g].mines) guest \(gs.players[g].mines)" }
        if hs.players[g].boat != gs.players[g].boat { return "boat flag differs: host \(hs.players[g].boat) guest \(gs.players[g].boat)" }
        if !hiddenMines {
            var diffs: [String] = []
            for i in hs.terrain.storage.indices where hs.terrain.storage[i] != gs.terrain.storage[i] {
                if diffs.count < 5 { diffs.append("(\(i % 256),\(i / 256)) host \(hs.terrain.storage[i]) guest \(gs.terrain.storage[i])") }
                else { diffs.append("..."); break }
            }
            if !diffs.isEmpty { return "terrain differs: " + diffs.joined(separator: "; ") }
        }
        return nil
    }
    var last: String?
    let settleDeadline = Date().addingTimeInterval(20)
    var clean = 0
    while Date() < settleDeadline {
        last = divergence()
        if last == nil { clean += 1; if clean >= 2 { break } } else { clean = 0 }
        try await Task.sleep(nanoseconds: 250_000_000)
    }
    if let last, clean < 2 { report.violations.append("no convergence after 20 s: \(last)") }

    let hsFinal = engine.state, gsFinal = guest.state
    if !hsFinal.players[g].dead {
        let t = hsFinal.players[g].tank
        let terr = hsFinal.terrain[Int(t.x), Int(t.y)]
        if hsFinal.players[g].boat, terr != .sea, terr != .river, terr != .boat {
            report.notes.append("guest tank alive on \(String(describing: terr)) with boat flag set (host truth) at tile (\(Int(t.x)),\(Int(t.y)))")
        }
    }
    _ = gsFinal

    report.messages = counters.snapshot
    return report
}

private final class ManagedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var value = false
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return value }
    func set() { lock.lock(); value = true; lock.unlock() }
}

@Test(.enabled(if: soakEnabled), .timeLimit(.minutes(10)))
func hostSimulatedGuestSoak() async throws {
    let env = ProcessInfo.processInfo.environment
    let seconds = Double(env["BOLO_SOAK_SECONDS"] ?? "") ?? 60
    let seed = UInt64(env["BOLO_SOAK_SEED"] ?? "") ?? UInt64.random(in: 1...UInt64.max)
    print("SOAK seed=\(seed) seconds=\(seconds) per round")

    for hiddenMines in [false, true] {
        let report = try await runSoakRound(hiddenMines: hiddenMines, seconds: seconds, seed: seed)
        print("SOAK [\(report.label)] samples=\(report.samples) guestDeaths=\(report.guestDeaths) guestRespawns=\(report.guestRespawns) hostDeaths=\(report.hostDeaths) minGuestShells=\(report.minGuestShells) minGuestArmour=\(report.minGuestArmour) minHostArmour=\(report.minHostArmour) tcp=\(report.messages.tcp) status=\(report.messages.status) shots=\(report.messages.shots) reveals=\(report.messages.reveals) maxStatusGap=\(String(format: "%.1f", report.messages.maxStatusGap))s")
        for note in report.notes { print("SOAK [\(report.label)] note: \(note)") }
        for v in report.violations.prefix(20) { print("SOAK [\(report.label)] VIOLATION: \(v)") }

        #expect(report.violations.isEmpty, "seed \(seed) [\(report.label)]: \(report.violations.prefix(5).joined(separator: " | "))")
        #expect(report.guestDeaths >= 1, "seed \(seed) [\(report.label)]: the guest never died (drowning/mines/shells should kill it in \(seconds) s)")
        #expect(report.guestRespawns >= 1, "seed \(seed) [\(report.label)]: the guest never respawned")
        #expect(report.messages.status >= 5, "seed \(seed) [\(report.label)]: the guest received only \(report.messages.status) SRTankStatus messages")
        #expect(report.minGuestShells < maxShells, "seed \(seed) [\(report.label)]: the guest's firing never spent shells on its HUD")
        #expect(report.minHostArmour < maxArmour, "seed \(seed) [\(report.label)]: the host's armour never dropped")
    }
}
