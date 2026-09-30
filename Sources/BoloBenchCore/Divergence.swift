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

public enum EpisodeLength: String, Sendable, Codable, CaseIterable {
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
public enum CandidateClass: String, Sendable, Codable, CaseIterable {
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

/// The comparable parts of one logged state value. A `nil` value means "not comparable here"
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
