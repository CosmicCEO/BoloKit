import Testing
import BoloKit
@testable import BoloNet

// Issue #79 investigation: "remote tank name label always visible; should show only when
// close." `GameRenderView.drawSprites` gates both the remote-tank sprite's alpha and its name
// label on `visFraction(at:useForestTerm:)` (`vis > 0.90` for the label), which is
// `calcVis`/`fogVis` under `state.hiddenMines`. That wiring is private to `GameRenderView`, but
// it calls nothing beyond this file's own `calcVis`/`fogVis`/`increaseVis` -- so this exercises
// the exact same math `HostGameEngine.updateFogVision` and `GameRenderView.visFraction` compose,
// confirming whether the underlying fog mechanism the label depends on already fog-gates a
// distant enemy tank, or whether the reported "always visible" behavior needs a code fix here.
struct RemoteTankFogGateTests {

    /// Builds a `GameState` with an observer (`player 0`) and one other, unallied player
    /// (`player 1`) at the given tank positions, plus a `FogState` that only has `player 0`'s
    /// own vision rect applied -- mirroring `HostGameEngine.updateFogVision`'s per-mover
    /// `increaseVis` call for the observer's own tank (the only vision source in this scenario;
    /// `player 1` is not allied with `player 0`, so it does not contribute to `player 0`'s fog).
    private func observerState(observerTank: Vec2f, otherTank: Vec2f) -> (state: GameState, fog: FogState) {
        var state = GameState()
        state.hiddenMines = true

        var observer = PlayerState()
        observer.connected = true
        observer.used = true
        observer.dead = false
        observer.tank = observerTank
        observer.alliance = 1 << 0

        var other = PlayerState()
        other.connected = true
        other.used = true
        other.dead = false
        other.tank = otherTank
        other.alliance = 1 << 1

        state.players = [observer, other]
        state.localPlayer = 0

        var fog = FogState()
        increaseVis(
            tankVisionRect(around: observerTank), state: &fog, terrain: state.terrain,
            pills: state.pills, bases: state.bases, hiddenMines: state.hiddenMines, observer: 0,
            players: state.players
        )
        return (state, fog)
    }

    @Test func anEnemyTankFarOutsideTheObserversVisionRectStaysBelowTheLabelThreshold() {
        let observerTank = Vec2f(x: 50, y: 50)
        // 29x29 vision rect (14-tile radius, `tankVisionRect`) around (50, 50) covers roughly
        // x/y in [36, 64]. 100 units away is comfortably outside it either axis.
        let (state, fog) = observerState(observerTank: observerTank, otherTank: Vec2f(x: 150, y: 50))

        let vis = calcVis(state.players[1].tank, state: state, fogState: fog, observer: 0)
        #expect(vis <= 0.90, "an enemy tank far outside the observer's own vision rect must fall below the label-draw threshold")
    }

    @Test func anEnemyTankInsideTheObserversVisionRectClearsTheLabelThreshold() {
        let observerTank = Vec2f(x: 50, y: 50)
        let (state, fog) = observerState(observerTank: observerTank, otherTank: Vec2f(x: 52, y: 50))

        let vis = calcVis(state.players[1].tank, state: state, fogState: fog, observer: 0)
        #expect(vis > 0.90, "an enemy tank inside the observer's own vision rect must clear the label-draw threshold")
    }
}
