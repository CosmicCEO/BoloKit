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

Fail = the listener could not bind and the app fell back to a solo local game. Swap roles and repeat, and record
whether the other Mac can join (a VM host may refuse a real Mac; #93). If neither binds, stop and record it.

## 2. Control run: Hidden Mines OFF

1. Host keeps Hidden Mines off and starts hosting.
2. Guest: New Game, Join tab. Host IP, port 50000, a player name. Join. Progress runs Connecting, Sending join request,
   Receiving game info, Receiving map, Joined.
3. Both screens show the full map, and each shows the other player's tank and correct name.
4. **Guest fires** (Space): shells fly, the ammo count on the guest HUD drops. **Guest lays a mine** (Shift): the mine
   shows and the mine count drops. Host presses Shift: the mine glyph draws immediately.
5. Quit both to menu.

Pass = join works, nothing is hidden, and the guest can fire and lay mines. Errors you might see: "Connection Reset by
Peer.", "The attempt to connect was forcefully rejected." (refused), "Connection establishment timed out...",
"Password rejected.", "Server version doesn't match." (build mismatch: recheck Step 0).

## 3. Fog run: Hidden Mines ON

Host: turn **Hidden Mines on**, Start Hosting again. Guest: rejoin. Screenshot both screens at each check.

| # | Action | Expected |
|---|--------|----------|
| 1 | Both join. Drive them at least 20 tiles apart (host north-west, guest east). | Join succeeds. Both tanks move on both screens. Record whether the first W press from rest moves each tank at once (#105 is open and not reproduced: note if Mac A was parked on the spawn tile and whether Mac B started from rest). |
| 2 | Host looks at the whole map. | Plain sea outside roughly a 29x29 area around the host tank. Nothing revealed elsewhere. Same blue as the guest's off-map area. |
| 3 | Guest looks at its screen. | Terrain the host has revealed to it, blue elsewhere. **The host tank and other pills/bases are visible outside the guest's vision: accepted (#86/#90).** Record anything else that differs. |
| 4 | Host presses Shift, then drives about 10 tiles away. Look at both screens. | The host still sees its own mine (revealed when laid, sticky). The guest, far away, does not see it. |
| 5 | Host lays a mine, both move away. Guest drives onto that tile. | The guest does not see the mine until its tank is within 2 tiles. It then detonates (explosion, guest damage on the guest HUD, event log). Record whether it detonated. |
| 6 | Guest lays a mine (Shift) and drives away. | The guest's mine count drops by one. The host sees that mine only once its own tank is within 2 tiles, and no "mine laid" message or glyph gives it away at range (#106). |
| 7 | Guest fires at the host tank, then the host fires at the guest. | Both shots fire and hit. Damage and armour update on the right HUD. Ammo drops on the shooter's HUD. |
| 8 | Host tank is destroyed and respawns while the guest watches. | The guest draws the host tank at its new spot as soon as it respawns, not at the old death spot (#61). |
| 9 | Host watches the guest tank approach the edge of host vision. | Guest tank fades in with distance on the host. Its name label appears only when close. |
| 10 | Both request an alliance with each other (Alliances button). Then break it. | Both screens agree on allied/enemy (#92); either side can leave. On forming, host fog opens around the guest within about 1 tick. On breaking, that extra vision recedes to sea. |
| 11 | Allied again, guest quits to menu. Host looks where the guest was. Guest rejoins. | Vision from the guest recedes after it leaves. On rejoin the guest starts from fresh fog and inherits none of its previous reveals. The rejoined guest's screen updates, and its tank responds to controls well past 2 tiles from spawn (#113). Try one rejoin with a new name and one with the same name. |
| 12 | Guest changes terrain far outside host vision (trees, build). Host later drives there. | Host does not see the change until it arrives, then shows current terrain. Mark N/A if not observable. |
| 13 | Host quits to menu while the guest is in the game. | Guest stays in the game view. Open Messages on the guest: a "disconnected" line appears (#107). |
| 14 | Both quit to menu. | No crash, no stuck connection, both return to the menu cleanly. |

Reading the results:
- Check 3 showing terrain is the expected v1.5.1 behaviour (the v1.5.0 script predicted all black; #75 fixed that).
- Mines: the rule is "revealed to a player within 2.0 tiles of their own tank, and sticky". A mine you lay is visible to you at once; the other player must be within 2.0 tiles to see it. To test hiding, look from the OTHER player's screen.
- The known deferred gap (pill and base capture, build and deploy are not vision sources) is not part of this run.
- A guest that sees the host tank far away is the accepted leak, not a Fail. Say so in the notes if it bothers you;
  reopening it is a ruling change, not a bug.

## 4. Diagnostics if something fails

- Screenshots of both screens, with wall-clock time and what you had just done.
- `log stream --level debug --signpost --predicate 'subsystem == "com.cosmicceo.Bolo-2026"'` on each Mac. Expect very little:
  the only text logs are tracker and UPnP lines. Nothing logs listener bind, joins, fog reveals or mines.
- Host: `lsof -nP -iTCP:50000` to see whether the guest connection is up.
- No debug overlay exists.

## 5. Results (fill in)

Date: ____  Build SHA (Mac A / Mac B): ____ / ____  Host was: Mac ___  Map: ____

| Step / check | Pass / Fail / N/A | Notes, screenshots |
|--------------|-------------------|--------------------|
| 1 Preflight bind | | |
| 2 Control run | | |
| 3.1 Join, first move | | |
| 3.2 Host fog look | | |
| 3.3 Guest view | | |
| 3.4 Sticky mine reveal | | |
| 3.5 Guest hits host mine | | |
| 3.6 Guest mine, no announce | | |
| 3.7 Shots both ways | | |
| 3.8 Host respawn seen by guest | | |
| 3.9 Guest fades at host edge | | |
| 3.10 Alliance both sides | | |
| 3.11 Guest leave and rejoin | | |
| 3.12 Far terrain change | | |
| 3.13 Host quit message | | |
| 3.14 Clean quit | | |

After the run: put the outcome in `docs/STATUS.md`, and file a GitHub issue for each Fail (milestone "v1.5.1 - Live
play fixes", per `docs/STATUS.md` "How we track work").
