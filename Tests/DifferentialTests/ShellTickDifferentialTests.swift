import Testing
import BoloKit
import CXBolo

// Fuzzes the shell move/range-advance numeric transform against the C
// oracle extracted in Sources/CXBolo/shellops.c. Collision resolution needs
// pill/base/terrain lookups (not pure numeric math) and is covered by
// Swift-only unit tests in ShellTickTests.swift instead.

@Suite struct ShellTickDifferentialTests {

    @Test func testShellAdvanceMatchesOracleFuzzed() {
        for _ in 0..<1000 {
            let dir = Float.random(in: -10...10)
            // Exercise both the partial-final-step branch (range below one
            // tick's travel, ~0.14) and the steady-state branch.
            let range = Float.random(in: 0...1)
            let point = BoloKit.Vec2f(x: Float.random(in: 10...245), y: Float.random(in: 10...245))

            var shell = Shell(point: point, dir: dir, range: range, owner: 0, boat: false, pill: false)
            shellAdvance(&shell)

            let cResult = CXBolo.shelladvance_oracle(
                CXBolo.Vec2f(x: point.x, y: point.y), dir, range
            )

            #expect(shell.point.x == cResult.point.x, "point.x mismatch dir=\(dir) range=\(range)")
            #expect(shell.point.y == cResult.point.y, "point.y mismatch dir=\(dir) range=\(range)")
            #expect(shell.range == cResult.range, "range mismatch dir=\(dir) range=\(range)")
        }
    }
}
