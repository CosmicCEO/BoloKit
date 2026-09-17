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

/* fogtilefor()'s (client.c:6143-6270) mine-substitution decision, the one
   piece tileFor() (this port's already-tested non-fog variant of the same
   C function) deliberately omits. Verbatim condition:
   `if (hiddenmines && tile != mined) return unmined; else return mined;` */
int fogtilefor_hides_mine_oracle(int hiddenmines, int tileMatchesPrevious) {
  return hiddenmines && !tileMatchesPrevious;
}
