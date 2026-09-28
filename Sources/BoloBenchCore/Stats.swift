import Foundation

// MARK: - Statistics (v1.6.9 baseline benchmark)
//
// Deliberately plain: nearest-rank percentiles, a seeded bootstrap for interval widths, and a
// rank-sum test for comparing two sets of runs. Everything is deterministic, so analysing the
// same logs twice gives the same numbers.

public enum Stats {
    /// Nearest-rank percentile of `values`, `p` in 0...1. `nil` when there are none.
    public static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up))
        return sorted[min(max(rank, 1), sorted.count) - 1]
    }

    public static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        return sorted.count % 2 == 1 ? sorted[middle] : (sorted[middle - 1] + sorted[middle]) / 2
    }

    public static func mean(_ values: [Double]) -> Double? {
        values.isEmpty ? nil : values.reduce(0, +) / Double(values.count)
    }

    /// Sample standard deviation. `nil` for fewer than two values.
    public static func standardDeviation(_ values: [Double]) -> Double? {
        guard values.count > 1, let mean = mean(values) else { return nil }
        let sum = values.reduce(0) { $0 + ($1 - mean) * ($1 - mean) }
        return (sum / Double(values.count - 1)).squareRoot()
    }

    /// Standard deviation over mean. `nil` when the mean is zero.
    public static func coefficientOfVariation(_ values: [Double]) -> Double? {
        guard let mean = mean(values), mean != 0, let deviation = standardDeviation(values) else { return nil }
        return deviation / abs(mean)
    }

    /// The 95% percentile-bootstrap interval of the median of `values`.
    public static func medianInterval(
        _ values: [Double], resamples: Int = 2_000, seed: UInt64 = 0x1_6_9
    ) -> (low: Double, high: Double)? {
        guard values.count > 1 else { return nil }
        var rng = SplitMix(state: seed)
        var medians: [Double] = []
        medians.reserveCapacity(resamples)
        var sample = [Double](repeating: 0, count: values.count)
        for _ in 0..<resamples {
            for index in sample.indices { sample[index] = values[Int(rng.next() % UInt64(values.count))] }
            medians.append(median(sample)!)
        }
        return (percentile(medians, 0.025)!, percentile(medians, 0.975)!)
    }

    /// Two-sided Mann-Whitney rank-sum test, normal approximation with tie correction.
    /// Returns the p-value, or `nil` when either side has no values or every value is equal.
    public static func rankSumP(_ a: [Double], _ b: [Double]) -> Double? {
        guard !a.isEmpty, !b.isEmpty else { return nil }
        let pooled = (a.map { ($0, 0) } + b.map { ($0, 1) }).sorted { $0.0 < $1.0 }
        var ranks = [Double](repeating: 0, count: pooled.count)
        var tieTerm = 0.0
        var index = 0
        while index < pooled.count {
            var end = index
            while end + 1 < pooled.count, pooled[end + 1].0 == pooled[index].0 { end += 1 }
            let rank = Double(index + end) / 2 + 1
            for position in index...end { ranks[position] = rank }
            let ties = Double(end - index + 1)
            tieTerm += ties * ties * ties - ties
            index = end + 1
        }
        let n1 = Double(a.count)
        let n2 = Double(b.count)
        let total = n1 + n2
        let rankSum = zip(pooled, ranks).filter { $0.0.1 == 0 }.reduce(0) { $0 + $1.1 }
        let u = rankSum - n1 * (n1 + 1) / 2
        let variance = n1 * n2 / 12 * ((total + 1) - tieTerm / (total * (total - 1)))
        guard variance > 0 else { return nil }
        // Continuity-corrected.
        let z = (abs(u - n1 * n2 / 2) - 0.5) / variance.squareRoot()
        return min(1, max(0, erfc(max(z, 0) / 2.0.squareRoot())))
    }

    /// The 95% Wilson score interval for `successes` out of `trials`.
    public static func wilson(successes: Int, trials: Int) -> (low: Double, high: Double)? {
        guard trials > 0 else { return nil }
        let z = 1.959964
        let n = Double(trials)
        let p = Double(successes) / n
        let denominator = 1 + z * z / n
        let centre = (p + z * z / (2 * n)) / denominator
        let half = z * (p * (1 - p) / n + z * z / (4 * n * n)).squareRoot() / denominator
        return (max(0, centre - half), min(1, centre + half))
    }

    struct SplitMix {
        var state: UInt64
        mutating func next() -> UInt64 {
            state &+= 0x9E37_79B9_7F4A_7C15
            var z = state
            z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
            z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
            return z ^ (z >> 31)
        }
    }
}

/// A named set of numbers being built up, written out as `name.p50`, `name.p95` and so on.
public struct MetricSet: Sendable, Equatable {
    public private(set) var values: [String: Double] = [:]

    public init() {}

    public mutating func set(_ name: String, _ value: Double?) {
        if let value, value.isFinite { values[name] = value }
    }

    public mutating func count(_ name: String, _ value: Int) {
        values[name] = Double(value)
    }

    /// `name.n`, `.p50`, `.p95`, `.p99`, `.max` of `samples`. Only `name.n` when there are none.
    public mutating func distribution(_ name: String, _ samples: [Double]) {
        values["\(name).n"] = Double(samples.count)
        guard !samples.isEmpty else { return }
        set("\(name).p50", Stats.percentile(samples, 0.50))
        set("\(name).p95", Stats.percentile(samples, 0.95))
        set("\(name).p99", Stats.percentile(samples, 0.99))
        set("\(name).max", samples.max())
    }

    public subscript(name: String) -> Double? { values[name] }
}

extension UInt64 {
    /// Nanoseconds as milliseconds.
    var ms: Double { Double(self) / 1_000_000 }
}
