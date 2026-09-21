import Testing
import BoloKit
import BoloNet

// Swift-only tests for `applyRemotePlayerUpdate` (Wave 6.4a) -- the
// pure post-decode application logic ported from `dgramclient()`
// (client.c:1280-1472). Not differential against a C oracle in the
// per-field sense (Wave 6.0's `clupdate_decode_oracle` already covers
// the decode step this function consumes); these instead cover the
// NEW logic this wave adds: the self/connected/newness guards, the
// lag-status threshold, the field-mapping, the shell/explosion
// rebuild + killPointBuilder trigger, and the D44-bounded
// dead-reckoning loop.

private func connectedPlayer() -> PlayerState {
    var p = PlayerState()
    p.used = true
    p.connected = true
    return p
}

private func makeState(players: [PlayerState], localPlayer: Int = 0) -> GameState {
    var state = GameState()
    state.players = players
    state.localPlayer = localPlayer
    state.terrain[50, 50] = .grass0
    // killBuilder() (TankLocalTick.swift) picks a random index into
    // `state.starts` unconditionally on every builder kill -- an empty
    // array (the bare GameState() default) traps. At least one entry is
    // required by any fixture that can reach a builder-kill path, same
    // pitfall already documented for other fixtures in this test suite.
    state.starts = [Start(x: 50, y: 50, dir: 0)]
    for i in state.players.indices {
        state.players[i].tank = Vec2f(x: 50.5, y: 50.5)
        state.players[i].builder = Vec2f(x: 50.5, y: 50.5)
    }
    return state
}

private func makeHeader(
    player: UInt8,
    seq: [Int32] = Array(repeating: 0, count: maxPlayers),
    dead: Bool = false,
    boat: Bool = false,
    dir: Float = 0,
    tank: Vec2f = Vec2f(x: 50.5, y: 50.5),
    speed: Float = 0,
    turnSpeed: Float = 0,
    kickDir: Float = 0,
    kickSpeed: Float = 0,
    builderStatus: UInt8 = 0,
    builder: Vec2f = Vec2f(x: 50.5, y: 50.5),
    builderTargetX: UInt8 = 0,
    builderTargetY: UInt8 = 0,
    builderWait: UInt8 = 0,
    inputFlags: Int32 = 0,
    tankShotSound: Bool = false,
    pillShotSound: Bool = false,
    sinkSound: Bool = false,
    builderDeathSound: Bool = false
) -> CLUpdateHeader {
    CLUpdateHeader(
        player: player, seq: seq, dead: dead, boat: boat, dir: dir, tank: tank, speed: speed,
        turnSpeed: turnSpeed, kickDir: kickDir, kickSpeed: kickSpeed, builderStatus: builderStatus,
        builder: builder, builderTargetX: builderTargetX, builderTargetY: builderTargetY,
        builderWait: builderWait, inputFlags: inputFlags, tankShotSound: tankShotSound,
        pillShotSound: pillShotSound, sinkSound: sinkSound, builderDeathSound: builderDeathSound
    )
}

// MARK: - Guards

@Test func applyRemotePlayerUpdateSkipsSelfEcho() {
    var state = makeState(players: [connectedPlayer()], localPlayer: 0)
    let header = makeHeader(player: 0, tank: Vec2f(x: 99, y: 99))
    let result = applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 10, state: &state
    )
    #expect(result == nil)
    #expect(state.players[0].tank == Vec2f(x: 50.5, y: 50.5))
}

@Test func applyRemotePlayerUpdateSkipsDisconnectedPlayer() {
    var players = [connectedPlayer(), PlayerState()]
    players[1].connected = false
    var state = makeState(players: players, localPlayer: 0)
    let header = makeHeader(player: 1, tank: Vec2f(x: 99, y: 99))
    let result = applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 10, state: &state
    )
    #expect(result == nil)
    #expect(state.players[1].tank != Vec2f(x: 99, y: 99))
}

@Test func applyRemotePlayerUpdateSkipsStaleSeq() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 5
    let header = makeHeader(player: 1, seq: seq, tank: Vec2f(x: 99, y: 99))
    let result = applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 10, previousRemoteLastUpdate: 0, myOwnSeq: 20, state: &state  // 10 is newer than the incoming 5
    )
    #expect(result == nil)
    #expect(state.players[1].tank != Vec2f(x: 99, y: 99))
}

// MARK: - Field mapping

@Test func applyRemotePlayerUpdateMapsAllFields() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 5
    let header = makeHeader(
        player: 1, seq: seq, dead: true, boat: true, dir: 1.5, tank: Vec2f(x: 10, y: 20),
        speed: 2, turnSpeed: 3, kickDir: 4, kickSpeed: 5, builderStatus: 3,
        builder: Vec2f(x: 30, y: 40), builderTargetX: 60, builderTargetY: 70, builderWait: 8,
        inputFlags: Int32(bitPattern: InputFlags.accel.rawValue)
    )
    let result = applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
    )
    #expect(result?.seq == 5)
    let p = state.players[1]
    #expect(p.dead)
    #expect(p.boat)
    #expect(p.dir == 1.5)
    #expect(p.tank == Vec2f(x: 10, y: 20))
    #expect(p.speed == 2)
    #expect(p.turnSpeed == 3)
    #expect(p.kickDir == 4)
    #expect(p.kickSpeed == 5)
    #expect(p.builderStatus == .wait)  // rawValue 3
    #expect(p.builder == Vec2f(x: 30, y: 40))
    #expect(p.builderTarget == Pointi(x: 60, y: 70))
    #expect(p.builderWait == 8)
    #expect(p.inputFlags.contains(.accel))
}

@Test func applyRemotePlayerUpdateInvalidBuilderStatusByteLeavesPreviousUntouched() {
    var players = [connectedPlayer(), connectedPlayer()]
    players[1].builderStatus = .goto
    var state = makeState(players: players, localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    let header = makeHeader(player: 1, seq: seq, builderStatus: 200)  // not a real BuilderStatus case
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
    )
    #expect(state.players[1].builderStatus == .goto)  // untouched, not trapped
}

// MARK: - Sound callbacks

@Test func applyRemotePlayerUpdateFiresOnlyTheSoundBitsThatAreSet() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    let header = makeHeader(player: 1, seq: seq, tankShotSound: true, sinkSound: true)
    var fired: Set<String> = []
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state,
        onTankShotSound: { fired.insert("tank") },
        onPillShotSound: { fired.insert("pill") },
        onSinkSound: { fired.insert("sink") },
        onBuilderDeathSound: { fired.insert("builderDeath") }
    )
    #expect(fired == ["tank", "sink"])
}

// MARK: - Shell/explosion rebuild + killPointBuilder

@Test func applyRemotePlayerUpdateRebuildsShellListFromScratch() {
    var players = [connectedPlayer(), connectedPlayer()]
    players[1].shells = [Shell(point: Vec2f(x: 1, y: 1), dir: 0, range: 1, owner: 1, boat: false, pill: false)]
    var state = makeState(players: players, localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    let newShell = CLUpdateShell(owner: 1, point: Vec2f(x: 9, y: 9), boat: true, pill: false, dir: 1.0, range: 5.0)
    let header = makeHeader(player: 1, seq: seq)
    applyRemotePlayerUpdate(
        header: header, shells: [newShell], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
    )
    #expect(state.players[1].shells.count == 1)
    #expect(state.players[1].shells[0].point == Vec2f(x: 9, y: 9))
    #expect(state.players[1].shells[0].boat)
}

@Test func applyRemotePlayerUpdateTriggersKillPointBuilderForFreshExplosionsOnly() {
    var players = [connectedPlayer(), connectedPlayer()]
    players[0].builderStatus = .goto
    players[0].builder = Vec2f(x: 50.5, y: 50.5)
    var state = makeState(players: players, localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    let fresh = CLUpdateExplosion(point: Vec2f(x: 50.5, y: 50.5), counter: 2)  // < 5: kills a nearby builder
    let stale = CLUpdateExplosion(point: Vec2f(x: 50.5, y: 50.5), counter: 10)  // >= 5: does not
    let header = makeHeader(player: 1, seq: seq)
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [fresh, stale],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
    )
    #expect(state.players[1].explosions.count == 2)
    #expect(state.players[0].builderStatus == .parachute)  // killed -- killBuilder respawns via parachute
}

// MARK: - Lag-status callback

@Test func applyRemotePlayerUpdateFiresLagStatusAtThresholdUsingOldLastUpdate() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    let header = makeHeader(player: 1, seq: seq)
    var fired = false
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: Int32(ticksPerSec), state: &state,
        onPlayerLagStatusChanged: { _ in fired = true }
    )
    #expect(fired)

    fired = false
    state.players[1] = connectedPlayer()
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: Int32(ticksPerSec) - 1, state: &state,
        onPlayerLagStatusChanged: { _ in fired = true }
    )
    #expect(!fired)
}

// MARK: - Dead reckoning

@Test func applyRemotePlayerUpdateSkipsExtrapolationWhenTheyHaveNoUpdateFromUs() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    seq[0] = 0  // their belief of my seq: zero -> "no update from us yet"
    let header = makeHeader(player: 1, seq: seq)
    let explosion = CLUpdateExplosion(point: Vec2f(x: 1, y: 1), counter: 0)
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [explosion],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 1000, state: &state
    )
    #expect(state.players[1].explosions[0].counter == 0)  // never aged: no extrapolation ran
}

/// The dead-reckoning iteration count is observed indirectly via how many
/// times the inlined per-player explosion-aging step ran, since it's a
/// precise, side-effect-free counter unaffected by tank-movement physics.
@Test func applyRemotePlayerUpdateExtrapolatesExactDivisorCount() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    seq[0] = 100  // their belief of my seq
    let header = makeHeader(player: 1, seq: seq)
    let explosion = CLUpdateExplosion(point: Vec2f(x: 1, y: 1), counter: 0)
    // myOwnSeq - theirBeliefOfMySeq = 110 - 100 = 10, /2 = 5 iterations.
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [explosion],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 110, state: &state
    )
    #expect(state.players[1].explosions[0].counter == 5)
}

/// D44's whole reason for existing: an unbounded loop here would attempt
/// roughly `Int32.max`-scale iterations (calling `tankMoveTick`/
/// `builderTick`/`shellTick` each time) and never return in practice.
/// This test's real assertion is that it *completes* at all -- with the
/// bound in place it runs at most `maxDeadReckoningExtrapolationTicks`
/// iterations regardless of how large the divisor is; the aged-out
/// explosion is a secondary confirmation, not the main point.
@Test func applyRemotePlayerUpdateClampsExtrapolationToD44BoundInsteadOfHanging() {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    var seq = Array(repeating: Int32(0), count: maxPlayers)
    seq[1] = 1
    seq[0] = 1  // nonzero, so extrapolation is attempted
    let header = makeHeader(player: 1, seq: seq)
    let explosion = CLUpdateExplosion(point: Vec2f(x: 1, y: 1), counter: 0)
    applyRemotePlayerUpdate(
        header: header, shells: [], explosions: [explosion],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: .max, state: &state
    )
    #expect(state.players[1].explosions.isEmpty)  // aged well past explosionTicks within the bounded run
}

// MARK: - #62 S3: authority split when the host simulates remote players

/// Host state with remote player 1 holding host-owned combat state (dead, boat, kick, a shell and an
/// explosion) that a guest update must not be able to overwrite.
private func hostSimulatedState(flag: Bool) -> GameState {
    var state = makeState(players: [connectedPlayer(), connectedPlayer()], localPlayer: 0)
    for y in 40..<70 { for x in 40..<70 { state.terrain[x, y] = .grass0 } }
    state.hostSimulatesRemotePlayers = flag
    state.players[1].dead = true
    state.players[1].boat = true
    state.players[1].kickDir = 1
    state.players[1].kickSpeed = 2
    state.players[1].shells = [Shell(point: Vec2f(x: 51, y: 51), dir: 0, range: 3, owner: 1, boat: false, pill: false)]
    state.players[1].explosions = [Explosion(point: Vec2f(x: 52, y: 52), counter: 1)]
    return state
}

private func guestClaimHeader(seq: Int32, tank: Vec2f = Vec2f(x: 60.5, y: 61.5), speed: Float = 2, beliefOfHostSeq: Int32 = 0) -> CLUpdateHeader {
    var seqs = Array(repeating: Int32(0), count: maxPlayers)
    seqs[1] = seq
    seqs[0] = beliefOfHostSeq
    return makeHeader(
        player: 1, seq: seqs, dead: false, boat: false, dir: 1.5, tank: tank, speed: speed, turnSpeed: 3,
        kickDir: 0, kickSpeed: 0, inputFlags: Int32(bitPattern: InputFlags.shoot.rawValue)
    )
}

@Test func hostSimulatedUpdateKeepsHostOwnedFieldsAndTakesGuestOwnedOnes() {
    var state = hostSimulatedState(flag: true)
    let result = applyRemotePlayerUpdate(
        header: guestClaimHeader(seq: 5), shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
    )
    #expect(result?.seq == 5)
    let p = state.players[1]
    #expect(p.dead, "the guest cannot revive itself")
    #expect(p.boat)
    #expect(p.kickDir == 1)
    #expect(p.kickSpeed == 2)
    #expect(p.shells.count == 1, "the host's shell list must survive a guest update")
    #expect(p.explosions.count == 1)
    #expect(p.dir == 1.5)
    #expect(p.tank == Vec2f(x: 60.5, y: 61.5))
    #expect(p.speed == 2)
    #expect(p.turnSpeed == 3)
    #expect(p.inputFlags == [.shoot])
}

@Test func withoutHostSimulationAGuestUpdateStillOverwritesEverything() {
    var state = hostSimulatedState(flag: false)
    applyRemotePlayerUpdate(
        header: guestClaimHeader(seq: 5), shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
    )
    let p = state.players[1]
    #expect(!p.dead)
    #expect(!p.boat)
    #expect(p.kickSpeed == 0)
    #expect(p.shells.isEmpty)
    #expect(p.explosions.isEmpty)
}

@Test func hostSimulatedUpdateSkipsDeadReckoningExtrapolation() {
    // The guest believes the host is 40 ticks ahead of it, so an unsimulated apply extrapolates 20 ticks.
    let claimed = Vec2f(x: 55.5, y: 50.5)
    var extrapolated = hostSimulatedState(flag: false)
    applyRemotePlayerUpdate(
        header: guestClaimHeader(seq: 5, tank: claimed, speed: 3, beliefOfHostSeq: 1), shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 41, state: &extrapolated
    )
    #expect(extrapolated.players[1].tank != claimed, "control: without the gate the tank is extrapolated forward")

    var simulated = hostSimulatedState(flag: true)
    applyRemotePlayerUpdate(
        header: guestClaimHeader(seq: 5, tank: claimed, speed: 3, beliefOfHostSeq: 1), shells: [], explosions: [],
        previousRemoteSeq: 0, previousRemoteLastUpdate: 0, myOwnSeq: 41, state: &simulated
    )
    #expect(simulated.players[1].tank == claimed, "the host's own runTick moves host-simulated tanks; extrapolating too would double-simulate")
}

@Test func hostSimulatedRemoteShellIsNotWipedByFollowingGuestUpdates() {
    var state = hostSimulatedState(flag: true)
    state.players[1].dead = false
    state.players[1].boat = false
    state.players[1].shells = []
    state.players[1].explosions = []
    state.players[1].tank = Vec2f(x: 50.5, y: 50.5)
    state.starts = [Start(x: 45, y: 45, dir: 0)]
    for p in 0..<2 {
        state.localStats[p].shells = 20
        state.localStats[p].armour = maxArmour
        state.localStats[p].range = 5.0
        state.localStats[p].shellCounter = shellFireThresholdTicks + 10
    }
    for n in 1...4 {
        // Each guest update claims no shells (its own copy has none) while holding the shoot key.
        applyRemotePlayerUpdate(
            header: guestClaimHeader(seq: Int32(n), tank: state.players[1].tank, speed: 0), shells: [], explosions: [],
            previousRemoteSeq: Int32(n - 1), previousRemoteLastUpdate: 0, myOwnSeq: 0, state: &state
        )
        runTick(state: &state, ticksSinceLastUpdate: [0, 0])
    }
    #expect(state.players[1].shells.count == 1, "exactly one shell fired by the host simulation, not wiped by guest updates")
    #expect(state.localStats[1].shells == 19, "exactly one shell spent")
}

@Test func hostSimulatedJoinedRemoteRespawnsAliveAtAStart() {
    var state = GameState()
    for y in 20..<70 { for x in 20..<70 { state.terrain[x, y] = .grass0 } }
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    state.players[0] = connectedPlayer()
    state.players[0].dead = false
    state.players[0].tank = Vec2f(x: 30.5, y: 30.5)
    state.localPlayer = 0
    state.starts = [Start(x: 45, y: 45, dir: 0)]
    state.hostSimulatesRemotePlayers = true
    applyJoin(player: 1, name: "Guest", address: "127.0.0.1", rejoin: false, state: &state)

    var ticks = 0
    while state.players[1].dead, ticks < 1000 {
        runTick(state: &state, ticksSinceLastUpdate: Array(repeating: 0, count: maxPlayers))
        ticks += 1
    }
    #expect(!state.players[1].dead, "a joined remote must respawn through the host's own respawn branch")
    #expect(Int(state.players[1].tank.x) == 45 && Int(state.players[1].tank.y) == 45)
}
