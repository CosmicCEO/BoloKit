import BoloKit
import BoloNet
import Foundation

// MARK: - One run's numbers (v1.6.9 baseline benchmark)
//
// Turns a host log and a guest log into the scorecard's metrics. Every metric is defined here,
// in one place, by the code that computes it; `Bench/README.md` lists them in words.
//
// Names are `<side>.<metric>[.<detail>].<statistic>`, where side is `host`, `guest`, `link`
// (needs both logs) or `correctness`.

public struct RunSummary: Sendable, Equatable, Codable {
    public var schema: Int
    public var runID: String
    public var scenario: String
    public var scenarioHash: String
    public var tier: String
    public var model: String
    public var osBuild: String
    public var valid: Bool
    public var invalidReasons: [String]
    public var metrics: [String: Double]
    /// Divergence that outlasted delivery, for a person to read. In-flight episodes are counted
    /// in `metrics` but not listed.
    public var episodes: [Episode]
}

public enum RunAnalysis {
    private static let tcp = BenchChannel.tcp.rawValue
    private static let udp = BenchChannel.udp.rawValue

    // MARK: Per side

    /// Metrics that need only one process's log.
    static func side(_ log: BenchLog, name: String) -> MetricSet {
        var metrics = MetricSet()
        let ticks = log.of(.tick)
        let span = ticks.count > 1 ? Double(ticks.last!.time &- ticks.first!.time) / 1_000_000_000 : 0
        metrics.set("\(name).run_s", Double(log.lastTime &- log.firstTime) / 1_000_000_000)

        // R1: time between tick handler entries.
        let intervals = zip(ticks, ticks.dropFirst()).map { ($1.time &- $0.time).ms }
        metrics.distribution("\(name).tick_interval_ms", intervals)
        if !intervals.isEmpty {
            metrics.set(
                "\(name).tick_interval_ms.over_25_pct",
                100 * Double(intervals.filter { $0 > 25 }.count) / Double(intervals.count)
            )
            metrics.set("\(name).tick_rate_hz", span > 0 ? Double(intervals.count) / span : nil)
        }

        // R2: timer fire to handler entry. The k-th fire is the k-th tick: each fire yields one.
        let fires = log.of(.timerFire)
        metrics.distribution(
            "\(name).tick_queue_delay_ms",
            zip(fires, ticks).compactMap { $1.time >= $0.time ? ($1.time &- $0.time).ms : nil }
        )
        metrics.count("\(name).ticks_lost", max(fires.count - ticks.count - 1, 0))

        // R3: events waiting when each tick was entered. In: timer fires and messages read.
        // Out: ticks entered and messages whose handling had begun.
        let applies = log.of(.apply)
        let arrivals = (fires + log.of(.receive)).map(\.time).sorted()
        let departures = (ticks.map(\.time) + applies.map { $0.time &- min($0.v0, $0.time) }).sorted()
        var depth: [Double] = []
        var arrived = 0
        var departed = 0
        for tick in ticks {
            while arrived < arrivals.count, arrivals[arrived] <= tick.time { arrived += 1 }
            while departed < departures.count, departures[departed] < tick.time { departed += 1 }
            depth.append(Double(max(arrived - departed - 1, 0)))
        }
        metrics.distribution("\(name).queue_depth", depth)

        // K1 and K2: tick duration by phase. A phase recorded twice in a tick is summed.
        var byPhase: [UInt8: [UInt32: UInt64]] = [:]
        for record in log.of(.phase) { byPhase[record.sub, default: [:]][record.id, default: 0] &+= record.v0 }
        for phase in BenchPhase.allCases {
            guard let durations = byPhase[phase.rawValue] else { continue }
            metrics.distribution("\(name).tick_ms.\(phase)", durations.values.map(\.ms))
        }
        // P1: the main-actor hop's wait is the hop less the work done inside its closures.
        if let hop = byPhase[BenchPhase.renderHop.rawValue], let work = byPhase[BenchPhase.renderHopWork.rawValue] {
            metrics.distribution(
                "\(name).tick_ms.renderHopWait", hop.map { ($0.value &- min(work[$0.key] ?? 0, $0.value)).ms }
            )
        }
        // The instrument's own work inside the tick, taken out of the whole.
        if let whole = byPhase[BenchPhase.whole.rawValue] {
            let digest = byPhase[BenchPhase.digest.rawValue] ?? [:]
            metrics.distribution(
                "\(name).tick_ms.game", whole.map { ($0.value &- min(digest[$0.key] ?? 0, $0.value)).ms }
            )
        }

        // K3 and K4: handling time per message.
        for (channel, label) in [(udp, "udp"), (tcp, "tcp")] {
            let handled = applies.filter { $0.sub == channel }
            metrics.distribution("\(name).apply_us.\(label)", handled.map { Double($0.v0) / 1_000 })
            if channel == udp {
                metrics.distribution(
                    "\(name).apply_us.udp_state_change",
                    handled.filter { $0.v1 > 0 }.map { Double($0.v1) / 1_000 }
                )
            }
        }
        var tcpByOpcode: [UInt32: [Double]] = [:]
        for record in applies where record.sub == tcp { tcpByOpcode[record.id, default: []].append(Double(record.v0) / 1_000) }
        for (opcode, values) in tcpByOpcode { metrics.distribution("\(name).apply_us.tcp.op\(opcode)", values) }

        // K5 and K6: traffic. Payload only, no IP, TCP or UDP headers.
        let seconds = max(Double(log.lastTime &- log.firstTime) / 1_000_000_000, 0.001)
        for (kind, direction) in [(BenchKind.send, "tx"), (BenchKind.receive, "rx")] {
            for (channel, label) in [(udp, "udp"), (tcp, "tcp")] {
                let traffic = log.of(kind).filter { $0.sub == channel }
                let bytes = traffic.reduce(0) { $0 + Double($1.v0) }
                metrics.count("\(name).\(direction).\(label).messages", traffic.count)
                metrics.set("\(name).\(direction).\(label).bytes", bytes)
                metrics.set("\(name).\(direction).\(label).bytes_per_s", bytes / seconds)
                metrics.set("\(name).\(direction).\(label).messages_per_s", Double(traffic.count) / seconds)
                guard channel == tcp else { continue }
                var byOpcode: [UInt32: (count: Int, bytes: Double)] = [:]
                for record in traffic {
                    byOpcode[record.id, default: (0, 0)].count += 1
                    byOpcode[record.id, default: (0, 0)].bytes += Double(record.v0)
                }
                for (opcode, total) in byOpcode {
                    metrics.count("\(name).\(direction).tcp.op\(opcode).messages", total.count)
                    metrics.set("\(name).\(direction).tcp.op\(opcode).bytes", total.bytes)
                }
            }
        }

        // K7: send call to completion.
        for (channel, label) in [(udp, "udp"), (tcp, "tcp")] {
            metrics.distribution(
                "\(name).send_completion_us.\(label)",
                log.of(.sendDone).filter { $0.sub == channel }.map { Double($0.v0) / 1_000 }
            )
        }

        // K8 and K9: process CPU and memory, from the once-a-second samples.
        let samples = log.of(.process)
        let cpu = zip(samples, samples.dropFirst()).compactMap { earlier, later -> Double? in
            let elapsed = later.time &- earlier.time
            return elapsed > 0 ? 100 * Double(later.v0 &- earlier.v0) / Double(elapsed) : nil
        }
        metrics.distribution("\(name).cpu_pct", cpu)
        if let first = samples.first, let last = samples.last, last.time > first.time {
            metrics.set("\(name).cpu_pct.mean", 100 * Double(last.v0 &- first.v0) / Double(last.time &- first.time))
        }
        metrics.distribution("\(name).memory_mb", samples.map { Double($0.v1) / 1_048_576 })
        metrics.set("\(name).thermal_state.max", samples.map { Double($0.sub) }.max())

        // K10, K11 and R10: frames.
        for (layer, label) in [(UInt8(0), "sprites"), (UInt8(1), "terrain")] {
            let frames = log.of(.frame).filter { $0.sub == layer }
            metrics.distribution("\(name).draw_ms.\(label)", frames.map { $0.v0.ms })
            guard layer == 0 else { continue }
            metrics.distribution(
                "\(name).frame_interval_ms", zip(frames, frames.dropFirst()).map { ($1.time &- $0.time).ms }
            )
            if frames.count > 1 {
                let drawn = Double(frames.last!.time &- frames.first!.time) / 1_000_000_000
                metrics.set("\(name).frames_per_s", drawn > 0 ? Double(frames.count - 1) / drawn : nil)
            }
        }
        let rebuilds = log.of(.rebuild)
        metrics.distribution("\(name).tile_grid_rebuild_ms", rebuilds.map { $0.v0.ms })
        metrics.set("\(name).tile_grid_rebuilds_per_s", Double(rebuilds.count) / seconds)

        // R6: scripted key press to the end of the first frame that shows the state after it.
        let renders = log.of(.renderState)
        let sprites = log.of(.frame).filter { $0.sub == 0 }
        var toFrame: [Double] = []
        var render = 0
        var frame = 0
        for input in log.of(.input) {
            while render < renders.count, renders[render].time < input.time { render += 1 }
            guard render < renders.count else { break }
            while frame < sprites.count,
                sprites[frame].time < renders[render].time || sprites[frame].id < renders[render].id
            { frame += 1 }
            guard frame < sprites.count else { break }
            toFrame.append((sprites[frame].time &- input.time).ms)
        }
        metrics.distribution("\(name).input_to_frame_ms", toFrame)

        // R12: dead-reckoning ticks run per update applied.
        metrics.distribution("\(name).extrapolation_ticks", log.of(.extrapolation).map { Double($0.v0) })

        // C6 and C7.
        metrics.count("\(name).invariant_violations", log.of(.invariant).count)
        let rejects = log.of(.reject)
        metrics.count("\(name).datagram_rejects", rejects.count)
        for cause in [BenchReject.noPeer, .malformed, .dropped, .applyReturnedNil] {
            metrics.count("\(name).datagram_rejects.\(cause)", rejects.filter { $0.sub == cause.rawValue }.count)
        }

        // R11: the join as the host saw it.
        let joins = log.of(.join).filter { $0.sub == 1 }
        metrics.distribution("\(name).join_handshake_ms", joins.map { $0.v0.ms })
        if let begin = log.of(.join).first(where: { $0.sub == 0 }), let end = joins.first {
            let during = zip(ticks, ticks.dropFirst())
                .filter { $1.time >= begin.time && $0.time <= end.time &+ 1_000_000_000 }
                .map { ($1.time &- $0.time).ms }
            metrics.set("\(name).join_stall_ms", during.max())
        }

        // K12: the recorder's own cost.
        if let last = log.of(.recorder).last {
            metrics.set("\(name).recorder.dropped", Double(last.v1))
            metrics.set("\(name).recorder.self_ms", last.v0.ms)
            metrics.set("\(name).recorder.self_us_per_tick", ticks.isEmpty ? nil : Double(last.v0) / 1_000 / Double(ticks.count))
        }
        metrics.count("\(name).records", log.records.count)
        return metrics
    }

    // MARK: Across the link

    /// Sequence numbers one side sent, against what the other received from it.
    private static func delivery(sent: [BenchRecord], received: [BenchRecord], until: UInt64) -> (lost: Int, of: Int, reordered: Int) {
        // A datagram sent in the last moments may simply not have arrived before the log ended.
        let sentSeqs = Set(sent.filter { $0.time &+ 500_000_000 <= until }.map(\.v0))
        let arrived = Set(received.map(\.v0))
        var reordered = 0
        var highest: UInt64 = 0
        for record in received {
            if record.v0 < highest { reordered += 1 }
            highest = max(highest, record.v0)
        }
        return (sentSeqs.subtracting(arrived).count, sentSeqs.count, reordered)
    }

    /// For each update `sender` sent, the wait until it first saw the other side acknowledge it.
    private static func acknowledgement(sent: [BenchRecord], heard: [BenchRecord]) -> [Double] {
        var ages: [Double] = []
        var index = 0
        for update in sent {
            while index < heard.count, heard[index].time < update.time || heard[index].v1 < update.v0 { index += 1 }
            guard index < heard.count else { break }
            ages.append((heard[index].time &- update.time).ms)
        }
        return ages
    }

    /// How long `value` took to appear on the other side after each change on this one.
    private static func propagation(from source: [BenchRecord], to destination: [BenchRecord], part: (UInt64) -> UInt64) -> [Double] {
        var delays: [Double] = []
        var index = 0
        var last: UInt64?
        for change in source {
            let value = part(change.v0)
            if value == last { continue }
            last = value
            while index < destination.count, destination[index].time < change.time { index += 1 }
            var probe = index
            // The value may be skipped on the far side if it changed again before an update went.
            while probe < destination.count, destination[probe].time &- change.time <= 2_000_000_000 {
                if part(destination[probe].v0) == value {
                    delays.append((destination[probe].time &- change.time).ms)
                    break
                }
                probe += 1
            }
        }
        return delays
    }

    static func link(host: BenchLog, guest: BenchLog, slot: Int) -> MetricSet {
        var metrics = MetricSet()
        let until = min(host.lastTime, guest.lastTime)

        // The host stamps its own update every fifth tick whether or not it has anywhere to send
        // it: it cannot send to a guest until that guest's first datagram has arrived. Only
        // updates from the first one actually sent to this guest count as sent.
        let firstSend = host.of(.send).first { $0.sub == udp && Int($0.v1) == slot }?.time
        // The stamp is made just before the send it belongs to.
        let flowStart = firstSend.map { $0 &- min($0, 5_000_000) } ?? UInt64.max

        // C8: loss and reordering, each way.
        let hostSent = host.of(.datagram).filter { $0.sub == 0 && $0.time >= flowStart }
        let guestSent = guest.of(.datagram).filter { $0.sub == 0 }
        let hostHeard = host.of(.datagram).filter { $0.sub == 1 && Int($0.id) == slot }
        let guestHeard = guest.of(.datagram).filter { $0.sub == 1 && $0.id == 0 }
        for (label, sent, received) in [("host_to_guest", hostSent, guestHeard), ("guest_to_host", guestSent, hostHeard)] {
            let result = delivery(sent: sent, received: received, until: until)
            metrics.count("link.udp.\(label).sent", result.of)
            metrics.count("link.udp.\(label).lost", result.lost)
            metrics.set("link.udp.\(label).loss_pct", result.of > 0 ? 100 * Double(result.lost) / Double(result.of) : nil)
            metrics.count("link.udp.\(label).reordered", result.reordered)
        }

        // R4: how long until a side sees its own update acknowledged.
        metrics.distribution("link.ack_age_ms.guest", acknowledgement(sent: guestSent, heard: guestHeard))
        metrics.distribution("link.ack_age_ms.host", acknowledgement(sent: hostSent, heard: hostHeard))

        // UDP one-way delay: the same sequence number, sent on one log and received on the other.
        for (label, sent, received) in [("host_to_guest", hostSent, guestHeard), ("guest_to_host", guestSent, hostHeard)] {
            let sentAt = Dictionary(sent.map { ($0.v0, $0.time) }, uniquingKeysWith: { first, _ in first })
            metrics.distribution(
                "link.udp.\(label).delay_ms",
                received.compactMap { record in
                    sentAt[record.v0].flatMap { record.time >= $0 ? (record.time &- $0).ms : nil }
                }
            )
        }

        // R5: TCP is reliable and ordered, so the k-th message sent to this guest is the k-th it
        // read and the k-th it applied.
        let sends = host.of(.send).filter { $0.sub == tcp && Int($0.v1) == slot }
        let reads = guest.of(.receive).filter { $0.sub == tcp }
        let applied = guest.of(.apply).filter { $0.sub == tcp }
        metrics.count("link.tcp.sent", sends.count)
        metrics.count("link.tcp.read", reads.count)
        metrics.count("link.tcp.unpaired", abs(sends.count - reads.count))
        var mismatched = 0
        var toRead: [Double] = []
        var toApplied: [Double] = []
        var byOpcode: [UInt32: [Double]] = [:]
        for index in 0..<min(sends.count, reads.count) {
            guard sends[index].id == reads[index].id, reads[index].time >= sends[index].time else {
                mismatched += 1
                continue
            }
            toRead.append((reads[index].time &- sends[index].time).ms)
            guard index < applied.count, applied[index].id == sends[index].id else { continue }
            let delay = (applied[index].time &- sends[index].time).ms
            toApplied.append(delay)
            byOpcode[sends[index].id, default: []].append(delay)
        }
        metrics.count("link.tcp.mismatched", mismatched)
        metrics.distribution("link.tcp.send_to_read_ms", toRead)
        metrics.distribution("link.tcp.send_to_applied_ms", toApplied)
        for (opcode, values) in byOpcode { metrics.distribution("link.tcp.send_to_applied_ms.op\(opcode)", values) }

        // R8: the guest's own tile and direction reaching the host, and R9 the other way.
        let selfDomain = DigestDomain.selfStatus.rawValue
        let peers = DigestDomain.peers.rawValue
        let position: (UInt64) -> UInt64 = { ($0 >> 8) & 0xf_ffff }
        let tile: (UInt64) -> UInt64 = { ($0 >> 8) & 0xffff }
        metrics.distribution(
            "link.position_delay_ms.guest_to_host",
            propagation(
                from: guest.of(.state).filter { $0.sub == selfDomain },
                to: host.of(.state).filter { $0.sub == selfDomain && Int($0.v1) == slot }, part: position
            )
        )
        let hostTank = host.of(.state).filter { $0.sub == peers && $0.id == 0 && Int($0.v1) == slot }
        let hostTankSeen = guest.of(.state).filter { $0.sub == peers && $0.id == 0 }
        metrics.distribution(
            "link.position_delay_ms.host_to_guest", propagation(from: hostTank, to: hostTankSeen, part: tile)
        )
        // R9: how often the host's tank moves on the guest's screen while it is moving.
        var moves: [UInt64] = []
        var seen: UInt64?
        for record in hostTankSeen where tile(record.v0) != seen {
            seen = tile(record.v0)
            moves.append(record.time)
        }
        metrics.distribution(
            "guest.remote_move_interval_ms",
            zip(moves, moves.dropFirst()).map { ($1 &- $0).ms }.filter { $0 <= 1_000 }
        )
        return metrics
    }

    // MARK: What the guest drew

    /// P1: the host's tank (always slot 0) as the guest's render view drew it, from the `drawn`
    /// records written each frame its smoothed position moved. Steps more than a second apart
    /// are left out of both metrics, as for `remote_move_interval_ms`, so a tank that stood
    /// still (or respawned elsewhere) does not count as one slow, long step.
    static func drawn(guest: BenchLog) -> MetricSet {
        var metrics = MetricSet()
        var steps: [BenchRecord] = []
        for record in guest.of(.drawn) where record.id == 0 {
            if let last = steps.last, last.v0 == record.v0, last.v1 == record.v1 { continue }
            steps.append(record)
        }
        var intervals: [Double] = []
        var sizes: [Double] = []
        for (earlier, later) in zip(steps, steps.dropFirst()) {
            let interval = (later.time &- earlier.time).ms
            guard interval <= 1_000 else { continue }
            intervals.append(interval)
            let dx = Double(later.v0) - Double(earlier.v0)
            let dy = Double(later.v1) - Double(earlier.v1)
            sizes.append((dx * dx + dy * dy).squareRoot() / Double(BenchDrawnProbe.unitsPerTile))
        }
        metrics.distribution("guest.drawn_remote_step_ms", intervals)
        metrics.distribution("guest.drawn_remote_step_tiles", sizes)
        return metrics
    }

    // MARK: Whole run

    public struct RunFacts: Sendable {
        public var scenario: BenchScenario
        public var tier: String
        public var killed: Bool
        public var hostExit: Int32
        public var guestExit: Int32

        public init(scenario: BenchScenario, tier: String, killed: Bool = false, hostExit: Int32 = 0, guestExit: Int32 = 0) {
            self.scenario = scenario
            self.tier = tier
            self.killed = killed
            self.hostExit = hostExit
            self.guestExit = guestExit
        }
    }

    public static func scenarioHash(_ scenario: BenchScenario) -> String {
        let data = (try? scenario.encoded()) ?? Data()
        return String(digestHash(data.map { UInt64($0) }), radix: 16)
    }

    /// Reasons this run cannot be used, empty when it can. C10.
    static func invalidReasons(host: BenchLog, guest: BenchLog?, facts: RunFacts) -> [String] {
        var reasons: [String] = []
        if facts.killed { reasons.append("killed by the watchdog") }
        if facts.hostExit != 0 { reasons.append("host exited with \(facts.hostExit)") }
        if facts.guestExit != 0 { reasons.append("guest exited with \(facts.guestExit)") }
        for (name, log, steps) in [("host", Optional(host), facts.scenario.host), ("guest", guest, facts.scenario.guest)] {
            guard let log else { continue }
            let marks = log.of(.mark)
            for mark in marks where mark.sub == BenchMark.stepTimedOut.rawValue {
                reasons.append("\(name) step \(mark.id) timed out")
            }
            if marks.contains(where: { $0.sub == BenchMark.hostingFellBack.rawValue }) {
                reasons.append("hosting was unavailable")
            }
            if !marks.contains(where: { $0.sub == BenchMark.scenarioEnd.rawValue }) {
                reasons.append("\(name) never finished its script")
            }
            let reached = marks.filter { $0.sub == BenchMark.stepReached.rawValue }.count
            if reached != steps.count, !reasons.contains(where: { $0.hasPrefix(name) }) {
                reasons.append("\(name) reached \(reached) of \(steps.count) steps")
            }
            if let dropped = log.of(.recorder).last?.v1, dropped > 0 {
                reasons.append("\(name) recorder dropped \(dropped) records")
            }
        }
        if let guest, guest.header.model != host.header.model || guest.header.osBuild != host.header.osBuild {
            reasons.append("host and guest logs are from different machines")
        }
        return reasons
    }

    /// `guest` is `nil` for the scaling sweep, which measures the host only.
    public static func summarize(host: BenchLog, guest: BenchLog?, facts: RunFacts) -> RunSummary {
        var metrics = side(host, name: "host").values
        var episodes: [Episode] = []
        if let guest {
            metrics.merge(side(guest, name: "guest").values) { _, new in new }
            metrics.merge(drawn(guest: guest).values) { _, new in new }
            if let divergence = findDivergence(host: host, guest: guest) {
                metrics.merge(divergence.metrics().values) { _, new in new }
                metrics.merge(link(host: host, guest: guest, slot: divergence.guest).values) { _, new in new }
                episodes = divergence.episodes.filter { $0.length != .inFlight && !$0.domain.isInformational }

                // C9: the guest seeing more, or less, than the host believes it can.
                let fog = divergence.episodes(in: .fogVisible).filter { $0.length != .inFlight }
                metrics["correctness.fog_over_reveal_tiles"] = Double(Set(fog.filter { $0.guestValue == 1 }.map(\.element)).count)
                metrics["correctness.fog_under_reveal_tiles"] = Double(Set(fog.filter { $0.hostValue == 1 }.map(\.element)).count)
            }
            // R11: from the guest's TCP join completing to its first step (alive) being reached.
            let marks = guest.of(.mark)
            if let joined = marks.first(where: { $0.sub == BenchMark.joined.rawValue }),
                let alive = marks.first(where: { $0.sub == BenchMark.stepReached.rawValue && $0.time >= joined.time })
            {
                metrics["guest.join_to_alive_ms"] = (alive.time &- joined.time).ms
            }
        }
        let reasons = invalidReasons(host: host, guest: guest, facts: facts)
        return RunSummary(
            schema: BoloBench.schemaVersion, runID: host.header.runID, scenario: facts.scenario.name,
            scenarioHash: scenarioHash(facts.scenario), tier: facts.tier, model: host.header.model,
            osBuild: host.header.osBuild, valid: reasons.isEmpty, invalidReasons: reasons, metrics: metrics,
            episodes: episodes
        )
    }
}
