import Testing
@testable import BoloKit

// Regression: the app started hosting with `state.players = [hostPlayer]` (one slot), so
// `evaluateJoinRequest` found no free slot and rejected every joiner as "server is full".
// Found by the v1.5.0 two-Mac test once the fixed-port listener bug stopped hiding it.

struct HostPlayerSlotsTests {
    private func hostPlayer() -> PlayerState {
        var player = PlayerState()
        player.connected = true
        player.used = true
        return player
    }

    @Test func `Host table has maxPlayers slots with only slot 0 in use`() {
        let players = hostPlayerSlots(hostPlayer: hostPlayer())
        #expect(players.count == maxPlayers)
        #expect(players[0].used && players[0].connected)
        #expect(players.dropFirst().allSatisfy { !$0.used && !$0.connected })
    }

    @Test func `A fresh host accepts a new joiner into slot 1`() {
        let players = hostPlayerSlots(hostPlayer: hostPlayer())
        let outcome = evaluateJoinRequest(
            name: "Guest", password: "", version: netGameVersionForJoin, address: "192.168.1.2",
            passwordRequired: false, serverPassword: "", allowJoin: true, bannedPlayers: [],
            players: players, ticksSinceLastUpdate: Array(repeating: 0, count: players.count)
        )
        #expect(outcome == .accepted(player: 1, rejoin: false))
    }

    @Test func `A single-slot table is the bug: it rejects the joiner as server full`() {
        let players = [hostPlayer()]
        let outcome = evaluateJoinRequest(
            name: "Guest", password: "", version: netGameVersionForJoin, address: "192.168.1.2",
            passwordRequired: false, serverPassword: "", allowJoin: true, bannedPlayers: [],
            players: players, ticksSinceLastUpdate: [0]
        )
        #expect(outcome == .rejected(.serverFull))
    }
}
