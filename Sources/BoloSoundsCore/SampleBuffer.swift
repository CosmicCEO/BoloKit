/// The `Canvas.swift` analogue for sound: a plain mono `[Float]` sample buffer in `[-1, 1]`,
/// carrying its own sample-rate metadata. Quantized to `Int16` only at AIFF-encode time
/// (`AIFFCodec.swift`) -- kept as `Float` here to avoid intermediate integer clipping/rounding
/// bugs across chained DSP primitives (mix/envelope/filter).
public struct SampleBuffer: Sendable, Equatable {
    public var samples: [Float]
    public let sampleRate: Double

    public init(samples: [Float] = [], sampleRate rate: Double = SampleBuffer.defaultSampleRate) {
        self.samples = samples
        self.sampleRate = rate
    }

    /// Mirrors the module-level `sampleRate` constant (`SoundSource.swift`) -- referenced by
    /// name here since a default parameter expression can't read an instance member, and using
    /// a distinct static avoids ambiguity with the global.
    public static let defaultSampleRate: Double = 44100.0

    public var count: Int { samples.count }
    public var duration: Double { Double(samples.count) / sampleRate }

    /// Sample-wise add against `other`, extended to the longer of the two lengths (missing
    /// samples on the shorter side treated as silence) -- used to combine e.g. a noise burst and
    /// a tone-sweep layer into one effect.
    public func mix(_ other: SampleBuffer) -> SampleBuffer {
        let n = max(samples.count, other.samples.count)
        var out = [Float](repeating: 0, count: n)
        for i in 0..<samples.count { out[i] += samples[i] }
        for i in 0..<other.samples.count { out[i] += other.samples[i] }
        return SampleBuffer(samples: out, sampleRate: sampleRate)
    }

    /// Sample-wise multiply against an envelope array. The envelope is zero-padded (if shorter)
    /// or truncated (if longer) to this buffer's length.
    public func apply(envelope: [Float]) -> SampleBuffer {
        var out = samples
        for i in 0..<out.count {
            out[i] *= i < envelope.count ? envelope[i] : 0
        }
        return SampleBuffer(samples: out, sampleRate: sampleRate)
    }

    /// Scalar gain multiply.
    public func gain(by factor: Float) -> SampleBuffer {
        SampleBuffer(samples: samples.map { $0 * factor }, sampleRate: sampleRate)
    }

    /// Trims or zero-pads to exactly `duration` seconds.
    public func trimOrPad(to duration: Double) -> SampleBuffer {
        let n = Int((duration * sampleRate).rounded())
        var out = samples
        if out.count > n {
            out = Array(out[0..<n])
        } else if out.count < n {
            out.append(contentsOf: [Float](repeating: 0, count: n - out.count))
        }
        return SampleBuffer(samples: out, sampleRate: sampleRate)
    }

    /// Appends `other` after this buffer's samples (sample-rate mismatch is a caller error --
    /// every buffer in this project is produced at the shared `sampleRate` constant).
    public func appending(_ other: SampleBuffer) -> SampleBuffer {
        SampleBuffer(samples: samples + other.samples, sampleRate: sampleRate)
    }

    /// A silent buffer of the given duration, at the shared sample rate -- used to build offset
    /// gaps between discrete pulses (e.g. `build`'s ascending triad).
    public static func silence(duration: Double) -> SampleBuffer {
        SampleBuffer(samples: [Float](repeating: 0, count: Int((duration * defaultSampleRate).rounded())))
    }

    /// Overlays `other` onto this buffer starting at `offset` seconds, extending this buffer's
    /// length if needed -- used for staggered sub-bursts (e.g. `bubbles`).
    public func overlaying(_ other: SampleBuffer, at offset: Double) -> SampleBuffer {
        let startIndex = Int((offset * sampleRate).rounded())
        let neededLength = startIndex + other.samples.count
        var out = samples
        if out.count < neededLength {
            out.append(contentsOf: [Float](repeating: 0, count: neededLength - out.count))
        }
        for i in 0..<other.samples.count {
            out[startIndex + i] += other.samples[i]
        }
        return SampleBuffer(samples: out, sampleRate: sampleRate)
    }
}
