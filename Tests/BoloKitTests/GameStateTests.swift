import Testing
import BoloKit

// #157: `hiddenMines` default flipped true (deliberate product decision, diverges from the
// oracle's own default-off). `pauseOnPlayerExit` stays default-off, matching the oracle.
@Test func gameStateDefaultsHiddenMinesOnAndPauseOnPlayerExitOff() {
    let state = GameState()
    #expect(state.hiddenMines == true)
    #expect(state.pauseOnPlayerExit == false)
}
