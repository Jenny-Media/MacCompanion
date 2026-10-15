#pragma once
#include <stdbool.h>
#include <stdint.h>
#include <stdlib.h>
#include <zlib.h>

// Apple STORE pixels carry a separate alpha plane. Do not use the binary
// standard-RFB cursor mask conversion for this format.
static inline bool CompanionVNCAppleCursorRGBA(int width, int height, int hotX, int hotY,
    const uint8_t *compressed, size_t length, uint8_t *rgba, size_t capacity) {
    if (width < 1 || height < 1 || width > 256 || height > 256 || hotX < 0 || hotY < 0
        || hotX >= width || hotY >= height || !compressed || !length || length > 512 * 1024) return false;
    size_t pixels = (size_t)width * height, expected = pixels * 5;
    if (!rgba || capacity < pixels * 4) return false;
    uint8_t *decoded = malloc(expected + 1);
    if (!decoded) return false;
    z_stream stream = {0};
    bool valid = false;
    if (inflateInit(&stream) == Z_OK) {
        stream.next_in = (Bytef *)compressed; stream.avail_in = (uInt)length;
        stream.next_out = decoded; stream.avail_out = (uInt)expected + 1;
        int result = inflate(&stream, Z_SYNC_FLUSH);
        bool flushed = length >= 4 && compressed[length - 4] == 0 && compressed[length - 3] == 0
            && compressed[length - 2] == 255 && compressed[length - 1] == 255;
        valid = stream.avail_in == 0 && stream.total_out == expected
            && (result == Z_STREAM_END || (result == Z_OK && flushed));
        inflateEnd(&stream);
    }
    if (valid) {
        for (size_t i = 0; i < pixels; i++) {
            unsigned alpha = decoded[pixels * 4 + i];
            rgba[i * 4] = (decoded[i * 4 + 2] * alpha + 127) / 255;
            rgba[i * 4 + 1] = (decoded[i * 4 + 1] * alpha + 127) / 255;
            rgba[i * 4 + 2] = (decoded[i * 4] * alpha + 127) / 255;
            rgba[i * 4 + 3] = alpha;
        }
    }
    free(decoded); return valid;
}
