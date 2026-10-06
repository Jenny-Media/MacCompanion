#ifndef COMPANION_VNC_COVERAGE_H
#define COMPANION_VNC_COVERAGE_H
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <stdbool.h>

// Two bits per pixel. Only used while establishing a baseline; no pixel inspection.
typedef struct {
    uint8_t *seen, *required;
    size_t bytes, received, expected;
    int width, height;
} CompanionVNCCoverage;
static inline void CompanionVNCCoverageFree(CompanionVNCCoverage *c) {
    free(c->seen); free(c->required); memset(c, 0, sizeof(*c));
}
static inline bool CompanionVNCCoverageReset(CompanionVNCCoverage *c, int w, int h) {
    size_t pixels = (size_t)w * h, bytes = (pixels + 7) / 8;
    uint8_t *seen = calloc(1, bytes), *required = malloc(bytes);
    if (!seen || !required) { free(seen); free(required); return false; }
    CompanionVNCCoverageFree(c); memset(required, 255, bytes);
    if (pixels % 8) required[bytes - 1] = (1u << (pixels % 8)) - 1;
    *c = (CompanionVNCCoverage){seen, required, bytes, 0, pixels, w, h}; return true;
}
static inline void CompanionVNCCoverageRange(CompanionVNCCoverage *c, size_t start, size_t end, bool requirement) {
    for (size_t byte = start / 8; byte < (end + 7) / 8; byte++) {
        unsigned low = byte == start / 8 ? start % 8 : 0;
        unsigned high = byte == (end - 1) / 8 ? (end - 1) % 8 + 1 : 8;
        uint8_t mask = ((1u << high) - 1) & ~((1u << low) - 1);
        if (requirement) {
            uint8_t added = mask & ~c->required[byte]; c->required[byte] |= mask;
            c->expected += __builtin_popcount(added); c->received += __builtin_popcount(added & c->seen[byte]);
        } else {
            uint8_t added = mask & ~c->seen[byte]; c->seen[byte] |= mask;
            c->received += __builtin_popcount(added & c->required[byte]);
        }
    }
}
static inline void CompanionVNCCoverageRect(CompanionVNCCoverage *c, int x, int y, int w, int h, bool requirement) {
    if (!c->seen || x < 0 || y < 0 || w <= 0 || h <= 0 || w > c->width - x || h > c->height - y) return;
    for (int row = y; row < y + h; row++) {
        size_t start = (size_t)row * c->width + x;
        CompanionVNCCoverageRange(c, start, start + w, requirement);
    }
}
static inline void CompanionVNCCoverageClearRequirements(CompanionVNCCoverage *c) {
    if (c->required) memset(c->required, 0, c->bytes); c->expected = c->received = 0;
}
static inline bool CompanionVNCCoverageReady(const CompanionVNCCoverage *c) {
    return c->expected > 0 && c->received == c->expected;
}
#endif
