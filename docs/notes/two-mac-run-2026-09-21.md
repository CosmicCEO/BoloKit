# Two-Mac run, 2026-09-21 (build c8046e4)

Script: `docs/TEST_TWO_MAC_FOG.md` (refreshed for v1.5.1, PR #112). Build: `Bolo 2026 (v151-test2 c8046e4).app`
from the local integration branch (every open PR of the #62 stack, #61, #106 and the soak fix; not #111).
Host = Mac A, guest = Mac B (a VM). Source: handwritten marks on a printout plus screenshots.

| Check | Result | Notes |
|-------|--------|-------|
| 0 Setup | done | c8046e4 on both. |
| 1 Preflight | Pass (Mac A hosts) / issue | Swapped roles: Mac A could not join the VM host as a client (#93). |
| 2 Control | Pass | Both screens blue outside the map; guest fires and lays mines. |
| 3.1 Join, first move | Pass | W works. The guest's arrival pushed a host parked on the spawn tile off it (#105). |
| 3.2 Host fog look | Expected mismatch | Black around the visible area: #111 (blue sea) is not in this build. |
| 3.3 Guest view | Pass | Guest shows terrain; host tank visible at distance (accepted, #86/#90). |
| 3.4 Own mine, far guest | Pass | Always visible to the host (sticky reveal, C oracle); not visible to the guest. Script wording was wrong. |
| 3.5 Guest reaches host mine | Pass | Guest sees the mine within 2 tiles, as designed. Script wording was wrong. |
| 3.6 Guest mine | Pass | Host sees it only within 2 tiles; no announcement (#106). Script wording was wrong. |
| 3.7 Shots both ways | Fail (observation) | A shell is not always visible for its whole flight ("all on or all off"), #114. |
| 3.8 Host respawn seen by guest | Pass | #61 verified on hardware. |
| 3.9 Guest fades at host edge | Pass | Name label appears about 2 tiles after the tank (#79). |
| 3.10 Alliance | Pass (forming) | Both sides agree (#92). Breaking not observed. |
| 3.11 Guest leave and rejoin | Fail | Guest screen does not refresh; its tank stops responding about 2 tiles from spawn, for good. Only on a rejoin. A rejoin under a new name works (#113). |
| 3.12 Far terrain change | Observation | Host always visible to the client outside its view (accepted leak). |
| 3.13 Host quit | Pass | Guest stays in the game; "disconnected" line seen (#107). |
| 3.14 Clean quit | Pass | |

## Open after this run
- #113 rejoin defect (blocks "reliable two-player").
- #114 shell visibility.
- #93 join from Mac A to a VM host.
- Needs a ruling: #77 (matches the oracle; propose closing as by design).
- Needs a hardware re-check with a build that includes #111 (3.2).
