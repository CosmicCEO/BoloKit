import BoloKit

/// Renders a small NxN character window centered on a tile, from whichever `GameState` copy the
/// caller passes in (host-truth for the host seat, the guest's own local copy for the guest seat
/// -- callers must never cross these, or Hidden Mines' fog-of-war leaks through the tool).
enum TerrainWindow {
    static let radius = 7 // 15x15 window

    /// One character per terrain family. Deliberately coarse (an LLM doesn't need growth-stage
    /// detail) but distinguishes anything build/traversal-relevant.
    private static func glyph(for terrain: Terrain?) -> Character {
        guard let terrain else { return "?" } // off the map edge
        switch terrain {
        case .sea, .minedSea: return "~"
        case .river: return "r"
        case .boat: return "b"
        case .wall: return "#"
        case .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3: return "%"
        case .swamp0, .swamp1, .swamp2, .swamp3, .minedSwamp: return "s"
        case .crater, .minedCrater: return "o"
        case .road, .minedRoad: return "="
        case .forest, .minedForest: return "T"
        case .rubble0, .rubble1, .rubble2, .rubble3, .minedRubble: return ","
        case .grass0, .grass1, .grass2, .grass3, .minedGrass: return "."
        }
    }

    /// Rows top-to-bottom (north to south), each a string of `2*radius+1` characters. The tank's
    /// own tile is always the center character, rendered as `@`.
    static func render(around center: Pointi, terrain: TerrainGrid) -> [String] {
        var rows: [String] = []
        for dy in -radius...radius {
            var row = ""
            for dx in -radius...radius {
                if dx == 0, dy == 0 {
                    row.append("@")
                    continue
                }
                let x = Int(center.x) + dx
                let y = Int(center.y) + dy
                guard x >= 0, x < 256, y >= 0, y < 256 else {
                    row.append("?")
                    continue
                }
                row.append(glyph(for: terrain[x, y]))
            }
            rows.append(row)
        }
        return rows
    }
}
