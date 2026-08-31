#include "../../Reference/c/tiles.h"
#include "../../Reference/c/images.h"

int isForestLikeTile_flat(int *tiles, int x, int y)    { return isForestLikeTile((int (*)[256])tiles, x, y); }
int isCraterLikeTile_flat(int *tiles, int x, int y)    { return isCraterLikeTile((int (*)[256])tiles, x, y); }
int isRoadLikeTile_flat(int *tiles, int x, int y)      { return isRoadLikeTile((int (*)[256])tiles, x, y); }
int isWaterLikeToLandTile_flat(int *tiles, int x, int y)  { return isWaterLikeToLandTile((int (*)[256])tiles, x, y); }
int isWaterLikeToWaterTile_flat(int *tiles, int x, int y) { return isWaterLikeToWaterTile((int (*)[256])tiles, x, y); }
int isWallLikeTile_flat(int *tiles, int x, int y)      { return isWallLikeTile((int (*)[256])tiles, x, y); }
int isSeaLikeTile_flat(int *tiles, int x, int y)       { return isSeaLikeTile((int (*)[256])tiles, x, y); }
int isMinedTile_flat(int *tiles, int x, int y)         { return isMinedTile((int (*)[256])tiles, x, y); }
int mapimage_flat(int *tiles, int x, int y)            { return mapimage((int (*)[256])tiles, x, y); }
