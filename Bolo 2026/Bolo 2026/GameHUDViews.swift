//
//  GameHUDViews.swift
//  Bolo 2026
//
//  D148(B): the always-visible main-window HUD Jerod's own reference screenshot of the original
//  Mac Bolo showed -- a persistent build-tool strip (left) and player/pill/base status grid +
//  shell/mine/armor gauges (right), replacing today's "open a sheet to see any of this" shape.
//  See `docs/AGENT_NOTES.md`'s D148(B) pre-brief for the full zone-by-zone plan, including the
//  two zones (event-log bar, win/loss surfacing) deliberately split out of this pass.
//
//  Both panels poll `session.state` on a `TimelineView`, the same "poll, don't observe" shape
//  `PlayerStatusView`/`GameRenderView` already use -- `GameSession` isn't `ObservableObject` by
//  design (see that file's own header).

import BoloKit
import SwiftUI

// MARK: - Build-tool strip

/// A vertical strip of the 5 builder-tool choices (`BuilderCommandKind`), supplementing D137's
/// silent digit-key selection with a visible, clickable equivalent. Reads/writes the same
/// `GameRenderView.selectedBuilderTool` the digit keys already drive -- no second source of
/// truth (see `GameRenderView.selectBuilderTool(_:)`'s own doc comment).
struct BuilderToolStrip: View {
    let session: GameSession
    /// Called after every tap -- see `GameView.reclaimMapFocus`'s doc comment for why this is
    /// mandatory, not optional polish.
    let reclaimFocus: () -> Void

    /// Faster than the 0.5s cadence `PlayerStatusGrid`/`ResourceGaugesPanel` poll at: this strip's
    /// whole point is visible feedback for a keyboard shortcut (digit keys 1-5) that already
    /// applies instantly, so a slower poll here would visibly lag a key press. Disclosed judgment
    /// call, not an oversight -- flagged in the D148(B) completion report.
    private static let pollInterval = 0.1

    var body: some View {
        TimelineView(.periodic(from: .now, by: Self.pollInterval)) { _ in
            VStack(spacing: 4) {
                ForEach(BuilderCommandKind.allCases, id: \.self) { tool in
                    Button {
                        session.renderView.selectBuilderTool(tool)
                        reclaimFocus()
                    } label: {
                        Text(Self.label(for: tool))
                            .frame(width: 36, height: 28)
                    }
                    .buttonStyle(.bordered)
                    .tint(session.renderView.selectedBuilderTool == tool ? .accentColor : .secondary)
                }
            }
            .padding(6)
        }
    }

    static func label(for tool: BuilderCommandKind) -> String {
        switch tool {
        case .tree: return "Tree"
        case .road: return "Road"
        case .wall: return "Wall"
        case .pill: return "Pill"
        case .mine: return "Mine"
        }
    }
}

extension BuilderCommandKind: CaseIterable {
    public static var allCases: [BuilderCommandKind] { [.tree, .road, .wall, .pill, .mine] }
}

// MARK: - Resource gauges

/// D148(B): shell/mine/armor gauges, mirroring the reference's `playerShellsStatusBar`/
/// `playerMinesStatusBar` (`GSXBoloController.m:278-279,2554-2555`) and base ammo bars
/// (`~2673-2674`). Pure display of existing `GameState` fields -- no new simulation state.
struct ResourceGaugesPanel: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let snapshot = session.state
            let localPlayer = snapshot.localPlayer
            // D148(B) (advisor-flagged): `mines` lives per-player (`state.players[localPlayer]`,
            // not `state.local`, per D105/D106), and this panel polls from first frame -- including
            // `#Preview`'s demo state and any moment `localPlayer` isn't a valid index yet. Guard
            // it the same way `GameSession` itself does everywhere else, rather than trapping like
            // D146's crash.
            let mines = snapshot.players.indices.contains(localPlayer)
                ? snapshot.players[localPlayer].mines : 0
            VStack(alignment: .leading, spacing: 8) {
                gauge(label: "Shells", value: Int(snapshot.local.shells), max: maxShells, color: .orange)
                gauge(label: "Mines", value: mines, max: maxMines, color: .purple)
                gauge(label: "Armor", value: Int(snapshot.local.armour), max: maxArmour, color: .green)
            }
            .padding(8)
        }
    }

    @ViewBuilder
    private func gauge(label: String, value: Int, max: Int, color: Color) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            ProgressView(value: Double(GameHUDMath.gaugeFraction(value: value, max: max)))
                .tint(color)
        }
    }
}

/// D148(B): extracted per D144/D145/D146's precedent of pulling pure logic out of view code so
/// it's directly unit-testable (`Bolo 2026Tests/GameHUDViewsTests.swift`).
enum GameHUDMath {
    /// Clamped 0...1 -- neither a negative `value` (shouldn't happen, but `mines`/`shells`/
    /// `armour` are plain `Int`/`UInt8` with no invariant enforced at this layer) nor a `value`
    /// above `max` (a real, transient possibility: `TankLocalTick.swift`'s refuel logic can leave
    /// `shells`/`armour` briefly reconciling) should ever produce an out-of-range `ProgressView`.
    static func gaugeFraction(value: Int, max: Int) -> Float {
        guard max > 0 else { return 0 }
        let fraction = Float(value) / Float(max)
        return Swift.min(1, Swift.max(0, fraction))
    }
}
