#pragma once
#include <CoreGraphics/CoreGraphics.h>
#include <math.h>

static inline CGRect CompanionVNCTextPixelRect(CGSize size, CGRect selection) {
    if (!isfinite(size.width) || !isfinite(size.height) || size.width <= 0 || size.height <= 0
        || !isfinite(selection.origin.x) || !isfinite(selection.origin.y)
        || !isfinite(selection.size.width) || !isfinite(selection.size.height)
        || selection.size.width <= 0 || selection.size.height <= 0) return CGRectNull;
    CGRect clipped = CGRectIntersection(selection, (CGRect){CGPointZero, size});
    if (CGRectIsNull(clipped) || CGRectIsEmpty(clipped)) return CGRectNull;
    return CGRectIntersection(CGRectIntegral(clipped), (CGRect){CGPointZero, size});
}

static inline bool CompanionVNCTextAreaFits(CGSize size) {
    return isfinite(size.width) && isfinite(size.height) && size.width > 0 && size.height > 0
        && size.width <= 8192 && size.height <= 8192 && size.width * size.height <= 16 * 1024 * 1024;
}
