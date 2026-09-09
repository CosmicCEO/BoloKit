import BoloKit

// MARK: - 1.1 backlog C.4 -- messages panel
//
// The reference's own player-facing send path is `sendmessage()` (`client.c:6705-6759`), called
// from `GSXBoloController.m`'s `sendMessage:` IBAction (`messageTextField`'s Return-key target,
// `GSXBoloController.m:1393-1411`), and the receive/display path is `recvsrsendmesg()`
// (`client.c:1495-1529`) feeding `printmessage()`/`GSXBoloController.m`'s `printMessage:`
// (`messagesTextView`, a plain scrollback append, `GSXBoloController.m:2707-2729`).
//
// This port's relay plumbing already exists end-to-end with zero `GameState` effect by design
// (`RecvCL.swift`/`RecvSR.swift`'s own headers, `HostSession.swift:243,493`) -- `sendsrsendmesg`
// is a pure masked broadcast, `recvclsendmesg`/`recvsrsendmesg` have no `recvCl*`/`recvSr*`
// counterpart at all because there is no simulation state to mutate. What was missing is only the
// player-facing send/display half: a target-to-mask computation (`sendmessage`'s own `switch`)
// and a place to keep the received scrollback (the reference keeps it in an `NSTextView`'s own
// text storage, not `client`'s simulation state -- this port mirrors that by keeping `messages`
// on `GameSession`, not `GameState`, since it is exactly the same kind of pure display sink).
//
// `MSGGAME` (`bolo.h:162`) is not a UI case here -- `sendmessage()`'s own `switch` (`client.c:
// 6718-6742`) never handles it (falls to `assert(0)`), matching the reference: it is a
// synthetic target the *server* uses for its own system messages, never one a player picks.

/// Mirrors `bolo.h`'s anonymous `enum { MSGEVERYONE, MSGALLIES, MSGNEARBY, MSGGAME }` -- only the
/// first three are ever chosen by a sending player (`sendmessage`'s own `switch`, `client.c:
/// 6718-6742`); `MSGGAME` (`3`) is the server-only synthetic target and has no case here.
public enum MessageTarget: UInt8, Sendable, CaseIterable {
    case everyone = 0
    case allies = 1
    case nearby = 2

    public var label: String {
        switch self {
        case .everyone: return "Everyone"
        case .allies: return "Allies"
        case .nearby: return "Nearby"
        }
    }
}

/// Mirrors `sendmessage()`'s own mask `switch` (`client.c:6718-6742`) exactly, including its
/// `htons` no-op on this port (already-host-order `UInt16`, no wire-endian step needed until
/// `CLSendMesg.encode()` writes it). `MSGNEARBY`'s `8.5` threshold and `mag2f(sub2f(...))` shape
/// are copied verbatim from `client.c:6731`.
public func computeMessageMask(target: MessageTarget, sender: Int, players: [PlayerState]) -> Int16 {
    switch target {
    case .everyone:
        return Int16(bitPattern: 0xffff)

    case .allies:
        return Int16(bitPattern: players[sender].alliance)

    case .nearby:
        var mask: UInt16 = 0
        for i in 0..<min(players.count, maxPlayers) {
            if mag2f(sub2f(players[sender].tank, players[i].tank)) < 8.5 {
                mask |= 1 << i
            }
        }
        return Int16(bitPattern: mask)
    }
}

/// One scrollback line -- mirrors `recvsrsendmesg`'s own `"%s: %s"` formatting (`client.c:1517`),
/// baked in once at construction (via `displayText`) rather than recomputed by every view redraw.
public struct ChatMessage: Sendable, Hashable, Identifiable {
    public let id: UInt64
    public let player: Int
    public let senderName: String
    public let text: String
    public let to: UInt8

    public init(id: UInt64, player: Int, senderName: String, text: String, to: UInt8) {
        self.id = id
        self.player = player
        self.senderName = senderName
        self.text = text
        self.to = to
    }

    public var displayText: String { "\(senderName): \(text)" }
}
