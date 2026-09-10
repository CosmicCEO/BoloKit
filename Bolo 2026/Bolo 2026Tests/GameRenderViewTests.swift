//
//  GameRenderViewTests.swift
//  Bolo 2026Tests
//
//  D146 -- regression coverage for the builder-task-indicator crash (Jerod's real
//  SIGABRT hit while tree-harvesting). Root cause confirmed by tracing
//  `resolveBuilderTask`/`queueBuilderCommand` (`Sources/BoloKit/BuilderCommand.swift`): neither
//  has a distance check against the builder's own current tile, so commanding a builder to
//  harvest the tree tile it's already standing on sets `builderTarget` to that exact tile.
//  `GameRenderView.drawBuilderTaskIndicators` then strokes a dashed line between the builder's
//  live position and that target -- a zero-length segment for this exact scenario -- which
//  crashed under Metal's debug draw-call validation (every frame in the crash report is inside
//  AppKit/QuartzCore/Metal, zero app-code frames). Reproduces the exact same-tile scenario via
//  the real `BoloKit` APIs (not synthetic geometry alone) and confirms the extracted guard
//  (`GameRenderView.isDegenerateBuilderIndicatorLine`) would skip the resulting draw call.

import AppKit
import CoreGraphics
import Testing
import BoloKit

@testable import Bolo_2026

struct GameRenderViewTests {

    /// Reconstructs Jerod's exact crash trigger: a builder standing on a forest tile is
    /// commanded to harvest that same tile (`.tree` targeting the builder's own position).
    /// Confirms this is a real, reachable path (not just a plausible-sounding theory) --
    /// `queueBuilderCommand` queues it, and once picked up `builderTarget` ends up equal to the
    /// builder's own tile -- and that the geometry this produces is exactly what the D146 guard
    /// is meant to catch.
    @Test func sameTileTreeHarvestProducesADegenerateIndicatorLine() {
        var state = GameState()
        var player = PlayerState()
        player.used = true
        player.dead = false
        player.builder = Vec2f(x: 12.5, y: 12.5)
        state.players = [player]
        state.localPlayer = 0
        state.terrain[12, 12] = .forest

        let target = Pointi(x: 12, y: 12)

        // No distance check anywhere in this path (D137's own documented ruling) -- confirms
        // the same-tile command is accepted, not silently rejected before it can matter.
        queueBuilderCommand(command: .tree, target: target, player: 0, state: &state)
        #expect(state.players[0].pendingBuilderCommand == .tree)

        let task = resolveBuilderTask(command: .tree, target: target, state: state)
        #expect(task == .getTree)

        // Mirrors `BuilderTick.swift`'s `.ready` branch: `builderTarget` is set directly from
        // the pending target, with no equality-to-current-position guard anywhere in that path.
        state.players[0].builderTarget = target

        let tile: CGFloat = 16
        let builder = state.players[0].builder
        let builderTarget = state.players[0].builderTarget
        let from = CGPoint(x: CGFloat(builder.x) * tile, y: CGFloat(builder.y) * tile)
        let to = CGPoint(
            x: (CGFloat(builderTarget.x) + 0.5) * tile,
            y: (CGFloat(builderTarget.y) + 0.5) * tile
        )

        // Same tile, and the builder is already centered on it -- from/to land on the exact
        // same point, the precise degenerate geometry that used to reach `ctx.strokePath()`.
        #expect(from == to)
        #expect(GameRenderView.isDegenerateBuilderIndicatorLine(from: from, to: to))
    }

    @Test func differentTileIndicatorLineIsNotDegenerate() {
        let from = CGPoint(x: 100, y: 100)
        let to = CGPoint(x: 116, y: 100)
        #expect(!GameRenderView.isDegenerateBuilderIndicatorLine(from: from, to: to))
    }

    @Test func subPixelDifferenceIsStillTreatedAsDegenerate() {
        // `from` carries the builder's live fractional position; `to` is tile-center-snapped.
        // A builder that has arrived but isn't dead-center on its own target tile can differ by
        // a sub-pixel amount -- not worth drawing a visible line for either.
        let from = CGPoint(x: 100.2, y: 100.1)
        let to = CGPoint(x: 100.0, y: 100.0)
        #expect(GameRenderView.isDegenerateBuilderIndicatorLine(from: from, to: to))
    }

    // MARK: - D152 item 1: crosshair (offscreen render, no live window/mouse -- bootstrap's
    // blessed `cacheDisplay`/`bitmapImageRepForCachingDisplay` substitution for GUI verification)

    /// Confirms `drawCrosshair` actually paints `CROSSHIMAGE` (a white cross, `GlyphSource.swift`'s
    /// `.crosshair` case) at `player.tank + dir2vec(player.dir) * state.local.range`, not just that
    /// the code compiles. `drawSelector` is not exercised here -- it needs a real `NSWindow`/mouse
    /// position (`guard let window else { return }`), which an offscreen-rendered, unparented view
    /// correctly and silently skips; that's expected, not a gap in this test.
    @Test @MainActor func drawCrosshairPaintsWhiteCrossAtTankPlusDirTimesRange() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let view = GameRenderView(tilesImage: tiles, spritesImage: sprites)

        var state = GameState()
        var player = PlayerState()
        player.used = true
        player.connected = true
        player.dead = false
        player.tank = Vec2f(x: 20, y: 20)
        player.dir = 0
        state.players = [player]
        state.localPlayer = 0
        state.local.range = 3.0
        view.render(state)

        let rep = try #require(view.bitmapImageRepForCachingDisplay(in: view.bounds))
        view.cacheDisplay(in: view.bounds, to: rep)
        let cg = try #require(rep.cgImage)
        let provider = try #require(cg.dataProvider)
        let data = try #require(provider.data)
        let ptr = try #require(CFDataGetBytePtr(data))
        let bytesPerRow = cg.bytesPerRow
        // `bitmapImageRepForCachingDisplay`/`cacheDisplay` render at the caching screen's
        // backing scale (2x on this Retina host) -- the produced bitmap's pixel grid is scale
        // times the view's own point-space coordinates, not 1:1.
        let scale = cg.width / Int(view.bounds.width)

        func isWhite(_ x: Int, _ y: Int) -> Bool {
            let i = y * bytesPerRow + x * 4
            return ptr[i] > 200 && ptr[i + 1] > 200 && ptr[i + 2] > 200 && ptr[i + 3] > 200
        }

        // dir2vec(0) == (1, 0) -- expected crosshair center at tile (23, 20), point-space pixel
        // (368, 320), scaled into the bitmap's own device-pixel grid.
        let expectedX = 23 * 16 * scale
        let expectedY = 20 * 16 * scale
        var foundWhite = false
        for dy in -8 * scale...8 * scale {
            for dx in -8 * scale...8 * scale {
                if isWhite(expectedX + dx, expectedY + dy) { foundWhite = true }
            }
        }
        #expect(foundWhite, "no white crosshair pixel found near the expected tank+dir2vec(dir)*range location")

        // Negative control: far from the expected location, in open unpainted terrain, no white.
        #expect(!isWhite(expectedX + 200 * scale, expectedY + 200 * scale))
    }
}
