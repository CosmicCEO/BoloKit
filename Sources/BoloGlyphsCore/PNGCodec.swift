import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// D77 fix: `Canvas16`/`RGBASheet` buffers are straight (non-premultiplied) alpha -- `set`/
// `fillRect` write r/g/b and a independently. `CGContext` bitmap creation only accepts
// premultiplied (or alpha-none) storage formats -- `CGImageAlphaInfo.last` is refused at
// context-creation time (verified empirically, not assumed). So the buffer must be
// premultiplied before it's copied into a `premultipliedLast` context; PNG encoding then
// un-premultiplies back to the original straight values on export, which is what makes this
// round-trip losslessly rather than silently drifting (PARITY's Wave 7.1 finding, F1).

/// Premultiplies a straight-alpha RGBA buffer in place semantics (returns a copy), rounding
/// to the nearest integer -- the inverse of the un-premultiply CoreGraphics performs when
/// encoding a premultiplied `CGImage` to PNG (PNG itself is always straight-alpha on disk).
public func premultiplyStraightAlpha(_ pixels: [UInt8]) -> [UInt8] {
    var out = pixels
    var i = 0
    while i < out.count {
        let a = Int(out[i + 3])
        out[i] = UInt8((Int(out[i]) * a + 127) / 255)
        out[i + 1] = UInt8((Int(out[i + 1]) * a + 127) / 255)
        out[i + 2] = UInt8((Int(out[i + 2]) * a + 127) / 255)
        i += 4
    }
    return out
}

/// Encodes a straight-alpha `size`x`size` RGBA buffer as PNG data.
public func encodePNGData(_ pixels: [UInt8], size: Int) -> Data? {
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(
        data: nil,
        width: size,
        height: size,
        bitsPerComponent: 8,
        bytesPerRow: size * 4,
        space: colorSpace,
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    ) else {
        return nil
    }

    let premultiplied = premultiplyStraightAlpha(pixels)
    premultiplied.withUnsafeBytes { src in
        context.data!.copyMemory(from: src.baseAddress!, byteCount: src.count)
    }

    guard let image = context.makeImage() else { return nil }

    let data = NSMutableData()
    guard let dest = CGImageDestinationCreateWithData(data, UTType.png.identifier as CFString, 1, nil) else {
        return nil
    }
    CGImageDestinationAddImage(dest, image, nil)
    guard CGImageDestinationFinalize(dest) else { return nil }
    return data as Data
}

/// Decodes PNG bytes back to a straight-alpha RGBA buffer -- used by the regression test to
/// verify emitted bytes match source intent, not just the in-memory buffer (F1's actual gap:
/// no prior test decoded an emitted PNG at all).
public func decodePNGToStraightAlphaRGBA(_ data: Data) -> [UInt8]? {
    guard let provider = CGDataProvider(data: data as CFData),
          let image = CGImage(
            pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent
          )
    else {
        return nil
    }
    guard let raw = image.dataProvider?.data as Data? else { return nil }
    return Array(raw)
}
