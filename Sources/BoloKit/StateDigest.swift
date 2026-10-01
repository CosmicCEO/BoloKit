// MARK: - State digests (v1.6.9 baseline benchmark)
//
// Measurement only: nothing here is read by the simulation or sent over the wire. Packs the
// parts of `GameState`/`FogState` that host and guest are supposed to agree on into plain
// integers, one per element, so two processes can log them and an offline analyzer can line
// the two logs up. See `Bench/README.md`.
//
// Fields a side never receives are left out on purpose, so they cannot show up as a false
// divergence: `Pill.speed`/`counter`/`coolCounter` and `Base.counter` are per-process tallies.

/// One comparable slice of game state. Raw values are part of the log format; never renumber.
public enum DigestDomain: UInt8, CaseIterable, Sendable {
    case terrain = 0
    case pills = 1
    case bases = 2
    case selfStatus = 3
    case resources = 4
    case fog = 5
    case peers = 6
}

/// Element index within `DigestDomain.resources`.
public enum DigestResource: Int, CaseIterable, Sendable {
    case armour = 0
    case shells = 1
    case mines = 2
    /// Guest-owned since v1.6.9 (#171), so informational rather than host-authoritative.
    case trees = 3
}

/// Terrain value for a tile the observer is not expected to know (outside its vision).
public let digestUnknownTerrain: UInt64 = 0xffff_ffff

public struct DigestChange: Hashable, Sendable {
    public var domain: DigestDomain
    public var element: UInt32
    public var value: UInt64

    public init(domain: DigestDomain, element: UInt32, value: UInt64) {
        self.domain = domain
        self.element = element
        self.value = value
    }
}

// MARK: - Packing

public func digestValue(_ pill: Pill) -> UInt64 {
    UInt64(pill.x) | UInt64(pill.y) << 8 | UInt64(pill.armour) << 16 | UInt64(pill.owner) << 24
}

public func digestValue(_ base: Base) -> UInt64 {
    UInt64(base.x) | UInt64(base.y) << 8 | UInt64(base.owner) << 16 | UInt64(base.armour) << 24
        | UInt64(base.shells) << 32 | UInt64(base.mines) << 40
}

/// Direction in sixteenths of a turn (0-15), the resolution the wire's one-byte direction and
/// the tank sprites both resolve to at best.
public func digestSixteenth(_ dir: Float) -> UInt64 {
    guard dir.isFinite else { return 0 }
    let steps = (dir * 8 / kPif).rounded()
    let wrapped = steps.truncatingRemainder(dividingBy: 16)
    return UInt64(wrapped < 0 ? wrapped + 16 : wrapped) & 15
}

private func digestTile(_ point: Vec2f) -> UInt64 {
    let x = UInt64(UInt8(truncatingIfNeeded: Int(point.x.isFinite ? point.x : 0)))
    let y = UInt64(UInt8(truncatingIfNeeded: Int(point.y.isFinite ? point.y : 0)))
    return x | y << 8
}

/// Bit `i` set when pill `i` is carried by `player`.
public func digestOnboardPillMask(player: Int, pills: [Pill]) -> UInt64 {
    var mask: UInt64 = 0
    for (index, pill) in pills.enumerated() where index < 64 {
        if pill.armour == pillOnboard && Int(pill.owner) == player { mask |= 1 << UInt64(index) }
    }
    return mask
}

/// `player`'s own status: dead, boat, tank tile, direction, carried pills.
public func digestSelfStatus(player: Int, state: GameState) -> UInt64 {
    guard state.players.indices.contains(player) else { return 0 }
    let p = state.players[player]
    return (p.dead ? 1 : 0) | (p.boat ? 2 : 0) | digestTile(p.tank) << 8 | digestSixteenth(p.dir) << 24
        | (digestOnboardPillMask(player: player, pills: state.pills) & 0xffff) << 32
}

/// Another player as seen in `state`: connected, dead, boat, tank tile, input flags.
public func digestPeer(_ player: PlayerState) -> UInt64 {
    (player.connected ? 1 : 0) | (player.dead ? 2 : 0) | (player.boat ? 4 : 0) | digestTile(player.tank) << 8
        | UInt64(player.inputFlags.rawValue & 0xff) << 24
}

public func digestResources(player: Int, state: GameState) -> [UInt64] {
    guard state.players.indices.contains(player), state.localStats.indices.contains(player) else {
        return [UInt64](repeating: 0, count: DigestResource.allCases.count)
    }
    let stats = state.localStats[player]
    let p = state.players[player]
    return [
        UInt64(truncatingIfNeeded: stats.armour), UInt64(truncatingIfNeeded: stats.shells),
        // P0b: the builder carries a mine the guest has already spent and the host has not yet,
        // so the count that both sides should agree on includes it.
        UInt64(truncatingIfNeeded: p.mines + p.builderMines), UInt64(truncatingIfNeeded: p.trees),
    ]
}

/// Bit 0: currently visible. Bits 1 and up: the last-seen display tile.
public func digestFogValue(fog: Int16, seen: Tile) -> UInt64 {
    (fog > 0 ? 1 : 0) | UInt64(UInt32(bitPattern: seen.rawValue)) << 1
}

// MARK: - Whole-domain hash

/// FNV-1a 64 over the values in order. Used for the end-of-run snapshot, where one number per
/// domain is enough to say "equal" or "not equal".
public func digestHash(_ values: [UInt64]) -> UInt64 {
    var hash: UInt64 = 0xcbf2_9ce4_8422_2325
    for value in values {
        var v = value
        for _ in 0..<8 {
            hash ^= v & 0xff
            hash = hash &* 0x0000_0100_0000_01b3
            v >>= 8
        }
    }
    return hash
}

// MARK: - Change tracking

/// Remembers the last value logged for every element and reports only what changed, so a
/// steady state costs a comparison and no log records.
public struct StateDigestTracker: Sendable {
    /// `player` is whose view this is: the guest's own slot on the guest, and that same slot
    /// on the host (one tracker per guest there).
    public let player: Int
    private var last: [[UInt64]]

    /// Never a real value in any domain, so the first sample reports every element.
    private static let unset = UInt64.max

    public init(player: Int) {
        self.player = player
        self.last = Array(repeating: [], count: DigestDomain.allCases.count)
    }

    /// Pills, bases, own status, resources and peers. Cheap enough for every tick.
    public mutating func sampleSmallDomains(_ state: GameState, into changes: inout [DigestChange]) {
        record(.pills, state.pills.map { digestValue($0) }, into: &changes)
        record(.bases, state.bases.map { digestValue($0) }, into: &changes)
        record(.selfStatus, [digestSelfStatus(player: player, state: state)], into: &changes)
        record(.resources, digestResources(player: player, state: state), into: &changes)
        var peers = state.players.map { digestPeer($0) }
        if peers.indices.contains(player) { peers[player] = 0 }
        record(.peers, peers, into: &changes)
    }

    /// `view` is one value per tile: the raw terrain, or `digestUnknownTerrain`.
    public mutating func sampleTerrain(view: [UInt64], into changes: inout [DigestChange]) {
        record(.terrain, view, into: &changes)
    }

    public mutating func sampleFog(_ fogState: FogState, into changes: inout [DigestChange]) {
        let count = min(fogState.fog.count, fogState.seenTiles.count)
        var values = [UInt64](repeating: 0, count: count)
        for index in 0..<count {
            values[index] = digestFogValue(fog: fogState.fog[index], seen: fogState.seenTiles[index])
        }
        record(.fog, values, into: &changes)
    }

    /// The last sampled values of `domain`, hashed. Zero elements hash to the FNV offset basis.
    public func hash(of domain: DigestDomain) -> UInt64 {
        digestHash(last[Int(domain.rawValue)])
    }

    private mutating func record(_ domain: DigestDomain, _ values: [UInt64], into changes: inout [DigestChange]) {
        let slot = Int(domain.rawValue)
        if last[slot].count != values.count {
            last[slot] = [UInt64](repeating: Self.unset, count: values.count)
        }
        for index in values.indices where last[slot][index] != values[index] {
            last[slot][index] = values[index]
            changes.append(DigestChange(domain: domain, element: UInt32(index), value: values[index]))
        }
    }
}

/// The plain terrain view: every tile known, as on a guest or on a host with Hidden Mines off.
public func digestTerrainView(_ terrain: TerrainGrid) -> [UInt64] {
    terrain.storage.map { UInt64(UInt32(bitPattern: $0)) }
}
