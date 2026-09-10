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
//  Milestone B.7 (D109): root-caused live -- `HostListener`/`HostDgramListener` construction fails
//  on *every* fixed port on Jerod's current machine (confirmed: a bare, zero-dependency `NWListener`
//  call outside this project entirely reproduces the identical `EINVAL`, while `port: 0` succeeds).
//  A macOS 27 beta Network.framework issue, not a bug in this port's own code, and nothing here can
//  fix it. Jerod confirmed solo play must still work regardless, so a failed listener construction
//  now falls back to `onStartHostingLocalOnly` -- the same local-only simulation
//  `JoinGameView`'s post-handshake flow already runs -- with a visible in-game notice, rather than
//  a dead-end form error. Real multi-human-one-machine networked play stays unscoped for now.
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

    @State private var mapURL: URL?
    /// Decoded from `mapURL`'s bytes via `decodeBMap` -- terrain/pills/bases/starts only; the
    /// form's settings below are merged into this right before `onStartHosting` fires.
    @State private var mapState: GameState?
    @State private var mapErrorMessage: String?
    @State private var isChoosingMap = false

    @State private var timeLimitEnabled = false
    @State private var timeLimitMinutes: Double = 30
    @State private var hiddenMinesEnabled = false
    @State private var passwordEnabled = false
    @State private var passwordText = ""
    @State private var dominationType: DominationType = .open
    @State private var baseControlSeconds: Double = 30
    /// No live effect yet -- no listener exists to bind this to until B.5. Kept in the form so
    /// the UI doesn't need rework once B.5 lands and actually needs a port.
    @State private var portText = "50000"
    /// Milestone B.6 (D105 Part 2, split from B.4): same "no live effect yet" treatment as
    /// `portText` above, for the identical reason -- `startHosting()` below still only produces a
    /// local `GameState` (D94's own disclosed scope), so there is no real listener for
    /// `registerWithTracker`/`PortMapping` (both already shipped, Wave 6.5) to bind to yet. Kept
    /// in the form now so it doesn't need rework once real host-network wiring lands.
    @State private var trackerEnabled = false
    @State private var upnpEnabled = false
    @State private var hostErrorMessage: String?
    @State private var isStartingHost = false

    private let mapContentType = UTType(filenameExtension: "map") ?? .data

    /// Milestone C.5 (D120): `portText`'s initial value now reads the same `"GSHostPortNumber"`
    /// key `PreferencesView`'s `@AppStorage` writes to (both back onto `UserDefaults.standard`,
    /// the same store) -- reading it directly here, rather than via a second `@AppStorage`
    /// property, avoids a `String`/`Int` type mismatch against this view's own text-field-bound
    /// `String` state with no extra conversion property.
    init(
        onStartHosting: @escaping (HostGameEngine) -> Void,
        onStartHostingLocalOnly: @escaping (GameState) -> Void
    ) {
        self.onStartHosting = onStartHosting
        self.onStartHostingLocalOnly = onStartHostingLocalOnly
        let storedPort = UserDefaults.standard.object(forKey: "GSHostPortNumber") as? Int
        _portText = State(initialValue: String(storedPort ?? 50000))
    }

    var body: some View {
        Form {
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
                Toggle("Password", isOn: $passwordEnabled)
                if passwordEnabled {
                    SecureField("Password", text: $passwordText)
                }
                TextField("Port", text: $portText)
                Toggle("Announce on Tracker", isOn: $trackerEnabled)
                    .help("Not wired to hosting yet")
                Toggle("UPnP Port Mapping", isOn: $upnpEnabled)
                    .help("Not wired to hosting yet")
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
        .fileImporter(isPresented: $isChoosingMap, allowedContentTypes: [mapContentType]) { result in
            handleMapPickerResult(result)
        }
        // D132: bundled default map, applied on first appearance only (`mapState == nil` guards
        // against re-applying over a user's already-chosen map if this view re-appears). Goes
        // through the exact same decode/post-process path as a user-imported map -- see
        // `applyDecodedMap` below -- via the byte-for-byte `encodeBMap` output of
        // `BoloKit.defaultBundledMapState()`, embedded in `DefaultMap.swift`.
        .onAppear {
            guard mapState == nil else { return }
            applyDecodedMap(bytes: defaultMapFileBytes)
        }
    }

    private func handleMapPickerResult(_ result: Result<URL, Error>) {
        mapErrorMessage = nil
        mapState = nil

        guard case .success(let url) = result else { return }
        mapURL = url

        guard url.startAccessingSecurityScopedResource() else {
            mapErrorMessage = "Unable to Open Map File"
            return
        }
        defer { url.stopAccessingSecurityScopedResource() }

        guard let data = try? Data(contentsOf: url) else {
            mapErrorMessage = "Unable to Open Map File"
            return
        }

        applyDecodedMap(bytes: Array(data))
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
        case .success(let decoded):
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
        state.passwordRequired = passwordEnabled
        state.serverPassword = passwordEnabled ? passwordText : ""
        state.dominationType = dominationType
        state.baseControlThreshold = Int(baseControlSeconds)

        var player = PlayerState()
        player.connected = true
        player.used = true
        player.dead = true
        state.local.respawnCounter = respawnTicks - 1  // spawn() fires on the very first tick
        state.players = [player]
        state.localPlayer = 0

        hostErrorMessage = nil
        isStartingHost = true
        defer { isStartingHost = false }

        do {
            let listener = try await HostListener(port: port)
            let dgramListener = try await HostDgramListener(port: port)
            let engine = HostGameEngine(initialState: state, listener: listener, dgramListener: dgramListener)
            engine.start()
            onStartHosting(engine)
        } catch {
            // D109: a real, environment-level Network.framework failure this port's own code
            // can't fix (see this file's own header) -- fall back to solo local play rather than
            // leaving the user at a dead end.
            onStartHostingLocalOnly(state)
        }
    }
}

#Preview {
    HostGameView(onStartHosting: { (_: HostGameEngine) in }, onStartHostingLocalOnly: { _ in })
}
