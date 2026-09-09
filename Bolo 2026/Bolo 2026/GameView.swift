//
//  GameView.swift
//  Bolo 2026
//
//  Wave 7.3 (D88): closes the loop -- driven by a real `GameSession` tick loop, not a frozen
//  snapshot.
//
//  Milestone B.1: renamed from `ContentView` -- once `AppRootView` exists, this is one of two
//  screens, not the app's whole root content, so the SwiftUI-template name no longer described
//  its role. Gained an `onQuitToMenu` exit path so the shell's round trip (matching
//  `GSXBoloController`'s own new-game-window <-> bolo-window shape) works in both directions.
//
//  Milestone B.2: `initialState` is now caller-supplied rather than a hardcoded demo terrain --
//  either `AppRootView.demoState` (the B.1 "Play Demo" scaffolding) or a real map decoded by
//  `HostGameView`. This view has no opinion on where its state came from.
//
//  Milestone B.7 (D108): a second init now exists for the host path, taking an already-`start()`ed
//  `HostGameEngine` instead of a bare `GameState` -- see `GameSession`'s own header for why that
//  class needs to know which path it's on. `session.stop()` is `async` now (both paths go through
//  it), so its two call sites below hop into a `Task`.
//
//  Milestone B.7 (D109): `notice`, an optional banner shown in the same top bar as "Quit to Menu"
//  -- currently only used for `AppRootView.hostingFallback`'s "running local-only" disclosure when
//  a real listener couldn't be constructed (see `HostGameView.swift`'s own header), but not tied
//  to that case specifically; any caller of the local-only `init` can supply one.
//
//  Milestone B.8 (D113): a third init for the join path, taking the already-live `TCPSession`/
//  `UDPSession` pair `JoinGameView` established -- see `GameSession`'s own header for the
//  merged-event-stream consumer that drives this path instead of a bare tick loop.
//

import BoloKit
import BoloNet
import SwiftUI

struct GameView: View {
    let onQuitToMenu: () -> Void
    let notice: String?

    @State private var session: GameSession
    @State private var showingStatus = false
    @State private var showingMessages = false

    init(initialState: GameState, onQuitToMenu: @escaping () -> Void, notice: String? = nil) {
        self.onQuitToMenu = onQuitToMenu
        self.notice = notice
        let (tiles, sprites) = Self.loadSheets()
        _session = State(
            initialValue: GameSession(initialState: initialState, tilesImage: tiles, spritesImage: sprites)
        )
    }

    init(hostEngine: HostGameEngine, onQuitToMenu: @escaping () -> Void) {
        self.onQuitToMenu = onQuitToMenu
        self.notice = nil
        let (tiles, sprites) = Self.loadSheets()
        _session = State(
            initialValue: GameSession(hostEngine: hostEngine, tilesImage: tiles, spritesImage: sprites)
        )
    }

    init(
        tcpSession: TCPSession, udpSession: UDPSession, initialState: GameState,
        onQuitToMenu: @escaping () -> Void
    ) {
        self.onQuitToMenu = onQuitToMenu
        self.notice = nil
        let (tiles, sprites) = Self.loadSheets()
        _session = State(
            initialValue: GameSession(
                tcpSession: tcpSession, udpSession: udpSession, initialState: initialState,
                tilesImage: tiles, spritesImage: sprites
            )
        )
    }

    private static func loadSheets() -> (tiles: CGImage, sprites: CGImage) {
        guard let tiles = loadSheetImage(named: "Tiles"),
            let sprites = loadSheetImage(named: "Sprites")
        else {
            fatalError("Tiles.png/Sprites.png missing from the bundle -- D72's Run Script phase should guarantee this")
        }
        return (tiles, sprites)
    }

    var body: some View {
        ScrollView([.horizontal, .vertical]) {
            GameRenderRepresentable(session: session)
        }
        .frame(minWidth: 480, minHeight: 360)
        .onAppear { session.start() }
        .onDisappear { Task { @MainActor in await session.stop() } }
        .safeAreaInset(edge: .top) {
            HStack {
                if let notice {
                    Text(notice).foregroundStyle(.orange)
                }
                Spacer()
                Button("Status") { showingStatus = true }
                Button("Messages") { showingMessages = true }
                Button("Quit to Menu") {
                    Task { @MainActor in
                        await session.stop()
                        onQuitToMenu()
                    }
                }
            }
            .padding(8)
        }
        .sheet(isPresented: $showingStatus) {
            PlayerStatusView(session: session, onDone: { showingStatus = false })
        }
        .sheet(isPresented: $showingMessages) {
            MessagesView(session: session, onDone: { showingMessages = false })
        }
    }
}

#Preview {
    GameView(initialState: AppRootView.demoState, onQuitToMenu: {})
}
