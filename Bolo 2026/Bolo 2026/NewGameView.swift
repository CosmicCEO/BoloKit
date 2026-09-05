//
//  NewGameView.swift
//  Bolo 2026
//
//  Milestone B.1 -- the SwiftUI equivalent of the reference's `newGameWindow`/`newGameTabView`
//  (`Reference/c/Mac OS X/GSXBoloController.h:16-20`): a `TabView` with Host and Join tabs. Both
//  tabs are placeholders in this sub-wave -- B.2 (host panel, map picker) and B.3 (join panel,
//  address/port/password, progress UI) fill them in; no `HostSession`/`JoinClient` call exists
//  anywhere in this file.
//

import SwiftUI

struct NewGameView: View {
    /// Scaffolding for the B.1 -> B.2/B.3 gap (approved by Planner, D93-era Milestone B review):
    /// without this, Wave 7.3's fully-verified gameplay loop would be unreachable from the
    /// shipped UI until a real host/join path exists. **Remove this button** (and
    /// `onPlayDemoTapped`, and this doc note) as part of whichever of B.2/B.3 lands second's own
    /// completion report -- by then a real path into `.playing` exists and this one is redundant.
    let onPlayDemoTapped: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            TabView {
                HostPlaceholderView()
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

private struct HostPlaceholderView: View {
    var body: some View {
        Text("Host a game -- coming in Milestone B.2")
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
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
    NewGameView(onPlayDemoTapped: {})
}
