import BoloKit
import Foundation
import Network

enum Seat: String {
    case host
    case guest
}

/// One seat's control channel: a minimal HTTP/1.1 listener (no framework -- one JSON request in,
/// one JSON response out, `Connection: close`) that a shell one-liner (`curl -s -d '{"cmd":...}'
/// http://127.0.0.1:PORT/`) drives once per turn. Deliberately not a persistent-connection
/// protocol: the two real players issuing these commands are Claude agents each running one
/// discrete shell command per turn, never holding a connection open.
final class ControlServer: @unchecked Sendable {
    private let seat: Seat
    private let port: UInt16
    private let stateBox: StateBox
    private let lifecycle: GameLifecycle
    private let anomalyLog: AnomalyLog
    private var listener: NWListener?

    init(seat: Seat, port: UInt16, stateBox: StateBox, lifecycle: GameLifecycle, anomalyLog: AnomalyLog) {
        self.seat = seat
        self.port = port
        self.stateBox = stateBox
        self.lifecycle = lifecycle
        self.anomalyLog = anomalyLog
    }

    func start() async throws {
        let parameters = NWParameters.tcp
        parameters.allowLocalEndpointReuse = true
        let boundPort = NWEndpoint.Port(rawValue: port)!
        parameters.requiredLocalEndpoint = .hostPort(host: .ipv4(.loopback), port: boundPort)
        let listener = try NWListener(using: parameters)
        self.listener = listener
        listener.newConnectionHandler = { [weak self] connection in
            connection.start(queue: .main)
            Task { await self?.handle(connection) }
        }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            nonisolated(unsafe) var resumed = false
            listener.stateUpdateHandler = { state in
                guard !resumed else { return }
                switch state {
                case .ready: resumed = true; continuation.resume()
                case .failed(let error): resumed = true; continuation.resume(throwing: error)
                default: break
                }
            }
            listener.start(queue: .main)
        }
    }

    // MARK: - Connection handling

    private func handle(_ connection: NWConnection) async {
        guard let (body, _) = await readHTTPRequest(connection) else {
            connection.cancel()
            return
        }
        let (status, json) = await respond(to: body)
        await writeHTTPResponse(connection, status: status, json: json)
        connection.cancel()
    }

    private func respond(to body: [UInt8]) async -> (status: String, json: Data) {
        guard let request = try? JSONDecoder().decode(ArenaRequest.self, from: Data(body)) else {
            return ("400 Bad Request", (try? JSONEncoder().encode(ErrorResponse(error: "malformed JSON body"))) ?? Data())
        }
        let (statusOK, response) = await dispatch(request)
        return (statusOK ? "200 OK" : "400 Bad Request", response)
    }

    private func dispatch(_ request: ArenaRequest) async -> (ok: Bool, json: Data) {
        let encoder = JSONEncoder()
        switch request.cmd {
        case "observe":
            let response = ObserveBuilder.build(from: stateBox)
            return (true, (try? encoder.encode(response)) ?? Data())

        case "input":
            let flags = FlagCoding.decode(request.flags ?? [])
            switch seat {
            case .host:
                lifecycle.hostSubmitInput(flags)
            case .guest:
                stateBox.setFlags(flags)
                stateBox.mutate { state in
                    let g = state.localPlayer
                    if state.players.indices.contains(g) { state.players[g].inputFlags = flags }
                }
            }
            return (true, (try? encoder.encode(AckResponse(ok: true, message: nil))) ?? Data())

        case "build":
            guard let kindName = request.kind, let kind = BuilderKindCoding.decode(kindName),
                  let x = request.x, let y = request.y
            else {
                return (false, (try? encoder.encode(ErrorResponse(error: "build needs kind/x/y"))) ?? Data())
            }
            let target = Pointi(x: x, y: y)
            switch seat {
            case .host: lifecycle.hostSubmitBuild(kind: kind, target: target)
            case .guest: stateBox.queueBuild(kind: kind, target: target)
            }
            return (true, (try? encoder.encode(AckResponse(ok: true, message: nil))) ?? Data())

        case "mine":
            switch seat {
            case .host: lifecycle.hostSubmitMine()
            case .guest: stateBox.requestMine()
            }
            return (true, (try? encoder.encode(AckResponse(ok: true, message: nil))) ?? Data())

        case "note":
            anomalyLog.note(seat: seat.rawValue, gameId: stateBox.snapshot.gameId, text: request.text ?? "")
            return (true, (try? encoder.encode(AckResponse(ok: true, message: nil))) ?? Data())

        case "newgame":
            guard seat == .host else {
                return (false, (try? encoder.encode(ErrorResponse(error: "newgame is host-seat only"))) ?? Data())
            }
            await lifecycle.newGame()
            return (true, (try? encoder.encode(NewGameResponse(ok: true, gameId: stateBox.snapshot.gameId, message: nil))) ?? Data())

        default:
            return (false, (try? encoder.encode(ErrorResponse(error: "unknown cmd \(request.cmd)"))) ?? Data())
        }
    }

    // MARK: - Minimal HTTP/1.1 framing

    /// Reads one HTTP request off `connection`: accumulates bytes until the header terminator
    /// (`\r\n\r\n`), reads `Content-Length` more bytes for the body. Returns `(body, headerText)`,
    /// or `nil` on a closed/malformed connection. No keep-alive support -- one request per
    /// connection, matching how the shell-side `curl` caller actually uses this.
    private func readHTTPRequest(_ connection: NWConnection) async -> ([UInt8], String)? {
        var buffer: [UInt8] = []
        let deadline = Date().addingTimeInterval(5)

        func receiveChunk() async -> [UInt8]? {
            await withCheckedContinuation { (continuation: CheckedContinuation<[UInt8]?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65536) { data, _, _, error in
                    if error != nil { continuation.resume(returning: nil) }
                    else { continuation.resume(returning: data.map { Array($0) }) }
                }
            }
        }

        while Date() < deadline {
            guard let chunk = await receiveChunk(), !chunk.isEmpty else { return buffer.isEmpty ? nil : (buffer, "") }
            buffer.append(contentsOf: chunk)
            guard let headerEnd = findSubrange(buffer, matching: [13, 10, 13, 10]) else { continue }
            let headerText = String(decoding: buffer[0..<headerEnd], as: UTF8.self)
            let contentLength = parseContentLength(headerText) ?? 0
            let bodyStart = headerEnd + 4
            while buffer.count < bodyStart + contentLength, Date() < deadline {
                guard let more = await receiveChunk(), !more.isEmpty else { break }
                buffer.append(contentsOf: more)
            }
            let bodyEnd = min(buffer.count, bodyStart + contentLength)
            return (Array(buffer[bodyStart..<bodyEnd]), headerText)
        }
        return nil
    }

    private func parseContentLength(_ headerText: String) -> Int? {
        for line in headerText.split(separator: "\r\n") {
            let parts = line.split(separator: ":", maxSplits: 1)
            guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces).lowercased() == "content-length" else { continue }
            return Int(parts[1].trimmingCharacters(in: .whitespaces))
        }
        return nil
    }

    private func findSubrange(_ haystack: [UInt8], matching needle: [UInt8]) -> Int? {
        guard haystack.count >= needle.count else { return nil }
        for i in 0...(haystack.count - needle.count) {
            if Array(haystack[i..<(i + needle.count)]) == needle { return i }
        }
        return nil
    }

    private func writeHTTPResponse(_ connection: NWConnection, status: String, json: Data) async {
        var head = "HTTP/1.1 \(status)\r\n"
        head += "Content-Type: application/json\r\n"
        head += "Content-Length: \(json.count)\r\n"
        head += "Connection: close\r\n\r\n"
        var payload = Data(head.utf8)
        payload.append(json)
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            connection.send(content: payload, completion: .contentProcessed { _ in continuation.resume() })
        }
    }
}
