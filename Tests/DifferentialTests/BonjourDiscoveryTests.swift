import Testing
import BoloNet
import Network

// v1.3.0 #14 — Bonjour LAN advertise/browse. Discovery only; no C oracle
// for the mechanism (same D31 reasoning as HostListenerTests). Live
// mDNS round-trips are not required: service identity and browse mapping
// are value-in-value-out. Join uses the service endpoint, not dnssd resolve.

@Test func bolo2026BonjourServiceTypeIsBolo2026TCP() {
    #expect(bolo2026BonjourServiceType == "_bolo2026._tcp")
}

@Test func lanGameMapsMatchingServiceEndpoint() {
    let endpoint = NWEndpoint.service(
        name: "Newbie", type: bolo2026BonjourServiceType, domain: "local.", interface: nil
    )
    let game = lanGame(from: endpoint)
    #expect(game?.name == "Newbie")
    #expect(game?.endpoint == endpoint)
}

@Test func lanGameIgnoresOtherServiceTypesAndHostPorts() {
    let other = NWEndpoint.service(
        name: "Nope", type: "_http._tcp", domain: "local.", interface: nil
    )
    #expect(lanGame(from: other) == nil)

    let hostPort = NWEndpoint.hostPort(host: "127.0.0.1", port: 50000)
    #expect(lanGame(from: hostPort) == nil)
}

@Test func hostListenerAdvertisesBolo2026Service() async throws {
    let listener = try await HostListener(port: 0, bonjourName: "TestHost")
    defer { listener.cancel() }
    #expect(listener.bonjourService?.type == bolo2026BonjourServiceType)
    #expect(listener.bonjourService?.name == "TestHost")
}

@Test func bonjourBrowserCancelBeforeAnyResultIsSafe() {
    let browser = BonjourBrowser()
    browser.cancel()
    browser.cancel()
}
