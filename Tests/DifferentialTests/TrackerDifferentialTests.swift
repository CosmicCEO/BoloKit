import Testing
import BoloKit
import BoloNet
import CXBolo
import Network
import Foundation

// Wave 6.5a — tracker protocol (registerserver()'s handshake +
// sendtrackerupdate()'s heartbeat, Sources/BoloNet/Tracker.swift +
// TrackerRegistration.swift; listtracker()'s browse client,
// TrackerBrowser.swift). Layout/encode claims are oracle-differential
// against Sources/CXBolo/netops.c's tracker_layout_oracle()/
// trackerhost_encode_oracle()/trackerupdate_encode_oracle(); the
// handshake/browse wire scripts have no C oracle for their transport
// mechanism (same D31 reasoning as JoinClientTests.swift/
// TCPSessionTests.swift), so those are Swift-only loopback tests against
// a fake tracker daemon played by a plain NWListener/NWConnection.

private func fixedBytes(_ s: String, count: Int) -> [UInt8] {
    var bytes = Array(s.utf8.prefix(count))
    while bytes.count < count { bytes.append(0) }
    return bytes
}

@Suite struct TrackerLayoutAndEncodeDifferentialTests {

    @Test func testTrackerLayoutMatchesOracle() {
        let L = CXBolo.tracker_layout_oracle()

        // BoloNet.TrackerHost (tracker.h:41-51): playername[16] + mapname[32] +
        // port(2) + gametype(1) + pad(1) + timelimit(4) + passreq(1) +
        // nplayers(1) + allowjoin(1) + pause(1) = 60 bytes, with the
        // offset-51 pad byte between gametype and the 4-byte-aligned
        // timelimit -- the trap docs/PLAN.md's Wave 6.5 row flags.
        #expect(Int(L.offPlayerName) == 0)
        #expect(Int(L.offMapName) == 16)
        #expect(Int(L.offPort) == 48)
        #expect(Int(L.offGameType) == 50)
        #expect(Int(L.offTimeLimit) == 52)
        #expect(Int(L.offPassReq) == 56)
        #expect(Int(L.offNPlayers) == 57)
        #expect(Int(L.offAllowJoin) == 58)
        #expect(Int(L.offPause) == 59)
        #expect(Int(L.sizeofTrackerHost) == 60)

        // TrackerHostList (tracker.h:53-56): in_addr(4) + BoloNet.TrackerHost(60) = 64.
        #expect(Int(L.offListAddr) == 0)
        #expect(Int(L.offListGame) == 4)
        #expect(Int(L.sizeofTrackerHostList) == 64)

        #expect(Int(L.sizeofTrackerHost) == BoloNet.TrackerHost.wireSize)
        #expect(Int(L.sizeofTrackerHostList) == TrackerHostList.wireSize)
    }

    private func oracleEncode(_ host: BoloNet.TrackerHost, heartbeat: Bool) -> [UInt8] {
        let playerNameBytes = fixedBytes(host.playerName, count: trkPlayerNameLen)
        let mapNameBytes = fixedBytes(host.mapName, count: trkMapNameLen)
        var out = CXBolo.TrackerHost()

        playerNameBytes.withUnsafeBufferPointer { pPtr in
            mapNameBytes.withUnsafeBufferPointer { mPtr in
                if heartbeat {
                    CXBolo.trackerupdate_encode_oracle(
                        pPtr.baseAddress, mPtr.baseAddress,
                        host.port, host.gameType, host.timeLimit,
                        host.passwordRequired ? 1 : 0, host.nPlayers, host.allowJoin ? 1 : 0, host.paused ? 1 : 0,
                        &out
                    )
                } else {
                    CXBolo.trackerhost_encode_oracle(
                        pPtr.baseAddress, mPtr.baseAddress,
                        host.port, host.gameType, host.timeLimit,
                        host.passwordRequired ? 1 : 0, host.nPlayers, host.allowJoin ? 1 : 0, host.paused ? 1 : 0,
                        &out
                    )
                }
            }
        }
        return withUnsafeBytes(of: out) { Array($0) }
    }

    private func randomHost() -> BoloNet.TrackerHost {
        BoloNet.TrackerHost(
            playerName: String((0..<Int.random(in: 0...10)).map { _ in "abcdefgh".randomElement()! }),
            mapName: String((0..<Int.random(in: 0...10)).map { _ in "abcdefgh".randomElement()! }),
            port: UInt16.random(in: 1...65535),
            gameType: 0,
            timeLimit: UInt32.random(in: 0...UInt32.max),
            passwordRequired: Bool.random(),
            nPlayers: UInt8.random(in: 0...16),
            allowJoin: Bool.random(),
            paused: Bool.random()
        )
    }

    @Test func testTrackerHostRegistrationEncodeMatchesOracleFuzzed() {
        for _ in 0..<300 {
            let host = randomHost()
            #expect(host.encode() == oracleEncode(host, heartbeat: false))
        }
    }

    @Test func testTrackerHostHeartbeatEncodeMatchesOracleFuzzed() {
        for _ in 0..<300 {
            let host = randomHost()
            #expect(host.encodeAsHeartbeat() == oracleEncode(host, heartbeat: true))
        }
    }

    /// T-2/D56 -- the real bug: proves the two encodings differ in
    /// exactly the 4 `timeLimit` bytes (byte-swapped in one, not the
    /// other) and agree everywhere else, for a `timeLimit` whose
    /// big-endian and little-endian representations are actually
    /// different (any value that isn't a byte-palindrome).
    @Test func testRegistrationAndHeartbeatEncodingsDifferOnlyInTimeLimitByteOrder() {
        let host = BoloNet.TrackerHost(
            playerName: "Alice", mapName: "TestMap", port: 6000, gameType: 0, timeLimit: 300,
            passwordRequired: true, nPlayers: 3, allowJoin: true, paused: false
        )
        let registration = host.encode()
        let heartbeat = host.encodeAsHeartbeat()
        #expect(registration.count == heartbeat.count)

        let timeLimitRange = 52..<56  // offTimeLimit..<(offTimeLimit + 4)
        #expect(Array(registration[timeLimitRange]) == [0x00, 0x00, 0x01, 0x2C])  // htonl(300), big-endian
        #expect(Array(heartbeat[timeLimitRange]) == [0x2C, 0x01, 0x00, 0x00])  // raw little-endian, the bug

        var registrationWithoutTimeLimit = registration
        registrationWithoutTimeLimit.replaceSubrange(timeLimitRange, with: [0, 0, 0, 0])
        var heartbeatWithoutTimeLimit = heartbeat
        heartbeatWithoutTimeLimit.replaceSubrange(timeLimitRange, with: [0, 0, 0, 0])
        #expect(registrationWithoutTimeLimit == heartbeatWithoutTimeLimit)
    }

    /// T-3, disclosed Swift-safety deviation -- the offset-51 pad byte is
    /// always zero in this port's encoding, unlike the C's own
    /// uninitialized stack byte at the same offset.
    @Test func testEncodePadByteIsAlwaysZero() {
        let host = randomHost()
        #expect(host.encode()[51] == 0)
        #expect(host.encodeAsHeartbeat()[51] == 0)
    }

    @Test func testTrackerHostRoundTrips() {
        for _ in 0..<50 {
            let host = randomHost()
            let decoded = BoloNet.TrackerHost.decode(host.encode())
            #expect(decoded == host)
        }
    }

    @Test func testTrackerHostListDecodesAddrAndGame() {
        let host = randomHost()
        let addr: UInt32 = 0x0100_007F  // an arbitrary opaque 4-byte value, T-9: never re-swapped
        var bytes: [UInt8] = [
            UInt8(addr >> 24), UInt8((addr >> 16) & 0xFF), UInt8((addr >> 8) & 0xFF), UInt8(addr & 0xFF),
        ]
        bytes += host.encode()
        let decoded = TrackerHostList.decode(bytes)
        #expect(decoded?.addr == addr)
        #expect(decoded?.game == host)
    }

    @Test func testTrackerPreambleWireSizeMatchesOracle() {
        #expect(TrackerPreamble.wireSize == Int(CXBolo.preamble_layout_oracle().sizeofTrackerPreamble))
    }
}

// MARK: - trackerHost(hostPlayerName:mapName:port:state:)

@Suite struct TrackerHostFromStateTests {

    @Test func testTrackerHostDerivesFromLiveGameState() {
        var state = GameState()
        state.timeLimit = 600
        state.passwordRequired = true
        state.allowJoin = false
        state.serverPauseTicks = -1
        var connected = PlayerState()
        connected.connected = true
        var notConnected = PlayerState()
        notConnected.connected = false
        state.players = [connected, connected, notConnected]

        let host = trackerHost(hostPlayerName: "Host", mapName: "Arena", port: 5000, state: state)
        #expect(host.playerName == "Host")
        #expect(host.mapName == "Arena")
        #expect(host.port == 5000)
        #expect(host.timeLimit == 600)
        #expect(host.passwordRequired)
        #expect(!host.allowJoin)
        #expect(host.nPlayers == 2)  // only the two `connected` slots count, matching nplayers()'s cntlsock check
        #expect(host.paused)
    }

    @Test func testTrackerHostReadsFiniteServerPauseAsNotPaused() {
        var state = GameState()
        state.serverPauseTicks = 0
        let host = trackerHost(hostPlayerName: "Host", mapName: "Arena", port: 5000, state: state)
        #expect(!host.paused)
    }

    /// D57 -- `UInt32(state.timeLimit)` traps on a negative `Int`, where
    /// the C's own implicit `int`->`uint32_t` conversion inside `htonl()`
    /// never would (`GameState.timeLimit` has no non-negative invariant
    /// enforced anywhere). `trackerHost` uses `truncatingIfNeeded`
    /// instead -- this asserts the actual truncated two's-complement bit
    /// pattern for a genuinely negative input, not merely that no trap
    /// occurs, and not a large-but-positive value that happens not to
    /// trap either way.
    @Test func testTrackerHostTruncatesNegativeTimeLimitInsteadOfTrapping() {
        var state = GameState()
        state.timeLimit = -300
        let host = trackerHost(hostPlayerName: "Host", mapName: "Arena", port: 5000, state: state)
        #expect(host.timeLimit == 0xFFFF_FED4)  // 32-bit two's complement of -300
    }
}

// MARK: - Loopback fake-tracker-daemon harness (Swift-only, no C oracle -- D31)

private enum HarnessError: Error {
    case shortRead
}

private final class ConnectionWaiter: @unchecked Sendable {
    private let lock = NSLock()
    private var pendingConnection: NWConnection?
    private var continuation: CheckedContinuation<NWConnection, Never>?

    func deliver(_ connection: NWConnection) {
        lock.lock()
        if let continuation {
            self.continuation = nil
            lock.unlock()
            continuation.resume(returning: connection)
        } else {
            pendingConnection = connection
            lock.unlock()
        }
    }

    private func takePending() -> NWConnection? {
        lock.lock()
        defer { lock.unlock() }
        if let pendingConnection {
            self.pendingConnection = nil
            return pendingConnection
        }
        return nil
    }

    private func register(_ continuation: CheckedContinuation<NWConnection, Never>) {
        lock.lock()
        if let pendingConnection {
            self.pendingConnection = nil
            lock.unlock()
            continuation.resume(returning: pendingConnection)
        } else {
            self.continuation = continuation
            lock.unlock()
        }
    }

    func wait() async -> NWConnection {
        if let connection = takePending() {
            return connection
        }
        return await withCheckedContinuation { continuation in
            register(continuation)
        }
    }
}

private func receiveExactly(_ connection: NWConnection, _ count: Int) async throws -> [UInt8] {
    try await withCheckedThrowingContinuation { continuation in
        connection.receive(minimumIncompleteLength: count, maximumLength: count) { data, _, _, error in
            if let error {
                continuation.resume(throwing: error)
                return
            }
            guard let data, data.count == count else {
                continuation.resume(throwing: HarnessError.shortRead)
                return
            }
            continuation.resume(returning: Array(data))
        }
    }
}

private func sendBytes(_ connection: NWConnection, _ bytes: [UInt8]) async throws {
    try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
        connection.send(
            content: Data(bytes),
            completion: .contentProcessed { error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume()
                }
            }
        )
    }
}

private func startLoopbackTrackerListener() async throws -> (NWListener, UInt16, ConnectionWaiter) {
    let listener = try NWListener(using: .tcp, on: .any)
    let waiter = ConnectionWaiter()

    listener.newConnectionHandler = { connection in
        connection.start(queue: .main)
        waiter.deliver(connection)
    }

    let port: UInt16 = try await withCheckedThrowingContinuation { continuation in
        nonisolated(unsafe) var resumed = false
        listener.stateUpdateHandler = { state in
            guard !resumed else { return }
            switch state {
            case .ready:
                resumed = true
                continuation.resume(returning: listener.port?.rawValue ?? 0)
            case .failed(let error):
                resumed = true
                continuation.resume(throwing: error)
            default:
                break
            }
        }
        listener.start(queue: .main)
    }
    return (listener, port, waiter)
}

private func sampleGameState() -> GameState {
    var state = GameState()
    state.timeLimit = 300
    state.passwordRequired = false
    state.allowJoin = true
    var p = PlayerState()
    p.connected = true
    state.players = [p]
    return state
}

// MARK: - registerWithTracker loopback tests

@Suite struct TrackerRegistrationTests {

    @Test func testRegisterWithTrackerReturnsNilWhenHostnameIsNil() async throws {
        // T-5 -- `if (server.tracker.hostname)` (server.c:1264): no
        // tracker configured is success, not an error, and no network
        // connection is ever attempted.
        let result = try await registerWithTracker(
            hostname: nil, advertisedPort: 1234, hostPlayerName: "Host", mapName: "Arena", state: sampleGameState()
        )
        #expect(result == nil)
    }

    @Test func testRegisterWithTrackerCompletesFullHandshakeAgainstFakeDaemon() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        async let daemonScript: BoloNet.TrackerHost? = {
            let connection = await waiter.wait()
            let preambleBytes = try await receiveExactly(connection, TrackerPreamble.wireSize)
            guard TrackerPreamble.decode(preambleBytes) != nil else { return nil }
            try await sendBytes(connection, [TrackerVersionStatus.ok.rawValue])

            let requestByte = try await receiveExactly(connection, 1)
            guard requestByte.first == TrackerRequestType.host.rawValue else { return nil }
            let hostBytes = try await receiveExactly(connection, BoloNet.TrackerHost.wireSize)
            let received = BoloNet.TrackerHost.decode(hostBytes)

            try await sendBytes(connection, [TrackerTCPPortStatus.ok.rawValue])
            try await sendBytes(connection, [TrackerUDPPortStatus.ok.rawValue])
            return received
        }()

        let session = try await registerWithTracker(
            hostname: "127.0.0.1", trackerServerPort: port, advertisedPort: 7000, hostPlayerName: "Host", mapName: "Arena", state: sampleGameState()
        )
        let received = try await daemonScript
        defer { session?.cancel() }

        #expect(session != nil)
        #expect(received?.playerName == "Host")
        #expect(received?.mapName == "Arena")
        #expect(received?.port == 7000)
        #expect(received?.nPlayers == 1)
    }

    @Test func testRegisterWithTrackerThrowsBadVersionWhenRejected() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        async let daemonScript: Void = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, TrackerPreamble.wireSize)
            try await sendBytes(connection, [TrackerVersionStatus.error.rawValue])
        }()

        await #expect(throws: TrackerRegistrationError.badVersion) {
            _ = try await registerWithTracker(
                hostname: "127.0.0.1", trackerServerPort: port, advertisedPort: 7000, hostPlayerName: "Host", mapName: "Arena", state: sampleGameState()
            )
        }
        try await daemonScript
    }

    @Test func testRegisterWithTrackerThrowsTCPPortClosedWhenRejected() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        async let daemonScript: Void = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, TrackerPreamble.wireSize)
            try await sendBytes(connection, [TrackerVersionStatus.ok.rawValue])
            _ = try await receiveExactly(connection, 1 + BoloNet.TrackerHost.wireSize)
            try await sendBytes(connection, [TrackerTCPPortStatus.closed.rawValue])
        }()

        await #expect(throws: TrackerRegistrationError.tcpPortClosed) {
            _ = try await registerWithTracker(
                hostname: "127.0.0.1", trackerServerPort: port, advertisedPort: 7000, hostPlayerName: "Host", mapName: "Arena", state: sampleGameState()
            )
        }
        try await daemonScript
    }

    @Test func testRegisterWithTrackerThrowsUDPPortClosedWhenRejected() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        async let daemonScript: Void = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, TrackerPreamble.wireSize)
            try await sendBytes(connection, [TrackerVersionStatus.ok.rawValue])
            _ = try await receiveExactly(connection, 1 + BoloNet.TrackerHost.wireSize)
            try await sendBytes(connection, [TrackerTCPPortStatus.ok.rawValue])
            try await sendBytes(connection, [TrackerUDPPortStatus.closed.rawValue])
        }()

        await #expect(throws: TrackerRegistrationError.udpPortClosed) {
            _ = try await registerWithTracker(
                hostname: "127.0.0.1", trackerServerPort: port, advertisedPort: 7000, hostPlayerName: "Host", mapName: "Arena", state: sampleGameState()
            )
        }
        try await daemonScript
    }

    @Test func testSendHeartbeatSendsBareHeartbeatEncodingWithNoRequestByte() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        async let daemonScript: [UInt8] = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, TrackerPreamble.wireSize)
            try await sendBytes(connection, [TrackerVersionStatus.ok.rawValue])
            _ = try await receiveExactly(connection, 1 + BoloNet.TrackerHost.wireSize)
            try await sendBytes(connection, [TrackerTCPPortStatus.ok.rawValue])
            try await sendBytes(connection, [TrackerUDPPortStatus.ok.rawValue])
            // sendtrackerupdate() sends a BARE BoloNet.TrackerHost -- no request
            // byte -- so reading exactly wireSize bytes next confirms
            // that shape.
            return try await receiveExactly(connection, BoloNet.TrackerHost.wireSize)
        }()

        let state = sampleGameState()
        let session = try await registerWithTracker(
            hostname: "127.0.0.1", trackerServerPort: port, advertisedPort: 7000, hostPlayerName: "Host", mapName: "Arena", state: state
        )
        let heartbeatHost = trackerHost(hostPlayerName: "Host", mapName: "Arena", port: 7000, state: state)
        try await session?.sendHeartbeat(heartbeatHost)
        defer { session?.cancel() }

        let received = try await daemonScript
        #expect(received == heartbeatHost.encodeAsHeartbeat())
    }
}

// MARK: - listTrackerGames loopback tests

@Suite struct TrackerBrowserTests {

    @Test func testListTrackerGamesReturnsEmptyListWhenDaemonReportsZero() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        async let daemonScript: Void = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, TrackerPreamble.wireSize)
            try await sendBytes(connection, [TrackerVersionStatus.ok.rawValue])
            let requestByte = try await receiveExactly(connection, 1)
            #expect(requestByte.first == TrackerRequestType.list.rawValue)
            try await sendBytes(connection, [0, 0, 0, 0])  // ntohl(0) games
        }()

        let games = try await listTrackerGames(hostname: "127.0.0.1", port: port)
        try await daemonScript
        #expect(games.isEmpty)
    }

    @Test func testListTrackerGamesDecodesMultipleEntries() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        let hostA = BoloNet.TrackerHost(
            playerName: "Alice", mapName: "IslandA", port: 6001, gameType: 0, timeLimit: 300,
            passwordRequired: false, nPlayers: 2, allowJoin: true, paused: false
        )
        let hostB = BoloNet.TrackerHost(
            playerName: "Bob", mapName: "IslandB", port: 6002, gameType: 0, timeLimit: 0,
            passwordRequired: true, nPlayers: 5, allowJoin: false, paused: true
        )

        async let daemonScript: Void = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, TrackerPreamble.wireSize)
            try await sendBytes(connection, [TrackerVersionStatus.ok.rawValue])
            _ = try await receiveExactly(connection, 1)
            try await sendBytes(connection, [0, 0, 0, 2])  // ntohl(2) games
            try await sendBytes(connection, [0, 0, 0, 1] + hostA.encode())
            try await sendBytes(connection, [0, 0, 0, 2] + hostB.encode())
        }()

        let games = try await listTrackerGames(hostname: "127.0.0.1", port: port)
        try await daemonScript

        #expect(games.count == 2)
        #expect(games[0].addr == 1)
        #expect(games[0].game == hostA)
        #expect(games[1].addr == 2)
        #expect(games[1].game == hostB)
    }

    @Test func testListTrackerGamesThrowsBadVersionWhenRejected() async throws {
        let (listener, port, waiter) = try await startLoopbackTrackerListener()
        defer { listener.cancel() }

        async let daemonScript: Void = {
            let connection = await waiter.wait()
            _ = try await receiveExactly(connection, TrackerPreamble.wireSize)
            try await sendBytes(connection, [TrackerVersionStatus.error.rawValue])
        }()

        await #expect(throws: TrackerBrowseError.badVersion) {
            _ = try await listTrackerGames(hostname: "127.0.0.1", port: port)
        }
        try await daemonScript
    }
}
