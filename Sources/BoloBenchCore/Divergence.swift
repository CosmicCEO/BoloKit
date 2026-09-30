import BoloKit
import BoloNet
import Foundation

// MARK: - Host/guest divergence (v1.6.9 baseline benchmark)
//
// The host logs what it expects one guest to hold; that guest logs what it holds. Both are on
// one clock, so the two logs merge into one timeline per element, and an element is divergent
// for as long as both sides have a comparable value and the values differ.
//
// Most divergence is the message still being on its way. What matters is how long it lasts.

/// What is compared. Finer than `DigestDomain`: parts of a logged value that are owned by
/// different sides, or differ by design, are separated so they cannot hide or fake a fault.
public enum CompareDomain: String, CaseIterable, Sendable, Codable {
    case pills
    case bases
    /// Dead, boat and carried pills. Host-authoritative.
    case selfStatus
    /// Armour, shells and mines. Host-authoritative.
    case resources
    /// Terrain by class (grass, swamp, rubble and damaged wall each count as one).
    case terrain
    case fogVisible
    case fogSeen
    /// Each other player's connected, dead and boat flags.
    case peers

    // Informational: these differ by design, so they are reported but never counted as faults.

    /// The guest's tank tile and direction. Guest-authoritative; the host follows at 10 Hz.
    case position
    /// Other players' tank tiles as each side sees them.
    case peerPosition
    /// Guest-owned since v1.6.9 (#171).
    case trees
    /// Exact terrain value. The map format does not carry growth and damage variants, so a
    /// joining guest starts with different variants from the host's.
    case terrainVariant

    public var isInformational: Bool {
        switch self {
        case .position, .peerPosition, .trees, .terrainVariant: return true
        default: return false
        }
    }
}

public enum EpisodeLength: String, CaseIterable, Sendable, Codable {
    /// Up to 250 ms: the send cadence, a tick and the delivery.
    case inFlight
    /// Over 250 ms and up to 2 s.
    case slow
    /// Over 2 s, but it did converge.
    case persistent
    /// Still divergent when the run ended.
    case terminal
}

/// A guess at the kind of fault, from the six classes in the `debugging-host-client-desync`
/// skill. A lead for a person to follow, not a finding.
public enum CandidateClass: String, CaseIterable, Sendable, Codable {
    case unreportedChange
    case doubleApplication
    case doubleDecision
    case maskedMessage
    case oneShotWiring
    case staleOverwrite
    case unclassified
}

public struct Episode: Sendable, Equatable, Codable {
    public var domain: CompareDomain
    public var element: UInt32
    public var start: UInt64
    /// `nil` while still divergent at the end of the run.
    public var end: UInt64?
    public var hostValue: UInt64
    public var guestValue: UInt64
    public var length: EpisodeLength
    public var candidate: CandidateClass?

    public func duration(until runEnd: UInt64) -> UInt64 { (end ?? runEnd) &- start }
}

public struct DivergenceThresholds: Sendable, Equatable {
    public var inFlight: UInt64 = 250_000_000
    public var persistent: UInt64 = 2_000_000_000

    public init() {}

    func length(of duration: UInt64, closed: Bool) -> EpisodeLength {
        if duration <= inFlight { return .inFlight }
        if !closed { return .terminal }
        return duration <= persistent ? .slow : .persistent
    }
}

// MARK: - Splitting logged values

func terrainClass(_ raw: UInt64) -> UInt64 {
    guard let terrain = Terrain(rawValue: Int32(truncatingIfNeeded: raw)) else { return raw }
    switch terrain {
    case .swamp0, .swamp1, .swamp2, .swamp3: return UInt64(Terrain.swamp0.rawValue)
    case .rubble0, .rubble1, .rubble2, .rubble3: return UInt64(Terrain.rubble0.rawValue)
    case .grass0, .grass1, .grass2, .grass3: return UInt64(Terrain.grass0.rawValue)
    case .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3: return UInt64(Terrain.damagedWall0.rawValue)
    default: return raw
    }
}

/// The comparable parts of one logged state value. A `nil` value means \"not comparable here\"
/// (a tile outside vision), which ends any divergence on that element without starting one.
func comparableParts(domain: DigestDomain, element: UInt32, value: UInt64) -> [(CompareDomain, UInt32, UInt64?)] {
    switch domain {
    case .pills:
        return [(.pills, element, value)]
    case .bases:
        return [(.bases, element, value)]
    case .selfStatus:
        // Bits 0-1 dead and boat, 8-27 tile and direction, 32-47 carried pills.
        return [
            (.selfStatus, element, value & 0x0000_ffff_0000_0003),
            (.position, element, (value >> 8) & 0xf_ffff),
        ]
    case .resources:
        return [(element == UInt32(DigestResource.trees.rawValue) ? .trees : .resources, element, value)]
    case .terrain:
        if value == digestUnknownTerrain { return [(.terrain, element, nil), (.terrainVariant, element, nil)] }
        return [(.terrain, element, terrainClass(value)), (.terrainVariant, element, value)]
    case .fog:
        return fogComparableParts(element: element, value: value)
    case .peers:
        // Bits 0-2 connected, dead and boat; 8-23 tile; 24-31 input flags (not compared).
        return [(.peers, element, value & 7), (.peerPosition, element, (value >> 8) & 0xffff)]
    }
}

// MARK: - Finding episodes

public struct DivergenceResult: Sendable {
    public var episodes: [Episode]
    public var windowStart: UInt64
    public var windowEnd: UInt64
    public var guest: Int

    public var window: UInt64 { windowEnd &- windowStart }

    public func episodes(in domain: CompareDomain) -> [Episode] {
        episodes.filter { $0.domain == domain }
    }
}

private struct Key: Hashable {
    var domain: CompareDomain
    var element: UInt32
}

private struct Cell {
    var host: UInt64??
    var guest: UInt64??
    var previousHost: UInt64?
    var previousGuest: UInt64?
    var hostChanged: UInt64 = 0
    var guestChanged: UInt64 = 0
    /// When the host last went from not-comparable to a value here (a tile entering vision).
    var hostBecameKnown: UInt64 = 0
    var open: Int?
}

public func findDivergence(
    host: BenchLog, guest: BenchLog, thresholds: DivergenceThresholds = DivergenceThresholds()
) -> DivergenceResult? {
    let guestStates = guest.of(.state)
    guard let slot = guestStates.first.map({ Int($0.v1) }) else { return nil }
    let hostStates = host.of(.state).filter { Int($0.v1) == slot }
    guard let hostFirst = hostStates.first?.time, let guestFirst = guestStates.first?.time else { return nil }

    let windowStart = max(hostFirst, guestFirst)
    let windowEnd = min(host.lastTime, guest.lastTime)
    guard windowEnd > windowStart else { return nil }

    // Host TCP sends to this guest, for telling \"never sent\" from \"sent and not applied\".
    let hostSends = host.of(.send)
        .filter { $0.sub == BenchChannel.tcp.rawValue && Int($0.v1) == slot }
        .map(\\.time)

    // Merge, host first on a shared timestamp.
    var merged: [(record: BenchRecord, isHost: Bool)] = []
    merged.reserveCapacity(hostStates.count + guestStates.count)
    var h = 0
    var g = 0
    while h < hostStates.count || g < guestStates.count {
        if g >= guestStates.count || (h < hostStates.count && hostStates[h].time <= guestStates[g].time) {
            merged.append((hostStates[h], true))
            h += 1
        } else {
            merged.append((guestStates[g], false))
            g += 1
        }
    }

    var cells: [Key: Cell] = [:]
    var episodes: [Episode] = []

    func close(_ cell: inout Cell, at time: UInt64) {
        guard let index = cell.open else { return }
        cell.open = nil
        episodes[index].end = time
        episodes[index].length = thresholds.length(of: time &- episodes[index].start, closed: true)
    }

    for (record, isHost) in merged where record.time <= windowEnd {
        guard let domain = DigestDomain(rawValue: record.sub) else { continue }
        for (compare, element, value) in comparableParts(domain: domain, element: record.id, value: record.v0) {
            let key = Key(domain: compare, element: element)
            var cell = cells[key] ?? Cell()
            if isHost {
                if case .some(.some(let old)) = cell.host {
                    cell.previousHost = old
                } else if value != nil {
                    // Unset or not comparable until now.
                    cell.hostBecameKnown = record.time
                }
                cell.host = .some(value)
                cell.hostChanged = record.time
            } else {
                if case .some(.some(let old)) = cell.guest { cell.previousGuest = old }
                cell.guest = .some(value)
                cell.guestChanged = record.time
            }

            var divergent = false
            if case .some(.some(let hostValue)) = cell.host, case .some(.some(let guestValue)) = cell.guest {
                divergent = hostValue != guestValue
                if divergent, let index = cell.open {
                    episodes[index].hostValue = hostValue
                    episodes[index].guestValue = guestValue
                    episodes[index].candidate = candidate(
                        for: episodes[index], cell: cell, startedByHost: isHost, windowStart: windowStart,
                        hostSends: hostSends, thresholds: thresholds
                    )
                } else if divergent {
                    let start = max(record.time, windowStart)
                    cell.open = episodes.count
                    var episode = Episode(
                        domain: compare, element: element, start: start, end: nil, hostValue: hostValue,
                        guestValue: guestValue, length: .terminal, candidate: nil
                    )
                    episode.candidate = candidate(
                        for: episode, cell: cell, startedByHost: isHost, windowStart: windowStart,
                        hostSends: hostSends, thresholds: thresholds
                    )
                    episodes.append(episode)
                }
            }
            if !divergent { close(&cell, at: record.time) }
            cells[key] = cell
        }
    }

    for index in episodes.indices where episodes[index].end == nil {
        episodes[index].length = thresholds.length(of: windowEnd &- episodes[index].start, closed: false)
    }
    for index in episodes.indices where episodes[index].length == .inFlight || episodes[index].domain.isInformational {
        episodes[index].candidate = nil
    }
    for index in episodes.indices where episodes[index].candidate == .unreportedChange {
        let end = episodes[index].end ?? windowEnd
        if sent(hostSends, from: episodes[index].start &- min(episodes[index].start, 20_000_000), to: end) {
            episodes[index].candidate = .unclassified
        }
    }
    return DivergenceResult(episodes: episodes, windowStart: windowStart, windowEnd: windowEnd, guest: slot)
}

private func sent(_ times: [UInt64], from: UInt64, to: UInt64) -> Bool {
    var low = 0
    var high = times.count
    while low < high {
        let middle = (low + high) / 2
        if times[middle] < from { low = middle + 1 } else { high = middle }
    }
    return low < times.count && times[low] <= to
}

private func quantity(_ value: UInt64, in domain: CompareDomain) -> Int64 {
    domain == .pills ? Int64((value >> 16) & 0xff) : Int64(bitPattern: value)
}

private func candidate(
    for episode: Episode, cell: Cell, startedByHost: Bool, windowStart: UInt64, hostSends: [UInt64],
    thresholds: DivergenceThresholds
) -> CandidateClass {
    if episode.start <= windowStart &+ 100_000_000 { return .oneShotWiring }

    if !startedByHost, let previousGuest = cell.previousGuest, let previousHost = cell.previousHost {
        if previousGuest == episode.hostValue, episode.guestValue == previousHost { return .staleOverwrite }
    }

    if [.resources, .pills].contains(episode.domain), let previousGuest = cell.previousGuest,
        let previousHost = cell.previousHost
    {
        let hostStep = quantity(episode.hostValue, in: episode.domain) - quantity(previousHost, in: episode.domain)
        let guestStep = quantity(episode.guestValue, in: episode.domain) - quantity(previousGuest, in: episode.domain)
        if hostStep != 0, guestStep == 2 * hostStep { return .doubleApplication }
    }

    if [.terrain, .fogSeen].contains(episode.domain), cell.hostBecameKnown != 0,
        episode.start &- cell.hostBecameKnown <= 1_000_000_000
    {
        return .maskedMessage
    }

    let gap = cell.hostChanged > cell.guestChanged
        ? cell.hostChanged &- cell.guestChanged : cell.guestChanged &- cell.hostChanged
    if cell.previousHost != nil, cell.previousGuest != nil, gap <= 40_000_000 { return .doubleDecision }

    if startedByHost { return .unreportedChange }
    return .unclassified
}

extension DivergenceResult {
    public func divergentTime(in domain: CompareDomain, thresholds: DivergenceThresholds) -> UInt64 {
        let spans = episodes(in: domain)
            .map { ($0.start &+ thresholds.inFlight, $0.end ?? windowEnd) }
            .filter { $0.0 < $0.1 }
            .sorted { $0.0 < $1.0 }
        var total: UInt64 = 0
        var current: (UInt64, UInt64)?
        for span in spans {
            if let open = current, span.0 <= open.1 {
                current = (open.0, max(open.1, span.1))
            } else {
                if let open = current { total &+= open.1 &- open.0 }
                current = span
            }
        }
        if let open = current { total &+= open.1 &- open.0 }
        return total
    }

    public func metrics(thresholds: DivergenceThresholds = DivergenceThresholds()) -> MetricSet {
        var metrics = MetricSet()
        metrics.set(\"correctness.window_s\", Double(window) / 1_000_000_000)
        var faults = [EpisodeLength: Int]()
        for domain in CompareDomain.allCases {
            let all = episodes(in: domain)
            let prefix = \"correctness.\\(domain.rawValue)\"
            for length in EpisodeLength.allCases {
                let count = all.filter { $0.length == length }.count
                metrics.count(\"\\(prefix).\\(length.rawValue)\", count)
                if !domain.isInformational { faults[length, default: 0] += count }
            }
            metrics.distribution(
                \"\\(prefix).convergence_ms\", all.filter { $0.end != nil }.map { $0.duration(until: windowEnd).ms }
            )
            metrics.set(
                \"\\(prefix).divergent_time_pct\",
                100 * Double(divergentTime(in: domain, thresholds: thresholds)) / Double(max(window, 1))
            )
        }
        for length in EpisodeLength.allCases {
            metrics.count(\"correctness.all.\\(length.rawValue)\", faults[length, default: 0])
        }
        for candidate in CandidateClass.allCases {
            metrics.count(
                \"correctness.candidate.\\(candidate.rawValue)\", episodes.filter { $0.candidate == candidate }.count
            )
        }
        return metrics
    }
}
