import Foundation
import Testing
@testable import Bolo_2026

// Issue #22 -- "Host a Game" / "Join Last Host" App Intents. `AppIntentRouter` and
// `LastJoinedHostStore` are the two testable-without-a-view pieces; the SwiftUI-side
// consumption in `HostGameView`/`JoinGameView`/`NewGameView` needs a live view hierarchy and
// isn't exercised here, matching `BoloJoinURLTests.swift`'s own precedent of testing the pure
// seam and leaving the view glue unverified by a unit test.

@MainActor
struct AppIntentsTests {
    @Test func hostGameIntentSetsPendingHostGame() async throws {
        AppIntentRouter.shared.pendingAction = nil
        defer { AppIntentRouter.shared.pendingAction = nil }
        _ = try await HostGameIntent().perform()
        #expect(AppIntentRouter.shared.pendingAction == .hostGame)
    }

    @Test func joinLastHostIntentSetsPendingJoinLastHost() async throws {
        AppIntentRouter.shared.pendingAction = nil
        defer { AppIntentRouter.shared.pendingAction = nil }
        _ = try await JoinLastHostIntent().perform()
        #expect(AppIntentRouter.shared.pendingAction == .joinLastHost)
    }
}

@Suite(.serialized)
struct LastJoinedHostStoreTests {
    private static let hostKey = "GSLastJoinHostString"
    private static let portKey = "GSLastJoinPortNumber"

    private func withRestoredDefaults(_ body: () -> Void) {
        let defaults = UserDefaults.standard
        let previousHost = defaults.object(forKey: Self.hostKey)
        let previousPort = defaults.object(forKey: Self.portKey)
        defer {
            if let previousHost { defaults.set(previousHost, forKey: Self.hostKey) } else {
                defaults.removeObject(forKey: Self.hostKey)
            }
            if let previousPort { defaults.set(previousPort, forKey: Self.portKey) } else {
                defaults.removeObject(forKey: Self.portKey)
            }
        }
        body()
    }

    @Test func recordThenLoadRoundTrips() {
        withRestoredDefaults {
            LastJoinedHostStore.record(LastJoinedHost(host: "192.0.2.10", port: 50000))
            #expect(LastJoinedHostStore.load() == LastJoinedHost(host: "192.0.2.10", port: 50000))
        }
    }

    @Test func loadReturnsNilWhenNothingRecorded() {
        withRestoredDefaults {
            UserDefaults.standard.removeObject(forKey: Self.hostKey)
            UserDefaults.standard.removeObject(forKey: Self.portKey)
            #expect(LastJoinedHostStore.load() == nil)
        }
    }

    @Test func loadReturnsNilWhenPortOutOfUInt16Range() {
        withRestoredDefaults {
            UserDefaults.standard.set("192.0.2.10", forKey: Self.hostKey)
            UserDefaults.standard.set(999_999, forKey: Self.portKey)
            #expect(LastJoinedHostStore.load() == nil)
        }
    }

    @Test func loadReturnsNilWhenHostIsEmpty() {
        withRestoredDefaults {
            UserDefaults.standard.set("", forKey: Self.hostKey)
            UserDefaults.standard.set(50000, forKey: Self.portKey)
            #expect(LastJoinedHostStore.load() == nil)
        }
    }

    @Test func recordOverwritesPreviousValue() {
        withRestoredDefaults {
            LastJoinedHostStore.record(LastJoinedHost(host: "192.0.2.10", port: 50000))
            LastJoinedHostStore.record(LastJoinedHost(host: "203.0.113.5", port: 12345))
            #expect(LastJoinedHostStore.load() == LastJoinedHost(host: "203.0.113.5", port: 12345))
        }
    }
}
