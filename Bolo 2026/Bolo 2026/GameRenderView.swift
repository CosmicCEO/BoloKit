//
//  GameRenderView.swift
//  Bolo 2026
//
//  Wave 7.2 -- the port's equivalent of GSBoloView.m's role (D60/D81). Renders a `GameState`
//  snapshot on demand; owns no clock of its own -- 7.3's tick loop calls `render(_:)` after
//  each `runTick()` (D82). Fog-of-war/seentiles are out of scope for v1 (D65): every tile is
//  drawn from `mapimage()` against the live `displayTileGrid`, unconditionally visible.
//
//  No C-style 255-y flip anywhere here: BoloKit's own `Vec2f`/`TerrainGrid` convention is
//  already +y-down (Vector.swift's `dir2vec` doc comment), matching D66's top-left sheet
//  origin with zero translation math -- `isFlipped = true` below is what makes that hold for
//  AppKit's own coordinate space too.
//
//  v1 draw-order scope (subset of GSBoloView.m's drawSprites, lines 286-439): terrain, the
//  local player's tank/builder/shells/explosions, and global (unattributed) explosions. Out
//  of scope, not a fidelity gap: other-player tank/name/builder sprites (D73 -- v1 is
//  single-process, there are never any other connected players) and the pause-label HUD
//  sprite (GSBoloView.m:411-419, Milestone C's concern). D152: the selector/crosshair are no
//  longer out of scope -- see drawSelector(_:)/drawCrosshair(_:) below.
//
//  Wave 7.3 (D88 §2) reopens this already-PARITY-passed file to add keyboard capture --
//  `acceptsFirstResponder`/`keyDown`/`keyUp`/`flagsChanged` directly on this view, mirroring
//  `GSBoloView.m`'s own architecture exactly (it is itself the first responder handling
//  `keyDown:`/`keyUp:`/`flagsChanged:`, `GSBoloView.m:465-505`), rather than inventing a new
//  capture mechanism. Key events translate through `BoloKit`'s `inputFlagsChange(forKeyCode:
//  isDown:)` (pure, testable independent of `NSEvent`) and are handed out via `onInputFlagsChange`/
//  `onLayMineKeyDown` closures -- `GameSession` (new this wave) is the only thing that sets them,
//  applying the change to its own owned `GameState` and calling `layMineOnKeyDown` directly, never
//  from inside a `runTick` call (that would be a nested `inout`-exclusivity violation -- see
//  `GameSession.swift`'s header). This view still owns no clock (D82 stands unchanged).

import AppKit
import BoloKit
import BoloNet
import os
import SwiftUI

private let tileSize = 16
private let mapPixelSize = 256 * tileSize

/// Converts a sheet image index to its 16x16 source rect. Same cell math as
/// `BoloGlyphsCore.cellRow`/`cellCol` (D66: top-left origin, `row = idx >> 4`, `col = idx & 0xF`)
/// -- re-derived here rather than imported because `BoloGlyphsCore` is a build-time-only
/// dependency (D73), not linked into this target.
private func sheetSrcRect(forIndex index: Int32) -> CGRect {
    let row = Int(index) >> 4
    let col = Int(index) & 0xF
    return CGRect(x: col * tileSize, y: row * tileSize, width: tileSize, height: tileSize)
}

/// v1.6.0 (#25) extraction seam: the tile/sprite draw pass `GameRenderView.draw(_:)` delegates
/// to, so a Metal-backed implementation can be swapped in behind this same call without
/// touching `render(_:fogState:)`'s public signature or any `GameSession.swift` call site.
/// `drawLabel`/`drawSelector`/`drawCrosshair` stay outside this
/// seam, called directly by `GameRenderView.draw(_:)` as a thin CGContext overlay -- disclosed
/// scope reduction, not a gap (text atlases/dashed-line shaders are out of scope for #25).
public protocol TileRenderer: AnyObject {
    func draw(_ view: GameRenderView, ctx: CGContext, dirtyRect: NSRect)
}

/// The existing CPU `CGContext` blit path, unchanged, just reached through the `TileRenderer`
/// seam instead of called directly from `draw(_:)`. Default renderer; stays in-tree as the
/// fallback/parity comparator once a Metal renderer lands.
public final class CGContextTileRenderer: TileRenderer {
    public init() {}
    public func draw(_ view: GameRenderView, ctx: CGContext, dirtyRect: NSRect) {
        view.drawTerrain(ctx, dirtyRect: dirtyRect)
        view.drawSprites(ctx)
    }
}

public final class GameRenderView: NSView {
    private var state = GameState()
    var tileGrid = TileGrid()
    let tilesImage: CGImage
    let spritesImage: CGImage

    /// B.9's smoothing half (D114) -- one `RemotePositionSmoother` per remote player index,
    /// keyed by index into `state.players` (stable across ticks). View-layer only; see
    /// `RemotePositionSmoother.swift`'s own header for why. Builder/shell positions are
    /// deliberately NOT smoothed this pass (disclosed scope, not an oversight).
    private var remoteTankSmoothers: [Int: RemotePositionSmoother] = [:]

    /// Phase 2 cleanup: extends B.9's smoothing to remote builders too -- `PlayerState.builder`
    /// is one stable `Vec2f` per player index, same shape as `tank`, so the identical per-index
    /// `RemotePositionSmoother` treatment applies directly. Shells (`[Shell]`, unstable indices
    /// across ticks as shots fire/expire) are NOT smoothed here -- disclosed remaining gap, not
    /// an oversight; keying a smoother by array index would mismatch a stale smoother against a
    /// newly-fired shell at the same slot.
    private var remoteBuilderSmoothers: [Int: RemotePositionSmoother] = [:]

    /// Set by `GameSession` -- applies a key transition's `InputFlags` change to the session's
    /// own owned `GameState`. Never called from inside a `runTick`/tick-timer call (§2 above).
    public var onInputFlagsChange: ((KeyInputChange) -> Void)?
    /// Set by `GameSession` -- fires once per LMINE key-down edge (not key-up, not `isARepeat`),
    /// mirroring `keyevent()`'s one-shot immediate mine plant (D88 §3).
    public var onLayMineKeyDown: (() -> Void)?
    /// **D137:** set by `GameSession` -- fires once per left-click on the map, carrying the
    /// currently-selected builder tool and the clicked tile. Mirrors `buildercommand()`
    /// (`client.c:6533-6538`): unlimited range, no distance check performed here or in
    /// `BoloKit.queueBuilderCommand`.
    public var onBuilderCommand: ((BuilderCommandKind, BoloKit.Pointi) -> Void)?
    /// **D137:** the builder tool digit keys 1-5 (`builderTool(forKeyCode:)`) select, not
    /// rebindable -- matches `GSXBoloController.m`'s own hardcoded chain (see
    /// `InputKeymap.swift`'s doc comment on `builderTool(forKeyCode:)`). Defaults to `.tree`,
    /// matching the reference's own `builderToolInteger` default of 0.
    public private(set) var selectedBuilderTool: BuilderCommandKind = .tree

    /// **D148(B):** lets the always-visible build-tool strip (`GameView.swift`) drive the same
    /// selection `keyDown`'s digit-key branch sets, without introducing a second source of truth.
    /// Deliberately does NOT reclaim first responder itself -- the caller (a SwiftUI button
    /// action) does that explicitly right after, matching this view's own `mouseDown` precedent
    /// (`window?.makeFirstResponder(self)`) rather than hiding a responder change inside a setter.
    public func selectBuilderTool(_ tool: BuilderCommandKind) {
        selectedBuilderTool = tool
    }

    /// D128 backlog C.1 -- the live, rebindable keymap. Defaults to whatever was last persisted
    /// (`PreferencesView`'s rebind UI writes through `KeyBindingsStore`); `GameSession` re-pushes
    /// a fresh value here whenever the settings UI saves a change (see `GameSession.swift`).
    public var bindings: KeyBindings = KeyBindingsStore.load()

    /// v1.6.0 (#25): the tile/sprite draw pass, set at init rather than read from
    /// `UserDefaults` so tests can instantiate either renderer directly. Defaults to the
    /// existing CPU path -- unchanged behavior for every existing call site.
    var renderer: TileRenderer

    /// v1.6.0 (#25) increment 6: when non-nil, terrain moves off this property's own
    /// `renderer` entirely onto `liveMetalOverlay`'s floating `MTKView` once the view is in a
    /// window (`installLiveMetalOverlayIfNeeded`) -- the actual on-screen performance path,
    /// bypassing `CGContext`/`draw(_:)` for the part of rendering that scales with zoom (tile
    /// count; sprites/builders/labels stay on the CGContext path unchanged, since they're
    /// small and roughly zoom-independent -- see `LiveMetalTerrainOverlay`'s own header).
    /// `nil` by default: every existing call site's behavior is unchanged unless this is
    /// explicitly supplied.
    let liveMetalTerrainRenderer: MetalTileRenderer?
    private var liveMetalOverlay: LiveMetalTerrainOverlay?
    private var liveMetalOverlayObserversInstalled = false

    public init(
        tilesImage: CGImage, spritesImage: CGImage, renderer: TileRenderer = CGContextTileRenderer(),
        liveMetalTerrainRenderer: MetalTileRenderer? = nil
    ) {
        self.tilesImage = tilesImage
        self.spritesImage = spritesImage
        self.renderer = renderer
        self.liveMetalTerrainRenderer = liveMetalTerrainRenderer
        super.init(frame: NSRect(x: 0, y: 0, width: mapPixelSize, height: mapPixelSize))
        setAccessibilityElement(true)
        setAccessibilityRole(.image)
        setAccessibilityLabel(HUDAccessibility.battleMap)
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    // MARK: - Zoom (Milestone D.0, D160)

    /// Ported verbatim from `kZoomLevels`/`DEFAULT_ZOOM` (`GSXBoloController.m:136-144`) --
    /// 5 discrete magnification steps, default index 2 (1.0x). D18: float literals copied
    /// exactly from the reference, not re-derived (all 5 are exact in binary floating point
    /// anyway, but the discipline is "copy," not "trust that it's exact").
    static let zoomLevels: [CGFloat] = [0.5, 0.75, 1.0, 1.5, 2.0]
    private static let defaultZoomIndex = 2

    private var zoomIndex = GameRenderView.defaultZoomIndex

    /// **D160 item 2:** the tile-count budget behind the dynamic minimum-magnification
    /// floor below (`minimumMagnification`). Refined this coding session from the D.0
    /// pre-brief's disclosed `T = 20,000` placeholder via a real live on-screen
    /// `displayIfNeeded()` benchmark hosting the actual `GameView` hierarchy in an `NSWindow`
    /// -- NOT the offscreen `bitmapImageRepForCachingDisplay`/`cacheDisplay` path this
    /// session tried first and discarded (measured ~15-20x slower and not representative of
    /// live on-screen compositing cost; see this wave's completion report in
    /// `AGENT_NOTES.md` for both data sets). The live benchmark's median draw time crosses
    /// this project's own 60Hz display-refresh frame budget (16.67ms -- distinct from
    /// D82/D83's separate 20ms *simulation-tick* budget, since `draw(_:)` runs on AppKit's
    /// own display-refresh cycle, not the tick loop) between ~7,900 and ~11,900 tiles.
    /// `T = 9,000` sits just past that measured crossing with a small safety margin --
    /// a real, disclosed, meaningful *downward* revision from the placeholder, not a
    /// re-confirmation of the guess. (For reference: the placeholder's basis, D81's
    /// AppKit-vs-Canvas crossover at 32,400 tiles, remains correct on its own terms --
    /// it answers a different question, "where does Canvas start winning," not "where does
    /// AppKit alone start missing a frame budget," which is what this cap actually guards.)
    static let tileCountBudget = 9_000

    /// v1.6.0 (#25) increment 7: `tileCountBudget` above calibrates the *CPU* `CGContext`
    /// draw-cost ladder -- but once `liveMetalOverlay` is live, `draw(_:)` skips the
    /// expensive tile pass entirely (terrain moves to the Metal overlay's own draw loop;
    /// this view's CGContext path only draws sprites, "small, roughly zoom-independent" per
    /// that call site's own comment). Applying the CPU-calibrated floor to the Metal path is
    /// therefore an artifact, not a real cost constraint -- the full 256x256 map (65,536
    /// tiles) is exactly the ceiling `GSBoloView.m` never had (the v1.6.1 brainstorm issue's
    /// item 1). Set to the whole map so the floor never binds under live Metal.
    static let liveMetalTileCountBudget = 256 * 256

    private var scrollViewFrameObserverInstalled = false

    /// **D160 item 1:** the dynamic minimum-magnification floor, a function of the live
    /// viewport size, with no reference counterpart (`GSBoloView.m` never bounds render
    /// cost by window size at all -- see this file's own Wave 7.2 header, D81). Pure,
    /// static, directly `swift test`-able, matching this file's own precedent (D146) of
    /// extracting geometry logic out of the view rather than only exercising it through the
    /// `xcodebuild`-hosted `NSView`
    /// path. `viewportWidth`/`viewportHeight` are screen-point dimensions (i.e. an
    /// `NSView.frame.size`, NOT a magnification-scaled `.bounds.size`) -- the floor is a cap
    /// on physical on-screen draw cost, which doesn't change just because magnification did.
    static func minimumMagnification(viewportWidth: CGFloat, viewportHeight: CGFloat, tileBudget: Int) -> CGFloat {
        guard viewportWidth > 0, viewportHeight > 0, tileBudget > 0 else { return 0.5 }
        let raw = ((viewportWidth * viewportHeight) / (256 * CGFloat(tileBudget))).squareRoot()
        return min(max(raw, 0.5), 2.0)
    }

    /// **D160 item 1, live-verified before any of this was built:** a hosted-`GameView`
    /// diagnostic run this session (temporary, not committed) confirmed
    /// `NSScrollView.magnification` survives both a real window resize and a SwiftUI
    /// layout-only pass unchanged -- unlike D157's `contentInsets` casualty, SwiftUI does
    /// NOT fight this property across relayout on this codebase's own `GameView` hierarchy.
    /// `NSScrollView.magnification` stands as the mechanism per D160's ruling; no fallback
    /// to the reference's manual frame/bounds trick was needed.
    private func configureZoom() {
        guard let scrollView = enclosingScrollView else { return }
        scrollView.allowsMagnification = true
        if !scrollViewFrameObserverInstalled {
            scrollViewFrameObserverInstalled = true
            scrollView.postsFrameChangedNotifications = true
            NotificationCenter.default.addObserver(
                self, selector: #selector(scrollViewFrameDidChange),
                name: NSView.frameDidChangeNotification, object: scrollView
            )
        }
        applyEffectiveMagnification()
    }

    /// Registered on the enclosing `NSScrollView`'s own frame, not its `NSClipView`
    /// (`contentView`) -- live-measured this session: `GameView`'s HUD `safeAreaInset`s
    /// contribute a *fixed* `contentInsets` (top 48/left 56/right 228, same figures D157
    /// already measured; bottom is the `EventLogBar` safe-area inset, not 0) that doesn't
    /// itself change with window size, so the scroll
    /// view's frame and its clip view's frame move together 1:1 on every resize this session
    /// observed -- observing either would do, this one matches `applyEffectiveMagnification`'s
    /// own read of `scrollView.frame` below.
    @objc private func scrollViewFrameDidChange() {
        applyEffectiveMagnification()
    }

    /// **Revised mid-session after a test caught a real bug in the first draft:** an earlier
    /// version of this method unconditionally snapped `scrollView.magnification` to
    /// `zoomLevels[zoomIndex]` on every call -- including from `viewWillDraw()`, i.e. every
    /// single frame. That silently fought native pinch-to-zoom/scroll-wheel-zoom gestures
    /// (D160 item 3, explicitly approved and left enabled): a user's live pinch sets
    /// `scrollView.magnification` directly, and the very next `viewWillDraw()` call would
    /// have stomped it straight back to whatever `zoomIndex` last pointed to.
    /// `GameRenderViewZoomTests.magnificationSurvivesWindowResizeAndAPureLayoutPass` caught
    /// this immediately (a manually-set 2.0 kept reverting to the default 1.0).
    ///
    /// Fixed by using `NSScrollView.minMagnification`/`maxMagnification` as the actual
    /// enforcement mechanism -- AppKit itself clamps every set (gesture-driven or
    /// programmatic) to that range continuously and natively, so a live pinch is bounded
    /// during the gesture rather than corrected after the fact, and this method never needs
    /// to touch `scrollView.magnification` at all when it's already >= the current floor.
    /// It only intervenes -- raising both the actual magnification and `zoomIndex` together,
    /// same "never let the button state and the screen silently diverge" reasoning as
    /// before -- when the *current* magnification has fallen below a *newly recomputed*
    /// floor (the one scenario `minMagnification`/`maxMagnification` alone can't already
    /// cover, since AppKit doesn't retroactively re-clamp an existing value just because the
    /// bound itself moved).
    /// v1.6.0 (#25) increment 7: lets `GameRenderViewZoomTests`' two window-resize/floor tests
    /// keep asserting against a small, explicit budget instead of the production Metal-path
    /// budget above (which, at 65,536 tiles, no longer floors those tests' window sizes at
    /// all) -- decouples the tests from the production constant by premise, per the plan, so
    /// a future revision of either budget doesn't silently break them. `nil` (the default) is
    /// a no-op; production code never sets this.
    var tileBudgetOverrideForTesting: Int?

    private func applyEffectiveMagnification() {
        guard let scrollView = enclosingScrollView else { return }
        let viewport = scrollView.frame.size
        let tileBudget = tileBudgetOverrideForTesting
            ?? (liveMetalTerrainRenderer != nil ? Self.liveMetalTileCountBudget : Self.tileCountBudget)
        let floor = Self.minimumMagnification(
            viewportWidth: viewport.width, viewportHeight: viewport.height, tileBudget: tileBudget
        )
        scrollView.minMagnification = floor
        scrollView.maxMagnification = Self.zoomLevels.last!
        guard scrollView.magnification < floor else { return }
        if let raisedIndex = Self.zoomLevels.firstIndex(where: { $0 >= floor }) {
            zoomIndex = max(zoomIndex, raisedIndex)
        }
        scrollView.magnification = Self.zoomLevels[zoomIndex]
    }

    /// Test-only hook: re-runs the floor computation on demand, so a test can set
    /// `tileBudgetOverrideForTesting` after `hostGameView` has already triggered the
    /// window's *initial* `configureZoom()` pass (which ran under the production budget)
    /// and still observe a floor computed under the override.
    func reapplyEffectiveMagnificationForTesting() {
        applyEffectiveMagnification()
    }

    /// Ported from `zoomIn:`/`zoomOut:` (`GSXBoloController.m:1483-1515`) -- same fixed
    /// fractional-viewport-offset recenter (`+0.25×` visRect size on zoom in, `-0.5×` on
    /// zoom out), applied via direct clip-view-origin math rather than
    /// `setMagnification(_:centeredAt:)` -- the same direct-origin idiom `scroll(dx:dy:)`
    /// already uses and this project already trusts (D157), not a new invention, and it
    /// avoids taking on trust in a second API's own centering semantics this session never
    /// empirically probed. **Disclosed:** the reference's own fixed `0.25`/`-0.5` fractions
    /// are only exactly center-preserving for a full 2× step; ported byte-for-byte anyway
    /// since that's the reference's own actual (slightly-off-center for a 1.0→1.5 or
    /// 1.0→0.75 step) behavior, not a bug this port should silently correct.
    ///
    /// **F1 fix (D161, PARITY audit `fc4894b`):** this used to set `zoomIndex = index`
    /// unconditionally, then apply the recenter pan unconditionally too. When AppKit's
    /// dynamic `minMagnification` floor clamps the requested set, the actual on-screen
    /// magnification can land exactly where it already was -- a live probe confirmed the
    /// clamp lands on `minMagnification` *exactly*, not merely near it -- so the old code
    /// still panned the viewport with zero zoom change (PARITY reproduced this live,
    /// 540-940pt phantom pans at 2400×1600/1600×1200) and still let `currentZoomLevel`
    /// report a level the screen wasn't actually at. Fixed by comparing the scroll view's
    /// *actual* magnification before and after the set: `zoomIndex` now always resyncs to
    /// the largest discrete level not exceeding the actual on-screen magnification (the
    /// same "never let the button state and the screen silently diverge" invariant
    /// `currentZoomLevel` documents below), and the recenter pan is skipped entirely
    /// whenever that actual magnification didn't move at all.
    private func setZoom(to index: Int) {
        guard Self.zoomLevels.indices.contains(index), let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        let visRect = clipView.bounds
        let goingIn = index > zoomIndex
        let previousMagnification = scrollView.magnification
        // AppKit clamps this set to the live `[minMagnification, maxMagnification]` range
        // already installed by a prior `applyEffectiveMagnification()` call -- e.g. zooming
        // out to 0.5x on a viewport whose floor already sits above 0.5x lands at the floor,
        // not at a value below it. The follow-up call below then only needs to recompute the
        // floor for the *current* viewport (the one case that set couldn't already handle:
        // the floor itself changing since it was last installed).
        scrollView.magnification = Self.zoomLevels[index]
        applyEffectiveMagnification()
        let effectiveMagnification = scrollView.magnification

        // Resync `zoomIndex` to whatever discrete level is actually in effect -- AppKit's
        // clamp can land `effectiveMagnification` on a value matching none of `zoomLevels`
        // exactly (a dynamic floor sitting strictly between two discrete steps). The
        // largest level not exceeding the real on-screen magnification is the honest
        // "currently in effect" answer.
        zoomIndex = Self.zoomLevels.lastIndex(where: { $0 <= effectiveMagnification }) ?? index

        // If the requested zoom didn't actually move the screen at all -- the clamp landed
        // exactly back where it already was -- skip the recenter pan entirely. Applying it
        // here would move the viewport with zero zoom change (F1's phantom-pan defect).
        guard effectiveMagnification != previousMagnification else { return }

        let fraction: CGFloat = goingIn ? 0.25 : -0.5
        let newOrigin = NSPoint(
            x: visRect.origin.x + fraction * visRect.size.width,
            y: visRect.origin.y + fraction * visRect.size.height
        )
        let constrained = clipView.constrainBoundsRect(NSRect(origin: newOrigin, size: clipView.bounds.size))
        clipView.scroll(to: constrained.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Wired to `GameView`'s top-bar "Zoom In" button (D160: no `NSToolbar` anywhere in this
    /// project, so the existing HStack is the natural home, not the reference's toolbar
    /// item). No-ops silently at `MAX_ZOOM` -- the reference's own bounds guard
    /// (`if (zoomLevel < MAX_ZOOM)`), reproduced via `setZoom(to:)`'s `indices.contains` guard.
    public func zoomIn() { setZoom(to: zoomIndex + 1) }
    /// Wired to `GameView`'s top-bar "Zoom Out" button. No-ops silently at zoom index 0,
    /// matching the reference's own `if (zoomLevel > 0)` guard.
    public func zoomOut() { setZoom(to: zoomIndex - 1) }

    /// The currently-selected discrete zoom level (`Self.zoomLevels[zoomIndex]`) -- exposed
    /// read-only, same `public private(set)`-style pattern as `selectedBuilderTool` above,
    /// for tests/future UI to inspect without exposing the mutable index itself.
    public var currentZoomLevel: CGFloat { Self.zoomLevels[zoomIndex] }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// Belt-and-suspenders alongside the `frameDidChangeNotification` observer above:
    /// `AppKit`'s notification is tied to the classic `setFrame(_:)`/`setFrameSize(_:)`
    /// setters, and this session couldn't independently confirm SwiftUI's own layout engine
    /// always routes a HUD-driven resize through those exact setters rather than some other
    /// (e.g. Auto Layout constraint) path that skips the notification. `viewWillDraw()` runs
    /// before every draw pass regardless of *how* a resize happened, and `render(_:)` sets
    /// `needsDisplay = true` every tick (file header) -- so within one tick of any resize,
    /// this self-heals the floor even if the notification silently didn't fire.
    /// `applyEffectiveMagnification()` itself is a cheap no-op once already at the target.
    public override func viewWillDraw() {
        super.viewWillDraw()
        applyEffectiveMagnification()
    }

    public override var isFlipped: Bool { true }
    /// v1.6.0 (#25) increment 6: `true` (the original, unconditional value) tells AppKit this
    /// view always fully covers its own bounds with opaque content, which lets it skip
    /// compositing anything positioned behind it -- fine when this view draws its own terrain,
    /// but it would make `LiveMetalTerrainOverlay`'s MTKView (deliberately positioned *behind*
    /// this view, see `installLiveMetalOverlayIfNeeded`) invisible regardless of z-order, since
    /// AppKit would never actually composite through to it. `false` only while the live overlay
    /// is active, when this view's own `draw(_:)` genuinely does leave terrain pixels
    /// transparent (it skips `drawTerrain` entirely in that mode) for the layer behind it to
    /// show through.
    public override var isOpaque: Bool { liveMetalOverlay == nil }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: mapPixelSize, height: mapPixelSize)
    }

    /// v1.5.0 #1: the host's own player-slot `FogState` for the current `state.localPlayer`,
    /// supplied by whichever `GameSession` init actually has one (the host path, via
    /// `HostGameEngine.fogState(for:)`) -- `nil` for the join/single-process paths, which
    /// render `state.terrain` as received/simulated with no fog logic of their own (the
    /// host-authoritative deviation, `docs/CONSTRAINTS.md`, moves fog entirely onto the
    /// host side; a join client's data is already redacted by the time it arrives, once
    /// Phase 4 wires that up).
    private var fogState: FogState?

    /// `fogState == nil` means this path has no fog logic (join client, solo): it draws the terrain
    /// it holds as-is, because the host already redacted what a join client receives. The host path
    /// always passes a `FogState` (an empty one before its first tick), so it stays fail-closed.
    static func resolvedTileGrid(for state: GameState, fogState: FogState?) -> TileGrid {
        if state.hiddenMines, let fogState {
            return fogResolvedTileGrid(for: state, fogState: fogState)
        } else {
            return displayTileGrid(for: state)
        }
    }

    /// How many times `render` actually rebuilt `tileGrid` (a test hook for the reuse check).
    private(set) var tileGridRebuildCount = 0

    /// True when everything `resolvedTileGrid` reads is identical, so the previous grid is still
    /// correct. Must list exactly the inputs of `displayTileGrid`/`fogResolvedTileGrid`: terrain
    /// storage; each pill's position, armour and owner; each base's position and owner; the local
    /// player; each player's `used`/`alliance` (via `testAlliance`); `hiddenMines`; and, when
    /// `hiddenMines` is on, the `FogState` refcount and seen-tile arrays. Anything else in
    /// `GameState` (ticks, counters, positions) deliberately does not count.
    static func tileGridInputsEqual(
        _ old: GameState, _ new: GameState, _ oldFog: FogState?, _ newFog: FogState?
    ) -> Bool {
        guard old.hiddenMines == new.hiddenMines, old.localPlayer == new.localPlayer,
            old.pills.count == new.pills.count, old.bases.count == new.bases.count,
            old.players.count == new.players.count,
            old.terrain.storage == new.terrain.storage
        else { return false }
        for i in old.pills.indices {
            let a = old.pills[i]
            let b = new.pills[i]
            if a.x != b.x || a.y != b.y || a.armour != b.armour || a.owner != b.owner { return false }
        }
        for i in old.bases.indices {
            let a = old.bases[i]
            let b = new.bases[i]
            if a.x != b.x || a.y != b.y || a.owner != b.owner { return false }
        }
        for i in old.players.indices {
            if old.players[i].used != new.players[i].used || old.players[i].alliance != new.players[i].alliance {
                return false
            }
        }
        guard new.hiddenMines else { return true }
        switch (oldFog, newFog) {
        case (nil, nil): return true
        case let (a?, b?): return a.fog == b.fog && a.seenTiles == b.seenTiles
        default: return false
        }
    }

    /// 7.3 calls this after each `runTick()`; this view schedules no redraw of its own (D82) --
    /// it only reacts to being handed a new snapshot. `fogState` is the rendering
    /// observer's own fog view (see this property's own doc comment above) -- `nil` unless
    /// `state.hiddenMines` is true and the host path supplies one.
    public func render(_ newState: GameState, fogState: FogState? = nil) {
        let previousState = state
        let previousFogState = self.fogState
        state = newState
        self.fogState = fogState
        // Rebuilding the 256x256 grid costs about 9 ms (18 ms with fog) in a Debug build, most of a
        // 20 ms tick, and most ticks change nothing it reads -- so reuse it when nothing did (#89).
        if tileGridRebuildCount == 0
            || !Self.tileGridInputsEqual(previousState, newState, previousFogState, fogState)
        {
            tileGrid = Self.resolvedTileGrid(for: newState, fogState: fogState)
            tileGridRebuildCount += 1
            // v1.6.0 follow-up: `liveMetalOverlay`'s MTKView is on-demand now (see its own
            // init doc comment), not continuous -- redraw it only when the grid it draws
            // actually changed, not every tick.
            liveMetalOverlay?.mtkView.needsDisplay = true
        }
        for i in newState.players.indices
        where newState.players[i].connected && i != newState.localPlayer {
            remoteTankSmoothers[i, default: RemotePositionSmoother()]
                .update(rawPosition: newState.players[i].tank, tick: newState.ticks)
            remoteBuilderSmoothers[i, default: RemotePositionSmoother()]
                .update(rawPosition: newState.players[i].builder, tick: newState.ticks)
        }
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        let signpost = BoloSignposts.render.beginInterval(BoloSignposts.drawName)
        defer { BoloSignposts.render.endInterval(BoloSignposts.drawName, signpost) }
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        if liveMetalOverlay != nil {
            // Terrain is drawn live by the floating Metal overlay's own MTKView draw loop --
            // only sprites/shells/explosions/builders stay on this CGContext path (small,
            // roughly zoom-independent; not what #25 exists to fix). See
            // `LiveMetalTerrainOverlay`'s own header for why terrain specifically moved.
            drawSprites(ctx)
        } else {
            renderer.draw(self, ctx: ctx, dirtyRect: dirtyRect)
        }
        drawSelector(ctx)
        drawCrosshair(ctx)
    }

    /// **D152 item 1:** mirrors `GSBoloView.m:394-403`'s "draw selector" block. The oracle polls
    /// `[NSEvent mouseLocation]` fresh inside its own `drawSprites`, converting screen -> window
    /// -> view coordinates and gating with `[self mouse:aPoint inRect:[self visibleRect]]` --
    /// same approach here, no `NSTrackingArea`/mouse-moved machinery needed since `render(_:)`
    /// already forces a redraw every tick (file header), so this always reflects a fresh poll.
    /// The oracle's own quantization line adds a `FWIDTH - ...` flip term because its view is
    /// *not* flipped; this view already is (`isFlipped == true`, D66/file header, the same
    /// convention `drawSprite`/`drawTerrain` use), so the flip term is dropped rather than
    /// transcribed literally -- porting it here would double-flip.
    private func drawSelector(_ ctx: CGContext) {
        guard let window else { return }
        let screenPoint = NSEvent.mouseLocation
        let windowPoint = window.convertPoint(fromScreen: screenPoint)
        let viewPoint = convert(windowPoint, from: nil)
        guard isMousePoint(viewPoint, in: visibleRect) else { return }
        let size = CGFloat(tileSize)
        let tileX = floor(viewPoint.x / size) + 0.5
        let tileY = floor(viewPoint.y / size) + 0.5
        drawSprite(SELETRIMAGE, at: Vec2f(x: Float(tileX), y: Float(tileY)), ctx)
    }

    /// **D152 item 1:** mirrors `GSBoloView.m:406-409`'s "draw crosshair" block exactly --
    /// `client.players[client.player].dir` is the same field the hull sprite itself is drawn
    /// with (`GSBoloView.m:337`), so this is a variable-*distance* marker along the hull's own
    /// heading (`state.local.range`, adjusted by the INCRE/DECRE aim keys -- `TankLocalTick.swift`
    /// lines 856-860), not a second independent aim direction.
    private func drawCrosshair(_ ctx: CGContext) {
        guard state.players.indices.contains(state.localPlayer) else { return }
        let player = state.players[state.localPlayer]
        guard !player.dead else { return }
        let point = player.tank + dir2vec(player.dir) * state.local.range
        drawSprite(CROSSHIMAGE, at: point, ctx)
    }

    // MARK: - Keyboard input (D88 §2)

    public override var acceptsFirstResponder: Bool { true }

    /// **B.7 follow-up:** `viewDidMoveToWindow()` alone can fire before `window` has actually
    /// become key (e.g. right after transitioning here from a form full of buttons/text fields
    /// that just held focus themselves) -- `makeFirstResponder` silently has no effect on a
    /// non-key window, and nothing else ever re-claims it, leaving every key press dead with no
    /// visible symptom. Deferring one runloop turn covers that race; `mouseDown` reclaiming focus
    /// on click covers the case where something else legitimately took it back afterward (e.g. a
    /// toolbar control).
    public override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        DispatchQueue.main.async { [weak self] in
            guard let self else { return }
            self.window?.makeFirstResponder(self)
            self.centerOnLocalPlayerSpawn()
            self.configureZoom()
            self.installLiveMetalOverlayIfNeeded()
        }
    }

    /// v1.6.0 (#25) increment 6: must halt `liveMetalOverlay`'s continuous draw loop before
    /// this view (and the window it's leaving) tear down -- see `LiveMetalTerrainOverlay.stop()`'s
    /// own doc comment for the crash this fixes and how it was found.
    public override func viewWillMove(toWindow newWindow: NSWindow?) {
        super.viewWillMove(toWindow: newWindow)
        if newWindow == nil {
            liveMetalOverlay?.stop()
        }
    }

    /// v1.6.0 (#25) increment 6: `enclosingScrollView` is reliably available by this point,
    /// same reasoning `configureZoom()` above already relies on. A no-op unless
    /// `liveMetalTerrainRenderer` was supplied at init and this hasn't already run.
    private func installLiveMetalOverlayIfNeeded() {
        guard liveMetalOverlay == nil, let renderer = liveMetalTerrainRenderer,
            let scrollView = enclosingScrollView, let overlay = LiveMetalTerrainOverlay(renderer: renderer, gameRenderView: self)
        else { return }
        // A plain subview of the scroll view itself, not `addFloatingSubview` (that API floats
        // a view along only one scroll axis at a time -- e.g. a ruler that scrolls vertically
        // with content but stays fixed horizontally -- there's no "fixed on both axes" case in
        // its `NSEventGestureAxis` parameter). The scroll view's own frame never moves during
        // scrolling (only its clip/document view's bounds.origin does), so an ordinary subview
        // of the scroll view already stays pinned to the viewport with no special API needed.
        //
        // `positioned: .below, relativeTo: scrollView.contentView` matters: terrain must stay
        // *behind* sprites (this view now draws only terrain, `GameRenderView.draw(_:)` now
        // draws only sprites when this overlay is active) -- a plain `addSubview` appends to
        // the end of the subview list, which AppKit draws *last*, i.e. on *top*, the wrong
        // side of the document view (which draws the sprites this needs to stay under).
        scrollView.addSubview(overlay.mtkView, positioned: .below, relativeTo: scrollView.contentView)
        liveMetalOverlay = overlay
        installLiveMetalOverlayObserversIfNeeded(on: scrollView)
        syncLiveMetalOverlayFrame()
    }

    /// **Live-evaluation bug fix (first eval build, `d49ca48`):** the original implementation
    /// sized `overlay.mtkView.frame` to `scrollView.bounds` (the *whole* scroll view, chrome
    /// included) and tracked resize via `autoresizingMask`. `GameView`'s HUD `safeAreaInset`s
    /// give this scroll view real, non-zero `contentInsets` (top 48/left 56/right 228 + a
    /// bottom inset, measured at `:227-234`/`:745-749` above) -- so that frame was systematically
    /// larger than the actual visible map region `renderLiveTerrain`'s `visibleRect` describes,
    /// by an amount that shrinks proportionally as the window grows. `MetalTileRenderer
    /// .renderLiveTerrain`'s `scale = targetTexture.width / visibleRect.width` then baked that
    /// mismatch straight into the terrain's on-screen size -- exactly the reported symptom
    /// ("elements scale with the window while the map does not"): the CPU-drawn sprites already
    /// used the correct, inset-excluding `visibleRect`; only the terrain overlay's backing
    /// geometry was wrong.
    ///
    /// Fixed by sizing/positioning the `MTKView` to `scrollView.contentView.frame` -- the clip
    /// view, whose frame AppKit already computes as `scrollView.bounds` minus `contentInsets`,
    /// in the *same* superview coordinate space this subview is added to (the clip view is
    /// itself a direct subview of the scroll view) -- and re-syncing that frame explicitly on
    /// both a scroll-view frame change (window resize) and a clip-view bounds change (scroll/
    /// pan/zoom), matching the mechanism `configureZoom()`/`scrollViewFrameDidChange()` above
    /// already prove reliable on this exact view hierarchy, rather than trusting
    /// `autoresizingMask` (which only tracks the *scroll view's* size, not the clip view's
    /// inset-adjusted one, and never fires on a pure scroll/pan at all).
    private func installLiveMetalOverlayObserversIfNeeded(on scrollView: NSScrollView) {
        guard !liveMetalOverlayObserversInstalled else { return }
        liveMetalOverlayObserversInstalled = true
        scrollView.postsFrameChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncLiveMetalOverlayFrame),
            name: NSView.frameDidChangeNotification, object: scrollView
        )
        scrollView.contentView.postsBoundsChangedNotifications = true
        NotificationCenter.default.addObserver(
            self, selector: #selector(syncLiveMetalOverlayFrame),
            name: NSView.boundsDidChangeNotification, object: scrollView.contentView
        )
    }

    @objc private func syncLiveMetalOverlayFrame() {
        guard let overlay = liveMetalOverlay, let scrollView = enclosingScrollView else { return }
        overlay.mtkView.frame = scrollView.contentView.frame
        // v1.6.0 follow-up: on-demand MTKView -- a frame/bounds change means the camera
        // (scroll/zoom/pan/resize) moved, so the terrain needs a fresh draw even though
        // `render(_:)` wasn't necessarily called this instant.
        overlay.mtkView.needsDisplay = true
    }

    /// **D137:** click-to-build. Converts the click to a tile coordinate using this view's own
    /// +y-down coordinate space (`isFlipped == true`, file header) -- same convention
    /// `drawTerrain`/`drawSprites` already use, no separate transform needed. Clamped to the
    /// 256x256 map bounds (a click on the view outside them shouldn't happen given
    /// `intrinsicContentSize`, but out-of-bounds is guarded rather than trusted). Unlimited
    /// range, matching `buildercommand()` (client.c:6533-6538) exactly -- no distance check here.
    public override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        let point = convert(event.locationInWindow, from: nil)
        let tx = Int(point.x) / tileSize
        let ty = Int(point.y) / tileSize
        if tx >= 0, tx < 256, ty >= 0, ty < 256 {
            onBuilderCommand?(selectedBuilderTool, BoloKit.Pointi(x: Int32(tx), y: Int32(ty)))
        }
        super.mouseDown(with: event)
    }

    /// **D110:** this view's `intrinsicContentSize` is the full 4096x4096 map, wrapped in
    /// `GameView`'s `ScrollView` -- with no camera logic at all, that opens scrolled to the map's
    /// (0,0) corner, not wherever the local player actually spawned, with no on-screen cue that
    /// scrolling is even necessary (found live: Jerod could see terrain but not his own tank).
    /// One-shot, same deferred timing as the first-responder claim above and for the same reason
    /// -- the enclosing `NSScrollView`'s own layout may not have settled on this runloop turn yet,
    /// so its `contentView.bounds.size` (used below) isn't trustworthy any earlier.
    private func centerOnLocalPlayerSpawn() {
        centerViewport(on: state.players.indices.contains(state.localPlayer)
            ? state.players[state.localPlayer].tank : nil)
    }

    public override func keyDown(with event: NSEvent) {
        // `isARepeat` guard mirrors `GSBoloView.m:477-482` exactly -- without it, holding a key
        // re-fires at the OS text-key-repeat rate on top of the flag already being set.
        guard !event.isARepeat else { return }
        // D137: builder-tool digit keys 1-5, checked first -- matches `keyEvent:forKey:`'s own
        // structure (dictionary lookup, then a separate hardcoded `else if` chain for these).
        // Not rebindable (see `selectedBuilderTool`'s doc comment), so this never goes through
        // `bindings`/`applyKeyChange` at all.
        if let tool = builderTool(forKeyCode: event.keyCode) {
            selectedBuilderTool = tool
            return
        }
        applyKeyChange(keyCode: event.keyCode, isDown: true)
    }

    public override func keyUp(with event: NSEvent) {
        guard !event.isARepeat else { return }
        applyKeyChange(keyCode: event.keyCode, isDown: false)
    }

    /// LMINE's binding is a modifier key by default (Shift, keycode 56) -- its transitions arrive
    /// here, not `keyDown`/`keyUp`. Tracking just the one bit actually bound (rather than porting
    /// `GSBoloView.m:489-498`'s fully generic 8-bit modifier diff) is sufficient because LayMine
    /// is the only modifier-key default the reference ships and the settings UI only lets it be
    /// rebound to another key, never a chord.
    private var shiftPressed = false

    public override func flagsChanged(with event: NSEvent) {
        let pressed = event.modifierFlags.contains(.shift)
        guard pressed != shiftPressed else { return }
        shiftPressed = pressed
        if let lmineKeyCode = bindings.keyCode(for: .layMine) {
            applyKeyChange(keyCode: lmineKeyCode, isDown: pressed)
        }
    }

    private func applyKeyChange(keyCode: UInt16, isDown: Bool) {
        if let change = inputFlagsChange(forKeyCode: keyCode, isDown: isDown, bindings: bindings) {
            onInputFlagsChange?(change)
            if bindings.resolve(keyCode: keyCode) == .layMine, isDown {
                onLayMineKeyDown?()
            }
            return
        }
        // Full action set (D128 backlog C.1): the 6 view actions (scroll/tank-center/pill-center)
        // have no InputFlags effect, only fire on key-down, matching `keyEvent:forKey:`'s own
        // `if (event) { ... }` guards around every one of those branches
        // (`GSXBoloController.m:1688-1717`).
        guard isDown, let action = nonMaskAction(forKeyCode: keyCode, bindings: bindings) else { return }
        performViewAction(action)
    }

    /// **Issue #17:** extracted out of `applyKeyChange` so `GameControllerInputHandler`
    /// (`GameControllerInput.swift`) can drive the same 6 view actions off a controller-button
    /// down edge, without duplicating this switch or going through a keycode at all. `action`
    /// being a mask action (or unrecognized here) is a silent no-op, matching the keyboard path's
    /// own `default: break`.
    public func performViewAction(_ action: InputAction) {
        switch action {
        case .scrollUp: scroll(dx: 0, dy: -64)
        case .scrollDown: scroll(dx: 0, dy: 64)
        case .scrollLeft: scroll(dx: -64, dy: 0)
        case .scrollRight: scroll(dx: 64, dy: 0)
        case .tankView: centerOnLocalPlayerTank()
        case .pillView: centerOnNearestFriendlyPill()
        default: break
        }
    }

    /// Ported from `scrollUp:`/`scrollDown:`/`scrollLeft:`/`scrollRight:`
    /// (`GSXBoloController.m:1236-1306`) -- the same fixed 64pt nudge those use at the reference's
    /// own default zoom level (`kZoomLevels[zoomLevel]` divisor dropped since v1 has no zoom
    /// system, D120). The reference also warps the mouse cursor to stay over the same map point
    /// after the scroll -- deliberately not ported: it's a cosmetic nicety with no gameplay
    /// effect, and `CGWarpMouseCursorPosition`-equivalent AppKit code would add real complexity
    /// for a nice-to-have (disclosed remaining gap, not an oversight).
    /// **D157 item 3 fix:** `scrollToVisible(_:)`'s "minimum move to reveal this rect" semantics
    /// measure against the *unobscured* region (`bounds` minus `contentInsets`), and this
    /// scroll view's insets are asymmetric by construction -- `GameView`'s HUD panels
    /// (`safeAreaInset`s for the top bar, leading `BuilderToolStrip`, trailing
    /// `ResourceGaugesPanel`/`PlayerStatusGrid`) push SwiftUI's `ScrollView` to set
    /// `contentInsets` of top:48/left:56/right:228 plus a non-zero bottom from
    /// `EventLogBar` (D154 Wave 3; `bottomSafeAreaInsetPushesScrollViewContentInsetsOffZero`).
    /// Requesting a full-`bounds`-sized rect offset by a fixed 64pt
    /// nudge, as this used to do, is a request AppKit only partially (or never) has to honor to
    /// satisfy "reveal the rect" against that inset region -- explains the exact asymmetry Jerod
    /// hit live (up fully worked, right/down partially moved, left no-opped: each clipped by
    /// whatever inset sits on the *far* side of the requested move). Setting the clip view's
    /// origin directly, rather than asking it to reveal a rect, has no such inset-dependent
    /// heuristic -- it is exactly what the already-correct `seed` step in
    /// `GameViewFocusRoutingTests` does, and that step always landed on the exact requested
    /// point in every test run.
    ///
    /// **Milestone D.0 fix (D160 item 1's own item 4, empirically traced in the pre-brief):**
    /// `clipView.bounds.origin` lives in the document's fixed logical space, so a fixed
    /// `dx`/`dy` move produces a magnification-dependent on-screen distance once zoom exists
    /// -- confirmed via a standalone probe before this fix was written (the pre-brief's §3).
    /// Dividing by `scrollView.magnification` is exactly, coordinate-space-for-coordinate-
    /// space, the same compensation the reference's own `64.0 / kZoomLevels[zoomLevel]`
    /// performs (`GSXBoloController.m:1236-1306`), since its `visibleRect` lives in the
    /// identical fixed-logical space `NSScrollView.magnification` reproduces natively.
    private func scroll(dx: CGFloat, dy: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        let clipView = scrollView.contentView
        var origin = clipView.bounds.origin
        origin.x += dx / scrollView.magnification
        origin.y += dy / scrollView.magnification
        let constrained = clipView.constrainBoundsRect(NSRect(origin: origin, size: clipView.bounds.size))
        clipView.scroll(to: constrained.origin)
        scrollView.reflectScrolledClipView(clipView)
    }

    /// Ported from `tankCenter:` (`GSXBoloController.m:1529-1552`) -- centers the visible rect on
    /// the local player's own tank. Shares `centerOnLocalPlayerSpawn`'s clamped-origin math since
    /// both are "center the viewport on this map point" (that method's only difference is running
    /// once at load time on the tank's spawn position rather than its live one).
    private func centerOnLocalPlayerTank() {
        centerViewport(on: state.players.indices.contains(state.localPlayer)
            ? state.players[state.localPlayer].tank : nil)
    }

    /// Ported from `pillCenter:` (`GSXBoloController.m:1566-1647`) -- centers on the local
    /// player's nearest owned, armed (non-onboard, non-destroyed) pillbox. The reference cycles
    /// through every owned pill starting from whichever one the viewport is already centered on;
    /// this v1 port simplifies to "the first eligible owned pill" (deterministic, no viewport-
    /// relative cycling state to track) -- disclosed simplification, not a fidelity requirement
    /// PLANNER called out for this backlog item.
    private func centerOnNearestFriendlyPill() {
        guard state.players.indices.contains(state.localPlayer) else { return }
        let owner = UInt8(state.localPlayer)
        let pill = state.pills.first { $0.owner == owner && $0.isArmed }
        centerViewport(on: pill.map { Vec2f(x: Float($0.x), y: Float($0.y)) })
    }

    private func centerViewport(on point: Vec2f?) {
        guard let point, let scrollView = enclosingScrollView else { return }
        let size = CGFloat(tileSize)
        let visible = scrollView.contentView.bounds.size
        let maxX = max(0, CGFloat(mapPixelSize) - visible.width)
        let maxY = max(0, CGFloat(mapPixelSize) - visible.height)
        let origin = NSPoint(
            x: min(max(0, CGFloat(point.x) * size - visible.width / 2), maxX),
            y: min(max(0, CGFloat(point.y) * size - visible.height / 2), maxY)
        )
        scrollView.contentView.scroll(to: origin)
        scrollView.reflectScrolledClipView(scrollView.contentView)
    }

    // MARK: - Terrain (D65 superseded by v1.5.0 #1 when `state.hiddenMines` is on -- see
    // `render(_:fogState:)`'s own doc comment)
    //
    // v1.5.0 #1: this function's own logic is unchanged from D65 -- `tileGrid` itself now
    // carries the fog-resolved values (`fogResolvedTileGrid`) whenever `state.hiddenMines`
    // is true and a `fogState` was supplied, so `mapimage`/`isMinedTile` below naturally
    // draw the unknown-tile glyph for never-seen tiles and skip the mine overlay for a
    // hidden (substituted-to-unmined) mine with no changes needed here. D148(C)'s own
    // rejection of per-observer mine visibility no longer applies -- that state is now
    // modeled (`FogState`/`fogTileFor`), just resolved before it reaches this function
    // rather than inside it.

    func drawTerrain(_ ctx: CGContext, dirtyRect: NSRect) {
        let minX = max(0, Int(dirtyRect.minX) / tileSize)
        let maxX = min(255, Int(dirtyRect.maxX.rounded(.up)) / tileSize)
        let minY = max(0, Int(dirtyRect.minY) / tileSize)
        let maxY = min(255, Int(dirtyRect.maxY.rounded(.up)) / tileSize)
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            for x in minX...maxX {
                let dst = CGRect(x: x * tileSize, y: y * tileSize, width: tileSize, height: tileSize)
                // mapimage()'s "tile unseen" sentinel (D64) -- reachable now under fog (a
                // never-seen tile's `Tile.unknown` resolves here) -- is drawn as plain sea, the
                // same look a guest shows outside its view, rather than black.
                let index = unseenTileAsSeaImage(mapimage(tileGrid, Int32(x), Int32(y)))
                if let cell = tilesImage.cropping(to: sheetSrcRect(forIndex: index)) {
                    blit(cell, in: dst, ctx)
                }
                // `mapimage()` intentionally returns the *unmined* image for every `minedX`
                // terrain variant (autotiling's own neighbor-matching needs), so the mine
                // glyph is a separate overlay blit, gated on `isMinedTile(tileGrid, ...)` --
                // which `fogResolvedTileGrid` has already substituted to the unmined `Tile`
                // for a hidden mine, so this naturally draws nothing for one this observer
                // hasn't (stickily) revealed.
                if isMinedTile(tileGrid, Int32(x), Int32(y)) != 0,
                   let mineCell = tilesImage.cropping(to: sheetSrcRect(forIndex: MINE00IMAGE)) {
                    blit(mineCell, in: dst, ctx)
                }
            }
        }
    }

    // MARK: - Sprites (every connected player -- B.9, generalized beyond the local-only D73 scope)
    //
    // D73's original v1 framing ("there are never any other connected players") is stale as of
    // B.7/B.8's real hosting/joining -- other players are real and connected now, and drawing
    // only the local one left them invisible on screen even though the simulation already tracks
    // them correctly. Generalized to match `GSBoloView.m:293-360`'s own draw order and per-player
    // scope exactly: builders for every connected player (shared BUILD0/BUILD1 sprite, no per-
    // player color), other players' tanks friendly/enemy-colored via the same mutual-alliance
    // `testAlliance` check `PlayerStatusView.swift` (C.0) already uses, the local player's own
    // tank last (always player-colored, unconditional), then shells/explosions for every
    // connected player (one shared sprite, no per-player color needed for either). Remote tanks
    // are drawn at `remoteTankSmoothers`' delayed/interpolated position (B.9's smoothing half,
    // D114), not the raw one -- builders/shells still draw raw, disclosed remaining scope, not
    // an oversight.
    func drawSprites(_ ctx: CGContext) {
        for explosion in state.explosions {
            // `GSBoloView.m:363`: fogvis for the global explosion list.
            drawExplosion(explosion, ctx, visFraction: visFraction(at: explosion.point, useForestTerm: false))
        }

        for i in state.players.indices where state.players[i].connected {
            let player = state.players[i]
            let position = i == state.localPlayer
                ? player.builder
                : (remoteBuilderSmoothers[i]?.smoothedPosition(atTick: state.ticks) ?? player.builder)
            drawBuilder(player, at: position, ctx)
        }

        for i in state.players.indices
        where state.players[i].connected && i != state.localPlayer && !state.players[i].dead {
            let other = state.players[i]
            let friendly = testAlliance(state.localPlayer, i, players: state.players)
            let base: Int32
            if friendly {
                base = other.boat ? FTKB00IMAGE : FTNK00IMAGE
            } else {
                base = other.boat ? ETKB00IMAGE : ETNK00IMAGE
            }
            // B.9 smoothing (D114): draw the delayed/interpolated position, not the raw
            // (jerky, ~10Hz-relay-frozen) one -- see `remoteTankSmoothers`'s own doc comment.
            // Falls back to the raw position only if `render(_:)` hasn't run yet for this index,
            // which shouldn't happen since it always runs immediately before `draw(_:)`.
            let smoothed = remoteTankSmoothers[i]?.smoothedPosition(atTick: state.ticks) ?? other.tank
            // `GSBoloView.m:315,322,325`: calcvis for a remote tank's own sprite.
            let vis = visFraction(at: smoothed, useForestTerm: true)
            drawSprite(base + headingColumn(other.dir), at: smoothed, ctx, fraction: vis)
            // `GSBoloView.m:328-330`'s `vis > 0.90` label case -- unconditionally true under
            // D65's full-visibility v1 scope (`visFraction` returns 1.0 there), real once
            // `state.hiddenMines` is on and a `fogState` was supplied.
            if vis > 0.90 {
                drawLabel(other.name, at: smoothed, ctx)
            }
        }

        if state.players.indices.contains(state.localPlayer) {
            let player = state.players[state.localPlayer]
            if !player.dead {
                let base = player.boat ? PTKB00IMAGE : PTNK00IMAGE
                drawSprite(base + headingColumn(player.dir), at: player.tank, ctx)
            }
        }

        for player in state.players where player.connected {
            for shell in player.shells {
                // `GSBoloView.m:349`: fogvis for a shell.
                drawSprite(
                    SHELL0IMAGE + headingColumn(shell.dir), at: shell.point, ctx,
                    fraction: visFraction(at: shell.point, useForestTerm: false)
                )
            }
            for explosion in player.explosions {
                // `GSBoloView.m:378`: fogvis for a per-player explosion.
                drawExplosion(explosion, ctx, visFraction: visFraction(at: explosion.point, useForestTerm: false))
            }
        }
    }

    private func drawBuilder(_ player: PlayerState, at position: Vec2f, _ ctx: CGContext) {
        switch player.builderStatus {
        case .goto, .work, .wait, .return:
            // GSBoloView alternates BUILD0/BUILD1 off a per-tick sequence counter
            // (`client.players[client.player].seq`) that this port's `PlayerState` has no
            // equivalent field for -- substituting `GameState.ticks` (always available,
            // monotonic), which drives the same cosmetic alternation with no gameplay effect.
            let frame = (state.ticks / 5) % 2 == 0 ? BUILD1IMAGE : BUILD0IMAGE
            // `GSBoloView.m:301`: calcvis, not fogvis, for a working builder.
            drawSprite(frame, at: position, ctx, fraction: visFraction(at: position, useForestTerm: true))
        case .parachute:
            // `GSBoloView.m:389`: fogvis (a separate loop from the goto/work/wait/return one
            // above), not calcvis, for a parachuting builder.
            drawSprite(BUILD2IMAGE, at: position, ctx, fraction: visFraction(at: position, useForestTerm: false))
        case .ready:
            break
        }
    }

    /// Mirrors `drawLabel:at:withAttributes:` (`GSBoloView.m:453-463`) -- white text centered on
    /// `point.x`, drawn flush against the sprite's own top edge. The reference computes
    /// `FWIDTH*16 - point.y*16 + 8` to flip into its own unflipped-view coordinate space; this
    /// view is already +y-down top-left-origin (D66/this file's own header), so no flip term is
    /// needed here.
    ///
    /// **D150(4) fix:** this used to compute `point.y*tile - tile - textSize.height`, an extra
    /// `tile - 8` (8px at `tileSize == 16`) below the sprite's real top edge -- `drawSprite`
    /// below draws the sprite's origin at `point.y*tile - 8`, not `point.y*tile - tile`. That
    /// left a consistent 8px gap between the label and the sprite the reference doesn't have.
    /// Corrected to anchor off the same `- 8` `drawSprite` uses.
    private static let labelAttributes: [NSAttributedString.Key: Any] = [
        .foregroundColor: NSColor.white,
        .font: NSFont.systemFont(ofSize: 11),
    ]

    private func drawLabel(_ name: String, at point: Vec2f, _ ctx: CGContext) {
        guard !name.isEmpty else { return }
        let string = NSAttributedString(string: name, attributes: Self.labelAttributes)
        let textSize = string.size()
        let tile = CGFloat(tileSize)
        let x = CGFloat(point.x) * tile - textSize.width * 0.5
        let y = CGFloat(point.y) * tile - 8 - textSize.height
        string.draw(at: CGPoint(x: x, y: y))
    }

    private func drawExplosion(_ explosion: Explosion, _ ctx: CGContext, visFraction: Float = 1.0) {
        let animationFraction = Float(explosion.counter) / Float(explosionTicks)
        let frame = EXPLO0IMAGE + Int32(Float(EXPLO5IMAGE - EXPLO0IMAGE) * animationFraction)
        drawSprite(frame, at: explosion.point, ctx, fraction: visFraction)
    }

    /// Mirrors `drawSprite:at:fraction:` (`GSBoloView.m:441-451`). `fraction` was dropped as
    /// dead always-1.0 code under D65's full-visibility v1 scope (this function's own prior
    /// doc comment said so) -- v1.5.0 #1 revives it: `fraction <= 0.00001` skips the draw
    /// entirely (matching the reference's own guard), otherwise blits at that alpha.
    /// v1.6.0 (#25) increment 5: lets a `TileRenderer` (`MetalTileRenderer`) source each
    /// sprite cell's pixels from its own GPU-rendered/cached texture instead of
    /// `spritesImage.cropping(to:)`, while every positioning/alliance/fog/animation decision
    /// in `drawSprites`/`drawBuilder`/`drawSprite` itself -- the actual business logic --
    /// stays exactly as-is, single source of truth. `nil` (the default) means "use the CPU
    /// crop," matching `CGContextTileRenderer`'s unmodified behavior.
    var spriteCellProvider: ((Int32) -> CGImage?)?

    private func drawSprite(_ index: Int32, at point: Vec2f, _ ctx: CGContext, fraction: Float = 1.0) {
        guard fraction > 0.00001 else { return }
        guard let cell = spriteCellProvider?(index) ?? spritesImage.cropping(to: sheetSrcRect(forIndex: index)) else { return }
        let size = CGFloat(tileSize)
        let originX: CGFloat = (CGFloat(point.x) * size - 8).rounded(.down)
        let originY: CGFloat = (CGFloat(point.y) * size - 8).rounded(.down)
        let dst = CGRect(x: originX, y: originY, width: size, height: size)
        if fraction < 1.0 {
            ctx.saveGState()
            ctx.setAlpha(CGFloat(fraction))
            blit(cell, in: dst, ctx)
            ctx.restoreGState()
        } else {
            blit(cell, in: dst, ctx)
        }
    }

    /// `calcVis`/`fogVis` fraction at `point` for the current render's observer, matching
    /// `GSBoloView.m:301,315,349,363,378,389`'s own per-sprite-kind choice of which of the
    /// two to call.
    ///
    /// #153: the `useForestTerm` (tank/walking-builder) path always calls `calcVis` now,
    /// even with no `fogState` -- forest concealment is core oracle gameplay, unrelated to
    /// `hiddenMines`/fog tracking (see `calcVis`'s own doc comment). The plain-`fogVis` path
    /// (shells/explosions/parachute builder) has nothing to offer without real fog data, so
    /// it keeps the `hiddenMines`/`fogState` gate -- `1.0` (fully visible, no fade) there is
    /// still the D65 default this feature must not change.
    private func visFraction(at point: Vec2f, useForestTerm: Bool) -> Float {
        if useForestTerm {
            return calcVis(point, state: state, fogState: fogState, observer: state.localPlayer)
        }
        guard state.hiddenMines, let fogState else { return 1.0 }
        return fogVis(point, fogState: fogState)
    }

    /// `CGContext.draw(_:in:)` draws a `CGImage`'s row 0 at the *high-Y* edge of the destination
    /// rect regardless of the view's own `isFlipped` state -- Core Graphics image drawing doesn't
    /// consult that AppKit-level flag, only NSView's own higher-level drawing paths do. In this
    /// view (`isFlipped == true`, low-Y = visual top), that leaves every blitted cell's content
    /// vertically mirrored on screen: row 0 (visually meant to be the top of the glyph) lands at
    /// the rect's bottom instead. Rotationally-symmetric art (flat terrain fills, the tip-on-
    /// centerline tank headings) hid this; the tank's off-centerline headings and turning
    /// direction (a vertical mirror reverses a rotating sequence's apparent spin) exposed it.
    /// Compensated here, once, for every caller -- flips the content back around the dst rect's
    /// own vertical center, leaving `dst`'s on-screen position untouched.
    func blit(_ image: CGImage, in dst: CGRect, _ ctx: CGContext) {
        ctx.saveGState()
        ctx.translateBy(x: 0, y: dst.midY)
        ctx.scaleBy(x: 1, y: -1)
        ctx.translateBy(x: 0, y: -dst.midY)
        ctx.draw(image, in: dst)
        ctx.restoreGState()
    }
}

// MARK: - SwiftUI bridge

/// Wraps a `GameSession`'s already-constructed `GameRenderView` (D82: the tick loop, not SwiftUI's
/// own diffing, decides when `render(_:)` fires -- `updateNSView` intentionally does nothing).
public struct GameRenderRepresentable: NSViewRepresentable {
    public let session: GameSession

    public init(session: GameSession) {
        self.session = session
    }

    public func makeNSView(context: Context) -> GameRenderView {
        session.renderView
    }

    public func updateNSView(_ nsView: GameRenderView, context: Context) {}
}

/// Loads a build-time-generated sheet PNG from the app bundle (D72's Run Script phase). Both
/// sheets are guaranteed present by that phase -- same fail-loud precedent as `GSBoloView`'s own
/// `+initialize` (`assert(... != nil)`). Free function (not `GameRenderRepresentable`'s own static
/// method) because `GameSession` -- which now constructs the `GameRenderView` -- needs it too.
public func loadSheetImage(named name: String) -> CGImage? {
    guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
          let provider = CGDataProvider(url: url as CFURL)
    else {
        return nil
    }
    return CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
}
