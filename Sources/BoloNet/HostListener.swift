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
// **Scope reduction, disclosed, not silently dropped:** this file
// implements the TCP accept loop and join handshake in full (`HostListener`
// class + `processJoinAttempt`), but does NOT wire a live `NWListener
// (using: .udp)` receive loop to `decodeDgramServerRelay`
// (`DgramServerRelay.swift`) -- that pure decision function is complete
// and independently oracle-tested (`DgramServerRelayTests.swift`), but no
// file in this wave drives it against a real socket. Flagged for
// PLANNER/PARITY as unfinished, not claimed as done.
//
// **`dgramaddr` at join time is a simplification, disclosed:** the real
// `joinplayerserver()` seeds `server.players[player].dgramaddr` from the
// joining TCP connection's own address (`server.c:817`), with the port
// corrected on the first real UDP packet (T-3's port-refresh mechanism).
// Deriving the numeric `sin_addr`/`sin_family` equivalents from an
// `NWConnection`'s endpoint without the not-yet-written UDP listener to
// exercise them is speculative, so this port seeds a zeroed
// `DgramServerPeerAddress` instead and leaves the real capture to
// whichever future wave wires the UDP side -- T-3's own port-mismatch
// refresh already tolerates an initially-wrong (here, zero) address/port,
// since a real first packet's family/addr can never match a zeroed
// sentinel `used`/`connected` gate anyway until that UDP wiring exists.

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
        await table.setDgramAddress(DgramServerPeerAddress(family: 0, addr: 0, port: 0), for: player)

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
        listener = try NWListener(using: parameters, on: NWEndpoint.Port(rawValue: port)!)
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
