# BoloKit — Wave 6.5 Bootstrap (Tracker / NAT-PMP)

> **Prepared ahead of time, 2026-09-03, by PLANNER — not yet active.** This wave is not GO'd yet;
> Wave 6.4c is still awaiting PARITY's post-commit audit as of this writing. **Do not start coding,
> and do not even start pre-brief research, until `docs/PLAN.md`'s Wave 6.5 row shows a status
> other than "Not started," or until you see an explicit `[TO: IMPLEMENTER]` Wave 6.5 GO in
> `docs/AGENT_NOTES.md`.** This file exists so a freshly-started Implementer session — replacing
> an earlier one that was archived to conserve read requirements (cost of AI), not a concurrent
> parallel agent — can pick up Wave 6.5 pre-planning without having to reconstruct context by
> reading this project's entire `docs/AGENT_NOTES.md` history. Read this file, then
> `docs/PLAN.md`'s Wave 6.5 row and its cited decisions, then start your own pre-brief research
> directly against `Reference/c/`.
>
> Run `git log --oneline -10` and `git status` before doing anything — this file can lag reality
> by the time you read it. If Wave 6.4c has since closed and Wave 6.5 has already been GO'd with
> more specific instructions in `docs/AGENT_NOTES.md`, those supersede this file's framing (not
> its citations, which are independently checkable against the C source regardless).

---

## Your role and its boundary

You are this project's regular IMPLEMENTER — full read/write on the workspace, own the Swift
port and its differential tests, commit to `main` (unlike Wave 5.9's scoped parallel agent, there
is no worktree isolation here; you work the normal way, on the normal branch). You do not choose
the next wave, do not declare a wave "done," and do not change architecture unilaterally — you
wait for a `[TO: IMPLEMENTER]` GO in `docs/AGENT_NOTES.md`, and you log ambiguous decisions there
as a question rather than resolving them solo. Same three-role structure as every prior wave:
PLANNER (Claude.app Cowork) gates on what's reported in `AGENT_NOTES.md`, no direct code access;
PARITY (Claude.app, adversarial) independently hand-traces your commits against `Reference/c/`
post-commit. See `docs/PLANNER.md`/`docs/PARITY.md` for their own bootstraps if you want the full
picture, but you don't need to impersonate either role — just know they exist and what they gate.

## What Wave 6.5 actually is

**Scope, per `docs/PLAN.md`'s Wave 6.5 row and decision D32:** tracker registration and NAT
traversal. Two genuinely separate pieces bundled under one wave name — confirm this split still
makes sense in your own pre-brief, same as every prior wave's pre-brief has been free to propose
re-splitting (D23/D43 precedent):

1. **The tracker protocol's remaining half.** `dgramserver()`'s tracker-reachability echo
   occurrence (a zeroed `CLUpdate` header, `player == 255`, echoed back verbatim with no zeroing)
   is **already built** — it shipped in Wave 6.4b/6.4c. What's left, per **D48**'s ruling, is
   `registerserver()`'s *separate* tracker-echo occurrence, which the C **does** zero
   (`bzero(&clupdate,...)` then `player = 255`) before replying — confirmed genuinely different
   from `dgramserver()`'s mechanism, not the same thing described twice. Beyond that specific
   echo, `registerserver()` almost certainly does more (the whole point of a tracker is server
   *registration* — telling a central directory "I exist, here's my address/name/player
   count/map" — and periodic re-registration/heartbeat). **This bootstrap file does not have
   `registerserver()`'s full behavior mapped** — that's real, uncompleted research; see "What you
   need to research yourself" below. Don't assume the echo is the *only* thing this wave needs
   just because it's the only piece already cited in this project's docs.
2. **NAT traversal.** Currently just UPnP/NAT-PMP port mapping in the C oracle, done via a GPLv3
   dependency (`TCMPortMapper`) that **this port explicitly does not use** — see the licensing
   constraint below. This half needs a permissively-licensed replacement approach (a different
   library, or `Network.framework`'s own NAT-traversal facilities if it has any suitable ones, or
   manual port forwarding with no automatic mapping at all) — no specific choice has been made
   yet anywhere in this project's docs. Proposing one, with its license checked, is part of your
   pre-brief's job, not a decision already made for you.

## Wire-format facts already confirmed (from `docs/notes/DEEPDIVE1.md`'s research pass — verify
## against source yourself before relying on these, but they're a strong starting point)

- **Tracker is TCP port 40000** (`tracker.h:8`).
- **`TRACKER_Preamble`, `TrackerHost`, `TrackerHostList` (`tracker.h:36-56`) are the one wire
  struct family in the entire protocol that is NOT `__attribute__((__packed__))`.** Every other
  `CL*`/`SR*`/preamble struct in this codebase is packed and this port has treated that as a given
  everywhere else — this family is the one place you cannot assume Swift's default struct layout
  matches the C's on-wire layout. `TrackerHost` carries a padding byte before its `timelimit`
  field (confirmed `sizeof(TrackerHost) == 60`, `sizeof(TrackerHostList) == 64`, both cited in
  `docs/PLAN.md`'s Wave 6.5 row already). You'll need to reproduce that padding deliberately —
  likely an explicit unused/padding field in the Swift struct, or manual byte-offset encode/decode
  rather than relying on `MemoryLayout`.
- **The tracker probe/echo mechanism** (already shipped for `dgramserver()`'s occurrence,
  outstanding for `registerserver()`'s): tracker sends a zeroed `CLUpdate` header with
  `player = 255` as a reachability probe (`tracker.c:230-232` per DEEPDIVE1's citation — verify
  yourself); a server failing to echo it back gets listed as UDP-closed by the tracker. D48's
  ruling (`docs/PLAN.md`) has the full distinction between the two echo occurrences if you need
  the background on why they're different.

## Licensing constraint — read this before proposing any NAT-traversal approach

`README.md:61-64` already commits, on the record, to something stronger than this project's
general MIT posture: *"XBolo itself bundles a separate dependency, TCMPortMapper, under the
GPLv3, used for UPnP/NAT-PMP port mapping. That dependency is not used here. Any NAT-traversal
functionality in this port will use a permissively-licensed alternative or manual port forwarding,
specifically to avoid GPL-encumbering this codebase."* This mirrors D25/D33's existing WinBolo
clean-room policy (read-only architectural reference, GPL code never copied or adapted) and D34's
prior ruling not to pursue any GPL-encumbered substitution. Any library or approach your pre-brief
proposes needs its license checked and stated explicitly — same discipline D46 already applied to
approving `import Foundation` in `BoloNet` (a reasoned call, not a silent assumption).

## Non-negotiable project-wide rules to carry forward (index only — full text in `docs/PLAN.md`'s
## decisions log; read the actual entries, this is not a substitute)

- **D18** — Float everywhere for position/physics/trig, never `Double`/`CGFloat`, for anything
  that touches simulation state. (Wire encodings for tracker structs may still need explicit
  byte-order handling regardless — that's a separate concern from D18's float-vs-double choice.)
- **D24/D40** — replicate C oracle bugs bug-for-bug where found; never silently "fix" one you
  notice. Log it as a disclosed trap/question instead, with a named regression test proving the
  bug is intentional.
- **D28** — no test count shrinks without an explicit, stated replacement. State your before/after
  count in every completion report.
- **D31/D42** — port the wire format byte-exact; rebuild the transport *mechanism* on
  `Network.framework`/async-await, not transliterated POSIX sockets. `Buf.swift`'s byte-queue half
  is fair game to reuse if relevant; its POSIX-socket half is not.
- **D41** — if any C behavior's correctness depends on real network round-trip timing (this
  project's single-process merge has no such latency), identify the actual invariant that timing
  protected and preserve *that*, not the literal statement order.
- **D45** — a wave's claimed scope must be verified complete, not assumed. Wave 6.4a and 6.4b both
  had a "did we actually cover X" gap surface after an initial pass looked done; do your own
  version of that check before calling this wave's pre-brief (or its coding) finished.
- **D49/D52 precedent, reusable pattern:** this project has twice now needed to serialize
  concurrent access to shared `inout GameState` around `Network.framework` accept/receive loops —
  once for TCP joins (`HostListener.swift`'s `AsyncStream`-drain design), once for UDP datagrams
  (`HostDgramListener.swift`, same shape). If tracker registration or a NAT-traversal library
  needs its own concurrent I/O around shared state, look at whether the same `AsyncStream`-drained-
  by-one-consumer pattern applies before inventing something new — it's proven twice in this
  codebase already, including having caught a real Swift-exclusivity bug the first time.
- No `import Foundation` in `BoloKit` sources specifically (`BoloNet` is not covered by that rule,
  per D46 — already has legitimate `Data`-related `Foundation` imports).
- Copy float/constant literals from the C source exactly — bit-for-bit transcription, not a
  recomputed equivalent.

## What you need to research yourself (this bootstrap does not have it — start here)

- `Reference/c/tracker.c`, `Reference/c/tracker.h`, `Reference/c/resolver.c` — the actual client
  side of the tracker protocol (querying a tracker for a server list) is not mapped in this
  project's docs at all yet, only the server-registration-echo half. If Wave 6.5's scope should
  include "Bolo 2026" being able to *browse* a tracker's server list (not just register with one),
  that's a real scope question to raise in your pre-brief, not something already decided.
- `Reference/c/server.c`'s `registerserver()`/`unregisterserver()` (exact line numbers not yet
  cited anywhere in this project — find them yourself) — full behavior: what does registration
  actually send, how often does it repeat/heartbeat, what triggers unregistration, what happens on
  tracker-unreachable.
- Whether `Network.framework` has any built-in NAT-traversal/port-mapping facility suitable here,
  or whether a permissively-licensed third-party library is needed, or whether "manual port
  forwarding, no automatic mapping" (the README's own fallback option) is the pragmatic choice for
  a first pass. State your recommendation and its license in the pre-brief; this is a real open
  design question, not a rubber-stamp.
- Confirm current status of Wave 6.4c before you start — check `docs/PLAN.md`'s Wave 6.4c row and
  the tail of `docs/AGENT_NOTES.md` for whether PARITY has passed it and Planner has formally
  issued the Wave 6.5 GO yet.

## Adjacent, not blocking: Q22

`docs/PLAN.md`'s open question Q22 (dedicated headless server binary vs. in-process-hosting only,
research in `docs/notes/HOSTMODELS.md`) is still open — Jerod's call, not yet ruled. It's adjacent
to this wave because a dedicated headless server would also need to register with the tracker,
but Wave 6.5's own scope doesn't depend on Q22's outcome either way — the registration/NAT-
traversal logic being built here is shared infrastructure regardless of which binary ends up
calling it. Don't block on Q22; just be aware it exists if your pre-brief's design touches on how
a future headless target would consume this wave's APIs.

## Two-stage process (same pattern every wave in this project follows)

1. **Pre-brief first.** Research directly against `Reference/c/` (the actual gap-filling this
   bootstrap explicitly leaves for you, above), then write a pre-brief into `docs/AGENT_NOTES.md`
   covering: exact `file:line` citations for every claim (this project's established discipline —
   see any prior wave's pre-brief for the expected rigor, e.g. Wave 6.4c's `091c364`), a trap list,
   a proposed scope/file breakdown, a test plan, and any open questions for PLANNER as a
   `> **→ Planner:**` blockquote. Commit it. Do not start coding before PLANNER's coding GO comes
   back — every prior wave in this project has followed this gate without exception.
2. **Then code**, per whatever PLANNER's ruling says, with named regression tests per D28,
   completion report appended to `docs/AGENT_NOTES.md` in the same header format as every prior
   entry, tagged `[TO: PARITY]` and `[TO: PLANNER]` at the end.

## Commit discipline (repo-wide, not Wave-6.5-specific, but easy to get bitten by if you skip it)

This repo is worked by multiple Claude sessions on the same checked-out tree, sometimes
concurrently. Before staging **and** again before committing: `git log --oneline -5 && git
status`. Stage only the specific files you changed — never `-A`/`.`. If something unrelated shows
up staged that isn't yours, commit with `git commit -m "..." -- <your specific files>` (message
first, then pathspec) rather than sweeping it in. If `git`/`device_bash` reports "Operation not
permitted" on a stale `.git/index.lock`/`.git/HEAD.lock`, that's routine concurrent-session
fallout, not a real error — request delete permission for the repo folder once per session, then
`rm -f` the stale lock file(s) and retry.

## When you're done with your pre-brief

Stop and wait for PLANNER's ruling — same as every other wave. Do not start coding on your own
judgment that the pre-brief is "obviously fine." Log genuinely open questions rather than picking
an answer and moving on; this project's decisions log (`docs/PLAN.md`) exists specifically because
those calls belong to PLANNER, not IMPLEMENTER, however confident you are in a particular answer.
