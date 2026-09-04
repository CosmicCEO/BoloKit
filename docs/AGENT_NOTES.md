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

### [PLANNER] 2026-09-03 — Jerod directs: run Wave 6.5a and 6.5b simultaneously

**Type:** planning — sequencing directive (Jerod's explicit call)
**Phase:** Wave 6.5a/6.5b coding
**Blocks:** nothing

Jerod: run both sub-waves at once rather than picking one to start first. D55 already established
there's no dependency between them, so this is compatible with that ruling, not a change to it —
just exercising the "or concurrent" half of D55's "either order or concurrent work is fine."

**Recommended mechanism: the proven scoped-parallel-Implementer-agent pattern (Wave 5.9,**
**`docs/notes/WAVE59_BOOTSTRAP.md`), not two sessions both editing the shared docs live.** 6.5a
(`Tracker.swift`/`TrackerRegistration.swift`/`TrackerBrowser.swift`) and 6.5b (`PortMapping.swift`)
already touch disjoint files per the pre-brief's own file list, satisfying that pattern's
precondition (independent wave, explicit off-limits list matching what the other session touches).
Concretely: one of the two runs as the primary session against `main` as normal; the other runs on
its own worktree/branch with its own bootstrap file and writes its progress to a standalone
`docs/notes/WAVE65B_REPORT.md` (or `WAVE65A_REPORT.md`, whichever is the parallel one) instead of
directly to `docs/AGENT_NOTES.md`/`docs/PLAN.md` — PLANNER folds it in at merge time, same as Wave
5.9. This avoids two Implementer sessions racing to commit to the same shared log files, which is
a real hazard this project's concurrency notes already warn about, not a hypothetical one.

[TO: IMPLEMENTER] Both 6.5a and 6.5b are to proceed now, in parallel, per Jerod's direction. Use
the Wave 5.9 scoped-parallel-worktree pattern for whichever one runs as the secondary session
(own branch, own bootstrap, own report file) — see `docs/notes/WAVE59_BOOTSTRAP.md` as the
template. Coordinate between the two sessions (or with Jerod relaying) on which sub-wave takes the
primary `main` slot vs. the parallel worktree, since that choice isn't fixed by this ruling.
[TO: PARITY] No action yet — nothing coded this entry to audit.

### [PLANNER] 2026-09-03 — Wave 6.5b folded in: NAT-PMP/UPnP shipped, PARITY held pending shared build

**Type:** planning — fold-in of a standalone report + PARITY-activation call
**Phase:** Wave 6.5b coding complete, audit pending
**Blocks:** Wave 6.5b's PARITY audit (deliberately, see below) — nothing else

Folding in IMPLEMENTER 6.5b's completion report (`docs/notes/WAVE65B_REPORT.md`, commit `a250c57`)
per its own request, since it was logged there rather than directly to this file to avoid racing
the concurrent 6.5a session's commits (both sessions worked the same checkout, not separate
worktrees — noting for the record since I'd recommended the Wave 5.9 worktree pattern and that
wasn't what actually ran; it still worked cleanly here because the two sub-waves' file lists were
genuinely disjoint, confirmed by `a250c57`'s diff touching only `PortMapping.swift`,
`PortMappingTests.swift`, and its own report file).

**Wave 6.5b shipped:** `Sources/BoloNet/PortMapping.swift` wraps `DNSServiceNATPortMappingCreate`
(D54) as an `AsyncStream`, same D49/D52 pattern, boxing the stream continuation through
`Unmanaged`/`UnsafeMutableRawPointer` since `dnssd`'s callback is a C function pointer and can't
capture Swift state directly — a genuinely new mechanism-crossing shape for this codebase, not a
mechanical repeat of the two prior `AsyncStream` listeners. Decision logic
(`decodePortMappingReply`) is correctly factored out of the callback for independent testing,
consistent with D31/D36/D42's decision-vs-mechanism split applied everywhere else in this port —
good instinct to preserve *something* testable given D55 already disclosed this sub-wave has no C
oracle. `doubleNAT` treated as a successful update with a flag, not a thrown error, matching the
API's own state-change-callback model rather than inventing a request/response shape for it. Byte
order handling (host-order `port` parameters, network-order wire values, `externalAddress` left
raw matching `DgramServerPeerAddress.addr`'s existing convention) is consistent with the rest of
`BoloNet`. 5 new tests, all against the pure decision function except one safety check
(`cancel()` idempotency) that legitimately talks to the live `mDNSResponder` daemon — disclosed
correctly as the one test touching real mechanism, not decision logic, and explicitly distinguished
from D55's actual non-goal (a live router round-trip, which nothing here exercises).

**No changes requested — this reads as complete and correctly scoped to exactly what the coding
GO accepted.**

**PARITY held, as IMPLEMENTER itself recommended — confirmed correct, not just accepted on
faith.** `netops.c`/`CXBolo.h` are mid-edit from the concurrent Wave 6.5a session as of this
writing (confirmed via `git status` at fold-in time: those files plus `Preambles.swift`/
`Tracker.swift`/`TrackerBrowser.swift`/`TrackerRegistration.swift` show uncommitted changes) — the
shared `DifferentialTests` target won't build until 6.5a lands, so a real audit isn't possible yet
regardless of 6.5b's own cleanliness. This is a build-dependency block, not a finding against
6.5b.

**Test count:** baseline 572 (Wave 6.4c). 6.5b adds 5 (577 once the suite builds again) — 6.5a's
own count is still pending its landing. Full-suite re-run and grand total confirmation deferred to
whichever of the two lands second, per IMPLEMENTER's own request.

[TO: IMPLEMENTER] Wave 6.5b is folded in, no changes requested — nothing further needed on 6.5b
unless the full-suite re-run (once 6.5a lands) surfaces something. Whichever of 6.5a/6.5b commits
second should run the full suite and report the real grand total in its own completion report.
[TO: PARITY] Hold on both 6.5a and 6.5b until the shared `CXBolo`/`DifferentialTests` target
builds clean again (blocked on 6.5a's in-flight edits) — will re-activate once both land and the
suite builds.

### [IMPLEMENTER] 2026-09-03 — Wave 6.5a shipped: tracker protocol (register/heartbeat/browse)

**Type:** coding — completion report
**Phase:** Wave 6.5a coding, per PLANNER's `9e5e481` GO
**Blocks:** nothing — this is the second of 6.5a/6.5b to land, per Jerod's simultaneous-start
directive (`d6f2011`); full suite re-run below per that entry's own request.

Coded to the pre-brief's accepted scope, no deviations. `Sources/BoloNet/Tracker.swift`:
`TrackerHost`/`TrackerHostList` wire structs (`tracker.h:41-56`), zero-filling the offset-51 pad
byte and the name/map fields' potential trailing byte on encode (T-3, disclosed Swift-safety
deviation from the C's own uninitialized stack bytes there) plus `trackerHost(...)`, deriving the
struct from a live `GameState` the same way `assembleBoloPreamble` already does.
`Sources/BoloNet/TrackerRegistration.swift`: `TrackerSession` (persistent, classic
completion-handler `NWConnection` API — same precedent `TCPSession`/`UDPSession` already set, since
a session must stay open across the handshake and every later heartbeat) plus
`registerWithTracker(...)`, porting `registerserver()`'s nine-step handshake
(`server.c:1259-1509`) and `sendtrackerupdate()`'s heartbeat (`server.c:1569-1588` — the
**previously undocumented 60-second heartbeat** the pre-brief found, `TRACKERUPDATESECONDS`,
`server.h:20`). `Sources/BoloNet/TrackerBrowser.swift`: `listTrackerGames(...)`, porting
`listtracker()` (`bolo.c:346-450`) via the closure-scoped `withNetworkConnection` API (`JoinClient.
swift`'s precedent, since this is a one-shot handshake, not a persistent session).

**D56's two-bug pairing, both landed as ruled:** `TrackerHost.encode()` (registration) correctly
`htonl`'s `timeLimit`; `encodeAsHeartbeat()` reproduces the real bug bit-for-bit (`server.c:1577`'s
missing `htonl`) by emitting `timeLimit`'s raw little-endian bytes — correct specifically because
every deployment target for this port is little-endian, same as the C oracle's own compiled
behavior on this architecture. `testRegistrationAndHeartbeatEncodingsDifferOnlyInTimeLimitByteOrder`
asserts both the byte-order difference AND that every other field matches exactly, so a future
edit collapsing the two paths back into one would fail loudly. The offset-51 pad byte and the
`strncpy`-boundary UB (T-3) are zero-filled unconditionally in both paths and asserted zero by
`testEncodePadByteIsAlwaysZero` — not compared against the oracle at that byte, since the oracle
also has to `memset` first to make its *own* comparison well-defined (see `netops.c`'s
`trackerhost_encode_oracle`/`trackerupdate_encode_oracle` header comment) — the zero-fill is a
disclosed Swift-side claim, not a fidelity match.

**T-4 (tri-state `registerserver()` return) — disclosed mechanism substitution, not implemented as
a third enum case.** Swift's structured-concurrency cancellation (`Task` cancellation →
`CancellationError` from the suspended read/write) already covers "closed by main thread"'s real
job cooperatively; `registerWithTracker` only models the two protocol-level outcomes (success /
specific rejection) plus T-5's `nil`-hostname short-circuit. Not separately unit-tested (would only
exercise Swift's own `Task` cancellation machinery, not this wave's code) — disclosed here rather
than silently dropped from the pre-brief's test list.

**T-10 (heartbeat back-pressure/single-flight guard) — scoped out, disclosed, not silently
dropped.** `TrackerSession.sendHeartbeat` takes an already-built `TrackerHost` and sends it once;
cadence/back-pressure is explicitly the caller's job (matching `UDPSession.sendLocalUpdate`'s
identical existing boundary) because no tick-orchestrator wave yet exists to own a 60-second
scheduling loop for the tracker the way `RunTick.swift` owns one for the game tick. The guard
belongs to whichever future wave builds that scheduler, not to this one's wire-level primitive —
noted so it isn't mistaken for a coverage gap later.

**Oracle exports** (`Sources/CXBolo/netops.c`/`include/CXBolo.h`): `tracker_layout_oracle()`
(offsetof ground truth, confirms the padding trap `docs/PLAN.md`'s Wave 6.5 row flagged, rather
than trusting my own hand-derivation) plus `trackerhost_encode_oracle()`/
`trackerupdate_encode_oracle()` (verbatim extracts of the two real field-assignment bodies,
`memset`-first per the T-3 note above), proving T-2/D56's byte-order asymmetry is real
compiler-observed behavior. `Preambles.swift`'s `TrackerPreamble` gained a `wireSize = 9` static
per the pre-brief, matching its two siblings' existing convention.

**Found and fixed, separately committed and disclosed, not folded into this wave's own commit:**
building for testing against the shared `DifferentialTests` target (blocked, per PLANNER's
`c68d250` entry, until 6.5a's edits landed) surfaced two real compile errors in Wave 6.5b's already
-folded-in `PortMapping.swift`/`PortMappingTests.swift` — `decodePortMappingReply` was `internal`
(unreachable from the separate `DifferentialTests` module) and `PortMappingUpdate` had no `public`
initializer (a `public let`-fields struct doesn't synthesize a public memberwise init), plus the
test file passed `dns_sd.h`'s error constants — which import as plain `Int`, not
`DNSServiceErrorType`, since they're an untagged anonymous C enum — without the explicit cast the
parameter type requires. All three are visibility/type-inference fixes with zero behavioral change
to 6.5b's own logic; PLANNER's `c68d250` review already passed 6.5b's design with no changes
requested, and nothing here revisits that. Committed separately (`cdff28d`, not folded into
`a23d49d`) so the attribution stays clean.

**Test count:** 572 (Wave 6.4c baseline) → 591 after 6.5a's own 19 new tests → **596** once 6.5b's
5 (already landed at `a250c57`, blocked from running until the shared build fix above) are
included. Full suite run and confirmed green at 596/596, per PLANNER's `c68d250` request that
whichever of 6.5a/6.5b lands second reports the real grand total. No coverage lost (D28).

[TO: PLANNER] Wave 6.5a and 6.5b are both landed and the shared suite is green at 596/596. Ready
for PARITY per your `c68d250` hold condition (shared build clean) now being satisfied.
[TO: PARITY] Hold lifted from this side — both 6.5a (`a23d49d`) and 6.5b (`a250c57`, plus the build
fix at `cdff28d`) are ready for audit once PLANNER activates.

### [PLANNER] 2026-09-03 — Wave 6.5a/6.5b reviewed, PARITY activated

**Type:** planning — completion review + PARITY activation
**Phase:** Wave 6.5a/6.5b coding complete, audit pending
**Blocks:** nothing — this is the standard post-commit gate

Reviewed Wave 6.5a's completion report (`be0684c`) against the coding GO (`9e5e481`, D54/D55/D56)
and the pre-brief's accepted scope. Matches, no deviations from what was approved:

- **D56's two-bug pairing landed as ruled** — registration's `htonl`'d `timeLimit` vs. the
  heartbeat's bit-for-bit reproduction of the missing-`htonl` bug, with a named test asserting the
  two encodings differ *only* there and match everywhere else. Exactly the "don't collapse them
  into one rule" concern the pre-brief itself raised.
- **T-3's zero-fill (pad byte + `strncpy` boundary) implemented and asserted**, correctly framed
  as a disclosed Swift-safety claim rather than an oracle-fidelity match (the oracle itself needs
  its own `memset` first to make the comparison well-defined at that byte — good catch that this
  isn't a real bit-for-bit comparison point).
- **T-4/T-10 scope boundaries — accepted as disclosed, not oversights.** T-4 (tri-state return)
  substituting Swift's structured-concurrency cancellation for a third enum case is a reasonable
  mechanism substitution (D31's own latitude: port the wire format, not the C's control-flow
  shape) and correctly not claimed as tested since there'd be nothing of this wave's own logic to
  test. T-10 (heartbeat cadence/back-pressure) deferred to whichever future wave owns a tracker
  scheduling loop, mirroring `UDPSession.sendLocalUpdate`'s identical existing boundary — same
  precedent already accepted for other wire-level primitives, not a new gap. Neither needs a
  Planner ruling; both are exactly the kind of call D45/D47 leave to the pre-brief/completion-report
  process rather than requiring pre-approval.
- **The 6.5b build fix (`cdff28d`) is legitimately mechanical** — visibility (`internal` →
  `public`), a missing memberwise init, and explicit casts for `dns_sd.h`'s untyped `Int` error
  constants. No behavioral change to 6.5b's own logic, consistent with what `c68d250` already
  passed; correctly committed separately from `a23d49d` so attribution stays clean rather than
  folded silently into 6.5a's commit.
- **Test count verified: 572 → 591 (6.5a, +19) → 596 (+5, 6.5b) → 596/596 green.** No coverage
  lost (D28).

**No changes requested on either sub-wave.** Both read as complete and correctly scoped to what
the coding GO accepted.

**PARITY activated for both 6.5a and 6.5b** — the hold condition from `c68d250` (shared build
green) is satisfied, confirmed independently against the commit history above, not just taken on
IMPLEMENTER's word. Standard post-commit audit, same as every prior wave.

[TO: IMPLEMENTER] No action needed on 6.5a/6.5b unless PARITY's audit surfaces a finding.
[TO: PARITY] **Activated.** Audit Wave 6.5a (`a23d49d`) and Wave 6.5b (`a250c57`+`cdff28d`)
against `Reference/c/` — `server.c`'s `registerserver()`/`sendtrackerupdate()`, `bolo.c`'s
`listtracker()`, and `PortMapping.swift`'s `dnssd` usage (no C oracle for the last one per D55;
verify the decision-logic split and disclosed test-coverage boundary instead of expecting a
byte-exact comparison there). D56's bug-pairing test and T-3's zero-fill claim are the two items
most worth independent verification, given they're the sub-wave's own highest-risk findings.

### [PARITY] 2026-09-04 — Wave 6.5a/6.5b post-commit audit: PASS with one real finding (6.5a)

**Type:** post-commit audit, standard sequence (Planner activated PARITY at `150e822`/`737783a`).
Auditing Wave 6.5a (`a23d49d`) and Wave 6.5b (`a250c57`+`cdff28d`) against `Reference/c/`.

**Standing limitation, as always:** no Swift toolchain in this environment. Every claim below is a
direct hand-trace against `Reference/c/` and the current `Sources/`/`Tests/` content, re-derived
independently, not a compile-and-run. IMPLEMENTER's own green 596/596 build (`be0684c`) remains
the authority that the code executes; this is the authority that it's correct against the oracle.

**Overall verdict: Wave 6.5a — PASS with one real, non-blocking finding (crash-safety divergence,
not a wire-format bug). Wave 6.5b — PASS, no changes requested.**

**Independently re-derived and confirmed correct (6.5a):**

- **`TrackerHost`/`TrackerHostList` layout** (`tracker.h:36-56`) — hand-walked field alignment
  myself: `playername[16]`(0) + `mapname[32]`(16) + `port`(48) + `gametype`(50) + 1 pad byte(51) +
  `timelimit`(52, 4-byte aligned) + `passreq`(56) + `nplayers`(57) + `allowjoin`(58) + `pause`(59)
  = 60 bytes exactly (no trailing pad needed, struct alignment is 4). Matches
  `tracker_layout_oracle()` (`netops.c:617-636`), `TrackerHost.wireSize` (`Tracker.swift:200-203`),
  and `testTrackerLayoutMatchesOracle`'s asserted offsets exactly.
- **D56's bug-pairing, read at the source, not trusted from the pre-brief:** `registerserver()`
  (`server.c:1383`) does `trackerhost.timelimit = htonl(server.timelimit)`;
  `sendtrackerupdate()` (`server.c:1577`) does the bare `trackerhost.timelimit = server.timelimit`
  — confirmed genuinely missing the swap, a real deterministic bug. `Tracker.swift`'s
  `encode()`/`encodeAsHeartbeat()` (lines ~123-160) reproduce this exactly; `port` correctly does
  NOT have the asymmetry (`server.c:1382` and `:1575` both `htons()` it) and neither encoding
  path treats it specially. `testRegistrationAndHeartbeatEncodingsDifferOnlyInTimeLimitByteOrder`
  independently checked: `htonl(300)` = `[0x00,0x00,0x01,0x2C]` at offset 52, raw little-endian
  `[0x2C,0x01,0x00,0x00]` for the heartbeat — both hand-verified correct, and the test's
  zero-out-then-compare confirms no other byte differs between the two encodings.
- **T-3's zero-fill claim** — confirmed neither `registerserver()` nor `sendtrackerupdate()`
  `bzero`s the local `TrackerHost` before `strncpy`-filling it (genuinely UB, not deterministic —
  correctly the D40-exception class, not D24's). `encodeCommonPrefix` (`Tracker.swift:113-119`)
  and `WireWriter.putFixedString` (full-count zero-pad, not `strncpy`'s LEN-1 partial pad) both
  confirm the disclosed Swift-safety deviation is real and consistently applied; `netops.c`'s two
  oracle functions correctly `memset(out,0,sizeof(*out))` first specifically so their *other*
  bytes have something well-defined to diff against, not as a fidelity claim about the real C
  functions — the doc comment is accurate on this point, not overstated.
- **`getpauseserver()`/`getallowjoinserver()`/`nplayers()`** (`server.c:369-371,419-421,4412-4419`)
  — confirmed these reduce to exactly the same expressions `registerserver()`'s registration path
  uses directly (`server.pause == -1`, `server.allowjoin`, connected-socket count), so
  `trackerHost()`'s one shared builder (`Tracker.swift:227-237`) correctly serves both send paths
  despite the C using a function call on one side and a direct field read on the other — not a
  divergence, confirmed by reading `getpauseserver`/`getallowjoinserver`'s bodies directly rather
  than assuming the names imply equivalence.
- **The T-8 UDP-echo reliance — checked byte-for-byte, not taken on faith.** The pre-brief's plan
  (reuse `HostDgramListener.swift`'s Wave 6.4b/6.4c echo rather than re-implementing
  `registerserver()`'s own inline UDP echo) reads at first glance like it could re-open D48's own
  distinction (`dgramserver()`'s verbatim echo vs. `registerserver()`'s explicit
  `bzero`+`player=255` reconstruction, "not the same mechanism," `registerserver()`'s occurrence
  "stays in Wave 6.5" per D43/D48 — checked this is genuinely unresolved, not just cited). Traced
  both C functions directly: `dgramserver()`'s trigger (`server.c:637-638`,
  `r == sizeof(clupdate.hdr) && clupdate.hdr.player == 255`) and response
  (`sendto(...,&clupdate,sizeof(clupdate.hdr),...)`, the buffer echoed verbatim) are *bit-for-bit
  identical in output* to `registerserver()`'s own reconstruction (`server.c:1466-1471`,
  `bzero(&clupdate,...); clupdate.hdr.player=255;`) for this specific probe, because the tracker's
  own probe packet (`tracker.c:225-227`) is itself already a `bzero`'d, header-only,
  `player=255` packet — echoing it back verbatim reproduces the same bytes a fresh
  zero-and-set reconstruction would produce. Confirmed further against `tracker.c:255-267`: the
  daemon's own check is only `r == sizeof(hdr) && player==255` — it never compares echoed bytes
  against what it sent, so content-identical-by-construction is sufficient, not incidental. Also
  confirmed `DgramServerRelay.swift`'s `isTrackerEchoDatagram` (`bytes.count ==
  CLUpdateHeader.wireSize && bytes.first == 255`) matches this exact trigger, and
  `processDgramPacket`'s `.trackerEcho` case echoes the received bytes verbatim over the same
  connection — so the mechanism substitution is sound, not a completeness gap. This *is* still an
  orchestration dependency (whichever wave wires up the running host process must start
  `HostDgramListener` before/during a live registration attempt) — correctly disclosed as a
  caller-responsibility boundary this wave doesn't own, not silently assumed.
- **Browse path** (`listtracker()`, `bolo.c:346-450`) — `TrackerBrowser.swift`'s count decode
  (manual big-endian reconstruction of the 4-byte count) and `TrackerHostList.decode`'s handling
  of `addr` (left raw, T-9) match `bolo.c:438,446-447` exactly (`addr.s_addr` never swapped, only
  `game.port`/`game.timelimit` are). Confirmed the heartbeat's byte-order bug propagates
  correctly and *without* special-casing: `TrackerHost.decode` always applies `getU32()`
  (unconditional big-endian read) regardless of which send path produced the bytes, so a listing
  client legitimately sees garbage for any host whose `timelimit` came from a post-registration
  heartbeat — reproducing the real bug's downstream symptom, not just its send-side cause.
- **Test counts, counted directly, not trusted from the commit message:** `grep -c "@Test"` on
  `TrackerDifferentialTests.swift` gives 19 (matches the completion report's claim exactly);
  `grep -rho "@Test" Tests/ | wc -l` across the whole suite gives **596**, matching the claimed
  grand total precisely. D26's `-ffp-contract=off` flag confirmed still present in `Package.swift`.
  No `Double`/`CGFloat` creep in any of the four new/touched files (D18) — only false-positive
  text matches on the identifier `DoubleNAT`.

**Real finding (6.5a) — crash-safety divergence, not a wire-format bug:**
`trackerHost(...)` (`Tracker.swift:227-237`) builds `timeLimit: UInt32(state.timeLimit)`, where
`GameState.timeLimit` (`GameState.swift:56`) is a plain `Int` with no non-negative invariant
enforced anywhere (`RunTick.swift:89` only guards `> 0` for tick logic, same shape as the C's own
`if (server.timelimit > 0)`, `server.c:1102` — so a negative value is already an anticipated,
tolerated state in this codebase's own tick logic, not an impossible one). `UInt32(_:)` on a
negative `Int` **traps** in Swift ("Fatal error: Negative value is not representable"). The C
oracle never can: `server.timelimit` is a plain `int`, and `htonl()` takes `uint32_t` — the
implicit `int`→`uint32_t` conversion on a negative value silently reinterprets the bit pattern
(well-defined, if consumer-nonsensical) and continues running. This is exactly the class of
unchecked-conversion footgun this project already disciplines elsewhere (the Int16
`truncatingIfNeeded` pattern in `CLAUDE.md`'s own stated constraints) — `UInt32(state.timeLimit)`
should be `UInt32(truncatingIfNeeded: state.timeLimit)` to match the C's actual never-crashes
behavior. Grepped the rest of `Sources/` to confirm this pattern (`UInt32(state.timeLimit)` /
`UInt32(...timeLimit)`) appears nowhere else — this is new to Wave 6.5a, not an already-accepted
site-wide precedent. Not currently reachable (no caller in this codebase yet constructs a
`GameState` with a negative `timeLimit` — no UI/config layer exists yet to do so), so this is
latent rather than actively triggered, and is a robustness/crash-safety gap rather than a
wire-format fidelity bug — the wire bytes this function *would* produce for a valid non-negative
input are correct.

**Confirmed correct, no changes requested (6.5b, D55 — no C oracle exists for this half):**
`decodePortMappingReply`'s pure decision logic (`PortMapping.swift:73-85`) — checked
`kDNSServiceErr_NoError`/`kDNSServiceErr_DoubleNAT` are the only two accepted codes, `doubleNAT`
flag set correctly, `UInt16(bigEndian: externalPort)` hand-verified against
`PortMappingTests.swift`'s own worked example (`0x901F` network-order → `8080` host-order,
confirmed the byte-swap arithmetic by hand). `decodePortMappingReply` is unit-testable and tested
(5 tests, `grep -c "@Test"` on `PortMappingTests.swift` confirms); the live NAT round-trip is
correctly and explicitly D55's disclosed non-goal, not silently skipped. `PortMappingContext`'s
`Unmanaged` boxing for the C callback's `context` pointer, and `cancel()`'s idempotent
release/deallocate, read as correct on inspection — matches the already-audited pattern this
review re-derived rather than re-reading Planner's own `c68d250` review verbatim.

**No citation drift found this audit** — every `file:line` cited in the completion report and
this wave's source comments was checked directly and matched what's actually there.

[TO: PLANNER] Wave 6.5a: one real finding above (the `UInt32(state.timeLimit)` crash-safety gap in
`trackerHost()`) — latent, not currently reachable, recommend `UInt32(truncatingIfNeeded:)` as the
fix, consistent with this project's own established Int16-truncatingIfNeeded convention. Everything
else in 6.5a (layout, D56 bug-pairing, T-3 zero-fill, the T-8 UDP-echo reliance — traced byte-for-
byte and confirmed sound, not just re-cited — and the browse path) independently confirmed correct.
Wave 6.5b: no findings, D55's no-oracle boundary and disclosed test-coverage scope both hold up.
Your call whether the timeLimit finding blocks close or is tracked as a quick follow-up fix.
[TO: IMPLEMENTER] One fix recommended if Planner rules on it: `Tracker.swift`'s `trackerHost()`,
`timeLimit: UInt32(state.timeLimit)` → `UInt32(truncatingIfNeeded: state.timeLimit)`, matching the
C's own never-crashes-on-this-conversion behavior. A named regression test (D28) would need a
`GameState` with a negative `timeLimit` and assert the resulting `TrackerHost.timeLimit`'s
truncated bit pattern rather than a thrown/trapped error.

### [PLANNER] 2026-09-04 — D57 ruled: fix required before Wave 6.5a closes; Wave 6.5b closed (PARITY PASS)

**Type:** planning — audit ruling + partial close-out
**Phase:** Wave 6.5a fix pending / Wave 6.5b closed
**Blocks:** Wave 6.5a's close (on the fix + re-audit); nothing else

Reviewed PARITY's audit (`c9e37ef`) in full — every claim was independently re-derived (struct
layout hand-walked, D56's bug pairing read at the source not trusted from the pre-brief, T-8's
UDP-echo mechanism substitution traced byte-for-byte including the tracker daemon's own check
logic, test counts counted directly), not a rubber-stamp of the completion reports. That level of
independent verification is exactly what this role is for.

**D57: confirmed real, fix required before Wave 6.5a closes — same precedent as D35/D37/D39/D45/
D46/D53.** `UInt32(state.timeLimit)` trapping on a negative `Int` where the C's own conversion
inside `htonl()` never would is a genuine crash-safety divergence, and this project already has an
established fix pattern for exactly this shape of bug (`Int16` `truncatingIfNeeded`, `CLAUDE.md`).
Latent today (nothing constructs a negative `timeLimit` yet) doesn't change the ruling — D45/D53's
precedent is that a real gap gets fixed now, not tracked as deferred debt, and this is a one-line
fix with an obvious test shape. See `docs/PLAN.md`'s D57 entry for full reasoning.

**Wave 6.5b closes now — PARITY PASS, no findings.** Sub-waves gate independently, same precedent
as 6.4a/6.4b (6.4a needed D45/D46's extension rounds while 6.4b closed clean on its own timeline).
Nothing in 6.5b's design or scope is touched by 6.5a's finding.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — D57 added to the decisions log; Wave 6.5a row marked "audited, fix required";
  Wave 6.5b row marked complete/PARITY PASS.

[TO: IMPLEMENTER] Wave 6.5a: apply D57's fix (`Tracker.swift`'s `trackerHost()`,
`UInt32(state.timeLimit)` → `UInt32(truncatingIfNeeded: state.timeLimit)`) plus the named
regression test (negative `timeLimit` → correct truncated bit pattern, no trap), then report
completion. Wave 6.5b needs no further action — it's closed.
[TO: PARITY] Re-audit needed once D57's fix lands — confirm the trap is gone and the regression
test genuinely exercises a negative `timeLimit` (not just a large-but-positive one that happens
not to trap). Same standard fix→test→re-audit sequence as D53.

### [IMPLEMENTER] 2026-09-03 — D57 fix landed: trackerHost() no longer traps on negative timeLimit

**Type:** coding — fix completion report
**Phase:** Wave 6.5a close (fix applied, awaiting PARITY re-audit)
**Blocks:** Wave 6.5a's close, pending PARITY's re-audit per PLANNER's `5a1e18a` ruling

Applied exactly the fix PLANNER ruled: `Sources/BoloNet/Tracker.swift`'s `trackerHost()`,
`timeLimit: UInt32(state.timeLimit)` → `timeLimit: UInt32(truncatingIfNeeded: state.timeLimit)`,
with a doc comment on `trackerHost` citing D57 directly so a future reader doesn't mistake the
`truncatingIfNeeded` for stylistic noise. Added
`testTrackerHostTruncatesNegativeTimeLimitInsteadOfTrapping`
(`Tests/DifferentialTests/TrackerDifferentialTests.swift`, `TrackerHostFromStateTests` suite) —
constructs a `GameState` with `timeLimit = -300` and asserts `TrackerHost.timeLimit == 0xFFFF_FED4`
(the 32-bit two's-complement bit pattern), not merely that no trap occurs — per PARITY's own
stated re-audit condition, this is a genuinely negative input, not a large-but-positive value that
would happen not to trap either way.

Full suite: 596 → **597** (+1, the new regression test only — no other change). Build and full
test run both clean (`BuildProject buildForTesting:true` succeeded; `RunAllTests` reports
597/597 passed, 0 failed).

Committed at `6cbec85`, explicit pathspec (`Sources/BoloNet/Tracker.swift
Tests/DifferentialTests/TrackerDifferentialTests.swift` only — `git status --short` showed only
these two files before staging).

[TO: PLANNER] D57's fix is landed and tested — 597/597 green. Ready for PARITY's re-audit.
[TO: PARITY] Re-audit requested per your hold condition: confirm `UInt32(truncatingIfNeeded:)`
actually matches the C's implicit `int`→`uint32_t` conversion behavior (not just "doesn't trap"),
and that the new test's `-300` input and `0xFFFF_FED4` expected value are both correct rather than
coincidentally passing.

### [PARITY] 2026-09-04 — D57 re-audit: fix confirmed, Wave 6.5a clear to close

**Type:** post-commit re-audit of a confirmed finding's fix (`6cbec85`+`f7b0528`), standard
sequence (Planner ruled D57 at `5a1e18a`, Implementer's own completion report requested this
re-audit). Quick, targeted check — the fix is a 2-line behavioral change in one function plus one
new test, not a re-audit of Wave 6.5a's already-confirmed layout/D56/T-3/T-8 findings from `c9e37ef`.

**Standing limitation as always:** no Swift toolchain here; every check below is a direct hand-read
of the diff and current source, not a build.

**Verdict: PASS. The fix is exactly what was ruled, correctly matches the C's actual conversion
semantics (not just "doesn't trap"), and the regression test's expected value is independently
verified correct by hand, not just trusted.**

- `Sources/BoloNet/Tracker.swift`'s `trackerHost()` now reads
  `timeLimit: UInt32(truncatingIfNeeded: state.timeLimit)`, exactly the fix D57 ruled — confirmed
  by reading the current source directly, not the diff hunk alone. `truncatingIfNeeded` on a
  wider signed `Int` takes the low-order bits of its two's-complement representation, which is
  precisely what C's implicit `int`->`uint32_t` conversion does for a negative value assigned into
  an unsigned parameter (`htonl(server.timelimit)` where `server.timelimit < 0`) -- this is a
  genuine semantic match to the oracle's behavior, not merely a trap-avoidance patch that happens
  to produce *some* value.
- **Hand-verified the regression test's own math, not trusted:**
  `testTrackerHostTruncatesNegativeTimeLimitInsteadOfTrapping` sets `state.timeLimit = -300` and
  asserts `host.timeLimit == 0xFFFF_FED4`. Checked by hand: 300 decimal = `0x0000012C`; 32-bit
  two's complement of -300 = `~0x0000012C + 1` = `0xFFFFFED3 + 1` = `0xFFFFFED4` -- matches
  exactly. This is a genuinely negative input (not a large-but-positive value that would happen
  not to trap either way, which was the specific failure mode worth guarding against in the
  original finding) -- confirmed by reading the test body directly, not just its name.
- Scope confirmed minimal and undrifted: `git show 6cbec85 --stat` touches exactly
  `Sources/BoloNet/Tracker.swift` (13 insertions/1 deletion -- the conversion fix plus a
  D57-citing doc comment) and `Tests/DifferentialTests/TrackerDifferentialTests.swift` (15
  insertions -- the one new test). No other file touched, no unrelated changes riding along.
- Confirmed the fix doesn't disturb any already-passing behavior: for any non-negative
  `timeLimit` (the only values ever actually exercised before this fix -- e.g. the existing
  `testTrackerHostDerivesFromLiveGameState`'s `timeLimit = 600`), `UInt32(truncatingIfNeeded:)`
  and the old `UInt32(_:)` produce identical results -- this is a strict widening of correct
  behavior (negative inputs now truncate instead of trapping), not a behavior change for the
  previously-working positive case.
- **Test count confirmed directly:** `grep -rho "@Test" Tests/ | wc -l` gives **597**, matching
  both the completion report's claim and the expected 596+1.

**No new findings.** D57 is closed from PARITY's side. Wave 6.5a has no other open items from the
`c9e37ef` audit (layout, D56's bug-pairing, T-3's zero-fill, and the T-8 UDP-echo mechanism
substitution were all independently confirmed sound in that pass and are unaffected by this fix).

[TO: PLANNER] D57's fix confirmed correct -- semantically matches the C's actual conversion
behavior (not just trap-avoidance), regression test's expected bit pattern independently
hand-verified, scope minimal and undrifted, test count 597/597 confirmed. No blockers remain on
PARITY's side -- **Wave 6.5a is clear to close.** With Wave 6.5b already closed independently
(`c9e37ef`), Wave 6.5 as a whole (6.5a+6.5b) is clear to close pending your formal sign-off.

### [PLANNER] 2026-09-04 — Wave 6.5a closed (D57 fix confirmed); Wave 6.5 and Wave 6 both closed; no next wave GO'd — evaluation below

**Type:** planning — close-out chain + next-wave evaluation
**Phase:** Wave 6 (networking) complete; next phase undetermined
**Blocks:** nothing code-blocking, but no wave is currently GO'd

Reviewed PARITY's D57 re-audit (`7f1a9ee`). Verdict: **PASS.** The fix genuinely matches the C's
implicit `int`->`uint32_t` conversion semantics (not just trap-avoidance — PARITY independently
hand-verified `truncatingIfNeeded` on `-300` produces the correct two's-complement bit pattern,
`0xFFFF_FED4`), scope is minimal (2 files) and undrifted, and 597/597 is confirmed directly rather
than trusted from the commit message.

**Wave 6.5a is closed — PARITY PASS.** Full chain: `a23d49d` (591 tests) → `150e822` (PARITY
activated) → `c9e37ef` (audit — layout/D56/T-3/T-8 all confirmed sound, D57 the one real finding)
→ `6cbec85`+`f7b0528` (fix + completion report, 597 tests) → `7f1a9ee` (re-audit PASS).

**Wave 6.5 (6.5a+6.5b combined) is closed** — both halves PARITY PASS, no open findings on either
side. 572→597 tests across the wave, no coverage lost (D28).

**Wave 6 (networking, 6.0-6.6 in full) is closed.** Every sub-wave from the wire codec through the
tracker/NAT client is now PARITY PASS with no open findings: 6.0 (codec) → 6.1 (tick orchestrator)
→ 6.2 (broadcast handlers) → 6.3 (session logic + preambles) → 6.4a/6.4b/6.4c (transport, join
handshake, live UDP wiring) → 6.5a/6.5b (tracker protocol + NAT-PMP) → 6.6 (server receive
handlers). Nine real PARITY findings across the whole wave (D35/D37/D39/D45/D46/D48's correction/
D50/D53/D57) were each fixed and re-confirmed before their sub-wave closed — none left open or
silently accepted. This is the largest single phase of the project closed to date.

**No next wave is GO'd. Evaluated whether one should be, and it isn't a call I can make solo:**

`docs/PLAN.md`'s own Phases section (Q18, already flagged as stale) still shows Phase 4
(measurement rig + fidelity spec, via Infinite Mac / emulator log parsing) and Phase 5 (close the
fidelity gaps) as **not yet started** — no wave in the 1-6 sequence has ever been that work; Waves
1-6 were entirely Phase 3 (the behavior-preserving incremental port) plus the Wave 6 networking
work Phase 3's own text never accounted for cleanly. Separately, D38 already recorded that a UI
phase exists as a concept ("split out to its own phase") but **no wave has ever been defined for
it** — there's no pre-brief, no file list, no scope document, nothing to GO. And two open
questions are explicitly gated on whichever of these comes next: Q22 (dedicated headless server
binary vs. in-process host) and Q26 (does this project ship a tracker daemon binary) are both
flagged "relevant once the app-UI/distribution phase starts" — ruling either now, before that
phase's shape exists, would be guessing at product scope I don't have.

This is a genuine fork, not a sequencing call I can make from `docs/PLAN.md` alone (no code
access, gate on what's reported — and nothing's been reported here because no one has started
scoping any of these three candidates yet):
1. **Phase 4/5 — fidelity measurement and gap-closing.** The originally-planned next step after
   the port, using Infinite Mac to extract ground-truth behavior and close any gaps Phase 3's
   behavior-preserving discipline deliberately left unresolved.
2. **The UI/app phase.** Bolo 2026's actual player-facing app — menus, the "Host a Game" panel,
   in-game HUD, settings — the layer D38 split out but never scoped. Q14 (explosions-list
   attribution) is also explicitly deferred here.
3. **Resolve Q22/Q26 first**, then let whichever answer falls out determine whether a dedicated
   host binary or tracker daemon is even in scope for near-term work, before scoping either
   Phase 4/5 or the UI phase around an assumption that might not hold.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Wave 6.5a row marked complete; Wave 6.5 row marked complete; Wave 6 summary row
  marked complete, noting no wave is currently GO'd.

[TO: IMPLEMENTER] No action needed — Wave 6 is fully closed, nothing currently GO'd. Stand by for
the next wave's pre-brief GO once Jerod picks a direction above.
[TO: PARITY] No action needed — nothing open on your side. Wave 6's full chain (D35 through D57)
has no outstanding findings.

### [PLANNER] 2026-09-04 — Jerod rules Q22/Q26 directly (D58/D59); next-wave direction still open

**Type:** planning — direct product ruling from Jerod, relayed live
**Phase:** post-Wave-6, pre-next-wave
**Blocks:** nothing — these were explicitly non-code-blocking questions

Presented the three-way fork from the prior entry to Jerod. He chose to resolve Q22/Q26 first,
then ruled both directly (not a Planner recommendation adopted — his own call, same as this
project's convention for anything marked "Jerod's call"):

**D58 (Q22): support both hosting models — in-process ("Host a Game" panel) and a separate**
**headless Dedicated Host binary.** Matches `docs/notes/HOSTMODELS.md`'s research and
recommendation, and both reference implementations' own precedent (xbolo and WinBolo/LinBolo each
ship both forms). No architecture change needed — confirms scope for whenever the dedicated-host
binary gets its own wave, doesn't require one now.

**D59 (Q26): no self-hosted tracker daemon — rely on manual IP connection for now.** Wave 6.5a's
tracker-protocol client code is unaffected — it's complete, tested, and would work against any
third-party or community tracker daemon speaking the same wire protocol; this project just isn't
building the daemon itself. Wave 6.5b's NAT-PMP/UPnP port mapping (D54, already shipped) remains
useful for the direct-IP-connect path.

Neither ruling is code-blocking and neither requires touching already-shipped Wave 6 code — both
are scope confirmations for future waves, not reopenings of closed work.

**Next-wave direction is still open** — resolving Q22/Q26 was Jerod's chosen first step, not a
commitment to which of Phase 4/5, the UI phase, or something else comes next. Will ask directly
once he's ready to pick.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Q22/Q26 removed from open questions; D58/D59 added to the decisions log.

[TO: IMPLEMENTER] No action needed — D58/D59 are scope confirmations for future waves, nothing to
build yet.
[TO: PARITY] No action needed.

### [PLANNER] 2026-09-04 — Wave 7 (UI/app phase) opened, pre-brief GO'd

**Type:** planning — new-wave open + pre-brief GO
**Phase:** Wave 7 pre-brief
**Blocks:** Wave 7 coding, pending IMPLEMENTER's pre-brief and PLANNER's review of it (standard
two-stage gate, same as every prior wave)

Jerod picked the UI/app phase as the next direction, out of the three-way fork laid out in the
prior close-out entry (`3d5cf51`). **Wave 7 is open, pre-brief GO'd.**

**Scope, at the level PLANNER can set (sequencing/boundaries, not code-level detail — that's
IMPLEMENTER's pre-brief to write):** Bolo 2026's actual player-facing app — main menu, "Host a
Game"/"Join a Game" panels (now scoped by D58: both in-process hosting and a separate Dedicated
Host binary), in-game HUD, settings, whatever else the reference client's UI shell covers. Same
D25 clean-room discipline already governing WinBolo applies to reading `Reference/c/`'s Cocoa UI
layer (`GSXBoloController.m` et al.) for architectural understanding only, never copied. **Also
folds in Q14** (explosions-list attribution) — PARITY already found no mechanical gameplay
consumer, so this is squarely a UI-layer call now that this phase exists to make it in.

**Real dependency surfaced before opening this blind: Phase 2 (glyph art) never happened.**
Checked directly — `Sources/BoloGlyphs/main.swift` is a single-line stub comment, no
implementation. This phase cannot render a single screen without an asset pipeline existing first.
Recommending (not mandating — IMPLEMENTER's pre-brief should confirm or counter-propose) a **7.0
sub-wave for the glyph-sheet generator + original-Cheshire-asset purge**, sequenced before any
screen-level sub-wave — same shape as D23/D43's "split when it's genuinely two units of work"
precedent, not a new product-scope call needing Jerod.

**Flagging loudly, not deciding:** Phase 2's own verify step calls for a **git-history rewrite** to
strip the original copyrighted assets before this project could ever be distributed with them
still reachable in history (Q18 already noted the cost grows with every commit made before it
happens — the project is now 60+ commits past where Q18 first flagged this). This is a real,
deliberate, destructive git operation. It does not block starting the asset-pipeline work itself,
but it should be raised to Jerod explicitly before anyone actually executes it — not treated as a
routine step buried inside a pre-brief.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Wave 7 row added (UI phase, D58/Q14/Phase-2-dependency noted); Wave 6 summary
  row updated to point at Wave 7 instead of "nothing GO'd."

[TO: IMPLEMENTER] Wave 7 (UI/app phase) is GO'd for pre-brief. Read `Reference/c/`'s UI layer
(Cocoa client shell) and the current state of `Sources/BoloGlyphs/` (currently empty) before
writing your pre-brief. Recommend scoping a 7.0 asset-pipeline sub-wave first, per the note above,
but confirm or counter-propose in your own pre-brief rather than treating this as fixed. Do not
execute the git-history rewrite (Q18) without raising it to PLANNER/Jerod first, even if it comes
up naturally while scoping the asset purge.
[TO: PARITY] No action yet — nothing coded this entry.

### [PLANNER] 2026-09-04 — Wave 7 re-scoped to a v1 vertical slice (D60), coding GO'd for 7.0-7.3

**Type:** planning — scope revision + coding GO
**Phase:** Wave 7.0-7.3 (v1 vertical slice)
**Blocks:** nothing — Milestones B/C/D deliberately NOT GO'd, sequenced later

Jerod flagged the prior GO as too large a step with no clear ship path. Correct call — sized the
reference Cocoa UI directly before doing anything else: `Reference/c/Mac OS X/GSXBoloController.m`
is 4,037 lines (IBOutlets for host/join panels, 48 status image views, key remapping, toolbar,
allegiance/messages panels, tracker table), `GSBoloView.m` (the actual draw loop) is 600 lines,
~5,700 lines total across the UI layer — and this project has no Xcode app target yet at all
(SPM-only since Phase 0, by original design, deferred to "when there's UI to show"). Also checked
`images.h` directly: 297 image indices, confirming the original single-256×256-sheet Phase 2 plan
still fits. One piece of good news found while sizing this: `TCPSession.swift`/`HostSession.swift`
already expose `onPlayerStatusChanged`/`onPillStatusChanged`/`onBaseStatusChanged`/
`onTankStatusChanged` — the exact hook points the reference `setplayerstatus`/`setpillstatus`/
`setbasestatus`/`settankstatus` C callbacks map onto — as a byproduct of Wave 6's networking work,
already built and tested. Milestone C's HUD wiring won't be starting from nothing.

Presented Jerod three staged options plus "show me the full breakdown first"; he picked the
smallest — **a playable vertical slice as v1**, no menus, no networking UI, no HUD. **Ruled as
D60.**

**Wave 7 re-scoped and split into 7.0-7.3, all coding GO'd now** (not just pre-brief — the split
itself, informed by direct research against `Reference/c/`, stands in for the normal pre-brief
step here; IMPLEMENTER should still confirm each sub-wave's detailed approach, especially 7.2's
rendering-mechanism choice, before coding it):

- **7.0** — asset pipeline (Phase 2 proper): `BoloGlyphs` parses `images.h`, renders the tile/
  sprite sheet(s), 16 tank headings as one rotated glyph, OFL-font geometric glyphs. Sound
  explicitly deferred past v1.
- **7.1** — Xcode app target: the app bundle/window/entitlements skeleton that doesn't exist yet.
  Blocks 7.2/7.3 — nothing else can run as an app without it.
- **7.2** — game rendering: the `GSBoloView`-equivalent draw loop, consuming 7.0's assets against
  a live `GameState`. **Rendering mechanism (SwiftUI Canvas/TimelineView vs. an AppKit
  `NSView`/`CALayer` wrapped via `NSViewRepresentable`) is left to IMPLEMENTER to prototype and
  propose** — not a call to make blind from this side; PLANNER reviews whichever the pre-brief
  proposes against D41's tick-timing discipline before that sub-wave's own coding proceeds.
- **7.3** — input + tick loop: keyboard → real `BoloKit` tick loop → 7.2's render. Single-process,
  no networking. This is what actually makes v1 "playable."

**Milestones B (multiplayer UI), C (full HUD/prefs/chat/sound), D (polish + ship prep, including**
**Q18's git-history rewrite no later than this point) are identified but deliberately NOT GO'd** —
sequenced as their own future waves once 7.0-7.3 land and PARITY-pass, not bundled into this GO.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — D60 added; Wave 7's row rewritten to describe the v1-slice scoping; four new
  sub-wave rows (7.0-7.3) added with individual scope and status.

[TO: IMPLEMENTER] Wave 7.0-7.3 are coding GO'd — the v1 vertical slice only. Read
`Reference/c/Mac OS X/` (GSXBoloController.m, GSBoloView.m) and `images.h` directly rather than
re-deriving what's already confirmed above. Write a pre-brief per sub-wave as usual, but 7.2 in
particular needs your own rendering-mechanism recommendation before PLANNER reviews it — don't
treat SwiftUI-vs-AppKit as pre-decided. Do not scope or start Milestones B/C/D without a fresh GO.
Do not execute Q18's git-history rewrite without raising it to PLANNER/Jerod first.
[TO: PARITY] No action yet — nothing coded this entry.


## [TO: IMPLEMENTER] PLANNER purges CLAUDE.md bootstrap for Wave 7 restart

Jerod is archiving and restarting the Implementer session per routine. Per his direction,
`CLAUDE.md` has been purged in place (not additively extended) — old Wave 1-6 decisions-index
content trimmed to only what still governs Wave 7 work, replaced with a dense Wave 7 scope
section: the 7.0-7.3 sub-wave breakdown, the pre-built Wave 6 callback hooks (`onPlayerStatusChanged`
et al.) available for reuse, and the corrected licensing basis for reading `Reference/c`.

**Self-correction**: the Wave 7.2 PLAN.md row previously said "read-only/clean-room per D25" —
that was wrong. `Reference/c` (xbolo) is MIT-licensed (`Reference/c/LICENSE`; D1/D13); D25/D33's
clean-room restriction applies only to WinBolo (GPL v2). Corrected in both CLAUDE.md and PLAN.md's
Wave 7.2 row. No decision text changed — this is a citation fix, not a new ruling.

Milestones B/C/D remain explicitly NOT GO'd in the new CLAUDE.md, matching D60/PLAN.md.
