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

    // #153: `fogState: nil` (the join/solo paths, or the host with `hiddenMines` off) must
    // still apply forest concealment -- only the fog term drops out to "fully lit."

    @Test func testCalcVisWithNilFogStateStillAppliesForestConcealmentFarAway() {
        var state = GameState()
        state.players = [PlayerState()]
        state.players[0].tank = BoloKit.Vec2f(x: 10, y: 10) // far from the forest tile below
        for dy in -1...1 {
            for dx in -1...1 {
                state.terrain[200 + dx, 200 + dy] = .forest
            }
        }
        let v = BoloKit.Vec2f(x: 200.5, y: 200.5)
        let vis = calcVis(v, state: state, fogState: nil, observer: 0)
        #expect(vis == forestVis(v, state: state))
        #expect(vis < 1.0) // fully forest-surrounded -> concealed
    }

    @Test func testCalcVisWithNilFogStateStillFloorsVisibilityNearOwnTank() {
        var state = GameState()
        state.players = [PlayerState()]
        state.players[0].tank = BoloKit.Vec2f(x: 50, y: 50)
        for dy in -1...1 {
            for dx in -1...1 {
                state.terrain[50 + dx, 50 + dy] = .forest
            }
        }
        // Standing on your own tank: dist == 0 <= 2.0, so vis is at least 0.5 even fully
        // forest-concealed, same distance floor as the fogState-present case above.
        let vis = calcVis(BoloKit.Vec2f(x: 50, y: 50), state: state, fogState: nil, observer: 0)
        #expect(vis >= 0.5)
    }

    @Test func testCalcVisWithNilFogStateMatchesCalcVisBlendWithFogTermOne() {
        var state = GameState()
        state.players = [PlayerState()]
        state.players[0].tank = BoloKit.Vec2f(x: 10, y: 10)
        state.terrain[100, 100] = .forest
        let v = BoloKit.Vec2f(x: 100.5, y: 100.5)
        let vis = calcVis(v, state: state, fogState: nil, observer: 0)
        let expected = calcVisBlend(forestVis: forestVis(v, state: state), fogVis: 1.0, dist: mag2f(sub2f(state.players[0].tank, v)))
        #expect(vis == expected)
    }
}

@Suite struct FogTileForDifferentialTests {

    // `.minedSea` deliberately excluded -- C's real `fogtilefor` never hides mined sea at all
    // (unconditional `return kMinedSeaTile`, no `hiddenmines` check), unlike every other mined
    // terrain case. Covered by its own dedicated test below, not this shared table.
    private static let minedCases: [(Terrain, Tile)] = [
        (.minedSwamp, .swamp), (.minedCrater, .crater),
        (.minedRoad, .road), (.minedForest, .forest), (.minedRubble, .rubble), (.minedGrass, .grass),
    ]

    @Test func testFogTileForNeverHidesMinedSeaRegardlessOfHiddenMinesOrPreviousSeen() {
        var state = GameState()
        state.terrain[100, 100] = .minedSea
        for hiddenMines in [true, false] {
            for previousSeen: Tile in [.unknown, .sea, .minedSea] {
                let result = fogTileFor(
                    x: 100, y: 100, previousSeen: previousSeen, terrain: state.terrain,
                    pills: [], bases: [], hiddenMines: hiddenMines, observer: 0, players: state.players
                )
                #expect(result == .minedSea, "mined sea must never be hidden (hiddenMines=\(hiddenMines), previousSeen=\(previousSeen))")
            }
        }
    }

    @Test func testFogTileForCrossRevealsMinedForestAndMinedGrass() {
        var state = GameState()
        for (mined, otherPreviouslySeen) in [(Terrain.minedForest, Tile.minedGrass), (Terrain.minedGrass, Tile.minedForest)] {
            state.terrain[100, 100] = mined
            let result = fogTileFor(
                x: 100, y: 100, previousSeen: otherPreviouslySeen, terrain: state.terrain,
                pills: [], bases: [], hiddenMines: true, observer: 0, players: state.players
            )
            #expect(result == terrainToTile(mined), "\(mined) must stay revealed when previously seen as the other mined-tree variant")
        }
    }

    // v1.5.0 #1 (fix pass, `/code-review max` on PR #56): the original version of this test
    // recomputed `hiddenMines && !tileMatchesPrevious` in Swift and compared it to a C oracle
    // computing the identical expression -- a tautology that could never fail regardless of
    // what `fogTileFor`/`applyMineSubstitution` actually did, and did in fact ship two real
    // parity bugs undetected (`.minedSea` wrongly hideable; the minedForest/minedGrass
    // cross-check missing). This version calls the real `fogTileFor` directly and compares
    // against `fogtilefor_mined_result_oracle`, a verbatim transcription of the real C switch
    // (`Sources/CXBolo/fog.c`'s own comment), across every mined terrain type, both
    // `hiddenMines` values, and a spread of `previousSeen` values including the
    // forest/grass cross-case.
    @Test func testFogTileForMinedResultMatchesOracleFuzzed() {
        let minedCases: [(Terrain, Tile)] = [
            (.minedSea, .minedSea), (.minedSwamp, .swamp), (.minedCrater, .crater),
            (.minedRoad, .road), (.minedForest, .forest), (.minedRubble, .rubble), (.minedGrass, .grass),
        ]
        let previousTileOptions: [Tile] = [.unknown, .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass]
        var state = GameState()
        for (mined, _) in minedCases {
            state.terrain[100, 100] = mined
            for hiddenMines in [true, false] {
                for previousTile in previousTileOptions {
                    let swiftResult = fogTileFor(
                        x: 100, y: 100, previousSeen: previousTile, terrain: state.terrain,
                        pills: [], bases: [], hiddenMines: hiddenMines, observer: 0, players: state.players
                    )
                    let cResult = CXBolo.fogtilefor_mined_result_oracle(
                        mined.rawValue, hiddenMines ? 1 : 0, previousTile.rawValue
                    )
                    #expect(
                        Int32(swiftResult.rawValue) == cResult,
                        "\(mined) hiddenMines=\(hiddenMines) previousTile=\(previousTile): swift=\(swiftResult) oracle=\(cResult)"
                    )
                }
            }
        }
    }

    /// Verbatim companion to the above: `testhiddenmine()`'s real terrain-type switch has no
    /// `kMinedSeaTerrain` case (`revealNearbyHiddenMines`'s own Fix-7 change, this same PR).
    @Test func testRevealNearbyHiddenMinesTerrainListMatchesOracle() {
        let allMinedTerrains: [Terrain] = [
            .minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass,
        ]
        for terrain in allMinedTerrains {
            var state = GameState()
            state.terrain[100, 100] = terrain
            var fogState = FogState()
            revealNearbyHiddenMines(
                tankPos: BoloKit.Vec2f(x: 100.5, y: 100.5), state: &fogState, terrain: state.terrain,
                pills: [], bases: [], observer: 0, players: state.players
            )
            let swiftRevealed = fogState.seenTiles[100 * 256 + 100] != .unknown
            let oracleRevealed = CXBolo.testhiddenmine_reveals_terrain_oracle(terrain.rawValue) != 0
            #expect(swiftRevealed == oracleRevealed, "\(terrain): swift revealed=\(swiftRevealed) oracle says=\(oracleRevealed)")
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

@Suite struct FogResolvedTileGridTests {

    @Test func testNeverSeenTileRendersUnknown() {
        var state = GameState()
        state.hiddenMines = true
        state.terrain[200, 200] = .grass0
        let fogState = FogState() // nothing visible or ever seen anywhere

        let grid = fogResolvedTileGrid(for: state, fogState: fogState)
        #expect(Tile(rawValue: grid.storage[200 * 256 + 200]) == .unknown)
    }

    @Test func testCurrentlyVisibleMineIsResolvedLiveNotFromAPossiblyStaleSnapshot() {
        var state = GameState()
        state.hiddenMines = true
        state.terrain[100, 100] = .minedGrass
        var fogState = FogState()
        fogState.fog[100 * 256 + 100] = 1
        // Stale/never-updated snapshot -- a real "currently visible" tile would normally
        // have this populated by increaseVis, but this test deliberately leaves it at the
        // default `.unknown` to prove the live branch doesn't depend on it being fresh.
        fogState.seenTiles[100 * 256 + 100] = .unknown

        let grid = fogResolvedTileGrid(for: state, fogState: fogState)
        // Never seen before (previousSeen == .unknown, not .minedGrass) -- hidden, matches
        // fogTileFor's own sticky-reveal rule, computed live off current ground truth.
        #expect(Tile(rawValue: grid.storage[100 * 256 + 100]) == .grass)
    }

    @Test func testFoggedButPreviouslySeenTileUsesTheFrozenSnapshot() {
        var state = GameState()
        state.hiddenMines = true
        state.terrain[100, 100] = .minedGrass // ground truth changed after this tile was last seen
        var fogState = FogState()
        fogState.fog[100 * 256 + 100] = 0 // currently fogged
        fogState.seenTiles[100 * 256 + 100] = .grass // what was actually observed while last visible

        let grid = fogResolvedTileGrid(for: state, fogState: fogState)
        #expect(Tile(rawValue: grid.storage[100 * 256 + 100]) == .grass, "must show the frozen snapshot, not re-derive from current ground truth")
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

// MARK: - #159: client-side FogVisionTracker

// Direct unit tests for `updateFogVisionTracker`, the join/solo-path equivalent of
// `HostGameEngine.updateFogVision`'s per-observer body (extracted to `BoloKit` so a
// non-host party can compute its own fog locally -- see `FogVisionTracker`'s own header).
// Exercises the same generic-transition diff (newly contributing / moved / stopped) that
// `HostGameEngineFogVisionTests` (`HostGameEngineTests.swift`) already covers end-to-end
// against a live ticking engine; these are synchronous, single-call unit tests of the
// extracted function itself.

@Suite struct FogVisionTrackerTests {

    @Test func testHiddenMinesOffIsANoOp() {
        var state = GameState()
        state.hiddenMines = false
        state.players = [PlayerState()]
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].alliance = 1 << 0
        state.players[0].tank = BoloKit.Vec2f(x: 105, y: 105)
        var tracker = FogVisionTracker()

        updateFogVisionTracker(&tracker, observer: 0, state: state)

        #expect(tracker.fogState.fog[105 * 256 + 105] == 0)
    }

    @Test func testBootstrapRevealsOwnTankImmediately() {
        var state = GameState()
        state.hiddenMines = true
        state.players = [PlayerState()]
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].alliance = 1 << 0 // self-allied, matching HostGameEngine's own test setup
        state.players[0].tank = BoloKit.Vec2f(x: 105, y: 105)
        var tracker = FogVisionTracker()

        updateFogVisionTracker(&tracker, observer: 0, state: state)

        #expect(tracker.fogState.fog[105 * 256 + 105] > 0)
        #expect(tracker.fogState.seenTiles[200 * 256 + 200] == .unknown, "far tile, never covered by any vision source, stays unknown")
    }

    @Test func testAllianceRevealsTheAllysPosition() {
        var state = GameState()
        state.hiddenMines = true
        state.players = [PlayerState(), PlayerState()]
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].alliance = (1 << 0) | (1 << 1)
        state.players[0].tank = BoloKit.Vec2f(x: 105, y: 105)

        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].alliance = (1 << 1) | (1 << 0)
        state.players[1].tank = BoloKit.Vec2f(x: 150, y: 150) // outside player 0's own vision

        var tracker = FogVisionTracker()
        updateFogVisionTracker(&tracker, observer: 0, state: state)

        #expect(tracker.fogState.fog[150 * 256 + 150] > 0, "an ally's position is its own vision source")
    }

    @Test func testUnalliedRemotePlayerIsNotRevealed() {
        var state = GameState()
        state.hiddenMines = true
        state.players = [PlayerState(), PlayerState()]
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].alliance = 1 << 0
        state.players[0].tank = BoloKit.Vec2f(x: 105, y: 105)

        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].alliance = 1 << 1 // not allied with player 0
        state.players[1].tank = BoloKit.Vec2f(x: 150, y: 150)

        var tracker = FogVisionTracker()
        updateFogVisionTracker(&tracker, observer: 0, state: state)

        #expect(tracker.fogState.fog[150 * 256 + 150] == 0, "an unallied remote tank must not be a vision source -- this is #159's actual bug")
        #expect(tracker.fogState.seenTiles[150 * 256 + 150] == .unknown)
    }

    @Test func testMovementDiffsTheVisionSourceRectInsteadOfDoubleCounting() {
        var state = GameState()
        state.hiddenMines = true
        state.players = [PlayerState()]
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].alliance = 1 << 0
        state.players[0].tank = BoloKit.Vec2f(x: 105, y: 105)
        var tracker = FogVisionTracker()

        updateFogVisionTracker(&tracker, observer: 0, state: state)
        #expect(tracker.fogState.fog[105 * 256 + 105] == 1)

        state.players[0].tank = BoloKit.Vec2f(x: 200, y: 200) // outside the old 29x29 vision rect
        updateFogVisionTracker(&tracker, observer: 0, state: state)

        #expect(tracker.fogState.fog[200 * 256 + 200] == 1, "new position becomes visible")
        #expect(tracker.fogState.fog[105 * 256 + 105] == 0, "old position's vision source is removed, not left double-counted")
        #expect(tracker.fogState.seenTiles[105 * 256 + 105] == .sea, "the stale snapshot persists while re-fogged")
    }

    @Test func testDisconnectDecrementsTheVisionThatMoverWasContributing() {
        var state = GameState()
        state.hiddenMines = true
        state.players = [PlayerState(), PlayerState()]
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].alliance = (1 << 0) | (1 << 1)
        state.players[0].tank = BoloKit.Vec2f(x: 105, y: 105)

        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].alliance = (1 << 1) | (1 << 0)
        state.players[1].tank = BoloKit.Vec2f(x: 150, y: 150)

        var tracker = FogVisionTracker()
        updateFogVisionTracker(&tracker, observer: 0, state: state)
        #expect(tracker.fogState.fog[150 * 256 + 150] > 0)

        state.players[1].connected = false
        updateFogVisionTracker(&tracker, observer: 0, state: state)

        #expect(tracker.fogState.fog[150 * 256 + 150] == 0, "a disconnected mover's vision source must be removed")
    }

    @Test func testOverlappingVisionSourcesComposeCorrectlyAcrossMovers() {
        // Two allied tanks both covering the same tile; one moving away must leave it
        // visible via the other's still-active vision source -- same refcount-composition
        // guarantee `IncreaseDecreaseVisTests.testOverlappingVisionSourcesComposeCorrectly`
        // already proves for `increaseVis`/`decreaseVis` directly, exercised here through
        // the tracker's own diff loop across two movers instead of two raw rect calls.
        var state = GameState()
        state.hiddenMines = true
        state.players = [PlayerState(), PlayerState()]
        state.players[0].used = true
        state.players[0].connected = true
        state.players[0].alliance = (1 << 0) | (1 << 1)
        state.players[0].tank = BoloKit.Vec2f(x: 100, y: 100)

        state.players[1].used = true
        state.players[1].connected = true
        state.players[1].alliance = (1 << 1) | (1 << 0)
        state.players[1].tank = BoloKit.Vec2f(x: 101, y: 101) // overlapping 29x29 vision rect

        var tracker = FogVisionTracker()
        updateFogVisionTracker(&tracker, observer: 0, state: state)
        #expect(tracker.fogState.fog[100 * 256 + 100] == 2, "both tanks' vision rects cover this tile")

        state.players[1].tank = BoloKit.Vec2f(x: 200, y: 200) // moves far away
        updateFogVisionTracker(&tracker, observer: 0, state: state)

        #expect(tracker.fogState.fog[100 * 256 + 100] == 1, "still covered by player 0's own tank")
    }
}

@Suite struct RevealNearbyHiddenMinesTests {

    @Test func testRevealsAMineWithinTheTwoUnitRadius() {
        var state = GameState()
        state.terrain[100, 101] = .minedGrass // 1.0 unit away from tile-center-of-(100,100)
        var fogState = FogState()

        revealNearbyHiddenMines(
            tankPos: BoloKit.Vec2f(x: 100.5, y: 100.5), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], observer: 0, players: state.players
        )

        // Discovered-defect fix: C's `testhiddenmine` calls `refresh(x, y)`, which stores
        // `tilefor(x, y)` (ground truth) unconditionally -- a proximity reveal shows the
        // *real* mined tile, not a substituted unmined one, even the first time it's seen.
        #expect(fogState.seenTiles[101 * 256 + 100] == .minedGrass, "mine within 2.0 units reveals its true mined tile")
    }

    @Test func testDoesNotRevealAMineBeyondTheTwoUnitRadius() {
        var state = GameState()
        state.terrain[100, 105] = .minedGrass // well outside the 3x3 block around (100,100)
        var fogState = FogState()

        revealNearbyHiddenMines(
            tankPos: BoloKit.Vec2f(x: 100.5, y: 100.5), state: &fogState, terrain: state.terrain,
            pills: [], bases: [], observer: 0, players: state.players
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
            pills: [], bases: [], observer: 0, players: state.players
        )
        // (0,0) is in the mined-sea border ring by default (`TerrainGrid.mapDefault()`,
        // mine zone is [10, 245]) -- `revealNearbyHiddenMines` no longer force-reveals mined
        // sea at all (matches C's real `testhiddenmine`, which has no `kMinedSeaTerrain`
        // case), so this stays `.unknown` here (nothing else in this isolated unit test
        // calls `increaseVis` to reveal it some other way). The real assertion is just "did
        // not trap" on the out-of-bounds (-1, -1) neighbor.
        #expect(fogState.seenTiles[0] == .unknown)
    }
}
