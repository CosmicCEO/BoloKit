import Foundation
import Testing
import BoloKit
import BoloNet

// v1.6.9 baseline benchmark: the probes turn what the transport did into records, so each
// must report the same numbers the transport itself used.

private func withRecorder(_ body: (BenchRecorder) -> Void) throws -> [BenchRecord] {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("bolo-bench-probes-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("join-0.jsonl")
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "join", runID: "t")
    body(recorder)
    recorder.finish()
    return try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap { BenchRecorder.parse($0) }
}

private func update(player: Int, seq: [Int32]) -> CLUpdate {
    var state = GameState()
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    return assembleClUpdate(player: player, state: state, seq: seq.map { UInt32(bitPattern: $0) })
}

@Test func aSentDatagramIsStampedWithItsSendersOwnSequenceNumber() throws {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[0] = 40
    seq[1] = 125
    let bytes = update(player: 1, seq: seq).encode()
    let records = try withRecorder { $0.datagramSent(bytes) }
    #expect(records == [BenchRecord(time: records.first?.time ?? 0, kind: .datagram, sub: 0, id: 1, v0: 125)])
}

@Test func aReceivedDatagramCarriesTheSendersSequenceAndItsEchoOfOurs() throws {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[0] = 300
    seq[1] = 120
    let header = update(player: 0, seq: seq).header
    let records = try withRecorder { $0.datagram(sent: false, header: header, local: 1) }
    #expect(records.map(\.sub) == [1])
    #expect(records.first?.id == 0)
    #expect(records.first?.v0 == 300)
    #expect(records.first?.v1 == 120)
}

@Test func extrapolationMatchesTheDeadReckoningRule() throws {
    var seq = [Int32](repeating: 0, count: maxPlayers)
    seq[1] = 100
    let header = update(player: 0, seq: seq).header

    // Half the gap between our sequence number and the one echoed back.
    #expect(try withRecorder { $0.extrapolation(header: header, myOwnSeq: 110, local: 1) }.first?.v0 == 5)
    // Never negative.
    #expect(try withRecorder { $0.extrapolation(header: header, myOwnSeq: 90, local: 1) }.first?.v0 == 0)
    // Capped.
    #expect(
        try withRecorder { $0.extrapolation(header: header, myOwnSeq: 10_000, local: 1) }.first?.v0
            == UInt64(maxDeadReckoningExtrapolationTicks)
    )
    // Nothing is extrapolated until the sender has acknowledged one of our updates.
    seq[1] = 0
    let unacknowledged = update(player: 0, seq: seq).header
    #expect(try withRecorder { $0.extrapolation(header: unacknowledged, myOwnSeq: 110, local: 1) }.isEmpty)
}

@Test func aSendIsRecordedWithItsSizeAndThenItsCompletion() throws {
    let records = try withRecorder { recorder in
        let send = BenchSend([35, 1, 2, 3], channel: .tcp, recipient: 1, recorder: recorder)
        send.done()
    }
    #expect(records.map(\.kind) == [BenchKind.send.rawValue, BenchKind.sendDone.rawValue])
    #expect(records[0].id == 35 && records[0].v0 == 4 && records[0].v1 == 1)
    #expect(records[1].id == 35)
    #expect(records[1].time >= records[0].time)
    #expect(records[1].v0 == records[1].time - records[0].time)
}

@Test func probesWithoutARecorderDoNothing() {
    let send = BenchSend([1], channel: .udp, recipient: 0, recorder: nil)
    send.done()
    BenchApply(channel: .udp, opcode: 0, recorder: nil).done()
    var lap = BenchLap(recorder: nil, tick: 1)
    lap.mark(.runTick)
    lap.finish()
}

@Test func valuesOutsideTheirLegalRangeAreRecordedAndLegalOnesAreNot() throws {
    var state = GameState()
    state.players = (0..<maxPlayers).map { _ in PlayerState() }
    state.localStats[1].armour = maxArmour
    state.localStats[1].shells = maxShells + 1
    state.players[1].mines = -1
    let records = try withRecorder { $0.checkInvariants(player: 1, state: state) }
    #expect(records.map(\.sub) == [BenchInvariant.shells.rawValue, BenchInvariant.mines.rawValue])
    #expect(records.first?.v0 == UInt64(maxShells + 1))
    #expect(records.last.map { Int64(bitPattern: $0.v0) } == -1)
}
