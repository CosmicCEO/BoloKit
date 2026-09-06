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
//
//  Milestone B.3: the Join tab is now real too (`JoinGameView.swift`). Both tabs now provide a
//  real path into `.playing` -- per Planner's ruling at B.1's review, the "Play Demo" scaffolding
//  button is removed here, in whichever of B.2/B.3 landed second (B.3, since B.2 landed first in
//  the existing order).
//

import BoloKit
import BoloNet
import SwiftUI

struct NewGameView: View {
    /// Milestone B.2 -- fires once the host form's "Start Hosting" succeeds. Carries a real,
    /// already-`start()`ed `HostGameEngine` as of Milestone B.7 (D108), not a bare `GameState`.
    let onStartHosting: (HostGameEngine) -> Void
    /// Milestone B.7 (D109) -- fires instead of `onStartHosting` when the real listener couldn't
    /// be constructed (see `HostGameView.swift`'s own header). Carries the same fully-assembled
    /// `GameState` `onStartHosting` would have.
    let onStartHostingLocalOnly: (GameState) -> Void
    /// Milestone B.3 -- fires with the fully-assembled `GameState` (`applyBoloPreamble`'s result)
    /// once the join form successfully completes a handshake.
    let onJoinedGame: (GameState) -> Void

    var body: some View {
        TabView {
            HostGameView(onStartHosting: onStartHosting, onStartHostingLocalOnly: onStartHostingLocalOnly)
                .tabItem { Text("Host") }
            JoinGameView(onJoinedGame: onJoinedGame)
                .tabItem { Text("Join") }
        }
        .frame(minWidth: 420, minHeight: 280)
    }
}

#Preview {
    NewGameView(onStartHosting: { (_: HostGameEngine) in }, onStartHostingLocalOnly: { _ in }, onJoinedGame: { _ in })
}
