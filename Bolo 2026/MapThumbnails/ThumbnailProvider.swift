import AppKit
import Foundation
import QuickLookThumbnailing
import CoreGraphics
import os

/// Finder desktop icons use this extension. Project-wide MainActor default
/// would isolate `provideThumbnail` (quicklookd calls it off-main).
@objc(ThumbnailProvider)
final class ThumbnailProvider: QLThumbnailProvider {
    private static let log = Logger(
        subsystem: "com.cosmicceo.Bolo-2026.MapThumbnails", category: "thumb"
    )

    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        let fileURL = request.fileURL
        let size = request.maximumSize
        Self.log.info("thumb \(fileURL.lastPathComponent, privacy: .public) \(size.width, format: .fixed)x\(size.height, format: .fixed)")
        handler(QLThumbnailReply(contextSize: size, currentContextDrawing: {
            let tiles = MapThumbnail.loadTiles(from: .main)
                ?? MapThumbnail.loadTiles(from: Bundle(for: ThumbnailProvider.self))
            guard let tiles else {
                Self.log.error("no Tiles.png")
                return false
            }
            let scoped = fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { fileURL.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: fileURL) else {
                Self.log.error("read failed")
                return false
            }
            guard let image = MapThumbnail.makeImage(from: Array(data), tiles: tiles) else {
                Self.log.error("decode/blit failed")
                return false
            }
            guard let ctx = NSGraphicsContext.current?.cgContext else {
                Self.log.error("no current context")
                return false
            }
            ctx.interpolationQuality = .none
            ctx.draw(image, in: CGRect(origin: .zero, size: size))
            return true
        }), nil)
    }
}
