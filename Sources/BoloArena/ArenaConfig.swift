import Foundation

/// Command-line/env configuration for the arena process. Not a game-shipping type -- this whole
/// target is a soak/anomaly-hunting tool, two real Claude agents each drive one seat by issuing
/// one HTTP request per shell command.
struct ArenaConfig {
    var hostControlPort: UInt16 = 9101
    var guestControlPort: UInt16 = 9102
    var logDirectory: URL

    static func fromEnvironment() -> ArenaConfig {
        let env = ProcessInfo.processInfo.environment
        var config = ArenaConfig(logDirectory: URL(fileURLWithPath: "/tmp/bolo-arena"))
        if let hostPort = env["BOLO_ARENA_HOST_PORT"], let value = UInt16(hostPort) {
            config.hostControlPort = value
        }
        if let guestPort = env["BOLO_ARENA_GUEST_PORT"], let value = UInt16(guestPort) {
            config.guestControlPort = value
        }
        if let dir = env["BOLO_ARENA_LOG_DIR"] {
            config.logDirectory = URL(fileURLWithPath: dir)
        }
        return config
    }
}
