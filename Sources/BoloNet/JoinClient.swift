import Network
import Foundation
import BoloKit

// MARK: - Wave 6.4a — client-side join handshake
//
// Ported from `joinclient()`'s wire-level protocol steps
// (`client.c:499-770`) -- NOT its POSIX mechanics. Per D42, the actual
// socket/`select`/`connect`/`bind` dance in the real function is exactly
// the "transliterated POSIX glue" D31 already ruled out; this is a fresh
// implementation of the same observable byte sequence
// (`JoinPreamble` -> status byte -> `BoloPreamble` -> map bytes) on
// `NWConnection`/async-await instead. DNS resolution (`joinclient()`'s
// own `nslookup`/`selectreadread` dance) is not reimplemented either --
// `NWEndpoint.hostPort` resolves hostnames internally, and D4 (no interop
// requirement) means there's no reason to duplicate that logic.
//
// Milestone B.3 (D95-era): added `onProgress` and a real connect-phase
// timeout, ported from tracing `joinprogress()`'s 21-status dispatch
// (`bolo.h:240-272`, `GSXBoloController.m:3780-3872` -- 21 `kJoin*` codes
// total, corrected per D97's citation-drift finding; the pre-brief had
// miscounted 19) against what `withNetworkConnection`'s API surface --
// and real empirical behavior in this environment -- can actually
// distinguish. Two disclosed simplifications, not guesses:
//
// 1. **`RESOLVING`/`CONNECTING` collapse to one `.connecting` progress
//    case.** `withNetworkConnection(to:using:body:)` fully establishes the
//    connection (DNS + TCP handshake) before ever invoking `body` -- there
//    is no hook between those two reference-distinguished phases to fire
//    a separate event from. No percentage value exists anywhere in the
//    reference's join path either (traced every `joinprogress()` call
//    site) -- corrects the original Milestone B pre-plan's "6 progress
//    states incl. percentage" claim.
// 2. **The reference's 8 network-error codes collapse to 3 cases, not 5.**
//    `.connectionRefused` maps `NWError.posix(.ECONNREFUSED)`, a clean,
//    confident 1:1 -- but per D97 (PARITY's B.3 re-audit, `cc10f29`),
//    **that case is currently unreachable through `joinClient` itself in
//    this environment**, not merely hard to trigger. A raw `NWConnection`
//    against a port nothing has ever bound to *does* receive `ECONNREFUSED`
//    immediately (confirmed independently, both by this file's original
//    author and by PARITY's own re-derivation) -- but `NWConnection`
//    treats that as the retryable `.waiting(.posix(.ECONNREFUSED))` state,
//    not `.failed`, and never transitions out of it on its own on this
//    OS/SDK. `withNetworkConnection`'s own retry semantics ride that
//    `.waiting` state rather than surfacing it, so only `joinClient`'s
//    explicit connect-phase timeout ever fires -- `.timedOut`, not
//    `.connectionRefused`, 19/19 times for PARITY and 5/5 on a fresh
//    re-probe here. (The original version of this comment attributed the
//    gap to a sandboxing difference between a standalone binary and
//    `swift test`'s own process -- PARITY couldn't reproduce that
//    framing, and neither could a fresh re-probe; withdrawn, replaced with
//    the mechanism above, which both re-derivations agree on.) The
//    mapping itself is still correct-by-construction and stays as
//    written, in case a future OS/SDK (or a lower-level rewrite bypassing
//    `withNetworkConnection`) ever does surface `.failed` promptly for
//    this case. A bad hostname and a non-routable address both produced
//    **no error at all** even after waiting 90 seconds -- not
//    `ETIMEDOUT`, not a DNS-specific error, nothing. That rules out ever
//    constructing the reference's 3-way DNS split
//    (`EHOSTNOTFOUND`/`EHOSTNORECOVERY`/`EHOSTNODATA` -- classic
//    `hstrerror()`/`h_errno` codes, a genuinely different taxonomy from
//    `NWError`'s own `DNSServiceErrorType`-based DNS case) or a distinct
//    `ENETUNREACH`/`EHOSTUNREACH` -- both manifest identically to "the
//    connection attempt just hangs," which is why `joinClient` needs its
//    *own* explicit connect-phase timeout at all (unlike the reference,
//    whose `ETIMEDOUT` is the OS's own `connect()` timeout, which this
//    environment's DNS-failure path evidently never reaches on its own
//    either). `.timedOut` is therefore the case that actually fires for
//    all of: DNS failure, network-unreachable, host-unreachable,
//    connection-refused (per above), and a genuinely slow connect.
//    `.connectionReset` (`ECONNRESET`) is kept as its own case despite not
//    being empirically triggered -- a clean, confident 1:1
//    `POSIXErrorCode` mapping, same shape of derived-not-guessed
//    reasoning as the others.

/// `bolo.h:190-198`'s join-message enum, wire values 0-6 -- the status
/// byte the server sends immediately after receiving a `JoinPreamble`.
public enum JoinStatusByte: UInt8, Sendable {
    case badVersion = 0
    case disallow = 1
    case badPassword = 2
    case serverFull = 3
    case serverTimeLimitReached = 4
    case bannedPlayer = 5
    case sendingPreamble = 6
}

/// The join handshake's live progress states -- fired via `joinClient`'s `onProgress` callback.
/// Collapses the reference's `RESOLVING`+`CONNECTING` into one `.connecting` case (see this
/// file's header); the remaining four map directly onto `joinClient`'s own existing checkpoints.
public enum JoinProgress: Sendable, Equatable {
    case connecting
    case sendingJoin
    case receivingPreamble
    case receivingMap
    case success
}

/// Mirrors `joinclient()`'s status-byte switch (`client.c:637-644`) --
/// every non-`sendingPreamble` status maps to a specific rejection
/// reason, matching the C's own `EBADVERSION`/`EDISSALLOW`/etc. `E`-codes
/// one for one.
public enum JoinClientError: Error, Sendable, Equatable {
    case badVersion
    case disallow
    case badPassword
    case serverFull
    case serverTimeLimitReached
    case bannedPlayer
    /// The server sent a status byte outside `JoinStatusByte`'s known
    /// range -- `ESERVERERROR` in the C (`client.c:644`, the `else`
    /// branch of its status-byte switch).
    case serverProtocolError
    /// The connection closed (or the server sent malformed bytes) before
    /// a complete `BoloPreamble` + map payload arrived.
    case connectionClosedEarly
    case malformedPreamble
    /// Covers DNS-resolution failure, network-unreachable, host-unreachable, and a genuinely
    /// slow connect -- see this file's header for why those don't distinguish from each other
    /// via this API, confirmed by measurement. Fired by `joinClient`'s own explicit
    /// connect-phase timeout.
    case timedOut
    /// `NWError.posix(.ECONNREFUSED)` -- empirically confirmed fast and reliable.
    case connectionRefused
    /// `NWError.posix(.ECONNRESET)` -- a clean 1:1 mapping, not empirically triggered.
    case connectionReset

    init(rejecting status: JoinStatusByte) {
        switch status {
        case .badVersion: self = .badVersion
        case .disallow: self = .disallow
        case .badPassword: self = .badPassword
        case .serverFull: self = .serverFull
        case .serverTimeLimitReached: self = .serverTimeLimitReached
        case .bannedPlayer: self = .bannedPlayer
        case .sendingPreamble:
            // Never actually constructed for this case -- `joinClient`
            // only calls this initializer once it's confirmed `status !=
            // .sendingPreamble`. Exhaustiveness only.
            self = .serverProtocolError
        }
    }

    /// Maps a thrown `NWError`'s POSIX case to the matching network-error case above, or `nil`
    /// if it's some other `NWError`/POSIX code this join path doesn't specifically distinguish
    /// (falls through to the generic `error` rethrow in `joinClient`, same as before B.3).
    init?(posix error: Error) {
        guard case .posix(let code) = error as? NWError else { return nil }
        switch code {
        case .ECONNREFUSED: self = .connectionRefused
        case .ECONNRESET: self = .connectionReset
        case .ETIMEDOUT: self = .timedOut
        default: return nil
        }
    }
}

/// First-writer-wins guard so two unstructured `Task`s can race to resume one continuation
/// without ever double-resuming it (a `CheckedContinuation` traps on a second resume). Also
/// cancels both tasks on the winning resume -- the loser would otherwise keep running for no
/// reason `joinClient`'s caller can observe: a won-by-`body()` race would still leave the sleep
/// task running for the rest of `seconds` (harmless but wasteful, since `Task.sleep` *is*
/// cancellation-aware and exits immediately once told), and a won-by-timeout race at least gets
/// a best-effort cancellation signal into the abandoned connection attempt, even though this
/// file's header already established `withNetworkConnection` doesn't reliably act on it for a
/// black-holed route.
/// **B.8 (D113):** dropped from `private` to file-scope-only `internal` so `TCPSession.join`
/// (`TCPSession.swift`) can reuse the identical connect-phase-timeout race this file's own header
/// already justifies at length -- the reasoning doesn't change just because the caller moved.
final class ResumeOnce<T: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var didResume = false
    private let continuation: CheckedContinuation<T, Error>
    var workTask: Task<Void, Never>?
    var timeoutTask: Task<Void, Never>?

    init(_ continuation: CheckedContinuation<T, Error>) {
        self.continuation = continuation
    }

    func resume(with result: Result<T, Error>) {
        lock.lock()
        let alreadyResumed = didResume
        didResume = true
        lock.unlock()
        guard !alreadyResumed else { return }
        workTask?.cancel()
        timeoutTask?.cancel()
        continuation.resume(with: result)
    }
}

/// Races `body` against `joinClient`'s own connect-phase timeout (default 15s -- a UX choice,
/// not a ported literal; the reference relies entirely on the OS's own `connect()` timeout,
/// which this file's header explains this environment's DNS-failure/unreachable-route path
/// never seems to reach on its own). Fires `.timedOut` if `body` hasn't finished within that
/// window.
///
/// **Deliberately not `withThrowingTaskGroup`** -- a first attempt used one, racing `body`
/// against a sleep-and-throw sibling and calling `cancelAll()` on whichever lost. That doesn't
/// actually cut the race short: `withThrowingTaskGroup` still awaits every child task before its
/// own scope returns, cancellation or not, and `withNetworkConnection`'s connection-establishment
/// doesn't appear to observe Swift's cooperative cancellation for a black-holed route -- the
/// whole function hung for minutes against a non-routable address, confirmed directly (killed a
/// stuck test process to find this, not inferred from documentation). Two independent
/// unstructured `Task`s racing to resume one `CheckedContinuation` (first writer wins, via
/// `ResumeOnce`) actually returns as soon as one finishes -- the loser keeps running detached in
/// the background until Network.framework's own internal state eventually resolves it, exactly
/// as a real caller closing/abandoning a slow connection attempt would have to work anyway.
func withConnectTimeout<T: Sendable>(
    seconds: Double, _ body: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withCheckedThrowingContinuation { continuation in
        let resumer = ResumeOnce(continuation)
        resumer.workTask = Task {
            do {
                resumer.resume(with: .success(try await body()))
            } catch {
                resumer.resume(with: .failure(error))
            }
        }
        resumer.timeoutTask = Task {
            do {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                resumer.resume(with: .failure(JoinClientError.timedOut))
            } catch {
                // Cancelled by `resume(with:)` because `body()` won the race first -- nothing
                // further to do.
            }
        }
    }
}

/// Performs the full join handshake against `host:port` and returns the
/// decoded `BoloPreamble` plus the raw map bytes that immediately follow
/// it on the wire (`bolopreamble.maplen` bytes, per `server.c:869`/
/// `client.c:661-680`) -- loading those bytes into a real map
/// (`BMap.swift`'s decoder, Wave 4.1) is the caller's job, not this
/// function's.
///
/// **B.8 (D113):** the real handshake wire logic moved to `TCPSession.join`
/// (`TCPSession.swift`) -- a join-side live network loop has to keep using the *same* accepted
/// connection the handshake ran on (the host's `HostSessionTable` slot is tied to that specific
/// connection; a fresh second one looks like an unauthenticated new join attempt, not a
/// resumption), which this function's own `withNetworkConnection`-scoped transport can't support
/// -- that helper closes the connection the moment its closure returns. This function is now a
/// thin wrapper that discards the live session, preserving its own existing signature/behavior
/// (and every test in `JoinClientTests.swift`) unchanged for whatever still only needs the
/// one-shot handshake result.
public func joinClient(
    host: String, port: UInt16, name: String, pass: String,
    connectTimeoutSeconds: Double = 15,
    onProgress: @escaping @Sendable (JoinProgress) -> Void = { _ in }
) async throws -> (preamble: BoloPreamble, mapData: [UInt8]) {
    let result = try await TCPSession.join(
        host: host, port: port, name: name, pass: pass,
        connectTimeoutSeconds: connectTimeoutSeconds, onProgress: onProgress
    )
    result.session.cancel()
    return (result.preamble, result.mapData)
}
