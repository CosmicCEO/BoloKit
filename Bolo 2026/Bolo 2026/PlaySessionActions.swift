import SwiftUI

/// Menu/key-equivalent surface for a live `GameView`. Closures, not observation —
/// `GameSession` is not `ObservableObject`.
struct PlaySessionActions {
    var canPauseResume: Bool
    var pauseResume: () -> Void
    var toggleMute: () -> Void
    var zoomIn: () -> Void
    var zoomOut: () -> Void
    var showStatus: () -> Void
    var showAlliances: () -> Void
    var showMessages: () -> Void
    var quitToMenu: () -> Void

    static let muteDefaultsKey = "GSMuteBool"

    static func make(
        session: GameSession,
        reclaimFocus: @escaping () -> Void,
        setShowingStatus: @escaping (Bool) -> Void,
        setShowingAlliances: @escaping (Bool) -> Void,
        setShowingMessages: @escaping (Bool) -> Void,
        onQuitToMenu: @escaping () -> Void
    ) -> PlaySessionActions {
        PlaySessionActions(
            canPauseResume: session.canHostAdmin,
            pauseResume: {
                session.pauseResumeServer()
                reclaimFocus()
            },
            toggleMute: {
                let defaults = UserDefaults.standard
                defaults.set(!defaults.bool(forKey: muteDefaultsKey), forKey: muteDefaultsKey)
                reclaimFocus()
            },
            zoomIn: {
                session.renderView.zoomIn()
                reclaimFocus()
            },
            zoomOut: {
                session.renderView.zoomOut()
                reclaimFocus()
            },
            showStatus: {
                setShowingStatus(true)
                reclaimFocus()
            },
            showAlliances: {
                setShowingAlliances(true)
                reclaimFocus()
            },
            showMessages: {
                setShowingMessages(true)
                reclaimFocus()
            },
            quitToMenu: {
                Task { @MainActor in
                    await session.stop()
                    onQuitToMenu()
                }
            }
        )
    }
}

private struct PlaySessionActionsKey: FocusedValueKey {
    typealias Value = PlaySessionActions
}

extension FocusedValues {
    var playSessionActions: PlaySessionActions? {
        get { self[PlaySessionActionsKey.self] }
        set { self[PlaySessionActionsKey.self] = newValue }
    }
}

struct PlayCommands: Commands {
    @FocusedValue(\.playSessionActions) private var actions

    var body: some Commands {
        CommandMenu("Game") {
            Button("Pause/Resume") { actions?.pauseResume() }
                .disabled(actions?.canPauseResume != true)
            Button("Mute") { actions?.toggleMute() }
                .disabled(actions == nil)
            Divider()
            Button("Quit to Menu") { actions?.quitToMenu() }
                .disabled(actions == nil)
        }
        CommandMenu("View") {
            Button("Zoom In") { actions?.zoomIn() }
                .keyboardShortcut("=")
                .disabled(actions == nil)
            Button("Zoom Out") { actions?.zoomOut() }
                .keyboardShortcut("-")
                .disabled(actions == nil)
            Divider()
            Button("Status") { actions?.showStatus() }
                .disabled(actions == nil)
            Button("Alliances") { actions?.showAlliances() }
                .disabled(actions == nil)
            Button("Messages") { actions?.showMessages() }
                .disabled(actions == nil)
        }
    }
}
