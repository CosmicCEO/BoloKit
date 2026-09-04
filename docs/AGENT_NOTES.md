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

### [PLANNER] 2026-09-04 — Rule PARITY's pre-code Wave 7 audit: F1/F2 corrected (D62/D63), F3 settled (D64), F4 ruled (D65)

**Type:** planning — ruling on ad hoc PARITY findings, doc corrections, one scope decision
**Phase:** Wave 7.0/7.2, pre-code
**Blocks:** nothing now — corrections land before Implementer codes against the old numbers

Jerod relayed PARITY's ad hoc pre-code audit (entry directly above this one) for review rather than
letting Implementer begin 7.0 on the briefed numbers. Independently re-verified every factual claim
before ruling — the images.h define count (297, matching PARITY's "296 + include guard"), both
`0x00` reset points (`WALL46IMAGE` line 13, `PTKB00IMAGE` line 193), the two `imageNamed:` call
sites in `GSBoloView.m`, the `Images.swift` constant/`mapimage()` count (290, both overloads
present), `BoloGlyphs/main.swift`'s stub state, the `isFlipped` grep (zero hits), and the
`client.images`/`seentiles`/`fog` read sites plus `BMap.swift`'s own "never modeled" comment. All
confirmed independently, not just restated.

**F1 — confirmed real, BLOCKER resolved by correction (D62).** `images.h` is two independent index
spaces (tiles 177/256, sprites 113/256), not one 256-cell sheet as `CLAUDE.md`/`PLAN.md` said.
`CLAUDE.md`'s 7.0 section and `PLAN.md`'s Wave 7/7.0 rows corrected to the right numbers.

**F2 — confirmed, scope corrected (D63).** 7.0's parse/manifest step is already done in
`Sources/BoloKit/Images.swift` (290 constants + `mapimage()`, from an earlier wave). 7.0 narrows to
the sheet renderer only — corrected in `CLAUDE.md` and `PLAN.md`'s Wave 7.0 row.

**F3 — settled, not left ambiguous (D64).** No fidelity obligation on sheet row-0 origin (sheets are
freshly generated), but 7.0 and 7.2 must agree on one convention explicitly — Implementer picks in
the 7.0 pre-brief, documents it, 7.2 consumes the same one. `-1` = no-image sentinel, never a valid
index, in both sub-waves.

**F4 — ruled (D65).** Fog-of-war/seen-tiles display (`client.images`/`seentiles`/`fog`, never
modeled anywhere in this port per `BMap.swift`'s own comments) is out of scope for the v1 slice —
every tile renders as fully visible, sheet index comes straight from `mapimage()`. Real fog-of-war
display deferred to a future wave (not yet assigned), not a v1 blocker. `PLAN.md`'s Wave 7.2 row
updated to say so.

**One item NOT acted on:** PARITY also reported `docs/PARITY.md`'s "no Swift toolchain" line as
stale, citing `swift --version` → Apple Swift 6.4 in its own session. Attempted to reproduce
independently this session: `swift`, `xcrun`, and `/usr/bin/swift` all report not-found, and
`/Applications` isn't even visible from this device-bridge shell. Not correcting `docs/PARITY.md`
on unreconciled evidence — flagging the discrepancy instead. Possible explanations: PARITY's
session had a different execution context (e.g. direct computer-use vs. this sandboxed device-bash
VM) rather than the claim being wrong outright. Needs re-confirmation by whoever next runs a PARITY
session, not assumed either way.

**Ad hoc activation retroactively covered, per precedent.** No `[TO: PARITY]` tag was open when
PARITY's session started; Jerod's direct activation (per `docs/PARITY.md`'s sanctioned override,
same pattern as Wave 6.4a/6.4b's ad hoc assessments) is confirmed legitimate, not a protocol break.
The uncommitted entry above this one is PARITY's own — committing it now alongside this ruling
since it was never committed by that session (commit discipline: an entry only exists once
committed).

**Docs updated (committed alongside this entry, same commit as PARITY's own uncommitted entry
above):**
- `docs/PLAN.md` — D62/D63/D64/D65 added to the decisions log; Wave 7, 7.0, and 7.2 rows corrected/
  annotated to match.
- `CLAUDE.md` — 7.0 and 7.2 sections corrected with the same facts, so a fresh Implementer session
  reads the right numbers without needing to cross-reference this entry.

[TO: IMPLEMENTER] Wave 7.0/7.2 remain coding GO'd (D60) — proceed under the corrected facts above:
two sheets not one (D62), build on `Images.swift`'s existing constants rather than re-parsing (D63),
document your row-0 sheet convention in the 7.0 pre-brief and keep 7.2 consistent with it (D64),
and skip fog-of-war/seen-tiles modeling in 7.2 — full visibility for v1 (D65).
[TO: PARITY] Retroactive `[TO: PARITY]` activation confirmed for the ad hoc audit above — thank you
for catching this before code landed on the wrong numbers. Please re-confirm the Swift-toolchain
claim (`swift --version`) in whatever execution context your next session actually runs in; this
session's device-bridge shell couldn't reproduce it.

### [PLANNER] 2026-09-04 — Admin agent: role-alignment audit (Jerod reported possible drift)

**Type:** admin/process — cross-check audit, one doc fix, findings reported (not fixed)
**Phase:** repo housekeeping (Admin agent)
**Blocks:** nothing

Jerod reported that a live Xcode/Implementer session appeared to be using the wrong
`docs/AGENT_NOTES.md` entry template and, separately, self-identifying as PARITY. Admin agent
audited all four current role bootstraps (`docs/ADMIN.md`, `CLAUDE.md`, `docs/PARITY.md`,
`docs/PLANNER.md`) plus `docs/AGENT_NOTES.md`'s own Format section, `README.md`'s role/status
text, and `docs/notes/WAVE59_BOOTSTRAP.md`/`WAVE65_BOOTSTRAP.md` for cross-contamination or stale
role instructions. **The four bootstrap files as currently committed are clean** — none
misidentifies a role, none instructs the wrong template, and `CLAUDE.md`'s content (post
`dac5bd7`'s purge + `7195eff`'s D62-D65 corrections) reads correctly for a fresh Implementer
session. Could not audit a live chat session's actual in-context state — that's outside this
agent's reach — so this doesn't rule out the reported symptom having occurred in a session
carrying forward older conversational context rather than misreading the committed files.

**Real findings, for the record:**

1. **`docs/AGENT_NOTES.md` line ~212** (`## [TO: IMPLEMENTER] PLANNER purges CLAUDE.md bootstrap
   for Wave 7 restart`) doesn't follow the documented Format template — H2 not H3, no
   `[ROLE] YYYY-MM-DD — title` header, no explicit authoring-role tag. Left as-is per the
   append-only convention (not an archive pass), but flagging so future entries don't copy its
   shape. A fresh session skimming recent entries for "what does a normal entry look like" would
   see this one among the most recent and could plausibly pattern-match off it instead of the
   Format section at the top of the file.
2. **`docs/PARITY.md`'s "no Swift toolchain" line is already known-stale** (PARITY's own Wave 7
   pre-code audit reported `swift --version` succeeding in its session; Planner's follow-up
   couldn't reproduce from the device-bridge shell and explicitly held off correcting the doc
   pending re-confirmation). Not touched here — already an open, deliberately-held item, not new.
3. **`git config user.name` for this repo is `Claude (Architectural Reviewer) <claude@anthropic.com>`,
   identical across every commit regardless of which of the four roles actually wrote it** — it
   predates the IMPLEMENTER/PLANNER/PARITY/Admin naming and carries zero role signal in `git log`.
   Cosmetic (doesn't affect any bootstrap file's content), but if any session leans on `git log`
   authorship to infer "who I am" or "who did what," this is actively unhelpful. Flagging, not
   changing — local git identity felt like a call for Jerod, not something to change unilaterally.
4. **`README.md`'s Status paragraph was substantially stale** (described Wave 6 as in-progress at
   445 tests, transport/tracker "forward-planned but not yet started") — genuinely out of sync
   with `docs/PLAN.md`/`docs/AGENT_NOTES.md`'s actual state (Wave 6 fully closed, 597 tests, Wave
   7 now the active wave). **Fixed** (`37e4d68`) — this is explicitly Admin's to keep in sync per
   `docs/ADMIN.md`, not a report-only item.

**No D-numbered decision changed, no code touched, no other role's committed work rewritten.**

[TO: IMPLEMENTER] If you're picking up a fresh session and anything about your own role feels
uncertain, `CLAUDE.md` as currently committed (post `7195eff`) is confirmed clean — re-read it
directly rather than trusting whatever context a prior session may have accumulated.
[TO: PLANNER] Two open items worth a look when convenient: the line-~212 entry's template
deviation (informational, not urgent) and whether `git config user.name` should be updated to
something that actually distinguishes roles.
[TO: PARITY] No action needed.

### [IMPLEMENTER] 2026-09-04 — Role self-correction (was misidentifying as PARITY); Wave 7.0 pre-brief

**Type:** self-correction + coding pre-brief, no Swift written yet
**Phase:** Wave 7.0 (asset pipeline), pre-code
**Blocks:** Wave 7.0 coding start — pre-brief below needs PLANNER's read before I write Swift,
same two-stage gate as every prior wave

**Self-correction, confirmed by Jerod directly this session:** the session that wrote both the
`[PARITY]` audit entry above (pre-`423ba37`) and, presumably, whatever live-session symptom the
Admin role-alignment audit's suspected drift ("a live Xcode/Implementer session... self-identifying
as PARITY") was reporting, **was this host** — the Xcode API session, which `AGENT_NOTES.md`'s own
header (line 3) documents as IMPLEMENTER's host, not PARITY/PLANNER's (Claude.ai). The
misidentification came from reading `git config user.name` ("Claude (Architectural Reviewer)") as a
role signal — which the Admin audit's finding #3 already flagged as carrying *zero* role signal,
identical across all four roles. I'm IMPLEMENTER. The audit content itself doesn't need redoing —
PLANNER independently re-verified every claim before ruling D62-D65 — only the byline was wrong.

**Toolchain finding, correcting my own earlier framing:** I told PLANNER (via the PARITY entry
above) that `docs/PARITY.md`'s "no Swift toolchain" line was stale. More precisely, it's
**host-conditional**: false here (`swift --version` → Apple Swift 6.4; confirmed compiling *and
executing* a trivial program, not just present on `PATH`), true on Claude.ai, PARITY's actual
intended host. PLANNER's device-bridge shell failing to reproduce it wasn't a contradiction, it was
two different hosts. Per Jerod: log this, don't edit `docs/PARITY.md` — the line is correct for the
host PARITY is meant to run on.

**Wave 7.0 pre-brief.** Read `Reference/c/images.c` (742 lines, `mapimage()`), confirmed
`Sources/BoloKit/Images.swift` (290 constants + both `mapimage()` overloads, `Sources/BoloKit/
Tiles.swift`'s `TileGrid`/`Tile` enum/`is*LikeTile` predicates) already covers D63's "build on this,
don't re-parse `images.h`" instruction, and confirmed `Package.swift`'s current `BoloGlyphs` is a
dependency-free `.executableTarget` (no `BoloKit` dependency yet).

- **D64 row-0 call:** top-left origin (`row = idx >> 4` measured from the top), not the C
  original's implicit bottom-left (`GSBoloView` never sets `isFlipped`). Reasoning: PNG and
  CoreGraphics are both top-down, 7.2 will sample `CGImage` sub-rects, top-left costs zero flips
  end to end, and D64 already grants no fidelity obligation on freshly-generated sheets. 7.2 must
  consume this same convention. `-1` stays a "no image" sentinel, never a valid index, in both.
- **Design: derive glyph semantics by probing `mapimage()`, don't hand-tabulate them.** For each
  `Tile` case, sweep all 256 eight-neighbor configurations on a `TileGrid` at an interior coordinate
  (edges fabricate connections — `is*LikeTile` predicates return 1 out-of-bounds), call
  `mapimage()`, and group configurations by resulting image index to recover each variant's
  connectivity signature. Self-checking: if the sweep doesn't yield exactly the 177 expected tile
  indices, a test fails before a wrong-looking sheet ships. Wall variants nest a diagonal-neighbor
  switch inside the orthogonal one (`images.c`, `case kWallTile`) — exactly why the sweep needs 8
  neighbors, not 4, to produce 47 variants from 4-bit logic.
- **Proposed deviation from `docs/PLAN.md`'s 7.0 row, flagged not decided:** the row calls for
  "geometric/box-drawing glyphs from an OFL font (Noto Sans Symbols/DejaVu)." Proposing procedural
  CoreGraphics drawing instead, no vendored font at all — nothing in the 290-cell set is actually
  text, hinted glyphs render mushy at 16×16px, and dropping the font removes a vendored binary +
  license file from a wave whose whole point is clean provenance. Keeping a `GlyphSource` seam so a
  font path could be added later without rework. This is otherwise my call per `CLAUDE.md`, but it
  contradicts named `PLAN.md` text, so flagging rather than just doing it.
- **Target split, also flagged:** `BoloGlyphs` is currently a bare `.executableTarget` with no
  dependencies; executables can't be cleanly imported by tests. Proposing
  `BoloGlyphsCore` (library, depends on `BoloKit`, holds the probe/derive/layout/pixel-buffer logic)
  + `BoloGlyphs` (thin executable: CLI args + PNG encode via ImageIO) + `BoloKitTests` gaining a
  `BoloGlyphsCore` dependency. `CXBolo`'s `-ffp-contract=off` (D26) untouched.
- **D28 baseline, verified directly this session, not taken from docs:** 597 `@Test` declarations,
  zero `@Test(arguments:)` parameterized cases (so declared count = executed count), zero
  `import XCTest` anywhere in `Tests/`. Matches `docs/PLAN.md`'s stated 597. **Before = 597.**

No Swift written yet — this is the pre-brief only, per `CLAUDE.md`'s "write your pre-brief before
coding" rule.

> **→ Planner:** two flagged deviations from the committed `PLAN.md` 7.0 text above (no-font
> procedural glyphs; the `BoloGlyphsCore`/`BoloGlyphs` target split) — need your read before I
> start Swift, not asking permission for the parts D60/D62/D63/D64/D65 already GO'd me on. Also:
> the toolchain finding above is a correction to my own prior report, logged per Jerod's direction
> to record-only, no `docs/PARITY.md` edit.
> **→ Parity:** nothing to audit yet — no code committed this entry.

### [PLANNER] 2026-09-04 — Wave 7.0 pre-brief reviewed, coding GO'd (D66-D68); role-attribution correction

**Type:** planning — pre-brief review + coding GO, plus a correction to prior record
**Phase:** Wave 7.0 (asset pipeline)
**Blocks:** nothing — coding is now clear to start

**Attribution correction first.** The entry two above this one (committed at `423ba37`,
"[PARITY] ... Wave 7 pre-code factual audit") was authored by the Implementer session, not PARITY —
it self-identified as PARITY in error, having read `git config user.name`
("Claude (Architectural Reviewer)") as a role signal, which it isn't (identical across all four
roles, per Admin's role-alignment audit below). Self-corrected directly by Implementer in `8170a18`.
This doesn't change D62-D65's substance: every fact in that audit was independently re-verified by
this session against the actual repo before those four decisions ruled, not taken on the report's
word. Only the byline was wrong, corrected in `docs/PLAN.md`'s D62 row rather than silently rewritten
(same convention as the D25 mis-citation fix).

**Toolchain finding, resolved.** Also corrected by Implementer directly: `docs/PARITY.md`'s "no Swift
toolchain" line isn't stale, it's host-conditional — false on the Xcode/Implementer host (`swift
--version` succeeds there), true on the actual Claude.ai/PARITY host this device-bridge session also
runs on (confirmed unreproducible here too). Per Jerod: log only, no `docs/PARITY.md` edit — the line
is correct for PARITY's actual intended host. Closing this out; no longer an open item.

**Wave 7.0 pre-brief (`8170a18`), reviewed and GO'd.** Independently re-verified before ruling:
`Package.swift`'s `BoloGlyphs` target is exactly `.executableTarget(name: "BoloGlyphs")`, no
dependencies; `Sources/BoloKit/Tiles.swift` exists; test baseline is 597 `@Test` declarations, 0
parameterized, 0 `XCTest` imports — matches the claimed D28 baseline exactly.

- **D66 — row-0 origin ratified: top-left.** Implementer's reasoning (PNG/CoreGraphics are top-down,
  zero flips end to end, D64 already waives fidelity obligation on freshly-generated sheets) is
  sound. Binding on both 7.0 and 7.2.
- **D67 — approved: procedural CoreGraphics glyphs, no vendored OFL font.** Deviates from `PLAN.md`'s
  named text, correctly flagged rather than just done. Good call: nothing in the 290-cell set is
  actual text, hinted fonts render mushy at 16×16px, and dropping the font removes a vendored binary
  + license file from a wave whose whole point is clean provenance — strictly less risk. The kept
  `GlyphSource` seam means this isn't a one-way door if a font is wanted later.
- **D68 — approved: `BoloGlyphsCore` (library) + `BoloGlyphs` (thin executable) target split.**
  Standard SPM logic/CLI separation for testability; doesn't contradict any named decision about file
  layout, which was always descriptive rather than a fixed target list.
- The probe-`mapimage()`-across-256-neighbor-configs design for deriving glyph semantics (rather than
  hand-tabulating) is Implementer's own call per `CLAUDE.md` and needs no ruling — noting it's a good,
  self-checking approach (fails loudly if the sweep doesn't yield exactly 177 tile indices).

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — D66/D67/D68 added; D62's row gets the attribution-correction sentence; Wave 7.0's
  row updated to the ratified row-0 convention, the approved font/target-split deviations, and an
  explicit coding-GO status.

**Admin's role-alignment audit (`9614a62`) — three other findings, dispositioned:**
1. The malformed `## [TO: IMPLEMENTER] PLANNER purges CLAUDE.md...` entry (H2, no role/date header)
   stays as historical record, not rewritten — but restating here for any session pattern-matching
   off recent entries instead of the Format section: every new entry is `### [ROLE] YYYY-MM-DD —
   title`, full stop.
2. Toolchain line — resolved above, no action.
3. `git config user.name` being role-agnostic across all four roles: not changing it — this is
   local git identity on Jerod's machine, out of scope for any of the four roles to touch
   unilaterally (same reason none of us edit git config generally), and now that the actual failure
   mode (inferring role from author identity) is named and corrected once, it shouldn't recur. If
   Jerod wants distinguishable commit authors for his own `git log` skimming, that's his call to make
   whenever convenient — not blocking anything.

[TO: IMPLEMENTER] Wave 7.0 is coding-GO'd on this pre-brief as reviewed — D66 (top-left origin), D67
(procedural glyphs), D68 (target split) all confirmed. Proceed.
[TO: PARITY] Nothing yet to audit — no Swift committed. When 7.0 lands, this will be your first real
post-commit audit of Wave 7 (the pre-code numeric review to date, corrected above, was never actually
yours).
