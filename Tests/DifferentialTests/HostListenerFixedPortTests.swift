import Foundation
import Testing
import BoloNet

// Regression for the "NWListener EINVAL" that blocked hosting on a fixed port through v1.5.0:
// `NWListener(using:on:)` combined with `requiredLocalEndpoint` carrying the same port throws
// EINVAL for every non-zero port. Every other listener test binds port 0, which is exempt, so
// none of them could see it. See `forceIPv4` in `HostListener.swift`.

@Test func hostListenersBindAnExplicitNonZeroPortOverBothTransports() async throws {
    // A random dynamic-range port may already be taken; that (EADDRINUSE, 48) is retried.
    // Any other error, EINVAL (22) above all, is the regression and fails the test.
    for _ in 0..<8 {
        let port = UInt16.random(in: 49_152...65_000)
        let tcp: HostListener
        do { tcp = try await HostListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        defer { tcp.cancel() }
        let udp: HostDgramListener
        do { udp = try await HostDgramListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        defer { udp.cancel() }

        #expect(tcp.port == port)
        #expect(udp.port == port)
        return
    }
    Issue.record("no free dynamic port found in 8 attempts")
}

// The host listeners must be genuinely IPv4-only. A Bonjour join reaches the host over its IPv6
// link-local address; a listener that accepts it can never track that peer (the wire protocol is a
// `sockaddr_in`), so every datagram was dropped and the guest evicted after 9 s. `requiredLocalEndpoint
// (.ipv4(.any))` alone does NOT prevent this; the IP-version option does (`forceIPv4`).

import Network

@Test(.disabled(if: ProcessInfo.processInfo.environment["CI"] != nil, "timing/IPv6-sensitive on GitHub runners; runs locally")) func hostListenerRefusesAnIPv6Client() async throws {
    for _ in 0..<8 {
        let port = UInt16.random(in: 49_152...65_000)
        let tcp: HostListener
        do { tcp = try await HostListener(port: port) }
        catch let error as POSIXError where error.code == .EADDRINUSE { continue }
        defer { tcp.cancel() }

        // Unlike 127.0.0.1, ::1 must not connect.
        let ipv6 = NWConnection(host: "::1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let ipv4 = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        defer { ipv6.cancel(); ipv4.cancel() }
        let state = StateBox()
        ipv6.stateUpdateHandler = { state.set6("\($0)") }
        ipv4.stateUpdateHandler = { state.set4("\($0)") }
        ipv6.start(queue: .global())
        ipv4.start(queue: .global())
        try await Task.sleep(nanoseconds: 1_500_000_000)

        #expect(state.v4 == "ready", "IPv4 client must connect, got \(state.v4)")
        #expect(state.v6 != "ready", "IPv6 client must be refused, got \(state.v6)")
        return
    }
    Issue.record("no free dynamic port found in 8 attempts")
}

private final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _v4 = "?", _v6 = "?"
    var v4: String { lock.lock(); defer { lock.unlock() }; return _v4 }
    var v6: String { lock.lock(); defer { lock.unlock() }; return _v6 }
    func set4(_ s: String) { lock.lock(); _v4 = s; lock.unlock() }
    func set6(_ s: String) { lock.lock(); _v6 = s; lock.unlock() }
}
