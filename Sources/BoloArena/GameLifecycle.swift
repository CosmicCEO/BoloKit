import BoloKit
import BoloNet
import Foundation

enum GameLifecycleError: Error { case noPort }

/// Owns one round's real host engine + real in-process guest, and the teardown/rebuild that
/// `newgame` triggers. Mirrors `HostSimulatedSoakTests.swift`'s `makeSoakHost`/`runSoakRound`
/// shape (a proven pattern in this exact codebase), generalized from "run random inputs for N
/// seconds" to "stay up indefinitely, driven by two control channels, until told to reset."
final class GameLifecycle: @unchecked Sendable {
    let hostBox: StateBox
    let guestBox: StateBox

    private var gameId = 0
    private var engine: HostGameEngine?
    private var tasks: [Task<Void, Never>] = []
    private var joinedSession: TCPSession?
    private var udpSession: UDPSession?
    private let anomalyLog: AnomalyLog

    /// Host player is always slot 0; the guest's slot is whatever the join handshake assigns
    /// (recorded once the join succeeds).
    private static let hostSlot = 0

    init(anomalyLog: AnomalyLog) {
        self.anomalyLog = anomalyLog
        hostBox = StateBox(state: GameState(), phase: .joining, gameId: 0, playerIndex: Self.hostSlot)
        guestBox = StateBox(state: GameState(), phase: .joining, gameId: 0, playerIndex: 0)
    }

    /// Tears down the current round (if any) and starts a fresh one. Safe to call repeatedly --
    /// this is the host-seat-only `newgame` command's implementation. Returns once the new round
    /// exists (host engine ticking); does NOT block on the join handshake completing -- callers
    /// poll `observe`'s `phase` for `.ready`.
    func newGame() async {
        teardown()
        gameId += 1
        let myGameId = gameId
        hostBox.resetRound(state: GameState(), phase: .joining, gameId: myGameId, playerIndex: Self.hostSlot)
        guestBox.resetRound(state: GameState(), phase: .joining, gameId: myGameId, playerIndex: 0)

        Task { [weak self] in
            guard let self else { return }
            do {
                try await self.buildRound(gameId: myGameId)
            } catch {
                FileHandle.standardError.write(Data("BoloArena: round \(myGameId) failed to start: \(error)\n".utf8))
            }
        }
    }

    // MARK: - Host-seat commands (guest-seat commands go through `guestBox` directly, from
    // `ControlServer` -- the host seat has no equivalent local-state box to mutate, its only
    // entry point into the engine is these `submitLocal*` calls).

    func hostSubmitInput(_ flags: InputFlags) {
        let previous = hostBox.currentFlags
        hostBox.setFlags(flags)
        engine?.submitLocalInputChange(set: flags.subtracting(previous), clear: previous.subtracting(flags))
    }

    func hostSubmitBuild(kind: BuilderCommandKind, target: Pointi) {
        engine?.submitLocalBuilderCommand(command: kind, target: target)
    }

    func hostSubmitMine() {
        engine?.submitLocalLayMineKeyDown()
    }

    private func teardown() {
        for task in tasks { task.cancel() }
        tasks.removeAll()
        joinedSession?.cancel()
        udpSession?.cancel()
        joinedSession = nil
        udpSession = nil
        engine?.stop()
        engine = nil
    }

    private func makeMap() -> GameState {
        var state = GameState()
        state.hostSimulatesRemotePlayers = true
        var host = PlayerState()
        host.name = "Host"
        host.connected = true
        host.used = true
        host.dead = true
        host.alliance = UInt16(1 << 0)
        state.players = hostPlayerSlots(hostPlayer: host)
        state.localPlayer = Self.hostSlot
        state.local.respawnCounter = respawnTicks - 1

        // A modest grass arena (90..<170 on each axis -- a generous 15-tile margin around both
        // start points, found the hard way: a first version stopped the grass at 100..<160 with
        // starts right at (105,105)/(155,155), and real play surfaced a genuine infinite
        // death-loop where the spawn/parachute scatter occasionally landed a tank just outside
        // that boundary, into the default map's open sea, drowning it every single respawn) with
        // a lake, a forest patch for build materials, and one neutral pill/base pair worth
        // fighting over. Fully grown grass, matching what a decoded join-path map yields
        // (avoids a growth-variant-only divergence between host and guest terrain copies).
        for y in 90..<170 { for x in 90..<170 { state.terrain.storage[y * 256 + x] = Terrain.grass3.rawValue } }
        for y in 125..<135 { for x in 120..<130 { state.terrain[x, y] = .sea } }
        for y in 100..<108 { for x in 145..<155 { state.terrain[x, y] = .forest } }
        state.starts = [Start(x: 105, y: 105, dir: 4), Start(x: 155, y: 155, dir: 12)]
        // `armour: 20` here previously exceeded `maxPillArmour` (15) -- `displayTile(forPill:)`
        // (`BMap.swift:101`) computes `Tile.neutralPill00.rawValue + armour` unconditionally and
        // force-unwraps the result, so a pill armour above 15 crashed the whole process the
        // moment anything asked for that tile's display value. Found by real play (a build/
        // repair command on this pill), not by inspection -- exactly what this tool is for.
        state.pills = [Pill(x: 130, y: 105, armour: UInt8(maxPillArmour), owner: playerNeutral, speed: 50, counter: 0)]
        state.bases = [Base(x: 105, y: 155, armour: 20, owner: playerNeutral, shells: 30, mines: 5)]
        return state
    }

    private func buildRound(gameId myGameId: Int) async throws {
        var lastError: Error = GameLifecycleError.noPort
        for _ in 0..<8 {
            let port = UInt16.random(in: 49_152...65_000)
            let tcp: HostListener
            do { tcp = try await HostListener(port: port) }
            catch let error as POSIXError where error.code == .EADDRINUSE { lastError = error; continue }
            let udp: HostDgramListener
            do { udp = try await HostDgramListener(port: port) }
            catch let error as POSIXError where error.code == .EADDRINUSE { tcp.cancel(); lastError = error; continue }

            let engine = HostGameEngine(initialState: makeMap(), listener: tcp, dgramListener: udp)
            self.engine = engine
            let hostBox = self.hostBox
            engine.onTickRendered = { [weak self] state in
                guard let self, self.gameId == myGameId else { return }
                hostBox.update(state)
                self.anomalyLog.sample(hostState: state, gameId: myGameId)
            }
            engine.start()
            hostBox.setPhase(.ready)

            try await joinGuest(port: port, gameId: myGameId)
            return
        }
        throw lastError
    }

    private func joinGuest(port: UInt16, gameId myGameId: Int) async throws {
        let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
        var initial = GameState()
        initial.players = (0..<maxPlayers).map { _ in PlayerState() }
        guard applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial) else {
            joined.session.cancel()
            throw GameLifecycleError.noPort
        }
        let g = initial.localPlayer
        let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
        joinedSession = joined.session
        udpSession = udp

        guestBox.resetRound(state: initial, phase: .ready, gameId: myGameId, playerIndex: g)

        let guestBox = self.guestBox
        let udpReceiver = Task {
            while !Task.isCancelled {
                guard let data = try? await udp.receiveOneRawDatagram() else { return }
                guestBox.mutate { state in _ = udp.apply(data, myOwnSeq: 0, state: &state) }
            }
        }
        let udpSender = Task {
            var localSeq: Int32 = 0
            while !Task.isCancelled {
                localSeq += 1
                if localSeq % 5 == 0 {
                    var seqs = udp.allRemoteSeqsAsUInt32()
                    seqs[g] = UInt32(bitPattern: localSeq)
                    let update = assembleClUpdate(player: g, state: guestBox.snapshot.state, seq: seqs)
                    try? await udp.sendLocalUpdate(update.encode())
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        let tcpReceiver = Task {
            while !Task.isCancelled {
                guard let message = try? await joined.session.receiveOneRawMessage() else { return }
                guestBox.mutate { state in _ = try? TCPSession.dispatch(message, state: &state) }
            }
        }
        // Movement + tile-entry + builder tick, once per 20ms tick -- mirrors the real join
        // path's own per-tick sequence (`GameSession.swift`'s `.tick` handler), not the soak
        // test's thinner "movement only" version, since a real agent needs to actually build.
        let mover = Task {
            while !Task.isCancelled {
                // Fetched before `mutate` -- `StateBox`'s `NSLock` isn't reentrant, and
                // `takePendingBuild`/`takePendingMine` each acquire it themselves.
                let pendingBuild = guestBox.takePendingBuild()
                let pendingMine = guestBox.takePendingMine()
                var outboundTile: [JoinOutboundCL] = []
                var outboundBuilder: JoinOutboundBuilderCL? = nil
                guestBox.mutate { state in
                    guard !state.players[g].dead else { return }
                    let old = Pointi(x: Int32(state.players[g].tank.x), y: Int32(state.players[g].tank.y))
                    tankMoveTick(player: g, state: &state)
                    let new = Pointi(x: Int32(state.players[g].tank.x), y: Int32(state.players[g].tank.y))
                    outboundTile = detectJoinTileEntry(new: new, old: old, state: state)

                    if let (kind, target) = pendingBuild {
                        queueBuilderCommand(command: kind, target: target, player: g, state: &state)
                    }
                    outboundBuilder = builderTick(
                        player: g, state: &state,
                        joinArrive: { player, state in detectJoinBuilderArrival(player: player, state: state) }
                    )
                    if pendingMine {
                        let t = state.players[g].tank
                        outboundTile.append(.dropMine(x: Int(t.x), y: Int(t.y)))
                    }
                }
                guestBox.noteMutated()

                for message in outboundTile {
                    let bytes: [UInt8]
                    switch message {
                    case .grabTile(let x, let y): bytes = CLGrabTile(x: UInt8(x), y: UInt8(y)).encode()
                    case .dropBoat(let x, let y): bytes = CLDropBoat(x: UInt8(x), y: UInt8(y)).encode()
                    case .dropMine(let x, let y): bytes = CLDropMine(x: UInt8(x), y: UInt8(y)).encode()
                    }
                    try? await joined.session.send(bytes)
                }
                if let outboundBuilder {
                    let bytes: [UInt8]
                    switch outboundBuilder {
                    case .grabTrees(let x, let y): bytes = CLGrabTrees(x: UInt8(x), y: UInt8(y)).encode()
                    case .buildRoad(let x, let y, let trees): bytes = CLBuildRoad(x: UInt8(x), y: UInt8(y), trees: UInt8(trees)).encode()
                    case .buildWall(let x, let y, let trees): bytes = CLBuildWall(x: UInt8(x), y: UInt8(y), trees: UInt8(trees)).encode()
                    case .buildBoat(let x, let y, let trees): bytes = CLBuildBoat(x: UInt8(x), y: UInt8(y), trees: UInt8(trees)).encode()
                    case .buildPill(let x, let y, let trees, let pill): bytes = CLBuildPill(x: UInt8(x), y: UInt8(y), trees: UInt8(trees), pill: UInt8(pill)).encode()
                    case .repairPill(let x, let y, let trees): bytes = CLRepairPill(x: UInt8(x), y: UInt8(y), trees: UInt8(trees)).encode()
                    case .placeMine(let x, let y): bytes = CLPlaceMine(x: UInt8(x), y: UInt8(y), mines: 0).encode()
                    }
                    try? await joined.session.send(bytes)
                }
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
        }
        tasks = [udpReceiver, udpSender, tcpReceiver, mover]

        // Wait for the host to spawn the guest before reporting `.ready` (mirrors the soak
        // test's own spawn wait) -- purely cosmetic for `phase`, since `observe` already works
        // before this resolves. Reads `hostBox`'s cached snapshot (fed by `onTickRendered`),
        // never `engine.state` directly -- see this file's own #139 discipline note.
        let hostBoxRef = self.hostBox
        let spawnDeadline = Date().addingTimeInterval(20)
        while hostBoxRef.snapshot.state.players.indices.contains(g), hostBoxRef.snapshot.state.players[g].dead,
              Date() < spawnDeadline {
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
}
