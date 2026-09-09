//
//  AlliancePanelView.swift
//  Bolo 2026
//
//  C.2 (D128): the port's equivalent of `GSXBoloController.m`'s `playerInfoTableView` +
//  "Request Alliance"/"Leave Alliance" buttons (`requestAlliance:`/`leaveAlliance:` IBActions,
//  `client.c:6314-6455`'s `requestalliance()`/`leavealliance()`). The reference has no accept/deny
//  dialog -- "request" is unilateral-until-mutual (the C's own "requested alliance with X" vs.
//  "alliance accepted with X" distinction, purely a printed message, not a UI state), so this
//  panel is the same shape: multi-select other players, press a button, the underlying bitmask
//  math (`SessionLogic.swift`'s `requestAlliance`/`leaveAlliance`) decides whether it went mutual.
//
//  Same "poll session.state via TimelineView" convention as `PlayerStatusView` (`GameSession` is
//  deliberately not `ObservableObject` -- see that view's own header) and the same three-way
//  Friendly/Allied/Hostile classification via `testAlliance`.
//
//  Every player has this right, not just the host (unlike Kick/Ban's `canKickBan` gate, C.0/D119)
//  -- matches the reference, where `requestAlliance:`/`leaveAlliance:` are plain client-side
//  `IBAction`s with no server-role check at all.

import BoloKit
import SwiftUI

struct AlliancePanelView: View {
    let session: GameSession
    let onDone: () -> Void

    @State private var selection: Set<Int> = []

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            panel(snapshot: session.state)
        }
    }

    private func panel(snapshot: GameState) -> some View {
        let otherPlayers = snapshot.players.indices.filter {
            $0 != snapshot.localPlayer && snapshot.players[$0].connected
        }
        return NavigationStack {
            List(selection: $selection) {
                Section("Players") {
                    ForEach(otherPlayers, id: \.self) { index in
                        row(index, snapshot: snapshot)
                    }
                }
            }
            .navigationTitle("Alliances")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onDone)
                }
            }
            .safeAreaInset(edge: .bottom) {
                HStack {
                    Button("Request Alliance") {
                        session.requestAlliance(bitmask(for: selection))
                    }
                    .disabled(selection.isEmpty)
                    Button("Leave Alliance") {
                        session.leaveAlliance(bitmask(for: selection))
                    }
                    .disabled(selection.isEmpty)
                }
                .padding(8)
            }
        }
        .frame(minWidth: 360, minHeight: 420)
    }

    private func bitmask(for selection: Set<Int>) -> UInt16 {
        selection.reduce(UInt16(0)) { $0 | UInt16(1 << $1) }
    }

    private func status(forPlayer index: Int, snapshot: GameState) -> (label: String, tint: Color) {
        if testAlliance(snapshot.localPlayer, index, players: snapshot.players) {
            return ("Allied", .blue)
        }
        return ("Hostile", .red)
    }

    @ViewBuilder
    private func row(_ index: Int, snapshot: GameState) -> some View {
        let player = snapshot.players[index]
        let status = status(forPlayer: index, snapshot: snapshot)
        HStack {
            Circle().fill(status.tint).frame(width: 10, height: 10)
            Text(player.name.isEmpty ? "Player \(index)" : player.name)
            Spacer()
            Text(status.label).foregroundStyle(.secondary)
        }
        .tag(index)
    }
}
