import Testing
import BoloKit
import BoloNet

// D154 Wave 3 / D163: every C `printmessage` `asprintf` shape, including
// `client.c:3048` `Minute%s`/`Second%s` pluralization (`n > 1 ? "s" : ""`).

@Test func eventLogTextRosterMatchesCAsprintfShapes() {
    #expect(EventLogText.joined("Alice") == "Alice joined")
    #expect(EventLogText.rejoined("Bob") == "Bob rejoined")
    #expect(EventLogText.left("Carol") == "Carol left")
    #expect(EventLogText.disconnected("Dave") == "Dave disconnected")
    #expect(EventLogText.kicked("Eve") == "Eve kicked")
    #expect(EventLogText.banned("Frank") == "Frank banned")
    #expect(EventLogText.disconnectedLocal == "disconnected")
    #expect(EventLogText.lostBuilder("Gina") == "Gina just lost his builder")
}

@Test func eventLogTextCaptureMatchesCAsprintfShapes() {
    #expect(EventLogText.capturedNeutralPill(capturer: "Alice", pill: 3) == "Alice captured neutral pill 3")
    #expect(EventLogText.capturedPill(capturer: "Alice", pill: 3, from: "Bob") == "Alice captured pill 3 from Bob")
    #expect(EventLogText.capturedNeutralBase(capturer: "Alice", base: 1) == "Alice captured neutral base 1")
    #expect(EventLogText.capturedBase(capturer: "Alice", base: 1, from: "Bob") == "Alice captured base 1 from Bob")
}

@Test func eventLogTextCapturePillIsGatedOnOwnerChange() {
    #expect(
        EventLogText.capturePill(
            capturer: "Alice", pill: 0, previousOwner: 1, previousOwnerName: "Bob", newOwner: 1
        ) == nil
    )
    #expect(
        EventLogText.capturePill(
            capturer: "Alice", pill: 0, previousOwner: playerNeutral, previousOwnerName: "", newOwner: 0
        ) == "Alice captured neutral pill 0"
    )
}

@Test func eventLogTextAllianceMatchesCAsprintfShapes() {
    #expect(EventLogText.acceptedTheAlliance("Alice") == "Alice accepted the alliance")
    #expect(EventLogText.leftTheAlliance("Alice") == "Alice left the alliance")
    #expect(EventLogText.requestsAnAlliance("Alice") == "Alice requests an alliance")
    #expect(EventLogText.allianceAcceptedWith("Alice") == "alliance accepted with Alice")
    #expect(EventLogText.requestedAllianceWith("Alice") == "requested alliance with Alice")
    #expect(EventLogText.leftAllianceWith("Alice") == "left alliance with Alice")
}

@Test func eventLogTextClockPluralizationMatchesClientC3048() {
    #expect(EventLogText.timeLimitRemaining(61) == "1 Minute and 1 Second Remaining!")
    #expect(EventLogText.timeLimitRemaining(62) == "1 Minute and 2 Seconds Remaining!")
    #expect(EventLogText.timeLimitRemaining(121) == "2 Minutes and 1 Second Remaining!")
    #expect(EventLogText.timeLimitRemaining(122) == "2 Minutes and 2 Seconds Remaining!")
    #expect(EventLogText.timeLimitRemaining(60) == "1 Minute Remaining!")
    #expect(EventLogText.timeLimitRemaining(120) == "2 Minutes Remaining!")
    #expect(EventLogText.timeLimitRemaining(1) == "1 Second Remaining!")
    #expect(EventLogText.timeLimitRemaining(2) == "2 Seconds Remaining!")
    #expect(EventLogText.timeLimitRemaining(0) == "Time Limit Reached!")
    #expect(EventLogText.baseControlRemaining(10) == "10 Seconds Remaining!")
    #expect(EventLogText.baseControlRemaining(0) == "Base Control Reached!")
}

@Test func eventLogTextBuilderNeedLiteralsMatchC() {
    #expect(EventLogText.needMoreTrees == "You need more trees.")
    #expect(EventLogText.needAPill == "You need a pill.")
    #expect(EventLogText.needMoreMines == "You need more mines.")
    #expect(EventLogText.wouldKillBuilder == "Your builder cannot do that.  It would kill him.")
}

@Test func eventLogTextRemoteAllianceAcceptedWhenBothBitsSet() {
    // Local player 0 already has bit 1; player 1's new mask now includes bit 0.
    let line = EventLogText.remoteAllianceChange(
        localPlayer: 0, actor: 1, actorName: "Bob",
        previousAlliance: 0b10, newAlliance: 0b11, localAlliance: 0b11
    )
    #expect(line == "Bob accepted the alliance")
}

@Test func eventLogTextRemoteAllianceLeftWhenTheirBitClears() {
    let line = EventLogText.remoteAllianceChange(
        localPlayer: 0, actor: 1, actorName: "Bob",
        previousAlliance: 0b11, newAlliance: 0b10, localAlliance: 0b11
    )
    #expect(line == "Bob left the alliance")
}

@Test func eventLogTextRemoteAllianceRequestWhenOurBitUnset() {
    let line = EventLogText.remoteAllianceChange(
        localPlayer: 0, actor: 1, actorName: "Bob",
        previousAlliance: 0b10, newAlliance: 0b11, localAlliance: 0b01
    )
    #expect(line == "Bob requests an alliance")
}

@Test func eventLogTextLocalAllianceRequestSplitsAcceptedAndRequested() {
    var alice = PlayerState()
    alice.connected = true
    alice.name = "Alice"
    alice.alliance = 0b01
    var bob = PlayerState()
    bob.connected = true
    bob.name = "Bob"
    bob.alliance = 0b10
    var carol = PlayerState()
    carol.connected = true
    carol.name = "Carol"
    carol.alliance = 0b101  // already has local player's bit

    let lines = EventLogText.localAllianceRequestMessages(
        withPlayers: 0b110, localPlayer: 0, previousAlliance: 0b001,
        players: [alice, bob, carol]
    )
    #expect(lines == ["requested alliance with Bob", "alliance accepted with Carol"])
}

@Test func eventLogTextGameTargetIsMSGGAME() {
    #expect(EventLogText.gameTarget == 3)
}
