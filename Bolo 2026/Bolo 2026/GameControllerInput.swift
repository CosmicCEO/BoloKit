//
//  GameControllerInput.swift
//  Bolo 2026
//
//  Issue #17: game-controller mapping to InputFlags. `controllerDigitalInputs(for:deadzone:)`
//  and `controllerEdges(from:to:)` take a plain `ControllerSnapshot` value, not
//  `GCExtendedGamepad` -- GameController's own gamepad types have no public initializer (only a
//  connected physical/virtual controller ever vends one), so a pure function signed against them
//  would be unwritable from `swift test`/`Bolo 2026Tests` at all. `GameControllerInputHandler` is
//  the thin, untested-by-necessity adapter that reads a real `GCExtendedGamepad`'s live state
//  into a `ControllerSnapshot` each time any element changes.
//
//  Deadzone and every analog reading are `Float` (AGENTS.md: never `Double`/`CGFloat` for a
//  position/physics-adjacent value).
//
//  No polling timer: `GameRenderView` deliberately owns no clock of its own (D82,
//  `GameRenderView.swift`'s file header), and `GameSession`'s host-path header separately warns
//  against a second ticker racing the tick loop -- this instead reuses
//  `GCExtendedGamepad.valueChangedHandler`, which fires once per physical element change, plus
//  `GCController` connect/disconnect notifications to attach/detach that handler as controllers
//  come and go.
//
//  Routes through `GameRenderView.onInputFlagsChange`/`onLayMineKeyDown`/`performViewAction` --
//  the same closures/method the keyboard path (`GameRenderView.applyKeyChange`) already drives,
//  which all three of `GameSession`'s paths (single-process/host/join) already wire per-path.
//  Controller support therefore lands on all three paths for free, with no path-specific code in
//  `GameSession.swift`.
//
//  10 of the 14 `InputAction`s get a controller mapping this pass (8 mask actions plus
//  tank-view/pill-view); the 4 scroll view-actions do not -- see
//  `controllerDigitalInputs(for:deadzone:)`'s own doc comment for why (a held analog stick can't
//  reproduce the keyboard's per-keypress discrete nudge without a polling clock this view
//  deliberately doesn't have).

import BoloKit
import GameController

/// A plain-value snapshot of a `GCExtendedGamepad`'s live state -- the seam that keeps
/// `controllerDigitalInputs(for:deadzone:)` unit-testable. `nonisolated` (along with every other
/// pure declaration in this file below) because the app target's `SWIFT_DEFAULT_ACTOR_ISOLATION
/// = MainActor` build setting would otherwise isolate it to the main actor, making it
/// uncallable from `Bolo 2026Tests`'s plain (non-`@MainActor`) `@Test` functions.
public nonisolated struct ControllerSnapshot: Equatable, Sendable {
    public var leftThumbstickX: Float
    public var leftThumbstickY: Float
    public var dpadUp: Bool
    public var dpadDown: Bool
    public var dpadLeft: Bool
    public var dpadRight: Bool
    public var buttonA: Bool
    public var buttonB: Bool
    public var buttonX: Bool
    public var buttonY: Bool
    public var leftShoulder: Bool
    public var rightShoulder: Bool

    public init(
        leftThumbstickX: Float = 0, leftThumbstickY: Float = 0,
        dpadUp: Bool = false, dpadDown: Bool = false, dpadLeft: Bool = false, dpadRight: Bool = false,
        buttonA: Bool = false, buttonB: Bool = false, buttonX: Bool = false, buttonY: Bool = false,
        leftShoulder: Bool = false, rightShoulder: Bool = false
    ) {
        self.leftThumbstickX = leftThumbstickX
        self.leftThumbstickY = leftThumbstickY
        self.dpadUp = dpadUp
        self.dpadDown = dpadDown
        self.dpadLeft = dpadLeft
        self.dpadRight = dpadRight
        self.buttonA = buttonA
        self.buttonB = buttonB
        self.buttonX = buttonX
        self.buttonY = buttonY
        self.leftShoulder = leftShoulder
        self.rightShoulder = rightShoulder
    }
}

/// Fixed control scheme (not rebindable, unlike `KeyBindings` -- no controller-remap UI exists),
/// mapping a live `ControllerSnapshot` to the set of `InputAction`s currently held: left
/// stick/D-pad for movement (mask actions), face buttons for shoot/lay-mine/tank-view/pill-view,
/// shoulders for aim increase/decrease. `deadzone` gates analog-stick noise from registering as a
/// digital press.
///
/// **Disclosed scope:** the 4 scroll view-actions have no controller mapping here. They're
/// discrete per-key-press nudges on the keyboard (`GameRenderView.performViewAction`'s `scroll(dx:
/// dy:)` calls) -- an analog stick held past the deadzone would report exactly one rising edge,
/// then nothing until released, so it would visually nudge the map once and then silently stop
/// doing anything while still held. Repeat-while-held would need a polling clock, which
/// `GameRenderView` deliberately doesn't have (D82, this file's own header) -- not a gap this
/// pass closes.
public nonisolated func controllerDigitalInputs(for snapshot: ControllerSnapshot, deadzone: Float) -> Set<InputAction> {
    var actions: Set<InputAction> = []
    if snapshot.dpadLeft || snapshot.leftThumbstickX < -deadzone { actions.insert(.turnLeft) }
    if snapshot.dpadRight || snapshot.leftThumbstickX > deadzone { actions.insert(.turnRight) }
    if snapshot.dpadUp || snapshot.leftThumbstickY > deadzone { actions.insert(.accelerate) }
    if snapshot.dpadDown || snapshot.leftThumbstickY < -deadzone { actions.insert(.brake) }
    if snapshot.buttonA { actions.insert(.shoot) }
    if snapshot.buttonB { actions.insert(.layMine) }
    if snapshot.rightShoulder { actions.insert(.increaseAim) }
    if snapshot.leftShoulder { actions.insert(.decreaseAim) }
    if snapshot.buttonX { actions.insert(.tankView) }
    if snapshot.buttonY { actions.insert(.pillView) }
    return actions
}

/// One momentary transition an `InputAction` made between two `controllerDigitalInputs` polls --
/// `isDown == true` on a rising edge (newly held), `false` on a falling edge (newly released).
/// Mirrors the keyboard path's own key-down/key-up shape (`GameRenderView.applyKeyChange`).
public nonisolated struct ControllerActionEdge: Hashable, Sendable {
    public var action: InputAction
    public var isDown: Bool

    public init(action: InputAction, isDown: Bool) {
        self.action = action
        self.isDown = isDown
    }
}

/// Diffs two `controllerDigitalInputs` snapshots into an ordered list of edges -- iterates
/// `InputAction.allCases` (not a `Set` difference) so output order is deterministic and callers
/// (and tests) never see it vary run to run.
public nonisolated func controllerEdges(from previous: Set<InputAction>, to current: Set<InputAction>) -> [ControllerActionEdge] {
    InputAction.allCases.compactMap { action in
        let was = previous.contains(action)
        let now = current.contains(action)
        guard was != now else { return nil }
        return ControllerActionEdge(action: action, isDown: now)
    }
}

/// Wires a connected `GCExtendedGamepad`'s live state into a `GameRenderView`, the same
/// `InputFlags`/lay-mine/view-action surface the keyboard path already drives (file header).
///
/// Subclasses `NSObject` and uses the selector-based `NotificationCenter` API (rather than
/// storing block-based observer tokens as properties) so `deinit` only ever calls
/// `removeObserver(self)` -- storing an `NSObjectProtocol` token would make this class's
/// (implicitly nonisolated) `deinit` try to touch a non-`Sendable` stored property, which the
/// Swift 6 strict-concurrency checker rejects outright.
@MainActor
public final class GameControllerInputHandler: NSObject {
    /// Matches `GCControllerAxisInput`'s own documented thumbstick noise floor -- the standard
    /// HIG-recommended default, not independently re-derived.
    public static let defaultDeadzone: Float = 0.2

    private weak var renderView: GameRenderView?
    private let deadzone: Float
    private var heldActions: Set<InputAction> = []

    public init(renderView: GameRenderView, deadzone: Float = GameControllerInputHandler.defaultDeadzone) {
        self.renderView = renderView
        self.deadzone = deadzone
        super.init()
        for controller in GCController.controllers() {
            attach(controller)
        }
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleControllerDidConnect(_:)),
            name: .GCControllerDidConnect, object: nil
        )
        NotificationCenter.default.addObserver(
            self, selector: #selector(handleControllerDidDisconnect(_:)),
            name: .GCControllerDidDisconnect, object: nil
        )
    }

    deinit {
        NotificationCenter.default.removeObserver(self)
    }

    /// `GCControllerDidConnect`/`GCControllerDidDisconnect` are always posted on the main queue
    /// (`GCController` framework contract) -- `MainActor.assumeIsolated` documents that
    /// guarantee at the one call site that depends on it, rather than hopping through an extra
    /// `Task` for a call that's synchronously already on this actor's executor.
    @objc private func handleControllerDidConnect(_ note: Notification) {
        MainActor.assumeIsolated {
            guard let controller = note.object as? GCController else { return }
            attach(controller)
        }
    }

    @objc private func handleControllerDidDisconnect(_ note: Notification) {
        MainActor.assumeIsolated {
            heldActions = []
        }
    }

    private func attach(_ controller: GCController) {
        guard let gamepad = controller.extendedGamepad else { return }
        gamepad.valueChangedHandler = { [weak self] gamepad, _ in
            // `valueChangedHandler` isn't guaranteed to fire on the main thread, unlike the
            // connect/disconnect notifications above -- read every (`Sendable`) analog/digital
            // value into a plain `ControllerSnapshot` here, synchronously, on whatever thread
            // called this, then hop to the main actor with that value rather than the
            // non-`Sendable` `GCExtendedGamepad` itself.
            let snapshot = ControllerSnapshot(
                leftThumbstickX: gamepad.leftThumbstick.xAxis.value,
                leftThumbstickY: gamepad.leftThumbstick.yAxis.value,
                dpadUp: gamepad.dpad.up.isPressed,
                dpadDown: gamepad.dpad.down.isPressed,
                dpadLeft: gamepad.dpad.left.isPressed,
                dpadRight: gamepad.dpad.right.isPressed,
                buttonA: gamepad.buttonA.isPressed,
                buttonB: gamepad.buttonB.isPressed,
                buttonX: gamepad.buttonX.isPressed,
                buttonY: gamepad.buttonY.isPressed,
                leftShoulder: gamepad.leftShoulder.isPressed,
                rightShoulder: gamepad.rightShoulder.isPressed
            )
            Task { @MainActor [weak self] in self?.handle(snapshot) }
        }
    }

    private func handle(_ snapshot: ControllerSnapshot) {
        guard let renderView else { return }
        let current = controllerDigitalInputs(for: snapshot, deadzone: deadzone)
        let edges = controllerEdges(from: heldActions, to: current)
        heldActions = current
        for edge in edges {
            apply(edge, to: renderView)
        }
    }

    private func apply(_ edge: ControllerActionEdge, to renderView: GameRenderView) {
        if let change = inputFlagsChange(forAction: edge.action, isDown: edge.isDown) {
            renderView.onInputFlagsChange?(change)
            if edge.action == .layMine, edge.isDown {
                renderView.onLayMineKeyDown?()
            }
            return
        }
        guard edge.isDown else { return }
        renderView.performViewAction(edge.action)
    }
}
