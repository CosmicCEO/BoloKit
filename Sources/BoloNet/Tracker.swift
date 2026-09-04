import BoloKit

// MARK: - Wave 6.5a — tracker protocol wire structs
//
// Ported from `tracker.h`. This half of Wave 6.5 covers the game host's
// registration/heartbeat with a tracker (`registerserver()`/
// `sendtrackerupdate()`, `server.c`) and a client's browse of a tracker's
// game list (`listtracker()`, `bolo.c`) -- both distinct from, and
// running the separate `TRACKERVERSION`/`TRACKERIDENT` handshake ahead
// of, this project's own game client<->server protocol
// (`NET_GAME_VERSION`/`NET_GAME_IDENT`, `Preambles.swift`). The tracker
// *daemon* itself (`tracker.c`, a third, separate binary) is out of
// scope -- Q26, `docs/AGENT_NOTES.md` -- this port only ever plays the
// other two roles.

/// `TRACKERPORT` (`tracker.h:8`) -- the tracker daemon's one listening
/// port, TCP only.
public let trackerPort: UInt16 = 40000

/// `TRKPLYRNAMELEN`/`TRKMAPNAMELEN` (`tracker.h:11-12`).
public let trkPlayerNameLen = 16
public let trkMapNameLen = 32

/// `kTrackerHost`/`kTrackerList` (`tracker.h:31-34`) -- the one-byte
/// request a connected client sends right after the version handshake,
/// selecting which of the daemon's two roles it wants: register a game,
/// or fetch the current list.
public enum TrackerRequestType: UInt8, Sendable {
    case host = 0
    case list = 1
}

/// `kTrackerVersionOK`/`Err` (`tracker.h:15-18`).
public enum TrackerVersionStatus: UInt8, Sendable {
    case ok = 0
    case error = 1
}

/// `kTrackerTCPPortOK`/`Closed` (`tracker.h:20-23`).
public enum TrackerTCPPortStatus: UInt8, Sendable {
    case ok = 0
    case closed = 1
}

/// `kTrackerUDPPortOK`/`Closed` (`tracker.h:25-28`).
public enum TrackerUDPPortStatus: UInt8, Sendable {
    case ok = 0
    case closed = 1
}

/// Ported from `struct TrackerHost` (`tracker.h:41-51`) -- one hosted
/// game's advertised state, sent both at registration
/// (`registerserver()`, `server.c:1379-1390`) and on every 60-second
/// heartbeat (`sendtrackerupdate()`, `server.c:1569-1588`,
/// `TRACKERUPDATESECONDS`, `server.h:20`).
///
/// **Not** `__attribute__((__packed__))` (flagged in `docs/PLAN.md`'s
/// Wave 6.5 row) -- a padding byte sits at wire offset 51, between
/// `gametype` and the 4-byte-aligned `timelimit`. The C leaves that pad
/// byte, plus `playername`/`mapname`'s own final byte on an
/// exactly-full-length input (`strncpy(dst,src,LEN-1)` never touches
/// byte `LEN-1` if `src` is that long or longer), as uninitialized stack
/// garbage. This port always zero-fills instead -- a disclosed
/// Swift-safety deviation (T-3, `docs/AGENT_NOTES.md`'s Wave 6.5a
/// pre-brief), not a fidelity fix, since the real value is genuinely
/// undefined rather than a fact to reproduce. See
/// `TrackerDifferentialTests.swift`'s named regression test.
///
/// `timeLimit` has two, deliberately different, encodings. `encode()`
/// (registration) matches `registerserver()`'s `htonl(server.timelimit)`
/// (`server.c:1383`). `encodeAsHeartbeat()` reproduces
/// `sendtrackerupdate()`'s real bug (`server.c:1577`, T-2/D56): it omits
/// the `htonl`, so the four bytes it emits are `timeLimit`'s raw
/// little-endian in-memory representation, not the big-endian convention
/// every other multi-byte field on this wire uses. Bit-for-bit correct
/// only because every deployment target for this port (arm64/x86_64
/// Darwin) is little-endian -- exactly the architecture the C oracle
/// itself compiles and runs on, so this reproduces the actual observed
/// bytes, not an abstract platform-independent notion of the bug. `port`
/// does NOT have this asymmetry -- both `registerserver()`
/// (`server.c:1382`) and `sendtrackerupdate()` (`server.c:1575`) call
/// `htons()` on it; only `timelimit` differs between the two send sites.
public struct TrackerHost: Sendable, Hashable {
    public var playerName: String
    public var mapName: String
    public var port: UInt16
    public var gameType: UInt8
    public var timeLimit: UInt32
    public var passwordRequired: Bool
    public var nPlayers: UInt8
    public var allowJoin: Bool
    public var paused: Bool

    public init(
        playerName: String, mapName: String, port: UInt16, gameType: UInt8, timeLimit: UInt32,
        passwordRequired: Bool, nPlayers: UInt8, allowJoin: Bool, paused: Bool
    ) {
        self.playerName = playerName
        self.mapName = mapName
        self.port = port
        self.gameType = gameType
        self.timeLimit = timeLimit
        self.passwordRequired = passwordRequired
        self.nPlayers = nPlayers
        self.allowJoin = allowJoin
        self.paused = paused
    }

    /// Every field up to, but not including, `timeLimit` -- identical
    /// between the two send paths, so factored out rather than repeated.
    private func encodeCommonPrefix(into w: inout WireWriter) {
        w.putFixedString(playerName, count: trkPlayerNameLen)
        w.putFixedString(mapName, count: trkMapNameLen)
        w.putU16(port)
        w.putU8(gameType)
        w.putU8(0)  // offset-51 pad byte -- T-3, always zero, never the C's uninitialized garbage
    }

    /// Registration-path encoding (`server.c:1379-1390`) -- `timeLimit`
    /// correctly byte-swapped, matching `htonl`.
    public func encode() -> [UInt8] {
        var w = WireWriter()
        encodeCommonPrefix(into: &w)
        w.putU32(timeLimit)
        w.putU8(passwordRequired ? 1 : 0)
        w.putU8(nPlayers)
        w.putU8(allowJoin ? 1 : 0)
        w.putU8(paused ? 1 : 0)
        return w.bytes
    }

    /// Heartbeat-path encoding (`sendtrackerupdate()`, `server.c:1569-
    /// 1588`) -- reproduces the missing-`htonl` bug on `timeLimit`
    /// bit-for-bit (T-2/D56, replicated per D24/D40's bug-for-bug
    /// precedent): the four bytes below are `timeLimit`'s raw
    /// little-endian representation, deliberately not run through the
    /// big-endian path `putU32` uses everywhere else in this codec.
    public func encodeAsHeartbeat() -> [UInt8] {
        var w = WireWriter()
        encodeCommonPrefix(into: &w)
        w.putU8(UInt8(truncatingIfNeeded: timeLimit))
        w.putU8(UInt8(truncatingIfNeeded: timeLimit >> 8))
        w.putU8(UInt8(truncatingIfNeeded: timeLimit >> 16))
        w.putU8(UInt8(truncatingIfNeeded: timeLimit >> 24))
        w.putU8(passwordRequired ? 1 : 0)
        w.putU8(nPlayers)
        w.putU8(allowJoin ? 1 : 0)
        w.putU8(paused ? 1 : 0)
        return w.bytes
    }

    /// Decodes the wire's big-endian `timeLimit` -- the shape every
    /// actual receiver reads back with `ntohl` (the tracker daemon's
    /// post-registration store, `tracker.c:299`; `listtracker()`'s browse
    /// decode, `bolo.c:447`); only the sender-side heartbeat bug skips
    /// the swap on the way out, so decode has exactly one correct shape.
    /// This port never decodes a `TrackerHost` any other way, since it
    /// never plays the tracker daemon itself (Q26).
    public static func decode(_ bytes: [UInt8]) -> TrackerHost? {
        var r = WireReader(bytes)
        guard let playerName = r.getFixedString(trkPlayerNameLen),
              let mapName = r.getFixedString(trkMapNameLen),
              let port = r.getU16(),
              let gameType = r.getU8(),
              r.getU8() != nil,  // offset-51 pad byte, discarded on decode
              let timeLimit = r.getU32(),
              let passReqByte = r.getU8(),
              let nPlayers = r.getU8(),
              let allowJoinByte = r.getU8(),
              let pauseByte = r.getU8()
        else {
            return nil
        }
        return TrackerHost(
            playerName: playerName, mapName: mapName, port: port, gameType: gameType, timeLimit: timeLimit,
            passwordRequired: passReqByte != 0, nPlayers: nPlayers, allowJoin: allowJoinByte != 0, paused: pauseByte != 0
        )
    }

    /// `playername[16]` + `mapname[32]` + `port`(2) + `gametype`(1) +
    /// pad(1) + `timelimit`(4) + `passreq`(1) + `nplayers`(1) +
    /// `allowjoin`(1) + `pause`(1) -- 60 bytes total (`tracker.h:41-51`).
    public static let wireSize = trkPlayerNameLen + trkMapNameLen + 2 + 1 + 1 + 4 + 1 + 1 + 1 + 1
}

/// Ported from `struct TrackerHostList` (`tracker.h:53-56`) -- one entry
/// in the tracker's game list, as returned by `listtracker()`
/// (`bolo.c:441-449`). Decode-only: this port never plays the tracker
/// daemon (Q26), so it never needs to produce this struct's bytes itself.
///
/// `addr` is left in network byte order on the wire AND on decode (T-9 --
/// `bolo.c:446-447` only swaps `game.port`/`game.timelimit`, both nested
/// inside `game`). This port has no reason to reconstruct a local
/// `sockaddr_in` from it, so the raw 32-bit value is kept opaque; a
/// caller that wants a human-readable address should format its four
/// bytes directly.
public struct TrackerHostList: Sendable, Hashable {
    public var addr: UInt32
    public var game: TrackerHost

    public init(addr: UInt32, game: TrackerHost) {
        self.addr = addr
        self.game = game
    }

    public static func decode(_ bytes: [UInt8]) -> TrackerHostList? {
        var r = WireReader(bytes)
        guard let addr = r.getU32(), let gameBytes = r.getBytes(TrackerHost.wireSize), let game = TrackerHost.decode(gameBytes) else {
            return nil
        }
        return TrackerHostList(addr: addr, game: game)
    }

    /// `in_addr`(4) + `TrackerHost`(60) -- 64 bytes (`tracker.h:53-56`).
    public static let wireSize = 4 + TrackerHost.wireSize
}

/// Builds the `TrackerHost` snapshot both `registerWithTracker` and
/// `TrackerSession.sendHeartbeat` send, from `state`'s live fields --
/// mirrors `nplayers()`/`getallowjoinserver()`/`getpauseserver()`'s C
/// counterparts (`server.c:4412-4422`, `:419-421`, `:369-371`) and
/// `assembleBoloPreamble`'s (`Preambles.swift`, Wave 6.3) own established
/// pattern of deriving wire values from a live `GameState` rather than a
/// separately-tracked config struct. `gameType` is always
/// `kDominationGameType` (0), same disclosed convention as
/// `BoloPreamble.gameType`'s own doc comment.
///
/// **D57:** `timeLimit` uses `truncatingIfNeeded`, not a plain `UInt32(...)`
/// conversion -- `GameState.timeLimit` has no non-negative invariant
/// enforced anywhere (`RunTick.swift`'s own tick logic already tolerates
/// a negative value the same way the C's `if (server.timelimit > 0)`
/// does), and `UInt32(_:)` traps on a negative `Int` where the C's
/// implicit `int`->`uint32_t` conversion inside `htonl()` never would --
/// same fix pattern this project already applies elsewhere for exactly
/// this shape of bug (the `Int16` `truncatingIfNeeded` convention,
/// `CLAUDE.md`). See `TrackerDifferentialTests.swift`'s named regression
/// test for the negative-`timeLimit` case this guards.
public func trackerHost(hostPlayerName: String, mapName: String, port: UInt16, state: GameState) -> TrackerHost {
    TrackerHost(
        playerName: hostPlayerName, mapName: mapName, port: port,
        gameType: 0,
        timeLimit: UInt32(truncatingIfNeeded: state.timeLimit),
        passwordRequired: state.passwordRequired,
        nPlayers: UInt8(state.players.filter(\.connected).count),
        allowJoin: state.allowJoin,
        paused: state.serverPauseTicks == -1
    )
}
