import Testing
import BoloKit
import CXBolo

// D137: differential coverage for `resolveBuilderTask` against
// `getbuildertask_oracle` (Sources/CXBolo/builderops.c, a verbatim
// transcription of `getbuildertaskforcommand()`, client.c:6539-6698, with
// `client.seentiles[at.y][at.x]` replaced by an explicit tile parameter —
// see that file's comment for why).

@Suite struct BuilderCommandDifferentialTests {

    /// Every non-mined/mined terrain variant this port models, paired with
    /// the C tile constant it corresponds to (tiles.h). Pill/base tiles
    /// are exercised separately below via `findPill`, since this port has
    /// no terrain-level tile for "occupied by a pill."
    static let terrainToTile: [(BoloKit.Terrain, Int32)] = [
        (.sea, 16 /* kSeaTile */), (.boat, 9 /* kBoatTile */), (.wall, 0 /* kWallTile */),
        (.river, 1 /* kRiverTile */),
        (.swamp0, 2), (.swamp1, 2), (.swamp2, 2), (.swamp3, 2),
        (.crater, 3), (.road, 4), (.forest, 5),
        (.rubble0, 6), (.rubble1, 6), (.rubble2, 6), (.rubble3, 6),
        (.grass0, 7), (.grass1, 7), (.grass2, 7), (.grass3, 7),
        (.damagedWall0, 8), (.damagedWall1, 8), (.damagedWall2, 8), (.damagedWall3, 8),
        (.minedSea, 17 /* kMinedSeaTile */), (.minedSwamp, 10), (.minedCrater, 11),
        (.minedRoad, 12), (.minedForest, 13), (.minedRubble, 14), (.minedGrass, 15),
    ]

    @Test func testResolveBuilderTaskMatchesOracleForAllTerrainAndCommands() {
        for (terrain, tile) in Self.terrainToTile {
            for command in [BuilderCommandKind.tree, .road, .wall, .pill, .mine] {
                var state = GameState()
                state.terrain[20, 20] = terrain
                let target = BoloKit.Pointi(x: 20, y: 20)

                let swiftResult = resolveBuilderTask(command: command, target: target, state: state)
                let cResult = CXBolo.getbuildertask_oracle(Int32(command.rawValue), tile)

                #expect(
                    swiftResult.rawValue == cResult,
                    "mismatch: command=\(command) terrain=\(terrain) tile=\(tile) swift=\(swiftResult) c=\(cResult)"
                )
            }
        }
    }

    @Test func testResolveBuilderTaskRepairPillTakesPriorityOverTerrain() {
        // kFriendlyPill00Tile == 20 (tiles.h, after the 4 base tiles
        // starting at kFriendlyBaseTile == 18/19/20... offsets confirmed
        // via the oracle call itself rather than re-deriving the raw
        // value here — the oracle is the source of truth for tile enum
        // layout, this test only needs BUILDERPILL + "a pill is present"
        // vs. BUILDERPILL + "no pill, buildable terrain".
        var state = GameState()
        state.terrain[30, 30] = .grass0
        state.pills = [Pill(x: 30, y: 30, armour: 5, owner: 0, speed: 30, counter: 0)]
        let target = BoloKit.Pointi(x: 30, y: 30)

        #expect(resolveBuilderTask(command: .pill, target: target, state: state) == .repairPill)

        state.pills = []
        #expect(resolveBuilderTask(command: .pill, target: target, state: state) == .buildPill)
    }

    @Test func testQueueBuilderCommandGatesOnStatusAndDeathAndPendingSlot() {
        var state = GameState()
        state.players = [PlayerState(dead: false)]
        let target = BoloKit.Pointi(x: 20, y: 20)

        // Ready + alive: queues.
        queueBuilderCommand(command: .tree, target: target, player: 0, state: &state)
        #expect(state.players[0].pendingBuilderCommand == .tree)

        // Slot already occupied: second click dropped (matches C's
        // `nextbuildercommand == BUILDERNILL` gate).
        queueBuilderCommand(command: .mine, target: target, player: 0, state: &state)
        #expect(state.players[0].pendingBuilderCommand == .tree)

        // Dead: never queues.
        state.players[0].pendingBuilderCommand = nil
        state.players[0].dead = true
        queueBuilderCommand(command: .tree, target: target, player: 0, state: &state)
        #expect(state.players[0].pendingBuilderCommand == nil)

        // Parachuting: never queues.
        state.players[0].dead = false
        state.players[0].builderStatus = .parachute
        queueBuilderCommand(command: .tree, target: target, player: 0, state: &state)
        #expect(state.players[0].pendingBuilderCommand == nil)
    }

    @Test func testReadyTickResolvesPendingCommandThenClearsSlot() {
        var state = GameState()
        state.players = [PlayerState(dead: false, connected: true)]
        state.terrain[20, 20] = .forest
        let target = BoloKit.Pointi(x: 20, y: 20)

        queueBuilderCommand(command: .tree, target: target, player: 0, state: &state)
        builderTick(player: 0, state: &state)

        #expect(state.players[0].pendingBuilderCommand == nil)
        #expect(state.players[0].builderTask == .getTree)
        #expect(state.players[0].builderStatus == .goto)
    }
}
