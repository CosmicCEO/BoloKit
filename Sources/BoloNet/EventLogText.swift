import BoloKit

// MARK: - D154 Wave 3 / D163 — `printmessage` formatters
//
// Pure string shapes copied from `client.c`'s `asprintf`/`printmessage` call sites.
// Format at the session/dispatch layer (D163 #5); BoloKit `recvSr*` stays UI-free.
// `MSGGAME` is `bolo.h:162` = 3; `MessageTarget` stays 0...2 (player-choosable only).

public enum EventLogText {
    /// `MSGGAME` (`bolo.h:162`). Not a `MessageTarget` case — display-only on the one
    /// `GameSession.messages` sink (D163 #1/#2).
    public static let gameTarget: UInt8 = 3

    // Shared with BoloKit `BuilderNeedText` (D165) so builder call sites do not
    // import BoloNet. Catalog type stays here.
    public static let needMoreTrees = BuilderNeedText.needMoreTrees
    public static let needAPill = BuilderNeedText.needAPill
    public static let needMoreMines = BuilderNeedText.needMoreMines
    /// Two spaces after the period, matching `client.c:6573`.
    public static let wouldKillBuilder = BuilderNeedText.wouldKillBuilder
    public static let timeLimitReached = "Time Limit Reached!"
    public static let baseControlReached = "Base Control Reached!"
    public static let disconnectedLocal = "disconnected"

    public static func joined(_ name: String) -> String { "\(name) joined" }
    public static func rejoined(_ name: String) -> String { "\(name) rejoined" }
    public static func left(_ name: String) -> String { "\(name) left" }
    public static func disconnected(_ name: String) -> String { "\(name) disconnected" }
    public static func kicked(_ name: String) -> String { "\(name) kicked" }
    public static func banned(_ name: String) -> String { "\(name) banned" }
    public static func lostBuilder(_ name: String) -> String { "\(name) just lost his builder" }

    public static func capturedNeutralPill(capturer: String, pill: Int) -> String {
        "\(capturer) captured neutral pill \(pill)"
    }
    public static func capturedPill(capturer: String, pill: Int, from: String) -> String {
        "\(capturer) captured pill \(pill) from \(from)"
    }
    public static func capturedNeutralBase(capturer: String, base: Int) -> String {
        "\(capturer) captured neutral base \(base)"
    }
    public static func capturedBase(capturer: String, base: Int, from: String) -> String {
        "\(capturer) captured base \(base) from \(from)"
    }

    /// Pill capture is gated on owner actually changing (`client.c:2259`).
    public static func capturePill(
        capturer: String, pill: Int, previousOwner: UInt8, previousOwnerName: String, newOwner: UInt8
    ) -> String? {
        guard previousOwner != newOwner else { return nil }
        if previousOwner == playerNeutral {
            return capturedNeutralPill(capturer: capturer, pill: pill)
        }
        return capturedPill(capturer: capturer, pill: pill, from: previousOwnerName)
    }

    /// Base capture always prints (`client.c:2463-2480`); no owner-changed gate.
    public static func captureBase(
        capturer: String, base: Int, previousOwner: UInt8, previousOwnerName: String
    ) -> String {
        if previousOwner == playerNeutral {
            return capturedNeutralBase(capturer: capturer, base: base)
        }
        return capturedBase(capturer: capturer, base: base, from: previousOwnerName)
    }

    public static func acceptedTheAlliance(_ name: String) -> String { "\(name) accepted the alliance" }
    public static func leftTheAlliance(_ name: String) -> String { "\(name) left the alliance" }
    public static func requestsAnAlliance(_ name: String) -> String { "\(name) requests an alliance" }
    public static func allianceAcceptedWith(_ name: String) -> String { "alliance accepted with \(name)" }
    public static func requestedAllianceWith(_ name: String) -> String { "requested alliance with \(name)" }
    public static func leftAllianceWith(_ name: String) -> String { "left alliance with \(name)" }

    /// `recvsrsetalliance` (`client.c:2918-3015`) — uses pre-assignment XOR of their bitmask.
    public static func remoteAllianceChange(
        localPlayer: Int, actor: Int, actorName: String,
        previousAlliance: UInt16, newAlliance: UInt16, localAlliance: UInt16
    ) -> String? {
        let xor = previousAlliance ^ newAlliance
        guard xor & (1 << localPlayer) != 0 else { return nil }
        if localAlliance & (1 << actor) != 0 {
            if newAlliance & (1 << localPlayer) != 0 {
                return acceptedTheAlliance(actorName)
            }
            return leftTheAlliance(actorName)
        }
        if newAlliance & (1 << localPlayer) != 0 {
            return requestsAnAlliance(actorName)
        }
        return nil
    }

    /// `requestalliance` (`client.c:6328-6379`) — call on the pre-mutation alliance bitmask.
    public static func localAllianceRequestMessages(
        withPlayers: UInt16, localPlayer: Int, previousAlliance: UInt16, players: [PlayerState]
    ) -> [String] {
        let xor = previousAlliance ^ (previousAlliance | withPlayers)
        var lines: [String] = []
        for i in players.indices where players[i].connected && (xor & (1 << i)) != 0 {
            if players[i].alliance & (1 << localPlayer) != 0 {
                lines.append(allianceAcceptedWith(players[i].name))
            } else {
                lines.append(requestedAllianceWith(players[i].name))
            }
        }
        return lines
    }

    /// `leavealliance` (`client.c:6403-6414`) — call on the pre-mutation alliance bitmask.
    public static func localAllianceLeaveMessages(
        withPlayers: UInt16, localPlayer: Int, previousAlliance: UInt16, players: [PlayerState]
    ) -> [String] {
        let keepMask: UInt16 = ~withPlayers | UInt16(1 << localPlayer)
        let xor = previousAlliance ^ (previousAlliance & keepMask)
        var lines: [String] = []
        for i in players.indices where players[i].connected && (xor & (1 << i)) != 0 {
            guard players[i].alliance & (1 << localPlayer) != 0 else { continue }
            lines.append(leftAllianceWith(players[i].name))
        }
        return lines
    }

    /// `recvsrtimelimit`/`recvsrbasecontrol` (`client.c:3042-3072`, `:3100-3130`).
    /// Pluralization is `n > 1 ? "s" : ""` (`Minute%s`/`Second%s`).
    public static func remaining(seconds: Int, reached: String) -> String {
        let minutes = seconds / 60
        let secs = seconds % 60
        if minutes != 0 {
            if secs != 0 {
                return "\(minutes) Minute\(minutes > 1 ? "s" : "") and \(secs) Second\(secs > 1 ? "s" : "") Remaining!"
            }
            return "\(minutes) Minute\(minutes > 1 ? "s" : "") Remaining!"
        }
        if secs != 0 {
            return "\(secs) Second\(secs > 1 ? "s" : "") Remaining!"
        }
        return reached
    }

    public static func timeLimitRemaining(_ seconds: Int) -> String {
        remaining(seconds: seconds, reached: timeLimitReached)
    }

    public static func baseControlRemaining(_ seconds: Int) -> String {
        remaining(seconds: seconds, reached: baseControlReached)
    }

    public static func captureMessages(
        previousPillOwners: [UInt8], pills: [Pill],
        previousBaseOwners: [UInt8], bases: [Base],
        players: [PlayerState]
    ) -> [String] {
        var lines: [String] = []
        for i in pills.indices {
            let previous = i < previousPillOwners.count ? previousPillOwners[i] : pills[i].owner
            let newOwner = pills[i].owner
            let capturer = playerName(Int(newOwner), players: players)
            let previousName = playerName(Int(previous), players: players)
            if let line = capturePill(
                capturer: capturer, pill: i, previousOwner: previous,
                previousOwnerName: previousName, newOwner: newOwner
            ) {
                lines.append(line)
            }
        }
        for i in bases.indices {
            let previous = i < previousBaseOwners.count ? previousBaseOwners[i] : bases[i].owner
            let newOwner = bases[i].owner
            guard previous != newOwner else { continue }
            let capturer = playerName(Int(newOwner), players: players)
            let previousName = playerName(Int(previous), players: players)
            lines.append(captureBase(
                capturer: capturer, base: i, previousOwner: previous, previousOwnerName: previousName
            ))
        }
        return lines
    }

    public static func playerName(_ index: Int, players: [PlayerState]) -> String {
        players.indices.contains(index) ? players[index].name : ""
    }
}
