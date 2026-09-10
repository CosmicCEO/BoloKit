//
//  GameHUDViewsTests.swift
//  Bolo 2026Tests
//
//  D148(B) -- regression coverage for `GameHUDMath.gaugeFraction`, the pure logic backing the
//  always-visible shell/mine/armor gauges (`GameHUDViews.swift`). Extracted per D144/D145/D146's
//  precedent of pulling pure logic out of view code for direct unit-testing.

import Testing

@testable import Bolo_2026

@MainActor
struct GameHUDViewsTests {
    @Test func fullValueYieldsOne() {
        #expect(GameHUDMath.gaugeFraction(value: 40, max: 40) == 1)
    }

    @Test func zeroValueYieldsZero() {
        #expect(GameHUDMath.gaugeFraction(value: 0, max: 40) == 0)
    }

    @Test func midValueYieldsExpectedFraction() {
        #expect(GameHUDMath.gaugeFraction(value: 20, max: 40) == 0.5)
    }

    @Test func overMaxValueClampsToOne() {
        #expect(GameHUDMath.gaugeFraction(value: 55, max: 40) == 1)
    }

    @Test func negativeValueClampsToZero() {
        #expect(GameHUDMath.gaugeFraction(value: -5, max: 40) == 0)
    }

    @Test func zeroMaxIsSafeAndYieldsZero() {
        #expect(GameHUDMath.gaugeFraction(value: 5, max: 0) == 0)
    }
}
