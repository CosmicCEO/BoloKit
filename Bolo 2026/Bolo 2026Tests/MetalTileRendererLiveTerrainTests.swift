//
//  MetalTileRendererLiveTerrainTests.swift
//  Bolo 2026Tests
//
//  v1.6.0 (#25) increment 6 follow-up: regression coverage for the resize bug found on first
//  live evaluation (eval build `v160-metal-eval d49ca48`) -- "elements scale with the window
//  while the map does not." Increments 4-5's `MetalTileRendererTests.swift` are pixel-exact but
//  only exercise `draw(_:ctx:dirtyRect:)`, the offscreen path; `renderLiveTerrain`'s camera math
//  (`MetalTileRenderer.cameraTransform`) had zero coverage, which is exactly the function that
//  was broken. The actual bug was `GameRenderView.installLiveMetalOverlayIfNeeded` sizing the
//  overlay's `MTKView` to the *whole* enclosing `NSScrollView` (`scrollView.bounds`), not the
//  inset-excluded clip-view region (`scrollView.contentView.frame`) that `visibleRect` -- and
//  every other on-screen geometry computation in this file -- already correctly uses. That bug
//  lived in AppKit view wiring, not in `cameraTransform`'s own arithmetic, so these tests can't
//  reproduce it directly without a hosted window (the fragility this codebase's own `.disabled`
//  precedent, `GameRenderViewZoomTests`' T-calibration benchmark and
//  `LiveMetalTerrainOverlayTests.swift`, already established isn't worth chasing here).
//
//  What these tests *can* do headlessly, with no window/MTKView/display link: assert
//  `cameraTransform`'s formula is self-consistent and behaves as documented across a spread of
//  `visibleRect`/`targetTextureWidthPixels` inputs -- catching a future regression in the
//  arithmetic itself, even though the original bug was upstream of it.

import AppKit
import Testing

@testable import Bolo_2026

struct MetalTileRendererLiveTerrainTests {

    /// The core invariant a correct caller must maintain (and the one the original bug broke):
    /// when `targetTextureWidthPixels` is exactly the `visibleRect`'s width scaled by some
    /// backing-scale/magnification factor, `cameraTransform.scale` must equal that same factor
    /// -- i.e. this function correctly *recovers* the caller's intended scale rather than
    /// silently absorbing a size mismatch. Swept across window-like widths standing in for
    /// several real window sizes and magnifications.
    @Test(arguments: [
        (visibleWidth: 400.0, factor: 1.0), (visibleWidth: 400.0, factor: 2.0),
        (visibleWidth: 812.0, factor: 1.0), (visibleWidth: 812.0, factor: 2.0),
        (visibleWidth: 1200.0, factor: 1.5), (visibleWidth: 50.0, factor: 2.0),
    ])
    func scaleRecoversTheCallersIntendedFactor(visibleWidth: Double, factor: Double) throws {
        let visibleRect = NSRect(x: 12, y: 34, width: visibleWidth, height: visibleWidth * 0.75)
        let targetWidthPixels = Int((visibleWidth * factor).rounded())
        let transform = MetalTileRenderer.cameraTransform(
            visibleRect: visibleRect, targetTextureWidthPixels: targetWidthPixels
        )
        let transformScale = try #require(transform).scale
        #expect(abs(Double(transformScale) - factor) < 0.01)
    }

    /// Regression guard for the actual reported symptom, reproduced as a pure arithmetic
    /// statement: if a caller's `targetTextureWidthPixels` corresponds to a *wider* region than
    /// `visibleRect` describes (exactly what `scrollView.bounds`, insets included, was versus
    /// `scrollView.contentView.frame`/`visibleRect`, insets excluded), the recovered scale comes
    /// out systematically *larger* than the true backing-scale/magnification factor, and that
    /// error shrinks as the extra width becomes a smaller fraction of the total -- both signed
    /// and magnitude behavior match "elements scale with the window while the map does not"
    /// getting worse on a narrow window and converging toward correct on a wide one.
    @Test
    func anOversizedTargetTextureInflatesScaleByExactlyTheExtraRegionsFraction() {
        let trueFactor: Float = 2.0
        let visibleWidth = 400.0
        let insetPoints = 284.0 // the real measured contentInsets total (56 + 228), D157/D160

        let correctTransform = try! #require(
            MetalTileRenderer.cameraTransform(
                visibleRect: NSRect(x: 0, y: 0, width: visibleWidth, height: 300),
                targetTextureWidthPixels: Int(visibleWidth * Double(trueFactor))
            )
        )
        // The bug: target sized off `scrollView.bounds` (visibleWidth + insetPoints) while
        // `visibleRect` (used unchanged) still only describes the inset-excluded region.
        let buggyTransform = try! #require(
            MetalTileRenderer.cameraTransform(
                visibleRect: NSRect(x: 0, y: 0, width: visibleWidth, height: 300),
                targetTextureWidthPixels: Int((visibleWidth + insetPoints) * Double(trueFactor))
            )
        )

        #expect(correctTransform.scale == trueFactor)
        let expectedBuggyScale = trueFactor * Float((visibleWidth + insetPoints) / visibleWidth)
        #expect(abs(buggyTransform.scale - expectedBuggyScale) < 0.001)
        #expect(buggyTransform.scale > correctTransform.scale) // the "elements too large" direction

        // Narrowing the window (smaller visibleWidth, same fixed inset) makes the same absolute
        // inset a *larger* fraction of the total -- the error must grow, not shrink, matching
        // "worse on a narrow window."
        let narrowerCorrect = try! #require(
            MetalTileRenderer.cameraTransform(
                visibleRect: NSRect(x: 0, y: 0, width: 200, height: 150),
                targetTextureWidthPixels: Int(200 * Double(trueFactor))
            )
        )
        let narrowerBuggy = try! #require(
            MetalTileRenderer.cameraTransform(
                visibleRect: NSRect(x: 0, y: 0, width: 200, height: 150),
                targetTextureWidthPixels: Int((200 + insetPoints) * Double(trueFactor))
            )
        )
        let widerErrorFraction = (buggyTransform.scale - correctTransform.scale) / correctTransform.scale
        let narrowerErrorFraction = (narrowerBuggy.scale - narrowerCorrect.scale) / narrowerCorrect.scale
        #expect(narrowerErrorFraction > widerErrorFraction)
    }

    /// `scaledTileSize` must track `scale` linearly (16pt tiles at 1x scale become 32px tiles at
    /// 2x) -- guards against reintroducing a separate, inconsistent tile-size computation.
    @Test
    func scaledTileSizeTracksScaleLinearly() {
        let visibleRect = NSRect(x: 0, y: 0, width: 100, height: 100)
        let transform1x = try! #require(
            MetalTileRenderer.cameraTransform(visibleRect: visibleRect, targetTextureWidthPixels: 100)
        )
        let transform2x = try! #require(
            MetalTileRenderer.cameraTransform(visibleRect: visibleRect, targetTextureWidthPixels: 200)
        )
        #expect(transform1x.scaledTileSize == 16)
        #expect(transform2x.scaledTileSize == 32)
    }

    /// A degenerate (zero-width) `visibleRect` -- e.g. a window mid-collapse -- must not divide
    /// by zero; `renderLiveTerrain` relies on this `nil` to skip the frame entirely.
    @Test
    func zeroWidthVisibleRectReturnsNilRatherThanDividingByZero() {
        let transform = MetalTileRenderer.cameraTransform(
            visibleRect: NSRect(x: 0, y: 0, width: 0, height: 100), targetTextureWidthPixels: 400
        )
        #expect(transform == nil)
    }
}
