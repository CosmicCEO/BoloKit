//
//  PreferencesView.swift
//  Bolo 2026
//
//  Milestone C.5 (D120) -- the persistent-preferences shell. The reference (`GSXBoloController.m:
//  525-731` + `DefaultPreferences.plist`) is a single flat `NSUserDefaults` domain seeded via
//  `registerDefaults:`, read/written directly by ~25 `set*` methods wired to a tabbed
//  `preferencesWindow` + `NSToolbar`. This port uses `@AppStorage` (SwiftUI's own wrapper over the
//  same `UserDefaults.standard` mechanism) directly in views instead -- no custom
//  `PreferencesStore`/model class, no seeded plist (each `@AppStorage` call site's own default-value
//  argument plays that role) -- same "reuse over invention" bias as D67/D72.
//
//  v1 scope, deliberately thin (D120): 4 scalar fields that already have a hardcoded, unpersisted
//  counterpart shipping today in `HostGameView`/`JoinGameView` -- player name (`GSPlayerNameString`),
//  tracker hostname (`GSTrackerString`), default host port (`GSHostPortNumber`), and mute sound
//  (`GSMuteBool`, landed ahead of C.3's own sound work -- the toggle itself has no dependency on
//  C.3's asset pipeline, C.3 just reads it later). Key *names* reused verbatim from the reference's
//  own `DefaultPreferences.plist` for consistency, not for interop (D31/D42: no interop requirement
//  exists or is implied by matching a string).
//
//  Explicitly out of v1 scope (D120's own list, not an oversight): every per-game `HostGameView`
//  option already surfaced at host-setup time (time limit, hidden mines, domination, map, password
//  -- duplicating those here would be scope creep, not a preference in the persistent-shell sense),
//  display toggles (no HUD exists yet for them to control -- C.0's concern once it lands),
//  zoom/auto-slowdown (no zoom/scroll polish exists -- Milestone D), and message-target/builder-tool
//  (transient per-session UI state in the reference, not a real preference even there).
//
//  **D128 backlog C.1, landed this pass:** a second tab now covers the previously-deferred
//  `GSKeyConfigDict` key remap -- `KeyBindingsRow` below, one row per `InputAction`, backed by
//  `KeyBindingsStore` (persistence) and `BoloKit`'s `KeyBindings` (the rebindable model). This
//  file *does* touch `InputKeymap.swift`'s public surface now, superseding the header note above
//  that used to say otherwise.
//
//  Wired into `Bolo_2026App.swift` via a `Settings { }` scene -- SwiftUI's native preferences-window
//  idiom, opens on Cmd+, automatically, rather than a hand-rolled window/sheet the reference's own
//  `NSToolbar`-based `preferencesWindow` would otherwise suggest porting literally.
//

import AppKit
import BoloKit
import SwiftUI

struct PreferencesView: View {
    var body: some View {
        TabView {
            GeneralPreferencesView()
                .tabItem { Text("General") }
            KeyBindingsPreferencesView()
                .tabItem { Text("Key Bindings") }
        }
        .padding()
        .frame(width: 420)
    }
}

private struct GeneralPreferencesView: View {
    @AppStorage("GSPlayerNameString") private var playerName = "Newbie"
    @AppStorage("GSTrackerString") private var trackerHostname = "tracker.xbolo.org"
    @AppStorage("GSHostPortNumber") private var hostPort = 50000
    @AppStorage("GSMuteBool") private var muteSound = false

    var body: some View {
        Form {
            TextField("Player Name", text: $playerName)
            TextField("Tracker Hostname", text: $trackerHostname)
            TextField("Default Host Port", value: $hostPort, format: .number.grouping(.never))
            Toggle("Mute Sound", isOn: $muteSound)
        }
        .padding()
    }
}

/// Human-readable labels for the settings list -- not reused anywhere else, so kept local rather
/// than added to `BoloKit`'s dependency-free `InputAction` (which stays UI-string-free).
private let actionDisplayNames: [InputAction: String] = [
    .accelerate: "Accelerate",
    .brake: "Brake",
    .turnLeft: "Turn Left",
    .turnRight: "Turn Right",
    .layMine: "Lay Mine",
    .shoot: "Shoot",
    .increaseAim: "Increase Range",
    .decreaseAim: "Decrease Range",
    .scrollUp: "Scroll Up",
    .scrollDown: "Scroll Down",
    .scrollLeft: "Scroll Left",
    .scrollRight: "Scroll Right",
    .tankView: "Center on Tank",
    .pillView: "Center on Pillbox",
]

/// Same virtual-keycode → display-name table `GSKeyCodeField.palette` (a whole custom
/// `NSControl` in the reference) exists to render -- this port only needs display, not the
/// reference's editable-field widget, so a plain lookup covers it. Not exhaustive -- unmapped
/// keycodes fall back to `"Key #<code>"`, which is enough to disambiguate during a rebind.
private let keyCodeDisplayNames: [UInt16: String] = [
    0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
    11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T", 32: "U", 34: "I", 31: "O",
    35: "P", 37: "L", 38: "J", 40: "K", 45: "N", 46: "M",
    49: "Space", 36: "Return", 48: "Tab", 51: "Delete", 53: "Escape", 56: "Shift",
    123: "Left Arrow", 124: "Right Arrow", 125: "Down Arrow", 126: "Up Arrow",
]

private func displayName(forKeyCode keyCode: UInt16) -> String {
    keyCodeDisplayNames[keyCode] ?? "Key #\(keyCode)"
}

private struct KeyBindingsPreferencesView: View {
    @State private var bindings = KeyBindingsStore.load()
    @State private var capturingAction: InputAction?
    @State private var monitor: Any?

    var body: some View {
        Form {
            ForEach(InputAction.allCases, id: \.self) { action in
                HStack {
                    Text(actionDisplayNames[action] ?? action.rawValue)
                    Spacer()
                    Button(rowLabel(for: action)) {
                        beginCapturing(action)
                    }
                    .frame(minWidth: 110)
                }
            }
        }
        .padding()
        .onDisappear { endCapturing() }
    }

    private func rowLabel(for action: InputAction) -> String {
        if capturingAction == action {
            return "Press a key…"
        }
        guard let keyCode = bindings.keyCode(for: action) else { return "Unbound" }
        return displayName(forKeyCode: keyCode)
    }

    /// Arms a one-shot local key-down monitor to capture the next physical key press as the new
    /// binding for `action`, then rebinds, persists via `KeyBindingsStore`, and tears the monitor
    /// down -- mirroring the reference's own `GSKeyCodeField` control (a text field that swallows
    /// the next keystroke into its own value) without needing a whole custom `NSControl`.
    private func beginCapturing(_ action: InputAction) {
        endCapturing()
        capturingAction = action
        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { event in
            self.bindings = self.bindings.rebind(action, to: event.keyCode)
            KeyBindingsStore.save(self.bindings)
            self.endCapturing()
            return nil  // swallow the keystroke -- it's a rebind capture, not real input
        }
    }

    private func endCapturing() {
        if let monitor {
            NSEvent.removeMonitor(monitor)
        }
        monitor = nil
        capturingAction = nil
    }
}

#Preview {
    PreferencesView()
}
