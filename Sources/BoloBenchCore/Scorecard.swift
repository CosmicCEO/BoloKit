import BoloNet
import Foundation

// MARK: - Scorecard, repeatability and comparison (v1.6.9 baseline benchmark)
//
// A scorecard is the repeated runs of one scenario on one tier, reduced to a median and an
// interval per metric, with a verdict on whether the measurement system itself is repeatable
// enough for that metric to be trusted. A later version is compared against a frozen scorecard
// metric by metric.

/// How a metric's repeatability is judged. The rule is chosen from the metric's name.
public enum RepeatabilityRule: String, Sendable, Codable, CaseIterable {
    /// Half-width of the median's 95% interval within 5% of the median.
    case relative5
    /// The same within 10%: 95th percentiles.
    case relative10
    /// Half-width within 10 ms, half a tick: delays across the link.
    case within10ms
    /// Coefficient of variation within 2%: message and byte counts.
    case variation2
    /// At least 9 runs in 10 agree on whether there was any: divergence counts.
    case verdict
    /// Reported, never judged and never compared: 99th percentiles, maxima, sample counts.
    case reportOnly
}

public struct MetricStat: Sendable, Equatable, Codable {
    public var values: [Double]
    public var median: Double
    public var low: Double
    public var high: Double
    public var rule: RepeatabilityRule
    public var repeatable: Bool

    public var halfWidth: Double { (high - low) / 2 }
}

public struct Scorecard: Sendable, Equatable, Codable {
    public var schema: Int
    public var scenario: String
    public var scenarioHash: String
    public var tier: String
    public var model: String
    public var osBuild: String
    public var validRuns: Int
    public var invalidRuns: Int
    public var invalidReasons: [String]
    public var metrics: [String: MetricStat]

    public var unrepeatable: [String] {
        metrics.filter { !$0.value.repeatable }.keys.sorted()
    }
}

public enum ScorecardError: Error, Equatable {
    case noValidRuns
    case mixedRuns(String)
}

public enum Repeatability {
    /// Below these a relative bound is asking for more than the clock and scheduler can give.
    static func floor(for name: String) -> Double {
        if name.contains("_us") { return 5 }
        if name.contains("_ms") { return 0.05 }
        if name.contains("_pct") { return 0.5 }
        if name.contains("_mb") { return 1 }
        return 0.5
    }

    public static func rule(for name: String) -> RepeatabilityRule {
        if name.hasSuffix(".n") || name.hasSuffix(".p99") || name.hasSuffix(".max") || name.hasSuffix("_s")
            || name.hasSuffix(".records") || name.contains(".recorder.") || name.contains("thermal")
        {
            return .reportOnly
        }
        if name.hasPrefix("correctness.") {
            if name.contains("convergence_ms") { return name.hasSuffix(".p50") ? .within10ms : .reportOnly }
            if name.hasSuffix("_pct") { return .reportOnly }
            return .verdict
        }
        if name.hasSuffix(".lost") || name.hasSuffix(".reordered") || name.contains("rejects")
            || name.contains("invariant") || name.contains("unpaired") || name.contains("mismatched")
            || name.hasSuffix("ticks_lost")
        {
            return .verdict
        }
        if name.hasSuffix(".messages") || name.hasSuffix(".bytes") || name.hasSuffix(".sent") || name.hasSuffix(".read") {
            return .variation2
        }
        if name.hasPrefix("link.") || name.contains("input_to_frame") || name.contains("join")
            || name.contains("remote_move_interval") || name.contains("queue_delay")
        {
            return name.hasSuffix(".p50") || !name.contains(".p") ? .within10ms : (name.hasSuffix(".p95") ? .within10ms : .reportOnly)
        }
        if name.hasSuffix(".p95") { return .relative10 }
        return .relative5
    }

    static func stat(_ name: String, _ values: [Double]) -> MetricStat? {
        guard let median = Stats.median(values) else { return nil }
        let interval = Stats.medianInterval(values) ?? (median, median)
        let rule = rule(for: name)
        let half = (interval.high - interval.low) / 2
        let repeatable: Bool
        switch rule {
        case .reportOnly:
            repeatable = true
        case .relative5:
            repeatable = values.count > 1 && half <= max(0.05 * abs(median), floor(for: name))
        case .relative10:
            repeatable = values.count > 1 && half <= max(0.10 * abs(median), floor(for: name))
        case .within10ms:
            repeatable = values.count > 1 && half <= 10
        case .variation2:
            let variation = Stats.coefficientOfVariation(values) ?? 0
            repeatable = values.count > 1 && variation <= 0.02
        case .verdict:
            let some = values.filter { $0 > 0 }.count
            let agreeing = max(some, values.count - some)
            repeatable = values.count > 1 && Double(agreeing) >= 0.9 * Double(values.count)
        }
        return MetricStat(
            values: values, median: median, low: interval.low, high: interval.high, rule: rule, repeatable: repeatable
        )
    }

    /// One scorecard from the runs of one scenario. Invalid runs are counted and left out.
    public static func scorecard(_ runs: [RunSummary]) throws -> Scorecard {
        let valid = runs.filter(\.valid)
        guard let first = valid.first else { throw ScorecardError.noValidRuns }
        for run in valid {
            if run.scenarioHash != first.scenarioHash { throw ScorecardError.mixedRuns("scenario") }
            if run.tier != first.tier { throw ScorecardError.mixedRuns("tier") }
            if run.model != first.model { throw ScorecardError.mixedRuns("hardware model") }
            if run.osBuild != first.osBuild { throw ScorecardError.mixedRuns("OS build") }
        }
        var names = Set<String>()
        for run in valid { names.formUnion(run.metrics.keys) }
        var metrics: [String: MetricStat] = [:]
        for name in names {
            // A metric absent from a run had nothing to measure there, which for a count is zero.
            let values = valid.compactMap { run -> Double? in
                run.metrics[name] ?? (rule(for: name) == .verdict ? 0 : nil)
            }
            metrics[name] = stat(name, values)
        }
        return Scorecard(
            schema: BoloBench.schemaVersion, scenario: first.scenario, scenarioHash: first.scenarioHash,
            tier: first.tier, model: first.model, osBuild: first.osBuild, validRuns: valid.count,
            invalidRuns: runs.count - valid.count,
            invalidReasons: runs.filter { !$0.valid }.flatMap(\.invalidReasons), metrics: metrics
        )
    }
}

// MARK: - Comparison

public enum Verdict: String, Sendable, Codable {
    case unchanged
    case changed
    /// Not judged: report-only, unrepeatable in the baseline, or missing on one side.
    case notCompared
}

public struct MetricComparison: Sendable, Equatable, Codable {
    public var name: String
    public var baseline: Double?
    public var candidate: Double?
    public var changePct: Double?
    public var p: Double?
    public var verdict: Verdict
    public var reason: String
}

public enum ComparisonError: Error, Equatable {
    case notComparable(String)
}

public enum Comparison {
    /// Refuses unless both scorecards are the same scenario, tier, hardware and recording schema.
    /// A metric has changed only when the two intervals do not overlap and a rank-sum test on
    /// the runs agrees (p below 0.05).
    public static func compare(baseline: Scorecard, candidate: Scorecard) throws -> [MetricComparison] {
        if baseline.schema != candidate.schema { throw ComparisonError.notComparable("recording schema differs") }
        if baseline.scenarioHash != candidate.scenarioHash { throw ComparisonError.notComparable("scenario differs") }
        if baseline.tier != candidate.tier { throw ComparisonError.notComparable("tier differs") }
        if baseline.model != candidate.model { throw ComparisonError.notComparable("hardware model differs") }

        return Set(baseline.metrics.keys).union(candidate.metrics.keys).sorted().map { name in
            let old = baseline.metrics[name]
            let new = candidate.metrics[name]
            var result = MetricComparison(
                name: name, baseline: old?.median, candidate: new?.median, changePct: nil, p: nil,
                verdict: .notCompared, reason: ""
            )
            guard let old, let new else {
                result.reason = old == nil ? "not in the baseline" : "not in the candidate"
                return result
            }
            if old.median != 0 { result.changePct = 100 * (new.median - old.median) / abs(old.median) }
            if old.rule == .reportOnly {
                result.reason = "report only"
                return result
            }
            if !old.repeatable {
                result.reason = "not repeatable in the baseline"
                return result
            }
            result.p = Stats.rankSumP(old.values, new.values)
            let apart = new.low > old.high || new.high < old.low
            let significant = (result.p ?? 1) < 0.05
            result.verdict = apart && significant ? .changed : .unchanged
            result.reason = apart ? (significant ? "intervals apart, p < 0.05" : "intervals apart, p >= 0.05") : "intervals overlap"
            return result
        }
    }
}
