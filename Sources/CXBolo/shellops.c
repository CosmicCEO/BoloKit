#include <math.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/bolo.h"

/* Permanent verbatim extract (like tankops.c) of the core per-tick shell
   move/range-advance numeric transform from shelllogic(), Reference/c/
   client.c:5382-5392. Takes explicit scalar parameters instead of the
   global `client` struct; collision resolution needs pill/base/terrain
   lookups (not pure numeric math) and is covered by Swift-only unit tests
   instead. */

static Vec2f dir2vec_(float dir) {
  Vec2f r;
  r.x = cosf(dir);
  r.y = -sinf(dir);
  return r;
}

struct ShellAdvanceResult {
  Vec2f point;
  float range;
};

struct ShellAdvanceResult shelladvance_oracle(Vec2f point, float dir, float range) {
  struct ShellAdvanceResult result;

  if (range < SHELLVEL/TICKSPERSEC) {
    result.point = add2f(point, mul2f(dir2vec_(dir), range));
    result.range = 0.0;
  }
  else {
    result.point = add2f(point, mul2f(dir2vec_(dir), SHELLVEL/TICKSPERSEC));
    result.range = range - SHELLVEL/TICKSPERSEC;
  }

  return result;
}
