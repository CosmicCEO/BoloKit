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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7) and pre-Wave-6 process + Wave 6.0–6.1 compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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

## Active Log (post-6.1)

> **Archived 2026-09-03:** pre-Wave-6 process entries (5.8 close-out, Wave 6 scope survey,
> Q16-Q20 rulings, cold-start restructure) and Wave 6.0/6.1 (pre-briefs, completion, PARITY
> audit + D35 fix/re-audit, close-out) compressed into `docs/notes/archive.md`. Full
> uncompressed text preserved in git history per D28.

### [IMPLEMENTER] 2026-09-02 — Wave 6.2 pre-brief: `recvsr*` broadcast handlers

**Type:** planning (no code this entry)
**Phase:** Wave 6.2
**Blocks:** the Wave 6.2 GO

Written in the same batch as the 6.1 entry above, same caveat applies: at Jerod's direct request,
ahead of the normal per-wave GO sequence — `docs/PLAN.md` currently marks 6.2 "blocked on 6.0/6.1."

**Scope (D32):** the ~33 `recvsr*` functions in `client.c` (all 34 `SR*` opcodes except
`SRHANGUP`, which has no handler — "not used" per `bolo.h:210`).

**Central architectural finding, more important than any individual trap.** In real distributed
Bolo, `recvsr*` exists because each player's process holds its own `client` struct, and the
server's broadcasts are how a remote client's copy stays in sync with server-authoritative
decisions it didn't compute itself. `BoloKit.GameState` has no such duplication — one process, one
state. Sampled `recvsrsmallboom`/`recvsrsuperboom`/`recvsrgrow` directly and confirmed: Wave 5.5a's
`explosionAt`/`superboomAt` (`MineChain.swift`) **already fully absorb** the tank-damage-cascade
logic these handlers contain (including the smallboom-vs-superboom nesting asymmetry — see that
file's own doc comments, which call this out explicitly). Wave 5's tick functions are the
*authoritative-role* computation (randomized decisions included, e.g. `growTrees`'s weighted
selection). `recvsr*`'s real job for a *client* role is different in kind, not degree: **apply a
given, already-decided value directly** (`client.terrain[y][x] = kForestTerrain` in `recvsrgrow`
— no re-invocation of `growTrees`, which would pick a *different* random winner locally and desync
from the server's actual choice). So 6.2 is not "wire the existing tick functions to incoming
messages" — it's a new, distinct category of thin state-application functions, most of which have
no Wave-5 counterpart to reuse.

**Recurring shape — player lifecycle (`rejoin`/`exit`/`disc`/`kick`/`ban`):** near-identical
bodies (print a message, conditionally decrease fog-of-war visibility, mark disconnected/
`seq = 0`, fire a status callback) are a strong candidate for one shared Swift helper parameterized
by reason. **Real, deliberate asymmetry to preserve, not smooth over:** `recvsrplayerexit`
(`client.c:2045-2080`) gates its vis-decrease only on `seq != 0 && testalliance(...)` — it does
**not** check `player != client.player` — while `recvsrplayerdisc`/`recvsrplayerkick`
(`client.c:2082-2154`) add that self-check explicitly. A shared helper needs a parameter for this,
not a single hardcoded condition.

**Resource/pill/base mutation handlers** (`repairpill`/`coolpill`/`capturepill`/`buildpill`/
`droppill`/`replenishbase`/`capturebase`/`refuel`/`grabboat`) — apply-given-value setters against
the existing `Pill`/`Base` model (`GameObjects.swift`), each with a UI status callback. Expected
to be short, mechanical — no oracle needed, same reasoning as the lifecycle handlers.

**Damage/explosion handlers** (`damage`/`smallboom`/`superboom`/`hittank`) — terrain/pill/base
mutation (apply-given-value, not recompute) plus **new evidence directly relevant to open Q14**
(`docs/PLAN.md`): `recvsrdamage`/`recvsrsmallboom`/`recvsrsuperboom` are the actual producers that
insert into `client.explosions` — the `-1`-sentinel, never-transmitted list — gated on
`srX->player != client.player`. This is concrete confirmation (not just the earlier
sendclupdate-side inference from the Wave 6 scope survey) that the never-transmitted list's
producer is exactly these broadcast handlers, for anyone else's action, never the local player's
own. Handing this to PLANNER as additional Q14 evidence, not a resolution by itself.

**`mineack`/`builderack`** — acks for the *local* player's own outstanding builder command, not a
broadcast about another player. Needs checking against `BuilderTick.swift`'s existing
`builderStatus`/`builderTask` model for the natural attachment point before assuming new state is
required.

**`setalliance`/`timelimit`/`basecontrol`/`pause`** — straightforward flag/counter updates, no
recomputation risk.

**`sendmesg`** — chat relay, no `GameState` mutation at all (just text + sender + mask for a UI
layer to render). Design call, flagged for PARITY to audit: this doesn't belong in `BoloKit` —
recommend it as a pure `BoloNet`/app-layer passthrough with nothing to differentially test, rather
than leaving it ambiguous.

**Already done, not 6.2's job:** the *local-effect* halves of `smallboom`/`superboom`/`flood`/
`droppill` (Wave 5.5a, per the original Wave 6 scope survey's Finding 1) and `damage`/`touch`
(Wave 5.3a, server-side `recvcldamage`/`recvcltouch` — a different function pair entirely: server
receiving a client's request, not client receiving a server broadcast). 6.2 must not re-port
either.

**Test plan:** unit tests per handler against hand-built `GameState` fixtures (apply-given-value
checks, not oracle fuzzing — no pure numeric transform here worth a C extract, unlike 6.0/6.1's
physics-adjacent pieces), plus a named regression test for the player-lifecycle asymmetry above.

**Out of scope for 6.2:** tick orchestrator (6.1), session/join/kick/ban/alliance (6.3), transport
(6.4), tracker/NAT-PMP (6.5).

No code changes this entry. Test baseline unchanged: **345**.

> **→ Planner:** Wave 6.2 pre-brief is complete and awaits a GO. The `sendmesg`-doesn't-belong-in-
> BoloKit call and the new Q14 evidence are the two items most worth your attention before GO'ing
> this one — everything else is either mechanical or already covered above.
> **→ Parity:** No action needed yet — no code shipped.

### [IMPLEMENTER] 2026-09-02 — Wave 6.3 pre-brief: server session logic

**Type:** planning (no code this entry)
**Phase:** Wave 6.3
**Blocks:** the Wave 6.3 GO

Written in the same batch as the 6.1/6.2 entries above, same caveat: at Jerod's direct request,
ahead of the normal per-wave GO sequence — `docs/PLAN.md` currently marks 6.3 "blocked on
6.0–6.2."

**Finding, flagged before scope — a real gap in what Wave 6.0 actually delivered.**
`docs/PLAN.md`'s Wave 6.0 row describes the delivered scope as "`CL*`/`SR*` structs,
`CLUpdate`/**preambles**." I did not implement preamble structs — `JOIN_Preamble` (`bolo.h:448`),
`BOLO_Preamble` (`bmap.h:18`), or the tracker's `TRACKER_Preamble`/`TrackerHost`/`TrackerHostList`
(`tracker.h`). Confirmed by grep: no `Preamble` type exists anywhere in `Sources/BoloNet/`. 6.0's
actual commits (`96704cd`/`5c5e47a`) only cover `CLUpdate` + the 20 `CL*`/34 `SR*` structs, and
PARITY's audit (which passed) never checked for preambles because nothing in the pre-brief
promised them — so this isn't a PARITY miss, it's a pre-brief scope gap. This matters for 6.3
specifically: `joinplayerserver()` (`server.c:714-912`) assembles a `BOLO_Preamble` field-by-field
as its core purpose, and `joinclient()` builds a `JOIN_Preamble` to send. Neither has a Swift wire
type yet. **Recommending 6.3 absorb the three preamble struct definitions as codec work**
(mechanically identical to 6.0's `CL*`/`SR*` pattern — pure structs, `sizeof`/`offsetof` oracle
checks, no I/O), done first within 6.3 before its session-logic content, rather than reopening 6.0
or inventing a 6.0.1. This is a recommendation, not a unilateral scope change.
**`docs/PLAN.md`'s Wave 6.0 row text is now on record as inaccurate — I'm not correcting it
myself** (that file is PLANNER's, per `CLAUDE.md`'s role boundary, no carve-out for "obviously
factual" fixes); flagging it here so PLANNER can fix it with full context.

**Scope (D32):** join/kick/ban/alliance + preamble assembly (per the finding above, preambles
first).

**`joinplayerserver()` (`server.c:714-912`) is genuinely mixed — pure decision logic wrapped in
transport plumbing, worth separating cleanly:**
- Pure: version check, password check, `allowjoin` check, ban-list scan (name + IP match), rejoin
  detection (name match among currently-disconnected-but-`used` slots), new-slot selection (first
  never-used slot, else the *oldest* disconnected-but-previously-used slot by `ticks -
  lastupdate`), server-full detection, and the `BOLO_Preamble` field values themselves.
- Not pure, stays out of scope here: `cntlsock` assignment, `writebuf`/`sendbuf` calls,
  `TCP_NODELAY` socket option, `serversavemap()`'s actual byte encoding (a BMAP concern, already
  ported in Wave 4.1 — only the call site is new here).

**`kickplayer()`/`banplayer()`/`removeplayer()` (`server.c:476-612`)** — thin wrappers over
lock/emit/removeplayer/unlock. Pure core: `removeplayer`'s "which onboard pills does this player
own, drop them" computation (`droppills`, already shipped in `MineChain.swift` — 6.3 just calls it
with the right arguments) plus `banplayer`'s ban-list insertion (name + IP, matching
`joinplayerserver`'s ban check above — same data, same struct, worth sharing one Swift type).
Socket close and mutex lock/unlock are 6.4.

**Alliance (`requestalliance`/`leavealliance`, `client.c:6314-6389+`; `recvclsetalliance`,
`server.c:3123-3145`)** — real, non-trivial business logic, not just a bitmask copy: mutual-
consent semantics (a request sets *your* bit for them; it's a live alliance only once *their* bit
for you is also set) drive different UI feedback ("requested" vs. "accepted") and, on acceptance,
a real state cascade — fog-of-war `increasevis` for their tank/pills/bases, refresh calls. The
server side (`recvclsetalliance`) is a trivial accept-and-broadcast with **no** consent-checking of
its own — the negotiation lives entirely client-side. This asymmetry (server never validates
alliance requests) is worth a trap-list note, not an assumed bug to "fix."

**Test plan:** unit tests for slot-selection (rejoin vs. new vs. LRU-eviction vs. server-full), the
ban-list match logic, the alliance mutual-consent state transitions (request → pending →
accepted, and the asymmetric UI-message branch), and `removeplayer`'s pill-drop computation
against `MineChain.swift`'s existing `dropPills`. Plus `sizeof`/`offsetof` layout tests for the
three new preamble structs, matching 6.0's pattern.

**Out of scope for 6.3:** tick orchestrator (6.1), `recvsr*` handlers (6.2), transport/handshake
mechanism (6.4), tracker/NAT-PMP (6.5).

No code changes this entry. Test baseline unchanged: **345**.

> **→ Planner:** Wave 6.3 pre-brief is complete and awaits a GO. Two things need your ruling
> before or alongside that GO: (1) the preamble-structs recommendation above — confirm 6.3 absorbs
> them, or redirect; (2) `docs/PLAN.md`'s Wave 6.0 row text needs correcting to match what 6.0
> actually shipped, since it currently overstates delivered scope.
> **→ Parity:** No action needed yet — no code shipped. Once 6.3 lands, the alliance
> mutual-consent asymmetry (server trusts, client negotiates) and the preamble-struct layout are
> the two things most worth independent re-derivation, same rigor as 6.0's FWIDTH finding.

### [PLANNER] 2026-09-02 — Wave 6.1 GO issued; 6.2/6.3 pre-briefs reviewed and banked

Reviewed all three pre-briefs above, written at Jerod's direct request ahead of the normal
per-wave cadence. **6.1 (tick orchestrator):** clean — GO issued for coding. Design call (plain-
data callbacks, not `BoloNet` wire structs, since `BoloNet` depends on `BoloKit` not the reverse)
is correct per `Package.swift` and stands without a ruling. **6.2/6.3:** sound, no blocking issues,
pre-approved — but per D32's order, their coding GOs wait for 6.1 (resp. 6.2) to close, not issued
now. `sendmesg` living outside `BoloKit` (6.2) is accepted as proposed.

**Ruling on 6.3's flagged gap:** confirmed — Wave 6.0's row overstated delivered scope (claimed
preambles that were never built); corrected in `docs/PLAN.md`, and the three preamble structs
(`JOIN_Preamble`/`BOLO_Preamble`/`TRACKER_Preamble`) are reassigned into 6.3 rather than reopening
6.0. Not a PARITY miss — 6.0's pre-brief never promised preambles, so nothing to re-audit there.
**Q14** gained real corroborating evidence (`recvsrdamage`/`recvsrsmallboom`/`recvsrsuperboom`
confirmed as the actual producers into the never-transmitted explosions list) — no ruling yet,
still deferred to Wave 6's UI phase per the existing entry in `docs/PLAN.md`.

[TO: IMPLEMENTER] Cleared to start Wave 6.1 coding. 6.2/6.3 pre-briefs stand as reviewed — no
need to resubmit when their turn comes, just flag anything 6.1's actual code changes that they
assumed.
[TO: PARITY] No action yet — no code shipped. When 6.1 lands, the basecontrol reset asymmetry is
worth independent re-derivation, same rigor as 6.0's FWIDTH finding.

### [PLANNER] 2026-09-03 — Forward-planning pass: 6.3 re-reviewed clean; 6.4 scope gap found (dgramclient), 6.5 traps flagged early

**Type:** planning — forward review (no GO issued, no in-flight wave touched)
**Phase:** pre-6.4/6.5
**Blocks:** nothing blocking Wave 6.2 (still in progress, untouched by this entry); informs
whoever writes Wave 6.4's pre-brief

At Jerod's request: get ahead of the normal cadence and review Wave 6.3's already-banked
pre-brief more deeply, plus think through 6.4/6.5 sequencing and open design questions before
IMPLEMENTER gets there. Wave 6.2 itself is not reviewed here — still awaiting IMPLEMENTER's
completion report.

**Wave 6.3 re-review: nothing new, stands as already banked.** Re-read the full pre-brief
(`ccb4481`) line by line against `docs/PLAN.md`'s decisions log. The `joinplayerserver()`
pure/impure split, the `kickplayer`/`banplayer`/`removeplayer` split (`droppills` reuse + ban-list
insertion as the pure core, socket close deferred to 6.4), and the alliance mutual-consent
asymmetry (server trusts, client negotiates — a design asymmetry worth preserving, not a bug to
fix, so no D24-style ruling needed) all hold up under a second pass. No gaps found beyond the
preamble-struct reassignment already resolved on 2026-09-02. No change to 6.3's status.

**Wave 6.4 scope gap found: `dgramclient()`'s post-decode logic has no assigned sub-wave.** Wave
6.0's own pre-brief explicitly carved this out of the codec ("stopping before list mutation,
sound playback, vis updates, and the dead-reckoning loop — those belong to 6.1/6.2, not 6.0").
But neither wave that actually landed claims it: **Wave 6.1** shipped as `runclient()`/
`runserver()`'s own tick state machines (pause/timelimit/basecontrol/disconnect) — nothing about
applying another player's incoming `CLUpdate`. **Wave 6.2** is explicitly scoped to the ~33 TCP
`recvsr*` handlers only, a different wire channel from UDP `CLUpdate`. So the actual application
of a *received* `CLUpdate` — other players' shell/explosion list mutation, the sound-flag hooks,
fog-of-war vis updates, and DEEPDIVE1's dead-reckoning re-simulation loop (`client.c:1446-1454`,
already flagged there as needing a Swift-side bound regardless of the C oracle's own unbounded
behavior — a `writeRun`-class safety deviation, not a fidelity fix) — is currently unhomed.

Ruling as **D36**: assign this to **Wave 6.4**, on the same split pattern already used for
`joinplayerserver()` in 6.3 — 6.4's pre-brief should separate the pure part (decode-to-state
application, dead-reckoning math; differentially testable against 6.0's existing
`clupdate_decode_oracle`) from the actual UDP-receive mechanism (Network.framework plumbing),
rather than treating "transport" as one undifferentiated block. Deliberately not folding this into
6.2, even though the "apply a given value" shape matches 6.2's stated design philosophy for
`recvsr*` — 6.2 already has a coding GO in flight, and changing its scope mid-wave risks exactly
the silent scope drift D28/D35 exist to prevent.

**Wave 6.5 traps flagged early, for whoever writes that pre-brief:**
- DEEPDIVE1 documents `TrackerHost`/`TrackerHostList` (`tracker.h:36-56`) as **not**
  `__attribute__((__packed__))`, unlike every other wire struct in the codebase so far
  (`sizeof(TrackerHost) == 60` includes a pad byte before `timelimit`; `sizeof(TrackerHostList) ==
  64`). Every 6.0-era struct assumed packed-with-no-padding; this one is the exception and its
  Swift layout needs to reproduce the same padding deliberately, not by accident of Swift's own
  default struct layout rules.
- The tracker reachability echo (`tracker.c:230-232`, `server.c:639-650`/`1467-1479`): a zeroed
  `CLUpdate` header with `player = 255` must be echoed verbatim by the **server's** UDP receive
  path. This is server-side transport code, so it belongs in **6.4**, even though it only matters
  once 6.5's tracker client exists — flagging now so 6.4's pre-brief doesn't drop the
  `player == 255` sentinel case as unreachable dead code.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — new **D36** in the decisions log; Wave 6.4's row updated to include the
  `dgramclient()` scope and the tracker-echo note; Wave 6.5's row updated to flag the
  `TrackerHost`/`TrackerHostList` packing trap for its own eventual pre-brief.

[TO: IMPLEMENTER] Nothing actionable for Wave 6.2, currently in flight — this doesn't change its
scope. When you get to Wave 6.4's pre-brief: read D36 above first, split `dgramclient()`'s pure
application logic from the receive mechanism the same way 6.3 split `joinplayerserver()`, and
don't drop the `player == 255` tracker-echo case as dead code just because 6.5 hasn't landed yet.
When you get to Wave 6.5: the `TrackerHost`/`TrackerHostList` packing note above is the one thing
most likely to get silently mis-ported if approached the same way as every other (packed) wire
struct.
[TO: PARITY] No action needed — no code shipped this entry, nothing to audit yet.

### [IMPLEMENTER] 2026-09-03 — Wave 6.2 complete: 30 `recvsr*` broadcast handlers

**Type:** coding
**Phase:** Wave 6.2
**Blocks:** nothing — 6.2 done, 6.3 (session logic) is next per D32

Commit `0d44f30`. Implemented against the pre-brief above; three findings changed scope from what
that pre-brief assumed, each surfaced as a design call rather than silently absorbed.

**Finding 1 — `sendmesg`/`timelimit`/`basecontrol` have no `GameState` mutation at all.** The
pre-brief expected "straightforward flag/counter updates" for `timelimit`/`basecontrol`; their
actual bodies (`client.c:3030-3086`, `3088-3135`) are pure UI text formatting ("N Minutes and M
Seconds Remaining!") with no state effect to apply — `client.timelimitreached`/`basecontrolreached`
have no analog because `runTick` (Wave 6.1) already derives the equivalent condition from `ticks`
vs. `timeLimit`/`baseControlThreshold` directly, every tick. **30 functions shipped, not 33** —
`sendmesg` (already flagged in the pre-brief) plus these two, confirmed the same way once their
bodies were actually read.

**Finding 2 — `recvSrCapturePill`'s `sendclgrabtile()` branches are network sends, not direct
mutations.** Two of its terrain-dispatch cases (`.boat`, and every mined-terrain case) call
`sendclgrabtile()` in the real C — the local client *asking the server* to process a grab, not a
direct call to the already-ported `grabTile()`. Calling `grabTile` directly there would re-trigger
a state change the real client never makes on its own — the same class of mistake PLANNER ruled
against for the mine-cascade case (Wave 5.9, per Finding 1's ruling above). Surfaced as
`onRequestGrabTile: (Pointi) -> Void` instead of applied. `drown()`/`superboom()` in the *other*
branches ARE direct local calls in the real C (`if (drown()) ...`, `if (superboom()) ...`) and are
called directly here.

**Finding 3 — `recvSrSetAlliance`'s "left the alliance" branch calls the real `leavealliance()`
(`client.c:6389-6454`), not a one-line bit clear.** I initially wrote a private helper assuming
`leavealliance(1 << player)` just clears one bit — wrong. The real function takes an arbitrary
bitmask of *multiple* players, sends its own `CLSetAlliance` packet, and cascades a further
status-refresh loop over every connected player. Caught this before committing by reading the
full function rather than trusting the shape implied by the call site. Removed the incorrect
helper; surfaced as `onShouldLeaveAlliance: (UInt16) -> Void` instead — the real implementation is
squarely Wave 6.3's `requestalliance`/`leavealliance` scope (already in that pre-brief), not
something safe to duplicate inline here.

**Design call, stated for PARITY to audit:** `recvSrSmallBoom`/`recvSrSuperBoom` do **not** call
`explosionAt`/`superboomAt` (`MineChain.swift`) despite the visible logic overlap (same terrain
crater conversion, same explosion-particle creation, same tank-damage-cascade shape). Those two
functions schedule chain/flood ring-buffer entries as part of being the *authoritative* role's
computation; a receiving client's `recvsrsmallboom`/`recvsrsuperboom` have no such scheduling
anywhere in `client.c` — calling them would silently add scheduling a real client never does, on
top of whatever the authoritative side already scheduled once. Independent, terminal
reimplementations instead, reusing `killSquareBuilder`/`killPointBuilder`/`drown`/`superboom`/
`smallboom`/`killTank` directly (all already-shipped, all operate on `state.localPlayer`
internally, matching their existing call sites elsewhere).

**Finding, flagged for PLANNER, deliberately not fixed here (pre-existing, out of this wave's
scope):** `recvSrDamage`'s pill/base heat logic (`client.c:1540-1577`) resets neither
`Pill.counter` nor `Pill.coolCounter` — confirmed by direct reading, matches `client.c` exactly.
Its server-side sibling `recvcldamage()` (`server.c:2804-2846`, ported as `heatPill`/`applyDamage`
in `ShellTick.swift`, Wave 5.3a) resets `server.pills[pill].counter = 0`. `Pill.coolCounter`'s own
doc comment identifies `server.pills[i].counter` as *its* C analog, not `Pill.counter`'s. If that
mapping is right, `heatPill` has been resetting the wrong field since Wave 5.3a — a real, if
narrow, pre-existing fidelity question, discovered only because writing `recvSrDamage` required
reading both functions side by side. Not touched here: `recvSrDamage` doesn't call `heatPill` at
all (writes its own inline logic matching `client.c` exactly), so this file is correct regardless
of how the `heatPill` question resolves. Recommend PLANNER decide whether this needs its own
tracked item (Wave 5.9-style) or a direct ruling.

**Test baseline: 363 → 408 (+45), all in new `Tests/BoloKitTests/RecvSRTests.swift`.** Covers all
30 functions: player lifecycle (join/rejoin/exit/disc/kick/ban), terrain broadcasts (damage
including the no-counter-reset regression, grabTrees/build/grow/flood/placeMine/dropMine/
dropBoat), pill broadcasts (repairPill/coolPill/capturePill including the boat-tile and
sea-without-boat dispatch branches/buildPill/dropPill), base broadcasts (replenishBase/
captureBase/refuel/grabBoat), local acks (mineAck/builderAck's per-task routing), explosions
(smallBoom/superBoom's terrain+cascade, hitTank), and alliance/pause (the three-way accepted/left/
requested branch, the `onShouldLeaveAlliance` surfacing, `pause`'s 255 sentinel). Two tests
initially crashed the whole test process from an out-of-bounds `localPlayer` (same class of
mistake as Wave 6.1's removed test — `recvSrSmallBoom`/`recvSrSuperBoom` unconditionally read
`state.players[state.localPlayer]` for the tank-damage check, so `localPlayer` must be a valid
index); fixed by using a real, distant player rather than an out-of-range sentinel, matching how
Wave 6.1 resolved the same issue.

No `Package.swift` changes. Build and full suite green before commit.

> **→ Planner:** Wave 6.2 done and committed. Two things need your attention before/alongside a
> close-out: (1) confirm the 30-not-33 function count and the `sendmesg`/`timelimit`/`basecontrol`
> no-mutation finding — this changes what "6.2 complete" means relative to the pre-brief's stated
> scope; (2) the `heatPill`/`Pill.counter` vs `Pill.coolCounter` question above needs a ruling or a
> tracked item, independent of whether 6.2 itself is accepted. `onRequestGrabTile`/
> `onShouldLeaveAlliance` are new callback surfaces Wave 6.3/6.4 should know exist when their turn
> comes — 6.3 already owns `leavealliance` so `onShouldLeaveAlliance` should wire there naturally.
> **→ Parity:** `0d44f30` is ready for audit. Priority: the three scope-changing findings above
> (especially Finding 3 — I want independent confirmation that `onShouldLeaveAlliance`'s bitmask
> and trigger condition match `client.c:2905-3028`'s "left" branch exactly, since I caught my own
> first draft being wrong here), and the `explosionAt`/`superboomAt`-avoidance design call. The
> `heatPill` finding is also worth independently re-deriving from `server.c:2804-2846` vs.
> `client.c:1540-1577` directly rather than trusting this report's reading of it.

### [PLANNER] 2026-09-03 — Wave 6.2 reviewed, sent to PARITY; Q21 opened (heatPill field-mapping question)

**Type:** planning — review + activation
**Phase:** Wave 6.2
**Blocks:** Wave 6.3 coding GO (until PARITY passes 6.2, per D32's order)

Reviewed `0d44f30` (code) + `a5e84b0` (completion report) against the pre-brief (`ccb4481`) and
`docs/PLAN.md`'s decisions.

**Scope corrections: accepted, correctly disclosed rather than silently absorbed.** 30 functions
shipped, not the pre-brief's estimated 33 — `sendmesg` was already flagged as out-of-`BoloKit` in
the pre-brief, and `timelimit`/`basecontrol` turning out to be pure UI text formatting (no
`GameState` mutation, since `runTick` from Wave 6.1 already derives the equivalent condition
directly every tick) is a legitimate finding, not scope creep — matches the pattern of `client.c`
bodies not always matching what a function name implies, same lesson as 6.3's `joinplayerserver()`
split. Findings 2 and 3 (`onRequestGrabTile`/`onShouldLeaveAlliance` surfaced as callbacks instead
of direct calls) are the same discipline PLANNER already ruled on for Wave 5.9 — a receiving
client asking the server to act is not the same as the client acting locally, and inlining the
target behavior here would duplicate logic that already has a correct home (6.3/6.4). Concur with
not inlining `leavealliance()`'s real cascade after catching the first-draft shortcut — exactly
the kind of self-check PARITY exists to also independently verify, not a substitute for it.

**`explosionAt`/`superboomAt` avoidance design call: sound, no ruling needed.** The reasoning
(authoritative-role scheduling vs. a receiving client's terminal reimplementation) is internally
consistent with how Wave 6.0/6.1's role split was already established — not a new architectural
question, just correctly applying the existing one.

**Q21 opened for the `heatPill`/`Pill.counter` finding — not ruled yet.** This is a Wave-5.3a-era
question about which field `heatPill` should reset, discovered incidentally, and it needs
independent field-mapping confirmation against the C source before a fix-now-vs-track ruling makes
sense — that confirmation is PARITY's job (hand-trace `server.c:2804-2846` vs. `client.c:1540-1577`
directly), not something to guess at from this report's reading alone. Logged as **Q21** in
`docs/PLAN.md` rather than pre-judging the answer. Wave 6.2 itself is not blocked by this — the
report is correct that `recvSrDamage` doesn't call `heatPill` and is right regardless.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — new **Q21** in the open-questions table; Wave 6.2's row updated to the actual
  30-function scope and code-complete status; Wave 6's summary row updated to match.

[TO: PARITY] `0d44f30`+`a5e84b0` ready for audit. Priority order: (1) Finding 3 —
`onShouldLeaveAlliance`'s bitmask and trigger condition against `client.c:2905-3028`'s "left"
branch exactly, since Implementer caught their own first draft being wrong here and wants
independent confirmation; (2) the `explosionAt`/`superboomAt`-avoidance design call — confirm no
scheduling gap or double-schedule results from the terminal-reimplementation choice; (3) **Q21** —
re-derive the `Pill.counter` vs. `Pill.coolCounter` mapping independently from
`server.c:2804-2846`/`client.c:1540-1577` and report a verdict either way, even though it's a
Wave-5.3a-era question, not this wave's own code; (4) the 30-vs-33 function count and the
`sendmesg`/`timelimit`/`basecontrol` no-mutation claim — spot-check `client.c:3030-3086`/
`3088-3135` directly rather than trusting the report's reading.
[TO: IMPLEMENTER] Nothing blocking — proceed to Wave 6.3's pre-brief-to-coding-GO once PARITY
passes 6.2, per D32's order. `onRequestGrabTile`/`onShouldLeaveAlliance` are noted for 6.3/6.4 to
pick up; 6.3 already owns `leavealliance` so `onShouldLeaveAlliance` should wire there naturally
per the pre-brief's existing scope.

### [PARITY] 2026-09-03 — Wave 6.2 audit: 2 new findings (superboom self-damage gate, missing tank-status callback), Q21 confirmed

**Type:** audit
**Phase:** Wave 6.2
**Blocks:** Wave 6.3 coding GO, per D32's ordering, pending Planner's ruling on Finding 1

**Standing limitation, stated per protocol:** no Swift toolchain in this environment. This is a
line-for-line hand-trace of `0d44f30` (`Sources/BoloKit/RecvSR.swift`,
`Tests/BoloKitTests/RecvSRTests.swift`) against `Reference/c/client.c`/`server.c`, not a
compile-and-run of the test suite. Implementer's green build remains the authority the code
executes; this is the authority it's correct against the oracle.

**Priority items from `e88ed25`, addressed in order:**

**(1) Finding 3 (`onShouldLeaveAlliance`) — CONFIRMED correct, no discrepancy.** Re-derived
`recvsrsetalliance()` (`client.c:2905-3028`) directly. Trigger condition matches exactly: fires
only when `xor & (1 << localPlayer)` (our alliance bit toward them actually changed) AND our own
alliance bit for them is set AND their new bit for us is now clear — precisely the "left" branch.
`onShouldLeaveAlliance(UInt16(1 << player))` matches `leavealliance(1 << srsetalliance->player)`'s
bitmask exactly (`RecvSR.swift:603` vs `client.c:3005`). Verified the "accepted" and "requested"
branches too: `onPlayerStatusChanged`/`onBaseStatusChanged`/`onPillStatusChanged` firing conditions
(unconditional per matching-owner base/pill, independent of the fog-of-war-gated
`increasevis`/`decreasevis` calls dropped alongside `refresh`) match `client.c`'s `setbasestatus`/
`setpillstatus` calls exactly in both branches (`client.c:2936-2955` accepted,
`client.c:2969-2989` left) — the armour-gated `if` in each pill loop wraps only the fog-of-war
call, not `setpillstatus`, and `RecvSR.swift` correctly reflects that (no armour gate on
`onPillStatusChanged`).

**(2) `explosionAt`/`superboomAt`-avoidance design call — sound in principle, but surfaced a real
bug in execution (see Finding 1 below).** No double-scheduling risk: confirmed `recvsrsmallboom`/
`recvsrsuperboom` (`client.c:2632-2903`) never touch `chains`/flood-test scheduling, matching the
design call. But re-deriving `recvsrsuperboom` from scratch (rather than trusting the "same shape
as recvSrSmallBoom" framing) turned up a real structural divergence — see Finding 1.

**(3) Q21 (`heatPill`/`Pill.counter` vs `Pill.coolCounter`) — CONFIRMED bug, independently
re-derived from four sites, not just the two cited in the report:**
- `GameObjects.swift:16-35` (Pill's own doc comments): `Pill.counter` mirrors C's
  `client.pills[i].counter`; `Pill.coolCounter` mirrors `server.pills[i].counter`.
- `client.c:5073-5117`: `client.pills[i].counter` is used exclusively as the CLIENT fire-cadence
  tally (`counter++`, compared against `.speed`, reset after firing) — confirms it's a different
  variable from the one `recvcldamage` touches.
- `server.c:1209-1217`: `server.pills[i].counter` is used exclusively as the cooldown-degradation
  tally compared against `COOLPILLTICKS` — matches `GrowTrees.swift:150-158`'s `coolPills`
  (Wave 5.7), which already correctly targets `Pill.coolCounter` for this exact C variable.
- `server.c:2821` and `:2844` (`recvcldamage`, the function `heatPill` ports): resets
  `server.pills[...].counter = 0` — i.e., the cooldown tally, which maps to `Pill.coolCounter`.
`ShellTick.swift:73` (`heatPill`) resets `state.pills[index].counter = 0` — the wrong field.
**Real effect, not just a mapping technicality:** taking pill/base shell damage spuriously resets
the pill's in-progress fire-cadence tally (interfering with `PillTick.swift`'s shot timer), while
failing to reset the cooldown-degradation tally that `coolPills` (Wave 5.7) would otherwise
correctly leave alone post-heat — letting an already-halved `.speed` degrade again sooner than the
real game allows. Recommend: one-line fix, `ShellTick.swift:73`'s `.counter = 0` →
`.coolCounter = 0`. Pre-existing since Wave 5.3a, not introduced by 6.2; 6.2's own
`recvSrDamage` doesn't call `heatPill` and is correct regardless (already confirmed in the
completion report and re-verified here directly against `client.c:1531-1626`).

**(4) 30-vs-33 count and `sendmesg`/`timelimit`/`basecontrol` no-mutation claim — CONFIRMED
correct on both counts.** Independently counted 34 `SR*` opcodes in `bolo.h:204-236`; 4 excluded
(`SRHANGUP` unused, `SRSENDMESG`/`SRTIMELIMIT`/`SRBASECONTROL` no `GameState` analog) = 30,
matching `grep -c "^public func recvSr" RecvSR.swift` = 30 exactly. Read `client.c:3030-3086`
(`recvsrtimelimit`) and `:3088-3135` (`recvsrbasecontrol`) directly: both are pure
`asprintf`/`printmessage` text formatting; the only state write in either
(`client.timelimitreached`/`basecontrolreached = 1`) is itself nested inside
`if (client.printmessage)` — i.e., in the real C it doesn't fire at all without a registered UI
callback — and Wave 6.1's `runTick` already derives the equivalent condition from `ticks` every
tick regardless, so dropping it here is correct, not a coverage gap. Also read `client.c:1495`
(`recvsrsendmesg`) directly: confirmed zero `GameState`-equivalent mutation, pure chat relay.

**New Finding 1 (mine), CONFIRMED, not previously disclosed — severity: real behavioral
divergence, not just a missing callback.** `recvSrSuperBoom` applies the local-tank splash-damage
check unconditionally; `recvsrsuperboom()` (`client.c:2709-2868`) does not. Brace-depth-verified
directly: `if (srsuperboom->player != client.player) {` opens at `client.c:2737` (depth 1→2) and
does not close until `client.c:2851` (depth 2→1) — the tank-damage check
(`client.c:2815-2840`, `client.armour -= 20`, the superboom/smallboom/killtank escalation,
`settankstatus()`, `playsound()`) sits **inside** that block, at depth 2, not as a sibling `if`.
`RecvSR.swift:487-530` gates only the explosion-particle creation on
`player != UInt8(state.localPlayer)` (lines 487-512); the tank-damage check (lines 514-530) is
outside that gate and runs unconditionally regardless of `player`. Net effect: when a broadcast
superboom is attributed to the local player (`player == localPlayer` — e.g. the echo of the local
player's own mine detonation, already applied optimistically per the `superboom()` local call,
Wave 5.2b, the same precedent `explosionAt`'s doc comment cites for why `recvsrsmallboom` skips
re-scheduling), the Swift port would incorrectly re-apply/apply local-tank damage a second time,
where the C oracle skips it entirely. **This is not the same shape as `recvSrSmallBoom`** — I
independently brace-traced `recvsrsmallboom()` too (`client.c:2632-2707`) and confirmed its
damage-check (`client.c:2660-2686`) genuinely is a **sibling** `if`, at depth 1, not nested inside
`if (srsmallboom->player != client.player)` — so `recvSrSmallBoom`'s unconditional damage check is
correct, and the pre-brief/completion-report framing of "the same tank-damage cascade shape" for
both functions is the source of the miss: they're structurally different in exactly this one way.
Notably, `MineChain.swift`'s `superboomAt` (Wave 5.5a) already documents this precise asymmetry
correctly in its own doc comment ("gated on `player != state.localPlayer`, this time wrapping the
damage check too... see file header for why that nesting differs from `explosionAt`") for the
authoritative-role twin function (`server.c:4192`) — Wave 6.2 dropped that nesting when
terminally reimplementing the client-broadcast role. No existing test exercises
`recvSrSuperBoom(player: state.localPlayer, ...)` with a tank in range — `RecvSRTests.swift`'s
`recvSrSuperBoomDamagesLocalTankWithinRadiusAndEscalates` uses `player: 1`, never the local
player, so this gap is silently uncovered.

**New Finding 2 (mine), CONFIRMED, not previously disclosed — severity: missing UI-status
notification, not a state-correctness bug.** Neither `recvSrSmallBoom` nor `recvSrSuperBoom`
exposes an `onTankStatusChanged` callback; `client.c` calls `client.settankstatus()`
unconditionally whenever local-tank splash damage is applied in both
(`client.c:2678-2680` smallboom, `client.c:2833-2835` superboom, both inside the respective
damage-check block). This is inconsistent with `recvSrHitTank` and `recvSrMineAck`
(`RecvSR.swift:534-551`, `:385-390`), which correctly model this same C hook for their own
armour/tank mutations — and `settankstatus` is not among the file header's declared
"consistently out of scope" UI callbacks (`printmessage`/`playsound`/`refresh`/`increasevis`/
`decreasevis`), so this reads as an inconsistency, not a considered scoping call. Traced the
omission one level deeper: it's inherited from `MineChain.swift`'s private `applySplashDamage`
helper (Wave 5.5a, `MineChain.swift:315-340`), which has the identical gap — `explosionAt`/
`superboomAt` don't fire it either, though for those the omission is arguably more defensible
since `server.c`'s `explosionat()`/`superboomat()` (Wave 5.5a's ported originals) have no
`settankstatus` analog at all (confirmed via `grep settankstatus Reference/c/*.c` — every hit is
in `client.c`, none in `server.c`). Wave 6.2's `recvSrSmallBoom`/`recvSrSuperBoom` are
independent, terminal reimplementations rather than calls into `applySplashDamage`, per the
design call reviewed and confirmed sound above — so this was an opportunity to add the missing
callback rather than inherit the gap, and it wasn't taken. Recommend a single ruling covering
both the Wave 6.2 sites and the pre-existing Wave 5.5a site.

**Everything else spot-checked line-for-line against `client.c`, no further findings:** player
lifecycle (`recvsrplayerjoin/rejoin/exit/disc/kick/ban`, `client.c:1957-2191` — confirmed the
rejoin pill-status-refresh loop's `setpillstatus` call is correctly unconditional on armour,
matching C's nesting exactly, and confirmed exit/disc/kick/ban really do reduce to the same
`connected=false`/`onPlayerStatusChanged` pair once fog-of-war is dropped); terrain broadcasts
(`recvsrgrabtrees/build/grow/flood/placemine/dropmine/dropboat`, `client.c:1628-1955` — all
switch/case tables match exactly, including `recvSrGrabTrees`'s true "else" branch covering every
non-mined-forest terrain, not just grass); `recvSrDamage` (`client.c:1531-1626`, matches exactly,
no counter reset either field); `recvSrCapturePill`'s terrain-dispatch switch
(`client.c:2251-2354` — every one of the 2 `sendclgrabtile`-deferred cases, the 2 direct-call
cases, and the do-nothing cases matches exactly); pill/base mechanical setters
(`recvsrcoolpill/buildpill/droppill/replenishbase/capturebase/refuel/grabboat`,
`client.c:2234-2547`, all match); `recvSrMineAck`/`recvSrBuilderAck`
(`client.c:2550-2629`, including the 5-way task-to-field dispatch, matches exactly);
`recvSrHitTank` (`client.c:2870-2903`, matches exactly, `onTankStatusChanged` correctly
unconditional); `recvSrPause` (`client.c:1474-1493`, matches exactly).

**D18:** no `Double`/`CGFloat` in `RecvSR.swift` — clean.
**D26:** `-ffp-contract=off` still present, `Package.swift:15` — untouched.
**D28:** test count independently verified: `grep -rc "@Test func\|func test" Tests/` = **408**,
matches the commit message's 363 → 408 (+45) exactly.
**D25/D33:** moot, confirmed — this remains a pure value-application layer, nothing for WinBolo's
architecture to have leaked into.

> **→ Planner:** Recommend **not** closing Wave 6.2 yet. Finding 1 is a genuine behavioral
> divergence (not a disclosed design tradeoff) and should block the close the same way D35 blocked
> 6.1 — recommend a ruling requiring a fix (gate `RecvSR.swift:514`'s damage check behind
> `player != UInt8(state.localPlayer)`, matching `client.c:2737-2851`'s nesting) before Wave 6.3's
> GO, per D32's order. Finding 2 is lower-severity (a missing UI notification, not a state bug)
> but touches both 6.2's two sites and the pre-existing Wave 5.5a `applySplashDamage` site —
> recommend one combined ruling/tracked item rather than two. Q21 verdict: confirmed bug,
> one-line fix, your call whether it's bundled with Finding 2's ruling or tracked separately
> given it's Wave-5.3a-scoped.
> **→ Implementer:** Two things to expect once Planner rules: (1) Finding 1 needs
> `RecvSR.swift`'s `recvSrSuperBoom` damage-check block moved inside the
> `player != UInt8(state.localPlayer)` gate (matching `recvSrSmallBoom`'s *lack* of that gate is
> correct and should NOT change); (2) likely an `onTankStatusChanged` parameter added to both
> `recvSrSmallBoom`/`recvSrSuperBoom` (Finding 2) and possibly `applySplashDamage`
> (`MineChain.swift`) if Planner bundles it. Not fixing either myself per PARITY's report-only
> role — holding for your commits once Planner rules.

### [PLANNER] 2026-09-03 — Q22 opened: dedicated headless server vs. in-process host; research logged

**Type:** planning — research + open question
**Phase:** cross-wave (not Wave 6.2-6.5 specific)
**Blocks:** nothing in-flight; relevant once Wave 6.3/6.4 land or the app-UI phase starts

Jerod flagged a runtime question we'd missed: does the Swift port need a standalone dedicated
server binary, or does the future app (linking `BoloKit`+`BoloNet`) hosting in-process cover it?
Asked for research on what other Bolo implementations did, logged for reference.

**Direct source read of our own oracle settles the easy half.** `Reference/c/` ships **both**,
confirmed by reading the actual files rather than assuming: the Cocoa client
(`Mac OS X/GSXBoloController.m`) calls `setupserver()`/`startserverthread()`/
`startserverthreadwithtracker()` directly from a "Host a Game" panel (in-process hosting, UPnP via
`TCMPortMapper` — the same GPLv3 dependency D32/D34 already rule out), **and** a fully separate,
headless `Dedicated Host` target exists (`Reference/c/Dedicated Host/main.c`, 740 lines) — CLI
flags for map/port/password/tracker/timelimit/hidden-mines/game-type, then a text
`status`/`pause`/`resume`/`allowjoin`/`disallowjoin`/`kick`/`ban`/`unban`/`quit` REPL, driving the
identical locked `server.c` state the Cocoa panel drives. Both are thin frontends over one shared
server core — the same functions Wave 6.3 is currently porting.

**External research (web, cited) shows the same pattern elsewhere in the lineage.** WinBolo's own
manual: a separate `WinBoloDS` dedicated-server program predates client-hosted play; v1.14 added
"Built In Server" support directly in the client specifically to remove the friction of running an
external program, and both options remain available today. LinBolo ships "client & server" from
the same source tree per its own README (not independently verified deeper than that line — GitHub
`robots.txt` blocked a directory-level fetch). The one counter-example is PyBolo, a from-scratch
modern Python rewrite with no in-client hosting at all (separate server app only, thin-client/
authoritative-server split) — weaker precedent for us since it isn't derived from the actual Bolo
codebase lineage. The 1987/1993 original's own internal architecture is undocumented in available
sources — not resolved, and not worth digging further per D3's behavior-only fidelity target.

**Full writeup with citations: `docs/notes/HOSTMODELS.md`** (new file, following the DEEPDIVE1
naming/citation convention). Logged as **Q22** in `docs/PLAN.md` rather than ruled here — this is
a product/scope call for Jerod, not something PLANNER should decide unilaterally. My
recommendation (in that doc, not a ruling): match the lineage's pattern and eventually support
both, since `BoloKit`/`BoloNet`'s existing headless-by-design split makes a companion CLI target
(mirroring `Reference/c/Dedicated Host/main.c`, alongside the existing `BoloGlyphs` CLI target)
close to free once Wave 6.3's session logic and Wave 6.4's transport exist — no architecture
change forced either way.

**Docs updated (committed alongside this entry):**
- `docs/notes/HOSTMODELS.md` — new research note, full findings + sources.
- `docs/PLAN.md` — new **Q22** in the open-questions table, pointing at the new doc.

[TO: IMPLEMENTER] No action needed now — Wave 6.2/6.3/6.4 scope is unchanged by this. Worth a
skim when you get to Wave 6.3/6.4's pre-briefs, since `HOSTMODELS.md` names the same `server.c`
functions those waves are already porting (`kickplayer`/`banplayer`/`lockserver`/`unlockserver`
etc.) and the eventual `BoloHost`-style companion target (if Jerod wants it) would be a thin
consumer of exactly what those waves build.
[TO: PARITY] No action needed — this is a product-scope question, not a parity question.

### [PLANNER] 2026-09-03 — Wave 6.2 PARITY findings ruling: fix all three before Wave 6.3 GO (D37)

**Type:** planning — ruling + handoff
**Phase:** Wave 6.2 → 6.3
**Blocks:** Wave 6.3 coding GO

Ruling on PARITY's Wave 6.2 audit (`1bc2b90`), same precedent as D35: all three findings get
fixed before Wave 6.3 opens, not deferred or tracked separately. Logged as **D37** in
`docs/PLAN.md`.

**Finding 1 (real bug — fix required).** `recvSrSuperBoom` applies local-tank splash damage
unconditionally; the C oracle (`client.c:2737-2851`, brace-depth-verified by PARITY) nests the
entire tank-damage-check-and-cascade block inside `player != client.player`, so a broadcast
superboom attributed to the local player is meant to skip local-tank damage entirely (it was
already applied optimistically when the local player triggered it, Wave 5.2b's precedent).
Concur with PARITY's fix: gate `RecvSR.swift`'s damage-check block the same way. Concur explicitly
that `recvSrSmallBoom`'s *lack* of that gate is correct and must not change — PARITY independently
brace-traced `recvsrsmallboom()` too and confirmed its damage check is a genuine sibling `if`, not
nested. This is not the same shape as superboom, and the pre-brief/report's "same cascade shape"
framing is exactly what caused the miss.

**Finding 2 (missing UI hook — fix required, narrowly).** `recvSrSmallBoom`/`recvSrSuperBoom`
don't fire `onTankStatusChanged` on local-tank damage, unlike `client.c`'s unconditional
`settankstatus()` and unlike `RecvSR.swift`'s own `recvSrHitTank`/`recvSrMineAck`, which already
model this hook correctly. Fix both sites. **Ruling on the pre-existing Wave 5.5a
`applySplashDamage` gap PARITY flagged alongside this: no fix.** PARITY's own trace found
`server.c`'s `explosionat()`/`superboomat()` have no `settankstatus` analog at all (grep-confirmed,
every hit lives in `client.c`) — so `applySplashDamage`'s omission correctly mirrors the
authoritative role it ports, not a gap the way the two `RecvSR.swift` sites are. Recording this
explicitly rather than leaving it silently ambiguous, per PARITY's request for "a single ruling
covering both" — the ruling is: fix the client-role sites only, the server-role site is correct
as-is.

**Q21 (heatPill/Pill.counter — fix required).** Confirmed bug, independently re-derived by PARITY
from four sites (not just the two the original report cited). One-line fix: `ShellTick.swift:73`'s
`state.pills[index].counter = 0` → `state.pills[index].coolCounter = 0`. Real effect, not a
technicality — pill damage was spuriously resetting the in-progress fire-cadence tally while
failing to reset the cooldown-degradation tally `coolPills` (Wave 5.7) expects to own exclusively.
Pre-existing since Wave 5.3a; Wave 6.2's own `recvSrDamage` doesn't call `heatPill` and stays
correct regardless. Removed from `docs/PLAN.md`'s open-questions table (resolved into D37) rather
than left open now that it's confirmed and ruled.

**Session note, same as D35's:** bundling ruling and handoff in one pass given where session
credits stand — Implementer should treat this as both the ruling and the GO to plan and execute
directly, no separate pre-brief-review cycle needed unless the plan surfaces something that
changes scope, in which case log it here as a question per the usual rule.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — new **D37** in the decisions log; Q21 removed from open questions (resolved);
  Wave 6.2's row updated to reflect the audit outcome and the fix-before-6.3 ruling.

[TO: IMPLEMENTER] Read PARITY's Wave 6.2 audit in full (`1bc2b90`, the "### [PARITY] 2026-09-03 —
Wave 6.2 audit" entry) before starting — both bugs are already hand-traced against the C source
there, don't re-derive them. Then plan and execute fixes for all three:
- **Finding 1:** gate `RecvSR.swift`'s `recvSrSuperBoom` damage-check block behind
  `player != UInt8(state.localPlayer)`, matching `client.c:2737-2851`'s nesting exactly.
  `recvSrSmallBoom` is already correct — do not add a gate there.
- **Finding 2:** add `onTankStatusChanged` firing to `recvSrSmallBoom`/`recvSrSuperBoom` when
  local-tank damage is applied, matching `recvSrHitTank`/`recvSrMineAck`'s existing pattern. Do
  **not** touch `MineChain.swift`'s `applySplashDamage` — its omission is ruled correct above.
- **Q21:** `ShellTick.swift:73`, `.counter = 0` → `.coolCounter = 0`.
- Named regression tests for all three per D28, including the specific case PARITY flagged as
  silently uncovered: `recvSrSuperBoom(player: state.localPlayer, ...)` with a tank in range,
  asserting damage is skipped.
- Note before/after test count in your completion report per D28.
- Once committed, tag `[TO: PARITY]` for a fast re-audit of just these three spots (mirroring how
  D35's re-audit was scoped), then `[TO: PLANNER]` to close 6.2 and GO Wave 6.3.

[TO: PARITY] No action needed until Implementer's fix lands — flagging here so the thread is
visible when you pick this back up. Nice independent catch on Finding 1/2 beyond the four items
this session asked you to prioritize — the brace-depth trace on both `recvsrsmallboom`/
`recvsrsuperboom` (not just the one that turned out broken) is exactly the rigor that keeps a
"same shape as X" framing from becoming an unverified assumption.

### [IMPLEMENTER] 2026-09-03 — Wave 6.2 fix: all three D37 findings resolved

**Type:** coding
**Phase:** Wave 6.2 (fix pass, per D37 ruling)
**Blocks:** nothing — all three D37 items resolved; ready for PARITY re-audit, then PLANNER's
Wave 6.3 GO

Commit `682173a`. Fixed all three items D37 ruled must land before Wave 6.3:

**Finding 1 (`recvSrSuperBoom` gating).** `RecvSR.swift`: moved the local-tank damage-check block
(`if !state.players[localPlayer].dead, mag2f(...) <= superboomRadius { ... }`) from a sibling `if`
after `if player != UInt8(state.localPlayer) { ... }` to nested *inside* that block, matching
`client.c:2737-2851`'s actual brace depth. A superboom attributed to the local player now
correctly skips local-tank damage entirely. Also corrected the function's doc comment, which had
previously claimed "the same tank-damage cascade as recvSrSmallBoom" — the exact framing PARITY
identified as the source of the original miss. It now states the nesting asymmetry explicitly and
cross-references `MineChain.swift`'s `superboomAt` doc comment, which already documents the same
asymmetry for this function's authoritative-role twin. `recvSrSmallBoom` itself was untouched
(confirmed correct, unconditional, per PARITY's independent brace-trace).

**Finding 2 (`onTankStatusChanged`).** Added `onTankStatusChanged: () -> Void = {}` to both
`recvSrSmallBoom` and `recvSrSuperBoom`, firing after the `if state.local.armour < 0 { ... }`
escalation block, inside the local-tank-damage-applied branch — matching
`recvSrHitTank`/`recvSrMineAck`'s existing pattern. `MineChain.swift`'s `applySplashDamage` was
**not** touched, per D37's explicit ruling that its server-role omission is correct as-is.

**Q21 (`heatPill` field bug).** `ShellTick.swift`: `state.pills[index].counter = 0` →
`state.pills[index].coolCounter = 0`. Expanded the doc comment to record the bug's history (a
Wave 5.3a field-mapping mistake, confirmed by PARITY from four independent sites) and its real
effect (spurious fire-cadence-tally resets while never resetting the cooldown-degradation tally
`coolPills` expects to own exclusively).

**Tests (D28):** 408 → 413 (5 new, 0 removed, 0 failed).
- `RecvSRTests.swift` (+5): `recvSrSuperBoomCausedByLocalPlayerSkipsLocalTankDamage` — the exact
  case PARITY flagged as silently uncovered pre-fix (`recvSrSuperBoom(player: state.localPlayer,
  ...)` with a tank in range, asserting damage is skipped); plus 4 covering
  `onTankStatusChanged`'s fire/no-fire conditions for both functions.
- `ShellTickTests.swift` (0 new, 2 modified): `applyDamagePillDirectHitHeatsAndDecrementsArmour`
  and `applyDamageResourcedBaseIsDamagedAndHeatsAlliedPillsNearby` previously asserted
  `.counter == 0` — the pre-fix (buggy) behavior. Both fixtures now seed a non-zero
  `coolCounter` and assert `.counter` is left untouched while `.coolCounter` is the field that
  resets to 0.

Build: succeeded. `RunAllTests`: 413 passed, 0 failed, 0 skipped.

[TO: PARITY] Ready for a fast re-audit of just these three spots (`RecvSR.swift`'s
`recvSrSuperBoom`/`recvSrSmallBoom`, `ShellTick.swift`'s `heatPill`), mirroring how D35's re-audit
was scoped.

[TO: PLANNER] All three D37 items are fixed, tested, and committed (`682173a`). Requesting
Wave 6.2 close-out and the Wave 6.3 coding GO, pending PARITY's re-audit above.

### [PARITY] 2026-09-03 — Wave 6.2 D37 re-audit: PASS, all three findings closed

**Type:** audit (scoped re-audit, mirroring D35's precedent)
**Phase:** Wave 6.2 → 6.3
**Blocks:** nothing — clears the way for Planner's Wave 6.3 GO

**Standing limitation, stated per protocol:** no Swift toolchain in this environment — hand-trace
against `Reference/c/`, not a compile-and-run. Scope, per Implementer's `[TO: PARITY]` request:
just the three spots `682173a` touched (`RecvSR.swift`'s `recvSrSuperBoom`/`recvSrSmallBoom`,
`ShellTick.swift`'s `heatPill`), not a full re-audit of all of Wave 6.2.

**Finding 1 (`recvSrSuperBoom` gating) — CONFIRMED fixed.** Re-read the full function
(`RecvSR.swift:493-554`) after the fix. The tank-damage-check block (armour decrement, boat=false,
the `armour < 0` escalation, `onTankStatusChanged`) is now nested inside
`if player != UInt8(state.localPlayer) { ... }` (opens `RecvSR.swift:508`, closes `:553`) —
brace-for-brace matching `client.c:2737` through `:2851`'s structure I traced in the original
audit. The unconditional crater-terrain conversion loop (`:500-506`) correctly stayed outside the
gate, matching `client.c:2719-2734`, which is also outside `recvsuperboom`'s player-check. Cross-
checked `recvSrSmallBoom` (`:433-475`) was left untouched — still a sibling `if`, still
unconditional on `player` — correct, since its C twin (`client.c:2660-2686`) genuinely lacks that
nesting; a gate there would have been a new, wrong divergence in the other direction. New test
`recvSrSuperBoomCausedByLocalPlayerSkipsLocalTankDamage`
(`RecvSRTests.swift`) directly exercises the case I flagged as silently uncovered pre-fix —
`player: 0` == `localPlayer: 0`, tank inside `superboomRadius` of the blast center, asserts
`state.local.armour` stays untouched. Ran the scenario by hand against the new code: `player !=
UInt8(state.localPlayer)` evaluates `0 != 0` → `false`, so the entire block including the damage
check is skipped — matches the assertion. Correct.

**Finding 2 (`onTankStatusChanged`) — CONFIRMED fixed, placement matches C exactly.** Both
functions now take `onTankStatusChanged: () -> Void = {}` and call it as the last statement inside
the local-tank-damage-applied branch, after the `armour < 0` escalation sub-block — matching
`client.c:2678-2680` (smallboom) and `:2833-2835` (superboom), where `settankstatus()` fires
unconditionally within the "hit" block, after the escalation `if`, regardless of whether armour
actually escalated to a kill. For superboom this callback is now correctly *inside* the
player-gate too (since the whole hit-check moved there per Finding 1) — matches `client.c:2833`
being nested inside `:2737`'s gate exactly, independently confirmed via the same brace read as
Finding 1. `MineChain.swift`'s `applySplashDamage` was left untouched, matching Planner's explicit
D37 ruling (its server-role omission mirrors `server.c`'s `explosionat()`/`superboomat()`, which
have no `settankstatus` analog — re-confirmed, no new grep hits there). 4 new tests cover both
functions' fire/no-fire conditions, including the local-player-superboom no-fire case, which
doubles as independent coverage of Finding 1.

**Q21 (`heatPill`) — CONFIRMED fixed.** `ShellTick.swift:73`(-ish, line shifted slightly by the
expanded doc comment) now reads `state.pills[index].coolCounter = 0`, not `.counter`. Matches the
recommended fix exactly. Both call sites (`applyDamage`'s direct-pill-hit and base-splash
branches) go through this one function, so a single-line fix covers both, as expected. Updated
`ShellTickTests.swift` fixtures now seed a nonzero `coolCounter` (`9`) alongside the existing
nonzero `counter` (`5`) and assert `counter` stays `5` (untouched) while `coolCounter` resets to
`0` — a meaningful regression guard against the field swapping back, not just a value change from
the old assertion.

**Test count independently verified:** `grep -rc "@Test func\|func test" Tests/` = **413**,
matches the commit message's 408 → 413 (+5) exactly. All 5 new tests are in `RecvSRTests.swift`;
`ShellTickTests.swift`'s 2 modified tests are not counted as new (correct — same test names,
updated fixtures/assertions).

**No further findings.** Wave 6.2, including the D37 fix, passes parity audit — clean.

> **→ Planner:** All three D37 items independently re-verified against the C oracle, including
> hand-running Finding 1's exact regression scenario against the new code rather than just reading
> it. Recommend closing Wave 6.2 for real and proceeding to Wave 6.3's coding GO.
> **→ Implementer:** Nothing outstanding from this audit. Clear to proceed to Wave 6.3 once
> Planner closes 6.2.

### [PLANNER] 2026-09-03 — Wave 6.2 closed (PARITY PASS after D37 fix); GO for Wave 6.3 coding

**Type:** planning — close-out + GO
**Phase:** Wave 6.2 → 6.3
**Blocks:** nothing

PARITY's re-audit (`d2c8fb0`) is clean — independently re-verified all three D37 items against the
C oracle directly, including hand-running Finding 1's exact regression scenario
(`player == localPlayer`, tank in range) against the fixed code rather than just reading it, and
re-confirming the `applySplashDamage` no-fix ruling holds (no new `settankstatus` grep hits in
`server.c`). No new findings. **Wave 6.2 (`recvsr*` broadcast handlers) is complete and
PARITY-passed** — full chain: `0d44f30`+`a5e84b0` (original, 408 tests) → `1bc2b90` (audit — 2
findings + Q21 confirmed) → `682173a`+`3c180c7` (D37 fix, 413 tests) → `d2c8fb0` (re-audit PASS).
Test count 413, verified independently by PARITY both times.

**Wave 6.3 coding GO issued.** Its pre-brief (`ccb4481`) was reviewed and banked back on
2026-09-02 alongside 6.1/6.2's, and re-checked a second time during the 2026-09-03
forward-planning pass with no gaps found either time — no re-review needed now that 6.2's close
satisfies D32's ordering. Implementer is cleared to start writing session logic (join/kick/ban/
alliance) plus the three reassigned preamble structs directly.

**Housekeeping note, not part of this ruling:** an unrelated, unstaged `README.md` whitespace/
line-wrap edit is sitting in the working tree (not committed by any of the three roles' recent
entries) — left untouched, not this session's to stage or explain. Flagging only so it isn't
mistaken for fallout from this close-out if someone runs `git status` next.

**Docs updated to close 6.2 and GO 6.3 (committed alongside this entry):**
- `docs/PLAN.md` — Wave 6.2 row moved to ✅ Complete — PARITY PASS with the full commit chain and
  test count. Wave 6.3 row updated to reflect the coding GO. Wave 6 summary row updated (6.0/6.1/
  6.2 done, 6.3 in progress, 6.4/6.5 forward-planned only).

[TO: IMPLEMENTER] Wave 6.2 is closed for real, D37 included. **Cleared to start Wave 6.3
coding** — session logic (join/kick/ban/alliance) plus the three preamble structs. Pre-brief
`ccb4481` stands as reviewed; no changes to the plan there. Recall from Wave 6.2's own findings:
`onShouldLeaveAlliance` (surfaced there) wires into this wave's `leavealliance()` naturally. Usual
process: write Swift → build → test → `git add` specific files → commit → completion report in
`AGENT_NOTES.md` → tell Jerod. Log anything ambiguous as a question here rather than resolving
solo.
[TO: PARITY] No action needed until Implementer's Wave 6.3 completion report lands. Good
independent verification on the re-audit — hand-running the flagged regression scenario against
the actual fixed code, not just re-reading the diff, is exactly the rigor this role is for.

### [IMPLEMENTER] 2026-09-03 — Wave 6.3 complete: session logic (join/kick/ban/alliance) + 3 preambles

**Type:** coding
**Phase:** Wave 6.3
**Blocks:** nothing — 6.3 done pending PARITY audit; 6.4 (transport + join handshake, D31/D32/D36)
is next

Commit `388a8c1`. Implemented against pre-brief `ccb4481` (banked 2026-09-02, re-reviewed clean
2026-09-03) — no scope surprises on the pre-brief's own claims, but two new findings surfaced
during implementation, both disclosed rather than absorbed or fixed silently.

**Preamble structs (`Sources/BoloNet/Preambles.swift`):** `JoinPreamble` (`bolo.h:448-452`),
`BoloPreamble` (`bmap.h:18-39`, with its nested `PlayerEntry` roster row), `TrackerPreamble`
(`tracker.h:35-38`) — the three reassigned from Wave 6.0's corrected row. Oracle ground truth
added to `CXBolo` (`netops.c`'s new `preamble_layout_oracle()`, declared in `CXBolo.h`) rather than
trusting `sizeof` alone — `BOLO_Preamble`'s nested per-player array and its `game.domination`
union are real layout traps, both offset-checked explicitly. Caught two build issues while wiring
this up, both fixed before committing: `netops.c` never included `bmap.h`/`tracker.h` (only
`bolo.h`), and `CLUpdateLayoutOracle`'s existing precedent of *duplicating* the oracle struct
definition locally in `netops.c` (that file never includes the public `CXBolo.h` header) had to be
matched for the new struct too, not just declared once in the header.

**`assembleBoloPreamble` (also `Preambles.swift`, `BoloNet`-side since it produces a `BoloNet`
type from a `BoloKit` `GameState`):** ported from `joinplayerserver()`'s field-by-field preamble
build (`server.c:846-873`). Two values the wire needs have no `GameState` analog to read, both
resolved as caller-supplied parameters rather than new stored fields, mirroring `RunTick.swift`'s
own Wave 6.1 precedent (`ticksSinceLastUpdate`) for the same reason: **`seq`** (Wave 6.0's
deliberate exclusion, reaffirmed by `RunTick.swift`'s own disclosure — a real transport layer
would own per-player sequence counters, not `GameState`) and **`mapLength`** (just the byte count
of whatever `BMap.swift`'s Wave-4.1 encoder already produced, not re-derived here).

**Session logic (`Sources/BoloKit/SessionLogic.swift`):** pure decision/mutation core of
`joinplayerserver()`/`kickplayer()`/`banplayer()`/`removeplayer()` (`server.c`) and
`requestalliance()`/`leavealliance()`/`recvclsetalliance()` (`client.c`/`server.c`) — every
socket, buffer, and mutex operation those C functions also perform stays out of scope, Wave 6.4's
concern (D31/D32).

- `evaluateJoinRequest`/`applyJoin`: rejection order matches the C exactly (version → password →
  `allowjoin` → ban list → slot search); slot search is rejoin-by-name-on-a-disconnected-slot >
  first-never-used-slot > oldest-disconnected-slot eviction (`server.c:789-806`'s strict `<`
  comparison keeps the lowest index on a tie — regression-tested explicitly, both the tie case and
  the strict-winner case).
- `kickPlayer`/`banPlayer`: `removeplayer()`'s pure core (onboard-pill bitmask → the already-shipped
  `dropPills`, Wave 5.5a) plus `banPlayer`'s real `cntlsock != -1` guard — banning an
  already-disconnected player is a silent no-op in the C, not an assertion precondition.
  `kickPlayer` has no such guard, matching the C's own asymmetry (not added defensively, per this
  port's established `GameState.localPlayer`-invariant precedent).
- `requestAlliance`/`leaveAlliance`: **this is the real implementation Wave 6.2's `RecvSR.swift`
  surfaced as `onShouldLeaveAlliance` (Finding 3) rather than duplicating** — the two are designed
  to wire together at whatever call site owns both (Wave 6.4's dispatch glue), not inside
  `RecvSR.swift` itself. `increasevis`/`decreasevis`/`refresh`/`client.printmessage` are skipped,
  consistent with the project-wide precedent already established for these exact four calls
  (`TankLocalTick.swift`/`BuilderTick.swift`/`RecvSR.swift`'s own file headers) — fog-of-war and
  screen invalidation are pure rendering concerns, never modeled anywhere in this port.
- `recvClSetAlliance`: the server's role really is a trivial accept-and-broadcast with **no**
  consent-checking of its own — reconfirmed the pre-brief's read, not a bug.

**New `GameState` fields:** `hiddenMines`/`allowJoin`/`passwordRequired`/`serverPassword`/
`bannedPlayers`, following the precedent Wave 6.1 already set (`pauseOnPlayerExit` etc.) of server
config living directly on `GameState` rather than as external parameters. **New `PlayerState`
fields:** `name`/`host`/`address`. `host` mirrors `server.players[i].host` — grep-confirmed the C
source declares this field but **never assigns it anywhere in `server.c`**, so it stays
permanently empty here too, for the same reason (presumably resolved by Objective-C glue outside
`Reference/c/`, not part of the oracle). `address` is a deliberately separate field from `host`,
standing in for `addr.sin_addr` — the ban list's actual security-relevant match key, kept distinct
so a future transport can't accidentally key bans off the spoofable display hostname instead.

**Finding, flagged not fixed — Wave 6.3 scope gap, not mine to absorb.** `server.c` has ~19 more
`recvcl*` handlers (`recvcldamage`, `recvclbuildroad`, `recvclbuildwall`, `recvclbuildboat`,
`recvclbuildpill`, `recvclrepairpill`, `recvclplacemine`, `recvclsmallboom`, `recvclsuperboom`,
`recvclrefuel`, `recvclhittank`, `recvclsendmesg`, `recvcldropboat`, `recvcldroppills`,
`recvcldropmine`, `recvcltouch`, `recvclgrabtile`, `recvclgrabtrees` — the server's TCP receive
side for every `CL*` opcode except `CLSetAlliance`) with no assigned wave anywhere in
`docs/PLAN.md`'s table. Only `recvclsetalliance` was in 6.3's explicit scope (per the pre-brief and
`docs/PLAN.md`'s Wave 6.3 row text), and that's the only one implemented here. This is the same
shape of gap as D36 (`dgramclient()`'s post-decode logic) — surfacing for PLANNER to assign a
wave, not silently absorbing ~19 more handlers into 6.3 or skipping the finding.

**Question, not fixed — a genuine pre-existing unit mismatch spotted while reading `client.c` for
this wave's alliance work, unrelated to anything 6.3 touches.** `server.pause` (ticks, decremented
once per `runTick` call, Wave 6.1) and `client.pause` (raw wire seconds, written verbatim by
`recvsrpause()`, never decremented anywhere in `client.c` — confirmed by grep, it's a pure
truthy/falsy display gate on the real client) are two separate C variables with different units and
different lifecycles. This port merged `client`/`server` into one `GameState.pause` field
(deliberate unification, not a mistake) — but that means `RunTick.swift`'s tick-domain countdown
(Wave 6.1) and `RecvSR.swift`'s `recvSrPause` decode (Wave 6.2, `state.pause = Int(pause)`, no
tick-scaling) write to the *same* field in *different units*, a cross-role hazard in the same
family as D27 even though it's cross-unit rather than cross-caller. Not fixing — pre-existing in
already-PARITY-passed waves, and this wave's own `assembleBoloPreamble` reads `state.pause`
correctly (ticks→seconds, matching `server.c:860-864` exactly) since it's assembling the *server*
role's value. Flagging for PLANNER to rule on whether/how to reconcile, same as Q21's precedent.

**Tests (D28):** 413 → 445 (32 new: 12 differential — preamble layout/round-trip/`assembleBoloPreamble`
— plus 20 unit — join slot-selection incl. the tie-vs-strict-eviction case, kick/ban incl. the
no-op guard, alliance mutual-consent incl. the one-sided-request no-callback case). 0 removed, 0
failed.

Build: succeeded. `RunAllTests`: 445 passed, 0 failed, 0 skipped.

[TO: PARITY] Ready for audit. Two things worth independent re-derivation, same rigor as 6.0's
FWIDTH finding: the `BOLO_Preamble` nested-struct/union offsets (I offset-checked them against the
oracle, but a second read of `bmap.h:18-39` against my `preamble_layout_oracle()` wouldn't hurt),
and the join slot-selection tie-breaking (`evictsOldestDisconnectedSlotOnATie` — I'm confident in
the strict-`<` read of `server.c:789-806` but it's exactly the kind of off-by-one PARITY's
brace/comparison-depth technique is built for).

[TO: PLANNER] Two questions logged above, neither blocking 6.4: (1) the ~19 unassigned `recvcl*`
handlers — same shape as D36, needs a wave; (2) the `server.pause`/`client.pause` unit-mismatch
question — pre-existing, not urgent, but worth a ruling before whatever wave next touches
`RunTick.swift`'s pause countdown or `RecvSR.swift`'s `recvSrPause`.

### [PARITY] 2026-09-03 — Wave 6.3 audit: PASS, no findings

**Type:** audit (full audit of Wave 6.3's scope — preamble structs + session logic)
**Phase:** Wave 6.3 → 6.4
**Blocks:** nothing — clears the way for Planner's Wave 6.4 pre-brief/GO

**Standing limitation, stated per protocol:** no Swift toolchain in this environment — this is a
line-for-line hand-trace against `Reference/c/`, not a compile-and-run. One item below
(`evictsOldestDisconnectedSlotOnATie`) is exactly the kind of check that would ideally be settled
by executing Swift directly; I don't have that tool, so I reasoned it from the stdlib's documented
algorithm and cross-checked against the fact that Implementer's own test of this exact scenario
passed (445/445) — noted explicitly below, not glossed over.

**Preamble struct layouts (`Sources/BoloNet/Preambles.swift`, oracle in `netops.c`) — CONFIRMED
correct.** Independently re-derived every offset in `preamble_layout_oracle()`'s test
(`PreamblesDifferentialTests.testPreambleLayoutMatchesOracle`) by hand from the actual struct
definitions, not by trusting the test's own numbers:
- `JOIN_Preamble` (`bolo.h:448-453`): `ident[8]` + `version`(1) -> `name` at offset 9
  (`MAXNAME`=16, confirmed `bolo.h:57`) -> `pass` at offset 25 (`MAXPASS`=32, confirmed `bolo.h:58`).
  Matches.
- `BOLO_Preamble` (`bmap.h:18-40`): both layout traps checked. The `game.domination` union
  (`bmap.h:26-31`) is itself `__attribute__((__packed__))` and its only member is a packed
  `{type, basecontrol}` pair, and the outer struct is packed too, so the union contributes exactly
  2 bytes with no hidden padding — offsets 13/14 for `dominationType`/`baseControl` check out.
  Per-player entry (`bmap.h:33-38`): `used`(1)+`connected`(1)+`seq`(4, offset 2)+`name[16]`(offset
  6)+`host[32]`(offset 22)+`alliance`(2, offset 54) = 56 bytes/entry — matches
  `sizeofBoloPlayerEntry`. `offBoloMapLen` = 15 + 16x56 = 911, `sizeofBoloPreamble` = 915 — both
  reproduced by hand, not just re-read from the test.
- `TRACKER_Preamble` (`tracker.h:35-38`): correctly noted as **not** `__attribute__((__packed__))`
  in the C, but since both fields are `uint8_t` no natural-alignment padding is possible anyway —
  size 9 is right either way. (This is a different struct from Wave 6.5's flagged
  `TrackerHost`/`TrackerHostList` packing trap — those really do need explicit padding
  reproduction; this one doesn't, and the code doesn't claim otherwise.)
- Field *order* in `BoloPreamble`'s encode/decode (`Preambles.swift:120-166`) matches the C
  struct's declaration order exactly: version, player, hiddenmines, pause, gametype,
  domination.type, domination.basecontrol, players[], maplen. Per-player field order (used,
  connected, seq, name, host, alliance) matches `bmap.h:33-38` too.
- Ident/version constants independently grep-checked: `NET_GAME_IDENT` = `"XBOLOGAM"`
  (`bolo.h:37`), `NET_GAME_VERSION` = `1` (`bolo.h:27`), `TRACKERIDENT` = `"XBOLOTRK"`,
  `TRACKERVERSION` = `0` (`tracker.h:9-10`) — all match `Preambles.swift`'s constants.

**`assembleBoloPreamble` (`Preambles.swift:213-236`) vs. `joinplayerserver()`'s field assembly
(`server.c:846-873`) — CONFIRMED correct**, including the two things worth independently
re-deriving:
- Pause: C does `if (server.pause == -1) bolopreamble.pause = 255; else bolopreamble.pause =
  server.pause/TICKSPERSEC;` — Swift's `state.pause == -1 ? 255 : UInt8(state.pause /
  Int(ticksPerSec))` matches exactly, ternary for ternary. This is also the answer to
  Implementer's flagged `server.pause`/`client.pause` unit-mismatch question, as far as *this*
  wave's own correctness goes: `assembleBoloPreamble` is assembling the server's tick-domain value
  and correctly divides by `TICKSPERSEC`, so it isn't affected by the cross-role hazard it
  flagged — confirmed independently, not just taking the completion report's word for it.
- `gameType` defaults to `0` (`kDominationGameType`, `bolo.h:325`, grep-confirmed) via
  `BoloPreamble.init`'s default parameter, never overridden by `assembleBoloPreamble` — correct
  per the project's existing, prior-audited stance that no other top-level game type was ever
  finished.
- `dominationType` enum mapping (`.open`->0, `.tournament`->1, `.strict`->2) independently checked
  against `bolo.h:334-338`'s `kOpenGame`/`kTournamentGame`/`kStrictGame` enum — matches.
- `PlayerEntry.host` claim re-derived independently, not trusted from the commit message: grepped
  all of `client.c`/`server.c` for `.host` — every `server.players[i].host` occurrence is a *read*
  (`server.c:880`, `:3359`, `:3378`); the only *write* to any `.host` field anywhere is
  `client.players[i].host` (a different struct, `client.c:253`/`733`/`1970`). `server.c` never
  assigns `server.players[i].host` at all. Confirms the claim exactly: this port's `host` field
  staying permanently empty faithfully reproduces a dead field in the oracle, not a gap.

**Session logic (`Sources/BoloKit/SessionLogic.swift`) — CONFIRMED correct against
`server.c`/`client.c`, function by function:**

- `evaluateJoinRequest` (`server.c:714-806`): rejection order (version -> password -> `allowjoin`
  -> ban list -> slot search) matches exactly. Ban-list check re-read against `server.c:772-777`'s
  `strncmp(...MAXNAME) == 0 && sin_addr match` — Swift's full-string `name`/`address` equality is
  equivalent in practice since both fields are already wire-truncated to `MAXNAME` before reaching
  this function (not a divergence, just noting the reasoning).
- Slot search order re-traced against `server.c:772-806` line by line: rejoin (first `used &&
  !connected && name==` match) -> fresh (`first !used && !connected`) -> oldest-disconnected
  eviction. Confirmed the implicit invariant the eviction branch relies on: by the time
  `evaluateJoinRequest` reaches `let disconnected = players.indices.filter { !players[$0].connected
  }`, every filtered index is guaranteed `used == true` — not because the filter checks it, but
  because if any `!used && !connected` slot existed it would have already matched the fresh-slot
  branch above and returned. Same guarantee the C relies on implicitly (its eviction loop also has
  no explicit `used` check). Correct.
- **`evictsOldestDisconnectedSlotOnATie` — the one item flagged for extra scrutiny.**
  `server.c:789-806`'s nested loop keeps the *first-found* champion unless a later candidate's age
  is *strictly greater* (`if (age < server.ticks - server.players[p].lastupdate)`) — so a tie
  keeps the lower index. Swift ports this as
  `disconnected.max(by: { ticksSinceLastUpdate[$0] < ticksSinceLastUpdate[$1] })`. Swift's
  documented `max(by:)` algorithm only replaces the running result when the *current* result
  compares strictly less than the *new* candidate (`areInIncreasingOrder(result, e)`); on an exact
  tie that predicate is false in both directions, so the earlier-encountered element is retained —
  the same "first found, only displaced by strictly-greater" shape as the C's own loop. I can't run
  the compiler here to confirm this directly, but it's corroborated by the passing test itself:
  `SessionLogicTests.swift`'s `evictsOldestDisconnectedSlotOnATie` constructs a genuine tie
  (indices 0 and 2 both at age 100, index 1 excluded as connected) and asserts `player: 0` — since
  Implementer's build reported this test passing (445/445, 0 failed), that's direct empirical
  evidence the real compiled behavior matches the C's tie-breaking, not just my algorithmic
  reasoning about the stdlib. Recording both the reasoning and the corroborating evidence rather
  than asserting confidence from either alone.
- `applyJoin` (`server.c:808-836`, state-affecting lines): rejoin correctly skips the
  alliance-reset/name-set (`server.c:826-828` only runs in the "not a rejoin" branch, matching
  `if !rejoin { ... }`); `used`/`connected`/`address` set unconditionally in both paths, matching
  the C's unconditional "initialize player" block after the if/else. Correct.
- `kickPlayer`/`banPlayer`/`removePlayerPills` (`server.c:475-535`, `585-599`): re-traced the
  *exact sub-step order* in `banPlayer`, since it's easy to get this one subtly wrong — C does
  `addlist` (ban-list insert) **then** `sendsrplayerban` (broadcast) **then** `removeplayer`
  (disconnect + pill drop); Swift's `banPlayer` does `bannedPlayers.append` ->
  `onShouldBroadcastPlayerBan` -> `connected = false` -> `removePlayerPills`, same order. The
  `cntlsock != -1` guard (`banPlayer` has one, `kickPlayer` doesn't) matches the C's own asymmetry
  exactly (`server.c:503-535` vs. `:475-501`, re-read both). `removePlayerPills`'s onboard-pill
  bitmask (`owner == player && armour == pillOnboard`) matches `removeplayer()`'s loop
  (`server.c:590-594`) exactly, including iterating the actual `pills` array rather than a fixed
  `MAXPLAYERS`/16 bound, matching `server.c`'s own `server.npills` bound (pre-existing project
  convention, not new here).
- `requestAlliance`/`leaveAlliance` (`client.c:6314-6389+`): xor-then-mutate ordering matches
  (`xor` computed from the pre-mutation alliance value in both C and Swift, `alliance` mutated
  after). Callback-firing conditions re-traced line by line against both functions: the
  `onPlayerStatusChanged`/`onBaseStatusChanged`/`onPillStatusChanged` calls in the C fire
  *unconditionally* within their respective `if owner == i` blocks — the fog-of-war
  `increasevis`/`decreasevis`/`refresh` calls are separately gated (on pill armour state) but the
  status callbacks themselves are not, and Swift's `for j in ... where owner == i {
  onXStatusChanged(j) }` correctly does not add a gate the C doesn't have. `leaveAlliance`'s lack
  of an "else" branch (only acts when `alliance[i] & (1 << localPlayer) != 0`, silently does
  nothing otherwise — `client.c:6403` has no companion `else`, unlike `requestalliance`'s
  "requested" message branch) is correctly reproduced by Swift's `guard ... else { continue }`
  with no else-branch side effect.
- `recvClSetAlliance` (`server.c:3123-3137`): assign-then-broadcast order matches
  (`server.players[player].alliance = ...` then `sendsrsetalliance(...)`).

**No findings. Wave 6.3 passes parity audit — clean**, across both the newly-added preamble codec
and the session-logic port.

**Two secondary notes, not findings, addressed to Planner:**
1. Implementer's flagged `server.pause`/`client.pause` unit-mismatch question (pre-existing,
   cross-role, not introduced by 6.3) — confirmed above that `assembleBoloPreamble` itself reads
   `state.pause` correctly (server/tick-domain role), so 6.3 isn't contributing a new instance of
   the hazard. The underlying question (should `RunTick`'s tick-domain countdown and
   `RecvSR.swift`'s wire-domain write share one `GameState.pause` field) still needs your ruling,
   independent of this audit passing.
2. The ~19 unassigned `recvcl*` handlers — same shape as D36, still needs a wave assignment;
   nothing for PARITY to check until one lands.

> **-> Planner:** Wave 6.3 clean. Recommend closing it and proceeding to Wave 6.4's pre-brief
> (transport + `dgramclient()` post-decode per D36), per Implementer's own completion report.
> Two secondary items above are yours to rule on, not blocking.
> **-> Implementer:** Nothing outstanding from this audit. The tie-break implementation
> (`evictsOldestDisconnectedSlotOnATie`) is correct as written — flagging above is documentation
> of the verification, not a request for a change.

### [PLANNER] 2026-09-03 — Wave 6.3 closed (PARITY PASS, no findings); D38/D39 rulings; Wave 6.6 pre-brief GO

**Type:** planning — close-out + two rulings + new pre-brief GO
**Phase:** Wave 6.3 → 6.4/6.6
**Blocks:** Wave 6.4's pre-brief GO (on D39's fix); Wave 6.6 is unblocked now

PARITY's Wave 6.3 audit (`f75e1f2`) is clean — full scope covered (three preamble structs +
`assembleBoloPreamble` + session logic), every offset and ordering claim independently re-derived
rather than trusted from the completion report, including explicit extra scrutiny on
`evictsOldestDisconnectedSlotOnATie` (reasoned from the stdlib's documented algorithm and
cross-checked against the passing test, both lines of evidence recorded since no Swift toolchain
is available here to confirm directly). **Wave 6.3 is complete and PARITY-passed.** Full chain:
`388a8c1` (session logic + 3 preambles, 445 tests) → `f75e1f2` (audit, clean). No findings — two
secondary notes only, both ruled on below.

**D38 — the ~19 unassigned `recvcl*` handlers get their own wave, not folded into 6.3 or 6.4.**
Same gap shape as D36: server's TCP receive side for every `CL*` opcode except `CLSetAlliance`
(shipped in 6.3) has no assigned wave anywhere in the table. Assigning to **new Wave 6.6**.
Reasoning on sequencing: this is pure decision/mutation-core work, identical in shape to Wave
6.2/6.3 (no transport dependency — split cleanly from the receive mechanism the same way 6.3 split
`joinplayerserver()`), and Wave 6.4 hasn't started coding yet, so there's no in-flight scope to
disturb by inserting new work ahead of it in the schedule (unlike D36's situation, where 6.2 was
already mid-flight and folding into it risked drift). Recommending Implementer tackle **Wave 6.6
before Wave 6.4** — 6.4's job is to wire real dispatch for incoming `CL*` opcodes, and right now
only `recvClSetAlliance` exists to dispatch to; doing 6.6 first means 6.4 wires a complete
dispatch table instead of a partial one. This is a recommendation, not a hard gate — same latitude
Wave 5.9 got — so if Jerod wants 6.4 first (e.g. to get the transport layer stood up sooner and
treat 6.6 as trailing debt), that's his call to make, not a deviation from process.

**Wave 6.6 pre-brief GO issued.** No open Q/D-log item gates it. Implementer: please write your
own pre-brief directly into this log per the usual two-stage pattern, covering the ~19 handlers
listed in `docs/PLAN.md`'s new Wave 6.6 row. Expect this to read a lot like 6.2's pre-brief in
shape (a batch of "apply the given wire value(s) to `GameState`" functions) — flag anything that
turns out to need real side-channel state (sockets, timers) the way 6.3 flagged `seq`/`mapLength`
as caller-supplied parameters, rather than inventing new `GameState` fields to route around it.

**D39 — `server.pause`/`client.pause` unit mismatch: real fix required before Wave 6.4's pre-brief
GO, not deferred.** This is not a C-oracle bug to replicate bug-for-bug (D24 doesn't apply here —
the C never had this hazard; it's created by this port's own choice to unify `server`/`client`
into one `GameState`). The C has two genuinely separate variables: `server.pause` (ticks,
decremented once per `runTick`, Wave 6.1) and `client.pause` (raw wire seconds, written verbatim
by `recvsrpause()`, never decremented in `client.c` — confirmed by Implementer's grep). Right now
`RunTick.swift`'s tick-domain countdown and `RecvSR.swift`'s `recvSrPause` decode both write
`GameState.pause` in different units. This becomes a live bug the moment one process holds both
roles at once — exactly the in-process-host shape Q22 is already tracking, and Wave 6.4 is where
real transport (and eventually real dual-role hosting) starts landing, so it needs to be closed
before that wave's own pre-brief, same precedent as D35 (fix findings before the next wave opens).

**Fix, for Implementer to plan and execute directly:** split `GameState.pause` into two fields
mirroring the C's own two variables — suggested names `serverPauseTicks` (tick-domain, what
`RunTick.swift` decrements) and `clientPauseDisplaySeconds` (wire-domain, what `RecvSR.swift`'s
`recvSrPause` writes verbatim) — pick better names if you find the C's own naming suggests
something clearer once you're in the code. Update both write sites plus `assembleBoloPreamble`'s
read (PARITY already confirmed it correctly reads the server/tick-domain role — just needs to
point at the renamed field, not a behavior change). Named regression test required (D28) asserting
the two fields are independently addressable — e.g. writing one via `recvSrPause` doesn't perturb
the other's tick countdown, and vice versa. This touches two already-PARITY-passed waves (6.1,
6.2); that's expected and fine, same as D35/D37's precedent for reaching back into prior waves
when a cross-role hazard surfaces later — flag the touched call sites clearly in your completion
report so PARITY knows exactly what to re-check.

**Docs updated to close 6.3, rule D38/D39, and open 6.6 (committed alongside this entry):**
- `docs/PLAN.md` — Wave 6.3 row moved to ✅ Complete — PARITY PASS with commit chain and test
  count (445). Wave 6 summary row updated. New Wave 6.6 row added. D38 and D39 added to the
  decisions table.

[TO: IMPLEMENTER] Two things, in this order:
1. **D39 fix first** — split `GameState.pause` per the plan above, add the regression test, build,
   test, commit, and report here. This must land and get a clean report before Wave 6.4's
   pre-brief GO.
2. **Then write Wave 6.6's pre-brief** (pre-brief GO already issued above — no need to wait on
   anything else to start that write-up) covering the ~19 `recvcl*` handlers in `docs/PLAN.md`'s
   new row. Recommended, not mandated, to sequence 6.6's actual coding before Wave 6.4 — see D38's
   reasoning above; say in your pre-brief if you'd rather do 6.4 first and why.
Log anything ambiguous as a question here rather than resolving solo, as always.

[TO: PARITY] Nothing to audit yet — wait for Implementer's D39 fix completion report (small,
targeted, should be quick to re-audit given how contained it is) and, separately, whatever lands
from Wave 6.6. Good work catching that the pause hazard was still live rather than treating
Implementer's own note as already resolved — that confirmation is exactly why this got a real fix
ruling instead of another deferred note.

### [IMPLEMENTER] 2026-09-03 — D39 fix complete: split `GameState.pause`

**Type:** coding
**Phase:** D39 fix, gating Wave 6.4's pre-brief GO
**Blocks:** nothing on my end — ready for PARITY's fast re-audit, then PLANNER's Wave 6.4 pre-brief
GO

Commit `029c8fc`. Executed per the ruling's exact suggested field names.

**`Sources/BoloKit/GameState.swift`:** replaced `pause: Int` with `serverPauseTicks: Int` (mirrors
`server.pause`, tick-domain, tri-state) and `clientPauseDisplaySeconds: Int` (mirrors
`client.pause`, wire-domain seconds/-1, never counted down anywhere in `client.c` — confirmed by
grep before this fix, reconfirmed now). No call site used the labeled `pause:` init argument
(grep-checked before touching the signature) — every use was post-construction `state.pause = ...`
— so this is a safe rename, not a breaking change for any caller.

**`Sources/BoloKit/RunTick.swift`:** the pause gate (step 1) now checks
`state.serverPauseTicks != 0 || state.clientPauseDisplaySeconds != 0`, not just the renamed server
field. This isn't a mechanical rename — the original gate was unified *specifically* because it
doubled as both `runserver()`'s own tri-state early-return (`server.c:1088-1099`) and
`runclient()`'s `client.pause` truthy early-exit (`client.c:430`). Splitting storage without adding
the second condition would have silently stopped honoring a client-domain pause signal (e.g. this
`GameState` acting as a non-hosting spectator that received an `SRPause` broadcast) — a real
regression, not just a name change. The countdown-and-callback logic only ever touches
`serverPauseTicks`, matching `server.c` exactly (`client.c` never decrements `client.pause`
either). The D35 `pauseOnPlayerExit` write (`state.pause = -1`) is purely server-domain
(`server.c:1192-1197`) → `state.serverPauseTicks = -1`; `onPause(255)` is unaffected, it only ever
reported the broadcast value, never read the field.

**`Sources/BoloKit/RecvSR.swift`:** `recvSrPause` now writes `state.clientPauseDisplaySeconds`,
not `state.pause` — this is the exact write site D39 exists to isolate.

**`Sources/BoloNet/Preambles.swift`:** `assembleBoloPreamble`'s read → `state.serverPauseTicks`.
Same ternary, same `TICKSPERSEC` division — PARITY's Wave 6.3 audit already confirmed this read
was correct for the server/tick-domain role; this is a rename only, not a logic change.

**Tests (D28):** 445 → 447 (2 new, 0 removed, 0 failed). Updated three existing test files'
`state.pause` references to whichever field the scenario actually exercises
(`RunTickTests.swift`/`PreamblesDifferentialTests.swift` → `serverPauseTicks`, since both were
already exercising the tick-domain countdown/preamble-assembly role; `RecvSRTests.swift` →
`clientPauseDisplaySeconds`, since `recvSrPause` is the wire-domain write). New, named regression
tests in `RunTickTests.swift`:
- `runTickServerAndClientPauseFieldsAreIndependent` — writes both fields via `recvSrPause` and a
  direct `serverPauseTicks` assignment, runs one tick, asserts each field only reflects its own
  write (the exact scenario D39 exists to prevent — pre-fix, this would have silently clobbered
  one write with the other's units).
- `runTickGateHonorsClientPauseEvenWhenServerPauseIsZero` — a pure `recvSrPause` write with
  `serverPauseTicks` untouched (`0`) still causes `runTick` to skip the tick, proving the gate's
  added `||` condition is load-bearing, not dead code.

Build: succeeded. `RunAllTests`: 447 passed, 0 failed, 0 skipped.

[TO: PARITY] Ready for a fast, targeted re-audit of the four touched sites (`GameState.swift`'s
field split, `RunTick.swift`'s gate + two write sites, `RecvSR.swift`'s `recvSrPause`,
`Preambles.swift`'s `assembleBoloPreamble` read) — same scope as D35/D37's re-audits.

[TO: PLANNER] D39 fixed, tested, committed (`029c8fc`). Requesting confirmation this unblocks Wave
6.4's pre-brief GO, pending PARITY's re-audit. Wave 6.6's pre-brief follows in the next entry below
— written directly after this one, per your instruction that its write-up needed no further gate.

### [IMPLEMENTER] 2026-09-03 — Wave 6.6 pre-brief: the ~19 unassigned `recvcl*` server handlers

**Type:** planning (no code this entry)
**Phase:** Wave 6.6
**Blocks:** the Wave 6.6 coding GO

Read all 19 handlers in full (`server.c:2059-3123`, everything between `recvclsendmesg` and
`recvclsetalliance` — the latter already shipped Wave 6.3, excluded here) before writing this up,
per the usual rigor. Two findings changed the shape of the expected work from what D38's own
description implied; both surfaced here rather than discovered mid-coding.

**Finding 1 — four of the nineteen are thin wrappers around engine functions already shipped in
Waves 5.3a/5.5a, not fresh ports.** `recvcldamage` (`server.c:2804-3035`) is, line for line, the
same function `ShellTick.swift`'s `applyDamage` already ports — including the documented
`pills[-1]` undefined-behavior deviation (the base-splash branch's pill-heat clamp reads the
*outer* `pill` lookup variable, which is always `-1` in that branch since it only runs when the
earlier `findpill` failed; `applyDamage`'s own header already explains why this isn't replicated
literally and why `pills[i]` — the evidently-intended target — is used instead) and the Q21
`heatPill` counter fix. `recvcltouch` (`server.c:2236-2270`) is `touchTile`. `recvclsmallboom`
(`server.c:3036-3055`) is a one-line call to `explosionat()` → `explosionAt` (`MineChain.swift`).
`recvclsuperboom` (`server.c:3056-3075`) is a one-line call to `superboomat()` → `superboomAt`.
**Nothing new to decide for any of these four** — the real remaining work is a thin
`recvCl*` function that decodes the wire fields (already done by the caller, per every prior
wave's convention), calls the existing engine function directly, and surfaces the `sendsr*`
broadcast trigger as a callback (matching the `onShouldBroadcastX` pattern Wave 6.3 established
for `recvClSetAlliance`). Flagging so nobody re-derives `applyDamage`/`explosionAt` from scratch
under a different name.

**Finding 2 — a genuinely new, valuable trigger-site resolution, independent of Wave 5.9's still-
open gap.** Eight of the remaining handlers (`recvcltouch`, `recvclgrabtile`, `recvclgrabtrees`,
`recvclbuildroad`, `recvclbuildwall`, `recvclbuildpill`, `recvclrepairpill`, `recvclplacemine`,
plus `recvcldamage` itself — nine, correcting my own count on a second pass) call
`explosionat(player, x, y)` when the target square turns out to be a mined variant. `explosionAt`
already has a complete, self-contained signature
(`player:x:y:state:onMineExplosion:onSuperboomTerrain:onDropPills:`) and every one of these call
sites already knows exactly who caused it and where — no callback-vs-direct-call ambiguity the way
Wave 5.9's tank/builder-movement trigger sites still have (those are genuinely unresolved because
nothing at those sites currently tracks causer-player attribution cleanly). **Wave 6.6 can call
`explosionAt`/`superboomAt` directly at these nine sites** — this is good news, not a blocker, and
worth stating plainly: 6.6 becomes the first wave to actually wire real trigger sites for the
mine-cascade engine, independent of and not gated on Wave 5.9.

**Finding 3 — a real oracle bug, needs a ruling before coding (D24 territory).**
`recvclbuildroad` (`server.c:2416`): `if (clbuildroad->trees >= clbuildroad->trees)` — the field
compared to itself, always true. Every sibling does a real threshold check immediately below it in
the same file (`recvclbuildwall`: `clbuildwall->trees >= WALLTREES`; `recvclbuildboat`: no
comparison at all, unconditional; `recvclbuildpill`/`recvclrepairpill`: no gate, armour is just
capped after the fact). This makes `recvclbuildroad`'s tree-cost check dead code — road building
always succeeds regardless of trees paid, the "insufficient trees" `else` branch (`sendsrbuilderack`
with the *unmodified* tree count, `NOPILL`) is unreachable. **Contrast with `applyDamage`'s
`pills[-1]` case:** that one is undefined-behavior-driven (an out-of-bounds C array read with no
deterministic, replicable observable effect), which is why non-replication was the right call
there. This one is fully well-defined and deterministic — replicating it bug-for-bug is entirely
possible (`if trees >= trees` compiles and runs identically in Swift, it's just always `true`).
**Question for Planner:** replicate as `if clbuildroad.trees >= clbuildroad.trees` (obviously
always true, a strange thing to write deliberately but not undefined), or treat this as a
correctable typo (`ROADTREES`, matching every sibling's pattern) under D24's exception path? I
lean toward flagging-and-asking rather than guessing, same as Q21's precedent — this one is more
consequential than Q21 (Q21 was an internal bookkeeping field; this one changes whether road
construction ever costs anything).

**Finding 4 — `recvclsendmesg` and `recvclhittank` are near-stateless relays, may need no
`GameState`-mutating function at all.** `recvclsendmesg` (`server.c:2059-2094`) has zero
`GameState` effect — pure `sendsrsendmesg` broadcast relay, matching Wave 6.2's own prior finding
that `sendmesg`/`timelimit`/`basecontrol` needed no state-mutating function, just a callback at
whatever layer owns dispatch (Wave 6.4's territory, not this one). `recvclhittank`
(`server.c:3101-3122`) is almost the same shape: `if (clhittank->player < MAXPLAYERS)
sendsrhittank(...)` — a bounds check, then relay, no state at all. Proposing to keep this one as a
minimal guard function (`recvClHitTank(player:dir:onShouldBroadcastHitTank:)`, matching
`recvSrHitTank`'s existing shape for parity) rather than skip it entirely, but flagging that it's
nearly trivial. `recvclsendmesg` I'd propose skipping as a `SessionLogic`/`RecvCL` function
entirely, same as `sendmesg` was skipped in Wave 6.2 — surfaced only as a callback at the real
dispatch layer once one exists.

**Everything else (the remaining ~11) is genuinely new pure decision/mutation logic, no surprises
beyond the usual terrain-switch transcription:** `recvcldropboat` (river→boat only, matches
`recvSrDropBoat`'s mirror), `recvcldroppills` (a validation wrapper — every requested pill bit
must actually be owned+onboard by `player`, plus an x/y range sanity check — around the
already-shipped `dropPills`, `MineChain.swift`), `recvcldropmine` (terrain-switch mineification,
matches `recvSrDropMine`'s mirror), `recvclgrabtile` (pill capture + base capture with the same
mutual-alliance three-way branch — neutral/mutually-allied/hostile — Wave 6.2's capture-base logic
already models the shape of, plus a terrain switch for boat-grab), `recvclgrabtrees`
(forest→grass, matches `recvSrGrabTrees`'s mirror), `recvclbuildwall`/`buildboat`/`buildpill`
(construction cost-and-convert, each with its own terrain-eligibility switch),
`recvclrepairpill` (`armour += trees*4`, capped at `maxPillArmour`, refunding excess trees — same
shape as `buildpill`'s cap logic), `recvclplacemine` (terrain-switch mineification, no `sendsrmineack`
success/fail branch the way `recvcldropmine` has — worth a named test distinguishing the two),
`recvclrefuel` (unclamped subtract + an array-bounds guard on `clrefuel->base < server.nbases` —
this is the *authoritative* decision `recvSrRefuel`'s already-shipped client mirror reflects, not
another "apply-given-value" function; matches that mirror's unclamped-subtract behavior exactly,
confirming no new design call needed there). All physics/game constants this needs are already
ported (`roadTrees`/`wallTrees`/`boatTrees`/`forestTreeYield`/`maxPillArmour`/`noPill`,
`Physics.swift`, grep-confirmed) — no new constant work.

**Proposed scope, files, test plan:**
- `Sources/BoloKit/RecvCL.swift` — new file, ~19 functions (minus `recvclsendmesg` per Finding 4),
  same "apply-given-value" design philosophy as `RecvSR.swift` (Wave 6.2) but for the server's
  receive side. Callbacks for every `sendsr*` broadcast trigger, matching the
  `onShouldBroadcastX`/`onXStatusChanged` naming already established.
- `Tests/BoloKitTests/RecvCLTests.swift` — unit tests per function, plus named regressions for:
  the four thin-wrapper functions actually delegating to the real engine calls (not
  reimplementing them), the nine `explosionAt`/`superboomAt` trigger sites firing with correct
  causer attribution, and whichever way Finding 3's bug gets ruled (a test asserting road building
  always succeeds regardless of `trees`, if replicated bug-for-bug; or a test asserting it
  correctly gates on `ROADTREES`, if corrected).
- No new `GameState` fields expected — every one of these 19 functions reads/writes existing
  `pills`/`bases`/`terrain`/`chains` state, the same fields Waves 5.x/6.2/6.3 already touch.

**Out of scope for 6.6:** the actual TCP receive/dispatch mechanism (Wave 6.4), `recvclsetalliance`
(already shipped Wave 6.3), Wave 5.9's tank/builder-movement trigger sites (independent gap, not
this wave's problem to solve even though it now shares a "wire `explosionAt` at a real site"
shape with Finding 2 above).

> **→ Planner:** Awaiting your ruling on Finding 3 (`recvclbuildroad`'s self-comparison — bug-for-bug
> or correct?) before I start coding; everything else above is ready to code as described once you
> GO it. Findings 1/2/4 are disclosures, not blocking questions.
> **→ Parity:** No action needed yet — no code shipped this entry. Once 6.6 lands, whichever way
> Finding 3 gets ruled is the one thing most worth independently re-deriving from the C source
> directly, same rigor as every prior "replicate or fix" call this project has made.

### [PLANNER] 2026-09-03 — Wave 6.6 pre-brief reviewed, coding GO'd (D40 rules Finding 3); D39 fix noted, awaiting PARITY

**Type:** planning — review + coding GO + one ruling
**Phase:** Wave 6.6 (coding); D39 (awaiting re-audit)
**Blocks:** nothing for Wave 6.6; D39 still needs PARITY's re-audit before I issue Wave 6.4's
pre-brief GO

**D39 fix acknowledged, not yet closing it.** Implementer's `029c8fc` report is exactly what I
asked for — the split is real (`serverPauseTicks`/`clientPauseDisplaySeconds`, not a bare rename),
and the report correctly caught that the old unified gate was doing double duty as both
`runserver()`'s tri-state early-return and `runclient()`'s truthy early-exit, so the fix added the
`||` condition rather than silently dropping client-domain pause handling — that's exactly the
kind of "don't just rename, verify the behavior the shared field was accidentally also providing"
check this class of fix needs. I'm not closing D39 or issuing Wave 6.4's pre-brief GO yet — Jerod
says PARITY is already checking this fix, so I'll wait for that re-audit to land before treating
it as done, same as D35/D37's pattern (fix reported ≠ fix verified).

**Wave 6.6 pre-brief (`a5d518d`) reviewed against `docs/PLAN.md`'s decisions and IMPLEMENTER's
non-negotiable rules — clean, no scope creep, coding GO issued.** Notes on what I checked:

- Findings 1/2/4 are disclosures, not decisions I need to make — they change the *shape* of the
  work (delegate to existing engine functions rather than re-port them; wire real trigger sites
  independent of Wave 5.9; skip a function with no state effect) but don't touch any D-log item or
  architectural rule, so no ruling needed there. Agreed with all three as read.
- Finding 3 (`recvclbuildroad`'s `trees >= trees` tautology) is the one real question, and it's
  squarely **D24 territory** — I checked D24's original text before ruling rather than treating
  this as a fresh question. **D40: replicate bug-for-bug.** This is a deterministic, well-defined
  comparison, not undefined behavior (the distinction Implementer itself drew correctly against
  `applyDamage`'s `pills[-1]` case, which *is* UB and rightly wasn't replicated literally), and
  it's not a Swift memory-safety concern — both of D24's stated conditions for "no countervailing
  reason to deviate" hold here exactly as they did for the dead-tank terrain-enum mismatch and
  `growtrees`' guard. The fact that this one is more *visible* (free road-building, not just an
  internal counter) argues for fidelity, not against it — silently correcting it would make this
  port's economy diverge from the oracle it's supposed to match. Named regression test required
  (D28), same as D24's own pattern.

**Wave 6.6 coding GO issued**, covering the full pre-brief scope: `Sources/BoloKit/RecvCL.swift`
(new file, ~18 functions per Finding 4's `recvclsendmesg` exclusion),
`Tests/BoloKitTests/RecvCLTests.swift`, with D40's ruling applied to `recvclbuildroad`. No new
`GameState` fields expected, matches the pre-brief's own claim — flag it here if that turns out
wrong once you're actually in the code.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — D39's row annotated with the fix commit and PARITY-pending status. Wave 6
  summary row updated. Wave 6.6 row updated to Coding GO'd with pre-brief findings summarized.
  D40 added to the decisions table.

[TO: IMPLEMENTER] Cleared to start Wave 6.6 coding per the pre-brief as written, with D40's ruling
on `recvclbuildroad` (replicate the tautology bug-for-bug, named test documenting it's
intentional). Everything else in the pre-brief — the four delegated wrappers, the nine
`explosionAt`/`superboomAt` trigger sites, skipping `recvclsendmesg`, the minimal
`recvClHitTank` — proceed exactly as proposed, no changes. Usual process: build → test →
`git add` specific files → commit → completion report here → tell Jerod.
[TO: PARITY] No new ask from me this entry — continue your D39 re-audit. Once that lands, report
here and I'll close D39 and issue Wave 6.4's pre-brief GO. When Wave 6.6 lands, Finding 3/D40's
`recvclbuildroad` replication is the one thing most worth independently re-deriving from the C
source directly, same as every prior "replicate or fix" ruling this project has made.

### [PARITY] 2026-09-03 — D39 fix re-audit: PASS, clean split

**Type:** audit (targeted re-audit, mirroring D35/D37's precedent)
**Phase:** D39 fix → Wave 6.4
**Blocks:** nothing — clears D39's gate on Wave 6.4's pre-brief GO

**Standing limitation, stated per protocol:** no Swift toolchain in this environment — hand-trace
against `Reference/c/`, not a compile-and-run. Scope, per Implementer's `[TO: PARITY]` request:
the four touched sites (`GameState.swift`'s field split, `RunTick.swift`'s gate + two write
sites, `RecvSR.swift`'s `recvSrPause`, `Preambles.swift`'s `assembleBoloPreamble` read).

**`GameState.swift` — field split confirmed clean.** `pause: Int` replaced by
`serverPauseTicks: Int` / `clientPauseDisplaySeconds: Int`, both defaulting to `0`. Grepped all of
`Sources/` for any leftover `state.pause`/`.pause =` reference that should have moved to one of
the two new fields — none found; every remaining `.pause` hit is either a doc comment, the
unrelated `SRPause`/`BoloPreamble.pause` wire-struct field (a `UInt8`, a different type
entirely), or `pauseOnPlayerExit` (a different field, unaffected by this split). Confirms the
rename touched every call site, not just the ones the commit message narrates.

**`RunTick.swift` gate — re-derived against both C functions it doubles for, not just re-read.**
- `runserver()` (`server.c:1088-1099`): `if (server.pause) { if (server.pause > 0) { countdown +
  sendsrpause on second boundary }; SUCCESS }` — early-exits on any nonzero value, counts down
  only the positive case.
- `runclient()` (`client.c:430`): `if (... || client.pause) { SUCCESS; }` — early-exits on any
  nonzero `client.pause`, with **no** countdown anywhere in `client.c` (confirmed by the same grep
  Implementer already ran, re-run independently: no `client.pause--` or `client.pause -= ` hit
  anywhere in `client.c`).
- The new Swift gate `if state.serverPauseTicks != 0 || state.clientPauseDisplaySeconds != 0`
  correctly unions both early-exit conditions — this single-process port models both roles
  simultaneously, so either domain signaling pause must skip the tick, matching what the *old*
  unified field already did by construction (any nonzero value, regardless of which role wrote
  it, triggered the old gate too) — the split doesn't change gate behavior, only which field
  the countdown touches. Countdown block still reads/writes `serverPauseTicks` only — correct,
  since `client.pause` is never decremented in the C. Traced the `-1`
  (indefinite) case explicitly: `serverPauseTicks == -1` still satisfies `!= 0`, enters the gate,
  fails `> 0`, skips the countdown, returns — identical to pre-split behavior, confirmed by the
  unchanged `runTickIndefinitePauseSkipsEverything` test still passing under the new field name.
- Traced the case the two new regression tests exist for by hand: `clientPauseDisplaySeconds` set
  via `recvSrPause`, `serverPauseTicks` left at `0` — gate correctly still triggers (via the `||`),
  proving a non-hosting client honors a received `SRPause` broadcast even with no server-domain
  countdown running. This is real, not incidental: pre-fix (single field), this exact scenario
  would have set the *shared* field to a **wire-seconds** value that the countdown logic would
  then have misinterpreted as a **tick count** on the next call — D39's whole reason for existing.
- `state.pauseOnPlayerExit` path (`server.c:1192-1197`): `state.pause = -1` → `state.serverPauseTicks
  = -1`, correctly server-domain only (`server.pauseonplayerexit` is a `server.c`-only mechanism,
  re-confirmed at `server.c:1192`), `onPause(255)` untouched (it only ever reported the broadcast
  value argument, never read the field itself — re-checked, correct).

**`RecvSR.swift`'s `recvSrPause` (`client.c:1474-1493`) — confirmed correct.** Re-read
`recvsrpause()` in full: `srpause->pause == 255 → client.pause = -1; else → client.pause =
srpause->pause` — no `TICKSPERSEC` scaling anywhere in this function (confirmed — it's a raw wire
copy). Swift's `state.clientPauseDisplaySeconds = (pause == 255) ? -1 : Int(pause)` matches
exactly, and correctly does **not** apply any tick conversion — the wire value already *is* the
display-seconds unit `client.pause` uses. Writing to `clientPauseDisplaySeconds` rather than
`serverPauseTicks` is the one-line change D39 exists for, confirmed at the write site itself, not
just the field name.

**`Preambles.swift`'s `assembleBoloPreamble` — confirmed correct, matches my own Wave 6.3 audit's
prior finding.** `server.c:860-864`'s `bolopreamble.pause` assembly reads `server.pause` (the
tick-domain variable) and divides by `TICKSPERSEC` — this is the server's own outbound field,
never `client.pause`. Swift's `state.serverPauseTicks == -1 ? 255 :
UInt8(state.serverPauseTicks / Int(ticksPerSec))` now points at the correctly-renamed field, same
ternary, same division, as I already confirmed independently in the Wave 6.3 audit (`f75e1f2`)
before the split existed — this is a rename-only change, not a new logic path, and I re-derived
that it still is one.

**Tests independently re-verified.** `grep -rc "@Test func\|func test" Tests/` = **447**, matches
the commit message's 445 → 447 (+2) exactly. Both new tests
(`runTickServerAndClientPauseFieldsAreIndependent`,
`runTickGateHonorsClientPauseEvenWhenServerPauseIsZero`) hand-run against the diff, not just
read: the first writes both fields via distinct paths (`recvSrPause` for
`clientPauseDisplaySeconds`, direct assignment for `serverPauseTicks`) and asserts each is
unperturbed by the other's tick — matches; the second isolates the gate's `||` as load-bearing by
zeroing `serverPauseTicks` entirely — matches. The three pre-existing tests whose field references
were renamed (`RunTickTests.swift` x4 occurrences, `RecvSRTests.swift`, `PreamblesDifferentialTests.swift`
x2) were spot-checked to confirm the rename didn't also silently change which field a given
scenario exercises — none did.

**No findings. D39's fix passes parity audit — clean.**

**Note on session timing, not a finding.** Mid-audit, `docs/PLAN.md` briefly carried an unstaged,
uncommitted edit (a concurrent PLANNER-role session's in-progress work referencing a Wave 6.6
coding GO and a new D40 ruling) — it landed and committed cleanly as `44ee11d` before this entry
was written, so no action needed; noting only because it was visible via `git diff` partway
through this audit and is worth knowing this session and that one were interleaved on the same
tree just now.

> **→ Planner:** D39's fix (`029c8fc`) independently re-verified clean — the gate union, the two
> write sites, and the preamble read all correctly separate tick-domain from wire-domain, and I
> re-derived (not just re-read) why the gate's `||` is necessary rather than a defensive
> no-op. Wave 6.4's pre-brief GO is unblocked on this item.
> **→ Implementer:** Nothing outstanding from this audit.
