# DEEPDIVE1 — Wave 6 wire-format verification + full scoping pass

> **Assignment doc for a dedicated IMPLEMENTER session, created by PLANNER 2026-09-02.**
> Read `CLAUDE.md` first, as always — this doc doesn't replace your normal orientation, it's the
> specific task Jerod is pointing you at for this session. Everything you need to execute without
> going back for more context should be here; if you find a genuine gap, log it as a question
> rather than guessing and pushing forward.

## Why this session exists

Jerod told PLANNER he's willing to be flexible and creative about GPL exposure if it reduces
time-to-market or implementation cost — a real reopening of **D25** (WinBolo, GPL v2, was
read-only/clean-room-reference-only) and by extension **D13** (BoloKit stays MIT). PLANNER laid
out four options ranging from "change nothing" to "relicense the whole project GPL." The cheapest
one to evaluate — and the one Jerod picked to act on first — is: **adapt WinBolo's wire-format
struct definitions directly (small, isolated, easy-to-contain GPL exposure) instead of deriving
the format independently from the C oracle**, *if and only if WinBolo's framing actually matches
the Mac Bolo 0.99.7bv oracle's*. Nobody has checked that yet. That factual check is this session's
job. This has been logged as **Q19** in `docs/PLAN.md`'s open-questions table, alongside **Q16**,
**Q17**, and **Q18** (your own Wave 6 scope-survey questions from the prior session, now
formalized with permanent IDs per the doc's ID convention — see that file's header note).

**Time budget: about an hour**, per Jerod. This is a fact-finding pass, not a wave. No code
changes, no `Package.swift` edits, no commits to `main`. If you're not converging within the
budget, stop and report what you found plus what's still open — don't push through to "finish."

## Primary task: does WinBolo's framing match the oracle?

1. Get WinBolo/LinBolo source read-only: `github.com/kippandrew/winbolo`, GPL v2, "copyright
   1998-2008 John Morrison" (already confirmed in D25 — no need to re-verify licence/provenance).
   **D25's clean-room discipline applies to this investigation too**: read for comparison and
   understanding, take notes in your own words. Do not copy, paste, or closely paraphrase any of
   its source into this repo's tree or into `AGENT_NOTES.md`. You are answering a factual
   question about structural similarity, not producing code — there is nothing to write that
   should ever look like WinBolo's actual text.
2. Find WinBolo's packet/protocol definitions — its client-server wire structs, sequence
   handling, framing. (Its own network/protocol source files; check both the classic C client and
   server sides, since Wave 6 needs both.)
3. Compare against the real oracle's actual format, already documented in the prior session's
   trap-list seed (`AGENT_NOTES.md`, `[IMPLEMENTER] 2026-09-02 — Wave 6 scope survey`) and
   directly in `Reference/c/client.c`/`server.c`: the ~40 `CL*`/`SR*` structs, `sendclupdate()`
   (client.c:3572), `dgramclient()` (client.c:1427), and the three-encodings-in-one-packet scheme
   — raw IEEE-754 float byte-swap for tank/builder positions, 1/256 fixed-point for shell/
   explosion positions, 8-bit values for directions/turns.
4. Answer explicitly, with evidence (struct-by-struct or field-by-field comparison, not a
   vibe-level impression):
   - Byte-for-byte identical framing? Structurally parallel but different scaling/constants?
     Substantially different design?
   - Does WinBolo negotiate or support multiple Bolo protocol versions, and if so, is 0.99.7bv
     (or something byte-compatible with it) one of them? (D4 said no interop was ever a goal, so
     this was never checked — don't assume either answer.)
   - **The question that actually matters for Q19:** would adapting WinBolo's struct definitions
     save real verification work over deriving the format independently from the C oracle, or
     would it require just as much cross-checking against the oracle to trust it — in which case
     it saves nothing and just adds GPL exposure for free?

## Secondary task: finish the Wave 6 scoping inputs in the same pass

You're already deep in both codebases for the primary task — use that state to close out Q16/Q17
so a later session doesn't have to re-read the same source from scratch.

- **Q16** (transport: port POSIX bug-for-bug, or port wire format byte-exact + rebuild the
  mechanism on Network.framework/async-await): restate your existing recommendation in light of
  what you found. If WinBolo's framing doesn't match the oracle, this is unaffected. If it does
  match, note whether that changes the cost/benefit of either option.
- **Q17** (proposed 6.0–6.5 sub-wave split — 6.0 wire codec, 6.1 tick orchestrator, 6.2 `recvsr*`
  broadcast handlers, 6.3 server session logic, 6.4 transport + join handshake, 6.5 tracker/NAT,
  arguably deferrable under D4): update 6.0's scope description if the framing verdict changes
  what that sub-wave actually involves (adapting vs. independently deriving the codec are
  different amounts of work). Leave 6.1–6.5 as-is unless something you found changes them too.
- **Q18** (Phase 2 art vs. Phase 3 port sequencing, git-history-rewrite cost) is explicitly not
  yours to resolve — PLANNER owns resequencing calls. Don't let it block this pass; just don't
  touch it.
- If anything else about WinBolo's code surfaces that's relevant to whichever path gets chosen
  (a bug, a design choice, a NAT/tracker approach worth knowing about), note it in your own words,
  same clean-room discipline as the primary task.

## Deliverable

One `[IMPLEMENTER]` entry in `docs/AGENT_NOTES.md`, tagged `→ Planner`, containing:

- The framing-match verdict with evidence, and a direct answer to "does adapting save real work."
- Updated Q16 recommendation (restated or revised) and Q17 sub-wave split (updated or unchanged),
  each with a one-line note on whether the framing finding changed anything.
- Nothing written to `Reference/`, no new git submodule, no code in `Sources/` — if you clone
  WinBolo to read it, keep it outside the tracked tree (e.g. `/tmp` or a gitignored scratch dir)
  and don't commit anything from it.

**Not your call this session:** whether to actually adopt WinBolo's framing (Option 2), GPL the
whole networking module (Option 3), or go further (Option 4) — that's Jerod's decision, informed
by what you find here. Your job is the fact, not the ruling.

---

# DEEPDIVE1 — session close-out (IMPLEMENTER, 2026-09-02)

> Closed out by Jerod's call ("your analysis is sufficient at this time") before the WinBolo-side
> read was performed. This section records what was actually established, what was not, and the
> executable method for the part left undone — so nothing here has to be re-derived.

## Status: PRIMARY TASK NOT COMPLETED

**The framing-match question (Q19's precondition) is still OPEN.** WinBolo was never cloned, read,
or compared. Network egress to `github.com/kippandrew/winbolo` was confirmed reachable (HTTP 200)
and no local copy exists — that is the full extent of the WinBolo-side work. **There is no framing
verdict in this document, and none should be inferred from it.**

What *was* completed: a full, citation-backed map of the oracle's own wire format (below), which is
one half of the comparison and the half that was going to be needed under every Q19 option anyway.

## Finding 1 — the oracle's wire format, fully mapped

All citations are `Reference/c/`. This supersedes the prior session's trap-list seed in detail.

**Protocol files:** `bolo.h` (513 lines, opcode enums + `JOIN_Preamble`), `client.h` (373, `Client`
+ 20 `CL*` structs + 3 `CLUpdate*`), `client.c` (7125), `server.h` (382, `Server` + 34 `SR*`),
`server.c` (4423), `buf.c`/`buf.h` (byte-queue only — no numeric helpers), `bmap.h` (`BOLO_Preamble`),
`tracker.h`/`tracker.c`, `resolver.c`, `errchk.h`. There is no `protocol.c`/`net.c`/`dgram.c`.

**TCP control channel.** 20 client→server opcodes (`bolo.h:167-188`, `kHangupClientMessage = 0` …
`CLSETALLIANCE = 19`) and 34 server→client (`bolo.h:203-238`, `SRPLAYERJOIN = 0` … `SRPAUSE = 33`).
Dispatch is a `switch` on the first buffered byte without consuming it (`client.c:800`,
`server.c:991`); each handler re-checks `nbytes >= sizeof(struct …)` and `FAIL(EAGAIN)` if short.
**No length prefix** — length is implied by opcode, except the two chat messages which are struct +
NUL-terminated text, scanned for `'\0'` (`client.c:1504-1512`, `server.c:2072-2079`). Every `CL*`/
`SR*` struct is `__attribute__((__packed__))` (`client.h:162-336`, `server.h:124-330`) — the sole
exception is `SRHangUp` (`server.h:124`), harmless at one byte, and `SRHANGUP` is marked "not used"
(`bolo.h:210`).

**UDP state channel.** `struct CLUpdate` (`client.h:308-336`): a packed 113-byte header, then
`nshells` × 10-byte `CLUpdateShell`, then `nexplosions` × 6-byte `CLUpdateExplosion`, no alignment
gap. `sizeof(struct CLUpdate) == 4193`. Header offsets: `player` 0, `seq[16]` 1–64, `tankstatus` 65,
`tankx/y/speed/turnspeed/kickdir/kickspeed` 66–89, `tankdir` 90, `builderstatus` 91, `builderx/y`
92–99, `buildertargetx/y` 100–101, `builderwait` 102, `inputflags` 103, four sound flags 107–110,
`nshells` 111, `nexplosions` 112. **No opcode byte and no magic** — the datagram *is* a `CLUpdate`;
`player` is self-asserted and cross-checked only against source IP (`server.c:663-668`).
`player == 255` is reserved as the tracker probe sentinel.

**Cadence and sequencing.** `sendclupdate()` (`client.c:3509-3592`) fires from `runclient()` on
`seq % 5 == 0` (`client.c:487-489`) → **10 Hz** against a 50 Hz tick (`TICKSPERSEC`, `bolo.h:41`).
Every datagram carries all 16 players' `seq` values, each `htonl` (`client.c:3521-3523`) — this
doubles as the ack/latency mechanism. `dgramclient()` (`client.c:1280-1472`) validates framing by
exact length recomputation (`client.c:1303-1310`), does its `ntohl` pass (`client.c:1312-1325`),
and drops stale/duplicate datagrams via a signed wraparound-tolerant `> 0` compare
(`client.c:1333`). **No acks, no NAKs, no retransmit, no fragmentation, no reorder buffer** —
reliability for state-changing events lives entirely on TCP. Latency is hidden by re-simulating
`(ourSeq − theirViewOfOurSeq)/2` ticks of dead reckoning (`client.c:1446-1454`). The server relays
without rewriting the payload: it reads only `seq` and `tankx/y` for authority checks, re-learns the
UDP source port for NAT rebinding (`server.c:676-678`), then blind-forwards the original bytes
(`server.c:683`).

**The three encodings, confirmed.** There are no `htonf`/`ntohf` helpers anywhere in the tree;
everything is inline `htonl`/`htons` plus type-punned casts.

| Encoding | Fields | Cite |
|---|---|---|
| Raw BE IEEE-754 `float` as `uint32` | 6 tank (`x`, `y`, `speed`, `turnspeed`, `kickdir`, `kickspeed`) + 2 builder (`x`, `y`) | encode `client.c:3526-3535`, decode `client.c:1352-1360`, server `server.c:673-674` |
| 1/256 fixed-point `uint16` (`FWIDTH`, `bolo.h:67`) | shell + explosion positions, shell `range` | encode `client.c:3561-3566`, `3578-3579`; decode `client.c:1416-1421`, `1434-1435` |
| 8-bit brads, scale `FWIDTH/k2Pif` = 256/2π | `tankdir`, `shelldir` | encode `client.c:3532`, `3565`; decode `client.c:1351`, `1420` |

Same raw-float trick also appears on TCP: `CLDropPills.x/y` (`client.c:3452-3453`) and
`CLHitTank.dir` (`client.c:3500`), the latter forwarded opaquely by the server without re-swapping
(`server.c:3754`) and decoded at `client.c:2877-2880`. **Fixed-point encodes truncate, they do not
round** — a reimplementation that rounds will desync from the oracle.

**Handshake (TCP).** `joinclient()` `client.c:499-792` / `joinplayerserver()` `server.c:714-912`.
Client sends the 57-byte `struct JOIN_Preamble` (`bolo.h:448-453`: `ident[8]`, `version`, `name`,
`pass`); server replies one byte from the join enum (`bolo.h:191-199`), then on accept the 915-byte
`struct BOLO_Preamble` (`bmap.h:18-42`, incl. 16 × 56-byte player records and a BE32 `maplen`),
then the map blob (`serversavemap()`). Only one joining connection is handled at a time
(`server.c:952-955`). Server drops a player after 9 s of UDP silence (`server.c:1191`).

**Magic / versioning.** `NET_GAME_IDENT = "XBOLOGAM"` (`bolo.h:37`), `NET_GAME_VERSION = 1`
(`bolo.h:27`). The server checks **only** `version` (`server.c:734`) and **never compares `ident`**.
Header comments claiming "currently 0" are stale — trust the constant. `"0.99.7"` appears nowhere
in the C sources; per Jerod, 0.99.7bv is the *behavioral* fidelity target and always was, so the
oracle's transport being XBolo's own invention is a fact about scope, not a discrepancy.

**Transport shape.** TCP (`SOCK_STREAM`, control) and UDP (`SOCK_DGRAM`, state) on the **same port
number at both ends** — server binds TCP, `getsockname()`s it back, binds UDP to the identical port
(`server.c:237-280`); client binds its UDP socket to its own TCP local address then `connect()`s it
(`client.c:587-604`). `TCP_NODELAY` both ends (`client.c:1001`, `server.c:899`). No fixed default
game port — `DEFAULT_HOSTPORT (0)` (`Dedicated Host/main.c:41`), ephemeral and tracker-advertised.
Tracker is TCP port **40000** (`tracker.h:8`).

**Tracker reachability echo — easy to miss.** The tracker probes a server by sending a zeroed
`CLUpdate` header with `player = 255` (`tracker.c:230-232`); the server must echo it back verbatim
(`server.c:639-650` and again `server.c:1467-1479`) or it gets listed UDP-closed. Also:
`TRACKER_Preamble`, `TrackerHost`, `TrackerHostList` (`tracker.h:36-56`) are **not** packed, so
`TrackerHost` carries a pad byte before `timelimit` (`sizeof == 60`, `TrackerHostList == 64`) — a
reimplementation must reproduce that padding.

## Finding 2 — oracle bugs and oddities for the eventual 6.0 trap list

1. `CLUpdateExplosion.tile` (`client.h:304`, offset 4) is never written by `sendclupdate()` and
   never read by `dgramclient()` — an uninitialized stack byte on the wire. Send 0, ignore on read.
2. `bcopy(NET_GAME_IDENT, joinpreamble.ident, sizeof(NET_GAME_IDENT))` (`client.c:606`, mirrored
   `server.c:857`) copies **9** bytes into an 8-byte array, overrunning into `version` — which the
   next line then assigns, so it works by accident. On the wire `ident` is 8 chars, no NUL.
3. `server.c:2069` tests `sizeof(clsendmesg)` — the **pointer** (8) — not `sizeof(struct
   CLSendMesg)` (4). Conservative-harmless, but the server won't look at a chat message until ≥8
   bytes are buffered.
4. `client.c:1291` passes `O_NONBLOCK` as a `recv()` *flag*, where the value aliases
   `MSG_DONTROUTE` on Darwin. Harmless; the socket is already non-blocking (`client.c:315`).
5. `INET_ADDRSTRLEN` (16) is used as a `sockaddr_in` length throughout by numeric coincidence.
6. The dead-reckoning loop (`client.c:1446-1454`) is a network-driven re-simulation with no bound —
   Swift needs a cap regardless of C's behavior. A `writeRun`-style safety deviation, not a
   fidelity fix; log it as such.
7. **CORRECTED 2026-09-02, do not port as a bug — see `docs/AGENT_NOTES.md`'s Wave 6.0 pre-brief
   entries.** ~~Previously noted and still standing: the double-`htons()` in `sendmessage()`'s
   `MSGNEARBY` case is a genuine C bug, D24-class — replicate with a named regression test, do not
   fix.~~ Direct read of `client.c:6705-6744` shows a single effective swap (`clsendmesg.mask =
   htons(0x00)` is a no-op at zero; the proximity loop ORs bits in host order; `htons()` applied
   once at line 6736) — correct code, not a bug. This claim originated in the Wave-6-scope-survey
   trap-list seed and was carried into this doc unverified. Under D24 ("replicate documented C
   bugs exactly"), porting a fix for a phantom bug would inject a real one — do not add any
   double-swap handling here. Struck through rather than deleted so the correction stays visible
   to anyone who reads this file directly instead of `AGENT_NOTES.md`.
8. **D27 applies to the tick orchestrator:** `explosionlogic` loops `-1..<MAXPLAYERS`, `pilllogic`
   runs once rather than per-player, `sendclupdate` fires only on `seq % 5`.

## Finding 3 — Q16: recommendation UNCHANGED

Port the **wire format byte-exact**, rebuild the **mechanism** on Network.framework + async/await.
Unchanged from the prior session, and the mapping above strengthens it: the format is compact,
pure, and now fully specified with citations, so it is cheap to make byte-exact and differentially
testable against the C oracle. The mechanism is the opposite — ~1500 lines of `select`/pthread
glue with no fidelity obligation under D4 and no way to differentially test it.

*Did the framing work change this?* No — and it couldn't have. Even a byte-identical WinBolo match
would only have affected how the codec's field layout is *sourced*, not whether the transport
mechanism should be transliterated.

## Finding 4 — Q17: 6.0 scope UNCHANGED, 6.1–6.5 untouched

6.0 remains "derive the wire codec from the C oracle." Because the framing question was left open,
there is no basis to rescope 6.0 toward adapting WinBolo's definitions, so it stays as briefed.
6.1–6.5 are unchanged. Two notes for whoever writes the pre-brief:

- Finding 1 is effectively 6.0's specification already — the remaining work is transcription plus
  differential tests, not discovery.
- **6.5 has a licensing constraint stronger than anything in `PLAN.md`:** `README.md:42-45` already
  commits on the record that XBolo's `TCMPortMapper` dependency is **GPLv3** and "is not used
  here," with NAT traversal to use a permissive alternative or manual port forwarding
  "specifically to avoid GPL-encumbering this codebase." Any Q19 ruling should be reconciled with
  that public statement, not just with D13/D25.

## Finding 5 — the Q19 cost argument, stated without the missing fact

The decision-relevant asymmetry does not actually depend on WinBolo's framing, and is worth having
on record: **adapted struct definitions would still have to be validated field-by-field against the
oracle before they could be trusted**, because the oracle is what BoloKit must match. That
validation is the same work as deriving the layout from the oracle directly — which Finding 1 shows
is already largely done. So option 2's upside is bounded by how much *transcription* it saves,
while its cost (GPL exposure in the codec, plus a PARITY over-similarity audit under D25) is
incurred regardless. **This is reasoning, not the measurement**; a byte-identical result would
still have independent value as corroboration, and the measurement remains unperformed.

## Method for finishing the primary task, if it's ever resumed

1. `git clone --depth 1 https://github.com/kippandrew/winbolo /tmp/deepdive1-winbolo` — outside
   the tracked tree, no submodule, nothing staged. D25 clean-room discipline applies to the read.
2. Locate its protocol layer on both client and server sides: packet/opcode enums, wire structs,
   `#pragma pack` / packed attributes, `htons`/`htonl` sites, socket setup, version constants.
3. Compare on the axes Finding 1 establishes: magic/version, channel split and port sharing,
   message discrimination (leading opcode, no length prefix), opcode-space size (20/34), the three
   position/direction encodings, 10 Hz cadence with the all-16 `seq` array as ack, and the
   no-retransmit/stale-drop reliability model. Classify each: identical / structurally parallel but
   differently scaled / substantially different.
4. Answer the brief's three questions, including whether WinBolo negotiates multiple Bolo protocol
   versions.

## Housekeeping

No code changes, no `Sources/` edits, no `Package.swift` edits, nothing written to `Reference/`, no
WinBolo clone in the tree. Test baseline **296**, unchanged (D28 — nothing shrank; no tests added
or removed, as no code shipped). The briefed `[IMPLEMENTER]` entry in `docs/AGENT_NOTES.md` was
**not** written — Jerod redirected the deliverable into this document instead, so this section is
the record. **Q18 was not touched**, as instructed.

> **→ Planner:** Q19's factual precondition is **still open** — do not read a framing verdict into
> this document. Q16's recommendation stands unchanged (wire format exact, mechanism modern) and is
> independent of that open fact, so it is rulable now. Q17's 6.0 stays as briefed. Finding 1 is a
> usable 6.0 spec as-is. Please reconcile any Q19 ruling with `README.md:42-45`'s on-record GPLv3
> commitment (Finding 4), which is stronger than D13/D25 alone. Finding 5 gives the cost argument
> that holds regardless of the missing measurement.
