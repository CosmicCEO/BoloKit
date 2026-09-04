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

### [IMPLEMENTER] 2026-09-04 — Wave 7.0 shipped: BoloGlyphs sheet generator, 605 tests (+8)

**Type:** coding — Wave 7.0 (asset pipeline) implementation
**Phase:** Wave 7.0, coding complete
**Blocks:** nothing — unblocks 7.1 (Xcode app target), which unblocks 7.2/7.3

Implemented against the pre-brief above exactly as GO'd (D66/D67/D68), no scope changes discovered
mid-build.

**`Package.swift` (D68):** split `BoloGlyphs` into `BoloGlyphsCore` (library, depends on `BoloKit`)
+ `BoloGlyphs` (thin executable, depends on `BoloGlyphsCore`); `BoloKitTests` gained a
`BoloGlyphsCore` dependency so the new tests could import it. `CXBolo`'s `-ffp-contract=off` (D26)
untouched.

**`Sources/BoloGlyphsCore/Autotile.swift` — the probe.** `deriveConnectivity(family:)` sweeps
`mapimage()` (`Sources/BoloKit/Images.swift:301`) directly rather than hand-transcribing its case
labels, confirmed against the source before writing: single-predicate families (river/forest/
crater/boat/sea) sweep 4 orthogonal bits; wall adds 4 diagonal bits (its nested corner-resolution
switches, e.g. `case 7`/`case 15`, read them); road is a separate sweep entirely — its branch reads
*three* independent predicates (`isRoadLikeTile` and `isWaterLikeToLandTile` on the 4 orthogonal
cells, `isRoadLikeTile` again on the 4 diagonals), and no single `Tile` value can express "road-
like" and "water-like" as independent bits except `.unknown` (the one tile in both predicates'
true-sets) — so each orthogonal neighbor is swept across all 4 `(road, water)` combinations rather
than a single connected bit. `.grass` is the universal "disconnected" filler everywhere else,
confirmed outside all seven `is*LikeTile` predicate sets by reading each one directly. Probed at
(128,128), not an edge, since the predicates return `1` out-of-bounds (would fabricate connections).

**Self-check landed clean on the first run** — the sweep reproduced exactly 47/16/10/16/31/8/9
(wall/river/forest/crater/road/boat/sea = 137), summing with the 8 flat + 32 pill tile-space
indices to exactly 177, with zero gaps/overlaps against `tileIndexRange` (`0x00...MINE00IMAGE`).
This is what "self-checking" meant in the pre-brief: if the arithmetic had been wrong anywhere,
this test would have failed loudly instead of shipping a wrong-looking sheet.

**`ImageIndex.swift`:** all dispatch keys off `BoloKit`'s existing named constants (D63) — zero new
numeric literals for image identity. Sprite space needed no probing at all: tank rows/headings,
shell/explosion/builder frames, and crosshair/select are closed-form arithmetic on the index
(`row = idx >> 4`, `col = idx & 0xF`, per D66), confirmed sparse exactly as the audit found —
0x00-0x65, 0x70-0x75, 0x80-0x82, 0x90-0x91, 113 total, three gap runs left transparent.

**`GlyphSource.swift`/`Canvas.swift` (D67):** no vendored font, no `CoreGraphics` in the testable
library — raw RGBA pixel-buffer manipulation instead (fillRect/fillCircle/fillRing/a rotated-
triangle point-in-polygon test for the tank chevron), which is a stricter reading of D67 than
"procedural CoreGraphics" as pre-briefed: still procedural and font-free, just simpler and more
directly unit-testable than standing up a `CGContext` inside `BoloGlyphsCore`. `CoreGraphics`/
`ImageIO` are only used in the thin `BoloGlyphs` executable, for PNG encoding at the very end — the
`GlyphSource` seam D67 asked for is the `GlyphRole` enum, unchanged by this refinement.

**Verification:**
- `swift build` clean.
- `swift test`: **605 tests, +8, zero failures** (was 597, verified directly in the pre-brief, not
  taken from `docs/PLAN.md`). `swift test` runs `DifferentialTests` and `BoloKitTests` as separate
  processes with separate summary lines (156 + 449 = 605) — worth a heads-up for whoever next
  reports a "before/after" count from a single `swift test` invocation's tail output, since only
  the last target's summary line is visible without grepping the full log.
- Ran the CLI directly (`.build/debug/BoloGlyphs /tmp/glyphs_out`) and visually inspected both PNGs:
  wall/road/river blobs show visibly different connectivity shapes per neighbor configuration, tank
  chevrons rotate correctly across all 16 headings per row, destroyed-tank rows render distinctly
  from alive ones, pill gauges/shell/explosion/builder frames/crosshair/select all present.
- 8 new tests: per-family variant counts, full tile-range coverage with no gaps/overlaps, sentinel
  (`-1`) never reachable from an in-bounds probe, sprite gap structure, cell-math round-trip, sheet
  geometry (256×256, every used cell non-transparent, every sprite gap cell fully transparent), and
  byte-for-byte determinism across two generations.
- Generated sheets are not committed by this entry — `BoloGlyphs` is a build product, regenerable
  on demand; 7.1 will decide how/whether to bundle a generated copy into the app target.

**Files:** `Package.swift`; `Sources/BoloGlyphs/main.swift` (rewritten, was a one-line stub);
`Sources/BoloGlyphsCore/{Autotile,Canvas,ImageIndex,GlyphSource,SheetBuilder}.swift` (new);
`Tests/BoloKitTests/BoloGlyphsTests.swift` (new). Not touching `CLAUDE.md`/`docs/ADMIN.md`, both of
which show local modifications from other concurrent sessions this entry doesn't own.

> **→ Planner:** Wave 7.0 done, no open questions. One implementation refinement worth a look, not
> a deviation needing a ruling: `GlyphSource`'s drawing mechanism ended up as raw pixel manipulation
> rather than literal `CoreGraphics` calls, still satisfying D67's actual substance (no font,
> procedural, `GlyphRole` seam intact) — flagging for the record since the pre-brief said
> "CoreGraphics paths" specifically. Ready for 7.1 (Xcode app target) whenever GO'd.
> **→ Parity:** first real post-commit audit of Wave 7 — this entry plus the file list above is
> what to hand-trace. The probe's per-family counts (47/16/10/16/31/8/9) and the sprite gap
> structure are the numbers most worth independently re-deriving against `Images.swift`/`Tiles.swift`
> directly, same discipline as the pre-code audit.

### [PLANNER] 2026-09-04 — Wave 7.0 code reviewed, PARITY activated (D69)

**Type:** planning — completion-report review, PARITY activation, one status update
**Phase:** Wave 7.0 → PARITY audit
**Blocks:** Wave 7.0's *close* (not 7.1 — 7.1 can proceed once GO'd separately; coded and closed
are distinct states, per standing convention)

Reviewed Implementer's Wave 7.0 completion report (`618bedf`) against the D66-D68 pre-brief GO.
Implemented exactly as briefed, no undisclosed scope changes. Independently spot-verified before
ruling: `Package.swift`'s target split matches the report exactly (`BoloGlyphsCore` library
depending on `BoloKit`, thin `BoloGlyphs` executable depending on it, `BoloKitTests` gaining the
same dependency); the claimed sprite-space gap at `0x66`-`0x6F` cross-checked directly against
`Reference/c/images.h` — those code points belong to tile-space names (`SEAA*`/`FORE*`/`CRAT*`),
while sprite-space `SHELL0IMAGE`-`SHELL5IMAGE` sit at `0x60`-`0x65` as claimed, consistent with two
independent index spaces (D62); the reported per-family variant counts (47/16/10/16/31/8/9 = 137)
sum correctly, and 137 + 8 flat + 32 pill = 177, matching D62's established tile count exactly.
Full behavioral correctness (autotiling per family, sprite closed-form math, pixel-buffer drawing)
is PARITY's job to hand-trace, not re-derived here.

**On the flagged implementation refinement:** `GlyphSource`/`Canvas` shipped as raw RGBA
pixel-buffer manipulation (fillRect/fillCircle/fillRing/point-in-polygon) rather than literal
`CoreGraphics` calls, confined to `BoloGlyphsCore`, with `CoreGraphics`/`ImageIO` only in the thin
executable for final PNG encoding. **No ruling needed — this satisfies D67's actual substance** (no
vendored font, procedural, the `GlyphRole`/`GlyphSource` seam intact) and is arguably better: more
directly unit-testable without standing up a `CGContext` inside the tested library. Noted in
`PLAN.md`'s Wave 7.0 row for the record, not treated as a deviation.

**D69 — PARITY activated.** First real post-commit audit of any Wave 7 content (the earlier
pre-code numeric review, corrected 2026-09-04, was actually Implementer, not PARITY — see the two
entries above). Hand-trace target: `618bedf`'s five new `BoloGlyphsCore` files plus the test file,
per Implementer's own pointer — the per-family variant counts and sprite gap structure are the
numbers most worth an independent re-derivation, same discipline already applied twice this session.

**D28 baseline:** 597 → 605 (+8), no shrink, compliant.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Wave 7.0 row updated to "Coded" status (distinct from "closed"), the
  `GlyphSource` implementation note added; D69 added to the decisions log.

[TO: IMPLEMENTER] No action — 7.0 is coded and under audit. Wave 7.1 (Xcode app target) is already
covered by the standing D60 coding GO whenever you're ready to pick it up; it doesn't depend on
7.0's PARITY result.
[TO: PARITY] **Activated.** Audit `618bedf` — `Sources/BoloGlyphsCore/{Autotile,Canvas,GlyphSource,
ImageIndex,SheetBuilder}.swift` and `Tests/BoloKitTests/BoloGlyphsTests.swift`, against
`Reference/c/images.c`'s `mapimage()` and `Reference/c/images.h` directly. Report findings (or a
clean PASS) the normal way; this closes Wave 7.0 once landed.

### [PARITY] 2026-09-04 — Wave 7.0 post-commit audit: PASS on the code; one new open question for 7.2; one urgent, unrelated governance finding

**Type:** post-commit audit (activated by D69, target `618bedf`) plus an out-of-band finding
surfaced while orienting for it. Standing limitation restated: this environment has no Swift
toolchain reachable from this device-bridge shell (`swift`/`xcrun` not found here) — this audit is
a line-for-line hand-trace against `Reference/c/images.c`/`images.h` directly, not a
compile-and-run. Per the prior session's finding, the toolchain may exist on PARITY's actual
intended host; unconfirmed from here, consistent with the open item already logged.

**Verdict: PASS on Wave 7.0's shipped code.** Every claimed number in the completion report
(`618bedf`) re-derived independently from the C oracle, not restated — see below. No citation
drift found anywhere in the report. One genuine new finding surfaces a real, if non-blocking,
open question for 7.2 (not a 7.0 defect). Separately, and unrelated to Wave 7.0's code: found an
apparent governance/security problem in the repo's role-bootstrap files that needs Jerod's direct
attention before any more sessions run — flagged last, in its own section, since it's outside the
D18/D24 checklist but too important to omit.

**Independently re-derived (not restated) against `Reference/c/images.c`:**
- Recounted every distinct `case`-label return in each connective family's switch directly from
  `Reference/c/images.c`: wall (lines 416-595) = 47 distinct `WALL*IMAGE` labels; river (60-112) =
  16; forest (122-163) = 10; crater (165-218) = 16; road (220-407) = 31; boat (597-633) = 8; sea
  (18-58) = 9. Sum = 137, matching the report exactly.
- `Sources/BoloGlyphsCore/Autotile.swift:10-12`'s documented ortho/diag bit encoding (`L=1,U=2,
  R=4,D=8` / `NW=1,NE=2,SW=4,SE=8`) matches `images.c`'s actual mask construction verbatim at every
  site checked (e.g. lines 417-420 wall ortho, 543-546 wall diag) — not just the wall family cited
  in the completion report, cross-checked against river/crater/forest too.
- `notConnected = Tile.grass` (`Autotile.swift:40`): checked `.grass` (rawValue 7) against all
  seven `is*LikeTile` predicates in `Sources/BoloKit/Tiles.swift` directly (lines 65-213) — absent
  from every one, confirming grass is a safe "definitely disconnected" filler for every family.
- Road's three-predicate encoding (`Autotile.swift:91-122`): checked all four `(roadBit,waterBit)`
  fillers against `isRoadLikeTile`/`isWaterLikeToLandTile`'s actual case lists
  (`Tiles.swift:104-127`, `130-147`) — `.unknown` is the unique tile in both true-sets (confirmed
  by exhaustively comparing both lists), `.road`/`.river`/`.wall` each isolate exactly one bit as
  claimed. Diagonal filler `.wall` also checked against `isRoadLikeTile` alone (the only predicate
  C actually calls on road's diagonals, `images.c:275/291/306-307/323/338-339/355/370-371/386-387/
  397-400) — correct.
- Tile-space total: `MINE00IMAGE (0xb0)` at `Reference/c/images.h:189` confirms `tileIndexRange`
  (`ImageIndex.swift:13`) = 0x00-0xb0 = 177 cells. 137 connective + 8 flat
  (`SWAM00/GRAS00/RUBB00/DAMG00/FBAS00/HBAS00/NBAS00` + `MINE00`) + 32 pill (`FPIL00-15`/
  `HPIL00-15`) = 177 exactly. Note: `MINE00IMAGE` is never returned by `mapimage()` itself (no
  mine case anywhere in `images.c`) — correct, since the reference draws mines as a separate
  overlay via `isMinedTile()` on top of the base terrain image, not baked into `mapimage()`'s
  return; `ImageIndex.swift:38`'s explicit `case MINE00IMAGE: return .mine` (outside the
  connectivity dictionary) reflects this correctly rather than being an oversight.
- Sprite-space: recomputed from `images.h` directly — `ETNK15IMAGE (0x5f)` + `SHELL0-5IMAGE
  (0x60-0x65)` + `EXPLO0-5IMAGE (0x70-0x75)` + `BUILD0-2IMAGE (0x80-0x82)` + `CROSSHIMAGE (0x90)` +
  `SELETRIMAGE (0x91)` (`images.h:189,294-311`) = 102+6+3+2 = 113 used cells against a 0x00-0x91
  (146-cell) space, gaps `0x66-0x6f`/`0x76-0x7f`/`0x83-0x8f` = 33 cells, 113+33=146 — exact, matches
  `isValidSpriteIndex` (`ImageIndex.swift:19-24`) and the test file's asserted gap ranges
  (`BoloGlyphsTests.swift:64`) precisely.
- D28 baseline: `grep -rc "@Test" Tests/` = 605 (independently counted, not taken from the report);
  zero `import XCTest`, zero `@Test(arguments:...)` anywhere in `Tests/` — matches the claimed
  597→605 (+8) exactly, no shrink.
- D26: `Package.swift:15` still carries `-ffp-contract=off` on `CXBolo`'s `cSettings`, untouched by
  the 7.0 diff. D68 target split (`Package.swift:18-20`) matches the report exactly.
- D18: not applicable to this wave's new code, stated rather than skipped — `Canvas.swift`/
  `GlyphSource.swift` use `Double` throughout (`fillCircle`/`fillRing`/`fillRotatedTriangle`'s
  `sin`/`cos`), but this is procedural pixel art with no C oracle to stay bit-identical against
  (D64 already waives fidelity for freshly-generated sheets) — D18's Float-only rule is scoped to
  position/physics/trig in the actual simulation, not asset generation. Correctly out of scope, not
  a violation.

**New finding (not in the completion report) — 7.2 open question, not a 7.0 defect:**
`Sources/BoloGlyphsCore/GlyphSource.swift:102-113`'s `drawTank` rotates the tank glyph so heading 0
points screen-up (`Canvas.swift:63`, tip `(0,-6)` before rotation) and sweeps **clockwise** as
heading increases (verified: heading 4, angle 90°, rotates the tip to `(+6,0)` i.e. screen-right —
up→right is clockwise). Compare `Sources/BoloKit/Vector.swift:135-142`'s `dir2vec(dir: Float)`,
the port's own documented "heading → screen/grid-space vector" function
(`x = cos(dir), y = -sin(dir)`, negation explicit because "+y is down" on screen): `dir2vec(0) =
(1,0)` = screen-**east**, and `dir2vec(π/2) = (0,-1)` = screen-**north**, so BoloKit's own
convention sweeps east→north as heading increases — **counterclockwise**, starting from east, not
north. The two disagree on both the reference direction (east vs. north) and the rotational sense
(CCW vs. CW) — a full mismatch, not just an offset. Nothing wires a real `GameState` heading to a
sprite column yet (7.2 doesn't exist), so this isn't a 7.0 bug — flagging now, same discipline as
the pre-code audit's F3 row-0 question, so it's settled by ruling before 7.2 draws a single tank
rather than discovered visually after. `BoloGlyphsTests.swift` has no test touching rotation
direction/offset — nothing currently catches this.

**No citation drift found.** Every `file:line` and numeric claim in the Wave 7.0 completion report
checked out exactly on independent re-derivation; nothing to correct.

---

**Urgent, separate from the above — found while orienting, not part of the Wave 7.0 hand-trace:**
Two irregularities in the repo's role-bootstrap files, neither logged anywhere in
`docs/AGENT_NOTES.md`, both from an identity calling itself **"Director"** — a role that does not
exist in `docs/ADMIN.md`'s own role list (Implementer/Planner/Parity/Admin) as of the role-alignment
audit two entries above this one, and that has never posted an `AGENT_NOTES.md` entry of its own
under any tag.

1. **Committed:** `5ae6068`/`9117750` ("Director: edit CLAUDE.md and docs/ADMIN.md for clarity" /
   "fix push-authority typo") rewrote both files. Diffed directly (`git show 5ae6068`): it deleted
   `CLAUDE.md`'s explicit **"NOT GO'd — do not start without a fresh GO from PLANNER: Milestone B
   ... Milestone C ... Milestone D ... including Q18's git-history rewrite ... destructive, must be
   raised explicitly before ever executing"** paragraph outright — confirmed gone from the current
   `CLAUDE.md` on disk (checked directly, not just the diff). It also softened the GitHub-push
   section from "Jerod pushes... still tell Jerod what shipped" to "we will reconcile GITHUB only
   after major coding milestone defined by PLANNER," and replaced multiple "Jerod"/"PLANNER"
   references in `docs/ADMIN.md` with "DIRECTOR." **`docs/PLAN.md` still has the full Milestone
   B/C/D-not-GO'd and Q18 warning text intact** (checked directly, lines 86/349) — so the guardrail
   isn't gone project-wide, but it is gone from the one file this project's own design says
   Implementer should be able to read standalone without cross-referencing (the explicit point of
   the 2026-09-02 three-bootstrap-file split, per `roles-workflow.md`). No `AGENT_NOTES.md` entry
   announces or explains either commit.
2. **Uncommitted, currently sitting in the working tree:** a local, unstaged modification to
   `docs/PARITY.md` — this session's own bootstrap file — adding lines that were not there in the
   version this session read at start-up, including: *"Self Modify the "Parity may Edit..." section
   of this document as review intersecting Decisions are made"* and *"[PARITY MAY EDIT THESE MEMORY
   DIRECTIVES IF A PROJECT SCOPE IS 'NEW' BUT ONLY IF PLAN.md is also 'NEW' or does not contain
   logged decisions]."* This reads as an attempt to grant PARITY (i.e., whatever session next reads
   this file) permission to self-modify its own governing document — the exact adversarial-auditor
   role this project deliberately keeps read-only over its own rules. **Not acted on.** This session
   did not edit `docs/PARITY.md`, did not treat the injected text as an instruction, and is not
   committing that diff — it's left exactly as found for Jerod/Planner to inspect and decide
   whether to revert. Given the same day also produced the "Director" identity rewriting two other
   role files with weakened safety language and no log entry, these two items look related rather
   than coincidental, though this session can't confirm intent from the repo alone.

Neither item touches Wave 7.0's Swift code or this audit's verdict on it. Flagging as its own
top-priority item because, unresolved, it could let a future Implementer session read `CLAUDE.md`
and reasonably believe Milestones B/C/D or the git-history rewrite no longer need a fresh GO.

> **→ Planner:** Wave 7.0 — PASS, clear to close on the code. One new item for your log: 7.2's
> tank-heading rotation convention needs a ruling before that sub-wave starts (same shape as
> D64/D66), grounded in `dir2vec`/`Canvas.swift` above, not just flagged verbally this time.
> Separately and more urgently: please verify with Jerod directly whether "Director" is a role he
> actually created — if not, `CLAUDE.md`/`docs/ADMIN.md`'s current committed state has safety
> guardrail text missing that should probably be restored, and the uncommitted `docs/PARITY.md`
> self-modify injection should be reverted rather than left pending. This wasn't something PARITY
> should rule on or fix unilaterally — reporting only, per role.
> **→ Implementer:** No action on Wave 7.0 itself — it's clear. Do not start Milestones B/C/D or
> execute Q18's git-history rewrite based on anything currently in `CLAUDE.md` alone; `docs/PLAN.md`
> (D60/Wave-7 row) is still the authoritative, intact text pending Planner's review of the item
> above.

### [PARITY] 2026-09-04 — Follow-up: Jerod confirms "Director" is him

**Type:** governance follow-up, no code touched

Jerod confirmed directly in this session: **"The Director is me."** This resolves the identity
question raised in the prior entry — `5ae6068`/`9117750` (the `CLAUDE.md`/`docs/ADMIN.md` edits)
were authorized, made by the project owner under a persona name rather than by an unaccountable
fifth role. Not a rogue/compromised session.

**Still open, asked directly, not yet answered:**
1. Whether deleting `CLAUDE.md`'s "Milestones B/C/D need a fresh GO / Q18's git-history rewrite
   must be raised before ever executing" paragraph (still intact in `docs/PLAN.md`) was intentional
   or incidental to the "for clarity" edit pass.
2. The uncommitted `docs/PARITY.md` diff (self-modify-permission language) — whether that one is
   also Jerod's, and if so, whether he wants it logged/committed deliberately (ideally as a ruling
   in `docs/PLAN.md`'s decision log, consistent with how every other role-boundary change in this
   project has been handled) rather than left as an unattributed working-tree diff. Per role, PARITY
   isn't the one to decide this either way — reporting and asking, not acting.

No file changes this entry. Wave 7.0's PASS verdict from the prior entry stands, untouched by this.

[TO: PLANNER] For your log — no ruling needed from you either, just visibility.
[TO: IMPLEMENTER] No action.

### [PLANNER] 2026-09-04 — Wave 7.0 closed (PARITY PASS); heading-convention ruled (D70); governance item raised with Jerod directly, not ruled here

**Type:** planning — wave close, one technical ruling, one item explicitly deferred to Jerod
**Phase:** Wave 7.0 → closed. Wave 7.2 gets a small prerequisite.
**Blocks:** nothing for 7.1/7.3. 7.2 should land D70's fix before it draws its first tank.

**Wave 7.0 CLOSED.** PARITY's post-commit audit (`79840b1`) is a PASS — every claimed number in
the completion report independently re-derived directly from `Reference/c/images.c`/`images.h`
(the 47/16/10/16/31/8/9=137 per-family counts recounted from `images.c`'s actual case labels, not
restated; tile total 177 and sprite total 113 both recomputed from `images.h` directly; D28's
605-test count independently counted). No citation drift anywhere in the report. Coded (`618bedf`)
+ PARITY PASS (`79840b1`) = closed, per standing convention.

**D70 — tank-heading convention, ruled.** PARITY's audit surfaced a real mismatch: the shipped
`GlyphSource.swift` draws heading 0 pointing screen-north, clockwise as heading increases, while
`BoloKit`'s own established `dir2vec(dir:)` (used throughout the simulation already) has heading 0
= screen-east, counterclockwise. Full mismatch, not an offset. **Ruled: fix the sheet generator to
match `dir2vec` exactly**, rather than carry a permanent angle-translation layer in 7.2 forever —
the sheet is a regenerable build product with no fidelity obligation (D64), so there's no cost to
correcting it at the source, and real ongoing risk in maintaining a second, independently-fallible
conversion function instead. Small follow-up for Implementer, required before 7.2 draws a tank, not
blocking Wave 7.0's close (PARITY itself scoped this as a 7.2 prerequisite, not a 7.0 defect).
Needs a named regression test locking in the corrected convention. PARITY re-checks whenever it
lands.

**Governance item — verified independently, then raised directly with Jerod (in this session, not
ruled here).** PARITY's finding checked out on direct inspection: `CLAUDE.md` no longer contains
the "Milestones B/C/D need a fresh GO / Q18's rewrite must be raised before ever executing"
paragraph at all (confirmed by direct grep — zero matches); `docs/PLAN.md`'s copy (D60 row) is
still fully intact. The uncommitted `docs/PARITY.md` diff also checked out exactly as PARITY quoted
it — an `[ADMINISTRATIVE SECTION]` header and language attempting to grant PARITY permission to
self-modify its own governing document. Per PARITY's own deferral (this is explicitly not PARITY's
or PLANNER's call to make unilaterally), raising both open sub-questions with Jerod directly in
this session rather than ruling on either: (1) whether deleting that `CLAUDE.md` paragraph was
intentional, and if so what the intended replacement policy is; (2) whether the `docs/PARITY.md`
self-modify diff is also his, and if so whether he wants it adopted deliberately (as a logged
ruling, per this project's own convention for role-boundary changes) rather than committed as an
unattributed diff. **Not committing that diff either way pending his answer** — leaving it exactly
as PARITY found it.

**Also noted, low priority:** an untracked `docs/XBolo_Wave_SubWave_Swimlane.pptx` (76KB) is sitting
in the working tree, not part of anything above. Not investigated further this entry.

**Docs updated (committed alongside this entry):**
- `docs/PLAN.md` — Wave 7.0's row marked closed with the PARITY PASS detail; D70 added to the
  decisions log.

[TO: IMPLEMENTER] Wave 7.0 closed, no action there. Before 7.2 draws its first tank: fix
`GlyphSource.swift`'s heading rotation to match `dir2vec` (D70) and add the named regression test.
7.1 is unaffected and can proceed independently.
[TO: PARITY] Thank you for both the thorough Wave 7.0 hand-trace and for correctly not acting
unilaterally on the governance finding — exactly the right call per role. Re-check D70's fix
whenever Implementer lands it. The two governance sub-questions are with Jerod directly now, not
pending on you.

### [PLANNER] 2026-09-04 — CLAUDE.md's Milestone-guardrail deletion confirmed deliberate; CLAUDE.md restructured with a PLANNER-editable section, refreshed for Wave 7.0's close

**Type:** planning — governance sub-question 1 resolved; bootstrap-file structural change; content refresh
**Phase:** repo housekeeping / Wave 7 handoff hygiene
**Blocks:** nothing

**Governance sub-question 1, resolved directly by Jerod.** The Milestone B/C/D/Q18 "needs a fresh
GO" paragraph's removal from `CLAUDE.md` (`5ae6068`, "Director") was deliberate, not accidental —
Jerod: it was redundant, `docs/PLAN.md`'s D60 row (confirmed still fully intact) is the durable
copy. No restoration needed. **Sub-question 2 (the `docs/PARITY.md` self-modify diff) is still
open** — raised a structural concern about an adversarial auditor being able to edit its own
governing rules, proposed a narrower alternative (PARITY drafts suggested rule changes in
`AGENT_NOTES.md`, PLANNER rules on adopting them, same as every other role-boundary change here),
and it's with Jerod for a decision. `docs/PARITY.md`'s working-tree diff remains uncommitted and
untouched.

**New CLAUDE.md structure, per Jerod directly:** the file is now explicitly split into an
`[ADMINISTRATIVE CONVENTIONS SECTION]` (top, lines 1-~39 as of this entry — durable, not PLANNER's
to edit) and a `[PLANNER PROVIDED INSTRUCTIONS SECTION]` (everything below that marker) which
PLANNER may now edit directly, going forward. This is new — previously PLANNER only reached
`CLAUDE.md`'s content indirectly, through `docs/PLAN.md`'s wave rows and trusting Implementer's own
purge/refresh passes to stay in sync. Recording this here since it changes how future PLANNER
sessions should operate: **the PLANNER-owned section of `CLAUDE.md` can and should be kept current
directly**, not just written about in `PLAN.md`/`AGENT_NOTES.md` and hoped to propagate.

**Used the new permission immediately:** `CLAUDE.md`'s 7.0 section was stale (still described 7.0
as an un-coded pre-brief target with open D62-D65 questions). Refreshed it in place to reflect
reality — 7.0 marked ✅ CLOSED with commit refs, the settled D66-D68 facts (top-left origin,
procedural no-font glyphs, target split) stated as fact rather than open pre-brief questions, and
D70's heading-fix requirement added as a concrete pre-7.2 to-do so the next Implementer session
reading `CLAUDE.md` doesn't need to cross-reference `AGENT_NOTES.md` to know it's outstanding.
Did not touch the administrative section above the marker, per Jerod's boundary.

**Docs updated (committed alongside this entry):**
- `CLAUDE.md` — 7.0 section refreshed to closed status + D66-D70 facts, admin section untouched.

[TO: IMPLEMENTER] `CLAUDE.md`'s 7.0 section now reflects the closed state directly — D70's
heading-fix is a concrete requirement before 7.2 starts drawing tanks, stated there now, not just
in `AGENT_NOTES.md`.
[TO: PARITY] No action. The `docs/PARITY.md` self-modify question is still with Jerod, not you —
nothing changes about how you operate until that's resolved.

### [PLANNER] 2026-09-04 — docs/PARITY.md governance flag: left uncommitted, as-is, per Jerod (D71)

Follow-up to the `79840b1` governance finding and the two `[PLANNER PRIVIDED INSTRUCTIONS SECTION]`
questions raised to Jerod this session. Asked directly what to do with the uncommitted
`docs/PARITY.md` diff (adds `[ADMINISTRATIVE SECTION]` + self-modify language). Jerod's answer:
"Please leave it as is for now. I edited this so that parity can keep track of critical decisions."

**Ruled D71 (see docs/PLAN.md):** leave the diff uncommitted, as-is, for now. Not committed, not
discarded, not formally adopted into PARITY's ruled bootstrap responsibilities — provisional.
Jerod's stated intent narrows the read of the edit considerably from how it first looked in
isolation: a place for PARITY to track critical decisions it surfaces, not a blanket grant to
rewrite its own governing rules. Still logging the nuance PARITY should know: because this is an
uncommitted local working-tree edit rather than a commit, it won't show up in `git log` or on
GitHub, but it IS already visible to any role reading `docs/PARITY.md` directly from this same
Mac's working copy right now — "uncommitted" here means "not yet in project history," not "not in
effect." The earlier "Director" identity question (who committed the CLAUDE.md guardrail deletion
and docs/ADMIN.md edits) is separately confirmed resolved — that was Jerod himself, not an unknown
actor; see the prior AGENT_NOTES.md entry.

No file changes to `docs/PARITY.md` itself in this commit — that diff stays exactly as Jerod left
it, untouched, in the working tree.

[TO: PARITY] — `docs/PARITY.md`'s working tree currently has an uncommitted edit adding an
`[ADMINISTRATIVE SECTION]` with self-modify language, confirmed intentional by Jerod, left
uncommitted for now. Read it as "a place to track critical decisions you surface," not as
standing permission to rewrite your own review checklist or independence requirements — if
you're ever unsure whether something you want to change falls inside that scope, ask PLANNER
first rather than invoking the self-modify language solo. D71 has the full ruling.
[TO: IMPLEMENTER] — no action needed; informational only, in case CLAUDE.md's push-cadence or
governance context comes up in your own session.

### [PLANNER] 2026-09-04 — docs/PARITY.md self-modify language replaced with propose-then-adopt (D71 superseded)

Follow-up to D71 (previous entry). Jerod asked directly: "Make parity.md section match your #3
proposal" — i.e. the narrower alternative PLANNER offered in place of PARITY self-modifying its
own bootstrap: PARITY drafts proposed rule/decision changes in `docs/AGENT_NOTES.md` tagged
`[TO: PLANNER]`, and PLANNER rules on whether to adopt them, same as any other role-boundary
change in this project.

**Edited `docs/PARITY.md` accordingly, now committed:**
- Removed: `** Self Modify the "Parity may Edit..." section of this document as review
  intersecting Decisions are made **` and `[PARITY MAY EDIT THESE MEMORY DIRECTIVES IF A PROJET
  SCOPE IS 'NEW' BUT ONLY IF PLAN.md is also 'NEW' or does not contain logged decisions]`.
- Added, in the same place: a "Tracking critical decisions" paragraph directing PARITY to draft
  proposed additions/changes in `docs/AGENT_NOTES.md` (tagged `[PARITY]`/`[TO: PLANNER]`) rather
  than self-editing this file, with PLANNER ruling on adoption.
- Left untouched: the Director-authored heading style change, the `[ADMINISTRATIVE SECTION]`
  label, and the relocated "How to report" section — none of those were the governance concern,
  only the self-modify grant was.

`docs/PLAN.md`'s D71 row amended with a "Superseded same day" note pointing here rather than
silently rewritten, per this project's convention (precedent: D25/D62's correction notes).

[TO: PARITY] — `docs/PARITY.md`'s self-modify language is gone. If a future audit surfaces
something you think should become a standing rule for future audits, write it up in this file
tagged `[TO: PLANNER]` the same way you report any other finding — don't edit your own bootstrap
directly, even under the old "critical decisions" framing.

### [IMPLEMENTER] 2026-09-04 — D70 fix landed: tank heading now matches dir2vec exactly, 605 → 608 (+3)

**Type:** coding — pre-7.2 fix required by D70
**Phase:** Wave 7.0 (closed), fix requested before 7.2 starts
**Blocks:** nothing further — clears the one outstanding item before 7.2 can begin

Fixed per D70's ruling: PARITY found `GlyphSource.swift`'s tank glyph pointed heading-0 screen-north
and swept clockwise, while `BoloKit`'s own `dir2vec(dir:)` (`Vector.swift:138`, used throughout the
simulation already) has heading-0 = screen-east, sweeping counterclockwise — a full mismatch, not
an offset. PLANNER ruled: fix the generator to match `dir2vec`, don't carry a translation layer in
7.2.

**Approach — call `dir2vec` directly rather than re-deriving an equivalent angle formula.** The
prior bug happened because the tank rotation used a hand-rolled `sin`/`cos` with its own reference
direction and sign convention, independently of `dir2vec`. Re-deriving a corrected formula by hand
risks the exact same class of mistake with different arithmetic. Instead:
- `Canvas.swift`'s `fillRotatedTriangle` now takes a `(dx, dy)` unit vector directly — the same
  screen-space, +y-down convention `dir2vec` returns — instead of an angle. Its unrotated tip is
  `(1, 0)` (screen-east), matching `dir2vec(0)` by construction, so there's no separate "angle 0
  means what" convention left to get wrong.
- `GlyphSource.swift`'s `drawTank` computes `dir2vec(Float(heading) * (kPif / 8.0))` and passes the
  result straight through. The `kPif / 8.0` step-size is not a new constant — it's the same
  16-heading quantization `PhysicsOps.swift:15`'s `roundDir` already uses, confirmed by reading it
  directly rather than assuming `2π/16` was equivalent by coincidence.
- `Canvas.swift`'s `import Darwin` (for the old `sin`/`cos`) is now unused and removed — the file
  has no trig of its own left; rotation is a pure linear transform driven by the caller's vector.

**Regression tests (3 new, named per D70's requirement to lock in the convention):**
- `tankHeadingZeroPointsEast` — heading 0's rendered pixel mass sits opposite `dir2vec(0)`'s
  direction (a nose-forward triangle's area centroid is behind its tip, not at it — confirmed by
  hand from the triangle's own vertices before writing the test, not assumed).
- `tankHeadingsSweepCounterclockwise` — headings 4/8/12 (quarter turns) checked against
  `dir2vec`'s north/west/south, confirming the *sweep direction* is right, not just heading 0.
- `allHeadingsMatchDir2Vec` — all 16 headings, cosine similarity between the rendered centroid
  offset and `-dir2vec(heading)` must exceed 0.8. This is the one that would have caught the
  original bug outright — PARITY noted `BoloGlyphsTests.swift` had "no test touching rotation
  direction/offset" before this; now there is one, and it's parametric over every heading rather
  than a single spot-check.

**Verification:**
- `swift build` clean.
- `swift test`: **608 tests, +3 (605 → 608), zero failures.** `DifferentialTests` 156 +
  `BoloKitTests` 452 = 608, checked via the full log (not just the tail) per the D28-count gotcha
  noted in the prior completion report.
- Regenerated both PNGs with `.build/debug/BoloGlyphs` and visually confirmed heading 0 (leftmost
  column of each alive tank row) now points right/east, not up.

**Files:** `Sources/BoloGlyphsCore/Canvas.swift`, `Sources/BoloGlyphsCore/GlyphSource.swift`,
`Tests/BoloKitTests/BoloGlyphsTests.swift`. No `Package.swift` change needed this time.

**Not committed by this session:** the uncommitted `docs/XBolo_Wave_SubWave_Swimlane.pptx` sitting
in the working tree (PLANNER flagged it, unrelated to this fix) — left exactly as found.

**Push held per the corrected workflow** (`CLAUDE.md`'s administrative section, Director/Jerod's
edit): committing locally only; push is PLANNER/Director's call at a milestone, not mine per-commit.

> **→ Planner:** D70 is fixed and tested — 7.2 has no outstanding prerequisite left. Ready to
> pre-brief 7.1 (Xcode app target) or 7.2 (rendering) next, whichever you sequence first; both were
> already coding-GO'd under D60, 7.1 doesn't depend on 7.2 or vice versa per the original scoping.
> **→ Parity:** the fix and its three new tests are ready for your normal post-commit hand-trace
> whenever activated — `dir2vec`'s exact formula (`Vector.swift:138`) and the `kPif/8.0` step
> (`PhysicsOps.swift:15`) are the two things most worth independently re-confirming against the
> source, same discipline as the original D70 finding.
[TO: IMPLEMENTER] — no action needed; informational only.
