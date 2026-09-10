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
    case NBAS00IMAGE: return .base(ownership: .neutral)
    case FBAS00IMAGE: return .base(ownership: .friendly)
    case HBAS00IMAGE: return .base(ownership: .hostile)
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
/// `ETKB`/`ETNK`) pair up as (boat, tank) x (player, friendly, enemy) --
/// **not** (dead, alive), confirmed directly against `GSBoloView.m:322,325,337`'s
/// own draw calls (`player.boat ? PTKB... : PTNK...`, always for a live player;
/// a dead player's sprite is never drawn at all, gated by `!dead` at the call
/// site, not by a "destroyed" sprite variant). The original `row % 2 == 0`
/// derivation here read that pairing as (dead, alive) and passed `destroyed:
/// true` for every boat row -- found live, this drew every boat as `drawTank`'s
/// X-shaped wreck glyph instead of an actual boat, for every player who ever
/// spawned on or near water (a large fraction of real maps). Heading is still
/// the column, 0-15.
public func spriteGlyphRole(for index: Int32) -> GlyphRole? {
    guard isValidSpriteIndex(index) else { return nil }
    if index <= ETNK15IMAGE {
        let row = cellRow(index)
        let heading = cellCol(index)
        let ownership = row / 2
        return .tank(heading: heading, ownership: ownership, destroyed: false)
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
