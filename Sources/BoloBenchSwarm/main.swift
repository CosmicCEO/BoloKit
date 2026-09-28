import BoloKit
import BoloNet
import Foundation

// v1.6.9 baseline benchmark: synthetic guests for the scaling sweep. Load for the host, not a
// measurement of guests: the sweep analyzes the host's log only.
//
//   BoloBenchSwarm <host> <port> <guests> <seconds> [seed]
//
// Each guest is the same shape as the soak test's (`HostSimulatedSoakTests`): a real
// `TCPSession.join` and `UDPSession`, its own movement run locally, seeded random keys, and a
// mine dropped now and then. It is not the shipped `GameSession`. All guests share this one
// process; its CPU use is printed at the end so a run where the swarm starved the host can be
// seen and thrown out.

final class GuestBox: @unchecked Sendable {
    private let lock = NSLock()
    private var _state: GameState
    init(_ state: GameState) { _state = state }
    var state: GameState { lock.lock(); defer { lock.unlock() }; return _state }
    func mutate(_ body: (inout GameState) -> Void) { lock.lock(); body(&_state); lock.unlock() }
}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var _set = false
    func set() { lock.lock(); _set = true; lock.unlock() }
    var isSet: Bool { lock.lock(); defer { lock.unlock() }; return _set }
}

final class Tally: @unchecked Sendable {
    private let lock = NSLock()
    private var _joined = 0
    private var _failed = 0
    func joined() { lock.lock(); _joined += 1; lock.unlock() }
    func failed() { lock.lock(); _failed += 1; lock.unlock() }
    var counts: (joined: Int, failed: Int) { lock.lock(); defer { lock.unlock() }; return (_joined, _failed) }
}

func runGuest(number: Int, host: String, port: UInt16, seed: UInt64, until deadline: Date, tally: Tally) async {
    guard let joined = try? await TCPSession.join(host: host, port: port, name: "Swarm\(number)", pass: "") else {
        tally.failed()
        return
    }
    var initial = GameState()
    initial.players = (0..<maxPlayers).map { _ in PlayerState() }
    guard applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial),
        let udp = try? await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
    else {
        joined.session.cancel()
        tally.failed()
        return
    }
    tally.joined()
    let me = initial.localPlayer
    let guest = GuestBox(initial)
    let hostGone = Flag()

    let udpReceiver = Task {
        while !Task.isCancelled {
            guard let data = try? await udp.receiveOneRawDatagram() else { return }
            guest.mutate { state in _ = udp.apply(data, myOwnSeq: 0, state: &state) }
        }
    }
    let tcpReceiver = Task {
        while !Task.isCancelled {
            guard let message = try? await joined.session.receiveOneRawMessage() else {
                hostGone.set()
                return
            }
            guest.mutate { state in _ = try? TCPSession.dispatch(message, state: &state) }
        }
    }
    // One 20 ms tick: own movement, tile entry, and the update every fifth tick.
    let ticker = Task {
        var localSeq: Int32 = 0
        while !Task.isCancelled {
            var outbound: [JoinOutboundCL] = []
            guest.mutate { state in
                guard !state.players[me].dead else { return }
                let old = Pointi(x: Int32(state.players[me].tank.x), y: Int32(state.players[me].tank.y))
                tankMoveTick(player: me, state: &state)
                let new = Pointi(x: Int32(state.players[me].tank.x), y: Int32(state.players[me].tank.y))
                outbound = detectJoinTileEntry(new: new, old: old, state: state)
            }
            for message in outbound {
                let bytes: [UInt8]
                switch message {
                case .grabTile(let x, let y): bytes = CLGrabTile(x: UInt8(x), y: UInt8(y)).encode()
                case .dropBoat(let x, let y): bytes = CLDropBoat(x: UInt8(x), y: UInt8(y)).encode()
                case .dropMine(let x, let y): bytes = CLDropMine(x: UInt8(x), y: UInt8(y)).encode()
                }
                try? await joined.session.send(bytes)
            }
            localSeq += 1
            if localSeq % 5 == 0 {
                var seqs = udp.allRemoteSeqsAsUInt32()
                seqs[me] = UInt32(bitPattern: localSeq)
                try? await udp.sendLocalUpdate(assembleClUpdate(player: me, state: guest.state, seq: seqs).encode())
            }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
    }
    let player = Task {
        var rng = BenchRNG(state: seed)
        while !Task.isCancelled {
            let state = guest.state
            let action = benchRandomAction(&rng, tank: state.players[me].tank)
            guest.mutate { $0.players[me].inputFlags = action.flags }
            if action.layMine, !state.players[me].dead {
                let tank = state.players[me].tank
                if (0..<256).contains(Int(tank.x)), (0..<256).contains(Int(tank.y)) {
                    try? await joined.session.send(CLDropMine(x: UInt8(tank.x), y: UInt8(tank.y)).encode())
                }
            }
            try? await Task.sleep(nanoseconds: UInt64(benchRandomStepMs) * 1_000_000)
        }
    }

    // Until the time is up or the host goes away.
    while Date() < deadline, !hostGone.isSet {
        try? await Task.sleep(nanoseconds: 100_000_000)
    }
    for task in [udpReceiver, tcpReceiver, ticker, player] { task.cancel() }
    if !hostGone.isSet { try? await joined.session.send(CLHangUp().encode()) }
    udp.cancel()
    joined.session.cancel()
}

let arguments = CommandLine.arguments
guard arguments.count >= 5, let port = UInt16(arguments[2]), let guests = Int(arguments[3]),
    let seconds = Double(arguments[4]), (1..<maxPlayers).contains(guests)
else {
    FileHandle.standardError.write(
        Data("usage: BoloBenchSwarm <host> <port> <guests 1-\(maxPlayers - 1)> <seconds> [seed]\n".utf8))
    exit(64)
}
let seed = arguments.count > 5 ? UInt64(arguments[5]) ?? 0x5EED : 0x5EED
let deadline = Date().addingTimeInterval(seconds)
let tally = Tally()

await withTaskGroup(of: Void.self) { group in
    for number in 1...guests {
        group.addTask {
            // Staggered, so the host's join handshakes do not all land in one tick.
            try? await Task.sleep(nanoseconds: UInt64(number - 1) * 250_000_000)
            await runGuest(
                number: number, host: arguments[1], port: port, seed: seed ^ UInt64(number), until: deadline,
                tally: tally
            )
        }
    }
}

var usage = rusage()
getrusage(RUSAGE_SELF, &usage)
let cpu = Double(usage.ru_utime.tv_sec + usage.ru_stime.tv_sec)
    + Double(usage.ru_utime.tv_usec + usage.ru_stime.tv_usec) / 1_000_000
let counts = tally.counts
print("{\"guests\":\(guests),\"joined\":\(counts.joined),\"failed\":\(counts.failed),\"cpuSeconds\":\(cpu),\"seconds\":\(seconds)}")
exit(counts.joined == guests ? 0 : 1)
