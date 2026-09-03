import Network
import BoloKit

// MARK: - Wave 6.4a — client-side join handshake
//
// Ported from `joinclient()`'s wire-level protocol steps
// (`client.c:499-770`) -- NOT its POSIX mechanics. Per D42, the actual
// socket/`select`/`connect`/`bind` dance in the real function is exactly
// the "transliterated POSIX glue" D31 already ruled out; this is a fresh
// implementation of the same observable byte sequence
// (`JoinPreamble` -> status byte -> `BoloPreamble` -> map bytes) on
// `NWConnection`/async-await instead. DNS resolution (`joinclient()`'s
// own `nslookup`/`selectreadread` dance) is not reimplemented either --
// `NWEndpoint.hostPort` resolves hostnames internally, and D4 (no interop
// requirement) means there's no reason to duplicate that logic.

/// `bolo.h:190-198`'s join-message enum, wire values 0-6 -- the status
/// byte the server sends immediately after receiving a `JoinPreamble`.
public enum JoinStatusByte: UInt8, Sendable {
    case badVersion = 0
    case disallow = 1
    case badPassword = 2
    case serverFull = 3
    case serverTimeLimitReached = 4
    case bannedPlayer = 5
    case sendingPreamble = 6
}

/// Mirrors `joinclient()`'s status-byte switch (`client.c:637-644`) --
/// every non-`sendingPreamble` status maps to a specific rejection
/// reason, matching the C's own `EBADVERSION`/`EDISSALLOW`/etc. `E`-codes
/// one for one.
public enum JoinClientError: Error, Sendable, Equatable {
    case badVersion
    case disallow
    case badPassword
    case serverFull
    case serverTimeLimitReached
    case bannedPlayer
    /// The server sent a status byte outside `JoinStatusByte`'s known
    /// range -- `ESERVERERROR` in the C (`client.c:644`, the `else`
    /// branch of its status-byte switch).
    case serverProtocolError
    /// The connection closed (or the server sent malformed bytes) before
    /// a complete `BoloPreamble` + map payload arrived.
    case connectionClosedEarly
    case malformedPreamble

    fileprivate init(rejecting status: JoinStatusByte) {
        switch status {
        case .badVersion: self = .badVersion
        case .disallow: self = .disallow
        case .badPassword: self = .badPassword
        case .serverFull: self = .serverFull
        case .serverTimeLimitReached: self = .serverTimeLimitReached
        case .bannedPlayer: self = .bannedPlayer
        case .sendingPreamble:
            // Never actually constructed for this case -- `joinClient`
            // only calls this initializer once it's confirmed `status !=
            // .sendingPreamble`. Exhaustiveness only.
            self = .serverProtocolError
        }
    }
}

/// Performs the full join handshake against `host:port` and returns the
/// decoded `BoloPreamble` plus the raw map bytes that immediately follow
/// it on the wire (`bolopreamble.maplen` bytes, per `server.c:869`/
/// `client.c:661-680`) -- loading those bytes into a real map
/// (`BMap.swift`'s decoder, Wave 4.1) is the caller's job, not this
/// function's.
public func joinClient(host: String, port: UInt16, name: String, pass: String) async throws -> (preamble: BoloPreamble, mapData: [UInt8]) {
    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)

    var outcome: Result<(BoloPreamble, [UInt8]), Error>?

    try await withNetworkConnection(to: endpoint, using: { TCP() }) { connection in
        do {
            let joinPreamble = JoinPreamble(name: name, pass: pass)
            try await connection.send(joinPreamble.encode())

            let statusMessage = try await connection.receive(exactly: 1)
            guard let statusByte = statusMessage.content.first,
                  let status = JoinStatusByte(rawValue: statusByte)
            else {
                outcome = .failure(JoinClientError.serverProtocolError)
                return
            }
            guard status == .sendingPreamble else {
                outcome = .failure(JoinClientError(rejecting: status))
                return
            }

            let preambleMessage = try await connection.receive(exactly: BoloPreamble.wireSize)
            guard let preamble = BoloPreamble.decode(Array(preambleMessage.content)) else {
                outcome = .failure(JoinClientError.malformedPreamble)
                return
            }

            let mapMessage = try await connection.receive(exactly: Int(preamble.mapLength))
            outcome = .success((preamble, Array(mapMessage.content)))
        } catch {
            outcome = .failure(error)
        }
    }

    guard let outcome else { throw JoinClientError.connectionClosedEarly }
    return try outcome.get()
}
