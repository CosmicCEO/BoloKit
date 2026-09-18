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
