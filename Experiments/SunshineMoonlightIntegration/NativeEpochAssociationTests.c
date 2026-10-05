#include "CompanionNativeEpochAssociation.h"
#include <stdio.h>
#include <stdlib.h>
#define Require(x) do { if (!(x)) { fprintf(stderr,"Native packet epoch check failed at line %d\n",__LINE__); abort(); } } while (0)
int main(int argc, const char **argv) {
  Require(argc == 2 && strlen(argv[1]) == 96);
  uint8_t old[48], next[48];
  for (size_t i = 0; i < 48; i++) { unsigned value; Require(sscanf(argv[1]+2*i,"%2x",&value) == 1); old[i] = (uint8_t)value; }
  memcpy(next,old,sizeof(next)); next[39]++; next[47]++;
  CompanionNativeEpochAssociation queue = {0}; CompanionNativeSurfaceEpoch epoch; bool marked = false;
  Require(CompanionNativeEpochAssociate(&queue,0,NULL,0));
  Require(CompanionNativeEpochAssociate(&queue,1,old,sizeof(old)));
  Require(CompanionNativeEpochAssociate(&queue,2,next,sizeof(next)));
  Require(!CompanionNativeEpochAssociate(&queue,2,old,sizeof(old)));
  Require(!CompanionNativeEpochAssociate(&queue,3,NULL,0));
  Require(CompanionNativeEpochTake(&queue,2,&epoch,&marked) && marked);
  uint8_t actual[48]; Require(CompanionNativeEpochEncode(&epoch,actual)); Require(!memcmp(actual,next,sizeof(next)));
  // Older queued output arrives after the newer epoch; it keeps the old marker.
  Require(CompanionNativeEpochTake(&queue,1,&epoch,&marked) && marked);
  Require(CompanionNativeEpochEncode(&epoch,actual)); Require(!memcmp(actual,old,sizeof(old)));
  Require(!CompanionNativeEpochTake(&queue,1,&epoch,&marked));
  Require(!CompanionNativeEpochTake(&queue,99,&epoch,&marked));
  Require(CompanionNativeEpochTake(&queue,0,&epoch,&marked) && !marked);
  for (int64_t i = 0; i < COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY; i++) Require(CompanionNativeEpochAssociate(&queue,i,old,sizeof(old)));
  Require(!CompanionNativeEpochAssociate(&queue,COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY,next,sizeof(next)));
  for (int64_t i = 0; i < COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY; i++) {
    Require(CompanionNativeEpochTake(&queue,i,&epoch,&marked) && marked);
    Require(CompanionNativeEpochEncode(&epoch,actual) && !memcmp(actual,old,sizeof(old)));
  }
  Require(CompanionNativeEpochAssociate(&queue,1000,next,sizeof(next)));
  puts("Native encoder epoch: capture/PTS association, reordered output, duplicate/unknown packet, missing marker and bounded capacity passed; no video content.");
  return 0;
}
