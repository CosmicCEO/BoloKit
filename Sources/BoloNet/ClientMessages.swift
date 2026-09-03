import BoloKit

// MARK: - Client -> server TCP control messages
//
// Ported from the 20 `CL*` structs (`Reference/c/client.h:155-245`) and
// their opcode enum (`Reference/c/bolo.h:167-188`). Dispatch on the real
// side is a `switch` on the first buffered byte, consumed as part of each
// struct rather than peeked — there is no length prefix; length is
// implied by opcode, except `sendMesg`, which is struct + NUL-terminated
// text. Every multi-byte field seen on the wire (`client.c:3195-3454,
// 6320-6399`) is confirmed `htons`/`htonl`'d — single-byte fields need no
// swap and get none. Two floats — `dropPills.x/y` and `hitTank.dir` — use
// the same raw-BE-bit-reinterpret trick as `CLUpdate`'s tank/builder
// positions, not the fixed-point scale used for shells/explosions.

public enum ClientOpcode: UInt8, Sendable {
    case hangUp = 0
    case sendMesg = 1
    case dropBoat = 2
    case dropPills = 3
    case dropMine = 4
    case touch = 5
    case grabTile = 6
    case grabTrees = 7
    case buildRoad = 8
    case buildWall = 9
    case buildBoat = 10
    case buildPill = 11
    case repairPill = 12
    case placeMine = 13
    case damage = 14
    case smallBoom = 15
    case superBoom = 16
    case refuel = 17
    case hitTank = 18
    case setAlliance = 19
}

private func decodeOpcode(_ r: inout WireReader, expect: ClientOpcode) -> Bool {
    guard let raw = r.getU8(), raw == expect.rawValue else { return false }
    return true
}

public struct CLHangUp: Sendable, Hashable {
    public init() {}
    public static let wireSize = 1
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.hangUp.rawValue); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLHangUp? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .hangUp) else { return nil }
        return CLHangUp()
    }
}

/// `mask` is `int16_t` on the wire (`client.h:167`) — signed, so bit 15
/// sets the sign bit. `text` is the NUL-terminated trailer with no fixed
/// width, the one variable-length payload among the `CL*` structs.
public struct CLSendMesg: Sendable, Hashable {
    public var to: UInt8
    public var mask: Int16
    public var text: String
    public init(to: UInt8, mask: Int16, text: String) {
        self.to = to; self.mask = mask; self.text = text
    }
    /// The fixed portion only (opcode+to+mask) -- `text` is a
    /// NUL-terminated tail with no length prefix, same convention as
    /// `SRSendMesg.wireSize`.
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ClientOpcode.sendMesg.rawValue)
        w.putU8(to)
        w.putI16(mask)
        w.putNulTerminatedString(text)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLSendMesg? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .sendMesg) else { return nil }
        guard let to = r.getU8(), let mask = r.getI16(), let text = r.getNulTerminatedString() else { return nil }
        return CLSendMesg(to: to, mask: mask, text: text)
    }
}

public struct CLDropBoat: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.dropBoat.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLDropBoat? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .dropBoat) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return CLDropBoat(x: x, y: y)
    }
}

/// `x`/`y` are raw-BE-bit-reinterpret floats, not fixed-point
/// (`client.c:3452-3453`) — the same trick `CLUpdate`'s tank/builder
/// positions use, unlike the shell/explosion fixed-point scale.
public struct CLDropPills: Sendable, Hashable {
    public var x: Float
    public var y: Float
    public var pills: UInt16
    public init(x: Float, y: Float, pills: UInt16) { self.x = x; self.y = y; self.pills = pills }
    public static let wireSize = 11
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ClientOpcode.dropPills.rawValue)
        w.putRawFloat(x)
        w.putRawFloat(y)
        w.putU16(pills)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLDropPills? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .dropPills) else { return nil }
        guard let x = r.getRawFloat(), let y = r.getRawFloat(), let pills = r.getU16() else { return nil }
        return CLDropPills(x: x, y: y, pills: pills)
    }
}

public struct CLDropMine: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.dropMine.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLDropMine? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .dropMine) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return CLDropMine(x: x, y: y)
    }
}

public struct CLTouch: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.touch.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLTouch? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .touch) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return CLTouch(x: x, y: y)
    }
}

public struct CLGrabTile: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.grabTile.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLGrabTile? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .grabTile) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return CLGrabTile(x: x, y: y)
    }
}

public struct CLGrabTrees: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.grabTrees.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLGrabTrees? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .grabTrees) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return CLGrabTrees(x: x, y: y)
    }
}

public struct CLBuildRoad: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var trees: UInt8
    public init(x: UInt8, y: UInt8, trees: UInt8) { self.x = x; self.y = y; self.trees = trees }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.buildRoad.rawValue); w.putU8(x); w.putU8(y); w.putU8(trees); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLBuildRoad? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .buildRoad) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let trees = r.getU8() else { return nil }
        return CLBuildRoad(x: x, y: y, trees: trees)
    }
}

public struct CLBuildWall: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var trees: UInt8
    public init(x: UInt8, y: UInt8, trees: UInt8) { self.x = x; self.y = y; self.trees = trees }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.buildWall.rawValue); w.putU8(x); w.putU8(y); w.putU8(trees); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLBuildWall? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .buildWall) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let trees = r.getU8() else { return nil }
        return CLBuildWall(x: x, y: y, trees: trees)
    }
}

public struct CLBuildBoat: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var trees: UInt8
    public init(x: UInt8, y: UInt8, trees: UInt8) { self.x = x; self.y = y; self.trees = trees }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.buildBoat.rawValue); w.putU8(x); w.putU8(y); w.putU8(trees); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLBuildBoat? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .buildBoat) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let trees = r.getU8() else { return nil }
        return CLBuildBoat(x: x, y: y, trees: trees)
    }
}

public struct CLBuildPill: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var trees: UInt8
    public var pill: UInt8
    public init(x: UInt8, y: UInt8, trees: UInt8, pill: UInt8) {
        self.x = x; self.y = y; self.trees = trees; self.pill = pill
    }
    public static let wireSize = 5
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ClientOpcode.buildPill.rawValue); w.putU8(x); w.putU8(y); w.putU8(trees); w.putU8(pill)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLBuildPill? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .buildPill) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let trees = r.getU8(), let pill = r.getU8() else { return nil }
        return CLBuildPill(x: x, y: y, trees: trees, pill: pill)
    }
}

public struct CLRepairPill: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var trees: UInt8
    public init(x: UInt8, y: UInt8, trees: UInt8) { self.x = x; self.y = y; self.trees = trees }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.repairPill.rawValue); w.putU8(x); w.putU8(y); w.putU8(trees); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLRepairPill? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .repairPill) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let trees = r.getU8() else { return nil }
        return CLRepairPill(x: x, y: y, trees: trees)
    }
}

public struct CLPlaceMine: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var mines: UInt8
    public init(x: UInt8, y: UInt8, mines: UInt8) { self.x = x; self.y = y; self.mines = mines }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.placeMine.rawValue); w.putU8(x); w.putU8(y); w.putU8(mines); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLPlaceMine? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .placeMine) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let mines = r.getU8() else { return nil }
        return CLPlaceMine(x: x, y: y, mines: mines)
    }
}

public struct CLDamage: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public var boat: UInt8
    public init(x: UInt8, y: UInt8, boat: UInt8) { self.x = x; self.y = y; self.boat = boat }
    public static let wireSize = 4
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.damage.rawValue); w.putU8(x); w.putU8(y); w.putU8(boat); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLDamage? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .damage) else { return nil }
        guard let x = r.getU8(), let y = r.getU8(), let boat = r.getU8() else { return nil }
        return CLDamage(x: x, y: y, boat: boat)
    }
}

public struct CLSmallBoom: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.smallBoom.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLSmallBoom? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .smallBoom) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return CLSmallBoom(x: x, y: y)
    }
}

public struct CLSuperBoom: Sendable, Hashable {
    public var x: UInt8
    public var y: UInt8
    public init(x: UInt8, y: UInt8) { self.x = x; self.y = y }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.superBoom.rawValue); w.putU8(x); w.putU8(y); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLSuperBoom? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .superBoom) else { return nil }
        guard let x = r.getU8(), let y = r.getU8() else { return nil }
        return CLSuperBoom(x: x, y: y)
    }
}

public struct CLRefuel: Sendable, Hashable {
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
        w.putU8(ClientOpcode.refuel.rawValue); w.putU8(base); w.putU8(armour); w.putU8(shells); w.putU8(mines)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLRefuel? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .refuel) else { return nil }
        guard let base = r.getU8(), let armour = r.getU8(), let shells = r.getU8(), let mines = r.getU8() else { return nil }
        return CLRefuel(base: base, armour: armour, shells: shells, mines: mines)
    }
}

/// `dir` is a raw-BE-bit-reinterpret float (`client.c:3500`), same trick
/// as `CLDropPills`. The server relays it opaquely to `SRHitTank.dir`
/// without re-decoding/re-encoding (`server.c:3754`) — a relay detail
/// belonging to 6.2/6.3, not this codec, which still defines the field as
/// a float regardless of how any particular relay happens to move it.
public struct CLHitTank: Sendable, Hashable {
    public var player: UInt8
    public var dir: Float
    public init(player: UInt8, dir: Float) { self.player = player; self.dir = dir }
    public static let wireSize = 6
    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putU8(ClientOpcode.hitTank.rawValue); w.putU8(player); w.putRawFloat(dir)
        return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLHitTank? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .hitTank) else { return nil }
        guard let player = r.getU8(), let dir = r.getRawFloat() else { return nil }
        return CLHitTank(player: player, dir: dir)
    }
}

public struct CLSetAlliance: Sendable, Hashable {
    public var alliance: UInt16
    public init(alliance: UInt16) { self.alliance = alliance }
    public static let wireSize = 3
    public func encode() -> [UInt8] {
        var w = WireWriter(); w.putU8(ClientOpcode.setAlliance.rawValue); w.putU16(alliance); return w.bytes
    }
    public static func decode(_ bytes: [UInt8]) -> CLSetAlliance? {
        var r = WireReader(bytes)
        guard decodeOpcode(&r, expect: .setAlliance) else { return nil }
        guard let alliance = r.getU16() else { return nil }
        return CLSetAlliance(alliance: alliance)
    }
}
