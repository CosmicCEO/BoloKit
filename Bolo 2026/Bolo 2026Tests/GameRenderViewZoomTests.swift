//
//  GameRenderViewZoomTests.swift
//  Bolo 2026Tests
//
//  Milestone D.0 (D160) -- extends the 21/21 `xcodebuild` UI-hosting suite per D160's own
//  ruling, rather than just re-running it. Covers:
//  1. The live SwiftUI-magnification-ownership question D160 item 1 required verifying
//     first, before any zoom code was built on top of it (kept as permanent regression
//     coverage -- a future SwiftUI/AppKit change silently starting to fight `magnification`
//     the way it fought `contentInsets` in D157 would be exactly this kind of foundational,
//     easy-to-invert claim worth re-checking automatically, same discipline D70/D81 already
//     established for this project's other empirically-verified claims).
//  2. A magnification-aware variant of `GameViewFocusRoutingTests`'s own
//     `arrowKeysScrollTheMapBySymmetric64PointsInEachDirection`, re-run at 2.0x and 0.5x to
//     confirm the new `÷ scrollView.magnification` fix in `scroll(dx:dy:)` holds live, not
//     just in the pre-brief's standalone `swiftc` probe.
//  3. Edge-clamping at zoom -- the pre-brief's own §3 explicitly flagged this as NOT covered
//     by that probe (it never pushed a scroll far enough to hit a boundary).
//  4. The Zoom In/Out button actions (bounds guards at both ends, recenter behavior).
//  5. The dynamic minimum-magnification floor's pure formula, plus its live behavior on a
//     real window resize (index/appearance kept in sync per this session's own design note
//     in `GameRenderView.applyEffectiveMagnification`'s doc comment).

import AppKit
import SwiftUI
import Testing
import BoloKit

@testable import Bolo_2026

@MainActor
struct GameRenderViewZoomTests {

    private func findRenderView(_ view: NSView) -> GameRenderView? {
        if let render = view as? GameRenderView { return render }
        for sub in view.subviews {
            if let found = findRenderView(sub) { return found }
        }
        return nil
    }

    /// Hosts the real `GameView` hierarchy in a live `NSWindow`, same pattern
    /// `GameViewFocusRoutingTests` already established, and returns the render view + its
    /// enclosing scroll view once first responder/layout have settled.
    private func hostGameView(size: NSSize = NSSize(width: 900, height: 700)) -> (
        window: NSWindow, renderView: GameRenderView, scrollView: NSScrollView
    ) {
        let hosting = NSHostingView(rootView: GameView(initialState: AppRootView.demoState, onQuitToMenu: {}))
        let window = NSWindow(
            contentRect: NSRect(origin: .zero, size: size),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))
        let renderView = findRenderView(hosting)!
        let scrollView = renderView.enclosingScrollView!
        _ = window.makeFirstResponder(renderView)
        return (window, renderView, scrollView)
    }

    // MARK: - 1. SwiftUI-magnification-ownership (D160 item 1's live-verify-first requirement)

    @Test func magnificationSurvivesWindowResizeAndAPureLayoutPass() throws {
        let (window, _, scrollView) = hostGameView()
        scrollView.magnification = 2.0
        #expect(scrollView.magnification == 2.0)

        window.setContentSize(NSSize(width: 1000, height: 800))
        window.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        #expect(scrollView.magnification == 2.0, "SwiftUI reset magnification across a real resize")

        window.contentView?.needsLayout = true
        window.contentView?.layoutSubtreeIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))
        #expect(scrollView.magnification == 2.0, "SwiftUI reset magnification across a layout-only pass")
    }

    // MARK: - 2. Magnification-aware scroll symmetry (extends GameViewFocusRoutingTests)

    private func sendArrow(_ keyCode: UInt16, to window: NSWindow) {
        let event = NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
            windowNumber: window.windowNumber, context: nil, characters: "",
            charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
        )!
        window.sendEvent(event)
    }

    /// `hostSize` matters here, not just cosmetically: the default 900x700 host window's
    /// own dynamic floor (`T = 9,000`, see `GameRenderView.tileCountBudget`) already sits
    /// at ~0.523x -- ABOVE the 0.5x this test wants to set directly. Setting
    /// `scrollView.magnification` below the live `minMagnification` silently clamps up to
    /// the floor instead of landing on the requested exact value (a real, correct AppKit
    /// behavior, caught by this test's own first draft asserting an exact 128-unit step and
    /// getting a ~122.4-unit one instead). 640x480 keeps the floor pinned at exactly 0.5x,
    /// matching the bounds-guard tests' own fix for the identical root cause.
    private func assertSymmetricArrowScroll(
        atMagnification magnification: CGFloat, expectedStep: CGFloat, hostSize: NSSize
    ) throws {
        let (window, _, scrollView) = hostGameView(size: hostSize)
        scrollView.magnification = magnification

        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 2000, y: 2000))
        scrollView.reflectScrolledClipView(clipView)
        func origin() -> NSPoint { clipView.bounds.origin }

        // Small tolerance throughout -- `NSScrollView.magnification`'s own coordinate
        // transform introduces sub-ULP floating-point noise on round-trip even at "nice"
        // scale factors (observed: 1999.9999999999843 instead of an exact 2000.0).
        func assertNear(_ point: NSPoint, _ expected: NSPoint) {
            #expect(abs(point.x - expected.x) < 0.01)
            #expect(abs(point.y - expected.y) < 0.01)
        }

        assertNear(origin(), NSPoint(x: 2000, y: 2000))

        sendArrow(126, to: window)  // Up
        assertNear(origin(), NSPoint(x: 2000, y: 2000 - expectedStep))

        sendArrow(125, to: window)  // Down -- back to seeded y
        assertNear(origin(), NSPoint(x: 2000, y: 2000))

        sendArrow(123, to: window)  // Left
        assertNear(origin(), NSPoint(x: 2000 - expectedStep, y: 2000))

        sendArrow(124, to: window)  // Right -- back to seeded x
        assertNear(origin(), NSPoint(x: 2000, y: 2000))
    }

    /// At 2.0x, the fixed 64pt request divides down to a 32-unit document-space move --
    /// half the no-zoom distance, confirming the fix (the un-fixed code would have moved a
    /// full 64 units regardless of magnification). The default 900x700 host size's floor
    /// (~0.523x) is well below 2.0x, so it doesn't interfere here.
    @Test func arrowKeysScrollBySymmetric32DocumentUnitsAtDoubleMagnification() throws {
        try assertSymmetricArrowScroll(
            atMagnification: 2.0, expectedStep: 32, hostSize: NSSize(width: 900, height: 700)
        )
    }

    /// At 0.5x, the fixed 64pt request divides up to a 128-unit document-space move --
    /// double the no-zoom distance, the other direction of the same fix.
    @Test func arrowKeysScrollBySymmetric128DocumentUnitsAtHalfMagnification() throws {
        try assertSymmetricArrowScroll(
            atMagnification: 0.5, expectedStep: 128, hostSize: NSSize(width: 640, height: 480)
        )
    }

    // MARK: - 3. Edge-clamping at zoom (pre-brief §3's explicitly-flagged gap)

    /// Drives hard toward each corner of the document (well past however many steps could
    /// possibly be needed to cross the full 4096-unit map at this magnification's per-step
    /// distance) and confirms one further push in the same direction doesn't move the
    /// viewport at all -- an *idempotence* check at whatever the real clamp boundary is,
    /// deliberately not a re-derivation of `constrainBoundsRect`'s own exact formula (which,
    /// found live while writing this test, is insets-aware and does NOT simply clamp to
    /// `documentSize - visibleSize` the way a naive first draft of this test assumed --
    /// re-deriving that formula independently here would just be duplicating AppKit's own
    /// logic rather than testing this code's use of it).
    ///
    /// Top-left corner = Left + Up (this view's `isFlipped == true`/D66 top-left-origin
    /// convention means Up, not Down, is the direction that approaches y == 0); bottom-right
    /// corner = Right + Down. Getting this backwards was a real bug in this test's own first
    /// draft, not a production bug -- caught because Down from y == 0 legitimately moved
    /// (away from the top edge, into free space), which a same-session `swift test` run
    /// surfaced immediately as a wrong-value failure, not a clamp failure.
    /// `hostSize` for the same reason `assertSymmetricArrowScroll` needs it: setting
    /// magnification below the live floor silently clamps upward instead. Not otherwise
    /// load-bearing for this test's own idempotence logic (which never hardcodes an
    /// expected numeric boundary), but keeping the *requested* magnification exact avoids
    /// conflating "the floor kicked in" with "the clamp boundary logic is broken" if this
    /// test ever fails again.
    private func assertEdgeClamp(atMagnification magnification: CGFloat, hostSize: NSSize) throws {
        let (window, _, scrollView) = hostGameView(size: hostSize)
        scrollView.magnification = magnification
        let clipView = scrollView.contentView

        func drive(_ keyCode: UInt16, times: Int) {
            for _ in 0..<times { sendArrow(keyCode, to: window) }
        }

        // Small tolerance -- `NSScrollView.magnification`'s coordinate transform introduces
        // sub-ULP floating-point noise on repeated round-trips (same finding as
        // `assertSymmetricArrowScroll`), which compounds slightly over ~150 repeated moves.
        func nearlyEqual(_ a: NSPoint, _ b: NSPoint) -> Bool {
            abs(a.x - b.x) < 0.01 && abs(a.y - b.y) < 0.01
        }

        clipView.scroll(to: NSPoint(x: 2000, y: 2000))
        scrollView.reflectScrolledClipView(clipView)
        drive(123, times: 150)  // Left
        drive(126, times: 150)  // Up
        let minCorner = clipView.bounds.origin
        sendArrow(123, to: window)
        sendArrow(126, to: window)
        #expect(
            nearlyEqual(clipView.bounds.origin, minCorner),
            "scrolling further past the top-left clamp boundary should not move the viewport"
        )

        clipView.scroll(to: NSPoint(x: 2000, y: 2000))
        scrollView.reflectScrolledClipView(clipView)
        drive(124, times: 150)  // Right
        drive(125, times: 150)  // Down
        let maxCorner = clipView.bounds.origin
        sendArrow(124, to: window)
        sendArrow(125, to: window)
        #expect(
            nearlyEqual(clipView.bounds.origin, maxCorner),
            "scrolling further past the bottom-right clamp boundary should not move the viewport"
        )

        // Sanity: a real, non-degenerate clamp range exists between the two corners.
        #expect(minCorner.x < maxCorner.x)
        #expect(minCorner.y < maxCorner.y)
    }

    @Test func scrollClampsAtMapEdgesWhenZoomedIn() throws {
        try assertEdgeClamp(atMagnification: 2.0, hostSize: NSSize(width: 900, height: 700))
    }

    @Test func scrollClampsAtMapEdgesWhenZoomedOut() throws {
        try assertEdgeClamp(atMagnification: 0.5, hostSize: NSSize(width: 640, height: 480))
    }

    // MARK: - 4. Zoom In/Out button actions

    @Test func zoomInStepsThroughAllFiveDiscreteLevelsThenNoOpsAtTheTop() throws {
        let (_, renderView, scrollView) = hostGameView()
        #expect(renderView.currentZoomLevel == 1.0)  // DEFAULT_ZOOM index 2

        renderView.zoomIn()
        #expect(renderView.currentZoomLevel == 1.5)
        #expect(scrollView.magnification == 1.5)

        renderView.zoomIn()
        #expect(renderView.currentZoomLevel == 2.0)

        renderView.zoomIn()  // already at MAX_ZOOM -- no-op, matches `if (zoomLevel < MAX_ZOOM)`
        #expect(renderView.currentZoomLevel == 2.0)
        #expect(scrollView.magnification == 2.0)
    }

    @Test func zoomOutStepsThroughAllFiveDiscreteLevelsThenNoOpsAtTheBottom() throws {
        // A small host window, deliberately: at the default 900x700 host size, this
        // session's own live benchmark data means the dynamic floor (`T = 9,000`) already
        // sits at ~0.523x (900*700 tiles at 0.5x already exceeds budget) -- a real, correct
        // enforcement this test isn't trying to exercise. 640x480 keeps the floor pinned at
        // its outer-bound 0.5x so this test only exercises the discrete-level bounds guard.
        let (_, renderView, scrollView) = hostGameView(size: NSSize(width: 640, height: 480))

        renderView.zoomOut()
        #expect(renderView.currentZoomLevel == 0.75)

        renderView.zoomOut()
        #expect(renderView.currentZoomLevel == 0.5)

        renderView.zoomOut()  // already at index 0 -- no-op, matches `if (zoomLevel > 0)`
        #expect(renderView.currentZoomLevel == 0.5)
        #expect(scrollView.magnification == 0.5)
    }

    @Test func zoomInRecentersByAQuarterOfTheVisibleRectPerTheReferencesOwnFormula() throws {
        let (_, renderView, scrollView) = hostGameView()
        let clipView = scrollView.contentView
        clipView.scroll(to: NSPoint(x: 1000, y: 1000))
        scrollView.reflectScrolledClipView(clipView)
        let visRect = clipView.bounds

        renderView.zoomIn()

        // Ported from `zoomIn:` (`GSXBoloController.m:1495`): new origin = old visRect.origin
        // + 0.25 * old visRect.size, then clamped -- computed against the ACTUAL pre-zoom
        // visRect (not assumed (1000,1000)) since NSScrollView-vs-manual-frame-trick geometry
        // isn't otherwise being asserted here.
        let expected = NSPoint(x: visRect.origin.x + 0.25 * visRect.width, y: visRect.origin.y + 0.25 * visRect.height)
        let constrained = clipView.constrainBoundsRect(NSRect(origin: expected, size: clipView.bounds.size))
        // Small tolerance, not exact equality -- this test recomputes the expected value via
        // its own independent floating-point arithmetic (a legitimate cross-check, not
        // sharing code with the production path), which can differ from the production
        // path's own arithmetic by a couple ULPs (observed: 1175.0 vs 1175.0000000000002).
        #expect(abs(clipView.bounds.origin.x - constrained.origin.x) < 0.001)
        #expect(abs(clipView.bounds.origin.y - constrained.origin.y) < 0.001)
    }

    // MARK: - 5. Dynamic minimum-magnification floor

    @Test func minimumMagnificationFormulaMatchesTheDerivedFloorAndClampsToTheOuterBounds() {
        // At the chosen T = 9,000 tile budget: a genuinely small viewport (640x480, this
        // app's own `GameView.frame(minWidth:480, minHeight:360)` neighborhood) needs no
        // floor above 0.5x -- 640*480/(256*9000) = 0.1333, well under 1.
        #expect(GameRenderView.minimumMagnification(viewportWidth: 640, viewportHeight: 480, tileBudget: 9_000) == 0.5)

        // Disclosed, not a bug: a "normal-looking" 900x700 window is already past this
        // budget's floor-engaging threshold at 0.5x (900*700 tiles at 0.5x alone is ~9,844,
        // over T=9,000) -- confirms the floor is not a rare edge case reserved for huge
        // windows, it's live at ordinary sizes with this session's chosen T.
        let ordinaryFloor = GameRenderView.minimumMagnification(viewportWidth: 900, viewportHeight: 700, tileBudget: 9_000)
        #expect(ordinaryFloor > 0.5 && ordinaryFloor < 0.75)

        // A viewport where the raw formula lands cleanly inside [0.5, 2.0]:
        // sqrt(2000*2000 / (256*9000)) = sqrt(4_000_000 / 2_304_000) ~= 1.31762...
        let floor = GameRenderView.minimumMagnification(viewportWidth: 2000, viewportHeight: 2000, tileBudget: 9_000)
        #expect(abs(floor - 1.31762) < 0.001)

        // A huge viewport clamps to the outer bound (2.0), never exceeding it.
        #expect(GameRenderView.minimumMagnification(viewportWidth: 20_000, viewportHeight: 20_000, tileBudget: 9_000) == 2.0)

        // Degenerate inputs return the safe minimum rather than NaN/crashing.
        #expect(GameRenderView.minimumMagnification(viewportWidth: 0, viewportHeight: 700, tileBudget: 9_000) == 0.5)
        #expect(GameRenderView.minimumMagnification(viewportWidth: 900, viewportHeight: 700, tileBudget: 0) == 0.5)
    }

    /// Live behavior: resizing the hosting window to a size whose floor exceeds the
    /// currently-selected zoom level raises BOTH the actual on-screen magnification AND
    /// `zoomIndex` itself (via `applyEffectiveMagnification`'s resync, wired through the
    /// scroll view's `frameDidChangeNotification` observer) -- confirms the two never
    /// silently diverge, per this file's own design note.
    @Test func windowResizeRaisesBothMagnificationAndZoomIndexWhenTheFloorExceedsTheSelection() throws {
        // Start small (see the bounds-guard test above for why 640x480 keeps the floor
        // pinned at 0.5x) so the initial zoom-out to 0.5x isn't itself floor-blocked --
        // this test is about the RESIZE-triggered raise, not the starting descent.
        let (window, renderView, scrollView) = hostGameView(size: NSSize(width: 640, height: 480))
        renderView.zoomOut()
        renderView.zoomOut()
        #expect(renderView.currentZoomLevel == 0.5)

        // floor(2000, 2000, T=9000) ~= 1.318 -- the lowest discrete level at/above it is 1.5.
        window.setContentSize(NSSize(width: 2000, height: 2000))
        window.layoutIfNeeded()
        // Force a draw pass deterministically (production relies on `render(_:)` doing this
        // every tick, but nothing is actively ticking in this test) -- exercises the
        // `viewWillDraw()` self-heal path, not just the frame-changed-notification path.
        renderView.needsDisplay = true
        renderView.displayIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.3))

        #expect(renderView.currentZoomLevel == 1.5)
        #expect(scrollView.magnification == 1.5)
    }
}
