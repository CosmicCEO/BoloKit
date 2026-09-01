import Testing
import BoloKit
import CXBolo

// Fuzzes the core numeric tank-physics transform (turning, direction wrap,
// acceleration, position update, kickspeed decay) against the C oracle
// extracted in Sources/CXBolo/tankops.c. Shore-push and collision are
// excluded from the oracle (they need pill/base/terrain lookups, not pure
// numeric math) and are covered by Swift-only unit tests instead.
//
// The Swift side under test here is tankMoveTick's alive-branch physics,
// exercised through a minimal single-player GameState so no shore-push
// (boat=false) or collision-clamping interferes with the pure numeric
// comparison — the oracle doesn't model those either.

@Suite struct TankTickDifferentialTests {

    private func makeState(
        dir: Float, speed: Float, turnSpeed: Float, kickDir: Float, kickSpeed: Float,
        boat: Bool, flags: InputFlags
    ) -> GameState {
        var state = GameState()
        var player = PlayerState()
        player.tank = Vec2f(x: 128, y: 128)
        player.dir = dir
        player.speed = speed
        player.turnSpeed = turnSpeed
        player.kickDir = kickDir
        player.kickSpeed = kickSpeed
        player.boat = boat
        player.dead = false
        player.connected = true
        player.inputFlags = flags
        state.players = [player]
        state.localPlayer = 0
        return state
    }

    @Test func testTankPhysicsMatchesOracleFuzzed() {
        let flagCombos: [InputFlags] = [
            [], [.turnL], [.turnR], [.turnL, .turnR],
            [.accel], [.brake], [.accel, .brake],
            [.turnL, .accel], [.turnR, .brake],
        ]

        for _ in 0..<1000 {
            let dir = Float.random(in: -10...10)
            let speed = Float.random(in: -1...4)
            let turnSpeed = Float.random(in: -5...5)
            let kickDir = Float.random(in: -10...10)
            let kickSpeed = Float.random(in: 0...5)
            let boat = Bool.random()
            let flags = flagCombos.randomElement()!
            var state = makeState(
                dir: dir, speed: speed, turnSpeed: turnSpeed,
                kickDir: kickDir, kickSpeed: kickSpeed, boat: boat, flags: flags
            )
            if !boat {
                // isShore treats grass (and every non-water terrain) as
                // "shore" — only relevant to the boat-only shore-push
                // block, so land terrain here is safe: it only feeds
                // maxSpeed/maxTurnSpeed's lookup, giving accel/turning
                // somewhere to go, and boat=false never runs shore-push.
                state.terrain[128, 128] = .grass3
            }
            // boat=true: leave the grid fully default (sea in the
            // interior) so every neighbor of (128,128) is water — isShore
            // is false everywhere near the tank, push stays (0,0), and
            // this matches the reduced oracle, which doesn't model shore
            // push at all. Any non-water cell here — even one the tank
            // only drifts adjacent to mid-tick — would trigger a push the
            // oracle has no way to reproduce.

            tankMoveTick(player: 0, state: &state)
            let swiftResult = state.players[0]

            let cInput = CXBolo.TankPhysicsState(
                tank: CXBolo.Vec2f(x: 128, y: 128),
                dir: dir, speed: speed, turnspeed: turnSpeed,
                kickdir: kickDir, kickspeed: kickSpeed
            )
            let cResult = CXBolo.tankphysics_oracle(
                cInput,
                flags.contains(.turnL) ? 1 : 0,
                flags.contains(.turnR) ? 1 : 0,
                flags.contains(.accel) ? 1 : 0,
                flags.contains(.brake) ? 1 : 0,
                boat ? 1 : 0,
                terrainMaxTurnSpeed(.grass3),
                terrainMaxSpeed(.grass3)
            )

            #expect(swiftResult.dir == cResult.dir, "dir mismatch boat=\(boat) flags=\(flags)")
            #expect(swiftResult.speed == cResult.speed, "speed mismatch boat=\(boat) flags=\(flags)")
            #expect(swiftResult.turnSpeed == cResult.turnspeed, "turnSpeed mismatch boat=\(boat) flags=\(flags)")
            #expect(swiftResult.kickSpeed == cResult.kickspeed, "kickSpeed mismatch boat=\(boat) flags=\(flags)")
            #expect(swiftResult.tank.x == cResult.tank.x, "tank.x mismatch boat=\(boat) flags=\(flags)")
            #expect(swiftResult.tank.y == cResult.tank.y, "tank.y mismatch boat=\(boat) flags=\(flags)")
        }
    }
}
