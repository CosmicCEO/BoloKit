# Two-Mac test: hidden-mines fog-of-war (v1.5.0, #1)

Manual session that closes the one unchecked box from PR #56. Run it once, fill in the
results table at the bottom, then update `docs/STATUS.md`.

**Roles.** Mac A = host (Jerod's MacBook). Mac B = guest (Apple-silicon MacBook, macOS 26).
If Mac A cannot bind a listener (Step 1), swap roles and note it.

**Design under test.** Fog is host-authoritative (`docs/CONSTRAINTS.md`, "Fog-of-war"): the host
tracks one `FogState` per player slot and redacts terrain data on the wire. This is a
deliberate deviation from the C oracle's client-side filter, so there is no C behavior to compare against.

## Facts the steps rely on

| Item | Value |
|------|-------|
| Hidden Mines toggle | Host tab, Game Settings. Off by default. |
| Port | 50000 (TCP and UDP). Leave Announce on Tracker and UPnP **off** for a LAN test. |
| Map | Bundled training map. One start point, so **both players spawn on the same tile** (102,121). No pre-placed mines: every mine is laid by a player. |
| Keys | W accelerate, A/D turn, Space shoot, **Shift lay mine**, X centre on tank, arrow keys scroll. Builder: keys 1-5 (5 = mine), then click a tile. |
| Fog look (host) | Never-seen tile = solid black. Hidden mine = plain terrain. Remote tanks/shells fade near the fog edge. Your own tank is always opaque. |
| Vision | 29x29 tiles around a tank. A hidden mine within 2.0 tiles of your tank is revealed and **stays** revealed. |
| Own mines | A mine you laid is hidden from **you** too until you come back within 2.0 tiles. Not seeing your own mine at range is expected. |
| Build id | `MARKETING_VERSION` is still 1.2.3, so the About box cannot confirm the build. Use the git SHA. |

## 0. Setup (both Macs)

1. Build the same commit on both. Record it: `git rev-parse --short HEAD` (must be `daa49b7` or later on `main`).
   - Preferred: clone and build on Mac B (needs Xcode):
     `xcodebuild -project "Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" -configuration Debug build`
   - Alternative: copy Mac A's built `.app` to Mac B. Mac B must be registered in the Apple Development
     provisioning profile. The app is not notarized: right-click, Open. If it still refuses, `xattr -cr <app>`.
2. Put both Macs on the same LAN and subnet.
3. Mac A: `ipconfig getifaddr en0` (use the interface you are actually on). Write the IP down.
4. On first join, Mac B shows a **Local Network** prompt. Allow it (System Settings, Privacy & Security, Local Network). If Mac A's firewall prompts for incoming connections, allow it.

## 1. Preflight: can the host bind? (gate)

Mac A: New Game, Host tab. Hidden Mines **off**, tracker and UPnP **off**, port 50000, Start Hosting.

| Check | Pass |
|-------|------|
| Game screen | **No** orange banner "Running local-only -- hosting is unavailable on this system". |
| Mac A: `lsof -nP -iTCP:50000 -sTCP:LISTEN` | Shows the app listening. |
| Mac B: `nc -vz <MacA-IP> 50000` | Succeeds. |
| Mac B: `dns-sd -B _bolo2026._tcp` | Lists the game (Bonjour is optional; manual IP is enough). |

**Fail** (banner, or `nc` refused) = the listener could not bind. The failure is silent: the app quietly
falls back to a solo local game and logs nothing. Builds before the `fix-listener-einval` change always fail
here (a code bug, not macOS: the port was set twice), so confirm both Macs run a build that includes it. If a
fixed build still fails, quit, swap roles (Mac B hosts, Mac A joins) and repeat. If neither binds, stop and record it.

## 2. Control run: Hidden Mines OFF (default unchanged)

1. Host keeps Hidden Mines off and starts hosting (Step 1 state is fine).
2. Guest: New Game, Join tab. Enter host IP, port 50000, a player name. Join. Progress runs Connecting, Sending join request, Receiving game info, Receiving map, Joined.
3. Both screens show the full map. Host presses Shift: the mine glyph draws immediately and stays visible.
4. Quit both to menu.

Pass = join works and nothing is hidden. Errors you might see: "Connection Reset by Peer.", "The attempt to connect was forcefully rejected." (refused), "Connection establishment timed out...", "Password rejected.", "Server version doesn't match." (build mismatch: recheck Step 0).

## 3. Fog run: Hidden Mines ON

Host: turn **Hidden Mines on**, Start Hosting again. Guest: rejoin. Take a screenshot of both screens at each numbered check.

| # | Action | Expected |
|---|--------|----------|
| 1 | Both join and spawn at (102,121). Host drives north-west, guest east, at least 20 tiles apart. | Join succeeds. Both tanks move. |
| 2 | Host looks at the whole map. | Solid black outside roughly a 29x29 area around the host tank. Nothing revealed elsewhere. |
| 3 | Guest looks at its screen. **Record exactly what it shows.** | **Predicted: the guest map is all black.** The join path renders with no `FogState` (`GameSession.swift:235,540,707`) and `GameRenderView.render` fails closed to all-unknown (:353-365). If black, note it and use gameplay checks below instead of guest visuals. If it shows terrain, record how much. |
| 4 | Host presses Shift, drives about 10 tiles away, then returns to within 2 tiles of the spot. | Mine is not visible at range. It appears when the tank is within 2 tiles, and **stays** after the tank leaves (sticky reveal). |
| 5 | Host lays a mine, both move away. Guest, without ever approaching it, drives onto that tile. | The mine detonates (explosion, guest tank damage, event log). The guest never displays that mine beforehand. |
| 6 | Host watches the guest tank approach the edge of host vision. | Guest tank fades in with distance. Its name label appears only when close. |
| 7 | Both request an alliance with each other (Alliances button). Then break it. | On forming: host fog opens around the guest's position within about 1 tick. On breaking: that extra vision recedes back to black. |
| 8 | Allied again, guest quits to menu. Host looks at the area around where the guest was. Guest rejoins. | Vision from the guest recedes after it leaves. On rejoin the guest starts from fresh fog and inherits none of its previous reveals. |
| 9 | Guest changes terrain far outside host vision (chop or plant trees, build). Host later drives there. | Host does not see the change until it arrives, then shows current terrain. Best effort: mark N/A if not observable. |
| 10 | Both quit to menu. | No crash, no stuck connection, both return to the menu cleanly. |

Reading the results:
- Check 3 black is a **finding**, not a setup error. Redaction on the wire is implemented, but no client-side display of seen tiles is wired. Checks 4-5 on the guest then have to be judged by gameplay (does it explode, does the log say so), not by looking.
- The known deferred gap (pill and base capture, build and deploy are not vision sources) is not part of this run.

## 4. Diagnostics if something fails

- Screenshots of both screens, with wall-clock time and what you had just done.
- `log stream --level debug --signpost --predicate 'subsystem == "com.cosmicceo.Bolo-2026"'` on each Mac. Expect very little: the only text logs are tracker and UPnP lines. Nothing logs listener bind, joins, fog reveals or mines.
- Host: `lsof -nP -iTCP:50000` to see whether the guest connection is up.
- No debug overlay exists.

## 5. Results (fill in)

Date: ____  Build SHA (Mac A / Mac B): ____ / ____  Host was: Mac ___

| Step / check | Pass / Fail / N/A | Notes, screenshots |
|--------------|-------------------|--------------------|
| 1 Preflight bind | | |
| 2 Control run | | |
| 3.1 | | |
| 3.2 | | |
| 3.3 (guest view) | | |
| 3.4 | | |
| 3.5 | | |
| 3.6 | | |
| 3.7 | | |
| 3.8 | | |
| 3.9 | | |
| 3.10 | | |

After the run: replace the "Not verified: manual two-peer hidden-mines session" line in `docs/STATUS.md`
with the outcome, and file a GitHub issue for each Fail (new patch or release milestone, per
`docs/STATUS.md` "How we track work"). A confirmed black guest map (check 3.3) is its own issue.
