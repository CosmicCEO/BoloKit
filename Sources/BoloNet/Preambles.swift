import BoloKit

// MARK: - Preamble structs (Wave 6.3)
//
// Reassigned from Wave 6.0's original scope (see docs/PLAN.md's Wave 6.0
// correction) -- these carry no opcode byte, unlike every CL*/SR* struct
// in ClientMessages.swift/ServerMessages.swift, so they're encoded/decoded
// standalone rather than through `decodeOpcode`.

/// Ported from `struct JOIN_Preamble` (`bolo.h:448-452`) -- the client's
/// very first bytes on connect, before any opcode-tagged message exists.
public struct JoinPreamble: Sendable, Hashable {
    public var version: UInt8
    public var name: String
    public var pass: String

    public init(version: UInt8 = netGameVersion, name: String, pass: String) {
        self.version = version
        self.name = name
        self.pass = pass
    }

    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putBytes(netGameIdent)
        w.putU8(version)
        w.putFixedString(name, count: 16)
        w.putFixedString(pass, count: 32)
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) -> JoinPreamble? {
        var r = WireReader(bytes)
        guard r.getBytes(8) == netGameIdent else { return nil }
        guard let version = r.getU8(), let name = r.getFixedString(16), let pass = r.getFixedString(32) else {
            return nil
        }
        return JoinPreamble(version: version, name: name, pass: pass)
    }
}

/// Ported from `struct BOLO_Preamble` (`bmap.h:18-39`) -- the server's
/// join-acceptance reply: game config plus every slot's roster entry,
/// immediately followed on the wire by the encoded map (`maplen` bytes,
/// already owned by `BMap.swift`'s `writeRun`/Wave 4.1 -- not this
/// struct's concern beyond reporting the byte count).
public struct BoloPreamble: Sendable, Hashable {
    /// One slot's row in the roster table (`bmap.h:33-38`'s anonymous
    /// packed struct) -- fixed at `maxPlayers` entries, matching the wire
    /// (never a variable-length array).
    public struct PlayerEntry: Sendable, Hashable {
        public var used: Bool
        public var connected: Bool
        /// `htonl(server.players[i].seq)` on the wire. This port never
        /// stores a per-player `seq` counter in `GameState` (Wave 6.0's
        /// deliberate exclusion, reaffirmed by `RunTick.swift`'s own
        /// step-7 disclosure) -- a real transport layer (Wave 6.4) would
        /// supply this value; callers with no such value should pass 0,
        /// which is also what a freshly-joined slot's own C counter reads
        /// before any datagram traffic exists.
        public var seq: UInt32
        public var name: String
        public var host: String
        public var alliance: UInt16

        public init(used: Bool, connected: Bool, seq: UInt32, name: String, host: String, alliance: UInt16) {
            self.used = used
            self.connected = connected
            self.seq = seq
            self.name = name
            self.host = host
            self.alliance = alliance
        }

        fileprivate func encode(into w: inout WireWriter) {
            w.putU8(used ? 1 : 0)
            w.putU8(connected ? 1 : 0)
            w.putU32(seq)
            w.putFixedString(name, count: 16)
            w.putFixedString(host, count: 32)
            w.putU16(alliance)
        }

        fileprivate static func decode(_ r: inout WireReader) -> PlayerEntry? {
            guard let usedByte = r.getU8(), let connectedByte = r.getU8(), let seq = r.getU32(),
                  let name = r.getFixedString(16), let host = r.getFixedString(32), let alliance = r.getU16()
            else {
                return nil
            }
            return PlayerEntry(used: usedByte != 0, connected: connectedByte != 0, seq: seq, name: name, host: host, alliance: alliance)
        }
    }

    public var version: UInt8
    public var player: UInt8
    public var hiddenMines: UInt8
    /// `255` is the wire's indefinite-pause sentinel (matches `SRPause`'s
    /// own encoding, confirmed by `RunTick.swift`'s D35 fix and
    /// `RecvSR.swift`'s `recvSrPause`).
    public var pause: UInt8
    /// Always `kDominationGameType` (0) in this port -- see
    /// `GameState.dominationType`'s own doc comment: no other top-level
    /// mode was ever finished in the reference source.
    public var gameType: UInt8
    public var dominationType: UInt8
    public var baseControl: UInt8
    /// Exactly `maxPlayers` entries; the wire has no length prefix here
    /// (a fixed-size array in the C struct, not a `Buf`-style variable
    /// payload).
    public var players: [PlayerEntry]
    public var mapLength: UInt32

    public init(
        version: UInt8 = netGameVersion, player: UInt8, hiddenMines: UInt8, pause: UInt8,
        gameType: UInt8 = 0, dominationType: UInt8, baseControl: UInt8,
        players: [PlayerEntry], mapLength: UInt32
    ) {
        self.version = version
        self.player = player
        self.hiddenMines = hiddenMines
        self.pause = pause
        self.gameType = gameType
        self.dominationType = dominationType
        self.baseControl = baseControl
        self.players = players
        self.mapLength = mapLength
    }

    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putBytes(netGameIdent)
        w.putU8(version)
        w.putU8(player)
        w.putU8(hiddenMines)
        w.putU8(pause)
        w.putU8(gameType)
        w.putU8(dominationType)
        w.putU8(baseControl)
        for entry in players {
            entry.encode(into: &w)
        }
        w.putU32(mapLength)
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) -> BoloPreamble? {
        var r = WireReader(bytes)
        guard r.getBytes(8) == netGameIdent else { return nil }
        guard let version = r.getU8(), let player = r.getU8(), let hiddenMines = r.getU8(),
              let pause = r.getU8(), let gameType = r.getU8(), let dominationType = r.getU8(),
              let baseControl = r.getU8()
        else {
            return nil
        }
        var players: [PlayerEntry] = []
        players.reserveCapacity(maxPlayers)
        for _ in 0..<maxPlayers {
            guard let entry = PlayerEntry.decode(&r) else { return nil }
            players.append(entry)
        }
        guard let mapLength = r.getU32() else { return nil }
        return BoloPreamble(
            version: version, player: player, hiddenMines: hiddenMines, pause: pause,
            gameType: gameType, dominationType: dominationType, baseControl: baseControl,
            players: players, mapLength: mapLength
        )
    }
}

/// Ported from `struct TRACKER_Preamble` (`tracker.h:35-38`) -- note
/// `TRACKERVERSION` (0) is a distinct constant from `NET_GAME_VERSION`
/// (1); this is a different protocol (game server ↔ tracker, not
/// client ↔ game server), not a shorthand for the same handshake.
public struct TrackerPreamble: Sendable, Hashable {
    public var version: UInt8

    public init(version: UInt8 = trackerVersion) {
        self.version = version
    }

    public func encode() -> [UInt8] {
        var w = WireWriter()
        w.putBytes(trackerIdent)
        w.putU8(version)
        return w.bytes
    }

    public static func decode(_ bytes: [UInt8]) -> TrackerPreamble? {
        var r = WireReader(bytes)
        guard r.getBytes(8) == trackerIdent else { return nil }
        guard let version = r.getU8() else { return nil }
        return TrackerPreamble(version: version)
    }
}

/// `NET_GAME_IDENT`/`NET_GAME_VERSION` (`bolo.h:27,37`) -- the game
/// client↔server handshake identity, shared by `JoinPreamble` and
/// `BoloPreamble`.
public let netGameIdent: [UInt8] = Array("XBOLOGAM".utf8)
public let netGameVersion: UInt8 = 1

/// `TRACKERIDENT`/`TRACKERVERSION` (`tracker.h:9-10`) -- the separate
/// tracker handshake identity, used only by `TrackerPreamble`.
public let trackerIdent: [UInt8] = Array("XBOLOTRK".utf8)
public let trackerVersion: UInt8 = 0

/// Assembles a `BoloPreamble` for a (re)joined `player`, from
/// `joinplayerserver()`'s own field-by-field construction
/// (`server.c:846-873`). `seq` is supplied by the caller, one entry per
/// player slot -- see `BoloPreamble.PlayerEntry.seq`'s doc comment for why
/// `GameState` itself has nothing to read there; missing/short `seq`
/// entries default to 0, the same value a never-joined slot's C counter
/// would read. `mapLength` is simply the byte count of whatever
/// `BMap.swift`'s encoder already produced (Wave 4.1, not re-derived
/// here). `state.players` shorter than `maxPlayers` (every existing test
/// fixture) is treated as the missing slots being never-used, matching
/// what an empty `PlayerState()` already means.
public func assembleBoloPreamble(player: Int, state: GameState, seq: [UInt32], mapLength: UInt32) -> BoloPreamble {
    // `server.pause` is the tick-domain field this wire byte derives from
    // (server.c:860-864) -- `serverPauseTicks` after D39's split, not
    // `clientPauseDisplaySeconds` (the wire-domain field that value would
    // already be expressed in, with no TICKSPERSEC division to redo).
    let pause: UInt8 = state.serverPauseTicks == -1 ? 255 : UInt8(state.serverPauseTicks / Int(ticksPerSec))

    let dominationType: UInt8
    switch state.dominationType {
    case .open: dominationType = 0
    case .tournament: dominationType = 1
    case .strict: dominationType = 2
    }

    let entries = (0..<maxPlayers).map { i -> BoloPreamble.PlayerEntry in
        let p = i < state.players.count ? state.players[i] : PlayerState()
        let s = i < seq.count ? seq[i] : 0
        return BoloPreamble.PlayerEntry(used: p.used, connected: p.connected, seq: s, name: p.name, host: p.host, alliance: p.alliance)
    }

    return BoloPreamble(
        player: UInt8(player),
        hiddenMines: state.hiddenMines ? 1 : 0,
        pause: pause,
        dominationType: dominationType,
        baseControl: UInt8(state.baseControlThreshold),
        players: entries,
        mapLength: mapLength
    )
}
