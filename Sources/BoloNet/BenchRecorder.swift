import BoloKit
import Darwin
import Foundation
import os

// MARK: - Benchmark recorder (v1.6.9 baseline benchmark)
//
// Measurement only: no gameplay effect and nothing sent over the wire. Always compiled, off
// unless the process is started with `BOLO_BENCH=1`; every call site is
// `BoloBench.recorder?.record(...)`, so the off path is one nil check.
//
// Each process writes raw timestamped facts to its own JSONL file and nothing is compared
// live. `BoloBench analyze` lines the host and guest files up afterwards. Timestamps are
// `CLOCK_UPTIME_RAW` nanoseconds, which is one clock for every process on the machine.

/// What a record describes. Raw values are part of the log format; never renumber.
///
/// Field use per kind (`sub`, `id`, `v0`, `v1`). A position update has no opcode: its first
/// byte is the sender's player slot, so that is what `id` holds on the UDP channel.
public enum BenchKind: UInt8, Sendable, CaseIterable {
    /// Tick handler entry. `id` tick ordinal. Queue delay and depth are worked out afterwards
    /// from this, `timerFire` and `receive`/`apply`.
    case tick = 1
    /// One phase of a tick. `sub` `BenchPhase`, `id` tick ordinal, `v0` duration ns.
    case phase = 2
    /// Send call. `sub` `BenchChannel`, `id` first payload byte, `v0` bytes, `v1` recipient.
    case send = 3
    /// Send completed. `sub` `BenchChannel`, `id` first payload byte, `v0` call-to-completion ns.
    case sendDone = 4
    /// Message received. `sub` `BenchChannel`, `id` first payload byte, `v0` bytes, `v1` sender.
    case receive = 5
    /// Message handled. `sub` `BenchChannel`, `id` first payload byte, `v0` duration ns,
    /// `v1` the part of it spent in the state change itself when timed separately.
    case apply = 6
    /// Datagram sequence stamp. `sub` 0 sent / 1 received, `id` sender's player slot,
    /// `v0` sender's sequence number, `v1` the echoed sequence number of the other side.
    case datagram = 7
    /// State element changed. `sub` `DigestDomain`, `id` element, `v0` value, `v1` whose view.
    case state = 8
    /// Frame drawn. `sub` 0 sprite pass / 1 Metal terrain, `id` render generation, `v0` duration ns.
    case frame = 9
    /// Scripted input injected. `sub` `BenchInput`, `id` step index, `v0` set, `v1` cleared.
    case input = 10
    /// Scenario progress. `sub` `BenchMark`, `id` step index.
    case mark = 11
    /// Datagram refused. `sub` `BenchReject`, `id` player slot or 0xffff_ffff.
    case reject = 12
    /// Once a second. `sub` thermal state, `v0` cumulative CPU ns, `v1` memory footprint bytes.
    case process = 13
    /// Join handshake. `sub` 0 begin / 1 end, `id` player slot, `v0` duration ns on end.
    case join = 14
    /// Value outside its legal range. `sub` `BenchInvariant`, `id` player slot, `v0` value.
    case invariant = 15
    /// Dead-reckoning ticks run for one datagram. `id` sender's player slot, `v0` ticks.
    case extrapolation = 16
    /// State handed to the renderer. `id` render generation, `v0` tick ordinal.
    case renderState = 17
    /// Tile grid rebuilt. `v0` duration ns.
    case rebuild = 18
    /// The recorder's own cost, once a second. `id` records written (wrapping),
    /// `v0` cumulative estimated ns inside `record`, `v1` cumulative records dropped.
    case recorder = 19
    /// Tick timer fired.
    case timerFire = 20
}

public enum BenchChannel: UInt8, Sendable {
    case tcp = 0
    case udp = 1
}

/// Host and guest share the numbering; each uses the phases it has.
public enum BenchPhase: UInt8, Sendable, CaseIterable {
    case whole = 0
    case prepare = 1
    case runTick = 2
    case terrainDiff = 3
    case status = 4
    case fog = 5
    case sendFlush = 6
    case renderHop = 7
    case updateSend = 8
    case move = 9
    case builder = 10
    case shells = 11
    case explosions = 12
    case digest = 13
}

public enum BenchInput: UInt8, Sendable {
    case flags = 0
    case layMine = 1
    case builder = 2
}

public enum BenchMark: UInt8, Sendable {
    case scenarioStart = 0
    case stepReached = 1
    case stepTimedOut = 2
    case scenarioEnd = 3
    case custom = 4
    case hostingFellBack = 5
    case joined = 6
    case spawned = 7
}

public enum BenchReject: UInt8, Sendable {
    case noPeer = 0
    case malformed = 1
    case dropped = 2
    case applyReturnedNil = 3
}

public enum BenchInvariant: UInt8, Sendable {
    case armour = 0
    case shells = 1
    case mines = 2
    case fogCount = 3
}

public struct BenchRecord: Sendable, Equatable {
    public var time: UInt64
    public var v0: UInt64
    public var v1: UInt64
    public var id: UInt32
    public var kind: UInt8
    public var sub: UInt8

    public init(time: UInt64, kind: BenchKind, sub: UInt8 = 0, id: UInt32 = 0, v0: UInt64 = 0, v1: UInt64 = 0) {
        self.time = time
        self.v0 = v0
        self.v1 = v1
        self.id = id
        self.kind = kind.rawValue
        self.sub = sub
    }
}

public enum BoloBench {
    public static let schemaVersion = 1

    /// `nil` unless the process was started with `BOLO_BENCH=1`.
    public static let recorder: BenchRecorder? = {
        let environment = ProcessInfo.processInfo.environment
        guard environment["BOLO_BENCH"] == "1" else { return nil }
        let runID = environment["BOLO_BENCH_RUN_ID"] ?? "run-\(Int(Date().timeIntervalSince1970))"
        let role = environment["BOLO_BENCH_ROLE"] ?? "unknown"
        let directory: URL
        if let out = environment["BOLO_BENCH_OUT"], !out.isEmpty {
            directory = URL(fileURLWithPath: out, isDirectory: true)
        } else {
            let support = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
                ?? URL(fileURLWithPath: NSTemporaryDirectory(), isDirectory: true)
            directory = support.appendingPathComponent("BoloBench", isDirectory: true)
        }
        let file = directory.appendingPathComponent(runID, isDirectory: true)
            .appendingPathComponent("\(role)-\(getpid()).jsonl")
        return try? BenchRecorder(
            url: file, role: role, runID: runID, samplesProcess: true,
            recordsState: environment["BOLO_BENCH_STATE"] != "0"
        )
    }()

    /// Nanoseconds on the machine-wide monotonic clock.
    @inlinable public static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
}

public final class BenchRecorder: @unchecked Sendable {
    public static let defaultCapacity = 1 << 19

    public let url: URL
    public let role: String
    public let runID: String
    /// Off for the scaling sweep (`BOLO_BENCH_STATE=0`), which measures host cost only.
    public let recordsState: Bool

    private let capacity: Int
    private let lock = OSAllocatedUnfairLock()
    // Guarded by `lock`.
    private var filling: UnsafeMutablePointer<BenchRecord>
    private var count = 0
    private var written: UInt64 = 0
    private var dropped: UInt64 = 0
    private var selfTime: UInt64 = 0

    // Touched only on `writerQueue`.
    private var draining: UnsafeMutablePointer<BenchRecord>
    private var handle: FileHandle?
    private var timer: DispatchSourceTimer?
    private var drainsSinceSample = 0
    private let writerQueue = DispatchQueue(label: "com.cosmicceo.Bolo-2026.bench", qos: .utility)

    private static let drainsPerSecond = 4
    /// One call in this many times itself, so the estimate costs one extra clock read in 64.
    private static let selfTimeSampling: UInt64 = 64

    public init(
        url: URL, role: String, runID: String, capacity: Int = BenchRecorder.defaultCapacity,
        samplesProcess: Bool = false, recordsState: Bool = true
    ) throws {
        self.url = url
        self.role = role
        self.runID = runID
        self.recordsState = recordsState
        self.capacity = max(capacity, 1)
        filling = .allocate(capacity: self.capacity)
        draining = .allocate(capacity: self.capacity)

        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(), withIntermediateDirectories: true
        )
        guard FileManager.default.createFile(atPath: url.path, contents: nil) else {
            throw CocoaError(.fileWriteUnknown)
        }
        handle = try FileHandle(forWritingTo: url)
        try handle?.write(contentsOf: Data((Self.headerLine(role: role, runID: runID) + "\n").utf8))

        let source = DispatchSource.makeTimerSource(queue: writerQueue)
        let interval = 1.0 / Double(Self.drainsPerSecond)
        source.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(50))
        source.setEventHandler { [weak self] in self?.drain(sampleProcess: samplesProcess) }
        source.resume()
        timer = source
    }

    deinit {
        timer?.cancel()
        try? handle?.close()
        filling.deallocate()
        draining.deallocate()
    }

    // MARK: Recording

    public func record(
        _ kind: BenchKind, sub: UInt8 = 0, id: UInt32 = 0, v0: UInt64 = 0, v1: UInt64 = 0,
        at time: UInt64 = BoloBench.now()
    ) {
        let sampled: Bool = lock.withLockUnchecked {
            guard count < capacity else {
                dropped &+= 1
                return false
            }
            filling[count] = BenchRecord(time: time, kind: kind, sub: sub, id: id, v0: v0, v1: v1)
            count += 1
            written &+= 1
            return written % Self.selfTimeSampling == 0
        }
        if sampled {
            let spent = BoloBench.now() &- time
            lock.withLockUnchecked { selfTime &+= spent &* Self.selfTimeSampling }
        }
    }

    /// `record(.phase, ...)` for an interval that started at `start` and ends now.
    public func phase(_ phase: BenchPhase, tick: UInt32, since start: UInt64) {
        let end = BoloBench.now()
        record(.phase, sub: phase.rawValue, id: tick, v0: end &- start, at: end)
    }

    public func changes(_ changes: [DigestChange], view player: Int, at time: UInt64 = BoloBench.now()) {
        for change in changes {
            record(
                .state, sub: change.domain.rawValue, id: change.element, v0: change.value,
                v1: UInt64(truncatingIfNeeded: player), at: time
            )
        }
    }

    public var droppedRecords: UInt64 { lock.withLockUnchecked { dropped } }

    // MARK: Writing

    /// Writes everything recorded so far. Returns once it is on disk.
    public func flush() {
        writerQueue.sync { drain(sampleProcess: false) }
    }

    /// Flushes and closes the file. Records made afterwards are counted as dropped.
    public func finish() {
        writerQueue.sync {
            timer?.cancel()
            timer = nil
            drain(sampleProcess: false)
            try? handle?.synchronize()
            try? handle?.close()
            handle = nil
        }
    }

    private func drain(sampleProcess: Bool) {
        if sampleProcess {
            drainsSinceSample += 1
            if drainsSinceSample >= Self.drainsPerSecond {
                drainsSinceSample = 0
                recordProcessSample()
            }
        }
        let taken: Int = lock.withLockUnchecked {
            let taken = count
            swap(&filling, &draining)
            count = 0
            return taken
        }
        guard taken > 0, let handle else { return }
        var text = ""
        text.reserveCapacity(taken * 64)
        for index in 0..<taken { Self.append(draining[index], to: &text) }
        do {
            try handle.write(contentsOf: Data(text.utf8))
        } catch {
            lock.withLockUnchecked { dropped &+= UInt64(taken) }
        }
    }

    private func recordProcessSample() {
        var usage = rusage()
        getrusage(RUSAGE_SELF, &usage)
        let cpu = Self.nanoseconds(usage.ru_utime) &+ Self.nanoseconds(usage.ru_stime)
        let thermal = UInt8(truncatingIfNeeded: ProcessInfo.processInfo.thermalState.rawValue)
        record(.process, sub: thermal, v0: cpu, v1: Self.memoryFootprint())
        let (total, spent, lost) = lock.withLockUnchecked { (written, selfTime, dropped) }
        record(.recorder, id: UInt32(truncatingIfNeeded: total), v0: spent, v1: lost)
    }

    private static func nanoseconds(_ value: timeval) -> UInt64 {
        UInt64(max(value.tv_sec, 0)) &* 1_000_000_000 &+ UInt64(max(value.tv_usec, 0)) &* 1_000
    }

    private static func memoryFootprint() -> UInt64 {
        var info = task_vm_info_data_t()
        var size = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<integer_t>.size)
        let result = withUnsafeMutablePointer(to: &info) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(size)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &size)
            }
        }
        return result == KERN_SUCCESS ? info.phys_footprint : 0
    }

    // MARK: Format

    static func append(_ record: BenchRecord, to text: inout String) {
        text += "{\"t\":\(record.time),\"k\":\(record.kind),\"s\":\(record.sub),\"i\":\(record.id),"
        text += "\"a\":\(record.v0),\"b\":\(record.v1)}\n"
    }

    /// Parses one line written by `append`. `nil` for the header or anything malformed.
    public static func parse(_ line: Substring) -> BenchRecord? {
        guard line.hasPrefix("{\"t\":"), line.hasSuffix("}") else { return nil }
        var fields: [UInt64] = []
        fields.reserveCapacity(6)
        var value: UInt64 = 0
        var inNumber = false
        var afterColon = false
        for byte in line.utf8 {
            switch byte {
            case UInt8(ascii: ":"):
                afterColon = true
            case UInt8(ascii: "0")...UInt8(ascii: "9") where afterColon:
                value = value &* 10 &+ UInt64(byte &- UInt8(ascii: "0"))
                inNumber = true
            default:
                if inNumber { fields.append(value) }
                value = 0
                inNumber = false
                afterColon = false
            }
        }
        guard fields.count == 6, let kind = BenchKind(rawValue: UInt8(truncatingIfNeeded: fields[1])) else {
            return nil
        }
        return BenchRecord(
            time: fields[0], kind: kind, sub: UInt8(truncatingIfNeeded: fields[2]),
            id: UInt32(truncatingIfNeeded: fields[3]), v0: fields[4], v1: fields[5]
        )
    }

    static func headerLine(role: String, runID: String) -> String {
        let info = ProcessInfo.processInfo
        let version = info.operatingSystemVersion
        let header: [String: Any] = [
            "type": "header",
            "schema": BoloBench.schemaVersion,
            "role": role,
            "runId": runID,
            "pid": Int(getpid()),
            "mono": BoloBench.now(),
            "wall": Date().timeIntervalSince1970,
            "model": sysctlString("hw.model"),
            "chip": sysctlString("machdep.cpu.brand_string"),
            "cores": info.processorCount,
            "performanceCores": sysctlInt("hw.perflevel0.physicalcpu"),
            "efficiencyCores": sysctlInt("hw.perflevel1.physicalcpu"),
            "memoryBytes": info.physicalMemory,
            "os": "\(version.majorVersion).\(version.minorVersion).\(version.patchVersion)",
            "osBuild": sysctlString("kern.osversion"),
            "thermalState": info.thermalState.rawValue,
            "lowPowerMode": info.isLowPowerModeEnabled,
        ]
        let data = (try? JSONSerialization.data(withJSONObject: header, options: [.sortedKeys])) ?? Data("{}".utf8)
        return String(decoding: data, as: UTF8.self)
    }

    private static func sysctlString(_ name: String) -> String {
        var size = 0
        guard sysctlbyname(name, nil, &size, nil, 0) == 0, size > 0 else { return "" }
        var buffer = [CChar](repeating: 0, count: size)
        guard sysctlbyname(name, &buffer, &size, nil, 0) == 0 else { return "" }
        return String(decoding: buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }

    private static func sysctlInt(_ name: String) -> Int {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname(name, &value, &size, nil, 0) == 0 ? Int(value) : 0
    }
}
