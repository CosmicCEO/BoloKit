//
//  Bolo_2026App.swift
//  Bolo 2026
//
//  Created by Jerod Price on 9/4/26.
//

import AppKit
import SwiftUI

@main
struct Bolo_2026App: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        .commands {
            CommandGroup(after: .windowArrangement) {
                Button("Full Screen") {
                    NSApp.keyWindow?.toggleFullScreen(nil)
                }
                .keyboardShortcut("f", modifiers: [.control, .command])
            }
        }
        // Milestone C.5 (D120): SwiftUI's native preferences-window idiom -- opens on Cmd+,
        // automatically, no hand-rolled window/menu-item wiring needed.
        Settings {
            PreferencesView()
        }
    }
}
