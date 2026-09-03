import Network
import Foundation
import BoloKit

// MARK: - Wave 6.4c (D50/D51) — live UDP listener driving DgramServerRelay.swift
//
// Confirmed by direct API research, not assumed: `NWListener(using: .udp,
// on:)` + `newConnectionHandler` hands back **one `NWConnection` per
// distinct remote 4-tuple** (Apple's own `nw_listener_t` header:
// "accepted connections will represent new local and remote address and
// port tuples"). A real mechanism difference from the C's single
// `recvfrom()`-on-one-socket loop (`dgramserver()`, `server.c:614-696`),
// permitted under D31/D42's "rebuild the mechanism, preserve the decision
// logic" latitude, same as every other transport substitution this
// project has made. `DgramServerRelay.swift`'s `decodeDgramServerRelay`
// (complete, independently oracle-tested) is unchanged by this file --
// this is purely the socket plumbing around it.
//
// **D51:** lives in its own file, matching `HostListener.swift`'s
// (TCP accept) precedent, rather than folding a network-facing accept
// loop into `HostSession.swift`'s session-bookkeeping concern.
//
// Binds to the *same port* `HostListener` resolved, matching
// `initserver()`'s own `getsockname()`-then-bind-UDP ordering
// (`server.c:256-274`, the 6.4b pre-brief's T-10) -- the caller is
// responsible for passing the already-known TCP port in, this type does
// not discover it independently.

/// Feeds every accepted peer's datagrams into one shared `AsyncStream`,
/// mirroring `HostListener.connections`'s already-shipped shape one for
/// one. **Load-bearing, not incidental:** each accepted UDP peer needs
/// its own persistent receive loop to get that peer's *subsequent*
/// datagrams, but `processDgramPacket` (`HostSession.swift`) mutates
/// `state: inout GameState` -- N independent per-peer loops touching it
/// concurrently would violate Swift's exclusivity law exactly the way
/// `HostListener.swift`'s original per-connection-`Task` sketch already
/// did once. Funneling every peer's bytes through one stream, drained by
/// one caller-owned sequential consumer, is the same fix applied here
/// directly rather than rediscovered.
public final class HostDgramListener: @unchecked Sendable {
    private let listener: NWListener
    private let stream: AsyncStream<(bytes: [UInt8], connection: NWConnection)>

    /// Forces IPv4 (`forceIPv4`, `HostListener.swift`) -- matches the C's
    /// own AF_INET-only design and keeps `peerAddress(from:)`'s `.ipv4`
    /// extraction from ever silently failing on an IPv6-mapped peer.
    public init(port: UInt16) async throws {
        let udpOptions = NWProtocolUDP.Options()
        let parameters = NWParameters(dtls: nil, udp: udpOptions)
        let boundPort = NWEndpoint.Port(rawValue: port)!
        forceIPv4(parameters, port: boundPort)
        listener = try NWListener(using: parameters, on: boundPort)

        var continuationBox: AsyncStream<(bytes: [UInt8], connection: NWConnection)>.Continuation?
        stream = AsyncStream { continuation in continuationBox = continuation }
        let packetContinuation = continuationBox!

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            Task {
                await Self.drainDatagrams(from: connection, into: packetContinuation)
            }
        }

        try await withCheckedThrowingContinuation { (readyContinuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready:
                    resumed = true
                    readyContinuation.resume()
                case .failed(let error):
                    resumed = true
                    readyContinuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: .main)
        }
    }

    /// One peer's persistent receive loop -- runs until that peer's flow
    /// fails or is canceled (e.g. by `HostSessionTable.setDgramConnection`'s
    /// D52 cancel-and-replace, once a replacement flow for the same
    /// player slot arrives). Cleanup of a now-dead entry in
    /// `HostSessionTable` itself is D52's cancel-and-replace's job, not
    /// this loop's -- this layer only ever reads bytes and hands them off,
    /// it never touches `GameState`/`HostSessionTable` directly.
    private static func drainDatagrams(
        from connection: NWConnection, into continuation: AsyncStream<(bytes: [UInt8], connection: NWConnection)>.Continuation
    ) async {
        while true {
            guard let data = try? await receiveOneDatagram(connection) else {
                return
            }
            continuation.yield((bytes: Array(data), connection: connection))
        }
    }

    /// Drain one datagram at a time -- see the type's own doc comment for
    /// why this, not N self-driving per-peer consumers touching shared
    /// state, is what keeps this safe under Swift's exclusivity law.
    public var packets: AsyncStream<(bytes: [UInt8], connection: NWConnection)> { stream }

    public var port: UInt16? { listener.port?.rawValue }

    public func cancel() {
        listener.cancel()
    }
}

private func receiveOneDatagram(_ connection: NWConnection) async throws -> Data {
    try await withCheckedThrowingContinuation { continuation in
        connection.receiveMessage { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data {
                continuation.resume(returning: data)
            } else {
                continuation.resume(throwing: HostSessionError.connectionClosed)
            }
        }
    }
}

private func sendBytes(_ bytes: [UInt8], over connection: NWConnection) async throws {
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

// MARK: - processDgramPacket

/// One already-received datagram's full decision-and-apply cycle -- the
/// tested, substantive unit (mirrors `processJoinAttempt`'s role in
/// `HostListener.swift`). A thin driver around `decodeDgramServerRelay`
/// (`DgramServerRelay.swift`, complete and independently oracle-tested --
/// no new decision logic here, only the socket plumbing around it):
/// `.trackerEcho` replies with the exact same bytes over the same
/// connection (T-4, `server.c:637-645` -- never zeroed, unlike
/// `registerserver()`'s own tracker echo, deferred to Wave 6.5 per D43);
/// `.malformed`/`.dropped` are no-ops; `.applied` writes `tank` into
/// `GameState` (T-2: only tank x/y), advances `table`'s `seq`, refreshes
/// `dgramAddress` (T-3's port-refresh), records this connection as the
/// player's live UDP flow (D52's cancel-and-replace lives inside
/// `setDgramConnection` itself), and relays the original bytes verbatim
/// (T-8) to every `relayTo` target that already has a live flow of its
/// own -- a target with none yet is silently skipped (a real, disclosed
/// limitation matching the C's own practical one: a `sendto()` to a
/// not-yet-port-corrected `dgramaddr` also goes nowhere useful until that
/// player's own first packet arrives).
public func processDgramPacket(
    bytes: [UInt8], from connection: NWConnection, state: inout GameState, table: HostSessionTable
) async {
    guard let senderAddress = peerAddress(from: connection) else { return }
    let players = await table.dgramSessionSnapshot(usedFlags: state.players.map(\.used))

    switch decodeDgramServerRelay(bytes, from: senderAddress, players: players) {
    case .trackerEcho:
        try? await sendBytes(bytes, over: connection)

    case .malformed, .dropped:
        break

    case .applied(let player, let tank, let newSeq, let portUpdate, let relayTo):
        state.players[player].tank = tank
        await table.setSeq(newSeq, for: player)

        var updatedAddress = senderAddress
        if let portUpdate {
            updatedAddress.port = portUpdate
        }
        await table.setDgramAddress(updatedAddress, for: player)
        await table.setDgramConnection(connection, for: player)

        for target in relayTo {
            if let targetConnection = await table.dgramConnection(for: target) {
                try? await sendBytes(bytes, over: targetConnection)
            }
        }
    }
}
