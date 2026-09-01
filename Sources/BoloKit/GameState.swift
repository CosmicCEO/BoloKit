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
        explosions: [Explosion] = []
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
    }
}
