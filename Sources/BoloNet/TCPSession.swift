import Network
import Foundation
import BoloKit

// MARK: - Wave 6.4a extension (D45) — persistent TCP SR* dispatch loop
//
// The persistent receive loop D45 named as missing around Wave 6.2's 30
// already-shipped `recvSr*` functions. Uses the same classic
// completion-handler `NWConnection` API `UDPSession.swift` chose for the
// same reason (a freely-held, persistent session object, not a
// closure-scoped one-shot handshake) -- see that file's header for the
// full D31/D42 reasoning, which applies identically here.
//
// TCP has no message framing of its own: each `SR*` struct's `wireSize`
// (`ServerMessages.swift`, additive this wave) says how many bytes to
// read once the leading opcode byte reveals which struct is coming,
// mirroring the real client's per-opcode `recv()` sizing. `SRSendMesg` is
// the one exception -- its `text` field is a NUL-terminated tail with no
// length prefix, so after its 3-byte fixed portion, this reads one byte
// at a time until (and including) a NUL.
//
// `sendMesg`/`timeLimit`/`baseControl` have no `recvSr*` counterpart
// (Wave 6.2's own finding, restated in `RecvSR.swift`'s file header: pure
// UI text formatting in the real client, no `GameState` mutation) --
// surfaced here as plain callbacks instead of a dispatch call, per the
// plan this extension was scoped against.

public enum TCPSessionError: Error {
    case connectionClosed
    case malformedMessage
}

/// Every callback a full 30-function `recvSr*` dispatch can fire, plus
/// the three opcodes that have no `recvSr*` counterpart at all
/// (`sendMesg`/`timeLimit`/`baseControl`) -- grouped into one struct
/// rather than a ~12-parameter function signature.
public struct SRDispatchCallbacks {
    public var onPlayerStatusChanged: (Int) -> Void = { _ in }
    public var onPillStatusChanged: (Int) -> Void = { _ in }
    public var onBaseStatusChanged: (Int) -> Void = { _ in }
    public var onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in }
    public var onRequestGrabTile: (Pointi) -> Void = { _ in }
    public var onShouldLeaveAlliance: (UInt16) -> Void = { _ in }
    public var onMineExplosion: (Pointi) -> Void = { _ in }
    public var onSuperboomTerrain: (Pointi) -> Void = { _ in }
    public var onTankStatusChanged: () -> Void = {}
    /// No `GameState` mutation exists for this opcode (Wave 6.2 finding)
    /// -- this is the entire handling it gets.
    public var onSendMesg: (UInt8, UInt8, String) -> Void = { _, _, _ in }
    /// No `GameState` mutation exists for this opcode (Wave 6.2 finding).
    public var onTimeLimit: (UInt16) -> Void = { _ in }
    /// No `GameState` mutation exists for this opcode (Wave 6.2 finding).
    public var onBaseControl: (UInt16) -> Void = { _ in }

    public init(
        onPlayerStatusChanged: @escaping (Int) -> Void = { _ in },
        onPillStatusChanged: @escaping (Int) -> Void = { _ in },
        onBaseStatusChanged: @escaping (Int) -> Void = { _ in },
        onShouldBroadcastDropPill: @escaping (Int, Int, Int) -> Void = { _, _, _ in },
        onRequestGrabTile: @escaping (Pointi) -> Void = { _ in },
        onShouldLeaveAlliance: @escaping (UInt16) -> Void = { _ in },
        onMineExplosion: @escaping (Pointi) -> Void = { _ in },
        onSuperboomTerrain: @escaping (Pointi) -> Void = { _ in },
        onTankStatusChanged: @escaping () -> Void = {},
        onSendMesg: @escaping (UInt8, UInt8, String) -> Void = { _, _, _ in },
        onTimeLimit: @escaping (UInt16) -> Void = { _ in },
        onBaseControl: @escaping (UInt16) -> Void = { _ in }
    ) {
        self.onPlayerStatusChanged = onPlayerStatusChanged
        self.onPillStatusChanged = onPillStatusChanged
        self.onBaseStatusChanged = onBaseStatusChanged
        self.onShouldBroadcastDropPill = onShouldBroadcastDropPill
        self.onRequestGrabTile = onRequestGrabTile
        self.onShouldLeaveAlliance = onShouldLeaveAlliance
        self.onMineExplosion = onMineExplosion
        self.onSuperboomTerrain = onSuperboomTerrain
        self.onTankStatusChanged = onTankStatusChanged
        self.onSendMesg = onSendMesg
        self.onTimeLimit = onTimeLimit
        self.onBaseControl = onBaseControl
    }
}

public final class TCPSession: @unchecked Sendable {
    private let connection: NWConnection

    public init(host: String, port: UInt16) async throws {
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

    public func send(_ bytes: [UInt8]) async throws {
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
                    continuation.resume(throwing: TCPSessionError.connectionClosed)
                }
            }
        }
    }

    private func receiveOneByte() async throws -> UInt8 {
        try await receiveExactly(1)[0]
    }

    /// Reads one full `SR*` opcode message off the stream, decodes it,
    /// and dispatches it to the matching `recvSr*` function (or, for the
    /// three opcodes with no such function, the matching plain callback).
    /// Returns the opcode that was dispatched.
    ///
    /// **B.8 (D117):** now a thin wrapper over the async-receive/sync-dispatch split below --
    /// existing callers/tests keep this exact signature and behavior unchanged.
    @discardableResult
    public func receiveAndDispatchOne(
        state: inout GameState, callbacks: SRDispatchCallbacks = SRDispatchCallbacks()
    ) async throws -> ServerOpcode {
        let message = try await receiveOneRawMessage()
        try Self.dispatch(message, state: &state, callbacks: callbacks)
        return message.opcode
    }

    /// One fully-read (but undecoded) `SR*` message -- the opcode plus every byte the wire format
    /// says belongs to it, opcode byte included.
    public struct RawMessage: Sendable {
        public let opcode: ServerOpcode
        public let bytes: [UInt8]
    }

    /// **B.8 (D117):** the async, I/O-only half of what `receiveAndDispatchOne` used to do in one
    /// call -- reads exactly the bytes one `SR*` message needs off the stream and returns them
    /// undecoded, touching no `GameState` at all. Mirrors `HostGameEngine`'s own producer/consumer
    /// split (`receiveOneHostMessageBytes`, I/O-only, vs. its single consumer's synchronous
    /// dispatch) -- built for the identical reason: a caller juggling multiple concurrent event
    /// sources (a join-side `GameSession`'s tick timer, this, and a `UDPSession` receive loop)
    /// needs the network *wait* off the critical path that touches shared state, so no `await`
    /// ever spans an actor-isolated mutation.
    public func receiveOneRawMessage() async throws -> RawMessage {
        let opcodeByte = try await receiveOneByte()
        guard let opcode = ServerOpcode(rawValue: opcodeByte) else {
            throw TCPSessionError.malformedMessage
        }

        // `wireSize` includes the opcode byte already read above.
        func rest(_ wireSize: Int) async throws -> [UInt8] {
            [opcodeByte] + (try await receiveExactly(wireSize - 1))
        }

        switch opcode {
        case .playerJoin: return RawMessage(opcode: opcode, bytes: try await rest(SRPlayerJoin.wireSize))
        case .playerRejoin: return RawMessage(opcode: opcode, bytes: try await rest(SRPlayerRejoin.wireSize))
        case .playerExit: return RawMessage(opcode: opcode, bytes: try await rest(SRPlayerExit.wireSize))
        case .playerDisc: return RawMessage(opcode: opcode, bytes: try await rest(SRPlayerDisc.wireSize))
        case .playerKick: return RawMessage(opcode: opcode, bytes: try await rest(SRPlayerKick.wireSize))
        case .playerBan: return RawMessage(opcode: opcode, bytes: try await rest(SRPlayerBan.wireSize))
        case .hangUp: return RawMessage(opcode: opcode, bytes: try await rest(SRHangUp.wireSize))
        case .sendMesg:
            let fixed = try await rest(SRSendMesg.wireSize)
            var textBytes: [UInt8] = []
            while true {
                let b = try await receiveOneByte()
                if b == 0 { break }
                textBytes.append(b)
            }
            return RawMessage(opcode: opcode, bytes: fixed + textBytes + [0])
        case .damage: return RawMessage(opcode: opcode, bytes: try await rest(SRDamage.wireSize))
        case .grabTrees: return RawMessage(opcode: opcode, bytes: try await rest(SRGrabTrees.wireSize))
        case .build: return RawMessage(opcode: opcode, bytes: try await rest(SRBuild.wireSize))
        case .grow: return RawMessage(opcode: opcode, bytes: try await rest(SRGrow.wireSize))
        case .flood: return RawMessage(opcode: opcode, bytes: try await rest(SRFlood.wireSize))
        case .placeMine: return RawMessage(opcode: opcode, bytes: try await rest(SRPlaceMine.wireSize))
        case .dropMine: return RawMessage(opcode: opcode, bytes: try await rest(SRDropMine.wireSize))
        case .dropBoat: return RawMessage(opcode: opcode, bytes: try await rest(SRDropBoat.wireSize))
        case .repairPill: return RawMessage(opcode: opcode, bytes: try await rest(SRRepairPill.wireSize))
        case .coolPill: return RawMessage(opcode: opcode, bytes: try await rest(SRCoolPill.wireSize))
        case .capturePill: return RawMessage(opcode: opcode, bytes: try await rest(SRCapturePill.wireSize))
        case .buildPill: return RawMessage(opcode: opcode, bytes: try await rest(SRBuildPill.wireSize))
        case .dropPill: return RawMessage(opcode: opcode, bytes: try await rest(SRDropPill.wireSize))
        case .replenishBase: return RawMessage(opcode: opcode, bytes: try await rest(SRReplenishBase.wireSize))
        case .captureBase: return RawMessage(opcode: opcode, bytes: try await rest(SRCaptureBase.wireSize))
        case .refuel: return RawMessage(opcode: opcode, bytes: try await rest(SRRefuel.wireSize))
        case .grabBoat: return RawMessage(opcode: opcode, bytes: try await rest(SRGrabBoat.wireSize))
        case .mineAck: return RawMessage(opcode: opcode, bytes: try await rest(SRMineAck.wireSize))
        case .builderAck: return RawMessage(opcode: opcode, bytes: try await rest(SRBuilderAck.wireSize))
        case .smallBoom: return RawMessage(opcode: opcode, bytes: try await rest(SRSmallBoom.wireSize))
        case .superBoom: return RawMessage(opcode: opcode, bytes: try await rest(SRSuperBoom.wireSize))
        case .hitTank: return RawMessage(opcode: opcode, bytes: try await rest(SRHitTank.wireSize))
        case .setAlliance: return RawMessage(opcode: opcode, bytes: try await rest(SRSetAlliance.wireSize))
        case .timeLimit: return RawMessage(opcode: opcode, bytes: try await rest(SRTimeLimit.wireSize))
        case .baseControl: return RawMessage(opcode: opcode, bytes: try await rest(SRBaseControl.wireSize))
        case .pause: return RawMessage(opcode: opcode, bytes: try await rest(SRPause.wireSize))
        }
    }

    /// **B.8 (D117):** the synchronous, no-`await` half -- decodes an already-fully-read
    /// `RawMessage` and dispatches it to the matching `recvSr*` function, exactly as
    /// `receiveAndDispatchOne` always did inline. `static` (not an instance method) since it
    /// touches no connection state at all, only `state`/`callbacks` -- a caller's single
    /// consumer can call this for a message that arrived from any `TCPSession`.
    public static func dispatch(
        _ message: RawMessage, state: inout GameState, callbacks: SRDispatchCallbacks = SRDispatchCallbacks()
    ) throws {
        let bytes = message.bytes
        switch message.opcode {
        case .playerJoin:
            guard let msg = SRPlayerJoin.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerJoin(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerRejoin:
            guard let msg = SRPlayerRejoin.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerRejoin(
                player: Int(msg.player), state: &state,
                onPlayerStatusChanged: callbacks.onPlayerStatusChanged, onPillStatusChanged: callbacks.onPillStatusChanged
            )
        case .playerExit:
            guard let msg = SRPlayerExit.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerExit(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerDisc:
            guard let msg = SRPlayerDisc.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerDisc(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerKick:
            guard let msg = SRPlayerKick.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerKick(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerBan:
            guard let msg = SRPlayerBan.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerBan(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .hangUp:
            // "Not used" per `bolo.h:210` -- no `recvSr*` function exists
            // (`RecvSR.swift`'s own header). Consumed off the stream and
            // otherwise ignored, matching that established finding.
            break
        case .sendMesg:
            guard let msg = SRSendMesg.decode(bytes) else { throw TCPSessionError.malformedMessage }
            callbacks.onSendMesg(msg.player, msg.to, msg.text)
        case .damage:
            guard let msg = SRDamage.decode(bytes), let terrain = Terrain(rawValue: Int32(msg.terrain)) else {
                throw TCPSessionError.malformedMessage
            }
            recvSrDamage(
                player: msg.player, x: Int(msg.x), y: Int(msg.y), terrain: terrain, state: &state,
                onPillStatusChanged: callbacks.onPillStatusChanged, onBaseStatusChanged: callbacks.onBaseStatusChanged,
                onShouldBroadcastDropPill: callbacks.onShouldBroadcastDropPill
            )
        case .grabTrees:
            guard let msg = SRGrabTrees.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrGrabTrees(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .build:
            guard let msg = SRBuild.decode(bytes), let terrain = Terrain(rawValue: Int32(msg.terrain)) else {
                throw TCPSessionError.malformedMessage
            }
            recvSrBuild(x: Int(msg.x), y: Int(msg.y), terrain: terrain, state: &state)
        case .grow:
            guard let msg = SRGrow.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrGrow(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .flood:
            guard let msg = SRFlood.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrFlood(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .placeMine:
            guard let msg = SRPlaceMine.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlaceMine(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .dropMine:
            guard let msg = SRDropMine.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrDropMine(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .dropBoat:
            guard let msg = SRDropBoat.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrDropBoat(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .repairPill:
            guard let msg = SRRepairPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrRepairPill(pill: Int(msg.pill), armour: msg.armour, state: &state, onPillStatusChanged: callbacks.onPillStatusChanged)
        case .coolPill:
            guard let msg = SRCoolPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrCoolPill(pill: Int(msg.pill), state: &state)
        case .capturePill:
            guard let msg = SRCapturePill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrCapturePill(
                pill: Int(msg.pill), owner: msg.owner, state: &state,
                onPillStatusChanged: callbacks.onPillStatusChanged, onShouldBroadcastDropPill: callbacks.onShouldBroadcastDropPill,
                onRequestGrabTile: callbacks.onRequestGrabTile
            )
        case .buildPill:
            guard let msg = SRBuildPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrBuildPill(
                pill: Int(msg.pill), x: msg.x, y: msg.y, armour: msg.armour, state: &state,
                onPillStatusChanged: callbacks.onPillStatusChanged
            )
        case .dropPill:
            guard let msg = SRDropPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrDropPill(pill: Int(msg.pill), x: msg.x, y: msg.y, state: &state, onPillStatusChanged: callbacks.onPillStatusChanged)
        case .replenishBase:
            guard let msg = SRReplenishBase.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrReplenishBase(base: Int(msg.base), state: &state, onBaseStatusChanged: callbacks.onBaseStatusChanged)
        case .captureBase:
            guard let msg = SRCaptureBase.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrCaptureBase(base: Int(msg.base), owner: msg.owner, state: &state, onBaseStatusChanged: callbacks.onBaseStatusChanged)
        case .refuel:
            guard let msg = SRRefuel.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrRefuel(base: Int(msg.base), armour: msg.armour, shells: msg.shells, mines: msg.mines, state: &state)
        case .grabBoat:
            guard let msg = SRGrabBoat.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrGrabBoat(player: Int(msg.player), x: Int(msg.x), y: Int(msg.y), state: &state)
        case .mineAck:
            guard let msg = SRMineAck.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrMineAck(success: msg.success != 0, state: &state, onTankStatusChanged: callbacks.onTankStatusChanged)
        case .builderAck:
            guard let msg = SRBuilderAck.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrBuilderAck(mines: msg.mines, trees: msg.trees, pill: msg.pill, state: &state)
        case .smallBoom:
            guard let msg = SRSmallBoom.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrSmallBoom(
                player: msg.player, x: Int(msg.x), y: Int(msg.y), state: &state,
                onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
                onShouldBroadcastDropPill: callbacks.onShouldBroadcastDropPill, onTankStatusChanged: callbacks.onTankStatusChanged
            )
        case .superBoom:
            guard let msg = SRSuperBoom.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrSuperBoom(
                player: msg.player, x: Int(msg.x), y: Int(msg.y), state: &state,
                onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
                onShouldBroadcastDropPill: callbacks.onShouldBroadcastDropPill, onTankStatusChanged: callbacks.onTankStatusChanged
            )
        case .hitTank:
            guard let msg = SRHitTank.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrHitTank(dir: msg.dir, state: &state, onTankStatusChanged: callbacks.onTankStatusChanged, onShouldBroadcastDropPill: callbacks.onShouldBroadcastDropPill)
        case .setAlliance:
            guard let msg = SRSetAlliance.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrSetAlliance(
                player: Int(msg.player), alliance: msg.alliance, state: &state,
                onPlayerStatusChanged: callbacks.onPlayerStatusChanged, onBaseStatusChanged: callbacks.onBaseStatusChanged,
                onPillStatusChanged: callbacks.onPillStatusChanged, onShouldLeaveAlliance: callbacks.onShouldLeaveAlliance
            )
        case .timeLimit:
            guard let msg = SRTimeLimit.decode(bytes) else { throw TCPSessionError.malformedMessage }
            callbacks.onTimeLimit(msg.timeRemaining)
        case .baseControl:
            guard let msg = SRBaseControl.decode(bytes) else { throw TCPSessionError.malformedMessage }
            callbacks.onBaseControl(msg.timeLeft)
        case .pause:
            guard let msg = SRPause.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPause(pause: msg.pause, state: &state)
        }
    }

    public func cancel() {
        connection.cancel()
    }

    // MARK: - Join handshake (B.8/D113)

    /// Performs the full join handshake against `host:port` and returns the still-live session
    /// alongside the decoded `BoloPreamble` + raw map bytes -- see this type's own file header
    /// and `joinClient`'s doc comment (`JoinClient.swift`) for why the handshake had to move
    /// here: a join-side live network loop must keep receiving on the *same* accepted connection
    /// the handshake used, not a fresh one, and `TCPSession` (not `withNetworkConnection`'s
    /// auto-closing scope) is the type built to hold a connection open past one call.
    ///
    /// Ported wire logic 1:1 from `joinClient`'s own original body (same protocol steps, same
    /// `JoinClientError`/`JoinProgress` taxonomy) -- only the transport underneath changed.
    ///
    /// **Known, disclosed, narrow leak risk, same shape already accepted in `withConnectTimeout`'s**
    /// **own doc comment:** if the connect+handshake loses the race against `connectTimeoutSeconds`
    /// but keeps running in the background and *later* succeeds, the resulting `TCPSession`'s
    /// connection is never cancelled -- nothing is listening for it once the timeout has already
    /// resumed the continuation. The original `joinClient` didn't have this specific leak (a lost
    /// race there left a `withNetworkConnection`-scoped closure running, which self-closes its
    /// connection on return regardless), so this is a new-but-narrow consequence of the transport
    /// change, not a pre-existing one carried over. Not fixed here -- flagged for Planner.
    public static func join(
        host: String, port: UInt16, name: String, pass: String,
        connectTimeoutSeconds: Double = 15,
        onProgress: @escaping @Sendable (JoinProgress) -> Void = { _ in }
    ) async throws -> (session: TCPSession, preamble: BoloPreamble, mapData: [UInt8]) {
        onProgress(.connecting)
        do {
            return try await withConnectTimeout(seconds: connectTimeoutSeconds) {
                // Not inside the `do` below on purpose -- if connecting itself throws, there is
                // no live session yet for that block's `catch` to cancel.
                let session = try await TCPSession(host: host, port: port)
                do {
                    onProgress(.sendingJoin)
                    let joinPreamble = JoinPreamble(name: name, pass: pass)
                    try await session.send(joinPreamble.encode())

                    let statusByte = try await session.receiveOneByte()
                    guard let status = JoinStatusByte(rawValue: statusByte) else {
                        throw JoinClientError.serverProtocolError
                    }
                    guard status == .sendingPreamble else {
                        throw JoinClientError(rejecting: status)
                    }

                    onProgress(.receivingPreamble)
                    let preambleBytes = try await session.receiveExactly(BoloPreamble.wireSize)
                    guard let preamble = BoloPreamble.decode(preambleBytes) else {
                        throw JoinClientError.malformedPreamble
                    }

                    onProgress(.receivingMap)
                    let mapData = try await session.receiveExactly(Int(preamble.mapLength))

                    onProgress(.success)
                    return (session, preamble, mapData)
                } catch let error as JoinClientError {
                    session.cancel()
                    throw error
                } catch {
                    session.cancel()
                    throw JoinClientError(posix: error) ?? error
                }
            }
        } catch let error as JoinClientError {
            throw error
        } catch {
            throw JoinClientError(posix: error) ?? error
        }
    }
}
