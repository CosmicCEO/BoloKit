# Host/client DMAIC

Index only. Read this, then open the one file you need.

| Phase | Status | Read |
|---|---|---|
| 1. Define | Closed | `1-define/README.md` |
| 2. Measure | Closed 2026-09-29 | `2-measure/README.md` |
| 3. Analyze | In progress | `3-analyze/KT.md`, `3-analyze/SPECS.md` |
| 4. Improve | Not started | `4-improve/README.md` |
| 5. Control | Not started | `5-control/README.md` |

## Where things are

| Need | File | Size |
|---|---|---|
| The benchmark's headline numbers | `2-measure/README.md` | Small |
| How the measurement system works, every metric defined | `2-measure/SYSTEM.md` | Medium |
| One metric's value, interval and run values | `data/measure/v1.6.9-baseline/<tier>/<scenario>/scorecard.json` | Large: query it, do not read it whole |
| One run's metrics | `data/<phase>/<name>/<tier>/<scenario>/run-NN/summary.json` | Large |
| What a session was run on | `data/<phase>/<name>/manifest.json` | Small |
| Findings and hypotheses | `3-analyze/README.md` | Small |
| Raw logs | `runs/<phase>/<name>/` on the benchmark machine, not in git | 2.3 GB a session |

Query a scorecard instead of reading it:

```sh
python3 -c "import json,sys; m=json.load(open(sys.argv[1]))['metrics'][sys.argv[2]]; print(m['median'], m['low'], m['high'], m['repeatable'])" \
  Bench/data/measure/v1.6.9-baseline/pair/s1-join-and-spawn/scorecard.json host.tick_ms.game.p50
```

## Rules

- **Data is filed and tagged by the phase that produced it:** `data/<phase>/<name>/`, with
  `"phase"` in its `manifest.json`, and a git tag `<phase>/<name>` once frozen.
- **A directory holding a `FROZEN` file is never edited or run into again.**
- **Each phase's `README.md` stays short.** Detail goes in a second file beside it.

## Running

```sh
zsh Bench/scripts/run-baseline.sh <phase> <name>     # a whole session, about two hours
zsh Bench/scripts/run-pair.sh <scenario> [runs]      # one scenario
zsh Bench/scripts/run-sweep.sh <players> [runs]      # host cost at a player count
```
