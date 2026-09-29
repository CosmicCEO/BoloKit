import BoloKit
import BoloNet
import Foundation

// MARK: - Reading a log (v1.6.9 baseline benchmark)
//
// One process's log as written by `BenchRecorder`: a header line, then one record per line.
// Lines that are neither are skipped, so stray output in the file cannot break a run's analysis.

public struct BenchHeader: Equatable, Sendable {
    public var schema: Int
    public var role: String
    public var runID: String
    public var monotonic: UInt64
    public var wall: Double
    public var model: String
    public var chip: String
    public var cores: Int
    public var memoryBytes: UInt64
    public var os: String
    public var osBuild: String
    public var thermalState: Int
    public var lowPowerMode: Bool

    public init(_ object: [String: Any]) {
        schema = object["schema"] as? Int ?? 0
        role = object["role"] as? String ?? ""
        runID = object["runId"] as? String ?? ""
        monotonic = (object["mono"] as? NSNumber)?.uint64Value ?? 0
        wall = object["wall"] as? Double ?? 0
        model = object["model"] as? String ?? ""
        chip = object["chip"] as? String ?? ""
        cores = object["cores"] as? Int ?? 0
        memoryBytes = (object["memoryBytes"] as? NSNumber)?.uint64Value ?? 0
        os = object["os"] as? String ?? ""
        osBuild = object["osBuild"] as? String ?? ""
        thermalState = object["thermalState"] as? Int ?? 0
        lowPowerMode = object["lowPowerMode"] as? Bool ?? false
    }
}

public enum BenchLogError: Error, Equatable {
    case noHeader
    case wrongSchema(Int)
}

public struct BenchLog: Sendable {
    public var header: BenchHeader
    /// In time order. The file is in call order, which differs wherever a record was stamped
    /// with a time earlier than its call.
    public var records: [BenchRecord]

    public init(header: BenchHeader, records: [BenchRecord]) {
        self.header = header
        // Stable, so records sharing a timestamp keep the order they were made in.
        self.records = records.enumerated().sorted {
            $0.element.time != $1.element.time ? $0.element.time < $1.element.time : $0.offset < $1.offset
        }.map(\.element)
    }

    public init(text: String) throws {
        var header: BenchHeader?
        var records: [BenchRecord] = []
        for line in text.split(separator: "\n", omittingEmptySubsequences: true) {
            if let record = BenchRecorder.parse(line) {
                records.append(record)
            } else if header == nil, line.hasPrefix("{"),
                let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any],
                object["type"] as? String == "header"
            {
                header = BenchHeader(object)
            }
        }
        guard let header else { throw BenchLogError.noHeader }
        guard header.schema == BoloBench.schemaVersion else { throw BenchLogError.wrongSchema(header.schema) }
        self.init(header: header, records: records)
    }

    public init(contentsOf url: URL) throws {
        try self.init(text: String(contentsOf: url, encoding: .utf8))
    }

    public func of(_ kind: BenchKind) -> [BenchRecord] {
        records.filter { $0.kind == kind.rawValue }
    }

    public var firstTime: UInt64 { records.first?.time ?? 0 }
    public var lastTime: UInt64 { records.last?.time ?? 0 }
}
