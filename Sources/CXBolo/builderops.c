#include <math.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/bolo.h"
#include "../../Reference/c/tiles.h"

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

/* Wave D137 (builder mouse control) — verbatim transcription of
   getbuildertaskforcommand()'s decision logic (client.c:6539-6698), with
   `client.seentiles[at.y][at.x]` replaced by an explicit `tile` parameter
   (the caller supplies the tile value directly instead of a fog-of-war
   lookup — this port has no seentiles model, D65) and the
   `client.printmessage(...)` UI side effect calls dropped (no observable
   return-value effect; command resolution is otherwise identical). */
int getbuildertask_oracle(int command, int tile) {
  switch (command) {
  case BUILDERNILL:
    return kBuilderDoNothing;

  case BUILDERTREE:
    switch (tile) {
    case kForestTile:
    case kMinedForestTile:
      return kBuilderGetTree;

    default:
      return kBuilderDoNothing;
    }

  case BUILDERROAD:
    switch (tile) {
    case kForestTile:
    case kMinedForestTile:
      return kBuilderGetTree;

    case kRiverTile:
    case kSwampTile:
    case kCraterTile:
    case kRubbleTile:
    case kGrassTile:
      return kBuilderBuildRoad;

    case kMinedSwampTile:
    case kMinedCraterTile:
    case kMinedRubbleTile:
    case kMinedGrassTile:
      return kBuilderDoNothing;

    default:
      return kBuilderDoNothing;
    }

  case BUILDERWALL:
    switch (tile) {
    case kForestTile:
    case kMinedForestTile:
      return kBuilderGetTree;

    case kSwampTile:
    case kCraterTile:
    case kRoadTile:
    case kRubbleTile:
    case kGrassTile:
    case kDamagedWallTile:
      return kBuilderBuildWall;

    case kRiverTile:
      return kBuilderBuildBoat;

    case kMinedSwampTile:
    case kMinedCraterTile:
    case kMinedRoadTile:
    case kMinedRubbleTile:
    case kMinedGrassTile:
      return kBuilderDoNothing;

    default:
      return kBuilderDoNothing;
    }

  case BUILDERPILL:
    switch (tile) {
    case kForestTile:
    case kMinedForestTile:
      return kBuilderGetTree;

    case kSwampTile:
    case kCraterTile:
    case kRoadTile:
    case kRubbleTile:
    case kGrassTile:
      return kBuilderBuildPill;

    case kMinedSwampTile:
    case kMinedCraterTile:
    case kMinedRoadTile:
    case kMinedRubbleTile:
    case kMinedGrassTile:
      return kBuilderDoNothing;

    case kFriendlyPill00Tile:
    case kFriendlyPill01Tile:
    case kFriendlyPill02Tile:
    case kFriendlyPill03Tile:
    case kFriendlyPill04Tile:
    case kFriendlyPill05Tile:
    case kFriendlyPill06Tile:
    case kFriendlyPill07Tile:
    case kFriendlyPill08Tile:
    case kFriendlyPill09Tile:
    case kFriendlyPill10Tile:
    case kFriendlyPill11Tile:
    case kFriendlyPill12Tile:
    case kFriendlyPill13Tile:
    case kFriendlyPill14Tile:
    case kHostilePill00Tile:
    case kHostilePill01Tile:
    case kHostilePill02Tile:
    case kHostilePill03Tile:
    case kHostilePill04Tile:
    case kHostilePill05Tile:
    case kHostilePill06Tile:
    case kHostilePill07Tile:
    case kHostilePill08Tile:
    case kHostilePill09Tile:
    case kHostilePill10Tile:
    case kHostilePill11Tile:
    case kHostilePill12Tile:
    case kHostilePill13Tile:
    case kHostilePill14Tile:
      return kBuilderRepairPill;

    default:
      return kBuilderDoNothing;
    }

  case BUILDERMINE:
    switch (tile) {
    case kSwampTile:
    case kCraterTile:
    case kRoadTile:
    case kForestTile:
    case kRubbleTile:
    case kGrassTile:
      return kBuilderPlaceMine;

    case kMinedSwampTile:
    case kMinedCraterTile:
    case kMinedRoadTile:
    case kMinedForestTile:
    case kMinedRubbleTile:
    case kMinedGrassTile:
      return kBuilderDoNothing;

    default:
      return kBuilderDoNothing;
    }

  default:
    return kBuilderDoNothing;
  }
}
