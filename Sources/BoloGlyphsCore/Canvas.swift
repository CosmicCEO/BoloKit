import Darwin

/// A 16x16 RGBA pixel patch. Top-left origin, row 0 = top (D66) -- matches
/// both PNG's and `CGContext`'s natural row order, so blitting into the
/// sheet and encoding to PNG both need zero flips.
public struct Canvas16: Sendable {
    public static let size = 16

    /// Row-major RGBA, `size * size * 4` bytes.
    public var pixels: [UInt8]

    public init() {
        pixels = [UInt8](repeating: 0, count: Canvas16.size * Canvas16.size * 4)
    }

    public mutating func set(_ x: Int, _ y: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        guard x >= 0, x < Canvas16.size, y >= 0, y < Canvas16.size else { return }
        let i = (y * Canvas16.size + x) * 4
        pixels[i] = r
        pixels[i + 1] = g
        pixels[i + 2] = b
        pixels[i + 3] = a
    }

    public mutating func fillRect(_ x0: Int, _ y0: Int, _ x1: Int, _ y1: Int, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        for y in max(0, y0)..<min(Canvas16.size, y1) {
            for x in max(0, x0)..<min(Canvas16.size, x1) {
                set(x, y, r, g, b, a)
            }
        }
    }

    public mutating func fillCircle(cx: Double, cy: Double, radius: Double, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        for y in 0..<Canvas16.size {
            for x in 0..<Canvas16.size {
                let dx = Double(x) + 0.5 - cx
                let dy = Double(y) + 0.5 - cy
                if dx * dx + dy * dy <= radius * radius {
                    set(x, y, r, g, b, a)
                }
            }
        }
    }

    public mutating func fillRing(cx: Double, cy: Double, inner: Double, outer: Double, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        for y in 0..<Canvas16.size {
            for x in 0..<Canvas16.size {
                let dx = Double(x) + 0.5 - cx
                let dy = Double(y) + 0.5 - cy
                let d2 = dx * dx + dy * dy
                if d2 <= outer * outer && d2 >= inner * inner {
                    set(x, y, r, g, b, a)
                }
            }
        }
    }

    /// Fills a triangle whose tip points toward -y (up) before rotation,
    /// rotated clockwise by `angle` radians about the cell center -- the
    /// "one directional glyph rotated per-angle" tank shape (PLAN.md 7.0).
    public mutating func fillRotatedTriangle(angle: Double, _ r: UInt8, _ g: UInt8, _ b: UInt8, _ a: UInt8 = 255) {
        let center = (8.0, 8.0)
        let tip = (0.0, -6.0)
        let left = (-5.0, 6.0)
        let right = (5.0, 6.0)
        func rotate(_ p: (Double, Double)) -> (Double, Double) {
            let s = sin(angle), c = cos(angle)
            return (p.0 * c - p.1 * s + center.0, p.0 * s + p.1 * c + center.1)
        }
        let p0 = rotate(tip), p1 = rotate(left), p2 = rotate(right)
        for y in 0..<Canvas16.size {
            for x in 0..<Canvas16.size {
                if Canvas16.pointInTriangle((Double(x) + 0.5, Double(y) + 0.5), p0, p1, p2) {
                    set(x, y, r, g, b, a)
                }
            }
        }
    }

    private static func sign(_ p1: (Double, Double), _ p2: (Double, Double), _ p3: (Double, Double)) -> Double {
        (p1.0 - p3.0) * (p2.1 - p3.1) - (p2.0 - p3.0) * (p1.1 - p3.1)
    }

    private static func pointInTriangle(_ pt: (Double, Double), _ v1: (Double, Double), _ v2: (Double, Double), _ v3: (Double, Double)) -> Bool {
        let d1 = sign(pt, v1, v2)
        let d2 = sign(pt, v2, v3)
        let d3 = sign(pt, v3, v1)
        let hasNeg = (d1 < 0) || (d2 < 0) || (d3 < 0)
        let hasPos = (d1 > 0) || (d2 > 0) || (d3 > 0)
        return !(hasNeg && hasPos)
    }
}

/// A 256x256 RGBA sheet buffer, same top-left convention as `Canvas16`.
public struct RGBASheet: Sendable {
    public static let size = 256

    public var pixels: [UInt8]

    public init() {
        pixels = [UInt8](repeating: 0, count: RGBASheet.size * RGBASheet.size * 4)
    }

    public mutating func blit(_ patch: Canvas16, atIndex index: Int32) {
        let originX = cellCol(index) * Canvas16.size
        let originY = cellRow(index) * Canvas16.size
        for y in 0..<Canvas16.size {
            for x in 0..<Canvas16.size {
                let srcI = (y * Canvas16.size + x) * 4
                let dstX = originX + x
                let dstY = originY + y
                let dstI = (dstY * RGBASheet.size + dstX) * 4
                pixels[dstI] = patch.pixels[srcI]
                pixels[dstI + 1] = patch.pixels[srcI + 1]
                pixels[dstI + 2] = patch.pixels[srcI + 2]
                pixels[dstI + 3] = patch.pixels[srcI + 3]
            }
        }
    }
}
