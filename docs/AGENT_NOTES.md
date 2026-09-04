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

### [PLANNER] 2026-09-04 — D70 fix reviewed and independently verified; PARITY activated; sequencing 7.1 next

Reviewed Implementer's D70 fix (`dd064dc`, "tank heading now matches dir2vec exactly, 608 tests
(+3)") against the actual D70 ruling and source, not the completion report's claims alone.

**Independently verified, all correct:**
- `Vector.swift:138-142`'s `dir2vec` and `PhysicsOps.swift:15`'s `roundDir`/`kPif/8.0` step read
  directly — the completion report's citations are accurate.
- `Canvas.swift`'s `fillRotatedTriangle(dx:dy:...)` now takes a unit vector, not an angle; its
  unrotated tip `(6, 0)` maps to pure `dx`-offset under the rotation formula used, i.e. heading 0
  points screen-east by construction — matches `dir2vec(0)`. Confirmed the rotation matrix itself
  (`x' = p.0*dx - p.1*dy`, `y' = p.0*dy + p.1*dx`) is the standard form for rotating by the angle
  whose (cos, sin) is (dx, dy), not just eyeballed.
- `GlyphSource.swift`'s `drawTank` computes `dir2vec(Float(heading) * (kPif / 8.0))` and passes the
  vector straight through — no independently-derived angle formula left to drift.
- Test count re-derived independently by grepping every test file directly (not trusting the
  commit message): `BoloKitTests` 452 + `DifferentialTests` 156 = **608**, exact match to the
  claimed 605→608 (+3).
- The three new named tests (`tankHeadingZeroPointsEast`, `tankHeadingsSweepCounterclockwise`,
  `allHeadingsMatchDir2Vec`) exist as described in `Tests/BoloKitTests/BoloGlyphsTests.swift` and
  correctly encode both the reference direction and the sweep sense.

`docs/PLAN.md`'s D71 -- correction, D70 row amended with this verification (not silently
rewritten).

**PARITY activated** for its normal post-commit hand-trace of `dd064dc`, per D70's own
requirement ("PARITY re-checks whenever Implementer lands the fix").

**Sequencing: pre-brief 7.1 next, not 7.2.** Implementer's handoff offered either "whichever you
sequence first," but `docs/PLAN.md`'s own Wave 7.1 row already settles this, not a fresh call:
"Unblocks every other sub-wave — nothing in 7.2/7.3 can run as an app without this existing
first." 7.1 (Xcode app target) is the one with no dependency in either direction; 7.2 needs an
actual window to render into. No new D-number — this is applying an already-recorded dependency,
not resolving an open question.

[TO: IMPLEMENTER] — Wave 7.0 fully closed out, D70 clear. Write Wave 7.1's pre-brief next (Xcode
app target — minimal window, placeholder icon, entitlements skeleton, per `docs/PLAN.md`'s Wave
7.1 row). 7.1's already coding-GO'd under D60; usual two-stage process applies — pre-brief here
first, PLANNER reviews it against `PLAN.md` before you start writing the app target itself.
[TO: PARITY] — `dd064dc` (D70's tank-heading fix) is ready for your normal post-commit hand-trace.
Worth independently re-confirming: `dir2vec`'s exact formula and sign convention
(`Vector.swift:138`), the `kPif/8.0` step matches `roundDir` (`PhysicsOps.swift:15`), and that
`fillRotatedTriangle`'s rotation matrix in `Canvas.swift` is actually the standard form (not just
plausible-looking) for rotating by the angle whose (cos, sin) is the passed-in (dx, dy).

### [PLANNER] 2026-09-04 — Heads-up: Jerod reviewing docs/PLANNER.md, may edit directly

**Type:** admin/process — advance notice, no action required
**Phase:** n/a — applies across whatever wave is active when this is read
**Blocks:** nothing

Jerod is reviewing `docs/PLANNER.md` and may edit it directly himself. If any role notices that
file change with no corresponding `[PLANNER]`/`[TO: X]` entry explaining it, that's expected —
not a sign of a rogue session, a lost commit, or drift to chase down. No other bootstrap
(`CLAUDE.md`, `docs/PARITY.md`, `docs/ADMIN.md`) is affected by this notice.

[TO: IMPLEMENTER] No action needed — don't treat an unexplained `docs/PLANNER.md` change as
something to investigate or flag.
[TO: PLANNER] Heads-up is for you too, in case a fresh Planner session sees its own bootstrap
changed out from under it.
[TO: PARITY] No action needed — this doesn't touch anything in your audit scope.

### [PARITY] 2026-09-04 — D70 fix post-commit audit: PASS; separate note on an uncommitted [PLANNER]-tagged entry found in the working tree

**Type:** post-commit audit, target `dd064dc`, activated by the entry two above this one.
Standing limitation restated: no Swift toolchain reachable from this device-bridge shell — hand
trace against source, not compile-and-run.

**Verdict: PASS, clean.** Independently re-derived, not restated from the completion report:
- `Sources/BoloGlyphsCore/GlyphSource.swift:113-118`'s `drawTank` computes
  `dir2vec(Float(heading) * (kPif / 8.0))` and passes the resulting `(x, y)` straight into
  `fillRotatedTriangle(dx:dy:)` — read directly, confirmed there is no independently-derived angle
  or trig call left anywhere in `GlyphSource.swift`/`Canvas.swift` (`Canvas.swift`'s `import Darwin`
  is gone, confirmed by grep). This is the strongest possible fix for the class of bug D70 found:
  structurally unable to drift from `dir2vec`, because it *is* `dir2vec`'s own output, not a
  parallel formula.
- `Canvas.swift:62-69`'s new `fillRotatedTriangle(dx:dy:...)`: `rotate(p) = (p.0*dx - p.1*dy + cx,
  p.0*dy + p.1*dx + cy)` is the standard rotation-by-(cosθ,sinθ) matrix, confirmed by hand, not
  eyeballed. Traced through concretely: unrotated tip `(6,0)`; at `(dx,dy) = dir2vec(0) = (1,0)`
  the tip stays at offset `(6,0)` = screen-east, matching `dir2vec(0)` by construction. At
  `(dx,dy) = dir2vec(π/2) = (0,-1)` (heading 4, `kPif/8*4 = π/2`), the tip rotates to offset
  `(0,-6)` = screen-north. East→north as heading 0→4 increases is counterclockwise — matches
  `dir2vec`'s own documented sweep (`Vector.swift:135-142`) exactly, independently re-derived by
  hand, not assumed from the commit message.
- `kPif/8.0` step (`GlyphSource.swift:114`) matches `PhysicsOps.swift:15`'s `roundDir` step exactly
  — same constant, checked directly.
- Test count re-derived independently: `grep -rc "@Test" Tests/` = **608**, zero `XCTest` imports,
  zero parameterized cases — matches the claimed 605→608 (+3) exactly.
- All three new tests (`tankHeadingZeroPointsEast`, `tankHeadingsSweepCounterclockwise`,
  `allHeadingsMatchDir2Vec`, `BoloGlyphsTests.swift:149-191`) read directly: the
  `centroidOffsetFromCenter` helper (lines 134-147) is a straightforward alpha-weighted pixel
  centroid, and all three tests' expected offsets match my own independent hand-trace above,
  including the "mass sits opposite the tip" framing (correct — a nose-forward triangle's alpha
  centroid sits behind its tip, toward the base). `allHeadingsMatchDir2Vec`'s parametric
  cosine-similarity check over all 16 headings is real coverage for exactly the bug class D70
  found; nothing like it existed before this fix.

**No citation drift.** Every file:line and formula claim in the completion report checked out.
D70 is closed — 7.2 has no outstanding tank-heading prerequisite.

---

**Separate note, not part of the D70 hand-trace (update mid-writing this entry):** while drafting
this, found a `[PLANNER]`-tagged entry ("Heads-up: Jerod reviewing docs/PLANNER.md, may edit
directly") sitting uncommitted in the working tree, appended after `d6f71ae`. Per this project's
own commit discipline, an uncommitted entry pre-authorizing a category of future unlogged changes
is the same pattern flagged twice already today (the `docs/PARITY.md` self-modify diff) — so this
was noted here rather than accepted silently. **Resolved before this commit landed:** it's now
committed as `9897428` ("Admin: log heads-up that Jerod may edit docs/PLANNER.md directly"), and
`docs/PLANNER.md` itself now shows as the actively-uncommitted file in the working tree, consistent
with that heads-up's own content. No open concern here — recording the sequence for the log rather
than deleting it, since it's a real example of the "flag first, let it resolve through the proper
channel" pattern working as intended, twice in one session now.

[TO: PLANNER] D70 fix — PASS, clean, closes the item. The docs/PLANNER.md heads-up note is
confirmed committed (`9897428`) — no outstanding action from that thread.
[TO: IMPLEMENTER] No action — D70 confirmed closed by PARITY too. Proceed with 7.1 pre-brief per
Planner's sequencing.

### [IMPLEMENTER] 2026-09-04 — Wave 7.1 pre-brief: Xcode app target, no Swift written yet

**Type:** pre-brief only, per `CLAUDE.md`'s "pre-brief before coding" rule
**Phase:** Wave 7.1 (Xcode app target), pre-code
**Blocks:** Wave 7.1 coding start — needs PLANNER's review of the two flagged items below, same
two-stage gate as every prior sub-wave

Picking up Wave 7.1 per PLANNER's sequencing (`d6f71ae`): "7.1 is the one with no dependency in
either direction; 7.2 needs an actual window to render into." Read `docs/PLAN.md`'s Wave 7.1 row
and `CLAUDE.md`'s 7.1 bullet directly before scoping — both are one-paragraph scope statements
("create the actual macOS app target/bundle... minimal window, placeholder app icon, entitlements
skeleton"), nothing more specific exists to cross-reference.

**Verified directly before proposing an approach, not assumed:**
- `Package.swift`: `platforms: [.macOS(.v26)]`; targets are `BoloKit`, `CXBolo`, `BoloNet`,
  `BoloGlyphsCore`, `BoloGlyphs` (executable), `BoloKitTests`, `DifferentialTests`. No app target.
- `XcodeListTargets` → zero targets right now. `XcodeListSchemes` → one synthesized scheme
  (`BoloKit`, the SPM package itself), no app scheme. Confirms the "none exists yet" claim as
  literally true in this session, not stale doc text.
- `XcodeListTemplates` → `com.apple.dt.unit.cocoaApplication` exists: a native macOS "App"
  template (SwiftUI lifecycle), category Application, platform macosx. This is the tool-supported
  path for "the actual macOS app shell wrapping the SPM package" — `XcodeNewTarget` can instantiate
  it and add the local package as a dependency directly, rather than hand-rolling a `.xcodeproj` or
  stretching a bare SPM executable to carry a real Info.plist/entitlements/icon the way
  `AddInfoPlist`/`AddEntitlement` expect to operate on an actual Xcode target.
- No `.entitlements` file exists anywhere in the repo outside `Reference/c`, and `Reference/c`
  itself never had one either (pre-sandbox-era app, checked its `Info.plist` directly — no
  entitlement-related keys) — no fidelity target to size the entitlements skeleton against.
- `Sources/BoloGlyphs`'s generated `Tiles.png`/`Sprites.png` are confirmed **not** committed (Wave
  7.0's own completion report says so explicitly) — 7.1 has to decide how the app actually gets
  them, not just declare a window.

**Proposed approach:**
1. **New Xcode target, `BoloApp`**, via `XcodeNewTarget` with the `com.apple.dt.unit.cocoaApplication`
   template. Add `BoloKit` as a local package dependency now; `BoloNet` once 7.3 needs it.
   `BoloGlyphsCore`/`BoloGlyphs` stay build-time-only tools (see item 4), not linked into the app.
2. **Minimal window, literally minimal:** one SwiftUI `WindowGroup`, a placeholder `Text` body —
   7.2 replaces it. No menus/prefs/HUD, per D60's v1 scope.
3. **Entitlements skeleton, sized to v1, not to the eventual multiplayer app:** an empty/default
   entitlements file with **no network client entitlement yet** — D60/7.3 explicitly exclude all
   networking from this slice, so provisioning for it now would be scope no sub-wave has asked for.
   `AddInfoPlist`/`AddEntitlement` to attach both files, not hand-written XML.
4. **Placeholder icon — generated, not copied.** `Reference/c`'s `XBolo.icns` is Stuart Cheshire's
   original copyrighted art per the licensing note already governing Wave 7.0 — off-limits as a
   *source* even for a placeholder, same restriction as the sprite/tile sheets. Proposing a trivial
   procedurally-drawn glyph, reusing `BoloGlyphsCore`'s existing pixel primitives scaled up, as the
   placeholder `AppIcon` — not a blank icon and not anything traced from the reference.

**Two items flagged for PLANNER's review before I touch `XcodeNewTarget` or any other mutating
tool — not asking permission for the parts D60 already GO'd me on, same convention as Wave 7.0's
flagged deviations:**
- **Sheet delivery.** Proposing a Run Script build phase on `BoloApp` that invokes `BoloGlyphs`
  directly to regenerate `Tiles.png`/`Sprites.png` into the app target's resources at build time,
  rather than committing generated PNGs to git. Consistent with D64 ("regenerable build product, no
  fidelity obligation") and avoids a second, hand-synced copy of build output sitting in version
  control. This is a build-process choice `PLAN.md`'s one-line row doesn't settle either way.
- **Target name/dependency set.** `BoloApp` depending on `BoloKit` now and `BoloNet` later (not
  now) — flagging the specific name and staged-dependency choice in case PLANNER or a later wave
  expects something else.

**Verification plan once coding starts:**
- `XcodeListTargets`/`XcodeListSchemes` should show `BoloApp` after `XcodeNewTarget` + dependency
  wiring; `BuildProject` should produce a runnable `.app`.
- Launch and confirm one window opens — the "minimal window" bar, met before 7.2 exists to fill it.
- `swift build`/`swift test` from the command line must still succeed unmodified at 608 tests — the
  app target is additive, must not perturb the existing SPM package graph or D28's baseline.
- Confirm via direct read that no `Reference/c` icon/asset bytes were copied into the new target's
  asset catalog.

No Swift/Xcode-project changes made this entry — pre-brief only.

> **→ Planner:** two items above need your read before I start: the sheet-delivery build-script
> approach, and the `BoloApp` name/staged-dependency choice. Everything else in D60's 7.1 scope
> (native Cocoa App target via `XcodeNewTarget`, minimal window, generated-not-copied icon,
> v1-sized empty entitlements) is proceeding as briefed unless you say otherwise.
> **→ Parity:** nothing to audit yet — no Xcode project mutation or Swift change made this entry.

### [PLANNER] 2026-09-04 — D70 fully closed (PARITY PASS); Wave 7.1 pre-brief reviewed, coding GO with two corrections (D72/D73); filing correction on D70/D71

**PARITY's D70 fix audit (`c4da9e0`): PASS, clean, no citation drift.** D70 is now fully closed —
Wave 7.2 has no outstanding tank-heading prerequisite. Also noted PARITY's own separate finding
(the `docs/PLANNER.md` heads-up entry mis-tagged `[PLANNER]` sitting uncommitted, since resolved
via Admin's `9897428` commit) — no action needed on that thread, confirmed already resolved.

**Filing correction (on me, not Implementer or PARITY):** while closing the loop on D70 I found
that my own prior verification note ("D70 fix landed and independently verified...") had been
appended to **D71's** `docs/PLAN.md` row instead of D70's, from a bad anchor match in an earlier
edit. Moved it to D70's row where it belongs, added the PARITY PASS confirmation there too, and
left a one-line correction note in place rather than silently fixing it — same convention this
project already applies to Implementer/PARITY's own citation errors (precedent: D25, D62).

**Reviewed Implementer's Wave 7.1 pre-brief (`4326d77`).** Verified directly before ruling: D21's
actual text ("name the primary application `Bolo 2026`"), README.md's confirming line, and
Wave 7.3's `docs/PLAN.md` row ("single-process, no networking wired in"). Two corrections against
the two flagged items, logged as **D72** and **D73**:
- **D72 (sheet delivery) — approved as proposed.** Build-time Run Script regenerating
  `Tiles.png`/`Sprites.png` via the built `BoloGlyphs` executable, not committed to git — consistent
  with D64. Required: `BoloGlyphs` as an explicit target dependency (build-order correctness) and
  declared input/output file lists (incremental-build correctness).
- **D73 (name/dependencies) — corrected, not approved as proposed.** `BoloApp` is a fresh name
  where one was already ruled — D21 says `Bolo 2026`, confirmed by README.md's own text; use that,
  not a new name invented at this pre-brief. And `BoloNet` isn't a 7.3 dependency at all — 7.3 is
  explicitly single-process/no-networking (its own PLAN.md row), Host/Join wiring is Milestone B's
  job, not yet GO'd. `Bolo 2026` depends on `BoloKit` only through the whole v1 slice.

**Coding GO issued on Wave 7.1's pre-brief with these two corrections** — everything else
(native Cocoa App template via `XcodeNewTarget`, minimal `WindowGroup`, generated-not-copied
placeholder icon, v1-sized empty entitlements) proceeds as briefed. `docs/PLAN.md`'s Wave 7.1 row
and `CLAUDE.md`'s 7.1 bullet (Planner's editable section) both updated to reflect D72/D73.

**Not touched:** the still-uncommitted `docs/PLANNER.md` working-tree edit — confirmed to be
Jerod's own direct edit in progress (per the `9897428` heads-up), not mine to commit or comment on
further; left exactly as found.

[TO: IMPLEMENTER] Coding GO for Wave 7.1, with the D72/D73 corrections above: target/product name
is `Bolo 2026`, not `BoloApp`; no `BoloNet` dependency at all for 7.1-7.3 (Milestone B territory
only); sheet-generation Run Script approach approved with the build-order/incremental-build
requirements noted. Proceed with `XcodeNewTarget` and the rest of the pre-brief as written.
[TO: PARITY] D70 fully closed on your PASS — nothing further needed there. Nothing to audit yet
for 7.1 (no Swift/Xcode-project changes landed).

### [PLANNER] 2026-09-04 — docs/PLANNER.md's pending edit now committed (`6412a67`)

Jerod asked directly for the working-tree edit to `docs/PLANNER.md` (flagged by PARITY, heads-up
logged in `9897428`) to be committed. Reviewed it first, same scrutiny given to every bootstrap
file this session — no self-modify grants or permission changes, just the `[ADMINISTRATIVE
SECTION]` header (matching `CLAUDE.md`/`docs/PARITY.md`'s convention), partner-bootstrap pointers,
and wording clarifications. Committed as `6412a67`, attributed to Director (Jerod) in the commit
message, not claimed as Planner's own authorship.

[TO: IMPLEMENTER] No action needed.
[TO: PARITY] The `docs/PLANNER.md` change you flagged is now committed — no longer just a
working-tree edit. Nothing in it needs audit (no code/behavior change).

### [PLANNER] 2026-09-04 — Heads-up from Jerod: Xcode crashed twice during Wave 7.1 work, extra scrutiny required

**Type:** process/risk flag, not a ruling — no D-number
**Phase:** Wave 7.1 (Xcode app target), mid-coding
**Blocks:** nothing yet — no completion report or commit has landed for 7.1's actual coding as of
this entry (`git log` shows only the pre-brief, `4326d77`, and the D72/D73 coding GO, `2c86747`;
working tree is clean). This is a standing caution for whatever lands next, not a response to
something already broken.

Jerod reported Xcode crashed twice while Implementer was working on Wave 7.1. He doesn't yet know
if/what it affected. Logging this now so it isn't lost before Implementer's next report, and so
whichever session (this one or a fresh Planner instance) reviews that report knows to look harder
than usual.

**Why this matters specifically for 7.1:** this sub-wave is the first one in the project doing real
Xcode-project mutation (`XcodeNewTarget`, build phases, entitlements, asset catalog) rather than
pure SPM/Swift-file work — exactly the kind of state a crash can leave inconsistent: a half-written
`.pbxproj` (duplicate or orphaned target/build-phase entries), a target that "exists" per
`XcodeListTargets` but doesn't actually build clean, an asset catalog with partial writes, or an
entitlements/Info.plist file left in a bad intermediate state. None of this would necessarily show
up in a diff read the way a Swift logic bug would — it can look fine on a text read and still fail
to build, or build but not match what the completion report claims.

[TO: IMPLEMENTER] Before writing Wave 7.1's completion report, explicitly verify project integrity,
not just that the feature works: a clean build from scratch (not an incremental one that might be
riding on stale derived data from before either crash), `XcodeListTargets`/`XcodeListSchemes`
showing exactly the expected target/scheme with no duplicates, a direct read of the `.pbxproj` (or
`BuildProject` diagnostics) for anything that looks malformed or doubled-up, and `swift build`/
`swift test` from the command line still passing at the expected count unmodified — same standard
already required, just called out explicitly given the crashes. If anything looks off, say so in
the report rather than smoothing over it — a "here's what I checked and it's clean" note is exactly
as valuable as a real finding would be.
[TO: PARITY] When 7.1's audit is activated, give the Xcode-project state itself (not just Swift
behavior) real scrutiny this time — duplicate/orphaned `.pbxproj` entries, a target that lists but
doesn't build, mismatched entitlements — in addition to the normal hand-trace. Xcode crashed twice
during this sub-wave's work per Jerod; nothing has confirmed impact yet either way.

### [PLANNER] 2026-09-04 — Xcode 27.1 beta reinstall attempted, hit an error; toolchain instability continues

Jerod attempted to reinstall Xcode 27.1 beta on the Implementer host in response to the two crashes
noted in the previous entry — initially reported as rev 6 over rev 6, corrected moments later: the
installed version was actually **rev 5**, and the reinstall itself **hit an error**. Logging for
the record, not changing the standing guidance, but this raises rather than lowers the caution
level: the toolchain is confirmed unstable right now (two crashes, plus a failed reinstall attempt
that also surfaced a version-tracking discrepancy), and there's no confirmation yet that Implementer's
host is in a good state to resume work at all. A reinstall, once it succeeds, addresses the
toolchain going forward — it does not retroactively validate anything already written to the repo
before or during the crashes.

**The integrity checks already requested of Implementer (clean build, no duplicate targets/schemes,
`.pbxproj` sanity, full test suite unmodified) still apply in full once 7.1 coding actually resumes
— if anything more firmly now.** Nothing further should be assumed complete or trusted from that
host until it's confirmed stable again.

[TO: IMPLEMENTER] No new instruction beyond the prior entry — once your host is confirmed stable
and back up, the same integrity checks apply before you report Wave 7.1 complete. If you have any
doubt the crashes or a failed reinstall affected in-progress work, say so explicitly rather than
proceeding as if nothing happened.

### [IMPLEMENTER] 2026-09-04 — Claude plugin for Xcode reinstalled, host state re-checked before resuming Wave 7.1

**Type:** resume-after-instability check, not a ruling — no D-number
**Phase:** Wave 7.1 (Xcode app target), pre-code (resuming)
**Blocks:** nothing — this is the integrity check PLANNER's prior two entries asked for before any
7.1 coding lands, done here before touching `XcodeNewTarget`.

Jerod deleted and reinstalled the Anthropic Claude plugin for Xcode (the integration this agent
runs through) — a different remedy than the Xcode 27.1 beta reinstall attempt logged previously,
which PLANNER's last entry noted had itself hit an error. Per that entry's standing instruction
("say so explicitly rather than proceeding as if nothing happened"), checked the actual project
state directly before writing any Swift or touching any mutating tool:

- `XcodeListTargets` → zero targets. `XcodeListSchemes` → one scheme, `BoloKit` (the synthesized
  SPM package scheme), active. Identical to the pre-brief's own "none exists yet" baseline
  (`docs/AGENT_NOTES.md`'s Wave 7.1 pre-brief entry, verified same way).
- Conclusion: the two Xcode crashes reported mid-Wave-7.1-work never got as far as a successful
  `XcodeNewTarget` call — there is no half-written target, no orphaned build phase, no partial
  asset catalog to clean up. The crashes interrupted *before* any project-mutating tool call
  landed, not during one. Nothing to repair; resuming from the same starting point the D72/D73
  coding GO left off at.
- `git log`/`git status` also consistent with this: last commits are PLANNER's own log entries
  (`f5251ad`, `cab74f5`), working tree clean apart from new untracked docs artifacts unrelated to
  7.1 (`docs/XBolo_Role_Deliverable_Matrix.xlsx`, `.pptx`, `docs/notes/*.numbers` — Director's own
  files, not touched).

Proceeding with Wave 7.1 coding now per the D72/D73 GO already on record: `Bolo 2026` target via
`XcodeNewTarget` (`com.apple.dt.unit.cocoaApplication`), `BoloKit`-only dependency, minimal
`WindowGroup`, v1-sized entitlements, generated-not-copied placeholder icon, Run Script sheet
generation with `BoloGlyphs` as an explicit dependency and declared input/output file lists. Will
still run the full integrity check (clean build, no duplicate targets/schemes, `.pbxproj` sanity,
608-test baseline unmodified, no `Reference/c` asset bytes copied) before writing the completion
report, per PLANNER's standing caution — this entry confirms the *starting* state is clean, it
doesn't substitute for that closing check.

[TO: PLANNER] Toolchain-instability flag from your last two entries: starting state independently
verified clean (zero targets/one SPM scheme, matching pre-brief baseline exactly) — the crashes
didn't leave anything behind to repair. Proceeding with 7.1 coding; closing integrity check still
to come before I call it done.
[TO: PARITY] Nothing to audit yet — no Xcode-project mutation or Swift change made this entry,
pre-coding check only.

### [IMPLEMENTER] 2026-09-04 — Wave 7.1 complete: `Bolo 2026` app target builds, runs, links `BoloKit`, generates sheets at build time (`426c6a4`)

**Type:** completion report
**Phase:** Wave 7.1 (Xcode app target) — coded, built, launched, committed
**Blocks:** nothing further from me. 7.2 and 7.3 now have a window to render into. Not calling this
wave "done" — that's PLANNER's GO, and there are four flagged items below that want a read first.

**What landed (`426c6a4`):** `Bolo 2026.xcodeproj` at the repo root, one native Cocoa App target
(SwiftUI lifecycle, macOS-only), `BoloKit` as its only package dependency, D72's build-time sheet
generation, and a generated placeholder AppIcon. Verified end-to-end, not just built: the app
launches, opens a window, and that window reports `BoloKit linked: 50 ticks/sec` (a real read of
`Physics.swift`'s `ticksPerSec`) and `Tiles.png`/`Sprites.png in bundle: yes` for both sheets.

**Deviation from the pre-brief's literal text — `XcodeNewProject`, not `XcodeNewTarget`.** The
pre-brief (and D72/D73's approval text) both say "native Cocoa App template via `XcodeNewTarget`".
That tool cannot do this job: it "adds a new target to a project in the current Xcode workspace,"
and there was no `.xcodeproj` to add one to — the only workspace in the repo is the SPM-synthesized
`.swiftpm/xcode/package.xcworkspace`, and you cannot add an app target to a Swift package. Used
`XcodeNewProject` with the *same* template identifier the pre-brief named
(`com.apple.dt.unit.cocoaApplication`, which exists as both a project and a target template) and
the same product name. Reporting it because the GO'd text names a specific tool, but I read this as
mechanical rather than a scope or architecture change: same template, same target, same everything
the pre-brief described. The pre-brief's own "No `.xcodeproj` exists yet" already implied one had
to be created.

**Necessary change the pre-brief didn't anticipate: `Package.swift` had no `products:` block at
all.** Only `targets:`. SPM exposes nothing to an external consumer without declared products, so
the Xcode project literally could not depend on `BoloKit` until this was added. Added exactly two,
no more: `.library(BoloKit)` and `.executable(BoloGlyphs)` (the latter is what the Run Script
invokes). Deliberately did **not** export `BoloNet` — D73 is explicit that v1 is single-process and
`BoloNet` is Milestone B's concern. This is additive to the package graph; `swift build`/`swift
test` are unaffected (counts below).

**Two `.pbxproj` edits made by hand, flagged because the MCP tooling says not to.** There is no
Xcode MCP tool for adding a Swift package dependency or a Run Script build phase — I checked; the
available project-mutating tools are `AddInfoPlist`, `AddEntitlement`, `UpdateTargetBuildSetting`,
and the target/project template tools, all of which carry a "do NOT modify `project.pbxproj`
directly" warning. That warning is scoped to things those tools *can* do; for package references
and script phases there is no tool, so a direct edit was the only path. Kept it minimal and
verified the result rather than trusting the edit: `plutil -lint` passes, and a structural dump
shows exactly 21 objects with exactly one `PBXNativeTarget`, one `PBXShellScriptBuildPhase`, one
`PBXTargetDependency`, one `XCLocalSwiftPackageReference`, two `XCSwiftPackageProductDependency` —
no duplicates, no orphans.

**D72 implemented as specified, both required properties present:**
- `BoloGlyphs` is wired as an explicit `PBXTargetDependency` (via `productRef`), so it always
  builds before the script runs — confirmed empirically by the from-scratch build below, which
  produced both sheets with no manual pre-step.
- The phase declares `inputPaths` (`$(BUILT_PRODUCTS_DIR)/BoloGlyphs`) and `outputPaths` (both
  PNGs) for incremental-build correctness. `alwaysOutOfDate = 0`. Also relevant:
  `ENABLE_USER_SCRIPT_SANDBOXING = YES` is on, and the declared inputs/outputs are what make the
  phase legal under it — this would fail silently-ish without them.
- Sheets are written into the built app's Resources and are **not** committed. Confirmed
  `git status` shows no `Tiles.png`/`Sprites.png`.

**Entitlements — reporting a judgment call, since the pre-brief asked for a file and I made none.**
The pre-brief proposed "an empty/default entitlements file with no network client entitlement."
Xcode 26's template doesn't work that way any more: it ships **no** `.entitlements` file and
instead synthesizes entitlements from build settings, and the template's own defaults are already
exactly the state the pre-brief was asking for — `ENABLE_APP_SANDBOX = YES`,
`ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO`, `ENABLE_INCOMING_NETWORK_CONNECTIONS = NO`. Verified on
the signed product rather than assumed: `codesign -d --entitlements -` on the built `.app` returns
`com.apple.security.app-sandbox`, `com.apple.security.files.user-selected.read-only`, and
`com.apple.security.get-task-allow` (the debug-build one) — **and no network entitlement of any
kind**. Creating an empty `.entitlements` file alongside this would have been an inert extra file,
so I left it. Flagging in case PLANNER wants the literal file anyway.

**Placeholder icon — generated, not copied, as ruled.** `Sources/BoloGlyphsCore/AppIcon.swift`
composites two of the game's *own* 16×16 glyphs (grass via `tileGlyphRole(for: GRAS00IMAGE)` so it
tracks the sheet palette rather than a hardcoded colour, plus
`renderGlyph(.tank(heading: 0, ...))`) and nearest-neighbour upscales. Every macOS slot size
(16/32/64/128/256/512/1024) is a whole multiple of 16, so it's exact pixel replication — no
resampling blur on pixel art. Regenerate with `BoloGlyphs icon <dir>`.
- Heading 0 renders pointing **east**, consistent with `dir2vec` per D70's ruling — not an
  independent icon-only convention.
- Unlike the sheets, the icon PNGs **are** committed: `actool` compiles the asset catalog during
  the Resources phase, so they must exist before the build starts. That's a deliberate difference
  from D72, not an oversight.
- **Licensing check, done by checksum not by eye:** md5'd every `.icns`/`.png`/`.tiff`/`.jpg` in
  `Reference/c` against all seven generated icons — zero overlap. No Stuart Cheshire asset bytes
  entered this repo.

**Integrity checks PLANNER's two Xcode-crash entries asked for — all run, all clean:**
- **Clean build from scratch, not incremental.** Deleted the project's entire DerivedData tree
  (note: `~/Library/Developer/Xcode/DerivedData` is a symlink to `/Volumes/mingus/...` on this
  host) and rebuilt from nothing. Succeeded, and regenerated both sheets with fresh timestamps —
  which is also the real proof the `BoloGlyphs` build-order dependency is correct.
- **No duplicate/orphaned project state.** `XcodeListTargets` → exactly one target, `Bolo 2026`,
  product type application. `XcodeListSchemes` → exactly one scheme, `Bolo 2026`, active. Plus the
  `plutil`/object-count dump described above.
- **One thing that looked wrong and wasn't, reported rather than smoothed over:** immediately after
  my first hand-edit to `.pbxproj`, `XcodeListSchemes` returned **zero schemes** and `BuildProject`
  failed with "No active scheme is selected." That is exactly the kind of half-broken state
  PLANNER's caution was written about, so I did not work around it — I validated the file on disk
  (`plutil -lint`: OK) and then closed and reopened the workspace. Scheme came back, build
  succeeded. Diagnosis: stale in-memory workspace state in Xcode after an on-disk project edit, not
  file corruption. Worth knowing for anyone hand-editing `.pbxproj` later in Wave 7.
- **Test baseline (D28): 608 → 612, no coverage removed.** Before: 156 (`DifferentialTests`) + 452
  (`BoloKitTests`) = 608, matching the recorded baseline exactly. After: 156 + 456 = 612. The +4 are
  new icon regression tests (exact-multiple slot sizes, full opacity at every size, upscale is
  exact pixel replication, determinism). Zero failures, `swift build` and `swift test` both clean
  from the command line.
- **No crash reports** generated by the launched app; it ran, held a window, and quit cleanly.

**Unruled choices I had to make to finish — none of these were settled anywhere I could find, so
they are flagged rather than presented as decided:**
1. **Bundle identifier prefix: `com.cosmicceo`** (→ `com.cosmicceo.Bolo-2026`). No convention
   exists anywhere in the repo; grepped README, docs, and `Reference/c`'s own `Info.plist` (which
   just uses `$(PRODUCT_BUNDLE_IDENTIFIER)`). Took it from the GitHub org `CosmicCEO`. Trivial to
   change now, much less so after any signing/distribution work.
2. **Project lives at `Bolo 2026/` off the repo root**, so the SPM package root is its parent and
   the local package reference is `relativePath = ".."`. SPM ignores the directory (targets are
   explicitly under `Sources/`), and `swift build`/`swift test` are unaffected. An `App/`
   subdirectory would also have worked.
3. **`MACOSX_DEPLOYMENT_TARGET = 27.0`** (template default) while `Package.swift` declares
   `.macOS(.v26)`. Compatible — the app floor is higher than the package's — but deliberately left
   at the template default rather than silently aligned to 26.0, since the v26 floor looks like an
   actual project decision I shouldn't move unilaterally.
4. **The scheme is Xcode-autocreated, not a shared `.xcscheme` file on disk.** It works and
   regenerates on clone, but a checked-in shared scheme would be more reproducible for CI or for
   PARITY auditing on another machine. Didn't add unrequested files.

**Not touched:** the three untracked Director artifacts in `docs/` (`.xlsx`, `.pptx`, `.numbers`) —
left exactly as found, same as the previous entry.

[TO: PLANNER] Wave 7.1 coded and committed (`426c6a4`), all your post-crash integrity checks run
and clean (details above). Four things want your read before you GO the close: (1) the
`XcodeNewProject`-vs-`XcodeNewTarget` deviation — forced, same template, but your GO text names the
other tool; (2) the `Package.swift` `products:` addition, which was a hard prerequisite nobody had
spotted; (3) entitlements delivered as build settings with no `.entitlements` file, verified
correct on the signed product — say if you want the literal file anyway; (4) the four unruled
choices above, of which the bundle identifier is the one that gets expensive to change later.
[TO: PARITY] Now activatable, and per PLANNER's standing note the Xcode project state itself wants
scrutiny, not just Swift behaviour. Specific things to hit: the two hand-written `.pbxproj`
sections (`XCLocalSwiftPackageReference` / `XCSwiftPackageProductDependency` /
`PBXTargetDependency` / `PBXShellScriptBuildPhase`) — I verified structure with `plutil` and object
counts, not against a reference project, so a second opinion on the encoding is worth having; the
Run Script's behaviour under `ENABLE_USER_SCRIPT_SANDBOXING = YES`; and whether the icon really is
free of `Reference/c` bytes (I checked by md5 across all its image files — re-run it). Test count
608 → 612, no removals.

### [PLANNER] 2026-09-04 — Wave 7.1 completion report reviewed: deviations accepted (D74), two required follow-ups (D75/D76), bundle ID to Jerod (Q27), PARITY activated

**Type:** review + rulings + PARITY activation
**Phase:** Wave 7.1 (Xcode app target) — coded and committed (`426c6a4`), **not closed**
**Blocks:** Wave 7.1's close, pending the D75/D76 follow-ups plus a PARITY PASS. Wave 7.2's pre-brief
is unblocked and GO'd below — it doesn't wait on either.

Reviewed Implementer's 7.1 completion report against `docs/PLAN.md`'s decisions, D72/D73's coding-GO
text, and the two standing Xcode-instability cautions. **The report is the standard I want on this
kind of wave:** every deviation from the GO'd text was surfaced with its reason rather than
smoothed over, the entitlements and licensing claims were verified on the *built product*
(`codesign -d --entitlements -`, md5 across every image file in `Reference/c`) rather than by
inspection, and the one moment that looked like the crash damage I'd warned about — zero schemes,
"No active scheme is selected" — was investigated and diagnosed rather than worked around. Two
substantive follow-ups below, neither a defect in what shipped.

**D74 — all four flagged deviations accepted as delivered, no rework.** `XcodeNewProject` instead of
D73's named `XcodeNewTarget` is mechanical (same template identifier, same product name; you cannot
add an app target to an SPM-synthesized workspace, and the pre-brief's own "no `.xcodeproj` exists
yet" already implied one had to be created) — **D73's row is corrected, not the work.** The
`Package.swift` `products:` addition was a hard prerequisite nobody had spotted, and holding
`BoloNet` out of it is D73's intent, not an oversight — recorded in D74 explicitly so a future
session doesn't "fix" its absence. Entitlements as template-synthesized build settings with no
`.entitlements` file: accepted, and I do **not** want the literal file — the pre-brief asked for a
state, the state is verified on the signed product, and an empty file next to authoritative build
settings is a decoy. Milestone B's `ENABLE_OUTGOING_NETWORK_CONNECTIONS` flip is recorded in D74 so
it isn't rediscovered. The two hand-edited `.pbxproj` sections were the only available path (no MCP
tool exists for package references or script phases; the warning is scoped to what those tools *can*
do), and the `plutil`-plus-object-count verification is adequate for my GO — the encoding second
opinion is PARITY's, and I've asked for it. Project location at `Bolo 2026/` ratified as-is.

**D75 — `MACOSX_DEPLOYMENT_TARGET` must come down from the template's 27.0 to 26.0.** This is the one
place the report's "left at the template default rather than silently aligned" instinct was right to
flag and the answer is to change it: D16 ruled macOS 26+ as the project's floor, and a template
default quietly making the shipped app 27-only while every package target advertises 26 is drift, not
compatibility. Nothing in a `WindowGroup`-over-`BoloKit` slice should need 27. If something does,
stop and report — that's a D16 amendment and Jerod's call, not a build setting.

**D76 — commit a shared `.xcscheme`.** Overriding Implementer's (generally correct) "didn't add
unrequested files" restraint: the file is requested now. An autocreated scheme is per-user derived
state, and this sub-wave already demonstrated how fragile that is. Bundled with D75 deliberately so
7.1 gets audited **once, in final state**, rather than audited and re-audited across two mechanical
changes.

**Q27 — bundle identifier is Jerod's, not mine.** `com.cosmicceo.Bolo-2026` stands provisionally and
blocks nothing. I'm not ruling it because it's product identity, not engineering: cheap today,
expensive after Milestone D's signing/notarization, and under App Sandbox it's also the on-disk
container name, so a later change orphans saved state. My recommendation is to keep it unless Jerod
wants a personal or vanity domain for distribution.

**Not treated as open items** (Implementer's report answered these, recording so they aren't re-asked):
608 → 612 tests with the +4 named and D28-compliant; sheets confirmed absent from `git status`; icon
PNGs committed *by necessity* (`actool` needs them pre-build) as a disclosed, reasoned difference
from D72's not-committed sheets, not an inconsistency; clean-build-from-deleted-DerivedData is also
the real proof D72's build-order dependency works.

[TO: IMPLEMENTER] Two mechanical changes, one commit, then one pre-brief — in this order:
1. **D75:** `MACOSX_DEPLOYMENT_TARGET = 26.0` on `Bolo 2026` via `UpdateTargetBuildSetting` (tool, not
   hand-edit — this one is tool-supported). Clean build after. If anything actually requires 27, stop
   and report instead of reverting.
2. **D76:** commit `Bolo 2026.xcodeproj/xcshareddata/xcschemes/Bolo 2026.xcscheme`. Confirm
   `XcodeListSchemes` still shows exactly one scheme, no duplicate arising from the shared/autocreated
   pair — that specific duplication is the failure mode worth checking here.
3. Re-confirm the 612-test baseline unchanged and `.pbxproj` still `plutil`-clean after both, then
   commit with your report appended. Keep it to these two items — everything else in 7.1 is accepted.
4. **Then write Wave 7.2's pre-brief** (rendering) in the same session if the above lands clean. Its
   coding GO will not issue until 7.1 has a PARITY PASS, but there's no reason for the pre-brief to
   wait on the audit. Per the Wave 7.2 row: the SwiftUI `Canvas`/`TimelineView` vs. AppKit
   `NSView`/`CALayer`-via-`NSViewRepresentable` choice is yours to prototype and propose — I'll review
   it against D41's tick-timing discipline, and I want the *measured* basis for the choice, not a
   preference. Bind to D66 (top-left row-0 origin), D65 (no fog/`seentiles` — every tile visible,
   index straight from `mapimage()`), D64's `-1` "no image" sentinel, and D70's now-closed
   `dir2vec` heading convention (no translation layer).

[TO: PARITY] **Wave 7.1 activated for post-commit audit — but audit the state *after* Implementer's
D75/D76 fix commit lands, not `426c6a4` alone.** That's deliberate: two mechanical changes are in
flight and I'd rather you audit once, in final state. If Director relays you before that commit
exists, audit `426c6a4` and treat the deployment target and shared scheme as known-in-flight rather
than findings. Priorities, per my standing Xcode-crash caution — the project state itself, not just
Swift behaviour:
- The two hand-written `.pbxproj` sections (`XCLocalSwiftPackageReference`,
  `XCSwiftPackageProductDependency` ×2, `PBXTargetDependency`, `PBXShellScriptBuildPhase`).
  Implementer verified *structure* (`plutil -lint`, object counts) but explicitly **not** against a
  reference project — a second opinion on the encoding is the single highest-value thing you can do
  on this wave, and Implementer asked for it directly.
- The Run Script phase's behaviour under `ENABLE_USER_SCRIPT_SANDBOXING = YES`, and whether the
  declared `inputPaths`/`outputPaths` are actually sufficient (the report notes it "would fail
  silently-ish without them" — test that claim rather than accept it).
- Re-run the icon licensing check yourself (md5 across `Reference/c`'s images vs. the seven committed
  icon PNGs). Implementer asked you to re-run it; the whole clean-provenance premise of Wave 7.0/7.1
  rests on it.
- `Package.swift`'s two new products: confirm `BoloNet` is genuinely not exported, and that
  `swift build`/`swift test` at 612 are unaffected by the products block.

### [PLANNER] 2026-09-04 — D75/D76 landed (`6e060e9`); process note on missing AGENT_NOTES entry

**Type:** review note, no new ruling
**Phase:** Wave 7.1 — still not closed, awaiting PARITY PASS on final state

`6e060e9` ("Wave 7.1: D75 deployment target 27.0 -> 26.0, D76 shared scheme") is on `main`. Commit
message content matches what I asked for in the prior entry: `MACOSX_DEPLOYMENT_TARGET = 26.0` via
`UpdateTargetBuildSetting`, verified on the built binary (`otool -l` → `minos 26.0`,
`LSMinimumSystemVersion = 26.0`, not just the project setting); shared `.xcscheme` committed with
exactly one scheme resolving post-change (no autocreated duplicate); incidental Xcode
re-serialization of the Run Script phase into canonical form, no semantic change, noted as
corroborating evidence the earlier hand-edit was valid; tests unchanged at 612; `.pbxproj` still
`plutil`-clean, 21 objects, one native target.

**Process note, not a blocker:** this landed as a commit message only — no corresponding
`[IMPLEMENTER]` entry exists in this file. CLAUDE.md's own rule is explicit that a report living
only in a commit message/chat doesn't exist for PLANNER/PARITY until it's committed *here*. The
substance above is sound and I'm not holding up the audit for it, but flagging so it isn't treated
as the norm going forward — a two-line entry mirroring the commit message would have satisfied the
rule.

**PLAN.md's Wave 7.1 row updated to reflect `6e060e9`** — still gated on PARITY PASS, no new
follow-ups introduced.

[TO: PARITY] Per `ece3f7d`'s activation, audit final state — `6e060e9` is that state. No new
activation needed. Same priorities as before: the two hand-written `.pbxproj` sections, the Run
Script phase under `ENABLE_USER_SCRIPT_SANDBOXING = YES`, the icon licensing md5 re-check, and
`Package.swift`'s products block.

[TO: IMPLEMENTER] Please log a short `[IMPLEMENTER]` entry here for `6e060e9` (even retroactively)
so the record matches convention, and pick up Wave 7.2's pre-brief per my prior note — rendering
approach prototyped and proposed, bound to D65/D66/D64/D70.
- Test count 608 → 612, +4 icon regression tests, no removals (D28).

### [IMPLEMENTER] 2026-09-04 — D75/D76 landed (`6e060e9`); Wave 7.1 now in final state for PARITY; one incidental finding

**Type:** follow-up completion report (D75, D76)
**Phase:** Wave 7.1 — both required follow-ups done, 7.1 still **not closed** (PARITY PASS pending)
**Blocks:** nothing. This is the "final state" commit PLANNER wanted PARITY to audit once, rather
than auditing `426c6a4` and then re-auditing.

Executed only the two items D75/D76 named, per "keep it to these two items." **Wave 7.2's pre-brief
(instruction 4) is deliberately not started** — Jerod asked me to execute the D items and then
pause. It's queued, not forgotten.

**D75 — done, and verified on the shipped product rather than on the setting.** Set
`MACOSX_DEPLOYMENT_TARGET = 26.0` on the `Bolo 2026` target via `UpdateTargetBuildSetting` (the
tool, as instructed — not a hand-edit). Nothing required 27, so there is nothing to escalate
against D16:
- `otool -l` on the built binary: `minos 26.0` (SDK still 27.0, which is correct — you build
  against the newest SDK and deploy to the older floor).
- `Info.plist`: `LSMinimumSystemVersion = 26.0`.
- Clean build from a **deleted** DerivedData tree succeeded, and D72's script phase still
  regenerated both sheets — so neither the app nor the sheet generation depended on 27.

**One thing D75 did not fix, flagged rather than fixed unilaterally:** the *project*-level
`MACOSX_DEPLOYMENT_TARGET` is still the template's `27.0` in both configurations (`.pbxproj` lines
217 and 274); only the target's two configurations are now 26.0. That is enough for D75's actual
concern — the shipped app is 26.0, confirmed above — because the target value overrides the
project's. But the project-level 27.0 remains as the default any *future* target would inherit,
which is the same drift D75 exists to prevent, just deferred to whoever adds target #2 (the
Dedicated Host CLI under D58 is the obvious candidate). I did not change it because
`UpdateTargetBuildSetting` only operates on targets, so fixing it means another hand-edit of
`.pbxproj`, and D75 explicitly framed this one as "tool, not hand-edit." Your call whether that's
worth a follow-up or just a note for the next target.

**D76 — done, including the specific duplication check you asked for.** Wrote
`Bolo 2026.xcodeproj/xcshareddata/xcschemes/Bolo 2026.xcscheme` (no MCP tool shares a scheme, and
no existing `.xcscheme` existed anywhere on this host to copy shape from, so it's hand-written
against the standard format; `xmllint` clean; `BlueprintIdentifier` matches the target's real
`.pbxproj` UUID).
- **No duplicate from the shared/autocreated pair** — the failure mode you named.
  `XcodeListSchemes` after a workspace close/reopen: exactly **one** scheme, `Bolo 2026`, now
  `isShared: true`. `XcodeListTargets`: still exactly one target.
- The user-level `xcschememanagement.plist` now keys it as
  `"Bolo 2026.xcscheme_^#shared#^_"` — Xcode reclassified the previously autocreated scheme as the
  shared one instead of keeping both. That's the positive confirmation, not just absence of a
  second row.
- Verified it works **outside** the Xcode app too: `xcodebuild -project ... -list` resolves
  `Bolo 2026` with Xcode uninvolved, which is the actual point of sharing it (CI, and PARITY on
  another machine).
- Related, not a duplicate: `xcodebuild -list` also shows `BoloGlyphs` and `BoloKit` schemes. Those
  are auto-derived **package-product** schemes, a consequence of the `products:` block D74
  accepted — they appear because the project now references the local package, and they are not
  competing definitions of `Bolo 2026`. Noting it so it doesn't read as a duplication finding.

**Incidental finding — 23 MB of derived index data was written into the `.xcodeproj` bundle.**
While staging I found an untracked directory literally named `-Xcc` at
`Bolo 2026.xcodeproj/-Xcc/`, containing `v5/records` and `v5/units` — a Clang **index store**, 23
MB, timestamped mid-session during the D75 tooling work. Something in the toolchain passed an
index-store path such that `-Xcc` was consumed as a *directory name* instead of a compiler flag.
I inspected it before touching it (pure derived data, no source), deleted it, and confirmed it did
not come back on a subsequent build. It is **not** in `6e060e9` — nothing was committed from it.
Reporting it rather than quietly cleaning up because of the standing toolchain-instability caution:
it's a third oddity from this host (after the two Xcode crashes and the failed reinstall), and if
it recurs it's a 23 MB trap for anyone who runs `git add -A` — which this project's git rules
already forbid, which is the only reason it didn't land in a commit. I did **not** add a
`.gitignore` entry for it: that would be a third change outside D75/D76's scope, and it may be
better fixed at the source than papered over. Flagging for your call.

**Re-verification after both changes, per instruction 3:**
- `swift build` clean; `swift test` **612 tests** (156 `DifferentialTests` + 456 `BoloKitTests`),
  zero failures — unchanged from `426c6a4`, D28 intact.
- `.pbxproj` `plutil -lint`: OK. Structural dump: still exactly **21 objects**, one
  `PBXNativeTarget`, one `PBXShellScriptBuildPhase`, one `PBXTargetDependency`, one
  `XCLocalSwiftPackageReference`, two `XCSwiftPackageProductDependency`. No duplicates or orphans
  introduced.
- Clean build from deleted DerivedData succeeded twice across these changes.

**Worth knowing for PARITY's encoding review:** when `UpdateTargetBuildSetting` touched the project,
**Xcode itself re-serialized my hand-written `Generate Glyph Sheets` phase** into its canonical
form — dropped four keys that were sitting at their defaults (`buildActionMask`,
`runOnlyForDeploymentPostprocessing`, `alwaysOutOfDate`, and the two empty file-list arrays) and
rewrote `shellScript` from an escaped single string into a string array. Semantically identical,
and the clean builds after it confirm the phase still runs. This is indirect evidence the
hand-written encoding was valid — Xcode parsed and rewrote it rather than rejecting or mangling it
— but it is not a substitute for the reference-project comparison you asked PARITY for, since Xcode
would also happily rewrite a phase that was valid-but-wrong.

[TO: PLANNER] D75 and D76 both landed in `6e060e9`; Wave 7.1 is in the final state you wanted
audited once. Three things for you: (1) project-level `MACOSX_DEPLOYMENT_TARGET` is still 27.0 and
will be inherited by the next target added — deliberately left, needs a hand-edit if you want it;
(2) the stray 23 MB `-Xcc` index store described above, deleted, not committed, no `.gitignore`
entry added; (3) Wave 7.2's pre-brief is not written — Jerod asked me to pause after the D items.
[TO: PARITY] `6e060e9` is the commit to audit, not `426c6a4` — the deployment target and shared
scheme are now in place, so nothing is in flight. Your priority list from PLANNER stands unchanged.
One addition: Xcode has since re-serialized the `PBXShellScriptBuildPhase` I hand-wrote (details
above), so what you'll be reading is Xcode's own encoding of it, not my original text — the
`git diff` in `6e060e9` shows exactly what changed if you want the before/after.

### [PARITY] 2026-09-04 — Wave 7.1 final-state audit (`6e060e9`): project state and encoding PASS; one confirmed defect in shipped PNG bytes (F1), three record corrections

**Type:** post-commit audit
**Phase:** Wave 7.1, final state (D75/D76 landed)
**Audited:** `6e060e9` (per `55e27be`/`0073139`'s redirection away from `426c6a4`). Working tree at
audit time is `0073139` plus the three untracked Director artifacts — not touched.

**Activation:** Director (Jerod) relayed me ad hoc. `ece3f7d` had activated PARITY but asked for the
post-D75/D76 state; that commit landed mid-audit, so I re-baselined from `426c6a4` to `6e060e9` and
re-ran every project-level check against the new state. Logging the ad hoc relay as the deliberate
override PARITY.md contemplates, not a protocol break.

**Standing limitation — does not apply this session, and `docs/PARITY.md` is wrong about it.**
PARITY.md says "this environment has no Swift toolchain … your audit is a line-for-line hand-trace,
not a compile-and-run." I checked instead of assuming: `/usr/bin/swift` (Apple Swift 6.4,
swiftlang-6.4.0.33.1), `/usr/bin/xcodebuild`, `plutil`, `codesign`, `vtool`, `xmllint` are all
present and working. **So this audit is execution-verified, not hand-traced** — I built the app from
scratch, ran the suite, decoded the shipped PNGs, and ran controlled build experiments. That is a
stronger claim than usual and I want it on the record as such. Proposed PARITY.md amendment at the
bottom (drafted, not self-applied, per PARITY.md's propose-then-adopt rule).

---

## Claims re-derived, not taken on faith

- **Test count 608 → 612 (D28).** `swift test --list-tests`: `BoloKitTests` 456 + `DifferentialTests`
  156 = **612**, my own count, at HEAD. Full `swift test` exits 0, zero failures. The +4 icon tests
  are present and named as reported. No removals. **D28 satisfied.**
- **`.pbxproj` structure.** `plutil -lint` OK. **21 objects**, histogram exactly as reported: 1
  `PBXNativeTarget`, 1 `PBXShellScriptBuildPhase`, 1 `PBXTargetDependency`, 1
  `XCLocalSwiftPackageReference`, 2 `XCSwiftPackageProductDependency`. Beyond what was claimed, I ran
  full referential integrity over all 25 id-shaped references: **0 dangling, 0 orphaned**. The
  duplicate/orphan failure mode PLANNER's crash caution was written about is not present.
- **D72 build-order dependency.** Verified by consequence, not by reading: clean build from a fresh
  isolated DerivedData (`-derivedDataPath /tmp/parity_dd2 clean build`) → `BUILD SUCCEEDED`, and both
  `Tiles.png`/`Sprites.png` land in `Contents/Resources`, byte-identical (md5) to what
  `swift run BoloGlyphs` produces standalone. `BoloGlyphs` therefore really is built before the phase
  runs.
- **Entitlements.** Reproduced on *my own* signed build, not the reported one:
  `codesign -d --entitlements -` returns exactly `com.apple.security.app-sandbox`,
  `com.apple.security.files.user-selected.read-only`, `com.apple.security.get-task-allow`, and **no
  network entitlement of any kind**. Claim confirmed.
- **D75.** Target `MACOSX_DEPLOYMENT_TARGET = 26.0` in both configurations; shipped binary
  `vtool -show-build` → `minos 26.0`, `sdk 27.0`; `Info.plist` `LSMinimumSystemVersion = 26.0`.
  Confirmed on the product. Implementer's own flag is also confirmed: **project-level** is still
  `27.0` in both configurations.
- **D76.** `xcodebuild -list` with Xcode uninvolved resolves scheme `Bolo 2026`; `xmllint` clean;
  `BlueprintIdentifier = 6288C26D304B70C6007A9580` matches the target's real UUID. `BoloGlyphs` and
  `BoloKit` also appear as schemes — auto-derived package-product schemes, correctly diagnosed by
  Implementer, not duplicates. **Concrete D76 benefit worth recording:** before it landed,
  `xcodebuild -derivedDataPath` refused to run at all ("The flag -scheme, -testProductsPath, or
  -xctestrun is required when specifying -derivedDataPath") — I had to fall back to SYMROOT/OBJROOT
  overrides on `426c6a4`. Isolated-DerivedData builds now work, which is exactly the CI/second-machine
  case D76 was for.
- **Licensing re-check, re-run as asked.** 95 image-type files under `Reference/c` → 62 distinct
  md5s; 7 committed icon PNGs; **intersection empty**. Claim reproduced. Two caveats I want on the
  record rather than implied: md5 only catches *byte-identical* copies — a rescaled or re-encoded
  derivative would pass — so the load-bearing assurance is generative provenance (`AppIcon.swift`
  composites `renderGlyph` output), which I read and confirmed. Stronger evidence than the
  determinism test: I regenerated all seven icons with `swift run BoloGlyphs icon` and they are
  **byte-identical (md5) to the committed PNGs**, so the committed artifacts are genuinely in sync
  with the generator source, not a stale drop.
- **`Package.swift` products.** Exactly two: `.library(BoloKit)`, `.executable(BoloGlyphs)`.
  **`BoloNet` is genuinely not exported** — confirmed by reading the manifest, per D73/D74.
  `swift build`/`swift test` unaffected at 612. **D26 intact:** `-ffp-contract=off` still on `CXBolo`
  (`Package.swift:22`), untouched.
- **Conventions.** `import Foundation` in `Sources/BoloKit`: **0 occurrences**. `Tiles.png`/
  `Sprites.png` tracked in git: **0** (D72 honoured). Stray `-Xcc` index store: gone, confirmed
  absent; no `.gitignore` entry exists for it (Implementer's report says so — accurate).
- **D18.** Nothing in this wave puts `Double`/`CGFloat` into position/physics/trig. Considered and
  cleared, not overlooked: `Canvas.swift`'s `fillCircle`/`fillRing`/`fillRotatedTriangle` take
  `Double` geometry, but that is pre-existing Wave 7.0 offline art tooling whose output is
  byte-deterministic and tested, not runtime position/physics state — outside D18's scope. Flagging
  it as examined so a later audit doesn't re-raise it as new.

## Encoding second opinion (PLANNER's stated highest-value item)

`BoloKit`'s wiring is textbook: `XCSwiftPackageProductDependency` + `PBXBuildFile.productRef` in the
Frameworks phase + listed in `packageProductDependencies`. `BoloGlyphs` is wired the
executable-as-target-dependency way: `PBXTargetDependency` carrying a bare `productRef`, and it is
**not** listed in `packageProductDependencies` (which holds `BoloKit` alone).

**I could not obtain the reference-project comparison that was asked for** — I searched this host for
another `project.pbxproj` using `XCSwiftPackageProductDependency` and found none within budget. So I
will not claim a canonical-schema verdict. Saying that plainly rather than dressing up a structural
read as one.

What I can offer is better than my own opinion, and it arrived during the audit: **`6e060e9` is a
partial canonicalization by Xcode's own writer.** `UpdateTargetBuildSetting` caused Xcode to
re-serialize the file, and it *actively rewrote* the `PBXShellScriptBuildPhase` it considered
non-canonical (dropped five keys sitting at defaults, converted `shellScript` from an escaped string
to a string array) while leaving **`XCLocalSwiftPackageReference`, both
`XCSwiftPackageProductDependency` objects, `PBXTargetDependency`, `PBXBuildFile`, and
`packageProductDependencies` byte-identical**. Xcode had the whole graph in hand and normalised one
section but not those. Combined with 0 dangling/0 orphaned refs, `plutil`-clean, package graph
resolving (`BoloKit: /Users/jerodprice/Developer/XBolo @ local`), and repeated successful
from-scratch builds with correct phase ordering, my verdict on the hand-written encoding is
**sound — no finding**. Implementer's own caveat is fair and I echo it: a rewrite is not proof of
correctness, so this is convergent evidence, not a schema proof. Also note `inputPaths`/`outputPaths`
**survived** the re-serialization intact, so D72's incremental-build properties are still declared.

---

## Findings

### F1 — CONFIRMED DEFECT: the PNG encoder corrupts every partial-alpha colour. Shipped bytes differ from source intent, and no test can see it.

`Sources/BoloGlyphs/main.swift`'s `writePNG` builds its `CGContext` with
`CGImageAlphaInfo.premultipliedLast` and then `copyMemory`s the glyph buffer in verbatim. But those
buffers are **straight** alpha: `Canvas.swift`'s `set`/`fillRect` write `r,g,b` and `a` independently
with no premultiplication. CoreGraphics therefore reads (50,50,50) at a=200 as already-premultiplied
and *un-premultiplies* it on PNG export.

Not inferred — measured, by decoding the PNG out of the built `.app`:

- Source intent: `Sources/BoloGlyphsCore/GlyphSource.swift:92` — `fillRect(2, 2, 14, 14, 50, 50, 50, 200)`,
  the pill body backing → RGB(50,50,50) @ a=200.
- **Shipped `Bolo 2026.app/Contents/Resources/Tiles.png` actually contains RGB(64,64,64) @ a=200
  across 2,548 pixels.** `round(50 × 255 / 200) = 64` — an exact match to the un-premultiply formula,
  which pins the mechanism rather than just the symptom.
- **Scope today is `Tiles.png` only.** `Sprites.png` uses only alphas {0, 255}; all seven icons are
  alpha 255 throughout. At a=255 un-premultiply is the identity, and at a=0 the buffer is zeroed
  (I verified 0 pixels with a=0 and RGB≠0). So sprites and icons are unaffected, and the committed
  icons are *not* wrong.
- **Why the whole suite is blind to it:** every sheet and icon test asserts on the in-memory
  `Canvas16`/`RGBASheet` buffers. Nothing decodes an emitted PNG. This entire defect class is
  invisible to current coverage — which I consider the more important half of the finding.
- **Provenance, stated plainly:** pre-existing from Wave 7.0 — `426c6a4` left `premultipliedLast`
  unchanged, so 7.1 did not introduce it. **My own Wave 7.0 audit missed it.** It is in scope now
  because 7.1 is what first ships these bytes inside an app bundle and refactored `writePNG` into the
  shared sheet+icon path.
- Impact today is cosmetic: one pill backing renders ~14/255 lighter than authored. The blast radius
  grows with every partial-alpha glyph Wave 7.2+ adds, and 7.2 is the wave that starts drawing these
  tiles for real.
- Fix direction only (PARITY does not write fixes): either declare the context
  `CGImageAlphaInfo.last` to match the straight-alpha buffers, or premultiply at write time — plus a
  regression test that decodes the emitted PNG and compares against the source buffer, which is the
  gap that let this survive two audits.

### F2 — The Run Script sandboxing rationale is wrong. Tested both ways, per PLANNER's "test that claim rather than accept it."

The completion report states the declared `inputPaths`/`outputPaths` "are what make the phase legal
under [`ENABLE_USER_SCRIPT_SANDBOXING = YES`] — this would fail silently-ish without them." I tested
it on a throwaway clone at `426c6a4`:

- **Removed both `outputPaths` entries** → `BUILD SUCCEEDED`, script logged
  `Wrote …/Tiles.png and …/Sprites.png`, both PNGs correctly in the bundle. Only a warning: *"Run
  script build phase 'Generate Glyph Sheets' will be run during every build because it does not
  specify any outputs."*
- **Restored outputs, removed `inputPaths`** → `BUILD SUCCEEDED`, both PNGs written.

Mechanism, from the generated `.sb` profile: it is `(allow default)` with targeted
`(deny file-read* file-write* (subpath (param "SYMROOT")))` and friends. Declared outputs *do* add
`(allow file-read* file-write* (literal (param "SCRIPT_OUTPUT_FILE_n")))`, so the grant mechanism is
real and would be load-bearing for a phase writing **outside** the build directory. But here the
writes target `$BUILT_PRODUCTS_DIR`, and on this toolchain (Xcode 27.0 beta, 27A5252f) those
build-root denies are not enforced as hard failures — I confirmed the phase genuinely was
`sandbox-exec`'d and that `-D SYMROOT=…` was bound, and the write still succeeded.

**What the declarations actually buy is dependency-analysis and incremental-build correctness, not
sandbox legality.** The implementation is right and must not change — declaring them is correct, and
without `outputPaths` the phase loses up-to-date checking and re-runs every build. Only the stated
reason is wrong. Worth correcting because the wrong mental model would mislead whoever adds a script
phase that writes outside the build dir, where the distinction genuinely bites. Toolchain-specific;
could change on a future Xcode.

### F3 — Two build settings the report quotes as `= NO` do not exist in the project at all.

The report states the template defaults are "already exactly the state the pre-brief was asking for —
`ENABLE_APP_SANDBOX = YES`, `ENABLE_OUTGOING_NETWORK_CONNECTIONS = NO`,
`ENABLE_INCOMING_NETWORK_CONNECTIONS = NO`." Checked all four `XCBuildConfiguration` objects at HEAD:
only `ENABLE_APP_SANDBOX = YES` is present (target level, both configurations). **Neither network
setting appears anywhere in the `.pbxproj`.**

The *conclusion* is correct — absent means no network entitlement is synthesized, which I confirmed
on the signed product — so nothing shipped wrong. But absent-and-defaulting is not the same as
explicitly `NO`: it depends on Xcode's default staying `NO` across toolchain updates, and there is
nothing in the file for a reader to see. **This bears directly on D74**, which records "Milestone B's
`ENABLE_OUTGOING_NETWORK_CONNECTIONS` flip" as though the key exists at `NO`. At Milestone B it will
have to be **added**, not flipped. Recommend correcting D74's wording so a future session doesn't
hunt for a key that was never there.

### F4 — `SWIFT_VERSION = 5.0` on the app target, while the package is `swift-tools-version: 6.4`. Raise it now, before 7.2/7.3 write concurrency into it.

`Bolo 2026`'s own sources compile in **Swift 5 language mode** (both configurations) — no strict
concurrency checking, `Sendable`/actor-isolation violations downgraded — while `BoloKit` is built
under Swift 6 semantics. Inert for a 17-line `WindowGroup` plus a 42-line `ContentView`. But 7.2 and
7.3 put the draw loop, the tick loop, and input handling in *exactly this target*, which is where
actor-isolation and `Sendable` diagnostics are worth the most under D41's tick-timing discipline.
Not a 7.1 defect and not a blocker — raising it while the target is 59 lines rather than after a
render loop exists. PLANNER's call whether it rides along with 7.2's pre-brief.

### F5 — TRIVIAL: comment in `AppIcon.swift` claims the opposite of what the code does.

`Sources/BoloGlyphsCore/AppIcon.swift:31-33`. The `else` branch's comment says it "only exists so a
future change there fails loudly at review rather than silently recolouring" — but the code silently
falls back to a hardcoded `(70, 140, 60)`. It does not fail loudly, and that literal sits awkwardly
against the function's own doc comment ("rather than a literal so the icon tracks the sheet's own
palette"). No behavioural impact: `GRAS00IMAGE` is an unconditional `.flatFill` in `tileGlyphRole`,
so the branch is unreachable today. If the intent is fail-loudly it wants `preconditionFailure`; if
it is a genuine fallback the comment should say so.

---

## Verdict

**PASS on everything Wave 7.1 set out to deliver.** The app target, `BoloKit` linkage, D72 build-time
sheet generation and build ordering, entitlements posture, generated-not-copied icon provenance, D75,
D76, D26, D28, and the hand-written `.pbxproj` encoding all verified — most of them by execution, and
several by stronger evidence than the completion report offered. The two Xcode crashes left no
detectable trace in the project state; Implementer's diagnosis on that holds up.

**Not a clean PASS overall, because of F1**: a confirmed, measured discrepancy between authored glyph
colours and the bytes shipped in `Tiles.png`, sitting behind a test-coverage gap that hides the whole
defect class. It is cosmetic today, it is pre-existing from Wave 7.0 rather than a 7.1 regression, and
my own 7.0 audit missed it — so I have no standing to call it a 7.1 blocker. PLANNER's call whether
7.1 closes with F1 routed to a follow-up or fixed first; my recommendation is that the *regression
test* is the part that shouldn't wait, since Wave 7.2 is about to start drawing these tiles.
F2 and F3 are corrections to the written record, not to code. F4 is cheap now and expensive later.
F5 is trivial.

[TO: PLANNER] Wave 7.1 final state (`6e060e9`) audited by execution, not hand-trace — this
environment does have a Swift toolchain, contrary to `docs/PARITY.md`. PASS on all of 7.1's own
deliverables. One confirmed defect (**F1**, PNG premultiply mismatch — 2,548 pixels in the shipped
`Tiles.png` are RGB(64,64,64) where the source authors RGB(50,50,50)); it is pre-existing from Wave
7.0 and my own 7.0 audit missed it, so I flag it without claiming it blocks 7.1. **F2** and **F3** are
record corrections you may want folded into D72's and D74's text respectively — F3 specifically
because D74 says "flip `ENABLE_OUTGOING_NETWORK_CONNECTIONS`" and that key does not exist. **F4**
(app target is Swift 5 language mode) is worth deciding before 7.2 writes a tick loop into it.
Also: `Q?` — nothing from me requires a Jerod ruling.
[TO: IMPLEMENTER] F1 is the only one that touches code: `writePNG` in `Sources/BoloGlyphs/main.swift`
declares `premultipliedLast` but is handed straight-alpha buffers from `Canvas.swift`. Reproduce with
any glyph using `a < 255` — today only `GlyphSource.swift:92`. The missing coverage (no test decodes
an emitted PNG) matters more than the one wrong colour. F2: your inputs/outputs declarations are
correct and should stay — only the *reason* recorded for them is wrong, tested both ways on a clone.
F5 is a two-line comment fix. Your D75/D76 report's numbers all checked out against my own counts.

## Proposed `docs/PARITY.md` amendment (drafted, not applied — propose-then-adopt)

Replace the "Standing limitation" paragraph's claim that the environment has no Swift toolchain with
an instruction to **verify tooling at the start of each session and state what was available**. As of
2026-09-04 this host has Swift 6.4, `xcodebuild`, `plutil`, `codesign`, `vtool` and `xmllint`, and
this audit used all of them — the current text would have had me hand-trace things I could simply run,
and F1 is a finding that only surfaced because I decoded shipped bytes rather than reading source.
Suggested replacement: *"Check your tooling first (`which swift xcodebuild plutil`) and say in your
findings which checks were executed versus hand-traced. Where a toolchain exists, prefer execution —
build it, run the suite, decode the artifact. Where it doesn't, hand-trace against `Reference/c` and
say so. IMPLEMENTER's green build remains the authority that the code executes; you are the authority
that it is correct against the oracle."*

### [PLANNER] 2026-09-04 — Wave 7.1 CLOSED (PARITY PASS `a03aa07`); D77-D80 ruled

**Type:** wave close + rulings
**Phase:** Wave 7.1 closed. Wave 7.2 unblocked with two new prerequisites gating its coding GO.

Reviewed PARITY's final-state audit (`a03aa07`) against Wave 7.1's own scope and against what's
fair to hold this wave responsible for. The audit itself is a step up in rigor worth naming: this
host does have a Swift toolchain (PARITY.md was wrong about that), so this was execution-verified —
built from scratch, ran the 612-test suite, decoded shipped PNG bytes, ran controlled build
experiments on sandbox behavior — not a hand-trace. That's how F1 got found at all.

**Wave 7.1 closes now.** Every claim it's actually responsible for — app target, `BoloKit` linkage,
D72 build ordering, entitlements posture (reproduced on PARITY's own signed build), icon provenance
(regenerated and byte-identical to committed), D75/D76 (verified on the shipped binary: `minos 26.0`,
one scheme resolving with Xcode closed), D26/D28, and the hand-written `.pbxproj` encoding (0
dangling/0 orphaned refs across 25 references, Xcode's own partial re-serialization left the
package-reference objects untouched) — PASS.

**D77 — F1 (confirmed PNG premultiply defect) does not block this close.** It's pre-existing from
Wave 7.0 (`426c6a4` never touched `writePNG`), and PARITY's own Wave 7.0 audit missed it too — so
by the same standard I'd apply to anyone else's already-closed work, it's not fair to charge it to
7.1. But it's real, measured (2,548 pixels off by exactly the un-premultiply formula), and its blast
radius is about to grow: **required before Wave 7.2's coding GO**, same precedent as D45/D53/D57 —
found-late-but-real defects get fixed promptly, gated on the next wave that actually depends on the
affected output, not carried as indefinite tracked debt. The regression test matters more than the
one wrong colour, per PARITY's own framing: the whole defect class is invisible to current coverage
because nothing decodes an emitted PNG.

**D78 — F3's record correction accepted.** D74's text is wrong in one detail: it describes
Milestone B as "flipping" `ENABLE_OUTGOING_NETWORK_CONNECTIONS`/`ENABLE_INCOMING_NETWORK_CONNECTIONS`
to `YES`, but PARITY confirmed neither key exists in `.pbxproj` at all today — only
`ENABLE_APP_SANDBOX = YES` is present. Nothing shipped is wrong (absent already produces the correct
signed-product result), this is purely so Milestone B doesn't go hunting for a key that isn't there.

**D79 — F4 (Swift 5 language mode on the app target) rides along with Wave 7.2, not this close.**
Inert today, not inert once 7.2/7.3 put a draw loop and a tick loop into this exact target — D41's
tick-timing discipline is worth having actor-isolation/`Sendable` checking for. Required before
7.2's coding GO stands, same gating as D77.

**D80 — adopted PARITY's `docs/PARITY.md` amendment, as proposed.** The "no Swift toolchain"
standing-limitation paragraph was flatly false on this host, and F1 is a direct demonstration of the
cost — a hand-trace-only session would plausibly never have found it. Edited `docs/PARITY.md`
directly to require a per-session tooling check and an explicit execution-vs-hand-trace disclosure,
per the propose-then-adopt convention (D71).

**F2 and F5 — no ruling needed.** F2 corrects the completion report's stated *rationale* for the
Run Script's input/output declarations (not sandbox legality, but dependency-analysis/incremental
correctness) — the declarations themselves are right and stay; the correction lives in PARITY's own
log entry, no PLAN.md text depended on the wrong reason. F5 is a two-line comment/behavior mismatch
in `AppIcon.swift`, unreachable today — Implementer can fix it opportunistically, not gating
anything.

**PLAN.md updated:** Wave 7.1 row closed citing `a03aa07`; Wave 7.2 row carries D77/D79 as coding-GO
prerequisites; D77-D80 added to the decisions log.

[TO: IMPLEMENTER] Wave 7.1 is closed — nice work surfacing all four D74 deviations and the stray
`-Xcc` index store rather than smoothing any of it over; that's exactly the standard this project
runs on. Before Wave 7.2's coding GO can stand, land D77 (fix `writePNG`'s premultiply mismatch —
`CGImageAlphaInfo.last` or premultiply at write time, your call — plus a regression test that
decodes an emitted PNG and compares against source, not just in-memory buffers) and D79 (raise
`Bolo 2026`'s language mode off Swift 5 to match the package's Swift 6 semantics, confirm a clean
build). Both can land together with, or just ahead of, Wave 7.2's pre-brief — your call on ordering,
but the pre-brief's coding GO won't issue without both reported done. F5 (the `AppIcon.swift`
comment) is yours to fix whenever convenient, not gating.
[TO: PARITY] Wave 7.1 closed on your PASS. Noted and valued: the execution-based audit method, the
proactive PARITY.md correction, and flagging F1 against your own prior Wave 7.0 audit rather than
letting it sit quietly. D77/D79's fixes will come back to you for re-audit once Implementer reports
them, same fix→test→re-audit sequence as every other confirmed finding this project has had.

### [IMPLEMENTER] 2026-09-04 — D77/D79/F5 landed (`72d880f`); Wave 7.2 pre-brief (rendering mechanism, measured)

**Type:** completion report (D77/D79/F5) + coding pre-brief for Wave 7.2
**Phase:** Wave 7.1 follow-ups done; Wave 7.2 (game rendering) pre-brief, no BoloKit production
rendering code written yet
**Blocks:** Wave 7.2 coding start — needs PLANNER's read on the rendering-mechanism choice below,
same two-stage gate as every prior wave. D77/D79 are unblocking, not blocked.

**Process note before anything else:** picked this session up mid-file — the `[PLANNER]` "process
note on missing AGENT_NOTES entry" entry above (the one right before this, timestamped alongside
`0073139`) was sitting uncommitted in the working tree when I started, never committed by whatever
session wrote it. Not mine to author or edit; committing it now as part of this entry's commit
simply because it was already there, per the same "an entry only exists once committed" rule it
itself quotes. Substance unaffected — everything after `55e27be` in the log had already made its
content moot (the short `[IMPLEMENTER]` entry it asked for was superseded by the full D75/D76
report immediately below it, and Wave 7.1 has since closed).

### D77 — fixed: PNG premultiply mismatch (PARITY's F1)

Root cause confirmed empirically before touching code: wrote a throwaway script that tried creating
a `CGContext` with `CGImageAlphaInfo.last` (straight, non-premultiplied) — **fails, returns `nil`**.
So `.premultipliedLast` was the only viable context format, meaning the buffer has to be
premultiplied *before* it's copied in, not declared away. Verified the fix mechanism round-trips
exactly with a two-pixel test case (50,50,50,200) → premultiply → context → `makeImage()` → PNG
encode → decode raw bytes → **(50,50,50,200) exactly**, before writing any production code.

- New `Sources/BoloGlyphsCore/PNGCodec.swift`: `premultiplyStraightAlpha` (round-to-nearest),
  `encodePNGData`, `decodePNGToStraightAlphaRGBA`. Moved out of `Sources/BoloGlyphs/main.swift`
  specifically so it's reachable from `BoloKitTests` — `writePNG` there is now a thin
  encode-then-write-to-disk wrapper.
- Two new tests in `BoloGlyphsTests.swift`: one round-trips both real generated sheets end-to-end
  (encode → decode, alpha exact, RGB within ±1 rounding tolerance) and one locks in the exact pixel
  PARITY measured (`fillRect(..., 50, 50, 50, 200)`) to a byte-exact expectation. This is the
  coverage gap PARITY named directly — "nothing decodes an emitted PNG" — closed by making the test
  decode one.
- Verified against the real executable, not just the test buffers: ran `swift run BoloGlyphs` fresh,
  decoded the actual `Tiles.png` it wrote, scanned for both the old defect's signature and the
  correct one. **0 pixels at RGB(64,64,64)@a=200 (old defect), 2,548 pixels at RGB(50,50,50)@a=200
  (correct) — the exact count PARITY reported.**
- Scope unchanged from PARITY's own finding: `Sprites.png` and all icons use only alpha ∈ {0, 255},
  where premultiply/un-premultiply is the identity — confirmed unaffected, not just assumed.

### D79 — fixed: `Bolo 2026` target raised from Swift 5 to Swift 6 language mode

`UpdateTargetBuildSetting SWIFT_VERSION=6` (tool, not hand-edit, per D75's own precedent for this
class of change). `GetTargetBuildSettings` confirms `SWIFT_VERSION` resolves to `6` on the target
now. Clean build succeeded **from a fully deleted DerivedData tree** (not incremental) — both
generated sheets still regenerate, confirming D72's build-order dependency survived the mode change.
`.pbxproj` unchanged at 21 objects, still `plutil`-clean; `XcodeListTargets`/`XcodeListSchemes` still
show exactly one target and one scheme, no duplication. Launched the app under the new mode — no
crash, same benign `linkd`/intents system noise as every prior run, nothing new.

### F5 — fixed, opportunistically (not gating): `AppIcon.swift`'s dead-branch comment

Changed the unreachable fallback from silently returning a hardcoded grass colour to
`preconditionFailure`, matching what its own comment already claimed it did. `GRAS00IMAGE` is still
confirmed an unconditional `.flatFill` today (branch stays dead), so this has no behavioral effect
now — it only changes what happens if that ever stops being true.

**Verification for all three:** `swift build` clean, `swift test` **612 → 614 (+2)**, zero removals
(D28) — the two D77 round-trip tests are the entire delta. Full suite re-run after F5's change too;
no regressions.

---

## Wave 7.2 pre-brief — rendering mechanism, with measured numbers

PLANNER's ask was explicit: "I want the measured basis for the choice, not a preference." Built two
disposable prototypes directly in the `Bolo 2026` target (SwiftUI `Canvas`+`TimelineView` vs. an
AppKit `NSView` via `NSViewRepresentable`), ran both live via `RunProject`/`GetConsoleOutput`,
deleted the scaffolding afterward — `git status` on `Bolo 2026/` is clean, nothing from this
benchmarking is committed. Both prototypes blitted from the *real* generated sheets, used
`mapimage()` on a real `TerrainGrid`→`TileGrid` (via `terrainToTile`, already ported), and drew 16
tank sprites at the real `PTNK00IMAGE + heading` indices — synthetic scene, real code paths.

### Finding, independent of the mechanism choice: no C-style y-flip needed in the renderer

Checked before writing either prototype: `Vector.swift`'s `dir2vec`/`vec2dir` doc comments
(`Sources/BoloKit/Vector.swift:135-136`) already state BoloKit's own `Vec2f` convention is
**screen/grid space where +y is down** — the negation inside `dir2vec` exists *because of* this,
not despite it. `TerrainGrid`/`TileGrid` storage (`storage[y*256+x]`) uses the same axis. This means
`GSBoloView.m`'s `255 - y` flip (`dstRect = NSMakeRect(16*x, 16*(255-y), ...)`, present at every one
of its seven draw call sites) is a C-specific artifact of AppKit's bottom-left-origin default that
**does not need porting** — screen pixel `(16*x, 16*y)` already lands tile `(x,y)` at the visually
correct position with zero flip math, for both tiles and sprite positions (`Vec2f` tank/shell/
explosion coordinates use the identical convention). Binding on 7.2: no `FWIDTH`/`255-y` translation
layer anywhere in the renderer. For the AppKit path specifically this means `isFlipped = true` on the
`NSView` (top-left origin, matching D66's sheet convention) with dst rects computed directly.

### Benchmark methodology and numbers

Synthetic scene: `TerrainGrid.mapDefault()` run through `terrainToTile`/`mapimage()` per visible
tile (real cost, not a stub), 16 tanks at `PTNK00IMAGE + heading`, camera orbiting so the drawn
content genuinely changes every tick (see gotcha below — a static scene invalidates this test).
Redraw driven at 50Hz (`ticksPerSec`) by a `Timer` standing in for what 7.3's real tick loop will do.
120-frame rolling avg/p95, printed to console.

| Viewport (px) | Visible tiles | AppKit avg / p95 | Canvas avg / p95 |
|---|---|---|---|
| 1280×800 (typical window) | ~4,400 | **6.7ms / 7.3ms** | 7.8ms / 9.3ms |
| 3840×2160 (near-full-map) | ~32,000 | 46.1ms / 48.4ms | **25.6ms / 26.9ms** |

At the realistic v1 window size, AppKit is ~15-20% faster with tighter tail latency, and both sit
comfortably inside the 20ms/tick budget (D41-style tick-timing discipline — render must not itself
become the tick bottleneck). At a viewport approaching the full 4096×4096 map, both approaches miss
the 20ms budget, and Canvas actually wins there — a real crossover, not noise (reproduced across
repeated runs at both sizes). Per-tile cost is roughly constant for AppKit (~1.5μs/tile at both
sizes); Canvas's per-tile cost *drops* at scale (~1.8μs/tile small → ~0.8μs/tile large), consistent
with GPU-compositing overhead amortizing better over more draw calls.

**This crossover doesn't change the recommendation for v1**, because D60's v1 scope has no zoom/
scroll (that's explicitly Milestone D polish) — nothing in 7.2/7.3 needs to render anywhere near
32,000 tiles in a frame. But it's real and worth recording so whoever picks up zoom/scroll doesn't
rediscover it: **recommend a hard cap on rendered-tile-count regardless of window size** (clamp the
camera's effective viewport, don't just blindly render whatever the OS hands the view), independent
of which rendering mechanism is in place by then. Not a v1 blocker — flagging for Milestone D.

### Gotcha found and worth recording on its own: `Canvas`+`TimelineView` silently drops frames on unchanging content

First benchmark pass used a **static** scene (fixed camera, fixed positions) and got zero
"`avgMs=...`" prints after 10+ seconds, even though the wrapping `TimelineView`'s own content
closure was independently confirmed firing ~90×/sec (separate print statement, outside `Canvas`).
Instrumented further: the `Canvas` draw closure itself fired **exactly twice, at startup, and never
again** — each of those two calls measured 3.6-3.8ms (cheap), so this wasn't a performance problem,
it was SwiftUI's diffing deciding a re-render was unnecessary because nothing the `Canvas` closure
read had changed. Fix: thread the `TimelineViewDefaultContext`'s `date` into the drawn content
(orbiting the synthetic camera off `timeline.date`) — once the closure's inputs genuinely vary from
tick to tick, it redraws every time, matching the AppKit path's unconditional `needsDisplay`-driven
redraw. Real production `GameState` mutates every tick (`runTick` moves tanks), so this won't bite
7.2's actual draw loop by accident — but it's a sharp edge worth naming explicitly: **if a future
edit to 7.2 ever hands `Canvas` content that's byte-identical to the previous frame (e.g. during
`server.pause`), frames will silently stop compositing** with no error, no dropped-frame log, nothing
— exactly the kind of thing that only shows up as "the game looks frozen but the tick counter in the
corner is still climbing." Named here so nobody has to rediscover it by staring at a black window
that should be redrawing at 20ms intervals.

### Recommendation: AppKit `NSView` via `NSViewRepresentable`, redraw invoked externally by 7.3's tick loop

Reasons, in order of weight:
1. **Faster and tighter-tailed at the only viewport sizes v1 actually needs** (measured above) — the
   Canvas-wins case is out of v1's scope entirely (no zoom/scroll).
2. **Directly analogous to `GSBoloView`'s own model**: an externally-invalidated `drawRect:`-style
   view, redrawn on command rather than diffed against prior content. 7.3's tick loop calls
   `setNeedsDisplay = true` after each `runTick()` — an explicit, auditable redraw trigger, not an
   implicit one riding on SwiftUI's change-detection. This is the safer choice under D41's
   tick-timing discipline specifically *because* of the gotcha above: no risk of a future edit
   accidentally producing "no visible change" content that silently stops compositing.
3. **`isFlipped = true` maps cleanly onto D66's already-decided top-left sheet convention** with zero
   translation math (see the y-flip finding above) — this holds for either mechanism, but AppKit's
   version needs no `context.clip`/value-type-context-copy pattern to blit sub-rects; a plain
   `CGContext.draw(_:in:)` from a `cropping(to:)` sub-image is the whole primitive.
4. Both mechanisms are viable and neither is a wrong choice — flagging this as a real engineering
   tradeoff, not a foregone conclusion, per PLANNER's own framing of this as an open call.

**Draw-order scope for v1** (subset of `GSBoloView.m`'s `drawSprites`, 286-439): terrain (D65 — every
tile from a straight `mapimage()` call, no fog/`seentiles`), local player's tank + builder (if
mid-task) + shells + explosions. **Explicitly out of scope, not a fidelity gap**: the ally/enemy tank
colour branch, other-players' name labels, other-players' builders, and the multi-tank alliance
check (`testAlliance`) — v1 is single-process with no networking wiring (D73), so there are never
any other connected players to draw. Selector/crosshair/pause-label sprites are cosmetic HUD-adjacent
elements Milestone C owns, not drawn here.

**Not yet decided, flagging for PLANNER rather than assuming:** whether 7.2's `NSViewRepresentable`
lives directly in `ContentView.swift` or its own file, and whether the tick-driven redraw trigger is
wired in 7.2 (as a placeholder tick) or deferred entirely to 7.3 (my preference — 7.2 should accept a
`GameState` snapshot and redraw-on-demand, 7.3 owns *when* "on-demand" fires, keeping the two
sub-waves' responsibilities the same shape as the reference's client/view split).

[TO: PLANNER] D77/D79/F5 done and committed (`72d880f`), verified end-to-end (not just re-stated) —
ready for PARITY re-audit whenever convenient, same fix→test→re-audit sequence as every prior
confirmed finding. Wave 7.2 pre-brief above: recommending AppKit `NSView`/`NSViewRepresentable` over
SwiftUI `Canvas`/`TimelineView`, with measured numbers at two viewport sizes, a real crossover at
near-full-map sizes that doesn't change the v1 recommendation, and a `Canvas`+`TimelineView` gotcha
(silent frame-drop on unchanging content) worth keeping in institutional memory even though it
doesn't affect the recommendation. Also surfaced: BoloKit's own `Vec2f`/grid convention is already
+y-down, so 7.2 needs zero C-style `255-y` flip math anywhere — smaller than I expected this wave to
be, worth confirming you read it the same way before I start writing the actual `NSView` subclass.
Awaiting your GO before writing production rendering code.
[TO: PARITY] Nothing new to audit yet for Wave 7.2 (pre-brief only, no production rendering code).
D77/D79/F5 are ready for your re-audit at `72d880f` — the PNG round-trip regression test is the one
I'd most want a second opinion on, since it's the exact coverage gap your own finding named.

### [PLANNER] 2026-09-04 — D77/D79/F5 accepted; Wave 7.2 coding GO'd (D81/D82)

**Type:** review + rulings + coding GO
**Phase:** Wave 7.1 follow-ups closed out; Wave 7.2 (game rendering) coding GO'd

**D77/D79/F5 — accepted, PARITY re-audit requested but not gating.** The D77 fix is the standard
I want: root cause diagnosed empirically before writing production code (confirmed
`.premultipliedLast` is the only viable context format, so the fix has to premultiply going in, not
declare the format away), verified against the *real* `BoloGlyphs` executable's actual output
(0 defect pixels, 2,548 correct pixels — the exact count PARITY measured), and the coverage gap
PARITY named directly ("nothing decodes an emitted PNG") is now closed by a test that does exactly
that. D79 (`SWIFT_VERSION=6` via the tool, clean build from deleted DerivedData, no duplication) and
F5 (dead-branch comment now matches behavior) are equally clean. 612→614 tests, D28-compliant.
**Not holding Wave 7.2's coding GO on PARITY's re-audit landing first** — the fix is already
committed and self-verified against real output with numbers that independently match PARITY's own
findings, so the re-audit (requested below) confirms rather than gates. If it finds something wrong,
that reopens D77 the normal way; it doesn't retroactively unwind 7.2's GO, since 7.2 doesn't touch
`writePNG` itself.

**Wave 7.2 pre-brief reviewed against D41's tick-timing discipline, D60/D65/D66/D70/D73 — approved,
see D81/D82 in `docs/PLAN.md`.** This is exactly the "measured basis, not a preference" I asked for:
two disposable prototypes built in the real target, benchmarked live against real sheets and real
`mapimage()`/tank-sprite code paths, cleaned up after (confirmed by `git status`). **D81: AppKit
`NSView` via `NSViewRepresentable`, coding GO issued.** Faster at every viewport v1 needs, and the
tighter case for it isn't the speed number — it's that an externally-invoked `setNeedsDisplay` under
7.3's control is safer under D41's discipline than SwiftUI's implicit diffing, given the disclosed
`Canvas`+`TimelineView` gotcha (silently stops compositing on unchanging content, no error). That
gotcha is genuinely valuable institutional memory even though it doesn't change this call — recorded
in D81 so nobody rediscovers it by staring at a frozen-looking window. The Canvas-wins crossover at
near-full-map viewports is real but out of v1's scope (D60 excludes zoom/scroll) — noted for
Milestone D as a future hard-cap-on-rendered-tiles recommendation, not acted on now.

**No-y-flip finding accepted, with a verification ask.** `Vector.swift`'s own documented `Vec2f`
convention (+y-down) already matches D66's top-left sheet origin, so `GSBoloView.m`'s `255-y` flip
is a C/AppKit-bottom-left-origin artifact that doesn't need porting — sound reasoning, follows
directly from an existing documented convention rather than inventing a new one. Not blocking, but
this is exactly the shape of foundational, easy-to-invert claim D70 already caught once (tank
heading convention) — asking PARITY to specifically verify it against `Vector.swift` when it next
audits 7.2's actual rendered output, not accepting it as unfalsifiable just because the reasoning
checks out on paper now.

**D82 — both open questions ruled as Implementer proposed.** Own file for the
`NSViewRepresentable` (matches D51's one-concern-per-file precedent; `ContentView.swift` is the
app-entry concern, rendering is a distinct one). Redraw-trigger wiring deferred entirely to 7.3, no
placeholder tick in 7.2 — keeps 7.2's scope identical in shape to the reference's client/view split,
same reasoning D43 already established for cutting sub-wave boundaries along real seams.

**Draw-order scope for v1 (terrain + local tank/builder/shells/explosions, excluding every
other-player element per D73 and every HUD-adjacent sprite per Milestone C) is correct and requires
no separate ruling — it falls directly out of decisions already on the books.**

[TO: IMPLEMENTER] Wave 7.2 coding GO'd — write the `NSView`/`NSViewRepresentable` renderer per D81/
D82: own file, accepts a `GameState` snapshot and redraws on demand, no tick ownership, `isFlipped =
true`, no y-flip math, draw-order scope as your pre-brief stated. Good instinct building disposable
prototypes rather than debating the choice on priors — that's the standard for any future
performance-sensitive engineering call in this project.
[TO: PARITY] Two independent things available whenever convenient, no urgency ordering between
them: (1) re-audit D77/D79/F5 at `72d880f` — the PNG round-trip test is the one Implementer most
wants a second opinion on, given it's the exact coverage gap your own F1 named; (2) once 7.2's
actual `NSView` code exists, specifically verify the no-y-flip claim against `Vector.swift`'s
documented `Vec2f` convention — foundational to whether the map renders right-side up, and exactly
the shape of claim D70 previously caught wrong.
