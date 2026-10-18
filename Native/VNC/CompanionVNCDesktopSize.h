#pragma once
#include <stdint.h>
#include <stdbool.h>
#include <stddef.h>
#include <string.h>
#include <math.h>
#include "CompanionVNCDisplayLayout.h"

typedef struct { uint16_t width, height; } CompanionVNCDesktopSize;
enum { CompanionVNCDesktopLargerText = 1, CompanionVNCDesktopBalanced = 2, CompanionVNCDesktopMoreSpace = 3 };
static inline bool CompanionVNCDesktopSizeForPreset(int preset, CompanionVNCDesktopSize *out) {
    if (!out) return false;
    switch (preset) {
        case CompanionVNCDesktopLargerText: *out = (CompanionVNCDesktopSize){1024,640}; return true;
        case CompanionVNCDesktopBalanced: *out = (CompanionVNCDesktopSize){1280,800}; return true;
        case CompanionVNCDesktopMoreSpace: *out = (CompanionVNCDesktopSize){1440,900}; return true;
        default: return false;
    }
}
enum { CompanionVNCDesktopPacketBytes = 196 };
static inline void CompanionVNCDesktopSelectionPacket(uint32_t identifier, uint8_t packet[8]) {
    memset(packet, 0, 8); packet[0] = 13; packet[1] = identifier == 0;
    for (int i = 0; i < 4; i++) packet[4 + i] = (uint8_t)(identifier >> (24 - 8 * i));
}
static inline bool CompanionVNCDesktopSizeValid(CompanionVNCDesktopSize size) {
    return size.width >= 600 && size.height >= 600 && (size.width >= 800 || size.height >= 800)
        && size.width <= 1664 && size.height <= 1664
        && size.width % 4 == 0 && size.height % 4 == 0
        && (uint64_t)size.width * size.height * 4 <= 6000000;
}
static inline bool CompanionVNCDesktopSizeForViewport(double width, double height, CompanionVNCDesktopSize *out) {
    if (!out || !isfinite(width) || !isfinite(height) || width <= 0 || height <= 0
        || width > 16384 || height > 16384) return false;
    double enlargement = fmax(1, fmax(600 / fmin(width, height), 800 / fmax(width, height)));
    double factor = fmin(enlargement, fmin(1664 / fmax(width, height), sqrt(6000000 / (4 * width * height))));
    CompanionVNCDesktopSize size = {(uint16_t)(floor((width * factor + 1e-9) / 4) * 4), (uint16_t)(floor((height * factor + 1e-9) / 4) * 4)};
    if (!CompanionVNCDesktopSizeValid(size)) return false;
    *out = size; return true;
}
static inline void CompanionVNCDesktopPut16(uint8_t *p, uint16_t v) { p[0] = v >> 8; p[1] = v; }
static inline void CompanionVNCDesktopPut32(uint8_t *p, uint32_t v) {
    for (int i = 0; i < 4; i++) p[i] = (uint8_t)(v >> (24 - 8 * i));
}
static inline void CompanionVNCDesktopPutFloat(uint8_t *p, float v) {
    uint32_t bits; memcpy(&bits, &v, 4); CompanionVNCDesktopPut32(p, bits);
}
static inline bool CompanionVNCDesktopDisplayPacket(CompanionVNCDesktopSize size, uint8_t *packet, size_t capacity) {
    if (!packet || capacity < CompanionVNCDesktopPacketBytes || !CompanionVNCDesktopSizeValid(size)) return false;
    uint8_t result[CompanionVNCDesktopPacketBytes] = {0};
    result[0] = 29; CompanionVNCDesktopPut16(result + 2, 192);
    CompanionVNCDesktopPut16(result + 4, 1); CompanionVNCDesktopPut16(result + 6, 1);
    uint8_t *d = result + 12; CompanionVNCDesktopPut16(d, 184);
    CompanionVNCDesktopPut32(d + 122, 1); CompanionVNCDesktopPut32(d + 126, 4);
    CompanionVNCDesktopPutFloat(d + 130, (float)((double)size.width / 132 * 25.4));
    CompanionVNCDesktopPutFloat(d + 134, (float)((double)size.height / 132 * 25.4));
    CompanionVNCDesktopPut32(d + 138, size.width * 2); CompanionVNCDesktopPut32(d + 142, size.height * 2);
    CompanionVNCDesktopPut32(d + 150, 7); CompanionVNCDesktopPut16(d + 154, 1);
    CompanionVNCDesktopPut32(d + 156, size.width * 2); CompanionVNCDesktopPut32(d + 160, size.height * 2);
    CompanionVNCDesktopPut32(d + 164, size.width); CompanionVNCDesktopPut32(d + 168, size.height);
    // IEEE-754 30.0, encoded explicitly without host byte-order assumptions.
    d[172] = 0x40; d[173] = 0x3e;
    memcpy(packet, result, sizeof(result)); return true;
}

static inline bool CompanionVNCDesktopSelectionMatches(const CompanionVNCDisplayLayout *layout,
                                                       const CompanionVNCDisplayLayout *catalogue, uint32_t identifier) {
    if (!layout || !catalogue || !layout->count || !catalogue->count) return false;
    if (identifier) return layout->count == 1 && layout->displays[0].id == identifier
        && layout->width == layout->displays[0].width && layout->height == layout->displays[0].height;
    if (layout->width != catalogue->width || layout->height != catalogue->height || layout->count != catalogue->count) return false;
    for (uint16_t i = 0; i < catalogue->count; i++) {
        bool found = false;
        for (uint16_t j = 0; j < layout->count; j++) {
            CompanionVNCDisplay a = catalogue->displays[i], b = layout->displays[j];
            if (a.id == b.id && a.x == b.x && a.y == b.y && a.width == b.width && a.height == b.height) found = true;
        }
        if (!found) return false;
    }
    return true;
}

// Apple can retain the global catalogue while the header names one monitor's
// stream. Admit this only against this owner's already validated catalogue.
static inline bool CompanionVNCDecodeSelectedDisplayLayout(const uint8_t *p, size_t n,
        uint32_t identifier, const CompanionVNCDisplayLayout *catalogue, CompanionVNCDisplayLayout *out) {
    if (!p || !out || !catalogue || !identifier || n < 20 || n > UINT16_MAX
        || !catalogue->count || catalogue->count > 32 || CompanionVNCBE32(p + 10) != identifier
        || CompanionVNCBE16(p + 18) != catalogue->count) return false;
    size_t bytes = 20 + (size_t)catalogue->count * 56;
    if (n < bytes) return false;
    uint8_t global[20 + 32 * 56];
    memcpy(global, p, bytes);
    CompanionVNCDesktopPut16(global + 6, catalogue->width);
    CompanionVNCDesktopPut16(global + 8, catalogue->height);
    CompanionVNCDisplayLayout candidate = {0};
    if (!CompanionVNCDecodeDisplayLayout(global, bytes, &candidate)
        || !CompanionVNCDesktopSelectionMatches(&candidate, catalogue, 0)) return false;
    for (uint16_t i = 0; i < candidate.count; i++) {
        CompanionVNCDisplay display = candidate.displays[i];
        if (display.id != identifier) continue;
        if (CompanionVNCBE16(p + 6) != display.width || CompanionVNCBE16(p + 8) != display.height) return false;
        CompanionVNCDisplayLayout result = {0};
        result.width = display.width; result.height = display.height; result.count = 1;
        display.x = display.y = 0; result.displays[0] = display;
        *out = result; return true;
    }
    return false;
}

// Once the requested layout is proven, its fresh-image baseline has its own
// bounded deadline. Do not discard valid pixels at the earlier metadata limit.
static inline bool CompanionVNCDesktopLayoutTimedOut(double elapsed, bool exactLayout) {
    return !isfinite(elapsed) || (!exactLayout && elapsed >= 6);
}
static inline bool CompanionVNCVirtualLayoutTimedOut(double elapsed, bool exactLayout) {
    return !isfinite(elapsed) || (!exactLayout && elapsed >= 20);
}

// Baseline retries repair stalled coverage; progress never extends the deadline.
enum { CompanionVNCBaselineWait = 0, CompanionVNCBaselineRetry = 1, CompanionVNCBaselineExpired = 2 };
static inline int CompanionVNCBaselineRefreshAction(double elapsed, double requestAge, double progressAge, unsigned retries) {
    if (!isfinite(elapsed) || !isfinite(requestAge) || !isfinite(progressAge) || elapsed >= 8) return CompanionVNCBaselineExpired;
    return retries < 2 && requestAge >= 1 && progressAge >= 1 ? CompanionVNCBaselineRetry : CompanionVNCBaselineWait;
}
