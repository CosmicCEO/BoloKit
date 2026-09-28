import BoloKit

// MARK: - Benchmark scenario library (v1.6.9 baseline benchmark)
//
// Measurement only. The fixed scenarios the baseline is made of, all on the bundled default map
// (`defaultBundledMapState`): grass x 100...145, y 118...140; a river along y 129 with a road
// bridge at (120, 129); one start at (102, 121) facing east; pill 0 dead and neutral at
// (108, 123); pill 1 armed and hostile at (140, 123); bases at (105, 123), (108, 134) and
// (140, 134). The host is player 0 and the guest player 1; both spawn on the one start, so
// every host script moves off it first.
//
// A scenario ends guest first: the guest finishes its steps, settles and quits; the host's last
// step waits for that, then the host settles and quits. Changing a scenario changes its hash,
// and results from different hashes are never compared.

public enum BenchScenarios {
    public static let all: [BenchScenario] = [
        joinAndSpawn, pillPickupAndCapture, mineLaying, building, deathAndRespawn, fogCrossing, sustainedFire,
        soakOpen, soakHidden,
    ]

    public static func named(_ name: String) -> BenchScenario? {
        all.first { $0.name == name }
    }

    /// Where the host waits, clear of the start and of the guest's routes.
    private static let hostPost = (x: 104, y: 119)

    private static let hostOpening: [BenchStep] = [
        .until(.alive, timeoutMs: 15_000),
        .driveTo(x: hostPost.x, y: hostPost.y, radius: 0.4, timeoutMs: 20_000),
        .until(.peerAlive, timeoutMs: 90_000),
        .mark("peer-alive"),
    ]

    private static let hostClosing: [BenchStep] = [.until(.peerGone, timeoutMs: 180_000)]

    /// S1. The join itself: handshake, map, first spawn and the first reveal burst.
    public static let joinAndSpawn = BenchScenario(
        name: "s1-join-and-spawn", hiddenMines: true,
        host: hostOpening + hostClosing,
        guest: [
            .until(.alive, timeoutMs: 30_000),
            .mark("spawned"),
            .wait(ms: 3_000),
        ]
    )

    /// S2. The guest collects the dead pill, has its builder place it, and the host shoots it.
    /// Exposes a broadcast keyed on the wrong field (owner, when only armour changed) and
    /// damage applied twice on the guest.
    public static let pillPickupAndCapture = BenchScenario(
        name: "s2-pill-pickup-and-capture", hiddenMines: true,
        host: hostOpening + [
            .until(.pillAt(pill: 0, x: 112, y: 121), timeoutMs: 90_000),
            // Close enough that being knocked back by the pill's own fire leaves it in range.
            .driveTo(x: 108, y: 121, radius: 0.3, timeoutMs: 20_000),
            .face(x: 112, y: 121, timeoutMs: 10_000),
            .mark("firing"),
            .keys(set: [.shoot], clear: []),
            .until(.pillArmourAtMost(pill: 0, armour: 12), timeoutMs: 30_000),
            .keys(set: [], clear: [.shoot]),
            .mark("ceased"),
            .driveTo(x: hostPost.x, y: hostPost.y, radius: 0.4, timeoutMs: 30_000),
        ] + hostClosing,
        guest: [
            .until(.alive, timeoutMs: 30_000),
            .mark("spawned"),
            .driveTo(x: 108, y: 123, radius: 0.4, timeoutMs: 30_000),
            .until(.carryingAtLeast(pills: 1), timeoutMs: 10_000),
            .mark("collected"),
            .driveTo(x: 110, y: 123, radius: 0.4, timeoutMs: 20_000),
            .builder(tool: .pill, x: 112, y: 121),
            .until(.pillAt(pill: 0, x: 112, y: 121), timeoutMs: 60_000),
            .mark("placed"),
            .until(.pillArmourAtMost(pill: 0, armour: 12), timeoutMs: 90_000),
            .mark("damage-seen"),
            .wait(ms: 2_000),
        ]
    )

    /// S3. One mine laid from the tank, one placed by the builder. Exposes resource accounting
    /// and a change the host masks from players who cannot see the tile.
    public static let mineLaying = BenchScenario(
        name: "s3-mine-laying", hiddenMines: true,
        host: hostOpening + hostClosing,
        guest: [
            .until(.alive, timeoutMs: 30_000),
            .mark("spawned"),
            .driveTo(x: 110, y: 121, radius: 0.4, timeoutMs: 30_000),
            .layMine,
            .until(.minesAtMost(39), timeoutMs: 10_000),
            .mark("laid"),
            .driveTo(x: 113, y: 121, radius: 0.4, timeoutMs: 20_000),
            .builder(tool: .mine, x: 113, y: 125),
            .until(.minesAtMost(38), timeoutMs: 30_000),
            .until(.builderReady, timeoutMs: 30_000),
            .mark("placed"),
            .wait(ms: 2_000),
        ]
    )

    /// S4. A road and a wall, with the guest firing while its builder is out. Hidden Mines off,
    /// as in `PillDesyncReproTests`. Exposes the guest's old tree and mine counts overwriting the
    /// host's (#171, #174).
    public static let building = BenchScenario(
        name: "s4-building", hiddenMines: false,
        host: hostOpening + hostClosing,
        guest: [
            .until(.alive, timeoutMs: 30_000),
            .mark("spawned"),
            .driveTo(x: 110, y: 123, radius: 0.4, timeoutMs: 30_000),
            .face(x: 125, y: 123, timeoutMs: 10_000),
            .builder(tool: .road, x: 110, y: 126),
            .keys(set: [.shoot], clear: []),
            .until(.terrain(x: 110, y: 126, anyOf: [Terrain.road.rawValue]), timeoutMs: 40_000),
            .keys(set: [], clear: [.shoot]),
            .until(.builderReady, timeoutMs: 30_000),
            .mark("road-built"),
            .builder(tool: .wall, x: 112, y: 126),
            .keys(set: [.shoot], clear: []),
            .until(.terrain(x: 112, y: 126, anyOf: [Terrain.wall.rawValue]), timeoutMs: 40_000),
            .keys(set: [], clear: [.shoot]),
            .until(.builderReady, timeoutMs: 30_000),
            .mark("wall-built"),
            .wait(ms: 2_000),
        ]
    )

    /// S5. The guest collects the pill, drives into the host's fire, dies carrying it and is
    /// respawned by the host. Exposes dropped-pill sync and the respawn teleport.
    public static let deathAndRespawn = BenchScenario(
        name: "s5-death-and-respawn", hiddenMines: true,
        host: [
            .until(.alive, timeoutMs: 15_000),
            .driveTo(x: 118, y: 123, radius: 0.4, timeoutMs: 30_000),
            .face(x: 108, y: 123, timeoutMs: 10_000),
            .until(.peerAlive, timeoutMs: 90_000),
            .mark("peer-alive"),
            .until(.peerAt(x: 115, y: 123, radius: 2.5), timeoutMs: 90_000),
            .mark("firing"),
            .keys(set: [.shoot], clear: []),
            .until(.peerDead, timeoutMs: 60_000),
            .keys(set: [], clear: [.shoot]),
            .mark("peer-dead"),
            .until(.peerAlive, timeoutMs: 30_000),
            .mark("peer-respawned"),
        ] + hostClosing,
        guest: [
            .until(.alive, timeoutMs: 60_000),
            .mark("spawned"),
            .driveTo(x: 108, y: 123, radius: 0.4, timeoutMs: 30_000),
            .until(.carryingAtLeast(pills: 1), timeoutMs: 10_000),
            .mark("collected"),
            // Each hit knocks the tank back a little, so stop well inside the host's 7-tile range.
            .driveTo(x: 115, y: 123, radius: 0.4, timeoutMs: 20_000),
            .until(.dead, timeoutMs: 90_000),
            .mark("died"),
            .until(.alive, timeoutMs: 30_000),
            .mark("respawned"),
            .wait(ms: 3_000),
        ]
    )

    /// S6. The guest drives out of sight of the start, the host's builder lays a road there, and
    /// the guest comes back. Exposes a change masked while the tile was out of vision and never
    /// delivered on its return.
    public static let fogCrossing = BenchScenario(
        name: "s6-fog-crossing", hiddenMines: true,
        host: hostOpening + [
            .until(.peerAt(x: 128, y: 121, radius: 2), timeoutMs: 90_000),
            .mark("peer-away"),
            .builder(tool: .road, x: 106, y: 120),
            .until(.terrain(x: 106, y: 120, anyOf: [Terrain.road.rawValue]), timeoutMs: 40_000),
            .mark("road-built"),
        ] + hostClosing,
        guest: [
            .until(.alive, timeoutMs: 30_000),
            .mark("spawned"),
            .driveTo(x: 128, y: 121, radius: 0.4, timeoutMs: 60_000),
            .mark("away"),
            .wait(ms: 12_000),
            .driveTo(x: 108, y: 121, radius: 0.4, timeoutMs: 60_000),
            .mark("back"),
            .wait(ms: 3_000),
        ]
    )

    /// S7. The guest fires until it has nothing left. Exposes the cost of one reliable message a
    /// tick while a shell is in flight.
    public static let sustainedFire = BenchScenario(
        name: "s7-sustained-fire", hiddenMines: true,
        host: hostOpening + hostClosing,
        guest: [
            .until(.alive, timeoutMs: 30_000),
            .mark("spawned"),
            .driveTo(x: 110, y: 121, radius: 0.4, timeoutMs: 30_000),
            .face(x: 130, y: 121, timeoutMs: 10_000),
            .mark("firing"),
            .keys(set: [.shoot], clear: []),
            .wait(ms: 20_000),
            .keys(set: [], clear: [.shoot]),
            .mark("ceased"),
            .wait(ms: 2_000),
        ]
    )

    private static func soak(name: String, hiddenMines: Bool) -> BenchScenario {
        BenchScenario(
            name: name, hiddenMines: hiddenMines,
            host: [
                .until(.alive, timeoutMs: 15_000),
                .until(.peerAlive, timeoutMs: 90_000),
                .mark("peer-alive"),
                .random(seed: 0x5EED ^ 0xA5A5_A5A5, seconds: 60),
            ] + hostClosing,
            guest: [
                .until(.alive, timeoutMs: 30_000),
                .mark("spawned"),
                .random(seed: 0x5EED ^ 0x5A5A_5A5A, seconds: 60),
            ]
        )
    }

    /// S8. Seeded random play on both sides, the same mix as `HostSimulatedSoakTests`.
    public static let soakOpen = soak(name: "s8-soak-open", hiddenMines: false)
    public static let soakHidden = soak(name: "s8-soak-hidden", hiddenMines: true)
}
