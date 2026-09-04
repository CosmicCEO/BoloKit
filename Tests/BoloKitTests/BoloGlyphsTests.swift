import Testing
import BoloKit
import BoloGlyphsCore

@Suite("BoloGlyphs asset pipeline (Wave 7.0)")
struct BoloGlyphsTests {

    // MARK: - Probe completeness (D62/D63)

    @Test("connectivity probe yields exactly the known per-family variant counts")
    func perFamilyVariantCounts() {
        #expect(deriveConnectivity(family: .wall).count == 47)
        #expect(deriveConnectivity(family: .river).count == 16)
        #expect(deriveConnectivity(family: .forest).count == 10)
        #expect(deriveConnectivity(family: .crater).count == 16)
        #expect(deriveConnectivity(family: .road).count == 31)
        #expect(deriveConnectivity(family: .boat).count == 8)
        #expect(deriveConnectivity(family: .sea).count == 9)
    }

    @Test("connectivity probe + flat/pill dispatch covers the dense tile range exactly once each")
    func tileRangeFullyCoveredNoOverlap() {
        let connectivity = deriveAllConnectivity()
        #expect(connectivity.count == 137)

        var seen = Set<Int32>()
        for index in tileIndexRange {
            guard let role = tileGlyphRole(for: index, connectivity: connectivity) else {
                Issue.record("tile index \(index) has no dispatch")
                continue
            }
            _ = role
            #expect(seen.insert(index).inserted)
        }
        #expect(seen.count == tileIndexRange.count)
        #expect(tileIndexRange.count == 177)
    }

    @Test("mapimage never returns -1 for any probed in-bounds neighbor configuration")
    func probeNeverHitsSentinel() {
        for family in TileFamily.allCases {
            for (image, _) in deriveConnectivity(family: family) {
                #expect(image >= 0)
            }
        }
    }

    // MARK: - Sprite index partition (D62)

    @Test("sprite validity matches the exact gap structure found in images.h")
    func spriteIndexPartition() {
        var validCount = 0
        for index: Int32 in 0...SELETRIMAGE {
            if isValidSpriteIndex(index) {
                validCount += 1
                #expect(spriteGlyphRole(for: index) != nil)
            } else {
                #expect(spriteGlyphRole(for: index) == nil)
            }
        }
        #expect(validCount == 113)

        // The three known gap runs (D62) must be invalid.
        for gap: ClosedRange<Int32> in [0x66...0x6f, 0x76...0x7f, 0x83...0x8f] {
            for index in gap {
                #expect(!isValidSpriteIndex(index))
            }
        }
    }

    // MARK: - Cell math (D64/D66)

    @Test("cell math round-trips for every valid tile and sprite index, top-left origin")
    func cellMathRoundTrips() {
        for index in tileIndexRange {
            #expect(Int32(cellRow(index) * 16 + cellCol(index)) == index)
        }
        for index: Int32 in 0...SELETRIMAGE where isValidSpriteIndex(index) {
            #expect(Int32(cellRow(index) * 16 + cellCol(index)) == index)
        }
    }

    // MARK: - Sheet geometry

    @Test("both sheets are 256x256 RGBA and every used cell has non-transparent pixels")
    func sheetGeometryAndCoverage() {
        let sheets = buildSheets()
        #expect(sheets.tiles.pixels.count == 256 * 256 * 4)
        #expect(sheets.sprites.pixels.count == 256 * 256 * 4)

        func hasOpaquePixel(_ sheet: RGBASheet, index: Int32) -> Bool {
            let originX = cellCol(index) * 16
            let originY = cellRow(index) * 16
            for y in 0..<16 {
                for x in 0..<16 {
                    let alphaOffset = ((originY + y) * RGBASheet.size + (originX + x)) * 4 + 3
                    if sheet.pixels[alphaOffset] != 0 { return true }
                }
            }
            return false
        }

        for index in tileIndexRange {
            #expect(hasOpaquePixel(sheets.tiles, index: index), "tile index \(index) has no visible content")
        }
        for index: Int32 in 0...SELETRIMAGE where isValidSpriteIndex(index) {
            #expect(hasOpaquePixel(sheets.sprites, index: index), "sprite index \(index) has no visible content")
        }
    }

    @Test("unused sprite gap cells are fully transparent")
    func unusedSpriteCellsAreTransparent() {
        let sheets = buildSheets()
        for gap: ClosedRange<Int32> in [0x66...0x6f, 0x76...0x7f, 0x83...0x8f] {
            for index in gap {
                let originX = cellCol(index) * 16
                let originY = cellRow(index) * 16
                for y in 0..<16 {
                    for x in 0..<16 {
                        let alphaOffset = ((originY + y) * RGBASheet.size + (originX + x)) * 4 + 3
                        #expect(sheets.sprites.pixels[alphaOffset] == 0)
                    }
                }
            }
        }
    }

    // MARK: - Determinism

    @Test("sheet generation is deterministic")
    func deterministic() {
        let a = buildSheets()
        let b = buildSheets()
        #expect(a.tiles.pixels == b.tiles.pixels)
        #expect(a.sprites.pixels == b.sprites.pixels)
    }
}
