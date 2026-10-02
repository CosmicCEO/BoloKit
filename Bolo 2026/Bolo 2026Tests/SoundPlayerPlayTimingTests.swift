//
//  SoundPlayerPlayTimingTests.swift
//  Bolo 2026Tests
//
//  Improve item 2D (2026-10-02) -- `SoundPlayer.play` runs on the host's 20 ms tick, so it must
//  not read or decode an AIFF from disk per call. Uses the real bundled sounds (TEST_HOST is the
//  app, so Bundle.main is Bolo 2026.app).

import Foundation
import Testing
@testable import Bolo_2026

struct SoundPlayerPlayTiming {
    @MainActor
    @Test func SoundPlayerPlayIsCheapOnTheMainThread() async throws {
        UserDefaults.standard.set(false, forKey: "GSMuteBool")
        #expect(Bundle.main.url(forResource: "tankshot", withExtension: "aiff") != nil)

        let clock = ContinuousClock()
        let player = SoundPlayer.shared
        player.play("tankshot")  // warm-up
        try await Task.sleep(for: .milliseconds(50))

        var millis: [Double] = []
        for _ in 0..<50 {
            let elapsed = clock.measure { player.play("tankshot") }
            let c = elapsed.components
            millis.append(Double(c.seconds) * 1000 + Double(c.attoseconds) / 1e15)
            try await Task.sleep(for: .milliseconds(30))
        }
        millis.sort()
        let maxMs = millis.last ?? 0
        let medianMs = (millis[24] + millis[25]) / 2
        print("SoundPlayerPlay timing: max=\(maxMs) ms median=\(medianMs) ms")
        #expect(maxMs < 2.0, "max single play() \(maxMs) ms")
        #expect(medianMs < 0.5, "median play() \(medianMs) ms")
    }
}
