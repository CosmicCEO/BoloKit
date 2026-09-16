import Testing
import BoloNet

@Test func boloSignpostsSubsystemMatchesAppBundleID() {
    #expect(BoloSignposts.subsystem == "com.cosmicceo.Bolo-2026")
}

@Test func boloSignpostsCategoriesAreTickRenderNet() {
    #expect(BoloSignposts.tickCategory == "tick")
    #expect(BoloSignposts.renderCategory == "render")
    #expect(BoloSignposts.netCategory == "net")
}

@Test func boloSignpostsIntervalNamesMatchIssue16() {
    #expect(staticStringContents(BoloSignposts.runTickName) == "runTick")
    #expect(staticStringContents(BoloSignposts.drawName) == "draw")
    #expect(staticStringContents(BoloSignposts.clUpdateName) == "clUpdate")
}

private func staticStringContents(_ value: StaticString) -> String {
    String(decoding: UnsafeBufferPointer(start: value.utf8Start, count: value.utf8CodeUnitCount), as: UTF8.self)
}
