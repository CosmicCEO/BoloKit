import Testing
import BoloKit

// MARK: - Pill state predicates

@Test func pillIsOnboard() {
    let pill = Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 50, counter: 0)
    #expect(pill.isOnboard)
    #expect(!pill.isArmed)
    #expect(!pill.isDead)
}

@Test func pillIsArmed() {
    let pill = Pill(x: 5, y: 5, armour: 10, owner: 0, speed: 50, counter: 0)
    #expect(!pill.isOnboard)
    #expect(pill.isArmed)
    #expect(!pill.isDead)
}

@Test func pillIsDead() {
    let pill = Pill(x: 5, y: 5, armour: 0, owner: 0, speed: 50, counter: 0)
    #expect(!pill.isOnboard)
    #expect(!pill.isArmed)
    #expect(pill.isDead)
}

// MARK: - findPill / findBase

@Test func findPillSkipsOnboard() {
    let pills = [
        Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 50, counter: 0),
        Pill(x: 8, y: 8, armour: 10, owner: 0, speed: 50, counter: 0),
    ]
    #expect(findPill(x: 5, y: 5, pills: pills) == nil)
    #expect(findPill(x: 8, y: 8, pills: pills) == 1)
}

@Test func findBaseAlwaysFound() {
    // No armour/owner filter at all — findBase matches purely on position,
    // including a base that would be considered "dead" (armour 0).
    let bases = [Base(x: 5, y: 5, armour: 0, owner: 0, shells: 0, mines: 0)]
    #expect(findBase(x: 5, y: 5, bases: bases) == 0)
    #expect(findBase(x: 6, y: 5, bases: bases) == nil)
}

// MARK: - testAlliance

@Test func testAllianceRequiresMutualBits() {
    var players = [PlayerState(used: true), PlayerState(used: true)]
    // Only player 0 -> 1 is allied; one-sided
    players[0].alliance = 1 << 1
    #expect(!testAlliance(0, 1, players: players))

    // Now mutual
    players[1].alliance = 1 << 0
    #expect(testAlliance(0, 1, players: players))
}

@Test func testAllianceRequiresUsedOnBothSides() {
    var players = [PlayerState(used: false), PlayerState(used: true)]
    players[0].alliance = 1 << 1
    players[1].alliance = 1 << 0
    // player 0 is not "used" -> never allied with anyone
    #expect(!testAlliance(0, 1, players: players))
    #expect(!testAlliance(1, 0, players: players))
}

@Test func testAllianceOutOfRangeIndicesAreFalse() {
    let players = [PlayerState(used: true)]
    #expect(!testAlliance(0, 5, players: players))
    #expect(!testAlliance(-1, 0, players: players))
}

// MARK: - BuilderStatus / BuilderTask raw values (must match bolo.h order)

@Test func builderStatusRawValues() {
    #expect(BuilderStatus.ready.rawValue == 0)
    #expect(BuilderStatus.goto.rawValue == 1)
    #expect(BuilderStatus.work.rawValue == 2)
    #expect(BuilderStatus.wait.rawValue == 3)
    #expect(BuilderStatus.`return`.rawValue == 4)
    #expect(BuilderStatus.parachute.rawValue == 5)
}

@Test func builderTaskRawValues() {
    #expect(BuilderTask.doNothing.rawValue == 0)
    #expect(BuilderTask.getTree.rawValue == 1)
    #expect(BuilderTask.buildRoad.rawValue == 2)
    #expect(BuilderTask.buildWall.rawValue == 3)
    #expect(BuilderTask.buildBoat.rawValue == 4)
    #expect(BuilderTask.buildPill.rawValue == 5)
    #expect(BuilderTask.repairPill.rawValue == 6)
    #expect(BuilderTask.placeMine.rawValue == 7)
}

// MARK: - InputFlags

@Test func inputFlagsBitmask() {
    let flags: InputFlags = [.accel, .turnL]
    #expect(flags.contains(.accel))
    #expect(flags.contains(.turnL))
    #expect(!flags.contains(.brake))
    #expect(!flags.contains(.turnR))
    #expect(InputFlags.accel.rawValue == 0x0000_0001)
    #expect(InputFlags.decre.rawValue == 0x0000_0080)
}

// MARK: - Base.counter width

@Test func baseCounterHoldsMaxReplenishValue() {
    // replenishBaseTicks(600) + maxPlayers(16) - 1 = 615, must fit in UInt16
    var base = Base(x: 0, y: 0, armour: 0, owner: 0, shells: 0, mines: 0)
    base.counter = UInt16(replenishBaseTicks + maxPlayers - 1)
    #expect(base.counter == 615)
}

// MARK: - GameState construction sanity

@Test func gameStateDefaultConstructsCleanly() {
    let state = GameState()
    #expect(state.pills.isEmpty)
    #expect(state.bases.isEmpty)
    #expect(state.players.isEmpty)
    #expect(state.ticks == 0)
    #expect(state.terrain.storage.count == 256 * 256)
}
