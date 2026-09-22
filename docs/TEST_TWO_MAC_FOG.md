# Two-Mac test: host-simulated guest tanks and hidden mines (v1.5.1)

Manual session for real hardware. Run it once, fill in the results table at the bottom, then update
`docs/STATUS.md`. Earlier runs (2026-09-20/21) found the issues these steps re-check.

**Roles.** Mac A = host (Jerod's MacBook). Mac B = guest (a Parallels VM, macOS 26, is fine).
If Mac A cannot bind a listener (Step 1), swap roles and note it.

**Designs under test.**
- Fog is host-authoritative (`docs/CONSTRAINTS.md`, "Fog-of-war"): the host tracks one `FogState` per
  player slot and redacts terrain data on the wire. Deliberate deviation from the C oracle, so there is
  no C behaviour to compare against.
- The host simulates guest tanks ([#59](https://github.com/CosmicCEO/BoloKit/issues/59) ruling,
  [#62](https://github.com/CosmicCEO/BoloKit/issues/62); `docs/CONSTRAINTS.md`, "Host-simulated guest tanks"):
  firing, range, mines, drowning, damage, death and respawn all run on the host. The guest keeps its own
  movement and gets armour, shells, death and its own shells back from the host.

## Facts the steps rely on

| Item | Value |
|------|-------|
| Hidden Mines toggle | Host tab, Game Settings. Off by default. |
| Port | 50000 (TCP and UDP). Leave Announce on Tracker and UPnP **off** for a LAN test. |
| Map | Bundled training map. One start point, so **both tanks spawn on the same tile** (102,121) and overlap until one moves. That is expected, not a bug ([#83](https://github.com/CosmicCEO/BoloKit/issues/83)). No pre-placed mines. |
| Keys | W accelerate, A/D turn, Space shoot, **Q/E range**, **Shift lay mine**, X centre on tank, arrow keys scroll. Builder: keys 1-5 (5 = mine), then click a tile. Toolbar (host and guest): Status, Alliances, Messages, Zoom In/Out, Quit to Menu. |
| Player names | The host name is the stored player name (default "Newbie"), shown to the guest in the roster and as a label ([#85](https://github.com/CosmicCEO/BoloKit/issues/85)). |
| Fog look (host) | Never-seen tile = solid black. Hidden mine = plain terrain. Remote tanks/shells fade near the fog edge. Your own tank is always opaque. |
| Fog look (guest) | The guest draws the terrain it was sent, as-is ([#75](https://github.com/CosmicCEO/BoloKit/issues/75)). Unseen tiles look like plain sea, **not black. Do not expect black.** By ruling ([#86](https://github.com/CosmicCEO/BoloKit/issues/86), [#90](https://github.com/CosmicCEO/BoloKit/issues/90)) the guest also sees pills, bases and the host tank outside its vision. |
| Vision | 29x29 tiles around a tank. A hidden mine within 2.0 tiles of your tank is revealed and **stays** revealed. |
| Own mines | A mine you laid is hidden from **you** too until you come back within 2.0 tiles (Hidden Mines on). |
| Build id | The About box cannot confirm the build. Use the binary hash (Step 0). |

## 0. Setup (both Macs)

1. Both Macs must run the **same build**. Copy one `.app` to the other (do not build twice). Check it on each Mac and write it down:
   `shasum "<path to app>/Contents/MacOS/Bolo 2026" | cut -c1-16` (the two prefixes must match).
   - The app is not notarized: right-click, Open. If it still refuses, `xattr -cr <app>`.
   - Mac B must be registered in the Apple Development provisioning profile.
   - Quit any older Bolo copies first so the right one is running.
2. Put both Macs on the same LAN and subnet.
3. Mac A: `ipconfig getifaddr en0` (use the interface you are actually on). Write the IP down.
4. On first join, Mac B shows a **Local Network** prompt. Allow it (System Settings, Privacy & Security, Local Network). If Mac A's firewall prompts for incoming connections, allow it. A failed first join that works on retry has been seen ([#93](https://github.com/CosmicCEO/BoloKit/issues/93)): note whether a prompt appeared.

## 1. Preflight: can the host bind? (gate)

Mac A: New Game, Host tab. Hidden Mines **off**, tracker and UPnP **off**, port 50000, Start Hosting.

| Check | Pass |
|-------|------|
| Game screen | **No** orange banner "Running local-only -- hosting is unavailable on this system". |
| Mac A: `lsof -nP -iTCP:50000 -sTCP:LISTEN` | Shows the app listening. |
| Mac B: `nc -vz <MacA-IP> 50000` | Succeeds. |
| Mac B: `dns-sd -B _bolo2026._tcp` | Lists the game (Bonjour is optional; manual IP is enough). |

**Fail** (banner, or `nc` refused) = the listener could not bind. The failure is silent: the app quietly
falls back to a solo local game and logs nothing. Confirm both Macs run a build that includes the
listener fix (PR #58). If a fixed build still fails, quit, swap roles and repeat. If neither binds, stop and record it.

## 2. Control run: Hidden Mines OFF

1. Host keeps Hidden Mines off and starts hosting (Step 1 state is fine).
2. Guest: New Game, Join tab. Enter host IP, port 50000, a player name. Join. Progress runs Connecting, Sending join request, Receiving game info, Receiving map, Joined.
3. Both screens show the full map and both toolbars. The guest roster shows the host by name.
4. Host presses Shift, and also sends the builder to plant a mine: both mines draw on **both** screens immediately and stay visible ([#76](https://github.com/CosmicCEO/BoloKit/issues/76), [#84](https://github.com/CosmicCEO/BoloKit/issues/84)).
5. Quit both to menu.

Pass = join works and nothing is hidden. Errors you might see: "Connection Reset by Peer.", "The attempt to connect was forcefully rejected." (refused), "Connection establishment timed out...", "Password rejected.", "Server version doesn't match." (build mismatch: recheck Step 0).

## 3. Guest combat (host-simulated tanks), Hidden Mines OFF

Host hosts, guest joins, both drive apart so the tanks no longer overlap. Watch the guest HUD (shells, mines, armour) and both event logs.

| # | Action | Expected |
|---|--------|----------|
| 1 | Guest fires (Space) several times. | Guest shells counter drops. The guest sees its **own** shells fly and land. The host sees them too. |
| 2 | Guest presses Q and E. | The guest crosshair range changes; shells land nearer or farther. |
| 3 | Guest drives into deep water without a boat. | It drowns (explosion, dead) and respawns. Leaving water on a boat does not leave a stray barge behind. |
| 4 | Guest lays a mine (Shift), moves off, host drives onto it. Then host lays one and the guest drives onto it. | Each mine detonates. Damage shows on **both** screens and in the HUD armour of the tank that hit it. The tile becomes a crater on both. |
| 5 | While driving and leaving a laid mine tile, watch the guest tank ([#91](https://github.com/CosmicCEO/BoloKit/issues/91)). | Note any push-back or resistance leaving a tile (like leaving a boat onto shore). Expected: none. |
| 6 | Host shoots the guest until it is hit. | Guest armour drops in its HUD and the tank is nudged back a little (kick). |
| 7 | Guest is destroyed (shells or mines). | Guest sees its **own** explosion, then respawns at the start tile. HUD armour and shells refill to full and track the host's values. The host sees the guest respawn at the new spot (no ghost at the death spot). |
| 8 | Both request an alliance with each other (Alliances). Then the guest, then the host, leaves it. | Both screens show Allied when formed and Hostile after leaving ([#92](https://github.com/CosmicCEO/BoloKit/issues/92)). Event-log messages appear on **both** Macs. |
| 9 | Both send a message (Messages). | Each arrives on the other Mac. |
| 10 | Check the names. | Guest sees the host name (roster and label near the host tank); host sees the guest name. |

## 4. Fog run: Hidden Mines ON

Host: turn **Hidden Mines on**, Start Hosting again. Guest: rejoin. Take a screenshot of both screens at each numbered check.

| # | Action | Expected |
|---|--------|----------|
| 1 | Guest joins. Start a timer at "Joined". | Note the **seconds until terrain draws** on the guest ([#89](https://github.com/CosmicCEO/BoloKit/issues/89), was 3-5 s). Join succeeds and both tanks move. |
| 2 | Host looks at the whole map. | Solid black outside roughly a 29x29 area around the host tank. Nothing revealed elsewhere. |
| 3 | Guest looks at its screen. | Terrain around the guest tank, sea elsewhere. **Not black.** Pills, bases and the host tank may show anywhere (accepted). |
| 4 | Host presses Shift, drives about 10 tiles away, then returns to within 2 tiles of the spot. | Mine is not visible at range. It appears when the tank is within 2 tiles and **stays** after the tank leaves (sticky reveal). |
| 5 | Host lays a mine, both move away. Guest, without approaching it, drives onto that tile. | The mine detonates (explosion, guest damage, event log). The guest never displays that mine beforehand. |
| 6 | Guest explores into unseen terrain. | New terrain draws promptly. Note any visible lag ([#89](https://github.com/CosmicCEO/BoloKit/issues/89)). |
| 7 | Watch a tree grow while both see it, then drive one Mac far away and back. | Growth matches on both screens where both can see. Distant trees update only when they come back into view. |
| 8 | Both request an alliance, then break it. | On forming: host fog opens around the guest's position within about 1 tick. On breaking: that extra vision recedes back to black. |
| 9 | Allied again, guest quits to menu; host looks where the guest was. Guest rejoins. | Vision from the guest recedes after it leaves. On rejoin the guest starts from fresh fog and inherits none of its previous reveals. |
| 10 | Guest changes terrain far outside host vision (chop or plant trees, build). Host later drives there. | Host does not see the change until it arrives, then shows current terrain. Best effort: mark N/A if not observable. |
| 11 | Both quit to menu. | No crash, no stuck connection, both return to the menu cleanly. |

Reading the results:
- The known deferred gap (pill and base capture, build and deploy are not vision sources) is not part of this run.
- Open follow-ups this run may touch: [#81](https://github.com/CosmicCEO/BoloKit/issues/81) (remote-laid mine masks), [#87](https://github.com/CosmicCEO/BoloKit/issues/87) (blue square artifact: note whenever you see one and what the builder was doing).

## 5. Diagnostics if something fails

- Screenshots of both screens, with wall-clock time and what you had just done.
- `log stream --level debug --signpost --predicate 'subsystem == "com.cosmicceo.Bolo-2026"'` on each Mac. Expect very little: the only text logs are tracker and UPnP lines. Nothing logs listener bind, joins, fog reveals or mines.
- Host: `lsof -nP -iTCP:50000` to see whether the guest connection is up.
- No debug overlay exists.

## 6. Results (fill in)

Date: ____  Build hash (Mac A / Mac B): ____ / ____  Host was: Mac ___

| Step / check | Pass / Fail / N/A | Notes, screenshots |
|--------------|-------------------|--------------------|
| 1 Preflight bind | | |
| 2 Control run | | |
| 3.1 Guest fires, own shells | | |
| 3.2 Q/E range | | |
| 3.3 Drowning, no stray barge | | |
| 3.4 Mines detonate, damage on both | | |
| 3.5 Push-back watch (#91) | | |
| 3.6 Host shells damage guest | | |
| 3.7 Guest death, own explosion, respawn, HUD | | |
| 3.8 Alliance formed and left, both screens | | |
| 3.9 Messages | | |
| 3.10 Names | | |
| 4.1 Terrain draw time (seconds) | | |
| 4.2 | | |
| 4.3 (guest view) | | |
| 4.4 | | |
| 4.5 | | |
| 4.6 | | |
| 4.7 | | |
| 4.8 | | |
| 4.9 | | |
| 4.10 | | |
| 4.11 | | |

After the run: update the "Not verified" lines in `docs/STATUS.md` with the outcome, and file a GitHub
issue for each Fail (new patch or release milestone, per `docs/STATUS.md` "How we track work").
