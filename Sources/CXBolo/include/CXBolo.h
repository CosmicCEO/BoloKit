#ifndef CXBOLO_H
#define CXBOLO_H

#include "../../../Reference/c/vector.h"
#include "../../../Reference/c/errchk.h"
#include "../../../Reference/c/rect.h"
#include "../../../Reference/c/list.h"
#include "../../../Reference/c/buf.h"
#include "../../../Reference/c/terrain.h"
#include "../../../Reference/c/tiles.h"
#include "../../../Reference/c/images.h"
#include "../../../Reference/c/bmap.h"

// Flat-pointer shim declarations for Swift differential testing
int isForestLikeTile_flat(int *tiles, int x, int y);
int isCraterLikeTile_flat(int *tiles, int x, int y);
int isRoadLikeTile_flat(int *tiles, int x, int y);
int isWaterLikeToLandTile_flat(int *tiles, int x, int y);
int isWaterLikeToWaterTile_flat(int *tiles, int x, int y);
int isWallLikeTile_flat(int *tiles, int x, int y);
int isSeaLikeTile_flat(int *tiles, int x, int y);
int isMinedTile_flat(int *tiles, int x, int y);
int mapimage_flat(int *tiles, int x, int y);

// Exposes the static defaulttile() in bmap.c for differential testing
int defaulttile_oracle(int x, int y);

// Flat-pointer shims for readrun()/writerun() differential testing
int readrun_flat(size_t *y, size_t *x, struct BMAP_Run *run, void *data, int *terrain);
int writerun_flat(struct BMAP_Run run, const void *buf, int *terrain);

// Permanent verbatim extracts from client.c for oracle testing (Wave 5.0)
float rounddir_oracle(float dir);
Vec2f collisiondetect_oracle(Vec2f p, float radius, int (*func)(Pointi square));

// Permanent verbatim extract of the core tankmovelogic() numeric physics
// transform (turning, wrap, accel, position, kickspeed decay) for oracle
// testing (Wave 5.2a). Reduced-parameter form — no globals.
struct TankPhysicsState {
  Vec2f tank;
  float dir;
  float speed;
  float turnspeed;
  float kickdir;
  float kickspeed;
};

struct TankPhysicsState tankphysics_oracle(
  struct TankPhysicsState s,
  int turnL, int turnR, int accelIn, int brakeIn,
  int boat, float maxTurn, float maxSpd
);

// Permanent verbatim extract of shelllogic()'s move/range-advance numeric
// transform for oracle testing (Wave 5.3a). Reduced-parameter form — no
// globals.
struct ShellAdvanceResult {
  Vec2f point;
  float range;
};

struct ShellAdvanceResult shelladvance_oracle(Vec2f point, float dir, float range);

// Permanent verbatim extracts of builderlogic()'s pure numeric transforms
// for oracle testing (Wave 5.3b). Reduced-parameter form — no globals.
Vec2f builderlaunch_oracle(Vec2f target, Vec2f tank);
Vec2f buildermove_oracle(Vec2f diff, float speed);
Vec2f parachutemove_oracle(Vec2f diff);

// Permanent verbatim extracts of forestvis()'s interpolation arithmetic
// and pilllogic()'s shell-firing lead-targeting math for oracle testing
// (Wave 5.3c). Reduced-parameter form — no globals.
float forestvis_oracle(
  float fx, float fy,
  int isForestCenter,
  int isForestXm1Y, int isForestXp1Y, int isForestXYm1, int isForestXYp1,
  int isForestXm1Ym1, int isForestXm1Yp1, int isForestXp1Ym1, int isForestXp1Yp1
);

struct PillShellResult {
  Vec2f point;
  float dir;
};

struct PillShellResult pillshell_oracle(Vec2f tank, Vec2f old, Vec2f pill);

#endif /* CXBOLO_H */
