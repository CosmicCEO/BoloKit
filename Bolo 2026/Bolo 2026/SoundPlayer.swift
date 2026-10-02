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
//  **#149/#150 (v1.6.5 Sound Parity): `far*` variants are now wired, host path only, and the**
//  **real networked host/guest silence bug is fixed.** Two real, confirmed findings superseded
//  the paragraph this replaces:
//
//  1. `GameSession.tick()` (this file's only caller before #149) has exactly one caller of its
//     own: the single-process/solo `DispatchSource` timer. A REAL networked host
//     (`HostGameEngine`) never called `SoundPlayer` at all -- `hostEngine.start()` runs its own
//     internal tick loop, entirely separate from this file's `tick()`, and had no sound callback
//     of any kind. Fixed: `HostGameEngine.onShouldPlaySound` (`Sources/BoloNet/HostGameEngine.swift`)
//     now fires the same 15 names this file already knew about, wired at the host `init` below.
//     A joined guest was *also* completely silent (zero `SoundPlayer` calls existed on the join
//     path before this pass, confirmed by grep, not merely under-scoped) -- fixed for the guest's
//     own locally-predicted actions (`tankMoveTick`/`builderTick`/`shellTick`, all three already
//     called in `handleJoinEvent`'s `.tick` case). `onTankShot`/`onMine`/`onBubbles`/`onSink`/
//     `onPillShot` remain unreachable on the join path -- those need `tankLocalTick`/`pillTick`
//     itself, which D116 deliberately keeps off this path (see `GameSession.swift`'s own B.8
//     header); not expanded here.
//
//  2. `far*` near/far selection: the reference's own choice is a `client.fog[y][x] > 0` check
//     (`client.c:1368` and elsewhere) -- a real, always-active vision-radius system (tank/pillbox/
//     alliance vision boxes), unrelated to the separate `hiddenmines` flag. This port's own
//     equivalent (`FogState`/`isFog`, `CalcVis.swift`) is currently maintained ONLY when
//     `state.hiddenMines` is on, and ONLY on the host path (`HostGameEngine.fogStates`) -- so
//     near/far selection here is real and oracle-faithful whenever Hidden Mines is on, for the 7
//     location-bearing hooks (`onMineExplosion`/`onSuperboomTerrain`/`onExplosion`/
//     `onTreeHarvest`/`onHitTerrain`/`onHitTree`/`onBuild`); the other 8 hooks have no location
//     in their `runTick` signature at all and stay "near" always (disclosed, narrower remaining
//     gap, see #150). With Hidden Mines off (this port's default, matching D65's "every tile
//     fully visible" v1 decision) or on the solo/join paths (no `FogState` tracked there at all),
//     everything still plays "near" regardless of distance -- this is the real, larger,
//     already-known vision-system gap D65 disclosed, not something #149/#150 silently claims to
//     have closed.
//
//  `play(_:near:)` picks the far name via a local reverse of `SoundSetBuilder.swift`'s
//  `farNameSources` (duplicated here, not imported, since the app target doesn't currently link
//  `BoloSoundsCore` as a runtime dependency -- keep the two lists in sync by hand); a near name
//  with no far entry (`mine`/`pillshot`/`bubbles`/`msgreceived` -- matches the oracle, which has
//  no `kFarMineSound` etc. either) always plays its near clip regardless of `near`.
//
//  **2026-10-02 (Improve item 2D): the pool is now preloaded `AVAudioPlayerNode` slots on one**
//  **`AVAudioEngine`, not `NSSound`s.** `NSSound(byReference: true)` re-read and re-decoded its
//  AIFF from disk inside every `play()`, measured at 19 to 26 ms (p95) on the main thread for a
//  tick that plays a sound -- enough to make the host's 20 ms tick late. Loading into memory
//  (`byReference: false`) did not help (`NSSound.play()` still ~10 ms median) and neither did a
//  prepared `AVAudioPlayer` (`play()` ~15 ms: it starts its own I/O synchronously). So each clip
//  is decoded once into an `AVAudioPCMBuffer`, each pool slot is a node already attached to a
//  running engine, and `play()` is just `scheduleBuffer` (~0.02 ms). A slot is busy until
//  `now + clip duration` (a lock-guarded deadline; no completion-handler thread). Pool
//  sizes, names, round-robin (first free slot, skip if all busy) and the mute check are unchanged.
//

import AVFoundation
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

    /// #150: near-name -> far-name, a local copy of `SoundSetBuilder.swift`'s own
    /// `farNameSources` (reversed) -- see this file's header for why it's duplicated, not
    /// imported. `fshot` covers both `tankshot`'s and `pillshot`'s far variant (D122, no
    /// separate `fpillshot`); a near name absent here (`mine`/`pillshot`/`bubbles`/
    /// `msgreceived`) has no far variant at all, matching the oracle.
    private static let farNames: [String: String] = [
        "explosion": "fexplosion", "superboom": "fsuperboom", "hittank": "fhittank",
        "hitterrain": "fhitterrain", "hittree": "fhittree", "build": "fbuild",
        "builderdeath": "fbuilderdeath", "tree": "ftree", "sink": "fsink", "tankshot": "fshot",
    ]

    /// One pool slot: a node permanently attached to `engine`, the clip's decoded buffer, and
    /// the instant the last scheduled play ends (replaces `NSSound.isPlaying`).
    private struct Slot {
        let node: AVAudioPlayerNode
        let buffer: AVAudioPCMBuffer
        let duration: Duration
        var busyUntil: ContinuousClock.Instant
    }

    private let engine = AVAudioEngine()
    private let clock = ContinuousClock()
    private var pools: [String: [Slot]] = [:]
    private let lock = NSLock()  // `play()` may be called from a host tick thread
    private var configObserver: NSObjectProtocol?

    private init() {
        for (name, count) in Self.poolSizes {
            loadPool(name, count: count)
            if let farName = Self.farNames[name] {
                loadPool(farName, count: count)
            }
        }
        startEngine()
        // A device change stops the engine; bring it back so `play()` stays silent-failure free.
        configObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.startEngine() }
        }
    }

    private func startEngine() {
        guard (try? engine.start()) != nil else { return }
        lock.lock()
        defer { lock.unlock() }
        for slots in pools.values {
            for slot in slots { slot.node.play() }
        }
    }

    private func loadPool(_ name: String, count: Int) {
        guard let url = Bundle.main.url(forResource: name, withExtension: "aiff"),
              let file = try? AVAudioFile(forReading: url),
              let buffer = AVAudioPCMBuffer(
                pcmFormat: file.processingFormat, frameCapacity: AVAudioFrameCount(file.length)),
              (try? file.read(into: buffer)) != nil else { return }
        let duration = Duration.seconds(Double(file.length) / file.processingFormat.sampleRate)
        pools[name] = (0..<count).map { _ in
            let node = AVAudioPlayerNode()
            engine.attach(node)
            engine.connect(node, to: engine.mainMixerNode, format: buffer.format)
            return Slot(node: node, buffer: buffer, duration: duration, busyUntil: .now)
        }
    }

    /// Plays `name` (or its far variant, if `near` is false and one exists) on the first
    /// non-playing pool slot, silently doing nothing if every slot is busy (matches
    /// `playsound()`'s own `for` loop exactly -- it never queues or interrupts, just skips the
    /// sound if the whole pool is already in use) or if the resolved name isn't in this v1
    /// slice's wired set. Checks `"GSMuteBool"` on every call, not once at init, so toggling the
    /// preference mid-session takes effect immediately -- matching `playsound()`'s own
    /// `if (!muteBool)` guard, evaluated fresh every call.
    func play(_ name: String, near: Bool = true) {
        guard !UserDefaults.standard.bool(forKey: "GSMuteBool") else { return }
        let resolvedName = (!near ? Self.farNames[name] : nil) ?? name
        lock.lock()
        defer { lock.unlock() }
        guard var pool = pools[resolvedName] else { return }
        let now = clock.now
        for i in pool.indices where pool[i].busyUntil <= now {
            pool[i].node.scheduleBuffer(pool[i].buffer, at: nil, options: .interrupts)
            pool[i].busyUntil = now + pool[i].duration
            pools[resolvedName] = pool
            return
        }
    }
}
