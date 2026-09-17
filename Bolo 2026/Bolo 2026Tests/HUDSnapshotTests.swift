//
//  HUDSnapshotTests.swift
//  Bolo 2026Tests
//
//  v1.4.0 #23 -- confirms `HUDSnapshot` tracks `GameSession.state` through the single-process
//  tick path (the only constructor exercisable headlessly, same D144 constraint as
//  `GameSessionTests.swift`).

import CoreGraphics
import Testing
import BoloKit
import BoloNet

@testable import Bolo_2026

@MainActor
private func makeTrivialImage() -> CGImage {
    let ctx = CGContext(
        data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
        space: CGColorSpaceCreateDeviceRGB(),
        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
    )!
    return ctx.makeImage()!
}

@MainActor
private func makeSession(
    players: [PlayerState] = [PlayerState()],
    configure: (inout GameState) -> Void = { _ in }
) -> GameSession {
    var state = GameState()
    state.players = players
    state.localPlayer = 0
    configure(&state)
    let image = makeTrivialImage()
    return GameSession(initialState: state, tilesImage: image, spritesImage: image)
}

@MainActor
struct HUDSnapshotTests {
    @Test
    func snapshotIsPopulatedAtConstructionBeforeAnyTick() {
        let session = makeSession(players: [PlayerState(), PlayerState()])

        #expect(session.hudSnapshot.localPlayer == session.state.localPlayer)
        #expect(session.hudSnapshot.players.count == session.state.players.count)
        #expect(session.hudSnapshot.pills.count == session.state.pills.count)
        #expect(session.hudSnapshot.bases.count == session.state.bases.count)
    }

    @Test
    func snapshotTracksLocalResourcesAfterATick() {
        let session = makeSession()
        session.tick()

        #expect(session.hudSnapshot.localShells == session.state.local.shells)
        #expect(session.hudSnapshot.localArmour == session.state.local.armour)
        #expect(session.hudSnapshot.localTank == session.state.players[session.state.localPlayer].tank)
    }

    @Test
    func snapshotTracksPillAndBaseOwnershipAfterATick() {
        let session = makeSession { state in
            if !state.pills.isEmpty { state.pills[0].owner = 0 }
            if !state.bases.isEmpty { state.bases[0].owner = 0 }
        }
        session.tick()

        for i in session.state.pills.indices {
            #expect(session.hudSnapshot.pills[i].owner == session.state.pills[i].owner)
        }
        for i in session.state.bases.indices {
            #expect(session.hudSnapshot.bases[i].owner == session.state.bases[i].owner)
        }
    }

    @Test
    func snapshotTracksPlayerFieldsAfterATick() {
        let session = makeSession(players: [PlayerState(), PlayerState()])
        session.tick()

        for i in session.state.players.indices {
            #expect(session.hudSnapshot.players[i].name == session.state.players[i].name)
            #expect(session.hudSnapshot.players[i].connected == session.state.players[i].connected)
            #expect(session.hudSnapshot.players[i].used == session.state.players[i].used)
            #expect(session.hudSnapshot.players[i].alliance == session.state.players[i].alliance)
            #expect(session.hudSnapshot.players[i].mines == session.state.players[i].mines)
            #expect(session.hudSnapshot.players[i].trees == session.state.players[i].trees)
        }
    }
}
