# v1.5.1 — Live play fixes (draft release notes)

Draft: confirm each item is merged before publishing, then paste into the GitHub release.

## Summary
Two-player LAN play with Hidden Mines works end to end on two Macs: the guest sees the map, the host's
name and tank, and can fire, lay mines and form alliances. The host now simulates the guest's tank, shells and
mines, so combat is host-authoritative. A guest that leaves and rejoins is the one known break; see below.

## Fixed since v1.5.0
- Guest map no longer renders all black with Hidden Mines on (#75); host-laid mines and host builder edits reach
  guests (#76, #84); host name shows on the guest (#85).
- Guest alliances work from both sides (#92); the guest sees the host's respawn at its new position (#61).
- Host simulates guest tanks (#59/#62): firing, shells, explosions, mine triggers and a host-owned mine count.
- Hidden Mines no longer announces a remote-laid mine at range (#106).
- Host draws never-seen tiles as plain sea, matching the guest, instead of black.
- A remote tank's name label now fades and hides with distance instead of always showing (#79, live-confirmed 2026-09-22).
- The host quitting to the menu now shows the guest a disconnected message instead of leaving its session hanging (#107, live-confirmed 2026-09-22).
- A guest's key-down mine no longer detonates under its own tank when the drop lands on the tile it already occupies (#105, PR #121, merged 2026-09-22). Note: the 2026-09-22 two-Mac run on this build didn't re-exercise the original continuous-lay-while-moving repro scenario specifically.

## Known limitations
- **Leaving and rejoining a hosted game breaks the rejoined guest** (#113, fix planned for v1.5.2). After a guest
  quits to the menu and rejoins, its screen does not refresh and its tank stops responding — pinned down
  2026-09-22 to losing control once it reaches the map border, not a fixed distance from spawn. **A rejoin under
  a new player name does not avoid this**: it renders the map correctly but spawns the tank at wherever the
  previous session was frozen, not a fresh spawn point (corrects this note's earlier claim that a new name
  "worked in testing"). Everything else in a two-player game was fine in testing as long as nobody left.
- The guest is not fogged for tanks or pillboxes/bases: it can see the host tank and other structures outside its own
  vision (#86/#90, closed as not planned for this release).
- A first join can fail once and succeed on the second try, and a real Mac joining a VM host was refused once (#93).
- Shells can vanish partway through their flight under Hidden Mines, and the pattern looks angle-of-travel-dependent
  rather than purely a fog-edge fade — reproduces even with Hidden Mines off (#114).
- Breaking an alliance removes the ally's tank sprite but does not re-fog the terrain that alliance had revealed —
  the map stays exactly as it was while allied (#120, found 2026-09-22, tracked and the focus of v1.5.2).
- A builder-laid mine may not render as visible to the host until the tank moves (a render-refresh gap, #77) —
  closed 2026-09-22 per triage direction without a dedicated re-test; flag if it resurfaces.
- Pill/base capture, build and deploy are still not fog vision sources (#72).
