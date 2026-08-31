#include "../../Reference/c/bmap.c"

/* defaulttile() is static in bmap.c; expose it for Swift differential
   testing from within the same translation unit. */
int defaulttile_oracle(int x, int y) {
  return defaulttile(x, y);
}

/* writerun() in bmap.c references tiletoterrain(), which is defined in
   server.c. server.c cannot be compiled into CXBolo yet (network and
   global-state dependencies), so the symbol is provided here as a
   VERBATIM extract of Reference/c/server.c:4301 to satisfy the linker.
   DELETE this copy when server.c is bridged. */
int tiletoterrain(int tile) {
  switch (tile) {
  case kWallTile:  /* wall */
    return kWallTerrain;

  case kRiverTile:  /* river */
    return kRiverTerrain;

  case kSwampTile:  /* swamp */
    return kSwampTerrain3;

  case kCraterTile:  /* crater */
    return kCraterTerrain;

  case kRoadTile:  /* road */
    return kRoadTerrain;

  case kForestTile:  /* forest */
    return kForestTerrain;

  case kRubbleTile:  /* rubble */
    return kRubbleTerrain3;

  case kGrassTile:  /* grass */
    return kGrassTerrain3;

  case kDamagedWallTile:  /* damaged wall */
    return kDamagedWallTerrain3;

  case kBoatTile:  /* river w/boat */
    return kBoatTerrain;

  case kMinedSwampTile:  /* mined swamp */
    return kMinedSwampTerrain;

  case kMinedCraterTile:  /* mined crater */
    return kMinedCraterTerrain;

  case kMinedRoadTile:  /* mined road */
    return kMinedRoadTerrain;

  case kMinedForestTile:  /* mined forest */
    return kMinedForestTerrain;

  case kMinedRubbleTile:  /* mined rubble */
    return kMinedRubbleTerrain;

  case kMinedGrassTile:  /* mined grass */
    return kMinedGrassTerrain;

  case kSeaTile:  /* sea */
    return kSeaTerrain;

  case kMinedSeaTile:  /* mined sea */
    return kMinedSeaTerrain;

  case kUnknownTile:  /* unknown */
    return kMinedSeaTerrain;

  default:
    assert(0);
    return -1;
  }
}
