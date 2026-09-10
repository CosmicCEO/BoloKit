//
//  DefaultMap.swift
//  Bolo 2026
//
//  D132: a small, freshly-authored map (never derived from any external map file) bundled with
//  the app so hosting works out of the box before a user ever imports a `.map` file via
//  `HostGameView`'s "Choose Map…" picker. These are the exact bytes `encodeBMap` produces for
//  `BoloKit.defaultBundledMapState()` (4 starts, 2 pills, 2 bases over stock `mapDefault()`
//  terrain) -- generated once via a throwaway `BoloKitTests` case (not kept, since the map-
//  authoring function it called, `defaultBundledMapState()`, is the permanent source of truth
//  in `Sources/BoloKit/BMap.swift`). Loaded through the exact same `decodeBMap` ->
//  `serverPostProcessLoadedMap` path a user-imported map takes -- see `HostGameView.swift`'s
//  shared `applyDecodedMap` helper.
//
//  GENERATED — do not hand-edit; regenerate from `defaultBundledMapState()` if that function
//  ever changes.
//
let defaultMapFileBytes: [UInt8] = [
    66, 77, 65, 80, 66, 79, 76, 79, 1, 2, 2, 4, 128, 60, 255, 15, 25, 128, 196, 255,
    15, 25, 60, 128, 255, 90, 90, 90, 196, 128, 255, 90, 90, 90, 40, 40, 4, 216, 40, 12,
    40, 216, 4, 216, 216, 12, 4, 255, 255, 255,
]
