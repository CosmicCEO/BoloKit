// MARK: - Wave 6.1 — tick orchestrator
//
// Ported from `runclient()` (client.c:425-497) and `runserver()`
// (server.c:1083-1257), unified into one per-tick entry point since
// BoloKit merges both roles into a single authoritative `GameState` — see
// `docs/PLAN.md`'s architecture note. The real system runs these as two
// independent, unsynchronized processes; there is no C precedent for an
// interleaving order between them, so the order below (server-role
// bookkeeping, then client-role per-player physics) is this port's own
// synthesis, not a transcription — noted here so it isn't mistaken for one.
//
// **Simplification, not an omission:** the real `client.timelimitreached`/
// `client.basecontrolreached` flags exist because a *remote* client only
// learns "time's up" via a broadcast (`SRTimeLimit`/`SRBaseControl` with
// payload 0) and must latch that fact until told otherwise. A single
// authoritative `GameState` has no such latency to bridge — comparing
// `ticks` against `timeLimit`/`baseControlThreshold` fresh every tick
// (exactly what `runserver()` itself already does) is equivalent and
// needs no separate flag.
//
// **Scope boundary, flagged in the Wave 6.1 completion report:** every
// `onMineExplosion`/`onSuperboomTerrain`/`onDropPills`/`onExplosion`/
// `onSuperboom`/`onSmallboom`/`onSpawn` callback below is a straight
// pass-through to `runTick`'s own caller — it does **not** wire these
// into `explosionAt`/`superboomAt`/`spawn`/`killPointBuilder` itself.
// Every wave from 5.2b through 5.7 left these as documented injection
// points "for a later wave," and nothing in the shipped codebase calls
// `explosionAt`/`superboomAt` from anywhere but `chainAt`/`floodAt`
// internally — confirmed by grep, not assumed. Wiring the full mine-cascade
// (with correct causer-player attribution at every tank/builder/shell
// trigger site) is real, undesigned subsystem work in its own right, the
// same shape of discovery that split Wave 5.5a out of 5.2b (D22) — it does
// not belong silently inside "orchestration."

/// One combined tick of the unified simulation. `ticksSinceLastUpdate` is
/// caller-owned, per-player elapsed-tick data (indexed like `state.players`)
/// — `seq`/`lastUpdate` live in a `BoloNet`-side table, not `BoloKit`, per
/// Wave 6.0's design call, so lag/staleness decisions take that data as an
/// explicit read-only input rather than storing it here. `runTick` never
/// mutates `seq` itself and never decides `CLUpdate` emission cadence
/// (`seq % 5 == 0`) — both are the caller's job once `seq` is available to
/// it; `BoloKit` cannot call into `BoloNet` without inverting the
/// `Package.swift` dependency direction (`BoloNet` depends on `BoloKit`,
/// not the reverse).
public func runTick(
    state: inout GameState,
    ticksSinceLastUpdate: [UInt64],
    onPlayerLagStatusChanged: (Int) -> Void = { _ in },
    onPlayerDisconnected: (Int) -> Void = { _ in },
    onPause: (Int) -> Void = { _ in },
    onTimeLimitWarning: (Int) -> Void = { _ in },
    onBaseControlWarning: (Int) -> Void = { _ in },
    onCoolPill: (Int) -> Void = { _ in },
    onReplenishBase: (Int) -> Void = { _ in },
    onGrow: (Int, Int) -> Void = { _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in },
    onExplosion: (Vec2f) -> Void = { _ in },
    onSuperboom: () -> Void = {},
    onSmallboom: () -> Void = {},
    onSpawn: () -> Void = {}
) {
    // 1. Pause gate. Mirrors `server.pause`'s tri-state handling
    // (server.c:1088-1099) and doubles as `runclient()`'s `client.pause`
    // early-exit (client.c:430) — a paused unified tick does nothing else.
    if state.pause != 0 {
        if state.pause > 0 {
            state.pause -= 1
            if state.pause % Int(ticksPerSec) == 0 {
                onPause(state.pause / Int(ticksPerSec))
            }
        }
        return
    }

    // 2. Time-limit warnings + freeze. Mirrors server.c:1102-1135. Exact
    // tick equality, not `>=` — matches C's `else if` chain exactly, so
    // only one branch (or none) fires per tick.
    if state.timeLimit > 0 {
        let limitTicks = Int(ticksPerSec) * state.timeLimit
        var fired = false
        for seconds in [300, 60, 10, 5, 4, 3, 2, 1] {
            if Int(state.ticks) == limitTicks - seconds * Int(ticksPerSec) {
                onTimeLimitWarning(seconds)
                fired = true
                break
            }
        }
        if !fired {
            if Int(state.ticks) == limitTicks {
                onTimeLimitWarning(0)
                state.ticks += 1
                return
            } else if Int(state.ticks) > limitTicks {
                return
            }
        }
    }

    // 3. Domination base-control win-condition. Mirrors server.c:1140-1176.
    // **Real trap, preserved exactly (see Wave 6.1 pre-brief):** the reset
    // to 0 only happens in the inner `else` below (all-bases-check failed
    // while base 0 is still held) — if base 0 itself isn't held (or there
    // are no bases), `baseControlCounter` is left untouched, not reset.
    if !state.bases.isEmpty,
       state.bases[0].armour >= UInt8(minBaseArmour),
       state.bases[0].owner != playerNeutral {
        let owner0 = Int(state.bases[0].owner)
        var allAllied = true
        for i in 1..<state.bases.count {
            let ownerI = Int(state.bases[i].owner)
            guard state.bases[i].armour >= UInt8(minBaseArmour),
                  state.players[owner0].alliance & (1 << ownerI) != 0,
                  state.players[ownerI].alliance & (1 << owner0) != 0
            else {
                allAllied = false
                break
            }
        }

        if allAllied {
            state.baseControlCounter += 1
            let threshold = Int(ticksPerSec) * state.baseControlThreshold
            var fired = false
            for seconds in [10, 5, 4, 3, 2, 1] {
                if state.baseControlCounter == threshold - seconds * Int(ticksPerSec) {
                    onBaseControlWarning(seconds)
                    fired = true
                    break
                }
            }
            if !fired {
                if state.baseControlCounter == threshold {
                    onBaseControlWarning(0)
                    state.ticks += 1
                    return
                } else if state.baseControlCounter > threshold {
                    return
                }
            }
        } else {
            state.baseControlCounter = 0
        }
        // else (outer condition false): counter left untouched, matching C.
    }

    state.ticks += 1

    // 4. Disconnect-lagged-players decision + removeplayer()'s pure core
    // (drop onboard pills, mark disconnected). Socket close is 6.4's job;
    // `onPlayerDisconnected` is where a caller does that. Runs before
    // coolPills/replenishBases/growTrees below so their internal
    // `connected`-count matches C's `nplayers`, computed in the same loop
    // that disconnects stale players (server.c:1188-1204) before those
    // three calls use it (server.c:1206-1246) — a deliberate refinement
    // over the Wave 6.1 pre-brief's "detection only" framing, since the
    // pill-drop and `connected` flip are pure state, not transport.
    for player in state.players.indices where state.players[player].connected {
        guard player < ticksSinceLastUpdate.count,
              ticksSinceLastUpdate[player] >= 9 * UInt64(ticksPerSec)
        else { continue }

        var pills: UInt16 = 0
        for i in state.pills.indices
            where Int(state.pills[i].owner) == player && state.pills[i].armour == pillOnboard {
            pills |= 1 << i
        }
        let tank = state.players[player].tank
        dropPills(player: player, x: tank.x, y: tank.y, pills: pills, state: &state)
        state.players[player].connected = false
        onPlayerDisconnected(player)

        // `server.pauseonplayerexit` (server.c:1192-1197) — same nesting
        // level as this loop, not removeplayer()'s own code. `255` is
        // already the wire's established "indefinite pause" sentinel
        // (see `joinplayerserver()`'s `bolopreamble.pause = 255` for
        // `server.pause == -1`), so this reuses `onPause` rather than
        // adding a new callback.
        if state.pauseOnPlayerExit {
            state.pause = -1
            onPause(255)
        }
    }

    // 5. Cool pills / replenish bases / grow trees / chain / flood — all
    // already-shipped per-tick passes (Wave 5.5a/5.7), just sequenced here.
    coolPills(state: &state, onCoolPill: onCoolPill)
    replenishBases(state: &state, onReplenishBase: onReplenishBase)
    growTrees(state: &state, onGrow: onGrow)
    chain(state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)
    flood(state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills)

    // 6. Lagged-player status callback. Mirrors client.c:437-447's two
    // thresholds — mutually exclusive per player per tick, matching C's
    // `if`/`else if`.
    for player in state.players.indices where player < ticksSinceLastUpdate.count {
        let elapsed = ticksSinceLastUpdate[player]
        if elapsed == 3 * UInt64(ticksPerSec) {
            onPlayerLagStatusChanged(player)
        } else if elapsed == UInt64(ticksPerSec) {
            onPlayerLagStatusChanged(player)
        }
    }

    // 7. Client-role per-player physics — every one of these is an
    // already-shipped Wave 5 function; this orchestrator only sequences
    // them, matching runclient()'s own order (client.c:449-484).
    //
    // **Disclosed simplification (PARITY Finding 2, Wave 6.1 D35):** C's
    // move-tanks loop gates on `connected && seq != 0` (client.c:451);
    // `tankMoveTick`'s own `connected` guard covers the first half, but
    // there's no `seq`-equivalent gate here for the second. `seq` was
    // deliberately excluded from `BoloKit` (Wave 6.0's design call), and
    // `seq != 0` means "never received a real update about player i yet"
    // — a network-bootstrapping concern with no analog when `GameState`
    // *is* the authoritative state rather than a mirror waiting on
    // broadcasts. Same shape as the `timelimitreached`/`basecontrolreached`
    // unification disclosed in this file's header, just not previously
    // written down here.
    let oldTankPositions = state.players.map { $0.tank }

    for player in state.players.indices {
        tankMoveTick(
            player: player, state: &state,
            onExplosion: onExplosion, onSuperboom: onSuperboom, onSmallboom: onSmallboom, onSpawn: onSpawn
        )
    }

    let localOld = oldTankPositions[state.localPlayer]
    tankLocalTick(
        old: Pointi(x: Int32(localOld.x), y: Int32(localOld.y)), state: &state,
        onSuperboomTerrain: onSuperboomTerrain, onMineExplosion: onMineExplosion, onDropPills: onDropPills
    )

    for player in state.players.indices {
        builderTick(player: player, state: &state, onMineExplosion: onMineExplosion)
    }

    pillTick(state: &state, oldTankPositions: oldTankPositions, onMineExplosion: onMineExplosion, onDropPills: onDropPills)

    for player in state.players.indices {
        shellTick(player: player, state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills)
    }

    explosionTick(state: &state)
}
