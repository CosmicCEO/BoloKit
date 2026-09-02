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
