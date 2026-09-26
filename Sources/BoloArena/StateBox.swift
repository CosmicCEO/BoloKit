import BoloKit
import Foundation

/// Game-round lifecycle phase, surfaced to both control channels via `observe`'s `phase` field.
enum RoundPhase: String, Codable {
    case joining
    case ready
    case ended
}

/// Lock-protected last-known-good snapshot for one seat (host or guest), fed by
/// `onTickRendered` (host seat) or the in-process guest's own mutate loop (guest seat).
///
/// **#139 discipline:** `HostGameEngine.state` must never be read directly off another
/// thread/task -- that's the exact mistake that caused a real production SIGABRT. Every value
/// this type holds is a plain value-type `GameState` copy handed to it, never a live reference.
final class StateBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    private var _phase: RoundPhase
    private var _gameId: Int
    /// The player index this seat is playing, into `_state.players`/`_state.localStats`.
    private var _playerIndex: Int
    private var _events: [String] = []
    private var _currentFlags: InputFlags = []
    private var _pendingBuild: (kind: BuilderCommandKind, target: Pointi)?
    private var _pendingMine = false
    private var _lastDead: Bool
    private var _lastArmour: Int
    private var _lastShells: Int
    private var _lastMines: Int

    private static let eventCap = 64

    init(state: GameState, phase: RoundPhase, gameId: Int, playerIndex: Int) {
        self._state = state
        self._phase = phase
        self._gameId = gameId
        self._playerIndex = playerIndex
        self._lastDead = state.players.indices.contains(playerIndex) ? state.players[playerIndex].dead : true
        self._lastArmour = state.localStats.indices.contains(playerIndex) ? state.localStats[playerIndex].armour : 0
        self._lastShells = state.localStats.indices.contains(playerIndex) ? state.localStats[playerIndex].shells : 0
        self._lastMines = state.players.indices.contains(playerIndex) ? Int(state.players[playerIndex].mines) : 0
    }

    /// Replaces the round entirely -- a fresh `HostGameEngine`/guest join, new game id.
    func resetRound(state: GameState, phase: RoundPhase, gameId: Int, playerIndex: Int) {
        lock.lock(); defer { lock.unlock() }
        _state = state
        _phase = phase
        _gameId = gameId
        _playerIndex = playerIndex
        _events.removeAll()
        _currentFlags = []
        _pendingBuild = nil
        _pendingMine = false
        _lastDead = state.players.indices.contains(playerIndex) ? state.players[playerIndex].dead : true
        _lastArmour = state.localStats.indices.contains(playerIndex) ? state.localStats[playerIndex].armour : 0
        _lastShells = state.localStats.indices.contains(playerIndex) ? state.localStats[playerIndex].shells : 0
        _lastMines = state.players.indices.contains(playerIndex) ? Int(state.players[playerIndex].mines) : 0
    }

    func setPhase(_ phase: RoundPhase) {
        lock.lock(); _phase = phase; lock.unlock()
    }

    /// Called once per tick with the freshly-rendered state (host seat -- `onTickRendered`
    /// hands over a value-type copy). Diffs this seat's own player slot against the previous
    /// snapshot to synthesize human-readable events.
    func update(_ newState: GameState) {
        lock.lock(); defer { lock.unlock() }
        _state = newState
        diffAndRecord()
    }

    /// Guest seat's equivalent of `update(_:)` -- called after `mutate(_:)` has already updated
    /// `_state` in place, so there's no new state to assign, just the same diff-and-record pass.
    func noteMutated() {
        lock.lock(); defer { lock.unlock() }
        diffAndRecord()
    }

    private func diffAndRecord() {
        guard _state.players.indices.contains(_playerIndex), _state.localStats.indices.contains(_playerIndex) else { return }
        let dead = _state.players[_playerIndex].dead
        let armour = _state.localStats[_playerIndex].armour
        let shells = _state.localStats[_playerIndex].shells
        let mines = Int(_state.players[_playerIndex].mines)

        if dead, !_lastDead { appendEvent("you died") }
        if !dead, _lastDead { appendEvent("you respawned") }
        if armour < _lastArmour { appendEvent("took damage: armour \(_lastArmour) -> \(armour)") }
        if shells < _lastShells { appendEvent("fired a shell: \(_lastShells) -> \(shells) shells left") }
        if mines < _lastMines { appendEvent("placed a mine: \(_lastMines) -> \(mines) mines left") }
        if mines > _lastMines { appendEvent("picked up a mine: \(_lastMines) -> \(mines) mines") }

        _lastDead = dead
        _lastArmour = armour
        _lastShells = shells
        _lastMines = mines
    }

    private func appendEvent(_ text: String) {
        _events.append(text)
        if _events.count > Self.eventCap { _events.removeFirst(_events.count - Self.eventCap) }
    }

    func appendNote(_ text: String) {
        lock.lock(); appendEvent("note: \(text)"); lock.unlock()
    }

    /// Drains and returns every event queued since the last `observe`.
    func drainEvents() -> [String] {
        lock.lock(); defer { lock.unlock() }
        let out = _events
        _events.removeAll()
        return out
    }

    var snapshot: (state: GameState, phase: RoundPhase, gameId: Int, playerIndex: Int) {
        lock.lock(); defer { lock.unlock() }
        return (_state, _phase, _gameId, _playerIndex)
    }

    var currentFlags: InputFlags {
        lock.lock(); defer { lock.unlock() }
        return _currentFlags
    }

    func setFlags(_ flags: InputFlags) {
        lock.lock(); _currentFlags = flags; lock.unlock()
    }

    /// Queues a builder command for the guest's builder task-loop to pick up on its next tick.
    /// (Host seat applies builder commands directly via `submitLocalBuilderCommand` instead --
    /// this queue is guest-only.)
    func queueBuild(kind: BuilderCommandKind, target: Pointi) {
        lock.lock(); _pendingBuild = (kind, target); lock.unlock()
    }

    func takePendingBuild() -> (kind: BuilderCommandKind, target: Pointi)? {
        lock.lock(); defer { lock.unlock() }
        let out = _pendingBuild
        _pendingBuild = nil
        return out
    }

    func requestMine() {
        lock.lock(); _pendingMine = true; lock.unlock()
    }

    func takePendingMine() -> Bool {
        lock.lock(); defer { lock.unlock() }
        let out = _pendingMine
        _pendingMine = false
        return out
    }

    /// Mutates the boxed state in place (guest seat only -- the host seat's box is fed
    /// read-only snapshots from `onTickRendered` and must never be mutated here).
    func mutate(_ body: (inout GameState) -> Void) {
        lock.lock(); body(&_state); lock.unlock()
    }
}
