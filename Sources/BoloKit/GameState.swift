// MARK: - GameState (Wave 5.1)
//
// The Swift equivalent of C's global `client`/`server` structs, unified
// into a single authoritative model since BoloKit is a standalone
// simulation with no separate network client/server split.

public struct GameState: Sendable {
    public var terrain: TerrainGrid
    public var pills: [Pill]
    public var bases: [Base]
    public var starts: [Start]
    public var players: [PlayerState]
    public var ticks: UInt64
    /// Index into `players` for the locally simulated player.
    public var localPlayer: Int
    public var local: LocalPlayerState
    public var grow: GrowState
    /// Global explosions not attached to any specific player (e.g. mine chains).
    public var explosions: [Explosion]
    /// Delayed mine-chain-reaction ring buffer (Wave 5.5a). `chainTicks + 1`
    /// slots, indexed by `ticks % (chainTicks + 1)`; a point scheduled "now"
    /// (written to slot `(ticks - 1) % (chainTicks + 1)`) is drained
    /// `chainTicks` ticks later. Mirrors `server.chains` (server.c).
    public var chains: [[Pointi]]
    /// Delayed sea-flood ring buffer (Wave 5.5a). Same ring-buffer shape as
    /// `chains`, sized `floodTicks + 1`. Mirrors `server.floods` (server.c).
    public var floods: [[Pointi]]

    public init(
        terrain: TerrainGrid = .mapDefault(),
        pills: [Pill] = [],
        bases: [Base] = [],
        starts: [Start] = [],
        players: [PlayerState] = [],
        ticks: UInt64 = 0,
        localPlayer: Int = 0,
        local: LocalPlayerState = LocalPlayerState(),
        grow: GrowState = GrowState(),
        explosions: [Explosion] = [],
        chains: [[Pointi]] = Array(repeating: [], count: chainTicks + 1),
        floods: [[Pointi]] = Array(repeating: [], count: floodTicks + 1)
    ) {
        self.terrain = terrain
        self.pills = pills
        self.bases = bases
        self.starts = starts
        self.players = players
        self.ticks = ticks
        self.localPlayer = localPlayer
        self.local = local
        self.grow = grow
        self.explosions = explosions
        self.chains = chains
        self.floods = floods
    }
}
