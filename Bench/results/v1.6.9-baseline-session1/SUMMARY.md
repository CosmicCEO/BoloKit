# v1.6.9 baseline, session 1

**Status: not frozen.** One session of the two the procedure asks for. Session 2 needs a reboot
first.

| | |
|---|---|
| When | 2026-09-28, 19:28 to 21:53 UTC, plus a rerun of one scenario afterwards |
| Machine | MacBook Pro 13-inch M1 (`MacBookPro17,1`), 8 cores (4 + 4), 16 GB |
| Displays | Built-in 2560 x 1600, external 5120 x 2880 |
| System | macOS 27.0 (`26A428`), Xcode 27.0 (`27A266a`) |
| Conditions | AC power, Low Power Mode off, display kept awake, Mac unattended |
| Build | Release, branch `bench/v1.6.9-baseline`, wire protocol and simulation identical to `v1.6.9` |
| Network | Loopback: both instances on this Mac |

Figures below are the median across valid runs. An asterisk marks a metric that was not
repeatable in this session; treat its value as indicative only.

## Runs

| Scenario | Valid | Invalid | Metrics judged | Repeatable |
|---|---|---|---|---|
| s1-join-and-spawn | 10 | 0 | 273 | 259 |
| s2-pill-pickup-and-capture | 10 | 0 | 324 | 299 |
| s3-mine-laying | 10 | 0 | 297 | 264 |
| s4-building | 10 | 0 | 303 | 276 |
| s5-death-and-respawn | 9 | 1 | 300 | 274 |
| s6-fog-crossing | 10 | 0 | 283 | 256 |
| s7-sustained-fire | 10 | 0 | 291 | 266 |
| s8-soak-open | 10 | 0 | 417 | 309 |
| s8-soak-hidden | 9 | 1 | 381 | 281 |
| Sweep, 2 / 4 / 8 / 16 players | 5 each | 0 | 101 to 109 | 60 to 73 |

Two things about these runs differ from the rest:

- **s5 was run again after the session, on a later commit.** Its first ten runs were all invalid
  because of a flaw in the scenario's script, since fixed (`3d20021`). Each run's `meta.json`
  records the commit and binary it came from. The other eight scenarios ran on `cb0629d`.
- **The manifest says `dirty: true`.** The only uncommitted content was the results directory the
  run itself was writing.

The invalid s8-soak-hidden run could not bind its port, still held by the run before it. The
invalid s5 run is one where the guest was knocked out of the host's range before it died.

## Is the instrument trustworthy?

| Check | Result |
|---|---|
| Analyzer against a direct comparison of final states | Agreed in 20 of 20 real runs |
| Planted defects detected | 6 of 6, with the right values |
| Bytes and messages sent against received | Equal on both channels |
| Records dropped | 0 in every run |
| Recorder cost | 9.3 ns per record; about 2 to 4 µs per tick |
| Observer effect on CPU, s7 | Host +0.4%, guest +1.0% (limit 3%) |
| Observer effect on CPU, s8-soak-hidden | Host -1.5%, guest -1.2% (limit 3%) |
| Wire protocol and simulation | Identical to `v1.6.9` |

The observer-effect check compared processor time only. The comparison of signpost durations
under Instruments that the plan also called for was not done.

## Correctness

Counts of divergence episodes, by how long they lasted.

| Scenario | In flight | Slow | Persistent | Terminal |
|---|---|---|---|---|
| s1-join-and-spawn | 1,469 | 0 | 0 | 302 |
| s2-pill-pickup-and-capture | 2,580 | 0 | 0 | 302 |
| s3-mine-laying | 2,683 | 14 | 1 | 346 |
| s4-building (Hidden Mines off) | 21 | 0 | 0 | 0 |
| s5-death-and-respawn | 4,568 | 20 | 322 | 3 |
| s6-fog-crossing | 5,150 | 0 | 280 | 42 |
| s7-sustained-fire | 2,394 | 0 | 0 | 308 |
| s8-soak-open (Hidden Mines off) | 420 | 0 | 0 | 0 |
| s8-soak-hidden | 17,840 | 23 | 412 | 6 |

**Pills, bases, own status, terrain, visibility and other players' status never diverged past
in-flight in any scripted scenario.** Almost everything that lasted is one thing, described next.

### What lasted

1. **The guest's remembered fog tile is wrong for a few hundred tiles, in every Hidden Mines
   run.** The guest remembers sea where the host remembers grass or river. The terrain itself
   agrees; only the last-seen tile differs. With the tank still, it lasts to the end of the run
   (about 302 tiles). Once the tank moves and tiles leave and re-enter vision, most are
   corrected. With Hidden Mines off there is no fog, and none of this appears.
2. **A mine placed by the builder shows a wrong mine count on the guest for about 1.3 s, in 10
   runs of 10.** The guest holds 38 while the host holds 39. It then converges.
3. **In the soak, resources or terrain diverged for between 250 ms and 2 s in a minority of
   runs:** resources in 2 of 9 and 2 of 10 runs, terrain in 2 of 9. These are intermittent and
   are to be read as rates.

### Candidate classes

The analyzer labelled most fog episodes `doubleDecision`, because both sides changed the element
within two ticks of each other. One soak run produced a `staleOverwrite` candidate. These labels
are leads, not findings.

## Responsiveness

| Metric | Value |
|---|---|
| Tick rate, host and guest | 50 per second; 95th percentile interval 20.8 to 21.0 ms |
| Host ticks over 25 ms apart | 0.1% to 0.8% scripted; 2.3% in the soak |
| Scripted key press to frame, guest | 16 to 20 ms |
| Guest update acknowledged by host | 49 to 89 ms |
| Host update acknowledged by guest | 21 to 55 ms |
| Reliable message, sent to applied, median | 0.3 to 32 ms |
| Reliable message, sent to applied, 95th percentile | About 41 ms with Hidden Mines on; 2 to 3 ms off |
| Host's tank moving on the guest's screen | Every 140 to 400 ms |
| Join handshake | 1.4 to 1.7 ms |
| Guest joined to alive | About 1,980 ms |
| UDP loss, either way | 0% |

## Cost

| Metric | Host | Guest |
|---|---|---|
| Tick, median | 0.31 to 0.39 ms | 0.07 to 0.09 ms |
| Tick, 95th percentile | 3 to 6 ms scripted; 11 to 13 ms soak * | 0.1 ms scripted; 0.3 to 0.4 ms soak |
| CPU, share of one core | 31% to 34% | 26% to 29% |
| Memory | 123 to 139 MB | 114 to 132 MB |
| Reliable traffic sent | 170 B/s idle to 6,300 B/s in the soak | |
| Position updates sent | 670 to 1,150 B/s | 1,085 to 1,260 B/s |

## Scaling sweep: host cost by player count

| Metric | 2 | 4 | 8 | 16 |
|---|---|---|---|---|
| Tick, median (ms) | 0.53 * | 0.98 * | 2.48 * | 3.63 |
| Tick, 95th percentile (ms) | 15.4 | 19.3 | 22.3 | 28.7 |
| Render hop, 95th percentile (ms) | 13.7 | 17.2 | 19.5 | 21.8 |
| Fog, median (ms) | 0.016 | 0.075 | 0.159 | 0.285 |
| Send flush, 95th percentile (ms) | 0.37 * | 1.87 | 2.16 | 3.59 |
| Terrain comparison, median (ms) | 0.109 | 0.093 | 0.073 | 0.060 |
| Simulation (`runTick`), median (ms) | 0.047 | 0.054 | 0.064 | 0.076 |
| Tick interval, 95th percentile (ms) | 22.2 | 23.5 | 25.3 | 31.6 |
| Ticks over 25 ms apart | 3.4% * | 4.2% * | 5.2% * | 11.0% * |
| Tick rate (per second) | 49.81 | 49.75 | 49.63 | 49.09 |
| CPU, share of one core | 41.9% | 42.4% | 43.0% * | 50.3% |
| Reliable traffic sent (B/s) | 7,470 | 18,039 | 41,494 | 88,698 |
| Position updates sent (B/s) | 1,208 | 9,536 | 50,238 | 222,781 |
| Handling one datagram, median (µs) | 25 | 145 | 270 * | 460 |

The guests in the sweep are synthetic and share the Mac with the host, so their own load is part
of what the host competes with.

## What was not repeatable

Most of these are 95th percentiles of quantities with long tails, or delays that depend on where
in the 100 ms update cycle an event falls. They stay on the scorecard and are never compared.

| Metric | Not repeatable in |
|---|---|
| Host tick, 95th percentile | 6 of 7 scripted scenarios |
| Host update send, median and 95th percentile | 6 of 7 |
| UDP send completion on the host | 7 of 7 |
| Position delay, guest to host, median | 6 of 7 |
| Position delay, host to guest, 95th percentile | 7 of 7 |
| Interval between the host tank's movements on the guest | 5 to 6 of 7 |

The two soak scenarios have about 100 unrepeatable metrics each. Random play for 60 s does not
settle to the same numbers in ten runs; the soak is useful for breadth, not for comparison.
