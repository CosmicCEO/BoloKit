//
//  VisibilityParityTests.swift
//  Bolo 2026Tests
//
//  #153 (v1.6.6 -- Visibility Parity): `visFraction`'s `useForestTerm: true` path now always
//  calls `calcVis`, even with no `fogState` -- the join/solo paths, and the host with
//  `hiddenMines` off, never had one (`GameRenderView.render(_:fogState:)`'s own doc comment).
//  Reuses `RenderParityHarness.swift`'s offscreen pixel-diff harness to confirm the render
//  effect actually happens, not just that `calcVis` returns the right number in isolation
//  (already covered by `FogDifferentialTests.swift`'s `nil`-`fogState` unit tests).

import AppKit
import CoreGraphics
import Testing
import BoloKit

@testable import Bolo_2026

private func twoPlayerForestScene(observerTank: Vec2f, enemyForestCenter: (x: Int32, y: Int32)) -> GameState {
    var state = GameState()
    var observer = PlayerState()
    observer.used = true
    observer.connected = true
    observer.dead = false
    observer.tank = observerTank

    var enemy = PlayerState()
    enemy.used = true
    enemy.connected = true
    enemy.dead = false
    enemy.tank = Vec2f(x: Float(enemyForestCenter.x) + 0.5, y: Float(enemyForestCenter.y) + 0.5)

    state.players = [observer, enemy]
    state.localPlayer = 0
    state.hiddenMines = false // the default -- concealment must not depend on this

    for dy: Int32 in -1...1 {
        for dx: Int32 in -1...1 {
            state.terrain[Int(enemyForestCenter.x + dx), Int(enemyForestCenter.y + dy)] = .forest
        }
    }
    return state
}

struct VisibilityParityTests {

    /// The actual reported symptom: with `hiddenMines` off and no `fogState` (the join/solo
    /// default -- `render(_:fogState:)` is called with no second argument at all), an enemy
    /// tank buried in forest, far from the observer's own tank, must render differently than
    /// the same tank fully in the open. If `visFraction` still short-circuited to `1.0` here,
    /// these two renders would be pixel-identical.
    @Test @MainActor func forestConcealedEnemyTankRendersDifferentlyThanOneInTheOpenWithNoFogState() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let viewConcealed = GameRenderView(tilesImage: tiles, spritesImage: sprites)
        let viewOpen = GameRenderView(tilesImage: tiles, spritesImage: sprites)

        let concealedState = twoPlayerForestScene(observerTank: Vec2f(x: 10, y: 10), enemyForestCenter: (x: 100, y: 100))
        var openState = concealedState
        openState.terrain = GameState().terrain // no forest anywhere

        viewConcealed.render(concealedState) // no fogState argument -- matches join/solo call sites
        viewOpen.render(openState)

        let captureRect = NSRect(x: 1584, y: 1584, width: 96, height: 96) // around tile (100, 100), tile = 16pt
        let concealedPixels = try renderRGBA(viewConcealed, rect: captureRect)
        let openPixels = try renderRGBA(viewOpen, rect: captureRect)
        let diff = try #require(pixelDiffCount(concealedPixels, openPixels))
        #expect(diff > 0, "a forest-concealed enemy tank must render differently than one in the open, even with hiddenMines off and no fogState")
    }

    /// Graduated, not binary: the same forest-buried enemy tank must render differently
    /// depending on the observer's own distance to it -- fully concealed far away, but the
    /// oracle's own 2-3 unit distance floor kicks in once the observer is right next to it
    /// (never fully invisible up close, matching Jerod's reported "still only slightly visible
    /// when sitting side by side").
    @Test @MainActor func forestConcealedEnemyTankRendersMoreVisiblyTheCloserTheObserverIs() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let viewFar = GameRenderView(tilesImage: tiles, spritesImage: sprites)
        let viewClose = GameRenderView(tilesImage: tiles, spritesImage: sprites)

        let farState = twoPlayerForestScene(observerTank: Vec2f(x: 10, y: 10), enemyForestCenter: (x: 100, y: 100))
        // 2.0 tiles from the enemy tank (100.5, 100.5) -- within the oracle's dist<=2.0 floor,
        // but far enough on screen (2 tiles = 32pt, sprites are ~16pt) not to overdraw it with
        // the observer's own always-fraction-1.0 tank sprite and contaminate the pixel diff.
        let closeState = twoPlayerForestScene(observerTank: Vec2f(x: 98.5, y: 100.5), enemyForestCenter: (x: 100, y: 100))

        viewFar.render(farState)
        viewClose.render(closeState)

        // Tight around the enemy tank's own sprite rect only (drawn at (100.5, 100.5) -> pixel
        // origin (1600, 1600), 16pt tile) -- excludes the observer's own tank sprite at tile 98
        // (pixel origin ~1568), which would otherwise overdraw and contaminate the diff if the
        // capture rect were wider.
        let captureRect = NSRect(x: 1596, y: 1596, width: 24, height: 24)
        let farPixels = try renderRGBA(viewFar, rect: captureRect)
        let closePixels = try renderRGBA(viewClose, rect: captureRect)
        let diff = try #require(pixelDiffCount(farPixels, closePixels))
        #expect(diff > 0, "concealment must be graduated by distance, not a fixed reduction regardless of how close the observer is")
    }
}
