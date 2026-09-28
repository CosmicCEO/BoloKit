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
    public static let all: [BenchScenario] = [joinAndSpawn, soakOpen, soakHidden]

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
