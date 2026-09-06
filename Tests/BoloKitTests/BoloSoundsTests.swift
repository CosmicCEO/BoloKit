import Testing
import BoloSoundsCore

@Suite("BoloSounds procedural synthesis (Milestone C, C.3)")
struct BoloSoundsTests {

    // MARK: - Primitive-level tests

    @Test("whiteNoise is deterministic for a fixed seed, correct length, and amplitude-bounded")
    func whiteNoiseDeterministicLengthAmplitude() {
        let a = whiteNoise(duration: 0.2, seed: 42, amplitude: 0.5)
        let b = whiteNoise(duration: 0.2, seed: 42, amplitude: 0.5)
        #expect(a.samples == b.samples)

        let expectedLength = Int((0.2 * sampleRate).rounded())
        #expect(a.samples.count == expectedLength)

        #expect(a.samples.allSatisfy { abs($0) <= 0.5 })

        let c = whiteNoise(duration: 0.2, seed: 99, amplitude: 0.5)
        #expect(a.samples != c.samples)
    }

    @Test("adEnvelope ramps to 1.0 at the attack/decay boundary, then decays monotonically non-increasing")
    func adEnvelopeShape() {
        let envelope = adEnvelope(attackTime: 0.01, decayTime: 0.1, decayRate: 0.05)
        let attackSamples = Int((0.01 * sampleRate).rounded())

        #expect(envelope[0] < 0.2)
        #expect(abs(envelope[attackSamples - 1] - 1.0) < 0.05)

        var previous = envelope[attackSamples]
        for i in (attackSamples + 1)..<envelope.count {
            #expect(envelope[i] <= previous + 0.0001)
            previous = envelope[i]
        }
        #expect(envelope.last! < 0.2)
    }

    @Test("toneSweep produces the correct buffer length for both a plain tone and a sweep")
    func toneSweepLength() {
        let tone = toneSweep(duration: 0.1, startFreq: 440, endFreq: 440, amplitude: 1.0)
        #expect(tone.samples.count == Int((0.1 * sampleRate).rounded()))

        let sweep = toneSweep(duration: 0.1, startFreq: 300, endFreq: 900, amplitude: 1.0)
        #expect(sweep.samples.count == tone.samples.count)
        #expect(sweep.samples.contains { $0 != 0 })
    }

    @Test("lowpass preserves buffer length and measurably attenuates a high-frequency tone")
    func lowpassAttenuatesHighFrequency() {
        let highTone = toneSweep(duration: 0.1, startFreq: 8000, endFreq: 8000, amplitude: 1.0)
        let filtered = lowpass(highTone, cutoffHz: 800)

        #expect(filtered.samples.count == highTone.samples.count)

        func rms(_ samples: [Float]) -> Float {
            let sumSquares = samples.reduce(Float(0)) { $0 + $1 * $1 }
            return (sumSquares / Float(samples.count)).squareRoot()
        }

        #expect(rms(filtered.samples) < rms(highTone.samples) * 0.5)
    }

    // MARK: - SampleBuffer helpers

    @Test("SampleBuffer.mix sums overlapping samples and extends to the longer length")
    func sampleBufferMix() {
        let a = SampleBuffer(samples: [1, 1, 1])
        let b = SampleBuffer(samples: [1, 1])
        let mixed = a.mix(b)
        #expect(mixed.samples == [2, 2, 1])
    }

    @Test("SampleBuffer.trimOrPad trims and pads to the exact requested duration")
    func sampleBufferTrimOrPad() {
        let short = SampleBuffer(samples: [1, 1])
        let padded = short.trimOrPad(to: 4.0 / sampleRate)
        #expect(padded.samples == [1, 1, 0, 0])

        let long = SampleBuffer(samples: [1, 1, 1, 1])
        let trimmed = long.trimOrPad(to: 2.0 / sampleRate)
        #expect(trimmed.samples == [1, 1])
    }

    // MARK: - Per-name integration tests

    @Test("buildSounds() returns exactly the 24 expected names")
    func buildSoundsNameCoverage() {
        let sounds = buildSounds()
        #expect(sounds.count == 24)
        for name in allSoundNames {
            #expect(sounds[name] != nil, "missing buffer for \(name)")
        }
        #expect(allSoundNames.count == 24)
        #expect(Set(allSoundNames).count == 24)
    }

    @Test("every named sound is non-empty and within its designed duration range")
    func perNameDurationRanges() {
        let sounds = buildSounds()
        let expectedDurations: [String: Double] = [
            "explosion": 0.5, "superboom": 0.9, "hittank": 0.15, "hitterrain": 0.2,
            "hittree": 0.15, "mine": 0.35, "tankshot": 0.1, "pillshot": 0.1,
            "tree": 0.08, "bubbles": 0.4, "sink": 0.6,
        ]
        for (name, expected) in expectedDurations {
            guard let buffer = sounds[name] else {
                Issue.record("missing \(name)")
                continue
            }
            #expect(!buffer.samples.isEmpty)
            #expect(abs(buffer.duration - expected) < 0.01, "\(name) duration \(buffer.duration) != \(expected)")
        }
        // build/builderdeath/msgreceived are pulse sequences -- just verify non-empty + roughly
        // in the expected magnitude (a few hundred ms), not an exact duration.
        for name in ["build", "builderdeath", "msgreceived"] {
            guard let buffer = sounds[name] else {
                Issue.record("missing \(name)")
                continue
            }
            #expect(!buffer.samples.isEmpty)
            #expect(buffer.duration > 0.05 && buffer.duration < 1.0)
        }
    }

    @Test("far* names are measurably attenuated (high-frequency content reduced) vs. their near counterpart")
    func farNamesAreAttenuated() {
        let sounds = buildSounds()

        func highFrequencyEnergy(_ samples: [Float]) -> Float {
            // Simple first-difference proxy for high-frequency content: a heavily lowpassed
            // signal has much smaller sample-to-sample deltas than its unfiltered source.
            guard samples.count > 1 else { return 0 }
            var sum: Float = 0
            for i in 1..<samples.count {
                let diff = samples[i] - samples[i - 1]
                sum += diff * diff
            }
            return sum
        }

        for (farName, nearName) in farNameSources {
            guard let farBuffer = sounds[farName], let nearBuffer = sounds[nearName] else {
                Issue.record("missing \(farName)/\(nearName)")
                continue
            }
            let farEnergy = highFrequencyEnergy(farBuffer.samples)
            let nearEnergy = highFrequencyEnergy(nearBuffer.samples)
            #expect(farEnergy < nearEnergy, "\(farName) not measurably attenuated vs \(nearName)")
        }
    }

    @Test("fshot is shared: it equals lowpass(tankshot), and is the only far entry pillshot maps to")
    func fshotSharedPairing() {
        let sounds = buildSounds()
        guard let fshot = sounds["fshot"], let tankshot = sounds["tankshot"] else {
            Issue.record("missing fshot/tankshot")
            return
        }
        #expect(fshot.samples == lowpass(tankshot, cutoffHz: farCutoffHz).samples)
        #expect(sounds["fpillshot"] == nil)
        #expect(farNameSources["fshot"] == "tankshot")
    }

    // MARK: - Determinism regression (mirrors BoloGlyphsCore's buildSheets() equality test)

    @Test("buildSounds() is deterministic across repeated calls")
    func buildSoundsDeterministic() {
        let a = buildSounds()
        let b = buildSounds()
        #expect(a.count == b.count)
        for (name, bufferA) in a {
            #expect(bufferA.samples == b[name]?.samples, "\(name) differs between calls")
        }
    }
}
