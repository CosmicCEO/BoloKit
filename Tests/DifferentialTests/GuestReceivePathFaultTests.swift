import Testing
import BoloKit

// Analyze register (v1.6.9 benchmark) items 3B and 4B: two suspected guest receive-path
// faults, each pinned by the smallest unit test that reaches the fault without a live pair.
// The `withKnownIssue` wrappers name the register item; a fix flips the test, which is the
// signal to remove the wrapper.

private func guestState(mines: Int, tank: BoloKit.Vec2f) -> GameState {
    var state = GameState()
    state.hiddenMines = true
    state.localPlayer = 0
    state.players = [PlayerState()]
    state.players[0].used = true
    state.players[0].connected = true
    state.players[0].dead = false
    state.players[0].alliance = 1 << 0
    state.players[0].tank = tank
    state.players[0].mines = mines
    return state
}

@Suite struct AnalyzeRegister3BMineRefundTests {

    /// 3B: the guest spends a mine when its builder launches (`BuilderTick.swift`'s
    /// `.placeMine` case: `builderMines = 1; mines -= 1`), but the host only spends it when
    /// `CLPlaceMine` arrives on builder arrival (`HostSession.swift`, "#174"). A tank status
    /// sent during the walk therefore carries the host's pre-launch count, and
    /// `recvSrTankStatus` writes it straight over `mines` while `builderMines` still holds
    /// the spent one.
    @Test func tankStatusDuringBuilderWalkDoesNotRefundTheMine() {
        let n = 5
        var state = guestState(mines: n, tank: BoloKit.Vec2f(x: 50.5, y: 50.5))
        state.players[0].builderTask = .placeMine
        state.players[0].builderTarget = Pointi(x: 55, y: 55)

        builderTick(player: 0, state: &state) // ready -> goto: launches with the mine aboard
        #expect(state.players[0].builderStatus == .goto)
        #expect(state.players[0].mines == n - 1)
        #expect(state.players[0].builderMines == 1)

        // Host-side count is still N while the builder walks; a status lands with it.
        recvSrTankStatus(
            armour: 40, shells: 40, mines: n, trees: 0, range: 8, dead: false, boat: false,
            kickDir: 0, kickSpeed: 0, teleport: nil, state: &state
        )

        let mines = state.players[0].mines
        let builderMines = state.players[0].builderMines
        withKnownIssue("Analyze register 3B: status message refunds a mine the builder is still carrying") {
            #expect(mines == n - 1, "mines=\(mines) builderMines=\(builderMines)")
            #expect(mines + builderMines == n, "mines=\(mines) builderMines=\(builderMines)")
        }
    }
}

@Suite struct AnalyzeRegister4BFogMemoryRevealTests {

    /// 4B: the guest snapshots `seenTiles` from its own (redacted) terrain the moment a tile
    /// becomes visible (`increaseVis`, via `updateFogVisionTracker` in `GameSession`), and
    /// `decreaseVis` re-samples it from that same terrain when vision is lost. A later
    /// `SRRevealTerrain` writes `state.terrain` only (`recvSrRevealTerrain`) and never touches
    /// `seenTiles`, so once the tile is fogged the drawn tile (`fogResolvedTileGrid`) is the
    /// stale unmined memory.
    @Test func revealOfAMinedTileRefreshesTheGuestsFogMemory() {
        let tile = Pointi(x: 50, y: 50)
        let index = Int(tile.y) * 256 + Int(tile.x)
        var state = guestState(mines: 0, tank: BoloKit.Vec2f(x: 50.5, y: 50.5))
        state.terrain[Int(tile.x), Int(tile.y)] = .grass0 // host truth is `.minedGrass`; the guest has the redacted view
        var tracker = FogVisionTracker()

        // Tile comes into view: memory = plain grass.
        updateFogVisionTracker(&tracker, observer: 0, state: state)
        #expect(tracker.fogState.fog[index] > 0)
        #expect(tracker.fogState.seenTiles[index] == .grass)

        // Tank moves far away: the tile drops back into fog.
        state.players[0].tank = BoloKit.Vec2f(x: 120.5, y: 120.5)
        updateFogVisionTracker(&tracker, observer: 0, state: state)
        #expect(tracker.fogState.fog[index] == 0)

        // The host's proximity reveal (`HostGameEngine.updateFogVision` ->
        // `revealNearbyHiddenMines` -> `SRRevealTerrain`) lands after the move.
        recvSrRevealTerrain(x: Int(tile.x), y: Int(tile.y), terrain: .minedGrass, state: &state)
        #expect(state.terrain[Int(tile.x), Int(tile.y)] == .minedGrass)

        let drawn = Tile(rawValue: fogResolvedTileGrid(for: state, fogState: tracker.fogState)[Int(tile.x), Int(tile.y)])
        let remembered = tracker.fogState.seenTiles[index]
        withKnownIssue("Analyze register 4B: reveal of a mined tile does not refresh the guest's fog memory") {
            #expect(remembered == .minedGrass, "seenTiles=\(String(describing: remembered))")
            #expect(drawn == .minedGrass, "drawn=\(String(describing: drawn))")
        }
    }
}
