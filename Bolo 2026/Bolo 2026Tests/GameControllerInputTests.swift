//
//  GameControllerInputTests.swift
//  Bolo 2026Tests
//
//  Issue #17: unit tests for the pure controller-mapping logic in `GameControllerInput.swift`.
//  Only `controllerDigitalInputs(for:deadzone:)`/`controllerEdges(from:to:)` are exercised here --
//  `GameControllerInputHandler` itself needs a real `GCExtendedGamepad`, which has no public
//  initializer, so it isn't (and can't be) unit-tested (see that file's own header).

import Testing
import BoloKit

@testable import Bolo_2026

private let deadzone: Float = 0.2

// MARK: - controllerDigitalInputs (digital buttons/D-pad)

@Test func digitalInputsMapsDpadDirectionsToTurnAndAccelerateActions() {
    let snapshot = ControllerSnapshot(dpadUp: true, dpadDown: false, dpadLeft: true, dpadRight: false)
    let actions = controllerDigitalInputs(for: snapshot, deadzone: deadzone)
    #expect(actions.contains(.accelerate))
    #expect(actions.contains(.turnLeft))
    #expect(!actions.contains(.brake))
    #expect(!actions.contains(.turnRight))
}

@Test func digitalInputsMapsFaceButtonsToShootLayMineTankViewPillView() {
    let snapshot = ControllerSnapshot(buttonA: true, buttonB: true, buttonX: true, buttonY: true)
    let actions = controllerDigitalInputs(for: snapshot, deadzone: deadzone)
    #expect(actions == [.shoot, .layMine, .tankView, .pillView])
}

@Test func digitalInputsMapsShouldersToAim() {
    let snapshot = ControllerSnapshot(leftShoulder: true, rightShoulder: false)
    #expect(controllerDigitalInputs(for: snapshot, deadzone: deadzone) == [.decreaseAim])
    let snapshot2 = ControllerSnapshot(leftShoulder: false, rightShoulder: true)
    #expect(controllerDigitalInputs(for: snapshot2, deadzone: deadzone) == [.increaseAim])
}

@Test func digitalInputsNoInputProducesEmptySet() {
    #expect(controllerDigitalInputs(for: ControllerSnapshot(), deadzone: deadzone).isEmpty)
}

// MARK: - controllerDigitalInputs (analog thumbsticks + deadzone)

@Test func digitalInputsLeftThumbstickBelowDeadzoneRegistersNothing() {
    let snapshot = ControllerSnapshot(leftThumbstickX: 0.1, leftThumbstickY: -0.1)
    #expect(controllerDigitalInputs(for: snapshot, deadzone: deadzone).isEmpty)
}

@Test func digitalInputsLeftThumbstickPastDeadzoneRegistersTurnAndAccelerate() {
    let snapshot = ControllerSnapshot(leftThumbstickX: 0.9, leftThumbstickY: 0.5)
    let actions = controllerDigitalInputs(for: snapshot, deadzone: deadzone)
    #expect(actions == [.turnRight, .accelerate])
}

@Test func digitalInputsLeftThumbstickNegativeYRegistersBrake() {
    let snapshot = ControllerSnapshot(leftThumbstickY: -0.9)
    #expect(controllerDigitalInputs(for: snapshot, deadzone: deadzone) == [.brake])
}

@Test func digitalInputsDpadAndThumbstickAreEquivalentAlternatives() {
    let viaDpad = ControllerSnapshot(dpadRight: true)
    let viaStick = ControllerSnapshot(leftThumbstickX: 0.5)
    #expect(controllerDigitalInputs(for: viaDpad, deadzone: deadzone) == controllerDigitalInputs(for: viaStick, deadzone: deadzone))
}

// MARK: - controllerEdges

@Test func edgesEmptyToHeldProducesDownEdges() {
    let edges = controllerEdges(from: [], to: [.turnLeft, .shoot])
    #expect(Set(edges) == [ControllerActionEdge(action: .turnLeft, isDown: true), ControllerActionEdge(action: .shoot, isDown: true)])
}

@Test func edgesHeldToEmptyProducesUpEdges() {
    let edges = controllerEdges(from: [.turnLeft, .shoot], to: [])
    #expect(Set(edges) == [ControllerActionEdge(action: .turnLeft, isDown: false), ControllerActionEdge(action: .shoot, isDown: false)])
}

@Test func edgesUnchangedActionsProduceNoEdge() {
    #expect(controllerEdges(from: [.turnLeft], to: [.turnLeft]).isEmpty)
}

@Test func edgesOrderMatchesInputActionDeclarationOrderNotInsertionOrder() {
    // .accelerate is declared before .turnLeft in `InputAction.allCases` -- inserted here in the
    // opposite order to prove the output order comes from `allCases`, not `Set` iteration.
    let edges = controllerEdges(from: [], to: [.turnLeft, .accelerate])
    #expect(edges.map(\.action) == [.accelerate, .turnLeft])
}

@Test func edgesMixOfDownAndUpTransitionsAreBothReported() {
    let edges = controllerEdges(from: [.turnLeft], to: [.turnRight])
    #expect(Set(edges) == [ControllerActionEdge(action: .turnLeft, isDown: false), ControllerActionEdge(action: .turnRight, isDown: true)])
}
