#include <math.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/bolo.h"

/* Permanent verbatim extracts (like tankops.c/shellops.c) of the pure
   numeric transforms from builderlogic() used by builderTick's ready/goto/
   return/parachute cases (Wave 5.3b). Collision resolution needs pill/
   base/terrain lookups (not pure numeric math) and is covered by
   Swift-only unit tests instead. */

/* client.c:4550-4553 (repeated for every kBuilderReady task branch). */
Vec2f builderlaunch_oracle(Vec2f target, Vec2f tank) {
  Vec2f diff = sub2f(target, tank);
  float mag = mag2f(diff);
  return mag <= (TANKRADIUS - BUILDERRADIUS)
    ? target
    : add2f(tank, mul2f(diff, (TANKRADIUS - BUILDERRADIUS)/mag));
}

/* client.c:4903 / 4989 — the per-tick step-toward-target scaling shared by
   kBuilderGoto and kBuilderReturn (before collision clipping). */
Vec2f buildermove_oracle(Vec2f diff, float speed) {
  return mul2f(diff, speed/(TICKSPERSEC*mag2f(diff)));
}

/* client.c:5019 — kBuilderParachute's descent step. */
Vec2f parachutemove_oracle(Vec2f diff) {
  return mul2f(diff, PARACHUTESPEED/(TICKSPERSEC*mag2f(diff)));
}
