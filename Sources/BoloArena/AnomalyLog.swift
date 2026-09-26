import BoloKit
import Foundation

private struct ViolationRecord: Encodable {
    var ts: String
    var gameId: Int
    var text: String
}

private struct NoteRecord: Encodable {
    var ts: String
    var seat: String
    var gameId: Int
    var text: String
}

/// The machine-checked anomaly channel: cheap per-tick bounds/range checks (called inline from
/// `onTickRendered`, so they must stay fast) write to `violations.jsonl`; each agent's own
/// free-text `note` command writes to `notes.jsonl`. Both files are flushed per-line, not
/// buffered, so a crash or kill mid-session doesn't lose anything already written. JSON-encoded
/// (not hand-built strings) so arbitrary agent free text can never corrupt the line.
final class AnomalyLog: @unchecked Sendable {
    private let lock = NSLock()
    private let violationsHandle: FileHandle
    private let notesHandle: FileHandle
    private let encoder = JSONEncoder()
    private var lastTickChecked: UInt64?

    init(logDirectory: URL) throws {
        try FileManager.default.createDirectory(at: logDirectory, withIntermediateDirectories: true)
        let violationsURL = logDirectory.appendingPathComponent("violations.jsonl")
        let notesURL = logDirectory.appendingPathComponent("notes.jsonl")
        for url in [violationsURL, notesURL] where !FileManager.default.fileExists(atPath: url.path) {
            FileManager.default.createFile(atPath: url.path, contents: nil)
        }
        violationsHandle = try FileHandle(forWritingTo: violationsURL)
        notesHandle = try FileHandle(forWritingTo: notesURL)
        violationsHandle.seekToEndOfFile()
        notesHandle.seekToEndOfFile()
    }

    private func appendLine<T: Encodable>(_ record: T, to handle: FileHandle) {
        lock.lock(); defer { lock.unlock() }
        guard var data = try? encoder.encode(record) else { return }
        data.append(0x0A) // "\n"
        handle.write(data)
    }

    func recordViolation(_ text: String, gameId: Int) {
        let ts = ISO8601DateFormatter().string(from: Date())
        appendLine(ViolationRecord(ts: ts, gameId: gameId, text: text), to: violationsHandle)
    }

    func note(seat: String, gameId: Int, text: String) {
        let ts = ISO8601DateFormatter().string(from: Date())
        appendLine(NoteRecord(ts: ts, seat: seat, gameId: gameId, text: text), to: notesHandle)
    }

    /// Cheap, inline per-tick invariant checks -- called from `onTickRendered`, so this must
    /// never block or allocate heavily. Deduplicated per-tick (a stuck out-of-range value would
    /// otherwise write one line per tick forever).
    func sample(hostState: GameState, gameId: Int) {
        guard hostState.ticks != lastTickChecked else { return }
        lastTickChecked = hostState.ticks
        for i in hostState.players.indices where hostState.players[i].used {
            let stats = hostState.localStats[i]
            if !(0...maxArmour).contains(stats.armour) {
                recordViolation("player \(i) armour out of range: \(stats.armour) tick \(hostState.ticks)", gameId: gameId)
            }
            if !(0...maxShells).contains(stats.shells) {
                recordViolation("player \(i) shells out of range: \(stats.shells) tick \(hostState.ticks)", gameId: gameId)
            }
            if !(0...maxMines).contains(Int(hostState.players[i].mines)) {
                recordViolation("player \(i) mines out of range: \(hostState.players[i].mines) tick \(hostState.ticks)", gameId: gameId)
            }
        }
    }
}
