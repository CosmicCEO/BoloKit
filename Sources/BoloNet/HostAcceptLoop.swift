import BoloKit

// MARK: - Milestone B.5a (D95) — accept/join wiring
//
// Drains `HostListener.connections` and calls the already-fully-built `processJoinAttempt` for
// each. Needs no new concurrency architecture: `AsyncStream` delivers to a single `for await`
// consumer one element at a time by construction, so `state: inout GameState` never has more
// than one join in flight here — `JoinAcceptSerializer` (T-11) governs a narrower, different
// race inside `processJoinAttempt` itself (accept-vs-slot-allocation ordering), not something
// this loop adds to.
//
// **Deliberately not this sub-wave's job (B.5b, per D95's split):** no `HostDgramListener`
// draining (identifying which player sent a raw UDP datagram requires decoding its content —
// packet-content-coupled, unlike TCP's connection-level accept); no per-connection message
// dispatch after a successful join (`receiveAndDispatchOneHostMessage` is not called here — a
// joined player's subsequent `CL*` messages go unread until B.5b's dispatch loop exists, an
// accepted intermediate state, same shape as the B.1->B.2/B.3 "Play Demo" scaffolding gap); no
// app-target/UI wiring (`HostGameView`'s "Start Hosting" still only builds a local `GameState`,
// per D94 — wiring this loop into the UI before a joined player's messages can be processed
// would present a host as more ready than it is).

/// Runs until `listener.cancel()` ends the underlying `NWListener`, which ends
/// `listener.connections`, which ends this loop -- no separate shutdown signal needed.
public func runHostAcceptLoop(
    listener: HostListener,
    state: inout GameState,
    table: HostSessionTable,
    onJoinOutcome: (HostJoinOutcome) -> Void = { _ in }
) async {
    for await connection in listener.connections {
        let outcome = await processJoinAttempt(
            connection: connection, serializer: listener.serializer, state: &state, table: table
        )
        onJoinOutcome(outcome)
    }
}
