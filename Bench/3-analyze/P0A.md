# P0a — land and re-read

Analyzer change: wire `fogComparableParts` from `FogCompare.swift` into
`comparableParts` in `Divergence.swift`:

```swift
    case .fog:
        return fogComparableParts(element: element, value: value)
```

`digestFogValue` bit 0 is currently visible. Visible tiles are not compared
on `fogSeen`.

Replace `fogIsComparedAsVisibleNowAndAsLastSeen` with:

- `fogMemoryIsIgnoredWhileTheTileIsVisible` — both visible, different seen → no `.fogSeen` episode
- `fogMemoryIsComparedOnlyWhileTheTileIsInFog` — both in fog, different seen → one `.fogSeen` episode

```
swift test --filter fogMemory
```

## Re-read (M1 only)

```
.build/release/BoloBench analyze <run-dir> --tier pair
# summaries under Bench/data/analyze/p0a-fog-join/ — not data/measure/
.build/release/BoloBench scorecard <scenario-dir>... --out Bench/data/analyze/p0a-fog-join/...
```

Leave `data/measure/v1.6.9-baseline/` frozen.
Do not un-quarantine builder-mine or tile-step from this scorecard.
