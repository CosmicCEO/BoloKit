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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, all of Wave 6 (6.0–6.3, the D39 fix, 6.6, 6.4a/6.4b/6.4c, 6.5a/6.5b, and the Wave 6 phase close-out), all of Wave 7 (7.0–7.3, the full v1 vertical slice, D58–D89), and Milestone B's D90–D93 pre-Milestone-B rulings through B.0–B.5b (all closed, PARITY PASS) plus B.5c's pre-brief (D94–D99, up to but not including D100's coding-GO ruling, which opens the active log) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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

## Active Log (from D100)

> **Archived 2026-09-05 (Wave 7 pass):** Wave 7's entire v1 vertical slice (7.0 asset pipeline, 7.1
> Xcode app target, 7.2 rendering, 7.3 input/tick loop — D58 through D89, including every
> pre-brief, completion report, and PARITY audit/re-audit in that span) compressed into
> `docs/notes/archive.md`.
>
> **Archived 2026-09-05 (Milestone B pass):** D90 through D93's pre-Milestone-B process rulings,
> and Milestone B's B.0 through B.5b (all closed, PARITY PASS) plus B.5c's pre-brief (D94 through
> D99, every pre-brief, completion report, and PARITY audit/re-audit in that span) also compressed
> into `docs/notes/archive.md`. Full uncompressed entries preserved in git history per D28. The
> active log below now begins at **D100** (B.5c's coding GO — the dynamic-producer extension
> approved, the mine-chain causer-threading gap split out to B.5d).

### [PLANNER] 2026-09-05 — D100: B.5c coding GO'd (dynamic-producer extension approved, mine-chain gap split to B.5d)

**Type:** ruling (D100), coding GO
**Phase:** Milestone B, sub-wave B.5c — GO'd for items 1-5; B.5d created, not pre-briefed

**(1) Dynamic per-connection producer — approved without reservation.** Producer *count* was never
the load-bearing part of D95/D96's safety property; "exactly one consumer ever mutates `state`" is,
and that holds regardless of how many I/O-only producers feed the merged stream. This generalizes
cleanly, not a new risk to weigh.

**(2) Bringing the 9-callback scope back for a re-rule, rather than either silently narrowing or**
**unilaterally attempting the causer-threading refactor, was exactly the right call.** My original
"fold all 9 into B.5c" ruling was made without this depth — correcting it now that real tracing
shows three of them are a different, older, bigger problem (a signature change across three
already-shipped/tested files, with a broadcast mapping that's never been decided at any layer since
Wave 5.5a) than "wire a callback to an existing struct." Same standard this project has applied
every time a ruling turns out incomplete: say so and re-rule, don't guess what would have been
wanted. Split into new **B.5d**, not yet pre-briefed.

**Coding GO issued for B.5c's items 1-5.**

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — D100 added, Milestone B's row
updated (B.5c GO'd, B.5d created).

[TO: IMPLEMENTER] Coding GO for B.5c items 1-5, exactly as proposed. Good instinct bringing the
scope question back rather than resolving it either direction on your own — this is precisely the
kind of thing to flag, not silently absorb or silently defer past. B.5d gets its own pre-brief when
you get to it, no rush.
[TO: PARITY] Heads up for whenever B.5c lands: the dynamic-producer extension to D95/D96's
architecture is approved but worth its own verification (does a producer genuinely stop cleanly on
disconnect/hangup, no leaked Task) — same standard as B.5a/B.5b's concurrency claims.

### [IMPLEMENTER] 2026-09-05 — B.5c items 1-5 landed; one real pre-existing bug found (not fixed yet)

**Type:** completion report + one flagged finding, held out of this commit
**Phase:** Wave 7 / Milestone B, sub-wave B.5c
**Commit:** `8ca6567`

## What landed

1. **`receiveAndDispatchOneHostMessage` split** (`HostSession.swift`) into `receiveOneHostMessageBytes`
   (I/O-only) and `dispatchHostMessage` (pure decode+dispatch, `await`s only into `table` at the
   end). `receiveAndDispatchOneHostMessage` itself is now a thin wrapper — verified all 24 existing
   `HostSessionTests.swift` call sites pass unchanged, confirming the extraction is behavior-preserving.
2. **Dynamic per-player producer `Task`** (`HostGameEngine.swift`), spawned from `.newConnection`'s
   handling once `processJoinAttempt` returns `.accepted` — generalizes D96's three-fixed-producers
   shape per your approval (`1b85dab`). Loops `receiveOneHostMessageBytes`, yields `.clMessage`/
   `.clConnectionEnded` into the same merged stream.
3. **`.clMessage`/`.clConnectionEnded` wired** in the consumer: dispatch + flush, `.hangUp` ->
   `handlePlayerDisconnect(.normal)`, a thrown decode/read error -> `.abnormal`. A dispatch-level
   decode failure (framing-correct bytes, logically invalid) is treated the same as a dead
   connection rather than silently ignored.
4. **`onPlayerDisconnected` wired** in `tick()` — the narrow two-step action (`sendToAllExcept`
   `SRPlayerDisc` + `table.disconnect`), deliberately NOT a call to `handlePlayerDisconnect` itself
   (would double-fire `removePlayer`'s drop-pills logic, since `RunTick.swift`'s own step 4 already
   ran it).
5. **5 callbacks confirmed correctly unwired** (`onExplosion`/`onSuperboom`/`onSmallboom`/`onSpawn`/
   `onPlayerLagStatusChanged`) — no code change, just settled per the pre-brief's source-reading.

**4 new regression tests**, each confirmed via negative control (disabled the relevant wiring,
confirmed the test fails; restored, confirmed byte-identical via `git diff`, confirmed passing
again): a real dispatched `CL*` message mutating state, hang-up disconnect, connection-close
disconnect, and lag-timeout disconnect via the tick timer.

## A real, pre-existing bug found (not part of this commit, not fixed yet)

While stabilizing the connection-close disconnect test, hit real flakiness — not in any of my new
code, traced to a genuine, disclosed-nowhere-until-now defect in `HostListener.swift`'s
`runJoinHandshake` (Wave 6.3/B.5a, well before B.5c): the `.accepted` branch's own `catch` (lines
245-248) on a preamble/map-send failure calls `table.disconnect(player)` but **never undoes
`applyJoin`'s `state.players[player].used/connected = true`**. Confirmed deterministically with a
standalone scratch test (cancel the client connection immediately after sending the join preamble,
no wait): result was `table.isConnected(1) == false` but `state.players[1].used == true,
connected == true` — **permanently** (nothing before B.5c ever read a connection this table had
already forgotten, so the leak was real but unreachable until my dynamic producer existed to
expose it). In production this would permanently occupy a `GameState` slot as
used-and-supposedly-connected with no real connection ever attached to it again — `runTick` keeps
simulating a tank nobody controls, and (per `evaluateJoinRequest`'s own rejoin logic) the slot
would need to be `used && !connected` to ever become rejoin-eligible again, which it never
reaches.

**Not something I'm fixing solo** — this is already-closed B.5a-era code, and the right fix
depends on a call I don't think is mine to make unilaterally: `removePlayer(player:state:)`
resets `connected` but deliberately leaves `used` (matching the C reference's own "used-but-
disconnected slots are rejoin-eligible" model) — calling it in that `catch` branch looks like the
right shape, but I have not found any real C-side precedent for "preamble/map send fails mid-
handshake" to transcribe from (the C reference's own async buffered-I/O model doesn't have an
equivalent synchronous failure point) — this port's own synthesis, not a transcription, same as
`RunTick.swift`'s own header discloses for its server/client interleaving order. Also: no
`SRPlayerDisc`/`SRPlayerExit` broadcast should fire here — `SRPlayerJoin`/`SRPlayerRejoin` is only
sent *after* a successful map send, so no other player has learned this slot exists yet;
`handlePlayerDisconnect` itself would be the wrong tool for that reason alone even before the
`used`-reset question.

My own affected test (`hostGameEngineDisconnectsAPlayerAbnormallyWhenConnectionCloses`) was
actually just carrying a wrong assumption of its own -- I fixed that separately, not by touching
the bug: it was cancelling the connection right after `table.isConnected(1)` became true, but that
signal fires (`HostListener.swift:230`) *before* the preamble/map send this bug lives in, and
before `.accepted` is even returned / my own producer spawned. Waiting for a real dispatched `CL*`
message's effect first (proving the join fully completed and my producer is actually running)
before testing *my own* disconnect handling avoids the unrelated join-handshake failure window
entirely -- confirmed stable across 10 repeated runs of the full `hostGameEngine` filter plus 3
full-suite runs after this fix, zero flakes.

## Verification

- `swift build --build-tests`: clean.
- `swift test --filter "hostGameEngine"`: 10/10 pass, 10 consecutive full runs, zero flakes.
- Full suite, 3 consecutive runs: **171 DifferentialTests + 483 BoloKitTests = 654**, up from 650
  (+4, matching the new tests). All pass, all 3 runs.

## Scope check

Touched exactly `Sources/BoloNet/HostSession.swift`, `Sources/BoloNet/HostGameEngine.swift`,
`Tests/DifferentialTests/HostGameEngineTests.swift`. Did not touch `HostListener.swift` (where the
found bug lives — deliberately left alone pending your ruling), `RunTick.swift`/`MineChain.swift`
(B.5d's territory), `README.md`, or the three Director-owned untracked files.

> **→ Planner:** B.5c items 1-5 landed clean at `8ca6567`, full suite 654/654, stable across
> repeated runs. One real bug found in already-closed B.5a-era code (`HostListener.swift`'s join
> slot-leak on send failure, detailed above) — proposing `removePlayer` in that `catch` branch
> (resets `connected`, deliberately leaves `used` for rejoin-eligibility) as the likely fix shape,
> but not touching it myself since it's outside this sub-wave's file scope and touches join-
> handshake semantics from a different, already-closed wave. Your call on whether this needs its
> own D-number/ruling or a quick go-ahead to fix in a follow-up commit.
> **→ Parity:** worth specifically re-deriving the join slot-leak independently (the scratch-test
> repro shape is in the report) before trusting my read, and confirming the `dispatchHostMessage`
> split is truly behavior-preserving against all 24 `HostSessionTests.swift` cases, not just that
> they still pass.

### [PLANNER] 2026-09-05 — D101 ruled (join slot-leak, pre-existing B.5a-era bug); fix assigned within B.5c

**Type:** ruling (D101), fix assigned
**Phase:** Milestone B, sub-wave B.5c — not closed, D101 required first

Same shape as D77's precedent: a real, pre-existing defect from an already-closed earlier wave,
only reachable now that this wave's own work (the dynamic producer) exercises the path — required
before this wave closes, not by reopening B.5a's close. The proposed fix (`removePlayer`, no
broadcast) is exactly right: `removePlayer`'s used-preserving/connected-resetting shape already
matches the reference's rejoin-eligibility model, and no broadcast is correct since `SRPlayerJoin`
never fired for this connection. Good instinct disclosing rather than silently fixing across a
wave-scope boundary, and equally good instinct not treating "outside B.5c's file list" as a reason
to leave a real bug unfixed once found.

**Required before B.5c closes.** IMPLEMENTER may touch `HostListener.swift`.

[TO: IMPLEMENTER] D101 approved as proposed — land it as a follow-up commit within B.5c. Report
before/after test counts as usual.
[TO: PARITY] Heads up for your eventual B.5c audit: independently re-derive the slot-leak repro
(don't just trust the scratch-test description) and confirm `dispatchHostMessage`'s split is truly
behavior-preserving against all 24 existing `HostSessionTests.swift` cases.

### [PLANNER] 2026-09-05 — D101 fix reviewed, PARITY activated for all of B.5c

**Type:** review, PARITY activation
**Phase:** Milestone B, sub-wave B.5c — items 1-5 (`8ca6567`) + D101 (`47e9c09`+`25bce0f`) landed,
pending PARITY

Reviewed `47e9c09` directly — exactly the approved shape: `removePlayer` before `table.disconnect`,
no broadcast, well-cited. Full suite 655/655. Activating PARITY for the whole sub-wave now that both
pieces have landed.

[TO: PARITY] B.5c ready for audit: items 1-5 at `8ca6567`+`82068fc`, D101 at `47e9c09`+`25bce0f`.
Priorities: (1) the join slot-leak repro and fix, independently re-derived, not trusted from the
report; (2) `dispatchHostMessage`'s split is truly behavior-preserving against all 24 existing
`HostSessionTests.swift` cases; (3) the dynamic per-connection producer Task genuinely stops on
disconnect/hangup with no leak (D100's own follow-up ask); (4) `onPlayerDisconnected`'s narrow wiring
doesn't double-fire pill-drop/broadcast logic `RunTick` already did; (5) full test count (expect
655). Same scope guardrail as always: one `[PARITY]` entry, no `docs/PLAN.md` edits, no closing, no
GO. `README.md`/`CLAUDE.md` are Jerod's own edits if either shows modified — leave untouched.
[TO: IMPLEMENTER] Clean landing on both. Nothing further needed until PARITY reports back.

### [IMPLEMENTER] 2026-09-05 — D101 fix landed (join slot-leak)

**Type:** completion report
**Phase:** Milestone B, sub-wave B.5c — D101 (required before close)
**Commit:** `47e9c09`

## What landed

Exactly as ruled: in `HostListener.swift`'s `runJoinHandshake`, the `.accepted` branch's `catch`
on a preamble/map-send failure now calls `removePlayer(player:state:)` before `table.disconnect`.
Resets `state.players[player].connected = false`; deliberately leaves `used = true`, matching the
reference's own "used-but-disconnected slots are rejoin-eligible" model. No broadcast — `SRPlayerJoin`/
`SRPlayerRejoin` never fired for this connection, so nothing to tell anyone about.

Added `processJoinAttemptOnSendFailureRevertsConnectedButPreservesUsed` to `HostListenerTests.swift`,
directly exercising `processJoinAttempt` (no `HostGameEngine` needed) — fully cancels the peer
connection and waits for real `.cancelled` state before calling `processJoinAttempt`, so the
preamble/map send is guaranteed to fail deterministically, not racing against timing. **Negative
control:** reverted the fix, reran — failed exactly as expected (`connected` read `true` instead of
`false`); restored, confirmed byte-identical via `git diff`, reran clean.

## Verification

- `swift build --build-tests`: clean.
- `swift test --filter "HostListenerTests"`: 7/7 pass (6 pre-existing + 1 new).
- Full suite, 3 consecutive runs: **172 DifferentialTests + 483 BoloKitTests = 655**, up from 654
  (+1, matching the new test). All pass, all 3 runs, no flakes.

## Scope check

Touched exactly `Sources/BoloNet/HostListener.swift` and `Tests/DifferentialTests/HostListenerTests.swift`
— the two files D101 authorized. Did not touch `HostGameEngine.swift`/`HostSession.swift` (B.5c's
already-landed items 1-5, untouched), `README.md`, or the three Director-owned untracked files.

> **→ Planner:** D101 landed at `47e9c09`, full suite 655/655, stable across 3 runs. B.5c items
> 1-5 (`8ca6567`) plus D101 (`47e9c09`) together — from my side, B.5c looks complete and ready for
> your close/PARITY activation, no other open items.
> **→ Parity:** the regression test's own determinism claim (`.cancelled` state before calling
> `processJoinAttempt`, not just calling `cancel()` and hoping) is worth re-deriving independently
> — confirm it isn't secretly still timing-dependent.

### [PARITY] 2026-09-05 — B.5c audit (`8ca6567`+`82068fc`+`47e9c09`+`25bce0f`): D101 fix and dispatch split both PASS, real new finding on `HostGameEngine.stop()`'s teardown

**Type:** post-commit audit. **Toolchain:** `swift` present (`swift-driver 1.168.6`, Swift 6.4) —
every claim below is execution-verified (built, ran, and for the two highest-priority items,
negative-control- or scratch-test-proved), not a hand-trace-only pass. **Concurrency note:**
`README.md` sits modified-uncommitted throughout (Jerod's own edit, pre-existing at session start)
— untouched by me, confirmed by `git diff --stat` before and after this session shows only that
file. `.claude/`, `Resources/`, and the three Director-owned docs artifacts left alone too.

**Verdict: not a clean PASS.** Both of PLANNER's top two priorities hold up under independent
re-derivation. But direct experimentation (not just hand-tracing) surfaced a real, previously-
undisclosed gap in `HostGameEngine.stop()`'s teardown of already-joined player connections —
smaller in scope than D101, but the same species of finding: a real defect only visible once you
go looking with a live repro rather than trusting the shipped tests' own coverage.

**1. Join slot-leak (D101) — PASS, independently re-derived from scratch, not trusted from the report.**
Read `HostListener.swift:242-258` directly: the `.accepted` branch's `catch` now calls
`removePlayer(player:state:)` (`SessionLogic.swift:148-154` — resets `connected`, deliberately
leaves `used`, no broadcast callback passed so no `SRDropPill`/other broadcast fires) *before*
`table.disconnect(player)`. Matches the reference's own "used-but-disconnected slots are rejoin-
eligible" model exactly, as claimed.

Independently re-ran the regression test (`processJoinAttemptOnSendFailureRevertsConnectedButPreservesUsed`,
`HostListenerTests.swift:346-385`) 10 consecutive times: 10/10 pass, no flakes. Then did my own
negative control — commented out the `removePlayer` call, rebuilt, reran: **fails exactly as
claimed**, `state.players[0].connected` reads `true` instead of `false`. Restored the file from a
pre-edit backup, confirmed `git diff --stat` shows zero diff (byte-identical), rebuilt clean.

**Determinism claim, specifically re-derived (this was PLANNER's named priority #1):** the test
waits for `link.clientEnd`'s `stateUpdateHandler` to actually observe `.cancelled`
(`HostListenerTests.swift:361-370`) before calling `processJoinAttempt` — not a bare `cancel()`
followed by a hope. Ran the isolated test 10 more times back-to-back with no sleep/retry padding:
consistently ~0.015-0.019s, no variance suggesting a race window. This is real determinism, not
disguised timing luck.

**2. `dispatchHostMessage`/`receiveOneHostMessageBytes` split — PASS, confirmed behavior-preserving
by diff, not just by passing tests.** `git show 8ca6567 -- Sources/BoloNet/HostSession.swift`: the
split is a pure mechanical extraction — every `let bytes = try await rest(...)` line that used to
sit inline in each `case` was moved, unchanged, into `receiveOneHostMessageBytes`'s own matching
`case`, in the same order, and the thin wrapper (`HostSession.swift:762-770`) calls
`receiveOneHostMessageBytes` then `dispatchHostMessage` in that same sequence — so the observable
read-then-decode-then-dispatch order is byte-for-byte identical to the pre-split version. Ran
`swift test --filter HostSessionTests` myself: **24/24 pass**. Note on the pre-brief's own "~15
call sites" figure (`AGENT_NOTES.md:3743`): direct calls to `receiveAndDispatchOneHostMessage`
in the test file are actually 10 (`grep -c`), not ~15 — the other 14 of the 24 tests exercise
`HostSessionTable`'s primitives (`sendToAll`/`sendToMask`/`disconnect`) and
`handlePlayerDisconnect`/`hostKickPlayer`/`hostBanPlayer` directly, not the dispatch path at all.
Minor citation looseness in an approximate pre-brief figure, not a defect in the completion
report's own claim ("all 24 ... pass unchanged") — that one is accurate as stated.

**3. Dynamic per-connection producer — disconnect/hangup path PASS, but a real new finding on
`stop()`'s own teardown.** Read `HostGameEngine.swift:153-167`: the producer loop breaks cleanly
on `.hangUp` and on any thrown read error (`catch` -> yield `.clConnectionEnded` -> `break`) — no
infinite retry, confirmed by re-running `hostGameEngineDisconnectsAPlayerNormallyOnHangUp` and
`hostGameEngineDisconnectsAPlayerAbnormallyWhenConnectionCloses` myself (both real-network tests,
both pass). That much matches the claim exactly.

**But I went further than re-reading the disconnect path and built a scratch test
(`HostGameEngineTests.swift`, appended, run, then restored from a pre-edit backup — confirmed
`git diff --stat` zero afterward) to check `stop()`'s own teardown, since "no leaked Task" is
PLANNER's actual ask and `stop()` is this type's only other lifecycle exit besides disconnect/hangup:**
joined a real player over a real TCP connection, called `engine.stop()`, waited 300ms, then sent
another `CL*` message on the still-open client connection. **The send succeeded with no error** —
proving `stop()` (`HostGameEngine.swift:130-138`) never cancels already-accepted player
`NWConnection`s or the dynamic producer `Task`s reading them: it only cancels `listener`/
`dgramListener`/`consumerTask` and nils `continuation`, none of which reach a connection already
handed off to its own per-player producer `Task` at `HostGameEngine.swift:154-166` (that closure
captured its own local `continuation` copy at spawn time, independent of the instance property
`stop()` nils). The practical effect: any already-joined player's producer `Task` — and the socket
it's blocked reading — outlives `stop()` entirely, continuing to consume CPU/memory and buffer
undelivered events into an abandoned `AsyncStream` for as long as the remote peer keeps the
connection open (which could be indefinitely).

**Currently latent, not yet a live bug:** `stop()` has no production caller yet (`grep` shows only
`HostGameEngineTests.swift`'s own `defer` cleanups) — Wave 7.1-7.3's app target hasn't wired
session start/stop to anything a user can trigger. But this is exactly the kind of thing D95/D96's
own "no leaked Task" discipline exists to catch, and it will matter the moment a real app wires
"stop hosting"/"quit" to this call. Not something I'm fixing — I don't write fixes — but real
enough that PLANNER should decide whether it's worth a D-number now or a note to catch before Wave
7.3 wires session lifecycle to UI.

**4. `onPlayerDisconnected`'s narrow wiring — PASS, confirmed no double-fire.** Read
`RunTick.swift:159-181` end to end: step 4 already computes the lagged player's onboard-pill mask,
calls `dropPills` (firing `onShouldBroadcastDropPill` per pill), sets `connected = false`, *then*
calls `onPlayerDisconnected(player)` — all before `onPlayerDisconnected` is even invoked.
`HostGameEngine.tick()` (`HostGameEngine.swift:210,226-231`) only ever appends to
`disconnectedPlayers` inside the callback, then after `runTick` returns does exactly two things per
disconnected player: `table.sendToAllExcept(player, SRPlayerDisc(...))` + `table.disconnect(player)`
— no second call to `removePlayer`/`dropPills`, confirmed by reading the full function body, not
just the diff. Ordering also matches the reference: `pending` (which includes any `SRDropPill`
broadcasts from step 4) is flushed via `table.sendToAll` *before* the `disconnectedPlayers` loop's
`SRPlayerDisc` send, matching `handlePlayerDisconnect`'s own documented C ordering
(`HostSession.swift:282-286`) of drop-pills-before-exit-broadcast.

Also independently confirmed the "5 correctly-unwired callbacks" claim, not just trusted it: read
`TankTick.swift:101-102` — `onExplosion`/`onSuperboom`/`onSmallboom`/`onSpawn` (lines 129, 135, 142,
159, exact line numbers as cited) all sit inside a block gated by `guard player ==
state.localPlayer else { return }` at line 102, so they provably never fire for a non-local
player's tank. And `client.c:436-446` (`client.setplayerstatus`, the C source
`onPlayerLagStatusChanged` mirrors) really is gated only on a UI-layer function-pointer being
non-NULL, with no `sendcl*`/`sendsr*` call anywhere in that block — confirmed by reading the actual
C, not the port's paraphrase of it.

**5. Test count — PASS, confirmed by direct execution, not by trusting the commit message.** Ran
the full suite 3 consecutive times: **172 `DifferentialTests` + 483 `BoloKitTests` = 655**, matching
exactly, stable across all 3 runs, zero flakes.

[TO: PLANNER] B.5c audited at `8ca6567`+`82068fc`+`47e9c09`+`25bce0f`. **D101 (join slot-leak) and
the `dispatchHostMessage` split: both PASS**, independently re-derived with a real negative control
and a real diff-level behavior check, not just re-running the shipped tests. **`onPlayerDisconnected`'s
narrow wiring: PASS**, confirmed no double-fire and correct ordering by reading `RunTick.swift`'s
step 4 and `HostGameEngine.tick()` in full. **One real new finding**: `HostGameEngine.stop()`
doesn't tear down already-joined players' `NWConnection`s or their dynamic producer `Task`s —
proved with a built scratch test (send after `stop()` succeeds when it should fail), not just
reasoned about. Currently latent (no production caller of `stop()` yet), so your call on whether
this rides as its own D-number now or gets tracked as a known gap to close before Wave 7.3 wires
session lifecycle to the app target. Test count confirmed: **655/655**, stable across 3 runs.
[TO: IMPLEMENTER] Nothing required right now — the `stop()` gap above is flagged for PLANNER's
ruling on timing, not assigned to you yet. If it does get assigned: the fix likely needs `stop()`
to call `table.disconnect(player)` (or otherwise cancel the connection) for every currently-connected
slot, which would make each blocked `receiveOneHostMessageBytes` throw and its producer `Task` exit
via the existing `catch` -> `break` path — the same clean-termination shape the disconnect/hangup
tests already prove works, just triggered from the other direction.

### [PLANNER] 2026-09-05 — B.5c CLOSED (D102 ruled: `stop()` teardown gap tracked, not blocking)

**Type:** ruling (D102), close
**Phase:** Milestone B, sub-wave B.5c — closed

**PARITY PASS on both top priorities.** D101's fix and the `dispatchHostMessage` split were both
independently re-derived (a real negative control on D101, a real diff-level behavior check on the
split), not re-run-and-trust. `onPlayerDisconnected`'s wiring and the 5-callback no-op claim both
confirmed by reading the actual code paths, not the port's paraphrase. 655/655, stable.

**D102 (the `stop()` teardown gap): tracked, not required before close — same shape as D98's own**
**base-control-reached deferral.** `stop()` has no production caller yet; nothing user-reachable
breaks. This is a different lifecycle surface than B.5c's own scope (TCP dispatch + the join
slot-leak), first exercised for real when Wave 7.3 wires session start/stop to the app. Revisit
there. IMPLEMENTER's own sketched fix shape (have `stop()` `table.disconnect` every connected slot,
letting the blocked read throw and the producer exit via the existing path) is the right direction
when it's picked up — not assigned now.

**B.5c is closed.** Milestone B status: B.0-B.3, B.5a, B.5b, B.5c all closed PARITY PASS. B.5d
(mine-chain causer-threading) remains not yet pre-briefed. B.4 (tracker/UPnP wiring) remains
undecided — proposed as optional/stretch at D92/D94, never explicitly folded, deferred, or dropped;
needs its own ruling before Milestone B can fully close, flagging here so it isn't missed at that
point.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — D102 added, Milestone B's row
updated (B.5c closed).

[TO: IMPLEMENTER] B.5c closed, nothing further needed on it. B.5d gets its own pre-brief whenever
you get to it, no rush. D102 is tracked for Wave 7.3, not assigned now.
[TO: PARITY] Excellent work on this audit and the run of B.0-B.5b before it — the negative
controls, the scratch-test proof on `stop()` rather than stopping at hand-tracing, real catches
throughout. Thank you, passed along from Jerod as well. Nothing further needed until B.5d or the
next wave lands.

### [IMPLEMENTER] 2026-09-05 — B.5d pre-brief (mine-chain broadcast wiring): D100's causer-threading premise doesn't hold

**Type:** pre-brief, not yet coding
**Phase:** Wave 7 / Milestone B, sub-wave B.5d

Read D100's full text in `docs/PLAN.md` and the B.5c pre-brief section it's drawn from first.
Then read `server.c`'s actual `explosionat()`/`superboomat()` bodies directly (not inferred from
this port's own comments) before assuming the causer-threading framing was right. **It isn't, for
two of the three callbacks** — the real fix is smaller and different in shape than D100 scoped.

## What `server.c` actually does (read directly, not restated from this port's comments)

- **`explosionat(player, x, y)`** (`server.c:4121-4165`): the `player` parameter is referenced
  **only in the `assert`**. Both branches that detonate a tile (mineable terrain, and mined-sea)
  call `sendsrsmallboom(NEUTRAL, x, y)` — always `NEUTRAL`, regardless of who actually caused it
  (a tank driving over a mine, a builder placing on one, or a chain/flood cascade). **No causer is
  ever broadcast for a single-mine detonation.**
- **`superboomat(player, x, y)`** (`server.c:4193-4249`): calls `sendsrsuperboom(player, x, y)`
  using the **real** `player` argument, at the very end, unconditionally — after all the
  terrain/flood/chain work, with no early return of any kind in the C source.

This port's own `explosionAt`/`superboomAt` (`MineChain.swift:373-495`) already replicate the
terrain/chain-scheduling logic exactly and already take a `player: UInt8` parameter — but **neither
one ever calls `onMineExplosion`/`onSuperboomTerrain` itself**. Both only thread the closures
further down into `applySplashDamage`, which fires them only via `smallboom()`/`superboom()`'s own
separate, `state.localPlayer`-scoped "notify hook" (a different, Wave-5.2b/5.9-era call site,
documented as firing *before* `dead` is set, for a different purpose).

**Consequence: D100's "thread a causer parameter through `TankLocalTick`/`ShellTick`/`BuilderTick`"
framing is the wrong shape of fix for `onMineExplosion` (needs no causer at all) and unnecessary
for `onSuperboomTerrain` (the causer it needs is already an existing parameter on `superboomAt` —
`ShellTick`/`BuilderTick`'s own call sites don't need to change).** The real gap is simpler: two
missing call sites, inside functions that already have what they need.

## Proposed fix shape (pending your GO)

1. **`onMineExplosion`** — add a call inside `explosionAt`, right after `guard detonated else {
   return }`, **before** the existing `if player != UInt8(state.localPlayer)` particle/builder-kill
   gate at line 410 (that gate is this port's own addition for the local-particle/builder-kill
   effect, not part of where C's broadcast sits — C's `sendsrsmallboom` fires unconditionally
   whenever a detonation happens, in both branches). Maps to `SRSmallBoom(player: playerNeutral,
   x:, y:)` in `HostGameEngine`'s wiring — always `NEUTRAL`, per the reference. No signature change
   anywhere else needed.
2. **`onSuperboomTerrain`** — add a call inside `superboomAt`, right after the chain-scheduling
   block, **before** the existing `guard player != UInt8(state.localPlayer) else { return }` at
   line 464 (C's `sendsrsuperboom` has no early return at all — putting the new call after that
   guard would silently never broadcast the local player's own superboom). Maps to
   `SRSuperBoom(player:, x:, y:)` using `superboomAt`'s own already-available `player` parameter.
   No signature change needed here either.

## One real question, not resolved here: does this double-fire the existing hooks?

Yes, structurally — `smallboom()`/`superboom()` already fire `onMineExplosion(explosionPoint!)`/
`onSuperboomTerrain(boomOrigin!)` once (the existing notify hook) and then call `explosionAt`/
`superboomAt` themselves at the end of their own bodies, which would fire it *again* under this
proposal, for the same tile. **This isn't actually a bug to reconcile away — it's two genuinely
different things that happen to share a parameter name, matching a real asymmetry already in the
C source:** `smallboom()`/`superboom()` (`client.c:5614,5647`) are the **client-role** optimistic
local path and have no `sendsrsmallboom`/`sendsrsuperboom` call at all in C; the broadcast lives
*only* in the **server-role** `explosionat()`/`superboomat()`. This port merges both roles into one
process (`RunTick.swift`'s own header already discloses this unification), but the two callback
firings still correspond to genuinely different C-side roles. **Recommend separate parameters**
(e.g. `onMineExplosion` keeps its current client-role-notify meaning; a new, distinctly-named
parameter carries the server-role broadcast), not collapsing them into one — the C source is why,
not a test-preservation concern.

## A separate, unrelated problem found in the same investigation: `onDropPills` may not belong in B.5d at all

`runTick`'s own top-level `onDropPills: (UInt16, Vec2f) -> Void` (fed to `chain`/`flood`, distinct
from the already-wired `onShouldBroadcastDropPill: (Int, Int, Int) -> Void`) is fired exclusively
from `killBuilder`/`killTank`/`drown` (`TankLocalTick.swift`/`ShellTick.swift`) — every one of
which just computes a mask and hands it to the closure with **no further `state` access**,
structurally identical to `onSpawn`'s shape *before* its own Wave 7.3/D88-§4 fix. Wiring it as-is
from inside a `runTick`-callback closure (to call the already-built `dropPills(player:x:y:pills:
state:onShouldBroadcastDropPill:)`) would be the exact nested `inout` exclusivity violation on
`state` that fix's own comment names by number, in this same file: *"a nested exclusive-access
violation on the same `state` `runTick` already holds `inout` for the duration of this call."* The
correct mirror of that fix is for `killBuilder`/`killTank`/`drown` to call `dropPills` **directly**
themselves (they already run safely nested inside `runTick`'s own held access) and surface the
already-wired `onShouldBroadcastDropPill` shape outward instead — at which point `onDropPills` as
its own top-level `runTick` parameter may become unnecessary entirely. **This is a different
problem from the broadcast-mapping question above** (it's about safe wiring, not about what SR*
message to send) — flagging separately rather than letting it inflate this sub-wave; may deserve
its own scope decision (fold into B.5d, or split further) rather than assuming it's included.

## A related scoping question this surfaced, not resolved here either

`killSquareBuilder`/`killPointBuilder` (`TankLocalTick.swift:43-78`) — called from `explosionAt`/
`superboomAt` for **any** exploding tile, not just ones the local player caused — only ever check
`state.players[state.localPlayer]`'s own builder, confirmed by the file's own header: *"Everything
here is scoped to the LOCAL player only, matching C exactly... this is not a simplification, it is
what the original code does."* That's true to a real distributed client's own `client.player`-only
local logic, but in this port's single unified `GameState`, it means **a remote player's builder
sitting on an exploding tile is never identified or killed by this call chain at all** — so even if
`onDropPills` gets fixed per above, there's no real `player:` to pass `dropPills` at these specific
call sites for a non-local builder. Whether `killSquareBuilder`/`killPointBuilder` need to become
multiplayer-general (scan every player's builder at the tile, not just `state.localPlayer`'s) is a
real question bigger than B.5d's own scope — flagging it, not resolving it.

## Proposed B.5d coding scope, pending your GO

1. `onMineExplosion` fix (item 1 above) — small, no signature changes.
2. `onSuperboomTerrain` fix (item 2 above) — small, no signature changes.
3. Two separate parameters (or equivalent) to resolve the double-fire question, your call on the
   exact shape.
4. Wire `HostGameEngine.tick()`'s `onMineExplosion`/`onSuperboomTerrain` (the new server-role ones)
   to `SRSmallBoom(playerNeutral,...)`/`SRSuperBoom(player,...)`.

**Explicitly NOT proposing to include, pending your ruling:** the `onDropPills` exclusivity fix,
and the `killSquareBuilder`/`killPointBuilder` multiplayer-scoping question — both real, both found
in this same investigation, both bigger or more separable than D100's own framing anticipated.

> **→ Planner:** D100's causer-threading premise doesn't hold for 2 of the 3 callbacks — both
> `explosionat()`/`superboomat()` reads are direct, not inferred (quoted above). Real fix is
> smaller (two missing call sites, using data already available) but raises a genuine design
> question (separate parameters for the client-role notify vs. server-role broadcast) plus two
> separable findings (`onDropPills`'s own exclusivity problem, and `killSquareBuilder`/
> `killPointBuilder`'s local-only scoping) that may or may not belong in this sub-wave. Same
> situation as D100 itself — bringing the corrected picture back before coding, not narrowing
> scope or guessing silently. Awaiting your coding-GO on the proposed scope above.

### [PLANNER] 2026-09-05 — Admin agent: archive/compression pass, D90 through B.5c's pre-brief (D94–D99) compressed

**Type:** repo housekeeping (archive/compression pass), no code, no ruling
**Phase:** n/a — administrative

Admin agent performed a scheduled archive/compression pass on this file, matching the existing
Wave 5.8/6.0–6.3/6.4–7.3 precedent in `docs/notes/archive.md`. Re-derived the cut point by heading
text rather than trusting a stale line number (per the assignment's own warning that a concurrent
Implementer session — B.5c's completion, then B.5d's pre-brief — would keep appending to the tail
while this pass was in progress; confirmed via `git log` that both landed strictly after the D100
heading, no collision).

**Archived:** everything strictly before the `### [PLANNER] ... D100: B.5c coding GO'd` heading —
D90 through D93's pre-Milestone-B process rulings, and Milestone B's B.0 through B.5b (all closed,
PARITY PASS) plus B.5c's pre-brief (D94 through D99), compressed into a new section in
`docs/notes/archive.md` matching its existing per-wave summary format (commit hashes, key
findings, decision cross-references). Full uncompressed text preserved in git history per D28 —
nothing here was deleted, only compressed. B.5c's actual coding/completion/audit/close (D100
onward, through D102) and B.5d's pre-brief were left untouched in the active log, exactly as
scoped — this pass does not reopen or re-summarize B.5c's own history.

**Updated in this file:** the `## Index` table's `docs/notes/archive.md` row (now describes the
extended range), and the active-log header retitled `## Active Log (from D100)` to match where the
trimmed log now starts.

`git status --short` checked immediately before this commit: only this file, `docs/notes/archive.md`,
and the pre-existing unrelated items (`README.md` modified, `.claude/`, `Resources/`, and the three
Director-owned untracked artifacts — one pair of which was renamed by Jerod mid-session, still
untouched) were present. Nothing else swept in.

[TO: PLANNER] Archive pass complete and committed. No ruling made, no wave status changed — purely
compression. Flag if any phrasing in the updated Index row or header needs correction.
[TO: PARITY] No action needed — no code or behavioral content in this pass.

### [PLANNER] 2026-09-05 — D103: B.5d coding GO'd (corrected fix shape); killSquareBuilder/killPointBuilder scoping split to new B.5e

**Type:** ruling (D103), coding GO, split
**Phase:** Wave 7 / Milestone B, sub-wave B.5d — GO'd; B.5e created, not pre-briefed
**Commit reviewed:** `f29d9a5`

**Correction confirmed — D100's causer-threading premise was wrong, exactly as this pre-brief's**
**direct `server.c` reads show.** `onMineExplosion` needs no causer (`sendsrsmallboom` always fires
`NEUTRAL`), `onSuperboomTerrain`'s causer is already an existing `superboomAt` parameter. Amended
D100's text inline with a pointer here — same standard D100 itself already applied once to its own
predecessor: say so and re-rule, don't guess what would have been wanted. Good instinct reading the
C source directly rather than trusting this port's own comments a second time.

**Fix shape approved as proposed** — two call sites inside `explosionAt`/`superboomAt`, placed
before the existing local-only gates exactly as cited (C's own broadcasts have no early return; the
port's gates are this port's own addition for a different, local-particle effect). No signature
changes to `TankLocalTick`/`ShellTick`/`BuilderTick`.

**Separate parameters for the double-fire question — approved.** The C source itself draws this
line (client-role `smallboom()`/`superboom()` never broadcast; only server-role `explosionat()`/
`superboomat()` do) — collapsing them into one meaning would erase a real distinction the reference
maintains, not just a naming coincidence. Same "preserve the invariant, not just the mechanism"
precedent as D41.

**`onDropPills`'s direct-call refactor — approved, folded into B.5d.** This is the correct fix
shape for scope D100 already intended `onDropPills` to cover, not new scope — small, and mirrors
an already-shipped precedent (D88 §4's `onSpawn` fix) rather than inventing a new mechanism.

**`killSquareBuilder`/`killPointBuilder`'s multiplayer-scoping gap — real, but out of B.5d, split**
**into new `B.5e`, not yet pre-briefed.** Same shape as D100 splitting B.5d out of B.5c: a
genuinely separable, larger unit of engineering surfaced mid-investigation. Unlike D102's `stop()`
gap (latent, no production caller yet), this one is reachable in live multiplayer today once B.5c's
engine runs with real players — a remote player's builder on an exploding tile is never found or
killed. Tracking it as a real gap owed its own sub-wave, not a deferred-forever note.

**B.5d coding GO'd:** the two call sites, separate parameters, `HostGameEngine.tick()`'s
`onMineExplosion`/`onSuperboomTerrain` wiring to `SRSmallBoom(playerNeutral,...)`/
`SRSuperBoom(player,...)`, and the `onDropPills` direct-call refactor.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — D103 added, D100 corrected
inline with a pointer to D103, Milestone B's row updated (B.5d GO'd, B.5e created).

[TO: IMPLEMENTER] Coding GO for B.5d exactly as proposed (items 1-4 in your pre-brief). Excellent
catch on D100's premise — bringing back a corrected picture rather than silently narrowing or
guessing is exactly this project's standard. B.5e (killSquareBuilder/killPointBuilder scoping) gets
its own pre-brief whenever you get to it, no rush.
[TO: PARITY] Heads up for whenever B.5d lands: the separate-parameters design for the double-fire
question is the one worth independently verifying (does the client-role notify path still fire
exactly where it always did, with the new server-role broadcast genuinely additive and not
reordering anything) — same standard as every other concurrency/ordering claim this milestone.

### [IMPLEMENTER] 2026-09-05 — B.5d completion report

**Commit:** `35e2320`. **Tests:** 655 → 660 (5 new: `MineChainTests.swift` ×4,
`HostSessionTests.swift` ×1). All existing tests still pass; no coverage shrinkage.

## What shipped, vs. the pre-brief's proposal — two corrections made along the way, both flagged to
## PLANNER live rather than discovered only here

1. **`onMineExplosion`/`onSuperboomTerrain` broadcast wiring — scope corrected DOWN from the
   pre-brief's ~15-call-site estimate to 2.** Reading `RecvCL.swift`'s `recvCl*` functions properly
   (not just grepping) showed every one of them already fires `onShouldBroadcastSmallBoom`/
   `onShouldBroadcastSuperBoom` immediately after `explosionAt`/`superboomAt` — wired since Wave
   6.6, already matching `server.c`'s real behavior (`recvClSmallBoom`'s own doc comment even
   explains why it re-derives `detonated` locally rather than exposing a new parameter — the exact
   call I nearly repeated). The **only** real gap was `chain()`/`flood()` (`MineChain.swift`) —
   cascading detonations driven straight from `runTick`, with no broadcast hook at all. Fixed:
   `chainAt`/`floodAt`/`chain`/`flood` gained `onShouldBroadcastSmallBoom: (UInt8, Int, Int) ->
   Void`, fired unconditionally right after their `explosionAt` call (their own switch only reaches
   it from an already-mined case — no `detonated` re-derivation needed, unlike `recvClSmallBoom`'s
   broader switch). Threaded through `runTick`, wired in `HostGameEngine.tick()` to
   `SRSmallBoom(player:, x:, y:)`.
2. **No causer-threading refactor needed anywhere** (the double-fire question the pre-brief raised
   never arose) — `smallboom`/`superboom`'s existing client-role notify-hook pre-fires were left
   untouched; the new broadcast lives only in `chainAt`/`floodAt`, a code path those two functions
   never touch.

Both corrections were messaged to PLANNER live as found (`fbae6c46`, `b733e142` — cross-session
message IDs), acknowledged without a ruling needed either time.

## `onDropPills` direct-call refactor — larger mechanical footprint than scoped, real behavior fix
## uncovered along the way

Confirmed the pre-brief's finding: every real fire site (`killBuilder`/`drown`/`smallboom`/
`superboom`, `TankLocalTick.swift`; `killTank`, `ShellTick.swift`) fired a bare `onDropPills(mask,
point)` pass-through with **no `state` access** — meaning **`dropPills`'s real spiral-search
placement never ran in production at all**, not just "no broadcast": a dead tank's/builder's
onboard pills stayed in their old owned-but-unreachable slots, never actually scattered onto the
map. This is a bigger fix than "broadcast wiring" — it restores real, previously-dead simulation
behavior, using the exact `onSpawn`/D88-§4 precedent (call the mutating function directly, since
these 5 sites already run nested inside `runTick`'s own held `&state`).

Renaming `onDropPills: (UInt16, Vec2f) -> Void` → `onShouldBroadcastDropPill: (Int, Int, Int) ->
Void` (already the correct shape, previously used only for the Wave-6.4c disconnect-drop case)
touches every intermediate pass-through between those 5 sites and every top-level caller — 13
files total, all mechanical except two real fixes found mid-refactor:
- **`CLDispatchCallbacks.onDropPills`** (`HostSession.swift`) was a no-op struct field with no
  `table`/`pending` access — meaning a builder killed by an explosion during any CL-dispatched
  action (`touch`/`grabTile`/`grabTrees`/build*/`repairPill`/`placeMine`/`damage`/`smallBoom`/
  `superBoom`) never broadcast its pill drop in production. Removed the field; all ~10 dispatch
  sites now pass an inline `onShouldBroadcastDropPill` closure straight to `pending`, matching the
  `.dropPills` case's own already-correct shape. Regression test:
  `dispatchTouchDetonationKillingABuilderBroadcastsRealDropPill` (`HostSessionTests.swift`) —
  negative-controlled (reverted to a no-op closure, confirmed the test hangs/fails waiting for a
  `SRDropPill` that never arrives, restored, re-verified clean).
- `TCPSession.swift`/`UDPSession.swift`/`DgramClientApply.swift`/`RecvSR.swift` (client-role
  receive/apply path) needed the same rename purely for type compatibility, since they call the
  same shared `drown`/`superboom`/`smallboom`/`killPointBuilder`/`killSquareBuilder`/`killTank`
  functions — no behavior change there beyond the label (still defaults to a no-op everywhere; a
  client should never fire a real broadcast from its own receive path, and nothing currently wires
  a live implementation on that side).

Negative-controlled the core fix too: reverted `killBuilder`'s `dropPills` call to a stub, confirmed
`killBuilderRespawnsAsParachuteAtAStart` fails exactly as expected (`broadcasts.count == 0`),
restored, re-verified clean.

## Not touched, per PLANNER's explicit instruction

D102 (`HostGameEngine.stop()` teardown gap) — tracked for Wave 7.3, out of scope here.

## Split out, not assigned

B.5e (`killSquareBuilder`/`killPointBuilder`'s `state.localPlayer`-only scoping, found investigating
`explosionAt`/`superboomAt`'s builder-kill gate) — a remote player's builder sitting on an exploding
tile is never identified or killed by this call chain today. Real, but bigger than B.5d's own scope
per PLANNER's D103 ruling; not picked up.

> **→ Planner:** B.5d landed as corrected (chain/flood broadcast gap only, no causer-threading
> refactor needed) plus the `onDropPills` direct-call refactor (bigger mechanical footprint than
> scoped — 13 files — but a real behavior fix, not just wiring: pill-scatter placement was
> previously dead code in production). 660 tests passing, all negative-controlled. Ready for
> PARITY.

### [PLANNER] 2026-09-05 — B.5d reviewed, PARITY activated

**Type:** review, PARITY activation
**Phase:** Milestone B, sub-wave B.5d — landed (`35e2320`+`f3e79af`), pending PARITY

Reviewed the completion report directly. Both live-flagged scope corrections (RecvCL.swift already
correctly wired since Wave 6.6; only chain/flood needed the new broadcast parameter) match what was
acknowledged in the moment — no surprises. The `onDropPills` refactor uncovering a real dead
behavior (pill-scatter placement never running) plus a dead-end `CLDispatchCallbacks` no-op is
exactly the kind of finding worth PARITY's independent re-derivation, not just re-run tests. 660
tests, negative-controlled throughout.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — Milestone B's row updated
(B.5d landed, pending PARITY).

[TO: PARITY] B.5d ready for audit: `35e2320` (implementation) + `f3e79af` (completion report).
Priorities: (1) independently confirm `chain()`/`flood()` was genuinely the only broadcast gap —
spot-check a couple of the claimed-already-wired `RecvCL.swift` call sites yourself rather than
trusting the report's "already wired since Wave 6.6" characterization; (2) the `onDropPills`
rename's behavior claim — that `dropPills`'s spiral-search placement never actually ran in
production before this fix — is the one substantive claim here, worth re-deriving with your own
negative control, not just re-running `killBuilderRespawnsAsParachuteAtAStart`; (3) confirm the new
`dispatchTouchDetonationKillingABuilderBroadcastsRealDropPill` test's negative control is real (the
report says reverting the fix makes it hang/fail waiting for a `SRDropPill`); (4) test count:
expect 660. Same scope guardrail as always: one `[PARITY]` entry, no `docs/PLAN.md` edits, no
closing, no GO. `README.md` and the three Director-owned untracked files are Jerod's own — leave
untouched.
[TO: IMPLEMENTER] Nothing further needed until PARITY reports back.

### [PARITY] 2026-09-05 — B.5d audit (`35e2320`+`f3e79af`): mine-chain broadcast wiring and `onDropPills` direct-call refactor both PASS

**Type:** post-commit audit. **Toolchain:** `swift` present (`swift-driver 1.168.6`, Swift 6.4) —
every claim below is execution-verified (built, ran the full suite 3 consecutive times, and for
both of PLANNER's top-priority claims, ran a real negative control by reverting the fix in place,
rebuilding, and confirming the expected failure, then restoring), not a hand-trace-only pass.
**Concurrency note:** `README.md` sits modified-uncommitted throughout (Jerod's own edit,
pre-existing at session start) — untouched by me; `git diff --stat` before and after this session
shows only that file plus this entry. `.claude/`, `Resources/`, and the three Director-owned docs
artifacts left alone too.

**Verdict: PASS.** Both of PLANNER's priorities hold up under independent re-derivation, and the
two negative controls behave exactly as the completion report claimed.

**1. "`RecvCL.swift`'s ~15 call sites already broadcast correctly since Wave 6.6" — PASS, spot-checked**
**3 of them directly, not trusted from the report.** `git show 35e2320 -- Sources/BoloKit/RecvCL.swift`
confirms the *entire* diff to that file is the `onDropPills` → `onShouldBroadcastDropPill` parameter
rename, nothing else — no new `onShouldBroadcastSmallBoom`/`onShouldBroadcastSuperBoom` call was
added anywhere in it. Read `recvClTouch` (`RecvCL.swift:100-126`), `recvClSmallBoom`
(`RecvCL.swift:592-618`), and `recvClSuperBoom` (`RecvCL.swift:622-638`) in full:
  - `recvClSmallBoom` re-derives its own `detonated` bool from the full terrain switch (mirroring
    `explosionAt`'s own case list) before firing `onShouldBroadcastSmallBoom(playerNeutral, x, y)` —
    correct, because unlike `chainAt`/`floodAt` its guard is *not* restricted to already-mined
    terrain, so it can't assume detonation. Matches `recvclsmallboom()`
    (`Reference/c/server.c:3034-3050`), which just forwards to `explosionat(player, x, y)`.
  - `recvClSuperBoom` fires `onShouldBroadcastSuperBoom(player, x, y)` unconditionally with the real
    causer, not `playerNeutral` — confirmed against `superboomat()` (`server.c:4242`,
    `sendsrsuperboom(player, x, y)`, no terrain gate, real `player`). Correctly asymmetric with
    `explosionat()`'s own unconditional `sendsrsmallboom(NEUTRAL, x, y)` (`server.c:4166`/`4170`,
    both detonating branches) — verified by reading `explosionat`/`superboomat` in full
    (`server.c:4121-4250`), not assumed symmetric.
  - `recvClTouch` only reaches `explosionAt` from a switch case restricted to the 7 mined terrain
    types, then fires `onShouldBroadcastSmallBoom(playerNeutral, x, y)` unconditionally — safe for
    the same structural reason `chainAt`/`floodAt` are (see #2).
  - Confirmed `NEUTRAL` really is `0xff` (`Reference/c/bolo.h:40`), matching `playerNeutral: UInt8 =
    0xff` (`Sources/BoloKit/Physics.swift:119`).

**2. `chainAt`/`floodAt`'s unconditional `onShouldBroadcastSmallBoom` fire — PASS, reasoning verified**
**by reading the switch statements, not accepted on the comment's say-so.** `chainAt`
(`MineChain.swift:292-310`) and `floodAt`'s mined branch (`MineChain.swift:238-259`) both guard on
exactly the 7 mined terrain cases (`.minedSea, .minedSwamp, .minedCrater, .minedRoad, .minedForest,
.minedRubble, .minedGrass`) before calling `explosionAt`. Read `explosionAt`'s own switch
(`MineChain.swift:390-436`): all 6 non-sea mined cases fall into the first case list (sets
`detonated = true` after mutating terrain), and `.minedSea` is its own case (`detonated = true`
directly) — there is no terrain value that passes `chainAt`/`floodAt`'s guard and reaches
`explosionAt`'s `default: detonated = false` branch. The claimed "no `detonated` re-derivation
needed" holds structurally, not just by inspection of one example. Cross-checked against C:
`chainat()`/`floodat()` (`server.c:4014-4057`) call `explosionat(NEUTRAL, x, y)` from the same
restricted mined-terrain switch, and `explosionat()` itself fires `sendsrsmallboom(NEUTRAL, x, y)`
unconditionally in both its detonating branches (`server.c:4166`, `4170`) — the port's split
(`explosionAt` no longer self-broadcasts; caller fires `onShouldBroadcastSmallBoom` after) correctly
preserves that C-side unconditional behavior for this restricted-guard case. Confirmed threading
through `chain()`/`flood()` (`MineChain.swift:264-283`, `316-335`) into `runTick`
(`RunTick.swift:211-218`, new `onShouldBroadcastSmallBoom` parameter) into
`HostGameEngine.tick()` (`HostGameEngine.swift:219-221`, wired to
`SRSmallBoom(player:, x:, y:).encode()`). New tests `floodAtBroadcastsSmallBoomOnDetonationWithNeutralCauser`/
`floodAtDoesNotBroadcastWhenNotDetonating`/`chainAtBroadcastsSmallBoomOnDetonationWithNeutralCauser`/
`chainAtDoesNotBroadcastForNonMinedTerrain` (`MineChainTests.swift`) each exercise both the positive
and negative case — read and confirmed they assert what they claim, not just that they pass.

**3. `onDropPills`'s dead-simulation-behavior claim — PASS, independently re-derived with my own**
**negative control, not just a re-run of the existing test.** Reverted `killBuilder`
(`TankLocalTick.swift:100-107`) to stub out the real `dropPills(...)` call (restoring the shape of
the pre-fix bare pass-through), rebuilt, and ran `killBuilderRespawnsAsParachuteAtAStart`
(`TankLocalTickTests.swift:395-409`) in isolation: it failed exactly as expected —
`broadcasts.count == 0` (not `1`), `broadcasts.first?.0` `nil` (not `2`) — confirming that before
this fix, killing a builder never actually invoked the spiral-search placement logic, only a
bare-data closure call with no `state` access. Restored the fix, rebuilt clean. Independently
confirmed (by reading, not re-testing each) the same direct-call pattern is applied at all 5 real
fire sites claimed: `killBuilder`/`drown`/`smallboom`/`superboom` (`TankLocalTick.swift`) and
`killTank` (`ShellTick.swift:327-349`) — each now calls `dropPills(player:, x:, y:, pills:, state:
&state, onShouldBroadcastDropPill:)` directly instead of the old bare `onDropPills(mask, point)`.
All other touched files (`TankTick.swift`, `PillTick.swift`, `RecvSR.swift`, `TCPSession.swift`,
`UDPSession.swift`, `DgramClientApply.swift`) are confirmed pure mechanical parameter renames with
no new call sites or logic changes — checked each file's diff directly.

**4. `CLDispatchCallbacks.onDropPills`'s dead-end-no-op fix — PASS, confirmed by diff and by my own**
**negative control (the hang), not just accepted from the report.** `git show 35e2320 --
Sources/BoloNet/HostSession.swift` shows the pre-fix struct field was exactly a bare
`(UInt16, Vec2f) -> Void` with no `pending`/`table` access in its declaration or `init` — genuinely
dead, since nothing in the shipped codebase ever configured it with a real implementation. Reverted
just the `.touch` case's `onShouldBroadcastDropPill` closure (`HostSession.swift:533`) to a no-op
(matching the old dead-end shape), rebuilt, and ran
`dispatchTouchDetonationKillingABuilderBroadcastsRealDropPill`
(`Tests/DifferentialTests/HostSessionTests.swift:285-317`) in isolation: it hung waiting on
`receiveExactly` for an `SRDropPill` that never arrives, exactly as claimed — had to kill the
background process after 45s rather than see a clean failure. Restored the fix, rebuilt clean, ran
the full suite 3 times with no regression. The test's own ordering claim (`SRDropPill` byte stream
arrives before `SRSmallBoom`) is structurally correct: `recvClTouch`'s single call to `explosionAt`
runs (and, via `killSquareBuilder` → `killBuilder` → `dropPills`, fires
`onShouldBroadcastDropPill` synchronously inside it) *before* `recvClTouch`'s own trailing
`onShouldBroadcastSmallBoom(playerNeutral, x, y)` call — confirmed by reading `recvClTouch`
(`RecvCL.swift:100-126`) top to bottom, not assumed from the test's own comment.

**5. Test count — PASS, confirmed by direct execution.** Ran the full suite 3 consecutive times:
**173 `DifferentialTests` + 487 `BoloKitTests` = 660**, up from 655 (172+483) at B.5c's close — a
net +5 matching the report's claim (`MineChainTests.swift` ×4, `HostSessionTests.swift` ×1), stable
across all 3 runs, zero flakes. Tree confirmed clean (`git diff --stat` shows only the pre-existing
`README.md` and this entry) after both negative controls were reverted.

**Coverage check on the "~15 already-wired" claim — ran it over the full set, not just the 3**
**spot-checked sites.** `grep -rn "explosionAt(\|superboomAt(" Sources/BoloKit/*.swift` (excluding
the two definitions) finds every call site. Of those: 11 in `RecvCL.swift` (server-role `recvCl*`,
all followed by a broadcast, per #1) + 2 in `MineChain.swift` (`chainAt`/`floodAt`, fixed by this
commit, per #2) are broadcast-covered. The remaining 3 — `TankLocalTick.swift:206` (`smallboom`),
`:288` (`superboom`), `:354` (`grabTile`) — are client-role and correctly *not* broadcast-covered:
confirmed `grabTile` maps to `client.c`'s `grabtile()`, which only calls `sendclgrabtile()`
(`client.c:5802` etc.) to notify the server, not a direct broadcast — the server's own
`recvClGrabTile` (already covered) is what actually broadcasts once it receives that message. Full
coverage confirmed, not extrapolated from 3 of ~15.

**Correction to my own draft, caught before commit:** I initially drafted a citation-accuracy note
claiming `explosionAt`/`superboomAt` "no longer self-broadcast (that behavior moved entirely to
callers)" — checked the actual diff (`git show 35e2320 -- Sources/BoloKit/MineChain.swift`) and
that's wrong: neither function fires or ever fired a broadcast closure internally, in this commit
or before it; nothing "moved." The real, worth-noting divergence is against D103's *ruling* text,
not the shipped code's own history: D103 GO'd "two call sites inside `explosionAt`/`superboomAt`,
placed before the existing local-only gates," but what shipped instead places the fire in the
*callers* (`chainAt`/`floodAt`) right after their `explosionAt` calls. This was already live-flagged
in the completion report ("the new broadcast lives only in `chainAt`/`floodAt`, a code path those
two functions never touch") and acknowledged without objection in PLANNER's review — not a new
finding, just noting the ruling-vs-shipped text mismatch explicitly since D103's own wording is
what a future reader would check against first.

**No real findings.** No `Double`/`CGFloat` creep (D18 n/a — no new float-position math here), no
bug-vs-feature ambiguity (D24 n/a), no shared-per-tick-state ordering hazard (D27 — `chain()`/
`flood()` were already covered by `MineChain.swift`'s own file-header D27 analysis, unchanged by
this commit), test count increased with a stated, verified replacement (D28 — satisfied, see #5).

[TO: PLANNER] B.5d audited at `35e2320`+`f3e79af`. **PASS on all 4 priorities** — the already-wired
`RecvCL.swift` claim, the `chainAt`/`floodAt` unconditional-broadcast reasoning, the `onDropPills`
dead-simulation-behavior claim, and the `CLDispatchCallbacks.onDropPills` dead-end fix — each
independently re-derived, two with my own from-scratch negative controls (not just re-running the
shipped tests). Test count 660, stable across 3 runs. No new findings to track. Ready to close from
my side.
[TO: IMPLEMENTER] Clean pass — nothing to fix. Nice catch chain on D100→D103, and the negative
controls in your own completion report matched what I independently reproduced exactly.

### [PLANNER] 2026-09-05 — B.5d CLOSED (PARITY PASS `aaf2229`)

**Type:** close
**Phase:** Milestone B, sub-wave B.5d — closed

Clean PASS, both priorities independently re-derived rather than trusted: the "already wired since
Wave 6.6" claim checked against all 16 `explosionAt`/`superboomAt` call sites (not just a sample),
and the `onDropPills` dead-simulation-behavior claim confirmed with a real negative control. One
non-blocking precision note on D103's ruling text (said "inside `explosionAt`/`superboomAt`,"
shipped in the callers instead) — already live-flagged during implementation, nothing to correct
beyond noting PARITY stated it exactly.

**B.5d is closed.** Milestone B status: B.0-B.3, B.5a-B.5d all closed PARITY PASS. Remaining open:
**B.5e** (killSquareBuilder/killPointBuilder scoping) not yet pre-briefed, and **B.4** (tracker/UPnP
wiring) still has no explicit disposition — flagged previously, still unruled, needed before
Milestone B can fully close.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — Milestone B's row updated
(B.5d closed).

[TO: IMPLEMENTER] B.5d closed, nothing further on it. B.5e whenever you get to it.
[TO: PARITY] Thank you — the full 16-call-site sweep instead of trusting a 3-site sample is exactly
the standard this project wants. Nothing further needed until B.5e or the next wave lands.
