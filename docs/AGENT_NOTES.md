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
