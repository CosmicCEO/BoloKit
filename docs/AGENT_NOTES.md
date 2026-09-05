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
| `docs/notes/archive.md` | Waves 1–5 (5.0–5.7), pre-Wave-6 process, all of Wave 6 (6.0–6.3, the D39 fix, 6.6, 6.4a/6.4b/6.4c, 6.5a/6.5b, and the Wave 6 phase close-out), and all of Wave 7 (7.0–7.3, the full v1 vertical slice, D58–D89) compressed summaries — commit hashes, key findings, decision cross-references. Full uncompressed text preserved in git history. |

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

## Active Log (post-Wave-7)

> **Archived 2026-09-05:** Wave 7's entire v1 vertical slice (7.0 asset pipeline, 7.1 Xcode app
> target, 7.2 rendering, 7.3 input/tick loop — D58 through D89, including every pre-brief,
> completion report, and PARITY audit/re-audit in that span) has been compressed into
> `docs/notes/archive.md`. Full uncompressed entries preserved in git history per D28. The active
> log below now begins at the close of Wave 7's v1 vertical slice.

### [PLANNER] 2026-09-05 — D90 (Q27) and D91 (subagent-gating) ruled directly by Jerod

**Type:** two direct rulings, no code, no wave impact
**Phase:** post-Wave-7, pre-Milestone-B/C/D

**D90 — Q27 resolved: bundle identifier confirmed as `com.cosmicceo.Bolo-2026`**, aligning with
the GitHub org (`github.com/CosmicCEO/BoloKit`). Same shape as D58/D59: a direct ruling on a raised
question, adopted as final rather than provisional — no further action before Milestone D's
signing/notarization work. `docs/PLAN.md`'s Q-table and decisions log updated; the Wave 7.1 status
row's stale "still open" pointer corrected to point at D90.

**D91 — D85's standing yes/no subagent-dispatch gate is removed, superseded by this environment's**
**own built-in Auto Mode.** Same shape as D87 but permanent rather than scoped to one wave: PLANNER
no longer asks a yes/no question before spawning or handing work to a PARITY/Implementer/Admin
subagent — it acts directly, per Auto Mode's own standing guidance (proceed by default, redirect if
needed, still stop when genuinely blocked on a decision only Jerod can make). D85's and D87's text
both stand unmodified as the historical record; D91 supersedes the mechanism, not the reasoning.
This does not touch Jerod's decision authority over genuinely ambiguous/high-stakes product or
scope calls (architectural forks, Q-numbered questions) — only the routing checkpoint between role
handoffs is removed.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` (D90, D91, Q27 removed from open
questions, Wave 7.1 row correction).

[TO: IMPLEMENTER] No action needed — both rulings are process/product-identity, not code.
[TO: PARITY] No action needed.

### [PLANNER] 2026-09-05 — Milestone B/C/D pre-plan (D92), sized but not GO'd

**Type:** sizing/risk pre-plan, no coding GO issued
**Phase:** post-Wave-7, pre-Milestone-B/C/D
**Blocks:** nothing — this sizes and sequences, it does not authorize coding on any of B/C/D

Jerod asked for a pre-plan of Milestones B/C/D with help from Implementer/Parity subagents to
surface risks/gaps, dispatched directly under D91 (no yes/no gate needed). Two subagents ran in
parallel: an Implementer-lens pass (sizing + sub-wave splits, reading `Reference/c`'s actual
IBActions/IBOutlets and this project's existing `BoloNet`/`BoloKit` surface) and a Parity-lens pass
(independently verifying two claims from my own earlier read rather than taking them on faith, plus
hunting for fidelity gaps). Both came back clean on method — real file:line citations throughout,
no unverified assertions.

**D92 — closes Q18.** My own earlier read found `Reference/c` is a git submodule, not vendored
content, and that no copyrighted asset bytes exist anywhere in this project's own git history — the
Parity-lens agent independently re-derived all three sub-claims with fresh commands and confirmed
every one. Q18/D61's "git-history rewrite" premise doesn't hold: removing `Reference/c` at
Milestone D is a plain `git submodule deinit`, not a destructive rewrite. This meaningfully de-risks
Milestone D. D61's text corrected in place with a dated pointer, not rewritten; Q18 removed from
the open-questions table.

**Two corrections to my own earlier (unverified) framing, caught by the subagents rather than left
standing:**
1. Milestone C's key remap is not "expose already-shipped defaults for editing" — `InputKeymap.swift`
   is a hardcoded 7-case switch, only 6 of 14 reference bindings wired at all. C.1 must build the
   remappable model, not just a settings UI.
2. Milestone C's sound is not procedural synthesis — confirmed sample-based, 24 named `.aiff`
   effects via round-robin `NSSound` pools, zero DSP code in the reference. Smaller code footprint
   than I'd guessed, but needs licensed replacement assets (**Q28**, new) since the originals are
   Stuart Cheshire's copyrighted material.

**One new fidelity risk surfaced, inherited from D65 rather than new in kind:** the alliance system
and fog-of-war aren't independently scopable — `requestalliance()`/`leavealliance()` call
`increasevis()`/`decreasevis()` to merge shared vision, never modeled anywhere in this port
(already disclosed in `SessionLogic.swift`'s own header). Milestone C's alliance panel, built before
real fog-of-war exists, will functionally diverge from the reference (no vision reveal) — an
accepted, D65-consistent v1-shape gap the C.2 pre-brief should state explicitly. HUD status icons
were traced and confirmed independent of this — no equivalent risk there.

**One new gap surfaced for Milestone B:** the reference's `joinprogress()` dispatches 19 distinct
status codes (6 live progress states + 8 network-error cases) through one callback; `JoinClient.swift`
only models 6 protocol-rejection cases plus two framing catch-alls and has no progress-callback
mechanism at all. B.3's pre-brief will need new `JoinClient` surface area to replicate the
reference's live progress UI and per-failure messaging — not just app-side wiring.

**Sizing, relative to Wave 5 (10 sub-waves)/Wave 6 (11)/Wave 7 (4):** Milestone B (proposed B.0-B.4)
is closer to Wave 7's UI-wiring character — the hard networking work is done and tested in
`BoloNet`; the one new axis is this project's first `async`/`await` call across a SwiftUI/AppKit UI
boundary. Milestone C (proposed C.0-C.6) is the largest of the three by sub-wave count, but most
sub-waves are bind-existing-model-to-UI; C.1 (key remap) and C.3 (sound) are the two genuinely
harder pieces, with C.3 being the closest thing to a new engineering axis in either B or C (licensed
asset sourcing + new tick-loop hook plumbing, echoing Wave 7.0's asset-pipeline problem). Milestone D
is now the smallest and lowest-risk of the three post-D92, gated mostly on a non-engineering
dependency (Q29 — an Apple Developer Team ID for signing/notarization) rather than code complexity.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — D92 added; Q18 closed/removed;
Q28 (sound-asset licensing) and Q29 (signing Team ID) added; D61 and Wave 7's row corrected in
place; three new wave-table rows (Milestone B, C, D) added with proposed sub-wave splits, explicitly
**not GO'd**.

[TO: IMPLEMENTER] Nothing actionable yet — no coding GO issued on B, C, or D. When Jerod picks one
to GO, that milestone's first sub-wave gets a real pre-brief same as every prior wave; this entry is
sizing context, not a substitute for one.
[TO: PARITY] Nothing actionable yet, same reason. Your fidelity-risk findings (alliance/fog-of-war
non-independence, join-progress granularity gap) are recorded above for whichever sub-wave's
pre-brief eventually needs them.

### [PLANNER] 2026-09-05 — D93: Jerod GO's Milestone B first, execute B→C→D in alphabetical order

**Type:** coding GO, first of three milestones
**Phase:** Milestone B opens; C and D queued behind it
**Blocks:** nothing new — same pre-brief-first cadence as every prior wave

Jerod ruled on the pre-plan's open fork directly: **execute Milestone B, then C, then D, in
alphabetical order.** Logged as **D93**. Milestone B is coding GO'd now; C and D stay queued,
not GO'd, until the milestone ahead of each closes with a clean PARITY PASS — same sequencing
discipline Wave 7's own sub-waves used (7.0→7.1→7.2→7.3, each gated on the previous). This ruling
authorizes *sequencing*, not a shortcut past the pre-brief step D91 didn't touch.

Assigning IMPLEMENTER Milestone B's first sub-wave directly under D91 (no yes/no gate needed):
**B.0 — package/entitlement plumbing.** Per the pre-plan's proposed split (this file's prior entry,
and `docs/PLAN.md`'s Milestone B row): export `BoloNet` as a real SPM library product in
`Package.swift` (currently only `BoloKit`/`BoloGlyphs` are exported — this is D74's own "Milestone
B's mechanical first step" note, finally due), add the `ENABLE_OUTGOING_NETWORK_CONNECTIONS`/
`ENABLE_INCOMING_NETWORK_CONNECTIONS` entitlement keys to `Bolo 2026`'s build settings (D78 — these
don't exist as keys at all today, confirmed twice this pass, so they must be *added*, not flipped
from `NO`), and wire `Bolo 2026`'s target dependency on `BoloNet`. Verify the same way D74 did:
`codesign -d --entitlements -` on the signed product, confirming both keys now appear alongside the
existing `app-sandbox` entitlement.

**Docs updated (committed alongside this entry):** `docs/PLAN.md` — D93 added; Milestone B's row
marked coding-GO'd; Milestone C/D rows marked queued (2nd/3rd of 3, gated on the milestone ahead of
each closing clean).

[TO: IMPLEMENTER] Coding GO for Milestone B, starting with B.0 (package/entitlement plumbing,
scoped above). Write your pre-brief into this file before touching Swift, same cadence as every
prior wave — read `Package.swift`, the app's `project.pbxproj`, and `Sources/BoloNet/`'s public
surface yourself rather than taking this pre-plan's summary as a substitute for your own read. Flag
any open question (e.g. how you want to structure the `BoloNet` dependency wiring, or anything the
pre-plan's Implementer-lens research pass didn't cover) same as always.
[TO: PARITY] Nothing yet — standard post-commit activation once IMPLEMENTER reports B.0 complete.

### [IMPLEMENTER] 2026-09-05 — Milestone B.0 pre-brief: package/entitlement plumbing

**Type:** pre-brief (no production code yet)
**Phase:** Milestone B (D93's coding GO), sub-wave B.0 — package export + entitlements + target
dependency wiring, first of Milestone B's proposed B.0-B.4 split.

Read `Package.swift`, `Bolo 2026/Bolo 2026.xcodeproj/project.pbxproj`, and `Sources/BoloNet/`'s
directory/public-surface myself rather than taking D92/D93's summary as a substitute, per the
assignment. Confirms both cited gaps exactly as described, with the concrete mechanics below.

## 1. `Package.swift` — export `BoloNet` as a real library product

Current `products:` array (lines 9-15) has exactly two entries — `BoloKit` and the `BoloGlyphs`
executable — with a comment reading "`BoloNet` is deliberately not exported — the v1 slice is
single-process (D73); revisit at Milestone B." That revisit is now. Proposing:

```swift
products: [
    // Consumed by the `Bolo 2026` app target (Wave 7.1).
    .library(name: "BoloKit", targets: ["BoloKit"]),
    // Host/Join panels, Milestone B (D93) — exported now that the app target needs it.
    .library(name: "BoloNet", targets: ["BoloNet"]),
    // Build-time sheet generator, invoked from the app's Run Script phase (D72).
    .executable(name: "BoloGlyphs", targets: ["BoloGlyphs"]),
],
```

The stale "deliberately not exported" comment gets corrected in place (not left standing now that
it's wrong), same convention this project already uses for outdated notes elsewhere (D74's own
"recorded so a future session doesn't fix it" pattern, applied in reverse here — a note that would
otherwise mislead a future session into thinking the omission is still deliberate).

`BoloNet`'s own target declaration (`.target(name: "BoloNet", dependencies: ["BoloKit"])`) needs no
change — every symbol I can find in `Sources/BoloNet/` (126 `public` declarations across 18 files,
spot-checked, not exhaustively counted by hand) is already `public`; SPM's product export is purely
an availability change for consumers outside the package, not a visibility change inside it.
`DifferentialTests`' existing in-package dependency on `BoloNet` (`Package.swift:30`) is a target-to-
target reference and is unaffected by whether `BoloNet` is also exported as a product.

## 2. `project.pbxproj` — wire the target dependency

Read the actual object graph rather than assuming its shape. `Bolo 2026`'s existing `BoloKit`
wiring is exactly three parts, all under the single already-present `XCLocalSwiftPackageReference
".."` (no second package reference needed — same local package, one more product):

1. A `PBXBuildFile` entry (`"BoloKit in Frameworks"`, `productRef` → the product dependency below),
   listed in `PBXFrameworksBuildPhase`'s `files`.
2. An `XCSwiftPackageProductDependency` object (`productName = BoloKit`).
3. That dependency's ID listed in the target's own `packageProductDependencies`.

(Contrast `BoloGlyphs`, which has its own `XCSwiftPackageProductDependency` object but is wired
via a plain `PBXTargetDependency` for build-order only — never added to `packageProductDependencies`
or the Frameworks phase, since it's a build-time executable, never linked. `BoloNet` needs the
`BoloKit`-shaped wiring, not the `BoloGlyphs`-shaped one — the app will link and `import BoloNet`.)

Proposing the identical three-part addition for `BoloNet`: a new `PBXBuildFile` ("BoloNet in
Frameworks"), a new `XCSwiftPackageProductDependency` (`productName = BoloNet`), and both IDs added
to the Frameworks-phase `files` list and the target's `packageProductDependencies` list respectively.
Mechanical, same shape as the existing `BoloKit` entries, new object IDs only.

This is a hand-edit to `project.pbxproj`, against the MCP tools' standing "do NOT modify
`project.pbxproj` directly" warning — same situation D74 already hit and PLANNER accepted (no MCP
tool exists for adding a Swift package product dependency to an existing target; the alternative is
not doing the assigned work). Will verify structurally afterward the same way D74's edit was
verified: confirm the file stays `plutil`-parseable and that the object counts move by exactly the
expected amount (one new `PBXBuildFile`, one new `XCSwiftPackageProductDependency`, both IDs
referenced exactly once each in the expected lists) — no duplicates, no orphans.

## 3. Entitlement keys — add, not flip (D78)

Confirmed independently: neither `ENABLE_OUTGOING_NETWORK_CONNECTIONS` nor
`ENABLE_INCOMING_NETWORK_CONNECTIONS` appears anywhere in `project.pbxproj` today.
`ENABLE_APP_SANDBOX = YES;` is present in both the target's Debug and Release `XCBuildConfiguration`
blocks (`project.pbxproj:290`, `:321`) — the two build settings' keys sort alphabetically right
after it (`APP_SANDBOX` < `INCOMING` < `OUTGOING` < `PREVIEWS`), matching this file's existing
alphabetical key ordering within each `buildSettings` block. Proposing both keys, `= YES`, added to
both configs at that position — hosting (B.2) needs incoming, joining (B.3) needs outgoing, and
D93's own text asks for both now rather than staggering one per sub-wave.

**Verification, same standard as D74:** `codesign -d --entitlements -` on the signed product,
confirming the *synthesized entitlement keys* appear (Xcode maps `ENABLE_OUTGOING_NETWORK_CONNECTIONS`
→ `com.apple.security.network.client` and `ENABLE_INCOMING_NETWORK_CONNECTIONS` →
`com.apple.security.network.server` in the generated entitlements — stating the expected mapping
here but confirming it against the real signed output rather than asserting it, same discipline
D74 used for `app-sandbox`/`files.user-selected.read-only`/`get-task-allow`) alongside the existing
`app-sandbox` entitlement, not just that the build settings exist in the project file.

## 4. Build/test verification plan

`swift build`/`swift test` first (BoloKit/BoloNet/BoloGlyphs side — unaffected by this sub-wave's
changes, should stay exactly at the current count, no BoloKit/BoloNet Swift is touched). Then a
real `xcodebuild` for the `Bolo 2026` scheme — the known Run Script toolchain hang (Wave 7.1/7.2)
did *not* recur on Wave 7.3's build, so attempting it directly rather than pre-emptively assuming a
hang; will fall back to the established substitute-verification path (kill the stuck process,
verify via direct inspection of the built artifacts) if it does recur, and will say so plainly if it
does. `codesign -d --entitlements -` on the resulting `.app` is the actual acceptance check per §3.

## 5. Judgment calls / open questions

1. **No `import BoloNet` anywhere yet.** B.0 wires the dependency structurally (product export +
   `.pbxproj` link + entitlements) but has nothing to use it *for* — B.1 (navigation shell) doesn't
   exist yet, so there's no call site. An unused linked product doesn't fail the build or the
   entitlement check, so I'm treating "wire the target dependency" as the structural link, not a
   requirement to add a smoke-test `import` somewhere. Flagging this reading explicitly in case
   you intended a minimal proof-of-import as part of B.0's acceptance bar rather than deferring
   that proof to B.1's first real usage.
2. **Scope boundary against B.1-B.4:** confirming (not re-deciding) that B.0 stops at "the app *can*
   link and import `BoloNet`, and *can* legally make network connections once sandboxed" — no
   navigation shell, no Host/Join UI, no actual `HostSession`/`JoinClient` call anywhere in this
   sub-wave. Matches D93's own text; stating it here so the completion report has an explicit line
   to check against.

No Jerod-level product/architecture question identified — everything above is mechanical plumbing
within the already-GO'd scope. Awaiting coding GO.

### [PLANNER] 2026-09-05 — B.0 pre-brief reviewed, coding GO'd as proposed

**Type:** pre-brief review, coding GO
**Phase:** Milestone B, sub-wave B.0

Approved as briefed, no corrections. The `Package.swift`/`.pbxproj` mechanics are the right shape —
`BoloNet` genuinely needs the `BoloKit`-shaped three-part wiring (linked product, not
`BoloGlyphs`'s build-order-only dependency), and treating the `.pbxproj` hand-edit the same way
D74 did (no MCP tool covers this, verify structurally after: object counts move by exactly the
expected amount, no dupes/orphans) is correct precedent, correctly applied, not just cited. The
entitlement-key alphabetical placement and the "confirm the synthesized keys on the signed product,
don't just trust the build-setting names" verification standard both match D74/D78 exactly.

**Judgment call 1 (no smoke-test `import BoloNet` in B.0) — agreed, as read.** B.0 is structural
plumbing; requiring a throwaway import to "prove" the link works would be weaker verification than
the `codesign -d --entitlements -` check already planned, which proves the thing that actually
matters (the app can legally make network connections once sandboxed). B.1's navigation shell will
be the first real usage — that's where an actual `import BoloNet` call site belongs, not manufactured
early for its own sake.

**Judgment call 2 (B.0's scope boundary) — confirmed, matches D93's text exactly.** No navigation
shell, no Host/Join UI, no `HostSession`/`JoinClient` call anywhere in this sub-wave — purely "the
app can link and import `BoloNet`, and can legally make network connections once sandboxed."

**Coding GO issued for B.0 as proposed.** Write the code, run the verification plan in §4 exactly as
scoped (Swift test suite unaffected, real `xcodebuild`, `codesign` entitlement check), and report
before/after test counts even though none are expected to change (D28 discipline applies to
confirming a count *didn't* move, not just to counting increases).

[TO: IMPLEMENTER] Coding GO for B.0. Proceed exactly as briefed. Report back the same way as every
prior wave — completion report in this file, explicit pathspec commit, before/after test counts,
and the actual `codesign` output confirming both entitlement keys landed correctly.
[TO: PARITY] Nothing yet — standard post-commit activation once IMPLEMENTER reports B.0 complete.

### [PLANNER] 2026-09-05 — B.0 completion report reviewed, PARITY activated

**Type:** review, PARITY activation
**Phase:** Milestone B, sub-wave B.0 — coded (`27c200c`), report (`89fadd4`), pending PARITY

Reviewed the actual diff, not just the completion report's prose. `Package.swift`'s stale
"deliberately not exported" comment is corrected in place exactly as the pre-brief said it would
be, not left standing. The `.pbxproj` hand-edit is the identical three-part shape `BoloKit` already
has (`PBXBuildFile` in the Frameworks phase, `XCSwiftPackageProductDependency`, and the ID in
`packageProductDependencies`) — not `BoloGlyphs`'s build-order-only shape, exactly the distinction
the pre-brief drew. Both entitlement keys land in both Debug and Release configs, alphabetically
positioned between `ENABLE_APP_SANDBOX` and `ENABLE_PREVIEWS` exactly as proposed. Minimal, no
stray changes — `Package.swift` + `.pbxproj` only, nothing else touched.

Going further than the pre-brief's own acceptance bar (a real `nm` check confirming 5,283
`BoloNet`-module symbols are actually linked into the Debug dylib, not just declared in the project
file) is exactly the kind of verification this project has valued since Wave 7.1 — proving the
*state*, not the intent. The `codesign` output confirms all five expected entitlements
(`app-sandbox`/`files.user-selected.read-only`/`get-task-allow` untouched,
`network.client`/`network.server` newly present) — matches the predicted
`ENABLE_OUTGOING_NETWORK_CONNECTIONS`→`network.client`/`ENABLE_INCOMING_NETWORK_CONNECTIONS`→
`network.server` mapping stated in the pre-brief, confirmed rather than just asserted, same as D74's
standard. 639→639 tests, correctly unaffected since no BoloKit/BoloNet Swift was touched.

**Activating PARITY for B.0.** Holding B.1's coding GO until B.0 gets a clean PARITY PASS — same
sequencing discipline as every Wave 7 sub-wave (7.0→7.1→7.2→7.3, each gated on the previous
closing clean before the next sub-wave's pre-brief started). B.1's pre-brief can be drafted whenever
IMPLEMENTER wants to get ahead of the audit, but its coding GO waits for B.0's PARITY PASS.

[TO: PARITY] B.0 ready for audit at `27c200c`+`89fadd4`. Check: the `Package.swift` product export
is purely additive (no visibility change needed inside `BoloNet`, since everything cited is already
`public`); the `.pbxproj` hand-edit's three new/modified sections are exactly the `BoloKit`-shaped
wiring (not `BoloGlyphs`'s), with no duplicate or orphaned object IDs; both entitlement keys are
genuinely new (D78 — confirm neither existed on `main` before this commit, not just that they're
`= YES` now); and independently verify the `codesign`/`nm` claims on a real build rather than taking
the completion report's output at face value, same standard as every prior sub-wave's audit.
[TO: IMPLEMENTER] Nice work, and the `nm` check beyond the pre-brief's own bar was the right call —
confirms the state rather than the file's stated intent. Feel free to start B.1's pre-brief
(navigation shell) in parallel if you want to get ahead of PARITY's audit, but its coding GO is
gated on B.0's clean PASS, same as every prior wave.

### [IMPLEMENTER] 2026-09-05 — Milestone B.0 completion report

**Type:** completion report
**Phase:** Milestone B — sub-wave B.0 (package/entitlement plumbing), coding GO'd `4519622`
**Commit:** `27c200c`

Implemented exactly as GO'd, no scope beyond the pre-brief.

## What landed

- **`Package.swift`:** `products:` gained `.library(name: "BoloNet", targets: ["BoloNet"])`. The
  now-stale "`BoloNet` is deliberately not exported" comment corrected in place. No target-level
  change needed — every symbol in `Sources/BoloNet/` was already `public`.
- **`project.pbxproj`:** three-part addition mirroring `BoloKit`'s existing wiring exactly (not
  `BoloGlyphs`'s build-order-only shape): new `PBXBuildFile` (`"BoloNet in Frameworks"`, object ID
  `B01A0004304B70C6007A9580`) referencing a new `XCSwiftPackageProductDependency`
  (`B01A0012304B70C6007A9580`, `productName = BoloNet`), the build-file ID added to
  `PBXFrameworksBuildPhase`'s `files`, the product-dependency ID added to the target's
  `packageProductDependencies`. No new `XCLocalSwiftPackageReference` — same local package
  reference already covers it.
- **Entitlements:** `ENABLE_INCOMING_NETWORK_CONNECTIONS = YES;` and
  `ENABLE_OUTGOING_NETWORK_CONNECTIONS = YES;` added to both the Debug and Release
  `XCBuildConfiguration` blocks for the `Bolo 2026` target, positioned alphabetically right after
  `ENABLE_APP_SANDBOX` to match the file's existing key ordering.

## Verification

- **Structural check on the hand-edit** (same standard as D74, applied before attempting a build):
  `plutil -lint` clean. Object counts moved by exactly the expected amount and nothing else:
  `PBXBuildFile` 1→2, `XCSwiftPackageProductDependency` 2→3, `ENABLE_INCOMING_NETWORK_CONNECTIONS`/
  `ENABLE_OUTGOING_NETWORK_CONNECTIONS` exactly 2 occurrences each (Debug+Release, no dupes).
  `XCLocalSwiftPackageReference`, `PBXTargetDependency` (the `BoloGlyphs` build-order dependency),
  and `PBXNativeTarget` counts all unchanged at 1 each — nothing else disturbed.
- **`swift build`/`swift test`:** clean, 156 + 483 = 639 tests, unaffected (no `BoloKit`/`BoloNet`
  Swift touched this sub-wave) — same total as Wave 7's close.
- **Real `xcodebuild -scheme "Bolo 2026" build`: `** BUILD SUCCEEDED **`.** No toolchain hang this
  run (SPM re-resolved the package graph for the new product with no issue).
- **`codesign -d --entitlements -` on the signed `Bolo 2026.app`** — full output:
  ```
  com.apple.security.app-sandbox = true
  com.apple.security.files.user-selected.read-only = true
  com.apple.security.get-task-allow = true
  com.apple.security.network.client = true
  com.apple.security.network.server = true
  ```
  Confirms the pre-brief's stated mapping (`ENABLE_OUTGOING_NETWORK_CONNECTIONS` →
  `network.client`, `ENABLE_INCOMING_NETWORK_CONNECTIONS` → `network.server`) against the real
  signed output, alongside the three pre-existing entitlements untouched.
- **Confirmed `BoloNet` is actually linked, not just declared:** `nm` on
  `Bolo 2026.debug.dylib` (the Debug-mode executable's actual code, distinct from the thin
  `Bolo 2026` launcher binary) shows 5,283 mangled `BoloNet`-module symbols present — the product
  dependency isn't a no-op declaration, the app binary genuinely contains `BoloNet`'s code.

## Scope check

Touched only `Package.swift` and `Bolo 2026/Bolo 2026.xcodeproj/project.pbxproj`. No Swift source
written — no `import BoloNet` anywhere yet, matching the pre-brief's confirmed scope boundary (no
smoke-test import; B.1's navigation shell is the first real call site). Did not touch
`docs/PLAN.md`, the three Director-owned untracked files, or anything in Wave 7's closed surface.

Test count: 639 → 639 (unaffected, no BoloKit/BoloNet source changed this sub-wave).

> **→ Planner:** B.0 implemented exactly as GO'd. Real `xcodebuild` succeeded (no hang), structural
> `.pbxproj` check clean, and the `codesign` entitlement output has all five expected entries
> including both new network entitlements. No new open questions. Ready for PARITY's audit
> whenever you activate it, and ready for B.1's pre-brief whenever you assign it.
> **→ Parity:** straightforward to re-derive independently — `plutil -lint` plus the object-count
> deltas above on `project.pbxproj`, a diff of `Package.swift`'s `products:` array, and your own
> `codesign -d --entitlements -` run against a fresh build. No behavioral/simulation code changed
> this sub-wave, so no C-oracle re-derivation applies here.
