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
//  Milestone B.6 (D105 Part 2, split from B.4): tracker browse list, calling the already-shipped
//  `listTrackerGames` (`TrackerBrowser.swift`, Wave 6.5) -- fully real networking, unlike
//  `HostGameView`'s still-local-only hosting (D94), since this view's own join path is already a
//  real remote connection. Default hostname matches the reference's shipped
//  `GSTrackerString` (`Reference/c/en.lproj/DefaultPreferences.plist`). `TrackerHostList.addr` is
//  kept opaque network-byte-order per that struct's own doc comment -- formatted here into a
//  dotted-quad purely for display, not reused as a real value anywhere else.
//
//  Milestone B.8 (D113): `startJoining()` now calls `TCPSession.join` directly instead of
//  `joinClient` -- the plain `joinClient` wrapper closes its connection before returning (see its
//  own doc comment), but B.8's live post-handshake network loop needs that exact same accepted
//  connection kept open, not a fresh reconnect the host would treat as an unauthenticated new
//  join attempt. A second, freshly-dialed `UDPSession` on the same host/port completes the pair
//  (matching `HostDgramListener.swift`'s own precedent: the dgram channel binds the same port the
//  TCP side resolved, with no handshake of its own -- the host registers it on first receipt).
//  `onJoinedGame` now hands both live sessions up alongside the decoded state.

import BoloKit
import BoloNet
import SwiftUI

struct JoinGameView: View {
    let onJoinedGame: (TCPSession, UDPSession, GameState) -> Void
    @Binding var pendingJoinURL: URL?

    @State private var addressText = "127.0.0.1"
    @State private var portText = "50000"  // GSJoinPortNumber's own shipped default
    @State private var passwordText = ""
    // #157: was a plain `@State` seeded once from "GSPlayerNameString" in `init` and never
    // written back, so edits made here never persisted. `@AppStorage` reads/writes the same
    // store live, matching `PreferencesView`'s and `HostGameView`'s own player-name field.
    @AppStorage("GSPlayerNameString") private var nameText = "Newbie"
    @State private var isJoining = false
    @State private var progress: JoinProgress?
    @State private var errorMessage: String?

    @State private var trackerHostnameText = "tracker.xbolo.org"
    @State private var isBrowsingTracker = false
    @State private var trackerGames: [TrackerHostList] = []
    @State private var trackerErrorMessage: String?

    @State private var lanBrowser: BonjourBrowser?
    @State private var lanGames: [LANGame] = []
    @State private var selectedLANGame: LANGame?

    /// Milestone C.5 (D120): `trackerHostnameText`'s initial value reads the same
    /// `"GSTrackerString"` key `PreferencesView`'s `@AppStorage` writes to (both back onto
    /// `UserDefaults.standard`, the same store) -- `portText` deliberately does NOT read
    /// `"GSHostPortNumber"` here, since that preference is the *host's own* default listening port
    /// (`HostGameView`'s own field), not this view's join-target port, which the reference's own
    /// `GSJoinPortNumber` keeps as a genuinely separate default (also 50000, but a different key,
    /// never wired to a preference in this v1 slice). `nameText` needs no seeding here -- #157
    /// switched it to `@AppStorage("GSPlayerNameString")` directly, same store, live.
    init(
        onJoinedGame: @escaping (TCPSession, UDPSession, GameState) -> Void,
        pendingJoinURL: Binding<URL?> = .constant(nil)
    ) {
        self.onJoinedGame = onJoinedGame
        _pendingJoinURL = pendingJoinURL
        let storedTracker = UserDefaults.standard.string(forKey: "GSTrackerString")
        _trackerHostnameText = State(initialValue: storedTracker ?? "tracker.xbolo.org")
    }

    var body: some View {
        Form {
            Section("Server") {
                TextField("Address", text: $addressText)
                TextField("Port", text: $portText)
                SecureField("Password (if required)", text: $passwordText)
                TextField("Player Name", text: $nameText)
            }

            Section("LAN") {
                if lanGames.isEmpty {
                    Text("No local games yet.").foregroundStyle(.secondary)
                }
                ForEach(lanGames, id: \.self) { game in
                    Button(action: { selectedLANGame = game }) {
                        Text(game.name)
                            .fontWeight(selectedLANGame == game ? .semibold : .regular)
                    }
                    .buttonStyle(.plain)
                }
            }

            Section("Tracker") {
                HStack {
                    TextField("Tracker Hostname", text: $trackerHostnameText)
                    Button("Browse", action: browseTracker)
                        .disabled(isBrowsingTracker || trackerHostnameText.isEmpty)
                }
                if isBrowsingTracker {
                    ProgressView()
                }
                if let trackerErrorMessage {
                    Text(trackerErrorMessage).foregroundStyle(.red)
                }
                ForEach(trackerGames, id: \.self) { listing in
                    Button(action: { fill(from: listing) }) {
                        VStack(alignment: .leading) {
                            Text("\(listing.game.playerName) — \(listing.game.mapName)")
                            Text("\(Self.dottedAddress(listing.addr)):\(listing.game.port) · \(listing.game.nPlayers) players")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                    .buttonStyle(.plain)
                }
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

            HStack {
                Button("Join", action: startJoining)
                    .disabled(isJoining || (selectedLANGame == nil && UInt16(portText) == nil))
                if selectedLANGame == nil, let port = UInt16(portText), !addressText.isEmpty {
                    ShareLink(item: BoloJoinURL.make(host: addressText, port: port))
                }
            }
        }
        .padding()
        .onAppear {
            consumePendingJoin()
            startLANBrowse()
            consumeJoinLastHostIntentIfPending()
        }
        .onChange(of: pendingJoinURL) { _, _ in consumePendingJoin() }
        .onChange(of: AppIntentRouter.shared.pendingAction) { _, _ in consumeJoinLastHostIntentIfPending() }
        .onDisappear(perform: stopLANBrowse)
    }

    /// Issue #22: `JoinLastHostIntent`'s own hand-off -- same two-hook shape as
    /// `consumePendingJoin()` above. Fills the same fields the tracker list's own `fill(from:)`
    /// does, then submits immediately rather than waiting for a second "Join" click.
    private func consumeJoinLastHostIntentIfPending() {
        guard AppIntentRouter.shared.pendingAction == .joinLastHost else { return }
        AppIntentRouter.shared.pendingAction = nil
        guard !isJoining, let last = LastJoinedHostStore.load() else { return }
        selectedLANGame = nil
        addressText = last.host
        portText = String(last.port)
        startJoining()
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

    private func browseTracker() {
        trackerErrorMessage = nil
        isBrowsingTracker = true
        trackerGames = []

        Task { @MainActor in
            do {
                trackerGames = try await listTrackerGames(hostname: trackerHostnameText)
            } catch let error as TrackerBrowseError {
                trackerErrorMessage = Self.message(for: error)
            } catch {
                trackerErrorMessage = "\(error)"
            }
            isBrowsingTracker = false
        }
    }

    private func fill(from listing: TrackerHostList) {
        selectedLANGame = nil
        addressText = Self.dottedAddress(listing.addr)
        portText = String(listing.game.port)
    }

    private func consumePendingJoin() {
        guard let url = pendingJoinURL, let join = BoloJoinURL.parse(url) else { return }
        pendingJoinURL = nil
        selectedLANGame = nil
        addressText = join.host
        portText = String(join.port)
    }

    private func startLANBrowse() {
        stopLANBrowse()
        let browser = BonjourBrowser()
        lanBrowser = browser
        Task { @MainActor in
            for await games in browser.games {
                lanGames = games
            }
        }
    }

    private func stopLANBrowse() {
        lanBrowser?.cancel()
        lanBrowser = nil
        lanGames = []
        selectedLANGame = nil
    }

    private static func dottedAddress(_ addr: UInt32) -> String {
        "\((addr >> 24) & 0xff).\((addr >> 16) & 0xff).\((addr >> 8) & 0xff).\(addr & 0xff)"
    }

    private static func message(for error: TrackerBrowseError) -> String {
        switch error {
        case .badVersion: return "Tracker version doesn't match."
        case .connectionClosedEarly: return "The connection closed before the tracker list finished."
        case .malformedResponse: return "The tracker sent an unreadable response."
        }
    }

    private func startJoining() {
        let lanGame = selectedLANGame
        if lanGame == nil, UInt16(portText) == nil { return }
        errorMessage = nil
        isJoining = true
        progress = nil

        Task { @MainActor in
            do {
                let onProgress: @Sendable (JoinProgress) -> Void = { newProgress in
                    Task { @MainActor in progress = newProgress }
                }
                let result: (session: TCPSession, preamble: BoloPreamble, mapData: [UInt8])
                if let lanGame {
                    result = try await TCPSession.join(
                        to: lanGame.endpoint, name: nameText, pass: passwordText, onProgress: onProgress
                    )
                } else if let port = UInt16(portText) {
                    result = try await TCPSession.join(
                        host: addressText, port: port, name: nameText, pass: passwordText, onProgress: onProgress
                    )
                } else {
                    isJoining = false
                    return
                }

                var state = GameState()
                guard applyBoloPreamble(result.preamble, mapData: result.mapData, state: &state) else {
                    isJoining = false
                    result.session.cancel()
                    errorMessage = "Incompatible Map Version"
                    return
                }

                let udpSession: UDPSession
                do {
                    udpSession = try await UDPSession(host: result.session.remoteHost, port: result.session.remotePort)
                } catch {
                    isJoining = false
                    result.session.cancel()
                    errorMessage = "Unable to Establish the Datagram Channel -- \(error.localizedDescription)"
                    return
                }

                // Issue #22: resolved values, not `addressText`/`portText` -- correct for a LAN
                // join too, where those text fields never held the LAN game's real address.
                LastJoinedHostStore.record(
                    LastJoinedHost(host: result.session.remoteHost, port: result.session.remotePort)
                )
                isJoining = false
                onJoinedGame(result.session, udpSession, state)
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
    JoinGameView(onJoinedGame: { (_: TCPSession, _: UDPSession, _: GameState) in })
}
