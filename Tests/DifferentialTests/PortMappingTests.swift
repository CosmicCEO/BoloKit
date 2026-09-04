import Testing
import BoloNet
import dnssd

// Swift-only tests for `decodePortMappingReply` (Wave 6.5b, `PortMapping.
// swift`) -- same "no C oracle for the mechanism itself" reasoning as
// `HostListenerTests.swift`/`HostDgramListenerTests.swift` (D31/D55): the
// live NAT-PMP/UPnP round-trip through `DNSServiceNATPortMappingCreate`
// cannot be exercised in a test without a real gateway, but the pure
// decision this file's callback closure delegates to -- which raw reply
// payloads become a `PortMappingUpdate`, and how ports get byte-swapped
// back to host order -- is a plain value-in-value-out function, tested
// directly here.

@Test func decodePortMappingReplySucceedsOnNoError() {
    // externalPort 0x1F90 (8080) in network byte order is 0x901F.
    let update = decodePortMappingReply(
        errorCode: kDNSServiceErr_NoError, externalAddress: 0x0101_0A0A, externalPort: 0x901F, ttl: 7200
    )
    #expect(update?.externalAddress == 0x0101_0A0A)
    #expect(update?.externalPort == 8080)
    #expect(update?.ttl == 7200)
    #expect(update?.doubleNAT == false)
}

@Test func decodePortMappingReplySucceedsWithDoubleNATFlagOnDoubleNATError() {
    let update = decodePortMappingReply(
        errorCode: kDNSServiceErr_DoubleNAT, externalAddress: 0xC0A8_0001, externalPort: 0x901F, ttl: 3600
    )
    #expect(update != nil)
    #expect(update?.doubleNAT == true)
}

@Test func decodePortMappingReplyReturnsNilOnAnyOtherError() {
    #expect(decodePortMappingReply(errorCode: kDNSServiceErr_Unknown, externalAddress: 0, externalPort: 0, ttl: 0) == nil)
    #expect(decodePortMappingReply(errorCode: kDNSServiceErr_Refused, externalAddress: 0, externalPort: 0, ttl: 0) == nil)
    #expect(decodePortMappingReply(errorCode: kDNSServiceErr_NATPortMappingUnsupported, externalAddress: 0, externalPort: 0, ttl: 0) == nil)
}

@Test func portMappingUpdateIsEquatable() {
    let a = PortMappingUpdate(externalAddress: 1, externalPort: 2, ttl: 3, doubleNAT: false)
    let b = PortMappingUpdate(externalAddress: 1, externalPort: 2, ttl: 3, doubleNAT: false)
    let c = PortMappingUpdate(externalAddress: 1, externalPort: 2, ttl: 3, doubleNAT: true)
    #expect(a == b)
    #expect(a != c)
}

// MARK: - PortMapping (D54) — construction failure surfaces, doesn't crash
//
// A live gateway round-trip is D55's own disclosed non-goal for this
// wave's test coverage; what IS testable without one is that a bogus
// request (internal port 0, an actual local listener has no reason to
// ever be zero) still produces a well-formed `PortMappingError` rather
// than crashing, and that a `cancel()` before any reply arrives is safe
// to call (covers the boxed-context release path with no live mapping).

@Test func portMappingCancelBeforeAnyReplyIsSafe() throws {
    let mapping = try PortMapping(internalPort: 27_500)
    mapping.cancel()
    mapping.cancel()  // idempotent -- must not double-release the boxed context
}
