import BoloKit

// Consumes BoloKit's existing 290 image constants and `mapimage()` as the
// single source of truth (D63) -- no re-parse of `images.h` here.

/// Cell math shared by both sheets, top-left origin (D66): `row = idx >> 4`,
/// `col = idx & 0xF`. `-1` (`mapimage()`'s "no image" sentinel) must never
/// reach these -- callers guard on `>= 0` first.
public func cellRow(_ index: Int32) -> Int { Int(index) >> 4 }
public func cellCol(_ index: Int32) -> Int { Int(index) & 0xF }

/// Tile sheet is dense `0x00`-`0xb0` (D62) -- every index in range is used.
public let tileIndexRange: ClosedRange<Int32> = 0x00...MINE00IMAGE

/// Sprite sheet is sparse (D62): tank rows + shells `0x00`-`0x65`,
/// explosions `0x70`-`0x75`, builder frames `0x80`-`0x82`, crosshair/select
/// `0x90`-`0x91`. Gaps (`0x66`-`0x6f`, `0x76`-`0x7f`, `0x83`-`0x8f`) are
/// unused cells, left transparent.
public func isValidSpriteIndex(_ idx: Int32) -> Bool {
    (0x00...SHELL5IMAGE).contains(idx) ||
        (EXPLO0IMAGE...EXPLO5IMAGE).contains(idx) ||
        (BUILD0IMAGE...BUILD2IMAGE).contains(idx) ||
        (CROSSHIMAGE...SELETRIMAGE).contains(idx)
}

public func tileGlyphRole(for index: Int32, connectivity: [Int32: ConnectiveGlyph]) -> GlyphRole? {
    if let g = connectivity[index] {
        return .connective(family: g.family, ortho: g.ortho, diag: g.diag)
    }
    switch index {
    case GRAS00IMAGE: return .flatFill(r: 70, g: 140, b: 60)
    case SWAM00IMAGE: return .flatFill(r: 110, g: 100, b: 50)
    case RUBB00IMAGE: return .flatFill(r: 120, g: 115, b: 110)
    case DAMG00IMAGE: return .flatFill(r: 150, g: 110, b: 70)
    case NBAS00IMAGE: return .flatFill(r: 200, g: 200, b: 60)
    case FBAS00IMAGE: return .flatFill(r: 60, g: 110, b: 220)
    case HBAS00IMAGE: return .flatFill(r: 200, g: 50, b: 50)
    case MINE00IMAGE: return .mine
    case FPIL00IMAGE...FPIL15IMAGE:
        return .pill(armor: Int(index - FPIL00IMAGE), friendly: true)
    case HPIL00IMAGE...HPIL15IMAGE:
        return .pill(armor: Int(index - HPIL00IMAGE), friendly: false)
    default:
        return nil
    }
}

/// Sprite-space dispatch is closed-form arithmetic on the index -- no
/// `mapimage()` probing needed. Tank rows 0-5 (`PTKB`/`PTNK`/`FTKB`/`FTNK`/
/// `ETKB`/`ETNK`) pair up as (dead, alive) x (player, friendly, enemy);
/// heading is the column, 0-15.
public func spriteGlyphRole(for index: Int32) -> GlyphRole? {
    guard isValidSpriteIndex(index) else { return nil }
    if index <= ETNK15IMAGE {
        let row = cellRow(index)
        let heading = cellCol(index)
        let ownership = row / 2
        let destroyed = row % 2 == 0
        return .tank(heading: heading, ownership: ownership, destroyed: destroyed)
    }
    if (SHELL0IMAGE...SHELL5IMAGE).contains(index) {
        return .shell(frame: Int(index - SHELL0IMAGE))
    }
    if (EXPLO0IMAGE...EXPLO5IMAGE).contains(index) {
        return .explosion(frame: Int(index - EXPLO0IMAGE))
    }
    if (BUILD0IMAGE...BUILD2IMAGE).contains(index) {
        return .builder(frame: Int(index - BUILD0IMAGE))
    }
    if index == CROSSHIMAGE { return .crosshair }
    if index == SELETRIMAGE { return .selectReticle }
    return nil
}
