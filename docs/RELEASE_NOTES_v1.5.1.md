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

## Known limitations
- **Leaving and rejoining a hosted game breaks the rejoined guest** (#113, fix planned for v1.5.2). After a guest
  quits to the menu and rejoins, its screen does not refresh and its tank stops responding about 2 tiles from spawn.
  A rejoin under a new player name worked in testing. Everything else in a two-player game was fine in testing as
  long as nobody left.
- The guest is not fogged for tanks or pillboxes/bases: it can see the host tank and other structures outside its own
  vision (#86/#90, closed as not planned for this release).
- A first join can fail once and succeed on the second try, and a real Mac joining a VM host was refused once (#93).
- Shells can vanish partway through their flight under Hidden Mines (#114).
- Pill/base capture, build and deploy are still not fog vision sources (#72).
