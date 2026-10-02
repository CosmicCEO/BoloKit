# Analyze register

**Status: 2026-10-02, the one live register. Every closing condition except Jerod's decisions is met; see the last table.** Matches `SPECS.md`. `KT.md` keeps the
2026-09-29 scores as history; `KT-audit-findings.md` is the audit of them; `PROPOSALS.md` and
`OBSERVED.md` hold the option detail. Do not rank from those files.

Musts: M1 the benchmark can prove it; M2 no wire change in 1.*; M3 `AGENTS.md`.
Y: player experience. Weights: responsiveness 45, tick-budget cost 30, visible correctness 25.

## Prerequisites

| Item | Status 2026-09-30 | Evidence |
|---|---|---|
| P0a fog memory compared only in fog; re-read of all 220 frozen runs | **Done.** `data/analyze/p0a-fog-join/` | Scripted fog faults fall to 0; the Hidden Mines soak keeps median 29 tiles at end of run in 13 of 19 runs |
| P0b digest `mines + builderMines` | **Done.** `data/analyze/v1.6.9-analyze-session1/` (s1 to s5) | s3 mine fault 20 of 20 runs to 0 of 10. The soak baseline waits for a clean rerun |
| Render closure split (`hopRender`, `hopHud`, `hopLiveState`) | **Done.** Same session | The three parts total 0.15 to 0.19 ms and equal the hop work in s1 to s5. In the soak the work is 9 to 13 ms, so it is in the sound hop, now timed as `hopSound` for the next session |
| Session conditions | **Learned the hard way.** See the manifest | Screensaver off or keep-awake loop (now in `run-baseline.sh`), still wallpaper, and `host.frames_per_s` about 50 in the warm-up. 60 runs were discarded for a covered or animated desktop |
| P1 drawn-position probe plus one soak | **Done.** `data/analyze/p1-drawn-step/` | Drawn step median 100 ms, 95th percentile 132 ms, 0.2 tiles a step. The whole-tile metric read 400 ms in the same run |
| Render hop split into wait and work | **Done, one run.** `host.tick_ms.renderHopWait`, `.renderHopWork` | Work 9.0 ms and wait 2.4 ms at the 95th percentile; work max 181 ms. The time is inside the host's render closure, not waiting for the main thread |
| 3B failing test | **Done.** `Tests/DifferentialTests/GuestReceivePathFaultTests.swift` | Demonstrated: with 5 mines and the builder carrying one, a status message leaves the guest at 5 plus 1 |
| 4B failing test | **Done.** Same file | Demonstrated on the drawing path: a reveal of a mined tile while it is in fog leaves the guest remembering, and drawing, plain grass |

The two tests record known issues on v1.6.9 and will fail the moment the fault is fixed.

## 1.* items

| Item | Gate | CTQ | Enters Improve when |
|---|---|---|---|
| 1A smoother clock owned by the view | Ready once the P1 baseline is on the scorecard | Responsiveness 45 | Analyze closed |
| 2D fix the sound player (new) | **Cause named and measured.** `SoundPlayer.play` on the main thread costs 19 to 26 ms at the 95th percentile and up to 139 ms on the ticks that play a sound (the median varies from 0 to 6 ms with how many sounds are already playing), because the sounds are `NSSound(contentsOf:byReference:)` and are read and decoded from disk at each play. Options: load the sounds into memory once; a preloaded `AVAudioPlayer` pool; play off the main thread. All pass the musts; no wire change, no simulation change | Tick budget 30, plus host frames | Analyze closed |
| 2B versus 2C, host render hop | **Superseded by 2D.** The hop's cost is the sound closure, not drawing and not waiting; moving the hop off the tick would hide the cost, 2D removes it. Revisit only if the hop is still over 5 ms after 2D. Original note: Reframed by the split. The hop is work, not waiting: 9.0 of 11.8 ms at the 95th percentile is spent inside the closure (`view.render`, the status display, `hostLiveState`), while the drawing itself is under 1 ms. Neither 2B nor 2C removes that work; both only move it off the tick and leave the host's own screen paying it. The render closure is cleared (under 0.5 ms); the sound hop, `SoundPlayer.shared.play` on the main thread, is the remaining suspect and is timed in the next session | Tick budget 30, plus host frames | The slow part is named; Jerod picks a fix; Analyze closed |
| 4B guest refreshes fog memory on reveal | Cause demonstrated; baseline measured | Visible correctness 25 | Analyze closed |
| 3B status message does not refund the builder's mine | Cause demonstrated; baseline pending P0b | Visible correctness 25 | P0b, then Analyze closed |
| Speed up the position send | Hold behind 2B or 2C | Tick budget | After the hop is off the send path |
| Relay positions less wastefully | Drop for 1.*; watch at 4 | Cost | 2.* or watch |
| Diagonal pill shell | Hold | Correctness | Reproduce in a test |
| Terrain change tracking, fog copies, drift-corrected clock, join off the consumer | Drop for 1.* | Not player experience | Never in 1.* |

## 2.* parked depth

| Item | Note |
|---|---|
| Periodic state checksum or resync | The authority-model fix for "host changed state without telling guests". Named depth, not dropped |
| Tank shots off the reliable channel; batched terrain reveals | Traffic; control-only at 2 to 4 |
| 3C guest reports the builder launch | Alternative to 3B once the wire may change |

## What closes Analyze

| Condition | State |
|---|---|
| Define amended | Done |
| Raw logs backed up | Jerod |
| P0a and one Analyze scorecard | Done |
| P1 probe and a measured 1A baseline | Done: 100 ms in all nine scenarios, repeatable, session 2 (110 runs) |
| Failing tests for 3B and 4B, or their removal | Done, both kept; both faults also seen in the session 2 soak |
| What owns the main thread | Answered: the sound closure, `hopSound`, 19 to 26 ms at the 95th percentile on sound ticks. Item 2D |
| Session conditions | Screensaver off, still wallpaper, keep-awake loop in the script; frame rate checked. Session 2 ran clean |
| One register matching one specs page | This file and `SPECS.md` |
