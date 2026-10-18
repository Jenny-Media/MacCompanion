#ifndef COMPANION_VNC_FRAMEBUFFER_BOUNDS_H
#define COMPANION_VNC_FRAMEBUFFER_BOUNDS_H
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
// Input coordinates are 16-bit RFB values; no image memory is needed for them.
static inline bool CompanionVNCInputGeometryValid(int64_t width, int64_t height) {
    return width > 0 && height > 0 && width <= UINT16_MAX && height <= UINT16_MAX;
}
static inline bool CompanionVNCFramebufferByteCount(int width, int height, size_t *result) {
    if (width <= 0 || height <= 0 || width > 16384 || height > 16384) return false;
    uint64_t bytes = (uint64_t)width * (uint64_t)height * 4;
    if (bytes > UINT64_C(96) * 1024 * 1024 || bytes > SIZE_MAX) return false;
    *result = (size_t)bytes;
    return true;
}
#endif
