import Network
import Foundation
import BoloKit

// MARK: - Wave 6.4b — host-side accept loop + join handshake
//
// Ported from `joinplayerserver()`'s wire-level protocol steps
// (`server.c:714-905`) -- NOT its POSIX mechanics, same D31/D42
// precedent `JoinClient.swift` (Wave 6.4a) already established for the
// reverse direction: the actual `accept()`/`select()` dance is
// transliterated POSIX glue D31 already ruled out; this is a fresh
// implementation of the same observable byte sequence (`JoinPreamble` ->
// status byte -> `BoloPreamble` -> map bytes) on `NWListener`/
// `NWConnection`/async-await instead.
//
// **T-11, load-bearing (D49):** the real server only ever has one
// `joiningplayer` in flight -- `listensock` re-enters `readfds` only once
// `joiningplayer.cntlsock == -1` (`server.c:954-957`). A naive "one actor
// method per join" does NOT reproduce this: actor methods are reentrant
// across their own `await` points (Swift's actor model interleaves calls
// at suspension points, it doesn't serialize whole async operations), and
// a join handshake is full of awaits (every network read/write). D49
// approved a real async mutex instead -- `JoinAcceptSerializer` below --
// so two concurrent join attempts genuinely run one at a time, front to
// back, not just between their own await points.
//
// **Wave 6.4c (D50/D51):** the live `NWListener(using: .udp)` receive loop
// driving `DgramServerRelay.swift`'s decision core against real datagrams
// now lives in its own file, `HostDgramListener.swift` (D51 -- matches
// this file's own one-listener-per-file precedent), not here.
//
// **`dgramaddr` at join time (Wave 6.4c, D50):** `joinplayerserver()`
// seeds `server.players[player].dgramaddr` from the joining TCP
// connection's own address (`server.c:844` -- corrected here from an
// earlier `:817` citation typo), with the port corrected on the first
// real UDP packet (T-3's port-refresh mechanism, `HostDgramListener.
// swift`). `peerAddress(from:)` below does the same extraction from an
// `NWConnection`'s `.endpoint`, used both here (seeding, with the TCP
// connection's own -- usually UDP-wrong -- port, matching the C exactly)
// and by `HostDgramListener.swift` (extracting the real sender address
// off each accepted UDP flow).

/// A real async mutex -- NOT just "make it an actor method," which
/// (per this file's header) would let two joins interleave at their own
/// `await` points instead of genuinely serializing (D49).
public actor JoinAcceptSerializer {
    private var isProcessing = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    public init() {}

    /// Suspends until this call holds exclusive access. Always paired
    /// with a later `release()` from the same caller.
    public func acquire() async {
        if !isProcessing {
            isProcessing = true
            return
        }
        await withCheckedContinuation { continuation in
            waiters.append(continuation)
        }
    }

    public func release() {
        if waiters.isEmpty {
            isProcessing = false
        } else {
            let next = waiters.removeFirst()
            next.resume()
        }
    }
}

public enum HostJoinOutcome: Sendable, Equatable {
    case rejected(JoinRejection)
    case accepted(player: Int, rejoin: Bool)
    /// The connection closed, or sent malformed bytes, before a complete
    /// `JoinPreamble` arrived -- no defined C recovery for this case
    /// either (`server.c:730`'s own early `SUCCESS` no-op on a short
    /// buffer just waits for more bytes next time through the select
    /// loop; a closed connection has no "next time").
    case malformedOrClosed
}

/// `JoinRejection` (`SessionLogic.swift`, Wave 6.3) -> the wire status
/// byte `joinplayerserver()` actually sends for each rejection
/// (`bolo.h:190-198`) -- `JoinStatusByte` already exists on the client
/// side (`JoinClient.swift`, Wave 6.4a); this is its send-side inverse.
private func statusByte(for rejection: JoinRejection) -> JoinStatusByte {
    switch rejection {
    case .badVersion: return .badVersion
    case .badPassword: return .badPassword
    case .notAllowed: return .disallow
    case .banned: return .bannedPlayer
    case .serverFull: return .serverFull
    }
}

private func receiveExactly(_ count: Int, from connection: NWConnection) async throws -> [UInt8] {
    guard count > 0 else { return [] }
    return try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
            } else if let data, data.count == count {
                continuation.resume(returning: Array(data))
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

/// A stable, comparison-friendly string for `evaluateJoinRequest`'s
/// `address`/ban-list matching -- not wire-visible, so any consistent
/// stringification of the remote endpoint works; this is not required to
/// (and does not) match the numeric `sin_addr` shape
/// `DgramServerPeerAddress` uses for the wire-level UDP validity check.
private func remoteAddressDescription(_ connection: NWConnection) -> String {
    "\(connection.endpoint)"
}

/// Extracts `connection`'s remote peer as a `DgramServerPeerAddress` --
/// `family` is `2` (`AF_INET` on Darwin's `sockaddr_in.sin_family`,
/// confirmed against the SDK, not assumed) for every IPv4 peer; `nil` for
/// anything else. Confirmed by direct API research, not assumed: an
/// already-accepted connection's `.endpoint` is always a concrete
/// `.hostPort(host:, port:)` with a resolved `.ipv4`/`.ipv6` host -- never
/// `.name(...)`, which only occurs on endpoints constructed from a
/// hostname string, never on an inbound accept. `IPv4Address.rawValue` is
/// the 4 raw address bytes already in network order (no `ntohl` needed);
/// `NWEndpoint.Port.rawValue` is the port as `UInt16` directly. Shared by
/// `processJoinAttempt` below (seeding `dgramaddr` at join, port included
/// even though it's the TCP connection's own -- usually UDP-wrong -- port,
/// matching `server.c:844` literally) and `HostDgramListener.swift`
/// (extracting each accepted UDP flow's real sender address).
public func peerAddress(from connection: NWConnection) -> DgramServerPeerAddress? {
    guard case .hostPort(let host, let port) = connection.endpoint,
          case .ipv4(let ip4) = host
    else {
        return nil
    }
    let addr = ip4.rawValue.withUnsafeBytes { $0.load(as: UInt32.self) }
    return DgramServerPeerAddress(family: 2, addr: addr, port: port.rawValue)
}

/// `parameters.requiredLocalEndpoint` forces IPv4 -- confirmed by direct
/// API research, not assumed: with default parameters, an IPv4 peer can
/// arrive as an IPv6 IPv4-mapped address, which `peerAddress(from:)`
/// above would then reject (`.ipv6`, not `.ipv4`). Matches the C's own
/// AF_INET-only design (`sockaddr_in` throughout `server.c`, no IPv6
/// anywhere) rather than leaving it to default dual-stack behavior.
/// Shared by `HostListener` (TCP) and `HostDgramListener.swift` (UDP) so
/// both listeners agree on the same restriction.
public func forceIPv4(_ parameters: NWParameters, port: NWEndpoint.Port) {
    parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.any), port: port)
}

/// One full join handshake for one already-accepted `connection`, run
/// under `serializer`'s exclusion (T-11/D49). Ported from
/// `joinplayerserver()` end to end (`server.c:714-905`): decode
/// `JoinPreamble` -> `evaluateJoinRequest` -> reject (status byte, close)
/// or accept (`applyJoin` -> register the connection -> `assembleBoloPreamble`
/// + `encodeBMap` -> write preamble + map -> broadcast `SRPlayerJoin`/
/// `SRPlayerRejoin` to everyone, itself included, matching T-9's ordering:
/// the connection is registered in `table` -- and so already eligible for
/// `sendToAll` -- before that broadcast fires, mirroring the C's own
/// `cntlsock` assignment happening before the tail-end `sendsrplayerjoin`/
/// `sendsrplayerrejoin` call).
@discardableResult
public func processJoinAttempt(
    connection: NWConnection, serializer: JoinAcceptSerializer, state: inout GameState, table: HostSessionTable
) async -> HostJoinOutcome {
    await serializer.acquire()
    defer { Task { await serializer.release() } }

    let outcome = await runJoinHandshake(connection: connection, state: &state, table: table)
    return outcome
}

private func runJoinHandshake(
    connection: NWConnection, state: inout GameState, table: HostSessionTable
) async -> HostJoinOutcome {
    let joinBytes: [UInt8]
    do {
        joinBytes = try await receiveExactly(JoinPreamble.wireSize, from: connection)
    } catch {
        connection.cancel()
        return .malformedOrClosed
    }
    guard let joinPreamble = JoinPreamble.decode(joinBytes) else {
        connection.cancel()
        return .malformedOrClosed
    }

    let address = remoteAddressDescription(connection)
    let ticksSinceLastUpdate = await table.allTicksSinceLastUpdate(currentTick: state.ticks)

    let decision = evaluateJoinRequest(
        name: joinPreamble.name, password: joinPreamble.pass, version: joinPreamble.version, address: address,
        passwordRequired: state.passwordRequired, serverPassword: state.serverPassword, allowJoin: state.allowJoin,
        bannedPlayers: state.bannedPlayers, players: state.players, ticksSinceLastUpdate: ticksSinceLastUpdate
    )

    switch decision {
    case .rejected(let reason):
        try? await sendBytes([statusByte(for: reason).rawValue], over: connection)
        connection.cancel()
        return .rejected(reason)

    case .accepted(let player, let rejoin):
        try? await sendBytes([JoinStatusByte.sendingPreamble.rawValue], over: connection)

        applyJoin(player: player, name: joinPreamble.name, address: address, rejoin: rejoin, state: &state)
        await table.setConnection(connection, for: player)
        // server.c:844's literal seed -- the TCP connection's own address,
        // port included (usually UDP-wrong; T-3 corrects it on the first
        // real UDP packet, `HostDgramListener.swift`). A non-IPv4 peer
        // (shouldn't occur once both listeners force IPv4, but `peerAddress`
        // is `Optional` regardless) falls back to the zeroed sentinel.
        await table.setDgramAddress(peerAddress(from: connection) ?? DgramServerPeerAddress(family: 0, addr: 0, port: 0), for: player)

        let seq = await table.allSeqsAsUInt32()
        let mapBytes = encodeBMap(state)
        let preamble = assembleBoloPreamble(player: player, state: state, seq: seq, mapLength: UInt32(mapBytes.count))

        do {
            try await sendBytes(preamble.encode(), over: connection)
            try await sendBytes(mapBytes, over: connection)
        } catch {
            await table.disconnect(player)
            return .malformedOrClosed
        }

        let broadcast = rejoin
            ? SRPlayerRejoin(player: UInt8(player), host: state.players[player].host).encode()
            : SRPlayerJoin(player: UInt8(player), name: state.players[player].name, host: state.players[player].host).encode()
        await table.sendToAll(broadcast)

        return .accepted(player: player, rejoin: rejoin)
    }
}

// MARK: - HostListener

/// Owns the `NWListener` accept loop. Exposes accepted connections as an
/// `AsyncStream` rather than self-driving a `Task` (and a call into
/// `processJoinAttempt`) per accepted connection -- `processJoinAttempt`
/// takes `state: inout GameState` (this port's established convention,
/// shared by every other simulation-touching function in `BoloKit`/
/// `BoloNet`), and Swift's exclusivity law forbids two overlapping
/// formal accesses to the same `inout` binding regardless of any mutex
/// discipline layered on top -- `JoinAcceptSerializer` genuinely
/// serializes concurrent *callers that don't share one `inout` binding*
/// (proved directly, `HostListenerTests.swift`), but spawning one Task
/// per accepted connection, each independently capturing `&state`, would
/// still trap. The caller (whoever owns the single canonical `state` and
/// `HostSessionTable`) drains `connections` with `for await connection in
/// listener.connections { await processJoinAttempt(connection:,
/// serializer:, state: &state, table:) }` -- one at a time, by
/// construction, which is what actually gives T-11 its guarantee here;
/// `JoinAcceptSerializer` remains available (and still passed through)
/// for a caller with a different state-sharing strategy of its own.
public final class HostListener: @unchecked Sendable {
    private let listener: NWListener
    public let serializer = JoinAcceptSerializer()
    private let stream: AsyncStream<NWConnection>

    /// `TCP_NODELAY` (`joinplayerserver()`'s per-connection `setsockopt`,
    /// `server.c:882-884`) has no post-accept equivalent on `NWConnection`
    /// -- `NWProtocolTCP.Options` is set on the listener's parameters
    /// instead, applying uniformly to every accepted connection. Same
    /// effective behavior via a different mechanism, consistent with
    /// D31/D42's "rebuild the mechanism, not the fidelity" latitude.
    public init(port: UInt16) async throws {
        let tcpOptions = NWProtocolTCP.Options()
        tcpOptions.noDelay = true
        let parameters = NWParameters(tls: nil, tcp: tcpOptions)
        let boundPort = NWEndpoint.Port(rawValue: port)!
        forceIPv4(parameters, port: boundPort)
        listener = try NWListener(using: parameters, on: boundPort)
        var continuationBox: AsyncStream<NWConnection>.Continuation?
        stream = AsyncStream { continuation in continuationBox = continuation }
        let connectionContinuation = continuationBox!

        listener.newConnectionHandler = { connection in
            connection.start(queue: .main)
            connectionContinuation.yield(connection)
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

    /// Drain one connection at a time -- see the type's own doc comment
    /// for why this, not a self-driving Task-per-connection, is what
    /// provides T-11's serialization for `state: inout GameState`.
    public var connections: AsyncStream<NWConnection> { stream }

    public var port: UInt16? { listener.port?.rawValue }

    public func cancel() {
        listener.cancel()
    }
}
