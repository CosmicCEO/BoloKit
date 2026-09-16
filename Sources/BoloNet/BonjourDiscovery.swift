import Network

// MARK: - v1.3.0 #14 — Bonjour LAN advertise/browse
//
// Discovery only. Session fabric stays Bolo TCP+UDP. Advertise is
// `NWListener.Service` on the existing TCP listener; browse is `NWBrowser`.
// Join uses the browsed `NWEndpoint.service` directly — no dnssd resolve.

public let bolo2026BonjourServiceType = "_bolo2026._tcp"

public struct LANGame: Sendable, Hashable {
    public var name: String
    public var endpoint: NWEndpoint

    public init(name: String, endpoint: NWEndpoint) {
        self.name = name
        self.endpoint = endpoint
    }
}

public func lanGame(from endpoint: NWEndpoint) -> LANGame? {
    guard case .service(let name, let type, _, _) = endpoint else { return nil }
    guard type == bolo2026BonjourServiceType else { return nil }
    return LANGame(name: name, endpoint: endpoint)
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
