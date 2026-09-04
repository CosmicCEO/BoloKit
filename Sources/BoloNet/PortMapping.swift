import dnssd
import Dispatch

// MARK: - Wave 6.5b (D54) — NAT-PMP/UPnP port mapping via `DNSServiceNATPortMappingCreate`
//
// No C oracle exists for this half of Wave 6.5 (D55) -- `TCMPortMapper`,
// the GPLv3 dependency `README.md:61-64` commits this port to never using,
// is the C oracle's own mechanism, off-limits both to read and to port
// (D25/D33's clean-room policy). `DNSServiceNATPortMappingCreate`
// (`import dnssd`, confirmed a `libSystem` system API during this wave's
// pre-brief -- nothing bundled, no GPL exposure) covers the same NAT-PMP/
// UPnP IGD union `TCMPortMapper` did, and self-renews/self-heals across
// sleep-wake and gateway changes on its own -- this file is a thin
// `AsyncStream` shim around its C callback, not new NAT logic of its own.
//
// Same drained-by-one-consumer `AsyncStream` shape `HostListener.swift`/
// `HostDgramListener.swift` already proved twice (D49/D52), reused here
// even though the mechanism crossing into Swift is genuinely new:
// `dnssd`'s reply is a plain C function pointer, not a `Network.framework`
// closure, so it cannot capture Swift state directly the way every other
// listener in this module does -- `PortMappingContext` boxes the stream
// continuation and crosses the C boundary via the callback's own
// documented `context: UnsafeMutableRawPointer?` mechanism instead.

/// Boxes the stream continuation for the C callback's `context` pointer --
/// see this file's header for why a plain closure capture doesn't work
/// here the way it does for every `Network.framework` listener elsewhere
/// in `BoloNet`.
private final class PortMappingContext {
    let continuation: AsyncStream<PortMappingUpdate>.Continuation
    init(continuation: AsyncStream<PortMappingUpdate>.Continuation) {
        self.continuation = continuation
    }
}

/// One `DNSServiceNATPortMappingReply` invocation's payload. Ports are
/// converted to host byte order here for API consistency with this
/// file's own `internalPort`/`externalPort` parameters (both host-order,
/// matching every other `port: UInt16` in this module -- `HostListener.
/// swift` et al.); `externalAddress` stays raw network-order, matching
/// `DgramServerPeerAddress.addr`'s existing convention (`HostListener.
/// swift`) rather than introducing a second one for the same shape of
/// value.
public struct PortMappingUpdate: Sendable, Equatable {
    public let externalAddress: UInt32
    public let externalPort: UInt16
    public let ttl: UInt32
    /// `true` when the reply's error was `kDNSServiceErr_DoubleNAT`, not
    /// `kDNSServiceErr_NoError` -- per the API's own documented contract,
    /// every other field is still meaningful in this case (the gateway
    /// itself is behind another NAT layer), so it surfaces as a flag on a
    /// successful update rather than a thrown error.
    public let doubleNAT: Bool
}

public enum PortMappingError: Error, Sendable, Equatable {
    case creationFailed(DNSServiceErrorType)
}

/// Pure decision logic for one raw callback invocation, factored out of
/// the C callback closure itself so it is unit-testable without a live
/// `DNSServiceRef`/gateway round-trip. D55 already ruled this wave has no
/// C oracle to test against -- but that only applies to the actual NAT
/// round-trip; this function's mapping from one reply payload to either
/// an update or nothing is a plain value-in-value-out decision, the same
/// "decision vs. mechanism" split this project has applied everywhere
/// else (D31/D36/D42).
func decodePortMappingReply(
    errorCode: DNSServiceErrorType, externalAddress: UInt32, externalPort: UInt16, ttl: UInt32
) -> PortMappingUpdate? {
    guard errorCode == kDNSServiceErr_NoError || errorCode == kDNSServiceErr_DoubleNAT else {
        return nil
    }
    return PortMappingUpdate(
        externalAddress: externalAddress,
        externalPort: UInt16(bigEndian: externalPort),
        ttl: ttl,
        doubleNAT: errorCode == kDNSServiceErr_DoubleNAT
    )
}

/// Wraps `DNSServiceNATPortMappingCreate` -- requests a mapping for both
/// UDP and TCP by default (Bolo's own transport needs both: game UDP plus
/// tracker/join TCP), renewed automatically by the system for the
/// mapping's lifetime until `cancel()`/`deinit`.
public final class PortMapping: @unchecked Sendable {
    private var serviceRef: DNSServiceRef?
    private var context: Unmanaged<PortMappingContext>?
    private let stream: AsyncStream<PortMappingUpdate>
    private let queue = DispatchQueue(label: "BoloNet.PortMapping")

    /// `internalPort`/`externalPort` are host byte order here -- converted
    /// to the API's required network byte order internally. `externalPort:
    /// 0`/`ttl: 0` are the API's own documented "don't care" sentinels
    /// (system picks the external port / a default renewal period), not a
    /// Swift-side default invented here.
    public init(
        internalPort: UInt16,
        externalPort: UInt16 = 0,
        ttl: UInt32 = 0,
        protocols: DNSServiceProtocol = DNSServiceProtocol(kDNSServiceProtocol_UDP | kDNSServiceProtocol_TCP)
    ) throws {
        var continuationBox: AsyncStream<PortMappingUpdate>.Continuation?
        stream = AsyncStream { continuationBox = $0 }
        let boxed = PortMappingContext(continuation: continuationBox!)
        let unmanaged = Unmanaged.passRetained(boxed)

        var ref: DNSServiceRef?
        let createError = DNSServiceNATPortMappingCreate(
            &ref, 0, 0, protocols,
            internalPort.bigEndian, externalPort.bigEndian, ttl,
            { _, _, _, errorCode, externalAddress, _, _, externalPort, ttl, context in
                guard let context else { return }
                guard let update = decodePortMappingReply(
                    errorCode: errorCode, externalAddress: externalAddress, externalPort: externalPort, ttl: ttl
                ) else {
                    return
                }
                let box = Unmanaged<PortMappingContext>.fromOpaque(context).takeUnretainedValue()
                box.continuation.yield(update)
            },
            unmanaged.toOpaque()
        )

        guard createError == kDNSServiceErr_NoError, let ref else {
            unmanaged.release()
            throw PortMappingError.creationFailed(createError)
        }

        serviceRef = ref
        context = unmanaged
        DNSServiceSetDispatchQueue(ref, queue)
    }

    /// Drain one update at a time -- see this file's header for why the
    /// same `AsyncStream` shape as `HostListener.connections`/
    /// `HostDgramListener.packets` applies here too, even though the
    /// mechanism crossing into Swift is different.
    public var updates: AsyncStream<PortMappingUpdate> { stream }

    /// Tears down the mapping request and releases the boxed context.
    /// Safe to call more than once (e.g. explicitly, then again from
    /// `deinit`).
    public func cancel() {
        if let ref = serviceRef {
            DNSServiceRefDeallocate(ref)
            serviceRef = nil
        }
        context?.release()
        context = nil
    }

    deinit {
        cancel()
    }
}
