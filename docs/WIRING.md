# BoloKit wiring

How **Bolo 2026** is put together: SPM packages, the three session modes, host/join network paths, and the 50 Hz tick. Grounded in `Package.swift`, `Sources/`, and `Bolo 2026/`. For fidelity rules see [CONSTRAINTS.md](CONSTRAINTS.md); for ship state see [STATUS.md](STATUS.md); for agent constraints see [`AGENTS.md`](../AGENTS.md).

## 1. Packages and targets

```mermaid
flowchart TB
  subgraph app["Bolo 2026 (Xcode app)"]
    UI["SwiftUI / AppKit UI"]
    GS["GameSession"]
    GRV["GameRenderView"]
    HUD["HUDSnapshot"]
    SP["SoundPlayer"]
  end

  subgraph spm["SwiftPM"]
    BK["BoloKit<br/>sim + GameState"]
    BN["BoloNet<br/>host / join / wire"]
    CX["CXBolo<br/>C oracle bridge"]
    BG["BoloGlyphs + Core"]
    BS["BoloSounds + Core"]
  end

  subgraph tests["Tests"]
    BKT["BoloKitTests"]
    DT["DifferentialTests"]
    APT["Bolo 2026Tests"]
  end

  subgraph oracle["Oracle"]
    REF["Reference/c<br/>bananazon/xbolo submodule"]
  end

  UI --> GS
  GS --> BK
  GS --> BN
  GS --> GRV
  GS --> HUD
  GS --> SP
  BN --> BK
  BG --> BK
  BKT --> BK
  DT --> BK
  DT --> BN
  DT --> CX
  CX -.-> REF
  APT --> GS
```

| Product | Role |
|---------|------|
| `BoloKit` | Authoritative `GameState`, physics, ticks, fog, map tiles. No `Foundation`. |
| `BoloNet` | Host engine, join client, TCP/UDP sessions, Bonjour, tracker, UPnP, codecs. Depends on `BoloKit`. |
| `CXBolo` | C sources compiled for bit-for-bit differential tests (`-ffp-contract=off`). |
| `BoloGlyphs` / `BoloSounds` | Build-time generators (Run Script phases); not runtime. |
| `Bolo 2026` | Playable Mac app: chrome, render, input, owns `GameSession`. |

Dependency direction is one-way: **app → BoloNet → BoloKit**. `BoloKit` never imports `BoloNet`; net cadence (`seq`, CL emission) stays in the app / `BoloNet`.

## 2. Three session modes

`GameSession` is the app-side hub. It has three constructions; only one is active per play.

```mermaid
flowchart LR
  subgraph modes["GameSession modes"]
    SP_MODE["Single-process<br/>local GameState + own 50 Hz timer"]
    HOST["Host<br/>delegates tick to HostGameEngine"]
    JOIN["Join<br/>own timer + TCP/UDP join consumer"]
  end

  SP_MODE -->|"runTick on self.state"| TICK["50 Hz runTick"]
  HOST -->|"HostGameEngine owns GameState + timer"| ENG["HostGameEngine"]
  ENG --> TICK
  JOIN -->|"merged JoinEvent stream"| TICK
```

| Mode | Who owns `GameState` | Who fires the timer | Local input |
|------|----------------------|---------------------|-------------|
| Single-process | `GameSession.state` | `GameSession` `DispatchSourceTimer` | Mutates `state` directly |
| Host | `HostGameEngine` (live) | Engine’s own timer; session timer **not** created | `submitLocal*` → engine event stream |
| Join | `GameSession.state` (post-handshake) | Session timer + TCP/UDP producers → one consumer | Local tank → `CLUpdate` on UDP |

Host path: session keeps a **snapshot** of state at init for bookkeeping; rendering goes through the engine’s tick callbacks (`onTickRendered`), not by re-reading that snapshot as truth.

## 3. Host path

```mermaid
sequenceDiagram
  participant UI as HostGameView
  participant GS as GameSession
  participant HGE as HostGameEngine
  participant TCP as Host TCP
  participant UDP as Host UDP
  participant TK as Tracker and UPnP
  participant Sim as runTick
  participant Out as Render HUD Sound

  UI->>GS: init with hostEngine
  UI->>GS: start
  GS->>HGE: start
  HGE->>TCP: accept joins
  HGE->>UDP: relay CL and broadcast SR
  opt discovery
    HGE->>TK: startNetworkDiscovery
  end
  loop every 50 Hz tick
    HGE->>Sim: runTick and apply CL
    HGE->>UDP: SR and dgram relay
    HGE-->>GS: onTickRendered
    GS->>Out: render HUD sounds
  end
  UI->>GS: local input builder chat
  GS->>HGE: submitLocal
```

Key types (`Sources/BoloNet/`):

- `HostGameEngine` — merged event stream, single consumer of `GameState`, fog per slot, broadcasts.
- `HostListener` / `HostAcceptLoop` / `HostSession` — TCP join / control plane.
- `HostDgramListener` / `DgramServerRelay` — UDP gameplay plane.
- `BonjourDiscovery`, `TrackerRegistration`, `PortMapping` — find-and-share (best-effort).

## 4. Join path

```mermaid
flowchart TB
  JV["JoinGameView"] --> JC["JoinClient<br/>TCPSession.join"]
  JC -->|"TCP + UDP live<br/>initial GameState"| GS["GameSession"]
  GS --> CONS["startJoinConsumer<br/>merged JoinEvent stream"]

  subgraph producers["Producers"]
    TCP["TCPSession<br/>SR messages"]
    UDP["UDPSession<br/>relayed CLUpdate"]
    TMR["DispatchSourceTimer<br/>tick"]
  end

  TCP --> CONS
  UDP --> CONS
  TMR --> CONS

  CONS --> APPLY["apply SR / CL<br/>runTick locally"]
  APPLY --> SEND["sendLocalUpdateIfDue<br/>about 10 Hz"]
  SEND --> UDP
  APPLY --> OUT["GameRenderView<br/>HUDSnapshot"]
```

```mermaid
sequenceDiagram
  participant UI as JoinGameView
  participant JC as JoinClient
  participant GS as GameSession
  participant TCP as TCPSession
  participant UDP as UDPSession
  participant Sim as GameState
  participant Out as Render and HUD

  UI->>JC: connect host
  JC-->>UI: hand off TCP UDP and initial state
  UI->>GS: init join sessions
  GS->>GS: startJoinConsumer
  loop join consumer
    TCP-->>GS: SR RawMessage
    UDP-->>GS: relayed CLUpdate
    GS->>GS: JoinEvent tick
    GS->>Sim: apply SR CL then runTick
    GS->>UDP: sendLocalUpdateIfDue
    GS->>Out: render and HUD
  end
```

Key types:

- `JoinClient` / `JoinClientApply` — handshake and initial map.
- `TCPSession` / `UDPSession` / `WireIO` — framed I/O.
- `CLUpdateCodec`, `ClientMessages`, `ServerMessages`, `Preambles` — wire shapes.
- `RecvSR` / `RecvCL` (in `BoloKit`) — decode into `GameState`.
- Join lag tint uses `UDPSession.lastUpdate(for:)` vs local `seq` (v1.4.0 #3).

Guest is still a **partial client** for some gameplay (fire, range, drown/barge). Product ruling: [#59](https://github.com/CosmicCEO/BoloKit/issues/59).

## 5. Tick loop (50 Hz)

`ticksPerSec` is 50 (`Physics.swift`). Orchestrator: `runTick` in `Sources/BoloKit/RunTick.swift` (unified port of C `runserver` + `runclient` order — synthesis, not a C interleaving).

```mermaid
flowchart TB
  START["runTick"] --> PAUSE{"serverPauseTicks or<br/>clientPauseDisplaySeconds?"}
  PAUSE -->|paused| RET1["return"]
  PAUSE -->|running| TL["time-limit / base-control checks"]
  TL --> INC["state.ticks += 1"]
  INC --> LAG["stale-player disconnect + dropPills"]
  LAG --> WORLD["coolPills then replenishBases<br/>then growTrees then chain then flood"]
  WORLD --> MOVE["tankMoveTick all players"]
  MOVE --> LOCAL["tankLocalTick local player"]
  LOCAL --> BLD["builderTick all"]
  BLD --> PILL["pillTick"]
  PILL --> SHELL["shellTick all"]
  SHELL --> EXP["explosionTick"]
```

Callbacks from `runTick` (sounds, broadcasts, lag UI) are closures supplied by `GameSession` or `HostGameEngine` — that is how `BoloKit` stays free of a `BoloNet` dependency.

Fog / vision: `FogState`, `CalcVis`, host-authoritative redaction on the wire (`SRRevealTerrain`, etc.). Deliberate deviation from C’s client-side filter — see CONSTRAINTS “Fog-of-war”.

## 6. UI chrome (app layer)

```mermaid
flowchart TB
  APP["Bolo_2026App"] --> ROOT["AppRootView"]
  ROOT --> NEW["NewGameView"]
  NEW --> HOSTV["HostGameView"]
  NEW --> JOINV["JoinGameView"]
  HOSTV --> GV["GameView"]
  JOINV --> GV
  GV --> GS["GameSession"]
  GS --> GRV["GameRenderView"]
  GS --> HUD["HUDSnapshot to gauges and player grid"]
  GS --> MSG["MessagesView / chat"]
  GS --> SP["SoundPlayer"]
  INPUT["keyboard mouse GameControllerInput"] --> GS
```

Also: `bolo://` (`BoloJoinURL`), App Intents (`HostGameIntent` / `JoinLastHostIntent`), preferences / key bindings.

## 7. Oracle and tests

```mermaid
flowchart LR
  XC["DifferentialTests"] --> SWIFT["BoloKit Swift"]
  XC --> C["CXBolo + Reference/c"]
  SWIFT -.->|"same inputs"| CMP["compare outputs"]
  C -.-> CMP
```

- Live executable spec: submodule `Reference/c` ([bananazon/xbolo](https://github.com/bananazon/xbolo), MIT).
- Cheshire original art/sound: never copy; glyphs/sounds are generated.
- WinBolo/LinBolo: GPL — read-only clean-room, no import.

## 8. Future optimization

**GPU (Metal compute) offload for fog/tile-grid resolution — idea, parked, not scheduled.**
Tracking issue: [#160](https://github.com/CosmicCEO/BoloKit/issues/160).

[#159](https://github.com/CosmicCEO/BoloKit/issues/159) (client-side fog gating for the join/solo
render paths, 2026-09-24) wired real per-tick fog resolution into paths that previously always
rendered unfogged. Measured cost, Debug build (`-Onone`, what a real desktop session actually
runs today) with Hidden Mines on:

| Path | Per-tick cost | Share of the 20 ms tick budget |
|------|---------------|----------------------------------|
| Unfogged (`displayTileGrid`, pre-#159 behavior) | ~9 ms | ~45% |
| Fogged (`fogResolvedTileGrid`, current) | ~16–17 ms | ~80–85% |

Tests pass reliably with margin at this cost, but the margin (~3–4 ms/tick) is tighter than
ideal — any future per-tick work added to the join/solo path eats directly into it.

```mermaid
flowchart LR
  subgraph current["Current: CPU-only, every tick"]
    LIVE1["state.terrain / pills / bases"] --> RESOLVE["fogResolvedTileGrid<br/>CPU loop, 65536 tiles"]
    FOG1["FogState.fog / seenTiles"] --> RESOLVE
    RESOLVE --> GRID1["TileGrid.storage<br/>(CPU array)"]
    GRID1 --> CALCVIS["calcVis / tileFor<br/>gameplay hit-testing"]
    GRID1 --> UPLOAD["upload to GPU as texture"]
    UPLOAD --> DRAW1["MetalTileRenderer draw"]
  end
```

```mermaid
flowchart LR
  subgraph proposed["Proposed: Metal compute kernel"]
    LIVE2["state.terrain / pills / bases"] --> BUF1["GPU buffer"]
    FOG2["FogState.fog / seenTiles"] --> BUF2["GPU buffer"]
    BUF1 --> KERNEL["Metal compute kernel<br/>per-tile select/substitute<br/>(embarrassingly parallel)"]
    BUF2 --> KERNEL
    KERNEL --> GPUOUT["GPU-resident resolved grid"]
    GPUOUT --> DRAW2["LiveMetalTerrainOverlay draw<br/>(no CPU round trip)"]
    GPUOUT -.->|"readback only if gameplay<br/>logic needs it"| CALCVIS2["calcVis / tileFor<br/>gameplay hit-testing"]
  end
```

**Why this is a plausible GPU candidate:** `fogResolvedTileGrid`/`displayTileGrid`
(`Sources/BoloKit/FogState.swift` / `Tiles.swift`) is a fixed-size (256×256), embarrassingly
parallel per-tile select/substitute transform with no cross-tile dependencies within a single
resolve pass — exactly the shape GPU compute shines at. The project already has Metal rendering
infrastructure from the v1.6.0 renderer (`MetalTileRenderer`, `LiveMetalTerrainOverlay`) a
compute-kernel output could feed directly, avoiding a CPU round trip if the result stays
GPU-resident for drawing (right diagram above).

**Why the Neural Engine (ANE/NPU) is ruled out:** present on every Apple Silicon Mac since the
M1 (2020; the underlying ANE itself debuted on the A11 Bionic, iPhone 8/X, 2017), but it's
built for CoreML-style neural-network inference (matrix multiplies) and isn't addressable
outside CoreML — a poor match for this workload's branchy, lookup-dependent substitution logic
(mine reveal state, sticky-reveal rules per `applyMineSubstitution`).

**Real tradeoffs, not a free win** (full detail in #160): CPU-side gameplay code (`calcVis` per
sprite, `tileFor` hit-testing) still needs to read individual resolved tiles, so a GPU-only
pipeline needs either a synced CPU fallback or a broader shift to make gameplay logic
GPU-buffer-aware; GPU dispatch overhead at this grid size is unmeasured and could eat into the
win; a Release (`-O`) build's real number is also unmeasured, and Debug's ~16-17ms may already
have healthier margin in what actually ships.

**Recommendation:** park until/unless the tick budget becomes a real constraint, then prototype
with a benchmark comparing GPU dispatch+readback cost against the current ~16 ms CPU number
before committing to the architecture change.

## 9. Related docs

| Doc | Topic |
|-----|--------|
| [STATUS.md](STATUS.md) | Ship version, open PRs, milestones |
| [CONSTRAINTS.md](CONSTRAINTS.md) | Physics constants, fog deviation |
| [ORACLE_COVERAGE.md](ORACLE_COVERAGE.md) | C-function coverage snapshot |
| [notes/HOSTMODELS.md](notes/HOSTMODELS.md) | In-process host vs dedicated server |
| [TEST_TWO_MAC_FOG.md](TEST_TWO_MAC_FOG.md) | Two-Mac fog checklist |
