---
name: bolokit-github-boards
description: >
  BoloKit GitHub board layout: issues (source), v1.* vs Decide milestones,
  Projects 1.* and 2.* linked to the repo. Use when adding milestones,
  projects, due dates, 1.*, 2.0, Decide items, or board conventions for
  CosmicCEO/BoloKit. /bolokit-github-boards
---

# BoloKit GitHub boards

**Source of truth:** issue [#43](https://github.com/CosmicCEO/BoloKit/issues/43). Read it before creating milestones or projects. Do not clone the issue list onto a new board.

## Layers

- **Source** = git + existing issues.
- **Milestone** = time box. `v1.x.0` = RELEASE (tag when closed). `Decide:` = written ruling, no code.
- **Project** = grouping only, user-owned, **linked** to `CosmicCEO/BoloKit`.

| Project | URL | Contents |
|---------|-----|----------|
| 1.* — path to 2.0.0 | https://github.com/users/CosmicCEO/projects/1 | v1.2–v1.7 issues. Tag 2.0.0 when done. |
| 2.* — open decisions | https://github.com/users/CosmicCEO/projects/2 | Decide:* issues, assignment only. |

Repo tab: https://github.com/CosmicCEO/BoloKit/projects

New v1.* work: existing or new **issue** → v1.* **milestone** → `gh project item-add 1`. New Decide work → Decide milestone → `item-add 2`.

Projects v2 mechanics (scopes, link): user skill `github-projects-v2`.
