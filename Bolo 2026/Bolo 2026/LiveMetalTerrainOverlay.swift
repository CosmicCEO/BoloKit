//
//  LiveMetalTerrainOverlay.swift
//  Bolo 2026
//
//  v1.6.0 (#25) increment 6: the real on-screen performance path. `MetalTileRenderer`
//  (increments 4-5) proved the Metal terrain/sprite pipeline pixel-correct, but it still
//  round-trips through an offscreen `MTLTexture` -> `CIImage` -> `CGImage` -> `CGContext.draw`
//  every frame to stay a drop-in `TileRenderer` -- that round trip is not faster than the CPU
//  path it replaces, only provably *correct*. This type is the actual performance swap: a
//  `CAMetalLayer`-backed `MTKView` added as a **plain subview of the enclosing `NSScrollView`
//  itself** (not `NSScrollView.addFloatingSubview(_:for:)` -- that API floats a view along only
//  one scroll axis at a time, e.g. a ruler that scrolls vertically with content but stays fixed
//  horizontally; there's no "fixed on both axes" case in its `NSEventGestureAxis` parameter).
//  The scroll view's own frame never moves during scrolling -- only its clip/document view's
//  `bounds.origin` does -- so an ordinary subview of the scroll view already stays pinned to
//  the viewport with no special floating API needed. Renders terrain tiles directly into the
//  live drawable, bypassing `CGContext`/`draw(_:)` entirely for that part of the frame.
//
//  Scope: **terrain only.** `#25`'s own text ("Live draw misses a 16.67ms frame between
//  ~7.9k-11.9k tiles") and `GameRenderView.tileCountBudget`'s doc comment both identify *tile
//  count* -- which scales with zoom-out level -- as the actual cost driver. Sprite/shell/
//  explosion/builder count stays small and roughly constant regardless of zoom, so it was
//  never the bottleneck; those, plus labels/crosshair/selector/dashed builder-task lines, stay
//  on the existing CGContext path in `GameRenderView.draw(_:)`.
//
//  Z-order and compositing -- two things had to change together, not just one:
//  1. This `MTKView` is inserted *behind* the scroll view's clip view
//     (`GameRenderView.installLiveMetalOverlayIfNeeded`: `positioned: .below, relativeTo:
//     scrollView.contentView`) -- a plain `addSubview` appends to the end of the subview list,
//     which AppKit draws last (on top), the wrong side of the document view that now draws the
//     sprites this needs to stay under.
//  2. `GameRenderView.isOpaque` is now conditional (`liveMetalOverlay == nil`) -- its prior
//     unconditional `true` told AppKit this view always fully covers its own bounds, which
//     licenses skipping compositing anything positioned behind it. Positioning this view behind
//     the document view alone would have been silently ineffective without also telling AppKit
//     the document view can, in this mode, actually leave pixels transparent for it.
//
//  Off by default (`GameRenderView.liveMetalTerrainRenderer`, `nil` unless explicitly
//  supplied) -- needs interactive visual verification (pan/zoom/scroll feel, whether the
//  compositing described above actually looks right end to end) that a headless session cannot
//  perform itself, unlike increments 1-5's fully offscreen-testable correctness work.

import AppKit
import Metal
import MetalKit
import BoloKit

@MainActor
final class LiveMetalTerrainOverlay: NSObject, MTKViewDelegate {
    let mtkView: MTKView
    private let renderer: MetalTileRenderer
    private weak var gameRenderView: GameRenderView?

    init?(renderer: MetalTileRenderer, gameRenderView: GameRenderView) {
        let view = MTKView(frame: .zero, device: renderer.device)
        view.colorPixelFormat = .bgra8Unorm
        view.framebufferOnly = true
        // Tick-driven redraw would need every scroll/zoom/pan input path to separately notify
        // this view; a continuous draw loop tracks live camera movement (scroll/zoom) for
        // free and is the conventional choice for this kind of always-visible viewport overlay.
        view.isPaused = false
        view.enableSetNeedsDisplay = false
        self.mtkView = view
        self.renderer = renderer
        self.gameRenderView = gameRenderView
        super.init()
        view.delegate = self
    }

    /// Halts the continuous draw loop and drops the delegate reference. Must be called before
    /// this overlay's `mtkView` is torn down (`GameRenderView.viewWillMove(toWindow:)`, when
    /// the new window is `nil`) -- found necessary the hard way: a continuous (`isPaused =
    /// false`) `MTKView` keeps its internal display-link timer firing `draw(in:)` even after
    /// its host window closes unless explicitly paused, and that callback then dereferences
    /// state (`gameRenderView`, `renderer`) that's mid-teardown, a `SIGSEGV` in a unit test
    /// (`LiveMetalTerrainOverlayTests.swift`) closing its test window right after installing
    /// this overlay -- not hypothetical, reproduced and root-caused via the crash's own
    /// `.ips` report before this fix.
    func stop() {
        mtkView.isPaused = true
        mtkView.delegate = nil
    }

    /// `nonisolated` + `MainActor.assumeIsolated` rather than a plain (implicitly `@MainActor`,
    /// this project builds with `-default-isolation=MainActor`) method: `MTKViewDelegate`'s
    /// methods are a plain synchronous ObjC callback invoked directly by `MTKView`'s internal
    /// display-link machinery, not `async`. A `@MainActor`-isolated implementation of a
    /// synchronous protocol requirement gets a generated thunk that hops onto the main actor's
    /// executor via the Swift Concurrency job-scheduling machinery for *every* call -- found
    /// the hard way (a `SIGSEGV` inside `swift_job_runImpl`/`objc_release`, reproduced and
    /// root-caused via a crash report, not hypothetical) that this hop is fragile/crash-prone
    /// for a display-link-driven callback under this specific combination of a continuous
    /// (`isPaused = false`) `MTKView`, Swift 6 strict concurrency, and this project's
    /// project-wide default actor isolation. `MTKView` is documented to already invoke its
    /// delegate on the main thread when using its own internal timer (this configuration, not
    /// `enableSetNeedsDisplay`) -- `assumeIsolated` asserts that synchronously instead of
    /// letting the compiler insert an async hop, which is both correct (it's really already on
    /// the main thread) and what actually fixed the crash.
    nonisolated func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    /// See `mtkView(_:drawableSizeWillChange:)`'s doc comment -- same `nonisolated` +
    /// `assumeIsolated` reasoning, and this is the method that was actually observed crashing.
    nonisolated func draw(in view: MTKView) {
        MainActor.assumeIsolated {
            guard let gameRenderView, let drawable = view.currentDrawable,
                let commandBuffer = renderer.makeCommandBuffer()
            else { return }
            renderer.renderLiveTerrain(
                tileGrid: gameRenderView.tileGrid, visibleRect: gameRenderView.visibleRect,
                into: drawable.texture, commandBuffer: commandBuffer, tilesImage: gameRenderView.tilesImage
            )
            commandBuffer.present(drawable)
            commandBuffer.commit()
        }
    }
}
