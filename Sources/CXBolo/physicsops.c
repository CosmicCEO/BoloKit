#include <math.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/rect.h"

/* client.c is a monolith (network, AppKit, global `client` state) and is
   never going to be #include-d wholesale the way bmap.c/tiles.c were.
   Unlike the Wave 4.1 tiletoterrain extract (a temporary shim awaiting a
   future server.c bridge), these are PERMANENT verbatim copies of pure
   functions pulled out of client.c for oracle testing — there is no future
   bridge that would let them be deleted. */

/* Verbatim from Reference/c/client.c:6765 (rounddir). */
float rounddir_oracle(float dir) {
  return (kPif/8.0)*floor(dir/(kPif/8.0) + 0.5);
}

/* Verbatim from Reference/c/client.c:6927 (collisiondetect), including the
   p.x/p.y bug in the lyc && hyc branch — must not be fixed. */
Vec2f collisiondetect_oracle(Vec2f p, float radius, int (*func)(Pointi square)) {
  int ix, iy;
  int lxc, hxc, lyc, hyc;
  float lx, hx, ly, hy, fx, fy;
  float sqr, sca, r2;

  ix = (int)p.x;
  iy = (int)p.y;
  fx = (float)ix;
  fy = (float)iy;
  lx = p.x - fx;
  hx = 1.0 - lx;
  ly = p.y - fy;
  hy = 1.0 - ly;
  r2 = radius*radius;

  lxc = lx < radius && func(makepoint(ix - 1, iy));
  hxc = hx < radius && func(makepoint(ix + 1, iy));
  lyc = ly < radius && func(makepoint(ix, iy - 1));
  hyc = hy < radius && func(makepoint(ix, iy + 1));

  if (lxc) {
    if (hxc) {
      p.x = fx + 0.5;
    }
    else {
      p.x = fx + radius;
    }
  }
  else if (hxc) {
    p.x = fx + (1.0 - radius);
  }

  if (lyc) {
    if (hyc) {
      p.x = fy + 0.5;
    }
    else {
      p.y = fy + radius;
    }
  }
  else if (hyc) {
    p.y = fy + (1.0 - radius);
  }

  if (!lxc && !lyc && (sqr = lx*lx + ly*ly) < r2 && func(makepoint(ix - 1, iy - 1))) {
    sca = radius/sqrtf(sqr);
    p.x = fx + sca*lx;
    p.y = fy + sca*ly;
  }

  if (!hxc && !lyc && (sqr = hx*hx + ly*ly) < r2 && func(makepoint(ix + 1, iy - 1))) {
    sca = radius/sqrtf(sqr);
    p.x = fx + (1.0 - sca*hx);
    p.y = fy + sca*ly;
  }

  if (!lxc && !hyc && (sqr = lx*lx + hy*hy) < r2 && func(makepoint(ix - 1, iy + 1))) {
    sca = radius/sqrtf(sqr);
    p.x = fx + sca*lx;
    p.y = fy + (1.0 - sca*hy);
  }

  if (!hxc && !hyc && (sqr = hx*hx + hy*hy) < r2 && func(makepoint(ix + 1, iy + 1))) {
    sca = radius/sqrtf(sqr);
    p.x = fx + (1.0 - sca*hx);
    p.y = fy + (1.0 - sca*hy);
  }

  return p;
}
