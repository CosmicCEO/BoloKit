#include <math.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/bolo.h"

/* Permanent verbatim extracts (like tankops.c/shellops.c/builderops.c) of
   the pure numeric transforms from forestvis() (bolo.c:174) and
   pilllogic()'s shell-firing lead-targeting math (client.c:5076-5093),
   for oracle testing (Wave 5.3c). forestvis's isforest() dependency is
   boolean terrain/pill/base lookups, not pure numeric math — passed here
   as explicit int flags for each of the 8 neighbors instead of reading a
   global grid, so the interpolation arithmetic itself can be fuzzed
   independently of world state. */

/* `vec2dir` itself is defined in Reference/c/bolo.c, which is not part of
   the CXBolo target's compiled sources (only vector.c/rect.c/etc. are) —
   linking directly against it would fail with an undefined symbol, the
   same reason tankops.c reimplements dir2vec_ locally rather than calling
   bolo.c's dir2vec. `_atan2f`/`k2Pif` ARE compiled (vector.c), so this
   wrapper only reimplements the trivial negate-and-wrap shell around them,
   deferring the actual trig to the real, already-shared function. */
static float vec2dir_(Vec2f v) {
  v.y = -v.y;
  return fmodf(_atan2f(v) + k2Pif, k2Pif);
}

float forestvis_oracle(
  float fx, float fy,
  int isForestCenter,
  int isForestXm1Y, int isForestXp1Y, int isForestXYm1, int isForestXYp1,
  int isForestXm1Ym1, int isForestXm1Yp1, int isForestXp1Ym1, int isForestXp1Yp1
) {
  float cx, cy;

  if (!isForestCenter) {
    return 1.0;
  }

  cx = 1.0 - fx;
  cy = 1.0 - fy;

  return
    MAX(
      MAX(
        MAX(isForestXm1Y ? 0.0 : cx, isForestXp1Y ? 0.0 : fx),
        MAX(isForestXYm1 ? 0.0 : cy, isForestXYp1 ? 0.0 : fy)
      ),
      MAX(
        MAX(
          isForestXm1Ym1 ? 0.0 : 1.0 - sqrtf(fx*fx + fy*fy),
          isForestXm1Yp1 ? 0.0 : 1.0 - sqrtf(fx*fx + cy*cy)
        ),
        MAX(
          isForestXp1Ym1 ? 0.0 : 1.0 - sqrtf(cx*cx + fy*fy),
          isForestXp1Yp1 ? 0.0 : 1.0 - sqrtf(cx*cx + cy*cy)
        )
      )
    );
}

struct PillShellResult {
  Vec2f point;
  float dir;
};

/* client.c:5076-5093, with the malloc/list/collision-test/range-constant
   parts excluded (no pure numeric content). `pill` is the pill's center
   (x+0.5, y+0.5); `diff` = tank - pill is recomputed here exactly as C
   does, not passed in, so mag2f(diff) matches bit-for-bit. */
struct PillShellResult pillshell_oracle(Vec2f tank, Vec2f old, Vec2f pill) {
  struct PillShellResult result;
  Vec2f diff = sub2f(tank, pill);
  float mag = mag2f(diff);
  Vec2f vel = mul2f(sub2f(tank, old), TICKSPERSEC);
  Vec2f compi = sub2f(vel, prj2f(diff, vel));
  Vec2f compj = mul2f(unit2f(diff), sqrtf(fabsf((SHELLVEL*SHELLVEL) - dot2f(compi, compi))));

  result.point = add2f(pill, mul2f(diff, 0.70711219/mag));
  result.dir = vec2dir_(add2f(compi, compj));
  return result;
}
