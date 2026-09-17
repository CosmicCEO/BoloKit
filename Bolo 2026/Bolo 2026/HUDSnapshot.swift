//
//  HUDSnapshot.swift
//  Bolo 2026
//
//  v1.4.0 #23 -- a display-only `@Observable` projection of `GameState`, populated from the
//  tick path (`GameSession`'s three `update(from:)` call sites) so `ResourceGaugesPanel`/
//  `PlayerStatusGrid` can read it directly instead of polling `session.state` on a
//  `TimelineView`. Deliberately not `GameState` itself, and never mutated by anything but
//  `update(from:)` -- `GameSession`'s own header explains why live `GameState` can't be a
//  single always-live SwiftUI source of truth (exclusivity across the single-process/join/
//  host paths); this type only ever copies already-committed values out of it.

import BoloKit
import Observation

@MainActor
@Observable
public final class HUDSnapshot {
    public struct PlayerSummary {
        public var name: String
        public var connected: Bool
        public var used: Bool
        public var alliance: UInt16
        public var mines: Int
        public var trees: Int
    }

    public struct PillSummary {
        public var owner: UInt8
    }

    public struct BaseSummary {
        public var x: UInt8
        public var y: UInt8
        public var owner: UInt8
        public var armour: UInt8
        public var shells: UInt8
        public var mines: UInt8
    }

    public private(set) var localPlayer: Int = 0
    public private(set) var players: [PlayerSummary] = []
    public private(set) var localShells: Int = 0
    public private(set) var localArmour: Int = 0
    public private(set) var localTank: Vec2f = Vec2f(x: 0, y: 0)
    public private(set) var pills: [PillSummary] = []
    public private(set) var bases: [BaseSummary] = []

    /// `HUDSnapshot`-typed overload of `testAlliance(_:_:players:)` (`GameObjects.swift`) -- same
    /// mutual-bitmask logic, ported field-for-field since `HUDSnapshot.PlayerSummary` isn't a
    /// `PlayerState`. Views that migrated to reading `HUDSnapshot` call this exactly as they
    /// called the `BoloKit` original against `session.state.players`.
    public static func testAlliance(_ p1: Int, _ p2: Int, players: [PlayerSummary]) -> Bool {
        guard p1 >= 0, p1 < players.count, p2 >= 0, p2 < players.count else { return false }
        let a = players[p1]
        let b = players[p2]
        return a.used && b.used
            && (a.alliance & (1 << p2)) != 0
            && (b.alliance & (1 << p1)) != 0
    }

    func update(from state: GameState) {
        localPlayer = state.localPlayer
        players = state.players.map {
            PlayerSummary(
                name: $0.name, connected: $0.connected, used: $0.used,
                alliance: $0.alliance, mines: $0.mines, trees: $0.trees
            )
        }
        localShells = state.local.shells
        localArmour = state.local.armour
        if state.players.indices.contains(state.localPlayer) {
            localTank = state.players[state.localPlayer].tank
        }
        pills = state.pills.map { PillSummary(owner: $0.owner) }
        bases = state.bases.map {
            BaseSummary(x: $0.x, y: $0.y, owner: $0.owner, armour: $0.armour, shells: $0.shells, mines: $0.mines)
        }
    }
}
