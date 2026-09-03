import Testing
import BoloKit
import BoloNet
import CXBolo

// Struct-layout ground truth + round-trip coverage for Wave 6.3's three
// preamble structs (Sources/BoloNet/Preambles.swift), oracle-extracted in
// Sources/CXBolo/netops.c's preamble_layout_oracle(). Unlike CLUpdate
// (Wave 6.0), these have no pre-existing real-C encode/decode function to
// fuzz byte-for-byte against -- the pre-brief's test plan calls only for
// sizeof/offsetof layout checks, matching every other wire struct
// (CL*/SR*) whose oracle coverage is layout-only.

@Suite struct PreamblesDifferentialTests {

    @Test func testPreambleLayoutMatchesOracle() {
        let L = CXBolo.preamble_layout_oracle()

        // JOIN_Preamble (bolo.h:448-452): ident[8] + version(1) + name[16] + pass[32].
        #expect(Int(L.sizeofJoinPreamble) == 8 + 1 + 16 + 32)
        #expect(Int(L.offJoinName) == 9)
        #expect(Int(L.offJoinPass) == 25)

        // BOLO_Preamble (bmap.h:18-39).
        #expect(Int(L.offBoloPlayer) == 9)
        #expect(Int(L.offBoloHiddenMines) == 10)
        #expect(Int(L.offBoloPause) == 11)
        #expect(Int(L.offBoloGameType) == 12)
        #expect(Int(L.offBoloDominationType) == 13)
        #expect(Int(L.offBoloDominationBaseControl) == 14)
        #expect(Int(L.offBoloPlayers) == 15)
        // Per-player entry: used(1) + connected(1) + seq(4) + name[16] + host[32] + alliance(2).
        #expect(Int(L.sizeofBoloPlayerEntry) == 1 + 1 + 4 + 16 + 32 + 2)
        #expect(Int(L.offEntryUsed) == 0)
        #expect(Int(L.offEntryConnected) == 1)
        #expect(Int(L.offEntrySeq) == 2)
        #expect(Int(L.offEntryName) == 6)
        #expect(Int(L.offEntryHost) == 22)
        #expect(Int(L.offEntryAlliance) == 54)
        #expect(Int(L.offBoloMapLen) == Int(L.offBoloPlayers) + maxPlayers * Int(L.sizeofBoloPlayerEntry))
        #expect(Int(L.sizeofBoloPreamble) == Int(L.offBoloMapLen) + 4)

        // TRACKER_Preamble (tracker.h:35-38): ident[8] + version(1), not
        // `__attribute__((__packed__))`, but every field here is already
        // byte-sized so natural alignment can't introduce padding anyway.
        #expect(Int(L.sizeofTrackerPreamble) == 9)
    }

    @Test func testJoinPreambleRoundTrips() {
        let original = JoinPreamble(name: "Alice", pass: "secret")
        let decoded = JoinPreamble.decode(original.encode())
        #expect(decoded == original)
    }

    @Test func testJoinPreambleEncodeMatchesOracleSize() {
        let bytes = JoinPreamble(name: "Alice", pass: "secret").encode()
        #expect(bytes.count == Int(CXBolo.preamble_layout_oracle().sizeofJoinPreamble))
    }

    @Test func testJoinPreambleDecodeRejectsWrongIdent() {
        var bytes = JoinPreamble(name: "Alice", pass: "secret").encode()
        bytes[0] = 0
        #expect(JoinPreamble.decode(bytes) == nil)
    }

    @Test func testTrackerPreambleRoundTrips() {
        let original = TrackerPreamble()
        let decoded = TrackerPreamble.decode(original.encode())
        #expect(decoded == original)
        #expect(original.version == 0)  // TRACKERVERSION, distinct from NET_GAME_VERSION (1)
    }

    @Test func testTrackerPreambleEncodeMatchesOracleSize() {
        let bytes = TrackerPreamble().encode()
        #expect(bytes.count == Int(CXBolo.preamble_layout_oracle().sizeofTrackerPreamble))
    }

    private func samplePlayerEntries() -> [BoloPreamble.PlayerEntry] {
        (0..<maxPlayers).map { i in
            BoloPreamble.PlayerEntry(
                used: i % 2 == 0, connected: i % 3 == 0, seq: UInt32(i * 7),
                name: "Player\(i)", host: "host\(i)", alliance: UInt16(i)
            )
        }
    }

    @Test func testBoloPreambleRoundTrips() {
        let original = BoloPreamble(
            player: 3, hiddenMines: 1, pause: 255, dominationType: 1, baseControl: 60,
            players: samplePlayerEntries(), mapLength: 12345
        )
        let decoded = BoloPreamble.decode(original.encode())
        #expect(decoded == original)
    }

    @Test func testBoloPreambleEncodeMatchesOracleSize() {
        let bytes = BoloPreamble(
            player: 0, hiddenMines: 0, pause: 0, dominationType: 0, baseControl: 0,
            players: samplePlayerEntries(), mapLength: 0
        ).encode()
        #expect(bytes.count == Int(CXBolo.preamble_layout_oracle().sizeofBoloPreamble))
    }

    @Test func testBoloPreambleDecodeRejectsWrongIdent() {
        var bytes = BoloPreamble(
            player: 0, hiddenMines: 0, pause: 0, dominationType: 0, baseControl: 0,
            players: samplePlayerEntries(), mapLength: 0
        ).encode()
        bytes[0] = 0
        #expect(BoloPreamble.decode(bytes) == nil)
    }

    // MARK: - assembleBoloPreamble

    @Test func testAssembleBoloPreambleTranslatesIndefinitePauseSentinel() {
        var state = GameState()
        state.serverPauseTicks = -1
        let preamble = assembleBoloPreamble(player: 0, state: state, seq: [], mapLength: 0)
        #expect(preamble.pause == 255)
    }

    @Test func testAssembleBoloPreambleConvertsTicksToSecondsForFiniteCountdown() {
        var state = GameState()
        state.serverPauseTicks = Int(ticksPerSec) * 3
        let preamble = assembleBoloPreamble(player: 0, state: state, seq: [], mapLength: 0)
        #expect(preamble.pause == 3)
    }

    @Test func testAssembleBoloPreambleFillsMissingSlotsAsNeverUsed() {
        var player = PlayerState()
        player.used = true
        player.name = "Solo"
        var state = GameState()
        state.players = [player]  // far short of maxPlayers, like every other fixture in this suite

        let preamble = assembleBoloPreamble(player: 0, state: state, seq: [], mapLength: 0)
        #expect(preamble.players.count == maxPlayers)
        #expect(preamble.players[0].used)
        #expect(preamble.players[0].name == "Solo")
        #expect(!preamble.players[1].used)
        #expect(preamble.players[1].seq == 0)
    }
}
