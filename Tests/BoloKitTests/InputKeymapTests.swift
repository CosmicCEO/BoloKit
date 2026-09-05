import Testing
import BoloKit

// MARK: - inputFlagsChange (D88 §2)

@Test(arguments: [
    (UInt16(0), InputFlags.turnL),
    (UInt16(2), InputFlags.turnR),
    (UInt16(12), InputFlags.decre),
    (UInt16(14), InputFlags.incre),
    (UInt16(49), InputFlags.shoot),
    (UInt16(56), InputFlags.lmine),
])
func inputFlagsChangeSimpleBindingsSetOnDownClearOnUp(keyCode: UInt16, flag: InputFlags) {
    #expect(inputFlagsChange(forKeyCode: keyCode, isDown: true) == KeyInputChange(set: flag))
    #expect(inputFlagsChange(forKeyCode: keyCode, isDown: false) == KeyInputChange(clear: flag))
}

@Test func inputFlagsChangeAccelerateDownSetsAccelAndClearsBrake() {
    #expect(inputFlagsChange(forKeyCode: 13, isDown: true) == KeyInputChange(set: .accel, clear: .brake))
}

@Test func inputFlagsChangeAccelerateUpSetsBrakeAndClearsAccel() {
    // The autoSlowdownBool==true default: releasing Accelerate auto-applies Brake.
    #expect(inputFlagsChange(forKeyCode: 13, isDown: false) == KeyInputChange(set: .brake, clear: .accel))
}

@Test func inputFlagsChangeBrakeKeyIsUnbound() {
    // Keycode 1 (S) — dead under the shipped autoSlowdownBool==true default (see file header).
    #expect(inputFlagsChange(forKeyCode: 1, isDown: true) == nil)
    #expect(inputFlagsChange(forKeyCode: 1, isDown: false) == nil)
}

@Test func inputFlagsChangeUnknownKeycodeIsUnbound() {
    #expect(inputFlagsChange(forKeyCode: 999, isDown: true) == nil)
}

@Test func lmineKeyCodeConstantMatchesTheLiteralDefault() {
    #expect(lmineKeyCode == 56)
}
