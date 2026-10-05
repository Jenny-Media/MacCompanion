#ifndef MACCOMPANION_NATIVE_EPOCH_ASSOCIATION_H
#define MACCOMPANION_NATIVE_EPOCH_ASSOCIATION_H
#include "../Client/CompanionNativeSurfaceEpoch.h"

// Capture-time marker -> submitted frame PTS -> actual packet PTS. The bounded
// queue never relabels delayed packets with the currently selected surface.
// This local metadata carries no presentation or input authorization.
#define COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY 128
typedef struct {
  bool occupied, marked;
  int64_t pts;
  CompanionNativeSurfaceEpoch epoch;
} CompanionNativeEpochAssociationEntry;
typedef struct {
  CompanionNativeEpochAssociationEntry entries[COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY];
  bool continuityStarted;
} CompanionNativeEpochAssociation;

static inline bool CompanionNativeEpochAssociate(CompanionNativeEpochAssociation *queue, int64_t pts,
    const uint8_t *bytes, size_t size) {
  if (!queue || pts < 0 || ((!bytes || !size) && (bytes || size || queue->continuityStarted))) return false;
  CompanionNativeSurfaceEpoch epoch = {0};
  bool marked = bytes != NULL;
  if (marked && !CompanionNativeEpochDecode(bytes,size,&epoch)) return false;
  size_t vacant = COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY;
  for (size_t i = 0; i < COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY; i++) {
    if (queue->entries[i].occupied && queue->entries[i].pts == pts) return false;
    if (!queue->entries[i].occupied && vacant == COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY) vacant = i;
  }
  if (vacant == COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY) return false;
  CompanionNativeEpochAssociationEntry entry = {0};
  entry.occupied = true; entry.marked = marked; entry.pts = pts; entry.epoch = epoch;
  queue->entries[vacant] = entry;
  if (marked) queue->continuityStarted = true;
  return true;
}
static inline bool CompanionNativeEpochTake(CompanionNativeEpochAssociation *queue, int64_t pts,
    CompanionNativeSurfaceEpoch *epoch, bool *marked) {
  if (!queue || !epoch || !marked || pts < 0) return false;
  for (size_t i = 0; i < COMPANION_NATIVE_EPOCH_QUEUE_CAPACITY; i++) {
    if (queue->entries[i].occupied && queue->entries[i].pts == pts) {
      *epoch = queue->entries[i].epoch; *marked = queue->entries[i].marked;
      memset(&queue->entries[i],0,sizeof(queue->entries[i])); return true;
    }
  }
  return false;
}
#endif
