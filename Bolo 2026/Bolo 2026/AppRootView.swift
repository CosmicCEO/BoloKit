//
//  AppRootView.swift
//  Bolo 2026
//
//  Milestone B.1 -- the port's equivalent of the reference's round trip between `newGameWindow`
//  and `boloWindow` (`GSXBoloController.m:740-760`'s disconnect path orders `boloWindow` out and
//  calls `newGame:` again). A single window with state-driven content, not the reference's three
//  literal `NSWindow`s -- nothing in the reference's own behavior depends on separate windows,
//  and one window avoids this project's first multi-window lifecycle problem under Swift 6 for a
//  mechanism the reference doesn't functionally require (same footing as D81's rendering-
//  mechanism disclosure; approved by Planner for B.1).
//
//  Milestone B.3: both `.playing` paths now come from a real host or join, per Planner's
//  B.1-review ruling -- the "Play Demo" scaffolding button is removed (B.3 lands second, per the
//  existing B.2-then-B.3 order, so B.3 owns this).
//

import BoloKit
import SwiftUI

enum AppScreen {
    case newGame
    case playing(GameState)
}

struct AppRootView: View {
    @State private var screen: AppScreen = .newGame

    var body: some View {
        switch screen {
        case .newGame:
            NewGameView(
                onStartHosting: { state in screen = .playing(state) },
                onJoinedGame: { state in screen = .playing(state) }
            )
        case .playing(let state):
            GameView(initialState: state, onQuitToMenu: { screen = .newGame })
        }
    }

    /// Preview-only fixture now (the B.1 "Play Demo" button that reached this in production is
    /// gone as of B.3) -- kept so `GameView`'s own `#Preview` still has something real to show.
    static var demoState: GameState {
        var terrain = TerrainGrid.mapDefault()

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

        return GameState(
            terrain: terrain, starts: [Start(x: 130, y: 130, dir: 0)],
            players: [player], localPlayer: 0
        )
    }
}

#Preview {
    AppRootView()
}
