# Two-Mac test: hidden-mines fog-of-war and host-simulated guest (v1.5.1)

Manual session on two physical Macs. Run it once, fill in the results table at the bottom, then update
`docs/STATUS.md`. It replaces the v1.5.0 script, which predicted an all-black guest map and predated the
host-simulated guest tank (#62), so most of its predictions no longer hold.

**Roles.** Mac A = host. Mac B = guest. Record the hardware of each (a VM counts, note it). If Mac A cannot bind a
listener (Step 1), swap roles and note it.

**Design under test.**
- Fog is host-authoritative (`docs/CONSTRAINTS.md`, "Fog-of-war"): the host tracks one `FogState` per player slot and
  redacts terrain on the wire. Deliberate deviation from the C oracle, so there is no C behaviour to compare against.
- The host simulates the guest's tank, shells and mines (`docs/CONSTRAINTS.md`, host-simulated guest tanks, #59/#62).
  The guest is a thin client for combat: it sends input, the host answers with `SRTankStatus`.
- **Accepted for v1.5.1 (#86/#90, closed not planned):** the guest is not fogged for tanks and pillboxes/bases. It
  will see the host tank, and other pills/bases, outside its own vision. This is expected, not a failure.

## Facts the steps rely on

| Item | Value |
|------|-------|
| Hidden Mines toggle | Host tab, Game Settings. Off by default. |
| Port | 50000 (TCP and UDP). Leave Announce on Tracker and UPnP **off** for a LAN test. |
| Map | Note which map you use. Note whether both tanks spawn on the same tile or on different start points. |
| Keys | W accelerate, A/D turn, Space shoot, **Shift lay mine**, X centre on tank, arrow keys scroll. Builder: keys 1-5 (5 = mine), then click a tile. |
| Fog look (host) | Never-seen tile = plain sea (same blue a guest shows off the map). Hidden mine = plain terrain. Remote tanks/shells fade near the fog edge. Your own tank is always opaque. |
| Fog look (guest) | Terrain the host has revealed to it, blue elsewhere. Tanks and pills/bases are drawn even outside vision (accepted, above). |
| Vision | 29x29 tiles around a tank. A hidden mine within 2.0 tiles of your tank is revealed and **stays** revealed. |
| Mines | A mine within 2.0 tiles of a player's own tank is revealed to that player at once and **stays** revealed. So a mine you lay is always visible to you, and another player sees it only once their tank has come within 2.0 tiles. |
| Build id | `MARKETING_VERSION` still says 1.2.3. Use the git SHA (or the Desktop app name). |

## 0. Setup (both Macs)

1. Run the same build on both and record its SHA. For v1.5.1 use the integration build until the stack is merged
   into `main`, then any `main` build at or after the merge.
   - Preferred: build on each Mac: `xcodebuild -project "Bolo 2026/Bolo 2026.xcodeproj" -scheme "Bolo 2026" -configuration Debug ENABLE_USER_SCRIPT_SANDBOXING=NO build`
   - Alternative: copy the built `.app` to Mac B. Mac B must be in the Apple Development provisioning profile. Not
     notarized: right-click, Open. If it still refuses, `xattr -cr <app>`.
2. Same LAN and subnet.
3. Mac A: `ipconfig getifaddr en0` (or the interface in use). Write the IP down.
4. First join: Mac B shows a **Local Network** prompt. Allow it (System Settings, Privacy & Security, Local Network).
   If Mac A's firewall prompts, allow it. If the first join fails and the second works, note it.

## 1. Preflight: can the host bind? (gate)

Mac A: New Game, Host tab. Hidden Mines **off**, tracker and UPnP **off**, port 50000, Start Hosting.

| Check | Pass |
|-------|------|
| Game screen | **No** orange banner "Running local-only -- hosting is unavailable on this system". |
| Mac A: `lsof -nP -iTCP:50000 -sTCP:LISTEN` | Shows the app listening. |
| Mac B: `nc -vz <MacA-IP> 50000` | Succeeds. |

**Fail** (banner, or `nc` refused) = the listener could not bind. The failure is silent: the app quietly
falls back to a solo local game and logs nothing. Confirm both Macs run a build that includes the
listener fix (PR #58). If a fixed build still fails, quit, swap roles and repeat. If neither binds, stop and record it.

## 2. Control run: Hidden Mines OFF

1. Host keeps Hidden Mines off and starts hosting (Step 1 state is fine).
2. Guest: New Game, Join tab. Enter host IP, port 50000, a player name. Join. Progress runs Connecting, Sending join request, Receiving game info, Receiving map, Joined.
3. Both screens show the full map and both toolbars. The guest roster shows the host by name.
4. Host presses Shift, and also sends the builder to plant a mine: both mines draw on **both** screens immediately and stay visible ([#76](https://github.com/CosmicCEO/BoloKit/issues/76), [#84](https://github.com/CosmicCEO/BoloKit/issues/84)).
5. Quit both to menu.

Pass = join works, nothing is hidden, and the guest can fire and lay mines. Errors you might see: "Connection Reset by
Peer.", "The attempt to connect was forcefully rejected." (refused), "Connection establishment timed out...",
"Password rejected.", "Server version doesn't match." (build mismatch: recheck Step 0).

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

Host: turn **Hidden Mines on**, Start Hosting again. Guest: rejoin. Screenshot both screens at each check.

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
- `log stream --level debug --signpost --predicate 'subsystem == "com.cosmicceo.Bolo-2026"'` on each Mac. Expect very little:
  the only text logs are tracker and UPnP lines. Nothing logs listener bind, joins, fog reveals or mines.
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
