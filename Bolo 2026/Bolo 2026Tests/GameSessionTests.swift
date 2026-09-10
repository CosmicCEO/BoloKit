//
//  GameSessionTests.swift
//  Bolo 2026Tests
//
//  D144 -- headless coverage for `GameSession`'s single-process dispatch paths (the only
//  constructor exercisable without real `BoloNet` networking/listener machinery; see
//  docs/AGENT_NOTES.md's D144 pre-brief for why the host/join constructors stay out of scope
//  this pass). Uses a synthetic 1x1 `CGImage` for `tilesImage`/`spritesImage` -- confirmed safe
//  by direct read of `GameRenderView.swift`: `init`/`render(_:)` never touch image dimensions,
//  and `draw(_:)`'s `cropping(to:)` calls already guard against `nil` (out-of-bounds rect),
//  which a headless test never triggers anyway (no real display, `draw(_:)` never called).

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
private func makeSession(players: [PlayerState] = [PlayerState()]) -> GameSession {
    var state = GameState()
    state.players = players
    state.localPlayer = 0
    let image = makeTrivialImage()
    return GameSession(initialState: state, tilesImage: image, spritesImage: image)
}

@MainActor
struct GameSessionTests {

    @Test func singleProcessSendMessageAppendsChatMessageDirectly() {
        var player = PlayerState()
        player.name = "Jerod"
        let session = makeSession(players: [player])

        session.sendMessage(text: "gg", target: .everyone)

        #expect(session.messages.count == 1)
        #expect(session.messages[0].text == "gg")
        #expect(session.messages[0].player == 0)
        #expect(session.messages[0].senderName == "Jerod")
        #expect(session.messages[0].to == MessageTarget.everyone.rawValue)
    }

    @Test func singleProcessSendMessageAssignsMonotonicIDs() {
        let session = makeSession()

        session.sendMessage(text: "one", target: .everyone)
        session.sendMessage(text: "two", target: .allies)

        #expect(session.messages.count == 2)
        #expect(session.messages[0].id != session.messages[1].id)
    }

    @Test func canKickBanIsFalseWithoutAHostEngine() {
        let session = makeSession()
        #expect(session.canKickBan == false)
    }

    @Test func kickAndBanPlayerAreSafeNoOpsWithoutAHostEngine() {
        // No `hostEngine` on the single-process path -- both route through `hostEngine?.` and
        // must not crash when it's `nil`.
        let session = makeSession()
        session.kickPlayer(0)
        session.banPlayer(0)
    }

    @Test func singleProcessRequestAllianceMutatesStateDirectly() {
        var players = [PlayerState(), PlayerState()]
        players[0].used = true
        players[1].used = true
        let session = makeSession(players: players)

        session.requestAlliance(0b10)

        // Single-process path (no hostEngine/tcpSession): BoloKit.requestAlliance mutates
        // `session.state` directly, no round trip needed.
        #expect(session.state.players[0].alliance & 0b10 != 0)
    }

    @Test func singleProcessLeaveAllianceMutatesStateDirectly() {
        var players = [PlayerState(), PlayerState()]
        players[0].used = true
        players[1].used = true
        players[0].alliance = 0b11
        players[1].alliance = 0b11
        let session = makeSession(players: players)

        session.leaveAlliance(0b10)

        #expect(session.state.players[0].alliance & 0b10 == 0)
    }
}
