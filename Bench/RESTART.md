# Restart plan: host/client DMAIC

**Paused 2026-10-12 by Jerod, for some time.** Written while the work was fresh. Read this first
when picking the project up again, then `4-improve/RESULTS.md`.

## Where it stands

| Area | State |
|---|---|
| Release | `v1.6.10` published, tag on merge commit `ed2d980`. Four Improve changes: sound player, remote tank smoothing, mine refund, fog memory on a reveal. No wire change |
| DMAIC | Define, Measure, Analyze closed. Improve: session 1 done, three questions open. Control: not started |
| Improve results | 2D met. 3B met on the mine count. 1A partly met (25 to 32 ms median against a 20 ms target). 4B not shown by the soak. Sound playtested by Jerod, on target |
| Open issues | [#197](https://github.com/CosmicCEO/BoloKit/issues/197) same-OS control run; [#198](https://github.com/CosmicCEO/BoloKit/issues/198) decisions on 4B proof, 1A targets, shell-count episodes |
| Board | Milestones `v1.6.10` (view parity) and `v1.6.11` (tick-budget perf) clash with the tag now used. Jerod's call; issue #43 is the source of truth |
| Token ceiling | Improve's 350,000 is spent, about 290,000 by estimate. Any further session needs a new ceiling from Jerod |

## Order of work on restart

1. **Jerod answers [#198](https://github.com/CosmicCEO/BoloKit/issues/198).** Each question has a recommendation. The answers set what Improve still owes.
2. **Run [#197](https://github.com/CosmicCEO/BoloKit/issues/197), the same-OS control.** Two hours. Best done back to back with a second candidate session on the same OS (about four hours in all), which also settles the shell-count episodes.
3. **Write the result into `4-improve/RESULTS.md`**, freeze the new data, tag it, and close Improve with a short decisions table.
4. **Open Control.** Proposal, not a decision:
   - Turn the tripwires on `3-analyze/SPECS.md` into a release gate: a short session (soak, 4-player sweep, a pair run of s5) compared with the newest frozen baseline.
   - Re-baseline on the OS then in use, once, so later comparisons are like for like.
   - File the gate in `5-control/README.md`, with the cost in tokens and hours of one gate run.
5. **Parked for 2.\*:** periodic state checksum or resync, tank shots off the reliable channel, batched reveals, guest reports the builder launch. All need a wire change; see `3-analyze/REGISTER.md`.

Held items now closed or moot: the host render hop (work is 0.5 to 0.8 ms after 2D), and the position send (whole tick meets its target).

## Before the first run

**Worktree.** `/Users/jerodprice/Developer/XBolo/.claude/worktrees/bench-1-6-9-baseline`, locked by Jerod, left detached at `main`. Work on a new branch from `origin/main`, not on main.

**Conditions** (the session is invalid otherwise; `4-improve/RESULTS.md` has why):
- AC power, Low Power Mode off, nothing else running, display awake, both game windows fully visible.
- Screensaver off and a still wallpaper (an animated wallpaper cost 60 runs once). The script keeps the Mac awake, but frame rate should read about 50 in the warm-up.
- Archive disk `Mingus` mounted. Raw logs are 2 to 4 GB a session and move to `/Volumes/Mingus/Xcode/archive/<phase>/<name>/` when a session ends.
- Record the macOS build. The session in #197 exists because two sessions differed by one point release.

**Launch** (from the worktree; the wire check mode follows the phase):

```sh
nohup zsh Bench/scripts/run-baseline.sh <phase> <name> 10 5 0 > Bench/runs/<name>.log 2>&1 &
```

Phase `improve` selects the improve wire check; every other phase stays strict, so a `control` run
needs the script's phase test widened first (one line in `run-baseline.sh`, and the classifier
will want an approval). Watch the log for `== done`, a failure line or the process vanishing:

```sh
log=Bench/runs/<name>.log; while true; do
  grep -qE 'wire protocol differs|build failed|stopping' "$log" && { tail -3 "$log"; exit 1; }
  grep -q '^== done' "$log" && { echo done; exit 0; }
  pgrep -f run-baseline.sh > /dev/null || { echo "process gone"; exit 1; }
  sleep 120; done
```

A monitor times out at 30 minutes and must be re-armed.

**Compare.**

```sh
.build/release/BoloBench compare <baseline scorecard.json> <candidate scorecard.json>
python3 Bench/4-improve/readout.py 2d        # tick budget
python3 Bench/4-improve/readout.py 1a        # drawn step
python3 Bench/4-improve/readout.py runs <metric> ...   # runs with a fault
```

`readout.py` has the session 2 and candidate 1 paths written in at the top. Change them for a new pair.

**Permissions on this Mac.** Claude Code's auto-mode classifier refuses edits and runs of the wire-check scripts as a "CI bypass", even after approval in chat. What worked: rules in `/Users/jerodprice/Developer/XBolo/.claude/settings.local.json`:

```json
"Bash(zsh Bench/scripts/*)",
"Bash(BOLO_WIRE_CHECK=improve zsh Bench/scripts/*)",
"Bash(git commit *)"
```

The file must stay valid JSON: a missing comma silently dropped the rules once. Commands must match a rule's form, with no pipes and no `cd`. Git inside another worktree is refused; use the session's own.

## Where things are

| What | Where |
|---|---|
| Frozen baselines | `data/measure/v1.6.9-baseline`, `data/analyze/v1.6.9-analyze-session2`, `data/analyze/p0a-fog-join`, `data/improve/candidate1-2d-1a-4b-3b` (each has a `FROZEN` file; tags `measure/v1.6.9-baseline`, `analyze/v1.6.9-analyze-session2`, `improve/candidate1-2d-1a-4b-3b`) |
| Raw logs | `/Volumes/Mingus/Xcode/archive/{measure,analyze,improve}/` |
| Improve readout and decisions | `4-improve/RESULTS.md`, `4-improve/README.md` |
| Specs and register | `3-analyze/SPECS.md`, `3-analyze/REGISTER.md` |
| How the instrument works | `2-measure/SYSTEM.md` |
| Scratch files | `Bench/runs/` is gitignored and holds only logs and one-off helpers. Nothing needed to restart lives there; the launch and watch commands are in this file |
| Wire rule | Closed to 1.\*, open to 2.\* (Jerod, 2026-09-29; `3-analyze/KT.md`). Not to be asked again |
| CI | Stays disabled. Do not propose re-enabling or fixing `test.yml` |

## Tooling gaps found, not yet fixed

1. **`BoloBench compare` does not check the macOS build.** It refuses on schema, scenario, tier or hardware model only. It should refuse or warn when `osBuild` differs, since that is what made #197 necessary.
2. **The scorecard counters hide fault signatures.** `resources.slow` stayed flat while mine-count episodes fell from 10 to 1, because other episodes took their place. A per-signature readout (element and value pair) belongs in `BoloBench`; today it is an ad hoc script.
3. **Fog episodes count tiles, resource episodes count differences.** The two are not comparable as counts and `RESULTS.md` says so; a per-run fault flag would be cleaner.
4. **The manifest's `dirty` flag is always true** because the new results folder is untracked at that point. It should ignore `Bench/data`.
5. **The vision-area mismatch** (tiles one side has seen and the other has not) is a real defect that was in the baseline and has no item of its own. It is raised in #198.
