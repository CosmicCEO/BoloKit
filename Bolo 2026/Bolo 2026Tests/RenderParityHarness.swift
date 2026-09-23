//
//  RenderParityHarness.swift
//  Bolo 2026Tests
//
//  v1.6.0 (#25) increment 3: a deterministic, offscreen pixel-diff harness so a future
//  Metal-backed `TileRenderer` can be checked for parity against the existing
//  `CGContextTileRenderer` without a live window or wall-clock timing (the T-calibration
//  benchmark in `GameRenderViewZoomTests.swift` already established `cacheDisplay(in:to:)`/
//  `bitmapImageRepForCachingDisplay(in:)` is the wrong tool for *timing* -- ~15-20x slower and
//  not representative of live on-screen compositing cost -- but it remains exactly right for
//  *correctness* capture, per `GameRenderViewTests.swift`'s own established use of it for the
//  crosshair test). `renderRGBA(_:)`/`pixelDiff(_:_:)` here are the reusable pieces increments
//  4-5's parity tests are expected to import.

import AppKit
import CoreGraphics
import Testing
import BoloKit

@testable import Bolo_2026

/// Offscreen-renders `view`'s current state into raw RGBA bytes, same pattern
/// `GameRenderViewTests.swift`'s crosshair test already established. `rect` bounds the capture
/// in view point-space -- the full `view.bounds` is the entire 4096x4096 map (~67M pixels at
/// 2x Retina), which byte-diffs in well over a minute; callers should pass a small rect
/// around whatever the scene actually puts on screen instead of the whole map, unless a
/// genuine full-scene check is actually what's being verified. Device-pixel dimensions in the
/// result (`cg.width`/`cg.height`), not point-space -- callers comparing two renders must use
/// the same backing scale (true for any two views hosted in this same process).
func renderRGBA(_ view: GameRenderView, rect: NSRect? = nil) throws -> (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int) {
    let captureRect = rect ?? view.bounds
    let rep = try #require(view.bitmapImageRepForCachingDisplay(in: captureRect))
    view.cacheDisplay(in: captureRect, to: rep)
    let cg = try #require(rep.cgImage)
    let provider = try #require(cg.dataProvider)
    let data = try #require(provider.data)
    let length = CFDataGetLength(data)
    var bytes = [UInt8](repeating: 0, count: length)
    CFDataGetBytes(data, CFRange(location: 0, length: length), &bytes)
    return (bytes, cg.width, cg.height, cg.bytesPerRow)
}

/// Counts pixels differing by more than `tolerance` in any RGBA channel. Returns `nil` (rather
/// than a count) when the two renders aren't even the same shape, since a size mismatch means
/// the comparison itself is meaningless, not that every pixel differs.
func pixelDiffCount(
    _ a: (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int),
    _ b: (bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int),
    tolerance: UInt8 = 0
) -> Int? {
    guard a.width == b.width, a.height == b.height, a.bytesPerRow == b.bytesPerRow else { return nil }
    var diffCount = 0
    for y in 0..<a.height {
        let rowStart = y * a.bytesPerRow
        for x in 0..<a.width {
            let i = rowStart + x * 4
            let differs = (0..<4).contains { channel in
                let da = a.bytes[i + channel], db = b.bytes[i + channel]
                return da > db ? (da - db) > tolerance : (db - da) > tolerance
            }
            if differs { diffCount += 1 }
        }
    }
    return diffCount
}

struct RenderParityHarnessTests {

    /// A scene built specifically to exercise `blit()`'s vertical-flip compensation (see that
    /// function's own doc comment): a tank at an **off-centerline** heading. Heading 0/4/8/12
    /// (the cardinal directions `GameRenderViewTests.swift`'s crosshair test already covers)
    /// are close to rotationally symmetric enough that a flip bug can hide behind them; this
    /// deliberately uses heading 2 (`dir = 2 * kPif/8` -- a diagonal), which isn't.
    private func offCenterlineScene() -> GameState {
        var state = GameState()
        var player = PlayerState()
        player.used = true
        player.connected = true
        player.dead = false
        player.tank = Vec2f(x: 30, y: 30)
        player.dir = 2 * (kPif / 8.0)
        state.players = [player]
        state.localPlayer = 0
        return state
    }

    /// Self-test: two independently-constructed views, both on the default (CPU
    /// `CGContextTileRenderer`) path, rendering the exact same off-centerline scene, must
    /// produce byte-identical output. This doesn't test a Metal renderer -- none exists yet --
    /// it proves the harness itself (offscreen capture + diff) actually detects equality
    /// correctly before increments 4-5 trust it to detect a *real* Metal-vs-CPU parity bug.
    @Test @MainActor func parityHarnessSelfTestReportsZeroDiffForIdenticalCPURenders() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let viewA = GameRenderView(tilesImage: tiles, spritesImage: sprites)
        let viewB = GameRenderView(tilesImage: tiles, spritesImage: sprites)

        let state = offCenterlineScene()
        viewA.render(state)
        viewB.render(state)

        // A small rect around the tank (30, 30) in tile units, tile = 16pt -- large enough to
        // catch the flip-sensitive sprite art, far smaller than the full 4096x4096 map.
        let captureRect = NSRect(x: 440, y: 440, width: 160, height: 160)
        let renderA = try renderRGBA(viewA, rect: captureRect)
        let renderB = try renderRGBA(viewB, rect: captureRect)
        let diff = try #require(pixelDiffCount(renderA, renderB))
        #expect(diff == 0, "two identical CPU renders of the same state must be pixel-identical, found \(diff) differing pixels")
    }

    /// Negative control: confirms the harness actually notices a *real* difference, not just
    /// that it always reports zero. A tank at a different position must not diff to zero.
    @Test @MainActor func parityHarnessSelfTestDetectsARealDifference() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let viewA = GameRenderView(tilesImage: tiles, spritesImage: sprites)
        let viewB = GameRenderView(tilesImage: tiles, spritesImage: sprites)

        var stateA = offCenterlineScene()
        var stateB = stateA
        stateA.players[0].tank = Vec2f(x: 30, y: 30)
        stateB.players[0].tank = Vec2f(x: 32, y: 30)
        viewA.render(stateA)
        viewB.render(stateB)

        // Wide enough to contain the tank at both positions.
        let captureRect = NSRect(x: 440, y: 440, width: 200, height: 160)
        let renderA = try renderRGBA(viewA, rect: captureRect)
        let renderB = try renderRGBA(viewB, rect: captureRect)
        let diff = try #require(pixelDiffCount(renderA, renderB))
        #expect(diff > 0, "a tank drawn at two different positions must not be pixel-identical")
    }
}
