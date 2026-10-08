#ifndef COMPANION_VNC_GESTURES_H
#define COMPANION_VNC_GESTURES_H
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <string.h>
#include <math.h>

enum { CompanionVNCMagnifyBegan = 1, CompanionVNCMagnifyChanged = 2, CompanionVNCMagnifyEnded = 4 };
typedef struct { bool active; int x, y; } CompanionVNCMagnification;

static inline bool CompanionVNCNativeGesturesSupported(bool apple889, bool layoutValid,
    int width, int height, int backingWidth, int backingHeight) {
    return apple889 && layoutValid && width > 0 && height > 0 && width <= 16384 && height <= 16384
        && width == backingWidth && height == backingHeight;
}
static inline void CompanionVNCGestureBE(uint8_t *p, uint64_t value, size_t n) {
    for (size_t i = 0; i < n; i++) p[i] = (uint8_t)(value >> (8 * (n - i - 1)));
}
static inline void CompanionVNCGestureBoundary(uint8_t *p, unsigned kind, int x, int y) {
    p[0] = 0x17; p[1] = 0; CompanionVNCGestureBE(p + 2, 12, 2);
    CompanionVNCGestureBE(p + 4, 1, 2); CompanionVNCGestureBE(p + 6, kind, 2);
    CompanionVNCGestureBE(p + 8, 3, 4); // AppKit touch subtype, not the magnification mask.
    CompanionVNCGestureBE(p + 12, x, 2); CompanionVNCGestureBE(p + 14, y, 2);
}
// Produce a whole begin/end group or one change. Invalid input leaves state/output untouched.
// The caller owns serialization and checks cancellation epochs before sending.
static inline size_t CompanionVNCMagnificationPacket(CompanionVNCMagnification *state,
    unsigned phase, double delta, int x, int y, int width, int height, uint8_t *out, size_t capacity) {
    if (!state || !out || !isfinite(delta) || fabs(delta) > .5
        || (phase != 1 && phase != 2 && phase != 4)
        || (phase != 2 && delta != 0) || (phase == 1 ? state->active : !state->active)
        || width <= 0 || height <= 0 || width > 16384 || height > 16384) return 0;
    if (phase != 1) { x = state->x; y = state->y; }
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    size_t size = phase == 2 ? 36 : 52;
    if (capacity < size) return 0;
    uint8_t packet[52] = {0};
    uint8_t *p = packet + (phase == 1 ? 16 : 0);
    p[0] = 0x17; CompanionVNCGestureBE(p + 2, 32, 2);
    CompanionVNCGestureBE(p + 4, 2, 2); CompanionVNCGestureBE(p + 6, 3, 2);
    uint64_t bits; memcpy(&bits, &delta, sizeof(bits)); CompanionVNCGestureBE(p + 8, bits, 8);
    CompanionVNCGestureBE(p + 16, x, 2); CompanionVNCGestureBE(p + 18, y, 2);
    CompanionVNCGestureBE(p + 20, phase, 8); CompanionVNCGestureBE(p + 28, 4, 8);
    if (phase == 1) CompanionVNCGestureBoundary(packet, 1, x, y);
    if (phase == 4) CompanionVNCGestureBoundary(packet + 36, 2, x, y);
    memcpy(out, packet, size);
    *state = (CompanionVNCMagnification){phase != 4, x, y};
    return size;
}

// Precise scroll fields are in Mac points; preserve fractional motion in 16.16.
typedef struct { bool active; int x, y; } CompanionVNCScroll;
static inline size_t CompanionVNCScrollPacket(CompanionVNCScroll *state, unsigned phase,
    double dx, double dy, int x, int y, int width, int height, uint8_t *out, size_t capacity) {
    if (!state || !out || !isfinite(dx) || !isfinite(dy) || fabs(dx) > 2048 || fabs(dy) > 2048
        || (phase != 1 && phase != 2 && phase != 4) || (phase != 2 && (dx != 0 || dy != 0))
        || (phase == 1 ? state->active : !state->active)
        || width <= 0 || height <= 0 || width > 16384 || height > 16384 || capacity < 58) return 0;
    if (phase != 1) { x = state->x; y = state->y; }
    if (x < 0 || y < 0 || x >= width || y >= height) return 0;
    uint8_t packet[58] = {0}; packet[0] = 0x17;
    CompanionVNCGestureBE(packet + 2, 54, 2);
    uint8_t *p = packet + 4;
    CompanionVNCGestureBE(p, 1, 2); CompanionVNCGestureBE(p + 2, 11, 2);
    CompanionVNCGestureBE(p + 10, (uint32_t)(int32_t)llround(dx * 65536), 4);
    CompanionVNCGestureBE(p + 14, (uint32_t)(int32_t)llround(dy * 65536), 4);
    CompanionVNCGestureBE(p + 22, (uint32_t)(int32_t)llround(dx), 4);
    CompanionVNCGestureBE(p + 26, (uint32_t)(int32_t)llround(dy), 4);
    CompanionVNCGestureBE(p + 34, phase, 4);
    CompanionVNCGestureBE(p + 42, 1, 4); CompanionVNCGestureBE(p + 46, 2, 4);
    CompanionVNCGestureBE(p + 50, x, 2); CompanionVNCGestureBE(p + 52, y, 2);
    memcpy(out, packet, sizeof(packet)); *state = (CompanionVNCScroll){phase != 4, x, y};
    return sizeof(packet);
}
#endif
