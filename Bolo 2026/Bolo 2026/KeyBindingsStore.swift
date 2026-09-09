//
//  KeyBindingsStore.swift
//  Bolo 2026
//
//  D128 backlog C.1 -- persistence for the rebindable keymap (`BoloKit`'s `KeyBindings`). Follows
//  `PreferencesView.swift`'s existing grain: same `UserDefaults.standard` domain, same reused-
//  literal-name-from-the-reference convention (`GSKeyConfigDict`, the C client's own key for this
//  exact dictionary in `DefaultPreferences.plist`) -- reused for consistency, not interop (D31/
//  D42, no interop requirement implied). Kept as a standalone free-function store rather than an
//  `@AppStorage`-in-view property, because `KeyBindings` is a 14-entry dictionary, not a scalar --
//  `@AppStorage` has no native `Codable`-dictionary support, and `GameRenderView` (an `NSView`,
//  not a SwiftUI view) needs to read/write it too.
//
//  `Foundation`'s `JSONEncoder`/`JSONDecoder` live here (the app target), not in `BoloKit` --
//  `KeyBindings.dictionaryRepresentation`/`init(dictionaryRepresentation:)` is the dependency-free
//  seam `BoloKit` exposes for exactly this.
//

import BoloKit
import Foundation

public enum KeyBindingsStore {
    public static let defaultsKey = "GSKeyConfigDict"

    /// Loads the persisted keymap, or `KeyBindings.default` if nothing has been saved yet (first
    /// launch, or a defaults domain wiped by `-D120`'s existing `Reset to Defaults` precedent --
    /// none exists yet for this store specifically, but the load path is safe either way).
    public static func load() -> KeyBindings {
        guard let data = UserDefaults.standard.data(forKey: defaultsKey),
              let decoded = try? JSONDecoder().decode([String: UInt16].self, from: data)
        else {
            return .default
        }
        return KeyBindings(dictionaryRepresentation: decoded)
    }

    /// Persists `bindings` so it survives relaunch.
    public static func save(_ bindings: KeyBindings) {
        guard let data = try? JSONEncoder().encode(bindings.dictionaryRepresentation) else { return }
        UserDefaults.standard.set(data, forKey: defaultsKey)
    }
}
