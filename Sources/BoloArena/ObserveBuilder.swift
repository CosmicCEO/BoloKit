import BoloKit

/// Builds an `observe` response purely from the seat's own `StateBox` snapshot -- never reads
/// any other state source, so the guest seat's view is always guest-truth (Hidden Mines
/// integrity: never render from host truth on the guest seat).
enum ObserveBuilder {
    static func build(from box: StateBox) -> ObserveResponse {
        let (state, phase, gameId, playerIndex, displayTick) = box.snapshot
        let events = box.drainEvents()

        guard state.players.indices.contains(playerIndex), state.localStats.indices.contains(playerIndex) else {
            return ObserveResponse(
                phase: phase.rawValue, gameId: gameId, tick: displayTick, alive: false,
                x: 0, y: 0, headingDegrees: 0, speed: 0, armour: 0, shells: 0, mines: 0, trees: 0,
                boat: false, terrain: [], nearby: [], events: events
            )
        }

        let me = state.players[playerIndex]
        let stats = state.localStats[playerIndex]
        let tankTile = Pointi(x: Int32(me.tank.x), y: Int32(me.tank.y))

        var nearby: [NearbyObject] = []
        for (i, player) in state.players.enumerated() where i != playerIndex && player.used && player.connected && !player.dead {
            nearby.append(NearbyObject(
                kind: "enemyTank",
                dx: Int32(player.tank.x) - tankTile.x, dy: Int32(player.tank.y) - tankTile.y,
                owner: "enemy"
            ))
        }
        for pill in state.pills where !pill.isOnboard {
            let owner = pill.owner == playerNeutral ? "neutral" : (Int(pill.owner) == playerIndex ? "you" : "enemy")
            nearby.append(NearbyObject(kind: "pill", dx: Int32(pill.x) - tankTile.x, dy: Int32(pill.y) - tankTile.y, owner: owner))
        }
        for base in state.bases {
            let owner = base.owner == playerNeutral ? "neutral" : (Int(base.owner) == playerIndex ? "you" : "enemy")
            nearby.append(NearbyObject(kind: "base", dx: Int32(base.x) - tankTile.x, dy: Int32(base.y) - tankTile.y, owner: owner))
        }
        for player in state.players {
            for shell in player.shells {
                nearby.append(NearbyObject(
                    kind: "shell", dx: Int32(shell.point.x) - tankTile.x, dy: Int32(shell.point.y) - tankTile.y,
                    owner: nil
                ))
            }
        }

        return ObserveResponse(
            phase: phase.rawValue, gameId: gameId, tick: displayTick, alive: !me.dead,
            x: me.tank.x, y: me.tank.y, headingDegrees: me.dir * 180 / kPif, speed: me.speed,
            armour: stats.armour, shells: stats.shells, mines: Int(me.mines), trees: Int(me.trees),
            boat: me.boat, terrain: TerrainWindow.render(around: tankTile, terrain: state.terrain),
            nearby: nearby, events: events
        )
    }
}
