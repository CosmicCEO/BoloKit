import Testing
import BoloKit

struct PerPlayerLocalStatsTests {
    @Test func defaultLocalMatchesTheOldSingletonDefault() {
        let state = GameState()
        let expected = LocalPlayerState()
        #expect(state.localStats.count == maxPlayers)
        #expect(state.local.armour == expected.armour)
        #expect(state.local.shells == expected.shells)
        #expect(state.local.range == expected.range)
        #expect(state.local.respawnCounter == expected.respawnCounter)
        #expect(state.local.spawned == expected.spawned)
        #expect(state.local.refuelingBase == expected.refuelingBase)
        #expect(state.local.deaths == expected.deaths)
    }

    @Test func localReadsAndWritesOnlyTheLocalPlayersSlot() {
        var state = GameState()
        state.localPlayer = 1
        state.local.armour = 33
        #expect(state.localStats[1].armour == 33)
        #expect(state.localStats[0].armour == 0)
        #expect(state.local.armour == 33)
    }

    @Test func initLocalParameterSeedsTheLocalPlayersSlot() {
        let state = GameState(localPlayer: 2, local: LocalPlayerState(armour: 9))
        #expect(state.localStats[2].armour == 9)
        #expect(state.localStats[0].armour == 0)
        #expect(state.local.armour == 9)
    }

    @Test func withSimulatedPlayerSwapsLocalToThatPlayerAndLeavesOthersUntouched() {
        var state = GameState()
        state.localStats[0].armour = 40
        state.localStats[1].armour = 7
        withSimulatedPlayer(1, &state) { $0.local.armour -= 2 }
        #expect(state.localStats[1].armour == 5)
        #expect(state.localStats[0].armour == 40)
        #expect(state.local.armour == 40)
    }

    @Test func withSimulatedPlayerRestoresLocalPlayerAndReturnsTheBodysValue() {
        var state = GameState()
        state.localPlayer = 2
        let result: Int = withSimulatedPlayer(1, &state) { s in
            guard s.localPlayer == 1 else { return -1 }
            return 42
        }
        #expect(result == 42)
        #expect(state.localPlayer == 2)
    }
}
