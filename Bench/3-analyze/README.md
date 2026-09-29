# Analyze phase

**Status: not started.** This is what Measure handed over. Nothing here is a conclusion yet.

The benchmark to analyze against is `../data/measure/v1.6.9-baseline/`. Its headline numbers are
in `../2-measure/README.md`.

## Specifications to build

| Item | From |
|---|---|
| Control limits per metric | The pooled run values in each `scorecard.json` |
| Targets for improvement | The findings and the hypotheses below |
| Which metrics are critical to quality | The three families, weighted equally so far |

## Measurement-system questions

| Question | Why it matters |
|---|---|
| What causes the 9% to 25% shift in durations between sessions? | It sets the smallest improvement that can be detected |
| Does honouring saved window state change the timing? | It is the one known procedural difference between the sessions |
| Should the soak and the sweep be lengthened? | They have the lowest repeatability |

## Findings about v1.6.9

| Finding | Evidence |
|---|---|
| The guest's remembered fog tile is wrong for about 300 tiles in every Hidden Mines run | All 7 Hidden Mines scenarios, both sessions |
| A mine placed by the builder shows a wrong count on the guest for about 1.3 s | 20 runs of 20 |
| Resources diverge for 250 ms to 2 s under random play | 3 of 19 and 5 of 20 soak runs |
| Terrain diverges under random play with Hidden Mines on, once to the end of the run | 3 of 19 runs; 1 terminal |
| Most slow host ticks are time waiting on the main-thread render hop | Sweep: render hop 95th percentile is 13.5 to 21.8 ms of a 15.0 to 28.9 ms tick |
| Position updates grow with the square of the player count | 1.2 kB/s at 2 players, 222 kB/s at 16 |
| The host's tank moves on the guest's screen every 141 to 400 ms | Remote smoothing never engages on the guest |
| A mine near spawn is sometimes never revealed to the guest | Existing test fails about 1 run in 12 on the untouched tag |
| A pill shell fired along an exact diagonal damages the pill itself, unreported | Seen in the validation harness |
| The dropped-datagram log reads the wrong byte as the player slot | `HostDgramListener.swift` |

## Hypotheses the benchmark can now test

| Hypothesis | Metrics |
|---|---|
| Take main-thread rendering out of the host tick loop | `host.tick_ms.renderHop`, `host.tick_interval_ms` |
| Relay position updates less wastefully as players are added | `host.tx.udp.bytes_per_s`, `host.apply_us.udp` |
| Reduce fog array copies | `host.tick_ms.fog`, sweep |
| Batch per-recipient sends | `host.tick_ms.sendFlush`, `send_completion_us` |
| Move `SRTankShots` off the reliable channel, or send deltas | `host.tx.tcp.op36` |
| Batch `SRRevealTerrain` | `host.tx.tcp.op34`, s1 and s6 |
| Let the guest's remote smoothing engage | `guest.remote_move_interval_ms` |
| Add a periodic state checksum or resync | `correctness.*.persistent`, `correctness.*.terminal` |
| Move the join handshake off the host consumer | `host.join_stall_ms` |
| Replace main-queue timers with a drift-corrected clock | `tick_interval_ms`, `tick_queue_delay_ms` |
| Replace the per-tick terrain comparison with change tracking | `host.tick_ms.terrainDiff` |
