//
//  AppInfoPlistTests.swift
//  Bolo 2026Tests
//
//  v1.2.0 #13 / #11 -- generated Info.plist keys and exported document types.
//  TEST_HOST is the app, so Bundle.main is Bolo 2026.app.

import Foundation
import Testing

struct AppInfoPlistTests {
    private var info: [String: Any] { Bundle.main.infoDictionary ?? [:] }

    @Test func applicationCategoryIsGames() {
        #expect(info["LSApplicationCategoryType"] as? String == "public.app-category.games")
    }

    @Test func supportsGameModeKeysAreTrue() {
        #expect(info["LSSupportsGameMode"] as? Bool == true)
        #expect(info["GCSupportsGameMode"] as? Bool == true)
    }

    @Test func humanReadableCopyrightIsNonEmpty() {
        let copyright = info["NSHumanReadableCopyright"] as? String ?? ""
        #expect(!copyright.isEmpty)
    }

    @Test func compiledAppIconIcnsIsInTheBundle() {
        #expect(Bundle.main.url(forResource: "AppIcon", withExtension: "icns") != nil)
    }

    @Test func exportsBoloMapUTIAsViewer() {
        let exported = info["UTExportedTypeDeclarations"] as? [[String: Any]] ?? []
        let ids = exported.compactMap { $0["UTTypeIdentifier"] as? String }
        #expect(ids.contains("com.cosmicceo.bolo-map"))

        let docs = info["CFBundleDocumentTypes"] as? [[String: Any]] ?? []
        let map = docs.first {
            ($0["LSItemContentTypes"] as? [String])?.contains("com.cosmicceo.bolo-map") == true
        }
        #expect(map?["CFBundleTypeRole"] as? String == "Viewer")
    }
}
