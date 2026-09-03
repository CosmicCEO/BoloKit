# HOSTMODELS — how other Bolo implementations split (or don't split) client vs. server

> **Research note, PLANNER, 2026-09-03.** Prompted by an open runtime question: does the Swift
> port need a standalone dedicated/headless server binary, or does the planned "Bolo 2026" app
> hosting in-process cover it? Logged as **Q22** in `docs/PLAN.md`. This document is the
> reference; `PLAN.md`'s row is the pointer.

## Why this matters for us

`BoloKit` (pure sim) + `BoloNet` (transport/session, headless by design — see D21/D31 and the
Wave 6.0 "no `Foundation`" design call) already have zero UI coupling. Whatever the answer is,
it's cheap for us: a dedicated headless binary is just a third, trivial SPM executable target
(like `BoloGlyphs` already is) linking the same two libraries the app links. This research is
about precedent and product decision, not feasibility — architecturally we can do either or both
for close to the same cost.

## Finding 1 — our own oracle (xbolo) does both, confirmed by direct source read

`Reference/c/` ships **two separate frontends over the identical server library**
(`server.c`/`server.h` — `initserver`/`setupserver`/`startserverthread`/
`startserverthreadwithtracker`/`stopserver`/`lockserver`/`unlockserver`/`kickplayer`/
`banplayer`/`unbanplayer`, the same functions Wave 6.3 is currently porting):

1. **The Cocoa client hosts in-process.** `Mac OS X/GSXBoloController.m` calls `setupserver()`
   then `startserverthread()` (or `startserverthreadwithtracker()` if registering with a
   tracker) directly from the "Host a Game" UI panel, with `TCMPortMapper` doing UPnP port
   mapping (`portMapperDidFinishWork:`, line ~888) — the same GPLv3 dependency D32/D34 already
   rule out for our port. Any player can host from their own copy of the running game.
2. **A separate, fully headless "Dedicated Host" binary also exists**, as its own target:
   `Reference/c/Dedicated Host/main.c` (740 lines, Robert Chrzanowski, 2009). Command-line flags
   for map path, port, password, tracker URL, time limit, hidden mines, game type
   (open/tournament/strict), pause-on-exit, start-paused. No GUI at all — after startup it drops
   into a text REPL (`commandloop()`) with `status`/`pause`/`resume`/`allowjoin`/`disallowjoin`/
   `kick <id>`/`ban <id>`/`unban <id>`/`quit`, driving the exact same locked server state
   (`lockserver()`/`unlockserver()` around each command) the Cocoa client's host panel drives.

**Conclusion: even our single reference implementation already has both modes, sharing one
server core.** This isn't an either/or choice in the lineage we're porting — it's additive, and
cheaply so, because both frontends are thin wrappers over the same `server.c`.

## Finding 2 — WinBolo: started separate-only, added client-hosted later, kept both

Per WinBolo's own manual (John Morrison, v1.14, `winbolo.com/downloads/manual.pdf`):

- A separate dedicated server program, **WinBoloDS** ("WinBolo Dedicated Server"), predates
  client-hosted play — command-line configurable (map, port, game type, player limits, tracker
  registration).
- **v1.14 added "Built In Server" support directly in the regular client**, explicitly framed as
  removing a pain point: *"WinBolo can now start a server from within the game client. This means
  it will no longer have to run an external program to run a server which was problematic under
  some systems."*
- Both options remain available today — dedicated server for unattended/continuous hosting,
  client-hosted for casual play alongside your own game.

LinBolo (the Linux/Unix sibling) ships from the same source tree
([milki/winbolo](https://github.com/milki/winbolo) — "complete source code to WinBolo client &
server, LinBolo client & server," per its own README) — same duality, not independently verified
beyond that line since GitHub's `robots.txt` blocked a deeper directory fetch.

**Pattern match with Finding 1:** the trend in an actively-maintained lineage is toward *offering
both*, with the standalone dedicated server treated as the power-user/always-on option and
client-hosting as the low-friction default — not toward picking one and dropping the other.

## Finding 3 — PyBolo (from-scratch modern rewrite): dedicated-server-only, different philosophy

[PyBoloPublic](https://github.com/joncox123/PyBoloPublic), a modern Python reimplementation,
went the other way: **no in-client hosting at all.** Its README has you unzip two separate copies
and run a standalone "Server app" from one of them; the server owns the authoritative game engine
and clients only transmit inputs, receiving state-sync updates back (a thin-client/authoritative-
server split, not peer-hosted). This is the one data point against universal duality — but it's
also the one project here that isn't derived from the original Bolo codebase lineage at all, so
it's weaker precedent for *this* port's fidelity goals than xbolo/WinBolo are.

## Finding 4 — the original 1987/1993 Mac Bolo (Stuart Cheshire): inconclusive from available sources

Wikipedia's [Bolo (1987 video game)](https://en.wikipedia.org/wiki/Bolo_(1987_video_game)) entry
confirms AppleTalk-LAN and UDP-Internet play up to 16 players but says nothing about whether
hosting was peer-embedded or a separate program. Not resolved here — xbolo (Finding 1) is a 2009
reimplementation of the original's *behavior*, not the original's own source, so its dual-mode
architecture is suggestive but not proof of what the 1987/1993 original itself did internally.
Not worth further digging unless this becomes decision-relevant — D3 already established
"faithful to 0.99.7bv's *behavior*," not to its undocumented internal server architecture.

## Recommendation (not a ruling — Q22 stays open for Jerod)

Every actively-maintained descendant of the actual Bolo lineage we could confirm (xbolo, WinBolo,
LinBolo) supports **both**: the regular client can host in-process, and a separate headless
binary/mode exists for continuous or unattended hosting. Given `BoloKit`/`BoloNet`'s existing
headless-by-design split, matching that pattern costs us almost nothing — "Bolo 2026" (the future
AppKit app, D21) gets a "Host" panel calling the same `BoloNet` session APIs a dedicated binary
would call, and a small companion SPM executable target (call it `BoloHost`, alongside the
existing `BoloGlyphs` CLI target) is close to free once `BoloNet`'s session-management API exists
— likely natural to schedule once Wave 6.3 (session logic: join/kick/ban/alliance) and Wave 6.4
(transport) land, since that headless target's `main.swift` would just be a thin driver over
exactly what those two waves are building, mirroring `Reference/c/Dedicated Host/main.c`'s own
relationship to `server.c`.

No architecture decision is *forced* by this research — it only says the cost of doing both is
low and the precedent favors it. Whether to actually build a dedicated headless target (and if
so, when — a good candidate slot is right after Wave 6.3/6.4, or deferred into the same later
phase as the app UI) is Jerod's call.

## Sources

- [WinBolo manual, v1.14 (PDF)](https://www.winbolo.com/downloads/manual.pdf)
- [milki/winbolo (WinBolo/LinBolo client & server source)](https://github.com/milki/winbolo)
- [joncox123/PyBoloPublic](https://github.com/joncox123/PyBoloPublic)
- [Bolo (1987 video game) — Wikipedia](https://en.wikipedia.org/wiki/Bolo_(1987_video_game))
- In-repo: `Reference/c/Dedicated Host/main.c`, `Reference/c/Mac OS X/GSXBoloController.m`,
  `Reference/c/server.h` (all direct source reads, cited by file:line above)
