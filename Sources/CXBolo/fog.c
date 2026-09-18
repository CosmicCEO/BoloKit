#include <math.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/bolo.h"

/* Permanent verbatim extract (same style as pillops.c's forestvis_oracle)
   of fogvis()'s pure interpolation math (bolo.c:108-150). ISFOG's own
   dependency (a live per-tile reference count) is a boolean lookup, not
   pure numeric math -- passed here as explicit int flags for each of the
   8 neighbors, same reasoning forestvis_oracle already established for
   isforest(). */
float fogvis_oracle(
  float fx, float fy,
  int isFogCenter,
  int isFogXm1Y, int isFogXp1Y, int isFogXYm1, int isFogXYp1,
  int isFogXm1Ym1, int isFogXm1Yp1, int isFogXp1Ym1, int isFogXp1Yp1
) {
  float cx, cy;

  if (!isFogCenter) {
    return 1.0;
  }

  cx = 1.0 - fx;
  cy = 1.0 - fy;

  return
    MAX(
      MAX(
        MAX(isFogXm1Y ? 0.0 : cx, isFogXp1Y ? 0.0 : fx),
        MAX(isFogXYm1 ? 0.0 : cy, isFogXYp1 ? 0.0 : fy)
      ),
      MAX(
        MAX(
          isFogXm1Ym1 ? 0.0 : 1.0 - sqrtf(fx*fx + fy*fy),
          isFogXm1Yp1 ? 0.0 : 1.0 - sqrtf(fx*fx + cy*cy)
        ),
        MAX(
          isFogXp1Ym1 ? 0.0 : 1.0 - sqrtf(cx*cx + fy*fy),
          isFogXp1Yp1 ? 0.0 : 1.0 - sqrtf(cx*cx + cy*cy)
        )
      )
    );
}

/* Permanent verbatim extract of calcvis()'s final distance/blend formula
   (bolo.c:304-322) -- the part downstream of fogvis/forestvis/the
   distance-to-nearest-vision-source scan, none of which is pure numeric
   math on its own (they're grid/list scans, already covered by
   fogvis_oracle/forestvis_oracle and ordinary Swift tests respectively).
   Takes the already-computed forestvis/fogvis product and the
   already-minimized distance as plain floats. */
float calcvis_blend_oracle(float forestvis, float fogvis, float dist) {
  float vis;

  if (dist <= 2.0) {
    if (forestvis*fogvis < 0.5) {
      vis = 0.5;
    }
    else {
      vis = forestvis*fogvis;
    }
  }
  else if (dist < 3.0) {
    if (forestvis*fogvis < 0.5) {
      vis = ((3.0 - dist)*(0.5 - forestvis*fogvis)) + forestvis*fogvis;
    }
    else {
      vis = forestvis*fogvis;
    }
  }
  else {
    vis = forestvis*fogvis;
  }

  return vis;
}

/* v1.5.0 #1 (fix pass, `/code-review max` on PR #56): a `/code-review max` review found the
   original `fogtilefor_hides_mine_oracle` above was tautological -- it recomputed the same
   boolean expression the Swift test already assumed, rather than deriving from the real C
   switch, so it could never have caught `applyMineSubstitution` diverging from the actual
   oracle. Two real parity bugs slipped through as a result: `kMinedSeaTerrain` being hidden
   like any other mine (the real switch never even checks `hiddenmines` for it -- unconditional
   `return kMinedSeaTile`), and the `kMinedForestTerrain`/`kMinedGrassTerrain` cases missing
   their cross-check (each treats *either* tile as "already seen", not just an exact match --
   tree growth/chopping toggles a mine's terrain between the two without un-discovering it).

   This function is a verbatim transcription of `fogtilefor()`'s real mined-terrain switch
   (`client.c:6172-6255`) for exactly the 7 mined cases -- the pill/base/plain-terrain
   branches are already covered by `tileFor()`'s own existing oracle-tested port and are not
   duplicated here. `terrainCase` is one of the 7 real `kMinedXTerrain` constants;
   `previousTile` is a real `kXTile`/`kMinedXTile` constant (the prior `seentiles` entry).
   Returns the real `kXTile`/`kMinedXTile` result. */
int fogtilefor_mined_result_oracle(int terrainCase, int hiddenmines, int previousTile) {
  switch (terrainCase) {
  case kMinedSeaTerrain:
    return kMinedSeaTile;

  case kMinedSwampTerrain:
    if (hiddenmines && previousTile != kMinedSwampTile) return kSwampTile;
    else return kMinedSwampTile;

  case kMinedCraterTerrain:
    if (hiddenmines && previousTile != kMinedCraterTile) return kCraterTile;
    else return kMinedCraterTile;

  case kMinedRoadTerrain:
    if (hiddenmines && previousTile != kMinedRoadTile) return kRoadTile;
    else return kMinedRoadTile;

  case kMinedForestTerrain:
    if (hiddenmines && previousTile != kMinedForestTile && previousTile != kMinedGrassTile) return kForestTile;
    else return kMinedForestTile;

  case kMinedRubbleTerrain:
    if (hiddenmines && previousTile != kMinedRubbleTile) return kRubbleTile;
    else return kMinedRubbleTile;

  case kMinedGrassTerrain:
    if (hiddenmines && previousTile != kMinedGrassTile && previousTile != kMinedForestTile) return kGrassTile;
    else return kMinedGrassTile;

  default:
    return -1;
  }
}

/* Verbatim transcription of `testhiddenmine()`'s own terrain-type switch (`client.c:4464-
   4490`), minus the distance check and `refresh()` side effect (already covered elsewhere --
   `revealNearbyHiddenMines`'s own `mag2f`/bounds-clamp tests). Real C has no
   `kMinedSeaTerrain` case at all; returns 1 for exactly the 6 terrain types the real switch's
   non-default cases list, 0 otherwise (including for `kMinedSeaTerrain`). */
int testhiddenmine_reveals_terrain_oracle(int terrainCase) {
  switch (terrainCase) {
  case kMinedSwampTerrain:
  case kMinedCraterTerrain:
  case kMinedRoadTerrain:
  case kMinedForestTerrain:
  case kMinedRubbleTerrain:
  case kMinedGrassTerrain:
    return 1;
  default:
    return 0;
  }
}
