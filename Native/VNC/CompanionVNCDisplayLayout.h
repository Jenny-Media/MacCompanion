#ifndef COMPANION_VNC_DISPLAY_LAYOUT_H
#define COMPANION_VNC_DISPLAY_LAYOUT_H
#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

typedef struct { uint32_t id; uint16_t x, y, width, height; } CompanionVNCDisplay;
typedef struct {
    uint16_t width, height, count;
    CompanionVNCDisplay displays[32];
} CompanionVNCDisplayLayout;

static inline uint16_t CompanionVNCBE16(const uint8_t *p) { return (uint16_t)((p[0] << 8) | p[1]); }
static inline uint32_t CompanionVNCBE32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) | ((uint32_t)p[2] << 8) | p[3];
}
// Apple 1105 body, excluding the uint16 length prefix. Publish atomically only
// after every record passes; an unknown revision must never create guessed crops.
static inline bool CompanionVNCDecodeDisplayLayout(const uint8_t *p, size_t n, CompanionVNCDisplayLayout *out) {
    if (!p || !out || n < 20 || n > UINT16_MAX || CompanionVNCBE16(p) != 5) return false;
    CompanionVNCDisplayLayout result = {0};
    result.width = CompanionVNCBE16(p + 6); result.height = CompanionVNCBE16(p + 8);
    result.count = CompanionVNCBE16(p + 18);
    if (!result.width || !result.height || result.width > 16384 || result.height > 16384
        || !result.count || result.count > 32 || n < 20 + (size_t)result.count * 56) return false;
    for (size_t i = 0; i < result.count; i++) {
        const uint8_t *r = p + 20 + i * 56;
        uint16_t y = CompanionVNCBE16(r + 28), x = CompanionVNCBE16(r + 30);
        uint16_t bottom = CompanionVNCBE16(r + 32), right = CompanionVNCBE16(r + 34);
        if (bottom <= y || right <= x || bottom > result.height || right > result.width) return false;
        uint32_t id = CompanionVNCBE32(r + 16);
        for (size_t j = 0; j < i; j++) if (result.displays[j].id == id) return false;
        result.displays[i] = (CompanionVNCDisplay){id, x, y, right - x, bottom - y};
    }
    *out = result; return true;
}
#endif
