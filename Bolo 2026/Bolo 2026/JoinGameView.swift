//
//  JoinGameView.swift
//  Bolo 2026
//
//  Milestone B.3 -- address/port/password form + progress UI, calling the now-extended
//  `joinClient` (progress callback + refined network-error taxonomy, see `JoinClient.swift`'s
//  own header for what's real vs. collapsed) and, on success, `applyBoloPreamble`
//  (`JoinClientApply.swift`, Wave 6.4a/D45-D46) -- already fully built and tested, and does
//  everything B.2's `HostGameView` had to hand-assemble manually for hosting: assigns
//  `localPlayer`, decodes the map, applies domination/hidden-mines/base-control settings, inits
//  every player slot, and spawns the local tank. This view's own job is thin by comparison.
//
//  This project's first `async` network call initiated directly from a SwiftUI view action --
//  `Bolo 2026` builds with `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor`, so this view's own
//  `@State` is already main-actor-isolated; wrapping the call in `Task { @MainActor in ... }`
//  and marking `onProgress` `@Sendable` (already required by `joinClient`'s own signature) is
//  what lets its background-thread-originating callback safely touch that state.
//
//  Error alert text matches the reference's own per-status strings
//  (`Reference/c/Mac OS X/GSXBoloController.m:2852-3181`, one exact quote per case below) where a
//  reference case exists; `.connectionClosedEarly`/`.malformedPreamble` have no reference
//  equivalent (framing catch-alls specific to this port's own transport, not the reference's
//  wire protocol) and get plain descriptive text instead.
//

import BoloKit
import BoloNet
import SwiftUI

struct JoinGameView: View {
    let onJoinedGame: (GameState) -> Void

    @State private var addressText = "127.0.0.1"
    @State private var portText = "50000"  // GSJoinPortNumber's own shipped default
    @State private var passwordText = ""
    @State private var nameText = "Newbie"  // GSPlayerNameString's own shipped default
    @State private var isJoining = false
    @State private var progress: JoinProgress?
    @State private var errorMessage: String?

    var body: some View {
        Form {
            Section("Server") {
                TextField("Address", text: $addressText)
                TextField("Port", text: $portText)
                SecureField("Password (if required)", text: $passwordText)
                TextField("Player Name", text: $nameText)
            }

            if isJoining {
                HStack {
                    ProgressView()
                    Text(progressLabel)
                }
            }

            if let errorMessage {
                Text(errorMessage).foregroundStyle(.red)
            }

            Button("Join", action: startJoining)
                .disabled(isJoining || UInt16(portText) == nil)
        }
        .padding()
    }

    private var progressLabel: String {
        switch progress {
        case nil: return ""
        case .connecting: return "Connecting…"
        case .sendingJoin: return "Sending join request…"
        case .receivingPreamble: return "Receiving game info…"
        case .receivingMap: return "Receiving map…"
        case .success: return "Joined."
        }
    }

    private func startJoining() {
        guard let port = UInt16(portText) else { return }
        errorMessage = nil
        isJoining = true
        progress = nil

        Task { @MainActor in
            do {
                let result = try await joinClient(
                    host: addressText, port: port, name: nameText, pass: passwordText,
                    onProgress: { newProgress in
                        Task { @MainActor in progress = newProgress }
                    }
                )

                var state = GameState()
                guard applyBoloPreamble(result.preamble, mapData: result.mapData, state: &state) else {
                    isJoining = false
                    errorMessage = "Incompatible Map Version"
                    return
                }

                isJoining = false
                onJoinedGame(state)
            } catch let error as JoinClientError {
                isJoining = false
                errorMessage = Self.message(for: error)
            } catch {
                isJoining = false
                errorMessage = "\(error)"
            }
        }
    }

    private static func message(for error: JoinClientError) -> String {
        switch error {
        case .badVersion: return "Server version doesn't match."
        case .disallow: return "Host is not allowing new players in the game."
        case .badPassword: return "Password rejected."
        case .serverFull: return "Server is full."
        case .serverTimeLimitReached: return "Time limit reached on server."
        case .bannedPlayer: return "Host has banned you from the game."
        case .serverProtocolError: return "Protocol error."
        case .connectionReset: return "Connection Reset by Peer."
        case .timedOut: return "Connection establishment timed out without establishing a connection."
        case .connectionRefused: return "The attempt to connect was forcefully rejected."
        case .connectionClosedEarly: return "The connection closed before the join finished."
        case .malformedPreamble: return "The server sent an unreadable response."
        }
    }
}

#Preview {
    JoinGameView(onJoinedGame: { _ in })
}
