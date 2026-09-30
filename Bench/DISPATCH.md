# Dispatch

Mailbox between the **remote lead** (this Grok project) and **Grok CLI on the M1**.
One job at a time. Same file is the instruction and the report.

Branch: `bench/v1.6.9-baseline`
Path: `Bench/DISPATCH.md`

## How the on-system Grok checks

From the repo on the Mac, whenever you sit down or on a short loop:

```sh
git fetch origin bench/v1.6.9-baseline
git checkout bench/v1.6.9-baseline
git pull --ff-only origin bench/v1.6.9-baseline

grok -p "$(cat Bench/DISPATCH.md)

You are the on-system Grok for BoloKit. Read this file.

If Job status is idle: stop. Reply that there is no job.

If Job status is queued:
1. Set status to claimed, write Claimed, commit and push only this file.
2. Do the Instruction. You choose the commands. The lead's examples are options, not orders.
3. Write Report (what you did, paths, numbers, blockers).
4. Set status to done or blocked. Commit and push this file plus any files the job required.
5. Do not start Improve. Do not change the wire. Do not write into Bench/data/measure/.

If Job status is claimed or running and the claim is yours: continue and report.
If claimed by someone else: stop."
```

Headless is fine: `grok -p "..." --cwd <repo>`. Interactive `grok` in the repo with `@Bench/DISPATCH.md` is the same job.

Remote lead writes a new Job only when status is `idle` or `done`/`blocked` (after reading the Report). Never overwrite a live Report.

---

## Job

| Field | Value |
|---|---|
| Id | JOB-001 |
| From | remote-lead |
| To | grok-cli-m1 |
| Created | 2026-09-29 |
| Status | **queued** |
| Claimed | |

### Instruction

Finish **P0a** so Analyze can read fog memory only when a tile is in fog, then produce one Analyze scorecard from the existing raw logs if they are on this machine.

Outcome:

1. `Sources/BoloBenchCore/Divergence.swift` compiles and calls `fogComparableParts` for the `.fog` arm. Last-seen is not compared while bit 0 is set (tile visible).
2. Tests exist that fail the old behaviour and pass the new one (visible + different memory → no `fogSeen` episode; in-fog + different memory → one episode).
3. If `Bench/runs/` for the v1.6.9 measure freeze is on this Mac, re-analyze into `Bench/data/analyze/p0a-fog-join/`. Do not touch `Bench/data/measure/`.
4. If logs are missing, say so in Report and stop after (1)–(2). That is still a valid done for the code half.

Do **not** implement 1A, 2B, 2C, 3B, or 4B. Do **not** treat `guest.remote_move_interval_ms` or the builder-mine 1.3 s row as targets.

Known hazard: commits `b2f8494` and `884fb09` left `Divergence.swift` with over-escaped strings and/or a truncated file. Prefer restoring a known-good full file (parent of those commits, or history at `b3e6cdc`) and applying the one-line wire, rather than editing the broken tip.

`FogCompare.swift` and `Bench/3-analyze/P0A.md` are already on the branch.

### Report

*(on-system writes here)*

| Field | Value |
|---|---|
| Finished | |
| Result | |
| Divergence compiles | |
| Tests | |
| Scorecard path | |
| fogSeen after P0a | |
| Blocker | |

Notes:

---

## Log

| When | Who | What |
|---|---|
| 2026-09-29 | remote-lead | Opened mailbox. Queued JOB-001 (P0a). |
