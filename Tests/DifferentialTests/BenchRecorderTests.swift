import Foundation
import Testing
import BoloKit
import BoloNet

// v1.6.9 baseline benchmark: the recorder is the instrument, so what it writes must read back
// exactly, it must say when it lost something, and it must stay off unless asked for.

private func temporaryLog() -> URL {
    FileManager.default.temporaryDirectory
        .appendingPathComponent("bolo-bench-tests-\(UUID().uuidString)", isDirectory: true)
        .appendingPathComponent("host-0.jsonl")
}

private func lines(_ url: URL) throws -> [Substring] {
    try String(contentsOf: url, encoding: .utf8).split(separator: "\n")
}

@Test func recorderIsOffUnlessTheProcessWasStartedWithBoloBench() {
    #expect(ProcessInfo.processInfo.environment["BOLO_BENCH"] != "1")
    #expect(BoloBench.recorder == nil)
}

@Test func recordsReadBackExactly() throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "host", runID: "t")

    let written = [
        BenchRecord(time: 10, kind: .tick, id: 7, v0: 1_500, v1: 2),
        BenchRecord(time: 11, kind: .phase, sub: BenchPhase.fog.rawValue, id: 7, v0: 420),
        BenchRecord(time: 12, kind: .send, sub: BenchChannel.tcp.rawValue, id: 35, v0: 31, v1: 1),
        BenchRecord(time: .max, kind: .state, sub: 255, id: .max, v0: .max, v1: .max),
    ]
    for record in written {
        recorder.record(
            BenchKind(rawValue: record.kind)!, sub: record.sub, id: record.id, v0: record.v0, v1: record.v1,
            at: record.time
        )
    }
    recorder.finish()

    let all = try lines(url)
    #expect(all.count == written.count + 1)
    #expect(BenchRecorder.parse(all[0]) == nil)
    #expect(all.dropFirst().compactMap { BenchRecorder.parse($0) } == written)
}

@Test func headerIdentifiesTheRunAndTheMachine() throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "join", runID: "run-42")
    recorder.finish()

    let first = try #require(try lines(url).first)
    let header = try #require(try JSONSerialization.jsonObject(with: Data(first.utf8)) as? [String: Any])
    #expect(header["type"] as? String == "header")
    #expect(header["schema"] as? Int == BoloBench.schemaVersion)
    #expect(header["role"] as? String == "join")
    #expect(header["runId"] as? String == "run-42")
    #expect((header["model"] as? String)?.isEmpty == false)
    #expect((header["osBuild"] as? String)?.isEmpty == false)
    #expect((header["mono"] as? UInt64 ?? 0) > 0)
}

@Test func aFullRingCountsWhatItDropsInsteadOfOverwriting() throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "host", runID: "t", capacity: 4)
    for index in 0..<10 { recorder.record(.mark, id: UInt32(index), at: UInt64(index)) }
    #expect(recorder.droppedRecords == 6)
    recorder.flush()
    recorder.record(.mark, id: 99, at: 99)
    recorder.finish()

    let ids = try lines(url).compactMap { BenchRecorder.parse($0) }.map(\.id)
    #expect(ids == [0, 1, 2, 3, 99])
}

@Test func stateChangesAreLoggedWithTheirViewer() throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "host", runID: "t")
    recorder.changes([DigestChange(domain: .pills, element: 3, value: 77)], view: 1, at: 5)
    recorder.finish()

    let records = try lines(url).compactMap { BenchRecorder.parse($0) }
    #expect(
        records
            == [BenchRecord(time: 5, kind: .state, sub: DigestDomain.pills.rawValue, id: 3, v0: 77, v1: 1)]
    )
}

// How the sandboxed app is given its log: the launcher opens the file and passes the descriptor.
@Test func aRecorderCanWriteToADescriptorItWasHanded() throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
    let descriptor = open(url.path, O_WRONLY | O_CREAT | O_TRUNC, 0o644)
    try #require(descriptor > 2)
    defer { close(descriptor) }

    let recorder = try BenchRecorder(
        handle: FileHandle(fileDescriptor: descriptor, closeOnDealloc: false), role: "host", runID: "t"
    )
    #expect(recorder.url == nil)
    recorder.record(.mark, id: 5, at: 9)
    recorder.flush()

    let all = try lines(url)
    #expect(all.count == 2)
    #expect(all.last.flatMap { BenchRecorder.parse($0) } == BenchRecord(time: 9, kind: .mark, id: 5))
}

// The recorder's own cost is timed from the call, not from the timestamp being recorded: a
// record stamped long ago must not look like a slow call.
@Test func selfTimeIsTheCostOfRecordingNotTheAgeOfTheRecord() throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "host", runID: "t")
    let longAgo = BoloBench.now() &- 60_000_000_000
    let started = BoloBench.now()
    for index in 0..<6_400 { recorder.record(.state, id: UInt32(index), at: longAgo) }
    let elapsed = BoloBench.now() &- started
    recorder.finish()

    #expect(recorder.estimatedSelfTime > 0)
    // An estimate from one call in 64, so allow it some slack over the measured total.
    #expect(recorder.estimatedSelfTime <= elapsed &* 4)
}

@Test func timestampsComeFromOneMonotonicClock() {
    let first = BoloBench.now()
    let second = BoloBench.now()
    #expect(second >= first)
    #expect(first > 0)
}

// Records concurrently from several threads; every record must arrive exactly once.
@Test func concurrentRecordingLosesAndDuplicatesNothing() async throws {
    let url = temporaryLog()
    defer { try? FileManager.default.removeItem(at: url.deletingLastPathComponent()) }
    let recorder = try BenchRecorder(url: url, role: "host", runID: "t")
    let writers = 8
    let each = 5_000

    await withTaskGroup(of: Void.self) { group in
        for writer in 0..<writers {
            group.addTask {
                for index in 0..<each {
                    recorder.record(.mark, sub: UInt8(writer), id: UInt32(index))
                }
            }
        }
    }
    recorder.finish()

    let records = try lines(url).compactMap { BenchRecorder.parse($0) }
    #expect(records.count == writers * each)
    #expect(recorder.droppedRecords == 0)
    for writer in 0..<writers {
        let ids = records.filter { $0.sub == UInt8(writer) }.map(\.id)
        #expect(ids == Array(0..<UInt32(each)))
    }
}
