import Network
import Foundation
import BoloKit

// MARK: - Wave 6.4a extension (D45) — persistent UDP session
//
// The persistent receive loop PARITY flagged as missing around the
// already-shipped `applyRemotePlayerUpdate` (Wave 6.4a,
// `DgramClientApply.swift`). Uses the classic completion-handler
// `NWConnection` API rather than `withNetworkConnection` (`JoinClient.
// swift`'s choice for its one-shot, closure-scoped handshake) -- a
// persistent, freely-held session object fits an imperative send/
// receive shape better than a closure-scoped connection lifetime. This
// is still genuine async/await-driven Network.framework usage per
// D31/D42 (every socket call is wrapped in a continuation, nothing
// blocks a thread), not the "transliterated POSIX glue" those rulings
// excluded -- it's a different part of the same framework's API surface.
//
// `import Foundation` here is new for production `BoloNet`/`BoloKit`
// code (every other production file avoids it; only test harnesses have
// needed it so far) -- the classic completion-handler API's
// `send(content: Data?, ...)` requires a concrete `Data` value, unlike
// the modern `withNetworkConnection` API `JoinClient.swift` uses, which
// never needs the type spelled out by its caller.

public enum UDPSessionError: Error {
    case malformedDatagram
}

public final class UDPSession: @unchecked Sendable {
    private let connection: NWConnection

    public init(host: String, port: UInt16) async throws {
        let connection = NWConnection(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!, using: .udp)
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

    /// Sends one already-encoded `CLUpdate` datagram. Cadence (the real
    /// `sendclupdate()`'s `seq % 5 == 0` decision) is the caller's job,
    /// not this session's -- matches the established "the network layer
    /// takes already-decided values, it doesn't make gameplay-cadence
    /// decisions" boundary (`RunTick.swift`'s own header disclosure for
    /// the same class of decision).
    public func sendLocalUpdate(_ bytes: [UInt8]) async throws {
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

    /// Receives one datagram and, if it decodes to a valid `CLUpdate`,
    /// applies it via `applyRemotePlayerUpdate` (Wave 6.4a). Returns the
    /// new `(seq, lastUpdate)` pair for the caller's own seq table on a
    /// successful apply, or `nil` if the datagram was malformed or the
    /// update was rejected (self-echo/stale/disconnected -- the same
    /// no-op conditions `applyRemotePlayerUpdate` itself already covers).
    @discardableResult
    public func receiveAndApply(
        previousRemoteSeq: Int32, previousRemoteLastUpdate: Int32, myOwnSeq: Int32, state: inout GameState,
        onPlayerLagStatusChanged: (Int) -> Void = { _ in },
        onTankShotSound: () -> Void = {},
        onPillShotSound: () -> Void = {},
        onSinkSound: () -> Void = {},
        onBuilderDeathSound: () -> Void = {},
        onDropPills: (UInt16, Vec2f) -> Void = { _, _ in },
        onMineExplosion: (Pointi) -> Void = { _ in },
        onSuperboomTerrain: (Pointi) -> Void = { _ in },
        onExplosion: (Vec2f) -> Void = { _ in },
        onSuperboom: () -> Void = {},
        onSmallboom: () -> Void = {},
        onSpawn: () -> Void = {}
    ) async throws -> (seq: Int32, lastUpdate: Int32)? {
        let data = try await receiveOneDatagram()
        guard let update = CLUpdate.decode(Array(data)) else { return nil }
        return applyRemotePlayerUpdate(
            header: update.header, shells: update.shells, explosions: update.explosions,
            previousRemoteSeq: previousRemoteSeq, previousRemoteLastUpdate: previousRemoteLastUpdate,
            myOwnSeq: myOwnSeq, state: &state,
            onPlayerLagStatusChanged: onPlayerLagStatusChanged, onTankShotSound: onTankShotSound,
            onPillShotSound: onPillShotSound, onSinkSound: onSinkSound, onBuilderDeathSound: onBuilderDeathSound,
            onDropPills: onDropPills, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain,
            onExplosion: onExplosion, onSuperboom: onSuperboom, onSmallboom: onSmallboom, onSpawn: onSpawn
        )
    }

    private func receiveOneDatagram() async throws -> Data {
        try await withCheckedThrowingContinuation { continuation in
            connection.receiveMessage { data, _, _, error in
                if let error {
                    continuation.resume(throwing: error)
                } else if let data {
                    continuation.resume(returning: data)
                } else {
                    continuation.resume(throwing: UDPSessionError.malformedDatagram)
                }
            }
        }
    }

    public func cancel() {
        connection.cancel()
    }
}
