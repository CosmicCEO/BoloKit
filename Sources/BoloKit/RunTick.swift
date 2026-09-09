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
// **Scope boundary, flagged in the Wave 6.1 completion report; updated B.5d
// (D100/D103):** `onMineExplosion`/`onSuperboomTerrain`/`onExplosion`/
// `onSuperboom`/`onSmallboom`/`onSpawn` remain straight pass-throughs to
// `runTick`'s own caller. `onDropPills` (the seventh, originally listed
// alongside these) is gone — B.5d found every real fire site
// (`killBuilder`/`drown`/`smallboom`/`superboom`/`killTank`) already runs
// nested inside this function's own `state: &state` access, so each now
// calls `dropPills` directly and surfaces `onShouldBroadcastDropPill`
// instead, the same fix `onSpawn` already got in D88 §4. The mine-chain
// broadcast gap this file's Wave 6.1 header once described ("nothing in the
// shipped codebase calls `explosionAt`/`superboomAt` from anywhere but
// `chainAt`/`floodAt` internally") was already stale by the time it was
// written — `TankLocalTick.swift`'s `smallboom`/`superboom`/`grabTile` and,
// later, `RecvCL.swift`'s ~15 call sites all call them too, and all of the
// latter already broadcast correctly (Wave 6.6). The one real remaining gap
// — `chain`/`flood`'s own cascading detonations — is fixed above via
// `onShouldBroadcastSmallBoom`.

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
    onExplosion: (Vec2f) -> Void = { _ in },
    onSuperboom: () -> Void = {},
    onSmallboom: () -> Void = {},
    onSpawn: () -> Void = {},
    // B.5d (D100/D103): this used to be wired only to the disconnect-triggered `dropPills` call
    // below (Wave 6.4c). `onDropPills` -- a bare `(UInt16, Vec2f) -> Void` pass-through with no
    // `state` access, threaded through `tankLocalTick`/`builderTick`/`pillTick`/`shellTick` -- had
    // the exact nested-`inout`-exclusivity problem `onSpawn` was already fixed for (D88 §4): no
    // caller-side closure can call `dropPills` itself while `runTick` already holds `state: &state`.
    // Removed; every real fire site (`killBuilder`/`drown`/`smallboom`/`superboom`/`killTank`) now
    // calls `dropPills` directly (it already runs nested inside this same `&state` access) and
    // surfaces this callback instead -- the one that was already correctly shaped for it.
    onShouldBroadcastDropPill: (Int, Int, Int) -> Void = { _, _, _ in },
    // B.5d (D100/D103): the one real mine-chain broadcast gap — `chain`/`flood`'s own cascading
    // `explosionAt(player: playerNeutral, ...)` calls, unlike every `RecvCL.swift` call site
    // (Wave 6.6, already wired), had no broadcast hook of their own until now.
    onShouldBroadcastSmallBoom: (UInt8, Int, Int) -> Void = { _, _, _ in },
    // D129 (Wave 1.1): `flood()`'s own crater-to-river conversion never had a
    // broadcast hook, mirroring `sendsrflood()`'s only call site in `floodat()`
    // (server.c:4038-4056). `chain`/`chainAt` never call `sendsrflood`, so this
    // is threaded only into the `flood(...)` call below, not `chain(...)`.
    onShouldBroadcastFlood: (Int, Int) -> Void = { _, _ in }
) {
    // 1. Pause gate. `serverPauseTicks` mirrors `server.pause`'s tri-state
    // countdown (server.c:1088-1099); `clientPauseDisplaySeconds` mirrors
    // `client.pause` (client.c:430) — wire-domain, never counted down
    // here either, but still gates the tick the same way runclient()'s
    // own early-exit does. D39: split from a single unified `pause`
    // field, which let this countdown and RecvSR.swift's `recvSrPause`
    // decode silently clobber each other's units.
    if state.serverPauseTicks != 0 || state.clientPauseDisplaySeconds != 0 {
        if state.serverPauseTicks > 0 {
            state.serverPauseTicks -= 1
            if state.serverPauseTicks % Int(ticksPerSec) == 0 {
                onPause(state.serverPauseTicks / Int(ticksPerSec))
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
        dropPills(player: player, x: tank.x, y: tank.y, pills: pills, state: &state, onShouldBroadcastDropPill: onShouldBroadcastDropPill)
        state.players[player].connected = false
        onPlayerDisconnected(player)

        // `server.pauseonplayerexit` (server.c:1192-1197) — same nesting
        // level as this loop, not removeplayer()'s own code. `255` is
        // already the wire's established "indefinite pause" sentinel
        // (see `joinplayerserver()`'s `bolopreamble.pause = 255` for
        // `server.pause == -1`), so this reuses `onPause` rather than
        // adding a new callback.
        if state.pauseOnPlayerExit {
            state.serverPauseTicks = -1
            onPause(255)
        }
    }

    // 5. Cool pills / replenish bases / grow trees / chain / flood — all
    // already-shipped per-tick passes (Wave 5.5a/5.7), just sequenced here.
    coolPills(state: &state, onCoolPill: onCoolPill)
    replenishBases(state: &state, onReplenishBase: onReplenishBase)
    growTrees(state: &state, onGrow: onGrow)
    chain(
        state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain,
        onShouldBroadcastDropPill: onShouldBroadcastDropPill, onShouldBroadcastSmallBoom: onShouldBroadcastSmallBoom
    )
    flood(
        state: &state, onMineExplosion: onMineExplosion, onSuperboomTerrain: onSuperboomTerrain,
        onShouldBroadcastDropPill: onShouldBroadcastDropPill, onShouldBroadcastSmallBoom: onShouldBroadcastSmallBoom,
        onShouldBroadcastFlood: onShouldBroadcastFlood
    )

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
            onExplosion: onExplosion, onSuperboom: onSuperboom, onSmallboom: onSmallboom, onSpawn: onSpawn,
            onShouldBroadcastDropPill: onShouldBroadcastDropPill
        )
    }

    let localOld = oldTankPositions[state.localPlayer]
    tankLocalTick(
        old: Pointi(x: Int32(localOld.x), y: Int32(localOld.y)), state: &state,
        onSuperboomTerrain: onSuperboomTerrain, onMineExplosion: onMineExplosion,
        onShouldBroadcastDropPill: onShouldBroadcastDropPill
    )

    for player in state.players.indices {
        builderTick(player: player, state: &state, onMineExplosion: onMineExplosion)
    }

    pillTick(
        state: &state, oldTankPositions: oldTankPositions, onMineExplosion: onMineExplosion,
        onShouldBroadcastDropPill: onShouldBroadcastDropPill
    )

    for player in state.players.indices {
        shellTick(
            player: player, state: &state, onMineExplosion: onMineExplosion,
            onShouldBroadcastDropPill: onShouldBroadcastDropPill
        )
    }

    explosionTick(state: &state)
}
