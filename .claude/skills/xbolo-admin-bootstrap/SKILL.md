---
name: xbolo-admin-bootstrap
description: "Use at the start of any XBolo Admin session to load the Admin role, run git pre-flight checks, and safely report repo status without touching concurrent work."
---

# XBolo Admin Bootstrap

This skill starts an Admin session for the XBolo project (the Swift port of xbolo/Bolo). It loads
the Admin role instructions and establishes a safe, current picture of the repo before doing
anything else.

## Steps

1. **Read `docs/admin.md`** in the XBolo repo (on the user's connected device, via the device
   bridge — this repo lives on the user's local machine, not the cloud workspace). This is the
   authoritative, current source for the Admin role. Do not rely on a summary from a prior
   session — re-read it fresh each session, since it can change.

2. **Run git pre-flight checks** before touching anything:
   - `git log --oneline -5`
   - `git status --short`
   - `git branch --show-current`

   This project routinely runs multiple concurrent sessions (Implementer/Planner/Parity/Admin)
   against the same working tree. Uncommitted or staged changes in the working tree that don't
   match what you're about to do are very likely another session's in-progress work — leave them
   untouched. Never assume the tree is clean.

3. **Recap the Admin role in your own words** back to the user: cross-checking
   `docs/AGENT_NOTES.md` against `docs/PLAN.md`, repo housekeeping (README, stale git locks,
   periodic archive/compression passes on `AGENT_NOTES.md`), logging admin/process questions in
   `PLAN.md`'s Q-numbered open-questions table, and relaying status to the user in plain terms —
   while explicitly NOT writing Swift, not auditing C-vs-Swift parity, and not ruling on
   wave-sequencing or architecture decisions.

4. **Report findings plainly**, including:
   - What the last several commits were (skim messages for context: recent Admin/Planner/Parity
     activity).
   - Whether the working tree is clean. If it's dirty, list the modified files and state clearly
     that they look like a concurrent session's in-progress work and won't be touched.
   - Offer next steps consistent with the Admin role (e.g., cross-check AGENT_NOTES.md vs
     PLAN.md's wave-status/decisions/open-questions tables, a README sync, an archive pass) rather
     than picking one unprompted.

## Git discipline reminders (from docs/admin.md — always apply)

- Never run a bare `git commit` when anything else might be staged — always commit with an
  explicit pathspec (`git commit <file1> <file2> -m "..."`).
- Check `git status --short` immediately before every commit and actually read it.
- If a commit accidentally mixes in files that aren't yours, do NOT try to surgically un-mix it
  with `reset`/`revert`. Log it as an incident in `docs/AGENT_NOTES.md`, tagged for the affected
  role to verify, and move on.
- This session cannot push to GitHub — commit locally and say so; don't imply the change is live
  until the user has pushed it.
- Requesting delete permission (e.g. for stale `.git/*.lock` files) should be narrow (repo root is
  enough) with a one-line reason, and only when a lock is actually blocking a commit.

## Scope boundaries (do not cross)

- No writing Swift, no C-vs-Swift parity auditing, no choosing/declaring waves "done", no
  unilateral architecture decisions.
- Real scope gaps or inconsistencies found in the plan itself get reported, not silently fixed —
  that's Planner's (or the user's) call.
- D-numbered decisions in `PLAN.md` are never authored unilaterally, even when the answer seems
  obvious — only Q-numbered open-questions entries and status-table text corrections are Admin's
  to write directly.