import Testing
import BoloKit
import CXBolo

// Fuzzes forestvis()'s interpolation arithmetic and pilllogic()'s
// shell-firing lead-targeting math against the C oracle extracted in
// Sources/CXBolo/pillops.c. isForest's terrain/pill/base lookups are
// exercised via Swift-only unit tests in PillTickTests.swift instead.

@Suite struct PillTickDifferentialTests {

    @Test func testForestVisMatchesOracleFuzzed() {
        var state = GameState()
        for _ in 0..<3000 {
            let fx = Float.random(in: 0..<1)
            let fy = Float.random(in: 0..<1)
            let isCenter = Bool.random()
            let neighbors = (0..<8).map { _ in Bool.random() }

            state.terrain[50, 50] = isCenter ? .forest : .grass0
            let deltas: [(Int, Int)] = [(-1, 0), (1, 0), (0, -1), (0, 1), (-1, -1), (-1, 1), (1, -1), (1, 1)]
            for (n, (dx, dy)) in zip(neighbors, deltas) {
                state.terrain[50 + dx, 50 + dy] = n ? .forest : .grass0
            }

            let v = BoloKit.Vec2f(x: 50 + fx, y: 50 + fy)
            let swiftResult = forestVis(v, state: state)

            // Re-derive fx/fy exactly as forestVis itself does internally
            // (v.x - floorf(v.x)) rather than reusing the pre-embedding
            // random values — adding/subtracting 50 loses precision on
            // the round trip, so the two can differ in the low bits even
            // though they're "the same" fraction conceptually.
            let derivedFx = v.x - floorf(v.x)
            let derivedFy = v.y - floorf(v.y)

            let cResult = CXBolo.forestvis_oracle(
                derivedFx, derivedFy,
                isCenter ? 1 : 0,
                neighbors[0] ? 1 : 0, neighbors[1] ? 1 : 0, neighbors[2] ? 1 : 0, neighbors[3] ? 1 : 0,
                neighbors[4] ? 1 : 0, neighbors[5] ? 1 : 0, neighbors[6] ? 1 : 0, neighbors[7] ? 1 : 0
            )

            #expect(swiftResult == cResult, "mismatch fx=\(fx) fy=\(fy) center=\(isCenter) neighbors=\(neighbors)")
        }
    }

    @Test func testPillShellLeadTargetingMatchesOracleFuzzed() {
        for _ in 0..<2000 {
            let pill = BoloKit.Vec2f(x: Float.random(in: 10...245), y: Float.random(in: 10...245))
            let tank = pill + Vec2f(x: Float.random(in: -8...8), y: Float.random(in: -8...8))
            let old = tank - Vec2f(x: Float.random(in: -0.2...0.2), y: Float.random(in: -0.2...0.2))

            let diff = tank - pill
            let mag = mag2f(diff)
            guard mag > 0.5 else { continue }  // avoid the singular mag==0 case

            let vel = (tank - old) * ticksPerSec
            let compi = vel - prj2f(diff, vel)
            let raw = Float(Double(shellVelocity) * Double(shellVelocity) - Double(dot2f(compi, compi)))
            let compj = unit2f(diff) * sqrtf(fabsf(raw))

            let swiftPoint = pill + diff * Float(0.70711219 / Double(mag))
            let swiftDir = vec2dir(compi + compj)

            let cResult = CXBolo.pillshell_oracle(
                CXBolo.Vec2f(x: tank.x, y: tank.y), CXBolo.Vec2f(x: old.x, y: old.y), CXBolo.Vec2f(x: pill.x, y: pill.y)
            )

            #expect(swiftPoint.x == cResult.point.x, "point.x mismatch tank=\(tank) old=\(old) pill=\(pill)")
            #expect(swiftPoint.y == cResult.point.y, "point.y mismatch tank=\(tank) old=\(old) pill=\(pill)")
            #expect(swiftDir == cResult.dir, "dir mismatch tank=\(tank) old=\(old) pill=\(pill)")
        }
    }
}
