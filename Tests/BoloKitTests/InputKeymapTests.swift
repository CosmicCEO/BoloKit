import Testing
import BoloKit

// MARK: - KeyBindings defaults (D128 backlog C.1)

@Test func defaultBindingsMatchTheReferencePlistLiterals() {
    let expected: [InputAction: UInt16] = [
        .turnLeft: 0, .brake: 1, .turnRight: 2, .decreaseAim: 12, .accelerate: 13,
        .increaseAim: 14, .shoot: 49, .layMine: 56, .tankView: 7, .pillView: 8,
        .scrollUp: 126, .scrollDown: 125, .scrollLeft: 123, .scrollRight: 124,
    ]
    for (action, keyCode) in expected {
        #expect(KeyBindings.default.keyCode(for: action) == keyCode)
    }
}

@Test func everyActionHasADefaultBinding() {
    for action in InputAction.allCases {
        #expect(KeyBindings.default.keyCode(for: action) != nil)
    }
}

// MARK: - inputFlagsChange (mask actions)

@Test(arguments: [
    (UInt16(0), InputFlags.turnL),
    (UInt16(2), InputFlags.turnR),
    (UInt16(12), InputFlags.decre),
    (UInt16(14), InputFlags.incre),
    (UInt16(49), InputFlags.shoot),
    (UInt16(56), InputFlags.lmine),
])
func inputFlagsChangeSimpleBindingsSetOnDownClearOnUp(keyCode: UInt16, flag: InputFlags) {
    #expect(inputFlagsChange(forKeyCode: keyCode, isDown: true, bindings: .default) == KeyInputChange(set: flag))
    #expect(inputFlagsChange(forKeyCode: keyCode, isDown: false, bindings: .default) == KeyInputChange(clear: flag))
}

@Test func inputFlagsChangeAccelerateDownSetsAccelAndClearsBrake() {
    #expect(inputFlagsChange(forKeyCode: 13, isDown: true, bindings: .default) == KeyInputChange(set: .accel, clear: .brake))
}

@Test func inputFlagsChangeAccelerateUpSetsBrakeAndClearsAccel() {
    // The autoSlowdownBool==true default: releasing Accelerate auto-applies Brake.
    #expect(inputFlagsChange(forKeyCode: 13, isDown: false, bindings: .default) == KeyInputChange(set: .brake, clear: .accel))
}

@Test func inputFlagsChangeBrakeKeyIsUnbound() {
    // Keycode 1 (S) — dead under the shipped autoSlowdownBool==true default (see file header).
    #expect(inputFlagsChange(forKeyCode: 1, isDown: true, bindings: .default) == nil)
    #expect(inputFlagsChange(forKeyCode: 1, isDown: false, bindings: .default) == nil)
}

@Test func inputFlagsChangeUnknownKeycodeIsUnbound() {
    #expect(inputFlagsChange(forKeyCode: 999, isDown: true, bindings: .default) == nil)
}

@Test func inputFlagsChangeViewActionsHaveNoMaskEffect() {
    // Up arrow defaults to .scrollUp — a view action, not an InputFlags mask.
    #expect(inputFlagsChange(forKeyCode: 126, isDown: true, bindings: .default) == nil)
}

// MARK: - nonMaskAction (view actions)

@Test func nonMaskActionResolvesTheFourScrollActionsAndTheTwoCenterActions() {
    #expect(nonMaskAction(forKeyCode: 126, bindings: .default) == .scrollUp)
    #expect(nonMaskAction(forKeyCode: 125, bindings: .default) == .scrollDown)
    #expect(nonMaskAction(forKeyCode: 123, bindings: .default) == .scrollLeft)
    #expect(nonMaskAction(forKeyCode: 124, bindings: .default) == .scrollRight)
    #expect(nonMaskAction(forKeyCode: 7, bindings: .default) == .tankView)
    #expect(nonMaskAction(forKeyCode: 8, bindings: .default) == .pillView)
}

@Test func nonMaskActionReturnsNilForAMaskActionsKeycode() {
    // Keycode 49 (Space) defaults to .shoot -- a mask action, not a view action.
    #expect(nonMaskAction(forKeyCode: 49, bindings: .default) == nil)
}

// MARK: - rebind / resolve

@Test func rebindMovesTheBindingAndOldKeycodeStopsResolving() {
    let rebound = KeyBindings.default.rebind(.shoot, to: 6)
    #expect(rebound.keyCode(for: .shoot) == 6)
    #expect(rebound.resolve(keyCode: 6) == .shoot)
    #expect(rebound.resolve(keyCode: 49) == nil)
}

@Test func rebindLeavesOtherActionsUntouched() {
    let rebound = KeyBindings.default.rebind(.shoot, to: 6)
    #expect(rebound.keyCode(for: .turnLeft) == KeyBindings.default.keyCode(for: .turnLeft))
}

@Test func resolveOnACollisionPicksTheFirstActionInDeclarationOrder() {
    // No conflict rejection (matches the reference's applyKeyConfig: exactly) -- binding
    // .turnRight onto TurnLeft's default key (0) means both report keycode 0, but resolve(_:)
    // returns .turnLeft since it's declared first in InputAction.allCases.
    let collided = KeyBindings.default.rebind(.turnRight, to: 0)
    #expect(collided.keyCode(for: .turnLeft) == 0)
    #expect(collided.keyCode(for: .turnRight) == 0)
    #expect(collided.resolve(keyCode: 0) == .turnLeft)
}

// MARK: - dictionaryRepresentation persistence round-trip

@Test func dictionaryRepresentationRoundTripsThroughAFreshKeyBindings() {
    let rebound = KeyBindings.default.rebind(.shoot, to: 6).rebind(.tankView, to: 17)
    let reloaded = KeyBindings(dictionaryRepresentation: rebound.dictionaryRepresentation)
    for action in InputAction.allCases {
        #expect(reloaded.keyCode(for: action) == rebound.keyCode(for: action))
    }
}

@Test func dictionaryRepresentationInitFillsMissingActionsFromDefault() {
    // Simulates loading an older save that predates an action being added.
    let partial = KeyBindings(dictionaryRepresentation: ["shoot": 6])
    #expect(partial.keyCode(for: .shoot) == 6)
    #expect(partial.keyCode(for: .turnLeft) == KeyBindings.default.keyCode(for: .turnLeft))
}

// MARK: - D137: builder-tool selection (digit keys 1-5, not rebindable)

@Test func builderToolMapsKeyCodes18Through21And23ToTheFiveTools() {
    #expect(builderTool(forKeyCode: 18) == .tree)
    #expect(builderTool(forKeyCode: 19) == .road)
    #expect(builderTool(forKeyCode: 20) == .wall)
    #expect(builderTool(forKeyCode: 21) == .pill)
    #expect(builderTool(forKeyCode: 23) == .mine)
}

@Test func builderToolKeyCode22IsUnbound() {
    // The reference's own hardcoded chain skips keyCode 22 ("6") — not a transcription gap.
    #expect(builderTool(forKeyCode: 22) == nil)
}

@Test func builderToolUnrelatedKeyCodeIsUnbound() {
    #expect(builderTool(forKeyCode: 13) == nil)  // W (accelerate)
}
