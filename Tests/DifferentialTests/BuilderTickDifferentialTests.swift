import Testing
import BoloKit
import CXBolo

// Fuzzes the pure numeric transforms behind builderTick's ready/goto/
// return/parachute cases against the C oracle in Sources/CXBolo/
// builderops.c. These mirror the plain-Float arithmetic used in
// BuilderTick.swift's private helpers (builderLaunchPosition, and the
// diff-scaling steps in gotoTick/returnTick/parachuteTick) — tested here
// via the same formula shape rather than through the private functions
// directly, to empirically confirm (not assume) whether the
// Double-promotion treatment already required elsewhere (kickspeed decay,
// shellVelocity/ticksPerSec) is also needed here.

@Suite struct BuilderTickDifferentialTests {

    @Test func testBuilderLaunchPositionMatchesOracleFuzzed() {
        for _ in 0..<2000 {
            let target = BoloKit.Vec2f(x: Float.random(in: 10...245), y: Float.random(in: 10...245))
            let tank = target + Vec2f(x: Float.random(in: -3...3), y: Float.random(in: -3...3))

            let diff = target - tank
            let mag = mag2f(diff)
            let swiftResult: BoloKit.Vec2f = mag <= (tankRadius - builderRadius)
                ? target
                : tank + diff * ((tankRadius - builderRadius) / mag)

            let cResult = CXBolo.builderlaunch_oracle(
                CXBolo.Vec2f(x: target.x, y: target.y), CXBolo.Vec2f(x: tank.x, y: tank.y)
            )

            #expect(swiftResult.x == cResult.x, "x mismatch target=\(target) tank=\(tank)")
            #expect(swiftResult.y == cResult.y, "y mismatch target=\(target) tank=\(tank)")
        }
    }

    @Test func testBuilderMoveStepMatchesOracleFuzzed() {
        for _ in 0..<2000 {
            let diff = BoloKit.Vec2f(x: Float.random(in: -5...5), y: Float.random(in: -5...5))
            guard mag2f(diff) > 0.0001 else { continue }
            let speed = Float.random(in: 0...4)

            let swiftResult = diff * (speed / (ticksPerSec * mag2f(diff)))

            let cResult = CXBolo.buildermove_oracle(CXBolo.Vec2f(x: diff.x, y: diff.y), speed)

            #expect(swiftResult.x == cResult.x, "x mismatch diff=\(diff) speed=\(speed)")
            #expect(swiftResult.y == cResult.y, "y mismatch diff=\(diff) speed=\(speed)")
        }
    }

    @Test func testParachuteMoveStepMatchesOracleFuzzed() {
        for _ in 0..<2000 {
            let diff = BoloKit.Vec2f(x: Float.random(in: -5...5), y: Float.random(in: -5...5))
            guard mag2f(diff) > 0.0001 else { continue }

            let swiftResult = diff * (parachuteSpeed / (ticksPerSec * mag2f(diff)))

            let cResult = CXBolo.parachutemove_oracle(CXBolo.Vec2f(x: diff.x, y: diff.y))

            #expect(swiftResult.x == cResult.x, "x mismatch diff=\(diff)")
            #expect(swiftResult.y == cResult.y, "y mismatch diff=\(diff)")
        }
    }
}
