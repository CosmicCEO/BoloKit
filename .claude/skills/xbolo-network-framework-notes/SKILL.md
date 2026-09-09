---
name: xbolo-network-framework-notes
description: "Accumulated Network.framework (NWListener/NWConnection) findings and gotchas specific to XBolo, including the unresolved NWListener EINVAL hosting bug. Use before starting any work on BoloNet's transport layer, investigating the hosting bug further, or debugging real-network behavior in this project."
---

# XBolo Network.framework notes

Project-specific accumulated knowledge about `Network.framework` usage in `Sources/BoloNet`.
This is not a general Network.framework tutorial (see Apple's own documentation for that) — it's
what this project has already learned the hard way, so future sessions don't re-derive it.

No published Claude Code skill (local, marketplace, or Apple's own Game Porting Toolkit 4 —
confirmed by direct search 2026-09-09) covers Network.framework/socket-level/multiplayer
networking. This file is the substitute until one exists.

## The open bug: `NWListener` fails with `POSIXErrorCode 22` (EINVAL)

**Status: unresolved, deferred to 1.1 per D128.** Mitigated, not fixed, by an automatic
local-only-play fallback (D109).

Symptoms: `NWListener` construction/start fails with EINVAL on every port tried. Reproduced
independently, outside the app entirely, via a bare standalone Swift binary with no entitlements
and no sandbox — meaning this is not a `BoloNet` code defect, not an entitlements problem, and
not app-specific. Raw BSD `socket()`/`bind()`/`listen()` on the same ports succeeds fine on the
same machine, at the same time — the failure is specific to `Network.framework`'s own listener
path, not the underlying kernel socket layer.

**Ruled out (do not re-investigate these without new evidence):**
- **Beta-OS-specific.** Reproduced on this machine's macOS 27 "Golden Gate" Public Beta, but
  *also* reproduced identically on a separate stable macOS 26.6.2 VM. Not a beta regression.
- **Ad-hoc code signing / missing Local Network permission.** Switched from "Sign to Run Locally"
  to a real Apple Development identity (`DEVELOPMENT_TEAM = L527M49YJ9`) — no permission prompt
  ever appeared either way, and the bug persisted identically after switching. Entitlements were
  independently confirmed correct (5 entitlements present, including `network.server`) before
  this was ruled out.

**Root cause: still not found.** Two full investigation passes (D109's initial diagnosis, D125's
later time-boxed attempt per the path-to-v1.0 plan) did not find it. Jerod has explicitly flagged
further open-ended investigation as an escalation-of-commitment risk on himself — see D128's
"lean v1.0" scope call, which stopped a third investigation pass mid-plan. **Do not open a new
investigation angle without an explicit ask** — this pattern has already been called out once.

If you are asked to investigate again, start from what's *not* yet ruled out rather than
repeating the two ruled-out theories above: candidates not yet tried include VPN/firewall/
network-extension software on the affected machines, and Apple Developer Forums / Feedback
Assistant reports of the same `EINVAL` signature on recent macOS.

## The fallback pattern (D109) — reuse this shape for any future "real network op might fail" case

`HostGameView.startHosting()` attempts `HostListener`/`HostDgramListener` construction; on
failure, it falls back to `AppScreen.hostingFallback(GameState)` — a local-simulation-only path
that reuses the exact same `GameView` initializer as the normal `.playing(GameState)` case, with
an added `notice: String?` for a visible, honest on-screen banner ("Running Local Only — Hosting
is Unavailable on This System"). Never fail silently into local-only play — always disclose it.

## General Network.framework gotchas confirmed in this codebase

- `NWListener`/`NWConnection` state updates arrive via `stateUpdateHandler` closures, not
  throwing calls — errors surface asynchronously, not at construction time. Don't assume a
  successful initializer call means the listener is actually bound; wait for `.ready`.
- This project deliberately does **not** port `Buf.swift`'s POSIX socket-layer half
  (`sendbuf`/`recvbuf`/`selectreadwrite`/`cntlsend`/`cntlrecv`, D31/D42) — only its pure
  byte-queue accumulation half is reused. All actual socket I/O goes through
  `NWConnection`/`NWListener`, async/await wrapped. Don't resurrect the POSIX half by mistake
  when porting more of `Reference/c`'s networking code.
- TCP and UDP are handled as two independent listeners/sessions (`HostListener` /
  `HostDgramListener`, `TCPSession` / `UDPSession`) — mirrors the C reference's own separate
  stream/datagram sockets, not a single multiplexed transport.
- The connection-handshake lifecycle (accept → validate join → keep connection alive for the
  session) is owned by a single type end-to-end (`TCPSession`), not split across a
  connect-scoped helper and a separate live-session object — D113 chose this explicitly after
  finding the alternative (a `withNetworkConnection`-scoped handshake that tears the connection
  down on return) unworkable, citing D102's same "single owner over split lifecycle" precedent.

## Where to look for more

- `docs/PLAN.md` decisions D31, D42, D50, D109, D125, D128, D129, D130 — full ruling text and
  cross-references for everything above.
- `Sources/BoloNet/HostSession.swift`, `TCPSession.swift`, `HostGameEngine.swift` — the actual
  implementation this project has settled on.
