import Darwin

// MARK: - Wave 5.5a — explosionAt / superboomAt / chain / flood / droppills
//
// Ported from `chainat`/`floodat`/`floodtest`/`explosionat`/`superboomat`/
// `chain`/`flood` (server.c:4014-4300), `clearterrain`/`dr`/`droppills`
// (server.c:1919-2053), and the local-effect halves of `recvsrsmallboom`/
// `recvsrsuperboom`/`recvsrflood` (client.c:1732, 2632, 2709).
//
// **D27 (PLANNER, after Wave 5.3c's PARITY FAIL): checked explicitly, not
// assumed.** `pillTick`'s original design mutated one shared scalar
// (`pill.counter`) from a per-caller loop, so evaluation order changed the
// outcome. Nothing here has that shape:
//   - `chainAt`/`floodAt`/`floodTest` only ever *append* to a ring-buffer
//     slot — multiple appends to the same slot in one tick are order-
//     independent (the result is just "these points are scheduled").
//   - `chain()`/`flood()` are already single, global, no-player-parameter
//     functions in C — there is no per-caller loop to generalize here,
//     unlike `pilllogic`'s hardcoded-`client.player` shape.
//   - `explosionAt`/`superboomAt` mutate terrain at their own specific
//     `(x, y)`; two calls targeting the same square are naturally
//     idempotent (the second finds `.crater` already and no-ops), matching
//     C exactly. No shared scalar to race on.
//   - `dropPills` re-checks `findPill`/`findBase` against current state on
//     every candidate square; concurrent calls (two deaths same tick) each
//     search independently and can't double-claim a square.
//
// **`explosionAt`/`superboomAt` collapse the server+client halves into one
// function, same precedent Wave 5.3a set merging `shellcollisiontest`
// (client) and `recvcldamage` (server).** C's client-side
// `recvsrsmallboom`/`recvsrsuperboom` — what happens when this client
// *receives* the broadcast of someone's mine/wall detonation — only run
// their explosion-particle/builder-kill block when `player !=
// client.player` (the causer's own client already did this optimistically
// via `smallboom()`/`superboom()`, Wave 5.2b). The tank-damage check is
// NOT nested inside that gate for smallboom (a second, independent `if`,
// guarded only by `!dead` — which naturally self-excludes the causer, who
// is already dead from their own `smallboom()`/`superboom()` call by the
// time this runs) but IS nested inside it for superboom — a real, if
// practically unobservable, asymmetry in the C source that this port
// preserves structurally rather than unifying the two shapes.
//
// **Deliberately NOT done this wave: wiring the existing `onMineExplosion`/
// `onSuperboomTerrain` closures (shipped in `TankLocalTick.swift`/
// `ShellTick.swift`/`BuilderTick.swift`) to call these functions.** Nothing
// calls those closures with a real implementation yet — connecting them
// requires threading the correct causer (shell owner, builder's player, or
// `state.localPlayer`) through three already-shipped files, which only a
// real top-level tick driver (Wave 6) can supply with full context. These
// functions are complete and independently tested with an explicit
// `player` argument now; wiring is deferred, not skipped.
//
// **A real client/server field inconsistency, resolved in the client's
// favor, not silently:** C's server-side `dr()` never sets a dropped
// pill's `speed`; the client's `recvsrdroppill()` sets it to
// `MAXTICKSPERSHOT`. Since `pillTick` (already shipped) reads `speed` from
// the *one* unified `state.pills` array to decide fire-readiness, and only
// the client's copy is ever behaviorally connected to firing, this port
// follows the client: `speed = maxTicksPerShot` on drop.
//
// **A real bug, replicated verbatim, not fixed:** `droppills`' NaN-clamp
// checks `isnan(x)` twice (once for the x-clamp branch, once for the
// y-clamp branch) and never checks `isnan(y)` at all — a copy-paste bug in
// the C source, same class as `growtrees`' outer-guard bug and
// `collisionDetect`'s p.x/p.y swap.

// MARK: - Ring-buffer slot indexing

/// The ring-buffer slot a point scheduled *this* tick is written to. C:
/// `(server.ticks - 1) % (N + 1)`, where `server.ticks` is `uint32_t` — at
/// `ticks == 0` this underflows to `0xFFFFFFFF`, well-defined (wrapping)
/// unsigned arithmetic in C, not a crash. `GameState.ticks` is `UInt64`
/// here, so this narrows to `UInt32` *before* subtracting to reproduce the
/// exact same wraparound value C computes, rather than wrapping at a
/// different boundary (`UInt64.max` vs `UInt32.max`).
private func writeSlot(_ ticks: UInt64, count: Int) -> Int {
    Int((UInt32(truncatingIfNeeded: ticks) &- 1) % UInt32(count))
}

// MARK: - clearTerrain

/// True if (x, y) is inside the mine-placement zone, unoccupied by a pill
/// or base, and its terrain is a type mines/pills can occupy (everything
/// except wall/damaged-wall). Ported from `clearterrain()` (server.c:1919).
public func clearTerrain(x: Int, y: Int, state: GameState) -> Bool {
    guard x >= mineZoneMin, x <= mineZoneMax, y >= mineZoneMin, y <= mineZoneMax else { return false }
    guard let terrain = state.terrain[x, y] else { return false }
    switch terrain {
    case .wall, .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        return false
    default:
        return findPill(x: x, y: y, pills: state.pills) == nil && findBase(x: x, y: y, bases: state.bases) == nil
    }
}

// MARK: - dropPillSearch / dropPills

/// Claims (x, y) for the next unclaimed bit in `pills`, if the square is
/// clear and pill-free. Returns the (possibly advanced) search index `i`.
/// Ported from `dr()` (server.c:1965). Sets `speed = maxTicksPerShot` on
/// claim — see the file header for why this follows the client's
/// `recvsrdroppill()`, not the server's own `dr()`, which never touches it.
public func dropPillSearch(x: Int, y: Int, i: Int, pills: UInt16, state: inout GameState) -> Int {
    var i = i
    guard clearTerrain(x: x, y: y, state: state), findPill(x: x, y: y, pills: state.pills) == nil else {
        return i
    }
    while i < state.pills.count {
        if (1 << i) & Int(pills) != 0 {
            state.pills[i].armour = 0
            state.pills[i].x = UInt8(x)
            state.pills[i].y = UInt8(y)
            state.pills[i].speed = UInt8(maxTicksPerShot)
            i += 1
            break
        }
        i += 1
    }
    return i
}

/// Scatters the bits set in `pills` (a bitmask of pill indices) onto empty
/// squares in an outward spiral from `(x, y)`, one pill per successive
/// ring edge closest to the origin point. Ported from `droppills()`
/// (server.c:1984). `player` is unused in the source beyond an assertion
/// bound and is kept here only for signature fidelity.
public func dropPills(player: Int, x: Float, y: Float, pills: UInt16, state: inout GameState) {
    var x = x
    var y = y

    // C: checks `isnan(x)` in BOTH the x- and y-clamp `else if` chains —
    // never `isnan(y)`. Replicated verbatim; see file header.
    if x < 0.0 {
        x = 0.0
    } else if x >= 256.0 {
        x = 256.0 - 0.00001
    } else if x.isNaN {
        x = 128.0
    }

    if y < 0.0 {
        y = 0.0
    } else if y >= 256.0 {
        y = 256.0 - 0.00001
    } else if x.isNaN {
        y = 128.0
    }

    var minX = Int(x)
    var maxX = minX + 1
    var minY = Int(y)
    var maxY = minY + 1

    var i = dropPillSearch(x: minX, y: minY, i: 0, pills: pills, state: &state)

    while i < state.pills.count {
        let lx = x - Float(minX)
        let hx = Float(maxX) - x
        let ly = y - Float(minY)
        let hy = Float(maxY) - y

        if lx <= hx && lx <= ly && lx <= hy {
            minX -= 1
            var j = 0
            while minY + j < maxY {
                i = dropPillSearch(x: minX, y: minY + j, i: i, pills: pills, state: &state)
                j += 1
            }
        } else if hx <= lx && hx <= ly && hx <= hy {
            var j = 0
            while minY + j < maxY {
                i = dropPillSearch(x: maxX, y: minY + j, i: i, pills: pills, state: &state)
                j += 1
            }
            maxX += 1
        } else if ly <= lx && ly <= hx && ly <= hy {
            minY -= 1
            var j = 0
            while minX + j < maxX {
                i = dropPillSearch(x: minX + j, y: minY, i: i, pills: pills, state: &state)
                j += 1
            }
        } else {
            var j = 0
            while minX + j < maxX {
                i = dropPillSearch(x: minX + j, y: maxY, i: i, pills: pills, state: &state)
                j += 1
            }
            maxY += 1
        }
    }
}

// MARK: - floodTest / floodAt / flood

/// Schedules a flood-propagation step at (x, y) if its terrain is
/// water-like (river/sea/mined-sea/boat). Ported from `floodtest()`
/// (server.c:4083).
public func floodTest(x: Int, y: Int, state: inout GameState) {
    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .river, .sea, .minedSea, .boat:
        state.floods[writeSlot(state.ticks, count: floodTicks + 1)].append(Pointi(x: Int32(x), y: Int32(y)))
    default:
        break
    }
}

/// Drains one scheduled flood point: converts a crater to river and
/// reschedules, or detonates a mined tile it has reached. Ported from
/// `floodat()` (server.c:4038). Threads all three closures through to
/// `explosionAt` — its splash-damage escalation can call `smallboom`/
/// `superboom`, which need `onMineExplosion`/`onSuperboomTerrain`
/// themselves, not just `onDropPills`.
public func floodAt(
    x: Int, y: Int, state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: playerNeutral, x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
    case .crater:
        state.terrain[x, y] = .river
        state.floods[writeSlot(state.ticks, count: floodTicks + 1)].append(Pointi(x: Int32(x), y: Int32(y)))
    default:
        break
    }
}

/// Drains this tick's flood ring-buffer slot, spreading to the 4 neighbors
/// of each scheduled point. Ported from `flood()` (server.c:4280). Called
/// once per tick, globally — no player parameter, matching C exactly.
public func flood(
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let slot = Int(state.ticks) % (floodTicks + 1)
    let scheduled = state.floods[slot]
    state.floods[slot] = []

    for point in scheduled {
        let x = Int(point.x)
        let y = Int(point.y)
        floodAt(x: x, y: y - 1, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        floodAt(x: x - 1, y: y, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        floodAt(x: x + 1, y: y, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        floodAt(x: x, y: y + 1, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
    }
}

// MARK: - chainAt / chain

/// Drains one scheduled chain point: detonates it if it's still mined.
/// Ported from `chainat()` (server.c:4014). See `floodAt` for why all
/// three closures are threaded through to `explosionAt`.
public func chainAt(
    x: Int, y: Int, state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else { return }
    switch terrain {
    case .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        explosionAt(
            player: playerNeutral, x: x, y: y, state: &state,
            onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
        )
    default:
        break
    }
}

/// Drains this tick's chain ring-buffer slot, propagating to the 4
/// neighbors of each scheduled point. Ported from `chain()`
/// (server.c:4259). Called once per tick, globally — no player parameter,
/// matching C exactly.
public func chain(
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    let slot = Int(state.ticks) % (chainTicks + 1)
    let scheduled = state.chains[slot]
    state.chains[slot] = []

    for point in scheduled {
        let x = Int(point.x)
        let y = Int(point.y)
        chainAt(x: x, y: y - 1, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        chainAt(x: x - 1, y: y, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        chainAt(x: x + 1, y: y, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        chainAt(x: x, y: y + 1, state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
    }
}

// MARK: - Splash damage (shared escalation logic)

/// Applies mine-splash armour damage to the local player's tank if it's
/// within `radius` of `point` and alive, escalating to `superboom`/
/// `smallboom`/`killTank` if armour goes negative — the exact three-way
/// branch already shipped for the dead-tumble sequence, but at a different
/// threshold (`> 32`, not `>= 32` — a distinct call site, not the same
/// constant reused). Ported from the tank-damage block duplicated in
/// `recvsrsmallboom`/`recvsrsuperboom` (client.c:2660, 2814).
private func applySplashDamage(
    radius: Float,
    damage: Int,
    point: Vec2f,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void,
    onSuperboomTerrain: (Pointi) -> Void,
    onDropPills: (UInt16, Vec2f) -> Void
) {
    let player = state.localPlayer
    guard !state.players[player].dead, mag2f(state.players[player].tank - point) <= radius else { return }

    state.local.armour -= damage
    state.players[player].boat = false

    if state.local.armour < 0 {
        state.local.armour = 0
        if state.local.mines > 32 {
            superboom(state: &state, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
        } else if state.local.mines > 0 || state.local.shells > 0 {
            smallboom(state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills)
        } else {
            killTank(state: &state, onDropPills: onDropPills)
        }
    }
}

// MARK: - explosionAt

/// Detonates a single tile: converts mineable terrain to crater, schedules
/// flood-tests on its 4 neighbors and a chain-reaction entry for itself,
/// and — if `player` isn't the local player, mirroring `recvsrsmallboom`'s
/// `player != client.player` gate (the local causer already did this
/// optimistically via `smallboom()`, Wave 5.2b) — creates a global
/// explosion particle and checks the local builder for a kill. The local
/// tank's splash-damage check is independent of that gate (see file
/// header). Ported from `explosionat()` (server.c:4121) +
/// `recvsrsmallboom()` (client.c:2632).
public func explosionAt(
    player: UInt8,
    x: Int,
    y: Int,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    guard let terrain = state.terrain[x, y] else { return }

    let detonated: Bool
    switch terrain {
    case .boat, .wall, .river,
        .swamp0, .swamp1, .swamp2, .swamp3, .crater, .road, .forest,
        .rubble0, .rubble1, .rubble2, .rubble3, .grass0, .grass1, .grass2, .grass3,
        .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3,
        .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
        state.terrain[x, y] = .crater
        floodTest(x: x, y: y - 1, state: &state)
        floodTest(x: x - 1, y: y, state: &state)
        floodTest(x: x + 1, y: y, state: &state)
        floodTest(x: x, y: y + 1, state: &state)
        state.chains[writeSlot(state.ticks, count: chainTicks + 1)].append(Pointi(x: Int32(x), y: Int32(y)))
        detonated = true

    case .minedSea:
        detonated = true

    default:
        detonated = false
    }

    guard detonated else { return }

    let point = Vec2f(x: Float(x) + 0.5, y: Float(y) + 0.5)

    if player != UInt8(state.localPlayer) {
        state.explosions.append(Explosion(point: point))
        killSquareBuilder(at: Pointi(x: Int32(x), y: Int32(y)), state: &state, onDropPills: onDropPills)
    }

    applySplashDamage(
        radius: smallboomRadius, damage: smallboomDamage, point: point, state: &state,
        onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
    )
}

// MARK: - superboomAt

/// Detonates a 2×2 tile area: converts each of the 4 cells to crater
/// (unless sea/mined-sea), schedules flood-tests on its 8 border
/// neighbors and 4 chain-reaction entries (one per cell), and — gated on
/// `player != state.localPlayer`, this time wrapping the damage check too
/// (see file header for why that nesting differs from `explosionAt`) —
/// creates 9 explosion particles (4 corners + 5 edge/center, the same
/// layout already shipped in `superboom()`, Wave 5.2b) with builder-kill
/// checks, then the local tank's splash-damage check. Ported from
/// `superboomat()` (server.c:4192) + `recvsrsuperboom()` (client.c:2709).
public func superboomAt(
    player: UInt8,
    x: Int,
    y: Int,
    state: inout GameState,
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in }
) {
    for (dx, dy) in [(0, 0), (1, 0), (0, 1), (1, 1)] {
        let cx = x + dx
        let cy = y + dy
        if let terrain = state.terrain[cx, cy], terrain != .sea, terrain != .minedSea {
            state.terrain[cx, cy] = .crater
        }
    }

    floodTest(x: x, y: y - 1, state: &state)
    floodTest(x: x + 1, y: y - 1, state: &state)
    floodTest(x: x - 1, y: y, state: &state)
    floodTest(x: x - 1, y: y + 1, state: &state)
    floodTest(x: x + 2, y: y, state: &state)
    floodTest(x: x + 2, y: y + 1, state: &state)
    floodTest(x: x, y: y + 2, state: &state)
    floodTest(x: x + 1, y: y + 2, state: &state)

    let slot = writeSlot(state.ticks, count: chainTicks + 1)
    state.chains[slot].append(Pointi(x: Int32(x), y: Int32(y)))
    state.chains[slot].append(Pointi(x: Int32(x + 1), y: Int32(y)))
    state.chains[slot].append(Pointi(x: Int32(x), y: Int32(y + 1)))
    state.chains[slot].append(Pointi(x: Int32(x + 1), y: Int32(y + 1)))

    guard player != UInt8(state.localPlayer) else { return }

    let fx = Float(x)
    let fy = Float(y)
    let corners: [(Vec2f, Pointi)] = [
        (Vec2f(x: fx + 0.5, y: fy + 0.5), Pointi(x: Int32(x), y: Int32(y))),
        (Vec2f(x: fx + 1.5, y: fy + 0.5), Pointi(x: Int32(x + 1), y: Int32(y))),
        (Vec2f(x: fx + 0.5, y: fy + 1.5), Pointi(x: Int32(x), y: Int32(y + 1))),
        (Vec2f(x: fx + 1.5, y: fy + 1.5), Pointi(x: Int32(x + 1), y: Int32(y + 1))),
    ]
    for (point, square) in corners {
        state.explosions.append(Explosion(point: point))
        killSquareBuilder(at: square, state: &state, onDropPills: onDropPills)
    }

    let edges: [Vec2f] = [
        Vec2f(x: fx + 0.25, y: fy + 1.0),
        Vec2f(x: fx + 1.0, y: fy + 0.25),
        Vec2f(x: fx + 1.75, y: fy + 1.0),
        Vec2f(x: fx + 1.0, y: fy + 1.75),
        Vec2f(x: fx + 1.0, y: fy + 1.0),
    ]
    for point in edges {
        state.explosions.append(Explosion(point: point))
        killPointBuilder(at: point, state: &state, onDropPills: onDropPills)
    }

    applySplashDamage(
        radius: superboomRadius, damage: superboomDamage, point: Vec2f(x: fx + 1.0, y: fy + 1.0), state: &state,
        onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills
    )
}
