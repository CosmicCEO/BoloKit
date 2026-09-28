import BoloKit
import Foundation

// MARK: - Benchmark scenarios (v1.6.9 baseline benchmark)
//
// Measurement only. A scenario is two scripts, one per side, read from a JSON file. Steps act
// through the same input hooks the keyboard uses and wait on game state rather than on the
// clock, because spawn direction, tree growth and scheduling all vary from run to run. The
// decisions here are pure functions of `GameState`, so the same script makes the same choices
// on every run that reaches the same state.

/// The seeded generator the soak test has always used (`HostSimulatedSoakTests`), shared so a
/// scenario's random phase and the soak draw from one definition.
public struct BenchRNG: RandomNumberGenerator, Sendable {
    public var state: UInt64

    public init(state: UInt64) { self.state = state }

    public mutating func next() -> UInt64 {
        state &+= 0x9E37_79B9_7F4A_7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58_476D_1CE4_E5B9
        z = (z ^ (z >> 27)) &* 0x94D0_49BB_1331_11EB
        return z ^ (z >> 31)
    }
}

public let benchAllInputFlags: InputFlags = [.accel, .brake, .turnL, .turnR, .lmine, .shoot, .incre, .decre]

public func benchRandomInputs(_ rng: inout BenchRNG) -> InputFlags {
    var flags: InputFlags = []
    if Double.random(in: 0..<1, using: &rng) < 0.70 { flags.insert(.accel) }
    if Double.random(in: 0..<1, using: &rng) < 0.10 { flags.insert(.brake) }
    let turn = Double.random(in: 0..<1, using: &rng)
    if turn < 0.20 { flags.insert(.turnL) } else if turn < 0.40 { flags.insert(.turnR) }
    if Double.random(in: 0..<1, using: &rng) < 0.30 { flags.insert(.shoot) }
    if Double.random(in: 0..<1, using: &rng) < 0.20 { flags.insert(.lmine) }
    if Double.random(in: 0..<1, using: &rng) < 0.10 { flags.insert(.incre) }
    if Double.random(in: 0..<1, using: &rng) < 0.10 { flags.insert(.decre) }
    return flags
}

// MARK: - Model

public enum BenchKey: String, Codable, Sendable, CaseIterable {
    case accel, brake, turnL, turnR, lmine, shoot, incre, decre

    public var flag: InputFlags {
        switch self {
        case .accel: return .accel
        case .brake: return .brake
        case .turnL: return .turnL
        case .turnR: return .turnR
        case .lmine: return .lmine
        case .shoot: return .shoot
        case .incre: return .incre
        case .decre: return .decre
        }
    }
}

public enum BenchTool: String, Codable, Sendable {
    case tree, road, wall, pill, mine

    public var command: BuilderCommandKind {
        switch self {
        case .tree: return .tree
        case .road: return .road
        case .wall: return .wall
        case .pill: return .pill
        case .mine: return .mine
        }
    }
}

/// Something about the game that is either true or not yet. `me` is the side running the
/// script; `peer` is the first other connected player.
public enum BenchCondition: Codable, Sendable, Equatable {
    case alive
    case dead
    case peerAlive
    case peerDead
    /// Within `radius` tiles of the centre of tile (`x`, `y`).
    case at(x: Int, y: Int, radius: Double)
    case peerAt(x: Int, y: Int, radius: Double)
    case carryingAtLeast(pills: Int)
    case pillOwnedByMe(pill: Int)
    case pillArmourAtMost(pill: Int, armour: Int)
    case terrain(x: Int, y: Int, anyOf: [Int32])
    case minesAtMost(Int)
    case treesAtMost(Int)
    case builderReady
}

public enum BenchStep: Codable, Sendable, Equatable {
    case wait(ms: Int)
    case until(BenchCondition, timeoutMs: Int)
    case keys(set: [BenchKey], clear: [BenchKey])
    /// Steers to within `radius` tiles of the centre of tile (`x`, `y`), then brakes.
    case driveTo(x: Int, y: Int, radius: Double, timeoutMs: Int)
    /// Turns on the spot to face tile (`x`, `y`).
    case face(x: Int, y: Int, timeoutMs: Int)
    case layMine
    case builder(tool: BenchTool, x: Int, y: Int)
    /// A named point in the log for the analyzer to measure from.
    case mark(String)
    case random(seed: UInt64, seconds: Int)
}

public struct BenchScenario: Codable, Sendable, Equatable {
    public var name: String
    public var hiddenMines: Bool
    /// How long both sides keep recording after their last step, so late divergence is seen.
    public var settleMs: Int
    public var host: [BenchStep]
    public var guest: [BenchStep]

    public init(name: String, hiddenMines: Bool, settleMs: Int = 3_000, host: [BenchStep], guest: [BenchStep]) {
        self.name = name
        self.hiddenMines = hiddenMines
        self.settleMs = settleMs
        self.host = host
        self.guest = guest
    }

    public static func load(_ url: URL) throws -> BenchScenario {
        try JSONDecoder().decode(BenchScenario.self, from: Data(contentsOf: url))
    }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
}

// MARK: - Decisions

private func tileCentre(_ x: Int, _ y: Int) -> Vec2f {
    Vec2f(x: Float(x) + 0.5, y: Float(y) + 0.5)
}

private func distance(_ a: Vec2f, _ b: Vec2f) -> Double {
    let dx = Double(a.x - b.x)
    let dy = Double(a.y - b.y)
    return (dx * dx + dy * dy).squareRoot()
}

/// The first connected player that is not `player`.
public func benchPeer(of player: Int, state: GameState) -> Int? {
    state.players.indices.first { $0 != player && state.players[$0].connected }
}

public func benchConditionHolds(_ condition: BenchCondition, player: Int, state: GameState) -> Bool {
    guard state.players.indices.contains(player) else { return false }
    let me = state.players[player]
    let peer = benchPeer(of: player, state: state).map { state.players[$0] }
    switch condition {
    case .alive:
        return !me.dead
    case .dead:
        return me.dead
    case .peerAlive:
        return peer.map { !$0.dead } ?? false
    case .peerDead:
        return peer.map(\.dead) ?? false
    case .at(let x, let y, let radius):
        return !me.dead && distance(me.tank, tileCentre(x, y)) <= radius
    case .peerAt(let x, let y, let radius):
        return peer.map { !$0.dead && distance($0.tank, tileCentre(x, y)) <= radius } ?? false
    case .carryingAtLeast(let pills):
        return digestOnboardPillMask(player: player, pills: state.pills).nonzeroBitCount >= pills
    case .pillOwnedByMe(let pill):
        return state.pills.indices.contains(pill) && Int(state.pills[pill].owner) == player
    case .pillArmourAtMost(let pill, let armour):
        return state.pills.indices.contains(pill) && state.pills[pill].armour != pillOnboard
            && Int(state.pills[pill].armour) <= armour
    case .terrain(let x, let y, let anyOf):
        guard (0..<256).contains(x), (0..<256).contains(y) else { return false }
        return anyOf.contains(state.terrain.storage[y * 256 + x])
    case .minesAtMost(let mines):
        return me.mines <= mines
    case .treesAtMost(let trees):
        return me.trees <= trees
    case .builderReady:
        return me.builderStatus == .ready
    }
}

/// The signed turn, in radians within (-pi, pi], that takes heading `dir` to face `target`.
/// Positive is the way `turnL` turns.
public func benchHeadingError(from tank: Vec2f, dir: Float, to target: Vec2f) -> Float {
    let wanted = vec2dir(Vec2f(x: target.x - tank.x, y: target.y - tank.y))
    var error = (wanted - dir).truncatingRemainder(dividingBy: 2 * kPif)
    if error > kPif { error -= 2 * kPif }
    if error <= -kPif { error += 2 * kPif }
    return error
}

/// Within this many radians of the wanted heading the tank stops turning (a sixteenth of a turn
/// is the finest direction it holds).
public let benchFacingTolerance: Float = kPif / 16
/// Wider than this off the wanted heading the tank turns on the spot before driving.
public let benchDriveTolerance: Float = kPif / 4

/// The keys to hold this instant to reach tile (`x`, `y`). Empty flags with `arrived` true once
/// within `radius`.
public func benchSteer(
    tank: Vec2f, dir: Float, x: Int, y: Int, radius: Double
) -> (flags: InputFlags, arrived: Bool) {
    let target = tileCentre(x, y)
    if distance(tank, target) <= radius { return ([.brake], true) }
    let error = benchHeadingError(from: tank, dir: dir, to: target)
    var flags: InputFlags = []
    if error > benchFacingTolerance { flags.insert(.turnL) } else if error < -benchFacingTolerance { flags.insert(.turnR) }
    if abs(error) <= benchDriveTolerance { flags.insert(.accel) } else { flags.insert(.brake) }
    return (flags, false)
}

/// The keys to hold this instant to turn on the spot toward tile (`x`, `y`).
public func benchFace(tank: Vec2f, dir: Float, x: Int, y: Int) -> (flags: InputFlags, facing: Bool) {
    let error = benchHeadingError(from: tank, dir: dir, to: tileCentre(x, y))
    if abs(error) <= benchFacingTolerance { return ([.brake], true) }
    return (error > 0 ? [.turnL, .brake] : [.turnR, .brake], false)
}

/// The key transition that takes the keys held from `held` to `wanted`, limited to `managed`
/// keys so a script's own held keys (say `shoot`) are left alone. `nil` when nothing changes.
public func benchKeyChange(from held: InputFlags, to wanted: InputFlags, managed: InputFlags) -> KeyInputChange? {
    let set = wanted.intersection(managed).subtracting(held)
    let clear = held.intersection(managed).subtracting(wanted)
    if set.isEmpty && clear.isEmpty { return nil }
    return KeyInputChange(set: set, clear: clear)
}
