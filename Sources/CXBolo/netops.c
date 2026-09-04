#include <stddef.h>
#include <string.h>
#include "../../Reference/c/vector.h"
#include "../../Reference/c/bolo.h"
#include "../../Reference/c/client.h"
#include "../../Reference/c/server.h"
#include "../../Reference/c/bmap.h"
#include "../../Reference/c/tracker.h"

/* Permanent verbatim extracts (like tankops.c/shellops.c/builderops.c/
   pillops.c) of the pure numeric wire-format transforms from
   sendclupdate() (Reference/c/client.c:3509-3592) and dgramclient()
   (Reference/c/client.c:1280-1472), for Wave 6.0 oracle testing. Both take
   explicit parameters instead of the global `client` struct and the
   `send()`/`recv()` socket calls; list traversal (linked lists in the real
   client.players[i].shells/.explosions) is replaced with plain arrays
   since the wire representation (CLUpdateShell/CLUpdateExplosion) is
   already flat, packed data with no list-specific behavior of its own.

   Decode stops short of dgramclient()'s list mutation, sound playback, vis
   updates, and dead-reckoning re-simulation loop -- those consume decoded
   state and belong to Wave 6.1/6.2, not the wire codec. */

/* `seq` is deliberately NOT a member here (unlike the real CLUpdate.hdr) --
   a fixed-size C array as a struct member imports into Swift as an
   unsubscriptable N-tuple, which is unusable from a differential test.
   Passed as a separate `const int32_t *seq` (MAXPLAYERS entries) instead,
   both here and in CLUpdateDecodeOutput below. */
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

/* Mirrors sendclupdate()'s field-assignment body exactly, minus the
   send() call and the four sound-flag clears (those are client-side
   bookkeeping after the send, not part of the wire encoding). Returns the
   same length sendclupdate() would pass to send(). */
size_t clupdate_encode_oracle(
  struct CLUpdateEncodeInput in,
  const int32_t *seq,
  const struct ShellEncodeInput *shells, int nshells,
  const struct ExplosionEncodeInput *explosions, int nexplosions,
  struct CLUpdate *out
) {
  struct CLUpdateShell *outshells;
  struct CLUpdateExplosion *outexplosions;
  int i;

  out->hdr.player = in.player;

  for (i = 0; i < MAXPLAYERS; i++) {
    out->hdr.seq[i] = htonl(seq[i]);
  }

  out->hdr.tankstatus = in.tankstatus;
  out->hdr.tankx = htonl(*((uint32_t *)&in.tank.x));
  out->hdr.tanky = htonl(*((uint32_t *)&in.tank.y));
  out->hdr.tankspeed = htonl(*((uint32_t *)&in.speed));
  out->hdr.tankturnspeed = htonl(*((uint32_t *)&in.turnspeed));
  out->hdr.tankkickdir = htonl(*((uint32_t *)&in.kickdir));
  out->hdr.tankkickspeed = htonl(*((uint32_t *)&in.kickspeed));
  out->hdr.tankdir = (uint8_t)(in.dir*(FWIDTH/k2Pif));
  out->hdr.builderstatus = in.builderstatus;
  out->hdr.builderx = htonl(*((uint32_t *)&in.builder.x));
  out->hdr.buildery = htonl(*((uint32_t *)&in.builder.y));
  out->hdr.buildertargetx = in.buildertargetx;
  out->hdr.buildertargety = in.buildertargety;
  out->hdr.builderwait = in.builderwait;
  out->hdr.inputflags = htonl(in.inputflags);
  out->hdr.tankshotsound = in.tankshotsound;
  out->hdr.pillshotsound = in.pillshotsound;
  out->hdr.sinksound = in.sinksound;
  out->hdr.builderdeathsound = in.builderdeathsound;
  out->hdr.nshells = 0;
  out->hdr.nexplosions = 0;

  outshells = (void *)out->buf;

  for (i = 0; i < nshells && out->hdr.nshells < CLUPDATEMAXSHELLS; i++) {
    outshells[out->hdr.nshells].owner = shells[i].owner;
    outshells[out->hdr.nshells].shellx = htons((uint16_t)(shells[i].point.x*FWIDTH));
    outshells[out->hdr.nshells].shelly = htons((uint16_t)(shells[i].point.y*FWIDTH));
    outshells[out->hdr.nshells].boat = shells[i].boat;
    outshells[out->hdr.nshells].pill = shells[i].pill;
    outshells[out->hdr.nshells].shelldir = (uint8_t)(shells[i].dir*(FWIDTH/k2Pif));
    outshells[out->hdr.nshells].range = htons((uint16_t)(shells[i].range*FWIDTH));
    out->hdr.nshells++;
  }

  outexplosions = (void *)(outshells + out->hdr.nshells);

  for (i = 0; i < nexplosions && out->hdr.nexplosions < CLUPDATEMAXEXPLOSIONS; i++) {
    outexplosions[out->hdr.nexplosions].explosionx = htons((uint16_t)(explosions[i].point.x*FWIDTH));
    outexplosions[out->hdr.nexplosions].explosiony = htons((uint16_t)(explosions[i].point.y*FWIDTH));
    outexplosions[out->hdr.nexplosions].counter = explosions[i].counter;
    /* .tile is intentionally left unset here, matching sendclupdate() --
       it is never written on the real wire either (trap 1). Pinned to 0
       (rather than left as this stack frame's garbage) so the oracle is
       deterministic; the Swift encoder must also emit 0. */
    outexplosions[out->hdr.nexplosions].tile = 0;
    out->hdr.nexplosions++;
  }

  return sizeof(out->hdr)
    + out->hdr.nshells*sizeof(struct CLUpdateShell)
    + out->hdr.nexplosions*sizeof(struct CLUpdateExplosion);
}

struct CLUpdateDecodeOutput {
  int valid;  /* 0 if rejected by the structural sanity check */
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

/* Mirrors dgramclient()'s structural check + ntoh pass + field decode.
   Deliberately excludes the `clupdate.hdr.player == client.player`
   self-check (session state, not wire format) -- that belongs to 6.1's
   orchestrator. `outShells`/`outExplosions` must each have room for at
   least CLUPDATEMAXSHELLS/CLUPDATEMAXEXPLOSIONS (255) entries. Returns 0
   (outHdr->valid also 0) if the structural check fails, matching
   dgramclient()'s `continue` on a malformed datagram. */
int clupdate_decode_oracle(
  const uint8_t *bytes, size_t len,
  struct CLUpdateDecodeOutput *outHdr,
  int32_t *outSeq,
  struct ShellDecodeOutput *outShells, int *outNShells,
  struct ExplosionDecodeOutput *outExplosions, int *outNExplosions
) {
  const struct CLUpdate *in = (const void *)bytes;
  uint8_t nshells, nexplosions;
  const struct CLUpdateShell *inshells;
  const struct CLUpdateExplosion *inexplosions;
  int i;
  uint32_t tankx, tanky, speed, turnspeed, kickdir, kickspeed, builderx, buildery;

  outHdr->valid = 0;
  *outNShells = 0;
  *outNExplosions = 0;

  if (len < sizeof(in->hdr)) {
    return 0;
  }

  nshells = in->hdr.nshells;
  nexplosions = in->hdr.nexplosions;

  if (len != sizeof(in->hdr) + nshells*sizeof(struct CLUpdateShell) + nexplosions*sizeof(struct CLUpdateExplosion)) {
    return 0;
  }

  if (in->hdr.player >= MAXPLAYERS) {
    return 0;
  }

  outHdr->player = in->hdr.player;
  for (i = 0; i < MAXPLAYERS; i++) {
    outSeq[i] = ntohl(in->hdr.seq[i]);
  }

  outHdr->dead = in->hdr.tankstatus == kTankDead;
  outHdr->boat = in->hdr.tankstatus == kTankOnBoat;
  outHdr->dir = in->hdr.tankdir*((k2Pif)/FWIDTH);

  tankx = ntohl(in->hdr.tankx);
  tanky = ntohl(in->hdr.tanky);
  speed = ntohl(in->hdr.tankspeed);
  turnspeed = ntohl(in->hdr.tankturnspeed);
  kickdir = ntohl(in->hdr.tankkickdir);
  kickspeed = ntohl(in->hdr.tankkickspeed);
  builderx = ntohl(in->hdr.builderx);
  buildery = ntohl(in->hdr.buildery);

  outHdr->tank.x = *((float *)&tankx);
  outHdr->tank.y = *((float *)&tanky);
  outHdr->speed = *((float *)&speed);
  outHdr->turnspeed = *((float *)&turnspeed);
  outHdr->kickdir = *((float *)&kickdir);
  outHdr->kickspeed = *((float *)&kickspeed);
  outHdr->builder.x = *((float *)&builderx);
  outHdr->builder.y = *((float *)&buildery);

  outHdr->builderstatus = in->hdr.builderstatus;
  outHdr->buildertargetx = in->hdr.buildertargetx;
  outHdr->buildertargety = in->hdr.buildertargety;
  outHdr->builderwait = in->hdr.builderwait;
  outHdr->inputflags = ntohl(in->hdr.inputflags);
  outHdr->tankshotsound = in->hdr.tankshotsound;
  outHdr->pillshotsound = in->hdr.pillshotsound;
  outHdr->sinksound = in->hdr.sinksound;
  outHdr->builderdeathsound = in->hdr.builderdeathsound;

  inshells = (const void *)in->buf;
  inexplosions = (const void *)(inshells + nshells);

  for (i = 0; i < nshells; i++) {
    outShells[i].owner = inshells[i].owner;
    outShells[i].point.x = ntohs(inshells[i].shellx)/FWIDTH;
    outShells[i].point.y = ntohs(inshells[i].shelly)/FWIDTH;
    outShells[i].boat = inshells[i].boat;
    outShells[i].pill = inshells[i].pill;
    outShells[i].dir = inshells[i].shelldir*((k2Pif)/FWIDTH);
    outShells[i].range = ntohs(inshells[i].range)/FWIDTH;
  }
  *outNShells = nshells;

  for (i = 0; i < nexplosions; i++) {
    outExplosions[i].point.x = ntohs(inexplosions[i].explosionx)/FWIDTH;
    outExplosions[i].point.y = ntohs(inexplosions[i].explosiony)/FWIDTH;
    outExplosions[i].counter = inexplosions[i].counter;
    /* .tile intentionally never read here either -- trap 1. */
  }
  *outNExplosions = nexplosions;

  outHdr->valid = 1;
  return 1;
}

/* Struct-layout ground truth, read straight from the real headers, so the
   Swift codec's hardcoded offsets/sizes can be asserted against the
   compiler's actual layout rather than trusted from transcription. */
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

struct CLUpdateLayoutOracle clupdate_layout_oracle(void) {
  struct CLUpdateLayoutOracle L;
  L.hdrSize = sizeof(((struct CLUpdate *)0)->hdr);
  L.shellSize = sizeof(struct CLUpdateShell);
  L.explosionSize = sizeof(struct CLUpdateExplosion);
  L.offPlayer = offsetof(struct CLUpdate, hdr.player);
  L.offSeq = offsetof(struct CLUpdate, hdr.seq);
  L.offTankStatus = offsetof(struct CLUpdate, hdr.tankstatus);
  L.offTankX = offsetof(struct CLUpdate, hdr.tankx);
  L.offTankY = offsetof(struct CLUpdate, hdr.tanky);
  L.offTankSpeed = offsetof(struct CLUpdate, hdr.tankspeed);
  L.offTankTurnSpeed = offsetof(struct CLUpdate, hdr.tankturnspeed);
  L.offTankKickDir = offsetof(struct CLUpdate, hdr.tankkickdir);
  L.offTankKickSpeed = offsetof(struct CLUpdate, hdr.tankkickspeed);
  L.offTankDir = offsetof(struct CLUpdate, hdr.tankdir);
  L.offBuilderStatus = offsetof(struct CLUpdate, hdr.builderstatus);
  L.offBuilderX = offsetof(struct CLUpdate, hdr.builderx);
  L.offBuilderY = offsetof(struct CLUpdate, hdr.buildery);
  L.offBuilderTargetX = offsetof(struct CLUpdate, hdr.buildertargetx);
  L.offBuilderTargetY = offsetof(struct CLUpdate, hdr.buildertargety);
  L.offBuilderWait = offsetof(struct CLUpdate, hdr.builderwait);
  L.offInputFlags = offsetof(struct CLUpdate, hdr.inputflags);
  L.offTankShotSound = offsetof(struct CLUpdate, hdr.tankshotsound);
  L.offPillShotSound = offsetof(struct CLUpdate, hdr.pillshotsound);
  L.offSinkSound = offsetof(struct CLUpdate, hdr.sinksound);
  L.offBuilderDeathSound = offsetof(struct CLUpdate, hdr.builderdeathsound);
  L.offNShells = offsetof(struct CLUpdate, hdr.nshells);
  L.offNExplosions = offsetof(struct CLUpdate, hdr.nexplosions);
  return L;
}

/* sizeof() ground truth for every CL and SR struct, keyed by its real wire
   opcode value (bolo.h's two anonymous enums), for the Swift codec's
   struct-layout differential tests. Returns 0 for an unrecognized opcode. */
size_t sizeof_cl_oracle(int type) {
  switch (type) {
    case kHangupClientMessage: return sizeof(struct CLHangUp);
    case CLSENDMESG: return sizeof(struct CLSendMesg);
    case CLDROPBOAT: return sizeof(struct CLDropBoat);
    case CLDROPPILLS: return sizeof(struct CLDropPills);
    case CLDROPMINE: return sizeof(struct CLDropMine);
    case CLTOUCH: return sizeof(struct CLTouch);
    case CLGRABTILE: return sizeof(struct CLGrabTile);
    case CLGRABTREES: return sizeof(struct CLGrabTrees);
    case CLBUILDROAD: return sizeof(struct CLBuildRoad);
    case CLBUILDWALL: return sizeof(struct CLBuildWall);
    case CLBUILDBOAT: return sizeof(struct CLBuildBoat);
    case CLBUILDPILL: return sizeof(struct CLBuildPill);
    case CLREPAIRPILL: return sizeof(struct CLRepairPill);
    case CLPLACEMINE: return sizeof(struct CLPlaceMine);
    case CLDAMAGE: return sizeof(struct CLDamage);
    case CLSMALLBOOM: return sizeof(struct CLSmallBoom);
    case CLSUPERBOOM: return sizeof(struct CLSuperBoom);
    case CLREFUEL: return sizeof(struct CLRefuel);
    case CLHITTANK: return sizeof(struct CLHitTank);
    case CLSETALLIANCE: return sizeof(struct CLSetAlliance);
    default: return 0;
  }
}

size_t sizeof_sr_oracle(int type) {
  switch (type) {
    case SRPLAYERJOIN: return sizeof(struct SRPlayerJoin);
    case SRPLAYERREJOIN: return sizeof(struct SRPlayerRejoin);
    case SRPLAYEREXIT: return sizeof(struct SRPlayerExit);
    case SRPLAYERDISC: return sizeof(struct SRPlayerDisc);
    case SRPLAYERKICK: return sizeof(struct SRPlayerKick);
    case SRPLAYERBAN: return sizeof(struct SRPlayerBan);
    case SRHANGUP: return sizeof(struct SRHangUp);
    case SRSENDMESG: return sizeof(struct SRSendMesg);
    case SRDAMAGE: return sizeof(struct SRDamage);
    case SRGRABTREES: return sizeof(struct SRGrabTrees);
    case SRBUILD: return sizeof(struct SRBuild);
    case SRGROW: return sizeof(struct SRGrow);
    case SRFLOOD: return sizeof(struct SRFlood);
    case SRPLACEMINE: return sizeof(struct SRPlaceMine);
    case SRDROPMINE: return sizeof(struct SRDropMine);
    case SRDROPBOAT: return sizeof(struct SRDropBoat);
    case SRREPAIRPILL: return sizeof(struct SRRepairPill);
    case SRCOOLPILL: return sizeof(struct SRCoolPill);
    case SRCAPTUREPILL: return sizeof(struct SRCapturePill);
    case SRBUILDPILL: return sizeof(struct SRBuildPill);
    case SRDROPPILL: return sizeof(struct SRDropPill);
    case SRREPLENISHBASE: return sizeof(struct SRReplenishBase);
    case SRCAPTUREBASE: return sizeof(struct SRCaptureBase);
    case SRREFUEL: return sizeof(struct SRRefuel);
    case SRGRABBOAT: return sizeof(struct SRGrabBoat);
    case SRMINEACK: return sizeof(struct SRMineAck);
    case SRBUILDERACK: return sizeof(struct SRBuilderAck);
    case SRSMALLBOOM: return sizeof(struct SRSmallBoom);
    case SRSUPERBOOM: return sizeof(struct SRSuperBoom);
    case SRHITTANK: return sizeof(struct SRHitTank);
    case SRSETALLIANCE: return sizeof(struct SRSetAlliance);
    case SRTIMELIMIT: return sizeof(struct SRTimeLimit);
    case SRBASECONTROL: return sizeof(struct SRBaseControl);
    case SRPAUSE: return sizeof(struct SRPause);
    default: return 0;
  }
}

/* sizeof/offsetof ground truth for the three preamble structs (Wave 6.3),
   which carry no opcode byte and so sit outside the sizeof_cl_oracle/
   sizeof_sr_oracle dispatch above -- JOIN_Preamble (bolo.h), BOLO_Preamble
   (bmap.h), and TRACKER_Preamble (tracker.h). BOLO_Preamble's nested
   per-player array and its `game.domination` union are the two layout
   traps worth an explicit offsetof check rather than trusting sizeof
   alone. Struct definition duplicated from CXBolo.h, matching
   CLUpdateLayoutOracle's own precedent just above -- this file never
   includes the public header, only the reference C headers themselves. */
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

struct PreambleLayoutOracle preamble_layout_oracle(void) {
  struct PreambleLayoutOracle L;

  L.sizeofJoinPreamble = sizeof(struct JOIN_Preamble);
  L.offJoinName = offsetof(struct JOIN_Preamble, name);
  L.offJoinPass = offsetof(struct JOIN_Preamble, pass);

  L.sizeofBoloPreamble = sizeof(struct BOLO_Preamble);
  L.offBoloPlayer = offsetof(struct BOLO_Preamble, player);
  L.offBoloHiddenMines = offsetof(struct BOLO_Preamble, hiddenmines);
  L.offBoloPause = offsetof(struct BOLO_Preamble, pause);
  L.offBoloGameType = offsetof(struct BOLO_Preamble, gametype);
  L.offBoloDominationType = offsetof(struct BOLO_Preamble, game.domination.type);
  L.offBoloDominationBaseControl = offsetof(struct BOLO_Preamble, game.domination.basecontrol);
  L.offBoloPlayers = offsetof(struct BOLO_Preamble, players);
  L.offBoloMapLen = offsetof(struct BOLO_Preamble, maplen);
  L.sizeofBoloPlayerEntry = sizeof(((struct BOLO_Preamble *)0)->players[0]);
  L.offEntryUsed = offsetof(__typeof__(((struct BOLO_Preamble *)0)->players[0]), used);
  L.offEntryConnected = offsetof(__typeof__(((struct BOLO_Preamble *)0)->players[0]), connected);
  L.offEntrySeq = offsetof(__typeof__(((struct BOLO_Preamble *)0)->players[0]), seq);
  L.offEntryName = offsetof(__typeof__(((struct BOLO_Preamble *)0)->players[0]), name);
  L.offEntryHost = offsetof(__typeof__(((struct BOLO_Preamble *)0)->players[0]), host);
  L.offEntryAlliance = offsetof(__typeof__(((struct BOLO_Preamble *)0)->players[0]), alliance);

  L.sizeofTrackerPreamble = sizeof(struct TRACKER_Preamble);

  return L;
}

/* Permanent verbatim extract of dgramserver()'s pure per-packet decision
   core (Reference/c/server.c:614-696), for Wave 6.4b oracle testing.
   Excludes the recvfrom()/sendto() socket calls and the outer for(;;)
   drain loop -- those are HostListener's transport mechanism, this is
   only what happens to one already-received datagram plus the server's
   already-known per-player session state.

   `sin_family` is `uint8_t` on Darwin's `struct sockaddr_in` (not the
   POSIX-generic `sa_family_t` some platforms widen to 16 bits) -- matched
   here as `uint8_t` rather than assumed, so this stays a faithful
   decomposition of the real comparison rather than a guess at its width. */
struct DgramServerPlayerState {
  int used;
  int connected;       /* cntlsock != -1 */
  uint8_t dgramFamily;
  uint32_t dgramAddr;  /* sin_addr.s_addr, network byte order */
  uint16_t dgramPort;  /* sin_port, network byte order */
  uint32_t seq;
};

struct DgramServerRelayResult {
  int isTrackerEcho;    /* server.c:637-645 -- r == sizeof(hdr) && player == 255 */
  int isMalformed;      /* server.c:648-654's sanity check failed */
  int player;           /* clupdate.hdr.player; only meaningful past the malformed check */
  int isValidPlayer;    /* server.c:663-667's used/cntlsock/family/addr check */
  int isNewerSeq;       /* server.c:668's (int32_t)(seq - stored) > 0 */
  uint32_t decodedSeq;  /* ntohl(clupdate.hdr.seq[player]), server.c:661 */
  int portChanged;      /* server.c:674-676 */
  uint16_t newPort;
  uint32_t tankXRaw;    /* ntohl(clupdate.hdr.tankx) -- still the raw float bit pattern */
  uint32_t tankYRaw;
  /* relayTo/relayCount deliberately NOT members here -- a fixed-size C
     array as a struct member imports into Swift as an unsubscriptable
     N-tuple, the exact same problem this file's own top-of-file comment
     already documents for CLUpdate.hdr.seq. Written through the separate
     `outRelayTo`/`outRelayCount` pointers below instead. */
};

/* `outRelayTo` must point at a caller-allocated buffer of at least
   MAXPLAYERS ints (server.c:678-684's `i != player && cntlsock != -1`
   loop, written as a dense list of the indices that pass, not a
   MAXPLAYERS-length bitmap). */
int dgramserver_relay_oracle(
  const uint8_t *bytes, size_t len,
  uint8_t addrFamily, uint32_t addrAddr, uint16_t addrPort,
  const struct DgramServerPlayerState *players, /* MAXPLAYERS entries */
  struct DgramServerRelayResult *out,
  int *outRelayTo, int *outRelayCount
) {
  const struct CLUpdate *clupdate = (const void *)bytes;
  int player;
  uint32_t seq;
  int i;

  memset(out, 0, sizeof(*out));
  *outRelayCount = 0;

  /* test packet from tracker (server.c:637-645) -- checked before the
     sanity check, matching the C's if/else-if ordering exactly. Safe to
     dereference clupdate->hdr.player only once len == sizeof(hdr) is
     confirmed by the left operand's short-circuit. */
  if (len == sizeof(clupdate->hdr) && clupdate->hdr.player == 255) {
    out->isTrackerEcho = 1;
    return 1;
  }

  /* sanity check the size (server.c:648-654) -- the `||` chain's own
     short-circuiting is load-bearing here too: nshells/nexplosions/player
     are never read from `bytes` unless len >= sizeof(hdr) already held. */
  if (
      len < sizeof(clupdate->hdr) ||
      len != sizeof(clupdate->hdr) + clupdate->hdr.nshells*sizeof(struct CLUpdateShell) + clupdate->hdr.nexplosions*sizeof(struct CLUpdateExplosion) ||
      clupdate->hdr.player >= MAXPLAYERS
    ) {
    out->isMalformed = 1;
    return 1;
  }

  player = clupdate->hdr.player;
  out->player = player;

  /* network to host byte order (server.c:661) */
  seq = ntohl(clupdate->hdr.seq[player]);
  out->decodedSeq = seq;

  /* verify this is a valid player (server.c:663-667) */
  if (
      players[player].used &&
      players[player].connected &&
      players[player].dgramFamily == addrFamily &&
      players[player].dgramAddr == addrAddr
    ) {
    out->isValidPlayer = 1;

    /* make sure this is not an old update (server.c:668) */
    if ((int32_t)(seq - players[player].seq) > 0) {
      out->isNewerSeq = 1;
      out->tankXRaw = ntohl(clupdate->hdr.tankx);
      out->tankYRaw = ntohl(clupdate->hdr.tanky);

      if (players[player].dgramPort != addrPort) {
        out->portChanged = 1;
        out->newPort = addrPort;
      }

      /* send update to all other players (server.c:678-684) */
      for (i = 0; i < MAXPLAYERS; i++) {
        if (i != player && players[i].connected) {
          outRelayTo[*outRelayCount] = i;
          (*outRelayCount)++;
        }
      }
    }
  }

  return 1;
}

/* Struct-layout ground truth for TrackerHost/TrackerHostList
   (tracker.h:41-56), for Wave 6.5a oracle testing -- this is the one wire
   struct family in the entire protocol that is NOT
   __attribute__((__packed__)) (docs/PLAN.md's Wave 6.5 flag), so unlike
   every other CL/SR/preamble struct's offsets, these cannot be assumed
   from field order alone; they need this explicit offsetof check the
   same way preamble_layout_oracle() above already does for
   BOLO_Preamble's own traps. */
struct TrackerLayoutOracle {
  size_t sizeofTrackerHost;
  size_t offPlayerName;
  size_t offMapName;
  size_t offPort;
  size_t offGameType;
  size_t offTimeLimit;
  size_t offPassReq;
  size_t offNPlayers;
  size_t offAllowJoin;
  size_t offPause;

  size_t sizeofTrackerHostList;
  size_t offListAddr;
  size_t offListGame;
};

struct TrackerLayoutOracle tracker_layout_oracle(void) {
  struct TrackerLayoutOracle L;

  L.sizeofTrackerHost = sizeof(struct TrackerHost);
  L.offPlayerName = offsetof(struct TrackerHost, playername);
  L.offMapName = offsetof(struct TrackerHost, mapname);
  L.offPort = offsetof(struct TrackerHost, port);
  L.offGameType = offsetof(struct TrackerHost, gametype);
  L.offTimeLimit = offsetof(struct TrackerHost, timelimit);
  L.offPassReq = offsetof(struct TrackerHost, passreq);
  L.offNPlayers = offsetof(struct TrackerHost, nplayers);
  L.offAllowJoin = offsetof(struct TrackerHost, allowjoin);
  L.offPause = offsetof(struct TrackerHost, pause);

  L.sizeofTrackerHostList = sizeof(struct TrackerHostList);
  L.offListAddr = offsetof(struct TrackerHostList, addr);
  L.offListGame = offsetof(struct TrackerHostList, game);

  return L;
}

/* Verbatim field-assignment extracts of registerserver()'s send-game-data
   step (server.c:1379-1390) and sendtrackerupdate() (server.c:1569-1588),
   for Wave 6.5a oracle testing -- this pair is what proves the T-2/D56
   byte-order asymmetry on `timelimit` (registration htonl's it, the
   60-second heartbeat doesn't) is real compiler-observed behavior, not
   merely a reading of the source. `pause` is the already-computed 0/1
   both real functions pass in (`server.pause == -1` / `getpauseserver()`,
   `server.c:1387`/`:1581`) -- neither oracle function recomputes that.

   Both `memset` `*out` to 0 first -- the real C functions never do this
   (T-3, disclosed in the Wave 6.5a pre-brief: `strncpy(dst,src,LEN-1)`
   leaves the struct's offset-51 pad byte, and `playername`/`mapname`'s
   own final byte on an exactly-full-length input, as uninitialized stack
   garbage). That is genuinely undefined behavior, not a fact to
   reproduce -- the zeroing here exists only so this oracle's *other*
   bytes (the ones that ARE well-defined) have something deterministic to
   diff against; it is not a claim about the real function's own
   behavior. Swift's `TrackerHost.encode()`/`encodeAsHeartbeat()` always
   zero-fills those same locations, a disclosed Swift-safety deviation
   asserted by its own regression test, not by comparison against this
   oracle. */
void trackerhost_encode_oracle(
  const uint8_t *playername, const uint8_t *mapname,
  uint16_t port, uint8_t gametype, uint32_t timelimit,
  uint8_t passreq, uint8_t nplayers, uint8_t allowjoin, uint8_t pause,
  struct TrackerHost *out
) {
  memset(out, 0, sizeof(*out));
  memcpy(out->playername, playername, TRKPLYRNAMELEN);
  memcpy(out->mapname, mapname, TRKMAPNAMELEN);
  out->port = htons(port);
  out->gametype = gametype;
  out->timelimit = htonl(timelimit);
  out->passreq = passreq;
  out->nplayers = nplayers;
  out->allowjoin = allowjoin;
  out->pause = pause;
}

/* Same field set, from sendtrackerupdate() (server.c:1569-1588) -- the
   real bug: `timelimit` is assigned directly with NO htonl
   (server.c:1577), unlike the registration path above. Ported bit for
   bit, not corrected (D24/D40/D56). */
void trackerupdate_encode_oracle(
  const uint8_t *playername, const uint8_t *mapname,
  uint16_t port, uint8_t gametype, uint32_t timelimit,
  uint8_t passreq, uint8_t nplayers, uint8_t allowjoin, uint8_t pause,
  struct TrackerHost *out
) {
  memset(out, 0, sizeof(*out));
  memcpy(out->playername, playername, TRKPLYRNAMELEN);
  memcpy(out->mapname, mapname, TRKMAPNAMELEN);
  out->port = htons(port);
  out->gametype = gametype;
  out->timelimit = timelimit;  /* <- the bug: no htonl, server.c:1577 */
  out->passreq = passreq;
  out->nplayers = nplayers;
  out->allowjoin = allowjoin;
  out->pause = pause;
}
