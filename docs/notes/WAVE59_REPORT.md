# Wave 5.9 Report — mine-cascade injection-point wiring

> Scoped-agent report file, per `docs/WAVE59_BOOTSTRAP.md`. Pre-brief first, completion report
> appended below it once coding lands. Not folded into `docs/AGENT_NOTES.md`/`docs/PLAN.md` by
> this agent — PLANNER does that at merge time.

---

### [WAVE 5.9 AGENT] 2026-09-03 — pre-brief: wiring `enterTile`/`grabTile`/`tankMoveTick`'s dead-tumble/`smallboom`/`superboom` to `explosionAt`/`superboomAt`

**Type:** pre-brief
**Phase:** Wave 5.9
**Blocks:** the Wave 5.9 coding GO

**Setup note:** `Reference/c` submodule was uninitialized in this worktree (`git submodule status`
showed a `-` prefix); ran `git submodule update --init` to get `client.c`/`server.c` before reading
anything, otherwise this pre-brief would have been working from doc-comment citations alone.

## 1. Confirmed via direct read: the gap is real and exactly where `docs/PLAN.md` says

`RunTick.swift`'s own file header (lines 21–33) already states this precisely: every
`onMineExplosion`/`onSuperboomTerrain`/`onDropPills` callback is a straight pass-through to
`runTick`'s caller, and "nothing in the shipped codebase calls `explosionAt`/`superboomAt` from
anywhere but `chainAt`/`floodAt` internally." Confirmed by grep — the only production callers of
`explosionAt`/`superboomAt` today are `chainAt`/`floodAt` (`MineChain.swift`). Every trigger site
named in the wave's scope (`enterTile`, `grabTile`, `smallboom`, `superboom`,
`tankMoveTick`'s dead-tumble) currently either calls a no-op closure or (for `tankMoveTick`) an
argument-less `onSuperboom()`/`onSmallboom()` hook with nothing behind it.

## 2. Causer attribution: `state.localPlayer`, uniformly, confirmed against the C oracle

Traced `recvclsmallboom`/`recvclsuperboom`/`recvclgrabtile`/`recvcldroppills` (`server.c:3036`,
`3056`, `2271`, `2127`) — all four take a `player` argument that is simply "whichever client sent
this message" and pass it straight through to `explosionat(player, x, y)` /
`superboomat(player, x, y)` / `droppills(player, x, y, pills)`. In the real system that's
whatever `client.player` was for the sending process; in `BoloKit`'s single-process model, every
one of these five trigger sites is scoped exclusively to the local player already (per
`TankLocalTick.swift`'s own file header, "Everything here is scoped to the LOCAL player only," and
`tankMoveTick`'s dead-tumble branch's own `guard player == state.localPlayer else { return }`).
So causer = `UInt8(state.localPlayer)` at every site, no exceptions, no shell-owner/builder-player
attribution needed here (that's `ShellTick.swift`/`BuilderTick.swift`'s job, explicitly out of
this wave's scope per the bootstrap doc).

## 3. Real trap found, not assumed: a dead-flag ordering hazard in `smallboom`/`superboom`

This is the one thing in this pre-brief I'd flag as needing sign-off before I start, not just FYI.

`MineChain.swift`'s own header (lines 34–41) already documents *why* `recvsrsmallboom`'s tank-
damage check is a sibling `if`, guarded only by `!dead` — "which naturally self-excludes the
causer, who is already dead from their own `smallboom()`/`superboom()` call by the time this
runs." That reasoning depends on real network latency: in the C client/server split, by the time
the broadcast round-trips back and `recvsrsmallboom`'s damage check runs, the causer's own
`dead = 1` has *already* landed locally (set synchronously, well before any socket I/O
completes).

`BoloKit` has no such latency to lean on — everything is synchronous. `smallboom()`'s current
body (`TankLocalTick.swift:159-179`) sets `dead = true` in its *second* `if` block, after the
point where the mine-explosion callback currently fires (in the first `if` block). If I simply
replace `onMineExplosion(point)` in place with a direct `explosionAt(...)` call, `explosionAt`'s
`applySplashDamage` would run while `state.players[player].dead` is **still `false`** — and since
the causer's own tank is sitting exactly at the detonation point (distance 0 ≤
`smallboomRadius`), it would take a *second*, spurious splash-damage hit from its own detonation,
something the real C's timing structurally prevents. Same hazard for `superboom()`.

**Fix, verified against both call contexts:** defer the `explosionAt`/`superboomAt` call in
`smallboom`/`superboom` until *after* the second `if` block sets `dead = true`, capturing the
detonation point/origin in a local `Optional` set only if the first block ran. Checked both
places these functions are entered:
- **First-death case** (e.g. `enterTile`'s wall/armed-pill branches calling `superboom` directly
  while the tank is still alive): `dead` transitions `false → true` inside the function itself —
  deferring the call to after that transition is what makes the self-exclusion work at all.
- **Already-dead case** (`tankMoveTick`'s dead-tumble branch calling `smallboom`/`superboom` at
  `respawnCounter == explodeTicks`): `dead` is already `true` on entry (that's the branch's own
  guard), so the second `if` block is a no-op either way and the deferred call still fires
  correctly from the captured point set in the first block.

Also traced what happens if `applySplashDamage`'s escalation calls `smallboom`/`superboom` again
recursively (armour still negative after a hit): by the time that nested call runs, `dead` is
already `true` *and* `respawnCounter` was just set to `explodeTicks + 1` (so `respawnCounter <=
explodeTicks` is false too) — the nested call's first `if` guard (`!dead || respawnCounter <=
explodeTicks`) is false, so it's a structural no-op. Confirmed this matches the real C: by the
time a self-inflicted broadcast round-trips back in a real multiplayer session,
`client.respawncounter` has already ticked well past `EXPLODETICKS` too, so the "recursive"
`smallboom()`/`superboom()` calls inside `recvsrsmallboom`/`recvsrsuperboom`'s escalation are
*also* structural no-ops for the original causer in the real system. Not a design change on my
part — reproducing an existing (if easy to miss) property of the oracle's timing.

`grabTile` has **no** equivalent hazard — it never sets `dead` itself, so a live tank walking onto
a mined tile correctly takes splash damage from its own `explosionAt` call in place, matching how
walking onto an unexploded mine is supposed to kill you.

## 4. Exact per-site plan

**`grabTile` (`TankLocalTick.swift:257-302`)** — Ported from `recvclgrabtile` (`server.c:2271`,
confirmed: mined-terrain cases call `explosionat(player, x, y)` at `server.c:2332`, no ordering
hazard — see §3). Add `onSuperboomTerrain`/`onDropPills` params (currently only has
`onMineExplosion`); replace the `onMineExplosion(point)` call in the mined-terrain switch case
with a direct `explosionAt(player: UInt8(player), x: x, y: y, state: &state, onMineExplosion:,
onSuperboomTerrain:, onDropPills:)` call, threading the same three closures through for
`explosionAt`'s own possible splash-damage escalation.

**`smallboom` (`TankLocalTick.swift:159-179`)** — Ported from `smallboom()` (`client.c:5614`) +
`recvclsmallboom` (`server.c:3036`, confirms `explosionat(player, x, y)` at `server.c:3046`). Add
`onSuperboomTerrain` param. Restructure per §3: capture the tank tile as an `Optional<Pointi>`
inside the first `if` block (keeping the existing `onMineExplosion(point)` notify call exactly
where it is, unchanged, for whatever UI hook wants "a mine just went off here" independent of the
state mutation), then call `explosionAt(player: UInt8(player), ...)` after the second `if` block,
only if the point was captured.

**`superboom` (`TankLocalTick.swift:188-244`)** — Ported from `superboom()` (`client.c:5647`) +
`recvclsuperboom` (`server.c:3056`, confirms `superboomat(player, x, y)` at `server.c:3066`). Add
`onMineExplosion` param. Same deferred-call restructure as `smallboom`, using the already-computed
`x`/`y` origin (the half-tile-adjustment logic already shipped, unchanged). The existing 9-particle
corner/edge loop and its `killSquareBuilder`/`killPointBuilder` calls are `superboom`'s own local
effect (matches `client.c`'s direct `addlist`/`killpointbuilder` calls, no network round trip
involved) — left untouched, not part of this wiring.

**`enterTile` (`TankLocalTick.swift:347-451`)** — No direct wiring of its own; it only delegates to
`grabTile`/`superboom`, which become self-wired above. Its 5 `grabTile(...)` call sites need the 2
new closures added (`onSuperboomTerrain: onSuperboomTerrain, onDropPills: onDropPills` — already
in `enterTile`'s own parameter list); its 2 `superboom(...)` call sites need `onMineExplosion:
onMineExplosion` added, same reasoning.

**`tankMoveTick`'s dead-tumble path (`TankTick.swift:85-139`)** — Ported from `tankmovelogic`'s
dead branch (`client.c:3977-4020`, re-confirmed line-by-line this session). Three things need
wiring, not two — see the third finding below.
- Add `onMineExplosion`/`onSuperboomTerrain`/`onDropPills` params (currently has none of the
  three).
- `respawnCounter == explodeTicks` branch: alongside the existing `onSuperboom()`/`onSmallboom()`
  notify calls (kept, unchanged, per RunTick.swift's compatibility — see §5), add direct
  `superboom(state:, onSuperboomTerrain:, onMineExplosion:, onDropPills:)` /
  `smallboom(state:, onMineExplosion:, onSuperboomTerrain:, onDropPills:)` calls, matching
  `client.c:4008-4013`'s direct `superboom()`/`smallboom()` calls exactly (no callback indirection
  in the oracle at all here — it's a straight function call, matching my earlier finding for
  `enterTile`'s wall case).

**Third finding, not previously named in the wave's scope text but squarely inside "tankMoveTick's
dead-tumble path": the periodic corpse-explosion sub-branch is also missing a builder-kill call.**
Re-read `client.c:3993-4006` (the `respawncounter % 5 == 0` sub-branch) directly: in the `default`
case of its terrain switch (the documented grass1/grass2 bug, already correctly preserved in
`TankTick.swift:113-124`), C calls `killpointbuilder(explosion->point)` *in addition to* creating
the explosion-list entry — `TankTick.swift`'s own header (lines 80-84) already names
`onExplosion` as the injection point for exactly this ("builder-kill-by-explosion"), so this reads
as an intentionally-deferred part of the same gap, not a separate one. Fix: after
`onExplosion(point)` in that branch, add `killPointBuilder(at: point, state: &state,
onDropPills: onDropPills)` — no ordering hazard (`killPointBuilder` never touches `dead`).

## 5. Why none of this needs to touch `RunTick.swift` (off-limits)

Every new parameter added above (`grabTile`'s two, `smallboom`'s one, `superboom`'s one,
`tankMoveTick`'s three) is added with a no-op default, so every existing keyword-argument call site
I don't own — specifically `RunTick.swift`'s `tankMoveTick(player:, state:, onExplosion:,
onSuperboom:, onSmallboom:, onSpawn:)` call — keeps compiling unchanged. I confirmed I'm not
silently downgrading anything by checking what each default costs:
- `tankMoveTick`'s dead-tumble `smallboom`/`superboom` calls still fire `explosionAt`/
  `superboomAt` correctly even with `onMineExplosion`/`onSuperboomTerrain` defaulting to no-ops,
  because I hardwired that call *inside* `smallboom`/`superboom` themselves, not dependent on
  what `tankMoveTick` forwards into them.
- The one default that *does* cost something: `onDropPills` defaulting to no-op means a tank that
  dies via the dead-tumble timeout won't have its onboard pills scattered onto the map until
  `RunTick.swift`'s call is updated to forward its own already-existing `onMineExplosion`/
  `onSuperboomTerrain`/`onDropPills` parameters into `tankMoveTick`. That's a **one-line
  follow-up in an off-limits file** — flagging it for PLANNER/whoever next owns `RunTick.swift`,
  not fixing it myself. Today's behavior (pills not scattered on tumble-death) is unchanged from
  before my fix either way, so nothing regresses; it's a disclosed gap, not a new one.

## 6. `MineChain.swift` — closing its own recursive-depth gap (file I own, fixing directly)

`applySplashDamage` (`MineChain.swift:315-340`) already has all three closures in scope but only
passes two of three at each of its two calls — `superboom(state:, onSuperboomTerrain:,
onDropPills:)` (missing `onMineExplosion`) and `smallboom(state:, onMineExplosion:,
onDropPills:)` (missing `onSuperboomTerrain`). Since `smallboom`/`superboom` are gaining the
missing param each, and `applySplashDamage` already has it locally, I'll add it at both call
sites — free correctness improvement for `explosionAt`/`superboomAt`'s own splash-escalation depth,
no behavior change for anything already shipped (these are currently-unreachable branches that
just weren't fully wired one level down).

## 7. Flagged, not fixed — off-limits file, real but narrow gap

`RecvSR.swift`'s 5 existing calls to `smallboom`/`superboom` (lines 302, 465, 467, 543, 545) each
omit one of the three closures (all default to `{ _ in }`/`{ _,_ in }` today). Once `smallboom`/
`superboom` gain the missing param, these calls keep compiling but a *second-level* recursive
splash cascade *originating from a broadcast receive* (rare: local tank takes splash damage from
someone else's mine, that pushes it into a self-detonation that itself cascades again in the same
tick) would silently no-op at the second level. `RecvSR.swift` already has all three closures in
its own scope at each call site — this is a trivial one-line-per-site follow-up for whoever next
owns that file, not something I can fix here.

**Also flagged, not a regression:** fixing `superboom()` this way changes the *observable*
behavior of one already-shipped, PARITY-passed `RecvSR.swift` call I'm not touching —
`recvSrCapturePill`'s wall/damaged-wall tile case (`RecvSR.swift:301-302`). Today it's a no-op for
terrain (since `superboom()` itself was unwired); after this fix it will correctly trigger a real
2×2 crater conversion, matching `client.c`'s direct `superboom()` call in that same branch exactly.
This is a desired fidelity upgrade, not scope creep into that file — I'm not editing
`RecvSR.swift`, just changing what a function it already calls actually does.

## 8. Test plan (D28)

Current baseline before this wave: will state exact before/after count in the completion report.
Planned new named tests, one per behavior wired at minimum:
- `grabTileMinedLandDetonatesTerrainAndSchedulesChain` — mined tile → crater + chain-slot entry.
- `smallboomDetonatesOwnTileAfterDeath` — terrain crater appears, and (regression per §3) local
  tank's armour is *not* double-decremented by its own splash radius.
- `superboomDetonatesTerrainAfterDeath` — 2×2 crater, same no-double-damage regression check.
- `tankMoveTickDeadTumbleSuperboomDetonatesTerrain` / `...SmallboomDetonatesTerrain` — dead-tumble
  path's escalation reaches real terrain mutation, not just the existing notify-flag assertions.
- `tankMoveTickDeadTumbleExplosionKillsPointBuilder` — the third finding (§4), builder in range of
  the periodic corpse explosion actually dies.
- `applySplashDamageEscalationReachesTerrain` (or extend an existing `MineChain` test) — confirms
  §6's fix threads correctly.

## 9. Open questions for PLANNER

1. Confirm the §3 ordering fix (defer `explosionAt`/`superboomAt` until after `dead = true`) is
   the right call, not something to resolve differently — I'm confident in the trace but this is
   exactly the kind of subtle timing-collapse decision the project's process wants a second set of
   eyes on before code lands, not after.
2. Confirm the periodic-corpse-explosion `killPointBuilder` gap (§4, third finding) is in-scope for
   this wave rather than tracked separately — it's inside the literal C function
   (`tankmovelogic`'s dead branch) the wave already owns, but it wasn't named in the original
   scope text.
3. Note for whoever next owns `RunTick.swift`/`RecvSR.swift`: two one-line follow-ups identified
   above (§5's `tankMoveTick` call needing 3 more forwarded arguments; §7's 5 `smallboom`/
   `superboom` calls needing their missing closure each). Not blocking this wave's own correctness,
   but worth a tracked item so they aren't lost.

No code written yet. Test baseline unchanged pending GO.

[TO: PLANNER] Pre-brief complete, awaiting review before coding starts. The ordering trap in §3 is
the one item I'd most want confirmed before I start — everything else is mechanical once that's
settled. Branch: `wave-5.9-mine-cascade` (already checked out in this worktree per the bootstrap's
setup step).
