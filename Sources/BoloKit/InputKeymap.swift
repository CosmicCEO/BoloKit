// MARK: - Wave 7.3 (D88) — literal default keymap
//
// Ported from `Reference/c/en.lproj/DefaultPreferences.plist`'s `GSKeyConfigDict` (the C
// client's *shipped default* key-remap dictionary — decoded directly, not guessed) plus the
// literal behavior of `keyevent()` (`Reference/c/Mac OS X/GSXBoloController.m:1650-1690`) under
// that plist's other shipped default, `GSAutoSlowdownBool == true`.
//
// No key-remap UI exists in this port yet (Milestone C) — this hardcodes the shipped defaults as
// v1's only bindings rather than modeling a remappable dictionary with nothing to remap it with.
//
// Deliberately placed in `BoloKit` rather than the `Bolo 2026` app target purely for testability:
// it takes a raw macOS virtual keycode (`UInt16`) and a down/up `Bool`, both plain types with no
// `AppKit`/`NSEvent` dependency, so it can run under `swift test` rather than needing an app-target
// UI test — the app target's `GameRenderView.keyDown`/`keyUp`/`flagsChanged` are the only callers,
// translating a real `NSEvent` into these two primitives before calling in.
//
// **Brake (keycode 1/S) is deliberately unbound, not an oversight:** under the shipped
// `autoSlowdownBool == true` default, C's own `keyevent()` only actually applies `BRAKEMASK` from
// the *release* of Accelerate (`keyevent(BRAKEMASK, !event)` in the `ACCELMASK` branch) — the
// explicit Brake-key branch is gated `if (!autoSlowdownBool)`, dead code under the shipped
// default. Binding keycode 1 to `.brake` here would only ever fire a redundant, immediately-
// overwritten set, never a distinguishable behavior.

/// The `InputFlags` bits to set/clear for one key transition, or `nil` for an unbound key.
public struct KeyInputChange: Equatable, Sendable {
    public var set: InputFlags
    public var clear: InputFlags

    public init(set: InputFlags = [], clear: InputFlags = []) {
        self.set = set
        self.clear = clear
    }
}

/// Virtual keycode for the LMINE binding (Shift, `GSKeyConfigDict` key `56`) — a modifier key,
/// so its transitions arrive via `flagsChanged`, not `keyDown`/`keyUp`; callers still route it
/// through `inputFlagsChange(forKeyCode:isDown:)` like every other binding. Exposed publicly so
/// the app target's `flagsChanged` handler doesn't need to re-hardcode the literal value.
public let lmineKeyCode: UInt16 = 56

/// Translates one key-down/key-up transition into the `InputFlags` change it causes, per the
/// literal default keymap described above. Returns `nil` for any keycode with no binding.
public func inputFlagsChange(forKeyCode keyCode: UInt16, isDown: Bool) -> KeyInputChange? {
    switch keyCode {
    case 0:  // A — TURNLMASK
        return isDown ? KeyInputChange(set: .turnL) : KeyInputChange(clear: .turnL)
    case 2:  // D — TURNRMASK
        return isDown ? KeyInputChange(set: .turnR) : KeyInputChange(clear: .turnR)
    case 12:  // Q — DECREMASK
        return isDown ? KeyInputChange(set: .decre) : KeyInputChange(clear: .decre)
    case 14:  // E — INCREMASK
        return isDown ? KeyInputChange(set: .incre) : KeyInputChange(clear: .incre)
    case 49:  // Space — SHOOTMASK
        return isDown ? KeyInputChange(set: .shoot) : KeyInputChange(clear: .shoot)
    case lmineKeyCode:  // Shift — LMINEMASK
        return isDown ? KeyInputChange(set: .lmine) : KeyInputChange(clear: .lmine)
    case 13:  // W — ACCELMASK, plus the autoSlowdownBool==true auto-brake coupling
        return isDown
            ? KeyInputChange(set: .accel, clear: .brake)
            : KeyInputChange(set: .brake, clear: .accel)
    default:
        return nil
    }
}
