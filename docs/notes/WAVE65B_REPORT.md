# Wave 6.5b — NAT-PMP/UPnP port mapping — Implementer completion report

> **Standalone report, not appended to `docs/AGENT_NOTES.md` directly.** Per PLANNER's
> 2026-09-03 directive to run Wave 6.5a and 6.5b simultaneously (`docs/AGENT_NOTES.md`,
> "Jerod directs: run Wave 6.5a and 6.5b simultaneously"), the non-primary sub-wave logs
> progress here instead of racing the other live session's commits to the shared
> `AGENT_NOTES.md`/`PLAN.md` tail. PLANNER folds this in at merge time. A concurrent session
> was actively editing `Sources/CXBolo/netops.c`, `Sources/CXBolo/include/CXBolo.h`,
> `Sources/BoloNet/Preambles.swift`, `Sources/BoloNet/Tracker.swift`,
> `Sources/BoloNet/TrackerBrowser.swift`, `Sources/BoloNet/TrackerRegistration.swift`
> (Wave 6.5a) throughout this session — confirmed via repeated `git status`/`git diff --stat`,
> none of those paths touched here.

**Type:** implementer — coding + completion report
**Phase:** Wave 6.5b (NAT-PMP/UPnP port mapping)
**Scope:** exactly the 6.5b file PLANNER's coding GO (`9e5e481`, D54/D55/D56) accepted from the
pre-brief's proposed file list: `Sources/BoloNet/PortMapping.swift`, plus its test file.

## What shipped

`Sources/BoloNet/PortMapping.swift` (new) — wraps `DNSServiceNATPortMappingCreate` (D54:
approved NAT-traversal approach, `import dnssd`, a `libSystem` system API, no bundled
dependency, satisfying `README.md:61-64`'s GPLv3-avoidance commitment) as an `AsyncStream`
drained by one consumer — the same shape `HostListener.swift`/`HostDgramListener.swift`
already proved twice (D49/D52), reused here even though the mechanism crossing into Swift is
genuinely new: `dnssd`'s reply is a C function pointer, not a `Network.framework` closure, so
it can't capture Swift state directly. A small `PortMappingContext` class boxes the stream
continuation and crosses the C boundary via the callback's own documented
`context: UnsafeMutableRawPointer?` mechanism (`Unmanaged.passRetained`/`.fromOpaque`).

Key design points:

- **`decodePortMappingReply(errorCode:externalAddress:externalPort:ttl:) -> PortMappingUpdate?`**
  is the pure decision logic, deliberately factored out of the C callback closure itself. D55
  ruled Wave 6.5b has no C oracle and its only real verification is a live router round-trip —
  but that only applies to the actual NAT mechanism, not to "which raw reply payloads become an
  update, and how do ports get byte-swapped back." Splitting decision from mechanism this way is
  the same pattern this project has used everywhere else (D31/D36/D42), applied here so this
  wave still has *something* independently unit-tested despite the disclosed live-round-trip
  limitation.
- **Byte order:** `PortMapping.init`'s `internalPort`/`externalPort` parameters are host byte
  order, matching every other `port: UInt16` in this module (`HostListener.swift` et al.);
  converted to the API's required network byte order internally via `.bigEndian`.
  `PortMappingUpdate.externalPort` converts the reply's network-order value back to host order
  via `UInt16(bigEndian:)` for the same consistency. `externalAddress` is left in its raw
  network-order `UInt32` form, matching `DgramServerPeerAddress.addr`'s existing convention
  (`HostListener.swift`) rather than inventing a second representation for the same shape of
  value.
- **`doubleNAT` is a flag, not a thrown error.** Per the API's own documented contract,
  `kDNSServiceErr_DoubleNAT` still carries a meaningful external address/port/ttl (the gateway
  itself is behind another NAT layer) — `decodePortMappingReply` treats it as a successful
  update with `doubleNAT: true`, not a failure case. Every other error code yields no update at
  all (the callback simply doesn't fire a Swift-visible event for it) rather than surfacing as a
  thrown `Error` — matching the C API's own "callback fires at any point mapping state changes"
  model, not a request/response one.
- **`PortMapping` requests both UDP and TCP mapping by default** (`kDNSServiceProtocol_UDP |
  kDNSServiceProtocol_TCP`) — Bolo's own transport needs both (game UDP, tracker/join TCP).

## Tests

`Tests/DifferentialTests/PortMappingTests.swift` (new) — 5 `@Test` functions:

- `decodePortMappingReplySucceedsOnNoError` — confirms the byte-swap math directly (network-order
  `0x901F` → host-order `8080`) and that all fields pass through.
- `decodePortMappingReplySucceedsWithDoubleNATFlagOnDoubleNATError` — confirms `kDNSServiceErr_
  DoubleNAT` still produces an update with `doubleNAT == true`, not `nil`.
- `decodePortMappingReplyReturnsNilOnAnyOtherError` — three other error codes (`kDNSServiceErr_
  Unknown`, `kDNSServiceErr_Refused`, `kDNSServiceErr_NATPortMappingUnsupported`) all suppress
  the update.
- `portMappingUpdateIsEquatable` — trivial value-semantics check.
- `portMappingCancelBeforeAnyReplyIsSafe` — constructs a real `PortMapping` (this does talk to
  the live `mDNSResponder` system daemon — a standard, always-running macOS component, not a
  simulated LAN gateway) and calls `cancel()` twice to confirm the boxed-context release path
  doesn't double-release. **Disclosed limitation:** this is the one test that exercises
  `PortMapping`'s actual mechanism rather than pure decision logic, and depends on the local
  daemon being reachable — the live NAT/router round-trip itself (D55's actual disclosed
  non-goal) is not exercised by anything in this file, only daemon-level construct/cancel safety.

**Test count:** prior baseline was 572 (Wave 6.4c close, `docs/AGENT_NOTES.md`). This file adds
5. **I could not run `RunAllTests`/a full `BuildProject(buildForTesting: true)` to confirm the
new grand total this session** — `Sources/CXBolo/netops.c` was left in a non-compiling
intermediate state by the concurrent Wave 6.5a session for the duration of this session
(`Unknown type name 'SR'`/`'they'` at netops.c:596-597, an in-progress edit, not a defect of
mine — confirmed via repeated `git status`/`git diff --stat`, only `netops.c`/`CXBolo.h`/
`Preambles.swift`/`Tracker.swift`/`TrackerBrowser.swift`/`TrackerRegistration.swift` showing as
concurrently modified). Before that interference began, `PortMapping.swift` on its own was
confirmed clean via `XcodeRefreshCodeIssuesInFile` (zero diagnostics) and one full successful
`BuildProject(buildForTesting: true)` run. `PortMappingTests.swift` was written after the
interference started and could not be independently diagnosed the same way; it is a
straightforward Swift Testing file with no unusual constructs, but a fresh compile check once
`netops.c` stabilizes is warranted before this is treated as fully verified.

## Files touched (this entry only)

- `Sources/BoloNet/PortMapping.swift` (new)
- `Tests/DifferentialTests/PortMappingTests.swift` (new)
- `docs/notes/WAVE65B_REPORT.md` (this file, new)

No other file was staged or committed by this session. `docs/AGENT_NOTES.md`/`docs/PLAN.md` are
untouched here, per PLANNER's directive above — those get PLANNER's own fold-in pass.

> **→ Planner:** Please fold this into `docs/AGENT_NOTES.md`/`PLAN.md` at your convenience, and
> re-run the full suite once Wave 6.5a's `netops.c`/`CXBolo.h` edits land and commit — this
> report's test-count claim is honest about being unverified past the pure-logic file itself.
> **→ Parity:** Hold Wave 6.5b's audit until the shared `CXBolo`/`DifferentialTests` target
> builds again (blocked on 6.5a's in-flight edits as of this writing), same as the note above.
