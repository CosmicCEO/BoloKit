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

/// Sprite heading column, matching `GSBoloView.m`'s literal formula at every one of its
/// heading-dependent draw calls: `(int)(dir/(kPif/8.0) + 0.5) % 16`.
private func headingColumn(_ dir: Float) -> Int32 {
    Int32(dir / (kPif / 8.0) + 0.5) % 16
}

public final class GameRenderView: NSView {
    private var state = GameState()
    private var tileGrid = TileGrid()
    private let tilesImage: CGImage
    private let spritesImage: CGImage

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

    public init(tilesImage: CGImage, spritesImage: CGImage) {
        self.tilesImage = tilesImage
        self.spritesImage = spritesImage
        super.init(frame: NSRect(x: 0, y: 0, width: mapPixelSize, height: mapPixelSize))
    }

    @available(*, unavailable)
    public required init?(coder: NSCoder) {
        fatalError("init(coder:) not supported")
    }

    public override var isFlipped: Bool { true }
    public override var isOpaque: Bool { true }

    public override var intrinsicContentSize: NSSize {
        NSSize(width: mapPixelSize, height: mapPixelSize)
    }

    /// 7.3 calls this after each `runTick()`; this view schedules no redraw of its own (D82) --
    /// it only reacts to being handed a new snapshot.
    public func render(_ newState: GameState) {
        state = newState
        tileGrid = displayTileGrid(for: newState)
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
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawTerrain(ctx, dirtyRect: dirtyRect)
        drawSprites(ctx)
        drawBuilderTaskIndicators(ctx)
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

    /// **D137 UX indicator (Jerod's ruling):** a disclosed, deliberate departure from strict UI
    /// parity -- the reference has no such indicator at all (client.c/GSBoloView.m grep-
    /// confirmed, D137 pre-brief). Simplest acceptable form per the ruling: a straight line from
    /// the builder's current live position to its target tile, redrawn every frame while a task
    /// is in flight (`builderStatus != .ready` and `!= .parachute` -- parachuting has its own
    /// descent target with no "task," see `parachuteTick`). Purely render-layer: reads
    /// `PlayerState.builder`/`.builderTarget`, no new simulation state (`BuilderTick.swift`
    /// already tracks both). Drawn for every connected player, not just the local one -- another
    /// player's builder en route is exactly as useful to see as your own.
    private func drawBuilderTaskIndicators(_ ctx: CGContext) {
        let tile = CGFloat(tileSize)
        ctx.saveGState()
        ctx.setStrokeColor(NSColor.systemYellow.withAlphaComponent(0.7).cgColor)
        ctx.setLineWidth(1.5)
        ctx.setLineDash(phase: 0, lengths: [4, 3])
        for i in state.players.indices where state.players[i].connected {
            let player = state.players[i]
            switch player.builderStatus {
            case .goto, .work, .wait, .return:
                let from = i == state.localPlayer
                    ? player.builder
                    : (remoteBuilderSmoothers[i]?.smoothedPosition(atTick: state.ticks) ?? player.builder)
                let to = CGPoint(
                    x: (CGFloat(player.builderTarget.x) + 0.5) * tile,
                    y: (CGFloat(player.builderTarget.y) + 0.5) * tile
                )
                let fromPoint = CGPoint(x: CGFloat(from.x) * tile, y: CGFloat(from.y) * tile)
                // D146: a same-tile task (e.g. harvesting a tree the builder is already
                // standing on -- `resolveBuilderTask`/`queueBuilderCommand`,
                // `Sources/BoloKit/BuilderCommand.swift`, have no distance check and will
                // happily set `builderTarget == builder`'s current tile) produces a
                // degenerate zero-length segment here. Stroking that with an active dash
                // pattern crashes (`SIGABRT` in AppKit/QuartzCore/Metal's debug draw-call
                // validation, zero app-code frames) rather than silently no-op'ing -- skip
                // the draw entirely rather than feed it a degenerate segment.
                guard !Self.isDegenerateBuilderIndicatorLine(from: fromPoint, to: to) else { continue }
                ctx.move(to: fromPoint)
                ctx.addLine(to: to)
                ctx.strokePath()
            case .ready, .parachute:
                break
            }
        }
        ctx.restoreGState()
    }

    /// D146: true when `from`/`to` are close enough that stroking a dashed line between them
    /// is degenerate (zero/near-zero length) -- the exact geometry that crashed under Metal's
    /// debug draw-call validation. Small epsilon rather than exact equality: `from` carries the
    /// builder's live fractional sub-tile position while `to` is tile-center-snapped, so a
    /// builder that has arrived but isn't dead-center on its own target tile could differ by a
    /// sub-pixel amount that's still not worth drawing a visible line for. Pure/static so it's
    /// directly testable without an `NSView`/`CGContext`, matching `Bolo 2026Tests`'s D144/D145
    /// pattern of extracting pure logic out of view code rather than testing the view itself.
    static func isDegenerateBuilderIndicatorLine(from: CGPoint, to: CGPoint) -> Bool {
        abs(from.x - to.x) <= 0.5 && abs(from.y - to.y) <= 0.5
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
        }
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
    private func scroll(dx: CGFloat, dy: CGFloat) {
        guard let scrollView = enclosingScrollView else { return }
        var rect = scrollView.contentView.bounds
        rect.origin.x += dx
        rect.origin.y += dy
        scrollView.contentView.scrollToVisible(rect)
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

    // MARK: - Terrain (D65: every tile visible, straight `mapimage()` call)

    private func drawTerrain(_ ctx: CGContext, dirtyRect: NSRect) {
        let minX = max(0, Int(dirtyRect.minX) / tileSize)
        let maxX = min(255, Int(dirtyRect.maxX.rounded(.up)) / tileSize)
        let minY = max(0, Int(dirtyRect.minY) / tileSize)
        let maxY = min(255, Int(dirtyRect.maxY.rounded(.up)) / tileSize)
        guard minX <= maxX, minY <= maxY else { return }

        for y in minY...maxY {
            for x in minX...maxX {
                let dst = CGRect(x: x * tileSize, y: y * tileSize, width: tileSize, height: tileSize)
                let index = mapimage(tileGrid, Int32(x), Int32(y))
                guard index >= 0 else {
                    // mapimage()'s "tile unseen" sentinel (D64) -- unreachable under D65's full
                    // visibility, painted black defensively rather than left undrawn.
                    ctx.setFillColor(gray: 0, alpha: 1)
                    ctx.fill(dst)
                    continue
                }
                if let cell = tilesImage.cropping(to: sheetSrcRect(forIndex: index)) {
                    ctx.draw(cell, in: dst)
                }
                // D148(C): mines were pure terrain state with no glyph ever drawn over the
                // base tile (`mapimage()` intentionally returns the *unmined* image for every
                // `minedX` terrain variant, matching autotiling's own neighbor-matching needs --
                // see D148(C) pre-brief in AGENT_NOTES.md for why per-owner visibility was
                // rejected: the C reference's `hiddenmines` option/per-observer reveal state
                // isn't modeled anywhere in this port, so the correct default (matching the
                // reference's `hiddenmines == false` behavior, which is this port's only
                // modeled mode) is every mine visible to every player, not owner-only).
                if isMinedTile(tileGrid, Int32(x), Int32(y)) != 0,
                   let mineCell = tilesImage.cropping(to: sheetSrcRect(forIndex: MINE00IMAGE)) {
                    ctx.draw(mineCell, in: dst)
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
    private func drawSprites(_ ctx: CGContext) {
        for explosion in state.explosions {
            drawExplosion(explosion, ctx)
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
            drawSprite(base + headingColumn(other.dir), at: smoothed, ctx)
            // `GSBoloView.m:328-330`'s `vis > 0.90` label case, unconditionally true under D65's
            // full-visibility v1 scope (B.9 disclosed remainder, Phase 2 cleanup).
            drawLabel(other.name, at: smoothed, ctx)
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
                drawSprite(SHELL0IMAGE + headingColumn(shell.dir), at: shell.point, ctx)
            }
            for explosion in player.explosions {
                drawExplosion(explosion, ctx)
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
            drawSprite(frame, at: position, ctx)
        case .parachute:
            drawSprite(BUILD2IMAGE, at: position, ctx)
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

    private func drawExplosion(_ explosion: Explosion, _ ctx: CGContext) {
        let fraction = Float(explosion.counter) / Float(explosionTicks)
        let frame = EXPLO0IMAGE + Int32(Float(EXPLO5IMAGE - EXPLO0IMAGE) * fraction)
        drawSprite(frame, at: explosion.point, ctx)
    }

    /// Mirrors `drawSprite:at:fraction:` (`GSBoloView.m:441-451`) at `fraction = 1.0` --
    /// D65 means no fog-driven partial visibility in v1, so the fraction term is dropped
    /// rather than ported as dead always-1.0 code.
    private func drawSprite(_ index: Int32, at point: Vec2f, _ ctx: CGContext) {
        guard let cell = spritesImage.cropping(to: sheetSrcRect(forIndex: index)) else { return }
        let size = CGFloat(tileSize)
        let originX: CGFloat = (CGFloat(point.x) * size - 8).rounded(.down)
        let originY: CGFloat = (CGFloat(point.y) * size - 8).rounded(.down)
        let dst = CGRect(x: originX, y: originY, width: size, height: size)
        ctx.draw(cell, in: dst)
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
