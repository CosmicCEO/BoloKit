import Testing
import BoloKit

// Wave 3.1 unit tests — pure value checks against Reference/c/bolo.h constants
// and the client.c maxspeed/maxturnspeed/builderspeed terrain tiers.
// No C oracle: these mappings are embedded in grid+state functions in C, so
// the expected values are pinned here as independent tables.

// MARK: - Physics constants

@Test func physicsConstantsMatchBoloH() {
    #expect(ticksPerSec == 50)
    #expect(boatMaxSpeed == 3.125)
    #expect(roadMaxSpeed == 3.125)
    #expect(grassMaxSpeed == 2.34375)
    #expect(forestMaxSpeed == 1.171875)
    #expect(rubbleMaxSpeed == 0.5859375)
    #expect(ticksForCompleteStop == 64)
    #expect(angularAccel == Float(12.5663706143592))
    #expect(builderMaxSpeed == roadMaxSpeed)
    #expect(parachuteSpeed == rubbleMaxSpeed)
}

@Test func accelDerivation() {
    // ACCEL = BOATMAXSPEED * TICKSPERSEC / TICKS_FOR_COMPLETE_STOP
    #expect(accel == boatMaxSpeed * ticksPerSec / ticksForCompleteStop)
    #expect(accel == 2.44140625)
}

// MARK: - terrainMaxSpeed (exhaustive, all 30 cases)

private let expectedMaxSpeed: [Terrain: Float] = [
    .sea: 0.0,
    .boat: 3.125,
    .wall: 0.0,
    .river: 0.5859375,
    .swamp0: 0.5859375,
    .swamp1: 0.5859375,
    .swamp2: 0.5859375,
    .swamp3: 0.5859375,
    .crater: 0.5859375,
    .road: 3.125,
    .forest: 1.171875,
    .rubble0: 0.5859375,
    .rubble1: 0.5859375,
    .rubble2: 0.5859375,
    .rubble3: 0.5859375,
    .grass0: 2.34375,
    .grass1: 2.34375,
    .grass2: 2.34375,
    .grass3: 2.34375,
    .damagedWall0: 0.0,
    .damagedWall1: 0.0,
    .damagedWall2: 0.0,
    .damagedWall3: 0.0,
    .minedSea: 0.0,
    .minedSwamp: 0.5859375,
    .minedCrater: 0.5859375,
    .minedRoad: 3.125,
    .minedForest: 1.171875,
    .minedRubble: 0.5859375,
    .minedGrass: 2.34375,
]

@Test func terrainMaxSpeedExhaustive() throws {
    #expect(expectedMaxSpeed.count == Terrain.allCases.count)
    for terrain in Terrain.allCases {
        let expected = try #require(expectedMaxSpeed[terrain])
        #expect(terrainMaxSpeed(terrain) == expected, "maxSpeed mismatch for \(terrain)")
    }
}

// MARK: - terrainMaxTurnSpeed (exhaustive, all 30 cases)

private let expectedMaxTurnSpeed: [Terrain: Float] = [
    .sea: 0.0,
    .boat: 2.5,
    .wall: 0.0,
    .river: 0.625,
    .swamp0: 0.625,
    .swamp1: 0.625,
    .swamp2: 0.625,
    .swamp3: 0.625,
    .crater: 0.625,
    .road: 2.5,
    .forest: 1.25,
    .rubble0: 0.625,
    .rubble1: 0.625,
    .rubble2: 0.625,
    .rubble3: 0.625,
    .grass0: 2.5,
    .grass1: 2.5,
    .grass2: 2.5,
    .grass3: 2.5,
    .damagedWall0: 0.0,
    .damagedWall1: 0.0,
    .damagedWall2: 0.0,
    .damagedWall3: 0.0,
    .minedSea: 0.0,
    .minedSwamp: 0.625,
    .minedCrater: 0.625,
    .minedRoad: 2.5,
    .minedForest: 1.25,
    .minedRubble: 0.625,
    .minedGrass: 2.5,
]

@Test func terrainMaxTurnSpeedExhaustive() throws {
    #expect(expectedMaxTurnSpeed.count == Terrain.allCases.count)
    for terrain in Terrain.allCases {
        let expected = try #require(expectedMaxTurnSpeed[terrain])
        #expect(terrainMaxTurnSpeed(terrain) == expected, "maxTurnSpeed mismatch for \(terrain)")
    }
}

// MARK: - terrainBuilderSpeed (exhaustive, all 30 cases)

private let expectedBuilderSpeed: [Terrain: Float] = [
    .sea: 0.0,
    .boat: 3.125,
    .wall: 0.0,
    .river: 0.0,
    .swamp0: 0.78125,
    .swamp1: 0.78125,
    .swamp2: 0.78125,
    .swamp3: 0.78125,
    .crater: 0.78125,
    .road: 3.125,
    .forest: 1.5625,
    .rubble0: 0.78125,
    .rubble1: 0.78125,
    .rubble2: 0.78125,
    .rubble3: 0.78125,
    .grass0: 3.125,
    .grass1: 3.125,
    .grass2: 3.125,
    .grass3: 3.125,
    .damagedWall0: 0.0,
    .damagedWall1: 0.0,
    .damagedWall2: 0.0,
    .damagedWall3: 0.0,
    .minedSea: 0.0,
    .minedSwamp: 0.78125,
    .minedCrater: 0.78125,
    .minedRoad: 3.125,
    .minedForest: 1.5625,
    .minedRubble: 0.78125,
    .minedGrass: 3.125,
]

@Test func terrainBuilderSpeedExhaustive() throws {
    #expect(expectedBuilderSpeed.count == Terrain.allCases.count)
    for terrain in Terrain.allCases {
        let expected = try #require(expectedBuilderSpeed[terrain])
        #expect(terrainBuilderSpeed(terrain) == expected, "builderSpeed mismatch for \(terrain)")
    }
}

// MARK: - TerrainGrid

@Test func terrainGridDefaultsToSea() {
    let grid = TerrainGrid()
    #expect(grid.storage.count == 256 * 256)
    #expect(grid[0, 0] == .sea)
    #expect(grid[255, 255] == .sea)
}

@Test func terrainGridSubscriptRoundTrip() {
    var grid = TerrainGrid()
    grid[10, 20] = .road
    #expect(grid[10, 20] == .road)
    // Flat storage layout is y * 256 + x
    #expect(grid.storage[20 * 256 + 10] == Terrain.road.rawValue)
    // Neighbors untouched
    #expect(grid[11, 20] == .sea)
    #expect(grid[10, 21] == .sea)
    // nil assignment resets to sea
    grid[10, 20] = nil
    #expect(grid[10, 20] == .sea)
}
