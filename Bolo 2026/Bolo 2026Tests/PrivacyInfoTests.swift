//
//  PrivacyInfoTests.swift
//  Bolo 2026Tests
//
//  v1.2.0 #12 -- the app must ship a privacy manifest covering the required-reason
//  APIs we actually call (UserDefaults). TEST_HOST is the app, so Bundle.main is
//  Bolo 2026.app.

import Foundation
import Testing

struct PrivacyInfoTests {
    @Test func appBundleContainsPrivacyManifestDeclaringUserDefaultsCA921() throws {
        let url = try #require(
            Bundle.main.url(forResource: "PrivacyInfo", withExtension: "xcprivacy"),
            "PrivacyInfo.xcprivacy missing from the app bundle"
        )
        let data = try Data(contentsOf: url)
        let plist = try #require(
            PropertyListSerialization.propertyList(from: data, format: nil) as? [String: Any]
        )

        #expect(plist["NSPrivacyTracking"] as? Bool == false)

        let accessed = try #require(plist["NSPrivacyAccessedAPITypes"] as? [[String: Any]])
        let userDefaults = accessed.first {
            $0["NSPrivacyAccessedAPIType"] as? String
                == "NSPrivacyAccessedAPICategoryUserDefaults"
        }
        let reasons = try #require(userDefaults?["NSPrivacyAccessedAPITypeReasons"] as? [String])
        #expect(reasons.contains("CA92.1"))
    }
}
