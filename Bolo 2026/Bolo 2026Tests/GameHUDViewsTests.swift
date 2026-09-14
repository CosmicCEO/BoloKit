//
//  GameHUDViewsTests.swift
//  Bolo 2026Tests
//
//  D148(B) -- regression coverage for `GameHUDMath.gaugeFraction`, the pure logic backing the
//  always-visible shell/mine/armor gauges (`GameHUDViews.swift`). Extracted per D144/D145/D146's
//  precedent of pulling pure logic out of view code for direct unit-testing.

import Testing
import BoloNet

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

    @Test func eventLogBarVisibleMessagesKeepsTheNewestThree() {
        let messages = (1...5).map {
            ChatMessage(id: UInt64($0), player: 0, senderName: "", text: "\($0)", to: EventLogText.gameTarget)
        }
        let visible = EventLogBarMath.visibleMessages(messages)
        #expect(visible.map(\.id) == [3, 4, 5])
    }

    @Test func eventLogBarVisibleMessagesEmptyIsEmpty() {
        #expect(EventLogBarMath.visibleMessages([]).isEmpty)
    }

    @Test func eventLogBarTintKindMatchesMessageTarget() {
        #expect(EventLogBarMath.tintKind(to: MessageTarget.everyone.rawValue) == .everyone)
        #expect(EventLogBarMath.tintKind(to: MessageTarget.allies.rawValue) == .allies)
        #expect(EventLogBarMath.tintKind(to: MessageTarget.nearby.rawValue) == .nearby)
        #expect(EventLogBarMath.tintKind(to: EventLogText.gameTarget) == .game)
    }
}
