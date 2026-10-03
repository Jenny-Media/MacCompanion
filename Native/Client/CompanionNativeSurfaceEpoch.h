#ifndef COMPANION_NATIVE_SURFACE_EPOCH_H
#define COMPANION_NATIVE_SURFACE_EPOCH_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>

// A frame observation only. Neither this marker nor this codec grants input.
typedef struct {
  uint8_t surfaceID[16];
  uint64_t surfaceRevision, coordinateSpaceRevision;
} CompanionNativeSurfaceEpoch;

static const uint8_t CompanionNativeEpochUUID[16] = {
  0xd5,0xe7,0xc9,0x3a,0x1d,0xa9,0x4b,0xf2,0x8f,0x2b,0x09,0xa1,0xde,0x10,0x5a,0x51
};

static inline bool CompanionNativeEpochValid(const CompanionNativeSurfaceEpoch *epoch) {
  return epoch && epoch->surfaceRevision > 0 && epoch->surfaceRevision <= UINT64_C(9007199254740991)
      && epoch->coordinateSpaceRevision > 0 && epoch->coordinateSpaceRevision <= UINT64_C(9007199254740991);
}

static inline bool CompanionNativeEpochEqual(const CompanionNativeSurfaceEpoch *a, const CompanionNativeSurfaceEpoch *b) {
  return a && b && memcmp(a->surfaceID,b->surfaceID,16) == 0
      && a->surfaceRevision == b->surfaceRevision && a->coordinateSpaceRevision == b->coordinateSpaceRevision;
}

static inline bool CompanionNativeEpochEncode(const CompanionNativeSurfaceEpoch *epoch, uint8_t bytes[48]) {
  if (!bytes || !CompanionNativeEpochValid(epoch)) return false;
  memcpy(bytes,CompanionNativeEpochUUID,16); memcpy(bytes+16,epoch->surfaceID,16);
  for (size_t i = 0; i < 8; i++) {
    bytes[32+i] = (uint8_t)(epoch->surfaceRevision >> ((7-i)*8));
    bytes[40+i] = (uint8_t)(epoch->coordinateSpaceRevision >> ((7-i)*8));
  }
  return true;
}

static inline bool CompanionNativeEpochDecode(const uint8_t *bytes, size_t size, CompanionNativeSurfaceEpoch *epoch) {
  if (!bytes || size != 48 || !epoch || memcmp(bytes,CompanionNativeEpochUUID,16)) return false;
  CompanionNativeSurfaceEpoch decoded = {0}; memcpy(decoded.surfaceID,bytes+16,16);
  for (size_t i = 0; i < 8; i++) {
    decoded.surfaceRevision = (decoded.surfaceRevision << 8) | bytes[32+i];
    decoded.coordinateSpaceRevision = (decoded.coordinateSpaceRevision << 8) | bytes[40+i];
  }
  if (!CompanionNativeEpochValid(&decoded)) return false;
  *epoch = decoded; return true;
}

// Prefix SEI in Annex B format; capacity 96 is sufficient for either codec.
static inline size_t CompanionNativeEpochSEI(const CompanionNativeSurfaceEpoch *epoch, bool hevc,
                                            uint8_t *output, size_t capacity) {
  uint8_t payload[48];
  if (!output || capacity < 96 || !CompanionNativeEpochEncode(epoch,payload)) return 0;
  size_t offset = 0;
  output[offset++] = 0; output[offset++] = 0; output[offset++] = 0; output[offset++] = 1;
  output[offset++] = hevc ? 0x4e : 0x06;
  if (hevc) output[offset++] = 1;
  output[offset++] = 5; output[offset++] = 48;
  unsigned zeros = 0;
  for (size_t i = 0; i < sizeof(payload); i++) {
    if (zeros >= 2 && payload[i] <= 3) { output[offset++] = 3; zeros = 0; }
    output[offset++] = payload[i]; zeros = payload[i] == 0 ? zeros+1 : 0;
  }
  output[offset++] = 0x80; return offset;
}

typedef struct { const uint8_t *data; size_t size, offset; unsigned zeros; } CompanionNativeRBSPReader;
static inline bool CompanionNativeRBSPNext(CompanionNativeRBSPReader *reader, uint8_t *byte) {
  if (reader->offset >= reader->size) return false;
  uint8_t next = reader->data[reader->offset++];
  if (reader->zeros >= 2 && next == 3) {
    if (reader->offset >= reader->size || reader->data[reader->offset] > 3) return false;
    next = reader->data[reader->offset++]; reader->zeros = 0;
  }
  reader->zeros = next == 0 ? reader->zeros+1 : 0; *byte = next; return true;
}

static inline size_t CompanionNativeStartCode(const uint8_t *data, size_t size, size_t offset) {
  if (offset <= size && size-offset >= 3 && data[offset] == 0 && data[offset+1] == 0) {
    if (data[offset+2] == 1) return 3;
    if (size-offset >= 4 && data[offset+2] == 0 && data[offset+3] == 1) return 4;
  }
  return 0;
}

// 1 = exactly one valid prefix marker, 0 = absent, -1 = malformed. No dynamic
// allocation or picture retention. IDR observation cannot admit input by itself.
static inline int CompanionNativeEpochInspect(const uint8_t *data, size_t size, bool hevc,
                                              CompanionNativeSurfaceEpoch *epoch, bool *independentPicture) {
  if (!epoch || !independentPicture || (!data && size) || size > 67108864) return -1;
  *independentPicture = false;
  bool found = false, pictureSeen = false;
  size_t position = 0;
  while (position < size) {
    size_t prefix = CompanionNativeStartCode(data,size,position);
    if (!prefix) { position++; continue; }
    size_t beginning = position+prefix, end = beginning;
    while (end < size && !CompanionNativeStartCode(data,size,end)) end++;
    position = end;
    if (beginning == end || (hevc && end-beginning < 2)) return -1;
    uint8_t type = hevc ? (data[beginning] >> 1) & 63 : data[beginning] & 31;
    bool picture = hevc ? type <= 31 : type >= 1 && type <= 5;
    if (picture) {
      pictureSeen = true;
      if (hevc ? type >= 16 && type <= 21 : type == 5) *independentPicture = true;
    }
    if (type != (hevc ? 39 : 6)) continue;
    if (data[beginning] & 0x80 || (hevc && !(data[beginning+1] & 7))) return -1;
    beginning += hevc ? 2 : 1;
    while (end > beginning && data[end-1] == 0) end--;
    CompanionNativeRBSPReader reader = {data+beginning,end-beginning,0,0};
    bool trailingSeen = false;
    while (reader.offset < reader.size) {
      uint8_t byte;
      if (!CompanionNativeRBSPNext(&reader,&byte)) return -1;
      if (byte == 0x80 && reader.offset == reader.size) { trailingSeen = true; break; }
      size_t payloadType = 0, payloadSize = 0;
      do { payloadType += byte; if (byte != 255) break;
        if (!CompanionNativeRBSPNext(&reader,&byte)) return -1;
      } while (payloadType <= reader.size);
      if (!CompanionNativeRBSPNext(&reader,&byte)) return -1;
      do { payloadSize += byte; if (byte != 255) break;
        if (!CompanionNativeRBSPNext(&reader,&byte)) return -1;
      } while (payloadSize <= reader.size);
      if (payloadSize > reader.size-reader.offset) return -1;
      uint8_t payload[48] = {0};
      for (size_t i = 0; i < payloadSize; i++) {
        if (!CompanionNativeRBSPNext(&reader,&byte)) return -1;
        if (i < sizeof(payload)) payload[i] = byte;
      }
      if (payloadType != 5 || payloadSize < 16 || memcmp(payload,CompanionNativeEpochUUID,16)) continue;
      if (found || pictureSeen || payloadSize != 48 || !CompanionNativeEpochDecode(payload,48,epoch)) return -1;
      found = true;
    }
    if (!trailingSeen) return -1;
  }
  return found ? 1 : 0;
}

#endif
