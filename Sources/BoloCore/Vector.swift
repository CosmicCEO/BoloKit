import Darwin

// MARK: - Constants
public let kPif: Float = 3.14159265358979
public let k2Pif: Float = 6.28318530717959

// MARK: - Vector Types

public struct Vec2f: Hashable, Sendable {
    public var x: Float
    public var y: Float

    public init(x: Float, y: Float) {
        self.x = x
        self.y = y
    }
}

public struct Vec2i32: Hashable, Sendable {
    public var x: Int32
    public var y: Int32

    public init(x: Int32, y: Int32) {
        self.x = x
        self.y = y
    }
}

public struct Vec2i16: Hashable, Sendable {
    public var x: Int16
    public var y: Int16

    public init(x: Int16, y: Int16) {
        self.x = x
        self.y = y
    }
}

public struct Vec2i8: Hashable, Sendable {
    public var x: Int8
    public var y: Int8

    public init(x: Int8, y: Int8) {
        self.x = x
        self.y = y
    }
}

public struct Vec2u8: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8

    public init(x: UInt8, y: UInt8) {
        self.x = x
        self.y = y
    }
}

// MARK: - Conversion Utilities

public func u16tof(_ s: UInt16) -> Float {
    return Float(s) / 256.0
}

public func ftou16(_ s: Float) -> UInt16 {
    return UInt16(bitPattern: Int16(s * 256.0))
}

public func i16tof(_ s: Int16) -> Float {
    return Float(s) / 256.0
}

public func ftoi16(_ s: Float) -> Int16 {
    return Int16(s * 256.0)
}

// MARK: - Vec2f Operations

public func make2f(_ x: Float, _ y: Float) -> Vec2f {
    return Vec2f(x: x, y: y)
}

public func neg2f(_ v: Vec2f) -> Vec2f {
    return Vec2f(x: -v.x, y: -v.y)
}

public func add2f(_ v1: Vec2f, _ v2: Vec2f) -> Vec2f {
    return Vec2f(x: v1.x + v2.x, y: v1.y + v2.y)
}

public func sub2f(_ v1: Vec2f, _ v2: Vec2f) -> Vec2f {
    return Vec2f(x: v1.x - v2.x, y: v1.y - v2.y)
}

public func mul2f(_ v: Vec2f, _ s: Float) -> Vec2f {
    return Vec2f(x: v.x * s, y: v.y * s)
}

public func div2f(_ v: Vec2f, _ s: Float) -> Vec2f {
    return Vec2f(x: v.x / s, y: v.y / s)
}

public func dot2f(_ v1: Vec2f, _ v2: Vec2f) -> Float {
    return v1.x * v2.x + v1.y * v2.y
}

public func mag2f(_ v: Vec2f) -> Float {
    return sqrt(dot2f(v, v))
}

public func unit2f(_ v: Vec2f) -> Vec2f {
    return div2f(v, mag2f(v))
}

public func prj2f(_ v1: Vec2f, _ v2: Vec2f) -> Vec2f {
    return mul2f(v1, dot2f(v1, v2) / dot2f(v1, v1))
}

public func cmp2f(_ v1: Vec2f, _ v2: Vec2f) -> Float {
    return dot2f(v1, v2) / mag2f(v1)
}

public func isequal2f(_ v1: Vec2f, _ v2: Vec2f) -> Int32 {
    return (v1.x == v2.x && v1.y == v2.y) ? 1 : 0
}

public func tan2f(_ theta: Float) -> Vec2f {
    return Vec2f(x: cos(theta), y: sin(theta))
}

public func _atan2f(_ dir: Vec2f) -> Float {
    return atan2(dir.y, dir.x)
}

// MARK: - Vec2i32 Operations

public func make2i32(_ x: Int32, _ y: Int32) -> Vec2i32 {
    return Vec2i32(x: x, y: y)
}

public func neg2i32(_ v: Vec2i32) -> Vec2i32 {
    return Vec2i32(x: 0 &- v.x, y: 0 &- v.y)
}

public func add2i32(_ v1: Vec2i32, _ v2: Vec2i32) -> Vec2i32 {
    return Vec2i32(x: v1.x &+ v2.x, y: v1.y &+ v2.y)
}

public func sub2i32(_ v1: Vec2i32, _ v2: Vec2i32) -> Vec2i32 {
    return Vec2i32(x: v1.x &- v2.x, y: v1.y &- v2.y)
}

public func mul2i32(_ v: Vec2i32, _ s: Int32) -> Vec2i32 {
    return Vec2i32(x: v.x &* s, y: v.y &* s)
}

public func div2i32(_ v: Vec2i32, _ s: Int32) -> Vec2i32 {
    return Vec2i32(x: v.x / s, y: v.y / s)
}

public func dot2i32(_ v1: Vec2i32, _ v2: Vec2i32) -> Int32 {
    return (v1.x &* v2.x) &+ (v1.y &* v2.y)
}

public func mag2i32(_ v: Vec2i32) -> Int32 {
    let d = Double(dot2i32(v, v))
    guard d >= 0 else { return 0 }
    return Int32(sqrt(d))
}

public func prj2i32(_ v1: Vec2i32, _ v2: Vec2i32) -> Vec2i32 {
    return mul2i32(v1, dot2i32(v1, v2) / dot2i32(v1, v1))
}

public func cmp2i32(_ v1: Vec2i32, _ v2: Vec2i32) -> Int32 {
    return dot2i32(v1, v2) / mag2i32(v1)
}

public func isequal2i32(_ v1: Vec2i32, _ v2: Vec2i32) -> Int32 {
    return (v1.x == v2.x && v1.y == v2.y) ? 1 : 0
}

public func tan2i32(_ dir: UInt8) -> Vec2i32 {
    let angle = Float(dir) * (kPif / 8.0)
    let cx = cos(Double(angle)) * Double(Int32.max)
    let cy = sin(Double(angle)) * Double(Int32.max)
    return Vec2i32(x: Int32(cx), y: Int32(cy))
}

public func scale2i32(_ dir: UInt8, _ scale: Int32) -> Vec2i32 {
    return div2i32(tan2i32(dir), Int32.max / scale)
}

public func c2i32to2i16(_ v: Vec2i32) -> Vec2i16 {
    return Vec2i16(x: Int16(truncatingIfNeeded: v.x), y: Int16(truncatingIfNeeded: v.y))
}

// MARK: - Vec2i16 Operations

public func make2i16(_ x: Int16, _ y: Int16) -> Vec2i16 {
    return Vec2i16(x: x, y: y)
}

public func neg2i16(_ v: Vec2i16) -> Vec2i16 {
    return Vec2i16(
        x: Int16(truncatingIfNeeded: -Int32(v.x)),
        y: Int16(truncatingIfNeeded: -Int32(v.y))
    )
}

public func add2i16(_ v1: Vec2i16, _ v2: Vec2i16) -> Vec2i16 {
    return Vec2i16(
        x: Int16(truncatingIfNeeded: Int32(v1.x) + Int32(v2.x)),
        y: Int16(truncatingIfNeeded: Int32(v1.y) + Int32(v2.y))
    )
}

public func sub2i16(_ v1: Vec2i16, _ v2: Vec2i16) -> Vec2i16 {
    return Vec2i16(
        x: Int16(truncatingIfNeeded: Int32(v1.x) - Int32(v2.x)),
        y: Int16(truncatingIfNeeded: Int32(v1.y) - Int32(v2.y))
    )
}

public func mul2i16(_ v: Vec2i16, _ s: Int16) -> Vec2i16 {
    return Vec2i16(
        x: Int16(truncatingIfNeeded: Int32(v.x) * Int32(s)),
        y: Int16(truncatingIfNeeded: Int32(v.y) * Int32(s))
    )
}

public func div2i16(_ v: Vec2i16, _ s: Int16) -> Vec2i16 {
    return Vec2i16(
        x: Int16(truncatingIfNeeded: Int32(v.x) / Int32(s)),
        y: Int16(truncatingIfNeeded: Int32(v.y) / Int32(s))
    )
}

public func dot2i16(_ v1: Vec2i16, _ v2: Vec2i16) -> Int16 {
    return Int16(truncatingIfNeeded: Int32(v1.x) * Int32(v2.x) + Int32(v1.y) * Int32(v2.y))
}

public func mag2i16(_ v: Vec2i16) -> Int16 {
    let d = Double(dot2i16(v, v))
    guard d >= 0 else { return 0 }
    return Int16(sqrt(d))
}

public func prj2i16(_ v1: Vec2i16, _ v2: Vec2i16) -> Vec2i16 {
    return mul2i16(v1, dot2i16(v1, v2) / dot2i16(v1, v1))
}

public func cmp2i16(_ v1: Vec2i16, _ v2: Vec2i16) -> Int16 {
    return dot2i16(v1, v2) / mag2i16(v1)
}

public func isequal2i16(_ v1: Vec2i16, _ v2: Vec2i16) -> Int32 {
    return (v1.x == v2.x && v1.y == v2.y) ? 1 : 0
}

public func tan2i16(_ dir: UInt8) -> Vec2i16 {
    let angle = Float(dir) * (kPif / 8.0)
    let cx = cos(Double(angle)) * Double(Int16.max)
    let cy = sin(Double(angle)) * Double(Int16.max)
    return Vec2i16(x: Int16(cx), y: Int16(cy))
}

public func scale2i16(_ dir: UInt8, _ scale: Int16) -> Vec2i16 {
    return div2i16(tan2i16(dir), Int16.max / scale)
}

public func c2i16to2i8(_ v: Vec2i16) -> Vec2i8 {
    return Vec2i8(x: Int8(truncatingIfNeeded: v.x), y: Int8(truncatingIfNeeded: v.y))
}

// MARK: - Vec2i8 Operations

public func make2i8(_ x: Int8, _ y: Int8) -> Vec2i8 {
    return Vec2i8(x: x, y: y)
}

public func isequal2i8(_ v1: Vec2i8, _ v2: Vec2i8) -> Int32 {
    return (v1.x == v2.x && v1.y == v2.y) ? 1 : 0
}

// MARK: - Operator Overloads

extension Vec2f {
    public static prefix func -(v: Vec2f) -> Vec2f {
        return Vec2f(x: -v.x, y: -v.y)
    }
    public static func +(lhs: Vec2f, rhs: Vec2f) -> Vec2f {
        return Vec2f(x: lhs.x + rhs.x, y: lhs.y + rhs.y)
    }
    public static func -(lhs: Vec2f, rhs: Vec2f) -> Vec2f {
        return Vec2f(x: lhs.x - rhs.x, y: lhs.y - rhs.y)
    }
    public static func *(lhs: Vec2f, rhs: Float) -> Vec2f {
        return Vec2f(x: lhs.x * rhs, y: lhs.y * rhs)
    }
    public static func /(lhs: Vec2f, rhs: Float) -> Vec2f {
        return Vec2f(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

extension Vec2i32 {
    public static prefix func -(v: Vec2i32) -> Vec2i32 {
        return Vec2i32(x: 0 &- v.x, y: 0 &- v.y)
    }
    public static func +(lhs: Vec2i32, rhs: Vec2i32) -> Vec2i32 {
        return Vec2i32(x: lhs.x &+ rhs.x, y: lhs.y &+ rhs.y)
    }
    public static func -(lhs: Vec2i32, rhs: Vec2i32) -> Vec2i32 {
        return Vec2i32(x: lhs.x &- rhs.x, y: lhs.y &- rhs.y)
    }
    public static func *(lhs: Vec2i32, rhs: Int32) -> Vec2i32 {
        return Vec2i32(x: lhs.x &* rhs, y: lhs.y &* rhs)
    }
    public static func /(lhs: Vec2i32, rhs: Int32) -> Vec2i32 {
        return Vec2i32(x: lhs.x / rhs, y: lhs.y / rhs)
    }
}

extension Vec2i16 {
    public static prefix func -(v: Vec2i16) -> Vec2i16 {
        return Vec2i16(
            x: Int16(truncatingIfNeeded: -Int32(v.x)),
            y: Int16(truncatingIfNeeded: -Int32(v.y))
        )
    }
    public static func +(lhs: Vec2i16, rhs: Vec2i16) -> Vec2i16 {
        return Vec2i16(
            x: Int16(truncatingIfNeeded: Int32(lhs.x) + Int32(rhs.x)),
            y: Int16(truncatingIfNeeded: Int32(lhs.y) + Int32(rhs.y))
        )
    }
    public static func -(lhs: Vec2i16, rhs: Vec2i16) -> Vec2i16 {
        return Vec2i16(
            x: Int16(truncatingIfNeeded: Int32(lhs.x) - Int32(rhs.x)),
            y: Int16(truncatingIfNeeded: Int32(lhs.y) - Int32(rhs.y))
        )
    }
    public static func *(lhs: Vec2i16, rhs: Int16) -> Vec2i16 {
        return Vec2i16(
            x: Int16(truncatingIfNeeded: Int32(lhs.x) * Int32(rhs)),
            y: Int16(truncatingIfNeeded: Int32(lhs.y) * Int32(rhs))
        )
    }
    public static func /(lhs: Vec2i16, rhs: Int16) -> Vec2i16 {
        return Vec2i16(
            x: Int16(truncatingIfNeeded: Int32(lhs.x) / Int32(rhs)),
            y: Int16(truncatingIfNeeded: Int32(lhs.y) / Int32(rhs))
        )
    }
}
