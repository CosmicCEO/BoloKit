import CoreGraphics
import Foundation
import Testing
import BoloKit

@testable import Bolo_2026

@MainActor
private func makeTrivialImage() -> CGImage {
    let ctx = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return ctx.makeImage()!
}

@MainActor
struct PlaySessionActionsTests {
    @Test func zoomAndSheetsReclaimFocus() {
        var reclaimed = 0
        var status = false
        let image = makeTrivialImage()
        let session = GameSession(
            initialState: GameState(), tilesImage: image, spritesImage: image
        )
        let actions = PlaySessionActions.make(
            session: session,
            reclaimFocus: { reclaimed += 1 },
            setShowingStatus: { status = $0 },
            setShowingAlliances: { _ in },
            setShowingMessages: { _ in },
            onQuitToMenu: {}
        )
        actions.zoomIn()
        actions.zoomOut()
        actions.showStatus()
        #expect(reclaimed == 3)
        #expect(status)
        #expect(!actions.canPauseResume)
    }

    @Test func toggleMuteFlipsGSMuteBool() {
        let key = PlaySessionActions.muteDefaultsKey
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: key)
        defaults.set(false, forKey: key)
        defer {
            if let previous {
                defaults.set(previous, forKey: key)
            } else {
                defaults.removeObject(forKey: key)
            }
        }
        let image = makeTrivialImage()
        let session = GameSession(
            initialState: GameState(), tilesImage: image, spritesImage: image
        )
        let actions = PlaySessionActions.make(
            session: session,
            reclaimFocus: {},
            setShowingStatus: { _ in },
            setShowingAlliances: { _ in },
            setShowingMessages: { _ in },
            onQuitToMenu: {}
        )
        actions.toggleMute()
        #expect(defaults.bool(forKey: key))
        actions.toggleMute()
        #expect(!defaults.bool(forKey: key))
    }
}
