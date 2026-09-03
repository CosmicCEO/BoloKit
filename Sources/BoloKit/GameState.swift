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
    /// Per-game configuration set once at connect time (Wave 5.6). Mirrors
    /// `client.game.domination.type`. C's top-level `client.gametype` always
    /// equals `kDominationGameType` in this port — no other top-level mode
    /// was ever finished in the reference source (see `DominationType`).
    public var dominationType: DominationType
    /// `0` = running; positive = counting down by one tick per call to
    /// `runTick`, emitting a pause-status event on each second boundary;
    /// `-1` = paused indefinitely, no countdown. Mirrors `server.pause`
    /// (Wave 6.1).
    public var pause: Int
    /// Game time limit in seconds; `0` = no limit. Mirrors `server.timelimit`.
    /// `runTick` derives every timing decision from `ticks` vs. this value
    /// directly — there is no separate "reached" flag, unlike the real
    /// distributed C's `client.timelimitreached` (see `RunTick.swift`'s
    /// header for why that's a legitimate unification, not an omission).
    public var timeLimit: Int
    /// Seconds all bases must be held (by one mutually-allied owner) to win
    /// a domination game. Mirrors `server.game.domination.basecontrol`. `0`
    /// with any bases configured means an instant win the moment they're
    /// all held — matches the C literally, not a guarded default.
    public var baseControlThreshold: Int
    /// Running tick count of consecutive ticks every base has been held by
    /// one mutually-allied owner. Mirrors `server.basecontrol` — a
    /// different variable from `baseControlThreshold` despite the similar
    /// C name (`server.basecontrol` vs. `server.game.domination.basecontrol`).
    public var baseControlCounter: Int

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
        floods: [[Pointi]] = Array(repeating: [], count: floodTicks + 1),
        dominationType: DominationType = .open,
        pause: Int = 0,
        timeLimit: Int = 0,
        baseControlThreshold: Int = 0,
        baseControlCounter: Int = 0
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
        self.dominationType = dominationType
        self.pause = pause
        self.timeLimit = timeLimit
        self.baseControlThreshold = baseControlThreshold
        self.baseControlCounter = baseControlCounter
    }
}
