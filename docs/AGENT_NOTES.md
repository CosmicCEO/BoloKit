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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, Wave 6.0–6.3, the D39 fix, Wave 6.6, and Wave 6.4 (6.4a/6.4b/6.4c) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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

## Active Log (post-6.4c)

> **Archived 2026-09-03:** the D39 `GameState.pause`-split fix and its PARITY re-audit, Wave
> 6.6 (the `recvcl*` server handlers, D40's bug-for-bug ruling), and the full Wave 6.4 family —
> 6.4a (client transport, D42/D44, extended under D45/D46), 6.4b (host transport, D47/D48/D49),
> and 6.4c (live UDP wiring, D50/D51/D52/D53) — through Wave 6.4c's close, compressed into
> `docs/notes/archive.md`. Full uncompressed text preserved in git history per D28. The active
> log below continues from the Wave 6.5 pre-brief GO entry.

### [PLANNER] 2026-09-03 — Wave 6.4c closed (PARITY PASS, D53 fix confirmed); Wave 6.5 pre-brief GO issued

**Type:** planning — close-out + GO
**Phase:** Wave 6.4c close / Wave 6.5 open
**Blocks:** nothing — Wave 6.5 is available to start now

Reviewed PARITY's re-audit (`999dbde`) of the D53 fix (`534aa57`+`172a1d0`). Verdict: **PASS**.
The fix is the minimal correct change (`.normal` now calls `table.sendToAll`, `.abnormal` provably
untouched, re-read in full not just diffed); both named regression tests were independently
assessed as sound, including a specific trace of *why* the new negative-assertion
(`confirmNoDatagramArrives`) test pattern resolves correctly rather than merely happening to pass
— PARITY traced the counterfactual (what would happen if `.abnormal`'s self-exclusion were
accidentally removed) and confirmed the test would actually catch it, not just that it currently
passes. One generic, low-probability caveat noted for the record (a sufficiently starved scheduler
could in principle let a timeout-race negative test false-pass) — not specific to this test, not
blocking.

**Wave 6.4c is closed — PARITY PASS.** Full chain, six commits from pre-brief to close:
`091c364` → `bc34c95` (D51/D52) → `5fdb1bc`+`b3d6c8a` → `7ead213` → `5bab7c1` (D53 found) →
`534aa57`+`172a1d0` (fixed) → `999dbde` (confirmed). This is the second wave in the 6.4 family to
need a post-ship fix before closing (6.4a needed three rounds via D45/D46; 6.4c needed one via
D53) — both times the standard fix→test→re-audit sequence caught and closed the gap correctly
before anything shipped uncorrected.

**Wave 6.5 pre-brief GO issued.** D50's sequencing condition (6.4c closes before 6.5 starts) is
satisfied. Per Jerod's plan to archive the current Implementer session to conserve read
requirements, the next Implementer session picking this up should start from
`docs/notes/WAVE65_BOOTSTRAP.md` (prepared and committed ahead of time, `3a5c58f`) rather than
reconstructing context from this file's full history — that document already covers scope, wire-
format facts, the licensing constraint, decisions to carry forward, and what still needs real
research. This entry is the formal trigger that bootstrap document was gated on.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Wave 6.4c row marked complete (PARITY PASS); Wave 6 summary row updated; Wave
  6.5 row marked pre-brief GO'd, pointing to the bootstrap doc.

[TO: IMPLEMENTER] Wave 6.4c is closed — no action needed on it. **Wave 6.5 is GO'd for pre-brief.**
If you are a freshly-started session, read `docs/notes/WAVE65_BOOTSTRAP.md` first, then this
file's tail and `docs/PLAN.md`'s Wave 6.5 row and cited decisions, then begin your own research
against `Reference/c/` per the bootstrap's process section. Write your pre-brief before any coding.
[TO: PARITY] No action needed yet — nothing new shipped this entry. D53 is closed on your side too.

### [PLANNER] 2026-09-03 — Admin agent: archive pass through Wave 6.4c close

**Type:** admin/process — archive/compression pass
**Phase:** repo housekeeping (Admin agent)
**Blocks:** nothing

Admin agent compressed everything from the D39 `GameState.pause`-split fix through Wave 6.4c's
close (D39 fix, Wave 6.6, Wave 6.4a/6.4b/6.4c — decisions D39 through D53) into
`docs/notes/archive.md`, matching the existing per-wave summary format and level of detail
(commit hashes, key findings, decision cross-references). Full uncompressed text remains in git
history per D28. `AGENT_NOTES.md`'s active log now starts from the Wave 6.4c close/Wave 6.5
pre-brief GO entry (renamed header to `## Active Log (post-6.4c)`); the index table and archived
note updated to match. Committed at `92a6298`, explicit pathspec (`docs/AGENT_NOTES.md
docs/notes/archive.md` only — verified `git status --short` showed only these two files before
staging, no concurrent-session work present).

A stale `.git/index.lock` blocked the initial commit attempt; requested and received delete
permission for the repo root, removed the lock, reconfirmed a clean two-file diff before
committing.

No action needed from any of the three rotation roles.

### [IMPLEMENTER] 2026-09-03 — Wave 6.5 pre-brief: tracker protocol + NAT traversal research

**Type:** planning — pre-brief (no coding this session, per the two-stage gate)
**Phase:** Wave 6.5 pre-brief
**Blocks:** Wave 6.5 coding, pending PLANNER's ruling below

Read `docs/notes/WAVE65_BOOTSTRAP.md`, `docs/PLAN.md`'s Wave 6.5 row and cited decisions
(D25/D31-D34/D41/D44/D48/D49/D52), and this file's tail confirming the pre-brief GO (`a5f28ef`).
Researched the three areas the bootstrap explicitly left open — `registerserver()`'s full
behavior, the tracker client browse path, and the NAT-mapping approach — directly against
`Reference/c/`, plus independently re-derived the `TrackerHost` padding trap the bootstrap
flagged rather than trusting `DEEPDIVE1.md`'s figure outright.

**Confirmed facts (all `file:line`-cited in full detail below; summarized here):**

- `tracker.h:41-56` — `TrackerHost` is 60 bytes with a padding byte at offset 51 (after
  `gametype`, before the 4-byte-aligned `timelimit`); `TrackerHostList` is 64 bytes
  (`in_addr` + `TrackerHost`). Independently re-derived by hand-walking field alignment, matching
  `DEEPDIVE1.md`'s existing figure rather than assuming it.
- `server.c:1259-1509` — `registerserver()` is a nine-step handshake (DNS resolve → TCP connect
  → send `TRACKER_Preamble` → version-ack → send `kTrackerHost`+`TrackerHost` → TCP-open ack →
  UDP-open ack, serviced live via the D48/6.4c echo → success), gated entirely on
  `server.tracker.hostname != NULL` (no tracker configured is success, not an error). Return value
  is tri-state (0 success / 1 "closed by main thread" / -1 error) via a shadowed `ret` variable —
  easy to misread as binary.
- **New finding, not in any prior doc:** `sendtrackerupdate()` (`server.c:1569-1588`) is a
  **60-second heartbeat** (`TRACKERUPDATESECONDS`, `server.h:20`), scheduled from
  `servermainthread()` (`server.c:1590-1630`, skip-if-still-queued + catch-up-if-late). Sends a
  **bare** `TrackerHost` struct with no `kTrackerHost` msg byte — correct, since the daemon's
  post-registration loop (`tracker.c:293-301`) reads bare structs forever.
- **New finding — a real C bug:** the heartbeat's `trackerhost.timelimit = server.timelimit`
  (`server.c:1577`) omits the `htonl()` the registration path applies at `server.c:1383`. The
  daemon stores bytes verbatim and the browsing client unconditionally `ntohl`s
  (`bolo.c:447`), so **60 seconds after any host registers, its advertised time limit becomes
  byte-swapped garbage in every client's game listing.** Deterministic, not UB — a D24/D40
  bug-for-bug candidate.
- Also newly noted: neither `registerserver()` nor `sendtrackerupdate()` ever `bzero`s the
  `TrackerHost` local before `strncpy`-filling it — `strncpy(dst,src,LEN-1)` zero-pads to `LEN-1`
  but leaves the final byte and the offset-51 pad byte indeterminate, so the C sends uninitialized
  stack bytes on the wire. Unlike the `timelimit` bug, this is indeterminate, not deterministic —
  the D40 `pills[-1]`-class exception, not the D24 tautology-class rule. These two findings sit
  four lines apart in the same struct and want opposite treatment; flagging explicitly so the
  coding pass doesn't collapse them into one rule.
- `bolo.c:346-450`/`bolo.h:485-490` — `listtracker()`/`stoptracker()`, the client browse path:
  same preamble/version prologue, then `kTrackerList` → `ntohl` count → count × 64-byte
  `TrackerHostList`, with only `port`/`timelimit` byte-swapped on decode (`bolo.c:446-447`) —
  `addr.s_addr` is left in network order deliberately. Status enum `kGetListTracker*`
  (`bolo.h:301-318`) is a **separate** enum from `registerserver()`'s `kRegister*`
  (`bolo.h:274-299`) — different member sets (e.g. only the browse enum has `REGISTERING` and
  `ECONNABORTED`), do not unify them into one Swift type.
- `Sources/BoloNet/Preambles.swift:187-207` already has `TrackerPreamble` (Wave 6.3) — reuse
  verbatim, just add a `wireSize = 9` static to match its two siblings' existing convention.

**NAT-traversal recommendation, with license checked per the bootstrap's requirement:**
`DNSServiceNATPortMappingCreate` (`import dnssd`) — confirmed via live `DocumentationSearch`
this session (not training-data recall) that it supports both NAT-PMP and UPnP IGD, the same
union `TCMPortMapper` covers, returns external IP/port, and self-renews/self-heals across
sleep-wake and gateway changes. It is a system API in `libSystem` — nothing bundled, no GPL
exposure, satisfying `README.md:61-64`'s commitment directly. Also confirmed
`Network.framework` itself has no port-mapping facility (`includePeerToPeer` is local-link/AWDL
only). Proposed shape: wrap the repeating callback as an `AsyncStream` drained by one consumer —
the same pattern already proven twice per D49/D52 (`HostListener.swift`/
`HostDgramListener.swift`), not a new mechanism.

**Proposed scope split (not a decision — for PLANNER):** 6.5a (tracker protocol — codec,
`registerserver()`, heartbeat, `listtracker()` — all oracle-testable) vs. 6.5b (NAT mapping — no
C oracle possible, its only real verification is a live router round-trip, and the licensing
constraint attaches to this half specifically). Same grounds as D23/D43: two units of work with
different verification stories bundled under one name. Register and browse stay together inside
6.5a despite being different roles — they share the codec and prologue, and browse is ~30 lines
of decode, D47's "volume not complexity" case even more clearly than G-2 was.

**Test plan (D28):** current baseline 572 tests, nothing shrinks. Extends
`netops.c`'s existing `preamble_layout_oracle()` precedent (`netops.c:411-472`) with three new
oracle exports — `tracker_layout_oracle()` (makes the offset-51 pad-byte claim a machine-checked
fact, not a hand-derivation I'm asking to be trusted), `trackerhost_encode_oracle()`/
`trackerupdate_encode_oracle()` (verbatim extracts of the two field-assignment bodies, `bzero`'d
first per the stated T-3 deviation, proving the T-2 byte-order asymmetry rather than asserting
it). Plus unit tests for: pad byte is zero; 64-byte round-trip with `s_addr` untouched; name/map
truncation; each handshake branch (version-err/TCP-closed/UDP-closed/success); the tri-state
return; nil-hostname short-circuit; heartbeat single-flight guard; 0-entry and n-entry browse
decode.

**Files proposed:** `Sources/BoloNet/Tracker.swift`, `TrackerRegistration.swift`,
`TrackerBrowser.swift` (6.5a, new); `Sources/BoloNet/PortMapping.swift` (6.5b, new);
`Preambles.swift` (add `wireSize`); `Sources/CXBolo/netops.c` + `include/CXBolo.h` (three oracle
exports); `Tests/DifferentialTests/TrackerDifferentialTests.swift` (new) plus unit tests in the
existing suites. Reusing `WireWriter`/`WireReader` (`WireIO.swift`) and `HostDgramListener.swift`
(already owns the UDP socket the register handshake's live-echo step needs) rather than building
either again.

**Cosmetic doc-drift note:** D32 cites `README.md:42-45` for the GPL-avoidance paragraph; it's now
at `README.md:61-64`. Same class of non-blocking citation drift PARITY has flagged before —
noting for PLANNER to fix at convenience, not blocking.

> **→ Planner:** Four open questions, none resolved solo per this project's convention:
> 1. Approve `DNSServiceNATPortMappingCreate` as the NAT-traversal approach (license checked
>    above)?
> 2. Approve the 6.5a/6.5b split, or keep this as one wave?
> 3. **Does this port need the tracker *daemon* (`tracker.c`) at all?** It's a third, separate
>    binary from the host (`server.c`) and browsing client (`bolo.c`) halves this pre-brief
>    otherwise covers — under D4 ("you and friends") someone has to run one for internet play to
>    work at all. Genuinely undecided anywhere in this project's docs; adjacent to Q22 but not the
>    same question — raising it, not answering it.
> 4. Confirm D24/D40 bug-for-bug applies to the missing `htonl` on the heartbeat's `timelimit`
>    (deterministic), and that the un-`bzero`'d struct gets the opposite (indeterminate-input,
>    zero-fill-and-disclose) treatment — these are four lines apart in the same C function and
>    the easy mistake is applying one rule to both.

No coding this session — stopping here per the two-stage gate pending PLANNER's ruling on the
above. [TO: PLANNER] Wave 6.5 pre-brief ready for review; four questions above. [TO: PARITY] No
action yet — nothing shipped this session to audit.

### [PLANNER] 2026-09-03 — Wave 6.5 pre-brief ruled: split approved, coding GO'd (D54/D55/D56, Q26)

**Type:** planning — pre-brief review + coding GO
**Phase:** Wave 6.5 pre-brief -> coding
**Blocks:** nothing — both 6.5a and 6.5b are cleared to start

Reviewed IMPLEMENTER's Wave 6.5 pre-brief against `docs/PLAN.md`'s cited decisions
(D25/D31-D34/D41/D44/D48/D49/D52) and this project's split/bug-for-bug precedent (D23/D24/D40/D43/D47).
Ruled all four open questions:

1. **NAT-traversal approach — approved (D54).** `DNSServiceNATPortMappingCreate` is a system API
   (`libSystem`, `import dnssd`), nothing bundled, satisfies `README.md`'s GPLv3-avoidance
   commitment directly. Covers the same NAT-PMP/UPnP union `TCMPortMapper` did; wrap as an
   `AsyncStream`, same proven pattern as D49/D52.
2. **6.5a/6.5b split — approved (D55).** Different verification stories (6.5a oracle-testable,
   6.5b only verifiable live) is the same grounds D23/D43 already used to split a wave; register
   and browse stay together inside 6.5a per D47's "volume not complexity" reasoning. No
   sequencing dependency between the two halves, unlike D43's 6.4a-before-6.4b risk ordering —
   IMPLEMENTER's choice which to start first, or both concurrently.
3. **Tracker daemon question — not ruled, tracked as Q26.** Genuinely adjacent to Q22 but a
   distinct question (whether this project ships the daemon binary at all, vs. Q22's
   host-in-process-vs-dedicated question). Not code-blocking for either 6.5a or 6.5b — both work
   against a tracker regardless of who runs it. Jerod's call, same as Q22.
4. **The two `TrackerHost` bugs get opposite treatment — confirmed (D56).** The heartbeat's
   missing `htonl` on `timelimit` is deterministic, well-defined C behavior — D24/D40 bug-for-bug
   precedent applies, replicate it. The un-`bzero`'d struct's indeterminate pad/tail bytes are
   genuinely UB — D40's own carved-out exception (the `pills[-1]` contrast) applies instead:
   zero-fill as a disclosed Swift-safety deviation, not a fidelity fix. Both need named regression
   tests per D28, and IMPLEMENTER's own flag (these are four lines apart and easy to conflate) is
   correct — the coding pass should keep them as two explicit, separately-asserted claims.

Also fixed D32's stale `README.md:42-45` citation to `:61-64` per the pre-brief's own cosmetic
drift note (non-blocking, folded in while touching this area).

**Wave 6.5 is coding GO'd**, split into Wave 6.5a (tracker protocol) and Wave 6.5b (NAT-PMP/UPnP),
both cleared to start per D55. Proposed file list, oracle exports, and test plan from the
pre-brief are all accepted as scoped — no changes requested there.

**Note on process:** this pre-brief was initially reported "ready" in a relayed session without
being committed — caught before ruling, per this project's own commit-discipline rule (an entry
only exists once committed). It was then staged and is being committed alongside this ruling.
Flagging only so the pattern doesn't repeat, not as a blocker — no harm done this time.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — D54/D55/D56 added to the decisions log; Q26 added to open questions; Wave 6.5's
  row split into three (6.5/6.5a/6.5b) reflecting the coding GO; Wave 6 summary row updated; D32's
  citation corrected.

[TO: IMPLEMENTER] Wave 6.5 is coding GO'd, split into 6.5a (tracker protocol) and 6.5b (NAT-PMP).
Proceed per the pre-brief's proposed scope, file list, and test plan — no changes requested.
Remember to commit your own pre-brief/completion entries yourself, in the same sitting, going
forward (see the note above).
[TO: PARITY] No action yet — nothing coded this entry to audit.
