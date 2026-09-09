// MARK: - D128 backlog C.1 — real, rebindable key mapping
//
// Ported from `Reference/c/en.lproj/DefaultPreferences.plist`'s `GSKeyConfigDict` (the C client's
// *shipped default* key-remap dictionary — decoded directly, not guessed) plus the full action
// switch in `keyEvent:forKey:` (`Reference/c/Mac OS X/GSXBoloController.m:1650-1717`), which reads
// that dictionary to dispatch to 14 named actions — not just the 8 `InputFlags`-mask actions this
// file originally ported (D88's v1 cut, before any remap UI existed to remap anything).
//
// Two action families, both rebindable via `KeyBindings`, mirroring the reference's own split:
//   - 8 **mask actions** feed straight into `InputFlags` bits consumed by the tick loop
//     (accelerate/brake/turnLeft/turnRight/layMine/shoot/increaseAim/decreaseAim).
//   - 6 **view actions** have no `InputFlags` bit at all — they're pure view-scrolling/centering
//     commands the reference dispatches to `NSScrollView`/window-controller methods
//     (`scrollUp:`/`scrollDown:`/`scrollLeft:`/`scrollRight:`/`tankCenter:`/`pillCenter:`), ported
//     to AppKit call sites in `GameRenderView.swift` (the app target), not here.
//
// **Brake (default keycode 1/S) is deliberately dead, not an oversight, and stays that way even
// though it's now rebindable:** under the shipped `autoSlowdownBool == true` default (this port
// never models the toggle — no zoom/auto-slowdown UI exists per D120), C's own `keyEvent:forKey:`
// only actually applies `BRAKEMASK` from the *release* of Accelerate (`keyevent(BRAKEMASK,
// !event)`); the explicit Brake-action branch is gated `if (!autoSlowdownBool)`, dead code under
// the shipped default. `.brake` is still a real `Action` (matching the reference's own dict/UI —
// it has a rebindable field for it too) so it's rebindable and shows up in the settings list, but
// `inputFlagsChange` will never independently fire from it; it stays exactly as coupled to
// `.accelerate`'s key as before.
//
// **No conflict rejection, matching the reference exactly:** `applyKeyConfig:`
// (`GSXBoloController.m:1453-1479`) just overwrites `dict[keycode] = actionString` per field in a
// fixed order with no uniqueness check — rebinding two actions to the same key leaves the second
// call's action as that key's *sole* resolution (last-write-wins), same as here: `KeyBindings`
// stores `[Action: UInt16]` (one keycode per action, always) and `resolve(keyCode:)` reverse-
// searches by iterating `Action.allCases` in declaration order, so on a collision the
// *first-declared* action in `Action.allCases` order wins the keycode — documented tie-break,
// not an accidental one. (The reference's own field-application order in `applyKeyConfig:`
// produces an analogous "last dict key set wins" — since the shipped UI never lets two rows share
// a key in normal use, this is unreachable in practice either way; both are just deterministic.)
//
// Deliberately kept dependency-free (no `AppKit`/`NSEvent`, no `Foundation`) so it runs under
// `swift test`: raw macOS virtual keycodes (`UInt16`) in, `InputFlags`-shaped or view-action output
// out. `GameRenderView.keyDown`/`keyUp`/`flagsChanged` (app target) are the only callers,
// translating a real `NSEvent` into these primitives; `KeyBindings.dictionaryRepresentation`/
// `init(dictionaryRepresentation:)` below are the seam the app target's `UserDefaults`+`JSONEncoder`
// persistence layer uses — encoding itself needs `Foundation`, which stays out of `BoloKit`.

/// One rebindable game action, in the same 14-action shape as `GSKeyConfigDict`. Declaration
/// order is the tie-break order `KeyBindings.resolve(keyCode:)` uses on a keycode collision (see
/// file header) — mask actions first (declaration order matches the mask bit order already used
/// elsewhere in `BoloKit`), then the 6 view actions in the reference's own toolbar/menu order.
public enum InputAction: String, CaseIterable, Codable, Sendable {
    case accelerate
    case brake
    case turnLeft
    case turnRight
    case layMine
    case shoot
    case increaseAim
    case decreaseAim
    case scrollUp
    case scrollDown
    case scrollLeft
    case scrollRight
    case tankView
    case pillView

    /// Whether this action feeds an `InputFlags` bit (vs. being a pure view-scroll/center action
    /// with no game-state effect). Mirrors the reference's own two dispatch families in
    /// `keyEvent:forKey:`.
    public var isMaskAction: Bool {
        switch self {
        case .accelerate, .brake, .turnLeft, .turnRight, .layMine, .shoot, .increaseAim, .decreaseAim:
            return true
        case .scrollUp, .scrollDown, .scrollLeft, .scrollRight, .tankView, .pillView:
            return false
        }
    }
}

/// The `InputFlags` bits to set/clear for one key transition, or `nil` for an unbound key.
public struct KeyInputChange: Equatable, Sendable {
    public var set: InputFlags
    public var clear: InputFlags

    public init(set: InputFlags = [], clear: InputFlags = []) {
        self.set = set
        self.clear = clear
    }
}

/// A complete, rebindable action→keycode map. One keycode per action (never a set) — same shape
/// as `GSKeyConfigDict` inverted (the reference keys its dictionary by keycode string, one action
/// value per key; this stores the natural inverse, one keycode per action, and reverse-resolves
/// on lookup, since "what key is Shoot bound to" is the settings-UI's own dominant query).
public struct KeyBindings: Equatable, Sendable {
    private var keyCodes: [InputAction: UInt16]

    public init(keyCodes: [InputAction: UInt16]) {
        self.keyCodes = keyCodes
    }

    /// Literal defaults decoded from `Reference/c/en.lproj/DefaultPreferences.plist`'s
    /// `GSKeyConfigDict` (14 entries, all present in the shipped plist).
    public static let `default` = KeyBindings(keyCodes: [
        .turnLeft: 0,  // A
        .brake: 1,  // S — dead under autoSlowdownBool==true, see file header
        .turnRight: 2,  // D
        .decreaseAim: 12,  // Q
        .accelerate: 13,  // W
        .increaseAim: 14,  // E
        .shoot: 49,  // Space
        .layMine: 56,  // Shift
        .tankView: 7,  // X
        .pillView: 8,  // C
        .scrollUp: 126,  // Up arrow
        .scrollDown: 125,  // Down arrow
        .scrollLeft: 123,  // Left arrow
        .scrollRight: 124,  // Right arrow
    ])

    /// Current keycode bound to `action`, or `nil` if somehow unbound (shouldn't happen for a
    /// `KeyBindings` built from `.default` or a full `rebind` chain, but the settings UI needs a
    /// non-crashing read for an in-progress/partial dictionary).
    public func keyCode(for action: InputAction) -> UInt16? {
        keyCodes[action]
    }

    /// Returns a copy with `action` rebound to `keyCode`. No conflict rejection (file header) —
    /// if another action already holds `keyCode`, both now report it via `keyCode(for:)`, but
    /// `resolve(keyCode:)` will only ever return the first one in `InputAction.allCases` order.
    public func rebind(_ action: InputAction, to keyCode: UInt16) -> KeyBindings {
        var updated = keyCodes
        updated[action] = keyCode
        return KeyBindings(keyCodes: updated)
    }

    /// Reverse lookup: which action (if any) is bound to `keyCode`. On a collision, returns the
    /// first action in `InputAction.allCases` declaration order (documented tie-break, file header).
    public func resolve(keyCode: UInt16) -> InputAction? {
        InputAction.allCases.first { keyCodes[$0] == keyCode }
    }

    /// Plain `[String: UInt16]` view keyed by `InputAction.rawValue`, for the app target's
    /// `Codable`/`UserDefaults` persistence layer (kept out of `BoloKit` — no `Foundation` here).
    public var dictionaryRepresentation: [String: UInt16] {
        Dictionary(uniqueKeysWithValues: keyCodes.map { ($0.key.rawValue, $0.value) })
    }

    /// Rebuilds from a persisted `dictionaryRepresentation`, filling in any action the dictionary
    /// is missing (e.g. an older save from before an action existed) from `.default`.
    public init(dictionaryRepresentation: [String: UInt16]) {
        var keyCodes = KeyBindings.default.keyCodes
        for action in InputAction.allCases {
            if let stored = dictionaryRepresentation[action.rawValue] {
                keyCodes[action] = stored
            }
        }
        self.keyCodes = keyCodes
    }
}

/// Translates one key-down/key-up transition into the `InputFlags` change it causes under
/// `bindings`, or `nil` if `keyCode` resolves to no action, or to a view action (no `InputFlags`
/// effect — see `nonMaskAction(forKeyCode:bindings:)` for those).
public func inputFlagsChange(forKeyCode keyCode: UInt16, isDown: Bool, bindings: KeyBindings) -> KeyInputChange? {
    guard let action = bindings.resolve(keyCode: keyCode), action.isMaskAction else { return nil }
    switch action {
    case .turnLeft:
        return isDown ? KeyInputChange(set: .turnL) : KeyInputChange(clear: .turnL)
    case .turnRight:
        return isDown ? KeyInputChange(set: .turnR) : KeyInputChange(clear: .turnR)
    case .decreaseAim:
        return isDown ? KeyInputChange(set: .decre) : KeyInputChange(clear: .decre)
    case .increaseAim:
        return isDown ? KeyInputChange(set: .incre) : KeyInputChange(clear: .incre)
    case .shoot:
        return isDown ? KeyInputChange(set: .shoot) : KeyInputChange(clear: .shoot)
    case .layMine:
        return isDown ? KeyInputChange(set: .lmine) : KeyInputChange(clear: .lmine)
    case .accelerate:
        // autoSlowdownBool==true auto-brake coupling (see file header) — Brake's own binding
        // never independently fires this; it's this action's release that does.
        return isDown
            ? KeyInputChange(set: .accel, clear: .brake)
            : KeyInputChange(set: .brake, clear: .accel)
    case .brake:
        // Dead under the shipped autoSlowdownBool==true default (file header) — matches the
        // reference's own `if (!autoSlowdownBool)` gate around this branch in `keyEvent:forKey:`.
        return nil
    case .scrollUp, .scrollDown, .scrollLeft, .scrollRight, .tankView, .pillView:
        return nil
    }
}

/// Resolves `keyCode` to a non-mask (view-scroll/center) action under `bindings`, or `nil` if it
/// resolves to no action or to a mask action. `GameRenderView` (app target) switches on this to
/// call its own scroll/tank-center/pill-center methods — those have no `InputFlags`/`GameState`
/// shape to return here, so this stays a plain action lookup rather than trying to model AppKit
/// scroll-rect math in dependency-free `BoloKit`.
public func nonMaskAction(forKeyCode keyCode: UInt16, bindings: KeyBindings) -> InputAction? {
    guard let action = bindings.resolve(keyCode: keyCode), !action.isMaskAction else { return nil }
    return action
}
