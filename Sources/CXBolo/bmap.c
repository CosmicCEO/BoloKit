#include "../../Reference/c/bmap.c"

/* defaulttile() is static in bmap.c; expose it for Swift differential
   testing from within the same translation unit. */
int defaulttile_oracle(int x, int y) {
  return defaulttile(x, y);
}

/* Flat-pointer shims for readrun()/writerun() — same int[][WIDTH]-decay
   problem as the Wave 2/3 tiles_shim.c shims. */
int readrun_flat(size_t *y, size_t *x, struct BMAP_Run *run, void *data, int *terrain) {
  return readrun(y, x, run, data, (int (*)[WIDTH])terrain);
}

int writerun_flat(struct BMAP_Run run, const void *buf, int *terrain) {
  return writerun(run, buf, (int (*)[WIDTH])terrain);
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

/* D129: `serverloadmap()`'s pill/base-site terrain normalization
   (Reference/c/bmap_server.c:140-193, identical again at 198-251 for
   bases) VERBATIM, extracted as a standalone terrain-in/terrain-out
   function so it can run without server.h's globals. Preserves the real
   fallthrough bug at 167-169/225-227: kMinedRubbleTerrain writes
   kRubbleTerrain0 then falls into the kMinedGrassTerrain case with no
   `break`, so the net observable result is kGrassTerrain0, not rubble. */
int serverloadmap_normalize_terrain_oracle(int terrain) {
  switch (terrain) {
  case kSeaTerrain:
  case kBoatTerrain:
  case kWallTerrain:
  case kRiverTerrain:
  case kForestTerrain:
  case kDamagedWallTerrain0:
  case kDamagedWallTerrain1:
  case kDamagedWallTerrain2:
  case kDamagedWallTerrain3:
  case kMinedSeaTerrain:
  case kMinedForestTerrain:
    return kGrassTerrain0;

  case kMinedSwampTerrain:
    return kSwampTerrain0;

  case kMinedCraterTerrain:
    return kCraterTerrain;

  case kMinedRoadTerrain:
    return kRoadTerrain;

  case kMinedRubbleTerrain:
    /* falls through, verbatim */

  case kMinedGrassTerrain:
    return kGrassTerrain0;

  case kSwampTerrain0:
  case kSwampTerrain1:
  case kSwampTerrain2:
  case kSwampTerrain3:
  case kCraterTerrain:
  case kRoadTerrain:
  case kRubbleTerrain0:
  case kRubbleTerrain1:
  case kRubbleTerrain2:
  case kRubbleTerrain3:
  case kGrassTerrain0:
  case kGrassTerrain1:
  case kGrassTerrain2:
  case kGrassTerrain3:
    return terrain;

  default:
    assert(0);
    return -1;
  }
}

/* D129: `serverloadmap()`'s pill speed rescale (bmap_server.c:81-85)
   VERBATIM: `(rawSpeed*MAXTICKSPERSHOT)/50`, clamped to MAXTICKSPERSHOT. */
int serverloadmap_pillspeed_oracle(int rawSpeed) {
  int speed = (rawSpeed * MAXTICKSPERSHOT) / 50;
  if (speed > MAXTICKSPERSHOT) {
    speed = MAXTICKSPERSHOT;
  }
  return speed;
}
