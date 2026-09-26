import BoloKit
import Foundation

/// The more expensive half of the machine-checked anomaly channel: host/guest divergence,
/// checked on a ~1s cadence (not inline in `onTickRendered`, unlike `AnomalyLog.sample`) and
/// reading only the two `StateBox`es -- never `HostGameEngine.state` directly (#139 discipline).
/// Started once for the process's lifetime; `StateBox`es persist across `newgame` resets, so one
/// long-running task naturally covers every round.
enum InvariantSampler {
    static func start(hostBox: StateBox, guestBox: StateBox, anomalyLog: AnomalyLog) -> Task<Void, Never> {
        Task {
            var lastDiff: String?
            var persistCount = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                let host = hostBox.snapshot
                let guest = guestBox.snapshot
                guard host.phase == .ready, guest.phase == .ready, host.gameId == guest.gameId else {
                    lastDiff = nil; persistCount = 0
                    continue
                }
                let g = guest.playerIndex
                guard host.state.players.indices.contains(g), host.state.localStats.indices.contains(g),
                      guest.state.players.indices.contains(g), guest.state.localStats.indices.contains(g)
                else { continue }

                let diff = divergence(host: host.state, guest: guest.state, g: g)
                if let diff, diff == lastDiff {
                    persistCount += 1
                } else {
                    persistCount = diff == nil ? 0 : 1
                }
                lastDiff = diff
                // ~3s of sustained divergence -- tolerates normal one-tick wire latency, matching
                // the spirit of `HostSimulatedSoakTests.swift`'s own settle-window tolerance.
                if let diff, persistCount == 3 {
                    anomalyLog.recordViolation("host/guest divergence: \(diff)", gameId: host.gameId)
                }
            }
        }
    }

    private static func divergence(host: GameState, guest: GameState, g: Int) -> String? {
        if host.players[g].dead != guest.players[g].dead {
            return "dead flag differs: host \(host.players[g].dead) guest \(guest.players[g].dead)"
        }
        if host.localStats[g].armour != guest.localStats[g].armour {
            return "armour differs: host \(host.localStats[g].armour) guest \(guest.localStats[g].armour)"
        }
        if host.localStats[g].shells != guest.localStats[g].shells {
            return "shells differ: host \(host.localStats[g].shells) guest \(guest.localStats[g].shells)"
        }
        if host.players[g].mines != guest.players[g].mines {
            return "mines differ: host \(host.players[g].mines) guest \(guest.players[g].mines)"
        }
        if host.players[g].boat != guest.players[g].boat {
            return "boat flag differs: host \(host.players[g].boat) guest \(guest.players[g].boat)"
        }
        return nil
    }
}
