// MARK: - BMAP Module Constants
//
// Ported from Reference/c/bmap.c and bolo.h.

/// The full 256×256 map area. Mirrors C `kWorldRect`.
public let worldRect = Recti(origin: Pointi(x: 0, y: 0), size: Sizei(width: 256, height: 256))

/// The mine-able interior area [10, 245] × [10, 245]. Mirrors C `kSeaRect` {10, 10, 236, 236}.
public let seaRect = Recti(origin: Pointi(x: 10, y: 10), size: Sizei(width: 236, height: 236))

/// Mine-zone bounds from bolo.h. Coordinates outside this closed range default to mined sea.
public let xMinMine: Int32 = 10
public let yMinMine: Int32 = 10
public let xMaxMine: Int32 = 245
public let yMaxMine: Int32 = 245

// MARK: - Default Terrain / Tile

/// The terrain a map cell holds before any run data is applied.
///
/// Ported from `defaultterrain()` in Reference/c/bmap.c: `.sea` inside the
/// mine zone [10, 245] × [10, 245], `.minedSea` in the outer border ring.
public func defaultTerrain(x: Int32, y: Int32) -> Terrain {
    (y >= yMinMine && y <= yMaxMine && x >= xMinMine && x <= xMaxMine) ? .sea : .minedSea
}

/// The tile a map cell displays before any run data is applied.
///
/// Ported from `defaulttile()` in Reference/c/bmap.c — same boundary logic
/// as `defaultTerrain(x:y:)`, returning the tile equivalents.
public func defaultTile(x: Int32, y: Int32) -> Tile {
    (y >= yMinMine && y <= yMaxMine && x >= xMinMine && x <= xMaxMine) ? .sea : .minedSea
}

// MARK: - Terrain → Tile Translation

/// Converts a terrain value to its canonical display tile.
///
/// Ported from `terraintotile()` in Reference/c/bmap.c. Terrain variants
/// collapse to a single tile: swamp0–3 → .swamp, rubble0–3 → .rubble,
/// grass0–3 → .grass, damagedWall0–3 → .damagedWall.
public func terrainToTile(_ terrain: Terrain) -> Tile {
    switch terrain {
    case .sea:
        return .sea
    case .wall:
        return .wall
    case .river:
        return .river
    case .swamp0, .swamp1, .swamp2, .swamp3:
        return .swamp
    case .crater:
        return .crater
    case .road:
        return .road
    case .forest:
        return .forest
    case .rubble0, .rubble1, .rubble2, .rubble3:
        return .rubble
    case .grass0, .grass1, .grass2, .grass3:
        return .grass
    case .damagedWall0, .damagedWall1, .damagedWall2, .damagedWall3:
        return .damagedWall
    case .boat:
        return .boat
    case .minedSea:
        return .minedSea
    case .minedSwamp:
        return .minedSwamp
    case .minedCrater:
        return .minedCrater
    case .minedRoad:
        return .minedRoad
    case .minedForest:
        return .minedForest
    case .minedRubble:
        return .minedRubble
    case .minedGrass:
        return .minedGrass
    }
}

/// Raw-value overload for differential testing against the C oracle.
///
/// Returns -1 for values outside the Terrain range, matching the C
/// `default: return -1` path (the C `assert(0)` is a debug-only trap,
/// not a behavioral contract — same divergence accepted for mapimage).
public func terrainToTile(_ terrain: Int32) -> Int32 {
    guard let t = Terrain(rawValue: terrain) else {
        return -1
    }
    return terrainToTile(t).rawValue
}

// MARK: - BMAP File Format Structs
//
// Pure data carriers mirroring the packed structs in Reference/c/bmap.h.
// Field order matches the on-disk .bolo map format byte-for-byte; the
// serialization codec (readrun/writerun) is deferred to a later wave.

/// Mirrors `struct BMAP_Preamble` (bmap.h): the .bolo file header.
public struct BMapPreamble: Hashable, Sendable {
    /// File identifier, 8 bytes: "BMAPBOLO"
    public var ident: [UInt8]
    /// Format version, currently 0
    public var version: UInt8
    /// Number of pillboxes (maximum 16)
    public var npills: UInt8
    /// Number of bases (maximum 16)
    public var nbases: UInt8
    /// Number of player starts (maximum 16)
    public var nstarts: UInt8

    public init(ident: [UInt8], version: UInt8, npills: UInt8, nbases: UInt8, nstarts: UInt8) {
        self.ident = ident
        self.version = version
        self.npills = npills
        self.nbases = nbases
        self.nstarts = nstarts
    }
}

/// Mirrors `struct BMAP_PillInfo` (bmap.h).
public struct BMapPillInfo: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// Should be 0xFF except in speciality maps
    public var owner: UInt8
    /// Range 0–15 (dead pillbox = 0, full strength = 15)
    public var armour: UInt8
    /// Typically 50. Time between shots, in 20ms units; lower values start the pillbox 'angry'
    public var speed: UInt8

    public init(x: UInt8, y: UInt8, owner: UInt8, armour: UInt8, speed: UInt8) {
        self.x = x
        self.y = y
        self.owner = owner
        self.armour = armour
        self.speed = speed
    }
}

/// Mirrors `struct BMAP_BaseInfo` (bmap.h).
public struct BMapBaseInfo: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// Should be 0xFF except in speciality maps
    public var owner: UInt8
    /// Initial stock, maximum 90
    public var armour: UInt8
    /// Initial stock, maximum 90
    public var shells: UInt8
    /// Initial stock, maximum 90
    public var mines: UInt8

    public init(x: UInt8, y: UInt8, owner: UInt8, armour: UInt8, shells: UInt8, mines: UInt8) {
        self.x = x
        self.y = y
        self.owner = owner
        self.armour = armour
        self.shells = shells
        self.mines = mines
    }
}

/// Mirrors `struct BMAP_StartInfo` (bmap.h).
public struct BMapStartInfo: Hashable, Sendable {
    public var x: UInt8
    public var y: UInt8
    /// Direction towards land from this start. Range 0–15
    public var dir: UInt8

    public init(x: UInt8, y: UInt8, dir: UInt8) {
        self.x = x
        self.y = y
        self.dir = dir
    }
}

/// Mirrors `struct BMAP_Run` (bmap.h): one RLE run header in the map data.
///
/// The run stream terminates with the sentinel
/// {datalen: 4, y: 0xFF, startx: 0xFF, endx: 0xFF} — all four fields must
/// be checked together when the codec is ported.
public struct BMapRun: Hashable, Sendable {
    /// Length of the data for this run, INCLUDING this 4-byte header
    public var datalen: UInt8
    /// Y coordinate of this run
    public var y: UInt8
    /// First square of the run
    public var startx: UInt8
    /// Last square of run + 1 (first deep-sea square after the run)
    public var endx: UInt8

    public init(datalen: UInt8, y: UInt8, startx: UInt8, endx: UInt8) {
        self.datalen = datalen
        self.y = y
        self.startx = startx
        self.endx = endx
    }
}

// MARK: - RLE Codec (readRun / writeRun)
//
// Ported from readrun()/writerun()/readnibble()/writenibble() in
// Reference/c/bmap.c. The errchk TRY/LOGFAIL/CLEANUP macro system is not
// ported — those sites become guard/return false.

/// Converts a display tile back to its canonical terrain value. Inverse of
/// `terrainToTile`, but lossy for variant-collapsed tiles: swamp/rubble/
/// grass/damagedWall always decode to their "3" variant specifically —
/// never 0/1/2. This is a real property of the original format (the
/// network/file layer never preserved decay sub-variants through a
/// tile-space round trip), not a bug to fix here.
///
/// Ported from `tiletoterrain()` in Reference/c/server.c:4301. The C
/// original lives in server.c (not bmap.c), but the codec needs it
/// directly since BoloKit does not depend on CXBolo. Returns -1 for tile
/// values with no terrain mapping (base/pill tiles, or out-of-range) —
/// matches the C `default: assert(0); return -1;` path; the assert is a
/// debug-only trap, not a behavioral contract, same divergence already
/// accepted for `terrainToTile`.
private func tileToTerrain(_ tile: Int32) -> Int32 {
    guard let t = Tile(rawValue: tile) else { return -1 }
    switch t {
    case .wall: return Terrain.wall.rawValue
    case .river: return Terrain.river.rawValue
    case .swamp: return Terrain.swamp3.rawValue
    case .crater: return Terrain.crater.rawValue
    case .road: return Terrain.road.rawValue
    case .forest: return Terrain.forest.rawValue
    case .rubble: return Terrain.rubble3.rawValue
    case .grass: return Terrain.grass3.rawValue
    case .damagedWall: return Terrain.damagedWall3.rawValue
    case .boat: return Terrain.boat.rawValue
    case .minedSwamp: return Terrain.minedSwamp.rawValue
    case .minedCrater: return Terrain.minedCrater.rawValue
    case .minedRoad: return Terrain.minedRoad.rawValue
    case .minedForest: return Terrain.minedForest.rawValue
    case .minedRubble: return Terrain.minedRubble.rawValue
    case .minedGrass: return Terrain.minedGrass.rawValue
    case .sea: return Terrain.sea.rawValue
    case .minedSea: return Terrain.minedSea.rawValue
    case .unknown: return Terrain.minedSea.rawValue
    default: return -1  // base/pill tiles — not terrain-representable
    }
}

/// Reads a tile-space nibble at index `i` from a packed byte buffer.
/// High nibble first: `readNibble(buf, 0)` reads the high 4 bits of
/// `buf[0]`, `readNibble(buf, 1)` reads the low 4 bits of `buf[0]`, etc.
private func readNibble(_ buf: [UInt8], _ i: Int) -> Int32 {
    let byte = buf[i / 2]
    return (i % 2 != 0) ? Int32(byte & 0x0f) : Int32((byte & 0xf0) >> 4)
}

/// Writes a nibble into a packed byte buffer at index `i`. Callers must
/// write each index exactly once into a zero-initialized buffer — this
/// mirrors the C reference's XOR-based bit packing, which only produces
/// correct results under that same assumption.
private func writeNibble(_ buf: inout [UInt8], _ i: Int, _ nibble: Int32) {
    let n = UInt8(truncatingIfNeeded: nibble) & 0x0f
    let byteIndex = i / 2
    if i % 2 != 0 {
        buf[byteIndex] = (buf[byteIndex] & 0xf0) ^ n
    } else {
        buf[byteIndex] = (buf[byteIndex] & 0x0f) ^ (n << 4)
    }
}

/// Reads the display-tile value at a flat grid position, allowing
/// `col == 256` to alias into column 0 of the next row — mirroring C's
/// contiguous `int terrain[256][256]` array layout, where
/// `terrain[row][256]` is the same memory as `terrain[row + 1][0]`. Only
/// `row == 255, col == 256` is genuinely one cell past the whole grid
/// (true undefined behavior in the C reference, with no reproducible
/// oracle value); that single case is clamped to "matches its own
/// default" so callers' equality checks terminate safely instead of
/// crashing.
private func terrainToTileFlatAt(_ grid: TerrainGrid, row: Int, col: Int) -> Int32 {
    let flatIndex = row * 256 + col
    guard flatIndex < grid.storage.count else {
        return defaultTile(x: Int32(col), y: Int32(row)).rawValue
    }
    return terrainToTile(grid.storage[flatIndex])
}

/// Encodes the next run of non-default tiles starting at `(x, y)`,
/// mirroring C `readrun()`. Call repeatedly with the same `y`/`x` pair
/// (starting at `y = 0, x = 0`) to enumerate every run in the grid, in
/// row-major order. When the grid is exhausted, returns the terminator
/// sentinel run with empty data and `isLast == true`.
///
/// Note: this is a Bool-flagged, non-optional return rather than the
/// `Optional` shape originally proposed for this API — an Optional and
/// "returns the sentinel run" are two different contracts, and the
/// sentinel-returning behavior is what the C reference actually does.
public func readRun(
    grid: TerrainGrid, y: inout Int, x: inout Int
) -> (run: BMapRun, data: [UInt8], isLast: Bool) {
    // 512 bytes (1024-nibble capacity) comfortably covers the worst-case
    // single-row run: at most 256 tiles, at most 2 nibbles emitted per tile.
    var nibbleBuffer = [UInt8](repeating: 0, count: 512)

    while y < 256 {
        while x < 256 {
            if terrainToTileFlatAt(grid, row: y, col: x)
                != defaultTile(x: Int32(x), y: Int32(y)).rawValue {
                var nibs = 0
                let runY = y
                let startX = x

                repeat {
                    var len: Int
                    if x + 1 < 256
                        && terrainToTileFlatAt(grid, row: y, col: x + 1)
                            == terrainToTileFlatAt(grid, row: y, col: x) {
                        // sequence of like tiles
                        len = 2
                        while x + len < 256 && len < 9
                            && terrainToTileFlatAt(grid, row: y, col: x + len)
                                == terrainToTileFlatAt(grid, row: y, col: x) {
                            len += 1
                        }
                        writeNibble(&nibbleBuffer, nibs, Int32(len + 6)); nibs += 1
                        writeNibble(&nibbleBuffer, nibs, terrainToTileFlatAt(grid, row: y, col: x)); nibs += 1
                    } else {
                        // sequence of different tiles
                        len = 1
                        while x + len < 256 && len < 8
                            && terrainToTileFlatAt(grid, row: y, col: x + len)
                                != defaultTile(x: Int32(x + len), y: Int32(y)).rawValue
                            && terrainToTileFlatAt(grid, row: y, col: x + len)
                                != terrainToTileFlatAt(grid, row: y, col: x + len + 1) {
                            len += 1
                        }
                        writeNibble(&nibbleBuffer, nibs, Int32(len - 1)); nibs += 1
                        for i in 0..<len {
                            writeNibble(&nibbleBuffer, nibs, terrainToTileFlatAt(grid, row: y, col: x + i))
                            nibs += 1
                        }
                    }
                    x += len
                } while terrainToTileFlatAt(grid, row: y, col: x)
                    != defaultTile(x: Int32(x), y: Int32(y)).rawValue

                let endX = x
                // 4 == sizeof(struct BMAP_Run) (all-UInt8 packed fields).
                // truncatingIfNeeded mirrors C's silent uint8_t wraparound
                // for pathological rows dense enough to overflow a byte —
                // the format's own header comment notes real run data is
                // "always much less than 0xFF", so this is unreachable in
                // practice but kept faithful rather than crashing.
                let datalen = 4 + (nibs + 1) / 2
                let run = BMapRun(
                    datalen: UInt8(truncatingIfNeeded: datalen),
                    y: UInt8(truncatingIfNeeded: runY),
                    startx: UInt8(truncatingIfNeeded: startX),
                    endx: UInt8(truncatingIfNeeded: endX)
                )
                let data = Array(nibbleBuffer[0..<((nibs + 1) / 2)])
                return (run, data, false)
            }
            x += 1
        }
        y += 1
        x = 0
    }

    return (BMapRun(datalen: 4, y: 0xff, startx: 0xff, endx: 0xff), [], true)
}

/// Decodes one run's nibble data into `grid`, mirroring C `writerun()`.
/// Returns false on corrupt data (C's `ECORFILE`, or an invalid tile
/// nibble) — matches the C -1 sentinel. `grid` may be partially written on
/// failure, matching the C in-place semantics (writes happen before the
/// trailing datalen re-check).
///
/// Deviation from the C reference: this also guards `x < 256` before every
/// grid write. C's `terrain[run.y][x++]` would silently overrun into
/// adjacent row memory for corrupt data that passes the datalen checks but
/// encodes a run reaching past column 256; Swift arrays cannot do that
/// safely, so this path fails closed (returns false) instead of crashing.
/// Well-formed data from `readRun` never reaches this guard.
@discardableResult
public func writeRun(_ run: BMapRun, data: [UInt8], into grid: inout TerrainGrid) -> Bool {
    let datalen = Int(run.datalen)
    var x = Int(run.startx)
    var offset = 0

    while x < Int(run.endx) {
        guard 4 + (offset + 2) / 2 <= datalen, offset / 2 < data.count else { return false }
        let len = Int(readNibble(data, offset))
        offset += 1

        if len <= 7 {
            // sequence of different tiles
            let count = len + 1
            guard 4 + (offset + count + 1) / 2 <= datalen else { return false }
            for _ in 0..<count {
                guard offset / 2 < data.count else { return false }
                let terrainValue = tileToTerrain(readNibble(data, offset))
                offset += 1
                guard terrainValue != -1, x < 256 else { return false }
                grid[x, Int(run.y)] = Terrain(rawValue: terrainValue)
                x += 1
            }
        } else {
            // sequence of like tiles (len is always 8...15 — readNibble
            // only ever returns 0...15, so no other case is reachable)
            let count = len - 6
            guard 4 + (offset + 2) / 2 <= datalen, offset / 2 < data.count else { return false }
            let terrainValue = tileToTerrain(readNibble(data, offset))
            offset += 1
            guard terrainValue != -1 else { return false }
            for _ in 0..<count {
                guard x < 256 else { return false }
                grid[x, Int(run.y)] = Terrain(rawValue: terrainValue)
                x += 1
            }
        }
    }

    guard 4 + (offset + 1) / 2 == datalen else { return false }
    return true
}

// MARK: - Full-file decode (Wave 6.4a extension, D45)
//
// Ported from `clientloadmap()` (`Reference/c/bmap_client.c:19-100`) — the
// full BMAP-format orchestrator this port never had, discovered mid-Wave
// 6.4a while tracing what the missing client-side preamble-apply function
// actually needs to populate `state.terrain`/`pills`/`bases`/`starts`.
// Only the DECODE half; the encode half (`serversavemap()`,
// `bmap_server.c`) is Wave 6.4b's concern (it needs real map bytes to send
// from the server's own accept loop).
//
// Everything past the pure state-loading in the real function —
// `client.seentiles`/`client.images`/`mapimage()` — is fog-of-war display
// state, never modeled anywhere in this port (the same established
// precedent `TankLocalTick.swift`/`BuilderTick.swift`/`RecvSR.swift`/
// `DgramClientApply.swift` all independently document for
// `increasevis`/`decreasevis`), so it's not ported here either.

/// Decodes a full BMAP-format byte blob into `state.terrain`/`pills`/
/// `bases`/`starts`, wiping the terrain to `.mapDefault()` first (matching
/// the C's own "wipe the map clean" step). Returns `false` on any
/// malformed input (bad ident/version, over-limit counts, truncated
/// buffer, a corrupt run) — the C's own `LOGFAIL(ECORFILE)` paths, ported
/// as a `Bool` return rather than a thrown error to match this port's
/// established convention for the majority of its parse-and-validate
/// functions (`CLUpdate.decode` etc.).
public func decodeBMap(_ bytes: [UInt8], into state: inout GameState) -> Bool {
    // BMAP_Preamble: ident[8] + version(1) + npills(1) + nbases(1) + nstarts(1) = 12 bytes.
    let preambleSize = 12
    guard bytes.count >= preambleSize else { return false }

    let ident = Array(bytes[0..<8])
    guard ident == Array("BMAPBOLO".utf8) else { return false }
    let version = bytes[8]
    guard version == 1 else { return false }  // CURRENT_MAP_VERSION (bolo.h:26)

    let npills = Int(bytes[9])
    let nbases = Int(bytes[10])
    let nstarts = Int(bytes[11])
    guard npills <= 16, nbases <= 16, nstarts <= 16 else { return false }  // MAXPILLS/MAXBASES/MAX_STARTS

    // BMAP_PillInfo: x,y,owner,armour,speed (5 bytes). BMAP_BaseInfo:
    // x,y,owner,armour,shells,mines (6 bytes). BMAP_StartInfo: x,y,dir (3 bytes).
    let pillsSize = npills * 5
    let basesSize = nbases * 6
    let startsSize = nstarts * 3
    let runDataStart = preambleSize + pillsSize + basesSize + startsSize
    guard bytes.count >= runDataStart else { return false }

    state.terrain = .mapDefault()

    var offset = preambleSize
    var pills: [Pill] = []
    for _ in 0..<npills {
        pills.append(Pill(x: bytes[offset], y: bytes[offset + 1], armour: bytes[offset + 3], owner: bytes[offset + 2], speed: bytes[offset + 4], counter: 0))
        offset += 5
    }
    state.pills = pills

    var bases: [Base] = []
    for _ in 0..<nbases {
        bases.append(Base(x: bytes[offset], y: bytes[offset + 1], armour: bytes[offset + 3], owner: bytes[offset + 2], shells: bytes[offset + 4], mines: bytes[offset + 5]))
        offset += 6
    }
    state.bases = bases

    var starts: [Start] = []
    for _ in 0..<nstarts {
        starts.append(Start(x: bytes[offset], y: bytes[offset + 1], dir: bytes[offset + 2]))
        offset += 3
    }
    state.starts = starts

    // Run stream: repeated {BMapRun header (4 bytes) + (datalen-4) data
    // bytes} until the sentinel {datalen:4, y:0xff, startx:0xff, endx:0xff}
    // is reached exactly at the end of the run data.
    let runDataLen = bytes.count - runDataStart
    var runOffset = 0
    while true {
        guard runOffset + 4 <= runDataLen else { return false }
        let base = runDataStart + runOffset
        let run = BMapRun(datalen: bytes[base], y: bytes[base + 1], startx: bytes[base + 2], endx: bytes[base + 3])

        if run.datalen == 4, run.y == 0xff, run.startx == 0xff, run.endx == 0xff {
            guard runOffset + Int(run.datalen) == runDataLen else { return false }
            break
        }

        guard runOffset + Int(run.datalen) <= runDataLen else { return false }
        let dataBytes = Array(bytes[(base + 4)..<(base + Int(run.datalen))])
        guard writeRun(run, data: dataBytes, into: &state.terrain) else { return false }

        runOffset += Int(run.datalen)
    }

    return true
}

// MARK: - Full-file encode (Wave 6.4b, G-1)
//
// Ported from `serversavemap()` (`Reference/c/bmap_server.c:259-346`) --
// `decodeBMap`'s inverse, needed by `joinplayerserver()`'s Swift
// counterpart (`server.c:885`) to produce the map-byte payload that
// follows `BoloPreamble` on the wire. Promoted from
// `BMapDecodeTests.swift`'s private `encodeFullBMap` test helper, which
// already implemented this exact byte layout to build `decodeBMap`
// fixtures (D28: that helper's coverage moves here, it doesn't vanish).
//
// Unlike `serversavemap()`, this never allocates or sizes a buffer up
// front (`serverloadmapsize()`'s own separate pass, `bmap_server.c:
// 348-374`) -- Swift's `Array` grows as needed, so there's no equivalent
// step to port.

/// Encodes `state.pills`/`bases`/`starts`/`terrain` into a full BMAP-format
/// byte blob -- the inverse of `decodeBMap`. Always succeeds (there is no
/// C failure mode on the encode side to replicate; `serversavemap()`'s own
/// `LOGFAIL`s are all allocation-failure or `readrun()`-internal, neither
/// of which apply to a Swift array builder).
public func encodeBMap(_ state: GameState) -> [UInt8] {
    var bytes: [UInt8] = Array("BMAPBOLO".utf8)
    bytes.append(1)  // CURRENT_MAP_VERSION (bolo.h:26)
    bytes.append(UInt8(state.pills.count))
    bytes.append(UInt8(state.bases.count))
    bytes.append(UInt8(state.starts.count))

    for p in state.pills {
        bytes += [p.x, p.y, p.owner, p.armour, p.speed]
    }
    for b in state.bases {
        bytes += [b.x, b.y, b.owner, b.armour, b.shells, b.mines]
    }
    for s in state.starts {
        bytes += [s.x, s.y, s.dir]
    }

    var y = 0
    var x = 0
    while true {
        let (run, data, isLast) = readRun(grid: state.terrain, y: &y, x: &x)
        bytes += [run.datalen, run.y, run.startx, run.endx]
        if isLast { break }
        bytes += data
    }

    return bytes
}
