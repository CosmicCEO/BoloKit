//
//  ContentView.swift
//  Bolo 2026
//

import BoloKit
import SwiftUI

/// Wave 7.2 demo. `GameRenderView` (own file, D82) needs *something* to render before 7.3's
/// tick loop exists to drive it -- this hand-builds a small terrain patch (not a real map
/// loader; that's future scope) plus one spawned local player, purely so the draw loop is
/// visually verifiable now. Wave 7.3 replaces `demoState` with real tick-driven `GameState`.
struct ContentView: View {
    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            GameRenderRepresentable(state: Self.demoState)
        }
        .frame(minWidth: 480, minHeight: 360)
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

        return GameState(terrain: terrain, players: [player], localPlayer: 0)
    }
}

#Preview {
    ContentView()
}
