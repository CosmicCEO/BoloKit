import BoloKit

/// P0a: split a logged fog value into visible-now vs last-seen.
/// Last-seen is comparable only while the tile is in fog (bit 0 clear).
func fogComparableParts(element: UInt32, value: UInt64) -> [(CompareDomain, UInt32, UInt64?)] {
    let visible = (value & 1) == 1
    let seen: UInt64? = visible ? nil : value >> 1
    return [(.fogVisible, element, value & 1), (.fogSeen, element, seen)]
}
