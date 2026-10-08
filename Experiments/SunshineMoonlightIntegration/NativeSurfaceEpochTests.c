#include "CompanionNativeSurfaceEpoch.h"
#include <stdio.h>
#include <stdlib.h>

static void Require(bool value) { if (!value) abort(); }
static size_t AddPicture(uint8_t *data, size_t offset, bool hevc, bool independent) {
  data[offset++] = 0; data[offset++] = 0; data[offset++] = 0; data[offset++] = 1;
  data[offset++] = hevc ? (independent ? 0x26 : 0x02) : (independent ? 0x65 : 0x41);
  if (hevc) data[offset++] = 1;
  data[offset++] = 0xb8; return offset;
}

int main(int argc, const char **argv) {
  Require(argc == 2 && strlen(argv[1]) == 96);
  uint8_t authoritative[48];
  for (size_t i = 0; i < 48; i++) {
    unsigned byte; Require(sscanf(argv[1]+i*2,"%2x",&byte) == 1); authoritative[i] = (uint8_t)byte;
  }
  CompanionNativeSurfaceEpoch epoch = {0}, actual = {0};
  Require(CompanionNativeEpochDecode(authoritative,48,&epoch));
  Require(epoch.surfaceRevision == 2 && epoch.coordinateSpaceRevision == 3);
  uint8_t encoded[48]; Require(CompanionNativeEpochEncode(&epoch,encoded));
  Require(memcmp(encoded,authoritative,48) == 0);
  for (unsigned codec = 0; codec < 2; codec++) {
    bool hevc = codec != 0, independent = false;
    uint8_t data[256]; size_t size = CompanionNativeEpochSEI(&epoch,hevc,data,sizeof(data));
    Require(size > 48 && size < 96);
    size_t full = AddPicture(data,size,hevc,true);
    Require(CompanionNativeEpochInspect(data,full,hevc,&actual,&independent) == 1);
    Require(independent && CompanionNativeEpochEqual(&epoch,&actual));
    Require(CompanionNativeEpochInspect(data,size-1,hevc,&actual,&independent) == -1);
    data[hevc ? 8 : 7] ^= 0x10;
    Require(CompanionNativeEpochInspect(data,full,hevc,&actual,&independent) == 0);
    size = CompanionNativeEpochSEI(&epoch,hevc,data,sizeof(data));
    full = size+CompanionNativeEpochSEI(&epoch,hevc,data+size,sizeof(data)-size);
    full = AddPicture(data,full,hevc,true);
    Require(CompanionNativeEpochInspect(data,full,hevc,&actual,&independent) == -1);
    CompanionNativeSurfaceEpoch newer = epoch; newer.coordinateSpaceRevision++;
    full = size+CompanionNativeEpochSEI(&newer,hevc,data+size,sizeof(data)-size);
    Require(CompanionNativeEpochInspect(data,full,hevc,&actual,&independent) == -1);
    size = AddPicture(data,0,hevc,true);
    Require(CompanionNativeEpochInspect(data,size,hevc,&actual,&independent) == 0);
    full = size+CompanionNativeEpochSEI(&epoch,hevc,data+size,sizeof(data)-size);
    Require(CompanionNativeEpochInspect(data,full,hevc,&actual,&independent) == -1);
    size = CompanionNativeEpochSEI(&epoch,hevc,data,sizeof(data));
    full = AddPicture(data,size,hevc,false);
    Require(CompanionNativeEpochInspect(data,full,hevc,&actual,&independent) == 1 && !independent);
    // Zero-heavy UUID/revisions exercise emulation prevention in both codecs.
    memset(newer.surfaceID,0,16); newer.surfaceRevision = 1; newer.coordinateSpaceRevision = 256;
    size = CompanionNativeEpochSEI(&newer,hevc,data,sizeof(data));
    Require(CompanionNativeEpochInspect(data,size,hevc,&actual,&independent) == 1);
    Require(CompanionNativeEpochEqual(&actual,&newer));
    for (size_t truncated = 0; truncated < size; truncated++) {
      Require(CompanionNativeEpochInspect(data,truncated,hevc,&actual,&independent) != 1);
    }
  }
  authoritative[32] = 0xff; Require(!CompanionNativeEpochDecode(authoritative,48,&actual));
  epoch.surfaceRevision = 0; Require(!CompanionNativeEpochEncode(&epoch,encoded));
  Require(CompanionNativeEpochInspect(NULL,67108865,false,&actual,&(bool){false}) == -1);
  puts("Native surface epoch: indexed H.264/HEVC vector, malformed, stale/mixed markers and IDR boundary cases passed; no pictures retained.");
  return 0;
}
