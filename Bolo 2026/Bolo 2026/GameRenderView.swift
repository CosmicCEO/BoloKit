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
//  single-process, there are never any other connected players) and the selector/crosshair/
//  pause-label HUD sprites (Milestone C's concern).

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
        needsDisplay = true
    }

    public override func draw(_ dirtyRect: NSRect) {
        guard let ctx = NSGraphicsContext.current?.cgContext else { return }
        drawTerrain(ctx, dirtyRect: dirtyRect)
        drawSprites(ctx)
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
            }
        }
    }

    // MARK: - Sprites (local player only -- v1 is single-process, D73)

    private func drawSprites(_ ctx: CGContext) {
        for explosion in state.explosions {
            drawExplosion(explosion, ctx)
        }

        guard state.players.indices.contains(state.localPlayer) else { return }
        let player = state.players[state.localPlayer]

        drawBuilder(player, ctx)
        for shell in player.shells {
            drawSprite(SHELL0IMAGE + headingColumn(shell.dir), at: shell.point, ctx)
        }
        for explosion in player.explosions {
            drawExplosion(explosion, ctx)
        }
        if !player.dead {
            let base = player.boat ? PTKB00IMAGE : PTNK00IMAGE
            drawSprite(base + headingColumn(player.dir), at: player.tank, ctx)
        }
    }

    private func drawBuilder(_ player: PlayerState, _ ctx: CGContext) {
        switch player.builderStatus {
        case .goto, .work, .wait, .return:
            // GSBoloView alternates BUILD0/BUILD1 off a per-tick sequence counter
            // (`client.players[client.player].seq`) that this port's `PlayerState` has no
            // equivalent field for -- substituting `GameState.ticks` (always available,
            // monotonic), which drives the same cosmetic alternation with no gameplay effect.
            let frame = (state.ticks / 5) % 2 == 0 ? BUILD1IMAGE : BUILD0IMAGE
            drawSprite(frame, at: player.builder, ctx)
        case .parachute:
            drawSprite(BUILD2IMAGE, at: player.builder, ctx)
        case .ready:
            break
        }
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

public struct GameRenderRepresentable: NSViewRepresentable {
    public let state: GameState

    public init(state: GameState) {
        self.state = state
    }

    public func makeNSView(context: Context) -> GameRenderView {
        // Both sheets are guaranteed present by D72's build-time Run Script phase -- same
        // fail-loud precedent as `GSBoloView`'s own `+initialize` (`assert(... != nil)`).
        guard let tiles = Self.loadSheetImage(named: "Tiles"),
              let sprites = Self.loadSheetImage(named: "Sprites")
        else {
            fatalError("Tiles.png/Sprites.png missing from the bundle -- D72's Run Script phase should guarantee this")
        }
        let view = GameRenderView(tilesImage: tiles, spritesImage: sprites)
        view.render(state)
        return view
    }

    public func updateNSView(_ nsView: GameRenderView, context: Context) {
        nsView.render(state)
    }

    private static func loadSheetImage(named name: String) -> CGImage? {
        guard let url = Bundle.main.url(forResource: name, withExtension: "png"),
              let provider = CGDataProvider(url: url as CFURL)
        else {
            return nil
        }
        return CGImage(pngDataProviderSource: provider, decode: nil, shouldInterpolate: false, intent: .defaultIntent)
    }
}
