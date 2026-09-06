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

import BoloKit
import SwiftUI
import UniformTypeIdentifiers

struct HostGameView: View {
    let onStartHosting: (GameState) -> Void

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

    private let mapContentType = UTType(filenameExtension: "map") ?? .data

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
                    .help("Not connected to a real listener yet -- Milestone B.5")
                Toggle("Announce on Tracker", isOn: $trackerEnabled)
                    .help("Not connected to a real listener yet -- Milestone B.5")
                Toggle("UPnP Port Mapping", isOn: $upnpEnabled)
                    .help("Not connected to a real listener yet -- Milestone B.5")
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

            Button("Start Hosting", action: startHosting)
                .disabled(mapState == nil)
        }
        .padding()
        .fileImporter(isPresented: $isChoosingMap, allowedContentTypes: [mapContentType]) { result in
            handleMapPickerResult(result)
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

        var decoded = GameState()
        guard decodeBMap(Array(data), into: &decoded) else {
            mapErrorMessage = "Incompatible Map Version"
            return
        }
        // Not a literal port -- a defensive check this port needs that the reference's map
        // format doesn't itself require: `spawn(state:)` (Wave 5.6, wired real per D88 §4)
        // indexes `state.starts` unconditionally, so a map with none would crash the very first
        // time the host's own tank dies, not on load. Catching it here, at the same "can't use
        // this map" moment as the other two failure messages above, not deferred to a crash.
        guard !decoded.starts.isEmpty else {
            mapErrorMessage = "Map Has No Start Points"
            return
        }

        mapState = decoded
    }

    private func startHosting() {
        guard var state = mapState else { return }

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

        onStartHosting(state)
    }
}

#Preview {
    HostGameView(onStartHosting: { _ in })
}
