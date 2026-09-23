# v1.6.0 — Metal-tastic

Tagged 2026-09-23.

## Summary

Terrain and sprite rendering moved from CPU `CGContext` blits to a live Metal overlay, removing
the render-cost ceiling that capped the tile budget at 9,000 (roughly a third of the map) —
Metal is now the default renderer, and there's no longer a visible tile-count ceiling at max
zoom-out. Along the way, live two-Mac testing surfaced and fixed a real, unrelated multiplayer
desync bug: guest-side pill/base capture, combat damage, base refuel, and builder-completion
actions weren't reaching the other player, a side effect of the earlier #59/#62
host-simulates-guest-tanks redesign moving those actions off the network-broadcasting code path.

Every fix in this release has been confirmed on real two-Mac hardware.

## Fixed / added since v1.5.1

**Metal renderer (#25):**
- Terrain and sprites render via a `CAMetalLayer`-backed `MTKView` floating behind the scroll
  view, live camera tracking, pixel-exact parity with the CPU path (offscreen pixel-diff harness
  covers both).
- Fixed a real live resize/scale bug found on first evaluation: the overlay's `MTKView` was
  sized off the whole scroll view (HUD chrome included) instead of the inset-excluded visible
  region — terrain and sprites disagreed on scale as the window resized, worse on a narrow
  window. Fixed by sizing off the clip view's frame instead, with explicit resize/scroll
  observers.
- Switched the overlay from a continuous ~60 Hz draw loop to on-demand rendering (redraw only on
  camera movement or an actual tile-grid change) — the continuous loop was competing with the
  network/tick consumer for the same thread, the root cause of a guest-side rendering-adjacent
  lag report.
- Raised the tile-count budget for the Metal path (effectively uncapped, matching the original
  game, which never had this ceiling); the CPU fallback keeps its original, measured budget.
- Live-confirmed clean at every window size, zoom level, and during active pan/resize; no
  tile-count ceiling visible at max zoom-out.

**Guest desync fixes (found live, unrelated to #25):**
- Pillbox pickup, build, and repair now sync to the guest — previously the guest's own client
  never learned a pill's ownership/armour had changed, matching "Mac B ran over the pillbox
  according to the host screen; Mac B doesn't think it was collected."
- Base capture (neutral and hostile takeover) now syncs — including the capture-war/regen
  mechanic: a base under 5 armour is freely re-capturable by anyone, matching the original
  game's own collision rule exactly, so a freshly-captured base can be immediately retaken until
  it regenerates.
- Combat damage to pill/base armour, and base refuel depletion, now sync — previously a guest
  watching a base they'd shot would see it silently regenerate with no visibility into its real
  armour.
- A builder's walked-to-completion pill build/repair now syncs (the instant click-command path
  already worked).

**Networking (found and fixed alongside the render work):**
- Guest-side TCP connection now sets `TCP_NODELAY`, matching the host's own listener — the
  guest's outbound actions (mine placement, etc.) were exposed to Nagle-algorithm coalescing
  delays the host side never had.
- Guest-side `TCPSession` moved off the main dispatch queue, removing contention with the
  render/tick loop.

## Known limitations

- Intermittent black seam lines in the live Metal terrain overlay, sea-only, hard to reproduce
  (#137) — cosmetic, not a blocker, tracked for v1.6.1.
- Builder movement after death can look unrouted before snapping to a direct line (#138) — seed
  issue from a live observation, not yet root-caused.
- A host-engine crash signature (SIGABRT, data-race shape in `GameState.local` mutation during
  `tankLocalTick`) was found via a crash log from an **older** (`v1.5.1`) build left running
  overnight (#139) — not yet reproduced live or confirmed against this build; flagged for
  investigation, not blocking this release.
- Whether a host-placed pillbox is visible to a guest (the reverse direction of the
  guest-builds-a-pillbox case, which is confirmed working) has not been directly tested.
