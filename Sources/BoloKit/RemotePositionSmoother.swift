//
//  RemotePositionSmoother.swift
//  BoloKit
//
//  B.9's smoothing half (D114) -- port-original UI polish with no reference-side counterpart
//  (`GSBoloView.m` never smooths anything; confirmed by grep, not assumed). Every render path
//  calls `GameRenderView.render(_:)` every game tick (50Hz), but a remote player's tank
//  position only changes when a UDP relay packet lands (~10Hz sender-side cadence, further
//  irregular on the wire) -- so the raw position is frozen for several render calls, then jumps.
//
//  A live lerp between "previous known sample" and "latest known sample" can't fix this: the
//  instant a new sample arrives, the interpolation fraction toward it is already 1.0, so it
//  still snaps. The fix is a fixed **render delay** -- draw each remote player
//  `smoothingDelayTicks` ticks in the past, so the *next* real sample has usually already
//  arrived by the time playback needs it as the interpolation's far endpoint, instead of
//  extrapolating into the unknown.
//
//  Pure view-layer concern -- one instance per remote player index, owned by `GameRenderView`,
//  never `GameState` itself. No effect on simulation, only on what's drawn.
//

/// Render delay, in ticks -- matches the known relay cadence exactly (`GameSession`'s
/// `localSeq % 5 == 0` / `HostGameEngine`'s identical gate), so one full relay interval of
/// buffer is available before a delayed render tick needs the next real sample.
public let smoothingDelayTicks: UInt64 = 5

/// Smooths one remote player's drawn tank position across the relay cadence above. See this
/// file's own header for why a live two-sample lerp alone isn't enough.
public struct RemotePositionSmoother: Sendable {
    private var previous: (position: Vec2f, tick: UInt64)?
    private var target: (position: Vec2f, tick: UInt64)?

    public init() {}

    /// Call every tick with the player's current raw position -- a no-op unless the value
    /// actually changed since the last call (i.e., a new relay sample actually landed).
    public mutating func update(rawPosition: Vec2f, tick: UInt64) {
        guard let target else {
            target = (rawPosition, tick)
            return
        }
        guard target.position != rawPosition else { return }
        previous = target
        self.target = (rawPosition, tick)
    }

    /// The delayed/interpolated draw position for `currentTick`. `nil` only before any sample
    /// has ever arrived.
    public func smoothedPosition(atTick currentTick: UInt64) -> Vec2f? {
        guard let target else { return nil }
        guard let previous else { return target.position }

        let displayTick = currentTick > smoothingDelayTicks ? currentTick - smoothingDelayTicks : 0
        if displayTick <= previous.tick { return previous.position }
        if displayTick >= target.tick { return target.position }

        let fraction = Float(displayTick - previous.tick) / Float(target.tick - previous.tick)
        return Vec2f(
            x: previous.position.x + (target.position.x - previous.position.x) * fraction,
            y: previous.position.y + (target.position.y - previous.position.y) * fraction
        )
    }
}
