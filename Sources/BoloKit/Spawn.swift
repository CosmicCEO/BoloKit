import Darwin

// MARK: - Wave 5.6 — spawn()
//
// Ported from `spawn()` (Reference/c/client.c:5966). Picks a start position
// for `state.localPlayer` via a two-pass weighted random selection, then
// resets tank state and resources for the new life.
//
// Pass 1 weights every start: 1 by default, boosted to 3/2 by proximity to
// a friendly-or-neutral base (never downgraded once boosted — `weights[i]
// < 3` guards), zeroed if within 8.5 of a pill hostile to the local player.
// If every start ends up zeroed (summed weight == 0), Pass 2 recomputes
// weights using only the base-boost loop — not a re-run with a flag, since
// C's own fallback block is a textually separate second copy of the loop.
//
// `testAlliance` already returns `false` for `playerNeutral` (0xff) via its
// own bounds guard, so the pill-penalty loop needs no explicit neutral
// check — unlike the base-boost loop, which treats a neutral-owned base as
// safe and must say so explicitly (`owner == playerNeutral ||`).
public func spawn(state: inout GameState) {
    let player = state.localPlayer

    var weights = computeSpawnWeights(state: state)
    if weights.reduce(0, +) == 0 {
        weights = computeSpawnWeights(state: state, includePillPenalty: false)
    }

    let range = weights.reduce(0, +)
    let index = Int(arc4random_uniform(UInt32(range)))

    var cumulative = 0
    var start = 0
    for i in state.starts.indices {
        cumulative += weights[i]
        start = i
        if cumulative > index {
            break
        }
    }

    let picked = state.starts[start]
    state.players[player].dead = false
    state.players[player].tank = Vec2f(x: Float(picked.x) + 0.5, y: Float(picked.y) + 0.5)
    state.players[player].dir = Float(picked.dir) * (kPif / 8.0)
    state.players[player].speed = 0.0
    state.players[player].turnSpeed = 0.0
    state.players[player].kickSpeed = 0.0
    state.players[player].kickDir = 0.0
    state.local.range = maxShellRange
    state.players[player].boat = true

    switch state.dominationType {
    case .open:
        state.local.shells = maxShells
        state.local.mines = maxMines
        state.local.armour = maxArmour
        state.local.trees = maxTrees
    case .tournament:
        state.local.shells = 2 * state.bases.filter { $0.owner == playerNeutral }.count
        state.local.mines = 0
        state.local.armour = maxArmour
        state.local.trees = 0
    case .strict:
        state.local.shells = 0
        state.local.mines = 0
        state.local.armour = maxArmour
        state.local.trees = 0
    }

    state.local.spawned = true
}

private func computeSpawnWeights(state: GameState, includePillPenalty: Bool = true) -> [Int] {
    let player = state.localPlayer
    var weights = [Int](repeating: 1, count: state.starts.count)

    for i in state.starts.indices {
        let startCenter = Vec2f(x: Float(state.starts[i].x) + 0.5, y: Float(state.starts[i].y) + 0.5)

        for base in state.bases {
            guard base.owner == playerNeutral || testAlliance(Int(base.owner), player, players: state.players)
            else { continue }

            let baseCenter = Vec2f(x: Float(base.x) + 0.5, y: Float(base.y) + 0.5)
            let dist = mag2f(startCenter - baseCenter)

            if dist < 8.5 {
                if weights[i] < 3 {
                    weights[i] = 3
                }
            } else if dist < 17 {
                if weights[i] < 2 {
                    weights[i] = 2
                }
            }
        }

        guard includePillPenalty else { continue }

        for pill in state.pills {
            guard !testAlliance(Int(pill.owner), player, players: state.players) else { continue }
            let pillCenter = Vec2f(x: Float(pill.x) + 0.5, y: Float(pill.y) + 0.5)
            if mag2f(startCenter - pillCenter) < 8.5 {
                weights[i] = 0
            }
        }
    }

    return weights
}
