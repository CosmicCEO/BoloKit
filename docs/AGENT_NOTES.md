# Agent Notes — Shared Running Log

> **Purpose:** Durable scratchpad shared between Claude Xcode API (implementer) and Claude.ai (reviewer and planner).
> High-level decisions belong in `PLAN.md`.
> This file is for implementation-level continuity: what was tried, what broke, what was resolved, and flags between agents.
>
> **Convention:** Always append — never edit or rewrite earlier entries, EXCEPT during an explicit
> periodic archive/compression pass (a Wave 5.8-style docs pass), which is the sanctioned exception
> to this rule. Pull before reading.

---

## Format

Each entry uses this block:

```
### [AGENT] YYYY-MM-DD — short title

Body — a few lines. Be concrete. No filler.

> **→ Parity:** action item or handoff note (omit if not applicable)
> **→ Planner:** item for review or question (omit if not applicable)
> **→ Implementer:** instructions for the xcode agent, coding environment (omit if not applicable)
```

Types:
- **[PLANNER]** — wave assignments, sign-offs, architectural decisions
- **[IMPLEMENTER]** — coding, completion reports, build results, deviations from spec
- **[PARITY]** — audit findings, behavioral verification, sign-offs

---

## Index

| Archive | Content |
|---|---|
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, all of Wave 6 (6.0–6.3, the D39 fix, 6.6, 6.4a/6.4b/6.4c, 6.5a/6.5b, and the Wave 6 phase close-out), all of Wave 7 (7.0–7.3, the full v1 vertical slice, D58–D89), Milestone B's D90–D93 pre-Milestone-B rulings through B.0–B.7 (all closed, PARITY PASS), and now also D109 through Milestone C's full close: Milestone B's final loose fixes (D109–D112, local-play fallback + three live-found fixes + the neutral-pillbox crash fix) and B.8 (D113–D117, join-side live network loop), plus all of Milestone C's D118-batch — C.0 (HUD status panel + kick/ban), C.5 (preferences shell), C.3 (procedural sound synthesis) — all closed PARITY PASS, and the D123/D124 git-worktree-race process ruling, up to but not including D125's scoped-autonomy-grant entry, which opens the active log — compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

**PARITY activation rule:** PARITY runs **post-commit only**. PARITY is activated exclusively by a `[TO: PARITY]` tag in a PLANNER sign-off after IMPLEMENTER commits. PARITY does NOT run during planning phases.

**Role split (2026-09-02 reorg):** IMPLEMENTER owns detailed code-level planning (trap lists, C-source pre-briefs, implementation-approach calls) for its own waves. PLANNER is limited to high-level project management (sequencing, GOs, the decisions/open-questions log, cross-wave policy) and does not pre-author trap lists.

**Commit discipline (all three roles):** an entry only exists once it is appended here AND
committed — never leave it sitting in a chat session as "done" or "ready." This has already
bitten the project twice: a Wave 6.0 pre-brief reported "ready" in conversation with nothing
committed, and a Wave 6.0 PARITY audit relayed by Jerod with nothing committed either. Whoever
writes an entry commits it themselves, in the same sitting — `git add docs/AGENT_NOTES.md` (plus
any other file touched) → `git commit`. This applies identically to IMPLEMENTER, PLANNER, and
PARITY; none of the three can push to `github.com/CosmicCEO/BoloKit` (Jerod pushes after
relaying), but all three can and must commit locally. If you're about to say something is done and
you haven't run `git commit` yet, it isn't done yet.

**Role bootstraps (read at session start, each is instructions-only — no wave status lives in
them):** `CLAUDE.md` (IMPLEMENTER), `docs/PARITY.md` (PARITY), `docs/PLANNER.md` (PLANNER). Wave
status and decisions live only in `docs/PLAN.md`; this file is the chronological log. Restructured
2026-09-02 from a single IMPLEMENTER-only `CLAUDE.md` into three role-specific files, specifically
to stop wave-status content from being duplicated (and going stale) across bootstrap files.

---

## Active Log (from D125)

> **Archived 2026-09-06 (Admin agent pass):** D109 through Milestone C's full close — Milestone B's
> final loose fixes (D109–D112), B.8 (D113–D117), and Milestone C's D118-batch (C.0, C.5, C.3, all
> closed PARITY PASS), plus the D123/D124 git-worktree-race process ruling — compressed into
> `docs/notes/archive.md`. Full uncompressed entries preserved in git history per D28. The active
> log below now begins at **D125** (the scoped autonomy grant / sound-wiring priority), which still
> owes PARITY audits for its own work (the sound-effect wiring and B.9's rendering-then-smoothing
> saga) — not yet closed, left fully active below.

### [PLANNER] 2026-09-06 — D125: scoped autonomy grant (1hr/25k-token budget), sound-wiring priority

**Type:** ruling (D125), scoped exception
**Phase:** cross-cutting — time-boxed, no ask-first checkpoints unless a decision would create real unplanned cost

**Jerod's direct grant, logged per D87's own precedent (a scoped exception is its own decision,**
**not a standing change):** work autonomously for up to ~1 hour / ~25,000 tokens of work-budget,
no waiting on intermediate decisions unless something would create real unplanned cost (pushing
to GitHub, destructive operations, spending money) — those still pause for a check. Everything
else, decide and proceed.

**Priority 1: wire the generated sounds to actual gameplay events** — the gap surfaced when Jerod
asked "is the sound rigged to the game?" and the answer was no: C.3 built generation+bundling only,
per the original Milestone C pre-plan's own framing (asset sourcing was one axis, "new
simulation-event → sound-trigger hook points through the tick loop" was always the other, separate
axis, never started).

**Priority 2, time/budget permitting: one more small item from the backlog** — B.9 (remote-tank
smoothing) is the lowest-risk remaining candidate. Running this sequentially after sound-wiring,
not in parallel, to avoid spending part of the time budget on git-race recovery overhead (D123's
own lesson) rather than actual work.

[TO: IMPLEMENTER] Coding GO issued directly for sound-wiring next (separate message incoming).

### [IMPLEMENTER] 2026-09-06 — D125 completion report: sound-effect wiring, deliberately partial

**Commit:** `a840fc3`. 684 tests passing (unchanged — zero `BoloKit`/`BoloNet` surface touched).
App target builds; this commit's two files (`SoundPlayer.swift`, `GameSession.swift`) carry no
real compile errors (the build tool's own unrelated stale-diagnostic noise on three other,
already-landed files persisted across this session — same documented toolchain-instability
pattern, not this commit's own defect).

**Traced the reference's own trigger map first** (`GSXBoloController.m:3619-3733`'s `playsound()`
dispatch + every `client.playsound(...)` call site across `client.c`), confirming the exact
24-name → sound-ID mapping and, critically, the near/far decision mechanism: `client.fog[y][x] >
0` (fog-of-war visibility of the event's *location*), not distance or player identity. **This is
D65's own already-deferred territory** ("treat every tile as fully visible" — no `fog`/`seentiles`
model exists in this port at all) — so a true near/far implementation isn't possible without first
reopening D65, which this time-boxed pass correctly didn't attempt. Every sound wired here is
inherently "near": always the local player's own on-screen action, never a relayed remote event.

**Landed, zero new `BoloKit` risk:** `onMineExplosion`/`onSuperboomTerrain`/`onExplosion`/
`onSuperboom`/`onSmallboom` — all five were *already* top-level `runTick` parameters (B.5b/B.5d/
D88 §4's own work), always defaulted to no-ops by every caller until now. `GameSession`'s
local-play `tick()` now supplies real `SoundPlayer.shared.play(...)` closures for all five —
covers `explosion`/`superboom`/`mine` of the priority-6 list directly.

**Deliberately not attempted, disclosed rather than rushed:** `tankshot`/`hittank` (the other two
priority names) each need a genuinely new callback parameter threaded through an existing
function (`TankLocalTick.swift`'s shoot-handling; `ShellTick.swift`'s `killTank`) — real,
multi-file `BoloKit` signature surgery under a hard time box, the same class of change this
session's own earlier `TCPSession`/`UDPSession` splits (D117) took real care over. Chose not to
rush it in the remaining budget rather than risk shipping something half-verified — same judgment
call as stopping the earlier `GameSession` join-mode attempt the moment a real concurrency bug
surfaced, tonight's own established standard for this session. `tree`/`build`/`pillshot`/
`bubbles`/`sink`/`builderdeath`/`msgreceived` also unwired for the same reason (new callback
threading each). **Host path (`HostGameEngine`, `BoloNet`) and the join path are entirely
unwired** — `HostGameEngine` deliberately has no `AppKit` dependency (layering: the app target
depends on `BoloNet`, never the reverse), so host-path sound needs a new cross-module callback
API on `HostGameEngine` itself, mirroring `onTickRendered`'s already-established `@MainActor`
closure shape — a scoped task of its own, not something to squeeze in here.

**`SoundPlayer.swift`** ports `playsound()`'s own mechanism exactly: a small round-robin `NSSound`
pool per name (sized to mirror the reference's implied concurrency — more slots for frequent
sounds like `explosion`/`tankshot`/`hittank`, fewer for rare one-shots), first-non-playing-slot
scan, no queueing if every slot is busy. Reads C.5's `"GSMuteBool"` `@AppStorage` key fresh on
every call (not cached at init) via `UserDefaults.standard`, matching `playsound()`'s own
`if (!muteBool)` guard re-evaluated every call.

> **→ Planner:** Landed the zero-risk third of this task cleanly within budget; the harder two-
> thirds (new callback threading for the remaining 6 priority-adjacent names, plus host/join-path
> wiring) is real, disclosed remaining work — recommend its own pre-brief/coding-GO rather than
> assuming "sound wiring" is closed. Not continuing further tonight per your own "land what's
> solid" framing — stopping here rather than rushing the harder pieces under the remaining time
> box.
> **→ Parity:** Straightforward to audit in isolation — two files, no `BoloKit`/`BoloNet` diff at
> all. Worth confirming live (build + actually trigger a mine/explosion in a real local-play
> session) that a sound audibly plays, not just that the wiring compiles — I did not have a way to
> confirm audible output myself this pass beyond reading the code and confirming clean
> build/tests.

### [PLANNER] 2026-09-06 — D125 sound-wiring reviewed and approved; remainder tracked, not assigned

**Type:** review, approval
**Phase:** sound-wiring — partial landing approved, remainder logged as future scope

Reviewed `a840fc3` directly. Correct, honest partial landing: 5 of 24 names wired via
already-existing, previously-unconsumed `runTick` callbacks, zero `BoloKit` signature changes.
Far/near correctly identified as blocked on fog-of-war (D65, already deferred) rather than faked.
Host-path/join-path sound correctly identified as needing a new cross-module callback API
(mirroring `onTickRendered`) — a real, separate scoped task, not squeezed into this pass.

**Approved as landed.** Remaining scope (tankshot/hittank/tree/build/pillshot/bubbles/sink/
builderdeath/msgreceived — needs new callback threading through `TankLocalTick.swift`/
`ShellTick.swift`; host-path sound via a new `HostGameEngine` callback) tracked as future work,
not assigned now — time budget (D125) better spent elsewhere this pass. Audible playback
confirmation still needed from Jerod directly, same as C.3's own synthesis quality question.

[TO: IMPLEMENTER] Approved, no changes needed. Given remaining time in D125's budget, pick up B.9
(remote-tank smoothing) next if you have room — small, low-risk, closes out one more Milestone B
loose end. If budget's tight, hold and report what's landed instead.

### [PLANNER] 2026-09-06 — B.9 re-scoped: remote-player rendering is the real gap, smoothing comes after

**Type:** ruling, coding GO
**Phase:** B.9 re-scoped (deciding directly, per D125's grant — don't wait on Jerod for this)

**Real, more significant finding than B.9's original framing assumed.** `GameRenderView.drawSprites()`
only ever draws the local player's own tank/builder/shells — a stale D73-era scope decision from
before B.7/B.8 made real other-connected-players possible. Right now, hosting or joining with a
real second player, **that player is completely invisible on screen**, not just jerky. B.9 as
originally scoped ("smoothing") has nothing to smooth yet.

**Re-scoping B.9: render every connected remote player's tank/builder/shells first** (reading
`state.players[p]` for every connected `p != localPlayer`, same ownership-colored sprite drawing
`drawSprites()` already does for the local player, just generalized), **with position smoothing
between relay updates folded in as the natural next layer once rendering exists** — not two
separate sub-waves, the same one, since smoothing a tank nobody can see was never a real
increment on its own.

**Coding GO'd, time-boxed per D125.** Land what's solid within remaining budget; disclose and hold
if it runs long rather than rushing render correctness.

[TO: IMPLEMENTER] Good catch holding rather than guessing or building a no-op. Coding GO for the
re-scoped B.9: remote-player rendering first, smoothing layered on top, same sub-wave. Time-boxed
per D125 — land what's solid, disclose what isn't, report back.

### [IMPLEMENTER] 2026-09-06 — B.9 completion report: remote-player rendering landed, smoothing deferred

**Commit:** `8da3454`. 684 tests passing (unchanged — pure app-target rendering change, no
`BoloKit`/`BoloNet` surface touched). App target builds; `GameView`'s preview re-rendered with no
errors (visual confirmation limited to "no crash, no regression to the local-only path" — the
existing `#Preview` fixture has only one player, so it can't itself show a second tank rendering
correctly; that needs a real host+join session, which I didn't have time to set up and drive live
this pass).

**Traced `GSBoloView.m:293-360`'s own `drawSprites` directly** rather than guessing at draw order:
builders for every connected player first (shared `BUILD0`/`BUILD1` sprite, no per-player color —
confirmed no such coloring exists in the reference either), then other players' tanks (mutual-
alliance friendly/enemy coloring — reused `testAlliance`, the exact same function `PlayerStatusView.
swift` (C.0) already calls for the identical ownership question, not a second implementation of
the same logic), then the local player's own tank last (unconditionally player-colored), then
shells/explosions for every connected player (one shared sprite each). Matches the reference's own
per-section scope exactly, not an approximation.

**Smoothing deferred, disclosed rather than rushed:** D114's re-scoped B.9 goal (remote players
looking smooth, not jerky, between the host's ~10Hz relay cadence) needs a genuinely separate
piece of work — a view-layer position-history buffer per remote player (previous position +
timestamp, interpolated/extrapolated at render time), distinct from "render them at all," which is
what actually landed. Given the remaining time box and that PLANNER's own framing already ranked
"invisible" as the more important gap than "jerky," landing that cleanly and stopping here rather
than also rushing the interpolation layer under continued time pressure.

> **→ Planner:** B.9's rendering half done and tested; smoothing is real, scoped, disclosed
> remaining work, not silently dropped — recommend its own explicit GO if picked back up rather
> than assuming "B.9" is fully closed. Given how much has landed across D109 through this in one
> continuous window, I'd suggest this is a reasonable point to pause for a real human check-in
> (a live playtest with an actual second player would catch anything my own read-the-reference-
> and-test-in-isolation approach can't) before continuing further unprompted.
> **→ Parity:** Worth a live check if you can arrange a real two-player session (host + join) —
> confirm the second tank actually appears, colored correctly (friendly vs. enemy, once alliance
> state differs), and that builders/shells for a remote player render at their real positions, not
> just that the diff structurally matches the reference's draw order.

### [PLANNER] 2026-09-06 — B.9's rendering half approved; pausing D125's autonomous work for a human check-in

**Type:** review, approval, pause
**Phase:** B.9 rendering landed; session paused pending Jerod's return

Reviewed `8da3454` directly — correct, matches `GSBoloView.m:293-360`'s own draw order and scope
exactly, reuses C.0's `testAlliance` check rather than reimplementing it. Approved. Smoothing
correctly deferred, disclosed rather than rushed, same standard as every other honest partial
landing tonight.

**Agreed with IMPLEMENTER's own call to pause rather than keep chaining GOs.** A great deal landed
in one continuous window (the crash fix, D109 through B.9's rendering, C.0/C.5/C.3, four
self-caught git-race incidents) — all tested and disclosed honestly, but the multiplayer-facing
pieces (B.8's join-side loop, B.9's remote-player rendering) have only ever been verified against
the C reference and unit-level tests, never a real second player. That's exactly the kind of gap
a live playtest catches that isolated read-and-verify can't — same standard this project already
applied once tonight (D109's own live-testing thread found four real bugs no test suite caught).
Stopping here for Jerod's own check-in, not because the budget (D125) ran out.

[TO: IMPLEMENTER] Agreed, good call. Holding here — nothing further until Jerod's back for a real
playtest (ideally once his Parallels VM is ready, so a real two-instance host↔join test is
finally possible, not just solo).

### [PLANNER] 2026-09-06 — D125 resumed within timebox, per Jerod's direct instruction

**Type:** ruling, coding GO
**Phase:** D125's budget resumed — B.9's smoothing next

Jerod explicitly said continue within the original timebox rather than hold for his return. B.9's
remote-player rendering already landed and is safe to build on without a live peer (position-
history smoothing is a pure view-layer interpolation concern, verifiable by unit test against
synthetic position sequences — it doesn't need a real second player to verify correctness, unlike
the network loop itself). Picking up the deliberately-deferred piece next.

[TO: IMPLEMENTER] Resume within D125's budget — Jerod said continue rather than hold. Next: B.9's
smoothing (position-history buffer per remote player, interpolating between the host's ~10Hz
relay updates, matching the goal D114 originally set). This is verifiable in isolation (feed a
synthetic sequence of relayed positions, assert the rendered position interpolates smoothly
between them) — doesn't require a live second peer, unlike the network loop itself. Same
time-boxed judgment as before: land what's solid, disclose what isn't.

### [IMPLEMENTER] 2026-09-06 — Pre-brief: B.9 smoothing (position-history buffer)

**Confirmed no reference-side counterpart exists** (`grep -rl "smooth\|interp\|dead.reckon"
Reference/c` → nothing but the LICENSE file matching "interp" substring) — this is genuinely
new, port-original UI polish, not a port of `GSBoloView.m` behavior. D114 is this port's own
goal, not something the C client ever did.

**Root cause of the jerk, confirmed by tracing the actual call sites, not assumed:** every path
(`GameSession.tick()`, `handleJoinEvent(.tick:)`, `HostGameEngine`'s own tick →
`onTickRendered`) calls `renderView.render(state)` every game tick (50Hz). A remote player's
`state.players[i].tank`, though, only changes when a UDP relay packet is actually decoded and
applied (`UDPSession.apply`) — sender-side gated at `localSeq % 5 == 0` (~10Hz,
`GameSession.sendLocalUpdateIfDue`/`HostGameEngine`'s identical cadence) and further irregular
on the wire. So a remote tank's drawn position is frozen for ~5 render calls, then jumps —
exactly D114's "jerky" complaint, not a bug in the relay itself.

**Why naive lerp-between-last-two-samples in real time doesn't work, worked out before writing
any code:** interpolating live between "previous known sample" and "latest known sample" only
smooths ticks that occur *after* the latest sample already arrived, but by definition nothing
is known about where the tank is heading until that sample lands — so a pure live lerp still
snaps the instant a new sample arrives (fraction hits 1.0 immediately) and holds flat in
between. The standard fix (used here) is a small **fixed render delay**: draw each remote
player `smoothingDelayTicks` ticks in the past, not at the current tick. That gives the *next*
real sample time to have already arrived by the time playback actually needs it, so the
interpolation has two genuine endpoints instead of extrapolating into the unknown. Set
`smoothingDelayTicks = 5`, matching the known relay cadence exactly (one interval of buffer).

**Design, verifiable without AppKit or a live peer:** a pure `RemotePositionSmoother` struct
in `BoloKit` (no `Foundation`, just `Vec2f` + tick math — same "reuse over invention," testable-
in-isolation bias as every other `BoloKitTests`-level type) — `update(rawPosition:tick:)` (no-op
unless the value actually changed since the last call, called every tick with the live
`state.players[i].tank`) and `smoothedPosition(atTick:)` (returns the delayed/interpolated draw
position — nil only before any sample has ever arrived). One instance per remote player index,
owned by `GameRenderView` (the view-layer concern PLANNER's own framing named), never by
`GameState`/`BoloKit` gameplay logic itself — this has no effect on simulation, only on what's
drawn. Unit-tested in `BoloKitTests` with a synthetic sequence of `update` calls at known ticks,
asserting: (a) before the delay window has any two real samples, position holds at the earliest
known sample (no premature interpolation off partial data); (b) between two known samples,
queried positions are strictly monotonic and bounded between them (not equal to either endpoint
except at the boundary ticks); (c) held flat at the latest sample once the query tick runs past
it with no third sample yet (no overshoot/extrapolation past known data).

**Scope line, disclosed up front:** builder/shell positions for remote players are NOT smoothed
this pass — same jerk exists there, but tanks are the visually dominant case and PLANNER's own
prior framing ranked "invisible" (B.9's rendering half) above "jerky" without further ranking
sub-parts of jerky itself; extending the same `RemotePositionSmoother` to builders/shells is a
mechanical follow-up once this lands, not attempted now to keep this pass reviewable as one
piece.

### [IMPLEMENTER] 2026-09-06 — B.9 completion report: smoothing landed (tanks only, disclosed)

**Commit:** `2aa96c6` (pre-brief at `47f2ca0`). 684 → 690 tests (183+501 XCTest/swift-testing
split, was 177+501 before this change — 6 new, no shrink, D28). App target builds clean
(`mcp__xcode__BuildProject`, no errors).

**Landed exactly the pre-brief's design:** `RemotePositionSmoother` (`BoloKit`, pure, no
`Foundation`) — records the last two distinct raw position samples per remote player, renders
at `currentTick - smoothingDelayTicks` (5, matching the known relay cadence) so the
interpolation's far endpoint has usually already arrived by the time playback needs it, rather
than a live lerp that still snaps the instant a new sample lands. Wired into `GameRenderView`
via a `[Int: RemotePositionSmoother]` keyed by player index, fed every `render(_:)` call,
consumed in `drawSprites`'s other-player-tank branch in place of the raw `other.tank`.

**6 new unit tests, synthetic sequences (no C reference oracle applies — confirmed by grep, not
assumed):** holds at the first sample before any second one arrives; returns `nil` before any
sample ever arrives; interpolates strictly monotonically between two known samples; holds flat
at the latest sample once query runs past it with no third sample (no overshoot); an unchanged
raw position is a no-op and doesn't reset the window; and a **negative control** proving the
render delay is actually load-bearing — temporarily zeroed `smoothingDelayTicks`, confirmed 2 of
the 6 tests fail for exactly the predicted reason (immediate snap to the new sample, the
identical failure mode a live two-sample lerp has), then restored to 5 and reconfirmed green.

**Disclosed, not attempted this pass:** builder/shell positions for remote players still draw
raw (same jerk, smaller visual weight, mechanical follow-up once this lands — pre-brief's own
stated scope line, not a new gap found mid-work). Still unverified against a live second peer
(same caveat as B.9's rendering half and B.8's whole network loop) — everything here is provably
correct against synthetic input, but "does it *look* smooth" with real network jitter is a live-
playtest question, not a unit-test one.

> **→ Planner:** B.9 (rendering + tank smoothing) is now fully landed and disclosed; builder/
> shell smoothing is real, scoped, remaining work if picked back up, not silently dropped.
> Deferring to your own read on whether anything else fits inside D125's remaining timebox.

### [PLANNER] 2026-09-06 — B.9 CLOSED (approved directly, PARITY still owed); D125 wrapping up

**Type:** close, session wrap-up
**Phase:** B.9 closed; D125's autonomous window ending

Reviewed `2aa96c6` directly — negative-controlled render-delay claim, correctly disclosed as
port-original (no reference counterpart, `GSBoloView.m` never smooths anything), 690 tests.
Approved and closing B.9's core scope (rendering + smoothing); builder/shell raw-draw for remote
players stays a small disclosed follow-up, not its own tracked gap.

**Wrapping up D125's window here rather than starting something larger (B.10/C.1/C.2/C.4).** A
long, dense, productive run landed tonight: the crash fix, D109 through B.9 (rendering+smoothing),
C.0/C.5/C.3, partial sound-wiring, four self-caught git-race incidents, zero data loss throughout.
B.9 and D125's sound-wiring both still owe PARITY audits — logging that explicitly rather than
losing track of it, next real session's first job.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — Milestone B's row updated
(B.9 closed).

[TO: IMPLEMENTER] B.9 closed, D125's session wrapping up here. Owed: PARITY audits for B.9
(`8da3454`+`2aa96c6`+`33dca74`) and the sound-wiring (`a840fc3`+`3f100b4`) — next session's first
job, whenever that is. Nothing further needed from you right now; good work tonight.
[TO: PARITY] Two audits queued for whenever you're next active: B.9 (remote-player rendering +
smoothing) and D125's sound-wiring (5 of 24 events, explosion/superboom/mine). Neither has been
touched by you yet.

### [PLANNER] 2026-09-06 — Admin agent: archive/compression pass (D109–Milestone C's close) + README status refresh

**Type:** repo housekeeping (archive/compression pass, README sync), no code, no ruling
**Phase:** n/a — administrative

Admin agent performed a scheduled archive/compression pass on this file, re-deriving the cut point
by heading text via `grep -n "### \[PLANNER\] 2026-09-06 — D125: scoped autonomy grant"` rather
than trusting a stale line number.

**Archived:** everything strictly before the D125 heading — D109 through D112 (local-play fallback
+ three live-found fixes + the neutral-pillbox crash fix), B.8 (D113–D117, join-side live network
loop), and all of Milestone C's D118-batch (C.0/C.5/C.3, all closed PARITY PASS) plus the D123/D124
git-worktree-race process ruling — compressed into a new section in `docs/notes/archive.md`,
matching its existing per-sub-wave summary format (commit hashes, key findings, decision
cross-references). Full uncompressed text preserved in git history per D28. **D125 onward (the
sound-effect wiring + B.9's rendering-then-smoothing saga) was left completely untouched in the
active log — it still owes PARITY audits and is explicitly not closed**, per the task's own
instruction not to sweep that in.

**Updated in this file:** the `## Index` table's `docs/notes/archive.md` row (now describes the
extended range through Milestone C's close), and the `## Active Log` header/archived-note block
retitled to "from D125" where the trimmed log now starts.

**Also refreshed `README.md`'s Status section** to match `docs/PLAN.md`'s actual current
wave-status table: Milestone B closed except B.10 (join client's outbound CL* protocol surface);
Milestone C in progress (C.0/C.3/C.5 closed, C.1/C.2/C.4 not started); Milestone D still queued;
test count updated to ~690. **Did not touch Jerod's own in-progress "Learning arc"/"Current
state"/"To do" narrative edit under Contributors & Partners** — confirmed via `git diff` before
editing and re-confirmed it survived byte-for-byte after this session's edits.

`git status --short` checked immediately before this commit: only `README.md`, `docs/AGENT_NOTES.md`,
and `docs/notes/archive.md` staged; the four Director-owned untracked artifacts, `docs/U.S.A.map`,
`.claude/`, and `Resources/` were present but left completely untouched and not included.

[TO: PLANNER] Archive pass and README refresh complete and committed. No ruling made, no wave
status changed in `PLAN.md` itself — purely compression + doc sync. D125 onward remains active,
still owing PARITY audits on the sound-wiring and B.9's smoothing work — flagging clearly so this
isn't mistaken for closed.
[TO: PARITY] No action needed on this pass — no code or behavioral content touched.

### [PLANNER] 2026-09-06 — First beta release published: v0.1.0-beta.1

**Type:** release, no code decision
**Phase:** cross-cutting — public artifact, not a wave/sub-wave

Built the app in Release configuration, bumped `MARKETING_VERSION` 1.0→0.1.0 (`8790be0`), tagged
`v0.1.0-beta.1`, and published a GitHub prerelease with the built `.app` (zipped) attached, notes
summarizing current status/known gaps.

**Release:** https://github.com/CosmicCEO/BoloKit/releases/tag/v0.1.0-beta.1

Semver pre-release naming, per Jerod's own choice — room to increment `beta.2`/`beta.3` etc. as
more builds land. Not a wave/sub-wave decision, just a project-management artifact; no D-number
assigned.
