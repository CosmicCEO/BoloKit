import Network
import dnssd
import Dispatch

// MARK: - v1.3.0 #14 — Bonjour LAN advertise/browse
//
// Discovery only. Session fabric stays Bolo TCP+UDP (`HostListener` /
// `HostDgramListener`). No C oracle: XBolo has no `_bolo` Bonjour path.
// Advertise is `NWListener.Service` on the existing TCP listener;
// browse is `NWBrowser`; resolve is `DNSServiceResolve` so filling the
// join form does not open a TCP connection (that would look like a join).

public let bolo2026BonjourServiceType = "_bolo2026._tcp"

public struct LANGame: Sendable, Hashable {
    public var name: String
    public var type: String
    public var domain: String
    public var endpoint: NWEndpoint

    public init(name: String, type: String, domain: String, endpoint: NWEndpoint) {
        self.name = name
        self.type = type
        self.domain = domain
        self.endpoint = endpoint
    }
}

public func lanGame(from endpoint: NWEndpoint) -> LANGame? {
    guard case .service(let name, let type, let domain, _) = endpoint else { return nil }
    guard type == bolo2026BonjourServiceType else { return nil }
    return LANGame(name: name, type: type, domain: domain, endpoint: endpoint)
}

public func decodeBonjourResolve(
    errorCode: DNSServiceErrorType, hosttarget: String?, portNetworkOrder: UInt16
) -> (host: String, port: UInt16)? {
    guard errorCode == kDNSServiceErr_NoError else { return nil }
    guard let hosttarget, !hosttarget.isEmpty else { return nil }
    return (hosttarget, UInt16(bigEndian: portNetworkOrder))
}

public enum BonjourResolveError: Error, Sendable, Equatable {
    case resolveFailed(DNSServiceErrorType)
    case malformedReply
}

private final class BonjourResolveContext {
    let onReply: (Result<(host: String, port: UInt16), Error>) -> Void
    var serviceRef: DNSServiceRef?

    init(onReply: @escaping (Result<(host: String, port: UInt16), Error>) -> Void) {
        self.onReply = onReply
    }
}

/// Resolves a browsed `_bolo2026._tcp` service to hostname+port without
/// opening the game TCP socket. `hosttarget` is a Bonjour hostname
/// (`*.local`); `TCPSession.join(host:port:)` already accepts that.
public func resolveBonjourService(_ game: LANGame) async throws -> (host: String, port: UInt16) {
    let domain = game.domain.isEmpty ? "local." : game.domain
    return try await withCheckedThrowingContinuation { continuation in
        nonisolated(unsafe) var resumed = false
        let finish: (Result<(host: String, port: UInt16), Error>) -> Void = { result in
            guard !resumed else { return }
            resumed = true
            continuation.resume(with: result)
        }
        let boxed = BonjourResolveContext(onReply: finish)
        let unmanaged = Unmanaged.passRetained(boxed)

        var ref: DNSServiceRef?
        let error = game.name.withCString { namePtr in
            game.type.withCString { typePtr in
                domain.withCString { domainPtr in
                    DNSServiceResolve(
                        &ref,
                        0,
                        0,
                        namePtr,
                        typePtr,
                        domainPtr,
                        { _, _, _, errorCode, _, hosttarget, port, _, _, context in
                            guard let context else { return }
                            let box = Unmanaged<BonjourResolveContext>.fromOpaque(context).takeUnretainedValue()
                            if let ref = box.serviceRef {
                                DNSServiceRefDeallocate(ref)
                                box.serviceRef = nil
                            }
                            let host = hosttarget.map { String(cString: $0) }
                            if let resolved = decodeBonjourResolve(
                                errorCode: errorCode, hosttarget: host, portNetworkOrder: port
                            ) {
                                box.onReply(.success(resolved))
                            } else if errorCode != kDNSServiceErr_NoError {
                                box.onReply(.failure(BonjourResolveError.resolveFailed(errorCode)))
                            } else {
                                box.onReply(.failure(BonjourResolveError.malformedReply))
                            }
                            Unmanaged<BonjourResolveContext>.fromOpaque(context).release()
                        },
                        unmanaged.toOpaque()
                    )
                }
            }
        }

        guard error == kDNSServiceErr_NoError, let ref else {
            unmanaged.release()
            finish(.failure(BonjourResolveError.resolveFailed(error)))
            return
        }

        boxed.serviceRef = ref
        DNSServiceSetDispatchQueue(ref, DispatchQueue(label: "BoloNet.BonjourResolve"))
    }
}

public final class BonjourBrowser: @unchecked Sendable {
    private let browser: NWBrowser
    private let stream: AsyncStream<[LANGame]>
    private let continuation: AsyncStream<[LANGame]>.Continuation
    private var isCancelled = false

    public init() {
        let descriptor = NWBrowser.Descriptor.bonjour(type: bolo2026BonjourServiceType, domain: nil)
        browser = NWBrowser(for: descriptor, using: .tcp)
        var continuationBox: AsyncStream<[LANGame]>.Continuation?
        stream = AsyncStream { continuationBox = $0 }
        let continuation = continuationBox!
        self.continuation = continuation

        browser.browseResultsChangedHandler = { results, _ in
            let games = results.compactMap { lanGame(from: $0.endpoint) }.sorted { $0.name < $1.name }
            continuation.yield(games)
        }
        browser.start(queue: .main)
    }

    public var games: AsyncStream<[LANGame]> { stream }

    public func cancel() {
        guard !isCancelled else { return }
        isCancelled = true
        browser.cancel()
        continuation.finish()
    }

    deinit {
        cancel()
    }
}
