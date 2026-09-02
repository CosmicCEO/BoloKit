// MARK: - Wave 5.5b — explosionlogic
//
// Ported from `explosionlogic()` (client.c:5499). Drains the explosion-
// particle lists Wave 5.5a's `explosionAt`/`superboomAt`/`smallboom`/
// `superboom` feed: the global list (`client.explosions`, `player == -1`
// in C) and each connected player's own list
// (`client.players[player].explosions`).
//
// C's driver calls this once per connected player plus once more with
// `player == -1` for the global list (the tick-loop order noted in this
// wave's pre-read: "explosionlogic(i) — all players + neutral (-1)").
// Since these are entirely disjoint lists — nothing here reads or resets
// a value any other call also touches — there's no D27-style shared-
// mutation-order risk to design around (confirmed, not assumed: unlike
// `pillTick`'s single shared `counter` field, every list drained here
// belongs to exactly one caller). This port drains all of them in one
// pass rather than replicating the per-call signature; the net effect
// across a full tick's worth of the original per-target calls is
// identical.

/// Ages every explosion particle in `state.explosions` and every
/// connected player's own `explosions` list by one tick, removing any
/// whose counter exceeds `explosionTicks` (24) — strictly greater, not
/// `>=`. A disconnected player's list is left untouched entirely, matching
/// C's `if (client.players[player].connected)` guard.
public func explosionTick(state: inout GameState) {
    state.explosions = drainExplosions(state.explosions)
    for i in state.players.indices where state.players[i].connected {
        state.players[i].explosions = drainExplosions(state.players[i].explosions)
    }
}

private func drainExplosions(_ explosions: [Explosion]) -> [Explosion] {
    explosions.compactMap { explosion in
        var explosion = explosion
        explosion.counter += 1
        return explosion.counter > explosionTicks ? nil : explosion
    }
}
