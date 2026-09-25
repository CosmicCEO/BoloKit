//
//  HostGameView.swift
//  Bolo 2026
//
//  Milestone B.2 (D94 -- narrowed scope, confirmed by Planner after this sub-wave's own
//  pre-brief traced `HostListener`/`HostDgramListener`/`HostSessionTable` and found no existing
//  orchestrator tying them to the tick loop): this view is the settings form + map picker only.
//  **No `HostSession`/`HostListener`/`HostDgramListener`/`HostSessionTable` call anywhere in this
//  file** -- the real host-network engine is B.5's separate, not-yet-briefed scope. "Start
//  Hosting" here means "start a real, single-process `GameSession` from a real loaded map,"
//  exactly what the B.1 "Play Demo" button already does with synthetic terrain.
//
//  Field mapping traced against the reference's actual host-panel outlets
//  (`Reference/c/Mac OS X/GSXBoloController.h:28-45`) and its shipped defaults
//  (`Reference/c/en.lproj/DefaultPreferences.plist`): domination type 0 (open), base-control
//  30s, hidden mines off, password off, port 50000. `hostGameTypeMenu`/`Tab` excluded -- the
//  reference's own header comment confirms domination is the only supported game type, and
//  `BoloKit.DominationType` only models that. `hostHiddenMinesTextField` excluded --
//  `GameState.hiddenMines` is a pure `Bool`, nothing in this port for a second numeric field to
//  bind to.
//
//  Milestone B.6 (D105 Part 2, split from B.4): Tracker/UPnP toggles added, same "no live
//  listener to bind to yet" treatment as `portText` -- see that field's own comment below.
//
//  Milestone B.7 (D108): "Start Hosting" now builds a real `HostListener`/`HostDgramListener`/
//  `HostGameEngine` and calls `engine.start()` before handing it to the caller -- `portText`'s own
//  "not connected to a real listener yet" disclosure above no longer applies to the port field
//  itself (it now binds the real listener), though Tracker/UPnP still do (B.8's own separate gap,
//  not this one -- registering with a tracker/mapping a port needs a reachable public address,
//  which this milestone doesn't add).
//
//  Milestone B.7 (D109): `HostListener`/`HostDgramListener` construction failed with `EINVAL` on
//  *every* fixed port (`port: 0` succeeded). This was first written up as a macOS 27 beta
//  Network.framework issue; it was not. Root cause (found after the v1.5.0 two-Mac test showed it
//  on macOS 26 too): the listeners passed the port both via `requiredLocalEndpoint` (`forceIPv4`)
//  and via `NWListener(using:on:)`, and that combination is rejected for any non-zero port. Fixed
//  by building with `NWListener(using:)` alone; see `forceIPv4` and
//  `HostListenerFixedPortTests`. The solo-play fallback stays: Jerod confirmed solo play must still
//  work regardless, so a failed listener construction
//  now falls back to `onStartHostingLocalOnly` -- the same local-only simulation
//  `JoinGameView`'s post-handshake flow already runs -- with a visible in-game notice, rather than
//  a dead-end form error. Real multi-human-one-machine networked play stays unscoped for now.
//
//  v1.3.0 #24: B.7/B.8's disclosed Tracker/UPnP gap above is closed -- `startHosting()` now calls
//  the new `HostGameEngine.startNetworkDiscovery` right after `engine.start()`, best-effort (a
//  failed/skipped tracker or UPnP request never blocks hosting, matching D109's own "solo play
//  must still work" precedent).
//

import BoloKit
import BoloNet
import SwiftUI
import UniformTypeIdentifiers

struct HostGameView: View {
    let onStartHosting: (HostGameEngine) -> Void
    /// D109's fallback target -- fires with the same fully-assembled `GameState` `onStartHosting`
    /// would have, when the real listener couldn't be constructed on this machine.
    let onStartHostingLocalOnly: (GameState) -> Void
    /// Finder / Open With URL. Consumed here only while Host is on screen; a live play
    /// session leaves it pending (`MapOpenPolicy`).
    @Binding var pendingMapURL: URL?

    @State private var mapURL: URL?
    /// Decoded from `mapURL`'s bytes via `decodeBMap` -- terrain/pills/bases/starts only; the
    /// form's settings below are merged into this right before `onStartHosting` fires.
    @State private var mapState: GameState?
    @State private var mapErrorMessage: String?
    @State private var isChoosingMap = false

    /// #157: same `"GSPlayerNameString"` key `PreferencesView`'s `@AppStorage` and
    /// `JoinGameView`'s own field write to -- one shared identity, matching the oracle's single
    /// `playerNameString` ivar. Previously this screen had no field at all; `startHosting()` read
    /// the key directly from `UserDefaults`.
    @AppStorage("GSPlayerNameString") private var playerName = "Newbie"
    /// #157: optional, new relative to the oracle (which has no server/game-name concept at all
    /// -- joiners there see the host's player name + map filename). Blank falls back to the
    /// player name at the two call sites that advertise this game's display string.
    @State private var gameName = ""

    @State private var timeLimitEnabled = false
    @State private var timeLimitMinutes: Double = 30
    // #157: default flipped true -- deliberate product decision, diverges from the oracle's own
    // default-off (`DefaultPreferences.plist`'s `hostHiddenMinesBool`).
    @State private var hiddenMinesEnabled = true
    // #157: surfaces `GameState.pauseOnPlayerExit` (already simulated, `GameState.swift:88`) --
    // the oracle only ever exposed this via the headless Dedicated Host CLI's `-e` flag, never in
    // its own GUI.
    @State private var pauseOnPlayerExitEnabled = false
    // #72: surfaces `GameState.baseVisionEnabled` -- no oracle equivalent (a captured base
    // never projects vision in `Reference/c`), a deliberate product enhancement a host can
    // opt into for "enhanced" play while defaulting off for oracle-authentic "genuine" play.
    @State private var baseVisionEnabled = false
    @State private var passwordEnabled = false
    @State private var passwordText = ""
    @State private var dominationType: DominationType = .open
    @State private var baseControlSeconds: Double = 30
    @State private var portText = "50000"
    /// v1.3.0 #24: wired to `HostGameEngine.startNetworkDiscovery` in `startHosting()` below.
    @State private var trackerEnabled = false
    @State private var upnpEnabled = false
    @State private var hostErrorMessage: String?
    @State private var isStartingHost = false

    static let mapContentType = UTType(exportedAs: "com.cosmicceo.bolo-map")
    /// Existing `.map` files on this Mac are often still tagged as XBolo's UTI
    /// (`mdls` on `U.S.A.map`). Import it so the picker is not greyed out and
    /// Quick Look can match the same files.
    static let importedXBoloMapType = UTType(importedAs: "com.gengasw.xbolo.map")
    static var mapPickerContentTypes: [UTType] { [mapContentType, importedXBoloMapType] }

    /// Milestone C.5 (D120): `portText`'s initial value now reads the same `"GSHostPortNumber"`
    /// key `PreferencesView`'s `@AppStorage` writes to (both back onto `UserDefaults.standard`,
    /// the same store) -- reading it directly here, rather than via a second `@AppStorage`
    /// property, avoids a `String`/`Int` type mismatch against this view's own text-field-bound
    /// `String` state with no extra conversion property.
    init(
        onStartHosting: @escaping (HostGameEngine) -> Void,
        onStartHostingLocalOnly: @escaping (GameState) -> Void,
        pendingMapURL: Binding<URL?> = .constant(nil)
    ) {
        self.onStartHosting = onStartHosting
        self.onStartHostingLocalOnly = onStartHostingLocalOnly
        _pendingMapURL = pendingMapURL
        let storedPort = UserDefaults.standard.object(forKey: "GSHostPortNumber") as? Int
        _portText = State(initialValue: String(storedPort ?? 50000))
    }

    var body: some View {
        Form {
            Section("Player") {
                TextField("Player Name", text: $playerName)
                TextField("Game Name (optional)", text: $gameName)
                    .help("Shown to joiners in the LAN/tracker list instead of your player name")
            }

            Section("Map") {
                HStack {
                    Button("Choose Map…") { isChoosingMap = true }
                    if let mapURL {
                        Text(mapURL.lastPathComponent).foregroundStyle(.secondary)
                    }
                }
                if let mapErrorMessage {
                    Text(mapErrorMessage).foregroundStyle(.red)
                }
            }

            Section("Game Settings") {
                Toggle("Time Limit", isOn: $timeLimitEnabled)
                if timeLimitEnabled {
                    Stepper(
                        "\(Int(timeLimitMinutes)) minutes", value: $timeLimitMinutes, in: 1...120
                    )
                }
                Toggle("Hidden Mines", isOn: $hiddenMinesEnabled)
                Toggle("Pause on Player Exit", isOn: $pauseOnPlayerExitEnabled)
                Toggle("Base Vision", isOn: $baseVisionEnabled)
                    .help("Enhanced play: a captured base reveals the area around it, like a built pillbox. Off matches the original game exactly.")
                Toggle("Password", isOn: $passwordEnabled)
                if passwordEnabled {
                    SecureField("Password", text: $passwordText)
                }
                TextField("Port", text: $portText)
                Toggle("Announce on Tracker", isOn: $trackerEnabled)
                    .help("Registers this game with the tracker hostname set in Preferences")
                Toggle("UPnP Port Mapping", isOn: $upnpEnabled)
                    .help("Requests a NAT-PMP/UPnP port mapping for this game's port")
            }

            Section("Domination") {
                Picker("Type", selection: $dominationType) {
                    Text("Open").tag(DominationType.open)
                    Text("Tournament").tag(DominationType.tournament)
                    Text("Strict").tag(DominationType.strict)
                }
                Stepper(
                    "Base control: \(Int(baseControlSeconds))s", value: $baseControlSeconds, in: 5...300, step: 5
                )
            }

            if let hostErrorMessage {
                Text(hostErrorMessage).foregroundStyle(.red)
            }
            Button("Start Hosting") { Task { await startHosting() } }
                .disabled(mapState == nil || isStartingHost)
        }
        .padding()
        .fileImporter(isPresented: $isChoosingMap, allowedContentTypes: Self.mapPickerContentTypes) { result in
            handleMapPickerResult(result)
        }
        // D132: bundled default map, applied on first appearance only (`mapState == nil` guards
        // against re-applying over a user's already-chosen map if this view re-appears). Goes
        // through the exact same decode/post-process path as a user-imported map -- see
        // `applyDecodedMap` below -- via the byte-for-byte `encodeBMap` output of
        // `BoloKit.defaultBundledMapState()`, embedded in `DefaultMap.swift`.
        .onAppear {
            if pendingMapURL != nil {
                consumePendingMap()
            } else if mapState == nil {
                applyDecodedMap(bytes: defaultMapFileBytes)
            }
            consumeHostIntentIfPending()
        }
        .onChange(of: pendingMapURL) { _, _ in
            consumePendingMap()
        }
        .onChange(of: AppIntentRouter.shared.pendingAction) { _, _ in
            consumeHostIntentIfPending()
        }
    }

    /// Issue #22: `HostGameIntent`'s own hand-off, consumed once whether it arrived before this
    /// view existed (`onAppear`, a cold launch via Shortcuts/Spotlight) or while it's already on
    /// screen (`onChange`) -- same two-hook shape as `pendingMapURL`'s own `consumePendingMap()`
    /// above. Only auto-submits once `mapState` is already populated -- the bundled default map,
    /// applied earlier in this same `onAppear` -- matching what "Start Hosting" itself requires.
    private func consumeHostIntentIfPending() {
        guard AppIntentRouter.shared.pendingAction == .hostGame else { return }
        AppIntentRouter.shared.pendingAction = nil
        guard mapState != nil, !isStartingHost else { return }
        Task { await startHosting() }
    }

    private func handleMapPickerResult(_ result: Result<URL, Error>) {
        guard case .success(let url) = result else { return }
        applyLoadedMap(url: url, outcome: Self.loadMap(from: url))
    }

    private func consumePendingMap() {
        guard let url = pendingMapURL else { return }
        pendingMapURL = nil
        applyLoadedMap(url: url, outcome: Self.loadMap(from: url))
    }

    private func applyLoadedMap(url: URL, outcome: MapLoadOutcome) {
        mapURL = url
        mapErrorMessage = nil
        mapState = nil
        switch outcome {
        case .failure(let message):
            mapErrorMessage = message
        case .success(let decoded):
            mapState = decoded
        }
    }

    /// Security-scoped read when the system provided a scoped URL; plain `Data(contentsOf:)`
    /// otherwise (temp files in tests, non-scoped `onOpenURL`).
    static func loadMap(from url: URL) -> MapLoadOutcome {
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        guard let data = try? Data(contentsOf: url) else {
            return .failure("Unable to Open Map File")
        }
        return decodeAndPostProcessMap(bytes: Array(data))
    }

    /// D144: outcome type for `decodeAndPostProcessMap` below -- pulled out of `applyDecodedMap`
    /// so the actual decode/post-process/validate logic is a true, `@State`-free pure function,
    /// directly unit-testable. (Discovered empirically this pass, not assumed: a `HostGameView`
    /// instantiated directly in a test and called with `applyDecodedMap` alone did NOT reliably
    /// persist `@State` writes back to the caller's own copy of the struct -- `@State`'s storage
    /// depends on SwiftUI's environment installation, not just a shared reference-type box, so
    /// direct-construction testing of `@State` mutation silently no-ops instead of crashing. Every
    /// `GameSessionTests` case, which touches zero `@State`, passed cleanly by contrast --
    /// isolating the cause to `@State` specifically, confirmed by a real `xcodebuild test` run
    /// showing 4/4 `GameSessionTests` green against 6/6 originally-written `HostGameViewTests`
    /// failing on stale-nil reads.)
    enum MapLoadOutcome {
        case success(GameState)
        case failure(String)
    }

    /// Shared by both the bundled default map (D132) and a user-imported file (D131): decode,
    /// server-post-process, and validate, in the exact same order either way. Factored out so the
    /// two call sites can't silently drift on which steps they run. Pure -- no `@State`, no
    /// `self` -- see `MapLoadOutcome`'s own comment above for why that separation matters.
    static func decodeAndPostProcessMap(bytes: [UInt8]) -> MapLoadOutcome {
        var decoded = GameState()
        guard decodeBMap(bytes, into: &decoded) else {
            return .failure("Incompatible Map Version")
        }
        // D131: this is the host's own map-load path -- `serverloadmap()`'s counterpart
        // (`Reference/c/bmap_server.c:21-252`), not `clientloadmap()`'s. Forces pill/base owner
        // to NEUTRAL, rescales pill speed, clears start tiles to sea, and normalizes any "mined"
        // terrain variant sitting under a pill/base -- none of which `decodeBMap` above does
        // (that's the shared client-side decode only). Must run before the starts-empty check
        // below is meaningless either way (post-process never adds/removes starts), but must run
        // before `mapState` is published, since `HostGameView.swift` is the actual real call site
        // `Sources/BoloKit/BMap.swift:621-624`'s doc comment incorrectly claimed didn't exist.
        serverPostProcessLoadedMap(&decoded)
        // Not a literal port -- a defensive check this port needs that the reference's map
        // format doesn't itself require: `spawn(state:)` (Wave 5.6, wired real per D88 §4)
        // indexes `state.starts` unconditionally, so a map with none would crash the very first
        // time the host's own tank dies, not on load. Catching it here, at the same "can't use
        // this map" moment as the other two failure messages above, not deferred to a crash.
        guard !decoded.starts.isEmpty else {
            return .failure("Map Has No Start Points")
        }

        return .success(decoded)
    }

    private func applyDecodedMap(bytes: [UInt8]) {
        mapErrorMessage = nil
        mapState = nil

        switch Self.decodeAndPostProcessMap(bytes: bytes) {
        case .failure(let message):
            mapErrorMessage = message
        case .success(var decoded):
            if bytes == defaultMapFileBytes {
                applyDefaultBundledMapOwners(&decoded)
            }
            mapState = decoded
        }
    }

    private func startHosting() async {
        guard var state = mapState else { return }

        guard let port = UInt16(portText) else {
            hostErrorMessage = "Invalid Port"
            return
        }

        state.timeLimit = timeLimitEnabled ? Int(timeLimitMinutes) * 60 : 0
        state.hiddenMines = hiddenMinesEnabled
        state.pauseOnPlayerExit = pauseOnPlayerExitEnabled
        state.baseVisionEnabled = baseVisionEnabled
        state.passwordRequired = passwordEnabled
        state.serverPassword = passwordEnabled ? passwordText : ""
        state.dominationType = dominationType
        state.baseControlThreshold = Int(baseControlSeconds)

        var player = PlayerState()
        player.name = hostPlayerDisplayName(stored: playerName)
        player.connected = true
        player.used = true
        player.dead = true
        player.alliance = UInt16(1 << 0)
        state.local.respawnCounter = respawnTicks - 1  // spawn() fires on the very first tick
        state.players = hostPlayerSlots(hostPlayer: player)
        state.localPlayer = 0

        hostErrorMessage = nil
        isStartingHost = true
        defer { isStartingHost = false }

        do {
            // #157: the LAN/tracker display string -- the optional custom game name if set,
            // otherwise the player's own name (matching the oracle's only option, host player
            // name + map filename; `Reference/c/Mac OS X/GSXBoloController.m`).
            let advertisedName = hostAdvertisedName(gameName: gameName, playerName: playerName)
            let listener = try await HostListener(port: port, bonjourName: advertisedName)
            let dgramListener = try await HostDgramListener(port: port)
            let engine = HostGameEngine(initialState: networkHostState(from: state), listener: listener, dgramListener: dgramListener)
            engine.start()
            // v1.3.0 #24: best-effort, matches `startNetworkDiscovery`'s own "never blocks hosting"
            // contract -- `trackerEnabled`/`upnpEnabled` off (or a failure inside either) is a
            // silent LAN-only outcome, not an error surfaced to this form.
            let trackerHostname = UserDefaults.standard.string(forKey: "GSTrackerString")
            await engine.startNetworkDiscovery(
                trackerHostname: trackerEnabled ? trackerHostname : nil,
                advertisedPort: port,
                hostPlayerName: advertisedName,
                mapName: mapURL?.lastPathComponent ?? "",
                upnpEnabled: upnpEnabled
            )
            onStartHosting(engine)
        } catch {
            // D109: a real, environment-level Network.framework failure this port's own code
            // can't fix (see this file's own header) -- fall back to solo local play rather than
            // leaving the user at a dead end.
            onStartHostingLocalOnly(state)
        }
    }
}

/// The state a real network host runs with: the host simulates guest tanks (#59/#62). A copy, so
/// the solo/local-only fallback (which reuses the original state) never turns simulation on.
nonisolated func networkHostState(from state: GameState) -> GameState {
    var hosted = state
    hosted.hostSimulatesRemotePlayers = true
    return hosted
}

/// The host's own display name: the stored `GSPlayerNameString`, or its shipped default. Without
/// this the host's `PlayerState.name` stayed empty, so guests (whose preamble carries it) saw the
/// host as "Player 0" and drew no name label for it (#85).
nonisolated func hostPlayerDisplayName(stored: String?) -> String {
    stored.flatMap { $0.isEmpty ? nil : $0 } ?? "Newbie"
}

/// #157: the LAN/tracker display string for a hosted game -- the host's optional custom game
/// name if set, otherwise their own player name (`hostPlayerDisplayName`'s "Newbie" fallback
/// still applies underneath). The oracle has no game-name concept at all, only host player name +
/// map filename (`Reference/c/Mac OS X/GSXBoloController.m`'s tracker-listing columns) -- this is
/// additive, not a parity gap.
nonisolated func hostAdvertisedName(gameName: String, playerName: String) -> String {
    gameName.isEmpty ? hostPlayerDisplayName(stored: playerName) : gameName
}

#Preview {
    HostGameView(onStartHosting: { (_: HostGameEngine) in }, onStartHostingLocalOnly: { _ in })
}
