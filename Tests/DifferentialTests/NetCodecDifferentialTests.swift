import Testing
import BoloKit
import BoloNet
import CXBolo

// Fuzzes the Wave 6.0 wire codec (Sources/BoloNet/CLUpdateCodec.swift,
// ClientMessages.swift, ServerMessages.swift) against the C oracle
// extracted in Sources/CXBolo/netops.c from sendclupdate()/dgramclient()
// (client.c:3509-3592, 1280-1472). Struct-layout assertions confirm the
// Swift codec's hardcoded field order/widths against the real headers'
// actual compiled layout, not a transcription of them.

@Suite struct NetCodecDifferentialTests {

    // MARK: - Struct-layout ground truth

    @Test func testCLUpdateHeaderLayoutMatchesOracle() {
        let layout = CXBolo.clupdate_layout_oracle()
        #expect(Int(layout.hdrSize) == CLUpdateHeader.wireSize)
        #expect(Int(layout.shellSize) == CLUpdateShell.wireSize)
        #expect(Int(layout.explosionSize) == CLUpdateExplosion.wireSize)
        #expect(Int(layout.offPlayer) == 0)
        #expect(Int(layout.offSeq) == 1)
        #expect(Int(layout.offTankStatus) == 65)
        #expect(Int(layout.offTankX) == 66)
        #expect(Int(layout.offTankY) == 70)
        #expect(Int(layout.offTankSpeed) == 74)
        #expect(Int(layout.offTankTurnSpeed) == 78)
        #expect(Int(layout.offTankKickDir) == 82)
        #expect(Int(layout.offTankKickSpeed) == 86)
        #expect(Int(layout.offTankDir) == 90)
        #expect(Int(layout.offBuilderStatus) == 91)
        #expect(Int(layout.offBuilderX) == 92)
        #expect(Int(layout.offBuilderY) == 96)
        #expect(Int(layout.offBuilderTargetX) == 100)
        #expect(Int(layout.offBuilderTargetY) == 101)
        #expect(Int(layout.offBuilderWait) == 102)
        #expect(Int(layout.offInputFlags) == 103)
        #expect(Int(layout.offTankShotSound) == 107)
        #expect(Int(layout.offPillShotSound) == 108)
        #expect(Int(layout.offSinkSound) == 109)
        #expect(Int(layout.offBuilderDeathSound) == 110)
        #expect(Int(layout.offNShells) == 111)
        #expect(Int(layout.offNExplosions) == 112)
    }

    @Test func testAllClOpcodeStructSizesMatchOracle() {
        let expected: [ClientOpcode: Int] = [
            .hangUp: 1, .sendMesg: 4, .dropBoat: 3, .dropPills: 11, .dropMine: 3,
            .touch: 3, .grabTile: 3, .grabTrees: 3, .buildRoad: 4, .buildWall: 4,
            .buildBoat: 4, .buildPill: 5, .repairPill: 4, .placeMine: 4, .damage: 4,
            .smallBoom: 3, .superBoom: 3, .refuel: 5, .hitTank: 6, .setAlliance: 3,
        ]
        for (opcode, size) in expected {
            let oracle = Int(CXBolo.sizeof_cl_oracle(Int32(opcode.rawValue)))
            #expect(oracle == size, "opcode \(opcode) expected \(size), oracle says \(oracle)")
        }
    }

    @Test func testAllSrOpcodeStructSizesMatchOracle() {
        let expected: [ServerOpcode: Int] = [
            .playerJoin: 50, .playerRejoin: 34, .playerExit: 2, .playerDisc: 2,
            .playerKick: 2, .playerBan: 2, .hangUp: 1, .sendMesg: 3, .damage: 5,
            .grabTrees: 3, .build: 4, .grow: 3, .flood: 3, .placeMine: 4, .dropMine: 4,
            .dropBoat: 3, .repairPill: 3, .coolPill: 2, .capturePill: 3, .buildPill: 5,
            .dropPill: 4, .replenishBase: 2, .captureBase: 3, .refuel: 5, .grabBoat: 4,
            .mineAck: 2, .builderAck: 4, .smallBoom: 4, .superBoom: 4, .hitTank: 6,
            .setAlliance: 4, .timeLimit: 3, .baseControl: 3, .pause: 2,
        ]
        for (opcode, size) in expected {
            let oracle = Int(CXBolo.sizeof_sr_oracle(Int32(opcode.rawValue)))
            #expect(oracle == size, "opcode \(opcode) expected \(size), oracle says \(oracle)")
        }
    }

    // MARK: - CLUpdate encode: Swift vs. oracle, byte-for-byte

    private func randomHeader() -> CLUpdateHeader {
        CLUpdateHeader(
            player: UInt8.random(in: 0..<UInt8(maxPlayers)),
            seq: (0..<maxPlayers).map { _ in Int32.random(in: .min ... .max) },
            dead: Bool.random(),
            boat: Bool.random(),
            dir: Float.random(in: 0..<BoloKit.k2Pif),
            tank: Vec2f(x: Float.random(in: 0..<256), y: Float.random(in: 0..<256)),
            speed: Float.random(in: -10...10),
            turnSpeed: Float.random(in: -10...10),
            kickDir: Float.random(in: 0..<BoloKit.k2Pif),
            kickSpeed: Float.random(in: 0...5),
            builderStatus: UInt8.random(in: 0...5),
            builder: Vec2f(x: Float.random(in: 0..<256), y: Float.random(in: 0..<256)),
            builderTargetX: UInt8.random(in: 0...255),
            builderTargetY: UInt8.random(in: 0...255),
            builderWait: UInt8.random(in: 0...255),
            inputFlags: Int32.random(in: .min ... .max),
            tankShotSound: Bool.random(),
            pillShotSound: Bool.random(),
            sinkSound: Bool.random(),
            builderDeathSound: Bool.random()
        )
    }

    private func randomShells(_ n: Int) -> [BoloNet.CLUpdateShell] {
        (0..<n).map { _ in
            BoloNet.CLUpdateShell(
                owner: UInt8.random(in: 0...255),
                point: BoloKit.Vec2f(x: Float.random(in: 0..<256), y: Float.random(in: 0..<256)),
                boat: Bool.random(),
                pill: Bool.random(),
                dir: Float.random(in: 0..<BoloKit.k2Pif),
                range: Float.random(in: 0...7)
            )
        }
    }

    private func randomExplosions(_ n: Int) -> [BoloNet.CLUpdateExplosion] {
        (0..<n).map { _ in
            BoloNet.CLUpdateExplosion(
                point: BoloKit.Vec2f(x: Float.random(in: 0..<256), y: Float.random(in: 0..<256)),
                counter: UInt8.random(in: 0...255)
            )
        }
    }

    private func oracleEncode(
        header: CLUpdateHeader, shells: [BoloNet.CLUpdateShell], explosions: [BoloNet.CLUpdateExplosion]
    ) -> [UInt8] {
        let input = CXBolo.CLUpdateEncodeInput(
            player: header.player,
            tankstatus: CLUpdateHeader.tankStatus(dead: header.dead, boat: header.boat),
            tank: CXBolo.Vec2f(x: header.tank.x, y: header.tank.y),
            speed: header.speed,
            turnspeed: header.turnSpeed,
            kickdir: header.kickDir,
            kickspeed: header.kickSpeed,
            dir: header.dir,
            builderstatus: header.builderStatus,
            builder: CXBolo.Vec2f(x: header.builder.x, y: header.builder.y),
            buildertargetx: header.builderTargetX,
            buildertargety: header.builderTargetY,
            builderwait: header.builderWait,
            inputflags: header.inputFlags,
            tankshotsound: header.tankShotSound ? 1 : 0,
            pillshotsound: header.pillShotSound ? 1 : 0,
            sinksound: header.sinkSound ? 1 : 0,
            builderdeathsound: header.builderDeathSound ? 1 : 0
        )

        let cShells = shells.map {
            CXBolo.ShellEncodeInput(
                owner: $0.owner, point: CXBolo.Vec2f(x: $0.point.x, y: $0.point.y),
                boat: $0.boat ? 1 : 0, pill: $0.pill ? 1 : 0, dir: $0.dir, range: $0.range
            )
        }
        let cExplosions = explosions.map {
            CXBolo.ExplosionEncodeInput(point: CXBolo.Vec2f(x: $0.point.x, y: $0.point.y), counter: $0.counter)
        }

        var out = CXBolo.CLUpdate()
        let length: Int = header.seq.withUnsafeBufferPointer { seqPtr in
            cShells.withUnsafeBufferPointer { shellsPtr in
                cExplosions.withUnsafeBufferPointer { explosionsPtr in
                    CXBolo.clupdate_encode_oracle(
                        input, seqPtr.baseAddress, shellsPtr.baseAddress, Int32(shells.count),
                        explosionsPtr.baseAddress, Int32(explosions.count), &out
                    )
                }
            }
        }

        return withUnsafeBytes(of: out) { raw in Array(raw.prefix(length)) }
    }

    @Test func testCLUpdateEncodeMatchesOracleFuzzed() {
        for _ in 0..<500 {
            let header = randomHeader()
            let nshells = Int.random(in: 0...6)
            let nexplosions = Int.random(in: 0...6)
            let shells = randomShells(nshells)
            let explosions = randomExplosions(nexplosions)

            let update = CLUpdate(header: header, shells: shells, explosions: explosions)
            let swiftBytes = update.encode()
            let oracleBytes = oracleEncode(header: header, shells: shells, explosions: explosions)

            #expect(swiftBytes == oracleBytes, "encode mismatch, nshells=\(nshells) nexplosions=\(nexplosions)")
        }
    }

    @Test func testCLUpdateEncodeMatchesOracleAtShellExplosionExtremes() {
        for n in [0, 1, 255] {
            let header = randomHeader()
            let shells = randomShells(n)
            let explosions = randomExplosions(n)
            let update = CLUpdate(header: header, shells: shells, explosions: explosions)
            let swiftBytes = update.encode()
            let oracleBytes = oracleEncode(header: header, shells: shells, explosions: explosions)
            #expect(swiftBytes == oracleBytes, "mismatch at n=\(n)")
        }
    }

    @Test func testCLUpdateEncodeMatchesOracleForNonFiniteFloats() {
        let weirdFloats: [Float] = [.nan, .infinity, -.infinity, -0.0, .leastNonzeroMagnitude]
        for f in weirdFloats {
            var header = randomHeader()
            header.tank = Vec2f(x: f, y: f)
            header.speed = f
            header.kickSpeed = f
            header.builder = Vec2f(x: f, y: f)

            let update = CLUpdate(header: header, shells: [], explosions: [])
            let swiftBytes = update.encode()
            let oracleBytes = oracleEncode(header: header, shells: [], explosions: [])

            // Raw-BE bit-reinterpret must match exactly, including NaN
            // payload bits -- this is a byte comparison, not `==` on Float.
            #expect(swiftBytes == oracleBytes, "non-finite float mismatch for \(f)")
        }
    }

    // MARK: - CLUpdate decode: Swift vs. oracle, field-for-field

    private struct OracleDecodeResult: Equatable {
        var valid: Bool
        var player: UInt8
        var seq: [Int32]
        var dead: Bool
        var boat: Bool
        var dir: Float
        var tank: BoloKit.Vec2f
        var speed: Float
        var turnSpeed: Float
        var kickDir: Float
        var kickSpeed: Float
        var builderStatus: UInt8
        var builder: BoloKit.Vec2f
        var builderTargetX: UInt8
        var builderTargetY: UInt8
        var builderWait: UInt8
        var inputFlags: Int32
        var tankShotSound: Bool
        var pillShotSound: Bool
        var sinkSound: Bool
        var builderDeathSound: Bool
        var shells: [BoloNet.CLUpdateShell]
        var explosions: [BoloNet.CLUpdateExplosion]
    }

    private func oracleDecode(_ bytes: [UInt8]) -> OracleDecodeResult {
        var hdr = CXBolo.CLUpdateDecodeOutput()
        var seq = [Int32](repeating: 0, count: maxPlayers)
        var cShells = [CXBolo.ShellDecodeOutput](repeating: CXBolo.ShellDecodeOutput(), count: CLUpdate.maxShells)
        var cExplosions = [CXBolo.ExplosionDecodeOutput](
            repeating: CXBolo.ExplosionDecodeOutput(), count: CLUpdate.maxExplosions
        )
        var nshells: Int32 = 0
        var nexplosions: Int32 = 0

        let ok: Int32 = bytes.withUnsafeBufferPointer { bytesPtr in
            seq.withUnsafeMutableBufferPointer { seqPtr in
                cShells.withUnsafeMutableBufferPointer { shellsPtr in
                    cExplosions.withUnsafeMutableBufferPointer { explosionsPtr in
                        CXBolo.clupdate_decode_oracle(
                            bytesPtr.baseAddress, bytes.count, &hdr, seqPtr.baseAddress,
                            shellsPtr.baseAddress, &nshells, explosionsPtr.baseAddress, &nexplosions
                        )
                    }
                }
            }
        }

        guard ok != 0 else {
            return OracleDecodeResult(
                valid: false, player: 0, seq: [], dead: false, boat: false, dir: 0,
                tank: Vec2f(x: 0, y: 0), speed: 0, turnSpeed: 0, kickDir: 0, kickSpeed: 0,
                builderStatus: 0, builder: Vec2f(x: 0, y: 0), builderTargetX: 0, builderTargetY: 0,
                builderWait: 0, inputFlags: 0, tankShotSound: false, pillShotSound: false,
                sinkSound: false, builderDeathSound: false, shells: [], explosions: []
            )
        }

        let shells = (0..<Int(nshells)).map { i in
            CLUpdateShell(
                owner: cShells[i].owner, point: Vec2f(x: cShells[i].point.x, y: cShells[i].point.y),
                boat: cShells[i].boat != 0, pill: cShells[i].pill != 0, dir: cShells[i].dir, range: cShells[i].range
            )
        }
        let explosions = (0..<Int(nexplosions)).map { i in
            CLUpdateExplosion(
                point: Vec2f(x: cExplosions[i].point.x, y: cExplosions[i].point.y),
                counter: cExplosions[i].counter
            )
        }

        return OracleDecodeResult(
            valid: true, player: hdr.player, seq: seq, dead: hdr.dead != 0, boat: hdr.boat != 0,
            dir: hdr.dir, tank: Vec2f(x: hdr.tank.x, y: hdr.tank.y), speed: hdr.speed,
            turnSpeed: hdr.turnspeed, kickDir: hdr.kickdir, kickSpeed: hdr.kickspeed,
            builderStatus: hdr.builderstatus, builder: Vec2f(x: hdr.builder.x, y: hdr.builder.y),
            builderTargetX: hdr.buildertargetx, builderTargetY: hdr.buildertargety,
            builderWait: hdr.builderwait, inputFlags: hdr.inputflags,
            tankShotSound: hdr.tankshotsound != 0, pillShotSound: hdr.pillshotsound != 0,
            sinkSound: hdr.sinksound != 0, builderDeathSound: hdr.builderdeathsound != 0,
            shells: shells, explosions: explosions
        )
    }

    @Test func testCLUpdateDecodeMatchesOracleFuzzed() {
        for _ in 0..<500 {
            let header = randomHeader()
            let nshells = Int.random(in: 0...6)
            let nexplosions = Int.random(in: 0...6)
            let shells = randomShells(nshells)
            let explosions = randomExplosions(nexplosions)
            let wireBytes = CLUpdate(header: header, shells: shells, explosions: explosions).encode()

            guard let swiftDecoded = CLUpdate.decode(wireBytes) else {
                Issue.record("Swift decode rejected a Swift-encoded datagram")
                continue
            }
            let oracle = oracleDecode(wireBytes)

            #expect(oracle.valid)
            #expect(swiftDecoded.header.player == oracle.player)
            #expect(swiftDecoded.header.seq == oracle.seq)
            #expect(swiftDecoded.header.dead == oracle.dead)
            #expect(swiftDecoded.header.boat == oracle.boat)
            #expect(swiftDecoded.header.dir == oracle.dir)
            #expect(swiftDecoded.header.tank == oracle.tank)
            #expect(swiftDecoded.header.speed == oracle.speed)
            #expect(swiftDecoded.header.turnSpeed == oracle.turnSpeed)
            #expect(swiftDecoded.header.kickDir == oracle.kickDir)
            #expect(swiftDecoded.header.kickSpeed == oracle.kickSpeed)
            #expect(swiftDecoded.header.builderStatus == oracle.builderStatus)
            #expect(swiftDecoded.header.builder == oracle.builder)
            #expect(swiftDecoded.header.builderTargetX == oracle.builderTargetX)
            #expect(swiftDecoded.header.builderTargetY == oracle.builderTargetY)
            #expect(swiftDecoded.header.builderWait == oracle.builderWait)
            #expect(swiftDecoded.header.inputFlags == oracle.inputFlags)
            #expect(swiftDecoded.header.tankShotSound == oracle.tankShotSound)
            #expect(swiftDecoded.header.pillShotSound == oracle.pillShotSound)
            #expect(swiftDecoded.header.sinkSound == oracle.sinkSound)
            #expect(swiftDecoded.header.builderDeathSound == oracle.builderDeathSound)
            #expect(swiftDecoded.shells == oracle.shells)
            #expect(swiftDecoded.explosions == oracle.explosions)
        }
    }

    @Test func testCLUpdateDecodeRejectsShortDatagramLikeOracle() {
        let header = randomHeader()
        let full = CLUpdate(header: header, shells: randomShells(2), explosions: []).encode()

        for truncateAt in [0, 1, 64, CLUpdateHeader.wireSize - 1, CLUpdateHeader.wireSize + 5] {
            let truncated = Array(full.prefix(truncateAt))
            #expect(CLUpdate.decode(truncated) == nil, "Swift accepted a short datagram at length \(truncateAt)")
            #expect(!oracleDecode(truncated).valid, "oracle accepted a short datagram at length \(truncateAt)")
        }
    }

    @Test func testCLUpdateDecodeRejectsInvalidPlayerLikeOracle() {
        var header = randomHeader()
        header.player = UInt8(maxPlayers)  // one past the valid range
        let bytes = CLUpdate(header: header, shells: [], explosions: []).encode()

        #expect(CLUpdate.decode(bytes) == nil)
        #expect(!oracleDecode(bytes).valid)
    }

    // MARK: - Named regression tests for the corrected trap list

    /// Trap 1: `CLUpdateExplosion.tile` is never written by the real
    /// encoder and never read by the real decoder. Confirms the Swift
    /// encoder emits a deterministic 0 (not garbage) and the decoder's
    /// output has no field for it at all.
    @Test func testExplosionTileByteIsAlwaysZeroOnEncode() {
        let explosion = CLUpdateExplosion(point: Vec2f(x: 12.5, y: 34.25), counter: 7)
        var w = WireWriter()
        explosion.encode(into: &w)
        // offset 4 within the 6-byte explosion record is `tile`.
        #expect(w.bytes[4] == 0)
    }

    /// Trap 5: fixed-point encode truncates, never rounds
    /// (`(uint16_t)(x*FWIDTH)` is a C cast, not `roundf`).
    @Test func testFixedPointEncodeTruncatesNotRounds() {
        // 1.99609375 * 256 == 511.0 exactly; pick a value whose product has
        // a fractional remainder so truncation and rounding disagree.
        // `x*FWIDTH` promotes to Double on the real C side (FWIDTH is an
        // unsuffixed literal) -- see fixedEncode's doc comment -- so the
        // sanity check below reproduces that same Double intermediate
        // rather than a naive Float multiply.
        let v: Float = 1.998
        let doubleProduct = Double(v) * 256.0
        let encoded = fixedEncode(v)
        #expect(encoded == UInt16(doubleProduct))  // sanity: matches the raw truncating cast
        #expect(Double(encoded) < doubleProduct)  // truncation strictly discards the fractional part
    }

    /// Trap 6: sequence comparison must be wraparound-tolerant signed
    /// subtraction (`client.c:1333`), not a trapping `-`.
    @Test func testSeqComparisonIsWraparoundTolerant() {
        #expect(isNewerSeq(5, than: 3))
        #expect(!isNewerSeq(3, than: 5))
        // Wraps past Int32.max: a "newer" sequence number that overflowed
        // must still compare as newer, matching C's silent signed wrap.
        #expect(isNewerSeq(Int32.min, than: Int32.max))
        #expect(!isNewerSeq(Int32.max, than: Int32.min))
    }

    /// DEEPDIVE1's trap-list item 7 claimed a double-`htons()` bug in
    /// `sendmessage()`'s MSGNEARBY case. Direct read of
    /// `client.c:6705-6744` shows a single effective swap and correct
    /// code -- this test exists to make sure no "fix" for that
    /// non-existent bug is ever ported into `CLSendMesg`'s codec: the
    /// mask must round-trip as an ordinary signed BE int16, nothing more.
    @Test func testSendMesgMaskHasNoDoubleSwap() {
        let msg = CLSendMesg(to: 0, mask: 0x00FF, text: "hi")
        let bytes = msg.encode()
        // offset 2-3 within the struct is `mask`, BE: 0x00FF -> [0x00, 0xFF].
        #expect(bytes[2] == 0x00)
        #expect(bytes[3] == 0xFF)
        #expect(CLSendMesg.decode(bytes)?.mask == 0x00FF)
    }

    // MARK: - Client/server TCP struct round trips

    @Test func testAllClientMessagesRoundTrip() {
        #expect(CLHangUp.decode(CLHangUp().encode()) == CLHangUp())
        #expect(CLSendMesg.decode(CLSendMesg(to: 3, mask: -1, text: "gg").encode())
            == CLSendMesg(to: 3, mask: -1, text: "gg"))
        #expect(CLDropBoat.decode(CLDropBoat(x: 1, y: 2).encode()) == CLDropBoat(x: 1, y: 2))
        #expect(CLDropPills.decode(CLDropPills(x: 12.5, y: -3.25, pills: 0xBEEF).encode())
            == CLDropPills(x: 12.5, y: -3.25, pills: 0xBEEF))
        #expect(CLDropMine.decode(CLDropMine(x: 4, y: 5).encode()) == CLDropMine(x: 4, y: 5))
        #expect(CLTouch.decode(CLTouch(x: 6, y: 7).encode()) == CLTouch(x: 6, y: 7))
        #expect(CLGrabTile.decode(CLGrabTile(x: 8, y: 9).encode()) == CLGrabTile(x: 8, y: 9))
        #expect(CLGrabTrees.decode(CLGrabTrees(x: 10, y: 11).encode()) == CLGrabTrees(x: 10, y: 11))
        #expect(CLBuildRoad.decode(CLBuildRoad(x: 1, y: 2, trees: 2).encode()) == CLBuildRoad(x: 1, y: 2, trees: 2))
        #expect(CLBuildWall.decode(CLBuildWall(x: 1, y: 2, trees: 2).encode()) == CLBuildWall(x: 1, y: 2, trees: 2))
        #expect(CLBuildBoat.decode(CLBuildBoat(x: 1, y: 2, trees: 20).encode()) == CLBuildBoat(x: 1, y: 2, trees: 20))
        #expect(CLBuildPill.decode(CLBuildPill(x: 1, y: 2, trees: 4, pill: 3).encode())
            == CLBuildPill(x: 1, y: 2, trees: 4, pill: 3))
        #expect(CLRepairPill.decode(CLRepairPill(x: 1, y: 2, trees: 4).encode()) == CLRepairPill(x: 1, y: 2, trees: 4))
        #expect(CLPlaceMine.decode(CLPlaceMine(x: 1, y: 2, mines: 1).encode()) == CLPlaceMine(x: 1, y: 2, mines: 1))
        #expect(CLDamage.decode(CLDamage(x: 1, y: 2, boat: 1).encode()) == CLDamage(x: 1, y: 2, boat: 1))
        #expect(CLSmallBoom.decode(CLSmallBoom(x: 1, y: 2).encode()) == CLSmallBoom(x: 1, y: 2))
        #expect(CLSuperBoom.decode(CLSuperBoom(x: 1, y: 2).encode()) == CLSuperBoom(x: 1, y: 2))
        #expect(CLRefuel.decode(CLRefuel(base: 1, armour: 2, shells: 3, mines: 4).encode())
            == CLRefuel(base: 1, armour: 2, shells: 3, mines: 4))
        #expect(CLHitTank.decode(CLHitTank(player: 1, dir: 1.5707964).encode())
            == CLHitTank(player: 1, dir: 1.5707964))
        #expect(CLSetAlliance.decode(CLSetAlliance(alliance: 0xF0F0).encode()) == CLSetAlliance(alliance: 0xF0F0))
    }

    @Test func testAllServerMessagesRoundTrip() {
        #expect(SRPlayerJoin.decode(SRPlayerJoin(player: 1, name: "Alice", host: "10.0.0.1").encode())
            == SRPlayerJoin(player: 1, name: "Alice", host: "10.0.0.1"))
        #expect(SRPlayerRejoin.decode(SRPlayerRejoin(player: 1, host: "10.0.0.1").encode())
            == SRPlayerRejoin(player: 1, host: "10.0.0.1"))
        #expect(SRPlayerExit.decode(SRPlayerExit(player: 2).encode()) == SRPlayerExit(player: 2))
        #expect(SRPlayerDisc.decode(SRPlayerDisc(player: 2).encode()) == SRPlayerDisc(player: 2))
        #expect(SRPlayerKick.decode(SRPlayerKick(player: 2).encode()) == SRPlayerKick(player: 2))
        #expect(SRPlayerBan.decode(SRPlayerBan(player: 2).encode()) == SRPlayerBan(player: 2))
        #expect(SRHangUp.decode(SRHangUp().encode()) == SRHangUp())
        #expect(SRSendMesg.decode(SRSendMesg(player: 1, to: 0, text: "yo").encode())
            == SRSendMesg(player: 1, to: 0, text: "yo"))
        #expect(SRDamage.decode(SRDamage(player: 1, x: 2, y: 3, terrain: 4).encode())
            == SRDamage(player: 1, x: 2, y: 3, terrain: 4))
        #expect(SRGrabTrees.decode(SRGrabTrees(x: 1, y: 2).encode()) == SRGrabTrees(x: 1, y: 2))
        #expect(SRBuild.decode(SRBuild(x: 1, y: 2, terrain: 3).encode()) == SRBuild(x: 1, y: 2, terrain: 3))
        #expect(SRGrow.decode(SRGrow(x: 1, y: 2).encode()) == SRGrow(x: 1, y: 2))
        #expect(SRFlood.decode(SRFlood(x: 1, y: 2).encode()) == SRFlood(x: 1, y: 2))
        #expect(SRPlaceMine.decode(SRPlaceMine(player: 1, x: 2, y: 3).encode())
            == SRPlaceMine(player: 1, x: 2, y: 3))
        #expect(SRDropMine.decode(SRDropMine(player: 1, x: 2, y: 3).encode()) == SRDropMine(player: 1, x: 2, y: 3))
        #expect(SRDropBoat.decode(SRDropBoat(x: 1, y: 2).encode()) == SRDropBoat(x: 1, y: 2))
        #expect(SRRepairPill.decode(SRRepairPill(pill: 1, armour: 2).encode()) == SRRepairPill(pill: 1, armour: 2))
        #expect(SRCoolPill.decode(SRCoolPill(pill: 1).encode()) == SRCoolPill(pill: 1))
        #expect(SRCapturePill.decode(SRCapturePill(pill: 1, owner: 2).encode())
            == SRCapturePill(pill: 1, owner: 2))
        #expect(SRBuildPill.decode(SRBuildPill(pill: 1, x: 2, y: 3, armour: 4).encode())
            == SRBuildPill(pill: 1, x: 2, y: 3, armour: 4))
        #expect(SRDropPill.decode(SRDropPill(pill: 1, x: 2, y: 3).encode()) == SRDropPill(pill: 1, x: 2, y: 3))
        #expect(SRReplenishBase.decode(SRReplenishBase(base: 1).encode()) == SRReplenishBase(base: 1))
        #expect(SRCaptureBase.decode(SRCaptureBase(base: 1, owner: 2).encode())
            == SRCaptureBase(base: 1, owner: 2))
        #expect(SRRefuel.decode(SRRefuel(base: 1, armour: 2, shells: 3, mines: 4).encode())
            == SRRefuel(base: 1, armour: 2, shells: 3, mines: 4))
        #expect(SRGrabBoat.decode(SRGrabBoat(player: 1, x: 2, y: 3).encode()) == SRGrabBoat(player: 1, x: 2, y: 3))
        #expect(SRMineAck.decode(SRMineAck(success: 1).encode()) == SRMineAck(success: 1))
        #expect(SRBuilderAck.decode(SRBuilderAck(mines: 1, trees: 2, pill: 3).encode())
            == SRBuilderAck(mines: 1, trees: 2, pill: 3))
        #expect(SRSmallBoom.decode(SRSmallBoom(player: 1, x: 2, y: 3).encode())
            == SRSmallBoom(player: 1, x: 2, y: 3))
        #expect(SRSuperBoom.decode(SRSuperBoom(player: 1, x: 2, y: 3).encode())
            == SRSuperBoom(player: 1, x: 2, y: 3))
        #expect(SRHitTank.decode(SRHitTank(player: 1, dir: 3.14159).encode())
            == SRHitTank(player: 1, dir: 3.14159))
        #expect(SRSetAlliance.decode(SRSetAlliance(player: 1, alliance: 0x1234).encode())
            == SRSetAlliance(player: 1, alliance: 0x1234))
        #expect(SRTimeLimit.decode(SRTimeLimit(timeRemaining: 600).encode()) == SRTimeLimit(timeRemaining: 600))
        #expect(SRBaseControl.decode(SRBaseControl(timeLeft: 60).encode()) == SRBaseControl(timeLeft: 60))
        #expect(SRPause.decode(SRPause(pause: 1).encode()) == SRPause(pause: 1))
    }

    // MARK: - Brad encoding: full 256-value sweep against the oracle
    //
    // NOT a `bradEncode(bradDecode(b)) == b` round-trip identity -- that
    // isn't a real property of the algorithm (single-precision rounding
    // in the two multiplications can shift the result by one step, and
    // the real C would do exactly the same on the same inputs, since it's
    // the same IEEE-754 arithmetic in the same order). What actually
    // matters, and is a real parity concern, is that Swift's encoder
    // produces the same wire byte the oracle's encoder does for every one
    // of the 256 possible `dir` values a decoded brad byte can produce.

    @Test func testBradEncodingCoversAll256ValuesAgainstOracle() {
        for b: UInt8 in 0...255 {
            var header = randomHeader()
            header.dir = bradDecode(b)
            let swiftBytes = CLUpdate(header: header, shells: [], explosions: []).encode()
            let oracleBytes = oracleEncode(header: header, shells: [], explosions: [])
            #expect(swiftBytes == oracleBytes, "brad byte b=\(b) diverged from oracle")
        }
    }
}
