import Testing
import BoloKit

private func usedPlayer(name: String, connected: Bool) -> PlayerState {
    var p = PlayerState()
    p.used = true
    p.connected = connected
    p.name = name
    return p
}

private func alliedConnectedPlayer(alliance: UInt16) -> PlayerState {
    var p = PlayerState()
    p.used = true
    p.connected = true
    p.alliance = alliance
    return p
}

// MARK: - evaluateJoinRequest

@Suite struct EvaluateJoinRequestTests {

    @Test func rejectsWrongVersion() {
        let outcome = evaluateJoinRequest(
            name: "A", password: "", version: 0, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: [], players: [], ticksSinceLastUpdate: []
        )
        #expect(outcome == .rejected(.badVersion))
    }

    @Test func rejectsWrongPasswordOnlyWhenRequired() {
        let rejected = evaluateJoinRequest(
            name: "A", password: "wrong", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: true, serverPassword: "right", allowJoin: true,
            bannedPlayers: [], players: [PlayerState()], ticksSinceLastUpdate: [0]
        )
        #expect(rejected == .rejected(.badPassword))

        let accepted = evaluateJoinRequest(
            name: "A", password: "wrong", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "right", allowJoin: true,
            bannedPlayers: [], players: [PlayerState()], ticksSinceLastUpdate: [0]
        )
        #expect(accepted == .accepted(player: 0, rejoin: false))
    }

    @Test func rejectsWhenJoinNotAllowed() {
        let outcome = evaluateJoinRequest(
            name: "A", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: false,
            bannedPlayers: [], players: [PlayerState()], ticksSinceLastUpdate: [0]
        )
        #expect(outcome == .rejected(.notAllowed))
    }

    @Test func rejectsBannedNameAndAddressPairOnly() {
        let banned = [BannedPlayer(name: "A", address: "1.2.3.4")]

        let sameNameDifferentAddress = evaluateJoinRequest(
            name: "A", password: "", version: netGameVersionForTest, address: "9.9.9.9",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: banned, players: [PlayerState()], ticksSinceLastUpdate: [0]
        )
        #expect(sameNameDifferentAddress == .accepted(player: 0, rejoin: false))

        let exactMatch = evaluateJoinRequest(
            name: "A", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: banned, players: [PlayerState()], ticksSinceLastUpdate: [0]
        )
        #expect(exactMatch == .rejected(.banned))
    }

    @Test func matchesRejoinByNameOnAUsedDisconnectedSlot() {
        let players = [usedPlayer(name: "Bob", connected: false), usedPlayer(name: "Alice", connected: true)]
        let outcome = evaluateJoinRequest(
            name: "Bob", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: [], players: players, ticksSinceLastUpdate: [0, 0]
        )
        #expect(outcome == .accepted(player: 0, rejoin: true))
    }

    @Test func prefersRejoinOverAFreshSlotEvenIfFreshSlotComesFirst() {
        let players = [PlayerState(), usedPlayer(name: "Bob", connected: false)]
        let outcome = evaluateJoinRequest(
            name: "Bob", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: [], players: players, ticksSinceLastUpdate: [0, 0]
        )
        #expect(outcome == .accepted(player: 1, rejoin: true))
    }

    @Test func picksFirstNeverUsedSlotWhenNoRejoinMatches() {
        let players = [usedPlayer(name: "Someone", connected: true), PlayerState(), PlayerState()]
        let outcome = evaluateJoinRequest(
            name: "NewGuy", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: [], players: players, ticksSinceLastUpdate: [0, 0, 0]
        )
        #expect(outcome == .accepted(player: 1, rejoin: false))
    }

    /// The real trap from the pre-brief: when every slot has been used at
    /// least once and none is free, evict the *oldest* disconnected slot —
    /// strictly greater age wins, so a tie keeps the lowest index.
    @Test func evictsOldestDisconnectedSlotOnATie() {
        let players = [
            usedPlayer(name: "A", connected: false),
            usedPlayer(name: "B", connected: true),
            usedPlayer(name: "C", connected: false),
        ]
        let outcome = evaluateJoinRequest(
            name: "NewGuy", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: [], players: players, ticksSinceLastUpdate: [100, 0, 100]
        )
        #expect(outcome == .accepted(player: 0, rejoin: false))  // tie: lowest index wins

        let outcomeStrict = evaluateJoinRequest(
            name: "NewGuy", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: [], players: players, ticksSinceLastUpdate: [50, 0, 100]
        )
        #expect(outcomeStrict == .accepted(player: 2, rejoin: false))  // strictly oldest
    }

    @Test func rejectsAsServerFullWhenNoSlotIsAvailable() {
        let players = [usedPlayer(name: "A", connected: true), usedPlayer(name: "B", connected: true)]
        let outcome = evaluateJoinRequest(
            name: "NewGuy", password: "", version: netGameVersionForTest, address: "1.2.3.4",
            passwordRequired: false, serverPassword: "", allowJoin: true,
            bannedPlayers: [], players: players, ticksSinceLastUpdate: [0, 0]
        )
        #expect(outcome == .rejected(.serverFull))
    }
}

private let netGameVersionForTest: UInt8 = 1

// MARK: - applyJoin

@Suite struct ApplyJoinTests {

    @Test func newSlotSetsSelfOnlyAllianceAndStoresName() {
        var state = GameState(players: [PlayerState()])
        applyJoin(player: 0, name: "Alice", address: "1.2.3.4", rejoin: false, state: &state)
        #expect(state.players[0].alliance == 1 << 0)
        #expect(state.players[0].name == "Alice")
        #expect(state.players[0].used)
        #expect(state.players[0].connected)
        #expect(state.players[0].address == "1.2.3.4")
    }

    @Test func rejoinPreservesExistingAllianceAndName() {
        var player = usedPlayer(name: "Bob", connected: false)
        player.alliance = 0b1010
        var state = GameState(players: [player])
        applyJoin(player: 0, name: "Bob", address: "5.6.7.8", rejoin: true, state: &state)
        #expect(state.players[0].alliance == 0b1010)  // untouched, not reset to self-only
        #expect(state.players[0].name == "Bob")
        #expect(state.players[0].connected)
        #expect(state.players[0].address == "5.6.7.8")
    }
}

// MARK: - removePlayer

@Suite struct RemovePlayerTests {

    /// The direct `removeplayer()` call site (Wave 6.4b's socket-close
    /// disconnect path) has no broadcast callback of its own -- the
    /// caller sends `sendsrplayerexit`/`sendsrplayerdisc` separately
    /// depending on how the connection ended (T-13), so this function's
    /// whole contract is just the two `GameState` effects.
    @Test func disconnectsAndDropsOnboardPills() {
        var state = GameState(players: [usedPlayer(name: "A", connected: true)])
        state.terrain[50, 50] = .grass0
        state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
        state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]

        removePlayer(player: 0, state: &state)

        #expect(!state.players[0].connected)
        #expect(state.pills[0].armour != pillOnboard)
    }
}

// MARK: - kickPlayer / banPlayer

@Suite struct KickBanPlayerTests {

    @Test func kickDisconnectsAndDropsOnboardPills() {
        var state = GameState(players: [usedPlayer(name: "A", connected: true)])
        state.terrain[50, 50] = .grass0
        state.players[0].tank = Vec2f(x: 50.5, y: 50.5)
        state.pills = [Pill(x: 5, y: 5, armour: pillOnboard, owner: 0, speed: 10, counter: 0)]

        var kicked: Int?
        kickPlayer(player: 0, state: &state, onShouldBroadcastPlayerKick: { kicked = $0 })

        #expect(!state.players[0].connected)
        #expect(state.pills[0].armour != pillOnboard)
        #expect(kicked == 0)
    }

    @Test func banAppendsToListAndDropsPillsAndBroadcasts() {
        var state = GameState(players: [usedPlayer(name: "A", connected: true)])
        state.players[0].address = "1.2.3.4"
        state.terrain[50, 50] = .grass0
        state.players[0].tank = Vec2f(x: 50.5, y: 50.5)

        var banned: Int?
        banPlayer(player: 0, state: &state, onShouldBroadcastPlayerBan: { banned = $0 })

        #expect(!state.players[0].connected)
        #expect(state.bannedPlayers == [BannedPlayer(name: "A", address: "1.2.3.4")])
        #expect(banned == 0)
    }

    /// The real business-logic guard from `banplayer()` — banning an
    /// already-disconnected player is a silent no-op, not an assertion.
    @Test func banOnAlreadyDisconnectedPlayerIsANoOp() {
        var state = GameState(players: [usedPlayer(name: "A", connected: false)])
        var banned: Int?
        banPlayer(player: 0, state: &state, onShouldBroadcastPlayerBan: { banned = $0 })
        #expect(state.bannedPlayers.isEmpty)
        #expect(banned == nil)
    }
}

// MARK: - requestAlliance / leaveAlliance

@Suite struct AllianceTests {

    @Test func requestAllianceSetsOwnBitAndSendsUpdatedMask() {
        var state = GameState(players: [alliedConnectedPlayer(alliance: 0), alliedConnectedPlayer(alliance: 0)])
        state.localPlayer = 0
        var sent: UInt16?
        requestAlliance(withPlayers: 1 << 1, state: &state, onSendSetAlliance: { sent = $0 })
        #expect(state.players[0].alliance == 1 << 1)
        #expect(sent == 1 << 1)
    }

    @Test func requestAllianceFiresStatusCallbacksOnlyWhenAlreadyMutual() {
        // Player 1 already allied with us (bit 0 set in their mask); we
        // request them back -> mutual, fires callbacks + fog-of-war refresh
        // targets (bases/pills owned by player 1).
        var state = GameState(players: [
            alliedConnectedPlayer(alliance: 0),
            alliedConnectedPlayer(alliance: 1 << 0),
        ])
        state.localPlayer = 0
        state.bases = [Base(x: 1, y: 1, armour: 10, owner: 1, shells: 0, mines: 0)]
        state.pills = [Pill(x: 2, y: 2, armour: 10, owner: 1, speed: 10, counter: 0)]

        var playerNotified: Int?
        var baseNotified: Int?
        var pillNotified: Int?
        requestAlliance(
            withPlayers: 1 << 1, state: &state,
            onPlayerStatusChanged: { playerNotified = $0 },
            onBaseStatusChanged: { baseNotified = $0 },
            onPillStatusChanged: { pillNotified = $0 }
        )
        #expect(playerNotified == 1)
        #expect(baseNotified == 0)
        #expect(pillNotified == 0)
    }

    @Test func requestAllianceOneSidedFiresNoStatusCallback() {
        // Player 1 has NOT allied back -- "requested" branch, no GameState
        // effect on player 1's own status besides the mask change we made.
        var state = GameState(players: [alliedConnectedPlayer(alliance: 0), alliedConnectedPlayer(alliance: 0)])
        state.localPlayer = 0
        var playerNotified: Int?
        requestAlliance(withPlayers: 1 << 1, state: &state, onPlayerStatusChanged: { playerNotified = $0 })
        #expect(playerNotified == nil)
    }

    @Test func leaveAllianceClearsBitButAlwaysKeepsOwnBit() {
        var state = GameState(players: [alliedConnectedPlayer(alliance: (1 << 0) | (1 << 1))])
        state.localPlayer = 0
        leaveAlliance(withPlayers: UInt16(1 << 0), state: &state)  // try to clear our OWN bit too
        #expect(state.players[0].alliance & (1 << 0) != 0)  // survives -- `~withplayers | (1 << player)`
    }

    @Test func leaveAllianceFiresStatusCallbackWhenTheyWereMutuallyAllied() {
        var state = GameState(players: [
            alliedConnectedPlayer(alliance: 1 << 1),
            alliedConnectedPlayer(alliance: 1 << 0),
        ])
        state.localPlayer = 0
        var playerNotified: Int?
        var sent: UInt16?
        leaveAlliance(
            withPlayers: 1 << 1, state: &state,
            onSendSetAlliance: { sent = $0 },
            onPlayerStatusChanged: { playerNotified = $0 }
        )
        #expect(state.players[0].alliance & (1 << 1) == 0)
        #expect(playerNotified == 1)
        #expect(sent == state.players[0].alliance)
    }
}

// MARK: - recvClSetAlliance

@Suite struct RecvClSetAllianceTests {

    @Test func appliesGivenValueDirectlyAndBroadcasts() {
        var state = GameState(players: [PlayerState()])
        var broadcast: (Int, UInt16)?
        recvClSetAlliance(player: 0, alliance: 0xBEEF, state: &state, onShouldBroadcastAlliance: { broadcast = ($0, $1) })
        #expect(state.players[0].alliance == 0xBEEF)
        #expect(broadcast?.0 == 0)
        #expect(broadcast?.1 == 0xBEEF)
    }
}
