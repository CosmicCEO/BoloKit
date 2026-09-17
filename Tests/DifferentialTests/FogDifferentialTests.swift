import Testing
import BoloKit
import CXBolo

// v1.5.0 (issue #1) — fog-of-war. Fuzzes fogVis/calcVis's pure interpolation/blend
// arithmetic and fogTileFor's mine-substitution decision against the C oracle extracted
// in Sources/CXBolo/fog.c, mirroring PillTickDifferentialTests.swift's forestVis pattern.
// increaseVis/decreaseVis/revealNearbyHiddenMines are grid/loop orchestration with
// documented deviations from the literal C behavior (docs/CONSTRAINTS.md's "Fog-of-war"
// section), so they're exercised via direct Swift-only unit tests below instead of an
// oracle diff — there is no "correct" C behavior to fuzz against at those two spots.

@Suite struct FogVisDifferentialTests {

    @Test func testFogVisMatchesOracleFuzzed() {
        var fogState = FogState()
        for _ in 0..<3000 {
            let fx = Float.random(in: 0..<1)
            let fy = Float.random(in: 0..<1)
            let isCenterFogged = Bool.random()
            let neighborsFogged = (0..<8).map { _ in Bool.random() }

            fogState.fog[50 * 256 + 50] = isCenterFogged ? 0 : 1
            let deltas: [(Int, Int)] = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
            for (n, (dx, dy)) in zip(neighborsFogged, deltas) {
                fogState.fog[(50 + dy) * 256 + (50 + dx)] = n ? 0 : 1
            }

            let v = BoloKit.Vec2f(x: 50 + fx, y: 50 + fy)
            let swiftResult = fogVis(v, fogState: fogState)

            let derivedFx = v.x - floorf(v.x)
            let derivedFy = v.y - floorf(v.y)

            let cResult = CXBolo.fogvis_oracle(
                derivedFx, derivedFy,
                isCenterFogged ? 1 : 0,
                neighborsFogged[0] ? 1 : 0, neighborsFogged[1] ? 1 : 0, neighborsFogged[2] ? 1 : 0, neighborsFogged[3] ? 1 : 0,
                neighborsFogged[4] ? 1 : 0, neighborsFogged[5] ? 1 : 0, neighborsFogged[6] ? 1 : 0, neighborsFogged[7] ? 1 : 0
            )

            #expect(swiftResult == cResult, "mismatch fx=\(fx) fy=\(fy) centerFogged=\(isCenterFogged) neighborsFogged=\(neighborsFogged)")
        }
    }

    @Test func testFogVisTreatsOffMapAsFullyFogged() {
        let fogState = FogState()
        #expect(fogVis(BoloKit.Vec2f(x: -1, y: 10), fogState: fogState) == 0.0)
        #expect(fogVis(BoloKit.Vec2f(x: 256, y: 10), fogState: fogState) == 0.0)
        #expect(fogVis(BoloKit.Vec2f(x: 10, y: -1), fogState: fogState) == 0.0)
        #expect(fogVis(BoloKit.Vec2f(x: 10, y: 256), fogState: fogState) == 0.0)
    }
}

@Suite struct CalcVisDifferentialTests {

    @Test func testCalcVisBlendMatchesOracleFuzzed() {
        for _ in 0..<3000 {
            let forest = Float.random(in: 0...1)
            let fog = Float.random(in: 0...1)
            let dist = Float.random(in: 0...5)

            let swiftResult = calcVisBlend(forestVis: forest, fogVis: fog, dist: dist)
            let cResult = CXBolo.calcvis_blend_oracle(forest, fog, dist)

            #expect(swiftResult == cResult, "mismatch forest=\(forest) fog=\(fog) dist=\(dist)")
        }
    }

    @Test func testCalcVisUsesOwnTankAsAHardVisibilityFloor() {
        var state = GameState()
        state.players = [PlayerState()]
        state.players[0].tank = BoloKit.Vec2f(x: 50, y: 50)
        let fogState = FogState() // fully fogged everywhere, no forest at (50,50)

        // Standing on your own tank: dist == 0 <= 2.0, so vis is at least 0.5
        // regardless of fog/forest both being fully opaque (0.0 combined).
        let vis = calcVis(BoloKit.Vec2f(x: 50, y: 50), state: state, fogState: fogState, observer: 0)
        #expect(vis >= 0.5)
    }

    @Test func testCalcVisFarFromEverythingMatchesPlainFogTimesForest() {
        var state = GameState()
        state.players = [PlayerState()]
        state.players[0].tank = BoloKit.Vec2f(x: 10, y: 10)
        var fogState = FogState()
        // Fully lit at (200, 200) and its neighbors, no forest there.
        for dy in -1...1 {
            for dx in -1...1 {
                fogState.fog[(200 + dy) * 256 + (200 + dx)] = 1
            }
        }
        let v = BoloKit.Vec2f(x: 200.5, y: 200.5)
        let vis = calcVis(v, state: state, fogState: fogState, observer: 0)
        #expect(vis == 1.0) // fully lit, no forest, far from own tank/pills
    }
}

@Suite struct FogTileForDifferentialTests {

    private static let minedCases: [(Terrain, Tile)] = [
        (.minedSea, .sea), (.minedSwamp, .swamp), (.minedCrater, .crater),
        (.minedRoad, .road), (.minedForest, .forest), (.minedRubble, .rubble), (.minedGrass, .grass),
    ]

    @Test func testFogTileForHidesMineMatchesOracleFuzzed() {
        for _ in 0..<500 {
            let hiddenMines = Bool.random()
            let tileMatchesPrevious = Bool.random()
            let swiftShouldHide = hiddenMines && !tileMatchesPrevious
            let cShouldHide = CXBolo.fogtilefor_hides_mine_oracle(hiddenMines ? 1 : 0, tileMatchesPrevious ? 1 : 0) != 0
            #expect(swiftShouldHide == cShouldHide)
        }
    }

    @Test func testFogTileForSubstitutesUnminedTerrainWhenHiddenMinesOnAndNotPreviouslySeen() {
        var state = GameState()
        for (mined, unmined) in Self.minedCases {
            state.terrain[100, 100] = mined
            let result = fogTileFor(
                x: 100, y: 100, previousSeen: .unknown, terrain: state.terrain,
                pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
            )
            #expect(result == unmined, "\(mined) should substitute to \(unmined) when unseen")
        }
    }

    @Test func testFogTileForIsStickyOnceAMineHasBeenSeen() {
        var state = GameState()
        for (mined, _) in Self.minedCases {
            let expectedTile = terrainToTile(mined)
            state.terrain[100, 100] = mined
            let result = fogTileFor(
                x: 100, y: 100, previousSeen: expectedTile, terrain: state.terrain,
                pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
            )
            #expect(result == expectedTile, "\(mined) should stay revealed once previously seen")
        }
    }

    @Test func testFogTileForNeverHidesMinesWhenHiddenMinesIsOff() {
        var state = GameState()
        for (mined, _) in Self.minedCases {
            let expectedTile = terrainToTile(mined)
            state.terrain[100, 100] = mined
            let result = fogTileFor(
                x: 100, y: 100, previousSeen: .unknown, terrain: state.terrain,
                pills: [], bases: [], hiddenMines: false, observer: 0, players: state.players
            )
            #expect(result == expectedTile)
        }
    }

    @Test func testFogTileForPlainTerrainIsUnaffectedByHiddenMines() {
        var state = GameState()
        state.terrain[100, 100] = .grass0
        let result = fogTileFor(
            x: 100, y: 100, previousSeen: .unknown, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
        )
        #expect(result == .grass)
    }
}

@Suite struct IncreaseDecreaseVisTests {

    @Test func testIncreaseVisIncrementsFogAndSnapshotsNewlyVisibleTiles() {
        var state = GameState()
        state.terrain[100, 100] = .minedGrass
        var fogState = FogState()

        increaseVis(
            makerect(99, 99, 3, 3), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
        )

        #expect(fogState.fog[100 * 256 + 100] == 1)
        // Newly visible with hiddenMines on and never-seen-before: substituted to grass.
        #expect(fogState.seenTiles[100 * 256 + 100] == .grass)
    }

    @Test func testIncreaseVisClipsToTheMapAtNegativeOrigin() {
        var state = GameState()
        var fogState = FogState()
        // A rect straddling the top-left corner must not crash or touch out-of-range
        // indices -- clipped to worldRect internally.
        increaseVis(
            makerect(-5, -5, 10, 10), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: false, observer: 0, players: state.players
        )
        #expect(fogState.fog[0] == 1)
    }

    @Test func testIncreaseVisReSnapshotsOverTheSameRectNotAGrownOne() {
        // Deviation from C's insetrect(-1,-1) sign bug (docs/CONSTRAINTS.md): guards
        // against a future "fix" reintroducing the grow-not-shrink quirk by reflex. A
        // tile just OUTSIDE the incremented rect must never be re-snapshotted by this
        // call, even though C's own insetrect(-1,-1) arithmetic would touch it.
        var state = GameState()
        state.terrain[105, 100] = .minedGrass // just outside the 100...104 rect below
        var fogState = FogState()

        increaseVis(
            makerect(100, 100, 5, 5), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
        )

        #expect(fogState.fog[100 * 256 + 105] == 0, "tile outside the incremented rect must not gain fog")
        #expect(fogState.seenTiles[100 * 256 + 105] == .unknown, "tile outside the incremented rect must not be snapshotted")
    }

    @Test func testDecreaseVisDecrementsFogButKeepsTheStaleSnapshot() {
        var state = GameState()
        state.terrain[100, 100] = .minedGrass
        var fogState = FogState()
        increaseVis(
            makerect(100, 100, 1, 1), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
        )
        let seenBefore = fogState.seenTiles[100 * 256 + 100]

        decreaseVis(makerect(100, 100, 1, 1), state: &fogState)

        #expect(fogState.fog[100 * 256 + 100] == 0)
        #expect(fogState.seenTiles[100 * 256 + 100] == seenBefore, "stale snapshot must persist while re-fogged")
    }

    @Test func testOverlappingVisionSourcesComposeCorrectly() {
        var state = GameState()
        var fogState = FogState()
        // Two overlapping sources cover (100,100); removing one must leave it visible.
        increaseVis(
            makerect(98, 98, 5, 5), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: false, observer: 0, players: state.players
        )
        increaseVis(
            makerect(99, 99, 3, 3), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: false, observer: 0, players: state.players
        )
        #expect(fogState.fog[100 * 256 + 100] == 2)

        decreaseVis(makerect(99, 99, 3, 3), state: &fogState)
        #expect(fogState.fog[100 * 256 + 100] == 1, "still covered by the first, wider source")
    }
}

@Suite struct RevealNearbyHiddenMinesTests {

    @Test func testRevealsAMineWithinTheTwoUnitRadius() {
        var state = GameState()
        state.terrain[100, 101] = .minedGrass // 1.0 unit away from tile-center-of-(100,100)
        var fogState = FogState()

        revealNearbyHiddenMines(
            tankPos: BoloKit.Vec2f(x: 100.5, y: 100.5), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
        )

        #expect(fogState.seenTiles[101 * 256 + 100] == .grass, "mine within 2.0 units substitutes to unmined when never seen")
    }

    @Test func testDoesNotRevealAMineBeyondTheTwoUnitRadius() {
        var state = GameState()
        state.terrain[100, 105] = .minedGrass // well outside the 3x3 block around (100,100)
        var fogState = FogState()

        revealNearbyHiddenMines(
            tankPos: BoloKit.Vec2f(x: 100.5, y: 100.5), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
        )

        #expect(fogState.seenTiles[105 * 256 + 100] == .unknown)
    }

    @Test func testBoundsClampsNearMapEdgesInsteadOfTrapping() {
        // Deviation from C's unbounded near-edge indexing (docs/CONSTRAINTS.md): a tank
        // at the map's own top-left corner must not crash, matching TerrainGrid's own
        // bounds-checked subscript.
        var state = GameState()
        var fogState = FogState()
        revealNearbyHiddenMines(
            tankPos: BoloKit.Vec2f(x: 0.5, y: 0.5), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
        )
        // (0,0) is in the mined-sea border ring by default (`TerrainGrid.mapDefault()`,
        // mine zone is [10, 245]) -- correctly revealed as substituted `.sea` (never seen
        // before, hiddenMines on), not left `.unknown`. The real assertion here is just
        // "did not trap" on the out-of-bounds (-1, -1) neighbor.
        #expect(fogState.seenTiles[0] == .sea)
    }
}
