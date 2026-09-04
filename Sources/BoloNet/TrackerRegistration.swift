import Network
import Foundation
import BoloKit

// MARK: - Wave 6.5a — registerserver()'s handshake + sendtrackerupdate()'s heartbeat
//
// Ported from `registerserver()`'s wire-level protocol steps
// (`server.c:1259-1509`) -- NOT its POSIX mechanics, same D31/D42
// precedent every prior transport wave has followed: the real function's
// `nslookup`/`select`/non-blocking-`connect` dance is exactly the
// "transliterated POSIX glue" those decisions already ruled out. DNS
// resolution is not reimplemented either, for the same reason
// `JoinClient.swift` doesn't reimplement it -- `NWEndpoint.hostPort`
// resolves hostnames internally.
//
// `TrackerSession` uses the classic completion-handler `NWConnection` API
// (`TCPSession.swift`/`UDPSession.swift`'s precedent), not
// `withNetworkConnection` (`JoinClient.swift`'s one-shot, closure-scoped
// choice) -- a session that must stay open across the initial handshake
// AND every subsequent 60-second heartbeat is exactly the "persistent,
// freely-held session object" `UDPSession.swift`'s own header comment
// already argues for over a closure-scoped connection lifetime.
//
// **T-4 (tri-state return, disclosed mechanism substitution):**
// `registerserver()` returns 0 (success), 1 ("closed by main thread" --
// the real function's own cooperative-cancellation signal, checked at
// several `SUCCESS`-on-`FD_ISSET(server.mainpipe[0], ...)` points), or -1
// (error). This port has no separate polling thread to signal a
// same-shaped "please stop" -- Swift's structured concurrency already
// models cooperative cancellation via `Task` cancellation/
// `CancellationError`, so a caller that wants the same "abandon this
// registration attempt" behavior cancels the enclosing `Task` and gets a
// thrown `CancellationError` from the suspended network read/write,
// rather than this function needing a third return case of its own. The
// *observable* protocol behavior (version/TCP/UDP rejection each with
// their own distinct outcome) is fully preserved; only the "closed by
// main thread" mechanism is substituted, per D31/D42's latitude.
//
// **T-5:** `if (server.tracker.hostname)` (`server.c:1264`) wraps the
// entire body -- no tracker configured is success, not an error.
// `registerWithTracker` models this as `hostname == nil` returning `nil`
// rather than throwing, so LAN-only hosting stays a first-class,
// non-error path.

public enum TrackerRegistrationError: Error, Sendable, Equatable {
    /// `EBADVERSION` (`server.c:1376`) -- the daemon didn't answer
    /// `kTrackerVersionOK` to this port's `TRACKERVERSION`.
    case badVersion
    /// `ETCPCLOSED` (`server.c:1412`) -- the daemon couldn't open a TCP
    /// connection back to this host's advertised port.
    case tcpPortClosed
    /// `EUDPCLOSED` (`server.c:1492`) -- the daemon's UDP reachability
    /// probe (the `dgramserver()`-occurrence echo, already shipped in
    /// Wave 6.4b/6.4c per D48) never came back within the daemon's own
    /// probe window (`tracker.c:19-20`, 5 tries * 2s). This host's own
    /// `HostDgramListener` (already running, Wave 6.4c) must be live and
    /// reachable for this NOT to happen -- this function does not start
    /// or manage that listener itself, matching T-8's framing in the
    /// Wave 6.5a pre-brief.
    case udpPortClosed
    /// The connection closed, or sent malformed bytes, before a complete
    /// handshake step arrived.
    case connectionClosedEarly
}

/// Persistent connection to a tracker daemon, held open across the
/// initial registration handshake and every later 60-second heartbeat
/// (`TRACKERUPDATESECONDS`, `server.h:20`) until `cancel()`
/// (`stoptracker()`'s equivalent, `bolo.h:490`).
public final class TrackerSession: @unchecked Sendable {
    private let connection: NWConnection

    fileprivate init(host: String, port: UInt16) async throws {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        self.connection = connection
        try await Self.waitUntilReady(connection)
    }

    private static func waitUntilReady(_ connection: NWConnection) async throws {
        try await withCheckedThrowingContinuation { continuation in
            nonisolated(unsafe) var resumed = false
            connection.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    continuation.resume()
                case .failed(let error):
                    resumed = true
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            connection.start(queue: .main)
        }
    }

    private func send(_ bytes: [UInt8]) async throws {
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

    private func receiveExactly(_ count: Int) async throws -> [UInt8] {
        guard count > 0 else { return [] }
        return try await withCheckedThrowingContinuation { continuation in
            connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data, data.count == count {
                    continuation.resume(returning: Array(data))
                } else {
                    continuation.resume(throwing: TrackerRegistrationError.connectionClosedEarly)
                }
            }
        }
    }

    private func receiveOneByte() async throws -> UInt8 {
        try await receiveExactly(1)[0]
    }

    /// The nine-step handshake (`registerserver()`, `server.c:1259-
    /// 1509`, minus DNS/connect -- already done by `init`): send
    /// `TrackerPreamble` -> version ack -> send `kTrackerHost` +
    /// `TrackerHost` -> TCP-open ack -> UDP-open ack. Throws the specific
    /// `TrackerRegistrationError` for whichever step rejects.
    fileprivate func performHandshake(host: TrackerHost) async throws {
        try await send(TrackerPreamble().encode())

        let versionByte = try await receiveOneByte()
        guard TrackerVersionStatus(rawValue: versionByte) == .ok else {
            throw TrackerRegistrationError.badVersion
        }

        try await send([TrackerRequestType.host.rawValue] + host.encode())

        let tcpByte = try await receiveOneByte()
        guard TrackerTCPPortStatus(rawValue: tcpByte) == .ok else {
            throw TrackerRegistrationError.tcpPortClosed
        }

        let udpByte = try await receiveOneByte()
        guard TrackerUDPPortStatus(rawValue: udpByte) == .ok else {
            throw TrackerRegistrationError.udpPortClosed
        }
    }

    /// `sendtrackerupdate()` (`server.c:1569-1588`) -- a bare
    /// `TrackerHost`, no `kTrackerHost` request byte, no reply expected
    /// (the daemon's own post-registration loop just reads bare 60-byte
    /// structs forever, `tracker.c:293-301`). Uses `encodeAsHeartbeat()`,
    /// not `encode()` -- see `Tracker.swift`'s own doc comment for why
    /// those two differ (T-2/D56).
    ///
    /// Scheduling cadence (`servermainthread()`'s own 60s-interval,
    /// catch-up-if-late loop, `server.c:1590-1630`) is the caller's job,
    /// not this method's -- matches this codebase's established boundary
    /// that the network layer takes already-decided values and sends
    /// them, it doesn't make its own timing decisions
    /// (`UDPSession.sendLocalUpdate`'s own doc comment states the same
    /// principle for send cadence).
    public func sendHeartbeat(_ host: TrackerHost) async throws {
        try await send(host.encodeAsHeartbeat())
    }

    /// `stoptracker()` (`bolo.h:490`).
    public func cancel() {
        connection.cancel()
    }
}

/// Full registration attempt against `hostname:trackerPort`
/// (`registerserver()`, `server.c:1259-1509`). `nil` `hostname` is T-5's
/// short-circuit -- no tracker configured, a first-class success case,
/// not an error -- and returns `nil` rather than a session. A non-nil
/// `hostname` that succeeds returns a `TrackerSession` ready for
/// `sendHeartbeat`; any handshake rejection throws
/// `TrackerRegistrationError` and the connection is torn down before this
/// function returns (mirrors `registerserver()`'s own `CLEANUP` closing
/// `lookup`/`server.tracker.sock` on every non-success path).
///
/// `advertisedPort` is this host's own game-port -- the value
/// `TrackerHost.port` advertises to the daemon, NOT `trackerServerPort`
/// (the daemon's own listening port, `server.c:1382`'s
/// `htons(server.tracker.port)`, a genuinely different port number).
/// `trackerServerPort` defaults to the real `trackerPort` (`tracker.h:8`)
/// but is overridable for tests against a loopback fake daemon on an
/// ephemeral port, matching `listTrackerGames`'s identical parameter.
public func registerWithTracker(
    hostname: String?, trackerServerPort: UInt16 = trackerPort, advertisedPort: UInt16,
    hostPlayerName: String, mapName: String, state: GameState
) async throws -> TrackerSession? {
    guard let hostname else { return nil }

    let session = try await TrackerSession(host: hostname, port: trackerServerPort)
    let host = trackerHost(hostPlayerName: hostPlayerName, mapName: mapName, port: advertisedPort, state: state)
    do {
        try await session.performHandshake(host: host)
    } catch {
        session.cancel()
        throw error
    }
    return session
}
