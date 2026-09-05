//
//  ContentView.swift
//  Bolo 2026
//

import BoloKit
import SwiftUI

/// Wave 7.3 (D88): closes the loop -- the same hand-built terrain patch Wave 7.2's demo used
/// (not a real map loader; `decodeBMap` exists but no `.map` asset exists anywhere in this repo
/// to feed it, and building one is separate scope from input/tick work) is now driven by a real
/// `GameSession` tick loop instead of a frozen snapshot.
struct ContentView: View {
    @State private var session = ContentView.makeSession()

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            GameRenderRepresentable(session: session)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
    }

    private static func makeSession() -> GameSession {
        guard let tiles = loadSheetImage(named: "Tiles"),
            let sprites = loadSheetImage(named: "Sprites")
        else {
            fatalError("Tiles.png/Sprites.png missing from the bundle -- D72's Run Script phase should guarantee this")
        }
        return GameSession(initialState: Self.demoState, tilesImage: tiles, spritesImage: sprites)
    }

    private static var demoState: GameState {
        var terrain = TerrainGrid.mapDefault()

        // Exercises autotiling variety (grass/road/forest connectivity, already validated by
        // Wave 7.0's own tests) without a real map loader.
        for y in 100..<160 {
            for x in 100..<160 {
                terrain.storage[y * 256 + x] = Terrain.grass0.rawValue
            }
        }
        for x in 100..<160 {
            terrain.storage[128 * 256 + x] = Terrain.road.rawValue
        }
        for y in 100..<120 {
            for x in 100..<120 {
                terrain.storage[y * 256 + x] = Terrain.forest.rawValue
            }
        }

        var player = PlayerState()
        player.tank = Vec2f(x: 130, y: 130)
        player.dir = 0
        player.dead = false
        player.connected = true
        player.used = true

        // D88 §4's corollary: `spawn(state:)` is now really wired (from `tankMoveTick`) and
        // indexes `state.starts` unconditionally -- must be nonempty before the first death,
        // unlike Wave 7.2's demo, which never needed a respawn to actually succeed.
        return GameState(
            terrain: terrain, starts: [Start(x: 130, y: 130, dir: 0)],
            players: [player], localPlayer: 0
        )
    }
}

#Preview {
    ContentView()
}
