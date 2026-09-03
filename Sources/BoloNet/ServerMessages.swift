import BoloKit

// MARK: - Server -> client TCP broadcast messages
//
// Ported from the 34 `SR*` structs (`Reference/c/server.h:124-330`) and
// their opcode enum (`Reference/c/bolo.h:203-238`). Same framing rules as
// `ClientMessages.swift`: no length prefix, dispatch on the leading
// opcode byte, every multi-byte field `htons`/`htonl`'d on the wire.
/// `SRHitTank.dir` is a raw-BE-bit-reinterpret float, matching
/// `CLHitTank.dir` — see that type's doc comment for the server's opaque-
/// forwarding relay detail, which doesn't change this codec's field type.
/// `SRHangUp` is the only struct not `__attribute__((__packed__))` in the
/// C source (`server.h:124`) — harmless at one byte, and the opcode is
/// marked "not used" (`bolo.h:210`); included here anyway since the
/// struct and opcode both still exist in the wire-format's namespace.

public enum ServerOpcode: UInt8, Sendable {
    case playerJoin = 0
    case playerRejoin = 1
    case playerExit = 2
    case playerDisc = 3
    case playerKick = 4
    case playerBan = 5
    case hangUp = 6
    case sendMesg = 7
    case damage = 8
    case grabTrees = 9
    case build = 10
    case grow = 11
    case flood = 12
    case placeMine = 13
    case dropMine = 14
    case dropBoat = 15
    case repairPill = 16
    case coolPill = 17
    case capturePill = 18
    case buildPill = 19
    case dropPill = 20
    case replenishBase = 21
    case captureBase = 22
    case refuel = 23
    case grabBoat = 24
    case mineAck = 25
    case builderAck = 26
    case smallBoom = 27
    case superBoom = 28
    case hitTank = 29
    case setAlliance = 30
    case timeLimit = 31
    case baseControl = 32
    case pause = 33
}

private func decodeOpcode(_ r: inout WireReader, expect: ServerOpcode) -> Bool {
    guard let raw = r.getU8(), raw == expect.rawValue else { return false }
    return true
}

/// Fixed-width `MAXNAME` (16) / `MAXHOST` (32) ASCII fields — NUL-padded,
/// not NUL-terminated-with-trailer like the chat messages.
public struct SRPlayerJoin: Sendable, Hashable {
    public var player: UInt8
    public var name: String
    public var host: String
    public init(player: UInt8, name: String, host: String) {
        self.player = player; self.name = name; self.host = host
    }
    public static let wireSize = 50
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.playerJoin.rawValue)
        w.putU8(player)
        w.putFixedString(name, count: 16)
        w.putFixedString(host, count: 32)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPlayerJoin? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .playerJoin) else { return nil }
        guard let player = r.getU8(), let name = r.getFixedString(16), let host = r.getFixedString(32) else { return nil }
        return SRPlayerJoin(player: player, name: name, host: host)
    }
}

public struct SRPlayerRejoin: Sendable, Hashable {
    public var player: UInt8
    public var host: String
    public init(player: UInt8, host: String) { self.player = player; self.host = host }
    public static let wireSize = 34
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.playerRejoin.rawValue)
        w.putU8(player)
        w.putFixedString(host, count: 32)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPlayerRejoin? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .playerRejoin) else { return nil }
        guard let player = r.getU8(), let host = r.getFixedString(32) else { return nil }
        return SRPlayerRejoin(player: player, host: host)
    }
}

public struct SRPlayerExit: Sendable, Hashable {
    public var player: UInt8
    public init(player: UInt8) { self.player = player }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.playerExit.rawValue); w.putU8(player); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPlayerExit? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .playerExit) else { return nil }
        guard let player = r.getU8() else { return nil }
        return SRPlayerExit(player: player)
    }
}

public struct SRPlayerDisc: Sendable, Hashable {
    public var player: UInt8
    public init(player: UInt8) { self.player = player }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.playerDisc.rawValue); w.putU8(player); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPlayerDisc? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .playerDisc) else { return nil }
        guard let player = r.getU8() else { return nil }
        return SRPlayerDisc(player: player)
    }
}

public struct SRPlayerKick: Sendable, Hashable {
    public var player: UInt8
    public init(player: UInt8) { self.player = player }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.playerKick.rawValue); w.putU8(player); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPlayerKick? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .playerKick) else { return nil }
        guard let player = r.getU8() else { return nil }
        return SRPlayerKick(player: player)
    }
}

public struct SRPlayerBan: Sendable, Hashable {
    public var player: UInt8
    public init(player: UInt8) { self.player = player }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.playerBan.rawValue); w.putU8(player); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPlayerBan? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .playerBan) else { return nil }
        guard let player = r.getU8() else { return nil }
        return SRPlayerBan(player: player)
    }
}

public struct SRHangUp: Sendable, Hashable {
    public init() {}
    public static let wireSize = 1
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.hangUp.rawValue); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRHangUp? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .hangUp) else { return nil }
        return SRHangUp()
    }
}

public struct SRSendMesg: Sendable, Hashable {
    public var player: UInt8
    public var to: UInt8
    public var text: String
    public init(player: UInt8, to: UInt8, text: String) { self.player = player; self.to = to; self.text = text }
    /// The fixed portion only (opcode+player+to) -- `text` is a
    /// NUL-terminated tail with no length prefix, so it isn't part of a
    /// fixed wire size. A TCP reader must read these 3 bytes first, then
    /// keep reading one byte at a time until (and including) the NUL.
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.sendMesg.rawValue)
        w.putU8(player)
        w.putU8(to)
        w.putNulTerminatedString(text)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRSendMesg? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .sendMesg) else { return nil }
        guard let player = r.getU8(), let to = r.getU8(), let text = r.getNulTerminatedString() else { return nil }
        return SRSendMesg(player: player, to: to, text: text)
    }
}

public struct SRDamage: Sendable, Hashable {
    public var player: UInt8
    public var x: UInt8
    public var y: UInt8
    public var terrain: UInt8
    public init(player: UInt8, x: UInt8, y: UInt8, terrain: UInt8) {
        self.player = player; self.x = x; self.y = y; self.terrain = terrain
    }
    public static let wireSize = 5
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.damage.rawValue); w.putU8(player); w.putU8(x); w.putU8(y); w.putU8(terrain)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRDamage? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .damage) else { return nil }
        guard let player = r.getU8(), let x = r.getU8(), let y = r.getU8(), let terrain = r.getU8() else { return nil }
        return SRDamage(player: player, x: x, y: y, terrain: terrain)
    }
}

public struct SRGrabTrees: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.grabTrees.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRGrabTrees? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .grabTrees) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRGrabTrees(x: x, y: y)
    }
}

public struct SRBuild: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var terrain: UInt8
    public init(x: UInt8, y: UInt8, terrain: UInt8) { self.x = x; self.y = y; self.terrain = terrain }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.build.rawValue); w.putU8(x); w.putU8(y); w.putU8(terrain); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRBuild? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .build) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let terrain = r.getU8() else { return nil }
        return SRBuild(x: x, y: y, terrain: terrain)
    }
}

public struct SRGrow: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.grow.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRGrow? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .grow) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRGrow(x: x, y: y)
    }
}

public struct SRFlood: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.flood.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRFlood? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .flood) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRFlood(x: x, y: y)
    }
}

public struct SRPlaceMine: Sendable, Hashable {
    public var player: UInt8
    public var x: UInt8
    public var y: UInt8
    public init(player: UInt8, x: UInt8, y: UInt8) { self.player = player; self.x = x; self.y = y }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.placeMine.rawValue); w.putU8(player); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPlaceMine? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .placeMine) else { return nil }
        guard let player = r.getU8(), let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRPlaceMine(player: player, x: x, y: y)
    }
}

public struct SRDropMine: Sendable, Hashable {
    public var player: UInt8
    public var x: UInt8
    public var y: UInt8
    public init(player: UInt8, x: UInt8, y: UInt8) { self.player = player; self.x = x; self.y = y }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.dropMine.rawValue); w.putU8(player); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRDropMine? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .dropMine) else { return nil }
        guard let player = r.getU8(), let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRDropMine(player: player, x: x, y: y)
    }
}

public struct SRDropBoat: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.dropBoat.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRDropBoat? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .dropBoat) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRDropBoat(x: x, y: y)
    }
}

public struct SRRepairPill: Sendable, Hashable {
    public var pill: UInt8
    public var armour: UInt8
    public init(pill: UInt8, armour: UInt8) { self.pill = pill; self.armour = armour }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.repairPill.rawValue); w.putU8(pill); w.putU8(armour); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRRepairPill? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .repairPill) else { return nil }
        guard let pill = r.getU8(), let armour = r.getU8() else { return nil }
        return SRRepairPill(pill: pill, armour: armour)
    }
}

public struct SRCoolPill: Sendable, Hashable {
    public var pill: UInt8
    public init(pill: UInt8) { self.pill = pill }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.coolPill.rawValue); w.putU8(pill); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRCoolPill? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .coolPill) else { return nil }
        guard let pill = r.getU8() else { return nil }
        return SRCoolPill(pill: pill)
    }
}

public struct SRCapturePill: Sendable, Hashable {
    public var pill: UInt8
    public var owner: UInt8
    public init(pill: UInt8, owner: UInt8) { self.pill = pill; self.owner = owner }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.capturePill.rawValue); w.putU8(pill); w.putU8(owner); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRCapturePill? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .capturePill) else { return nil }
        guard let pill = r.getU8(), let owner = r.getU8() else { return nil }
        return SRCapturePill(pill: pill, owner: owner)
    }
}

public struct SRBuildPill: Sendable, Hashable {
    public var pill: UInt8
    public var x: UInt8
    public var y: UInt8
    public var armour: UInt8
    public init(pill: UInt8, x: UInt8, y: UInt8, armour: UInt8) {
        self.pill = pill; self.x = x; self.y = y; self.armour = armour
    }
    public static let wireSize = 5
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.buildPill.rawValue); w.putU8(pill); w.putU8(x); w.putU8(y); w.putU8(armour)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRBuildPill? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .buildPill) else { return nil }
        guard let pill = r.getU8(), let x = r.getU8(), let y = r.getU8(), let armour = r.getU8() else { return nil }
        return SRBuildPill(pill: pill, x: x, y: y, armour: armour)
    }
}

public struct SRDropPill: Sendable, Hashable {
    public var pill: UInt8
    public var x: UInt8
    public var y: UInt8
    public init(pill: UInt8, x: UInt8, y: UInt8) { self.pill = pill; self.x = x; self.y = y }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.dropPill.rawValue); w.putU8(pill); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRDropPill? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .dropPill) else { return nil }
        guard let pill = r.getU8(), let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRDropPill(pill: pill, x: x, y: y)
    }
}

public struct SRReplenishBase: Sendable, Hashable {
    public var base: UInt8
    public init(base: UInt8) { self.base = base }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.replenishBase.rawValue); w.putU8(base); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRReplenishBase? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .replenishBase) else { return nil }
        guard let base = r.getU8() else { return nil }
        return SRReplenishBase(base: base)
    }
}

public struct SRCaptureBase: Sendable, Hashable {
    public var base: UInt8
    public var owner: UInt8
    public init(base: UInt8, owner: UInt8) { self.base = base; self.owner = owner }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.captureBase.rawValue); w.putU8(base); w.putU8(owner); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRCaptureBase? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .captureBase) else { return nil }
        guard let base = r.getU8(), let owner = r.getU8() else { return nil }
        return SRCaptureBase(base: base, owner: owner)
    }
}

public struct SRRefuel: Sendable, Hashable {
    public var base: UInt8
    public var armour: UInt8
    public var shells: UInt8
    public var mines: UInt8
    public init(base: UInt8, armour: UInt8, shells: UInt8, mines: UInt8) {
        self.base = base; self.armour = armour; self.shells = shells; self.mines = mines
    }
    public static let wireSize = 5
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.refuel.rawValue); w.putU8(base); w.putU8(armour); w.putU8(shells); w.putU8(mines)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRRefuel? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .refuel) else { return nil }
        guard let base = r.getU8(), let armour = r.getU8(), let shells = r.getU8(), let mines = r.getU8() else { return nil }
        return SRRefuel(base: base, armour: armour, shells: shells, mines: mines)
    }
}

public struct SRGrabBoat: Sendable, Hashable {
    public var player: UInt8
    public var x: UInt8
    public var y: UInt8
    public init(player: UInt8, x: UInt8, y: UInt8) { self.player = player; self.x = x; self.y = y }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.grabBoat.rawValue); w.putU8(player); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRGrabBoat? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .grabBoat) else { return nil }
        guard let player = r.getU8(), let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRGrabBoat(player: player, x: x, y: y)
    }
}

public struct SRMineAck: Sendable, Hashable {
    public var success: UInt8
    public init(success: UInt8) { self.success = success }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.mineAck.rawValue); w.putU8(success); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRMineAck? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .mineAck) else { return nil }
        guard let success = r.getU8() else { return nil }
        return SRMineAck(success: success)
    }
}

public struct SRBuilderAck: Sendable, Hashable {
    public var mines: UInt8
    public var trees: UInt8
    public var pill: UInt8
    public init(mines: UInt8, trees: UInt8, pill: UInt8) { self.mines = mines; self.trees = trees; self.pill = pill }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.builderAck.rawValue); w.putU8(mines); w.putU8(trees); w.putU8(pill)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRBuilderAck? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .builderAck) else { return nil }
        guard let mines = r.getU8(), let trees = r.getU8(), let pill = r.getU8() else { return nil }
        return SRBuilderAck(mines: mines, trees: trees, pill: pill)
    }
}

public struct SRSmallBoom: Sendable, Hashable {
    public var player: UInt8
    public var x: UInt8
    public var y: UInt8
    public init(player: UInt8, x: UInt8, y: UInt8) { self.player = player; self.x = x; self.y = y }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.smallBoom.rawValue); w.putU8(player); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRSmallBoom? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .smallBoom) else { return nil }
        guard let player = r.getU8(), let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRSmallBoom(player: player, x: x, y: y)
    }
}

public struct SRSuperBoom: Sendable, Hashable {
    public var player: UInt8
    public var x: UInt8
    public var y: UInt8
    public init(player: UInt8, x: UInt8, y: UInt8) { self.player = player; self.x = x; self.y = y }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.superBoom.rawValue); w.putU8(player); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRSuperBoom? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .superBoom) else { return nil }
        guard let player = r.getU8(), let x = r.getU8(), let y = r.getU8() else { return nil }
        return SRSuperBoom(player: player, x: x, y: y)
    }
}

public struct SRHitTank: Sendable, Hashable {
    public var player: UInt8
    public var dir: Float
    public init(player: UInt8, dir: Float) { self.player = player; self.dir = dir }
    public static let wireSize = 6
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ServerOpcode.hitTank.rawValue); w.putU8(player); w.putRawFloat(dir)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRHitTank? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .hitTank) else { return nil }
        guard let player = r.getU8(), let dir = r.getRawFloat() else { return nil }
        return SRHitTank(player: player, dir: dir)
    }
}

public struct SRSetAlliance: Sendable, Hashable {
    public var player: UInt8
    public var alliance: UInt16
    public init(player: UInt8, alliance: UInt16) { self.player = player; self.alliance = alliance }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.setAlliance.rawValue); w.putU8(player); w.putU16(alliance); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRSetAlliance? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .setAlliance) else { return nil }
        guard let player = r.getU8(), let alliance = r.getU16() else { return nil }
        return SRSetAlliance(player: player, alliance: alliance)
    }
}

public struct SRTimeLimit: Sendable, Hashable {
    public var timeRemaining: UInt16
    public init(timeRemaining: UInt16) { self.timeRemaining = timeRemaining }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.timeLimit.rawValue); w.putU16(timeRemaining); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRTimeLimit? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .timeLimit) else { return nil }
        guard let timeRemaining = r.getU16() else { return nil }
        return SRTimeLimit(timeRemaining: timeRemaining)
    }
}

public struct SRBaseControl: Sendable, Hashable {
    public var timeLeft: UInt16
    public init(timeLeft: UInt16) { self.timeLeft = timeLeft }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.baseControl.rawValue); w.putU16(timeLeft); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRBaseControl? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .baseControl) else { return nil }
        guard let timeLeft = r.getU16() else { return nil }
        return SRBaseControl(timeLeft: timeLeft)
    }
}

public struct SRPause: Sendable, Hashable {
    public var pause: UInt8
    public init(pause: UInt8) { self.pause = pause }
    public static let wireSize = 2
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ServerOpcode.pause.rawValue); w.putU8(pause); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> SRPause? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .pause) else { return nil }
        guard let pause = r.getU8() else { return nil }
        return SRPause(pause: pause)
    }
}
