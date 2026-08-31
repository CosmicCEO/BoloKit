import Darwin

// MARK: - Physics Constants
//
// Ported verbatim from Reference/c/bolo.h.
//
// D18: All physics values are Float (32-bit), matching the C reference code's
// use of float for Vec2f, tank position, trig, and physics calculations.
// Using Double here would create a type mismatch at every Wave 5 call site.

/// Simulation ticks per second. The fundamental time step of the engine.
public let ticksPerSec: Float = 50

/// Maximum tank speed on road or boat terrain (squares per second).
public let boatMaxSpeed: Float = 3.125

/// Maximum tank speed on road terrain (= boatMaxSpeed).
public let roadMaxSpeed: Float = boatMaxSpeed

/// Maximum tank speed on grass terrain (squares per second).
/// Ratio to road: 75%
public let grassMaxSpeed: Float = 2.34375

/// Maximum tank speed on forest terrain (squares per second).
/// Ratio to road: 37.5%
public let forestMaxSpeed: Float = 1.171875

/// Maximum tank speed on rubble/swamp/crater/river terrain (squares per second).
/// Ratio to road: ~18.75%
public let rubbleMaxSpeed: Float = 0.5859375

/// Number of ticks required for a tank at boatMaxSpeed to decelerate to zero.
public let ticksForCompleteStop: Float = 64

/// Tank linear acceleration (squares per second²).
/// = boatMaxSpeed × ticksPerSec / ticksForCompleteStop = 2.44140625
public let accel: Float = boatMaxSpeed * ticksPerSec / ticksForCompleteStop

/// Tank angular acceleration (radians per second²).
/// C value: 12.5663706143592 (≈ 4π). Stored as Float per D18.
public let angularAccel: Float = 12.5663706143592

/// Maximum LGM (builder) movement speed. Equal to roadMaxSpeed.
public let builderMaxSpeed: Float = roadMaxSpeed

/// Parachute descent speed. Equal to rubbleMaxSpeed.
public let parachuteSpeed: Float = rubbleMaxSpeed
