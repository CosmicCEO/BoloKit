import Testing
import BoloKit
import CXBolo

// "Is this cell solid" rules, expressed on plain Int32 coordinates so the
// SAME logic can back both a Swift closure (BoloKit.Pointi) and a raw C
// function pointer (CXBolo.Pointi) without a cross-module type mismatch —
// the two imported Pointi types have identical layout but are distinct
// Swift types. Using one shared coordinate-level rule guarantees the
// "solid" decision is bit-identical on both sides, not a coincidentally
// matching reimplementation.

/// Deterministic pseudo-random solid pattern (~25% density) for fuzzing
/// collisionDetect across many cell configurations.
private func fixtureSolidAt(_ x: Int32, _ y: Int32) -> Bool {
    let h = (x &* 928371) &+ (y &* 12345)
    return (h & 3) == 0
}

/// Top-level, non-capturing C-callback adapter for `fixtureSolidAt`.
private func fixtureSolidPatternC(_ p: CXBolo.Pointi) -> Int32 {
    fixtureSolidAt(p.x, p.y) ? 1 : 0
}

/// Solid only at (5, 7) and (5, 9) — up/down neighbors of (5, y), with
/// left/right and all diagonals open. Used to isolate the `lyc && hyc`
/// bug branch in collisionDetect.
private func fixtureBugBranchSolidAt(_ x: Int32, _ y: Int32) -> Bool {
    x == 5 && (y == 7 || y == 9)
}

private func fixtureBugBranchSolidC(_ p: CXBolo.Pointi) -> Int32 {
    fixtureBugBranchSolidAt(p.x, p.y) ? 1 : 0
}

@Suite struct PhysicsOpsDifferentialTests {

    // MARK: - roundDir

    @Test func testRoundDirMatchesOracleFuzzed() {
        for _ in 0..<1000 {
            let dir = Float.random(in: 0...(2 * BoloKit.kPif))
            #expect(roundDir(dir) == CXBolo.rounddir_oracle(dir), "mismatch for dir=\(dir)")
        }
    }

    @Test func testRoundDirMatchesOracleAtBoundaries() {
        // The 16 exact quantization boundaries themselves
        for k in 0..<16 {
            let dir = Float(k) * (BoloKit.kPif / 8.0)
            #expect(roundDir(dir) == CXBolo.rounddir_oracle(dir), "mismatch at boundary k=\(k)")
        }
    }

    // MARK: - collisionDetect

    @Test func testCollisionDetectMatchesOracleFuzzed() {
        // Tolerance, not exact equality: the diagonal-corner branches
        // compute `fy + sca * ly` (sca itself from `radius / sqrtf(sqr)`).
        // Investigated a real, reproducible mismatch here (p=(7.276611,
        // 15.311005), radius=0.6) and confirmed via bit-pattern dump it was
        // exactly 1 ULP (0x41772c5b vs 0x41772c5c) — an FMA-contraction
        // difference between how clang and swiftc independently compile
        // the identical `a + b*c` expression, not a translation error (the
        // x value in that same case matched exactly). This is a known,
        // unavoidable cross-compiler floating-point non-portability class,
        // not something to chase to bit-identity. A real logic bug would
        // be off by orders of magnitude more than this tolerance.
        let tolerance: Float = 1e-4
        let radii: [Float] = [0.1, 0.2, 0.375, 0.5, 0.6]
        for _ in 0..<500 {
            let px = Float.random(in: 5...50)
            let py = Float.random(in: 5...50)
            let radius = radii.randomElement()!

            let swiftResult = BoloKit.collisionDetect(BoloKit.Vec2f(x: px, y: py), radius: radius) {
                fixtureSolidAt($0.x, $0.y)
            }
            let cResult = CXBolo.collisiondetect_oracle(
                CXBolo.Vec2f(x: px, y: py), radius, fixtureSolidPatternC
            )

            #expect(
                abs(swiftResult.x - cResult.x) <= tolerance,
                "x mismatch at p=(\(px),\(py)) radius=\(radius)"
            )
            #expect(
                abs(swiftResult.y - cResult.y) <= tolerance,
                "y mismatch at p=(\(px),\(py)) radius=\(radius)"
            )
        }
    }

    @Test func testCollisionDetectBugBranchMatchesOracle() {
        // Squeezed between solid cells above (5,7) and below (5,9) of
        // (5,8), with radius=0.6 (>0.5, required for lyc && hyc to both
        // fire) and an asymmetric fractional y-offset (0.45, not 0.5) so
        // the bug's effect is unambiguous rather than coinciding with the
        // "correct" value by symmetry. This branch is pure addition (no
        // sqrtf/multiply), so exact equality is safe here.
        let px: Float = 5.5
        let py: Float = 8.45
        let radius: Float = 0.6

        let swiftResult = BoloKit.collisionDetect(BoloKit.Vec2f(x: px, y: py), radius: radius) {
            fixtureBugBranchSolidAt($0.x, $0.y)
        }
        let cResult = CXBolo.collisiondetect_oracle(
            CXBolo.Vec2f(x: px, y: py), radius, fixtureBugBranchSolidC
        )

        #expect(swiftResult.x == cResult.x)
        #expect(swiftResult.y == cResult.y)
    }
}
