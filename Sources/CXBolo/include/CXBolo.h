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
#include "../../../Reference/c/client.h"
#include "../../../Reference/c/server.h"
#include "../../../Reference/c/tracker.h"

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

// Wave 6.0 wire-codec oracle extracts (netops.c) of sendclupdate()/
// dgramclient()'s pure encode/decode transforms, plus struct-layout ground
// truth for the CL*/SR* TCP structs and CLUpdate's UDP header.
// `seq` is deliberately not a struct member of either input or output
// below -- a fixed-size C array as a struct member imports into Swift as
// an unsubscriptable N-tuple. Passed as a separate `int32_t *` (MAXPLAYERS
// entries) instead.
struct CLUpdateEncodeInput {
  uint8_t player;
  uint8_t tankstatus;
  Vec2f tank;
  float speed;
  float turnspeed;
  float kickdir;
  float kickspeed;
  float dir;
  uint8_t builderstatus;
  Vec2f builder;
  uint8_t buildertargetx;
  uint8_t buildertargety;
  uint8_t builderwait;
  int32_t inputflags;
  uint8_t tankshotsound;
  uint8_t pillshotsound;
  uint8_t sinksound;
  uint8_t builderdeathsound;
};

struct ShellEncodeInput {
  uint8_t owner;
  Vec2f point;
  uint8_t boat;
  uint8_t pill;
  float dir;
  float range;
};

struct ExplosionEncodeInput {
  Vec2f point;
  uint8_t counter;
};

size_t clupdate_encode_oracle(
  struct CLUpdateEncodeInput in,
  const int32_t *seq,
  const struct ShellEncodeInput *shells, int nshells,
  const struct ExplosionEncodeInput *explosions, int nexplosions,
  struct CLUpdate *out
);

struct CLUpdateDecodeOutput {
  int valid;
  uint8_t player;
  int dead;
  int boat;
  float dir;
  Vec2f tank;
  float speed;
  float turnspeed;
  float kickdir;
  float kickspeed;
  uint8_t builderstatus;
  Vec2f builder;
  uint8_t buildertargetx;
  uint8_t buildertargety;
  uint8_t builderwait;
  int32_t inputflags;
  uint8_t tankshotsound;
  uint8_t pillshotsound;
  uint8_t sinksound;
  uint8_t builderdeathsound;
};

struct ShellDecodeOutput {
  uint8_t owner;
  Vec2f point;
  uint8_t boat;
  uint8_t pill;
  float dir;
  float range;
};

struct ExplosionDecodeOutput {
  Vec2f point;
  uint8_t counter;
};

int clupdate_decode_oracle(
  const uint8_t *bytes, size_t len,
  struct CLUpdateDecodeOutput *outHdr,
  int32_t *outSeq,
  struct ShellDecodeOutput *outShells, int *outNShells,
  struct ExplosionDecodeOutput *outExplosions, int *outNExplosions
);

struct CLUpdateLayoutOracle {
  size_t hdrSize;
  size_t shellSize;
  size_t explosionSize;
  size_t offPlayer;
  size_t offSeq;
  size_t offTankStatus;
  size_t offTankX;
  size_t offTankY;
  size_t offTankSpeed;
  size_t offTankTurnSpeed;
  size_t offTankKickDir;
  size_t offTankKickSpeed;
  size_t offTankDir;
  size_t offBuilderStatus;
  size_t offBuilderX;
  size_t offBuilderY;
  size_t offBuilderTargetX;
  size_t offBuilderTargetY;
  size_t offBuilderWait;
  size_t offInputFlags;
  size_t offTankShotSound;
  size_t offPillShotSound;
  size_t offSinkSound;
  size_t offBuilderDeathSound;
  size_t offNShells;
  size_t offNExplosions;
};

struct CLUpdateLayoutOracle clupdate_layout_oracle(void);

size_t sizeof_cl_oracle(int type);
size_t sizeof_sr_oracle(int type);

// Wave 6.3: JOIN_Preamble/BOLO_Preamble/TRACKER_Preamble layout ground
// truth -- see netops.c's preamble_layout_oracle() for why these need
// explicit offsetof checks rather than a plain sizeof_*_oracle dispatch.
struct PreambleLayoutOracle {
  size_t sizeofJoinPreamble;
  size_t offJoinName;
  size_t offJoinPass;

  size_t sizeofBoloPreamble;
  size_t offBoloPlayer;
  size_t offBoloHiddenMines;
  size_t offBoloPause;
  size_t offBoloGameType;
  size_t offBoloDominationType;
  size_t offBoloDominationBaseControl;
  size_t offBoloPlayers;
  size_t offBoloMapLen;
  size_t sizeofBoloPlayerEntry;
  size_t offEntryUsed;
  size_t offEntryConnected;
  size_t offEntrySeq;
  size_t offEntryName;
  size_t offEntryHost;
  size_t offEntryAlliance;

  size_t sizeofTrackerPreamble;
};

struct PreambleLayoutOracle preamble_layout_oracle(void);

// Wave 6.4b: dgramserver()'s pure per-packet decision core -- see
// netops.c's dgramserver_relay_oracle() for the full server.c:614-696
// citation trail this decomposes.
struct DgramServerPlayerState {
  int used;
  int connected;
  uint8_t dgramFamily;
  uint32_t dgramAddr;
  uint16_t dgramPort;
  uint32_t seq;
};

struct DgramServerRelayResult {
  int isTrackerEcho;
  int isMalformed;
  int player;
  int isValidPlayer;
  int isNewerSeq;
  uint32_t decodedSeq;
  int portChanged;
  uint16_t newPort;
  uint32_t tankXRaw;
  uint32_t tankYRaw;
  /* relayTo/relayCount are NOT members here -- see netops.c's own
     comment; a fixed-size C array as a struct member imports into Swift
     as an unsubscriptable N-tuple. Written through the separate
     `outRelayTo`/`outRelayCount` pointers below instead. */
};

// `outRelayTo` must point at a caller-allocated buffer of at least
// MAXPLAYERS ints.
int dgramserver_relay_oracle(
  const uint8_t *bytes, size_t len,
  uint8_t addrFamily, uint32_t addrAddr, uint16_t addrPort,
  const struct DgramServerPlayerState *players,
  struct DgramServerRelayResult *out,
  int *outRelayTo, int *outRelayCount
);

#endif /* CXBOLO_H */
