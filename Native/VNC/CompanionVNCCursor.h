#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

static inline bool CompanionVNCCursorRGBA(int width, int height, int bytesPerPixel, int hotX, int hotY,
    const uint8_t *source, size_t sourceLength, const uint8_t *mask, size_t maskLength,
    uint8_t *rgba, size_t capacity) {
    if (width <= 0 || height <= 0 || width > 256 || height > 256 || bytesPerPixel != 4
        || hotX < 0 || hotY < 0 || hotX >= width || hotY >= height) return false;
    size_t count = (size_t)width * (size_t)height;
    if (!source || !mask || !rgba || sourceLength < count * 4 || maskLength < count || capacity < count * 4) return false;
    for (size_t i = 0; i < count; i++) {
        bool visible = mask[i] != 0;
        rgba[i * 4] = visible ? source[i * 4 + 2] : 0;
        rgba[i * 4 + 1] = visible ? source[i * 4 + 1] : 0;
        rgba[i * 4 + 2] = visible ? source[i * 4] : 0;
        rgba[i * 4 + 3] = visible ? 255 : 0;
    }
    return true;
}

static inline bool CompanionVNCCursorLocalPoint(CGRect crop, CGPoint point, CGPoint *local) {
    if (CGRectIsNull(crop) || CGRectIsEmpty(crop) || !isfinite(point.x) || !isfinite(point.y)
        || !CGRectContainsPoint(crop, point)) return false;
    *local = CGPointMake(point.x - crop.origin.x, point.y - crop.origin.y);
    return true;
}

static inline CGRect CompanionVNCCursorScreenRect(CGPoint anchor, CGSize pixels, CGPoint hotspot, CGFloat zoom) {
    if (!isfinite(anchor.x) || !isfinite(anchor.y) || !isfinite(pixels.width) || !isfinite(pixels.height)
        || !isfinite(hotspot.x) || !isfinite(hotspot.y) || !isfinite(zoom) || zoom <= 0
        || pixels.width <= 0 || pixels.height <= 0 || pixels.width > 256 || pixels.height > 256
        || hotspot.x < 0 || hotspot.y < 0 || hotspot.x >= pixels.width || hotspot.y >= pixels.height) return CGRectNull;
    CGFloat longest = fmax(pixels.width, pixels.height);
    CGFloat scale = fmax(24, fmin(64, longest * zoom)) / longest;
    return CGRectMake(anchor.x - hotspot.x * scale, anchor.y - hotspot.y * scale,
                      pixels.width * scale, pixels.height * scale);
}
