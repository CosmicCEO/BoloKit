import Testing
@testable import BoloKit

/// B.9's smoothing half (D114). No C reference oracle exists for this (confirmed by grep --
/// this is port-original UI polish), so these are synthetic-sequence unit tests, not
/// differential ones.
struct RemotePositionSmootherTests {
    @Test func `Holds at first sample before any second sample arrives`() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 10, y: 10), tick: 0)

        #expect(smoother.smoothedPosition(atTick: 0) == Vec2f(x: 10, y: 10))
        #expect(smoother.smoothedPosition(atTick: 20) == Vec2f(x: 10, y: 10))
    }

    @Test func `Returns nil before any sample has ever arrived`() {
        let smoother = RemotePositionSmoother()
        #expect(smoother.smoothedPosition(atTick: 0) == nil)
    }

    @Test func `Interpolates strictly between two known samples`() throws {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)

        // Delayed display tick = currentTick - 5, so query ticks 6...9 land strictly inside
        // the (0, 5) sample window, mid-interpolation.
        var previousX: Float = -1
        for currentTick in UInt64(6)...9 {
            let x = try #require(smoother.smoothedPosition(atTick: currentTick)).x
            #expect(x > 0, "tick \(currentTick) should be strictly past the earlier sample")
            #expect(x < 10, "tick \(currentTick) should be strictly before the later sample")
            #expect(x > previousX, "interpolation should be monotonically increasing")
            previousX = x
        }
    }

    @Test func `Holds flat at latest sample once query runs past it with no third sample`() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)

        // Display tick = currentTick - 5; once that exceeds tick 5 (i.e. currentTick > 10)
        // with no third sample, the smoother must hold at the latest sample, not extrapolate.
        #expect(smoother.smoothedPosition(atTick: 15) == Vec2f(x: 10, y: 0))
        #expect(smoother.smoothedPosition(atTick: 100) == Vec2f(x: 10, y: 0))
    }

    @Test func `Unchanged raw position is a no-op and does not reset the interpolation window`() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)
        let before = smoother.smoothedPosition(atTick: 7)

        // Same raw position repeated on later ticks (no new relay sample) must not disturb the
        // existing previous/target window.
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 6)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 7)
        let after = smoother.smoothedPosition(atTick: 7)

        #expect(before == after)
    }

    /// Negative control: without the render delay (querying at the *un-delayed* current tick,
    /// i.e. `atTick: target.tick` right when a sample lands), the design's own header claims a
    /// live lerp still snaps immediately. Confirms that claim is real, not asserted -- this is
    /// exactly the failure mode `smoothingDelayTicks` exists to avoid.
    @Test func `Without the render delay a new sample would snap immediately`() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)

        // Querying at the un-delayed tick where the new sample landed: displayTick = 5 - 5 = 0,
        // i.e. still the *previous* sample -- proving the delay is actually doing the work
        // above, not that fraction 1.0 happens to equal the earlier sample by coincidence.
        #expect(smoother.smoothedPosition(atTick: 5) == Vec2f(x: 0, y: 0))
    }

    // MARK: - #61: a join client's `state.ticks` never advances, so every sample carries the same tick

    /// The guest never advances `state.ticks`, so every sample is stamped with the same tick. A
    /// tank that teleports (host respawn) and then stands still must be drawn at the new spot, not
    /// at the previous sample (the death spot), which is what a stuck clock used to leave behind.
    @Test func `A teleport under a frozen clock is drawn at the new position`() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 10, y: 10), tick: 500)
        smoother.update(rawPosition: Vec2f(x: 3, y: 4), tick: 500)

        #expect(smoother.smoothedPosition(atTick: 500) == Vec2f(x: 3, y: 4))
    }

    @Test func `Every sample under a frozen clock is drawn as the latest one`() {
        var smoother = RemotePositionSmoother()
        for x in 1...5 {
            smoother.update(rawPosition: Vec2f(x: Float(x), y: 0), tick: 500)
            #expect(smoother.smoothedPosition(atTick: 500) == Vec2f(x: Float(x), y: 0))
        }
    }
}
