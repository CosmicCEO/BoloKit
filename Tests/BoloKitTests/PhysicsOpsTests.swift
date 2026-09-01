import Testing
import BoloKit
import Darwin

// MARK: - Physics object constants (Wave 5.0)

@Test func physicsObjectConstantsMatchBoloH() {
    #expect(builderRadius == 0.125)
    #expect(tankRadius == 0.375)
    #expect(shellVelocity == 7.0)
    #expect(maxShellRange == 7.0)
    #expect(maxAngularVelocity == 2.5)
    #expect(pushForce == 1.5625)
    #expect(kickForce == 3.125)
    #expect(kickSpeedDecay == 12.0)
    #expect(explosionTicks == 24)
    #expect(explodeTicks == 45)
    #expect(respawnTicks == 150)
    #expect(maxShells == 40)
    #expect(maxMines == 40)
    #expect(maxArmour == 40)
    #expect(maxTrees == 40)
    #expect(roadTrees == 2)
    #expect(wallTrees == 2)
    #expect(boatTrees == 20)
    #expect(pillTrees == 4)
    #expect(maxPlayers == 16)
    #expect(maxStarts == 16)
    #expect(pillOnboard == 0xff)
    #expect(playerNeutral == 0xff)
    #expect(noPill == 0xff)
    #expect(minBaseArmour == 5)
    #expect(coolPillTicks == 32)
    #expect(replenishBaseTicks == 600)
    #expect(treesPlantRate == 10)
    #expect(treesBestOf == 4200)
    #expect(maxTicksPerShot == 100)
    #expect(maxBaseArmour == 90)
    #expect(maxBaseShells == 90)
    #expect(maxBaseMines == 90)
}

// MARK: - maxSpeed / maxTurnSpeed

@Test func maxSpeedArmedPillBlocks() {
    let pills = [Pill(x: 10, y: 10, armour: 5, owner: 0)]
    #expect(maxSpeed(x: 10, y: 10, terrain: .road, pills: pills, bases: []) == 0.0)
}

@Test func maxSpeedDeadPillAllowsRoadSpeed() {
    let pills = [Pill(x: 10, y: 10, armour: 0, owner: 0)]
    // Underlying terrain is sea (impassable) — dead pill override still wins
    #expect(maxSpeed(x: 10, y: 10, terrain: .sea, pills: pills, bases: []) == roadMaxSpeed)
}

@Test func maxSpeedOnboardPillIsIgnored() {
    // armour == pillOnboard means "carried by a builder", not present on the map
    let pills = [Pill(x: 10, y: 10, armour: pillOnboard, owner: 0)]
    #expect(maxSpeed(x: 10, y: 10, terrain: .grass3, pills: pills, bases: []) == grassMaxSpeed)
}

@Test func maxSpeedBaseAllowsRoadSpeed() {
    let bases = [Base(x: 20, y: 20)]
    #expect(maxSpeed(x: 20, y: 20, terrain: .forest, pills: [], bases: bases) == roadMaxSpeed)
}

@Test func maxSpeedFallsThroughToTerrain() {
    #expect(maxSpeed(x: 1, y: 1, terrain: .forest, pills: [], bases: []) == terrainMaxSpeed(.forest))
    #expect(maxSpeed(x: 1, y: 1, terrain: .rubble2, pills: [], bases: []) == terrainMaxSpeed(.rubble2))
}

@Test func maxTurnSpeedArmedPillBlocks() {
    let pills = [Pill(x: 10, y: 10, armour: 5, owner: 0)]
    #expect(maxTurnSpeed(x: 10, y: 10, terrain: .road, pills: pills, bases: []) == 0.0)
}

@Test func maxTurnSpeedDeadPillAllowsFullTurn() {
    let pills = [Pill(x: 10, y: 10, armour: 0, owner: 0)]
    #expect(maxTurnSpeed(x: 10, y: 10, terrain: .sea, pills: pills, bases: []) == 2.5)
}

@Test func maxTurnSpeedBaseAllowsFullTurn() {
    let bases = [Base(x: 20, y: 20)]
    #expect(maxTurnSpeed(x: 20, y: 20, terrain: .forest, pills: [], bases: bases) == 2.5)
}

@Test func maxTurnSpeedFallsThroughToTerrain() {
    #expect(maxTurnSpeed(x: 1, y: 1, terrain: .forest, pills: [], bases: []) == terrainMaxTurnSpeed(.forest))
    #expect(maxTurnSpeed(x: 1, y: 1, terrain: .grass1, pills: [], bases: []) == terrainMaxTurnSpeed(.grass1))
}

// MARK: - collisionDetect

@Test func collisionDetectNoCollisionLeavesPositionUnchanged() {
    let p = Vec2f(x: 5.5, y: 5.5)
    let result = collisionDetect(p, radius: 0.375) { _ in false }
    #expect(result.x == p.x)
    #expect(result.y == p.y)
}

@Test func collisionDetectSingleAxisPush() {
    // Solid only to the left of (5,5) — expect a pure x-axis push, y untouched.
    let p = Vec2f(x: 5.1, y: 5.5)
    let radius: Float = 0.2
    let result = collisionDetect(p, radius: radius) { $0.x == 4 && $0.y == 5 }
    #expect(result.x == 5.0 + radius)
    #expect(result.y == p.y)
}

@Test func collisionDetectBugBranchSetsXNotY() {
    // Squeezed between solid cells above (5,7) and below (5,9) of (5,8),
    // radius=0.6 (>0.5, required for lyc && hyc to both fire). Correct
    // behavior would set p.y = fy + 0.5 = 8.5; the ported C bug instead
    // sets p.x = fy + 0.5 = 8.5 and leaves p.y untouched at its original
    // 8.45 — asserting exactly that mistaken behavior, not the fix.
    let p = Vec2f(x: 5.5, y: 8.45)
    let radius: Float = 0.6
    let result = collisionDetect(p, radius: radius) { sq in
        sq.x == 5 && (sq.y == 7 || sq.y == 9)
    }
    #expect(result.x == 8.5, "bug should set p.x = fy + 0.5")
    #expect(result.y == 8.45, "bug leaves p.y untouched — this is the defect, not a fix")
}

@Test func collisionDetectDiagonalCornerPush() {
    // Solid only at the upper-left diagonal (4,4) of (5,5) — no cardinal
    // neighbors solid, so only the diagonal-corner branch can fire.
    let p = Vec2f(x: 5.1, y: 5.1)
    let radius: Float = 0.3
    let result = collisionDetect(p, radius: radius) { $0.x == 4 && $0.y == 4 }

    let lx: Float = 0.1
    let ly: Float = 0.1
    let sqr = lx * lx + ly * ly
    let sca = radius / sqrtf(sqr)
    #expect(result.x == 5.0 + sca * lx)
    #expect(result.y == 5.0 + sca * ly)
}
