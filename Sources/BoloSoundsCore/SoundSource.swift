import Darwin

/// Shared sample rate for all procedurally-generated sound effects (D122/C.3) -- matches the
/// reference's own on-disk AIFF format (44.1kHz, confirmed via `afinfo`).
public let sampleRate: Double = 44100.0

// MARK: - DSP primitives

/// Deterministic white noise via a fixed-seed 64-bit LCG -- NOT `SystemRandomNumberGenerator`.
/// Determinism is required so `buildSounds()` can be regression-tested for byte-identical
/// repeat output (mirrors `BoloGlyphsCore`'s own determinism test for `buildSheets()`).
public func whiteNoise(duration: Double, seed: UInt64, amplitude: Float = 1.0) -> SampleBuffer {
    let n = Int((duration * sampleRate).rounded())
    var state = seed == 0 ? 1 : seed
    var out = [Float](repeating: 0, count: n)
    for i in 0..<n {
        // Numerical Recipes LCG constants.
        state = state &* 6364136223846793005 &+ 1442695040888963407
        let unit = Float(state >> 40) / Float(1 << 24) // in [0, 1)
        out[i] = (unit * 2 - 1) * amplitude
    }
    return SampleBuffer(samples: out, sampleRate: sampleRate)
}

/// Two-stage attack/decay envelope (one-shots only, no sustain/release): linear attack ramp
/// 0->1 over `attackTime`, then exponential decay 1->~0 over `decayTime` with `decayRate` as
/// the exponent's time constant (amplitude(t) = exp(-t / decayRate) after the attack completes).
public func adEnvelope(attackTime: Double, decayTime: Double, decayRate: Double) -> [Float] {
    let attackSamples = Int((attackTime * sampleRate).rounded())
    let decaySamples = Int((decayTime * sampleRate).rounded())
    var out = [Float](repeating: 0, count: attackSamples + decaySamples)
    for i in 0..<attackSamples {
        out[i] = attackSamples > 0 ? Float(i) / Float(attackSamples) : 1
    }
    for i in 0..<decaySamples {
        let t = Double(i) / sampleRate
        out[attackSamples + i] = Float(exp(-t / decayRate))
    }
    return out
}

/// Pure tone or linear frequency sweep (startFreq == endFreq for a plain tone). Sine wave, phase
/// accumulated from the instantaneous frequency so the sweep is continuous (no clicks).
public func toneSweep(duration: Double, startFreq: Double, endFreq: Double, amplitude: Float = 1.0) -> SampleBuffer {
    let n = Int((duration * sampleRate).rounded())
    var out = [Float](repeating: 0, count: n)
    var phase = 0.0
    for i in 0..<n {
        let t = Double(i) / Double(max(n - 1, 1))
        let freq = startFreq + (endFreq - startFreq) * t
        phase += 2 * Double.pi * freq / sampleRate
        out[i] = Float(sin(phase)) * amplitude
    }
    return SampleBuffer(samples: out, sampleRate: sampleRate)
}

/// Single-pole IIR lowpass: y[n] = y[n-1] + alpha*(x[n]-y[n-1]). This is the `far*` muffling
/// filter (10 of 24 names are filtered-not-independent, per D121/D122).
public func lowpass(_ buffer: SampleBuffer, cutoffHz: Double) -> SampleBuffer {
    let dt = 1.0 / buffer.sampleRate
    let rc = 1.0 / (2 * Double.pi * cutoffHz)
    let alpha = Float(dt / (rc + dt))
    var out = [Float](repeating: 0, count: buffer.samples.count)
    var y: Float = 0
    for i in 0..<buffer.samples.count {
        y = y + alpha * (buffer.samples[i] - y)
        out[i] = y
    }
    return SampleBuffer(samples: out, sampleRate: buffer.sampleRate)
}

// MARK: - Shared constants

/// Shared cutoff for all `far*` derivations (D122).
public let farCutoffHz: Double = 800.0

/// LCG seeds -- one per name that uses noise, so buffers stay deterministic and distinct from
/// one another (reusing the same seed across names would make their noise components
/// byte-identical, which is fine functionally but makes debugging confusing).
private enum Seed {
    static let explosion: UInt64 = 1
    static let superboom: UInt64 = 2
    static let hittank: UInt64 = 3
    static let hitterrain: UInt64 = 4
    static let hittree: UInt64 = 5
    static let mine: UInt64 = 6
    static let builderdeath: UInt64 = 7
    static let tree: UInt64 = 8
    static let bubbles1: UInt64 = 9
    static let bubbles2: UInt64 = 10
    static let bubbles3: UInt64 = 11
    static let sink: UInt64 = 12
}

// MARK: - 14-entry parameter table / per-name render dispatch

/// Renders one of the 14 designed (non-`far*`) named sounds. `far*` derivation happens in
/// `SoundSetBuilder.swift`, one level up, since it's a pure post-processing step (lowpass)
/// shared across names rather than part of any one name's own synthesis.
public func renderSound(named name: String) -> SampleBuffer? {
    switch name {
    case "explosion":
        let noise = whiteNoise(duration: 0.5, seed: Seed.explosion, amplitude: 0.9)
            .apply(envelope: adEnvelope(attackTime: 0.005, decayTime: 0.3, decayRate: 0.15))
        let sweep = toneSweep(duration: 0.5, startFreq: 400, endFreq: 60, amplitude: 0.6)
            .apply(envelope: adEnvelope(attackTime: 0.005, decayTime: 0.3, decayRate: 0.15))
        return noise.mix(sweep).trimOrPad(to: 0.5)

    case "superboom":
        let noise = whiteNoise(duration: 0.9, seed: Seed.superboom, amplitude: 1.0)
            .apply(envelope: adEnvelope(attackTime: 0.005, decayTime: 0.5, decayRate: 0.25))
        let sweep = toneSweep(duration: 0.9, startFreq: 250, endFreq: 40, amplitude: 0.7)
            .apply(envelope: adEnvelope(attackTime: 0.005, decayTime: 0.5, decayRate: 0.25))
        return noise.mix(sweep).trimOrPad(to: 0.9)

    case "hittank":
        return whiteNoise(duration: 0.15, seed: Seed.hittank, amplitude: 0.9)
            .apply(envelope: adEnvelope(attackTime: 0.002, decayTime: 0.08, decayRate: 0.03))
            .trimOrPad(to: 0.15)

    case "hitterrain":
        let noise = whiteNoise(duration: 0.2, seed: Seed.hitterrain, amplitude: 0.9)
        let dulled = lowpass(noise, cutoffHz: 2000)
        return dulled
            .apply(envelope: adEnvelope(attackTime: 0.003, decayTime: 0.12, decayRate: 0.05))
            .trimOrPad(to: 0.2)

    case "hittree":
        return whiteNoise(duration: 0.15, seed: Seed.hittree, amplitude: 0.8)
            .apply(envelope: adEnvelope(attackTime: 0.002, decayTime: 0.08, decayRate: 0.03))
            .trimOrPad(to: 0.15)

    case "mine":
        return whiteNoise(duration: 0.35, seed: Seed.mine, amplitude: 0.9)
            .apply(envelope: adEnvelope(attackTime: 0.004, decayTime: 0.2, decayRate: 0.1))
            .trimOrPad(to: 0.35)

    case "tankshot":
        return toneSweep(duration: 0.1, startFreq: 300, endFreq: 900, amplitude: 0.8)
            .apply(envelope: adEnvelope(attackTime: 0.001, decayTime: 0.06, decayRate: 0.02))
            .trimOrPad(to: 0.1)

    case "pillshot":
        return toneSweep(duration: 0.1, startFreq: 350, endFreq: 1000, amplitude: 0.8)
            .apply(envelope: adEnvelope(attackTime: 0.001, decayTime: 0.06, decayRate: 0.02))
            .trimOrPad(to: 0.1)

    case "build":
        return tonePulseSequence(frequencies: [440, 554, 659], pulseDuration: 0.06, gap: 0.02)

    case "builderdeath":
        let tones = tonePulseSequence(frequencies: [659, 554, 440], pulseDuration: 0.06, gap: 0.02)
        let noiseTail = whiteNoise(duration: 0.1, seed: Seed.builderdeath, amplitude: 0.7)
            .apply(envelope: adEnvelope(attackTime: 0.002, decayTime: 0.08, decayRate: 0.03))
        return tones.overlaying(noiseTail, at: max(tones.duration - 0.1, 0))

    case "tree":
        return whiteNoise(duration: 0.08, seed: Seed.tree, amplitude: 0.7)
            .apply(envelope: adEnvelope(attackTime: 0.001, decayTime: 0.03, decayRate: 0.01))
            .trimOrPad(to: 0.08)

    case "bubbles":
        let seeds: [UInt64] = [Seed.bubbles1, Seed.bubbles2, Seed.bubbles3]
        let offsets: [Double] = [0, 0.12, 0.24]
        var out = SampleBuffer(samples: [Float](repeating: 0, count: Int((0.4 * sampleRate).rounded())), sampleRate: sampleRate)
        for (seed, offset) in zip(seeds, offsets) {
            let burst = lowpass(whiteNoise(duration: 0.08, seed: seed, amplitude: 0.8), cutoffHz: 500)
                .apply(envelope: adEnvelope(attackTime: 0.005, decayTime: 0.06, decayRate: 0.03))
            out = out.overlaying(burst, at: offset)
        }
        return out.trimOrPad(to: 0.4)

    case "sink":
        let noise = lowpass(whiteNoise(duration: 0.6, seed: Seed.sink, amplitude: 0.9), cutoffHz: 400)
            .apply(envelope: adEnvelope(attackTime: 0.01, decayTime: 0.4, decayRate: 0.2))
        let sweep = toneSweep(duration: 0.6, startFreq: 200, endFreq: 50, amplitude: 0.6)
            .apply(envelope: adEnvelope(attackTime: 0.01, decayTime: 0.4, decayRate: 0.2))
        return noise.mix(sweep).trimOrPad(to: 0.6)

    case "msgreceived":
        return tonePulseSequence(frequencies: [880, 1100], pulseDuration: 0.08, gap: 0.03)

    default:
        return nil
    }
}

/// Builds a sequence of short discrete tone pulses separated by silence gaps -- shared by
/// `build`/`builderdeath`/`msgreceived`.
private func tonePulseSequence(frequencies: [Double], pulseDuration: Double, gap: Double) -> SampleBuffer {
    var out = SampleBuffer(samples: [], sampleRate: sampleRate)
    for (i, freq) in frequencies.enumerated() {
        let pulse = toneSweep(duration: pulseDuration, startFreq: freq, endFreq: freq, amplitude: 0.7)
            .apply(envelope: adEnvelope(attackTime: 0.005, decayTime: pulseDuration - 0.005, decayRate: pulseDuration / 3))
        out = out.appending(pulse)
        if i < frequencies.count - 1 {
            out = out.appending(.silence(duration: gap))
        }
    }
    return out
}

/// The 14 designed (non-`far*`) names, in the reference's own listing order (D65's Milestone C
/// row) -- the authoritative source of "which names exist" for `buildSounds()`'s iteration.
public let designedSoundNames: [String] = [
    "explosion", "superboom", "hittank", "hitterrain", "hittree", "mine",
    "tankshot", "pillshot", "build", "builderdeath", "tree", "bubbles",
    "sink", "msgreceived",
]

/// `far*` name -> its near-name source buffer, per D122's exact pairing (`fshot` shares
/// `tankshot`'s buffer and is used for BOTH `tankshot`'s and `pillshot`'s far variant -- there
/// is no separate `fpillshot`).
public let farNameSources: [String: String] = [
    "fexplosion": "explosion",
    "fsuperboom": "superboom",
    "fhittank": "hittank",
    "fhitterrain": "hitterrain",
    "fhittree": "hittree",
    "fbuild": "build",
    "fbuilderdeath": "builderdeath",
    "ftree": "tree",
    "fsink": "sink",
    "fshot": "tankshot",
]
