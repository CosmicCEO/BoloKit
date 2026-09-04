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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, and all of Wave 6 (6.0–6.3, the D39 fix, 6.6, 6.4a/6.4b/6.4c, 6.5a/6.5b, and the Wave 6 phase close-out) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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

## Active Log (post-Wave-6)

> **Archived 2026-09-04:** Wave 6.5 (tracker protocol + NAT-PMP, split into 6.5a/6.5b per
> D55) and the full Wave 6 networking phase close-out (6.0 through 6.6, nine real PARITY
> findings — D35/D37/D39/D45/D46/D48's correction/D50/D53/D57 — all fixed and re-confirmed)
> have been compressed into `docs/notes/archive.md`. Full uncompressed entries preserved in
> git history per D28. The active log below now begins at Wave 7's opening (Jerod ruling
> Q22/Q26 directly, D58/D59).

### [PLANNER] 2026-09-04 — Jerod rules Q22/Q26 directly (D58/D59); next-wave direction still open

**Type:** planning — direct product ruling from Jerod, relayed live
**Phase:** post-Wave-6, pre-next-wave
**Blocks:** nothing — these were explicitly non-code-blocking questions

Presented the three-way fork from the prior entry to Jerod. He chose to resolve Q22/Q26 first,
then ruled both directly (not a Planner recommendation adopted — his own call, same as this
project's convention for anything marked "Jerod's call"):

**D58 (Q22): support both hosting models — in-process ("Host a Game" panel) and a separate**
**headless Dedicated Host binary.** Matches `docs/notes/HOSTMODELS.md`'s research and
recommendation, and both reference implementations' own precedent (xbolo and WinBolo/LinBolo each
ship both forms). No architecture change needed — confirms scope for whenever the dedicated-host
binary gets its own wave, doesn't require one now.

**D59 (Q26): no self-hosted tracker daemon — rely on manual IP connection for now.** Wave 6.5a's
tracker-protocol client code is unaffected — it's complete, tested, and would work against any
third-party or community tracker daemon speaking the same wire protocol; this project just isn't
building the daemon itself. Wave 6.5b's NAT-PMP/UPnP port mapping (D54, already shipped) remains
useful for the direct-IP-connect path.

Neither ruling is code-blocking and neither requires touching already-shipped Wave 6 code — both
are scope confirmations for future waves, not reopenings of closed work.

**Next-wave direction is still open** — resolving Q22/Q26 was Jerod's chosen first step, not a
commitment to which of Phase 4/5, the UI phase, or something else comes next. Will ask directly
once he's ready to pick.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Q22/Q26 removed from open questions; D58/D59 added to the decisions log.

[TO: IMPLEMENTER] No action needed — D58/D59 are scope confirmations for future waves, nothing to
build yet.
[TO: PARITY] No action needed.

### [PLANNER] 2026-09-04 — Wave 7 (UI/app phase) opened, pre-brief GO'd

**Type:** planning — new-wave open + pre-brief GO
**Phase:** Wave 7 pre-brief
**Blocks:** Wave 7 coding, pending IMPLEMENTER's pre-brief and PLANNER's review of it (standard
two-stage gate, same as every prior wave)

Jerod picked the UI/app phase as the next direction, out of the three-way fork laid out in the
prior close-out entry (`3d5cf51`). **Wave 7 is open, pre-brief GO'd.**

**Scope, at the level PLANNER can set (sequencing/boundaries, not code-level detail — that's
IMPLEMENTER's pre-brief to write):** Bolo 2026's actual player-facing app — main menu, "Host a
Game"/"Join a Game" panels (now scoped by D58: both in-process hosting and a separate Dedicated
Host binary), in-game HUD, settings, whatever else the reference client's UI shell covers. Same
D25 clean-room discipline already governing WinBolo applies to reading `Reference/c/`'s Cocoa UI
layer (`GSXBoloController.m` et al.) for architectural understanding only, never copied. **Also
folds in Q14** (explosions-list attribution) — PARITY already found no mechanical gameplay
consumer, so this is squarely a UI-layer call now that this phase exists to make it in.

**Real dependency surfaced before opening this blind: Phase 2 (glyph art) never happened.**
Checked directly — `Sources/BoloGlyphs/main.swift` is a single-line stub comment, no
implementation. This phase cannot render a single screen without an asset pipeline existing first.
Recommending (not mandating — IMPLEMENTER's pre-brief should confirm or counter-propose) a **7.0
sub-wave for the glyph-sheet generator + original-Cheshire-asset purge**, sequenced before any
screen-level sub-wave — same shape as D23/D43's "split when it's genuinely two units of work"
precedent, not a new product-scope call needing Jerod.

**Flagging loudly, not deciding:** Phase 2's own verify step calls for a **git-history rewrite** to
strip the original copyrighted assets before this project could ever be distributed with them
still reachable in history (Q18 already noted the cost grows with every commit made before it
happens — the project is now 60+ commits past where Q18 first flagged this). This is a real,
deliberate, destructive git operation. It does not block starting the asset-pipeline work itself,
but it should be raised to Jerod explicitly before anyone actually executes it — not treated as a
routine step buried inside a pre-brief.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Wave 7 row added (UI phase, D58/Q14/Phase-2-dependency noted); Wave 6 summary
  row updated to point at Wave 7 instead of "nothing GO'd."

[TO: IMPLEMENTER] Wave 7 (UI/app phase) is GO'd for pre-brief. Read `Reference/c/`'s UI layer
(Cocoa client shell) and the current state of `Sources/BoloGlyphs/` (currently empty) before
writing your pre-brief. Recommend scoping a 7.0 asset-pipeline sub-wave first, per the note above,
but confirm or counter-propose in your own pre-brief rather than treating this as fixed. Do not
execute the git-history rewrite (Q18) without raising it to PLANNER/Jerod first, even if it comes
up naturally while scoping the asset purge.
[TO: PARITY] No action yet — nothing coded this entry.

### [PLANNER] 2026-09-04 — Wave 7 re-scoped to a v1 vertical slice (D60), coding GO'd for 7.0-7.3

**Type:** planning — scope revision + coding GO
**Phase:** Wave 7.0-7.3 (v1 vertical slice)
**Blocks:** nothing — Milestones B/C/D deliberately NOT GO'd, sequenced later

Jerod flagged the prior GO as too large a step with no clear ship path. Correct call — sized the
reference Cocoa UI directly before doing anything else: `Reference/c/Mac OS X/GSXBoloController.m`
is 4,037 lines (IBOutlets for host/join panels, 48 status image views, key remapping, toolbar,
allegiance/messages panels, tracker table), `GSBoloView.m` (the actual draw loop) is 600 lines,
~5,700 lines total across the UI layer — and this project has no Xcode app target yet at all
(SPM-only since Phase 0, by original design, deferred to "when there's UI to show"). Also checked
`images.h` directly: 297 image indices, confirming the original single-256×256-sheet Phase 2 plan
still fits. One piece of good news found while sizing this: `TCPSession.swift`/`HostSession.swift`
already expose `onPlayerStatusChanged`/`onPillStatusChanged`/`onBaseStatusChanged`/
`onTankStatusChanged` — the exact hook points the reference `setplayerstatus`/`setpillstatus`/
`setbasestatus`/`settankstatus` C callbacks map onto — as a byproduct of Wave 6's networking work,
already built and tested. Milestone C's HUD wiring won't be starting from nothing.

Presented Jerod three staged options plus "show me the full breakdown first"; he picked the
smallest — **a playable vertical slice as v1**, no menus, no networking UI, no HUD. **Ruled as
D60.**

**Wave 7 re-scoped and split into 7.0-7.3, all coding GO'd now** (not just pre-brief — the split
itself, informed by direct research against `Reference/c/`, stands in for the normal pre-brief
step here; IMPLEMENTER should still confirm each sub-wave's detailed approach, especially 7.2's
rendering-mechanism choice, before coding it):

- **7.0** — asset pipeline (Phase 2 proper): `BoloGlyphs` parses `images.h`, renders the tile/
  sprite sheet(s), 16 tank headings as one rotated glyph, OFL-font geometric glyphs. Sound
  explicitly deferred past v1.
- **7.1** — Xcode app target: the app bundle/window/entitlements skeleton that doesn't exist yet.
  Blocks 7.2/7.3 — nothing else can run as an app without it.
- **7.2** — game rendering: the `GSBoloView`-equivalent draw loop, consuming 7.0's assets against
  a live `GameState`. **Rendering mechanism (SwiftUI Canvas/TimelineView vs. an AppKit
  `NSView`/`CALayer` wrapped via `NSViewRepresentable`) is left to IMPLEMENTER to prototype and
  propose** — not a call to make blind from this side; PLANNER reviews whichever the pre-brief
  proposes against D41's tick-timing discipline before that sub-wave's own coding proceeds.
- **7.3** — input + tick loop: keyboard → real `BoloKit` tick loop → 7.2's render. Single-process,
  no networking. This is what actually makes v1 "playable."

**Milestones B (multiplayer UI), C (full HUD/prefs/chat/sound), D (polish + ship prep, including**
**Q18's git-history rewrite no later than this point) are identified but deliberately NOT GO'd** —
sequenced as their own future waves once 7.0-7.3 land and PARITY-pass, not bundled into this GO.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — D60 added; Wave 7's row rewritten to describe the v1-slice scoping; four new
  sub-wave rows (7.0-7.3) added with individual scope and status.

[TO: IMPLEMENTER] Wave 7.0-7.3 are coding GO'd — the v1 vertical slice only. Read
`Reference/c/Mac OS X/` (GSXBoloController.m, GSBoloView.m) and `images.h` directly rather than
re-deriving what's already confirmed above. Write a pre-brief per sub-wave as usual, but 7.2 in
particular needs your own rendering-mechanism recommendation before PLANNER reviews it — don't
treat SwiftUI-vs-AppKit as pre-decided. Do not scope or start Milestones B/C/D without a fresh GO.
Do not execute Q18's git-history rewrite without raising it to PLANNER/Jerod first.
[TO: PARITY] No action yet — nothing coded this entry.


## [TO: IMPLEMENTER] PLANNER purges CLAUDE.md bootstrap for Wave 7 restart

Jerod is archiving and restarting the Implementer session per routine. Per his direction,
`CLAUDE.md` has been purged in place (not additively extended) — old Wave 1-6 decisions-index
content trimmed to only what still governs Wave 7 work, replaced with a dense Wave 7 scope
section: the 7.0-7.3 sub-wave breakdown, the pre-built Wave 6 callback hooks (`onPlayerStatusChanged`
et al.) available for reuse, and the corrected licensing basis for reading `Reference/c`.

**Self-correction**: the Wave 7.2 PLAN.md row previously said "read-only/clean-room per D25" —
that was wrong. `Reference/c` (xbolo) is MIT-licensed (`Reference/c/LICENSE`; D1/D13); D25/D33's
clean-room restriction applies only to WinBolo (GPL v2). Corrected in both CLAUDE.md and PLAN.md's
Wave 7.2 row. No decision text changed — this is a citation fix, not a new ruling.

Milestones B/C/D remain explicitly NOT GO'd in the new CLAUDE.md, matching D60/PLAN.md.

### [PLANNER] 2026-09-04 — Admin agent: archive pass through Wave 6 close

**Type:** admin/process — archive/compression pass
**Phase:** repo housekeeping (Admin agent)
**Blocks:** nothing

Admin agent compressed everything from the Wave 6.5 pre-brief through Wave 6's formal close
(6.5a/6.5b — D54/D55/D56/D57 — and the Wave 6 phase close-out covering all of 6.0-6.6, nine real
PARITY findings) into `docs/notes/archive.md`, matching the existing per-wave summary format.
Full uncompressed text remains in git history per D28. `AGENT_NOTES.md`'s active log now starts
at Wave 7's opening (Jerod's direct Q22/Q26 ruling, D58/D59); header renamed to
`## Active Log (post-Wave-6)`, blockquote and index table updated to match. Committed at
`24474fe`, explicit pathspec (`docs/AGENT_NOTES.md docs/notes/archive.md` only — verified
`git status --short` showed only these two files before staging).

A stale `.git/index.lock` again blocked the initial commit attempt (same recurring nuisance as
the prior archive pass); requested delete permission for the repo root, removed the lock,
reconfirmed a clean two-file diff before committing.

No action needed from any of the three rotation roles.

### [PLANNER] 2026-09-04 — Q10 ruled (D61): hold Reference/c removal until port is done with it

**Type:** planning — open-question ruling, no coding impact
**Phase:** documentation/process policy
**Blocks:** nothing — deferred action, not executed now

Jerod raised Q10 directly: documentation, especially the README, should ultimately point back to
the original source of the C code rather than this project permanently maintaining a full copy,
and confirmed his own assumption that this action holds until we're done needing the C code.

**Ruled as D61.** Confirmed: `Reference/c` stays in-tree as an actively-consulted oracle for now.
The eventual state is docs pointing to `https://github.com/bananazon/xbolo` (already linked at the
top of the README) as canonical, with the local submodule removed (recoverable in git history) —
matching Q10's original recommendation. Retimed the trigger, though: not the old "Phase 5 ends"
language, which Q18 already flagged as stale roadmap text, but "the project is done actively
referencing `Reference/c`" (IMPLEMENTER/PARITY no longer hand-tracing or differential-testing
against it). Practically that lands no earlier than Milestone D (ship prep), the same checkpoint
already set for Q18's git-history rewrite of original asset bytes — one cleanup pass, not two.

Two concrete to-dos parked for that future Milestone D scoping pass, not now: (a) `git rm` the
`Reference/c` submodule, (b) update the README's Approach section (currently: Reference/ "kept as
oracle") to say it's been removed and point to the original repo as canonical.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — D61 added to the decisions log; Q10 removed from Open Questions (closed); the
  `Reference/c/` layout-tree comment and Phase 6's stale "Resolve Q10" line updated to match.

[TO: IMPLEMENTER] No action — `Reference/c` stays exactly as-is, keep using it as the oracle for
Wave 7 work as normal. Nothing changes about how you reference it day to day.
[TO: PARITY] No action — same, no change to how you hand-trace against `Reference/c`.

### [PARITY] 2026-09-04 — Wave 7 pre-code factual audit: `images.h` is two sheets, not one (blocker); 7.0 mostly already ported

**Type:** audit — factual/numeric re-derivation of the Wave 7 brief, not a post-commit code audit
**Phase:** Wave 7.0 (asset pipeline), pre-code
**Blocks:** 7.0's sheet-writer design, until IMPLEMENTER accounts for two sheets

**Activation note:** there is no open `[TO: PARITY]` tag — the prior entry says "no action, nothing
coded this entry," and nothing has landed for Wave 7 yet, so there is no commit to hand-trace.
Jerod activated this session ad hoc (`docs/PARITY.md`'s sanctioned override) to check the Wave 7
brief's own numbers before a live Implementer session codes against them — applying "verify claimed
numbers yourself" to the brief's arithmetic instead of to a completion report. Jerod's ruling: write
findings, request retroactive `[TO: PARITY]` activation, do not treat this as protocol-as-usual.

**Standing-limitation correction:** `docs/PARITY.md` states this environment has no Swift
toolchain. That's stale — `swift --version` here reports Apple Swift 6.4,
`arm64-apple-macosx27.0.0`. I ran no build this session (text/header analysis only), but a future
PARITY session can `swift build && swift test` and check claimed test counts directly instead of
trusting the report, which hasn't been possible before now. Worth PLANNER updating `docs/PARITY.md`.

**F1 — BLOCKER.** `CLAUDE.md`'s Wave 7 section and `docs/PLAN.md`'s Wave 7 row both say `images.h`
has "297 `#define ...IMAGE` indices (roughly `0x00`–`0x91`), fitting one 256-cell (16×16) sheet."
Re-parsed `Reference/c/images.h` directly: 296 `#define` directives (297 counted the `__IMAGES__`
include guard); of those, **290 unique names** (6 are benign identical redefinitions, e.g.
`PTKB08IMAGE (0x08)` twice, zero conflicting values). More importantly, the index space **resets
to `0x00` twice** — `WALL46IMAGE` at the top of the file and `PTKB00IMAGE` partway through — because
these are **two independent index spaces for two separate sheets**, confirmed at
`Reference/c/Mac OS X/GSBoloView.m:40-41` (`[NSImage imageNamed:@"Tiles"]` /
`imageNamed:@"Sprites"]`), sampled from different call sites (`tiles` at lines 137/144/190/197/
265/272, `sprites` at line 448). Tiles: 177 names, dense contiguous `0x00`-`0xb0`. Sprites: 113
names, sparse `0x00`-`0x91` (33 unused cells). 177+113 = 290 > 256, so "one sheet" was arithmetically
impossible regardless — the `0x91` in the brief is only the sprite max, paired with the tile-space
name count. Both shipped sheets are confirmed 256×256px/16×16 cells from the PNG IHDR headers.
Per-sheet the "fits a 256-cell sheet" conclusion is still true (tiles 177/256, sprites 113/256) —
only the sheet *count* is wrong. `docs/PLAN.md`'s Phase-2 line and the 7.0 row itself already say
"sheet(s)" plural elsewhere; it's specifically the "297 indices... one sheet" sentence that's wrong.

**F2 — scope reduction.** 7.0 is scoped as "`BoloGlyphs` CLI parses `images.h` → manifest → renders."
That parse/manifest step is already done: all 290 image constants are already ported to
`Sources/BoloKit/Images.swift` (`public let <NAME>IMAGE: Int32 = 0x..`, starting near the top of the
file) — mechanically diffed against `images.h`, zero missing, zero extra, zero value mismatches.
`mapimage()` (`Reference/c/images.c`, the 742-line terrain→index neighbour-bitmask selector) is also
already ported, at `Sources/BoloKit/Images.swift` (both a raw-pointer and a `TileGrid` overload),
wired for differential testing via `Sources/CXBolo/images.c` + `tiles_shim.c`'s `mapimage_flat`.
`Sources/BoloGlyphs/main.swift` is confirmed still a one-line stub. Recommend 7.0 consume `BoloKit`'s
existing constants as the single source of truth for the sheet writer rather than re-parsing
`images.h` a second time — a second parse would be a drift-prone duplicate, not new fidelity.

**F3 — confirmed, with a trap.** The brief's `row = idx >> 4, col = idx & 0xF` decoding is verified
correct — `GSBoloView.m:180`, `srcRect = NSMakeRect((image%16)*16, (image/16)*16, 16.0, 16.0)`,
identical at all seven cell-math call sites. Trap for whoever writes the renderer: `GSBoloView`
never overrides `isFlipped` (grep count 0), so that y is measured from AppKit's default
**bottom-left origin** — index 0 is the sheet's bottom-left cell. Transcribing this y-math verbatim
into a top-left-origin context (CoreGraphics, SwiftUI `Canvas`) inverts row order silently. Since
7.0 generates fresh sheets, there's no fidelity *obligation* here, but the generator and the 7.2
renderer need to agree on one row-0 convention explicitly. Also for 7.2: `client.images[y][x] == -1`
is a "tile unseen, paint black" sentinel (`GSBoloView.m:130/183/258`), not a valid sheet index.

**F4 — open question, not resolved here.** 7.2 is scoped to draw "terrain + tanks from a live
`GameState`," but `GSBoloView` actually draws from three display-side arrays computed by the C
client — `client.images[y][x]`, `isMinedTile(client.seentiles, …)`, `client.fog[y][x]`
(`GSBoloView.m:178/193/201`) — and `Sources/BoloKit/BMap.swift` already documents, in its own
comments, that `client.seentiles`/`client.images`/fog-of-war display state was never modeled
anywhere in this port (same established precedent as `increasevis`/`decreasevis` elsewhere). 7.2
therefore carries unbudgeted scope: building that display layer before it can draw a tile. Question
for PLANNER, not mine to resolve per my own role: for a single-player v1 slice, is fog-of-war
stubbed to "everything visible" (reducing `images[][]` to a straight per-tile `mapimage` pass, no
`fog`/`seentiles` needed), or is the visibility layer in scope for 7.2? D60 doesn't address this.

**Claims verified, not just restated:** `GSXBoloController.m` 4,037 lines ✓, `GSBoloView.m` 600
lines ✓, `BoloGlyphs/main.swift` one-line stub ✓, all seven Wave 6 callback hooks
(`onPlayerStatusChanged`/`onPillStatusChanged`/`onBaseStatusChanged`/`onTankStatusChanged`/
`onMineExplosion`/`onSuperboomTerrain`/`onDropPills`) exist and are usable as claimed — minor
imprecision only, the four `*StatusChanged` hooks live in `TCPSession.swift`/`JoinClientApply.swift`,
not `HostSession.swift` as `CLAUDE.md` states; the mine/superboom/droppills trio does span
`HostSession.swift` as claimed, plus `UDPSession.swift`/`DgramClientApply.swift`.

**Decision checklist (D18/D24/D25+D33/D26/D27/D28):** not applicable this session — no Swift was
committed for Wave 7, so there's no code to check for `Double` creep, replicated-bug drift, WinBolo
similarity, build-flag regressions, per-tick ordering, or test-count change. Stated rather than
silently skipped, per the standing-limitation discipline.

> **→ Planner:** F1 blocks 7.0's sheet design as currently briefed — recommend correcting
> `CLAUDE.md` and `docs/PLAN.md`'s Wave 7 row (297/one-sheet → 290 names/two sheets/177+113) before
> more coding lands on the old numbers. F2 is a scope note for the 7.0 row (constants + `mapimage`
> already ported; 7.0 is rendering only). F4 needs a ruling on fog-of-war scope for the v1 slice.
> Also requesting this session be retroactively covered by a `[TO: PARITY]` tag, since none was
> open when I started — logging as Jerod's deliberate ad hoc override, not a protocol break.
> **→ Implementer:** F1 is a blocker if 7.0 is actively being coded — `BoloGlyphs` needs to emit
> two sheets (tiles 177/256 cells, sprites 113/256 cells), not one flat 290-entry sheet; index
> collisions exist between the two spaces (e.g. `0x08` = `WALL38IMAGE` in tiles, `PTKB08IMAGE` in
> sprites). F2: no need to re-parse `images.h` — `Sources/BoloKit/Images.swift` already has all 290
> constants and `mapimage()`; build the sheet writer on top of those rather than duplicating the
> parse. F3: pick and document one sheet row-0 convention (native bottom-left vs. flipped) between
> the sheet generator and the eventual 7.2 renderer, and treat `-1` as "no image," not an index.
