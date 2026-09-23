//
//  GameRenderViewTests.swift
//  Bolo 2026Tests
//

import AppKit
import CoreGraphics
import Testing
import BoloKit

@testable import Bolo_2026

struct GameRenderViewTests {

    @Test @MainActor func battleMapIsASingleImageAccessibilityElement() throws {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        let view = GameRenderView(tilesImage: tiles, spritesImage: sprites)
        #expect(view.isAccessibilityElement())
        #expect(view.accessibilityRole() == .image)
        #expect(view.accessibilityLabel() == HUDAccessibility.battleMap)
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

    // MARK: - Issue #75: hidden-mines render (guest must not go all-black)

    /// A join client (and the solo path) never has a `FogState` -- the host already redacted what
    /// it was sent -- so with Hidden Mines on it must draw the received terrain, not fail closed.
    @Test @MainActor func hiddenMinesWithNoFogStateRendersReceivedTerrainNotAllUnknown() {
        var state = GameState()
        state.hiddenMines = true
        state.terrain[12, 12] = .forest
        let grid = GameRenderView.resolvedTileGrid(for: state, fogState: nil)
        #expect(grid.storage == displayTileGrid(for: state).storage)
        #expect(grid[12, 12] != Tile.unknown.rawValue)
    }

    /// The host's first frame renders before `HostGameEngine` has populated any `FogState`; the
    /// host call sites hand in an empty `FogState()` so that frame stays fully fogged.
    @Test @MainActor func hiddenMinesWithAnEmptyFogStateStaysAllUnknown() {
        var state = GameState()
        state.hiddenMines = true
        state.terrain[12, 12] = .minedGrass
        let grid = GameRenderView.resolvedTileGrid(for: state, fogState: FogState())
        #expect(grid[12, 12] == Tile.unknown.rawValue)
    }

    @Test @MainActor func hiddenMinesOffIgnoresAnyFogState() {
        var state = GameState()
        state.hiddenMines = false
        state.terrain[12, 12] = .minedGrass
        let grid = GameRenderView.resolvedTileGrid(for: state, fogState: FogState())
        #expect(grid.storage == displayTileGrid(for: state).storage)
    }
}

// MARK: - Issue #89: reuse the tile grid when nothing it depends on changed

/// A realistic mid-game snapshot: a land patch, 16 pills and 16 bases across three owners, two
/// allied-capable players, and a 29x29 visible fog area.
private func makeGridState(hiddenMines: Bool) -> (GameState, FogState) {
    var state = GameState()
    state.hiddenMines = hiddenMines
    var players = (0..<maxPlayers).map { _ in PlayerState() }
    players[0].used = true
    players[0].alliance = 1
    players[1].used = true
    players[1].alliance = 2
    state.players = players
    state.localPlayer = 0
    for y in 60..<200 { for x in 60..<200 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
    var pills: [Pill] = []
    var bases: [Base] = []
    for i in 0..<16 {
        let px = UInt8(70 + i * 5)
        let py = UInt8(80 + i * 3)
        pills.append(Pill(x: px, y: py, armour: 15, owner: UInt8(i % 3), speed: 100, counter: 0))
        let bx = UInt8(65 + i * 6)
        let by = UInt8(150 - i * 2)
        bases.append(Base(x: bx, y: by, armour: 90, owner: UInt8(i % 3), shells: 90, mines: 90))
    }
    state.pills = pills
    state.bases = bases
    var fog = FogState()
    for y in 90..<119 { for x in 90..<119 { fog.fog[y * 256 + x] = 1 } }
    return (state, fog)
}

struct TileGridCacheTests {
    @MainActor private func makeView() throws -> GameRenderView {
        let tiles = try #require(loadSheetImage(named: "Tiles"))
        let sprites = try #require(loadSheetImage(named: "Sprites"))
        return GameRenderView(tilesImage: tiles, spritesImage: sprites)
    }

    /// Renders `before`, then `after`; returns how many times the tile grid was actually rebuilt.
    @MainActor private func rebuilds(
        hiddenMines: Bool = false,
        fogBefore: Bool = false, fogAfter: Bool = false,
        mutate: (inout GameState, inout FogState) -> Void
    ) throws -> Int {
        let view = try makeView()
        var (state, fog) = makeGridState(hiddenMines: hiddenMines)
        view.render(state, fogState: fogBefore ? fog : nil)
        mutate(&state, &fog)
        view.render(state, fogState: fogAfter ? fog : nil)
        return view.tileGridRebuildCount
    }

    @Test @MainActor func identicalRendersBuildTheGridOnce() throws {
        #expect(try rebuilds { _, _ in } == 1, "the second identical render must reuse the grid")
    }

    @Test @MainActor func unchangedRenderReusesTheGridWithFogToo() throws {
        #expect(try rebuilds(hiddenMines: true, fogBefore: true, fogAfter: true) { _, _ in } == 1)
    }

    @Test @MainActor func fieldsTheGridDoesNotReadNeverForceARebuild() throws {
        let count = try rebuilds { state, _ in
            state.ticks += 1
            state.pills[0].counter = 7
            state.pills[0].speed = 50
            state.bases[0].shells = 3
            state.players[0].tank = Vec2f(x: 90.5, y: 90.5)
        }
        #expect(count == 1, "per-tick churn in fields the grid ignores must not rebuild it")
    }

    @Test @MainActor func aTerrainChangeRebuilds() throws {
        #expect(try rebuilds { state, _ in state.terrain[100, 100] = .minedGrass } == 2)
    }

    @Test @MainActor func aPillOwnerChangeRebuilds() throws {
        #expect(try rebuilds { state, _ in state.pills[0].owner = 5 } == 2)
    }

    @Test @MainActor func aPillArmourChangeRebuilds() throws {
        #expect(try rebuilds { state, _ in state.pills[0].armour = 3 } == 2)
    }

    @Test @MainActor func aPillMovingRebuilds() throws {
        #expect(try rebuilds { state, _ in state.pills[0].x += 1 } == 2)
    }

    @Test @MainActor func aBaseOwnerChangeRebuilds() throws {
        #expect(try rebuilds { state, _ in state.bases[0].owner = 5 } == 2)
    }

    @Test @MainActor func aBaseMovingRebuilds() throws {
        #expect(try rebuilds { state, _ in state.bases[0].y += 1 } == 2)
    }

    @Test @MainActor func anAllianceChangeRebuilds() throws {
        #expect(try rebuilds { state, _ in state.players[0].alliance |= 2 } == 2)
    }

    @Test @MainActor func aPlayerBecomingUsedRebuilds() throws {
        #expect(try rebuilds { state, _ in state.players[2].used = true } == 2)
    }

    @Test @MainActor func theLocalPlayerChangingRebuilds() throws {
        #expect(try rebuilds { state, _ in state.localPlayer = 1 } == 2)
    }

    @Test @MainActor func hiddenMinesChangingRebuilds() throws {
        #expect(try rebuilds(hiddenMines: false, fogBefore: true, fogAfter: true) { state, _ in state.hiddenMines = true } == 2)
    }

    @Test @MainActor func aFogRefcountChangeRebuilds() throws {
        #expect(try rebuilds(hiddenMines: true, fogBefore: true, fogAfter: true) { _, fog in fog.fog[95 * 256 + 95] = 0 } == 2)
    }

    @Test @MainActor func aSeenTileChangeRebuilds() throws {
        #expect(try rebuilds(hiddenMines: true, fogBefore: true, fogAfter: true) { _, fog in fog.seenTiles[10 * 256 + 10] = .minedGrass } == 2)
    }

    @Test @MainActor func gainingAFogStateRebuilds() throws {
        #expect(try rebuilds(hiddenMines: true, fogBefore: false, fogAfter: true) { _, _ in } == 2)
    }

    @Test @MainActor func losingAFogStateRebuilds() throws {
        #expect(try rebuilds(hiddenMines: true, fogBefore: true, fogAfter: false) { _, _ in } == 2)
    }
}
