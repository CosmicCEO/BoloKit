//
//  BoloSignpostsTests.swift
//  Bolo 2026Tests
//
//  v1.4.0 #16 -- Instruments signposts on tick/draw/net. Locks the subsystem
//  and category strings so HostGameEngine and GameRenderView cannot drift.

import Testing
import BoloNet

struct BoloSignpostsTests {
    @Test func subsystemMatchesAppBundleID() {
        #expect(BoloSignposts.subsystem == "com.cosmicceo.Bolo-2026")
    }

    @Test func categoriesAreTickRenderNet() {
        #expect(BoloSignposts.tickCategory == "tick")
        #expect(BoloSignposts.renderCategory == "render")
        #expect(BoloSignposts.netCategory == "net")
    }

    @Test func intervalNamesMatchIssue16() {
        #expect(staticStringContents(BoloSignposts.runTickName) == "runTick")
        #expect(staticStringContents(BoloSignposts.drawName) == "draw")
        #expect(staticStringContents(BoloSignposts.clUpdateName) == "clUpdate")
    }
}

private func staticStringContents(_ value: StaticString) -> String {
    String(decoding: UnsafeBufferPointer(start: value.utf8Start, count: value.utf8CodeUnitCount), as: UTF8.self)
}
