//
//  SoundPlayer.swift
//  Bolo 2026
//
//  Milestone C.3 follow-up (D125) -- plays the 24 procedurally-synthesized `.aiff` effects
//  (`Sources/BoloSoundsCore`, bundled at build time by D124's Run Script) on real gameplay
//  events. Ported from `playsound()` (`Reference/c/Mac OS X/GSXBoloController.m:3619-3733`)
//  exactly: a small round-robin pool of `NSSound` instances per name, scanned for the first
//  slot that `!isPlaying`, matching the reference's own pool-sizing intent (explosion/tankshot/
//  hittank get more concurrent slots than rare one-shots like sink/builderdeath). `muteBool`'s
//  check (`if (!muteBool)`) is C.5's own `"GSMuteBool"` `@AppStorage` key, read directly here via
//  `UserDefaults.standard` rather than a second `@AppStorage` property (this type is a plain
//  singleton, not a SwiftUI view).
//
//  **v1 scope, time-boxed (D125): only the sounds reachable from this port's already-existing**
//  **callback hooks are wired here** -- `onExplosion`/`onSuperboom`/`onSmallboom` (`RunTick.swift`,
//  already threaded through, previously always defaulted to no-ops) and `onMineExplosion`/
//  `onSuperboomTerrain` (same file, already broadcasting to the network host-side).
//
//  **D148(A) follow-up:** `tankshot` (cannon fire) and `tree` (harvest-complete) are wired via
//  `onTankShot`/`onTreeHarvest` callbacks threaded through `TankLocalTick.swift`'s shell-fire
//  branch and `BuilderTick.swift`'s `grabTrees`/`arriveAtTarget` `.getTree` completion.
//
//  **Issue #8: the remaining 9 designed sounds are now wired too**, via new `RunTick.swift`
//  callback parameters (all defaulting to no-ops, so every pre-existing call site is unaffected):
//  `onHitTank`/`onHitTerrain`/`onHitTree` (`ShellTick.swift`'s `shellTick`/`applyDamage`),
//  `onMine` (`TankLocalTick.swift`'s `plantMine` call sites -- LMINE keydown and the continuous
//  lay-while-moving branch), `onBuild` (`BuilderTick.swift`'s `arriveAtTarget` success branches --
//  road/wall/boat/pill/repair/mine), `onBuilderDeath` (`TankLocalTick.swift`'s `killBuilder`,
//  fired unconditionally, reached from every mine-detonation/splash-damage/shell-collision path
//  that can kill a builder), `onSink` (`drown`), `onBubbles` (`tankLocalTick`'s river-drain
//  branch), and `onPillShot` (`PillTick.swift`'s `emitPillShell`). Fog-dependent `far*` variants
//  remain out of scope (see below) -- these are all "near" names.
//
//  **`far*` variants are explicitly NOT wired.** The reference's own near/far choice is a
//  `client.fog[y][x] > 0` check (`client.c:1368` and elsewhere) -- fog-of-war/seen-tiles is out
//  of v1 scope entirely (D65: "treat every tile as fully visible"), so there is no real signal to
//  compute near-vs-far from yet.
//
//  **Not every sound wired here is the local player's own action.** `onTankShot`/`onTreeHarvest`/
//  `onMine` are local-player-only (`TankLocalTick.swift` only ever runs for `state.localPlayer`).
//  But `onHitTank`/`onBuild`/`onBuilderDeath`/`onSink`/`onPillShot` fire for *any* connected
//  player's shells/builder/tank/pillbox -- `shellTick`'s tank-hit loop, `builderTick`'s per-player
//  call, and the mine-detonation/splash-damage chain (`explosionAt`/`superboomAt`) all run once
//  per player, not just the local one. With fog out of scope (D65: every tile fully visible),
//  there's no near/far signal to gate these on, so the local player now hears every player's hit/
//  build/death/sink/pill-shot map-wide, not just their own -- a real behavior change from the
//  four sounds wired before this pass, all of which happened to be local-player-only. Remote-
//  player-triggered sounds are still not wired for the *join* client specifically: this port's
//  join-mode client doesn't run the callback-bearing `runTick` at all (D116 -- see
//  `GameSession.swift`'s own B.8 header), so a join client only ever hears its own locally-
//  predicted actions regardless of this pass.
//

import AppKit

final class SoundPlayer {
    static let shared = SoundPlayer()

    /// Pool sizes chosen to mirror the reference's own implied concurrency (frequent, often-
    /// simultaneous sounds like `explosion`/`tankshot`/`hittank` get more slots than rare
    /// one-shots) -- not a literal port of a specific reference constant, since `playsound()`'s
    /// arrays are populated by however many `NSSound` copies `GSXBoloController` happened to
    /// preload per name, not a single named pool-size table.
    private static let poolSizes: [String: Int] = [
        "explosion": 3, "superboom": 2, "hittank": 3, "hitterrain": 2, "hittree": 2,
        "mine": 2, "tankshot": 3, "pillshot": 2, "build": 2, "builderdeath": 1,
        "tree": 2, "bubbles": 2, "sink": 1, "msgreceived": 1,
    ]

    private var pools: [String: [NSSound]] = [:]

    private init() {
        for (name, count) in Self.poolSizes {
            guard let url = Bundle.main.url(forResource: name, withExtension: "aiff") else { continue }
            pools[name] = (0..<count).compactMap { _ in NSSound(contentsOf: url, byReference: true) }
        }
    }

    /// Plays `name` on the first non-playing pool slot, silently doing nothing if every slot is
    /// busy (matches `playsound()`'s own `for` loop exactly -- it never queues or interrupts,
    /// just skips the sound if the whole pool is already in use) or if the name isn't in this
    /// v1 slice's wired set. Checks `"GSMuteBool"` on every call, not once at init, so toggling
    /// the preference mid-session takes effect immediately -- matching `playsound()`'s own
    /// `if (!muteBool)` guard, evaluated fresh every call.
    func play(_ name: String) {
        guard !UserDefaults.standard.bool(forKey: "GSMuteBool") else { return }
        guard let pool = pools[name] else { return }
        for sound in pool where !sound.isPlaying {
            sound.play()
            return
        }
    }
}
