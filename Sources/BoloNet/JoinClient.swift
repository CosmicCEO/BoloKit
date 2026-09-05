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

    fileprivate init(rejecting status: JoinStatusByte) {
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
    fileprivate init?(posix error: Error) {
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
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
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
private func withConnectTimeout<T: Sendable>(
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
public func joinClient(
    host: String, port: UInt16, name: String, pass: String,
    connectTimeoutSeconds: Double = 15,
    onProgress: @escaping @Sendable (JoinProgress) -> Void = { _ in }
) async throws -> (preamble: BoloPreamble, mapData: [UInt8]) {
    let endpoint = NWEndpoint.hostPort(host: NWEndpoint.Host(host), port: NWEndpoint.Port(rawValue: port)!)

    onProgress(.connecting)
    let result: (preamble: BoloPreamble, mapData: [UInt8])
    do {
        result = try await withConnectTimeout(seconds: connectTimeoutSeconds) {
            // `outcome` is local to this closure -- it's the one child task `withConnectTimeout`
            // races against its timeout sibling, so nothing else ever touches it concurrently
            // (unlike a var declared in `joinClient`'s own scope and captured by both tasks,
            // which is what the compiler correctly rejected here originally).
            var outcome: Result<(BoloPreamble, [UInt8]), Error>?

            try await withNetworkConnection(to: endpoint, using: { TCP() }) { connection in
                do {
                    onProgress(.sendingJoin)
                    let joinPreamble = JoinPreamble(name: name, pass: pass)
                    try await connection.send(joinPreamble.encode())

                    let statusMessage = try await connection.receive(exactly: 1)
                    guard let statusByte = statusMessage.content.first,
                          let status = JoinStatusByte(rawValue: statusByte)
                    else {
                        outcome = .failure(JoinClientError.serverProtocolError)
                        return
                    }
                    guard status == .sendingPreamble else {
                        outcome = .failure(JoinClientError(rejecting: status))
                        return
                    }

                    onProgress(.receivingPreamble)
                    let preambleMessage = try await connection.receive(exactly: BoloPreamble.wireSize)
                    guard let preamble = BoloPreamble.decode(Array(preambleMessage.content)) else {
                        outcome = .failure(JoinClientError.malformedPreamble)
                        return
                    }

                    onProgress(.receivingMap)
                    let mapMessage = try await connection.receive(exactly: Int(preamble.mapLength))
                    outcome = .success((preamble, Array(mapMessage.content)))
                } catch {
                    // A reset (or, in principle, any other POSIX code this join path
                    // recognizes) can happen mid-handshake too, not just while connecting --
                    // classify it here the same way the outer catch does for connect-phase
                    // failures, rather than only mapping half the cases.
                    outcome = .failure(JoinClientError(posix: error) ?? error)
                }
            }

            guard let outcome else { throw JoinClientError.connectionClosedEarly }
            return try outcome.get()
        }
    } catch let error as JoinClientError {
        throw error
    } catch {
        throw JoinClientError(posix: error) ?? error
    }

    onProgress(.success)
    return result
}
