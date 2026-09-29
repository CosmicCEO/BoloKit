//
//  BenchAutopilot.swift
//  Bolo 2026
//
//  v1.6.9 baseline benchmark. Measurement only: does nothing unless the app is started with
//  `BOLO_BENCH_ROLE=host` or `BOLO_BENCH_ROLE=join`.
//
//  Runs the shipped app unattended: hosts or joins with the same calls the Host and Join forms
//  make, plays one side of a scenario through the same hooks the keyboard uses
//  (`GameRenderView.onInputFlagsChange` / `onLayMineKeyDown` / `onBuilderCommand`), then quits.
//  The decisions themselves are `BoloNet`'s pure functions (`BenchScenario.swift`); this file
//  only reads state, presses keys and keeps time.
//
//    BOLO_BENCH=1                 record (see `BenchRecorder.swift`)
//    BOLO_BENCH_ROLE=host|join    which side of the scenario to play
//    BOLO_BENCH_SCENARIO=<name>   a name from `BenchScenarios`, or a path to a scenario JSON
//    BOLO_BENCH_HOST=<address>    join only; default 127.0.0.1
//    BOLO_BENCH_PORT=<port>       default 50000
//

import AppKit
import BoloKit
import BoloNet

@MainActor
enum BenchAutopilot {
    enum Role: String {
        case host
        case join
    }

    struct Config {
        var role: Role
        var scenario: BenchScenario
        var host: String
        var port: UInt16
    }

    /// Process exit codes, so the run script can tell a bad run from a finished one.
    enum Exit: Int32 {
        case finished = 0
        case badConfiguration = 64
        case hostingUnavailable = 65
        case joinFailed = 66
    }

    static let config: Config? = {
        let environment = ProcessInfo.processInfo.environment
        guard let role = environment["BOLO_BENCH_ROLE"].flatMap(Role.init(rawValue:)) else { return nil }
        let name = environment["BOLO_BENCH_SCENARIO"] ?? ""
        let scenario = BenchScenarios.named(name) ?? (try? BenchScenario.load(URL(fileURLWithPath: name)))
        guard let scenario else {
            FileHandle.standardError.write(Data("BenchAutopilot: unknown scenario '\(name)'\n".utf8))
            exit(Exit.badConfiguration.rawValue)
        }
        return Config(
            role: role, scenario: scenario, host: environment["BOLO_BENCH_HOST"] ?? "127.0.0.1",
            port: environment["BOLO_BENCH_PORT"].flatMap(UInt16.init) ?? 50_000
        )
    }()

    private static var runner: Task<Void, Never>?

    // MARK: Hosting and joining

    /// The screen to open on, or `nil` when not benchmarking. Never returns on failure: a run
    /// that could not host or join is ended with an exit code instead of played locally.
    static func launch() async -> AppScreen? {
        guard let config else { return nil }
        switch config.role {
        case .host: return await host(config)
        case .join: return await join(config)
        }
    }

    /// The bundled default map with the Host form's own default settings, as
    /// `HostGameView.startHosting` builds it.
    static func hostState(hiddenMines: Bool) -> GameState? {
        guard case .success(var state) = HostGameView.decodeAndPostProcessMap(bytes: defaultMapFileBytes) else {
            return nil
        }
        applyDefaultBundledMapOwners(&state)
        state.timeLimit = 0
        state.hiddenMines = hiddenMines
        state.pauseOnPlayerExit = false
        state.baseVisionEnabled = false
        state.passwordRequired = false
        state.serverPassword = ""
        state.dominationType = .open
        state.baseControlThreshold = 30

        var player = PlayerState()
        player.name = "BenchHost"
        player.connected = true
        player.used = true
        player.dead = true
        player.alliance = UInt16(1 << 0)
        state.local.respawnCounter = respawnTicks - 1
        state.players = hostPlayerSlots(hostPlayer: player)
        state.localPlayer = 0
        return state
    }

    private static func host(_ config: Config) async -> AppScreen {
        guard let state = hostState(hiddenMines: config.scenario.hiddenMines) else {
            end(.badConfiguration)
        }
        // The port may still be held for a moment by the run before this one.
        for attempt in 0..<10 {
            if attempt > 0 { try? await Task.sleep(for: .seconds(1)) }
            guard let listener = try? await HostListener(port: config.port) else { continue }
            guard let dgramListener = try? await HostDgramListener(port: config.port) else {
                listener.cancel()
                continue
            }
            let engine = HostGameEngine(
                initialState: networkHostState(from: state), listener: listener, dgramListener: dgramListener
            )
            engine.start()
            return .hosting(engine)
        }
        // The app itself falls back to local-only play here. A benchmark run must not.
        BoloBench.recorder?.record(.mark, sub: BenchMark.hostingFellBack.rawValue)
        end(.hostingUnavailable)
    }

    private static func join(_ config: Config) async -> AppScreen {
        // The host is started first but may not be listening yet.
        for _ in 0..<60 {
            if let joined = try? await TCPSession.join(host: config.host, port: config.port, name: "BenchGuest", pass: "") {
                var state = GameState()
                guard applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &state),
                    let udpSession = try? await UDPSession(
                        host: joined.session.remoteHost, port: joined.session.remotePort)
                else {
                    joined.session.cancel()
                    end(.joinFailed)
                }
                BoloBench.recorder?.record(.mark, sub: BenchMark.joined.rawValue)
                return .playing(tcpSession: joined.session, udpSession: udpSession, state: state)
            }
            try? await Task.sleep(for: .seconds(1))
        }
        end(.joinFailed)
    }

    private static func end(_ code: Exit) -> Never {
        BoloBench.recorder?.finish()
        exit(code.rawValue)
    }

    // MARK: Playing

    /// Starts this side's script against a running session. Called once the game view appears.
    static func attach(to session: GameSession) {
        guard let config, runner == nil else { return }
        let steps = config.role == .host ? config.scenario.host : config.scenario.guest
        runner = Task { @MainActor in
            var pilot = Pilot(session: session)
            await pilot.run(steps, settleMs: config.scenario.settleMs)
            await session.stop()
            end(.finished)
        }
    }

    private struct Pilot {
        let session: GameSession
        let recorder = BoloBench.recorder
        /// The keys this script is holding down.
        var held: InputFlags = []

        static let pollMs = 20
        static let steering: InputFlags = [.accel, .brake, .turnL, .turnR]

        var state: GameState { session.liveState }
        var me: Int { state.localPlayer }

        mutating func run(_ steps: [BenchStep], settleMs: Int) async {
            recorder?.record(.mark, sub: BenchMark.scenarioStart.rawValue)
            for (index, step) in steps.enumerated() {
                let reached = await perform(step, index: UInt32(index))
                let mark: BenchMark = reached ? .stepReached : .stepTimedOut
                recorder?.record(.mark, sub: mark.rawValue, id: UInt32(index))
            }
            press(wanted: [], managed: benchAllInputFlags, index: UInt32(steps.count))
            await pause(settleMs)
            recorder?.record(.mark, sub: BenchMark.scenarioEnd.rawValue, id: UInt32(steps.count))
        }

        private func pause(_ ms: Int) async {
            try? await Task.sleep(for: .milliseconds(ms))
        }

        /// Presses and releases whatever takes the `managed` keys from what is held to `wanted`.
        private mutating func press(wanted: InputFlags, managed: InputFlags, index: UInt32) {
            guard let change = benchKeyChange(from: held, to: wanted, managed: managed) else { return }
            held.formUnion(change.set)
            held.subtract(change.clear)
            recorder?.record(
                .input, sub: BenchInput.flags.rawValue, id: index, v0: UInt64(change.set.rawValue),
                v1: UInt64(change.clear.rawValue)
            )
            session.renderView.onInputFlagsChange?(change)
        }

        private mutating func layMine(index: UInt32) {
            recorder?.record(.input, sub: BenchInput.layMine.rawValue, id: index)
            session.renderView.onLayMineKeyDown?()
        }

        private mutating func order(_ kind: BuilderCommandKind, x: Int32, y: Int32, index: UInt32) {
            recorder?.record(
                .input, sub: BenchInput.builder.rawValue, id: index, v0: UInt64(kind.rawValue),
                v1: UInt64(UInt32(bitPattern: y)) << 32 | UInt64(UInt32(bitPattern: x))
            )
            session.renderView.onBuilderCommand?(kind, Pointi(x: x, y: y))
        }

        /// Polls `body` until it returns true or `timeoutMs` passes.
        private mutating func poll(timeoutMs: Int, _ body: (inout Pilot) -> Bool) async -> Bool {
            let deadline = ContinuousClock.now + .milliseconds(timeoutMs)
            while true {
                if body(&self) { return true }
                if ContinuousClock.now >= deadline { return false }
                await pause(Self.pollMs)
            }
        }

        private mutating func perform(_ step: BenchStep, index: UInt32) async -> Bool {
            switch step {
            case .wait(let ms):
                await pause(ms)
                return true

            case .until(let condition, let timeoutMs):
                return await poll(timeoutMs: timeoutMs) { pilot in
                    benchConditionHolds(condition, player: pilot.me, state: pilot.state)
                }

            case .keys(let set, let clear):
                let setFlags = set.reduce(into: InputFlags()) { $0.insert($1.flag) }
                let clearFlags = clear.reduce(into: InputFlags()) { $0.insert($1.flag) }
                press(
                    wanted: held.union(setFlags).subtracting(clearFlags), managed: setFlags.union(clearFlags),
                    index: index
                )
                return true

            case .driveTo(let x, let y, let radius, let timeoutMs):
                return await poll(timeoutMs: timeoutMs) { pilot in
                    let state = pilot.state
                    guard state.players.indices.contains(pilot.me), !state.players[pilot.me].dead else {
                        pilot.press(wanted: [], managed: Self.steering, index: index)
                        return false
                    }
                    let tank = state.players[pilot.me]
                    let decision = benchSteer(tank: tank.tank, dir: tank.dir, x: x, y: y, radius: radius)
                    pilot.press(wanted: decision.flags, managed: Self.steering, index: index)
                    // Arrived means stopped there, not passing through.
                    return decision.arrived && tank.speed == 0
                }

            case .driveUntil(let x, let y, let radius, let condition, let timeoutMs):
                return await poll(timeoutMs: timeoutMs) { pilot in
                    let state = pilot.state
                    if benchConditionHolds(condition, player: pilot.me, state: state) {
                        pilot.press(wanted: [], managed: Self.steering, index: index)
                        return true
                    }
                    guard state.players.indices.contains(pilot.me), !state.players[pilot.me].dead else {
                        pilot.press(wanted: [], managed: Self.steering, index: index)
                        return false
                    }
                    let tank = state.players[pilot.me]
                    let decision = benchSteer(tank: tank.tank, dir: tank.dir, x: x, y: y, radius: radius)
                    pilot.press(wanted: decision.flags, managed: Self.steering, index: index)
                    return false
                }

            case .face(let x, let y, let timeoutMs):
                return await poll(timeoutMs: timeoutMs) { pilot in
                    let state = pilot.state
                    guard state.players.indices.contains(pilot.me), !state.players[pilot.me].dead else { return false }
                    let tank = state.players[pilot.me]
                    let decision = benchFace(tank: tank.tank, dir: tank.dir, x: x, y: y)
                    pilot.press(wanted: decision.flags, managed: Self.steering, index: index)
                    return decision.facing
                }

            case .layMine:
                layMine(index: index)
                return true

            case .builder(let tool, let x, let y):
                order(tool.command, x: Int32(x), y: Int32(y), index: index)
                return true

            case .mark:
                recorder?.record(.mark, sub: BenchMark.custom.rawValue, id: index)
                return true

            case .random(let seed, let seconds):
                var rng = BenchRNG(state: seed)
                let deadline = ContinuousClock.now + .seconds(seconds)
                while ContinuousClock.now < deadline {
                    let state = self.state
                    let tank = state.players.indices.contains(me) ? state.players[me].tank : Vec2f(x: 0, y: 0)
                    let action = benchRandomAction(&rng, tank: tank)
                    press(wanted: action.flags, managed: benchAllInputFlags, index: index)
                    if action.layMine { layMine(index: index) }
                    if let kind = action.builder { order(kind, x: action.target.x, y: action.target.y, index: index) }
                    await pause(benchRandomStepMs)
                }
                press(wanted: [], managed: benchAllInputFlags, index: index)
                return true
            }
        }
    }
}
