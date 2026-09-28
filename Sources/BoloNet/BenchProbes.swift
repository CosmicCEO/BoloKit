import BoloKit

// MARK: - Benchmark probes (v1.6.9 baseline benchmark)
//
// Measurement only. The small helpers the instrumented call sites use, kept here so each call
// site in shipped code stays one line. With recording off every helper holds a `nil` recorder
// and does nothing.

/// Splits one tick into consecutive phases: each `mark` closes the phase that began at the
/// previous one.
public struct BenchLap {
    public let recorder: BenchRecorder?
    public let tick: UInt32
    private let start: UInt64
    private var last: UInt64

    public init(recorder: BenchRecorder?, tick: UInt32) {
        self.recorder = recorder
        self.tick = tick
        start = recorder == nil ? 0 : BoloBench.now()
        last = start
        recorder?.record(.tick, id: tick, at: start)
    }

    public mutating func mark(_ phase: BenchPhase) {
        guard let recorder else { return }
        let now = BoloBench.now()
        recorder.record(.phase, sub: phase.rawValue, id: tick, v0: now &- last, at: now)
        last = now
    }

    /// Restarts the clock without recording, to leave out time that belongs to no phase.
    public mutating func skip() {
        guard recorder != nil else { return }
        last = BoloBench.now()
    }

    public func finish() {
        recorder?.phase(.whole, tick: tick, since: start)
    }
}

/// One send, from the call to its completion.
public struct BenchSend {
    private let recorder: BenchRecorder?
    private let start: UInt64
    private let channel: BenchChannel
    private let opcode: UInt32

    public init(_ bytes: [UInt8], channel: BenchChannel, recipient: Int, recorder: BenchRecorder? = BoloBench.recorder) {
        self.recorder = recorder
        self.channel = channel
        opcode = UInt32(bytes.first ?? 0)
        guard let recorder else {
            start = 0
            return
        }
        start = BoloBench.now()
        recorder.record(
            .send, sub: channel.rawValue, id: opcode, v0: UInt64(bytes.count),
            v1: UInt64(truncatingIfNeeded: recipient), at: start
        )
    }

    public func done() {
        guard let recorder else { return }
        let now = BoloBench.now()
        recorder.record(.sendDone, sub: channel.rawValue, id: opcode, v0: now &- start, at: now)
    }
}

/// A message handled from start to finish.
public struct BenchApply {
    private let recorder: BenchRecorder?
    private let start: UInt64
    private let channel: BenchChannel
    private let opcode: UInt32

    public init(channel: BenchChannel, opcode: UInt8, recorder: BenchRecorder? = BoloBench.recorder) {
        self.recorder = recorder
        self.channel = channel
        self.opcode = UInt32(opcode)
        start = recorder == nil ? 0 : BoloBench.now()
    }

    /// `inner` is the part of the total spent in the state change itself, when that is timed
    /// separately from the surrounding bookkeeping.
    public func done(inner: UInt64 = 0) {
        guard let recorder else { return }
        let now = BoloBench.now()
        recorder.record(.apply, sub: channel.rawValue, id: opcode, v0: now &- start, v1: inner, at: now)
    }
}

extension BenchRecorder {
    /// A message arriving, stamped where it is read, before it waits for the consumer.
    public func received(_ bytes: [UInt8], channel: BenchChannel, sender: Int, opcode: UInt8? = nil) {
        record(
            .receive, sub: channel.rawValue, id: UInt32(opcode ?? bytes.first ?? 0), v0: UInt64(bytes.count),
            v1: UInt64(truncatingIfNeeded: sender)
        )
    }

    /// A position update sent or received, with the sequence numbers it carries.
    /// `local` is this process's own player slot.
    public func datagram(sent: Bool, header: CLUpdateHeader, local: Int) {
        let sender = Int(header.player)
        let own = header.seq.indices.contains(sender) ? header.seq[sender] : 0
        let echo = header.seq.indices.contains(local) ? header.seq[local] : 0
        record(
            .datagram, sub: sent ? 0 : 1, id: UInt32(sender), v0: UInt64(UInt32(bitPattern: own)),
            v1: UInt64(UInt32(bitPattern: echo))
        )
    }

    public func rejected(_ cause: BenchReject, player: Int? = nil) {
        record(.reject, sub: cause.rawValue, id: player.map { UInt32(truncatingIfNeeded: $0) } ?? .max)
    }

    /// Armour, shells and mines of `player`, recorded only when outside their legal range.
    public func checkInvariants(player: Int, state: GameState) {
        guard state.players.indices.contains(player), state.localStats.indices.contains(player) else { return }
        let stats = state.localStats[player]
        let checks: [(BenchInvariant, Int, Int)] = [
            (.armour, stats.armour, maxArmour), (.shells, stats.shells, maxShells),
            (.mines, state.players[player].mines, maxMines),
        ]
        for (invariant, value, limit) in checks where !(0...limit).contains(value) {
            record(
                .invariant, sub: invariant.rawValue, id: UInt32(truncatingIfNeeded: player),
                v0: UInt64(bitPattern: Int64(value))
            )
        }
    }
}

/// The host's record of what each guest should hold: one tracker per connected guest.
public struct BenchHostStateProbe {
    /// Terrain and fog are 65,536 elements each, so they are sampled at the update rate
    /// (every 5th tick) instead of every tick.
    public static let gridInterval: UInt32 = 5

    private var trackers: [Int: StateDigestTracker] = [:]
    private var changes: [DigestChange] = []

    public init() {}

    public mutating func sample(
        state: GameState, fogState: (Int) -> FogState?, tick: UInt32, recorder: BenchRecorder
    ) {
        for player in state.players.indices where player != state.localPlayer {
            guard state.players[player].connected else {
                trackers[player] = nil
                continue
            }
            var tracker = trackers[player] ?? StateDigestTracker(player: player)
            changes.removeAll(keepingCapacity: true)
            tracker.sampleSmallDomains(state, into: &changes)
            if tick % Self.gridInterval == 0 {
                let fog = state.hiddenMines ? fogState(player) : nil
                tracker.sampleTerrain(
                    view: expectedGuestTerrainView(terrain: state.terrain, fogState: fog), into: &changes
                )
                if let fog { tracker.sampleFog(fog, into: &changes) }
            }
            trackers[player] = tracker
            recorder.changes(changes, view: player)
            recorder.checkInvariants(player: player, state: state)
        }
        recorder.checkInvariants(player: state.localPlayer, state: state)
    }

    /// One whole-domain hash per domain and guest, from the values last sampled.
    public func snapshot(recorder: BenchRecorder) {
        for (player, tracker) in trackers {
            for domain in DigestDomain.allCases {
                recorder.record(
                    .snapshot, sub: domain.rawValue, v0: tracker.hash(of: domain),
                    v1: UInt64(truncatingIfNeeded: player)
                )
            }
        }
    }
}
