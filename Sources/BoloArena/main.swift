import Foundation

// BoloArena: a real host+guest game of Bolo, driven by two independent HTTP control channels --
// one per seat -- so two real Claude agents can actually play against each other, repeatedly,
// while a machine-checked invariant/divergence log and each agent's own free-text `note` command
// both watch for anomalous play. Not shipped game functionality -- a soak/testing tool only.
//
// Usage: `swift run BoloArena` (ports/log dir overridable via BOLO_ARENA_HOST_PORT/
// BOLO_ARENA_GUEST_PORT/BOLO_ARENA_LOG_DIR). Each seat is one HTTP POST per turn:
//   curl -s -d '{"cmd":"observe"}' http://127.0.0.1:9101/
//
// `HostGameEngine.start()` schedules its tick timer on `DispatchQueue.main` -- a plain
// `async` top-level `main.swift` runs on Swift Concurrency's cooperative thread pool, NOT the
// real main thread, so nothing would ever service that queue without `dispatchMain()` actually
// blocking the real main thread. The async arena setup runs on a detached `Task`; the real main
// thread parks in `dispatchMain()` forever, servicing exactly the queue the tick timer needs.

let config = ArenaConfig.fromEnvironment()

// Top-level globals, not locals inside the setup `Task` below -- a `ControlServer`'s only
// strong-reference chain to its own `NWListener` lives on the `ControlServer` instance itself
// (`newConnectionHandler` captures `self` weakly), so a `let` scoped to the setup closure would
// deallocate the whole server -- listener included -- the moment that closure returned.
var lifecycle: GameLifecycle!
var hostServer: ControlServer!
var guestServer: ControlServer!
var sampler: Task<Void, Never>!

Task {
    do {
        let anomalyLog = try AnomalyLog(logDirectory: config.logDirectory)
        lifecycle = GameLifecycle(anomalyLog: anomalyLog, mapPath: config.mapPath)

        hostServer = ControlServer(
            seat: .host, port: config.hostControlPort, stateBox: lifecycle.hostBox,
            lifecycle: lifecycle, anomalyLog: anomalyLog
        )
        guestServer = ControlServer(
            seat: .guest, port: config.guestControlPort, stateBox: lifecycle.guestBox,
            lifecycle: lifecycle, anomalyLog: anomalyLog
        )
        try await hostServer.start()
        try await guestServer.start()
        sampler = InvariantSampler.start(hostBox: lifecycle.hostBox, guestBox: lifecycle.guestBox, anomalyLog: anomalyLog)

        await lifecycle.newGame()

        print("BoloArena ready -- host seat http://127.0.0.1:\(config.hostControlPort)/, guest seat http://127.0.0.1:\(config.guestControlPort)/")
        print("Logs: \(config.logDirectory.path)/violations.jsonl, \(config.logDirectory.path)/notes.jsonl")
        fflush(stdout)
    } catch {
        FileHandle.standardError.write(Data("BoloArena: startup failed: \(error)\n".utf8))
        exit(1)
    }
}

dispatchMain()
