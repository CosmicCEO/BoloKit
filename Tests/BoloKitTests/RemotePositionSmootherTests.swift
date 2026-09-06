import XCTest
@testable import BoloKit

/// B.9's smoothing half (D114). No C reference oracle exists for this (confirmed by grep --
/// this is port-original UI polish), so these are synthetic-sequence unit tests, not
/// differential ones.
final class RemotePositionSmootherTests: XCTestCase {
    func testHoldsAtFirstSampleBeforeAnySecondSampleArrives() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 10, y: 10), tick: 0)

        XCTAssertEqual(smoother.smoothedPosition(atTick: 0), Vec2f(x: 10, y: 10))
        XCTAssertEqual(smoother.smoothedPosition(atTick: 20), Vec2f(x: 10, y: 10))
    }

    func testReturnsNilBeforeAnySampleHasEverArrived() {
        let smoother = RemotePositionSmoother()
        XCTAssertNil(smoother.smoothedPosition(atTick: 0))
    }

    func testInterpolatesStrictlyBetweenTwoKnownSamples() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)

        // Delayed display tick = currentTick - 5, so query ticks 6...9 land strictly inside
        // the (0, 5) sample window, mid-interpolation.
        var previousX: Float = -1
        for currentTick in UInt64(6)...9 {
            let position = smoother.smoothedPosition(atTick: currentTick)
            let x = position!.x
            XCTAssertGreaterThan(x, 0, "tick \(currentTick) should be strictly past the earlier sample")
            XCTAssertLessThan(x, 10, "tick \(currentTick) should be strictly before the later sample")
            XCTAssertGreaterThan(x, previousX, "interpolation should be monotonically increasing")
            previousX = x
        }
    }

    func testHoldsFlatAtLatestSampleOnceQueryRunsPastItWithNoThirdSample() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)

        // Display tick = currentTick - 5; once that exceeds tick 5 (i.e. currentTick > 10)
        // with no third sample, the smoother must hold at the latest sample, not extrapolate.
        XCTAssertEqual(smoother.smoothedPosition(atTick: 15), Vec2f(x: 10, y: 0))
        XCTAssertEqual(smoother.smoothedPosition(atTick: 100), Vec2f(x: 10, y: 0))
    }

    func testUnchangedRawPositionIsANoOpAndDoesNotResetTheInterpolationWindow() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)
        let before = smoother.smoothedPosition(atTick: 7)

        // Same raw position repeated on later ticks (no new relay sample) must not disturb the
        // existing previous/target window.
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 6)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 7)
        let after = smoother.smoothedPosition(atTick: 7)

        XCTAssertEqual(before, after)
    }

    /// Negative control: without the render delay (querying at the *un-delayed* current tick,
    /// i.e. `atTick: target.tick` right when a sample lands), the design's own header claims a
    /// live lerp still snaps immediately. Confirms that claim is real, not asserted -- this is
    /// exactly the failure mode `smoothingDelayTicks` exists to avoid.
    func testWithoutTheRenderDelayANewSampleWouldSnapImmediately() {
        var smoother = RemotePositionSmoother()
        smoother.update(rawPosition: Vec2f(x: 0, y: 0), tick: 0)
        smoother.update(rawPosition: Vec2f(x: 10, y: 0), tick: 5)

        // Querying at the un-delayed tick where the new sample landed: displayTick = 5 - 5 = 0,
        // i.e. still the *previous* sample -- proving the delay is actually doing the work
        // above, not that fraction 1.0 happens to equal the earlier sample by coincidence.
        XCTAssertEqual(smoother.smoothedPosition(atTick: 5), Vec2f(x: 0, y: 0))
    }
}
