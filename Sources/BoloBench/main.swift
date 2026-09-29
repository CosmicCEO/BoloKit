import BoloBenchCore
import BoloNet
import Foundation

// v1.6.9 baseline benchmark: the offline half. Reads the logs the app wrote and produces the
// numbers. Never touches a socket or the game.
//
//   BoloBench analyze <run-dir> [--tier pair|sweep]   one run: host.jsonl (+ join.jsonl) -> summary.json
//   BoloBench scorecard <scenario-dir>... [--out <file>]
//                                                     every run-NN/summary.json -> scorecard.json;
//                                                     several directories pool their runs
//   BoloBench compare <baseline.json> <candidate.json>
//   BoloBench scenario <name>                         print a scenario as JSON, with its hash
//   BoloBench overhead                                measure the recorder's cost per record here
//   BoloBench observer <recording-dir> <not-recording-dir>
//                                                     processor time with recording on against off

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("BoloBench: \(message)\n".utf8))
    exit(1)
}

func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
    return encoder
}

func option(_ name: String, in arguments: [String]) -> String? {
    guard let index = arguments.firstIndex(of: name), index + 1 < arguments.count else { return nil }
    return arguments[index + 1]
}

func format(_ value: Double?) -> String {
    guard let value else { return "-" }
    return abs(value) >= 100 ? String(format: "%.0f", value) : String(format: "%.3g", value)
}

func analyze(_ arguments: [String]) throws {
    guard let path = arguments.first else { fail("usage: analyze <run-dir> [--tier pair|sweep]") }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    let tier = option("--tier", in: arguments) ?? "pair"
    let host = try BenchLog(contentsOf: directory.appendingPathComponent("host.jsonl"))
    let guestURL = directory.appendingPathComponent("join.jsonl")
    // Any tier but `pair` is a sweep (`sweep-n04` and so on), which has only the host's log.
    let guest = tier == "pair" ? try BenchLog(contentsOf: guestURL) : nil

    // What the run script recorded about how the two processes ended.
    var facts: [String: Any] = [:]
    if let data = try? Data(contentsOf: directory.appendingPathComponent("run.json")) {
        facts = (try? JSONSerialization.jsonObject(with: data) as? [String: Any]) ?? [:]
    }
    let name = facts["scenario"] as? String ?? host.header.runID
    guard let scenario = BenchScenarios.named(name) else { fail("unknown scenario '\(name)'") }

    let summary = RunAnalysis.summarize(
        host: host, guest: guest,
        facts: RunAnalysis.RunFacts(
            scenario: scenario, tier: tier, killed: (facts["killed"] as? Int ?? 0) != 0,
            hostExit: Int32(facts["hostExit"] as? Int ?? 0), guestExit: Int32(facts["guestExit"] as? Int ?? 0)
        )
    )
    try encoder().encode(summary).write(to: directory.appendingPathComponent("summary.json"))
    let faults = summary.episodes.count
    print("\(directory.lastPathComponent): \(summary.valid ? "valid" : "INVALID") \(summary.metrics.count) metrics, \(faults) divergence episode(s) past in-flight")
    for reason in summary.invalidReasons { print("  invalid: \(reason)") }
}

func scorecard(_ arguments: [String]) throws {
    var paths: [String] = []
    var skip = false
    for argument in arguments {
        if skip { skip = false } else if argument == "--out" { skip = true } else { paths.append(argument) }
    }
    guard let path = paths.first else { fail("usage: scorecard <scenario-dir>... [--out <file>]") }
    let directory = URL(fileURLWithPath: path, isDirectory: true)
    // Runs of one scenario from several sessions pool into one scorecard, whose spread then
    // includes how much the numbers move from one session to the next.
    let runs = try paths.flatMap { path in
        try FileManager.default.contentsOfDirectory(
            at: URL(fileURLWithPath: path, isDirectory: true), includingPropertiesForKeys: nil
        )
        .filter { $0.lastPathComponent.hasPrefix("run-") }
        .sorted { $0.lastPathComponent < $1.lastPathComponent }
        .compactMap { try? Data(contentsOf: $0.appendingPathComponent("summary.json")) }
        .map { try JSONDecoder().decode(RunSummary.self, from: $0) }
    }
    let card = try Repeatability.scorecard(runs)
    let out = option("--out", in: arguments).map { URL(fileURLWithPath: $0) }
        ?? directory.appendingPathComponent("scorecard.json")
    try encoder().encode(card).write(to: out)

    let judged = card.metrics.filter { $0.value.rule != .reportOnly }
    print("\(card.scenario) [\(card.tier)]: \(card.validRuns) valid run(s), \(card.invalidRuns) invalid")
    print("  \(judged.count) metrics judged, \(judged.count - card.unrepeatable.count) repeatable, \(card.unrepeatable.count) not")
    for name in card.unrepeatable.prefix(40) {
        guard let stat = card.metrics[name] else { continue }
        print("  not repeatable: \(name)  median \(format(stat.median))  [\(format(stat.low)), \(format(stat.high))]  rule \(stat.rule.rawValue)")
    }
}

func compare(_ arguments: [String]) throws {
    guard arguments.count >= 2 else { fail("usage: compare <baseline.json> <candidate.json>") }
    let cards = try arguments.prefix(2).map {
        try JSONDecoder().decode(Scorecard.self, from: Data(contentsOf: URL(fileURLWithPath: $0)))
    }
    let results = try Comparison.compare(baseline: cards[0], candidate: cards[1])
    let changed = results.filter { $0.verdict == .changed }
    print("\(cards[0].scenario): \(results.filter { $0.verdict != .notCompared }.count) metrics compared, \(changed.count) changed")
    for result in changed {
        let change = result.changePct.map { String(format: "%+.1f%%", $0) } ?? "-"
        print("  changed: \(result.name)  \(format(result.baseline)) -> \(format(result.candidate))  \(change)")
    }
    if let out = option("--out", in: arguments) {
        try encoder().encode(results).write(to: URL(fileURLWithPath: out))
    }
}

func scenario(_ arguments: [String]) throws {
    guard let name = arguments.first else {
        for scenario in BenchScenarios.all { print("\(scenario.name)  \(RunAnalysis.scenarioHash(scenario))") }
        return
    }
    guard let scenario = BenchScenarios.named(name) else { fail("unknown scenario '\(name)'") }
    print(String(decoding: try scenario.encoded(), as: UTF8.self))
    FileHandle.standardError.write(Data("hash \(RunAnalysis.scenarioHash(scenario))\n".utf8))
}

/// The cost of one `record` call on this machine, so a run's record count can be turned into
/// time. Build with `-c release`: a debug build measures the debug build.
func overhead() throws {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("bolo-bench-overhead-\(getpid()).jsonl")
    defer { try? FileManager.default.removeItem(at: url) }
    var perRecord: [Double] = []
    for _ in 0..<7 {
        let recorder = try BenchRecorder(url: url, role: "overhead", runID: "overhead")
        let count = 200_000
        let start = BoloBench.now()
        for index in 0..<count { recorder.record(.state, id: UInt32(index), v0: UInt64(index), at: start) }
        let spent = BoloBench.now() &- start
        recorder.finish()
        perRecord.append(Double(spent) / Double(count))
    }
    print(String(format: "record(): median %.1f ns per record over 7 rounds of 200,000 (min %.1f, max %.1f)",
        Stats.median(perRecord)!, perRecord.min()!, perRecord.max()!))
}

/// The observer effect: what recording costs the thing being measured. Compares the processor
/// time each process used, as the run script read it from outside, over runs of one scenario
/// with recording on and with it off. Runs of different lengths are compared per second.
func observer(_ arguments: [String]) throws {
    guard arguments.count >= 2 else { fail("usage: observer <recording-dir> <not-recording-dir>") }
    func rates(_ path: String, recording: Int) throws -> (host: [Double], guest: [Double]) {
        let directory = URL(fileURLWithPath: path, isDirectory: true)
        var host: [Double] = []
        var guest: [Double] = []
        for run in try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
        where run.lastPathComponent.hasPrefix("run-") {
            guard let data = try? Data(contentsOf: run.appendingPathComponent("run.json")),
                let facts = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                facts["recording"] as? Int == recording, (facts["killed"] as? Int ?? 0) == 0,
                (facts["hostExit"] as? Int ?? 1) == 0, (facts["guestExit"] as? Int ?? 1) == 0,
                let seconds = facts["seconds"] as? Double, seconds > 0,
                let hostCpu = facts["hostCpuSeconds"] as? Double, let guestCpu = facts["guestCpuSeconds"] as? Double
            else { continue }
            host.append(100 * hostCpu / seconds)
            guest.append(100 * guestCpu / seconds)
        }
        return (host, guest)
    }
    let on = try rates(arguments[0], recording: 1)
    let off = try rates(arguments[1], recording: 0)
    var report: [String: Any] = [:]
    for (side, recorded, plain) in [("host", on.host, off.host), ("guest", on.guest, off.guest)] {
        guard let with = Stats.median(recorded), let without = Stats.median(plain), without > 0 else {
            fail("no usable runs for the \(side) (recording \(recorded.count), not recording \(plain.count))")
        }
        let change = 100 * (with - without) / without
        let p = Stats.rankSumP(recorded, plain)
        print(String(
            format: "%@: %.1f%% of a core recording (n=%d), %.1f%% not (n=%d): %+.1f%%, p %@", side, with,
            recorded.count, without, plain.count, change, p.map { String(format: "%.3f", $0) } ?? "-"
        ))
        report[side] = [
            "recordingPct": with, "notRecordingPct": without, "changePct": change, "p": p as Any,
            "recordingRuns": recorded.count, "notRecordingRuns": plain.count, "within3Pct": abs(change) <= 3,
        ]
    }
    if let out = option("--out", in: arguments) {
        try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
            .write(to: URL(fileURLWithPath: out))
    }
}

let arguments = Array(CommandLine.arguments.dropFirst())
guard let command = arguments.first else {
    fail("usage: BoloBench analyze|scorecard|compare|scenario|overhead|observer ...")
}
do {
    let rest = Array(arguments.dropFirst())
    switch command {
    case "analyze": try analyze(rest)
    case "scorecard": try scorecard(rest)
    case "compare": try compare(rest)
    case "scenario": try scenario(rest)
    case "overhead": try overhead()
    case "observer": try observer(rest)
    default: fail("unknown command '\(command)'")
    }
} catch {
    fail("\(error)")
}
