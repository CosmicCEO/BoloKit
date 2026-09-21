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

    @Test func tickRecordsIntervalAndDoesNotCrash() {
        let session = makeSession()
        session.tick()
        session.tick()
        #expect(session.recentTickIntervals.count == 1)
        #expect(session.recentTickIntervals[0] > 0)
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

    @Test func canHostAdminIsFalseWithoutAHostEngine() {
        let session = makeSession()
        #expect(session.canHostAdmin == false)
    }

    @Test func hostAdminCommandsAreSafeNoOpsWithoutAHostEngine() {
        let session = makeSession()
        session.pauseResumeServer()
        session.setAllowJoin(false)
        session.unbanPlayer(index: 0)
        #expect(session.allowJoin)
        #expect(session.bannedPlayers.isEmpty)
    }

    @Test func hostAdminReadsPauseAndBanListFromStateOnSingleProcessPath() {
        let session = makeSession { state in
            state.serverPauseTicks = 50
            state.allowJoin = false
            state.bannedPlayers = [BannedPlayer(name: "Eve", address: "1.2.3.4")]
        }
        #expect(session.isServerPaused)
        #expect(!session.allowJoin)
        #expect(session.bannedPlayers == [BannedPlayer(name: "Eve", address: "1.2.3.4")])
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

    @Test func singleProcessTickAppendsTimeLimitWarningToTheOneSink() {
        var player = PlayerState()
        player.name = "Jerod"
        player.connected = true
        let session = makeSession(players: [player]) { state in
            state.timeLimit = 10
            state.ticks = UInt64(Int(ticksPerSec) * 10 - Int(ticksPerSec) * 5)
        }

        session.tick()

        #expect(session.messages.count == 1)
        #expect(session.messages[0].to == EventLogText.gameTarget)
        #expect(session.messages[0].text == "5 Seconds Remaining!")
        #expect(session.messages[0].displayText == "5 Seconds Remaining!")
    }

    @Test func singleProcessTickAtTimeLimitReachedDrivesMatchEndOverlay() {
        var player = PlayerState()
        player.connected = true
        let session = makeSession(players: [player]) { state in
            state.timeLimit = 10
            state.ticks = UInt64(Int(ticksPerSec) * 10)
        }

        session.tick()

        #expect(session.messages.map(\.text) == [EventLogText.timeLimitReached])
        #expect(MatchEndMath.kind(from: session.messages) == .timeLimit)
    }

    @Test func singleProcessRequestAllianceAppendsRequestedLine() {
        var players = [PlayerState(), PlayerState()]
        players[0].used = true
        players[0].connected = true
        players[0].name = "Alice"
        players[0].alliance = 0b01
        players[1].used = true
        players[1].connected = true
        players[1].name = "Bob"
        players[1].alliance = 0b10
        let session = makeSession(players: players)

        session.requestAlliance(0b10)

        #expect(session.messages.map(\.text) == ["requested alliance with Bob"])
        #expect(session.messages[0].to == EventLogText.gameTarget)
    }

    @Test func joinTransportEndedAppendsDisconnectedLocalToTheOneSink() {
        let session = makeSession()
        session.appendDisconnectedLocal()
        #expect(session.messages.count == 1)
        #expect(session.messages[0].text == EventLogText.disconnectedLocal)
        #expect(session.messages[0].to == EventLogText.gameTarget)
        #expect(session.messages[0].displayText == "disconnected")
    }
}

// MARK: - Issue #85: the host's own player name

/// #62 S4: once the host has told a guest its combat state (`SRTankStatus`), the host simulates
/// that guest's tank, so the guest must stop simulating/reporting the same things itself.
struct JoinTickThinningTests {
    @Test func aGuestNotYetSimulatedByItsHostKeepsTheOldBehaviour() {
        let policy = JoinTickThinning(hostSimulatesMe: false)
        #expect(policy.sendsTileEntry && policy.sendsShellDamage && policy.runsOwnMovementWhileDead)
    }

    @Test func aGuestSimulatedByItsHostStopsReportingAndRespawningItself() {
        let policy = JoinTickThinning(hostSimulatesMe: true)
        #expect(!policy.sendsTileEntry && !policy.sendsShellDamage && !policy.runsOwnMovementWhileDead)
    }
}

struct HostPlayerNameTests {
    @Test func storedNameIsUsedWhenNonEmpty() {
        #expect(hostPlayerDisplayName(stored: "Ace") == "Ace")
    }

    @Test func missingOrEmptyStoredNameFallsBackToTheShippedDefault() {
        #expect(hostPlayerDisplayName(stored: nil) == "Newbie")
        #expect(hostPlayerDisplayName(stored: "") == "Newbie")
    }
}
