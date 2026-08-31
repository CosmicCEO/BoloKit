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

#endif /* CXBOLO_H */
