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

    /// A full scene: terrain plus a local tank, a connected enemy tank (off-centerline
    /// heading), a builder, an in-flight shell, and an explosion -- exercises every draw call
    /// `drawSpritesViaMetal` routes through `spriteCellProvider`, not just terrain.
    private func fullScene() -> GameState {
        var state = variedTerrainScene()

        var local = PlayerState()
        local.used = true
        local.connected = true
        local.dead = false
        local.tank = Vec2f(x: 32, y: 32)
        local.dir = 0
        local.builder = Vec2f(x: 34, y: 34)
        local.builderStatus = .ready

        var enemy = PlayerState()
        enemy.used = true
        enemy.connected = true
        enemy.dead = false
        enemy.tank = Vec2f(x: 36, y: 36)
        enemy.dir = 2 * (kPif / 8.0)
        enemy.alliance = 1 << 5 // distinct bit from local's default 0 -- not mutually allied
        enemy.shells = [Shell(point: Vec2f(x: 35, y: 32), dir: 1 * (kPif / 8.0), range: 4, owner: 1, boat: false, pill: false)]
        enemy.explosions = [Explosion(point: Vec2f(x: 38, y: 38), counter: 2)]

        state.players = [local, enemy]
        state.localPlayer = 0
        return state
    }

    @Test @MainActor func metalFullSceneMatchesCGContextPixelForPixel() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let metalRenderer = try #require(MetalTileRenderer(), "Metal unavailable on this host -- skip rather than false-fail")

        let cpuView = GameRenderView(tilesImage: tiles, spritesImage: sprites, renderer: CGContextTileRenderer())
        let metalView = GameRenderView(tilesImage: tiles, spritesImage: sprites, renderer: metalRenderer)

        let state = fullScene()
        cpuView.render(state)
        metalView.render(state)

        // Covers tiles (30,30)-(39,39) plus a margin for the shell/tank/explosion positions
        // above, all within tile range 30-39: pixel (480,480) to (656,656).
        let captureRect = NSRect(x: 480, y: 480, width: 176, height: 176)
        let cpuRender = try renderRGBA(cpuView, rect: captureRect)
        let metalRender = try renderRGBA(metalView, rect: captureRect)
        let diff = try #require(pixelDiffCount(cpuRender, metalRender))
        #expect(diff == 0, "Metal full-scene render differs from the CGContext render at \(diff) pixels")
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
