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
    /// once the join form successfully completes a handshake. Carries the live `TCPSession`/
    /// `UDPSession` pair as of Milestone B.8 (D113), not a bare `GameState`.
    let onJoinedGame: (TCPSession, UDPSession, GameState) -> Void
    @Binding var pendingMapURL: URL?
    @Binding var pendingJoinURL: URL?
    @State private var tab: Tab = .host

    private enum Tab: Hashable {
        case host, join
    }

    init(
        onStartHosting: @escaping (HostGameEngine) -> Void,
        onStartHostingLocalOnly: @escaping (GameState) -> Void,
        onJoinedGame: @escaping (TCPSession, UDPSession, GameState) -> Void,
        pendingMapURL: Binding<URL?> = .constant(nil),
        pendingJoinURL: Binding<URL?> = .constant(nil)
    ) {
        self.onStartHosting = onStartHosting
        self.onStartHostingLocalOnly = onStartHostingLocalOnly
        self.onJoinedGame = onJoinedGame
        _pendingMapURL = pendingMapURL
        _pendingJoinURL = pendingJoinURL
    }

    var body: some View {
        TabView(selection: $tab) {
            HostGameView(
                onStartHosting: onStartHosting,
                onStartHostingLocalOnly: onStartHostingLocalOnly,
                pendingMapURL: $pendingMapURL
            )
                .tabItem { Text("Host") }
                .tag(Tab.host)
            JoinGameView(onJoinedGame: onJoinedGame, pendingJoinURL: $pendingJoinURL)
                .tabItem { Text("Join") }
                .tag(Tab.join)
        }
        .frame(minWidth: 420, minHeight: 280)
        .onAppear {
            if pendingJoinURL != nil { tab = .join }
            switchTabForPendingIntent()
        }
        .onChange(of: pendingJoinURL) { _, url in
            if url != nil { tab = .join }
        }
        .onChange(of: AppIntentRouter.shared.pendingAction) { _, _ in switchTabForPendingIntent() }
    }

    /// Issue #22: switches to the tab a pending `HostGameIntent`/`JoinLastHostIntent` targets
    /// before that tab's own view consumes and clears it -- same reasoning as `pendingJoinURL`'s
    /// own tab-switch above: a form that isn't on screen has no visible effect once it acts.
    /// Doesn't clear `pendingAction` itself -- `HostGameView`/`JoinGameView` own that.
    private func switchTabForPendingIntent() {
        switch AppIntentRouter.shared.pendingAction {
        case .hostGame: tab = .host
        case .joinLastHost: tab = .join
        case nil: break
        }
    }
}

#Preview {
    NewGameView(
        onStartHosting: { (_: HostGameEngine) in }, onStartHostingLocalOnly: { _ in },
        onJoinedGame: { (_: TCPSession, _: UDPSession, _: GameState) in }
    )
}
