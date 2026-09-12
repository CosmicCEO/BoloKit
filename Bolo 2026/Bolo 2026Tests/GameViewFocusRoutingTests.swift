//
//  GameViewFocusRoutingTests.swift
//  Bolo 2026Tests
//
//  D157 item 3: live testing (Jerod, 2026-09-12) found arrow-key map scrolling asymmetric --
//  Up worked, Right "indexed some grid/list" instead of scrolling, Left/Down were complete
//  no-ops. `GameRenderView.applyKeyChange`/`scroll(dx:dy:)`'s own request math was already
//  confirmed code-symmetric (D157's own row), so this hosts the REAL `GameView` SwiftUI
//  hierarchy (not a bare `GameRenderView`) in a live `NSWindow` and sends real `NSEvent`s
//  through `NSWindow.sendEvent`, since that's the only way to see what AppKit's scroll
//  machinery actually does once SwiftUI's `safeAreaInset` HUD panels are in the picture --
//  needs no Accessibility/Screen Recording permission, since `sendEvent` is a same-process
//  AppKit API call, not synthetic-event injection into another process.
//
//  Root cause confirmed by this test's own instrumented run (temporarily printed
//  `contentInsets`/`documentVisibleRect` inside `scroll(dx:dy:)`, removed before commit):
//  `GameView`'s HUD `safeAreaInset`s (top bar, leading `BuilderToolStrip`, trailing
//  `ResourceGaugesPanel`/`PlayerStatusGrid`) make the enclosing `NSScrollView`'s
//  `contentInsets` asymmetric (measured live: top 48 / left 56 / right 228 / bottom 0). The old
//  `scroll(dx:dy:)` asked `NSClipView.scrollToVisible(_:)` to reveal a full-`bounds`-sized rect
//  offset by a fixed 64pt nudge -- that method's "minimum move to reveal this rect" semantics
//  are measured against the *unobscured* region (`bounds` minus `contentInsets`), so the actual
//  distance moved came out clipped by whichever inset sat on the far side of each direction:
//  Down landed at requested-minus-top-inset (2000 -> 1952, not 2000 -> 2064), Right at
//  requested-minus-left-inset (2064 -> 2008, not 2064), Left returned `false` and moved nothing.
//  Up happened to land exactly on the requested value only because nothing sits below the
//  window's own bottom edge to clip against. Not a focus-theft bug at all -- `GameRenderView`
//  held first responder for the entire run below, confirmed via `window.firstResponder`.
//
//  Fix: `scroll(dx:dy:)` now sets the clip view's origin directly
//  (`NSClipView.scroll(to:)`/`constrainBoundsRect`) instead of asking it to reveal a rect --
//  no inset-dependent reveal heuristic in the loop at all.
//
//  Not yet accounted for: Jerod's exact live phrasing that Right "indexes some grid/list."
//  This test's window never truly becomes key (background test process, not the frontmost
//  app), so first responder here is force-claimed rather than earned the way a live user
//  session earns it -- this reproduces and fixes the scroll-math bug conclusively, but does not
//  rule out a second, focus-related issue on top of it. Flagged for one more live check by
//  Jerod after this fix lands, not claimed as fully closed.

import AppKit
import SwiftUI
import Testing
import BoloKit

@testable import Bolo_2026

@MainActor
struct GameViewFocusRoutingTests {

    private func findRenderView(_ view: NSView) -> GameRenderView? {
        if let render = view as? GameRenderView { return render }
        for sub in view.subviews {
            if let found = findRenderView(sub) { return found }
        }
        return nil
    }

    @Test func arrowKeysScrollTheMapBySymmetric64PointsInEachDirection() throws {
        let hosting = NSHostingView(rootView: GameView(initialState: AppRootView.demoState, onQuitToMenu: {}))
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 900, height: 700),
            styleMask: [.titled, .resizable],
            backing: .buffered,
            defer: false
        )
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
        window.contentView = hosting
        window.makeKeyAndOrderFront(nil)

        // Let the runloop settle: GameRenderView.viewDidMoveToWindow defers its own
        // makeFirstResponder(self) by one turn (GameRenderView.swift:252-259), and SwiftUI's own
        // layout for the hosted hierarchy needs at least one pass too.
        RunLoop.main.run(until: Date().addingTimeInterval(0.5))

        let renderView = try #require(findRenderView(hosting), "GameRenderView not found in hosted hierarchy")
        let scrollView = try #require(renderView.enclosingScrollView, "GameRenderView has no enclosing NSScrollView")

        // A background test process's window never truly goes key the way a live app's does
        // (GameRenderView.swift:245-251's own documented race), so force the claim explicitly
        // here rather than trust the deferred async one -- this isolates "given GameRenderView
        // as first responder, does the scroll math work for all 4 keys" from "did this test
        // harness's window become key at all" (a separate, harness-only concern, not this bug).
        #expect(window.makeFirstResponder(renderView))

        // Seed well away from the document edges (and away from (0,0)) so a real scroll in any
        // of the 4 directions is observable and not masked by edge-clamping.
        scrollView.contentView.scroll(to: NSPoint(x: 2000, y: 2000))
        scrollView.reflectScrolledClipView(scrollView.contentView)

        func origin() -> NSPoint { scrollView.contentView.bounds.origin }

        func sendArrow(_ keyCode: UInt16) {
            let event = NSEvent.keyEvent(
                with: .keyDown, location: .zero, modifierFlags: [], timestamp: 0,
                windowNumber: window.windowNumber, context: nil, characters: "",
                charactersIgnoringModifiers: "", isARepeat: false, keyCode: keyCode
            )!
            window.sendEvent(event)
        }

        let start = origin()
        #expect(start == NSPoint(x: 2000, y: 2000))

        sendArrow(126)  // Up
        #expect(origin() == NSPoint(x: 2000, y: 1936))

        sendArrow(125)  // Down -- back to the seeded y
        #expect(origin() == NSPoint(x: 2000, y: 2000))

        sendArrow(123)  // Left
        #expect(origin() == NSPoint(x: 1936, y: 2000))

        sendArrow(124)  // Right -- back to the seeded x
        #expect(origin() == NSPoint(x: 2000, y: 2000))
    }
}
