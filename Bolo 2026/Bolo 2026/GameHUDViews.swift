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
                    let selected = session.renderView.selectedBuilderTool == tool
                    Button {
                        session.renderView.selectBuilderTool(tool)
                        reclaimFocus()
                    } label: {
                        Text(Self.label(for: tool))
                            .frame(width: 36, height: 28)
                    }
                    .buttonStyle(.plain)
                    .focusable(false)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .fill(selected ? Color.accentColor.opacity(0.3) : Color.secondary.opacity(0.15))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(selected ? Color.accentColor : Color.secondary, lineWidth: selected ? 2 : 1)
                    )
                }
            }
            .padding(6)
            // Opaque, not `.regularMaterial`: the original bug report was text rendering directly
            // over the (frequently bright/busy) map, so translucency risks reproducing the same
            // legibility problem it's meant to fix.
            .background(Color(nsColor: .windowBackgroundColor))
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
///
/// D150(1)/(2): extended with the reference's 4th player gauge (`playerTreesStatusBar`,
/// `:2557-2558`) and its separate "nearest allied base within 8 tiles" cluster
/// (`baseArmourStatusBar`/`baseShellsStatusBar`/`baseMinesStatusBar`, `:2652-2680`) -- see the
/// D150 pre-brief in `docs/AGENT_NOTES.md` for the full trace against the reference's `dist`/
/// mutual-alliance scan.
struct ResourceGaugesPanel: View {
    let session: GameSession

    var body: some View {
        TimelineView(.periodic(from: .now, by: 0.5)) { _ in
            let snapshot = session.state
            let localPlayer = snapshot.localPlayer
            // D148(B) (advisor-flagged): `mines`/`trees` live per-player (`state.players[localPlayer]`,
            // not `state.local`, per D105/D106), and this panel polls from first frame -- including
            // `#Preview`'s demo state and any moment `localPlayer` isn't a valid index yet. Guard
            // it the same way `GameSession` itself does everywhere else, rather than trapping like
            // D146's crash.
            let mines = snapshot.players.indices.contains(localPlayer)
                ? snapshot.players[localPlayer].mines : 0
            let trees = snapshot.players.indices.contains(localPlayer)
                ? snapshot.players[localPlayer].trees : 0
            let base = Self.nearestBase(snapshot: snapshot)
            VStack(alignment: .leading, spacing: 8) {
                gauge(label: "Shells", value: Int(snapshot.local.shells), max: maxShells, color: .orange)
                gauge(label: "Mines", value: mines, max: maxMines, color: .purple)
                gauge(label: "Armor", value: Int(snapshot.local.armour), max: maxArmour, color: .green)
                gauge(label: "Trees", value: trees, max: maxTrees, color: .brown)
                gauge(label: "Base Armor", value: Int(base?.armour ?? 0), max: maxBaseArmour, color: .green)
                gauge(label: "Base Shells", value: Int(base?.shells ?? 0), max: maxBaseShells, color: .orange)
                gauge(label: "Base Mines", value: Int(base?.mines ?? 0), max: maxBaseMines, color: .purple)
            }
            .padding(8)
            // Same opaque choice as `BuilderToolStrip` above, same reason.
            .background(Color(nsColor: .windowBackgroundColor))
        }
    }

    /// **D150(2):** ported from `GSXBoloController.m:2562-2563,2652-2669`'s `refresh:` timer --
    /// nearest base (by real Euclidean distance, `mag2f`/`vector.c:82-84` is `sqrt(dot2f(...))`,
    /// not squared) owned by a player mutually allied with the local player, within 8 tiles of
    /// the local tank. `nil` (all-zero display, `:2675-2679`) when no such base exists, or the
    /// local player index isn't valid yet (same guard style as `mines`/`trees` above).
    static func nearestBase(snapshot: GameState) -> Base? {
        guard snapshot.players.indices.contains(snapshot.localPlayer) else { return nil }
        let tank = snapshot.players[snapshot.localPlayer].tank
        var best: Base?
        var bestDist: Float = 8.0
        for candidate in snapshot.bases where candidate.owner != playerNeutral {
            guard testAlliance(snapshot.localPlayer, Int(candidate.owner), players: snapshot.players)
            else { continue }
            let d = mag2f(sub2f(tank, make2f(Float(candidate.x) + 0.5, Float(candidate.y) + 0.5)))
            if d < bestDist {
                best = candidate
                bestDist = d
            }
        }
        return best
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
