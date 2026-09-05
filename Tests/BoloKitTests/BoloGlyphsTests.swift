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

    // MARK: - Connective corner fill (Wave 7.2 finding, GlyphSource.swift's drawConnective)

    private func isFullyOpaque(_ patch: Canvas16) -> Bool {
        !stride(from: 3, to: patch.pixels.count, by: 4).contains { patch.pixels[$0] != 255 }
    }

    @Test(
        "a family with no tracked diagonal bits (sea/river/forest/crater/boat) renders a solid fill when fully orthogonally connected, not a cross with transparent corners",
        arguments: [TileFamily.sea, .river, .forest, .crater, .boat]
    )
    func nonDiagonalFamilyFullyConnectedIsSolid(family: TileFamily) {
        let patch = renderGlyph(.connective(family: family, ortho: 0b1111, diag: 0))
        #expect(isFullyOpaque(patch), "\(family) should render a solid fill when all 4 orthogonal neighbors connect")
    }

    @Test("wall's real diagonal tracking is unaffected by the corner-inference fix")
    func wallCornerFillStillUsesItsOwnDiagBitsNotInference() {
        // Orthogonally connected on all 4 sides but explicitly no diagonal neighbors --
        // wall must still leave all four corners transparent, unlike the inferred families
        // above, since it has real diagonal data to trust instead of inferring from ortho.
        let noDiag = renderGlyph(.connective(family: .wall, ortho: 0b1111, diag: 0))
        #expect(!isFullyOpaque(noDiag), "wall must not infer corners from ortho pairs -- it tracks real diag bits")

        // Fully connected on every side, including diagonals -- must be solid, same as before.
        let fullDiag = renderGlyph(.connective(family: .wall, ortho: 0b1111, diag: 0b1111))
        #expect(isFullyOpaque(fullDiag))
    }

    @Test("D86: road's real diagonal tracking is unaffected by the corner-inference fix, and images 81/143 render distinctly")
    func roadCornerFillStillUsesItsOwnDiagBitsNotInference() {
        // Orthogonally connected on all 4 sides but explicitly no diagonal neighbors -- like
        // wall, road has real diagonal data (`deriveRoadConnectivity()`) to trust instead of
        // inferring corners from ortho pairs, so it must still leave all four corners
        // transparent here, unlike the inferred families above.
        let noDiag = renderGlyph(.connective(family: .road, ortho: 0b1111, diag: 0))
        #expect(!isFullyOpaque(noDiag), "road must not infer corners from ortho pairs -- it tracks real diag bits")

        // Fully connected on every side, including diagonals -- must be solid.
        let fullDiag = renderGlyph(.connective(family: .road, ortho: 0b1111, diag: 0b1111))
        #expect(isFullyOpaque(fullDiag))

        // PARITY's D86 finding, reproduced directly: with ortho=15 fully connected, the
        // diag=0 and diag=15 configurations -- images 143 and 81 respectively, per
        // `deriveConnectivity(family: .road)` -- must render as visually distinct patches,
        // not the pixel-identical collapse the regression produced.
        #expect(noDiag.pixels != fullDiag.pixels, "road's diag=0 and diag=15 variants at ortho=15 (images 143/81) must render differently")

        // Confirm those two connectivities really do correspond to images 81 and 143, so this
        // test is anchored to the actual regression PARITY measured, not just a generic shape.
        let roadConnectivity = deriveConnectivity(family: .road)
        #expect(roadConnectivity[81]?.ortho == 0b1111 && roadConnectivity[81]?.diag == 0b1111)
        #expect(roadConnectivity[143]?.ortho == 0b1111 && roadConnectivity[143]?.diag == 0)
    }

    // MARK: - Tank heading convention (D70)

    /// Centroid of every non-transparent pixel in a 16x16 patch, relative
    /// to the cell center (8, 8). A nose-forward triangle's pixel mass sits
    /// opposite its tip, so this centroid should point *against*
    /// `dir2vec(heading)`, not with it -- see the two explicit checks below.
    private func centroidOffsetFromCenter(_ patch: Canvas16) -> (Double, Double) {
        var sumX = 0.0, sumY = 0.0, count = 0.0
        for y in 0..<Canvas16.size {
            for x in 0..<Canvas16.size {
                let a = patch.pixels[(y * Canvas16.size + x) * 4 + 3]
                if a != 0 {
                    sumX += Double(x) + 0.5
                    sumY += Double(y) + 0.5
                    count += 1
                }
            }
        }
        return (sumX / count - 8.0, sumY / count - 8.0)
    }

    @Test("tank heading 0 points screen-east, matching dir2vec(0), not screen-north")
    func tankHeadingZeroPointsEast() {
        let patch = renderGlyph(.tank(heading: 0, ownership: 0, destroyed: false))
        let (offX, offY) = centroidOffsetFromCenter(patch)
        // Tip points east (+x); pixel mass sits behind it, toward -x.
        #expect(offX < -0.5)
        #expect(abs(offY) < 0.5)
    }

    @Test("tank headings sweep counterclockwise on screen as the index increases, matching dir2vec")
    func tankHeadingsSweepCounterclockwise() {
        // heading 4 -> dir = pi/2 -> dir2vec = (0, -1) = screen-north.
        let north = centroidOffsetFromCenter(renderGlyph(.tank(heading: 4, ownership: 0, destroyed: false)))
        #expect(north.1 > 0.5)   // mass sits south (behind a north-pointing tip)
        #expect(abs(north.0) < 0.5)

        // heading 8 -> dir = pi -> dir2vec = (-1, 0) = screen-west.
        let west = centroidOffsetFromCenter(renderGlyph(.tank(heading: 8, ownership: 0, destroyed: false)))
        #expect(west.0 > 0.5)    // mass sits east (behind a west-pointing tip)
        #expect(abs(west.1) < 0.5)

        // heading 12 -> dir = 3pi/2 -> dir2vec = (0, 1) = screen-south.
        let south = centroidOffsetFromCenter(renderGlyph(.tank(heading: 12, ownership: 0, destroyed: false)))
        #expect(south.1 < -0.5)  // mass sits north (behind a south-pointing tip)
        #expect(abs(south.0) < 0.5)
    }

    @Test("every heading's rendered tip direction matches dir2vec, not an independently-derived angle")
    func allHeadingsMatchDir2Vec() {
        for heading in 0..<16 {
            let patch = renderGlyph(.tank(heading: heading, ownership: 0, destroyed: false))
            let (offX, offY) = centroidOffsetFromCenter(patch)
            let mag = (offX * offX + offY * offY).squareRoot()
            guard mag > 0 else {
                Issue.record("heading \(heading) rendered no pixels")
                continue
            }
            let expected = dir2vec(Float(heading) * (kPif / 8.0))
            // Pixel mass points opposite the tip, i.e. opposite dir2vec.
            let cosineSimilarity = (offX * -Double(expected.x) + offY * -Double(expected.y)) / mag
            #expect(cosineSimilarity > 0.8, "heading \(heading) diverges from dir2vec")
        }
    }

    // MARK: - PNG round-trip (D77 -- PARITY's F1: nothing previously decoded an emitted PNG)

    @Test("emitted PNG bytes match source buffer intent, including partial-alpha pixels")
    func pngRoundTripPreservesStraightAlpha() throws {
        let sheets = buildSheets()
        for (label, sheet) in [("tiles", sheets.tiles), ("sprites", sheets.sprites)] {
            let data = try #require(encodePNGData(sheet.pixels, size: RGBASheet.size), "\(label) failed to encode")
            let decoded = try #require(decodePNGToStraightAlphaRGBA(data), "\(label) failed to decode")
            #expect(decoded.count == sheet.pixels.count, "\(label) size mismatch")

            var maxDiff = 0
            for i in stride(from: 0, to: sheet.pixels.count, by: 4) {
                // Alpha itself must be exact; RGB is allowed +/-1 for the premultiply/
                // un-premultiply round-trip's integer rounding, but no more than that --
                // this is the specific tolerance that would have caught F1 (a 14/255 drift).
                #expect(decoded[i + 3] == sheet.pixels[i + 3], "\(label) alpha drift at pixel \(i / 4)")
                for c in 0..<3 {
                    let diff = abs(Int(decoded[i + c]) - Int(sheet.pixels[i + c]))
                    maxDiff = max(maxDiff, diff)
                }
            }
            #expect(maxDiff <= 1, "\(label) RGB round-trip drift exceeds rounding tolerance: max diff \(maxDiff)")
        }
    }

    @Test("a known partial-alpha source pixel survives PNG round-trip exactly")
    func pngRoundTripPillBackingPixel() throws {
        // GlyphSource.swift's pill backing is fillRect(..., 50, 50, 50, 200) -- the exact
        // pixel PARITY measured as shipping RGB(64,64,64) before the D77 fix.
        var patch = Canvas16()
        patch.fillRect(0, 0, 16, 16, 50, 50, 50, 200)
        let data = try #require(encodePNGData(patch.pixels, size: Canvas16.size))
        let decoded = try #require(decodePNGToStraightAlphaRGBA(data))
        #expect(Array(decoded[0..<4]) == [50, 50, 50, 200])
    }

    // MARK: - Determinism

    @Test("sheet generation is deterministic")
    func deterministic() {
        let a = buildSheets()
        let b = buildSheets()
        #expect(a.tiles.pixels == b.tiles.pixels)
        #expect(a.sprites.pixels == b.sprites.pixels)
    }

    // MARK: - Placeholder app icon (Wave 7.1)

    @Test("every macOS AppIcon slot size is an exact whole multiple of the 16x16 glyph")
    func iconSizesScaleExactly() {
        // The generator nearest-neighbour replicates pixels; a non-multiple would need
        // resampling and would blur the pixel art.
        for size in appIconPixelSizes {
            #expect(size % Canvas16.size == 0)
        }
        // The distinct pixel sizes the 1x/2x mac slots in AppIcon.appiconset resolve to.
        #expect(appIconPixelSizes == [16, 32, 64, 128, 256, 512, 1024])
    }

    @Test("app icon is fully opaque at every size and sized correctly")
    func iconIsOpaqueAndCorrectlySized() {
        for size in appIconPixelSizes {
            let icon = buildAppIcon(size: size)
            #expect(icon.size == size)
            #expect(icon.pixels.count == size * size * 4)
            // The grass base fills all 16x16, so compositing the tank over it must leave no
            // transparent pixel anywhere -- a macOS app icon with holes would look broken.
            let transparent = stride(from: 3, to: icon.pixels.count, by: 4).contains {
                icon.pixels[$0] != 255
            }
            #expect(!transparent)
        }
    }

    @Test("app icon upscale is exact pixel replication of the 16x16 base")
    func iconUpscaleIsExactReplication() {
        let base = buildAppIconBase()
        let scale = 4
        let icon = buildAppIcon(size: Canvas16.size * scale)
        for y in 0..<icon.size {
            for x in 0..<icon.size {
                let src = ((y / scale) * Canvas16.size + x / scale) * 4
                let dst = (y * icon.size + x) * 4
                #expect(Array(icon.pixels[dst..<dst + 4]) == Array(base.pixels[src..<src + 4]))
            }
        }
    }

    @Test("app icon generation is deterministic")
    func iconDeterministic() {
        #expect(buildAppIcon(size: 256).pixels == buildAppIcon(size: 256).pixels)
    }
}
