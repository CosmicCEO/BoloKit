import Testing
import BoloKit
import BoloNet

// 1.1 backlog C.4 -- `computeMessageMask` mirrors `sendmessage()`'s own mask `switch`
// (`client.c:6718-6742`) exactly; `ChatMessage.displayText` mirrors `recvsrsendmesg`'s own
// `"%s: %s"` formatting (`client.c:1517`). No C oracle exists that returns these values in a
// form a Swift test can call directly (both are buried in a `TRY`/`CLEANUP` socket-write
// function on the C side), so these are direct behavioral checks against the reference's own
// read source, the same standard `HostListenerTests.swift`'s header states for anything in this
// port with no callable oracle.

private func makePlayers(count: Int) -> [PlayerState] {
    (0..<count).map { _ in PlayerState() }
}

@Test func computeMessageMaskEveryoneIsAllBitsSet() {
    let players = makePlayers(count: 3)
    let mask = computeMessageMask(target: .everyone, sender: 0, players: players)
    #expect(UInt16(bitPattern: mask) == 0xffff)
}

@Test func computeMessageMaskAlliesMatchesTheSendersOwnAllianceBitmask() {
    var players = makePlayers(count: 3)
    players[0].alliance = 0b101  // players 0 and 2
    let mask = computeMessageMask(target: .allies, sender: 0, players: players)
    #expect(UInt16(bitPattern: mask) == 0b101)
}

@Test func computeMessageMaskAlliesReadsTheSpecificSenderNotAlwaysPlayerZero() {
    var players = makePlayers(count: 3)
    players[1].alliance = 0b010
    let mask = computeMessageMask(target: .allies, sender: 1, players: players)
    #expect(UInt16(bitPattern: mask) == 0b010)
}

@Test func computeMessageMaskNearbyIncludesOnlyPlayersWithinTheReferencesEightPointFiveThreshold() {
    var players = makePlayers(count: 3)
    players[0].tank = Vec2f(x: 0, y: 0)
    players[1].tank = Vec2f(x: 5, y: 0)   // distance 5 -- mag2 == 25, well under 8.5*8.5
    players[2].tank = Vec2f(x: 100, y: 0)  // far -- excluded

    let mask = UInt16(bitPattern: computeMessageMask(target: .nearby, sender: 0, players: players))
    #expect(mask & (1 << 0) != 0)  // sender always includes themself (distance 0)
    #expect(mask & (1 << 1) != 0)
    #expect(mask & (1 << 2) == 0)
}

@Test func computeMessageMaskNearbyThresholdIsExclusiveAtExactlyEightPointFiveTiles() {
    // `client.c:6731`: `mag2f(sub2f(...)) < 8.5` -- `mag2f` (`Vector.swift:107`) is a real
    // (post-`sqrt`) magnitude despite the "2" in its name, so the threshold is a plain tile
    // distance, not a squared one. Exactly `8.5` must be excluded (`<`, not `<=`); just under it
    // must be included.
    var players = makePlayers(count: 3)
    players[0].tank = Vec2f(x: 0, y: 0)
    players[1].tank = Vec2f(x: 8.5, y: 0)   // exactly at the threshold -- excluded
    players[2].tank = Vec2f(x: 8.4, y: 0)   // just under -- included

    let mask = UInt16(bitPattern: computeMessageMask(target: .nearby, sender: 0, players: players))
    #expect(mask & (1 << 1) == 0)
    #expect(mask & (1 << 2) != 0)
}

@Test func chatMessageDisplayTextMatchesTheReferencesNameColonTextFormat() {
    let message = ChatMessage(id: 1, player: 2, senderName: "Alice", text: "hello", to: MessageTarget.everyone.rawValue)
    #expect(message.displayText == "Alice: hello")
}

@Test func messageTargetLabelsCoverExactlyTheThreePlayerChoosableCases() {
    // `MSGGAME` (`bolo.h:162`) is server-only -- `sendmessage`'s own `switch` (`client.c:
    // 6718-6742`) never handles it, so `MessageTarget` deliberately has no `.game` case at all.
    #expect(MessageTarget.allCases.map(\.rawValue) == [0, 1, 2])
    #expect(MessageTarget.everyone.label == "Everyone")
    #expect(MessageTarget.allies.label == "Allies")
    #expect(MessageTarget.nearby.label == "Nearby")
}
