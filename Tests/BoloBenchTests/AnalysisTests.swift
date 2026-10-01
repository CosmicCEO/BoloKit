import Foundation
import Testing
import BoloKit
import BoloNet

@testable import BoloBenchCore

// v1.6.9 baseline benchmark: statistics, log reading, per-run metrics, scorecards and
// comparison, all against inputs where the right answer is known.

// MARK: - Statistics

@Test func percentilesAreNearestRank() {
    let values = (1...100).map(Double.init)
    #expect(Stats.percentile(values, 0.50) == 50)
    #expect(Stats.percentile(values, 0.95) == 95)
    #expect(Stats.percentile(values, 0.99) == 99)
    #expect(Stats.percentile(values, 1.0) == 100)
    #expect(Stats.percentile([7], 0.95) == 7)
    #expect(Stats.percentile([], 0.5) == nil)
    #expect(Stats.median([3, 1, 2]) == 2)
    #expect(Stats.median([4, 1, 2, 3]) == 2.5)
}

@Test func theBootstrapIntervalIsDeterministicAndBracketsTheMedian() throws {
    let values: [Double] = [10.1, 9.8, 10.4, 10.0, 9.9, 10.2, 10.3, 9.7, 10.0, 10.1]
    let first = try #require(Stats.medianInterval(values))
    let second = try #require(Stats.medianInterval(values))
    #expect(first == second)
    let median = try #require(Stats.median(values))
    #expect(first.low <= median && median <= first.high)
    #expect(first.high - first.low < 0.6)
    #expect(Stats.medianInterval([5]) == nil)
}

@Test func theRankSumTestSeparatesShiftedSamplesAndNotIdenticalOnes() throws {
    let a: [Double] = [10.1, 9.8, 10.4, 10.0, 9.9, 10.2, 10.3, 9.7, 10.05, 10.15]
    let shifted = a.map { $0 + 2 }
    #expect(try #require(Stats.rankSumP(a, shifted)) < 0.001)
    #expect(try #require(Stats.rankSumP(a, a)) > 0.9)
    #expect(Stats.rankSumP([1, 1, 1], [1, 1, 1]) == nil, "no spread at all, nothing to rank")
    #expect(Stats.rankSumP([], a) == nil)
}

@Test func wilsonIntervalsStayInsideZeroToOne() throws {
    let none = try #require(Stats.wilson(successes: 0, trials: 10))
    #expect(none.low == 0 && none.high > 0.2 && none.high < 0.35)
    let one = try #require(Stats.wilson(successes: 1, trials: 12))
    #expect(one.low > 0 && one.high < 0.4)
    #expect(Stats.wilson(successes: 0, trials: 0) == nil)
}

// MARK: - Reading logs

@Test func aLogIsReadInTimeOrderAndStrayLinesAreSkipped() throws {
    let text = """
        some stray output before the header
        {"type":"header","schema":\(BoloBench.schemaVersion),"role":"host","runId":"r1","model":"MacBookPro17,1","osBuild":"26A428","mono":100,"wall":1.5,"cores":8,"memoryBytes":17179869184,"lowPowerMode":false,"thermalState":0}
        {"t":300,"k":1,"s":0,"i":2,"a":0,"b":0}
        not a record
        {"t":100,"k":1,"s":0,"i":1,"a":0,"b":0}
        {"t":300,"k":11,"s":4,"i":0,"a":0,"b":0}
        """
    let log = try BenchLog(text: text)
    #expect(log.header.role == "host")
    #expect(log.header.model == "MacBookPro17,1")
    #expect(log.header.memoryBytes == 17_179_869_184)
    #expect(log.records.map(\.time) == [100, 300, 300])
    // Records sharing a timestamp keep the order they were written in.
    #expect(log.records.map(\.kind) == [BenchKind.tick.rawValue, BenchKind.tick.rawValue, BenchKind.mark.rawValue])
    #expect(log.of(.tick).map(\.id) == [1, 2])
}

@Test func aLogWithoutAHeaderOrFromAnotherSchemaIsRefused() {
    #expect(throws: BenchLogError.noHeader) { try BenchLog(text: #"{"t":1,"k":1,"s":0,"i":1,"a":0,"b":0}"#) }
    #expect(throws: BenchLogError.wrongSchema(99)) {
        try BenchLog(text: #"{"type":"header","schema":99,"role":"host","runId":"r"}"#)
    }
}

// MARK: - One side

private func record(_ kind: BenchKind, at time: UInt64, sub: UInt8 = 0, id: UInt32 = 0, v0: UInt64 = 0, v1: UInt64 = 0) -> BenchRecord {
    BenchRecord(time: t0 + time, kind: kind, sub: sub, id: id, v0: v0, v1: v1)
}

@Test func tickTimingComesFromTheTicksAndTheirTimerFires() {
    var records: [BenchRecord] = []
    // 100 ticks 20 ms apart, each entered 1 ms after its timer fired; one tick 15 ms late.
    for index in 0..<100 {
        let late: UInt64 = index == 50 ? 15 * ms : 0
        let fire = UInt64(index) * 20 * ms
        records.append(record(.timerFire, at: fire))
        records.append(record(.tick, at: fire + 1 * ms + late, id: UInt32(index + 1)))
        records.append(record(.phase, at: fire + 3 * ms + late, sub: BenchPhase.whole.rawValue, id: UInt32(index + 1), v0: 2 * ms))
        records.append(record(.phase, at: fire + 2 * ms + late, sub: BenchPhase.digest.rawValue, id: UInt32(index + 1), v0: 500_000))
    }
    let metrics = RunAnalysis.side(BenchLog(header: header("host"), records: records), name: "host")
    #expect(metrics["host.tick_interval_ms.p50"] == 20)
    #expect(metrics["host.tick_interval_ms.max"] == 35)
    #expect(metrics["host.tick_interval_ms.n"] == 99)
    // Two of 99 intervals are off: the late tick's own (35 ms) is over 25; the next (5 ms) is not.
    #expect(abs((metrics["host.tick_interval_ms.over_25_pct"] ?? 0) - 100.0 / 99) < 0.001)
    #expect(metrics["host.tick_queue_delay_ms.p50"] == 1)
    #expect(metrics["host.tick_queue_delay_ms.max"] == 16)
    #expect(metrics["host.ticks_lost"] == 0)
    #expect(metrics["host.tick_ms.whole.p50"] == 2)
    // The instrument's own digest work is taken out of the game's tick time.
    #expect(metrics["host.tick_ms.game.p50"] == 1.5)
}

@Test func aPhaseRecordedTwiceInOneTickIsSummed() {
    let records = [
        record(.tick, at: 0, id: 1),
        record(.phase, at: 1 * ms, sub: BenchPhase.terrainDiff.rawValue, id: 1, v0: 300_000),
        record(.phase, at: 2 * ms, sub: BenchPhase.terrainDiff.rawValue, id: 1, v0: 200_000),
    ]
    let metrics = RunAnalysis.side(BenchLog(header: header("host"), records: records), name: "host")
    #expect(metrics["host.tick_ms.terrainDiff.n"] == 1)
    #expect(metrics["host.tick_ms.terrainDiff.p50"] == 0.5)
}

@Test func theHopsWaitIsTheHopLessTheWorkInsideIt() {
    var records: [BenchRecord] = []
    // Four ticks whose main-actor hop takes 12 ms, with 1, 2, 3 and 4 ms of work inside it.
    for tick in 1...4 {
        let at = UInt64(tick) * 20 * ms
        records.append(record(.tick, at: at, id: UInt32(tick)))
        records.append(record(.phase, at: at + 1 * ms, sub: BenchPhase.renderHopWork.rawValue, id: UInt32(tick), v0: UInt64(tick) * ms))
        records.append(record(.phase, at: at + 13 * ms, sub: BenchPhase.renderHop.rawValue, id: UInt32(tick), v0: 12 * ms))
    }
    let metrics = RunAnalysis.side(BenchLog(header: header("host"), records: records), name: "host")
    #expect(metrics["host.tick_ms.renderHop.n"] == 4)
    #expect(metrics["host.tick_ms.renderHop.max"] == 12)
    #expect(metrics["host.tick_ms.renderHopWork.n"] == 4)
    #expect(metrics["host.tick_ms.renderHopWork.max"] == 4)
    #expect(metrics["host.tick_ms.renderHopWait.n"] == 4)
    #expect(metrics["host.tick_ms.renderHopWait.max"] == 11)
    #expect(metrics["host.tick_ms.renderHopWait.p50"] == 9)
}

@Test func drawnStepsAreTheFramesInWhichTheHostsTankMovedOnTheGuestsScreen() {
    let records = [
        record(.drawn, at: 0, id: 0, v0: 160, v1: 160),
        // A sixteenth of a tile, 20 ms later.
        record(.drawn, at: 20 * ms, id: 0, v0: 161, v1: 160),
        // Another player's tank does not count.
        record(.drawn, at: 40 * ms, id: 1, v0: 999, v1: 999),
        // A whole tile, 40 ms later.
        record(.drawn, at: 60 * ms, id: 0, v0: 161, v1: 176),
        // The same spot again is no step.
        record(.drawn, at: 80 * ms, id: 0, v0: 161, v1: 176),
        // After standing still for two seconds: neither the interval nor the jump counts.
        record(.drawn, at: 60 * ms + 2 * second, id: 0, v0: 200, v1: 176),
        // Five sixteenths (3, 4), 100 ms later.
        record(.drawn, at: 60 * ms + 2 * second + 100 * ms, id: 0, v0: 203, v1: 180),
    ]
    let metrics = RunAnalysis.drawn(guest: BenchLog(header: header("join"), records: records))
    #expect(metrics["guest.drawn_remote_step_ms.n"] == 3)
    #expect(metrics["guest.drawn_remote_step_ms.p50"] == 40)
    #expect(metrics["guest.drawn_remote_step_ms.max"] == 100)
    #expect(metrics["guest.drawn_remote_step_tiles.n"] == 3)
    #expect(metrics["guest.drawn_remote_step_tiles.p50"] == 0.3125)
    #expect(metrics["guest.drawn_remote_step_tiles.max"] == 1)
}

@Test func trafficIsCountedPerChannelDirectionAndOpcode() {
    let tcp = BenchChannel.tcp.rawValue
    let udp = BenchChannel.udp.rawValue
    let records = [
        record(.send, at: 0, sub: tcp, id: 34, v0: 4, v1: 1),
        record(.send, at: 1 * ms, sub: tcp, id: 34, v0: 4, v1: 1),
        record(.send, at: 2 * ms, sub: tcp, id: 35, v0: 31, v1: 1),
        record(.send, at: 3 * ms, sub: udp, id: 0, v0: 113, v1: 1),
        record(.receive, at: 4 * ms, sub: udp, id: 1, v0: 123, v1: 1),
        record(.sendDone, at: 5 * ms, sub: tcp, id: 34, v0: 40_000),
        record(.mark, at: 2 * second),
    ]
    let metrics = RunAnalysis.side(BenchLog(header: header("host"), records: records), name: "host")
    #expect(metrics["host.tx.tcp.messages"] == 3)
    #expect(metrics["host.tx.tcp.bytes"] == 39)
    #expect(metrics["host.tx.tcp.op34.messages"] == 2)
    #expect(metrics["host.tx.tcp.op34.bytes"] == 8)
    #expect(metrics["host.tx.tcp.op35.bytes"] == 31)
    #expect(metrics["host.tx.udp.bytes"] == 113)
    #expect(metrics["host.rx.udp.bytes"] == 123)
    #expect(metrics["host.tx.tcp.bytes_per_s"] == 19.5)
    #expect(metrics["host.send_completion_us.tcp.p50"] == 40)
}

@Test func processorUseIsTheChangeInProcessorTimeOverTheChangeInTime() {
    let records = [
        record(.process, at: 0, v0: 0, v1: 100 * 1_048_576),
        record(.process, at: 1 * second, v0: 250 * ms, v1: 120 * 1_048_576),
        record(.process, at: 2 * second, v0: 750 * ms, v1: 110 * 1_048_576),
    ]
    let metrics = RunAnalysis.side(BenchLog(header: header("host"), records: records), name: "host")
    #expect(metrics["host.cpu_pct.mean"] == 37.5)
    #expect(metrics["host.cpu_pct.max"] == 50)
    #expect(metrics["host.memory_mb.max"] == 120)
}

@Test func inputToFrameEndsAtTheFirstFrameShowingAStateMadeAfterTheInput() {
    let records = [
        record(.renderState, at: 0, id: 1),
        record(.frame, at: 2 * ms, sub: 0, id: 1, v0: 100_000),
        record(.input, at: 5 * ms, sub: BenchInput.flags.rawValue),
        // A frame drawn after the input but still showing the state from before it.
        record(.frame, at: 18 * ms, sub: 0, id: 1, v0: 100_000),
        record(.renderState, at: 20 * ms, id: 2),
        record(.frame, at: 34 * ms, sub: 0, id: 2, v0: 100_000),
    ]
    let metrics = RunAnalysis.side(BenchLog(header: header("join"), records: records), name: "guest")
    #expect(metrics["guest.input_to_frame_ms.n"] == 1)
    #expect(metrics["guest.input_to_frame_ms.p50"] == 29)
}

@Test func queueDepthCountsEventsStillWaitingWhenATickIsEntered() {
    let tcp = BenchChannel.tcp.rawValue
    let records = [
        record(.timerFire, at: 0), record(.tick, at: 1 * ms, id: 1),
        // Three messages read, and a timer fire, all before the next tick is entered.
        record(.receive, at: 10 * ms, sub: tcp, id: 34, v0: 4),
        record(.receive, at: 11 * ms, sub: tcp, id: 34, v0: 4),
        record(.receive, at: 12 * ms, sub: tcp, id: 34, v0: 4),
        record(.timerFire, at: 20 * ms),
        // One of them had been handled by then.
        record(.apply, at: 14 * ms, sub: tcp, id: 34, v0: 1 * ms),
        record(.tick, at: 25 * ms, id: 2),
    ]
    let metrics = RunAnalysis.side(BenchLog(header: header("join"), records: records), name: "guest")
    // In: 2 fires + 3 reads. Out before the tick: tick 1 and one message. The tick itself is one
    // of the five, so two messages were waiting behind it.
    #expect(metrics["guest.queue_depth.max"] == 2)
}

// MARK: - Across the link

private func datagram(sent: Bool, sender: Int, seq: UInt64, echo: UInt64 = 0, at time: UInt64) -> BenchRecord {
    record(.datagram, at: time, sub: sent ? 0 : 1, id: UInt32(sender), v0: seq, v1: echo)
}

@Test func lossIsWhatWasSentAndNeverArrived() {
    let udp = BenchChannel.udp.rawValue
    var host: [BenchRecord] = [
        // Stamped before the guest's flow existed: never sent, so not lost.
        datagram(sent: true, sender: 0, seq: 5, at: 100 * ms),
        record(.send, at: 200 * ms + 1, sub: udp, id: 0, v0: 113, v1: 1),
    ]
    var guest: [BenchRecord] = []
    for index in 0..<10 {
        let seq = UInt64(10 + index * 5)
        let time = 200 * ms + UInt64(index) * 100 * ms
        host.append(datagram(sent: true, sender: 0, seq: seq, at: time))
        if index != 4 { guest.append(datagram(sent: false, sender: 0, seq: seq, echo: 0, at: time + 300_000)) }
    }
    // Two arrive swapped.
    guest.swapAt(1, 2)
    guest = guest.enumerated().map { index, item in
        var item = item
        item.time = t0 + 200 * ms + UInt64(index) * 100 * ms + 300_000
        return item
    }
    host.append(record(.mark, at: 5 * second))
    guest.append(record(.mark, at: 5 * second))

    let metrics = RunAnalysis.link(
        host: BenchLog(header: header("host"), records: host), guest: BenchLog(header: header("join"), records: guest),
        slot: 1
    )
    #expect(metrics["link.udp.host_to_guest.sent"] == 10)
    #expect(metrics["link.udp.host_to_guest.lost"] == 1)
    #expect(metrics["link.udp.host_to_guest.loss_pct"] == 10)
    #expect(metrics["link.udp.host_to_guest.reordered"] == 1)
}

@Test func acknowledgementAgeIsTheWaitForTheOtherSideToEchoTheUpdate() {
    let udp = BenchChannel.udp.rawValue
    let host = [
        record(.send, at: 0, sub: udp, id: 0, v0: 113, v1: 1),
        datagram(sent: false, sender: 1, seq: 100, at: 1 * ms),
        datagram(sent: false, sender: 1, seq: 105, at: 101 * ms),
        record(.mark, at: 5 * second),
    ]
    let guest = [
        datagram(sent: true, sender: 1, seq: 100, at: 0),
        // The host's next update still echoes the guest's previous one.
        datagram(sent: false, sender: 0, seq: 50, echo: 95, at: 30 * ms),
        datagram(sent: false, sender: 0, seq: 55, echo: 100, at: 62 * ms),
        datagram(sent: true, sender: 1, seq: 105, at: 100 * ms),
        datagram(sent: false, sender: 0, seq: 60, echo: 105, at: 160 * ms),
        record(.mark, at: 5 * second),
    ]
    let metrics = RunAnalysis.link(
        host: BenchLog(header: header("host"), records: host), guest: BenchLog(header: header("join"), records: guest),
        slot: 1
    )
    #expect(metrics["link.ack_age_ms.guest.n"] == 2)
    #expect(metrics["link.ack_age_ms.guest.p50"] == 60)
    #expect(metrics["link.ack_age_ms.guest.max"] == 62)
    #expect(metrics["link.udp.guest_to_host.delay_ms.p50"] == 1)
}

@Test func reliableMessagesPairBySequenceAndReportEachLeg() {
    let tcp = BenchChannel.tcp.rawValue
    let host = [
        record(.send, at: 0, sub: tcp, id: 34, v0: 4, v1: 1),
        record(.send, at: 1 * ms, sub: tcp, id: 35, v0: 31, v1: 1),
        // To another guest: not part of this link.
        record(.send, at: 2 * ms, sub: tcp, id: 35, v0: 31, v1: 2),
        record(.mark, at: 5 * second),
    ]
    let guest = [
        record(.receive, at: 3 * ms, sub: tcp, id: 34, v0: 4),
        record(.apply, at: 5 * ms, sub: tcp, id: 34, v0: 500_000),
        record(.receive, at: 6 * ms, sub: tcp, id: 35, v0: 31),
        record(.apply, at: 9 * ms, sub: tcp, id: 35, v0: 500_000),
        record(.mark, at: 5 * second),
    ]
    let metrics = RunAnalysis.link(
        host: BenchLog(header: header("host"), records: host), guest: BenchLog(header: header("join"), records: guest),
        slot: 1
    )
    #expect(metrics["link.tcp.sent"] == 2)
    #expect(metrics["link.tcp.read"] == 2)
    #expect(metrics["link.tcp.unpaired"] == 0)
    #expect(metrics["link.tcp.mismatched"] == 0)
    #expect(metrics["link.tcp.send_to_read_ms.max"] == 5)
    #expect(metrics["link.tcp.send_to_applied_ms.op34.p50"] == 5)
    #expect(metrics["link.tcp.send_to_applied_ms.op35.p50"] == 8)
}

// MARK: - Validity

private func script(_ role: String, steps: Int, timedOut: Int? = nil, finished: Bool = true, dropped: UInt64 = 0) -> BenchLog {
    var records = [record(.mark, at: 0, sub: BenchMark.scenarioStart.rawValue)]
    for index in 0..<steps {
        let mark: BenchMark = index == timedOut ? .stepTimedOut : .stepReached
        records.append(record(.mark, at: UInt64(index + 1) * second, sub: mark.rawValue, id: UInt32(index)))
    }
    if finished { records.append(record(.mark, at: 20 * second, sub: BenchMark.scenarioEnd.rawValue)) }
    records.append(record(.recorder, at: 21 * second, v1: dropped))
    return BenchLog(header: header(role), records: records)
}

@Test func aRunIsValidOnlyIfBothScriptsFinishedCleanly() {
    let scenario = BenchScenarios.joinAndSpawn
    let hostSteps = scenario.host.count
    let guestSteps = scenario.guest.count
    let facts = RunAnalysis.RunFacts(scenario: scenario, tier: "pair")

    #expect(RunAnalysis.invalidReasons(host: script("host", steps: hostSteps), guest: script("join", steps: guestSteps), facts: facts).isEmpty)

    #expect(
        RunAnalysis.invalidReasons(
            host: script("host", steps: hostSteps), guest: script("join", steps: guestSteps, timedOut: 0), facts: facts
        ) == ["guest step 0 timed out"]
    )
    #expect(
        RunAnalysis.invalidReasons(
            host: script("host", steps: hostSteps, finished: false), guest: script("join", steps: guestSteps), facts: facts
        ) == ["host never finished its script"]
    )
    #expect(
        RunAnalysis.invalidReasons(
            host: script("host", steps: hostSteps, dropped: 12), guest: script("join", steps: guestSteps), facts: facts
        ) == ["host recorder dropped 12 records"]
    )
    let killed = RunAnalysis.RunFacts(scenario: scenario, tier: "pair", killed: true, hostExit: 15, guestExit: 0)
    #expect(
        RunAnalysis.invalidReasons(host: script("host", steps: hostSteps), guest: script("join", steps: guestSteps), facts: killed)
            == ["killed by the watchdog", "host exited with 15"]
    )
}

@Test func theScenarioHashChangesWithTheScenario() {
    var changed = BenchScenarios.joinAndSpawn
    #expect(RunAnalysis.scenarioHash(changed) == RunAnalysis.scenarioHash(BenchScenarios.joinAndSpawn))
    changed.settleMs += 1
    #expect(RunAnalysis.scenarioHash(changed) != RunAnalysis.scenarioHash(BenchScenarios.joinAndSpawn))
    #expect(Set(BenchScenarios.all.map(RunAnalysis.scenarioHash)).count == BenchScenarios.all.count)
    #expect(Set(BenchScenarios.all.map(\.name)).count == BenchScenarios.all.count)
}

// MARK: - Scorecards

private func run(_ metrics: [String: Double], valid: Bool = true, hash: String = "abc", model: String = "MacBookPro17,1") -> RunSummary {
    RunSummary(
        schema: BoloBench.schemaVersion, runID: "r", scenario: "s", scenarioHash: hash, tier: "pair", model: model,
        osBuild: "26A428", valid: valid, invalidReasons: valid ? [] : ["killed by the watchdog"], metrics: metrics,
        episodes: []
    )
}

@Test func eachMetricIsJudgedByTheRuleItsNameCallsFor() {
    #expect(Repeatability.rule(for: "host.tick_ms.whole.p50") == .relative5)
    #expect(Repeatability.rule(for: "host.tick_ms.whole.p95") == .relative10)
    #expect(Repeatability.rule(for: "host.tick_ms.whole.p99") == .reportOnly)
    #expect(Repeatability.rule(for: "host.tick_ms.whole.max") == .reportOnly)
    #expect(Repeatability.rule(for: "host.tick_ms.whole.n") == .reportOnly)
    #expect(Repeatability.rule(for: "host.cpu_pct.mean") == .relative5)
    #expect(Repeatability.rule(for: "link.tcp.send_to_applied_ms.p50") == .within10ms)
    #expect(Repeatability.rule(for: "link.ack_age_ms.guest.p95") == .within10ms)
    #expect(Repeatability.rule(for: "guest.input_to_frame_ms.p50") == .within10ms)
    #expect(Repeatability.rule(for: "host.tx.tcp.messages") == .variation2)
    #expect(Repeatability.rule(for: "host.tx.tcp.op34.bytes") == .variation2)
    #expect(Repeatability.rule(for: "correctness.pills.terminal") == .verdict)
    #expect(Repeatability.rule(for: "correctness.candidate.staleOverwrite") == .verdict)
    #expect(Repeatability.rule(for: "link.udp.host_to_guest.lost") == .verdict)
    #expect(Repeatability.rule(for: "host.datagram_rejects.dropped") == .verdict)
    #expect(Repeatability.rule(for: "host.recorder.self_ms") == .reportOnly)
    #expect(Repeatability.rule(for: "correctness.window_s") == .reportOnly)
}

@Test func aTightMetricIsRepeatableAndAScatteredOneIsNot() throws {
    let tight: [Double] = [2.00, 2.02, 1.99, 2.01, 2.00, 1.98, 2.03, 2.00, 2.01, 1.99]
    let scattered: [Double] = [2.0, 3.5, 1.2, 4.1, 2.8, 1.5, 3.9, 2.2, 4.4, 1.1]
    let runs = zip(tight, scattered).map { run(["host.tick_ms.whole.p50": $0, "host.tick_ms.fog.p50": $1]) }
    let card = try Repeatability.scorecard(runs)
    #expect(card.validRuns == 10)
    #expect(card.metrics["host.tick_ms.whole.p50"]?.repeatable == true)
    #expect(card.metrics["host.tick_ms.fog.p50"]?.repeatable == false)
    #expect(card.unrepeatable == ["host.tick_ms.fog.p50"])
    #expect(card.metrics["host.tick_ms.whole.p50"]?.median == 2.0)
}

@Test func aSmallValueIsNotHeldToATighterBoundThanTheClockCanMeet() throws {
    // 3 microseconds give or take 1: a third of the value, and far below anything that matters.
    let runs = [2.0, 3.0, 4.0, 3.0, 2.0, 4.0, 3.0, 3.0, 2.0, 4.0].map { run(["host.apply_us.udp.p50": $0]) }
    #expect(try Repeatability.scorecard(runs).metrics["host.apply_us.udp.p50"]?.repeatable == true)
}

@Test func aDivergenceVerdictNeedsNineRunsInTenToAgree() throws {
    func card(_ values: [Double]) throws -> MetricStat? {
        try Repeatability.scorecard(values.map { run(["correctness.pills.terminal": $0]) }).metrics["correctness.pills.terminal"]
    }
    #expect(try card([0, 0, 0, 0, 0, 0, 0, 0, 0, 0])?.repeatable == true)
    #expect(try card([0, 0, 0, 0, 3, 0, 0, 0, 0, 0])?.repeatable == true)
    #expect(try card([0, 0, 1, 0, 3, 0, 0, 0, 0, 0])?.repeatable == false, "intermittent: report as a rate")
    // Always divergent is as repeatable as never, however the count varies.
    #expect(try card([302, 298, 305, 302, 300, 302, 301, 299, 302, 304])?.repeatable == true)
}

@Test func aCountAbsentFromARunIsZeroThere() throws {
    var runs = (0..<9).map { _ in run(["host.tick_ms.whole.p50": 2]) }
    runs.append(run(["host.tick_ms.whole.p50": 2, "host.datagram_rejects.dropped": 4]))
    let stat = try #require(try Repeatability.scorecard(runs).metrics["host.datagram_rejects.dropped"])
    #expect(stat.values.count == 10)
    #expect(stat.values.filter { $0 == 0 }.count == 9)
}

@Test func invalidRunsAreCountedAndLeftOut() throws {
    var runs = (0..<9).map { _ in run(["host.tick_ms.whole.p50": 2]) }
    runs.append(run(["host.tick_ms.whole.p50": 900], valid: false))
    let card = try Repeatability.scorecard(runs)
    #expect(card.validRuns == 9)
    #expect(card.invalidRuns == 1)
    #expect(card.invalidReasons == ["killed by the watchdog"])
    #expect(card.metrics["host.tick_ms.whole.p50"]?.values.max() == 2)
    #expect(throws: ScorecardError.noValidRuns) { try Repeatability.scorecard([run([:], valid: false)]) }
}

@Test func runsOfDifferentScenariosOrMachinesAreNeverPooled() {
    #expect(throws: ScorecardError.mixedRuns("scenario")) {
        try Repeatability.scorecard([run(["a.p50": 1]), run(["a.p50": 1], hash: "different")])
    }
    #expect(throws: ScorecardError.mixedRuns("hardware model")) {
        try Repeatability.scorecard([run(["a.p50": 1]), run(["a.p50": 1], model: "Mac15,6")])
    }
}

// MARK: - Comparison

private let steady: [Double] = [2.00, 2.02, 1.99, 2.01, 2.00, 1.98, 2.03, 2.00, 2.01, 1.99]

@Test func aScorecardComparedWithItselfHasChangedNowhere() throws {
    let card = try Repeatability.scorecard(steady.map { run(["host.tick_ms.whole.p50": $0, "host.tick_ms.whole.max": $0 * 9]) })
    let results = try Comparison.compare(baseline: card, candidate: card)
    #expect(results.allSatisfy { $0.verdict != .changed })
    #expect(results.first { $0.name == "host.tick_ms.whole.p50" }?.verdict == .unchanged)
    #expect(results.first { $0.name == "host.tick_ms.whole.max" }?.reason == "report only")
}

@Test func aRealShiftIsReportedAsChangedAndASmallWobbleIsNot() throws {
    let baseline = try Repeatability.scorecard(steady.map { run(["host.tick_ms.whole.p50": $0]) })
    let faster = try Repeatability.scorecard(steady.map { run(["host.tick_ms.whole.p50": $0 * 0.6]) })
    let wobble = try Repeatability.scorecard(steady.reversed().map { run(["host.tick_ms.whole.p50": $0 + 0.005]) })

    let shifted = try #require(try Comparison.compare(baseline: baseline, candidate: faster).first)
    #expect(shifted.verdict == .changed)
    #expect(abs((shifted.changePct ?? 0) + 40) < 0.5)
    #expect((shifted.p ?? 1) < 0.001)

    #expect(try Comparison.compare(baseline: baseline, candidate: wobble).first?.verdict == .unchanged)
}

@Test func aMetricThatWasNotRepeatableInTheBaselineIsNeverCompared() throws {
    let scattered: [Double] = [2.0, 3.5, 1.2, 4.1, 2.8, 1.5, 3.9, 2.2, 4.4, 1.1]
    let baseline = try Repeatability.scorecard(scattered.map { run(["host.tick_ms.fog.p50": $0]) })
    let candidate = try Repeatability.scorecard(steady.map { run(["host.tick_ms.fog.p50": $0 * 10]) })
    let result = try #require(try Comparison.compare(baseline: baseline, candidate: candidate).first)
    #expect(result.verdict == .notCompared)
    #expect(result.reason == "not repeatable in the baseline")
}

@Test func scorecardsFromDifferentScenariosOrMachinesAreRefused() throws {
    let baseline = try Repeatability.scorecard(steady.map { run(["a.p50": $0]) })
    let otherScenario = try Repeatability.scorecard(steady.map { run(["a.p50": $0], hash: "different") })
    let otherMachine = try Repeatability.scorecard(steady.map { run(["a.p50": $0], model: "Mac15,6") })
    #expect(throws: ComparisonError.notComparable("scenario differs")) {
        try Comparison.compare(baseline: baseline, candidate: otherScenario)
    }
    #expect(throws: ComparisonError.notComparable("hardware model differs")) {
        try Comparison.compare(baseline: baseline, candidate: otherMachine)
    }
}
