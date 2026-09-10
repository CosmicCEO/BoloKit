//
//  HostGameViewTests.swift
//  Bolo 2026Tests
//
//  D144 -- headless coverage for `HostGameView.decodeAndPostProcessMap`, the pure decode/
//  post-process/validate core factored out of `applyDecodedMap` specifically so it could be
//  tested without a live SwiftUI environment. `applyDecodedMap`/`handleMapPickerResult`
//  themselves stay thin `@State`-touching wrappers around it and are NOT tested directly here --
//  a `HostGameView` instantiated outside SwiftUI's real environment does not reliably persist
//  `@State` writes back to the caller (confirmed empirically: an earlier version of this file
//  asserted on `view.mapState`/`view.mapErrorMessage` after calling `applyDecodedMap` directly,
//  and every such assertion read back a stale `nil` under a real `xcodebuild test` run, while
//  the `@State`-free `GameSessionTests` in this same target passed cleanly) -- so this file
//  targets the pure function `decodeAndPostProcessMap` was extracted into instead, per D144's
//  own "pure logic extractable... without a display/window server" scope.

import Testing
import BoloKit

@testable import Bolo_2026

private func bmapBytes(npills: UInt8 = 0, nbases: UInt8 = 0, nstarts: UInt8 = 0, tail: [UInt8] = []) -> [UInt8] {
    var bytes: [UInt8] = Array("BMAPBOLO".utf8)
    bytes.append(1)  // CURRENT_MAP_VERSION
    bytes.append(npills)
    bytes.append(nbases)
    bytes.append(nstarts)
    bytes.append(contentsOf: tail)
    // Sentinel BMapRun: {datalen: 4, y: 0xff, startx: 0xff, endx: 0xff} -- terminates the run
    // stream with zero terrain runs, i.e. an all-default (`.mapDefault()`) terrain grid.
    bytes.append(contentsOf: [4, 0xff, 0xff, 0xff])
    return bytes
}

struct HostGameViewTests {

    @Test func decodeAndPostProcessMapRejectsGarbageBytes() {
        let outcome = HostGameView.decodeAndPostProcessMap(bytes: [0, 1, 2, 3])

        guard case .failure(let message) = outcome else {
            Issue.record("expected .failure, got \(outcome)")
            return
        }
        #expect(message == "Incompatible Map Version")
    }

    @Test func decodeAndPostProcessMapRejectsAMapWithNoStartPoints() {
        let outcome = HostGameView.decodeAndPostProcessMap(bytes: bmapBytes(nstarts: 0))

        guard case .failure(let message) = outcome else {
            Issue.record("expected .failure, got \(outcome)")
            return
        }
        #expect(message == "Map Has No Start Points")
    }

    @Test func decodeAndPostProcessMapAcceptsAValidMapWithAStartPoint() {
        // One BMAP_StartInfo record: x=5, y=5, dir=0 (3 bytes), nstarts=1.
        let outcome = HostGameView.decodeAndPostProcessMap(bytes: bmapBytes(nstarts: 1, tail: [5, 5, 0]))

        guard case .success(let decoded) = outcome else {
            Issue.record("expected .success, got \(outcome)")
            return
        }
        #expect(decoded.starts.count == 1)
        // D131: this is the host's own post-process path -- starts are cleared to sea --
        // confirmed running (not just decode) by checking the one observable side effect
        // reachable with zero pills/bases: the start tile itself is sea after post-process.
        #expect(decoded.terrain[5, 5] == .sea)
    }

    @Test func decodeAndPostProcessMapForcesPillOwnerToNeutral() {
        // One BMAP_PillInfo record: x=3, y=3, owner=2 (some real player), armour=10, speed=5,
        // plus one start so the no-starts guard doesn't short-circuit before the pill assertion.
        let tail: [UInt8] = [3, 3, 2, 10, 5] + [5, 5, 0]
        let outcome = HostGameView.decodeAndPostProcessMap(bytes: bmapBytes(npills: 1, nstarts: 1, tail: tail))

        guard case .success(let decoded) = outcome else {
            Issue.record("expected .success, got \(outcome)")
            return
        }
        #expect(decoded.pills.count == 1)
        // D131/`serverPostProcessLoadedMap`: pill owner always forced to NEUTRAL server-side,
        // regardless of whatever the map file itself stored (owner=2 above).
        #expect(decoded.pills[0].owner == playerNeutral)
    }
}
