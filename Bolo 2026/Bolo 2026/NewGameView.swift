//
//  NewGameView.swift
//  Bolo 2026
//
//  Milestone B.1 -- the SwiftUI equivalent of the reference's `newGameWindow`/`newGameTabView`
//  (`Reference/c/Mac OS X/GSXBoloController.h:16-20`): a `TabView` with Host and Join tabs.
//
//  Milestone B.2 (D94 -- narrowed scope, see `HostGameView.swift`'s own header): the Host tab is
//  now real (map picker + settings form + a local-only `GameState`, zero `HostListener`/
//  `HostDgramListener`/`HostSessionTable` calls -- that's B.5's separate, not-yet-briefed scope).
//  Join stays a placeholder for B.3.
//

import BoloKit
import SwiftUI

struct NewGameView: View {
    /// Scaffolding for the B.1 -> B.2/B.3 gap (approved by Planner, D93-era Milestone B review):
    /// without this, Wave 7.3's fully-verified gameplay loop would be unreachable from the
    /// shipped UI until a real host/join path exists. **Remove this button** (and
    /// `onPlayDemoTapped`, and this doc note) as part of whichever of B.2/B.3 lands second's own
    /// completion report -- B.2 lands first in the existing order, so B.3 still owns this removal.
    let onPlayDemoTapped: () -> Void
    /// Milestone B.2 -- fires with the fully-assembled `GameState` (decoded map + form settings)
    /// once the host form's "Start Hosting" succeeds.
    let onStartHosting: (GameState) -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                HostGameView(onStartHosting: onStartHosting)
                    .tabItem { Text("Host") }
                JoinPlaceholderView()
                    .tabItem { Text("Join") }
            }
            .frame(minWidth: 420, minHeight: 280)

            Divider()

            // Scaffolding -- see `onPlayDemoTapped`'s doc comment above.
            Button("Play Demo", action: onPlayDemoTapped)
                .padding(8)
        }
    }
}

private struct JoinPlaceholderView: View {
    var body: some View {
        Text("Join a game -- coming in Milestone B.3")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    NewGameView(onPlayDemoTapped: {}, onStartHosting: { _ in })
}
