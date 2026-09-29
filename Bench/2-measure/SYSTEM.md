# The measurement system

A measurement system for Bolo 2026's host/client play, and the procedure for freezing a baseline
with it. Built on a branch cut from `v1.6.9`, so that later changes to the netcode can be judged
against numbers.

It measures three things with equal weight:

| | Question | Examples |
|---|---|---|
| **Correctness** | Do host and guest agree on the game? | How long each disagreement lasts, how many never resolve |
| **Responsiveness** | How long until a player sees it? | Tick pacing, message delay, input to frame |
| **Cost** | What does it take from the machine? | Tick time by phase, bytes per second, CPU |

It changes no gameplay and nothing that goes over the wire. `check-no-wire-change.sh` proves that
against the tag.

## Running it

Everything runs on one Mac. Before starting: plug in, turn Low Power Mode off, quit everything
else, and leave the Mac alone until it finishes. Two game windows open and close for every run and
must stay fully visible, because macOS slows the timers of a window it cannot see.

```sh
# The whole baseline: about two hours.
zsh Bench/scripts/run-baseline.sh measure v1.6.9-baseline

# One scenario, three runs.
zsh Bench/scripts/run-pair.sh s5-death-and-respawn 3
.build/release/BoloBench analyze Bench/runs/s5-death-and-respawn/run-01

# Host cost with eight players.
zsh Bench/scripts/run-sweep.sh 8 1

# A later version against the frozen baseline.
.build/release/BoloBench compare \
  Bench/data/measure/v1.6.9-baseline/pair/s5-death-and-respawn/scorecard.json \
  Bench/data/improve/v1.7.0/pair/s5-death-and-respawn/scorecard.json
```

| Script | Does |
|---|---|
| `run-baseline.sh <phase> <name> [runs] [sweep-runs] [observer-runs]` | Checks conditions, builds, runs everything, writes `Bench/data/<phase>/<name>/` |
| `run-pair.sh <scenario> [runs] [first]` | One host and one guest, both the Release app, over `127.0.0.1` |
| `run-sweep.sh <players> [runs] [first]` | One host and `players - 1` synthetic guests |
| `check-no-wire-change.sh [base]` | Fails if the wire protocol or the simulation differs from the base |

| `BoloBench` command | Does |
|---|---|
| `analyze <run-dir> [--tier <tier>]` | One run's logs to `summary.json` |
| `scorecard <scenario-dir>...` | Every run's summary to `scorecard.json`, with a repeatability verdict per metric. Several directories pool their runs |
| `compare <baseline> <candidate>` | Which metrics changed |
| `observer <recording-dir> <not-recording-dir>` | What recording costs |
| `overhead` | The recorder's cost per record on this machine |
| `scenario [name]` | The scenario list with hashes, or one scenario as JSON |

## How it works

**Each process records raw facts; all comparison happens afterwards.** The app is always built
with the recorder, and the recorder is `nil` unless the app is started with `BOLO_BENCH=1`, so
with recording off each call site costs one nil check. When on, every record is a timestamp and
five integers, written to a preallocated ring and flushed to a JSONL file four times a second.

Both instances run on one Mac and read one clock (`CLOCK_UPTIME_RAW`), so the host's log and the
guest's log merge into a single timeline with no clock-offset estimate.

| Tier | What runs | Used for |
|---|---|---|
| Validation | Real host engine and real sessions inside the test process | Proving the instrument is right |
| Pair | The Release app twice, playing a scripted scenario | Every number on the scorecard |
| Sweep | The Release app hosting, plus synthetic guests | Host cost at 2, 4, 8 and 16 players |

### Environment variables

| Variable | Meaning |
|---|---|
| `BOLO_BENCH=1` | Record |
| `BOLO_BENCH_FD=<n>` | Write the log to this already-open file descriptor |
| `BOLO_BENCH_ROLE=host\|join` | Play one side of a scenario unattended, then quit |
| `BOLO_BENCH_SCENARIO=<name>` | Which scenario |
| `BOLO_BENCH_HOST`, `BOLO_BENCH_PORT` | Where to join or listen (default `127.0.0.1`, `50000`) |
| `BOLO_BENCH_STATE=0` | Do not record state (the sweep) |
| `BOLO_BENCH_RUN_ID=<id>` | Stamped into the log's header |

The app is sandboxed, so a log it created itself would land in its container, which other
processes may not read. The run scripts open each log themselves and pass it down as descriptor 3.

## Scenarios

All use the bundled default map, with the host as player 0 and the guest as player 1. Each side
plays a script through the same hooks the keyboard uses. Steps wait on the state of the game, not
on the clock.

| Scenario | What happens | Written to expose |
|---|---|---|
| `s1-join-and-spawn` | The guest joins and spawns | Join stall, the first reveal burst, one-shot wiring |
| `s2-pill-pickup-and-capture` | The guest collects and places a pill; the host shoots it | Unreported change, double application |
| `s3-mine-laying` | One mine from the tank, one by the builder | Resource accounting, masked message |
| `s4-building` | A road and a wall, firing while the builder is out (Hidden Mines off) | Stale overwrite of trees and mines |
| `s5-death-and-respawn` | The guest dies carrying a pill and is respawned | Dropped-pill sync, the respawn teleport |
| `s6-fog-crossing` | The host builds where the guest cannot see; the guest returns | A change masked and never delivered |
| `s7-sustained-fire` | The guest fires until it has nothing left | One reliable message a tick per shell in flight |
| `s8-soak-open`, `s8-soak-hidden` | Seeded random play for 60 s | Breadth |

A scenario's hash is taken from its full definition. Results from different hashes are never
pooled or compared, so changing a scenario starts a new series.

## Correctness

The host logs what it expects one guest to hold. That guest logs what it holds. An element is
**divergent** for as long as both have a comparable value and the values differ.

| Length | Meaning |
|---|---|
| In flight | Up to 250 ms: the send cadence, a tick and the delivery |
| Slow | Over 250 ms, up to 2 s |
| Persistent | Over 2 s, but it converged |
| Terminal | Still divergent when the run ended |

| Domain | Compares |
|---|---|
| `pills`, `bases` | Position, armour, owner; for bases also shells and mines |
| `selfStatus` | The guest's dead, boat and carried-pill flags |
| `resources` | The guest's armour, shells and mines |
| `terrain` | Every tile in the guest's vision, by class |
| `fogVisible`, `fogSeen` | Which tiles the guest can see now, and what it last saw there |
| `peers` | Each other player's connected, dead and boat flags |

Four more are reported and never counted as faults, because they differ by design:

| Domain | Why it differs |
|---|---|
| `position` | The guest owns its own movement; the host follows at 10 Hz |
| `peerPosition` | Other tanks arrive at 10 Hz |
| `trees` | Guest-owned since v1.6.9 |
| `terrainVariant` | The map format does not carry growth and damage variants |

A tile outside the guest's vision is never divergent. With Hidden Mines on, the host stops
reporting changes there by design.

Each episode that outlasts delivery gets a **candidate class**, one of the six in the
`debugging-host-client-desync` skill. It is a lead for a person to follow. It is not a finding.

## Metrics

Names are `<side>.<metric>[.<detail>].<statistic>`. Distributions report `.n`, `.p50`, `.p95`,
`.p99` and `.max`. The defining code is `Sources/BoloBenchCore/RunAnalysis.swift`.

| Metric | Unit | Definition |
|---|---|---|
| `correctness.<domain>.<length>` | episodes | Count by domain and length |
| `correctness.<domain>.convergence_ms` | ms | Duration of each episode that ended |
| `correctness.<domain>.divergent_time_pct` | % | Share of the run with any element divergent past 250 ms |
| `correctness.candidate.<class>` | episodes | Count by candidate class |
| `correctness.fog_over_reveal_tiles`, `fog_under_reveal_tiles` | tiles | The guest seeing more, or less, than the host believes |
| `<side>.invariant_violations` | count | Armour, shells or mines outside 0 to 40 |
| `<side>.datagram_rejects.<cause>` | count | Every one, not just the first |
| `link.udp.<direction>.loss_pct`, `.reordered` | %, count | From the sequence numbers already on the wire |
| `<side>.tick_interval_ms` | ms | Between tick handler entries; `.over_25_pct` is the share over 25 ms |
| `<side>.tick_queue_delay_ms` | ms | Timer fire to handler entry |
| `<side>.queue_depth` | events | Waiting when each tick was entered |
| `link.ack_age_ms.<side>` | ms | From sending an update to seeing it acknowledged |
| `link.udp.<direction>.delay_ms` | ms | The same update, sent on one log and received on the other |
| `link.tcp.send_to_read_ms`, `send_to_applied_ms` | ms | Host send call to guest read, and to guest applied |
| `link.position_delay_ms.<direction>` | ms | A tank's tile changing on one side, then on the other |
| `<side>.input_to_frame_ms` | ms | A scripted key press to the first frame showing the state after it |
| `guest.remote_move_interval_ms` | ms | Between movements of the host's tank on the guest's screen |
| `<side>.frame_interval_ms`, `frames_per_s` | ms, Hz | Sprite pass |
| `host.join_handshake_ms`, `join_stall_ms` | ms | The handshake, and the longest tick gap during it |
| `guest.join_to_alive_ms` | ms | TCP join complete to first alive |
| `guest.extrapolation_ticks` | ticks | Dead-reckoning ticks run per update applied |
| `<side>.tick_ms.<phase>` | ms | Tick time by phase; `game` is the whole less the instrument's own sampling |
| `<side>.apply_us.<channel>` | µs | Handling one message |
| `<side>.<tx\|rx>.<channel>.bytes_per_s`, `.messages_per_s` | | Payload only |
| `<side>.<tx\|rx>.tcp.op<N>.messages`, `.bytes` | | Per opcode |
| `<side>.send_completion_us.<channel>` | µs | Send call to completion |
| `<side>.cpu_pct`, `memory_mb` | % of one core, MB | Sampled once a second |
| `<side>.draw_ms.sprites`, `draw_ms.terrain` | ms | The CGContext pass and the Metal pass |
| `<side>.tile_grid_rebuild_ms`, `tile_grid_rebuilds_per_s` | | |
| `<side>.recorder.self_us_per_tick`, `recorder.dropped` | µs, count | The instrument's own cost; drops invalidate a run |

"Frame" means the end of the draw call. That is up to one display refresh before the pixels
change. The bias is the same in every run as long as the renderer is unchanged.

## Is the measurement itself trustworthy?

A number is only worth comparing if measuring the same thing twice gives the same number. Each
metric on a scorecard is judged by a rule chosen from its name.

| Rule | Applies to | Repeatable when |
|---|---|---|
| `relative5` | Medians of cost metrics | Half-width of the median's 95% interval is within 5% of the median |
| `relative10` | 95th percentiles | The same, within 10% |
| `within10ms` | Delays across the link | Half-width within 10 ms, half a tick |
| `variation2` | Message and byte counts | Coefficient of variation within 2% |
| `verdict` | Divergence and error counts | At least 9 runs in 10 agree on whether there was any |
| `reportOnly` | 99th percentiles, maxima, sample counts | Reported, never judged, never compared |

A relative bound is not applied below a floor (0.05 ms, 5 µs, 0.5 percentage points, 1 MB), where
it would ask for more than the clock and the scheduler can give.

A metric that is not repeatable in the baseline is kept on the scorecard and never compared. A
divergence count that fails the `verdict` rule is an intermittent fault, and is read as a rate.

### What makes a run invalid

Killed by the watchdog; either process exited with an error; any step timed out; either script
did not finish; the recorder dropped a record; hosting fell back to local-only play. Invalid runs
are counted on the scorecard and left out of every number.

### Comparing a later version

`BoloBench compare` refuses unless both scorecards have the same scenario hash, tier, hardware
model and recording schema. A metric has **changed** only when the two 95% intervals do not
overlap and a rank-sum test on the runs gives p below 0.05.

## Freezing a baseline

1. Run `run-baseline.sh <phase> <name>` under the conditions above.
2. Reboot, and run it again under a second name. The two sessions' medians should agree within
   the same bounds.
3. Read the scorecards. Anything not repeatable needs more runs or a longer scenario, or is left
   as report-only.
4. Commit `Bench/data/<phase>/<name>/`, add a `FROZEN` file to it, and tag the commit `<phase>/<name>`.
5. Keep the raw logs from `Bench/runs/<phase>/<name>/`, compressed, to the tag's release.

`run-baseline.sh` refuses to run into a directory that holds a `FROZEN` file.

## What this baseline cannot tell you

- **Nothing about a real network.** Both instances are on one Mac. Delays across the link are a
  floor for a guest on another machine.
- **Timing-dependent faults are less likely to show.** A stale overwrite or a masked message
  needs messages to cross in flight, which loopback makes rare. A two-Mac session is still the
  only proof of what a player experiences.
- **Host and guest share eight cores.** Their costs interact. Numbers are comparable only with
  runs made the same way on the same hardware.
- **Some randomness cannot be seeded.** Spawn is fixed by the map's single start; tree growth and
  parachute direction are not. Their effect is part of each metric's spread.

## Where this differs from the plan

| Plan | What was built | Why |
|---|---|---|
| Scenarios as JSON files in the app bundle | Defined in Swift, in `BenchScenarioLibrary.swift` | Type-checked and testable; a JSON file can still be loaded by path |
| Extract BoloArena's guest loop for the sweep | A separate `BoloBenchSwarm` executable | Leaves a working tool untouched |
| All validation in the app's test target | Split between the app's tests and the package's | The analyzer cannot be linked into the app's test bundle without loading a second copy of BoloNet's types |
| Logs collected from the app's sandbox container | Logs written to a descriptor the launcher passes in | The container is not readable by the launching script |
| Observer effect checked on CPU and on signposts | CPU only | The signpost comparison under Instruments was not done |

## Found while building this

None of these is fixed on this branch. Each is a lead for the Analyze phase.

| Finding | Evidence |
|---|---|
| The guest's remembered fog tile is wrong for a few hundred tiles in every Hidden Mines run | Every Hidden Mines scenario in session 1 |
| A mine placed by the builder shows a wrong count on the guest for about 1.3 s | 10 runs of 10 in `s3-mine-laying` |
| A mine near spawn is sometimes never revealed to the guest as mined | `HostGuestFogRevealTests` fails about 1 run in 12 on the untouched tag |
| A pill shell fired along an exact diagonal hits the pill itself, and the host changes its armour without telling guests | Seen in the validation harness; needs an exact diagonal |
| The host's dropped-datagram log reads byte 1 as the player slot; the slot is byte 0 | `HostDgramListener.swift`, the `.dropped` case |
| `usaMapThumbnailIs256AndNotFlat` reads `docs/U.S.A.map`, which is not in the repository | Fails on the untouched tag |
| Both `PillDesyncReproTests` fail whenever the whole app suite is run | 3 full runs of 3, on the tag and on this branch |

## Decisions on record

| Decision | By | Date |
|---|---|---|
| The `Float` rule in `AGENTS.md` covers the simulation. The benchmark's scenario steering uses `Double` and stays as designed | Jerod | 2026-09-28 |
| Both sessions are frozen together as the v1.6.9 baseline, and the Measure phase is closed. See `README.md` beside this file | Jerod | 2026-09-29 |

## Reproducibility between sessions

Two sessions of v1.6.9, a day apart, agreed on correctness, traffic and errors, and disagreed on
durations by about 9% to 25%. A scorecard's interval describes one session only. See
`Bench/data/measure/v1.6.9-baseline-session2/SUMMARY.md` before comparing durations across sessions.
