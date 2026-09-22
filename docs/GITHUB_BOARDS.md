# BoloKit GitHub boards

**Source of truth:** issue [#43](https://github.com/CosmicCEO/BoloKit/issues/43). Read it before creating milestones or projects. Do not clone the issue list onto a new board.

## Layers

- **Source** = git + existing issues.
- **Milestone** = time box. `v1.x.0` = RELEASE (tag when every issue closes). `v1.x.y` (`y ≥ 1`) = PATCH between planned sprints. `Decide:` = written ruling, no code.
- **Project** = grouping only, user-owned, **linked** to `CosmicCEO/BoloKit`.

| Project | URL | Contents |
|---------|-----|----------|
| 1.* — path to 2.0.0 | https://github.com/users/CosmicCEO/projects/1 | v1.2–v1.7 issues. Tag 2.0.0 when done. |
| 2.* — open decisions | https://github.com/users/CosmicCEO/projects/2 | Decide:* issues, assignment only. |

Repo tab: https://github.com/CosmicCEO/BoloKit/projects

New v1.* work: existing or new **issue** → release or patch **milestone** → `gh project item-add 1`. New Decide work → Decide milestone → `item-add 2`.

Sprints are two weeks (Monday–Friday of week 2). Skip windows that contain a US federal holiday. Patch milestones do not replace the next `v1.x.0` sprint.

**v1.6.0 is a hard ceiling (2026-09-22 ruling):** its scope is the Metal renderer only ([#25](https://github.com/CosmicCEO/BoloKit/issues/25)). Do not add issues to it. Any new follow-on work that would naturally attach to v1.6.0 (polish, fixes found once the renderer lands) goes to a **v1.6.1** patch created after v1.6.0 ships, not into v1.6.0 itself. Work found before then that isn't v1.6.0-scoped stays in the `v1.5.x` patch line.

Projects v2 mechanics (scopes, link): user skill `github-projects-v2`.
