//
//  AppIntents.swift
//  Bolo 2026
//
//  Issue #22 -- local App Intents for Shortcuts/Spotlight: "Host a Game" and "Join Last Host".
//  No Game Center, no `BoloKit`/`BoloNet` change (per the issue) -- both intents open the app
//  (`openAppWhenRun`) and hand off through `AppIntentRouter`, since an `AppIntent` is a fresh
//  struct the system constructs and has no `Binding` of its own into the live view hierarchy
//  the way `Bolo_2026App`'s `onOpenURL` does for `pendingMapURL`/`pendingJoinURL`.
//  `HostGameView`/`JoinGameView` observe the same singleton and drive their own existing
//  "Start Hosting"/"Join" entry points -- no separate host/join code path to drift from theirs.
//

import AppIntents
import Foundation

/// The one piece of mutable state an `AppIntent.perform()` can reach into the running app with.
/// `AppRootView` clears `pendingAction` on every "Quit to Menu" so a stale intent from a previous,
/// already-finished game can't silently fire the moment the user gets back to `NewGameView`.
@MainActor
@Observable
final class AppIntentRouter {
    static let shared = AppIntentRouter()

    enum PendingAction: Equatable {
        case hostGame
        case joinLastHost
    }

    var pendingAction: PendingAction?

    private init() {}
}

/// "Join Last Host"'s own target: the address/port `JoinGameView.startJoining()` last connected
/// with successfully, LAN or manual entry alike (recorded from `TCPSession.remoteHost`/
/// `remotePort` -- the resolved values, not whatever `addressText` happened to hold for a LAN
/// join). No password is ever persisted here, matching `BoloJoinURL.make`'s own precedent of
/// never carrying one -- a server that still requires one fails the same "Password rejected" way
/// a blank-password form submission already does.
nonisolated struct LastJoinedHost: Equatable, Sendable {
    var host: String
    var port: UInt16
}

enum LastJoinedHostStore {
    private static let hostKey = "GSLastJoinHostString"
    private static let portKey = "GSLastJoinPortNumber"

    static func record(_ record: LastJoinedHost) {
        let defaults = UserDefaults.standard
        defaults.set(record.host, forKey: hostKey)
        defaults.set(Int(record.port), forKey: portKey)
    }

    static func load() -> LastJoinedHost? {
        let defaults = UserDefaults.standard
        guard let host = defaults.string(forKey: hostKey), !host.isEmpty,
            let portNumber = defaults.object(forKey: portKey) as? Int,
            let port = UInt16(exactly: portNumber)
        else { return nil }
        return LastJoinedHost(host: host, port: port)
    }
}

struct HostGameIntent: AppIntent {
    static let title: LocalizedStringResource = "Host a Game"
    static let description = IntentDescription("Starts hosting a Bolo game with your default settings.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRouter.shared.pendingAction = .hostGame
        return .result()
    }
}

struct JoinLastHostIntent: AppIntent {
    static let title: LocalizedStringResource = "Join Last Host"
    static let description = IntentDescription("Rejoins the most recent Bolo host you connected to.")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        AppIntentRouter.shared.pendingAction = .joinLastHost
        return .result()
    }
}

struct BoloAppShortcutsProvider: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: HostGameIntent(),
            phrases: ["Host a game in \(.applicationName)"],
            shortTitle: "Host a Game",
            systemImageName: "antenna.radiowaves.left.and.right"
        )
        AppShortcut(
            intent: JoinLastHostIntent(),
            phrases: ["Join last host in \(.applicationName)"],
            shortTitle: "Join Last Host",
            systemImageName: "arrow.triangle.2.circlepath"
        )
    }
}
