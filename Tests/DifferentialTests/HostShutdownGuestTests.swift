import Foundation
import Testing
import BoloKit
import BoloNet

// Issue #107 -- when the host quits to the menu (`HostGameEngine.shutdown()`), a joined guest must
// learn the connection ended: its TCP receive path has to throw so `GameSession` can print the
// disconnected line. Real host, real guest, over loopback. Positive checks only: the ended flag is
// polled and the guest's blocked read is always released by cancelling its session.

private final class EndedFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var _ended = false
    private var _messagesBeforeEnd = 0
    var ended: Bool { lock.lock(); defer { lock.unlock() }; return _ended }
    var messagesBeforeEnd: Int { lock.lock(); defer { lock.unlock() }; return _messagesBeforeEnd }
    func sawMessage() { lock.lock(); _messagesBeforeEnd += 1; lock.unlock() }
    func end() { lock.lock(); _ended = true; lock.unlock() }
}

private enum ShutdownHarnessError: Error { case noPort }

private func makeShutdownHost() async throws -> (engine: HostGameEngine, port: UInt16) {
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
        for y in 100..<120 { for x in 100..<120 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
        state.starts = [Start(x: 105, y: 105, dir: 0)]
        return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
    }
    throw ShutdownHarnessError.noPort
}

private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
    let deadline = Date().addingTimeInterval(timeout)
    while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 10_000_000) }
}

@Test(.timeLimit(.minutes(1))) func hostShutdownEndsTheJoinedGuestsTCPReceive() async throws {
    let (engine, port) = try await makeShutdownHost()
    engine.start()

    let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
    defer { joined.session.cancel() }

    let flag = EndedFlag()
    let receiver = Task {
        while true {
            do {
                _ = try await joined.session.receiveOneRawMessage()
                flag.sawMessage()
            } catch {
                flag.end()
                return
            }
        }
    }
    defer { receiver.cancel() }

    try await waitUntil(timeout: 3) { flag.messagesBeforeEnd > 0 }
    #expect(!flag.ended, "the guest must stay connected while the host is running")

    await engine.shutdown()

    try await waitUntil(timeout: 5) { flag.ended }
    #expect(flag.ended, "the guest's receive must end when the host shuts down, so the disconnected line can be printed (#107)")
}
