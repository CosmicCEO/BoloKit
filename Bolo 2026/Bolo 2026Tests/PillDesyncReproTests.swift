//
//  PillDesyncReproTests.swift
//  Bolo 2026Tests
//
//  Real host + real join client. Live report: a guest saw a 3x3 block of its own dropped pills
//  it could not pick up, and died at once driving onto the centre one, which the host showed as
//  a damaged live pillbox.
//

import CoreGraphics
import Foundation
import Testing
import BoloKit
import BoloNet

@testable import Bolo_2026

private enum PillHarnessError: Error { case noPort }

@MainActor
struct PillDesyncReproTests {

    private func image() -> CGImage {
        let ctx = CGContext(
            data: nil, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
            space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        return ctx.makeImage()!
    }

    /// Host tank is placed alive, away from the single start at (50, 50) the guest spawns on.
    private func makeHost(
        pills: [Pill], hostTank: Vec2f = Vec2f(x: 200.5, y: 200.5), hostDir: Float = 0
    ) async throws -> (engine: HostGameEngine, port: UInt16) {
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
            host.tank = hostTank
            host.dir = hostDir
            host.alliance = UInt16(1 << 0)
            state.players = hostPlayerSlots(hostPlayer: host)
            state.localPlayer = 0
            state.local.shells = 40
            state.local.armour = 40
            state.local.range = 7
            state.hostSimulatesRemotePlayers = true
            for y in 20..<240 { for x in 20..<240 { state.terrain.storage[y * 256 + x] = Terrain.grass0.rawValue } }
            state.starts = [Start(x: 50, y: 50, dir: 0)]
            state.pills = pills
            return (HostGameEngine(initialState: state, listener: tcp, dgramListener: udp), port)
        }
        throw PillHarnessError.noPort
    }

    private func join(_ port: UInt16) async throws -> (GameSession, UDPSession, TCPSession) {
        let joined = try await TCPSession.join(host: "127.0.0.1", port: port, name: "Guest", pass: "")
        var initial = GameState()
        initial.players = (0..<maxPlayers).map { _ in PlayerState() }
        #expect(applyBoloPreamble(joined.preamble, mapData: joined.mapData, state: &initial))
        let udp = try await UDPSession(host: joined.session.remoteHost, port: joined.session.remotePort)
        let session = GameSession(
            tcpSession: joined.session, udpSession: udp, initialState: initial,
            tilesImage: image(), spritesImage: image())
        session.start()
        return (session, udp, joined.session)
    }

    private func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) async throws {
        let deadline = Date().addingTimeInterval(timeout)
        while !condition(), Date() < deadline { try await Task.sleep(nanoseconds: 20_000_000) }
    }

    private func pillSummary(_ pills: [Pill]) -> [String] {
        pills.map { "(\($0.x),\($0.y)) armour \($0.armour) owner \($0.owner)" }
    }

    /// The host only announced a pickup when the pill's owner changed, so a guest collecting
    /// pills it already owned (dropped when it died) never saw them leave the ground.
    @Test func guestSeesItsOwnDroppedPillsBeingPickedUpAgain() async throws {
        var pills: [Pill] = []
        for i in 0..<9 {
            pills.append(Pill(x: UInt8(52 + i), y: 50, armour: 0, owner: playerNeutral, speed: 100, counter: 0))
        }
        let (engine, port) = try await makeHost(pills: pills, hostTank: Vec2f(x: 72.5, y: 50.5), hostDir: kPif)
        engine.start()
        defer { engine.stop() }
        let (session, udp, tcp) = try await join(port)
        defer { udp.cancel(); tcp.cancel() }
        let me = session.state.localPlayer
        try await waitUntil(timeout: 10) { !session.state.players[me].dead && !engine.state.players[me].dead }

        // Collect all nine driving east, into the host's fire, and die carrying them.
        engine.submitLocalInputChange(set: .shoot, clear: [])
        session.renderView.onInputFlagsChange?(KeyInputChange(set: .accel, clear: .brake))
        try await waitUntil(timeout: 30) { session.state.players[me].dead && engine.state.players[me].dead }
        engine.submitLocalInputChange(set: [], clear: .shoot)
        try await waitUntil(timeout: 10) { pillSummary(session.state.pills) == pillSummary(engine.state.pills) }
        #expect(engine.state.pills.contains { $0.armour == 0 && Int($0.owner) == me }, "died carrying pills")
        #expect(pillSummary(session.state.pills) == pillSummary(engine.state.pills))

        // Respawn and drive east again, through the dropped block.
        try await waitUntil(timeout: 10) { !session.state.players[me].dead && !engine.state.players[me].dead }
        try await waitUntil(timeout: 30) { session.state.players[me].tank.x > 70 || session.state.players[me].dead }
        session.renderView.onInputFlagsChange?(KeyInputChange(set: .brake, clear: .accel))
        try await waitUntil(timeout: 10) { pillSummary(session.state.pills) == pillSummary(engine.state.pills) }

        #expect(engine.state.pills.contains { $0.armour == pillOnboard }, "the host picked some up")
        #expect(pillSummary(session.state.pills) == pillSummary(engine.state.pills))
    }

    /// The guest stepped the host's shells forward itself between updates and let them damage
    /// pills locally, on top of the host's own `SRDamage`. Its armour count ran low, so a pill the
    /// host still held at armour 1 looked dead to the guest, which then drove onto it and died.
    @Test func guestAndHostAgreeOnPillArmourWhileTheHostShootsIt() async throws {
        let pills = [Pill(x: 60, y: 50, armour: 15, owner: 1, speed: 100, counter: 0)]
        let (engine, port) = try await makeHost(pills: pills, hostTank: Vec2f(x: 65.5, y: 50.5), hostDir: kPif)
        engine.start()
        defer { engine.stop() }
        let (session, udp, tcp) = try await join(port)
        defer { udp.cancel(); tcp.cancel() }
        let me = session.state.localPlayer
        try await waitUntil(timeout: 10) { !session.state.players[me].dead && !engine.state.players[me].dead }

        engine.submitLocalInputChange(set: .shoot, clear: [])
        try await waitUntil(timeout: 20) { engine.state.pills[0].armour <= 8 || engine.state.players[0].dead }
        engine.submitLocalInputChange(set: [], clear: .shoot)
        try await Task.sleep(nanoseconds: 1_500_000_000)
        try await waitUntil(timeout: 10) { session.state.pills[0].armour == engine.state.pills[0].armour }

        #expect(engine.state.pills[0].armour < 15, "the host did hit it")
        #expect(
            session.state.pills[0].armour == engine.state.pills[0].armour,
            "guest \(session.state.pills[0].armour) host \(engine.state.pills[0].armour)")
    }
}
