import Testing
import BoloKit

private func connectedPlayer(dead: Bool = false, boat: Bool = false, used: Bool = true) -> PlayerState {
    var p = PlayerState()
    p.connected = true
    p.dead = dead
    p.boat = boat
    p.used = used
    return p
}

private func makeState(players: [PlayerState], localPlayer: Int = 0) -> GameState {
    var state = GameState()
    state.players = players
    state.localPlayer = localPlayer
    // Safe default square, matching the fixture pitfall already recorded in
    // TankLocalTickTests: a bare GameState() puts (0,0) in the mined-sea
    // border ring, silently drowning anyone left at the default position.
    state.terrain[50, 50] = .grass0
    return state
}

// MARK: - heatPill / applyDamage

/// Q21 (D37): `heatPill` resets `Pill.coolCounter` (the SERVER-side
/// cooldown tally `coolPills` owns), never `Pill.counter` (the CLIENT-side
/// fire-cadence tally `pillTick` owns) — fixed from a Wave 5.3a field-
/// mapping bug that had been resetting the wrong one.
@Test func applyDamagePillDirectHitHeatsAndDecrementsArmour() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 5, coolCounter: 9)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state)
    #expect(state.pills[0].armour == 9)
    #expect(state.pills[0].speed == 20)
    #expect(state.pills[0].counter == 5)  // untouched: not heatPill's field
    #expect(state.pills[0].coolCounter == 0)  // reset: the correct field
}

@Test func applyDamagePillDirectHitClampsSpeedToMinTicksPerShot() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 10, counter: 5)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state)
    // 10/2 = 5, clamped up to minTicksPerShot (6).
    #expect(state.pills[0].speed == UInt8(minTicksPerShot))
}

@Test func applyDamageDeadPillIsUntouched() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 40, counter: 5)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state)
    #expect(state.pills[0].armour == 0)
    #expect(state.pills[0].speed == 40)
    #expect(state.pills[0].counter == 5)
}

@Test func applyDamageResourcedBaseIsDamagedAndHeatsAlliedPillsNearby() {
    var owner = connectedPlayer()
    owner.alliance = 0b10  // allied with player 1
    var ally = connectedPlayer()
    ally.alliance = 0b01  // allied with player 0
    var state = makeState(players: [owner, ally])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 0, shells: 10, mines: 10)]
    state.pills = [Pill(x: 52, y: 50, armour: 10, owner: 1, speed: 40, counter: 5, coolCounter: 9)]  // 2 squares away, allied
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state)
    #expect(state.bases[0].armour == 45)
    #expect(state.bases[0].counter == 0)
    // Base-splash heating does NOT decrement armour, only speed/coolCounter.
    #expect(state.pills[0].armour == 10)
    #expect(state.pills[0].speed == 20)
    #expect(state.pills[0].counter == 5)  // untouched: not heatPill's field
    #expect(state.pills[0].coolCounter == 0)  // reset: the correct field
}

@Test func applyDamageResourcedBaseDoesNotHeatNonAlliedPillsNearby() {
    let owner = connectedPlayer()
    let hostile = connectedPlayer()
    var state = makeState(players: [owner, hostile])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 0, shells: 10, mines: 10)]
    state.pills = [Pill(x: 52, y: 50, armour: 10, owner: 1, speed: 40, counter: 5)]  // not allied
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state)
    #expect(state.pills[0].speed == 40)
    #expect(state.pills[0].counter == 5)
}

@Test func applyDamageUnderResourcedBaseIsUntouched() {
    var state = makeState(players: [connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: UInt8(minBaseArmour - 1), owner: 0, shells: 10, mines: 10)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state)
    #expect(state.bases[0].armour == UInt8(minBaseArmour - 1))
}

@Test func applyDamageTerrainProgressionNonBoat() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .wall
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state)
    #expect(state.terrain[50, 50] == .damagedWall3)

    state.terrain[51, 50] = .forest
    applyDamage(at: Pointi(x: 51, y: 50), boat: false, player: 0, state: &state)
    #expect(state.terrain[51, 50] == .grass3)

    // Non-boat shells do not step plain grass at all (not in the damage set).
    state.terrain[52, 50] = .grass1
    applyDamage(at: Pointi(x: 52, y: 50), boat: false, player: 0, state: &state)
    #expect(state.terrain[52, 50] == .grass1)
}

@Test func applyDamageTerrainProgressionBoat() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass1
    applyDamage(at: Pointi(x: 50, y: 50), boat: true, player: 0, state: &state)
    #expect(state.terrain[50, 50] == .grass0)

    state.terrain[51, 50] = .damagedWall0
    applyDamage(at: Pointi(x: 51, y: 50), boat: true, player: 0, state: &state)
    #expect(state.terrain[51, 50] == .rubble3)
}

@Test func applyDamageBoatRoadWithWaterAdjacencyBecomesRiver() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .road
    state.terrain[49, 50] = .river
    state.terrain[51, 50] = .river
    applyDamage(at: Pointi(x: 50, y: 50), boat: true, player: 0, state: &state)
    #expect(state.terrain[50, 50] == .river)
}

@Test func applyDamageBoatRoadWithoutWaterAdjacencyIsUnchanged() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .road
    state.terrain[49, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 49] = .grass0
    state.terrain[50, 51] = .grass0
    applyDamage(at: Pointi(x: 50, y: 50), boat: true, player: 0, state: &state)
    #expect(state.terrain[50, 50] == .road)
}

/// D156: `applyDamage`'s mined-terrain case now calls `explosionAt` directly (not just the
/// `onMineExplosion` notify hook), so the tile actually detonates: converts to `.crater` and
/// applies splash damage — mirroring `TankLocalTick.swift`'s already-working `grabTile`. Renamed
/// from `...WithoutMutatingTerrain` (D28: a stated correction, not a coverage shrink), since that
/// name encoded the pre-fix bug as expected behavior.
@Test func applyDamageMinedTerrainDetonatesViaExplosionAt() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .minedForest
    var exploded: Pointi?
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, player: 0, state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == Pointi(x: 50, y: 50))
    #expect(state.terrain[50, 50] == .crater)
}

// MARK: - touchTile

/// D156: same fix as `applyDamage` above — `touchTile`'s mined-terrain case now calls
/// `explosionAt` directly, so terrain actually converts to `.crater`, not just notifying.
@Test func touchTileMinedTerrainTriggersOnMineExplosion() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .minedGrass
    var exploded: Pointi?
    touchTile(at: Pointi(x: 50, y: 50), player: 0, state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == Pointi(x: 50, y: 50))
    #expect(state.terrain[50, 50] == .crater)
}

@Test func touchTilePlainTerrainDoesNotTriggerOnMineExplosion() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    var exploded: Pointi?
    touchTile(at: Pointi(x: 50, y: 50), player: 0, state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == nil)
}

// MARK: - shellCollisionTest: pills

@Test func shellCollisionTestArmedPillIsConsumedAndHeated() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 5)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    let consumed = shellCollisionTest(shell: shell, player: 0, state: &state)
    #expect(consumed)
    #expect(state.pills[0].armour == 9)
}

@Test func shellCollisionTestDeadPillIsNotConsumed() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 40, counter: 5)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    let consumed = shellCollisionTest(shell: shell, player: 0, state: &state)
    #expect(!consumed)
}

// MARK: - shellCollisionTest: bases

@Test func shellCollisionTestPillFiredShellAlwaysPassesThroughBases() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: true)
    let consumed = shellCollisionTest(shell: shell, player: 0, state: &state)
    #expect(!consumed)
    #expect(state.bases[0].armour == 50)
}

@Test func shellCollisionTestBoatShellOnHostileResourcedBaseDamagesIt() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    let consumed = shellCollisionTest(shell: shell, player: 0, state: &state)
    #expect(consumed)
    #expect(state.bases[0].armour == 45)
}

@Test func shellCollisionTestBoatShellOnFriendlyBaseIsDudButStillConsumed() {
    var owner = connectedPlayer()
    owner.alliance = 0b10
    var ally = connectedPlayer()
    ally.alliance = 0b01
    var state = makeState(players: [owner, ally])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    let consumed = shellCollisionTest(shell: shell, player: 0, state: &state)
    #expect(consumed)
    #expect(state.bases[0].armour == 50)
    #expect(state.players[0].explosions.count == 1)
    #expect(state.players[0].explosions[0].point == shell.point)
}

@Test func shellCollisionTestNonBoatShellOnFriendlyBasePassesThroughUnconsumed() {
    var owner = connectedPlayer()
    owner.alliance = 0b10
    var ally = connectedPlayer()
    ally.alliance = 0b01
    var state = makeState(players: [owner, ally])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    let consumed = shellCollisionTest(shell: shell, player: 0, state: &state)
    #expect(!consumed)
    #expect(state.bases[0].armour == 50)
    #expect(state.players[0].explosions.isEmpty)
}

@Test func shellCollisionTestNonBoatShellOnUnderResourcedHostileBasePassesThroughUnconsumed() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: UInt8(minBaseArmour - 1), owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    let consumed = shellCollisionTest(shell: shell, player: 0, state: &state)
    #expect(!consumed)
}

// MARK: - shellCollisionTest: terrain

@Test func shellCollisionTestBoatShellPassesThroughOpenWater() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .sea
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    #expect(!shellCollisionTest(shell: shell, player: 0, state: &state))
}

@Test func shellCollisionTestBoatShellDamagesSolidTerrain() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    #expect(shellCollisionTest(shell: shell, player: 0, state: &state))
    #expect(state.terrain[50, 50] == .swamp3)
}

@Test func shellCollisionTestNonBoatShellPassesThroughGrass() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    #expect(!shellCollisionTest(shell: shell, player: 0, state: &state))
    #expect(state.terrain[50, 50] == .grass0)
}

@Test func shellCollisionTestNonBoatShellDamagesForest() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .forest
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    #expect(shellCollisionTest(shell: shell, player: 0, state: &state))
    #expect(state.terrain[50, 50] == .grass3)
}

// MARK: - shellTick: movement and expiry

@Test func shellTickAdvancesShellPositionAndRange() {
    var state = makeState(players: [connectedPlayer()])
    state.players[0].shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    ]
    shellTick(player: 0, state: &state)
    #expect(state.players[0].shells.count == 1)
    #expect(state.players[0].shells[0].point.x > 50.5)
    #expect(state.players[0].shells[0].range < 5)
}

@Test func shellTickExpiresShellAndTouchesMinedTerrain() {
    var state = makeState(players: [connectedPlayer()])
    state.players[0].shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 0.01, owner: 0, boat: false, pill: false)
    ]
    state.terrain[50, 50] = .minedGrass
    var exploded: Pointi?
    shellTick(player: 0, state: &state, onMineExplosion: { exploded = $0 })
    #expect(state.players[0].shells.isEmpty)
    #expect(state.players[0].explosions.count == 1)
    #expect(exploded == Pointi(x: 50, y: 50))
    // D156: `touchTile` now calls `explosionAt` directly, so the mined tile actually detonates
    // (converts to crater), not just notifies.
    #expect(state.terrain[50, 50] == .crater)
}

/// D156: the actually-reported bug, end to end — a shell hits a forest-blocked mined tile mid-
/// flight (the oracle's other narrow trigger case, `explosionAt`'s forest-block path, not just
/// range-expiry) via `shellCollisionTest`/`shellTick`, and the mine now really detonates: terrain
/// converts to crater and the tile is consumed. Confirms correct causer attribution too: the shell
/// belongs to `player: 1`'s own list (the shell-list owner threaded through as `explosionAt`'s
/// `player`), while `shell.owner` is deliberately set to `playerNeutral` — mirroring D112's
/// precedent that `shell.owner` can legitimately be neutral (an unowned pillbox's return fire) and
/// must never be used as an array index/causer. No crash, no misattribution.
@Test func shellTickDirectHitOnMinedForestDetonatesWithCorrectCauserNotShellOwner() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.terrain[50, 50] = .minedForest
    state.players[1].shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: playerNeutral, boat: false, pill: false)
    ]
    shellTick(player: 1, state: &state)
    #expect(state.players[1].shells.isEmpty)
    #expect(state.terrain[50, 50] == .crater)
}

// MARK: - shellTick: tank hits

@Test func shellTickHitsRemoteTankSetsKickWithoutLocalArmourChange() {
    var shooter = connectedPlayer()
    shooter.shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 1.0, range: 5, owner: 0, boat: false, pill: false)
    ]
    var target = connectedPlayer()
    target.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [shooter, target], localPlayer: 0)
    state.local.armour = 40

    shellTick(player: 1, state: &state)

    #expect(state.players[0].shells.isEmpty)
    #expect(state.players[1].kickSpeed == kickForce)
    #expect(state.players[1].kickDir == 1.0)
    // Fix: the hit-explosion belongs to the TARGET (`player`, here 1) being ticked, matching
    // `client.players[client.player].explosions` (client.c:5423) -- not the shooter/shell.owner
    // (this test's own original assertion, before the fix, wrongly expected it on player 0).
    #expect(state.players[1].explosions.count == 1)
    // Target is remote (not localPlayer): no LocalPlayerState armour pool
    // to decrement against in this port — see ShellTick.swift's file header.
    #expect(state.local.armour == 40)
}

// A mine-chain / crash fix, found live (Jerod driving a real map) -- a neutral pillbox's
// return-fire shell (owner: playerNeutral, per PillTick.swift) hitting any tank used to index
// `state.players[Int(shell.owner)]` == `state.players[0xff]`, trapping with "Index out of range."
// Not a contrived edge case: any neutral pillbox actually hitting a tank reproduced it in a fuzzed
// 20,000-tick drive across the real U.S.A.map fixture within the first couple thousand ticks.
@Test func shellTickNeutralOwnedShellHittingATankDoesNotCrashAndAttributesToTheTarget() {
    var shooter = connectedPlayer()
    shooter.shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 1.0, range: 5, owner: playerNeutral, boat: false, pill: true)
    ]
    var target = connectedPlayer()
    target.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [shooter, target], localPlayer: 1)

    shellTick(player: 1, state: &state)

    #expect(state.players[0].shells.isEmpty)
    #expect(state.players[1].kickSpeed == kickForce)
    #expect(state.players[1].explosions.count == 1)
}

@Test func shellTickHitOnLocalPlayerDecrementsArmourAndDropsBoat() {
    var shooter = connectedPlayer()
    shooter.shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 1, boat: false, pill: false)
    ]
    var localTarget = connectedPlayer(boat: true)
    localTarget.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [localTarget, shooter], localPlayer: 0)
    state.local.armour = 40

    shellTick(player: 0, state: &state)

    #expect(state.local.armour == 40 - shellDamage)
    #expect(!state.players[0].boat)
}

@Test func shellTickArmourDepletionKillsLocalTank() {
    var shooter = connectedPlayer()
    shooter.shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 1, boat: false, pill: false)
    ]
    var localTarget = connectedPlayer()
    localTarget.tank = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: [localTarget, shooter], localPlayer: 0)
    state.local.armour = 2  // less than shellDamage (5)

    shellTick(player: 0, state: &state)

    #expect(state.local.armour == 0)
    #expect(state.players[0].dead)
    #expect(state.local.deaths == 1)
}

@Test func shellTickSelfHitIsReplicatedNotExcluded() {
    // C's tank-hit loop never excludes the shooter's own tank from its own
    // shells — see ShellTick.swift's file header. Structurally reachable
    // only via an unusual fixture (a shell spawns 0.5 outside tank radius
    // 0.375 and travels outward in practice), but the code path itself must
    // not special-case "shell.owner == target".
    var state = makeState(players: [connectedPlayer()])
    state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
    state.players[0].shells = [
        Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    ]
    state.local.armour = 40

    shellTick(player: 0, state: &state)

    #expect(state.players[0].shells.isEmpty)
    #expect(state.local.armour == 40 - shellDamage)
}

// MARK: - killTank

// B.5d (D100/D103): `killTank` now calls `dropPills` directly (the `onSpawn`-precedent fix for
// the nested-`inout`-exclusivity problem `onDropPills` had) — this fires `onShouldBroadcastDropPill`
// once per pill actually placed, with that pill's real index and landed (x, y), not once with the
// raw mask and the tank's own scatter-origin point.
@Test func killTankScattersOnboardPillsAndMarksDead() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [
        Pill(x: 1, y: 1, armour: pillOnboard, owner: 0, speed: 40, counter: 0),
        Pill(x: 2, y: 2, armour: pillOnboard, owner: 0, speed: 40, counter: 0),
        Pill(x: 3, y: 3, armour: 10, owner: 0, speed: 40, counter: 0),  // placed, not onboard
    ]
    state.players[0].builderPill = 1  // reserved by the builder — excluded from the scatter mask

    var broadcasts: [(Int, Int, Int)] = []
    state.players[0].tank = Vec2f(x: 50, y: 60)
    killTank(state: &state, onShouldBroadcastDropPill: { pill, x, y in
        broadcasts.append((pill, x, y))
    })

    #expect(broadcasts.count == 1)  // only pill 0
    #expect(broadcasts.first?.0 == 0)
    #expect(broadcasts.first?.1 == 50)
    #expect(broadcasts.first?.2 == 60)
    #expect(state.pills[0].x == 50)
    #expect(state.pills[0].y == 60)
    #expect(state.players[0].dead)
    #expect(!state.players[0].boat)
    #expect(state.local.deaths == 1)
    #expect(state.local.respawnCounter == 0)
}

@Test func killTankOnAlreadyDeadTankIsNoOp() {
    var state = makeState(players: [connectedPlayer(dead: true)])
    state.local.deaths = 3
    var called = false
    killTank(state: &state, onShouldBroadcastDropPill: { _, _, _ in called = true })
    #expect(!called)
    #expect(state.local.deaths == 3)
}

// MARK: - shellCollisionTest: onSelfReportDamage (D142, B.10 follow-on join-path hook)

/// Guarded case: `player == state.localPlayer` and a real hit occurs (armed pill) — the callback
/// fires exactly once with the hit coordinates and the shell's own `boat` flag. Mirrors
/// `shellcollisiontest()`'s `sendcldamage` gate at the pill call site (client.c:5142).
@Test func shellCollisionTestSelfReportFiresOnLocalPlayersPillHit() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 5)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    var reports: [(Int, Int, Bool)] = []
    let consumed = shellCollisionTest(
        shell: shell, player: 0, state: &state,
        onSelfReportDamage: { x, y, boat in reports.append((x, y, boat)) }
    )
    #expect(consumed)
    #expect(reports.count == 1)
    #expect(reports.first?.0 == 50)
    #expect(reports.first?.1 == 50)
    #expect(reports.first?.2 == true)
}

/// Unguarded case: same hit, but `player != state.localPlayer` — the callback must never fire,
/// matching C's `if (player == client.player)` gate excluding every other player's own shell list.
@Test func shellCollisionTestSelfReportDoesNotFireForNonLocalPlayersPillHit() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 5)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 1, boat: false, pill: false)
    var reports: [(Int, Int, Bool)] = []
    let consumed = shellCollisionTest(
        shell: shell, player: 1, state: &state,
        onSelfReportDamage: { x, y, boat in reports.append((x, y, boat)) }
    )
    #expect(consumed)
    #expect(reports.isEmpty)
}

/// No-hit case: the shell belongs to the local player, but the terrain underneath is not
/// damageable (sea) — the callback must not fire even though the "owner" gate would otherwise
/// pass, matching `shellcollisiontest()`'s own `ret = 0` branches, which never reach `sendcldamage`.
@Test func shellCollisionTestSelfReportDoesNotFireOnANoHit() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.terrain[50, 50] = .sea
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    var reports: [(Int, Int, Bool)] = []
    let consumed = shellCollisionTest(
        shell: shell, player: 0, state: &state,
        onSelfReportDamage: { x, y, boat in reports.append((x, y, boat)) }
    )
    #expect(!consumed)
    #expect(reports.isEmpty)
}

/// Guarded case at a second, structurally distinct branch (non-boat terrain hit on a wall) —
/// confirms the hook is wired at more than just the pill call site, matching the pre-brief's
/// six-site port of `shellcollisiontest()`'s six `sendcldamage` calls.
@Test func shellCollisionTestSelfReportFiresOnLocalPlayersTerrainHit() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.terrain[50, 50] = .wall
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    var reports: [(Int, Int, Bool)] = []
    let consumed = shellCollisionTest(
        shell: shell, player: 0, state: &state,
        onSelfReportDamage: { x, y, boat in reports.append((x, y, boat)) }
    )
    #expect(consumed)
    #expect(reports.count == 1)
    #expect(reports.first?.0 == 50)
    #expect(reports.first?.1 == 50)
    #expect(reports.first?.2 == false)
}

/// `shellTick` threads `onSelfReportDamage` straight through to `shellCollisionTest` for every
/// shell it tests this tick — confirms the driver-level wiring (not just the leaf function) works
/// end to end, matching how the join `.tick` handler (`GameSession.swift`) actually calls it.
@Test func shellTickThreadsSelfReportDamageThroughToCollisionTest() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 5)]
    let shell = Shell(point: Vec2f(x: 50, y: 50), dir: 0, range: 0.01, owner: 0, boat: false, pill: false)
    state.players[0].shells = [shell]
    var reports: [(Int, Int, Bool)] = []
    shellTick(player: 0, state: &state, onSelfReportDamage: { x, y, boat in reports.append((x, y, boat)) })
    #expect(reports.count == 1)
    #expect(reports.first?.0 == 50)
    #expect(reports.first?.1 == 50)
    #expect(reports.first?.2 == false)
}
