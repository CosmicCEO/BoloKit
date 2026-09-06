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

    /// **B.8 (D115):** `receiveAndApply` used to take the caller's stored `previousRemoteSeq`/
    /// `previousRemoteLastUpdate` as plain per-call scalars -- fine for a test that already
    /// constructs its own header and knows which player it's for, impossible for a real caller
    /// receiving relayed updates for arbitrary players over one shared socket (exactly the join
    /// client's situation, and the first real caller this type has ever had). `UDPSession` now
    /// owns this table itself, the same "the type owning the one shared socket owns the
    /// demultiplexing state" principle already applied to `HostSessionTable`.
    private var remoteSeqs = [Int32](repeating: 0, count: maxPlayers)
    private var remoteLastUpdates = [Int32](repeating: 0, count: maxPlayers)

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

    /// Receives one datagram and, if it decodes to a valid `CLUpdate`, applies it via
    /// `applyRemotePlayerUpdate` (Wave 6.4a), looking up and updating this session's own
    /// per-player `seq`/`lastUpdate` table for whichever player the datagram turns out to be for
    /// (`header.player`, only known after decoding -- see this type's own `remoteSeqs`/
    /// `remoteLastUpdates` doc comment). Returns `(player, seq, lastUpdate)` on a successful
    /// apply, or `nil` if the datagram was malformed, the player index was out of range, or the
    /// update was rejected (self-echo/stale/disconnected -- the same no-op conditions
    /// `applyRemotePlayerUpdate` itself already covers).
    ///
    /// **B.8 (D117):** now a thin wrapper over the async-receive/sync-apply split below --
    /// existing callers/tests keep this exact signature and behavior unchanged.
    @discardableResult
    public func receiveAndApply(
        myOwnSeq: Int32, state: inout GameState,
        onPlayerLagStatusChanged: (Int) -> Void = { _ in },
        onTankShotSound: () -> Void = {},
        onPillShotSound: () -> Void = {},
        onSinkSound: () -> Void = {},
        onBuilderDeathSound: () -> Void = {},
        onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in },
        onMineExplosion: (Pointi) -> Void = { _ in },
        onSuperboomTerrain: (Pointi) -> Void = { _ in },
        onExplosion: (Vec2f) -> Void = { _ in },
        onSuperboom: () -> Void = {},
        onSmallboom: () -> Void = {},
        onSpawn: () -> Void = {}
    ) async throws -> (player: Int, seq: Int32, lastUpdate: Int32)? {
        let data = try await receiveOneRawDatagram()
        return apply(
            data, myOwnSeq: myOwnSeq, state: &state,
            onPlayerLagStatusChanged: onPlayerLagStatusChanged, onTankShotSound: onTankShotSound,
            onPillShotSound: onPillShotSound, onSinkSound: onSinkSound, onBuilderDeathSound: onBuilderDeathSound,
            onShouldBroadcastDropPill: onShouldBroadcastDropPill, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain,
            onExplosion: onExplosion, onSuperboom: onSuperboom, onSmallboom: onSmallboom, onSpawn: onSpawn
        )
    }

    /// **B.8 (D117):** the async, I/O-only half -- waits for one raw datagram off the socket,
    /// touching no `GameState` at all. Mirrors `TCPSession.receiveOneRawMessage`'s identical
    /// role and the identical reason: a join-side consumer juggling this, a `TCPSession` receive
    /// loop, and its own tick timer needs the network *wait* off the critical path that ever
    /// touches shared state, so no `await` spans an actor-isolated mutation.
    public func receiveOneRawDatagram() async throws -> Data {
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

    /// **B.8 (D117):** the synchronous, no-`await` half -- decodes an already-received raw
    /// datagram and applies it, exactly as `receiveAndApply` always did inline. An instance
    /// method (unlike `TCPSession.dispatch`, which is `static`) because it reads/writes this
    /// session's own `remoteSeqs`/`remoteLastUpdates` table -- the demultiplexing state stays
    /// owned by whichever `UDPSession` actually received the datagram.
    @discardableResult
    public func apply(
        _ data: Data, myOwnSeq: Int32, state: inout GameState,
        onPlayerLagStatusChanged: (Int) -> Void = { _ in },
        onTankShotSound: () -> Void = {},
        onPillShotSound: () -> Void = {},
        onSinkSound: () -> Void = {},
        onBuilderDeathSound: () -> Void = {},
        onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in },
        onMineExplosion: (Pointi) -> Void = { _ in },
        onSuperboomTerrain: (Pointi) -> Void = { _ in },
        onExplosion: (Vec2f) -> Void = { _ in },
        onSuperboom: () -> Void = {},
        onSmallboom: () -> Void = {},
        onSpawn: () -> Void = {}
    ) -> (player: Int, seq: Int32, lastUpdate: Int32)? {
        guard let update = CLUpdate.decode(Array(data)) else { return nil }
        let player = Int(update.header.player)
        // `applyRemotePlayerUpdate` itself already bounds-checks `player` against
        // `state.players.indices` -- this guard is only to keep this session's OWN
        // `remoteSeqs`/`remoteLastUpdates` (sized `maxPlayers`, not `state.players.count`) from
        // ever being indexed out of range, the same class of trap D111 fixed elsewhere tonight.
        guard state.players.indices.contains(player), player < maxPlayers else { return nil }
        guard let result = applyRemotePlayerUpdate(
            header: update.header, shells: update.shells, explosions: update.explosions,
            previousRemoteSeq: remoteSeqs[player], previousRemoteLastUpdate: remoteLastUpdates[player],
            myOwnSeq: myOwnSeq, state: &state,
            onPlayerLagStatusChanged: onPlayerLagStatusChanged, onTankShotSound: onTankShotSound,
            onPillShotSound: onPillShotSound, onSinkSound: onSinkSound, onBuilderDeathSound: onBuilderDeathSound,
            onShouldBroadcastDropPill: onShouldBroadcastDropPill, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain,
            onExplosion: onExplosion, onSuperboom: onSuperboom, onSmallboom: onSmallboom, onSpawn: onSpawn
        ) else { return nil }
        remoteSeqs[player] = result.seq
        remoteLastUpdates[player] = result.lastUpdate
        return (player, result.seq, result.lastUpdate)
    }

    public func cancel() {
        connection.cancel()
    }
}
