import BoloKit

// MARK: - Request

/// One flat, all-optional-fields request shape shared by every command -- simpler than a
/// Codable discriminated union for a tool this size. `cmd` selects which of the other fields
/// matter; unused fields are just absent from the JSON body.
struct ArenaRequest: Decodable {
    var cmd: String
    var flags: [String]?
    var kind: String?
    var x: Int32?
    var y: Int32?
    var text: String?
}

// MARK: - Responses

struct NearbyObject: Encodable {
    var kind: String // "enemyTank", "pill", "base", "shell"
    var dx: Int32
    var dy: Int32
    var owner: String? // "you", "enemy", "neutral" -- omitted for shells
}

struct ObserveResponse: Encodable {
    var phase: String
    var gameId: Int
    var tick: UInt64
    var alive: Bool
    var x: Float
    var y: Float
    var headingDegrees: Float
    var speed: Float
    var armour: Int
    var shells: Int
    var mines: Int
    var trees: Int
    var boat: Bool
    var terrain: [String] // TerrainWindow.render rows, center = your tank
    var nearby: [NearbyObject]
    var events: [String]
}

struct AckResponse: Encodable {
    var ok: Bool
    var message: String?
}

struct NewGameResponse: Encodable {
    var ok: Bool
    var gameId: Int
    var message: String?
}

struct ErrorResponse: Encodable {
    var ok = false
    var error: String
}

// MARK: - Flags decode/encode

enum FlagCoding {
    static func decode(_ names: [String]) -> InputFlags {
        var flags: InputFlags = []
        for name in names {
            switch name {
            case "accel": flags.insert(.accel)
            case "brake": flags.insert(.brake)
            case "turnL": flags.insert(.turnL)
            case "turnR": flags.insert(.turnR)
            case "shoot": flags.insert(.shoot)
            case "lmine": flags.insert(.lmine)
            case "incre": flags.insert(.incre)
            case "decre": flags.insert(.decre)
            default: break
            }
        }
        return flags
    }
}

enum BuilderKindCoding {
    static func decode(_ name: String) -> BuilderCommandKind? {
        switch name {
        case "tree": return .tree
        case "road": return .road
        case "wall": return .wall
        case "pill": return .pill
        case "mine": return .mine
        default: return nil
        }
    }
}
