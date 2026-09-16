import Foundation

/// v1.3.0 #20 — `bolo://join?host=&port=`. Invite only; session fabric
/// stays Bolo TCP+UDP. Generated URLs never include a password.
nonisolated struct BoloJoinURL: Equatable, Sendable {
    var host: String
    var port: UInt16

    static func parse(_ url: URL) -> BoloJoinURL? {
        guard url.scheme?.lowercased() == "bolo" else { return nil }
        guard url.host?.lowercased() == "join" else { return nil }
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems else {
            return nil
        }
        guard let host = items.first(where: { $0.name == "host" })?.value, !host.isEmpty else {
            return nil
        }
        guard let portText = items.first(where: { $0.name == "port" })?.value,
              let port = UInt16(portText)
        else { return nil }
        return BoloJoinURL(host: host, port: port)
    }

    static func make(host: String, port: UInt16) -> URL {
        var components = URLComponents()
        components.scheme = "bolo"
        components.host = "join"
        components.queryItems = [
            URLQueryItem(name: "host", value: host),
            URLQueryItem(name: "port", value: String(port)),
        ]
        return components.url!
    }
}
