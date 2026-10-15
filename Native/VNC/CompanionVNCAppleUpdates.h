#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <string.h>
#include "CompanionVNCFramebufferBounds.h"

// Classic Apple opcode 9 uses a microsecond period, not the high-performance
// session's separately described fields. Keep all reserved bytes zero.
static inline bool CompanionVNCAppleUpdatePacket(int width, int height, bool enabled, uint8_t packet[16]) {
    size_t bytes;
    if (!packet || !CompanionVNCFramebufferByteCount(width, height, &bytes)) return false;
    uint32_t period = enabled ? 100000 : UINT32_MAX;
    memset(packet, 0, 16); packet[0] = 9;
    for (int i = 0; i < 4; i++) packet[4 + i] = (uint8_t)(period >> (24 - 8 * i));
    packet[12] = (uint8_t)(width >> 8); packet[13] = (uint8_t)width;
    packet[14] = (uint8_t)(height >> 8); packet[15] = (uint8_t)height;
    return true;
}
