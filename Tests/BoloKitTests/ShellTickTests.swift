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

@Test func applyDamagePillDirectHitHeatsAndDecrementsArmour() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 5)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state)
    #expect(state.pills[0].armour == 9)
    #expect(state.pills[0].speed == 20)
    #expect(state.pills[0].counter == 0)
}

@Test func applyDamagePillDirectHitClampsSpeedToMinTicksPerShot() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 10, counter: 5)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state)
    // 10/2 = 5, clamped up to minTicksPerShot (6).
    #expect(state.pills[0].speed == UInt8(minTicksPerShot))
}

@Test func applyDamageDeadPillIsUntouched() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 40, counter: 5)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state)
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
    state.pills = [Pill(x: 52, y: 50, armour: 10, owner: 1, speed: 40, counter: 5)]  // 2 squares away, allied
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state)
    #expect(state.bases[0].armour == 45)
    #expect(state.bases[0].counter == 0)
    // Base-splash heating does NOT decrement armour, only speed/counter.
    #expect(state.pills[0].armour == 10)
    #expect(state.pills[0].speed == 20)
    #expect(state.pills[0].counter == 0)
}

@Test func applyDamageResourcedBaseDoesNotHeatNonAlliedPillsNearby() {
    let owner = connectedPlayer()
    let hostile = connectedPlayer()
    var state = makeState(players: [owner, hostile])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 0, shells: 10, mines: 10)]
    state.pills = [Pill(x: 52, y: 50, armour: 10, owner: 1, speed: 40, counter: 5)]  // not allied
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state)
    #expect(state.pills[0].speed == 40)
    #expect(state.pills[0].counter == 5)
}

@Test func applyDamageUnderResourcedBaseIsUntouched() {
    var state = makeState(players: [connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: UInt8(minBaseArmour - 1), owner: 0, shells: 10, mines: 10)]
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state)
    #expect(state.bases[0].armour == UInt8(minBaseArmour - 1))
}

@Test func applyDamageTerrainProgressionNonBoat() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .wall
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state)
    #expect(state.terrain[50, 50] == .damagedWall3)

    state.terrain[51, 50] = .forest
    applyDamage(at: Pointi(x: 51, y: 50), boat: false, state: &state)
    #expect(state.terrain[51, 50] == .grass3)

    // Non-boat shells do not step plain grass at all (not in the damage set).
    state.terrain[52, 50] = .grass1
    applyDamage(at: Pointi(x: 52, y: 50), boat: false, state: &state)
    #expect(state.terrain[52, 50] == .grass1)
}

@Test func applyDamageTerrainProgressionBoat() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass1
    applyDamage(at: Pointi(x: 50, y: 50), boat: true, state: &state)
    #expect(state.terrain[50, 50] == .grass0)

    state.terrain[51, 50] = .damagedWall0
    applyDamage(at: Pointi(x: 51, y: 50), boat: true, state: &state)
    #expect(state.terrain[51, 50] == .rubble3)
}

@Test func applyDamageBoatRoadWithWaterAdjacencyBecomesRiver() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .road
    state.terrain[49, 50] = .river
    state.terrain[51, 50] = .river
    applyDamage(at: Pointi(x: 50, y: 50), boat: true, state: &state)
    #expect(state.terrain[50, 50] == .river)
}

@Test func applyDamageBoatRoadWithoutWaterAdjacencyIsUnchanged() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .road
    state.terrain[49, 50] = .grass0
    state.terrain[51, 50] = .grass0
    state.terrain[50, 49] = .grass0
    state.terrain[50, 51] = .grass0
    applyDamage(at: Pointi(x: 50, y: 50), boat: true, state: &state)
    #expect(state.terrain[50, 50] == .road)
}

@Test func applyDamageMinedTerrainTriggersOnMineExplosionWithoutMutatingTerrain() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .minedForest
    var exploded: Pointi?
    applyDamage(at: Pointi(x: 50, y: 50), boat: false, state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == Pointi(x: 50, y: 50))
    #expect(state.terrain[50, 50] == .minedForest)
}

// MARK: - touchTile

@Test func touchTileMinedTerrainTriggersOnMineExplosion() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .minedGrass
    var exploded: Pointi?
    touchTile(at: Pointi(x: 50, y: 50), state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == Pointi(x: 50, y: 50))
}

@Test func touchTilePlainTerrainDoesNotTriggerOnMineExplosion() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    var exploded: Pointi?
    touchTile(at: Pointi(x: 50, y: 50), state: &state, onMineExplosion: { exploded = $0 })
    #expect(exploded == nil)
}

// MARK: - shellCollisionTest: pills

@Test func shellCollisionTestArmedPillIsConsumedAndHeated() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 10, owner: playerNeutral, speed: 40, counter: 5)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    let consumed = shellCollisionTest(shell: shell, state: &state)
    #expect(consumed)
    #expect(state.pills[0].armour == 9)
}

@Test func shellCollisionTestDeadPillIsNotConsumed() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [Pill(x: 50, y: 50, armour: 0, owner: playerNeutral, speed: 40, counter: 5)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    let consumed = shellCollisionTest(shell: shell, state: &state)
    #expect(!consumed)
}

// MARK: - shellCollisionTest: bases

@Test func shellCollisionTestPillFiredShellAlwaysPassesThroughBases() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: true)
    let consumed = shellCollisionTest(shell: shell, state: &state)
    #expect(!consumed)
    #expect(state.bases[0].armour == 50)
}

@Test func shellCollisionTestBoatShellOnHostileResourcedBaseDamagesIt() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: 50, owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    let consumed = shellCollisionTest(shell: shell, state: &state)
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
    let consumed = shellCollisionTest(shell: shell, state: &state)
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
    let consumed = shellCollisionTest(shell: shell, state: &state)
    #expect(!consumed)
    #expect(state.bases[0].armour == 50)
    #expect(state.players[0].explosions.isEmpty)
}

@Test func shellCollisionTestNonBoatShellOnUnderResourcedHostileBasePassesThroughUnconsumed() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()])
    state.bases = [Base(x: 50, y: 50, armour: UInt8(minBaseArmour - 1), owner: 1, shells: 10, mines: 10)]
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    let consumed = shellCollisionTest(shell: shell, state: &state)
    #expect(!consumed)
}

// MARK: - shellCollisionTest: terrain

@Test func shellCollisionTestBoatShellPassesThroughOpenWater() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .sea
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    #expect(!shellCollisionTest(shell: shell, state: &state))
}

@Test func shellCollisionTestBoatShellDamagesSolidTerrain() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: true, pill: false)
    #expect(shellCollisionTest(shell: shell, state: &state))
    #expect(state.terrain[50, 50] == .swamp3)
}

@Test func shellCollisionTestNonBoatShellPassesThroughGrass() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .grass0
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    #expect(!shellCollisionTest(shell: shell, state: &state))
    #expect(state.terrain[50, 50] == .grass0)
}

@Test func shellCollisionTestNonBoatShellDamagesForest() {
    var state = makeState(players: [connectedPlayer()])
    state.terrain[50, 50] = .forest
    let shell = Shell(point: Vec2f(x: 50.5, y: 50.5), dir: 0, range: 5, owner: 0, boat: false, pill: false)
    #expect(shellCollisionTest(shell: shell, state: &state))
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
    #expect(state.players[0].explosions.count == 1)
    // Target is remote (not localPlayer): no LocalPlayerState armour pool
    // to decrement against in this port — see ShellTick.swift's file header.
    #expect(state.local.armour == 40)
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

@Test func killTankScattersOnboardPillsAndMarksDead() {
    var state = makeState(players: [connectedPlayer()])
    state.pills = [
        Pill(x: 1, y: 1, armour: pillOnboard, owner: 0, speed: 40, counter: 0),
        Pill(x: 2, y: 2, armour: pillOnboard, owner: 0, speed: 40, counter: 0),
        Pill(x: 3, y: 3, armour: 10, owner: 0, speed: 40, counter: 0),  // placed, not onboard
    ]
    state.local.builderPill = 1  // reserved by the builder — excluded from the scatter mask

    var droppedMask: UInt16?
    var droppedAt: Vec2f?
    state.players[0].tank = Vec2f(x: 7, y: 8)
    killTank(state: &state, onDropPills: { mask, point in
        droppedMask = mask
        droppedAt = point
    })

    #expect(droppedMask == 0b0001)  // only pill 0
    #expect(droppedAt == Vec2f(x: 7, y: 8))
    #expect(state.players[0].dead)
    #expect(!state.players[0].boat)
    #expect(state.local.deaths == 1)
    #expect(state.local.respawnCounter == 0)
}

@Test func killTankOnAlreadyDeadTankIsNoOp() {
    var state = makeState(players: [connectedPlayer(dead: true)])
    state.local.deaths = 3
    var called = false
    killTank(state: &state, onDropPills: { _, _ in called = true })
    #expect(!called)
    #expect(state.local.deaths == 3)
}
