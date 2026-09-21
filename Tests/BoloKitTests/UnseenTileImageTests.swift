import Testing
@testable import BoloKit

/// Host fog look: a never-seen tile is drawn as plain sea (matching what a guest shows outside
/// the playable area), not black. Port-original render policy, so these are synthetic tests,
/// not differential ones. `mapimage` itself stays oracle-exact and still returns -1.
struct UnseenTileImageTests {
    @Test func `An unseen tile is drawn as plain sea`() {
        #expect(unseenTileAsSeaImage(-1) == SEAA00IMAGE)
    }

    @Test func `A seen tile keeps its own image`() {
        #expect(unseenTileAsSeaImage(SEAA01IMAGE) == SEAA01IMAGE)
        #expect(unseenTileAsSeaImage(0) == 0)
    }

    @Test func `A grid unknown tile resolves through mapimage to plain sea`() {
        var grid = TileGrid()
        grid[10, 10] = Tile.unknown.rawValue
        #expect(mapimage(grid, 10, 10) == -1)
        #expect(unseenTileAsSeaImage(mapimage(grid, 10, 10)) == SEAA00IMAGE)
    }
}
