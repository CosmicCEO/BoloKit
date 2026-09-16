import Foundation
import QuickLookThumbnailing
import CoreGraphics

final class ThumbnailProvider: QLThumbnailProvider {
    override func provideThumbnail(
        for request: QLFileThumbnailRequest,
        _ handler: @escaping (QLThumbnailReply?, Error?) -> Void
    ) {
        handler(QLThumbnailReply(contextSize: request.maximumSize, drawing: { context in
            guard let tiles = MapThumbnail.loadTiles() else { return false }
            let scoped = request.fileURL.startAccessingSecurityScopedResource()
            defer { if scoped { request.fileURL.stopAccessingSecurityScopedResource() } }
            guard let data = try? Data(contentsOf: request.fileURL) else { return false }
            guard let image = MapThumbnail.makeImage(from: Array(data), tiles: tiles) else { return false }
            let size = request.maximumSize
            context.interpolationQuality = .none
            context.draw(image, in: CGRect(origin: .zero, size: size))
            return true
        }), nil)
    }
}
