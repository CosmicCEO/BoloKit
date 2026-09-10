# Agent Notes — Shared Running Log

> **Purpose:** Durable scratchpad shared between Claude Xcode API (implementer) and Claude.ai (reviewer and planner).
> High-level decisions belong in `PLAN.md`.
> This file is for implementation-level continuity: what was tried, what broke, what was resolved, and flags between agents.
>
> **Convention:** Always append — never edit or rewrite earlier entries, EXCEPT during an explicit
> periodic archive/compression pass (a Wave 5.8-style docs pass), which is the sanctioned exception
> to this rule. Pull before reading.

---

## Format

Each entry uses this block:

```
### [AGENT] YYYY-MM-DD — short title

Body — a few lines. Be concrete. No filler.

> **→ Parity:** action item or handoff note (omit if not applicable)
> **→ Planner:** item for review or question (omit if not applicable)
> **→ Implementer:** instructions for the xcode agent, coding environment (omit if not applicable)
```

Types:
- **[PLANNER]** — wave assignments, sign-offs, architectural decisions
- **[IMPLEMENTER]** — coding, completion reports, build results, deviations from spec
- **[PARITY]** — audit findings, behavioral verification, sign-offs

---

## Index

| Archive | Content |
|---|---|
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, all of Wave 6, all of Wave 7 (the full v1 vertical slice, D58–D89), Milestone B's D90–D93 through B.0–B.7, D109 through Milestone C's full close (B.8, B.9/B.10 deferrals, C.0/C.3/C.5), the D123/D124 git-worktree-race ruling, **and now also D125 through D149**: the path-to-v1.0 plan and v1.0.0 ship (D124–D128), the D129 function-coverage audit, and the 1.1 backlog's first wave — host map-load wiring fix (D131/D133), the bundled default map and its Alabama-silhouette rebuild (D132/D134, D135/D136), real mouse-driven builder control (D137/D138) and its crash fix (D146/D147), B.10's builder-task/shell-impact join-path follow-on (D139/D142/D143), the `Bolo 2026Tests` app-target test harness (D144/D145), a batch of 7 playtest-found UX gaps (D148/D149, sound wiring/always-visible HUD/tank sprite/mine visibility), and a PARITY audit of the whole self-review backlog (D141, 4/4 PASS) — up to but not including D150, which opens the active log. Compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

**PARITY activation rule:** PARITY runs **post-commit only**. PARITY is activated exclusively by a `[TO: PARITY]` tag in a PLANNER sign-off after IMPLEMENTER commits. PARITY does NOT run during planning phases.

**Role split (2026-09-02 reorg):** IMPLEMENTER owns detailed code-level planning (trap lists, C-source pre-briefs, implementation-approach calls) for its own waves. PLANNER is limited to high-level project management (sequencing, GOs, the decisions/open-questions log, cross-wave policy) and does not pre-author trap lists.

**Commit discipline (all three roles):** an entry only exists once it is appended here AND
committed — never leave it sitting in a chat session as "done" or "ready." This has already
bitten the project twice: a Wave 6.0 pre-brief reported "ready" in conversation with nothing
committed, and a Wave 6.0 PARITY audit relayed by Jerod with nothing committed either. Whoever
writes an entry commits it themselves, in the same sitting — `git add docs/AGENT_NOTES.md` (plus
any other file touched) → `git commit`. This applies identically to IMPLEMENTER, PLANNER, and
PARITY; none of the three can push to `github.com/CosmicCEO/BoloKit` (Jerod pushes after
relaying), but all three can and must commit locally. If you're about to say something is done and
you haven't run `git commit` yet, it isn't done yet.

**Role bootstraps (read at session start, each is instructions-only — no wave status lives in
them):** `CLAUDE.md` (IMPLEMENTER), `docs/PARITY.md` (PARITY), `docs/PLANNER.md` (PLANNER). Wave
status and decisions live only in `docs/PLAN.md`; this file is the chronological log. Restructured
2026-09-02 from a single IMPLEMENTER-only `CLAUDE.md` into three role-specific files, specifically
to stop wave-status content from being duplicated (and going stale) across bootstrap files.

---



### [PARITY] 2026-09-10 — Fresh visual-parity sweep: rendering, HUD, animation (post-commit audit, no `[TO: PARITY]` tag — Jerod-initiated ad hoc sweep, logged as a deliberate override per this project's own override convention)

**Type:** post-commit audit (current shipped Swift rendering/HUD code vs. the C oracle), not a pre-brief assessment. **Standing limitation:** no Swift toolchain used this session — every finding below is a hand-trace (`Reference/c/` line-by-line against `Sources/`/`Bolo 2026/Bolo 2026/`), not a compiled/run comparison. `xcodebuild`/`swift test` verification of these findings is left to whoever picks them up.

**Scope:** `GameRenderView.swift` (terrain/sprite/label draw loop), `GameHUDViews.swift` (build-tool strip, resource gauges), `PlayerStatusView.swift`/`PlayerStatusGrid`, `AlliancePanelView.swift` — the full current rendering/HUD surface — against `Reference/c/Mac OS X/GSBoloView.m` and `GSXBoloController.m`. Re-derived every citation already embedded in the Swift files' own doc comments rather than trusting them; also checked for reference-side visual features with no Swift-side citation at all (the class of gap a citation-based re-check alone would miss).

**C.2/fog-of-war note (per the task framing):** confirmed `AlliancePanelView.swift` (commit `20be903`/`0b2492d`, D128) exists and is live — contra a stale `docs/PLAN.md` Milestone-C-row sentence ("C.1/C.2/C.4 not yet started") that D130 already superseded. The fog-of-war/vision-merge gap in the alliance system is D65-inherited, explicitly disclosed, and Jerod-accepted as a v1-shape gap, not a defect (`docs/PLAN.md` Milestone C row, D130) — **out of scope for this sweep's findings**, already logged and ruled on. C.1/C.2 commits were previously reviewed only "at the commit-log/AGENT_NOTES level" (D130) with no full independent line-by-line audit — this sweep supplies that for C.2's `AlliancePanelView.swift` (checked, no new defects: unilateral-request bitmask math, Friendly/Allied/Hostile-only classification, and the "every player has this right, not just host" scope all match `client.c:6314-6455`/`GSXBoloController.m`'s plain `IBAction` shape exactly).

**Confirmed correct (re-derived, not just re-read):**
- `headingColumn`/heading-column formula (`GameRenderView.swift:51-53`) exactly matches `GSBoloView.m:322,325,337,349`'s `(int)(dir/(kPif/8.0)+0.5)%16` at all 4 heading-dependent draw call sites.
- BUILD0/BUILD1 builder-frame alternation (`GameRenderView.swift:476`, `state.ticks/5 % 2`) is the correct mapping of `GSBoloView.m:301`'s `(seq/5)%2 ? BUILD0 : BUILD1` — confirmed the `ticks`-for-`seq` substitution preserves the same on/off phase, not just "some" alternation.
- Draw order (builders → other players → local player → shells → explosions → parachuting builders) at `GameRenderView.swift:417-467` matches `GSBoloView.m:286-410`'s order exactly, modulo the reference's trailing selector/crosshair/pause-label sprites, correctly disclosed as out of scope (Milestone C's concern).
- `scrollUp/Down/Left/Right`, `tankCenter`, `pillCenter` (`GameRenderView.swift:303-347`) correctly reproduce `GSXBoloController.m:1236-1306,1529-1647`'s geometry (64pt nudge, tank/pill-centering math) modulo the disclosed zoom-divisor drop (D120, no zoom system in v1) and disclosed cursor-warp/cycling omissions.

**New findings (not previously logged):**

1. **(Moderate) HUD is missing the Trees resource gauge entirely.** The reference's status-bar cluster is 4 gauges, not 3: `playerShellsStatusBar`/`playerMinesStatusBar`/`playerArmourStatusBar`/**`playerTreesStatusBar`** (`GSXBoloController.m:2554-2558`, `[playerTreesStatusBar setValue:((float)client.trees)/MAXTREES]`). `ResourceGaugesPanel` (`GameHUDViews.swift:75-106`, D148(B)) only implements Shells/Mines/Armour. `trees` is not decorative — it's a fully-modeled, gameplay-consumed resource (`Sources/BoloKit/BuilderTick.swift:465-547,771-776`, spent building roads/walls/boats/pills, capped at `maxTrees`, `Spawn.swift:57`) with zero UI surface anywhere in the app target (`grep` of `Bolo 2026/` for `.trees`/`Trees` gauge turns up nothing). A player has gameplay-relevant state they can never see on screen. D148(B)'s own pre-brief/completion report named only "shell/mine/armor bars" and didn't flag Trees as split out (contrast with event-log/win-loss, which *were* explicitly named and deferred) — this reads as an unflagged omission, not a disclosed scope cut.

2. **(Moderate) Base resource status bars have no Swift equivalent anywhere.** The reference's `refresh:` timer (`GSXBoloController.m:2662-2680`) finds the nearest allied base within 8 tiles of the local tank and displays its armour/shells/mines via `baseArmourStatusBar`/`baseShellsStatusBar`/`baseMinesStatusBar` (falling back to all-zero when none in range) — a whole HUD subsystem letting a player see a nearby friendly base's resupply state at a glance. No file under `Bolo 2026/` implements this; `Base` objects (`GameObjects.swift`) already carry `armour`/`shells`/`mines` fields (used by `BuilderTick.swift`'s refuel logic), so the underlying data exists, only the display doesn't. Not previously logged anywhere in `docs/PLAN.md`'s Milestone C scope notes (C.0's "status/HUD panel" framing named player-status and kick/ban only).

3. **(Moderate) No lag/staleness visual indicator on player names anywhere in the HUD.** `setPlayerStatus:` (`GSXBoloController.m:2196-2210`) color-codes each player's name background by connection staleness: green (`< TICKSPERSEC` since `lastupdate`), yellow (`1-3× TICKSPERSEC`), red-background/white-text (`>= 3× TICKSPERSEC` — effectively "presumed dropped"). `PlayerStatusGrid` (`PlayerStatusView.swift:96-116`) only ever renders a static friendly/allied/hostile tint dot + label, with no staleness dimension at all. The underlying data isn't even missing — `HostSession.allTicksSinceLastUpdate(currentTick:)` (`HostSession.swift:175-177`) already computes exactly this age, but only for LRU-eviction logic, never plumbed to any view. This is a real "feel" gap: the reference gives visible, at-a-glance feedback that a peer's connection is lagging or has dropped; the port gives none.

4. **(Low/cosmetic) Player-name label sits ~8px (half a tile) further from the tank sprite than the reference.** `GSBoloView.m:453-463`'s `drawLabel:at:withAttributes:` places the label's origin exactly at the sprite's top edge (`rect.origin.y = FWIDTH*16.0 - point.y*16.0 + 8.0`, which — worked through the same unflipped-coordinate math the sprite's own `drawSprite:at:fraction:` uses — is precisely the sprite's top pixel row, zero gap). `GameRenderView.swift:495-503`'s `drawLabel` computes `y = point.y*tile - tile - textSize.height`; since the sprite's own top edge (from `drawSprite`, `GameRenderView.swift:514-521`) is at `point.y*tile - 8`, this leaves a consistent 8px gap between the bottom of the label and the top of the sprite that the reference doesn't have. Cosmetic only, but a real, reproducible pixel-position divergence in a HUD element already otherwise confirmed faithful (Wave 7.2 D86-audited).

**Citation-drift note:** none found — every doc-comment citation checked in scope (headingColumn, BUILD0/1 alternation, draw order, scroll/center math) pointed at the line ranges it claimed and said what it claimed. The 4 findings above are all *reference-side visual features the Swift doc comments never cited at all* (categories 1-3) or a *derivable pixel-offset consequence* (4) — not citation errors.

**Verdict: real findings — 4 new (2 moderate-HUD-completeness, 1 moderate-feedback-affordance, 1 low-cosmetic), 0 confirming/reopening the disclosed C.2 fog-of-war gap** (which remains correctly out of scope, per D65/D130). No regressions in previously-PARITY-passed code (Wave 7.2's terrain/tank draw-order/no-y-flip work all reconfirmed clean).

> **→ Planner:** items 1-3 read as unflagged gaps in D148(B)/C.0's own stated scope (Trees gauge, base gauges, lag indicator) rather than disclosed cuts — worth a ruling on whether they're 1.1 backlog now or deliberately deferred (and if deferred, disclosed as such going forward, matching this project's own standing discipline for every other scope cut). Item 4 is small enough to fold into whichever pass next touches `GameRenderView.swift`'s label code, no dedicated wave needed.
> **→ Implementer:** none of these are coding GOs yet — PLANNER rules first, per the two-stage GO pattern.

[TO: PLANNER]
