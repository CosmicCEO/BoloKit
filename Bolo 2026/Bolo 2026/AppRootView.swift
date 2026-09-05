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

import SwiftUI

enum AppScreen: Equatable {
    case newGame
    case playing
}

struct AppRootView: View {
    @State private var screen: AppScreen = .newGame

    var body: some View {
        switch screen {
        case .newGame:
            NewGameView(onPlayDemoTapped: { screen = .playing })
        case .playing:
            GameView(onQuitToMenu: { screen = .newGame })
        }
    }
}

#Preview {
    AppRootView()
}
