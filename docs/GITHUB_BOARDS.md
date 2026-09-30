# BoloKit GitHub boards

**Source of truth:** issue [#43](https://github.com/CosmicCEO/BoloKit/issues/43). Read it before creating milestones or projects. Do not clone the issue list onto a new board.

## Layers

- **Source** = git + existing issues.
- **Milestone** = time box. `v1.x.0` = RELEASE (tag when every issue closes). `v1.x.y` (`y ≥ 1`) = PATCH between planned sprints. `v2.0.0` = the first wire-breaking RELEASE. `Decide:` = written ruling, no code.
- **Project** = grouping only, user-owned, **linked** to `CosmicCEO/BoloKit`.

| Project | URL | Contents |
|---------|-----|----------|
| 1.* — path to 2.0.0 | https://github.com/users/CosmicCEO/projects/1 | v1.2–v1.8 releases and v1.6.x patches. Wire-compatible work only. |
| 2.* — path to 2.0.0 and open decisions | https://github.com/users/CosmicCEO/projects/2 | Decide:* issues plus the v2.0.0 wire-breaking release. Assignment only. |

Repo tab: https://github.com/CosmicCEO/BoloKit/projects

New v1.* work: existing or new **issue** → release or patch **milestone** → `gh project item-add 1`. New Decide work → Decide milestone → `item-add 2`. Wire-breaking work waits for a Decide ruling, then moves to the `v2.0.0 — Wire v2` milestone. `item-add` succeeds before `gh project item-list` shows the item; verify from the issue side (`projectItems` in GraphQL) instead of re-adding.

Sprints are two weeks (Monday–Friday of week 2). Skip windows that contain a US federal holiday. Patch milestones do not replace the next `v1.x.0` sprint.

**Hard-ceiling rulings age out fast on this project** (the 2026-09-22 "v1.6.0 is a hard ceiling"
ruling this paragraph used to state was itself six tags stale within two days). Don't hardcode a
milestone name/date here — read `docs/STATUS.md`'s "Path to 2.0.0" table for the current sprint
target and its ceiling instead. As of 2026-09-30 the next patch is `v1.6.10 — View and status-panel parity`, the next `v1.x.0` release
target is `v1.7.0 — Gameplay packs` (data-only packs, wire unchanged), and `v1.8.0 — LAN/WAN discovery`
follows it. Wire-breaking scope, if any, lands on `v2.0.0 — Wire v2` after Decide rulings.

Projects v2 mechanics (scopes, link): user skill `github-projects-v2`.
