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
    public var onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
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
        onDropPills: @escaping (UInt16, Vec2f) -> Void = { _, _ in },
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
        self.onDropPills = onDropPills
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
    @discardableResult
    public func receiveAndDispatchOne(
        state: inout GameState, callbacks: SRDispatchCallbacks = SRDispatchCallbacks()
    ) async throws -> ServerOpcode {
        let opcodeByte = try await receiveOneByte()
        guard let opcode = ServerOpcode(rawValue: opcodeByte) else {
            throw TCPSessionError.malformedMessage
        }

        // `wireSize` includes the opcode byte already read above.
        func rest(_ wireSize: Int) async throws -> [UInt8] {
            [opcodeByte] + (try await receiveExactly(wireSize - 1))
        }

        switch opcode {
        case .playerJoin:
            let bytes = try await rest(SRPlayerJoin.wireSize)
            guard let msg = SRPlayerJoin.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerJoin(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerRejoin:
            let bytes = try await rest(SRPlayerRejoin.wireSize)
            guard let msg = SRPlayerRejoin.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerRejoin(
                player: Int(msg.player), state: &state,
                onPlayerStatusChanged: callbacks.onPlayerStatusChanged, onPillStatusChanged: callbacks.onPillStatusChanged
            )
        case .playerExit:
            let bytes = try await rest(SRPlayerExit.wireSize)
            guard let msg = SRPlayerExit.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerExit(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerDisc:
            let bytes = try await rest(SRPlayerDisc.wireSize)
            guard let msg = SRPlayerDisc.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerDisc(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerKick:
            let bytes = try await rest(SRPlayerKick.wireSize)
            guard let msg = SRPlayerKick.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerKick(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .playerBan:
            let bytes = try await rest(SRPlayerBan.wireSize)
            guard let msg = SRPlayerBan.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlayerBan(player: Int(msg.player), state: &state, onPlayerStatusChanged: callbacks.onPlayerStatusChanged)
        case .hangUp:
            _ = try await rest(SRHangUp.wireSize)
            // "Not used" per `bolo.h:210` -- no `recvSr*` function exists
            // (`RecvSR.swift`'s own header). Consumed off the stream and
            // otherwise ignored, matching that established finding.
            break
        case .sendMesg:
            let fixed = try await rest(SRSendMesg.wireSize)
            var textBytes: [UInt8] = []
            while true {
                let b = try await receiveOneByte()
                if b == 0 { break }
                textBytes.append(b)
            }
            guard let msg = SRSendMesg.decode(fixed + textBytes + [0]) else { throw TCPSessionError.malformedMessage }
            callbacks.onSendMesg(msg.player, msg.to, msg.text)
        case .damage:
            let bytes = try await rest(SRDamage.wireSize)
            guard let msg = SRDamage.decode(bytes), let terrain = Terrain(rawValue: Int32(msg.terrain)) else {
                throw TCPSessionError.malformedMessage
            }
            recvSrDamage(
                player: msg.player, x: Int(msg.x), y: Int(msg.y), terrain: terrain, state: &state,
                onPillStatusChanged: callbacks.onPillStatusChanged, onBaseStatusChanged: callbacks.onBaseStatusChanged,
                onDropPills: callbacks.onDropPills
            )
        case .grabTrees:
            let bytes = try await rest(SRGrabTrees.wireSize)
            guard let msg = SRGrabTrees.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrGrabTrees(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .build:
            let bytes = try await rest(SRBuild.wireSize)
            guard let msg = SRBuild.decode(bytes), let terrain = Terrain(rawValue: Int32(msg.terrain)) else {
                throw TCPSessionError.malformedMessage
            }
            recvSrBuild(x: Int(msg.x), y: Int(msg.y), terrain: terrain, state: &state)
        case .grow:
            let bytes = try await rest(SRGrow.wireSize)
            guard let msg = SRGrow.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrGrow(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .flood:
            let bytes = try await rest(SRFlood.wireSize)
            guard let msg = SRFlood.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrFlood(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .placeMine:
            let bytes = try await rest(SRPlaceMine.wireSize)
            guard let msg = SRPlaceMine.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPlaceMine(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .dropMine:
            let bytes = try await rest(SRDropMine.wireSize)
            guard let msg = SRDropMine.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrDropMine(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .dropBoat:
            let bytes = try await rest(SRDropBoat.wireSize)
            guard let msg = SRDropBoat.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrDropBoat(x: Int(msg.x), y: Int(msg.y), state: &state)
        case .repairPill:
            let bytes = try await rest(SRRepairPill.wireSize)
            guard let msg = SRRepairPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrRepairPill(pill: Int(msg.pill), armour: msg.armour, state: &state, onPillStatusChanged: callbacks.onPillStatusChanged)
        case .coolPill:
            let bytes = try await rest(SRCoolPill.wireSize)
            guard let msg = SRCoolPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrCoolPill(pill: Int(msg.pill), state: &state)
        case .capturePill:
            let bytes = try await rest(SRCapturePill.wireSize)
            guard let msg = SRCapturePill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrCapturePill(
                pill: Int(msg.pill), owner: msg.owner, state: &state,
                onPillStatusChanged: callbacks.onPillStatusChanged, onDropPills: callbacks.onDropPills,
                onRequestGrabTile: callbacks.onRequestGrabTile
            )
        case .buildPill:
            let bytes = try await rest(SRBuildPill.wireSize)
            guard let msg = SRBuildPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrBuildPill(
                pill: Int(msg.pill), x: msg.x, y: msg.y, armour: msg.armour, state: &state,
                onPillStatusChanged: callbacks.onPillStatusChanged
            )
        case .dropPill:
            let bytes = try await rest(SRDropPill.wireSize)
            guard let msg = SRDropPill.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrDropPill(pill: Int(msg.pill), x: msg.x, y: msg.y, state: &state, onPillStatusChanged: callbacks.onPillStatusChanged)
        case .replenishBase:
            let bytes = try await rest(SRReplenishBase.wireSize)
            guard let msg = SRReplenishBase.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrReplenishBase(base: Int(msg.base), state: &state, onBaseStatusChanged: callbacks.onBaseStatusChanged)
        case .captureBase:
            let bytes = try await rest(SRCaptureBase.wireSize)
            guard let msg = SRCaptureBase.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrCaptureBase(base: Int(msg.base), owner: msg.owner, state: &state, onBaseStatusChanged: callbacks.onBaseStatusChanged)
        case .refuel:
            let bytes = try await rest(SRRefuel.wireSize)
            guard let msg = SRRefuel.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrRefuel(base: Int(msg.base), armour: msg.armour, shells: msg.shells, mines: msg.mines, state: &state)
        case .grabBoat:
            let bytes = try await rest(SRGrabBoat.wireSize)
            guard let msg = SRGrabBoat.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrGrabBoat(player: Int(msg.player), x: Int(msg.x), y: Int(msg.y), state: &state)
        case .mineAck:
            let bytes = try await rest(SRMineAck.wireSize)
            guard let msg = SRMineAck.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrMineAck(success: msg.success != 0, state: &state, onTankStatusChanged: callbacks.onTankStatusChanged)
        case .builderAck:
            let bytes = try await rest(SRBuilderAck.wireSize)
            guard let msg = SRBuilderAck.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrBuilderAck(mines: msg.mines, trees: msg.trees, pill: msg.pill, state: &state)
        case .smallBoom:
            let bytes = try await rest(SRSmallBoom.wireSize)
            guard let msg = SRSmallBoom.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrSmallBoom(
                player: msg.player, x: Int(msg.x), y: Int(msg.y), state: &state,
                onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
                onDropPills: callbacks.onDropPills, onTankStatusChanged: callbacks.onTankStatusChanged
            )
        case .superBoom:
            let bytes = try await rest(SRSuperBoom.wireSize)
            guard let msg = SRSuperBoom.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrSuperBoom(
                player: msg.player, x: Int(msg.x), y: Int(msg.y), state: &state,
                onMineExplosion: callbacks.onMineExplosion, onSuperboomTerrain: callbacks.onSuperboomTerrain,
                onDropPills: callbacks.onDropPills, onTankStatusChanged: callbacks.onTankStatusChanged
            )
        case .hitTank:
            let bytes = try await rest(SRHitTank.wireSize)
            guard let msg = SRHitTank.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrHitTank(dir: msg.dir, state: &state, onTankStatusChanged: callbacks.onTankStatusChanged, onDropPills: callbacks.onDropPills)
        case .setAlliance:
            let bytes = try await rest(SRSetAlliance.wireSize)
            guard let msg = SRSetAlliance.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrSetAlliance(
                player: Int(msg.player), alliance: msg.alliance, state: &state,
                onPlayerStatusChanged: callbacks.onPlayerStatusChanged, onBaseStatusChanged: callbacks.onBaseStatusChanged,
                onPillStatusChanged: callbacks.onPillStatusChanged, onShouldLeaveAlliance: callbacks.onShouldLeaveAlliance
            )
        case .timeLimit:
            let bytes = try await rest(SRTimeLimit.wireSize)
            guard let msg = SRTimeLimit.decode(bytes) else { throw TCPSessionError.malformedMessage }
            callbacks.onTimeLimit(msg.timeRemaining)
        case .baseControl:
            let bytes = try await rest(SRBaseControl.wireSize)
            guard let msg = SRBaseControl.decode(bytes) else { throw TCPSessionError.malformedMessage }
            callbacks.onBaseControl(msg.timeLeft)
        case .pause:
            let bytes = try await rest(SRPause.wireSize)
            guard let msg = SRPause.decode(bytes) else { throw TCPSessionError.malformedMessage }
            recvSrPause(pause: msg.pause, state: &state)
        }

        return opcode
    }

    public func cancel() {
        connection.cancel()
    }
}
