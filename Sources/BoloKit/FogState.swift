import Darwin

// MARK: - v1.5.0 (issue #1) — fog-of-war state and vision algorithm
//
// Ported from `client.h:59,61`'s per-client `fog[WIDTH][WIDTH]`/`seentiles[WIDTH][WIDTH]`
// globals and `client.c`'s `increasevis`/`decreasevis`/`fogtilefor`/`testhiddenmine`
// (3850-3921, 6143-6270, 4462-4498). See `docs/CONSTRAINTS.md`'s "Fog-of-war (v1.5.0)"
// section for the full rationale behind every deviation noted below.
//
// **Deviation from C's architecture, not from the algorithm:** in C there is exactly one
// `FogState`-equivalent per running process (the single global `struct Client client`),
// because C's networking sends every client full ground truth and fog is purely a local
// rendering filter. This port instead gives the HOST one `FogState` per connected player
// slot, and redacts what crosses the wire per recipient (wired up in `HostGameEngine`/
// `HostListener`, not here). This file only ports the algorithm itself, which stays
// bit-for-bit faithful to `Reference/c` regardless of who owns the state.

/// Per-observer fog-of-war state. One instance represents one observer's accumulated
/// vision: the host's own view, or (once wired into `HostGameEngine`) one per connected
/// player slot. Mirrors C's `fog`/`seentiles` globals, unified into a value type since
/// this port has no separate client/server split.
public struct FogState: Sendable {
    /// Reference-count grid; `fog[y*256+x] > 0` means the tile is currently visible.
    /// Mirrors `fog[WIDTH][WIDTH]` — magnitude counts overlapping vision sources (own
    /// tank, own pills/bases, allied tanks/pills/bases) so one source moving away doesn't
    /// falsely re-fog a tile another source still covers. `Int16` comfortably bounds the
    /// realistic overlap count; this is a pure count, never sent over the wire, so exact
    /// bit-width parity with C's `int` isn't required.
    public var fog: [Int16]
    /// Last-observed display `Tile` at each coordinate, at full resolution (pill/base
    /// occupancy classification included, matching what `fogTileFor` actually returns —
    /// not collapsed to raw terrain). `.unknown` where never seen. Mirrors `seentiles`.
    public var seenTiles: [Tile]

    public init() {
        fog = [Int16](repeating: 0, count: 256 * 256)
        seenTiles = [Tile](repeating: .unknown, count: 256 * 256)
    }

    /// `seenTiles` as a `TileGrid`, ready for `mapimage()`/`isMinedTile()` — the same
    /// autotiling functions `GameRenderView.drawTerrain` already calls against live
    /// ground truth today. Recomputed on read rather than kept as a second stored
    /// representation, since this is a rendering-time convenience, not a hot path.
    public var tileGrid: TileGrid {
        var grid = TileGrid()
        grid.storage = seenTiles.map(\.rawValue)
        return grid
    }
}

// MARK: - increaseVis / decreaseVis

/// Ported from `increasevis()` (`client.c:3876-3921`). Clips `r` to the map, increments
/// `fog` over the clipped rect, then re-snapshots `seenTiles` via `fogTileFor` wherever
/// `fog <= 1` (the tile just transitioned to visible) over that **same** rect.
///
/// **Deviation (`docs/CONSTRAINTS.md`):** C's second pass runs over
/// `insetrect(r, -1, -1)`, which actually *grows* the rect by 1 in each direction due to
/// `insetrect`'s sign convention — a sign artifact, not a deliberate behavior, with no
/// visible/gameplay consequence either way (a tile's final visible/hidden state and
/// revealed value are unaffected; only how eagerly an already-covered neighbor gets
/// redundantly re-snapshot changes). This port re-snapshots over the same clipped rect
/// `fog` was incremented over, per the invisible-bug exception to D24.
public func increaseVis(
    _ r: Recti, state: inout FogState, terrain: TerrainGrid, pills: [Pill], bases: [Base],
    hiddenMines: Bool, observer: Int, players: [PlayerState]
) {
    let clipped = intersectionrect(worldRect, r)
    guard clipped.size.width > 0, clipped.size.height > 0 else { return }

    let minX = clipped.origin.x
    let minY = clipped.origin.y
    let maxX = minX + clipped.size.width
    let maxY = minY + clipped.size.height

    for y in minY..<maxY {
        for x in minX..<maxX {
            state.fog[Int(y) * 256 + Int(x)] += 1
        }
    }
    for y in minY..<maxY {
        for x in minX..<maxX {
            let index = Int(y) * 256 + Int(x)
            guard state.fog[index] <= 1 else { continue }
            state.seenTiles[index] = fogTileFor(
                x: x, y: y, previousSeen: state.seenTiles[index], terrain: terrain,
                pills: pills, bases: bases, hiddenMines: hiddenMines, observer: observer, players: players
            )
        }
    }
}

/// Ported from `decreasevis()` (`client.c:3850-3874`). Decrements `fog` over the clipped
/// rect. Does **not** clear `seenTiles` — the last-seen snapshot persists (stale) while
/// re-fogged, matching C exactly.
public func decreaseVis(_ r: Recti, state: inout FogState) {
    let clipped = intersectionrect(worldRect, r)
    guard clipped.size.width > 0, clipped.size.height > 0 else { return }

    let minX = clipped.origin.x
    let minY = clipped.origin.y
    let maxX = minX + clipped.size.width
    let maxY = minY + clipped.size.height

    for y in minY..<maxY {
        for x in minX..<maxX {
            state.fog[Int(y) * 256 + Int(x)] -= 1
        }
    }
}

// MARK: - fogTileFor

/// Ported from the `static fogtilefor()` (`client.c:6143-6270`). Reuses `tileFor` — its
/// own doc comment already names it "the non-fog variant" of this exact C function — for
/// the shared pill/base/terrain resolution, then layers on the one piece `tileFor`
/// deliberately left out: mined-terrain substitution. A mine is hidden (rendered as its
/// unmined equivalent) unless `hiddenMines` is false, or `previousSeen` already equals
/// this exact mined tile (sticky reveal — once shown, a mine stays shown to this observer
/// even after re-fogging and re-revealing).
public func fogTileFor(
    x: Int32, y: Int32, previousSeen: Tile, terrain: TerrainGrid, pills: [Pill], bases: [Base],
    hiddenMines: Bool, observer: Int, players: [PlayerState]
) -> Tile {
    let resolved = tileFor(x: x, y: y, terrain: terrain, pills: pills, bases: bases, localPlayer: observer, players: players)
    return applyMineSubstitution(resolved: resolved, previousSeen: previousSeen, hiddenMines: hiddenMines)
}

/// The mine-substitution half of `fogTileFor`, factored out so a bulk whole-map resolver
/// (`fogResolvedTileGrid`, used for rendering) can reuse it without paying `tileFor`'s
/// per-cell pill/base linear-scan cost over all 65536 tiles — `displayTileGrid`'s own doc
/// comment already measured that at ~120ms for a full map, far over a 50Hz tick's 20ms
/// budget. `resolved` is whatever already-computed display tile (from `tileFor` or
/// `displayTileGrid`) this observer would see with full visibility.
public func applyMineSubstitution(resolved: Tile, previousSeen: Tile, hiddenMines: Bool) -> Tile {
    guard hiddenMines else { return resolved }

    switch resolved {
    // v1.5.0 #1 (fix pass, `/code-review max` on PR #56): `fogtilefor`'s real
    // `kMinedSeaTerrain` case (`client.c:6172-6173`) returns `kMinedSeaTile`
    // *unconditionally* -- it never even checks `hiddenmines`. Mined sea is never hidden,
    // matching its role as static, always-known border-ring geometry (`docs/CONSTRAINTS.md`'s
    // "Fog-of-war" section already treats it this way for the join-time redacted map; this
    // was the one place still substituting it like an ordinary hideable mine, a real parity
    // bug the review's `.minedSea`-in-`revealNearbyHiddenMines` finding pointed at without
    // catching this half of it).
    case .minedSea:
        return resolved
    // `fogtilefor`'s `kMinedForestTerrain`/`kMinedGrassTerrain` cases each check for
    // *either* tile as "already seen" (`client.c:6221-6227,6249-6255`) -- tree growth/
    // chopping toggles a mine's terrain between forest and grass without un-discovering it.
    case .minedForest:
        return (previousSeen == .minedForest || previousSeen == .minedGrass) ? resolved : .forest
    case .minedGrass:
        return (previousSeen == .minedForest || previousSeen == .minedGrass) ? resolved : .grass
    case .minedSwamp:
        return previousSeen == resolved ? resolved : .swamp
    case .minedCrater:
        return previousSeen == resolved ? resolved : .crater
    case .minedRoad:
        return previousSeen == resolved ? resolved : .road
    case .minedRubble:
        return previousSeen == resolved ? resolved : .rubble
    default:
        return resolved
    }
}

// MARK: - fogResolvedTileGrid

/// Whole-map display grid for a fog-aware renderer, matching `displayTileGrid`'s own
/// O(256×256 + overlays) performance discipline (reused directly for the ground-truth
/// half of this computation, not a second per-cell `tileFor` scan). For each tile:
/// currently visible (`fog > 0`) tiles resolve live every call (so a currently-watched
/// pill capture or terrain change is never stale, compensating for the known gap that
/// pill/base state transitions don't yet re-trigger their own vision-source resync —
/// see `HostGameEngine.updateFogVision`'s own doc comment); fogged-but-previously-seen
/// tiles use the frozen `seenTiles` snapshot; never-seen tiles are `.unknown`.
public func fogResolvedTileGrid(for state: GameState, fogState: FogState) -> TileGrid {
    let live = displayTileGrid(for: state)
    var grid = TileGrid()
    for key in grid.storage.indices {
        if fogState.fog[key] > 0 {
            let liveTile = Tile(rawValue: live.storage[key])!
            grid.storage[key] = applyMineSubstitution(
                resolved: liveTile, previousSeen: fogState.seenTiles[key], hiddenMines: state.hiddenMines
            ).rawValue
        } else {
            grid.storage[key] = fogState.seenTiles[key].rawValue
        }
    }
    return grid
}

// MARK: - revealNearbyHiddenMines

/// Ported from `testhiddenmine()` (`client.c:4462-4498`), deliberately renamed — despite
/// its C name, this is not a boolean predicate (its `TRY`/`CLEANUP`/`ERRHANDLER`-wrapped
/// return value is always 0 on success, and its call site only ever checks for the -1
/// error sentinel, never treats it as "is there a mine here"). It force-reveals any mined
/// tile within 2.0 world units of `tankPos` in the surrounding 3×3 tile block, regardless
/// of alliance or current fog state. Called every tick for the local/observing player's
/// own tank only (`client.c:4273-4280`).
///
/// **Discovered-defect fix:** this previously called `fogTileFor` (the substituting,
/// sticky-reveal variant), which on a never-before-seen mine returns the *unmined*
/// substitute — the opposite of "reveal". C's own `testhiddenmine` calls `refresh(x, y)`
/// (`client.c:4462-4498`), which computes `seentile = tilefor(x, y)` — the ground-truth,
/// non-substituting resolver (`client.c:6272-6303`) — and stores that unconditionally.
/// This function now does the same: `tileFor`, never `fogTileFor`. `docs/CONSTRAINTS.md`'s
/// "Fog-of-war" section previously (incorrectly) claimed this stayed bit-for-bit ported.
///
/// **Deviation (`docs/CONSTRAINTS.md`):** C indexes `client.terrain[y][x]` with no bounds
/// check near map edges, silently wrapping to an adjacent row (row-major memory layout).
/// This port relies on `TerrainGrid`'s own bounds-checked subscript (`nil` off-map) — a
/// real safety deviation, not a judgment call, since a literal Swift `Array` port would
/// trap instead of silently reading wrong-but-harmless data.
public func revealNearbyHiddenMines(
    tankPos: Vec2f, state: inout FogState, terrain: TerrainGrid, pills: [Pill], bases: [Base],
    observer: Int, players: [PlayerState]
) {
    let originX = Int32(tankPos.x) - 1
    let originY = Int32(tankPos.y) - 1

    for dy in Int32(0)..<3 {
        for dx in Int32(0)..<3 {
            let x = originX + dx
            let y = originY + dy
            guard let rawTerrain = terrain[Int(x), Int(y)] else { continue }

            let tileCenter = Vec2f(x: Float(x) + 0.5, y: Float(y) + 0.5)
            guard mag2f(sub2f(tileCenter, tankPos)) <= 2.0 else { continue }

            switch rawTerrain {
            // v1.5.0 #1 (fix pass, `/code-review max` on PR #56): C's real `testhiddenmine`
            // (`client.c:4462-4498`) has no `kMinedSeaTerrain` case in its own switch --
            // matches `fogtilefor`'s own unconditional non-hiding of mined sea
            // (`applyMineSubstitution`'s identical fix, `FogState.swift`); this port's switch
            // previously included it, a real parity deviation the review caught.
            case .minedSwamp, .minedCrater, .minedRoad, .minedForest, .minedRubble, .minedGrass:
                let index = Int(y) * 256 + Int(x)
                state.seenTiles[index] = tileFor(
                    x: x, y: y, terrain: terrain, pills: pills, bases: bases,
                    localPlayer: observer, players: players
                )
            default:
                break
            }
        }
    }
}
