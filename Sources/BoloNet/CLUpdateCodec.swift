import BoloKit

// MARK: - CLUpdate — the UDP state datagram
//
// Ported from `sendclupdate()`/`dgramclient()` (`Reference/c/client.c:
// 3509-3592`, `1280-1472`). No opcode byte, no magic — the datagram *is*
// this struct. Three encodings live in one packet: raw big-endian
// IEEE-754 bit-reinterpret for tank/builder floats, 1/256 fixed-point for
// shell/explosion positions and shell range, and 8-bit "brad" scale for
// directions. See `WireIO.swift` for the shared conversion helpers.

public struct CLUpdateShell: Sendable, Hashable {
    public var owner: UInt8
    public var point: Vec2f
    public var boat: Bool
    public var pill: Bool
    public var dir: Float
    public var range: Float

    public init(owner: UInt8, point: Vec2f, boat: Bool, pill: Bool, dir: Float, range: Float) {
        self.owner = owner
        self.point = point
        self.boat = boat
        self.pill = pill
        self.dir = dir
        self.range = range
    }

    public static let wireSize = 10

    public func encode(into w: inout WireWriter) {
        w.putU8(owner)
        w.putU16(fixedEncode(point.x))
        w.putU16(fixedEncode(point.y))
        w.putU8(boat ? 1 : 0)
        w.putU8(pill ? 1 : 0)
        w.putU8(bradEncode(dir))
        w.putU16(fixedEncode(range))
    }

    static func decode(from r: inout WireReader) -> CLUpdateShell? {
        guard let owner = r.getU8(),
              let x = r.getU16(),
              let y = r.getU16(),
              let boat = r.getU8(),
              let pill = r.getU8(),
              let dir = r.getU8(),
              let range = r.getU16()
        else { return nil }
        return CLUpdateShell(
            owner: owner,
            point: Vec2f(x: fixedDecode(x), y: fixedDecode(y)),
            boat: boat != 0,
            pill: pill != 0,
            dir: bradDecode(dir),
            range: fixedDecode(range)
        )
    }
}

public struct CLUpdateExplosion: Sendable, Hashable {
    public var point: Vec2f
    public var counter: UInt8

    public init(point: Vec2f, counter: UInt8) {
        self.point = point
        self.counter = counter
    }

    public static let wireSize = 6

    /// `tile` (offset 4, between the position and `counter`) is never
    /// written by `sendclupdate()` and never read by `dgramclient()` —
    /// trap 1. Encoded as 0 for a deterministic wire image, ignored on
    /// decode; there is deliberately no Swift-side field for it.
    public func encode(into w: inout WireWriter) {
        w.putU16(fixedEncode(point.x))
        w.putU16(fixedEncode(point.y))
        w.putU8(0)
        w.putU8(counter)
    }

    static func decode(from r: inout WireReader) -> CLUpdateExplosion? {
        guard let x = r.getU16(),
              let y = r.getU16(),
              let _tile = r.getU8(),
              let counter = r.getU8()
        else { return nil }
        return CLUpdateExplosion(point: Vec2f(x: fixedDecode(x), y: fixedDecode(y)), counter: counter)
    }
}

public struct CLUpdateHeader: Sendable, Hashable {
    public var player: UInt8
    /// One sequence number per player slot (`MAXPLAYERS` = 16) — doubles
    /// as the ack/latency mechanism; there is no separate ack packet.
    public var seq: [Int32]
    public var dead: Bool
    public var boat: Bool
    public var dir: Float
    public var tank: Vec2f
    public var speed: Float
    public var turnSpeed: Float
    public var kickDir: Float
    public var kickSpeed: Float
    public var builderStatus: UInt8
    public var builder: Vec2f
    public var builderTargetX: UInt8
    public var builderTargetY: UInt8
    public var builderWait: UInt8
    public var inputFlags: Int32
    public var tankShotSound: Bool
    public var pillShotSound: Bool
    public var sinkSound: Bool
    public var builderDeathSound: Bool

    public init(
        player: UInt8,
        seq: [Int32],
        dead: Bool,
        boat: Bool,
        dir: Float,
        tank: Vec2f,
        speed: Float,
        turnSpeed: Float,
        kickDir: Float,
        kickSpeed: Float,
        builderStatus: UInt8,
        builder: Vec2f,
        builderTargetX: UInt8,
        builderTargetY: UInt8,
        builderWait: UInt8,
        inputFlags: Int32,
        tankShotSound: Bool,
        pillShotSound: Bool,
        sinkSound: Bool,
        builderDeathSound: Bool
    ) {
        self.player = player
        self.seq = seq
        self.dead = dead
        self.boat = boat
        self.dir = dir
        self.tank = tank
        self.speed = speed
        self.turnSpeed = turnSpeed
        self.kickDir = kickDir
        self.kickSpeed = kickSpeed
        self.builderStatus = builderStatus
        self.builder = builder
        self.builderTargetX = builderTargetX
        self.builderTargetY = builderTargetY
        self.builderWait = builderWait
        self.inputFlags = inputFlags
        self.tankShotSound = tankShotSound
        self.pillShotSound = pillShotSound
        self.sinkSound = sinkSound
        self.builderDeathSound = builderDeathSound
    }

    /// `kTankDead = 0`, `kTankFireball = 1`, `kTankOnBoat = 2`,
    /// `kTankNormal = 3` (`bolo.h:342-346`) — `dead`/`boat` are each one
    /// bit of that 4-way status, `kTankFireball` maps to neither.
    public static func tankStatus(dead: Bool, boat: Bool) -> UInt8 {
        if dead { return 0 }
        if boat { return 2 }
        return 3
    }

    public static let wireSize = 113
}

public struct CLUpdate: Sendable, Hashable {
    public var header: CLUpdateHeader
    public var shells: [CLUpdateShell]
    public var explosions: [CLUpdateExplosion]

    public init(header: CLUpdateHeader, shells: [CLUpdateShell], explosions: [CLUpdateExplosion]) {
        self.header = header
        self.shells = shells
        self.explosions = explosions
    }

    public static let maxShells = 255
    public static let maxExplosions = 255

    /// Mirrors `sendclupdate()` exactly, including its truncation to
    /// `CLUPDATEMAXSHELLS`/`CLUPDATEMAXEXPLOSIONS` (255 each) if more are
    /// supplied — matching the oracle's `nshells < CLUPDATEMAXSHELLS`
    /// loop guard rather than trapping or erroring.
    public func encode() -> [UInt8] {
        var w = WireWriter()
        let hdr = header

        w.putU8(hdr.player)
        for i in 0..<maxPlayers {
            w.putI32(i < hdr.seq.count ? hdr.seq[i] : 0)
        }
        w.putU8(CLUpdateHeader.tankStatus(dead: hdr.dead, boat: hdr.boat))
        w.putRawFloat(hdr.tank.x)
        w.putRawFloat(hdr.tank.y)
        w.putRawFloat(hdr.speed)
        w.putRawFloat(hdr.turnSpeed)
        w.putRawFloat(hdr.kickDir)
        w.putRawFloat(hdr.kickSpeed)
        w.putU8(bradEncode(hdr.dir))
        w.putU8(hdr.builderStatus)
        w.putRawFloat(hdr.builder.x)
        w.putRawFloat(hdr.builder.y)
        w.putU8(hdr.builderTargetX)
        w.putU8(hdr.builderTargetY)
        w.putU8(hdr.builderWait)
        w.putI32(hdr.inputFlags)
        w.putU8(hdr.tankShotSound ? 1 : 0)
        w.putU8(hdr.pillShotSound ? 1 : 0)
        w.putU8(hdr.sinkSound ? 1 : 0)
        w.putU8(hdr.builderDeathSound ? 1 : 0)

        let clampedShells = Array(shells.prefix(Self.maxShells))
        let clampedExplosions = Array(explosions.prefix(Self.maxExplosions))
        w.putU8(UInt8(clampedShells.count))
        w.putU8(UInt8(clampedExplosions.count))

        for shell in clampedShells {
            shell.encode(into: &w)
        }
        for explosion in clampedExplosions {
            explosion.encode(into: &w)
        }

        return w.bytes
    }

    /// Mirrors `dgramclient()`'s structural sanity check + `ntoh` pass +
    /// field decode. Deliberately excludes the `player == client.player`
    /// self-rejection (session state, not wire format — belongs to 6.1)
    /// and everything past decode: list mutation, sound playback, vis
    /// updates, and the dead-reckoning re-simulation loop (6.1/6.2).
    /// Returns `nil` on the same malformed-datagram conditions that make
    /// `dgramclient()` silently `continue` to the next packet.
    public static func decode(_ bytes: [UInt8]) -> CLUpdate? {
        guard bytes.count >= CLUpdateHeader.wireSize else { return nil }

        var r = WireReader(bytes)
        guard let player = r.getU8() else { return nil }

        var seq = [Int32](repeating: 0, count: maxPlayers)
        for i in 0..<maxPlayers {
            guard let s = r.getI32() else { return nil }
            seq[i] = s
        }

        guard let tankStatus = r.getU8(),
              let tankX = r.getRawFloat(),
              let tankY = r.getRawFloat(),
              let speed = r.getRawFloat(),
              let turnSpeed = r.getRawFloat(),
              let kickDir = r.getRawFloat(),
              let kickSpeed = r.getRawFloat(),
              let dir = r.getU8(),
              let builderStatus = r.getU8(),
              let builderX = r.getRawFloat(),
              let builderY = r.getRawFloat(),
              let builderTargetX = r.getU8(),
              let builderTargetY = r.getU8(),
              let builderWait = r.getU8(),
              let inputFlags = r.getI32(),
              let tankShotSound = r.getU8(),
              let pillShotSound = r.getU8(),
              let sinkSound = r.getU8(),
              let builderDeathSound = r.getU8(),
              let nshells = r.getU8(),
              let nexplosions = r.getU8()
        else { return nil }

        guard player < UInt8(maxPlayers) else { return nil }

        let expectedLength = CLUpdateHeader.wireSize
            + Int(nshells) * CLUpdateShell.wireSize
            + Int(nexplosions) * CLUpdateExplosion.wireSize
        guard bytes.count == expectedLength else { return nil }

        var shells: [CLUpdateShell] = []
        shells.reserveCapacity(Int(nshells))
        for _ in 0..<nshells {
            guard let shell = CLUpdateShell.decode(from: &r) else { return nil }
            shells.append(shell)
        }

        var explosions: [CLUpdateExplosion] = []
        explosions.reserveCapacity(Int(nexplosions))
        for _ in 0..<nexplosions {
            guard let explosion = CLUpdateExplosion.decode(from: &r) else { return nil }
            explosions.append(explosion)
        }

        let header = CLUpdateHeader(
            player: player,
            seq: seq,
            dead: tankStatus == 0,
            boat: tankStatus == 2,
            dir: bradDecode(dir),
            tank: Vec2f(x: tankX, y: tankY),
            speed: speed,
            turnSpeed: turnSpeed,
            kickDir: kickDir,
            kickSpeed: kickSpeed,
            builderStatus: builderStatus,
            builder: Vec2f(x: builderX, y: builderY),
            builderTargetX: builderTargetX,
            builderTargetY: builderTargetY,
            builderWait: builderWait,
            inputFlags: inputFlags,
            tankShotSound: tankShotSound != 0,
            pillShotSound: pillShotSound != 0,
            sinkSound: sinkSound != 0,
            builderDeathSound: builderDeathSound != 0
        )

        return CLUpdate(header: header, shells: shells, explosions: explosions)
    }
}

/// Wraparound-tolerant sequence comparison — `(new - old) > 0` as signed
/// 32-bit arithmetic (`client.c:1333`). Swift's `-` traps on `Int32`
/// overflow; `&-` reproduces C's silently-wrapping signed subtraction,
/// which is exactly what makes the comparison wraparound-tolerant in the
/// first place.
public func isNewerSeq(_ new: Int32, than old: Int32) -> Bool {
    (new &- old) > 0
}
