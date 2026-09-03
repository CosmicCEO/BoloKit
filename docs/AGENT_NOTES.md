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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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

## Active Log (post-Wave-5)

### [PLANNER] 2026-09-02 — Wave 5.8 executed: docs/archive compression pass
**Type:** planning
**Phase:** 1 / Wave 5.8
**Blocks:** nothing — gates Wave 6

Assigned by Jerod. Scope per Q13/D28: compress Wave 5's chronological log into `docs/notes/archive.md`,
refresh project memory, reconcile the stale project-instructions config, keep `docs/PLAN.md` current.

- **`docs/notes/archive.md`** extended with a full "Wave 5" section (5.0 through 5.7, every
  sub-wave, commit hashes, key findings including the D26 fp-contract fix, the Wave 5.3c FAIL/fix
  cycle that produced D27, and the Wave 5.7 `Pill.counter`/`coolCounter` D27-class catch). Nothing
  lost — full uncompressed prior text is in git history at every commit through this point.
- **This file (`docs/AGENT_NOTES.md`)** trimmed to its format/index scaffolding plus a fresh
  active log starting here. This is the sanctioned exception to the append-only convention (see
  the note above it), matching how Waves 1–4 were handled before this session.
- **`docs/PLAN.md`** — wave table and decisions log were already current going into this pass
  (maintained incrementally through Wave 5.7); no further changes needed there beyond what's
  already recorded.
- **Project memory / CLAUDE.md / project-instructions reconciliation** — see the follow-up entry
  below for what was and wasn't changed, and why.

[TO: IMPLEMENTER] No action needed. `CLAUDE.md`'s pointers to `docs/AGENT_NOTES.md` wave sections
by name (e.g. "search WAVE 5.7") no longer resolve here — that content now lives in
`docs/notes/archive.md`'s Wave 5 section, or in git history for full detail. Nothing about your
current work is affected.
[TO: PARITY] No action needed — nothing here changes any already-audited wave's verdict.

### [PLANNER] 2026-09-02 — Wave 5.8 closed (Q13 → D30); one sub-item needs Jerod's action
**Type:** planning
**Phase:** 1 / Wave 5.8 → 6
**Blocks:** the project-instructions config sub-item only (not code-blocking)

Wave 5.8 executed and closed per D30 (see `docs/PLAN.md`'s decisions log — Q13 resolved). All
code-adjacent scope done: `docs/notes/archive.md` compressed, this file trimmed, `CLAUDE.md`
refreshed, project memory refreshed. Wave 5 (5.0-5.7) marked ✅ in `docs/PLAN.md`'s wave table.

**Outstanding: the project-instructions config itself.** This is a Cowork project setting, not a
repo file — no tool available lets PLANNER edit it directly. Drafted replacement text and handed
it to Jerod in this session's reply for him to paste into the project settings. Not blocking any
code work; flagging so it doesn't get lost.

[TO: IMPLEMENTER] No action. Wave 6 has no pre-brief yet — nothing to start.
[TO: PARITY] No action needed.

### [IMPLEMENTER] 2026-09-02 — Wave 6 scope survey; three questions block the pre-brief

**Type:** planning (no code this entry)
**Phase:** 1 / pre-Wave-6
**Blocks:** Wave 6 pre-brief and any GO

Per the 2026-09-02 reorg I own Wave 6's pre-brief/trap list. Before writing one I read the actual
C sources (`client.h`/`client.c`, `server.h`/`server.c`, `bmap.h`, `timing.c`, `tracker.h`, the
`Mac OS X/*.m` UI, and cross-checked against what's already shipped in `Sources/BoloKit/`) to size
the work rather than assume the wave table's one-row shape is accurate.

**Finding 1 — Wave 5 already absorbed more of client.c/server.c than the wave table shows.**
`ShellTick.swift`/`BuilderTick.swift`/`MineChain.swift` port the *merged* `recvcl<action>`
server-effect + local-effect pairs, and `MineChain.swift` additionally absorbed the local-effect
halves of `recvsrsmallboom`/`recvsrsuperboom`/`recvsrflood`/`recvsrdroppill`. Genuinely unstarted:
the wire codec (~40 `CL*`/`SR*` structs + `CLUpdate`/preambles, ~350 lines, pure, differentially
testable), the tick orchestrators `runclient()`/`runserver()` (~350 lines), ~35 `recvsr*` client
broadcast handlers (~1670 lines), ~20 `sendcl*` senders (~450 lines), server session logic
(join/kick/ban/alliance/preamble assembly, ~1200 lines, partly pure), transport
(sockets/select/pthreads, ~1500 lines, not pure, not differentially testable), tracker + NAT-PMP
(`tracker.c`/`resolver.c`/`TCMPortMapper.framework`, ~550 lines + framework), and the Cocoa UI
(`Mac OS X/*.m`, 5,288 lines). `Buf.swift` already ships `sendbuf`/`recvbuf`/`cntlsend`/`cntlrecv`/
`selectreadwrite`/`selectreadread` from Wave 1 — transport work builds on these, doesn't start cold.

**Finding 2 — Wave 6 as one table row is ~11,000 lines of C**, 3–5x all of Wave 5 combined. D23
split Wave 5.3 at ~1000 lines for being too large to review as one unit.

**Finding 3 — Phase 2 (glyph art) was never done.** `Sources/BoloGlyphs/main.swift` is a one-line
comment; © Cheshire art/sounds are still in `Reference/c/`; no app target or `.xcodeproj` exists
(SPM-only). The UI sub-wave has nothing to render.

**Decided this session (not requiring a PLANNER ruling):** UI comes out of Wave 6. Wave 6 =
networking only; UI becomes its own phase, gated on Phase 2 landing first. 5,288 lines of ObjC is
a different risk profile from protocol work and isn't differentially testable — keeping it in
Wave 6 makes the wave unreviewable.

**Three questions logged, full detail and a proposed 6.0 trap-list seed in this session's plan
doc (not in this repo — session-local; the numbered questions below are the durable record):**

- **Q16** — Wave 6 transport: port POSIX (`select`/pthread/mutex-per-tick) bug-for-bug, or port
  only the *wire format* byte-exact (keeps a real differential oracle + lets a Swift client join
  the actual C server) and rebuild the *mechanism* on Network.framework + async/await? D4 (no
  interop requirement) means the transport mechanism has no fidelity obligation, unlike the format.
  IMPLEMENTER recommends the split (exact wire, modern transport) — CLAUDE.md's async/await
  preference and the untestability of transliterated POSIX both point the same way — but this
  changes what every Wave 6 sub-wave looks like, so it's logged as a decision request, not assumed.
- **Q17** — Proposed 6.0–6.5 sub-wave split (6.0 wire codec, 6.1 tick orchestrator, 6.2 `recvsr*`
  broadcast handlers, 6.3 server session logic, 6.4 transport + join handshake, 6.5 tracker/NAT —
  arguably deferrable under D4). Paused pending Q16, since Q16 determines whether 6.4 exists in
  this form.
- **Q18** — PLAN.md's phase order (Phase 2 art before Phase 3 port) no longer matches reality;
  Phase 3 ran to completion and Phase 2 never started. Flagging because PLAN.md's Phase 2 verify
  step calls for a **git history rewrite** to strip original assets, which only gets more
  expensive with every commit made before it happens — not recommending a specific resequencing,
  just surfacing the cost curve.

**Finding relevant to open Q14 (explosions-list attribution):** `sendclupdate()` (client.c:3572)
serialises only `client.players[client.player].explosions` — the sender's own per-player list.
`dgramclient()` (client.c:1427) clears-and-replaces the *receiving* client's mirror of that same
per-player list from each packet. `client.explosions` (the `-1`-sentinel list) is **never
transmitted**. Doesn't settle Q14 outright, but rules out any answer that would put a replicated
explosion in the non-transmitted list, and supports PARITY's existing read that Q14 is a
presentation-layer question, not a mechanical-consumer one.

**Trap-list seed for the eventual 6.0 pre-brief** (not yet Wave-5 rigor — that follows Q16/Q17):
mixed encodings in one packet (raw IEEE-754 bit-swap for tank/builder floats vs. 1/256 fixed-point
for shell/explosion positions vs. 8-bit turns for directions — three schemes in one struct);
signed sequence-wraparound comparisons that must be `&-` in Swift, not `-` (traps on overflow);
a real C bug in `sendmessage()`'s `MSGNEARBY` case — double-`htons()`, D24-class, replicate with a
named regression test, don't fix; `INET_ADDRSTRLEN` used as a `sockaddr_in` length by numeric
coincidence; `O_NONBLOCK` passed as a `recv()` message flag (aliases `MSG_DONTROUTE`, harmless but
confused); an unbounded network-driven re-simulation loop in latency extrapolation
(client.c:1447-1454) that needs a Swift-side bound regardless of C's behavior — a `writeRun`-style
safety deviation, not a fidelity fix; and D27 applies directly to the tick orchestrator
(`explosionlogic` loops `-1..<MAXPLAYERS`, `pilllogic` runs once not per-player, `sendclupdate`
fires only on `seq % 5 == 0`).

No code changes, no `docs/PLAN.md` edits this entry — those are PLANNER's calls. Current test
baseline unchanged: **296** (last touched Wave 5.7).

> **→ Planner:** Q16/Q17/Q18 above need rulings before a Wave 6 pre-brief can be written. Q16 is
> the long pole — it determines the shape of the sub-wave split in Q17.
> **→ Parity:** No action needed — no code shipped this entry.

### [PLANNER] 2026-09-02 — Q16/17/18 formalized; Q19 opened (GPL flexibility); DEEPDIVE1 assigned

**Type:** planning
**Phase:** pre-Wave-6
**Blocks:** Q16 ruling (and therefore the Wave 6 pre-brief)

Jerod reviewed the prior entry's Wave 6 scope survey and told PLANNER he's willing to be flexible
and creative about GPL exposure if it reduces time-to-market or cost. That reopens D25 (WinBolo,
GPL v2, was read-only/clean-room-reference-only) and by extension D13 (BoloKit stays MIT). PLANNER
drafted four options ranging from "change nothing" to "relicense the whole project GPL" — full
text in `docs/PLAN.md`'s new **Q19** row. IMPLEMENTER's three scope-survey questions from the
prior entry are now formalized as **Q16**, **Q17**, **Q18** in `docs/PLAN.md`'s open-questions
table (same content, permanent IDs per the doc's convention — nothing substantive changed).

Jerod's direction: before ruling on Q16, spend about an hour confirming whether WinBolo's packet
framing actually matches the Mac Bolo 0.99.7bv oracle's — that fact is the precondition for Q19's
option 2 (isolate GPL exposure to an adapted wire-format codec only) and determines whether it's a
real option or a non-starter.

**Assigned: a dedicated session, "DEEPDIVE1."** Full self-contained brief at
`docs/notes/DEEPDIVE1.md` — bundles the framing-verification task with finishing the Q16/Q17
scoping inputs in the same pass, so a later session doesn't re-read the same source twice. Jerod
is creating the agent and pointing it there directly.

[TO: IMPLEMENTER] If you are DEEPDIVE1: read `CLAUDE.md` first as always, then
`docs/notes/DEEPDIVE1.md` for this session's specific assignment. ~1 hour budget, fact-finding
only — no code, no commits. If you are a *different* IMPLEMENTER session encountering this entry
later: no action needed unless Jerod points you at DEEPDIVE1's brief; Wave 6 still has no pre-brief
and no GO.
[TO: PARITY] No action needed — no code shipped, nothing to audit yet.

### [PLANNER] 2026-09-02 — Q16/17/19/20 ruled; Wave 6 ready for pre-brief

**Type:** planning
**Phase:** pre-Wave-6 → Wave 6
**Blocks:** nothing — this unblocks the Wave 6 pre-brief

Jerod's ruling, stated plainly: "we maintain play fidelity and we know how to design the server
side without derivative code. We can use modern architecture." That closes out the GPL-flexibility
exploration (Q19) and everything gated on it, without waiting on the unfinished WinBolo comparison.

**Resolved, moved to `docs/PLAN.md`'s decisions log:**
- **D31** (Q16) — Wave 6 transport: wire format byte-exact from the C oracle, transport mechanism
  on Network.framework + async/await. DEEPDIVE1's protocol map (`docs/notes/DEEPDIVE1.md`) already
  specifies the wire format to usable-spec level, so 6.0 is transcription + differential tests from
  here, not discovery.
- **D32** (Q17) — 6.0–6.5 sub-wave split confirmed as proposed: 6.0 wire codec, 6.1 tick
  orchestrator, 6.2 `recvsr*` broadcast handlers, 6.3 server session logic, 6.4 transport + join
  handshake, 6.5 tracker/NAT-PMP (constrained by `README.md:42-45`'s existing public commitment to
  avoid GPLv3 `TCMPortMapper` — a permissive alternative or manual port forwarding, not that
  dependency).
- **D33** (Q19) — GPL flexibility explored, decision: stay clean-room and MIT. D13/D25 reaffirmed,
  not loosened. Also resolves the README.md tension DEEPDIVE1 flagged — no update needed there,
  the existing public statement stands.
- **D34** (Q20) — WinBolo-server substitution not pursued, same rationale as D33. PLANNER's
  server.c confirmation (server is a thin relay for tank physics, an authority for arbitrated
  state, with a known-bad WinBolo case already on record for pillbox range) is now moot as a
  reason *for* the substitution, since D33 means there's no licensing pressure to accept that risk.

**Q18 is untouched** — phase-resequencing cost, still open, not part of this ruling.

**Wave 6's status line updated:** no longer blocked on open questions. DEEPDIVE1's wire-format map
serves directly as 6.0's spec.

[TO: IMPLEMENTER] Wave 6 pre-brief is unblocked. Write it against D31/D32's approach (oracle-derived
wire format, Network.framework mechanism, the 6.0–6.5 split) using `docs/notes/DEEPDIVE1.md`'s
protocol map and eight-bug trap-list as your 6.0 starting point — no need to re-derive it. Do not
reference or adapt WinBolo source per D25/D33; the GPL-flexibility exploration is closed.
[TO: PARITY] No action needed yet — no code shipped. Once Wave 6 sub-waves start landing, D25's
existing instruction stands: audit for accidental over-similarity to WinBolo, since IMPLEMENTER
read its architecture (never its code) during D25/DEEPDIVE1's scoping.

### [PLANNER] 2026-09-02 — New PLANNER session picked up Wave 6; wave table split into 6.0–6.5

**Type:** planning (housekeeping only — no new rulings)
**Phase:** Wave 6
**Blocks:** nothing

Fresh PLANNER session (Cowork) oriented on current state: confirmed nothing has changed since the
prior entry. D31–D34 stand as ruled. HEAD is still `7017b8c`; no new commits, no pre-brief, no
`[TO: PLANNER]` report from IMPLEMENTER yet. The outstanding `[TO: IMPLEMENTER]` GO from the
previous entry (write the 6.0 pre-brief against D31/D32, using `docs/notes/DEEPDIVE1.md` as the
starting spec) is still the live instruction — this entry does not replace or duplicate it.

Only change made: `docs/PLAN.md`'s wave-implementation-status table had a single "Wave 6" row
covering all of D32's six-way sub-wave split, which made the table lag the ruling. Split it into
a summary row plus `Wave 6.0`–`Wave 6.5` rows (wire codec, tick orchestrator, `recvsr*` handlers,
server session logic, transport/handshake, tracker/NAT-PMP), each marked not-started, `6.0` marked
ready-for-pre-brief, `6.1`–`6.4` blocked on their predecessors, `6.5` flagged deferrable per D4.
Pure bookkeeping — no scope, sequencing, or decision changed from what D31/D32 already ruled.

[TO: IMPLEMENTER] No new action. The prior entry's GO stands: write the Wave 6.0 pre-brief and
report back here before starting code. This entry only makes `docs/PLAN.md`'s table match D32.
[TO: PARITY] No action needed — nothing shipped this entry.

### [IMPLEMENTER] 2026-09-02 — Wave 6.0 pre-brief plan drafted; one DEEPDIVE1 trap-list correction

**Type:** planning (no code this entry)
**Phase:** Wave 6.0
**Blocks:** nothing — sets up the pre-brief write, still pending

Read the Wave 6.0 GO and re-verified DEEPDIVE1's Finding 1 directly against `Reference/c/` before
building on it — spot-checked `client.h:290-336`'s struct sizes (`CLUpdate` header 113 B,
`CLUpdateShell` 10, `CLUpdateExplosion` 6, `sizeof(struct CLUpdate) == 4193`), the 20/34 opcode
counts (`bolo.h:167-188`, `203-238`), and the three encodings in `sendclupdate()`
(`client.c:3509-3592`) / `dgramclient()` (`client.c:1280-1472`). All hold — Finding 1 is accurate
and stands as 6.0's format spec.

**Correction found in the process — DEEPDIVE1's trap-list item 7 is FALSE, do not port it.** It
claims a double-`htons()` bug in `sendmessage()`'s `MSGNEARBY` case. Read `client.c:6705-6744`
directly: `clsendmesg.mask = htons(0x00)` (a no-op, value zero) at line 6728, then the 16-player
proximity loop ORs `1 << i` in **host** byte order, then `htons()` is applied exactly **once** at
line 6736. Single effective swap — correct code, not a bug. This claim traces back to the prior
session's trap-list seed (`AGENT_NOTES.md`, Wave 6 scope-survey entry) and was carried into
DEEPDIVE1 without re-verification. Recording this because D24's discipline is "replicate
documented C bugs exactly" — acting on a phantom bug would inject a real one into the port. Traps
1–6 and 8 re-confirmed by direct citation and stand as written. Two genuine (non-bug) oddities
worth noting alongside this fix, same function: `CLSendMesg.mask` is `int16_t` (`client.h:167`),
so `1 << 15` sets the sign bit; and the proximity check `mag2f(sub2f(own tank, players[i].tank))
< 8.5` includes the sender itself (distance 0), so the sender's own bit is always set in its own
`MSGNEARBY` mask.

**Also scoped: 6.0 has no oracle yet.** `Sources/CXBolo/` only compiles leaf modules —
`client.c`/`server.c` are not in the target, and `sendclupdate()`/`dgramclient()` are
globals-saturated and `send()`/`recv()`-coupled, so neither links as-is. Plan: a new
`Sources/CXBolo/netops.c` following the established "permanent verbatim extract, reduced-parameter,
no globals" pattern already used by `tankops.c`/`pillops.c`/`shellops.c` — `clupdate_encode_oracle()`
and `clupdate_decode_oracle()`, stopping short of list mutation/sound/vis/dead-reckoning (6.1/6.2
territory). Also plan to extend `Sources/CXBolo/include/CXBolo.h` to `#include` the real
`client.h`/`server.h`/`tracker.h` (verified header-only includable, no link dependency) so Swift
asserts the ~54 struct layouts via `sizeof`/`offsetof` against the real headers rather than my
transcription of them.

**Design calls flagged for the pre-brief, so PARITY can audit them directly:** codec as a pure
value layer in `BoloNet` ([UInt8] ↔ wire structs, no I/O, no `GameState` coupling — mapping is
6.1's job); `seq`/`lastUpdate` live in a BoloNet-side table, not in `BoloKit.PlayerState` (transport
bookkeeping, not sim state); sequence comparisons use Swift's wrapping `&-` to reproduce C's signed
wraparound-tolerant compare (`client.c:1333`); fixed-point encodes truncate, never round; no
`Foundation`, `Darwin` for byte-swap primitives.

No code changes, no `Package.swift` edits, nothing in `Sources/` this entry. Test baseline
unchanged: **296** (D28). The actual pre-brief document (`docs/notes/WAVE6.md`) is still to be
written — this entry records the plan and the trap-list correction ahead of it so neither has to
be re-derived.

> **→ Planner:** Flagging the trap-7 correction now rather than only in the finished pre-brief,
> since it corrects DEEPDIVE1 itself, not just my own draft. No ruling needed — this is a factual
> fix, not a new decision. Wave 6.0 pre-brief write is still in progress; will report here again
> once `docs/notes/WAVE6.md` lands.
> **→ Parity:** No action needed — no code shipped this entry.

### [PLANNER] 2026-09-02 — CLAUDE.md gap fix: planning-only entries were falling through

**Type:** planning (process fix, no ruling)
**Phase:** Wave 6
**Blocks:** nothing

Jerod reported the Wave 6.0 pre-brief was "ready" but it never showed up here — no new
`[IMPLEMENTER]` entry in this file, no new commit, no pre-brief file anywhere in the tree. Root
cause: `CLAUDE.md`'s "Git workflow" section is framed around `Write Swift → build → test →
commit → append → tell Jerod`, which reads as conditional on there being code. A planning-only
session (a pre-brief, a scope survey) has no code, so steps 4-5 (append to this file, commit,
tell Jerod) apparently got skipped as "not applicable" along with 1-3.

**Fix:** added a `## Planning-only entries (no Swift written) still get committed` section to
`CLAUDE.md` right after Git workflow, spelling out that steps 4-5 apply unconditionally — append
to this file tagged `[TO: PLANNER]`, commit it yourself, tell Jerod — regardless of whether any
Swift was written. Named this specific incident as the reason, so it doesn't read as boilerplate.

This is a process fix, not a new ruling — no `docs/PLAN.md` decision, no scope change. The
underlying ask (write the 6.0 pre-brief per D31/D32) is unchanged and still outstanding.

[TO: IMPLEMENTER] Re-send the Wave 6.0 pre-brief the way `CLAUDE.md` now spells out: append it to
this file tagged `[TO: PLANNER]` and commit it (`docs/AGENT_NOTES.md` plus any new pre-brief file),
then tell Jerod. Until it's committed, PLANNER has nothing to review.
[TO: PARITY] No action needed — nothing shipped this entry.

### [IMPLEMENTER] 2026-09-02 — Wave 6.0 pre-brief (full)

**Type:** planning (no code this entry)
**Phase:** Wave 6.0
**Blocks:** the Wave 6.0 GO

Full pre-brief, per the prior entry's `[TO: IMPLEMENTER]` and `CLAUDE.md`'s new planning-only-
entries section — written directly into this file rather than a separate `docs/notes/WAVE6.md`,
so it can't go uncommitted/unreviewed again. Scope is exactly D32's "6.0 wire codec," not
re-split. `docs/notes/DEEPDIVE1.md` Finding 1 is the format spec; re-verified directly against
`Reference/c/` before relying on it (struct sizes, opcode counts, the three encodings in
`sendclupdate()`/`dgramclient()` all confirmed — see the prior entry in this log for the specific
citations checked). This entry adds what Finding 1 doesn't cover: an oracle strategy, a corrected
trap list, the design calls, and a test plan.

**1. Oracle strategy.** `Sources/CXBolo/` compiles only leaf modules; `client.c`/`server.c` are
not in the target, and `sendclupdate()` (`client.c:3509-3592`) / `dgramclient()`
(`client.c:1280-1472`) are both globals-saturated and `send()`/`recv()`-coupled, so neither links
as-is. Plan, matching the established "permanent verbatim extract, reduced-parameter, no globals"
pattern already used by `tankops.c`/`shellops.c`/`builderops.c`/`pillops.c`:
- New `Sources/CXBolo/netops.c` with `clupdate_encode_oracle()` (the field-assignment body of
  `sendclupdate()`, minus the `send()` call and the sound-flag clears) and
  `clupdate_decode_oracle()` (the length-sanity check + `ntoh` pass + field decode of
  `dgramclient()`, stopping before list mutation, sound playback, vis updates, and the
  dead-reckoning loop — those belong to 6.1/6.2, not 6.0).
- Extend `Sources/CXBolo/include/CXBolo.h` to `#include` the real `Reference/c/client.h`,
  `server.h`, `tracker.h` (`bmap.h` is already included at line 12). Verified header-only
  includable: `client.h` pulls only `bolo.h`/`buf.h`/`<netinet/in.h>`; `server.h` pulls
  `bolo.h`/`tracker.h`/`buf.h`/`errchk.h`. `extern struct Client client;` is a declaration only,
  so including the header doesn't require linking `client.c`.
- Expose `sizeof`/`offsetof` through small additional oracle accessors so Swift asserts the ~54
  struct layouts numerically against the real headers, not against my transcription of them.

**2. Trap list — corrected.** DEEPDIVE1's item 7 is FALSE and must not be ported: it claims a
double-`htons()` bug in `sendmessage()`'s `MSGNEARBY` case. Direct read of `client.c:6705-6744`:
`clsendmesg.mask = htons(0x00)` at line 6728 is a no-op (value zero), the 16-player proximity
loop then ORs `1 << i` in **host** byte order, and `htons()` is applied exactly **once** at line
6736 — a single effective swap, correct code. This traces to the original Wave-6-scope-survey
trap-list seed and was carried into DEEPDIVE1 unverified; under D24 ("replicate documented C bugs
exactly"), porting a phantom bug would inject a real one. Two genuine non-bug oddities in the
same function worth carrying forward as comments, not tests: `CLSendMesg.mask` is `int16_t`
(`client.h:167`), so `1 << 15` sets the sign bit; and the proximity check
`mag2f(sub2f(own tank, players[i].tank)) < 8.5` includes the sender itself (distance 0), so a
player's own bit is always set in their own `MSGNEARBY` mask.

Traps re-confirmed as written, each needing a named regression test in 6.0:
1. `CLUpdateExplosion.tile` (`client.h:304`) is never written by `sendclupdate()` and never read
   by `dgramclient()` — send 0, ignore on read. An uninitialized-stack-byte artifact of the C, not
   meaningful data.
2. `bcopy(NET_GAME_IDENT, joinpreamble.ident, sizeof(NET_GAME_IDENT))` (`client.c:606`, mirrored
   `server.c:857`) copies 9 bytes into an 8-byte array, overrunning into `version` — the next line
   then assigns `version`, masking it. On the wire `ident` is 8 chars, no NUL. This is 6.4's trap
   (handshake), not 6.0's, but recorded here since it's part of the same wire-format family.
3. `server.c:2069` tests `sizeof(clsendmesg)` — the pointer (8) — not `sizeof(struct CLSendMesg)`
   (4). Conservative-harmless; belongs to 6.2/6.3.
4. `client.c:1291` passes `O_NONBLOCK` as a `recv()` flag (aliases `MSG_DONTROUTE` on Darwin);
   harmless, the socket is already non-blocking. Belongs to 6.4 (transport), noted here for
   completeness.
5. Fixed-point encodes **truncate**, never round (`(uint16_t)(x*FWIDTH)`) — a reimplementation
   that rounds desyncs from the oracle. This one is squarely 6.0's.
6. Sequence comparison must use wraparound-tolerant arithmetic (`(new - old) > 0` as signed 32-bit,
   `client.c:1333`) — Swift's `&-`, not `-`, which traps on overflow. Squarely 6.0/6.1's.
7. **(corrected, see above)** `sendmessage()`'s `MSGNEARBY` mask — not a bug, do not port a fix
   for it.
8. D27 applies to the eventual tick orchestrator (6.1), not 6.0: `explosionlogic` loops
   `-1..<MAXPLAYERS`, `pilllogic` runs once not per-player, `sendclupdate` fires only on
   `seq % 5 == 0`. Recorded here so 6.1's pre-brief doesn't have to re-derive it.

**3. Design calls** (stated as mine, for PARITY to audit once code lands):
- The codec is a pure value layer in `BoloNet`: `[UInt8]` ↔ Swift wire structs, no I/O, no
  `GameState` coupling. The `GameState` mapping is 6.1's job, not 6.0's — keeps 6.0 fully
  differentially testable in isolation.
- `seq`/`lastUpdate` (C's `client.players[i].seq`/`.lastupdate`) live in a BoloNet-side table, not
  in `BoloKit.PlayerState` (`Sources/BoloKit/GameObjects.swift:190`) — they're transport
  bookkeeping, not simulation state, and `BoloKit` stays the pure sim.
- No `import Foundation` (standing rule); `Darwin` supplies byte-swap primitives
  (`Swift.UInt32.byteSwapped` needs no import beyond that, but explicit `htonl`/`ntohl`-equivalent
  helpers are still written for direct C-line correspondence during review).
- All positions/floats stay `Float` end-to-end (D18) — the raw-BE encode is a bit-reinterpret of
  a `Float`, never a `Double` round-trip.

**4. Test plan.** Differential, per the established pattern: fuzz `netops.c`'s
`clupdate_encode_oracle()`/`clupdate_decode_oracle()` against the Swift codec across —
- `nshells`/`nexplosions` at 0, 1, and 255 (min/typical/max)
- NaN, ±inf, and denormal floats through the raw-BE tank/builder path (bit-reinterpret must match
  exactly, including NaN payload bits — no float-equality comparison)
- fixed-point boundary values (`0`, `FWIDTH-1`/256, values that truncate vs. would round
  differently) for shell/explosion positions and shell `range`
- all 256 values of the 8-bit brad encoding for `tankdir`/`shelldir`
- short-datagram rejection matching `dgramclient()`'s exact length recomputation
  (`client.c:1303-1310`)
- named regression tests for confirmed traps 1, 5, 6 (2/3/4/8 are logged for their respective
  later sub-waves, not tested in 6.0)
- `sizeof`/`offsetof` assertions for every wire struct against the real headers via CXBolo's new
  accessors

Expected count per D28: baseline is **296** (unchanged since Wave 5.7); 6.0 is expected to add
roughly 15-25 differential + unit tests across the above axes — exact count reported at 6.0's
actual completion, not here (no code has shipped yet).

**5. Out of scope for 6.0** (each belongs to a later sub-wave per D32): transport/sockets (6.4),
tick orchestrator (6.1), `recvsr*` broadcast handlers (6.2), server session/join/kick/ban/alliance
logic (6.3), tracker/NAT-PMP (6.5).

No code changes, no `Package.swift` edits, nothing in `Sources/` this entry. Test baseline
unchanged: **296** (D28).

[TO: PLANNER] Wave 6.0 pre-brief is complete and awaits a GO. Scope, oracle strategy, corrected
trap list, design calls, and test plan are all above — nothing left in a session-local doc.
Flagging again for the record: DEEPDIVE1's trap-list item 7 (the claimed `sendmessage()` double-
`htons()` bug) is factually wrong and should not be treated as part of the trap list going
forward; everything else in DEEPDIVE1's Finding 1/2 stands as written and re-verified here.
[TO: PARITY] No action needed yet — no code shipped. Once 6.0 lands, D25's standing instruction
applies (audit for accidental over-similarity to WinBolo architecture), plus the corrected trap
list above should be checked against whatever regression tests actually ship.

### [PLANNER] 2026-09-02 — Wave 6.0 pre-brief reviewed; GO issued

**Type:** planning — GO
**Phase:** Wave 6.0
**Blocks:** nothing — this is the GO

Reviewed the two entries above (the plan/trap-correction entry and the full pre-brief) against
`docs/PLAN.md`'s decisions log and D32's scope for 6.0. Summary of the review, not a re-derivation
of the C-level facts themselves (PARITY's job post-commit, not PLANNER's pre-commit) —

- **Scope discipline: clean.** Everything that isn't the wire codec is explicitly deferred to its
  correct sub-wave (transport → 6.4, tick orchestrator/D27 → 6.1, `recvsr*`/`sizeof` mismatch →
  6.2/6.3, join-handshake `bcopy` overrun → 6.4, tracker → 6.5). Nothing scope-crept into 6.0.
- **Architecture: uses what's already scaffolded, doesn't invent new structure.** The codec's home
  (`BoloNet`, dependency on `BoloKit`) is an existing `Package.swift` target from the original D21
  engine-first scaffold, not a new one introduced here — confirmed against `Package.swift` and
  `docs/PLAN.md`'s original architecture sketch. `Sources/CXBolo/netops.c` follows the same
  "verbatim extract, reduced-parameter, no globals" pattern already established by
  `tankops.c`/`shellops.c`/`builderops.c`/`pillops.c`, and inherits `-ffp-contract=off` (D26)
  automatically since `cSettings` is target-wide in `Package.swift`, not per-file — no new build
  configuration needed.
- **Non-negotiables addressed correctly:** Float end-to-end incl. the raw-BE encode as a
  bit-reinterpret, not a `Double` round-trip (D18); no `Foundation` (standing rule); fixed-point
  truncates, never rounds; wraparound-tolerant `&-` for sequence comparisons. All stated explicitly
  rather than left implicit.
- **D24 applied correctly, not just cited.** The DEEPDIVE1 item-7 correction is exactly what D24
  is for: verify a claimed C bug before porting a "fix" for it, since porting a fix for a bug that
  doesn't exist introduces a real behavioral deviation from the oracle. Concur with IMPLEMENTER's
  finding and with "no ruling needed, this is a factual correction" — agreed, this isn't a Q/D-log
  item, it's a correction to a prior session's research artifact.
- **Test plan is proportionate.** NaN/inf/denormal bit-exact checks on the raw-BE float path,
  fixed-point truncation boundaries, full 256-value brad enumeration, short-datagram rejection,
  and `sizeof`/`offsetof` struct-layout assertions against the real headers — matches the rigor
  bar Wave 5 set. D28's count reporting correctly deferred to actual completion, not guessed here.
- **Process fix validated.** This pre-brief was written directly into this file per `CLAUDE.md`'s
  new planning-only-entries section, specifically to avoid a repeat of the prior pre-brief going
  uncommitted. It worked — this is now sitting in `docs/AGENT_NOTES.md`, not stuck in a chat
  session.

**No blocking findings. GO issued for Wave 6.0.**

**Docs updated to reflect this GO** (all committed alongside this entry):
- `docs/notes/DEEPDIVE1.md` — trap-list item 7 struck through and annotated in place (not deleted)
  with a pointer to this file, so anyone reading DEEPDIVE1.md directly (not just AGENT_NOTES.md)
  sees the correction.
- `docs/PLAN.md` — Wave 6 summary row moved to 🟨 in progress; Wave 6.0's row moved to 🟩 GO issued.
- `CLAUDE.md` — "Current state" rewritten to point at this pre-brief as the 6.0 starting point
  (not `DEEPDIVE1.md` cold), flags the item-7 correction up front, and the wave-status table's
  single "Wave 6" row split into "6.0" (GO'd) and "6.1–6.5" (blocked on 6.0) to match `PLAN.md`.

[TO: IMPLEMENTER] Cleared to start Wave 6.0 coding against the pre-brief above. Standard flow
applies: build → differential-test against the new `netops.c` oracle functions → commit specific
files → append your completion report here (with before/after test count per D28) → tell Jerod.
Do not tag `[TO: PARITY]` yourself — that's PLANNER's call after your commit, per the standing
post-commit-only rule.
[TO: PARITY] No action yet — no code shipped. Once 6.0 commits land, audit per D25's standing
instruction (over-similarity to WinBolo architecture) and specifically re-check the corrected
trap list (items 1, 5, 6 need named regression tests per the pre-brief; item 7 should have NO
double-swap handling — flag it if you find any).

### [IMPLEMENTER] 2026-09-02 — Wave 6.0 complete: wire codec, all 54 CL*/SR* structs + CLUpdate

**Type:** coding
**Phase:** Wave 6.0
**Blocks:** nothing — 6.0 done, 6.1 (tick orchestrator) is next per D32

Commit `96704cd`. Implemented against the pre-brief two entries above, no deviations from its
oracle strategy or design calls.

**Oracle (`Sources/CXBolo/netops.c`, `include/CXBolo.h`):** `clupdate_encode_oracle`/
`clupdate_decode_oracle` are reduced-parameter extracts of `sendclupdate()`/`dgramclient()`,
same "verbatim extract, no globals" style as `tankops.c`/`shellops.c`. One interop-driven
deviation from the pre-brief's sketch: `seq[MAXPLAYERS]` is passed as a separate `int32_t *`
parameter on both encode input and decode output, not embedded as a struct field — a fixed-size
C array as a struct member imports into Swift as an unsubscriptable N-tuple, unusable from a
differential test. `clupdate_layout_oracle` exposes `sizeof`/`offsetof` ground truth for the
header; `sizeof_cl_oracle`/`sizeof_sr_oracle` cover all 54 opcodes by switch. `CXBolo.h` now
includes the real `client.h`/`server.h`/`tracker.h`.

**Codec (`Sources/BoloNet/`):** `WireIO.swift` (BE read/write primitives, `fixedEncode`/
`fixedDecode`/`bradEncode`/`bradDecode`), `CLUpdateCodec.swift` (header + shell + explosion +
`CLUpdate.encode()`/`.decode()`, plus `isNewerSeq` for wraparound-tolerant sequence comparison),
`ClientMessages.swift` (20 `CL*` structs), `ServerMessages.swift` (34 `SR*` structs). All as
planned: pure value layer, no I/O, no `GameState` coupling.

**Real finding, not a transcription bug — logged here because it changes what "the C oracle"
computes for every future wave touching `FWIDTH`, same reason D26 has its own entry:** `FWIDTH`
(`bolo.h:67`) is `#define FWIDTH (256.0)` — an unsuffixed literal, so it's a C `double`, not a
`float`. `k2Pif` (`vector.c:17`) is `const float`. C's usual arithmetic conversions mean every
`x*FWIDTH` and `dir*(FWIDTH/k2Pif)` in `sendclupdate()`/`dgramclient()` computes in double
precision — `FWIDTH/k2Pif` promotes `k2Pif` to double first, then the outer multiply promotes
`dir`/`x` to double — before truncating (encode) or rounding to the destination `float` field on
assignment (decode). Caught by the full-256-value brad fuzz test: an all-`Float` Swift port of
the identical formula diverged from the oracle on a real fraction of inputs (roughly 1 in 4 of
the 256 `tankdir` byte values, in the initial run). Fixed by giving `fixedEncode`/`fixedDecode`/
`bradEncode`/`bradDecode` `Double` intermediates matching C's actual promotion — this is the
oracle's own arithmetic, not a Swift precision upgrade, so D18's "Float, never Double" rule
(which governs `BoloKit`'s stored state) doesn't apply to it.

**Trap list:** items 1 (`.tile` never written/read), 5 (fixed-point truncates), 6 (wraparound
sequence compare), and the item-7 correction (no double-`htons()` in `MSGNEARBY`) each have a
named regression test. Items 2/3/4/8 are logged in the pre-brief for their correct later
sub-waves (6.2–6.4) and not tested here, per that entry's scope.

**Test baseline: 329 → 345 (+16), all in new `Tests/DifferentialTests/NetCodecDifferentialTests.swift`.**
No existing test file touched. The 329 baseline (not 296 — Wave 5.7's stated count, now stale by
33 tests added in the interim per the current repo state) confirmed directly by `grep -rc
"@Test func\|func test" Tests/` before/after this session's addition, not assumed.

No `Package.swift` target/dependency changes beyond adding `BoloNet` to `DifferentialTests`'
dependencies (needed to import the new codec types for testing).

> **→ Planner:** Wave 6.0 done and committed. Ready for a 6.1 pre-brief (tick orchestrator —
> `runclient()`/`runserver()`) whenever you want it started; D27 already applies there per the
> pre-brief's trap-list item 8, so that pre-brief can lean on this session's groundwork rather
> than re-deriving it.
> **→ Parity:** `96704cd` is ready for audit. Per D25, check for accidental over-similarity to
> WinBolo's wire-format framing (never read, but flag if anything looks coincidentally close).
> The `FWIDTH`-is-double finding above is the one item here that isn't just "did the port match
> the brief" — worth independently re-deriving from `bolo.h`/`vector.c` rather than taking this
> entry's word for it, same rigor as any other oracle-behavior claim.

### [PARITY] 2026-09-02 — Wave 6.0 audit: PASS, no findings

**Type:** audit
**Phase:** Wave 6.0
**Blocks:** nothing — clears 6.0 for close-out

Independent post-commit audit of `96704cd` (wire codec) + `5c5e47a` (completion report) per
`docs/PLAN.md`'s D25 standing instruction and PLANNER's specific ask to independently re-derive
the `FWIDTH`-double claim rather than take it on faith.

- **`FWIDTH`-double finding: independently re-derived and confirmed correct.** Read `bolo.h:67`
  (`#define FWIDTH (256.0)`, unsuffixed double literal) and `vector.c:16-17` (`k2Pif` is `const
  float`) directly, then traced `sendclupdate()` (`client.c:3509-3592`) and `dgramclient()`
  (`client.c:1280-1472`) line by line. C's usual arithmetic conversions do force every `x*FWIDTH`
  and `dir*(FWIDTH/k2Pif)` through double precision — encode narrows via a truncating
  `(uint16_t)`/`(uint8_t)` cast, decode narrows via an implicit double-to-float assignment
  (rounding). `WireIO.swift`'s `fixedEncode`/`fixedDecode`/`bradEncode`/`bradDecode` correctly use
  `Double` intermediates for exactly this reason, correctly scoped as the oracle's own arithmetic
  rather than a D18 violation (D18 governs `BoloKit`'s stored sim state, not oracle-matching math).
- **Struct layout: hand-verified against the real headers**, not just the codec's own claims.
  `CLUpdateHeader.wireSize = 113` and `CLUpdateCodec.swift`'s field order match `client.h`'s
  packed `CLUpdate.hdr` field-by-field and byte-for-byte (offsets summed by hand:
  1+64+1+24+1+1+8+3+4+4+2 = 113, matching the differential test's per-field offsets).
  `CLUpdateShell` (10 B) and `CLUpdateExplosion` (6 B) check out the same way.
- **Trap-7 correction: independently confirmed**, not just trusted. Read `client.c:6705-6744`
  directly — `clsendmesg.mask = htons(0x00)` is a no-op, the proximity loop ORs bits in host
  order, `htons()` applies exactly once. DEEPDIVE1's claimed double-swap bug doesn't exist.
- `tankstatus`/`dead`/`boat` mapping, decode validation order, `.tile` handling (trap 1), and the
  `player == client.player` self-rejection being correctly deferred to 6.1 — all checked
  line-for-line against `client.c` and all match.
- **Test count verified independently**, not taken on faith: `grep -rc` across `Tests/` gives
  exactly 345, with 16 `@Test func` in the new file — matches the commit message exactly.
- **D25 (WinBolo over-similarity): moot for this sub-wave.** 6.0 is a pure value-layer codec
  derived directly and verifiably from the C oracle's byte layout — no transport or session
  architecture exists yet for WinBolo's design to have leaked into. Becomes meaningful at 6.3/6.4.
- **BoloNet pre-existence claim: confirmed** — the target predates Wave 6, not introduced by it.

**Limitation flagged by PARITY, recorded here as a standing fact about this audit method, not a
new decision:** this audit's environment has no Swift toolchain — the check is a line-for-line
hand-trace against `client.c`/`bolo.h`/`vector.c`, not a compile-and-run of the test suite.
Implementer's own green build remains the authoritative signal that the code actually builds and
the 345 tests actually pass; PARITY confirms the code is *correct against the oracle*, not that
it *executes*.

**No findings, no corrections needed. Wave 6.0 passes parity audit.**

**Scope note for the record, since "Parity is complete" was ambiguous in the relay:** this audit
covers Wave 6.0 (wire codec) only. Wave 6.1–6.5 (tick orchestrator, `recvsr*` handlers, session
logic, transport, tracker) are unstarted per `docs/PLAN.md` — Wave 6 as a whole is not complete.

> **→ Planner:** Wave 6.0 clean. Nothing blocking a close-out and a GO for 6.1's pre-brief.

### [PLANNER] 2026-09-02 — Wave 6.0 closed (PARITY PASS); GO for 6.1 pre-brief

**Type:** planning — close-out + GO
**Phase:** Wave 6.0 → 6.1
**Blocks:** nothing

PARITY's audit above is clean — no findings, and it independently re-derived the one claim I
specifically flagged as needing outside verification (the `FWIDTH`-double finding), not just
re-stated Implementer's report. **Wave 6.0 (wire codec) is complete and PARITY-passed.** Test
count: 329 → 345 (+16), all in `Tests/DifferentialTests/NetCodecDifferentialTests.swift`, per D28.

**Correcting scope for the record** (PARITY flagged this ambiguity and was right to): "Parity is
complete" referred to the Wave 6.0 audit only. Wave 6 as a whole is **not** complete — 6.1
(tick orchestrator) through 6.5 (tracker/NAT-PMP) remain unstarted, per D32's sub-wave split.
`docs/PLAN.md`/`CLAUDE.md` updated accordingly below, so this doesn't get misread later.

**Docs updated to close 6.0 and open 6.1** (committed alongside this entry):
- `docs/PLAN.md` — Wave 6.0's row moved to ✅ Complete — PARITY PASS, with commit hashes and test
  count. Wave 6 summary row status updated to reflect one of six sub-waves done.
- `CLAUDE.md` — "Current state" rewritten: Wave 6.0 closed, Wave 6.1 unblocked and next. Wave
  status table's 6.0 row moved to ✅ Complete; a new 6.1 row added, 6.2–6.5 row kept as blocked.

[TO: IMPLEMENTER] Wave 6.0 is closed — nice work, including catching the `FWIDTH`-double issue
yourself before PARITY ever saw it. **Cleared to write the Wave 6.1 pre-brief** (tick orchestrator
— `runclient()`/`runserver()`), same process as 6.0: read the C source yourself, write the
pre-brief directly into `docs/AGENT_NOTES.md` tagged `[TO: PLANNER]`, commit it. D27 applies
directly here per your own 6.0 pre-brief's trap-list item 8 (`explosionlogic` loops
`-1..<MAXPLAYERS`, `pilllogic` runs once not per-player, `sendclupdate` fires only on
`seq % 5 == 0`) — lean on that, don't re-derive it. This is a pre-brief GO, not a coding GO — as
with 6.0, I'll review the pre-brief before you start writing Swift.
[TO: PARITY] No action needed yet — 6.1 has no code. Thank you for independently re-deriving the
FWIDTH finding rather than taking the completion report's word for it — that's exactly the rigor
this role is for, keep applying it the same way to 6.1 onward, especially once 6.3/6.4 make the
D25 WinBolo-similarity check meaningful again.

### [PLANNER] 2026-09-02 — Cold-start restructure: three role bootstraps, not one

**Type:** planning — process restructure, no ruling
**Phase:** cross-wave (not tied to Wave 6)
**Blocks:** nothing

Jerod asked for the cold-start concept (previously a single `CLAUDE.md`, IMPLEMENTER-only) to be
redone as three separate files, one per role, focused on instructions rather than status — with
`docs/AGENT_NOTES.md` and `docs/PLAN.md` as the two common references so status/decisions live in
exactly one place each, not copy-pasted into every bootstrap.

**What changed:**
- **`docs/AGENT_NOTES.md`'s header** gained a `Commit discipline (all three roles)` note and a
  `Role bootstraps` pointer, alongside the existing `PARITY activation rule` and `Role split`
  notes. This is the new home for anything that would otherwise get duplicated across all three
  bootstrap files — the commit-discipline rule specifically, since it had already been stated
  once for IMPLEMENTER only and then the exact same gap recurred on PARITY's side this session.
- **`CLAUDE.md`** rewritten from scratch: dropped the "Current state" narrative and the "Wave
  status" table entirely (both duplicated `docs/PLAN.md`'s wave table and required PLANNER to
  touch this file at every wave transition — the recurring staleness this file's own header used
  to warn about). Dropped the "Non-negotiable rules" table's full explanatory text for every
  D-numbered rule (D18/D24/D25-D26-D27-D28-D29/D33) down to a one-line index, since the full text
  already lives in `docs/PLAN.md`'s decisions log — kept full text only for the three conventions
  that exist nowhere else (`no Foundation`, `Darwin OK`, `literal precision`). Dropped the
  "Key constants" table — already duplicated in `docs/PLAN.md`'s Wave 5.0 physics-constants
  section, now just a pointer. Kept: role definition, git workflow, PARITY-activation reminder,
  pointers to the other two bootstraps.
- **`docs/PARITY.md`** (new) — PARITY's own bootstrap: role definition, the no-Swift-toolchain
  limitation as a standing disclosure, how to audit (re-derive, don't restate; cite `file:line`),
  a decision-ID checklist (index only, same D-numbers as CLAUDE.md's list but framed as "what to
  check" rather than "what to obey"), and how to report (commit discipline, same as everyone).
- **`docs/PLANNER.md`** (new) — PLANNER's own bootstrap: role definition, the two-stage GO pattern
  (pre-brief GO, then coding GO after review) formalized as an explicit named pattern for the
  first time rather than left implicit across several `AGENT_NOTES.md` entries, PARITY activation
  ownership, which docs PLANNER owns and must keep in sync in the same sitting, commit discipline.
- **`docs/PLAN.md`'s header** — added one line pointing at all three bootstraps and naming
  `PLAN.md`/`AGENT_NOTES.md` as the two common references, for anyone who opens this file first.

**Deliberately NOT done:** no new shared "rules" file — Jerod named exactly two common points
(`AGENT_NOTES.md`, `PLAN.md`), so the commit-discipline note went into `AGENT_NOTES.md`'s existing
header rather than a fourth file. No new `docs/PLAN.md` decision (D35+) was added for `no
Foundation`/`Darwin OK`/`literal precision` — they stay CLAUDE.md-only since PARITY/PLANNER don't
need instructions to follow them, only IMPLEMENTER does, so keeping them in one file already
satisfies "don't duplicate."

[TO: IMPLEMENTER] Your bootstrap moved from a single big file to a leaner `CLAUDE.md` — re-read it
at your next session start rather than assuming you remember its old shape. Nothing about your
day-to-day workflow changed (same git workflow, same pre-brief ownership, same commit discipline);
only where things are documented and how much is restated changed.
[TO: PARITY] You now have your own bootstrap, `docs/PARITY.md` — read it at your next session
start instead of relying on ad hoc instructions relayed by Jerod each time.

### [IMPLEMENTER] 2026-09-02 — Wave 6.1 pre-brief: tick orchestrator

**Type:** planning (no code this entry)
**Phase:** Wave 6.1
**Blocks:** the Wave 6.1 GO

**Written at Jerod's direct request, ahead of the normal per-wave cadence.** `docs/PLAN.md`'s
wave table shows 6.1 with a pre-brief GO (issued after 6.0 closed and PARITY-passed) but no
pre-brief written yet; 6.2/6.3 are marked blocked on 6.0/6.1 and 6.0–6.2 respectively, and Wave
6.0's own history shows PLANNER gating pre-brief-writing itself, one sub-wave at a time. Jerod
asked for 6.1, 6.2, and 6.3 pre-briefs together in one session — this entry and the two after it
are the result. Noting this plainly rather than letting three pre-briefs appear with no matching
GO trail and no explanation.

**Scope (D32):** `runclient()` (`client.c:425-497`) and `runserver()` (`server.c:1083-1257`) —
composing already-shipped per-tick functions into the real sequence, plus what's genuinely new.

**Already shipped, just needs sequencing, no new logic:** `tankMoveTick` (loop all `MAXPLAYERS`,
vis increase/decrease on position change — independent per-player state, not a D27 hazard),
`TankLocalTick`'s local-input handling, `builderTick` (loop all `MAXPLAYERS`), `pillTick` (single
call, already D27-safe per its own FAIL/fix history), `shellTick` (loop all `MAXPLAYERS`),
`explosionTick` (needs confirming its current signature covers the `-1..<MAXPLAYERS` sentinel
range from `explosionlogic`, not just `0..<MAXPLAYERS`), `coolPills`/`replenishBases`/`growTrees`/
`chain`/`flood` (all exist in `GrowTrees.swift`/`MineChain.swift` with `onX` closure callbacks
already).

**Genuinely new, `runclient()` side:**
- `seq` increment + old-tank-position capture for the local player.
- Lagged-player status callback: two distinct thresholds (`3*TICKSPERSEC` and `TICKSPERSEC` ticks
  since `lastupdate`), both firing `setplayerstatus` — needs `seq`/`lastUpdate` (added to a
  BoloNet-side table per Wave 6.0's design call) wired into this loop.
- `CLUpdate` emission gated on `seq % 5 == 0` — mechanically ready now that 6.0's codec exists;
  6.1 only calls `CLUpdate.encode()`, doesn't build any new encoding.

**Genuinely new, `runserver()` side — the bulk of 6.1's real work:**
- **Pause state machine.** `server.pause` is tri-state in the C: `0` (not paused), positive
  (counting down, decrements every tick, emits `SRPause` on each second boundary), `-1`
  (indefinite pause, no countdown). `GameState` has no `pause` field yet.
- **Time-limit warnings.** Eight exact tick-equality checks (5 min / 1 min / 10s / 5s / 4s / 3s /
  2s / 1s / 0) against `server.timelimit`, each firing a distinct `sendsrtimelimit` value. Exact
  equality (`==`, not `>=`) — a tick skipped or double-counted anywhere upstream would silently
  drop a warning. `GameState` already has `ticks` (`GameState.swift:13`); has no `timeLimit` field.
- **Domination base-control win-condition — real trap, not obvious from a skim.**
  `server.c:1140-1176` increments `server.basecontrol` only while base 0 is held (armour ≥
  `MINBASEARMOUR`, owner ≠ neutral) AND every other base's owner is mutually allied with base 0's
  owner. The reset to `0` only happens in the *inner* `else` (all-bases-check failed while base 0
  itself is still held) — if the *outer* condition fails (base 0 not held, or `nbases == 0`),
  `basecontrol` is left **untouched**, not reset. A naive "reset whenever the win condition isn't
  fully met" port would diverge from this. `GameState.dominationType` (`GameObjects.swift:166`)
  exists; the `basecontrol` counter and `game.domination.basecontrol` threshold do not.
- **Disconnect-lagged-players decision.** `9*TICKSPERSEC` since `lastupdate` — the *decision* is
  pure per-tick state (compare and flag), but `removeplayer()`'s actual work (socket close, buffer
  drain, drop-pills side effect) is 6.3/6.4 territory. 6.1 should only detect and report which
  players are stale via a callback, leaving actual removal to 6.3.

**Design call, for PARITY to audit once code lands:** the orchestrator's outbound side effects
(`SRPause`/`SRTimeLimit`/`SRBaseControl`/`SRCoolPill`/`SRReplenishBase`/`SRGrow`, etc.) must
**not** be emitted as `BoloNet` wire-struct values directly from `BoloKit` — `Package.swift` has
`BoloNet` depending on `BoloKit`, not the reverse, and introducing that dependency backward would
be a real architecture regression, not a style preference. Continue the existing plain-data
closure-callback convention (`onGrow: (Int, Int) -> Void`, `onCoolPill: (Int) -> Void`, already
shipped in `GrowTrees.swift`) for every new emission point; wrapping those payloads into `SR*`
wire structs is a `BoloNet`-side (or future app-layer) adapter's job, not `BoloKit`'s.

**Trap-list carryover from 6.0's own pre-brief (item 8), restated here so 6.1 doesn't re-derive
it:** `explosionlogic` loops `-1..<MAXPLAYERS`, `pilllogic` runs once not per-player, `sendclupdate`
fires only on `seq % 5 == 0`.

**Test plan:** unit tests for the pause/timelimit/basecontrol state machines against hand-computed
tick sequences (pure control flow over already-oracle-tested primitives, no C oracle needed for
the sequencing itself) plus a named test exercising both the basecontrol increment path and the
untouched-not-reset path, since that asymmetry is exactly the kind of thing a partial test suite
would miss.

**Out of scope for 6.1:** `recvsr*` handlers (6.2), session/join/kick/ban/alliance (6.3),
transport/sockets (6.4), tracker/NAT-PMP (6.5).

No code changes this entry. Test baseline unchanged: **345** (confirmed via `grep -rc` immediately
before writing this entry, not assumed).

> **→ Planner:** Wave 6.1 pre-brief is complete and awaits a GO, same as 6.0's process. See the
> note at the top of this entry re: writing this (and 6.2/6.3) ahead of the normal per-wave GO
> sequence, at Jerod's direct request.
> **→ Parity:** No action needed yet — no code shipped.

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

### [IMPLEMENTER] 2026-09-02 — Wave 6.1 complete: tick orchestrator

**Type:** coding
**Phase:** Wave 6.1
**Blocks:** nothing — 6.1 done, 6.2 (`recvsr*` handlers) is next per D32

Commit `d0a9834`. Implemented against the pre-brief four entries above, one real scope-boundary
finding surfaced mid-implementation (below) plus one deliberate refinement over the pre-brief's
own framing.

**`Sources/BoloKit/GameState.swift`:** added `pause`/`timeLimit`/`baseControlThreshold`/
`baseControlCounter` — session state `runclient()`/`runserver()` need that nothing in `GameState`
modeled yet. All defaulted, appended after the existing params, so no existing call site broke.

**`Sources/BoloKit/RunTick.swift`:** `runTick(state:ticksSinceLastUpdate:...)` sequences every
already-shipped Wave 5 per-tick function (`tankMoveTick`, `tankLocalTick`, `builderTick`,
`pillTick`, `shellTick`, `explosionTick`, `coolPills`, `replenishBases`, `growTrees`, `chain`,
`flood`) into one combined pass, plus the genuinely new pieces: a pause state machine, exact-
tick-equality timelimit warnings, and the domination base-control win-condition — including its
trap from the pre-brief, preserved exactly and covered by a named test
(`runTickBaseControlUntouchedWhenBaseZeroNotHeld`): the counter resets to 0 only when the
all-bases alliance check fails while base 0 is still held, and is left **untouched** (not reset)
when base 0 itself isn't held. `seq`/`lastUpdate` stay outside `BoloKit` per Wave 6.0's design
call — `runTick` takes per-player elapsed-tick data as a read-only input and never decides
`CLUpdate` emission cadence itself; that's the caller's job once `seq` is available to it.

**Refinement over the pre-brief, stated plainly since it changes what the pre-brief promised:**
disconnect handling does `removeplayer()`'s pure core (drop onboard pills via the existing
`dropPills`, flip `connected` off) directly inside `runTick`, not just detection-and-report as the
pre-brief framed it. Reason found during implementation: `coolPills`/`replenishBases`/`growTrees`
need the post-disconnect connected-player count the *same* tick, matching C's own ordering
(`server.c:1188-1246` disconnects before those three calls use the resulting `nplayers`) — leaving
it as detection-only would give those three functions a stale count for one tick versus the
oracle. Socket close stays 6.3/6.4's job via the `onPlayerDisconnected` callback; only the pure
state mutation moved into 6.1.

**Real scope-boundary finding, not resolved here, flagged for PLANNER:** nothing in the shipped
codebase wires `onMineExplosion`/`onSuperboomTerrain`/`onDropPills` into `explosionAt`/
`superboomAt` outside `chainAt`/`floodAt`'s own internal calls — confirmed by grep, not assumed.
Every tank/builder/shell trigger site (`enterTile`, `grabTile`, `tankMoveTick`'s dead-tumble,
`smallboom`/`superboom`) still surfaces these as documented no-op injection points, exactly as
every wave from 5.2b onward left them "for a later wave." `runTick`'s own same-named parameters
are plain pass-throughs to its caller, not wired to `explosionAt`/`superboomAt`/`spawn`/
`killPointBuilder`. Wiring the full mine-cascade correctly (with correct causer-player attribution
at every trigger site, and the mutual-recursion shape `explosionAt`↔`smallboom`/`superboom`
already has internally) is real, undesigned subsystem work — the same shape of discovery that
split Wave 5.5a out of 5.2b under D22 — not something to silently absorb into "orchestration."
Recommend PLANNER decide where this lands: its own sub-wave, folded into 6.2 (which already
touches several of these trigger sites via `recvsr*`), or deferred until the UI/app layer exists
(since the original doc comments frame several of these injection points as UI-adjacent).

**Design synthesis, stated as mine for PARITY to audit:** the real `runclient()`/`runserver()` are
two independent, unsynchronized processes with no defined interleaving order. `runTick` runs
server-role bookkeeping (pause/timelimit/basecontrol/disconnect/coolpills/replenish/growtrees/
chain/flood) first, then client-role per-player physics second — a new synthesis choice, not a
transcription, documented in the file header so it isn't mistaken for one.

**Test baseline: 345 → 361 (+16), all in new `Tests/BoloKitTests/RunTickTests.swift`.** Covers the
pause state machine (indefinite, countdown-with-emission, normal ticking), timelimit warnings
(exact-boundary fire, reached-freezes, off-boundary no-op), base-control (increment while held,
warning-then-freeze, the untouched-vs-reset asymmetry as two separate named tests, no-bases-
configured), disconnect detection (drops pills + flips connected, below-threshold no-op), lagged-
status callback (both thresholds, and the gap between them), and full-tick sequencing smoke tests
(multi-tick base replenish, mixed dead/alive players, no crashes). One test
(`runTickSkipsLocalPlayerLogicWhenLocalPlayerIndexOutOfRange`) was written, found to crash the
whole `BoloKitTests` process, and removed rather than "fixed" — it exercised an out-of-bounds
`localPlayer` index, an invariant violation `tankMoveTick` (and every other Wave 5 function reading
`state.localPlayer`) already trusts unconditionally with no defensive guard; adding one only to
`runTick` would have been inconsistent, not a real fix. No test-count loss from this — the removed
test never should have existed, so nothing is missing per D28's intent (it's not a coverage
regression, since it tested an impossible state, not real behavior).

No `Package.swift` changes. Build and full suite green before commit.

> **→ Planner:** Wave 6.1 done and committed. The mine-cascade-wiring gap above is the one item
> that needs a scoping decision before 6.2 (or whenever it gets addressed) — everything else is
> either exactly per the pre-brief or a stated, reasoned refinement over it. Ready for a 6.2
> pre-brief-to-coding-GO whenever you want it (6.2's pre-brief already stands as reviewed per your
> prior entry).
> **→ Parity:** `d0a9834` is ready for audit. Per your own ask: the basecontrol reset-vs-untouched
> asymmetry has a named regression test now
> (`runTickBaseControlUntouchedWhenBaseZeroNotHeld` vs. `runTickBaseControlResetWhenOtherBaseNotAllied`)
> — worth independently re-deriving from `server.c:1140-1176` directly rather than trusting this
> report's reading of it. The disconnect-handling refinement (pure `removeplayer()` core moved
> into 6.1) is the other thing most worth checking against `server.c:1188-1246`'s exact ordering.

### [PLANNER] 2026-09-02 — Wave 6.1 sent to PARITY; mine-cascade wiring gap ruled as new Wave 5.9

Reviewed `d0a9834`/`b028bf8`. Nothing blocking: the disconnect-handling refinement (moving
`removeplayer()`'s pure core into `runTick` rather than detect-only) is well-justified against
`server.c:1188-1246`'s actual ordering, and the removed out-of-bounds-`localPlayer` test was the
right call — it exercised an invariant no other Wave 5 function guards either, not a real
behavior. `runTick`'s server-then-client sequencing is correctly flagged as a synthesis choice,
not a transcription, since the real `runclient()`/`runserver()` have no defined interleaving.

**Ruling on the mine-cascade wiring gap:** this is unfinished Phase 3 port work, not a new
design question and not Wave 6 scope — the engine functions shipped in 5.5a, only their trigger
sites (`enterTile`/`grabTile`/`tankMoveTick`'s dead-tumble/`smallboom`/`superboom`) were never
wired, left as no-ops since 5.2b. Opened as **Wave 5.9** in `docs/PLAN.md` rather than folded into
6.2 (which only applies already-decided values, never re-triggers cascades — confirmed no
dependency either direction) or deferred to a UI layer (this is gameplay-affecting simulation
state, not presentation). No pre-brief yet; sequencing relative to 6.2+ is open for Jerod to
prioritize.

[TO: PARITY] `d0a9834`+`b028bf8` ready for audit. Priority: the basecontrol reset-vs-untouched
asymmetry (two named tests already exist — verify against `server.c:1140-1176` directly) and the
disconnect-ordering refinement (`server.c:1188-1246`).
[TO: IMPLEMENTER] Proceed to Wave 6.2's coding GO once PARITY passes 6.1 — no need to wait on
Wave 5.9, which is independent and unscheduled for now.

### [PARITY] 2026-09-03 — Wave 6.1 audit: 2 findings (1 real gap, 1 undisclosed simplification)

**Type:** audit
**Phase:** Wave 6.1
**Blocks:** recommend PLANNER hold 6.1's close-out for a ruling on Finding 1 before GO'ing 6.2

Independent post-commit audit of `d0a9834` (tick orchestrator) + `b028bf8` (completion report),
per `docs/PARITY.md` and PLANNER's specific ask to re-derive the basecontrol asymmetry and the
disconnect-ordering refinement rather than trust the completion report.

**Re-derived and confirmed correct, hand-traced against `server.c`/`client.c` directly:**
- Pause gate (`RunTick.swift` step 1) matches `server.c:1088-1099` exactly — full early return
  while paused, decrement-then-modulo-check order preserved, `onPause` argument
  (`pause/TICKSPERSEC`) matches `sendsrpause`'s.
- Time-limit warning chain (step 2) matches `server.c:1102-1135` field-for-field: same eight
  offsets checked in the same order, same "reached" vs. "exceeded" early-return split (reached
  does its own `ticks+=1` then returns; exceeded returns without incrementing).
- Basecontrol asymmetry (step 3), the specific item flagged for re-derivation: confirmed against
  `server.c:1140-1176` directly. The reset-to-0 only happens in the alliance-loop's failure branch
  (`else { server.basecontrol = 0; }`); when base 0 itself isn't held (or `nbases == 0`), the
  outer `if` is simply false and the counter is untouched by construction — `RunTick.swift`'s
  structure (outer `if` gating an inner `allAllied` bool that only resets on failure) reproduces
  this exactly, including the `nbases == 1` edge case (C's `for` loop never executes, `i` stays at
  its initial value `1 == nbases`, condition trivially true — Swift's `1..<1` empty range leaves
  `allAllied` at its initial `true` the same way). Both named tests
  (`runTickBaseControlUntouchedWhenBaseZeroNotHeld` / `...ResetWhenOtherBaseNotAllied`) exercise
  exactly this asymmetry and match my hand-derived expectations.
- The domination-only gating: confirmed the port-wide "gametype is always domination" simplification
  is real, not assumed — `client.c:707-723` hits `assert(0)` in the join-preamble parse for any
  non-domination `bolopreamble.gametype`, so a session that successfully joins is domination by
  construction. `RunTick.swift`'s basecontrol block correctly omits an explicit gametype switch on
  this basis (minor citation nit: `GameObjects.swift`'s existing comment attributes the assert to
  `spawn()`; the actual site is the join-preamble parse at `client.c:717-723` — cosmetic, inherited
  from Wave 5.x, not this commit, not worth a fix on its own).
- Disconnect-ordering refinement: confirmed against `server.c:1188-1246` directly. `nplayers` in C
  is computed in the same loop that disconnects stale players, before `coolPills`/`replenishBases`/
  `growTrees` consume it (`server.c:1206-1246`) — `RunTick.swift` flips `connected = false` for
  disconnected players before calling those three (which independently recompute their own
  `nplayers` as `state.players.filter { $0.connected }.count`), landing on the same count for the
  same tick. `removeplayer()`'s pure core (`server.c:584-609`: pill-mask-then-`droppills`, using
  the player's own tank position) matches the ported pill-drop step field-for-field; `closesock`
  (`io.c:264-279`) setting `*sock = -1` confirms `connected == (cntlsock != -1)` is the right
  representation choice, not a new assumption.

**Finding 1 (real, actionable) — `pauseonplayerexit` side effect missing from the lagged-disconnect
path.** `server.c:1192-1197`, inside the exact function/line-range (`server.c:1083-1257`) this
wave claims to port, sets `server.pause = -1` (and would broadcast `sendsrpause(255)`) when a
lagged player is disconnected **and** the server was configured with `pauseonplayerexit`. This is
pure `GameState` mutation with no transport dependency — it does not fit the stated deferral
rationale ("`removeplayer()`'s actual work... is 6.3/6.4 territory"), since it isn't
`removeplayer()`'s code at all; it's `runserver()`'s own code sitting directly after the
`removeplayer()` call at the same nesting level as the disconnect loop. `GameState` has no
`pauseOnPlayerExit` field — notable because this commit's own message frames `pause`/`timeLimit`/
`baseControlThreshold`/`baseControlCounter` as "session state that runclient()/runserver() need
and nothing in GameState modeled yet," which `pauseonplayerexit` equally is, sitting right next to
`pause` in the same struct in `server.h`. Unlike the mine-cascade gap (prominently flagged, routed
to a new Wave 5.9), this one has no mention anywhere in the pre-brief or completion report. No test
exercises it, consistent with the field not existing. Recommend either wiring a
`pauseOnPlayerExit: Bool` field + the mutation now (small, matches this wave's existing pattern),
or explicitly flagging it as a deferred gap the way Wave 5.9 was — but not shipping it silently
uncounted, since a live server configured with this option would see the game continue past a lag
disconnect that the C oracle would have frozen indefinitely.

**Finding 2 (documentation gap, likely-correct but undisclosed) — the `seq != 0` half of
`runclient()`'s move-tank gate has no analog, and isn't mentioned.** `client.c:451`:
`if (client.players[i].connected && client.players[i].seq != 0)` gates `tankmovelogic(i)` in the
real move-tanks loop. `TankTick.swift`'s `tankMoveTick` (Wave 5.2a, unchanged by this commit)
already guards on `connected` (line 93); `RunTick.swift` step 7 calls it unconditionally for every
player index with no `seq`-equivalent gate. Given `seq` was deliberately kept out of `BoloKit`
(Wave 6.0's design call), this can't be replicated verbatim — and it's likely genuinely
inapplicable in a single-authoritative-state model (`seq != 0` in the real distributed client means
"we've never received a real update about player i yet," a network-bootstrapping concern that
doesn't exist when `GameState` *is* the source of truth rather than a mirror waiting on broadcasts,
unlike `connected`, which already implies real state exists). This is the same shape of
simplification as the `timelimitreached`/`basecontrolreached` flag unification `RunTick.swift`'s
own header explicitly discloses — but this one isn't disclosed anywhere. Recommend Implementer add
one line to the file header (or step 7's comment) stating the same reasoning explicitly, so a
future reader doesn't mistake this for an untraced gap the way I nearly did.

**Everything else checked line-for-line against `client.c`/`server.c` and matches:** the lagged-
status callback's exact-equality double-threshold (`client.c:437-447`), `runclient()`'s
`pause || timelimitreached || basecontrolreached` top gate being subsumed by `runTick`'s
server-role-first sequencing (already disclosed in the file header, re-verified rather than
trusted), and `explosionTick`'s `-1` sentinel + `0..<MAXPLAYERS` coverage (pre-existing Wave 5.5b
code, unchanged by this commit — confirmed via `git show --stat d0a9834`, not re-audited).

**Standing limitation, same as every PARITY entry:** no Swift toolchain in this environment — this
is a hand-trace against the C source, not a compile-and-run. Implementer's green build remains the
authority that the code executes; this audit is the authority that it's correct against the oracle.

**Test count verified independently:** `grep -rc "@Test func\|func test" Tests/` gives 361;
`RunTickTests.swift` has 16 `@Test func` — matches the commit message exactly.

> **→ Planner:** Two findings above, ranked by severity. Finding 1 is a real, evidenced gap in a
> function this wave claims to fully port — recommend a ruling (add the field now vs. open a
> tracked gap like Wave 5.9) before closing 6.1 out as clean. Finding 2 is lower stakes (likely
> correct, just undocumented) — a one-line disclosure closes it, no design change needed.
> **→ Implementer:** See Finding 1/2 above for the specific gaps; both are narrow, scoped fixes,
> not a rework of `RunTick.swift`'s structure.

### [PLANNER] 2026-09-03 — Jerod's ruling on Wave 6.1 PARITY findings: fix both before 6.2 GO

**Type:** planning — ruling + handoff
**Phase:** Wave 6.1 → 6.2
**Blocks:** Wave 6.2 coding GO

Jerod's ruling on PARITY's two Wave 6.1 findings above (`c1cddee`): both get fixed before Wave 6.2
opens, not deferred the way Wave 5.9 deferred the mine-cascade gap. Logged as **D35** in
`docs/PLAN.md`. Reasoning: unlike Wave 5.9 (independent engine work, confirmed decoupled from
6.2+), Finding 1 sits inside the exact function this wave claims to have fully ported, and
Finding 2 is a one-line disclosure — both are small enough to close before 6.2 starts rather than
carry forward as tracked debt.

**Session note:** we're low on usage credits right now, so this entry does the ruling and the
hand-off to Implementer in one pass rather than the usual GO-then-pre-brief-review round trip.
Implementer should treat this as both the ruling and the GO to plan and execute Finding 1/2's fix
directly — no separate pre-brief-review cycle needed unless the plan surfaces something that
changes scope, in which case log it here as a question rather than resolving solo per the usual
rule.

**Docs updated to reflect this (committed alongside this entry):**
- `docs/PLAN.md` — new **D35** in the decisions log (right after D34); Wave 6.1's status row
  updated to reflect the audit outcome and the fix-before-6.2 ruling; Wave 6's summary row
  updated to match.

[TO: IMPLEMENTER] Read PARITY's Wave 6.1 audit above in full (`c1cddee`, the
"### [PARITY] 2026-09-03 — Wave 6.1 audit: 2 findings" entry) before starting — both findings are
already hand-traced against the C source there, don't re-derive them. Then plan and execute a fix
for both, and close Wave 6.1 out for real before opening 6.2:

- **Finding 1 (real gap):** `server.c:1192-1197`'s `pauseonplayerexit` → `server.pause = -1` side
  effect on a lagged-player disconnect has no `GameState` field and no `RunTick.swift` wiring.
  PARITY's recommendation: add a `pauseOnPlayerExit: Bool` field alongside the `pause`/`timeLimit`/
  `baseControlThreshold`/`baseControlCounter` session-state fields this wave already added, and
  wire the mutation into the disconnect path. Small, matches this wave's existing pattern — your
  call on the exact shape, but it should land as a real fix this time, not a deferred/flagged gap
  (no independent-of-6.x rationale exists here the way it did for Wave 5.9's mine cascade).
- **Finding 2 (doc-only):** `client.c:451`'s `seq != 0` half of the move-tank gate has no analog
  in the unified `GameState` model and wasn't disclosed. One line in `RunTick.swift`'s file header
  or step 7's comment, same style as the existing `timelimitreached`/`basecontrolreached`
  disclosure, closes this — no design change.
- Per D28, note the before/after test count in your completion report even though this is a small
  fix, not a full wave.
- Once both land and you've committed, tag `[TO: PARITY]` for a fast re-audit of just these two
  spots, then `[TO: PLANNER]` to close 6.1 and GO Wave 6.2.

[TO: PARITY] No action needed until Implementer's fix lands — flagging here so the thread is
visible when you pick this back up for the re-audit.

### [IMPLEMENTER] 2026-09-03 — Wave 6.1 D35 fix complete: both PARITY findings closed

**Type:** coding (small fix, not a full wave)
**Phase:** Wave 6.1 → 6.2
**Blocks:** nothing — ready for PARITY re-audit, then PLANNER's Wave 6.2 GO

Commit `1e0cbe6`. Both findings from PARITY's Wave 6.1 audit fixed per Jerod's D35 ruling, exactly
as specified — no scope surfaced that changed the plan, so no mid-fix question needed.

**Finding 1 (real gap) — fixed.** `Sources/BoloKit/GameState.swift` gains
`pauseOnPlayerExit: Bool` (default `false`), mirroring `server.pauseonplayerexit`.
`Sources/BoloKit/RunTick.swift`'s disconnect loop (step 4) now sets `state.pause = -1` and calls
`onPause(255)` right after `onPlayerDisconnected(player)` when the flag is set — matching
`server.c:1192-1197`'s nesting level exactly. Reused the existing `onPause` callback rather than
adding a new one: `255` is already the wire's established "indefinite pause" sentinel (confirmed
via `joinplayerserver()`'s `bolopreamble.pause = 255` for `server.pause == -1`), so no new
callback contract was needed.

**Finding 2 (doc-only) — fixed.** Added a disclosure comment at `RunTick.swift` step 7, same
style/rigor as the existing `timelimitreached`/`basecontrolreached` header disclosure: `seq != 0`
(`client.c:451`) has no analog in a unified authoritative-state model and is inapplicable by
construction, not an untraced gap. No behavior change.

**Tests:** two new, named for the exact scenario PARITY described —
`runTickPauseOnPlayerExitPausesIndefinitelyOnDisconnect` (flag set, disconnect fires, asserts
`pause == -1` and `onPause` received `255`) and
`runTickPauseOnPlayerExitDefaultFalseLeavesPauseUntouched` (default `false`, same disconnect
scenario, asserts `pause` stays `0` — a regression guard against the new field defaulting to
active).

**Test baseline: 361 → 363 (+2), per D28.** Full suite green before commit.

No other files touched — `Package.swift` unchanged, no new targets/dependencies.

> **→ Planner:** Both D35 findings closed. Recommend closing Wave 6.1 out for real once PARITY's
> re-audit comes back clean, then GO'ing Wave 6.2 (its pre-brief already stands as reviewed from
> the earlier batch).
> **→ Parity:** Ready for the fast re-audit of just these two spots you flagged:
> `RunTick.swift`'s disconnect loop (Finding 1 — check `pauseOnPlayerExit`'s wiring against
> `server.c:1192-1197` directly, and that `255` is really the right sentinel, not assumed from this
> report) and step 7's new comment (Finding 2 — confirm it says what you'd have wanted disclosed,
> not just that a comment now exists).

### [PLANNER] 2026-09-03 — D35 fix reviewed, activating PARITY for re-audit

**Type:** planning — review + activation
**Phase:** Wave 6.1 → 6.2
**Blocks:** Wave 6.2 coding GO (until PARITY's re-audit comes back clean)

Reviewed `1e0cbe6` (fix) and `91c4a8d` (completion report) against D35's ruling. Scope matches
exactly — `GameState.pauseOnPlayerExit` added, disconnect loop wired at the same nesting level as
`server.c:1192-1197`, `onPause(255)` reused rather than a new callback. Independently checked the
sentinel claim directly against the oracle rather than trusting the report: `server.c:862-863`
does set `bolopreamble.pause = 255` when `server.pause == -1`, confirming 255 is the right value,
not assumed. Finding 2's disclosure comment is in place at step 7. Two new tests, named for the
exact scenarios PARITY described; baseline 361 → 363 (+2), per D28. Nothing else touched.

This is a scope/consistency check, not a substitute for PARITY's own line-by-line re-derivation —
still standing on the "no Swift toolchain here" limitation every PLANNER/PARITY review carries.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — Wave 6.1/6 rows updated to
"D35 fix committed, awaiting PARITY re-audit."

[TO: PARITY] Activating for the fast re-audit Implementer's report asked for — just the two spots:
`RunTick.swift`'s disconnect loop (Finding 1 — verify `pauseOnPlayerExit`'s wiring against
`server.c:1192-1197` directly, including that `255` is really the established sentinel and not
just asserted) and step 7's new disclosure comment (Finding 2 — confirm it says what you'd have
wanted disclosed). Commits: `1e0cbe6` (fix), `91c4a8d` (report). If clean, PASS and tell Implementer
6.1 is closed for real — Wave 6.2's coding GO follows immediately, no separate PLANNER round trip
needed given where session credits stand; if not clean, route back through PLANNER as usual.
