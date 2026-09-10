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
//  `onSuperboomTerrain` (same file, already broadcasting to the network host-side). Threading
//  *new* callback parameters through `TankLocalTick.swift`'s shoot-handling (`tankshot`) or
//  `ShellTick.swift`'s `killTank` (`hittank`) for the remaining named-priority sounds is real
//  `BoloKit` surgery, not attempted in this pass -- disclosed, not silently dropped.
//
//  **D148(A) follow-up:** `tankshot` (cannon fire) and `tree` (harvest-complete) are now wired
//  too, via new `onTankShot`/`onTreeHarvest` callbacks threaded through `TankLocalTick.swift`'s
//  shell-fire branch and `BuilderTick.swift`'s `grabTrees`/`arriveAtTarget` `.getTree` completion
//  respectively (see those files' own doc comments at the fire sites). `hittank`'s `ShellTick.
//  swift`/`killTank` wiring is still not attempted -- out of D148(A)'s scope.
//
//  **`far*` variants and remote-player-triggered sounds are explicitly NOT wired.** The
//  reference's own near/far choice is a `client.fog[y][x] > 0` check (`client.c:1368` and
//  elsewhere) -- fog-of-war/seen-tiles is out of v1 scope entirely (D65: "treat every tile as
//  fully visible"), so there is no real signal to compute near-vs-far from yet. Every sound
//  wired here is inherently "near" regardless -- it's always the local player's own on-screen
//  action, never a remote player's relayed event (this port's join-mode client doesn't run the
//  callback-bearing `runTick` at all, D116 -- see `GameSession.swift`'s own B.8 header).
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
