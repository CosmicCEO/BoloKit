import Network
import BoloKit

// MARK: - Wave 6.5a — listtracker() client browse
//
// Ported from `listtracker()`'s wire-level protocol steps
// (`bolo.c:346-450`, `bolo.h:485-490`) -- NOT its POSIX mechanics, same
// D31/D42 precedent as every other transport wave. One-shot,
// closure-scoped handshake -- same shape as `joinClient`
// (`JoinClient.swift`), so this uses `withNetworkConnection`, not
// `TrackerSession`'s persistent classic-API session (`TrackerRegistration.
// swift`'s own header comment covers why registration/heartbeat need the
// persistent shape and this doesn't).

public enum TrackerBrowseError: Error, Sendable, Equatable {
    /// `EBADVERSION` (`bolo.c:429`).
    case badVersion
    /// The connection closed, or sent malformed bytes, before a complete
    /// response arrived.
    case connectionClosedEarly
    case malformedResponse
}

/// Fetches the tracker's current game list (`listtracker()`,
/// `bolo.c:346-450`): version handshake, `kTrackerList` request, a
/// `uint32_t` count (`ntohl`'d, `bolo.c:438`), then that many 64-byte
/// `TrackerHostList` entries. `stoptracker()`'s mid-fetch cancellation
/// (`bolo.h:490`) maps to this `Task`'s own cancellation, same T-4
/// mechanism substitution `TrackerRegistration.swift` already discloses
/// for `registerserver()`'s tri-state return.
public func listTrackerGames(hostname: String, port: UInt16 = trackerPort) async throws -> [TrackerHostList] {
    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(hostname), port: NWEndpoint.Port(rawValue: port)!)

    var outcome: Result<[TrackerHostList], Error>?

    try await withNetworkConnection(to: endpoint, using: { TCP() }) { connection in
        do {
            try await connection.send(TrackerPreamble().encode())

            let versionMessage = try await connection.receive(exactly: 1)
            guard let versionByte = versionMessage.content.first, TrackerVersionStatus(rawValue: versionByte) == .ok else {
                outcome = .failure(TrackerBrowseError.badVersion)
                return
            }

            try await connection.send([TrackerRequestType.list.rawValue])

            let countMessage = try await connection.receive(exactly: 4)
            let countBytes = Array(countMessage.content)
            let count = (UInt32(countBytes[0]) << 24) | (UInt32(countBytes[1]) << 16) | (UInt32(countBytes[2]) << 8) | UInt32(countBytes[3])

            var games: [TrackerHostList] = []
            games.reserveCapacity(Int(count))
            for _ in 0..<count {
                let entryMessage = try await connection.receive(exactly: TrackerHostList.wireSize)
                guard let entry = TrackerHostList.decode(Array(entryMessage.content)) else {
                    outcome = .failure(TrackerBrowseError.malformedResponse)
                    return
                }
                games.append(entry)
            }
            outcome = .success(games)
        } catch {
            outcome = .failure(error)
        }
    }

    guard let outcome else { throw TrackerBrowseError.connectionClosedEarly }
    return try outcome.get()
}
