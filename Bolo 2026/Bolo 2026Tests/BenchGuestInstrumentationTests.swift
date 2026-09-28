//
//  BenchGuestInstrumentationTests.swift
//  Bolo 2026Tests
//
//  v1.6.9 baseline benchmark. Real host + real join client (`GameSession`), each with its own
//  recorder, to check that what the guest logs is what the guest held. Harness shape borrowed
//  from `PillDesyncReproTests.swift`.
//

import CoreGraphics
import Foundation
import Testing
import BoloKit
import BoloNet

@testable import Bolo_2026

private enum BenchGuestHarnessError: Error { case noPort }

@MainActor
struct BenchGuestInstrumentationTests {

    private func image() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    private func makeHost(hiddenMines: Bool) async throws -> (engine: HostGameEngine, port: UInt16) {
        for _ in 0..<8 {
            let port = UInt16.random(in: 49_152...65_000)
            let tcp: HostListener
            do { tcp = try await HostListener(port: port) } catch { continue }
            let udp: HostDgramListener
            do { udp = try await HostDgramListener(port: port) } catch { tcp.cancel(); continue }
            var state = GameState()
            var host = PlayerState()
            host.name = "Host"
            host.connected = true
            host.used = true
            host.dead = false
            host.tank = Vec2f(x: 200.5, y: 200.5)
            host.alliance = UInt16(1 << 0)
            state.players = hostPlayerSlots(hostPlayer: host)
            state.localPlayer = 0
            state.local.shells = 40
            state.local.armour = 40
            state.hostSimulatesRemotePlayers = true
            state.hiddenMines = hiddenMines
            for y in 20..<240 { for x in 20..<240 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
            state.starts = [Start(x: 50, y: 50, dir: 0)]
            state.pills = [Pill(x: 60, y: 50, armour: 15, owner: playerNeutral, speed: 100, counter: 0)]
            return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
        }
        throw BenchGuestHarnessError.noPort
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    }

    private func log(_ role: String) throws -> (BenchRecorder, URL) {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("bolo-bench-guest-\(UUID().uuidString)", isDirectory: true)
            .appendingPathComponent("\(role)-0.jsonl")
        return (try BenchRecorder(url: url, role: role, runID: "t"), url)
    }

    private func records(_ url: URL) throws -> [BenchRecord] {
        try String(contentsOf: url, encoding: .utf8).split(separator: "\n").compactMap { BenchRecorder.parse($0) }
    }

    private func latest(_ records: [BenchRecord], _ domain: DigestDomain, element: Int, view: Int) -> UInt64? {
        records.last {
            $0.kind == BenchKind.state.rawValue && $0.sub == domain.rawValue && $0.id == UInt32(element)
                && $0.v1 == UInt64(view)
        }?.v0
    }

    /// Hosts and joins with a recorder on each side, drives the guest a few tiles east, lets
    /// both settle, and returns both logs with the guest's final state.
    private func recordedPair(
        hiddenMines: Bool
    ) async throws -> (host: [BenchRecord], guest: [BenchRecord], guestState: GameState, hostState: GameState) {
        let (hostRecorder, hostURL) = try log("host")
        let (guestRecorder, guestURL) = try log("join")
        defer {
            try? FileManager.default.removeItem(at: hostURL.deletingLastPathComponent())
            try? FileManager.default.removeItem(at: guestURL.deletingLastPathComponent())
        }

        let (engine, port) = try await makeHost(hiddenMines: hiddenMines)
        engine.benchRecorder = hostRecorder
        engine.start()

        let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
        var initial = GameState()
        initial.players = (0..<maxPlayers).map { _ in PlayerState() }
        #expect(applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial))
        let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
        let session = GameSession(
            tcpSession: joined.session, udpSession: udp, initialState: initial,
            tilesImage: image(), spritesImage: image())
        session.benchRecorder = guestRecorder
        session.start()

        let me = session.state.localPlayer
        try await waitUntil(timeout: 10) { !session.state.players[me].dead && !engine.state.players[me].dead }
        session.renderView.onInputFlagsChange?(KeyInputChange(set: .accel, clear: .brake))
        try await waitUntil(timeout: 15) { session.state.players[me].tank.x > 54 }
        session.renderView.onInputFlagsChange?(KeyInputChange(set: .brake, clear: .accel))
        // Wait on the two sides agreeing rather than on the clock: the host learns the guest's
        // position from its 10 Hz updates, and how long that takes depends on load.
        try await waitUntil(timeout: 15) {
            digestSelfStatus(player: me, state: engine.state) == digestSelfStatus(player: me, state: session.state)
                && session.state.players[me].speed == 0
        }
        // Then long enough for both to log it, including one 10 Hz grid sample.
        try await Task.sleep(nanoseconds: 500_000_000)

        engine.stop()
        await session.stop()
        try await Task.sleep(nanoseconds: 200_000_000)
        let hostState = engine.state
        let guestState = session.state
        udp.cancel(); joined.session.cancel()
        hostRecorder.finish()
        guestRecorder.finish()
        return (try records(hostURL), try records(guestURL), guestState, hostState)
    }

    @Test func theGuestRecordsNothingByDefault() async throws {
        let session = GameSession(initialState: GameState(), tilesImage: image(), spritesImage: image())
        #expect(session.benchRecorder == nil)
        #expect(session.renderView.benchRecorder == nil)
    }

    @Test func everyGuestTickIsRecordedOnceWithItsPhases() async throws {
        let (_, guest, _, _) = try await recordedPair(hiddenMines: true)

        let ticks = guest.filter { $0.kind == BenchKind.tick.rawValue }.map(\.id)
        #expect(ticks.count > 50)
        #expect(ticks == Array(1...UInt32(ticks.count)), "tick ordinals must be consecutive from 1")
        #expect(guest.filter { $0.kind == BenchKind.timerFire.rawValue }.count >= ticks.count)

        let phases = guest.filter { $0.kind == BenchKind.phase.rawValue }
        for phase in [BenchPhase.whole, .move, .builder, .shells, .explosions, .updateSend, .fog, .digest, .renderHop] {
            #expect(phases.filter { $0.sub == phase.rawValue }.count >= ticks.count - 1, "missing phase \(phase)")
        }

        // Every state handed to the renderer is counted, one per tick. The count does not start
        // at 1 here: the session renders once in `init`, before this test attaches its recorder.
        let generations = guest.filter { $0.kind == BenchKind.renderState.rawValue }.map(\.id)
        #expect(zip(generations, generations.dropFirst()).allSatisfy { $1 == $0 + 1 })
        #expect(generations.count >= ticks.count - 1)
        #expect(!guest.contains { $0.kind == BenchKind.invariant.rawValue })
    }

    @Test func theLastLoggedStateIsTheGuestsFinalState() async throws {
        let (_, guest, state, _) = try await recordedPair(hiddenMines: true)
        let me = state.localPlayer

        #expect(latest(guest, .selfStatus, element: 0, view: me) == digestSelfStatus(player: me, state: state))
        let resources = digestResources(player: me, state: state)
        for resource in DigestResource.allCases {
            #expect(latest(guest, .resources, element: resource.rawValue, view: me) == resources[resource.rawValue])
        }
        #expect(latest(guest, .pills, element: 0, view: me) == digestValue(state.pills[0]))
        #expect(latest(guest, .peers, element: 0, view: me) == digestPeer(state.players[0]))

        // The tile under the guest's tank is inside its own vision; a far corner is not.
        let tank = state.players[me].tank
        let under = Int(tank.y) * 256 + Int(tank.x)
        #expect(latest(guest, .terrain, element: under, view: me) == UInt64(Terrain.grass0.rawValue))
        #expect(latest(guest, .terrain, element: 0, view: me) == digestUnknownTerrain)
    }

    /// The comparison the whole benchmark rests on: once both sides have settled, what the host
    /// expects the guest to hold and what the guest holds are logged as the same values.
    @Test func hostAndGuestLogsAgreeOnceSettled() async throws {
        let (host, guest, guestState, hostState) = try await recordedPair(hiddenMines: true)
        let me = guestState.localPlayer

        #expect(latest(host, .pills, element: 0, view: me) == latest(guest, .pills, element: 0, view: me))
        for resource in [DigestResource.armour, .shells, .mines] {
            #expect(
                latest(host, .resources, element: resource.rawValue, view: me)
                    == latest(guest, .resources, element: resource.rawValue, view: me),
                "\(resource) differs"
            )
        }
        // Each log must match its own side's final state whether or not the two sides agree.
        #expect(latest(host, .selfStatus, element: 0, view: me) == digestSelfStatus(player: me, state: hostState))
        #expect(latest(guest, .selfStatus, element: 0, view: me) == digestSelfStatus(player: me, state: guestState))
        // And here the two sides did agree, so the logs must too.
        #expect(
            digestSelfStatus(player: me, state: hostState) == digestSelfStatus(player: me, state: guestState),
            "host and guest never agreed on the guest's own status"
        )
        #expect(latest(host, .selfStatus, element: 0, view: me) == latest(guest, .selfStatus, element: 0, view: me))

        let tank = guestState.players[me].tank
        let under = Int(tank.y) * 256 + Int(tank.x)
        #expect(latest(host, .terrain, element: under, view: me) == latest(guest, .terrain, element: under, view: me))
        #expect(latest(host, .fog, element: under, view: me).map { $0 & 1 } == 1)
        #expect(latest(guest, .fog, element: under, view: me).map { $0 & 1 } == 1)
    }
}
