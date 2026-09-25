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
    public var fog: [Int16] {
        didSet { revision += 1 }
    }
    /// Last-observed display `Tile` at each coordinate, at full resolution (pill/base
    /// occupancy classification included, matching what `fogTileFor` actually returns —
    /// not collapsed to raw terrain). `.unknown` where never seen. Mirrors `seentiles`.
    public var seenTiles: [Tile] {
        didSet { revision += 1 }
    }
    /// #159: bumped by every write to `fog`/`seenTiles` (a `didSet` observer, not a manual
    /// call at each known mutator -- `fog`/`seenTiles` are `public var`, and
    /// `TileGridCacheTests` legitimately pokes them directly to simulate a change without
    /// going through `increaseVis`/`decreaseVis`, so anything less than "any write bumps
    /// this" misses real callers). Exists so `GameRenderView.tileGridInputsEqual` can detect
    /// "this FogState is unchanged since the last render" in O(1) instead of comparing two
    /// 65536-element arrays every tick -- cheap for the host path (whose `FogState` was
    /// already paying that cost once per tick regardless of whether anything moved) but was
    /// a real regression on the join/solo paths once #159 gave them a fog of their own:
    /// their tick-consuming loop shares one queue with TCP/UDP message dispatch, so a
    /// per-tick cost that used to be O(1) (`fogState == nil` short-circuits) growing to
    /// O(131072 elements) in a -Onone debug build was enough to fall behind the ~20ms tick
    /// budget and starve message delivery -- confirmed by `JoinPathAllianceTests` timing out
    /// only with the unthrottled comparison, not with this counter.
    public var revision: UInt64 = 0

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

/// v1.5.0 #1's tank-vision rect: 29×29 tiles centered on `pos`'s own tile, matching every C
/// call site's hardcoded literal (`client.c:459-460` et al.) -- no named `bolo.h` macro
/// exists for this (`docs/CONSTRAINTS.md`). Shared by `HostGameEngine`'s tick-driven
/// movement/alliance hooks, `HostListener`'s join-time spawn reveal, and
/// `updateFogVisionTracker`'s client-side equivalent. Moved here from `BoloNet`
/// (`HostSession.swift`) for #159 since it's pure geometry with no host-only dependency.
public func tankVisionRect(around pos: Vec2f) -> Recti {
    makerect(Int32(pos.x) - 14, Int32(pos.y) - 14, 29, 29)
}

/// #72: the fixed vision rect a built pill (oracle-verified) or, if
/// `GameState.baseVisionEnabled` is on, a captured base (a deliberate deviation -- see
/// that property's own doc comment) projects -- 15×15 tiles centered on its own tile,
/// `tankVisionRect`'s shape at a smaller size. Oracle-verified for pills:
/// `makerect(pillX - 7, pillY - 7, 15, 15)` at every one of `client.c`'s pill-vision call
/// sites (`1549,2013,2205,2383,2954,2993,6359,6436`) -- no `bolo.h` macro exists for this
/// either, matching `tankVisionRect`'s own precedent. Bases reuse this exact size for
/// consistency rather than inventing a second magic number, since the oracle has no size
/// of its own to port for them.
public func structureVisionRect(around tile: Pointi) -> Recti {
    makerect(tile.x - 7, tile.y - 7, 15, 15)
}

/// #72: factors out the "moved / newly-contributing / stopped-contributing" three-way
/// branch that both `HostGameEngine.updateFogVision`'s tank loop and
/// `updateFogVisionTracker`'s tank loop already duplicate inline -- used by the new
/// pill/base loops in both places so this logic isn't written a third time. Deliberately
/// **not** used to refactor the existing tank loops in this pass (shipped, tested, out of
/// scope) -- new code shares an abstraction; old code stays untouched. Returns the rect to
/// cache for next tick's diff (`nil` when not currently contributing).
public func applyVisionSourceTransition(
    shouldContribute: Bool, currentRect: Recti, previousRect: Recti?,
    fogState: inout FogState, terrain: TerrainGrid, pills: [Pill], bases: [Base],
    hiddenMines: Bool, observer: Int, players: [PlayerState]
) -> Recti? {
    if shouldContribute {
        if let previousRect, previousRect.origin != currentRect.origin {
            increaseVis(
                currentRect, state: &fogState, terrain: terrain, pills: pills, bases: bases,
                hiddenMines: hiddenMines, observer: observer, players: players
            )
            decreaseVis(previousRect, state: &fogState)
            return currentRect
        } else if previousRect == nil {
            increaseVis(
                currentRect, state: &fogState, terrain: terrain, pills: pills, bases: bases,
                hiddenMines: hiddenMines, observer: observer, players: players
            )
            return currentRect
        }
        return previousRect // unchanged
    } else if let previousRect {
        decreaseVis(previousRect, state: &fogState)
        return nil
    }
    return nil
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
///
/// **#159 perf note:** starts from `live` in place (instead of allocating a second empty
/// `TileGrid` and copying every cell from `live.storage`), skips the `Tile(rawValue:)!`
/// round trip for the ~65000 non-mined tiles per call (mine substitution only matters for
/// the 7 mined `Tile` raw values), and hoists the `hiddenMines` check out of the per-tile
/// loop (`applyMineSubstitution`'s own guard made this a no-op call every tile when off).
/// Measured ~19ms -> well under 10ms in a Debug build -- this made #159's join/solo-path
/// fog wiring (which now calls this every tick, not just the host path) cheap enough to
/// not starve `handleJoinEvent`'s single-consumer TCP/UDP dispatch loop
/// (`JoinPathAllianceTests.guestRequestingAndLeavingAnAllianceUpdatesItsOwnState` was the
/// regression this was caught by). Behavior is unchanged -- `FogResolvedTileGridTests`
/// pins it.
public func fogResolvedTileGrid(for state: GameState, fogState: FogState) -> TileGrid {
    var grid = displayTileGrid(for: state)
    let hiddenMines = state.hiddenMines

    grid.storage.withUnsafeMutableBufferPointer { gridBuf in
        fogState.fog.withUnsafeBufferPointer { fogBuf in
            fogState.seenTiles.withUnsafeBufferPointer { seenBuf in
                for key in 0..<gridBuf.count {
                    if fogBuf[key] > 0 {
                        guard hiddenMines else { continue } // live value already in place
                        let raw = gridBuf[key]
                        guard (10...15).contains(raw) || raw == Tile.minedSea.rawValue else { continue }
                        let liveTile = Tile(rawValue: raw)!
                        gridBuf[key] = applyMineSubstitution(
                            resolved: liveTile, previousSeen: seenBuf[key], hiddenMines: true
                        ).rawValue
                    } else {
                        gridBuf[key] = seenBuf[key].rawValue
                    }
                }
            }
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
                let revealed = tileFor(
                    x: x, y: y, terrain: terrain, pills: pills, bases: bases,
                    localPlayer: observer, players: players
                )
                if state.seenTiles[index] != revealed {
                    state.seenTiles[index] = revealed // bumps `revision` via `didSet`
                }
            default:
                break
            }
        }
    }
}

// MARK: - FogVisionTracker (#159)

/// One observer's fog-vision bookkeeping across ticks: the accumulated `FogState` plus,
/// per contributing mover, the vision rect they're currently contributing. Generalizes
/// the per-observer body of `HostGameEngine.updateFogVision` (`BoloNet`) so a non-host
/// party -- the join client, or the solo/local-tab session, neither of which has a
/// `HostGameEngine` -- can compute its own fog locally, matching the C oracle's actual
/// architecture: each peer maintains its own `client.fog[][]` from data it already holds
/// (`client.c`'s `increasevis`/`decreasevis`), rather than the host transmitting a fog
/// grid over the wire. See `updateFogVisionTracker` below.
public struct FogVisionTracker: Sendable {
    public var fogState = FogState()
    /// Keyed by mover's player index -- unlike `HostGameEngine`'s `observer * maxPlayers +
    /// mover` key (which tracks every observer at once), a tracker only ever has one
    /// observer, so the mover index alone is unambiguous. Not `private`: mutated directly
    /// by the free function `updateFogVisionTracker` below, which needs write access but
    /// isn't a member of this struct (kept as a free function, matching `increaseVis`/
    /// `decreaseVis`'s own shape, rather than adding a `BoloKit`-only mutating method).
    var visionSourceRect: [Int: Recti] = [:]
    /// #72: same shape as `visionSourceRect`, keyed by `state.pills`/`state.bases` array
    /// index instead of player index -- a separate dictionary per object kind, not a
    /// shared key space, since a pill index and a player index would otherwise collide.
    var visionSourcePillRect: [Int: Recti] = [:]
    var visionSourceBaseRect: [Int: Recti] = [:]

    public init() {}
}

/// Diffs `observer`'s vision sources (own tank + allied tanks) against last tick's cached
/// rects and applies exactly one `increaseVis`/`decreaseVis` per real transition (newly
/// contributing / moved / stopped contributing), then runs the observer's own proximity
/// mine reveal -- the same generic-transition diff `HostGameEngine.updateFogVision` uses,
/// minus that function's `SRRevealTerrain` wire-send bookkeeping (irrelevant here: the
/// caller already holds ground-truth `state`, so there's nothing to redact to itself).
/// Must be called every tick, diffing against `tracker`'s cached rects rather than
/// rebuilt from scratch each time -- rebuilding breaks `fog`'s refcount semantics the
/// same way `updateFogVision`'s own doc comment already documents paying to avoid
/// (double-apply, an unclamped `Int16` going negative, a stale `decreaseVis`).
public func updateFogVisionTracker(_ tracker: inout FogVisionTracker, observer: Int, state: GameState) {
    guard state.hiddenMines else { return }

    for mover in state.players.indices {
        let shouldContribute = state.players[mover].connected
            && testAlliance(observer, mover, players: state.players)
        let previousRect = tracker.visionSourceRect[mover]

        if shouldContribute {
            let currentRect = tankVisionRect(around: state.players[mover].tank)
            if let previousRect, previousRect.origin != currentRect.origin {
                increaseVis(
                    currentRect, state: &tracker.fogState, terrain: state.terrain, pills: state.pills,
                    bases: state.bases, hiddenMines: state.hiddenMines, observer: observer,
                    players: state.players
                )
                decreaseVis(previousRect, state: &tracker.fogState)
                tracker.visionSourceRect[mover] = currentRect
            } else if previousRect == nil {
                increaseVis(
                    currentRect, state: &tracker.fogState, terrain: state.terrain, pills: state.pills,
                    bases: state.bases, hiddenMines: state.hiddenMines, observer: observer,
                    players: state.players
                )
                tracker.visionSourceRect[mover] = currentRect
            }
            // previousRect == currentRect (same tile): unchanged, no-op.
        } else if let previousRect {
            decreaseVis(previousRect, state: &tracker.fogState)
            tracker.visionSourceRect[mover] = nil
        }
    }

    for pill in state.pills.indices {
        let key = pill
        let shouldContribute = state.pills[pill].owner != playerNeutral
            && testAlliance(observer, Int(state.pills[pill].owner), players: state.players)
            && !state.pills[pill].isOnboard && !state.pills[pill].isDead
        let currentRect = structureVisionRect(around: Pointi(x: Int32(state.pills[pill].x), y: Int32(state.pills[pill].y)))
        tracker.visionSourcePillRect[key] = applyVisionSourceTransition(
            shouldContribute: shouldContribute, currentRect: currentRect, previousRect: tracker.visionSourcePillRect[key],
            fogState: &tracker.fogState, terrain: state.terrain, pills: state.pills, bases: state.bases,
            hiddenMines: state.hiddenMines, observer: observer, players: state.players
        )
    }

    if state.baseVisionEnabled {
        for base in state.bases.indices {
            let key = base
            let shouldContribute = state.bases[base].owner != playerNeutral
                && testAlliance(observer, Int(state.bases[base].owner), players: state.players)
            let currentRect = structureVisionRect(around: Pointi(x: Int32(state.bases[base].x), y: Int32(state.bases[base].y)))
            tracker.visionSourceBaseRect[key] = applyVisionSourceTransition(
                shouldContribute: shouldContribute, currentRect: currentRect, previousRect: tracker.visionSourceBaseRect[key],
                fogState: &tracker.fogState, terrain: state.terrain, pills: state.pills, bases: state.bases,
                hiddenMines: state.hiddenMines, observer: observer, players: state.players
            )
        }
    } else if !tracker.visionSourceBaseRect.isEmpty {
        // #72: the host toggle was turned off mid-session -- decay every currently-active
        // base vision source cleanly (matches the generic diff's own "stopped contributing"
        // branch) rather than leaving stale fog counts stuck incremented forever.
        for (key, rect) in tracker.visionSourceBaseRect {
            decreaseVis(rect, state: &tracker.fogState)
            tracker.visionSourceBaseRect[key] = nil
        }
    }

    revealNearbyHiddenMines(
        tankPos: state.players[observer].tank, state: &tracker.fogState, terrain: state.terrain,
        pills: state.pills, bases: state.bases, observer: observer, players: state.players
    )
}
