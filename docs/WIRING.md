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

## 8. Related docs

| Doc | Topic |
|-----|--------|
| [STATUS.md](STATUS.md) | Ship version, open PRs, milestones |
| [CONSTRAINTS.md](CONSTRAINTS.md) | Physics constants, fog deviation |
| [ORACLE_COVERAGE.md](ORACLE_COVERAGE.md) | C-function coverage snapshot |
| [notes/HOSTMODELS.md](notes/HOSTMODELS.md) | In-process host vs dedicated server |
| [TEST_TWO_MAC_FOG.md](TEST_TWO_MAC_FOG.md) | Two-Mac fog checklist |
