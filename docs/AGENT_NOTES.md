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
