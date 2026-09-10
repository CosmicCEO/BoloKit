//
//  PlayerStatusView.swift
//  Bolo 2026
//
//  C.0 (D119): the port's equivalent of `GSXBoloController.m:2103-2419`'s `setPlayerStatus:`/
//  `setPillStatus:`/`setBaseStatus:` -- a 16-slot player status grid plus pill/base ownership
//  rows, each rendered with the same three-way friendly/allied/hostile (or neutral, for pills/
//  bases) image switch the reference hand-codes per method. This port renders one SwiftUI list
//  instead of 16 fixed `NSImageView`s, but the underlying classification is identical:
//  `PlayerState.alliance`/`testAlliance` for players, `Pill.owner`/`Base.owner` + `testAlliance`
//  for pills/bases -- no new model needed (`GameObjects.swift` already carries every field this
//  view reads).
//
//  Confirmed independent of `client.images`/`seentiles`/`fog` (D65/D92) -- this view never reads
//  terrain visibility, only ownership/connection state, matching the reference's own methods.
//
//  Host-only Kick/Ban buttons are gated on `GameSession.canKickBan` (true only on the host path,
//  per that property's own doc comment) -- a join-side or single-process client has no authority
//  to kick/ban anyone, matching the reference (only the server-role menu ever calls
//  `kickplayer()`/`banplayer()`).
//
//  Not live-updating via SwiftUI observation (`GameSession` isn't `ObservableObject` -- its own
//  header explains why: `state` is deliberately not a single source of truth on every path). A
//  `TimelineView` forces a periodic re-render that re-reads `session.state` fresh each time
//  instead, the same "poll, don't observe" shape `GameRenderView` itself already uses each tick.
//
//  D148(B): the grid content used to live inline inside this file's own `NavigationStack`/
//  `.toolbar` sheet chrome. Split into `PlayerStatusGrid` (just the `List` + row logic, no sheet
//  chrome) so the always-visible main-window HUD (`GameView.swift`) can embed the identical
//  content without a "Done" button or navigation title that only make sense in a sheet. This
//  file's own `PlayerStatusView` is now a thin wrapper: `PlayerStatusGrid` + the sheet chrome it
//  always had. No classification logic duplicated or changed.

import BoloKit
import SwiftUI

/// The three-way classification `setPlayerStatus:`/`setPillStatus:`/`setBaseStatus:` each render
/// as a distinct image. `.neutral` only ever applies to pills/bases (no unowned player slot).
enum OwnershipStatus {
    case friendly
    case allied
    case hostile
    case neutral

    var label: String {
        switch self {
        case .friendly: return "Friendly"
        case .allied: return "Allied"
        case .hostile: return "Hostile"
        case .neutral: return "Neutral"
        }
    }

    var tint: Color {
        switch self {
        case .friendly: return .green
        case .allied: return .blue
        case .hostile: return .red
        case .neutral: return .gray
        }
    }
}

/// D148(B): the reusable grid content, independent of sheet-vs-embedded presentation. See this
/// file's header for why it was split out of `PlayerStatusView`.
struct PlayerStatusGrid: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            list(snapshot: session.state)
        }
    }

    private func list(snapshot: GameState) -> some View {
        let connectedPlayerIndices = snapshot.players.indices.filter { snapshot.players[$0].connected }
        return List {
            Section("Players") {
                ForEach(connectedPlayerIndices, id: \.self) { index in
                    playerRow(index, snapshot: snapshot)
                }
            }
            Section("Pillboxes") {
                ForEach(Array(snapshot.pills.enumerated()), id: \.offset) { offset, pill in
                    ownershipRow(name: "Pillbox \(offset)", owner: pill.owner, snapshot: snapshot)
                }
            }
            Section("Bases") {
                ForEach(Array(snapshot.bases.enumerated()), id: \.offset) { offset, base in
                    ownershipRow(name: "Base \(offset)", owner: base.owner, snapshot: snapshot)
                }
            }
        }
    }

    private func status(forPlayer index: Int, snapshot: GameState) -> OwnershipStatus {
        if index == snapshot.localPlayer { return .friendly }
        if testAlliance(snapshot.localPlayer, index, players: snapshot.players) { return .allied }
        return .hostile
    }

    /// **D150(3):** mirrors `setPlayerStatus:`'s connection-staleness coloring
    /// (`GSXBoloController.m:2196-2210`) -- green under `TICKSPERSEC` ticks since the last real
    /// update, yellow from 1x up to (not including) 3x, red background/white text at 3x or more
    /// (thresholds compared with `>=`, matching the reference exactly). `nil` when
    /// `GameSession.connectionAge` has no data for this slot (join/single-process path, or a
    /// disconnected player never assigned an age) -- rendered as today's plain, untinted text.
    private func staleness(forPlayer index: Int) -> LagTint? {
        guard let age = session.connectionAge(for: index) else { return nil }
        let threshold = UInt64(ticksPerSec)
        if age >= threshold * 3 { return .dropped }
        if age >= threshold { return .lagging }
        return .fresh
    }

    private enum LagTint {
        case fresh, lagging, dropped

        var background: Color {
            switch self {
            case .fresh: return .green
            case .lagging: return .yellow
            case .dropped: return .red
            }
        }

        var foreground: Color {
            self == .dropped ? .white : .primary
        }
    }

    @ViewBuilder
    private func playerRow(_ index: Int, snapshot: GameState) -> some View {
        let player = snapshot.players[index]
        let status = status(forPlayer: index, snapshot: snapshot)
        let lag = staleness(forPlayer: index)
        HStack {
            Circle().fill(status.tint).frame(width: 10, height: 10)
            Text(player.name.isEmpty ? "Player \(index)" : player.name)
                .foregroundStyle(lag?.foreground ?? Color.primary)
                .padding(.horizontal, 4)
                .background(lag?.background.opacity(0.6) ?? Color.clear)
            Spacer()
            Text(status.label).foregroundStyle(.secondary)
            if session.canKickBan && index != snapshot.localPlayer {
                Button("Kick") { session.kickPlayer(index) }
                Button("Ban") { session.banPlayer(index) }
            }
        }
    }

    private func ownershipStatus(owner: UInt8, snapshot: GameState) -> OwnershipStatus {
        if owner == playerNeutral { return .neutral }
        let ownerIndex = Int(owner)
        if ownerIndex == snapshot.localPlayer { return .friendly }
        if testAlliance(snapshot.localPlayer, ownerIndex, players: snapshot.players) { return .allied }
        return .hostile
    }

    @ViewBuilder
    private func ownershipRow(name: String, owner: UInt8, snapshot: GameState) -> some View {
        let status = ownershipStatus(owner: owner, snapshot: snapshot)
        HStack {
            Circle().fill(status.tint).frame(width: 10, height: 10)
            Text(name)
            Spacer()
            Text(status.label).foregroundStyle(.secondary)
        }
    }
}

struct PlayerStatusView: View {
    let session: GameSession
    let onDone: () -> Void

    var body: some View {
        NavigationStack {
            PlayerStatusGrid(session: session)
                .navigationTitle("Status")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done", action: onDone)
                    }
                }
        }
        .frame(minWidth: 360, minHeight: 420)
    }
}
