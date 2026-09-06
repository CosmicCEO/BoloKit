//
//  Bolo_2026App.swift
//  Bolo 2026
//
//  Created by Jerod Price on 9/4/26.
//

import SwiftUI

@main
struct Bolo_2026App: App {
    var body: some Scene {
        WindowGroup {
            AppRootView()
        }
        // Milestone C.5 (D120): SwiftUI's native preferences-window idiom -- opens on Cmd+,
        // automatically, no hand-rolled window/menu-item wiring needed.
        Settings {
            PreferencesView()
        }
    }
}
