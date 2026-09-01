#include <math.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/bolo.h"

/* Permanent verbatim extract (like physicsops.c) of the core per-tick
   numeric tank physics transform from tankmovelogic()'s alive branch,
   Reference/c/client.c:4022-4120 — turning, direction wrap, acceleration,
   position update, kickspeed decay. Takes explicit scalar parameters
   instead of the global `client` struct; shore-push and collision are
   excluded (they need pill/base/terrain lookups, not pure numeric math)
   and are covered by Swift-only unit tests instead. */

struct TankPhysicsState {
  Vec2f tank;
  float dir;
  float speed;
  float turnspeed;
  float kickdir;
  float kickspeed;
};

static Vec2f dir2vec_(float dir) {
  Vec2f r;
  r.x = cosf(dir);
  r.y = -sinf(dir);
  return r;
}

float rounddir_oracle(float dir);

struct TankPhysicsState tankphysics_oracle(
  struct TankPhysicsState s,
  int turnL, int turnR, int accelIn, int brakeIn,
  int boat, float maxTurn, float maxSpd
) {
  float max;

  if (turnL && !turnR) {
    if (s.turnspeed < 0) s.turnspeed = 0;
    max = boat ? MAXANGULARVELOCITY : maxTurn;
    if (s.turnspeed > max) {
      s.turnspeed -= ANGULARACCEL/TICKSPERSEC;
      if (s.turnspeed < max) s.turnspeed = max;
    }
    else {
      s.turnspeed += ANGULARACCEL/TICKSPERSEC;
      if (s.turnspeed > max) s.turnspeed = max;
    }
  }
  else if (turnR && !turnL) {
    if (s.turnspeed > 0) s.turnspeed = 0;
    max = boat ? MAXANGULARVELOCITY : maxTurn;
    if (s.turnspeed < -max) {
      s.turnspeed += ANGULARACCEL/TICKSPERSEC;
      if (s.turnspeed > -max) s.turnspeed = -max;
    }
    else {
      s.turnspeed -= ANGULARACCEL/TICKSPERSEC;
      if (s.turnspeed < -max) s.turnspeed = -max;
    }
  }
  else {
    s.turnspeed = 0.0;
  }

  s.dir += s.turnspeed/TICKSPERSEC;

  if (s.dir > k2Pif) {
    s.dir -= k2Pif*floorf(s.dir/k2Pif);
  }
  else if (s.dir < 0.0) {
    s.dir += k2Pif*floorf(s.dir/-k2Pif + 1.0);
  }

  max = boat ? BOATMAXSPEED : maxSpd;

  if (accelIn && !brakeIn) {
    if (s.speed < max) {
      s.speed += ACCEL/TICKSPERSEC;
      if (s.speed > max) s.speed = max;
    }
    else {
      s.speed -= ACCEL/TICKSPERSEC;
      if (s.speed < max) s.speed = max;
    }
  }
  else if (!accelIn && brakeIn) {
    s.speed -= ACCEL/TICKSPERSEC;
    if (s.speed < 0.0) s.speed = 0.0;
  }
  else if (s.speed > max) {
    s.speed -= ACCEL/TICKSPERSEC;
    if (s.speed < max) s.speed = max;
  }

  s.tank = add2f(s.tank, div2f(add2f(mul2f(dir2vec_(rounddir_oracle(s.dir)), s.speed), mul2f(dir2vec_(s.kickdir), s.kickspeed)), TICKSPERSEC));

  s.kickspeed -= 12.0/TICKSPERSEC;
  if (s.kickspeed < 0.0) s.kickspeed = 0.0;

  return s;
}
