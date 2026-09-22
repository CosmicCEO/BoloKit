//
//  MetalTileRendererTests.swift
//  Bolo 2026Tests
//
//  v1.6.0 (#25) increment 4: pixel-diff parity between `MetalTileRenderer` and
//  `CGContextTileRenderer`, using the harness `RenderParityHarness.swift` established.
//  `MetalTileRenderer.draw(_:ctx:dirtyRect:)` still calls `view.drawSprites(ctx)` with the
//  same CPU code `CGContextTileRenderer` does (only terrain moved to Metal this increment),
//  so any diff these tests catch isolates to the terrain path specifically.

import AppKit
import Testing
import BoloKit

@testable import Bolo_2026

struct MetalTileRendererTests {

    /// Varied terrain (several `Terrain` cases, including one mined tile) inside the capture
    /// rect below -- exercises the sheet-index lookup, the mine overlay's second instance, and
    /// plain-sea rendering all in one small area, not just a single uniform tile type.
    private func variedTerrainScene() -> GameState {
        var state = GameState()
        for y in 30..<40 {
            for x in 30..<40 {
                let terrain: Terrain
                switch (x + y) % 4 {
                case 0: terrain = .grass0
                case 1: terrain = .forest
                case 2: terrain = .road
                default: terrain = .sea
                }
                state.terrain[x, y] = terrain
            }
        }
        state.terrain[33, 33] = .minedGrass
        state.hiddenMines = false // mine glyph always drawn regardless of fog in this scene
        return state
    }

    @Test @MainActor func metalTerrainMatchesCGContextTerrainPixelForPixel() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let metalRenderer = try #require(MetalTileRenderer(), "Metal unavailable on this host -- skip rather than false-fail")

        let cpuView = GameRenderView(tilesImage: tiles, spritesImage: sprites, renderer: CGContextTileRenderer())
        let metalView = GameRenderView(tilesImage: tiles, spritesImage: sprites, renderer: metalRenderer)

        let state = variedTerrainScene()
        cpuView.render(state)
        metalView.render(state)

        // Covers tiles (30,30)-(39,39) at 16pt/tile: pixel (480,480) to (640,640).
        let captureRect = NSRect(x: 480, y: 480, width: 160, height: 160)
        let cpuRender = try renderRGBA(cpuView, rect: captureRect)
        let metalRender = try renderRGBA(metalView, rect: captureRect)
        let diff = try #require(pixelDiffCount(cpuRender, metalRender))
        #expect(diff == 0, "Metal terrain render differs from the CGContext render at \(diff) pixels")
    }
}
