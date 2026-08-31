import Darwin

// MARK: - Error Constants

public let ELAST: Int32 = Darwin.ELAST

public let EHOSTNOTFOUND: Int32   = ELAST + 1
public let EHOSTNORECOVERY: Int32 = ELAST + 2
public let EHOSTNODATA: Int32     = ELAST + 3
public let ECORFILE: Int32        = ELAST + 4
public let EINCMPAT: Int32        = ELAST + 5
public let EBADVERSION: Int32     = ELAST + 6
public let ETCPCLOSED: Int32      = ELAST + 7
public let EUDPCLOSED: Int32      = ELAST + 8
public let EDISSALLOW: Int32      = ELAST + 9
public let EBADPASS: Int32        = ELAST + 10
public let ESERVERFULL: Int32     = ELAST + 11
public let ETIMELIMIT: Int32      = ELAST + 12
public let EBANNEDPLAYER: Int32   = ELAST + 13
public let ESERVERERROR: Int32    = ELAST + 14

// MARK: - Line Info Structure

public struct ErrLineInfo: Hashable, Sendable {
    public var file: String
    public var function: String
    public var line: Int

    public init(file: String, function: String, line: Int) {
        self.file = file
        self.function = function
        self.line = line
    }
}

// MARK: - Thread-Safe Registry

private final class ErrChkRegistry: @unchecked Sendable {
    private var mutex = pthread_mutex_t()
    private var top: [pthread_t: [ErrLineInfo]] = [:]

    static let shared = ErrChkRegistry()

    private init() {
        pthread_mutex_init(&mutex, nil)
    }

    func push(file: String, function: String, line: Int) {
        pthread_mutex_lock(&mutex)
        let thread = pthread_self()
        var stack = top[thread] ?? []
        stack.append(ErrLineInfo(file: file, function: function, line: line))
        top[thread] = stack
        pthread_mutex_unlock(&mutex)
    }

    func cleanup() {
        pthread_mutex_lock(&mutex)
        let thread = pthread_self()
        top.removeValue(forKey: thread)
        pthread_mutex_unlock(&mutex)
    }

    func printTrace() {
        pthread_mutex_lock(&mutex)
        let thread = pthread_self()
        let stack = top[thread] ?? []
        // We write to stderr using standard Darwin fputs to avoid Foundation
        fputs("Error Trace:\n", stderr)
        for frame in stack {
            let traceLine = "file:\(frame.file):\(frame.function):\(frame.line)\n"
            fputs(traceLine, stderr)
        }
        pthread_mutex_unlock(&mutex)
    }

    func getTrace() -> [ErrLineInfo] {
        pthread_mutex_lock(&mutex)
        let thread = pthread_self()
        let stack = top[thread] ?? []
        pthread_mutex_unlock(&mutex)
        return stack
    }
}

// MARK: - Global API Functions

public func pushlineinfo(_ file: UnsafePointer<CChar>, _ function: UnsafePointer<CChar>, _ line: Int) {
    let fileStr = String(cString: file)
    let funcStr = String(cString: function)
    ErrChkRegistry.shared.push(file: fileStr, function: funcStr, line: line)
}

public func errchkcleanup() {
    ErrChkRegistry.shared.cleanup()
}

public func printlineinfo() {
    ErrChkRegistry.shared.printTrace()
}

public func gettrace() -> [ErrLineInfo] {
    return ErrChkRegistry.shared.getTrace()
}
