# v1.6.9 baseline, session 2, and how it compares with session 1

**Status: not frozen.** Both sessions are complete. The two do not agree within the bounds the
procedure set for timing metrics, so what to freeze is a decision, described at the end.

| | Session 1 | Session 2 |
|---|---|---|
| When (UTC) | 2026-09-28, 19:28 to 21:53 | 2026-09-29, 13:17 to 15:20 |
| Time since boot at start | About 18 hours | About 11 hours |
| Commit | `cb0629d` (s5: `3d20021`) | `2d6c4fd` |
| App sources | | Identical to `3d20021` |
| Launch | Saved window state honoured | Saved window state ignored |
| Valid runs | 108 of 110 | 110 of 110 |
| Machine, system, power | Same: MacBook Pro M1, macOS 27.0 (`26A428`), AC power |

The manifest says `dirty: true`; the only uncommitted content was the results being written.

## Within session 2

| Check | Result |
|---|---|
| Records dropped | 0 in every run |
| Recorder cost | 9.3 ns per record |
| Observer effect on CPU, s7 | Host +1.8%, guest -0.1% (limit 3%) |
| Observer effect on CPU, s8-soak-hidden | Host +0.2%, guest -0.6% (limit 3%) |

## Between the sessions

`BoloBench compare` was run on every scorecard pair: 2,746 metrics compared, 575 reported as
changed (20.9%). Nothing in the game changed between the sessions, so every one of these is
variation in the measurement, not in what was measured.

By kind of metric, over the seven scripted scenarios:

| Kind | Compared | Changed | Share |
|---|---|---|---|
| Errors and loss | 140 | 0 | 0% |
| Correctness | 468 | 21 | 4% |
| Traffic counts | 334 | 20 | 6% |
| Tick pacing | 108 | 15 | 14% |
| Link delays | 172 | 40 | 23% |
| Tick and draw durations | 513 | 209 | 41% |
| CPU and memory | 60 | 34 | 57% |

### What reproduced

- **What the game did.** Bytes and messages sent, loss, rejects and invariant violations.
- **Whether host and guest agreed.** The stale fog memory appears in every Hidden Mines scenario
  in both sessions. The 1.3 s wrong mine count after a builder places a mine appears in 10 runs
  of 10 in both.
- **Tick pacing.** The 95th percentile tick interval agrees within 1%.

### What did not

**Durations were about 9% to 25% longer in session 2, across the board.**

| Metric, median | Session 1 | Session 2 | Change |
|---|---|---|---|
| Host tick, s1 | 0.315 ms | 0.352 ms | +11.5% |
| Guest tick, s1 | 0.080 ms | 0.094 ms | +17.5% |
| Host simulation (`runTick`), s1 | 0.041 ms | 0.047 ms | +12.9% |
| Host terrain comparison, s1 | 0.093 ms | 0.106 ms | +14.3% |
| Host tick, s5 | 0.310 ms | 0.358 ms | +15.6% |
| Guest tick, s5 | 0.078 ms | 0.097 ms | +25.1% |
| Guest CPU, s1 | 28.1% | 30.7% | +9.2% |
| Guest update acknowledged by host, s1 | 79.2 ms | 64.3 ms | -18.8% |

The shift is the same size in s5, whose app sources were identical in both sessions, so the code
is not the cause. The cause is not known. The sessions differed in time of day, time since boot,
and whether saved window state was honoured at launch; this data cannot tell those apart.

## What this means

1. **Within a session the instrument is tight; between sessions it is not.** A scorecard's
   interval describes one session. It understates how much a timing metric moves from one day to
   the next.
2. **A later version's durations must differ by more than about 25% to be attributable to the
   code**, unless baseline and candidate are measured in the same session.
3. **Correctness, traffic and error metrics can be compared across sessions as they stand.**

## Options for freezing

| Option | What it gives |
|---|---|
| Freeze both sessions together as the baseline | Twenty runs per scenario whose spread includes the between-session variation. Comparisons become honest and less sensitive |
| Freeze one session, and always re-measure v1.6.9 alongside any candidate | The tightest comparison. Every later comparison costs two sessions instead of one |
| Run more sessions first | An estimate of between-session variation from more than two points |
