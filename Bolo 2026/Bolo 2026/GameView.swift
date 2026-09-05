//
//  GameView.swift
//  Bolo 2026
//
//  Wave 7.3 (D88): closes the loop -- driven by a real `GameSession` tick loop, not a frozen
//  snapshot.
//
//  Milestone B.1: renamed from `ContentView` -- once `AppRootView` exists, this is one of two
//  screens, not the app's whole root content, so the SwiftUI-template name no longer described
//  its role. Gained an `onQuitToMenu` exit path so the shell's round trip (matching
//  `GSXBoloController`'s own new-game-window <-> bolo-window shape) works in both directions.
//
//  Milestone B.2: `initialState` is now caller-supplied rather than a hardcoded demo terrain --
//  either `AppRootView.demoState` (the B.1 "Play Demo" scaffolding) or a real map decoded by
//  `HostGameView`. This view has no opinion on where its state came from.
//

import BoloKit
import SwiftUI

struct GameView: View {
    let initialState: GameState
    let onQuitToMenu: () -> Void

    @State private var session: GameSession

    init(initialState: GameState, onQuitToMenu: @escaping () -> Void) {
        self.initialState = initialState
        self.onQuitToMenu = onQuitToMenu
        guard let tiles = loadSheetImage(named: "Tiles"),
            let sprites = loadSheetImage(named: "Sprites")
        else {
            fatalError("Tiles.png/Sprites.png missing from the bundle -- D72's Run Script phase should guarantee this")
        }
        _session = State(
            initialValue: GameSession(initialState: initialState, tilesImage: tiles, spritesImage: sprites)
        )
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            GameRenderRepresentable(session: session)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { session.start() }
        .onDisappear { session.stop() }
        .safeAreaInset(edge: .top) {
            HStack {
                Spacer()
                Button("Quit to Menu") {
                    session.stop()
                    onQuitToMenu()
                }
            }
            .padding(8)
        }
    }
}

#Preview {
    GameView(initialState: AppRootView.demoState, onQuitToMenu: {})
}
