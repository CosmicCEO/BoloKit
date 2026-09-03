import Testing
import BoloKit
import BoloNet
import CXBolo

// Tests for `decodeDgramServerRelay` (Wave 6.4b) -- ported from
// `dgramserver()`'s pure per-packet decision core (`server.c:614-696`).
// Combines Swift-only unit tests for each named trap (T-1 through T-8 in
// the pre-brief) with a fuzz-differential harness against
// `dgramserver_relay_oracle` (`Sources/CXBolo/netops.c`).

private func connectedPlayer(family: UInt8 = 1, addr: UInt32 = 100, port: UInt16 = 5000, seq: Int32 = 0)
    -> DgramServerPlayerSessionState {
    DgramServerPlayerSessionState(
        used: true, connected: true,
        dgramAddress: DgramServerPeerAddress(family: family, addr: addr, port: port), seq: seq
    )
}

private func disconnectedSlot() -> DgramServerPlayerSessionState {
    DgramServerPlayerSessionState(used: false, connected: false, dgramAddress: DgramServerPeerAddress(family: 0, addr: 0, port: 0), seq: 0)
}

private func fullTable(_ overrides: [Int: DgramServerPlayerSessionState]) -> [DgramServerPlayerSessionState] {
    var table = (0..<maxPlayers).map { _ in disconnectedSlot() }
    for (i, p) in overrides { table[i] = p }
    return table
}

private func sampleHeader(player: UInt8, seq: [Int32], tank: Vec2f = Vec2f(x: 12, y: 34)) -> CLUpdateHeader {
    CLUpdateHeader(
        player: player, seq: seq, dead: false, boat: false, dir: 0, tank: tank, speed: 0, turnSpeed: 0,
        kickDir: 0, kickSpeed: 0, builderStatus: 0, builder: Vec2f(x: 0, y: 0),
        builderTargetX: 0, builderTargetY: 0, builderWait: 0, inputFlags: 0,
        tankShotSound: false, pillShotSound: false, sinkSound: false, builderDeathSound: false
    )
}

private let matchingAddress = DgramServerPeerAddress(family: 1, addr: 100, port: 5000)

// MARK: - Tracker echo (T-4, T-5)

@Test func trackerEchoDetectedBeforeAnyDecodeAttempt() {
    var bytes = [UInt8](repeating: 0, count: CLUpdateHeader.wireSize)
    bytes[0] = 255  // player == 255 -- would fail CLUpdate.decode's own player < maxPlayers guard
    let decision = decodeDgramServerRelay(bytes, from: matchingAddress, players: fullTable([:]))
    #expect(decision == .trackerEcho)
}

@Test func nonTrackerLengthDatagramWithPlayer255FallsThroughToMalformed() {
    // Wrong length for the tracker-echo shape (one extra byte) -- must be
    // treated as an ordinary malformed packet, not an echo.
    var bytes = [UInt8](repeating: 0, count: CLUpdateHeader.wireSize + 1)
    bytes[0] = 255
    let decision = decodeDgramServerRelay(bytes, from: matchingAddress, players: fullTable([:]))
    #expect(decision == .malformed)
}

// MARK: - Malformed (T-6)

@Test func tooShortDatagramIsMalformed() {
    let decision = decodeDgramServerRelay([1, 2, 3], from: matchingAddress, players: fullTable([:]))
    #expect(decision == .malformed)
}

// MARK: - Invalid player (T-3)

@Test func unusedPlayerSlotIsDropped() {
    let header = sampleHeader(player: 0, seq: [Int32](repeating: 0, count: maxPlayers))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()
    let decision = decodeDgramServerRelay(bytes, from: matchingAddress, players: fullTable([0: disconnectedSlot()]))
    #expect(decision == .dropped)
}

@Test func addressFamilyMismatchIsDropped() {
    let header = sampleHeader(player: 0, seq: [Int32](repeating: 0, count: maxPlayers))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()
    let players = fullTable([0: connectedPlayer(family: 2)])  // stored family != matchingAddress.family
    #expect(decodeDgramServerRelay(bytes, from: matchingAddress, players: players) == .dropped)
}

@Test func addressMismatchIsDropped() {
    let header = sampleHeader(player: 0, seq: [Int32](repeating: 0, count: maxPlayers))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()
    let players = fullTable([0: connectedPlayer(addr: 999)])  // stored addr != matchingAddress.addr
    #expect(decodeDgramServerRelay(bytes, from: matchingAddress, players: players) == .dropped)
}

/// T-3's actual point: a PORT mismatch alone must NOT invalidate the
/// sender -- only family+addr are checked for validity, the port is
/// refreshed from every accepted packet instead.
@Test func portMismatchAloneDoesNotInvalidateTheSender() {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[0] = 1
    let header = sampleHeader(player: 0, seq: seq)
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()
    let differentPortAddress = DgramServerPeerAddress(family: 1, addr: 100, port: 9999)
    let players = fullTable([0: connectedPlayer(port: 5000, seq: 0)])
    guard case .applied(let player, _, _, let portUpdate, _) = decodeDgramServerRelay(bytes, from: differentPortAddress, players: players) else {
        Issue.record("expected .applied")
        return
    }
    #expect(player == 0)
    #expect(portUpdate == 9999)
}

// MARK: - Stale seq (T-7)

@Test func staleSeqDropsAndDoesNotEvenRefreshThePort() {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[0] = 5
    let header = sampleHeader(player: 0, seq: seq)
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()
    // Stored seq (10) is already newer than the incoming seq (5).
    let differentPortAddress = DgramServerPeerAddress(family: 1, addr: 100, port: 9999)
    let players = fullTable([0: connectedPlayer(port: 5000, seq: 10)])
    #expect(decodeDgramServerRelay(bytes, from: differentPortAddress, players: players) == .dropped)
}

// MARK: - Applied: tank apply (T-2) + relay set (T-8)

@Test func appliedUpdateCarriesOnlyTankPositionAndRelaysToConnectedNonSenders() {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[1] = 7
    let header = sampleHeader(player: 1, seq: seq, tank: Vec2f(x: 42, y: 99))
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()

    let players = fullTable([
        0: connectedPlayer(),  // should be relayed to
        1: connectedPlayer(),  // sender -- excluded from relay
        2: disconnectedSlot(),  // not connected -- excluded from relay
    ])

    guard case .applied(let player, let tank, let newSeq, _, let relayTo) = decodeDgramServerRelay(bytes, from: matchingAddress, players: players) else {
        Issue.record("expected .applied")
        return
    }
    #expect(player == 1)
    #expect(tank == Vec2f(x: 42, y: 99))
    #expect(newSeq == 7)
    #expect(relayTo == [0])
}

/// T-8's other half: the relay predicate does NOT check `used` -- a slot
/// that's `connected` but (in some hypothetical future state) not `used`
/// still receives the relay.
@Test func relayPredicateIgnoresUsedOnRecipients() {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[1] = 1
    let header = sampleHeader(player: 1, seq: seq)
    let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()

    var recipient = connectedPlayer()
    recipient.used = false  // connected but not used
    let players = fullTable([0: recipient, 1: connectedPlayer()])

    guard case .applied(_, _, _, _, let relayTo) = decodeDgramServerRelay(bytes, from: matchingAddress, players: players) else {
        Issue.record("expected .applied")
        return
    }
    #expect(relayTo == [0])
}

// MARK: - Fuzz differential test against dgramserver_relay_oracle

private func randomPlayerState() -> DgramServerPlayerSessionState {
    DgramServerPlayerSessionState(
        used: Bool.random(), connected: Bool.random(),
        dgramAddress: DgramServerPeerAddress(
            family: UInt8.random(in: 0...2), addr: UInt32.random(in: 90...110), port: UInt16.random(in: 4990...5010)
        ),
        seq: Int32.random(in: -5...5)
    )
}

private func cPlayerState(_ p: DgramServerPlayerSessionState) -> CXBolo.DgramServerPlayerState {
    CXBolo.DgramServerPlayerState(
        used: p.used ? 1 : 0, connected: p.connected ? 1 : 0,
        dgramFamily: p.dgramAddress.family, dgramAddr: p.dgramAddress.addr, dgramPort: p.dgramAddress.port,
        seq: UInt32(bitPattern: p.seq)
    )
}

private func oracleDecide(
    bytes: [UInt8], address: DgramServerPeerAddress, players: [DgramServerPlayerSessionState]
) -> (result: CXBolo.DgramServerRelayResult, relayTo: [Int]) {
    let cPlayers = players.map(cPlayerState)
    var result = CXBolo.DgramServerRelayResult()
    var relayToBuf = [Int32](repeating: -1, count: maxPlayers)
    var relayCount: Int32 = 0

    bytes.withUnsafeBufferPointer { bytesPtr in
        cPlayers.withUnsafeBufferPointer { playersPtr in
            relayToBuf.withUnsafeMutableBufferPointer { relayPtr in
                CXBolo.dgramserver_relay_oracle(
                    bytesPtr.baseAddress, bytes.count,
                    address.family, address.addr, address.port,
                    playersPtr.baseAddress, &result,
                    relayPtr.baseAddress, &relayCount
                )
            }
        }
    }
    return (result, relayToBuf.prefix(Int(relayCount)).map(Int.init))
}

@Test func decodeDgramServerRelayMatchesOracleFuzzed() {
    for _ in 0..<300 {
        let players = (0..<maxPlayers).map { _ in randomPlayerState() }
        let address = DgramServerPeerAddress(
            family: UInt8.random(in: 0...2), addr: UInt32.random(in: 90...110), port: UInt16.random(in: 4990...5010)
        )

        let bytes: [UInt8]
        switch Int.random(in: 0...3) {
        case 0:
            // Well-formed CLUpdate for a random (possibly invalid) player.
            var seq = (0..<maxPlayers).map { _ in Int32.random(in: -3...3) }
            let player = UInt8.random(in: 0..<UInt8(maxPlayers))
            let header = sampleHeader(player: player, seq: seq)
            bytes = CLUpdate(header: header, shells: [], explosions: []).encode()
            seq.removeAll()  // silence unused-mutation warning path; seq already captured by header
        case 1:
            // Tracker-echo shape.
            var b = [UInt8](repeating: UInt8.random(in: 0...255), count: CLUpdateHeader.wireSize)
            b[0] = 255
            bytes = b
        case 2:
            // Malformed: too short.
            bytes = [UInt8](repeating: 0, count: Int.random(in: 0..<CLUpdateHeader.wireSize))
        default:
            // Malformed: right header size but garbage nshells/nexplosions
            // making the declared total length not match `bytes.count`.
            var b = [UInt8](repeating: 0, count: CLUpdateHeader.wireSize)
            b[111] = UInt8.random(in: 1...5)  // offNShells, claims shells that aren't present
            bytes = b
        }

        let swiftDecision = decodeDgramServerRelay(bytes, from: address, players: players)
        let (oracleResult, oracleRelayTo) = oracleDecide(bytes: bytes, address: address, players: players)

        if oracleResult.isTrackerEcho != 0 {
            #expect(swiftDecision == .trackerEcho, "tracker echo mismatch")
        } else if oracleResult.isMalformed != 0 {
            #expect(swiftDecision == .malformed, "malformed mismatch")
        } else if oracleResult.isValidPlayer == 0 || oracleResult.isNewerSeq == 0 {
            #expect(swiftDecision == .dropped, "dropped mismatch, player=\(oracleResult.player)")
        } else {
            guard case .applied(let player, let tank, let newSeq, let portUpdate, let relayTo) = swiftDecision else {
                Issue.record("expected .applied to match oracle's accepted case")
                continue
            }
            #expect(player == Int(oracleResult.player))
            #expect(tank.x.bitPattern == oracleResult.tankXRaw)
            #expect(tank.y.bitPattern == oracleResult.tankYRaw)
            #expect(newSeq == Int32(bitPattern: oracleResult.decodedSeq))
            if oracleResult.portChanged != 0 {
                #expect(portUpdate == oracleResult.newPort)
            } else {
                #expect(portUpdate == nil)
            }
            #expect(Set(relayTo) == Set(oracleRelayTo), "relay set mismatch")
        }
    }
}
