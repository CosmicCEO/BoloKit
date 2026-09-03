import BoloKit

// MARK: - Wave 6.4a — dgramclient()'s post-decode application logic
//
// Ported from `dgramclient()`'s per-packet body (`client.c:1280-1472`), the
// part after Wave 6.0's `CLUpdate.decode` already ran. Lives in `BoloNet`,
// not `BoloKit`, because it needs both a `BoloKit` `GameState` and
// `BoloNet`'s decoded wire types (`CLUpdateHeader`/`CLUpdateShell`/
// `CLUpdateExplosion`) plus `isNewerSeq` — the same "bridges the two
// modules" placement `Preambles.swift`'s `assembleBoloPreamble` already
// established (Wave 6.3).
//
// `seq`/`lastupdate` are caller-supplied, not read from `GameState` — Wave
// 6.0's own design call (reaffirmed by `RunTick.swift`'s Wave 6.1
// disclosure and `SessionLogic.swift`'s `evaluateJoinRequest`): this port
// never stores per-player network sequence bookkeeping in `GameState`
// itself. Callers own that table; this function takes the old values in
// and returns the new ones out, rather than mutating a field that doesn't
// exist.
//
// Fog-of-war (`client.fog`) is never modeled anywhere in this port
// (established precedent — see `TankLocalTick.swift`/`BuilderTick.swift`/
// `RecvSR.swift`'s own file headers for the same four C calls) — the
// near/far sound-effect distinction `dgramclient()` makes by checking
// `client.fog[][]` is simplified here to a single callback per sound,
// firing whenever the wire bit is set, with no distance branch.
// `printmessage`'s builder-death chat line is skipped for the same
// established reason (UI-layer, never modeled).

/// `client.c`'s dead-reckoning extrapolation loop
/// (`client.c:1446-1454`) iterates `(mySeq - theirBeliefOfMySeq)/2` times
/// unbounded — a real griefing/DoS vector once real transport exists (a
/// lagged or adversarial peer can inflate this arbitrarily). D44 approves
/// this as the bound: 3 seconds' worth of ticks, long enough to smooth an
/// ordinary UDP burst-loss gap without visible correction-snapping, short
/// enough to bound worst-case per-packet CPU. Not a literal port of
/// anything in `client.c` — a `writeRun`-class Swift-side safety
/// deviation (D36's framing), named as its own constant so a future
/// reader doesn't mistake `* 3` for an oracle-derived value.
public let maxDeadReckoningExtrapolationTicks: Int = Int(ticksPerSec) * 3

/// Applies one decoded `CLUpdate` describing another player's state.
/// Returns the new `(seq, lastupdate)` pair for the caller to store
/// against `header.player`, or `nil` if the update was rejected (self-
/// echo, unknown/disconnected player, or not newer than what's already
/// stored) — mirroring every `continue`/no-op path in the real
/// `dgramclient()` loop that skips the rest of the body.
@discardableResult
public func applyRemotePlayerUpdate(
    header: CLUpdateHeader, shells: [CLUpdateShell], explosions: [CLUpdateExplosion],
    previousRemoteSeq: Int32, previousRemoteLastUpdate: Int32, myOwnSeq: Int32,
    state: inout GameState,
    onPlayerLagStatusChanged: (Int) -> Void = { _ in },
    onTankShotSound: () -> Void = {},
    onPillShotSound: () -> Void = {},
    onSinkSound: () -> Void = {},
    onBuilderDeathSound: () -> Void = {},
    onDropPills: (UInt16, Vec2f) -> Void = { _, _ in },
    onMineExplosion: (Pointi) -> Void = { _ in },
    onSuperboomTerrain: (Pointi) -> Void = { _ in },
    onExplosion: (Vec2f) -> Void = { _ in },
    onSuperboom: () -> Void = {},
    onSmallboom: () -> Void = {},
    onSpawn: () -> Void = {}
) -> (seq: Int32, lastUpdate: Int32)? {
    let player = Int(header.player)

    // `clupdate.hdr.player == client.player` (client.c:1305) -- decode
    // already bounds-checks `player < maxPlayers`; the self-echo skip is
    // this loop's own job, not the codec's.
    guard player != state.localPlayer else { return nil }
    guard state.players[player].connected else { return nil }
    guard isNewerSeq(header.seq[player], than: previousRemoteSeq) else { return nil }

    // Lag-status check uses the OLD lastupdate, before this update's
    // values are applied (client.c:1341-1343).
    if myOwnSeq - previousRemoteLastUpdate >= Int32(ticksPerSec) {
        onPlayerLagStatusChanged(player)
    }

    state.players[player].dead = header.dead
    state.players[player].boat = header.boat
    state.players[player].dir = header.dir
    state.players[player].tank = header.tank
    state.players[player].speed = header.speed
    state.players[player].turnSpeed = header.turnSpeed
    state.players[player].kickDir = header.kickDir
    state.players[player].kickSpeed = header.kickSpeed
    // A malformed/adversarial peer's raw byte may not be a valid
    // BuilderStatus case (0-5) -- C just stores whatever int value; Swift
    // has no such "invalid but stored" state for a closed enum. Leaving
    // the previous status untouched on an out-of-range byte is a Swift-
    // safety deviation, not a fidelity choice -- there's no oracle
    // behavior to match once the byte is outside the enum's real range.
    if let builderStatus = BuilderStatus(rawValue: Int(header.builderStatus)) {
        state.players[player].builderStatus = builderStatus
    }
    state.players[player].builder = header.builder
    state.players[player].builderTarget = Pointi(x: Int32(header.builderTargetX), y: Int32(header.builderTargetY))
    state.players[player].builderWait = Int(header.builderWait)
    state.players[player].inputFlags = InputFlags(rawValue: UInt32(bitPattern: header.inputFlags))

    if header.tankShotSound { onTankShotSound() }
    if header.pillShotSound { onPillShotSound() }
    if header.sinkSound { onSinkSound() }
    if header.builderDeathSound { onBuilderDeathSound() }

    state.players[player].shells = shells.map {
        Shell(point: $0.point, dir: $0.dir, range: $0.range, owner: $0.owner, boat: $0.boat, pill: $0.pill)
    }

    var newExplosions: [Explosion] = []
    newExplosions.reserveCapacity(explosions.count)
    for e in explosions {
        let explosion = Explosion(point: e.point, counter: Int(e.counter))
        newExplosions.append(explosion)
        if explosion.counter < 5 {
            killPointBuilder(at: explosion.point, state: &state, onDropPills: onDropPills)
        }
    }
    state.players[player].explosions = newExplosions

    // Dead-reckoning: extrapolate `player`'s tank/builder/shells/
    // explosions forward to compensate for the latency since their last
    // real update, gated on "they've acknowledged at least one update
    // from us" (client.c:1446, `seq[client.player] != 0`) and bounded per
    // D44 above.
    let theirBeliefOfMySeq = header.seq[state.localPlayer]
    if theirBeliefOfMySeq != 0 {
        let rawCount = Int(myOwnSeq &- theirBeliefOfMySeq) / 2
        let count = min(max(rawCount, 0), maxDeadReckoningExtrapolationTicks)
        for _ in 0..<count {
            tankMoveTick(
                player: player, state: &state,
                onExplosion: onExplosion, onSuperboom: onSuperboom, onSmallboom: onSmallboom, onSpawn: onSpawn
            )
            builderTick(player: player, state: &state, onMineExplosion: onMineExplosion)
            shellTick(player: player, state: &state, onMineExplosion: onMineExplosion, onDropPills: onDropPills)
            // `explosionTick` (Wave 5.5b) only ever drains every
            // connected player's list plus the global one in a single
            // pass -- calling it here, potentially up to
            // `maxDeadReckoningExtrapolationTicks` times per packet,
            // would over-age every OTHER player's explosions and the
            // global list too, not just `player`'s. `explosionlogic(i)`
            // in the real C is genuinely per-player; this port's version
            // collapsed that granularity away (Wave 5.5b's own header
            // explains why, for the normal per-tick case, where it's
            // called exactly once per player anyway). Inlining the same
            // two-line drain scoped to just `player`'s own list avoids
            // reaching back into that already-shipped function's
            // signature for this one caller's different shape of need.
            state.players[player].explosions = state.players[player].explosions.compactMap { explosion in
                var explosion = explosion
                explosion.counter += 1
                return explosion.counter > explosionTicks ? nil : explosion
            }
        }
    }

    return (header.seq[player], myOwnSeq)
}
