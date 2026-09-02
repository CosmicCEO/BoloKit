import Darwin

// MARK: - Wave 5.7 — growtrees, pill cooldown, base replenish
//
// Ported from `growtrees()`, the "cool pills" loop, and the "replenish
// bases" loop, all in the per-tick server driver (Reference/c/server.c,
// around line 1206 through 1246).

// MARK: - Tree-growth scoring

/// Ported from `adjacentscore()` (server.c:3917). 1 if (x, y) is forest or
/// mined-forest, 0 otherwise (including out-of-bounds, via the terrain
/// subscript's own bounds guard — matches C's explicit range check).
public func adjacentScore(x: Int, y: Int, state: GameState) -> Int {
    switch state.terrain[x, y] {
    case .forest, .minedForest:
        return 1
    default:
        return 0
    }
}

/// Ported from `basescore()` (server.c:3872). Zero if a pill or base
/// occupies the square; otherwise a terrain-tier score, mined and
/// unmined variants scoring identically.
public func baseScore(x: Int, y: Int, state: GameState) -> Int {
    guard findPill(x: x, y: y, pills: state.pills) == nil,
          findBase(x: x, y: y, bases: state.bases) == nil
    else {
        return 0
    }

    switch state.terrain[x, y] {
    case .grass0, .grass1, .grass2, .grass3, .minedGrass:
        return 5
    case .swamp0, .swamp1, .swamp2, .swamp3, .minedSwamp:
        return 4
    case .crater, .minedCrater:
        return 3
    case .rubble0, .rubble1, .rubble2, .rubble3, .minedRubble:
        return 2
    case .road, .minedRoad:
        return 1
    default:
        return 0
    }
}

/// Ported from `treescore()` (server.c:3933): base score weighted by
/// existing forest in the 8-neighborhood, orthogonal neighbors counting
/// double a diagonal neighbor's contribution.
public func treeScore(x: Int, y: Int, state: GameState) -> Int {
    baseScore(x: x, y: y, state: state) * (
        2 * (
            adjacentScore(x: x + 1, y: y, state: state) + adjacentScore(x: x - 1, y: y, state: state)
                + adjacentScore(x: x, y: y + 1, state: state) + adjacentScore(x: x, y: y - 1, state: state)
        )
            + adjacentScore(x: x - 1, y: y - 1, state: state) + adjacentScore(x: x + 1, y: y - 1, state: state)
            + adjacentScore(x: x - 1, y: y + 1, state: state) + adjacentScore(x: x + 1, y: y + 1, state: state)
    )
}

// MARK: - growTrees

/// Runs `nplayers * (treesBestOf / (treesPlantRate * Int(ticksPerSec)))`
/// (integer arithmetic throughout — `4200 / (10 * 50) = 8`) best-of-N
/// tournament samples toward `state.grow`'s persistent running winner,
/// applying a grow action and starting a fresh tournament every
/// `treesBestOf` samples. Ported from `growtrees()` (server.c:3946).
///
/// **C bug, replicated intentionally (do not "fix"):** the outer
/// pill/base guard below checks `(x, y)` — the cell sampled on THIS
/// iteration, essentially unrelated to the tournament winner most of the
/// time — not `(growX, growY)`, the actual cell about to be grown. The
/// inner guard (inside the switch) correctly checks `(growX, growY)`.
/// Both forms are required exactly as in C; this is documented in
/// `docs/PLAN.md`'s known-intentional-divergences table.
public func growTrees(state: inout GameState, onGrow: (Int, Int) -> Void = { _, _ in }) {
    let width = 256
    let nplayers = state.players.filter { $0.connected }.count
    let iterations = nplayers * (treesBestOf / (treesPlantRate * Int(ticksPerSec)))

    for _ in 0..<iterations {
        let flat = Int(arc4random_uniform(UInt32(width * width)))
        // C: `x = random()%(WIDTH*WIDTH); y = x/WIDTH; x %= WIDTH;` — see
        // spawn()'s file header (Wave 5.6) for the arc4random_uniform
        // rationale; no C oracle exists for an independent PRNG stream.
        let y = flat / width
        let x = flat % width

        if treeScore(x: state.grow.growX, y: state.grow.growY, state: state)
            < treeScore(x: x, y: y, state: state) {
            state.grow.growX = x
            state.grow.growY = y
        }

        state.grow.growBestOf += 1

        if state.grow.growBestOf >= treesBestOf {
            state.grow.growBestOf = 0

            // Outer guard: last-sampled (x, y) — the C bug, see doc comment above.
            if findPill(x: x, y: y, pills: state.pills) == nil,
               findBase(x: x, y: y, bases: state.bases) == nil {
                let growX = state.grow.growX
                let growY = state.grow.growY

                switch state.terrain[growX, growY] {
                case .grass0, .grass1, .grass2, .grass3,
                     .rubble0, .rubble1, .rubble2, .rubble3,
                     .crater, .swamp0, .swamp1, .swamp2, .swamp3, .road:
                    // Inner guard: the tournament winner (growX, growY) — correct.
                    if findPill(x: growX, y: growY, pills: state.pills) == nil,
                       findBase(x: growX, y: growY, bases: state.bases) == nil {
                        state.terrain[growX, growY] = .forest
                        onGrow(growX, growY)
                    }

                case .minedGrass, .minedRubble, .minedCrater, .minedSwamp, .minedRoad:
                    if findPill(x: growX, y: growY, pills: state.pills) == nil,
                       findBase(x: growX, y: growY, bases: state.bases) == nil {
                        state.terrain[growX, growY] = .minedForest
                        onGrow(growX, growY)
                    }

                default:
                    break
                }
            }

            // Begin new search.
            let newFlat = Int(arc4random_uniform(UInt32(width * width)))
            state.grow.growY = newFlat / width
            state.grow.growX = newFlat % width
        }
    }
}

// MARK: - coolPills

/// Per-tick pill reload-interval degradation — NOT the fire-cadence tally
/// `pillTick` owns (see `Pill.coolCounter`'s doc comment). Ported from the
/// "cool pills" loop (server.c:1206-1220). Applies to every pill not
/// carried by a builder, dead or alive, matching C's literal
/// `armour != ONBOARD` guard (no additional `armour > 0` check in C).
public func coolPills(state: inout GameState, onCoolPill: (Int) -> Void = { _ in }) {
    for i in state.pills.indices {
        guard state.pills[i].armour != pillOnboard else { continue }

        state.pills[i].coolCounter += 1

        if state.pills[i].coolCounter >= UInt8(coolPillTicks) {
            if state.pills[i].speed < UInt8(maxTicksPerShot) {
                state.pills[i].speed += 1
                onCoolPill(i)
            }

            state.pills[i].coolCounter = 0
        }
    }
}

// MARK: - replenishBases

/// Per-tick base resource replenishment, scaling with the connected-player
/// count (not a flat +1 — see `Base.counter`'s doc comment). Ported from
/// the "replenish bases" loop (server.c:1222-1243).
public func replenishBases(state: inout GameState, onReplenishBase: (Int) -> Void = { _ in }) {
    let nplayers = state.players.filter { $0.connected }.count

    for i in state.bases.indices {
        state.bases[i].counter += UInt16(nplayers)

        if state.bases[i].counter >= UInt16(replenishBaseTicks) {
            state.bases[i].armour = min(state.bases[i].armour + 1, UInt8(maxBaseArmour))
            state.bases[i].mines = min(state.bases[i].mines + 1, UInt8(maxBaseMines))
            state.bases[i].shells = min(state.bases[i].shells + 1, UInt8(maxBaseShells))

            onReplenishBase(i)

            state.bases[i].counter = 0
        }
    }
}
