import BoloKit

// MARK: - Big-endian byte reader/writer
//
// The wire format has no host-native fields anywhere: every multi-byte
// integer is `htons`/`htonl`'d, and every float is sent as its raw
// IEEE-754 bit pattern, also byte-swapped as if it were an integer of the
// same width (`client.c:3526` etc. — `htonl(*((uint32_t *)&x))`). These
// primitives exist once, here, so every wire struct's encode/decode is a
// straight sequence of `put`/`get` calls with no per-struct byte-order
// logic to get wrong.

public struct WireWriter {
    public private(set) var bytes: [UInt8] = []

    public init() {}

    public mutating func putU8(_ v: UInt8) {
        bytes.append(v)
    }

    public mutating func putU16(_ v: UInt16) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    public mutating func putU32(_ v: UInt32) {
        bytes.append(UInt8(truncatingIfNeeded: v >> 24))
        bytes.append(UInt8(truncatingIfNeeded: v >> 16))
        bytes.append(UInt8(truncatingIfNeeded: v >> 8))
        bytes.append(UInt8(truncatingIfNeeded: v))
    }

    public mutating func putI16(_ v: Int16) {
        putU16(UInt16(bitPattern: v))
    }

    public mutating func putI32(_ v: Int32) {
        putU32(UInt32(bitPattern: v))
    }

    /// Raw IEEE-754 bit-reinterpret, never a numeric round-trip — matches
    /// `htonl(*((uint32_t *)&f))`, not `htonl((uint32_t)f)`.
    public mutating func putRawFloat(_ v: Float) {
        putU32(v.bitPattern)
    }

    public mutating func putBytes(_ b: [UInt8]) {
        bytes.append(contentsOf: b)
    }

    /// Fixed-width ASCII field, NUL-padded/truncated to `count` bytes —
    /// matches C's `char name[MAXNAME]` struct members.
    public mutating func putFixedString(_ s: String, count: Int) {
        var utf8 = Array(s.utf8.prefix(count))
        while utf8.count < count {
            utf8.append(0)
        }
        bytes.append(contentsOf: utf8)
    }

    /// NUL-terminated string with no fixed width — matches the chat
    /// messages, the only variable-length wire payloads (`CLSendMesg`/
    /// `SRSendMesg`'s trailing text, scanned for `'\0'` on the C side).
    public mutating func putNulTerminatedString(_ s: String) {
        bytes.append(contentsOf: Array(s.utf8))
        bytes.append(0)
    }
}

public struct WireReader {
    private let bytes: [UInt8]
    private var offset: Int

    public init(_ bytes: [UInt8]) {
        self.bytes = bytes
        self.offset = 0
    }

    public var remaining: Int { bytes.count - offset }

    public mutating func getU8() -> UInt8? {
        guard remaining >= 1 else { return nil }
        let v = bytes[offset]
        offset += 1
        return v
    }

    public mutating func getU16() -> UInt16? {
        guard remaining >= 2 else { return nil }
        let v = (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
        offset += 2
        return v
    }

    public mutating func getU32() -> UInt32? {
        guard remaining >= 4 else { return nil }
        let v = (UInt32(bytes[offset]) << 24)
            | (UInt32(bytes[offset + 1]) << 16)
            | (UInt32(bytes[offset + 2]) << 8)
            | UInt32(bytes[offset + 3])
        offset += 4
        return v
    }

    public mutating func getI16() -> Int16? {
        getU16().map { Int16(bitPattern: $0) }
    }

    public mutating func getI32() -> Int32? {
        getU32().map { Int32(bitPattern: $0) }
    }

    public mutating func getRawFloat() -> Float? {
        getU32().map { Float(bitPattern: $0) }
    }

    public mutating func getBytes(_ count: Int) -> [UInt8]? {
        guard remaining >= count else { return nil }
        let slice = Array(bytes[offset..<(offset + count)])
        offset += count
        return slice
    }

    public mutating func getFixedString(_ count: Int) -> String? {
        guard let raw = getBytes(count) else { return nil }
        let nulIndex = raw.firstIndex(of: 0) ?? raw.count
        return String(decoding: raw[raw.startIndex..<nulIndex], as: UTF8.self)
    }

    /// Scans the remainder of the buffer for a NUL terminator, matching
    /// `strlen`-style parsing of `CLSendMesg`/`SRSendMesg`'s trailing text.
    public mutating func getNulTerminatedString() -> String? {
        guard let nulOffset = bytes[offset...].firstIndex(of: 0) else { return nil }
        let raw = Array(bytes[offset..<nulOffset])
        offset = nulOffset + 1
        return String(decoding: raw, as: UTF8.self)
    }
}

// MARK: - Fixed-point and brad conversions
//
// `FWIDTH` (bolo.h) is the shared scale for both the 1/256 fixed-point
// position encoding and the 8-bit "brad" direction encoding
// (`FWIDTH/k2Pif` — 256 subdivisions of a full turn). Both truncate on
// encode; neither rounds (`(uint16_t)(x*FWIDTH)`, `(uint8_t)(dir*(FWIDTH/
// k2Pif))` are C casts, not `roundf`). `Int64` intermediates avoid Swift's
// float-to-integer trap on out-of-domain input without changing behavior
// for the valid domain (map coordinates in [0, 256), directions in
// [0, 2π)) — the only domain the real game ever produces.

public let fWidth: Float = 256.0

/// `FWIDTH` is `#define FWIDTH (256.0)` (`bolo.h:67`) — an unsuffixed
/// literal, so it's a C `double`, not a `float`. `k2Pif` (`vector.c:17`)
/// is `const float`. C's usual arithmetic conversions mean every
/// `x*FWIDTH` and `dir*(FWIDTH/k2Pif)` in `sendclupdate()`/`dgramclient()`
/// actually computes in double precision — `FWIDTH/k2Pif` promotes
/// `k2Pif` to `double` first, then `dir`/`x` promotes to `double` for the
/// outer multiply — before truncating (encode) or rounding to the
/// destination `float` field (decode, an implicit double-to-float
/// conversion). All four conversions below use `Double` for exactly this
/// reason: naive all-`Float` arithmetic (matching `fWidth`'s Swift type)
/// diverges from the oracle on a real fraction of inputs, the same class
/// of finding as D26's `-ffp-contract=off` fix for `dot2f`/`mag2f`. This
/// is the oracle's own arithmetic, not a Swift precision upgrade — D18's
/// "Float, never Double" rule governs BoloKit's stored state, not the
/// literal type C's preprocessor assigned to `FWIDTH`.
private let fWidthD: Double = 256.0

public func fixedEncode(_ v: Float) -> UInt16 {
    UInt16(truncatingIfNeeded: Int64(Double(v) * fWidthD))
}

public func fixedDecode(_ v: UInt16) -> Float {
    Float(Double(v) / fWidthD)
}

public func bradEncode(_ dir: Float) -> UInt8 {
    UInt8(truncatingIfNeeded: Int64(Double(dir) * (fWidthD / Double(k2Pif))))
}

public func bradDecode(_ b: UInt8) -> Float {
    Float(Double(b) * (Double(k2Pif) / fWidthD))
}
