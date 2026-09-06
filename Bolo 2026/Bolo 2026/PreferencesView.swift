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
//  Explicitly out of v1 scope (D120's own list, not an oversight): `GSKeyConfigDict` key remap
//  (C.1's territory -- this file never touches `InputKeymap.swift`), every per-game `HostGameView`
//  option already surfaced at host-setup time (time limit, hidden mines, domination, map, password
//  -- duplicating those here would be scope creep, not a preference in the persistent-shell sense),
//  display toggles (no HUD exists yet for them to control -- C.0's concern once it lands),
//  zoom/auto-slowdown (no zoom/scroll polish exists -- Milestone D), and message-target/builder-tool
//  (transient per-session UI state in the reference, not a real preference even there).
//
//  Wired into `Bolo_2026App.swift` via a `Settings { }` scene -- SwiftUI's native preferences-window
//  idiom, opens on Cmd+, automatically, rather than a hand-rolled window/sheet the reference's own
//  `NSToolbar`-based `preferencesWindow` would otherwise suggest porting literally.
//

import SwiftUI

struct PreferencesView: View {
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
        .frame(width: 360)
    }
}

#Preview {
    PreferencesView()
}
