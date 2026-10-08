#import <CoreGraphics/CoreGraphics.h>
#include <math.h>
#include <stdbool.h>

static inline CGRect CompanionVNCViewportRect(CGSize framebuffer, CGRect normalized, bool selected, CGFloat aspect) {
    if (!isfinite(framebuffer.width) || !isfinite(framebuffer.height) || framebuffer.width <= 0 || framebuffer.height <= 0) return CGRectNull;
    if (!selected) return (CGRect){CGPointZero, framebuffer};
    if (!isfinite(aspect) || aspect <= 0 || fabs(framebuffer.width / framebuffer.height - aspect) / aspect >= .03
        || !isfinite(normalized.origin.x) || !isfinite(normalized.origin.y)
        || !isfinite(normalized.size.width) || !isfinite(normalized.size.height)
        || normalized.origin.x < 0 || normalized.origin.y < 0 || normalized.size.width <= 0 || normalized.size.height <= 0
        || CGRectGetMaxX(normalized) > 1.000001 || CGRectGetMaxY(normalized) > 1.000001) return CGRectNull;
    CGFloat x = round(normalized.origin.x * framebuffer.width), y = round(normalized.origin.y * framebuffer.height);
    CGFloat right = fmin(framebuffer.width, round(CGRectGetMaxX(normalized) * framebuffer.width));
    CGFloat bottom = fmin(framebuffer.height, round(CGRectGetMaxY(normalized) * framebuffer.height));
    if (right <= x || bottom <= y) return CGRectNull;
    return CGRectMake(x, y, right - x, bottom - y);
}
static inline bool CompanionVNCPointerPoint(CGRect crop, CGPoint local, bool clamp, CGPoint *mapped) {
    if (CGRectIsNull(crop) || CGRectIsEmpty(crop) || !isfinite(local.x) || !isfinite(local.y)) return false;
    if (!clamp && (local.x < 0 || local.y < 0 || local.x >= crop.size.width || local.y >= crop.size.height)) return false;
    *mapped = CGPointMake(crop.origin.x + floor(fmax(0, fmin(crop.size.width - 1, local.x))),
                         crop.origin.y + floor(fmax(0, fmin(crop.size.height - 1, local.y))));
    return true;
}
static inline CGRect CompanionVNCWindowInCrop(CGRect crop, CGRect window) {
    CGRect visible = CGRectIntersection(crop, window);
    if (CGRectIsNull(visible) || CGRectIsEmpty(visible)) return CGRectNull;
    return CGRectOffset(visible, -crop.origin.x, -crop.origin.y);
}

static inline CGPoint CompanionVNCFollowOffset(CGSize content, CGRect viewport, CGPoint cursor) {
    if (!isfinite(content.width) || !isfinite(content.height) || content.width < 0 || content.height < 0
        || !isfinite(viewport.origin.x) || !isfinite(viewport.origin.y)
        || !isfinite(viewport.size.width) || !isfinite(viewport.size.height)
        || viewport.size.width <= 0 || viewport.size.height <= 0 || !isfinite(cursor.x) || !isfinite(cursor.y)) return viewport.origin;
    CGFloat mx = fmin(64, viewport.size.width * .12), my = fmin(64, viewport.size.height * .12);
    CGRect safe = CGRectInset(viewport, mx, my);
    CGPoint offset = viewport.origin;
    if (cursor.x < CGRectGetMinX(safe)) offset.x += cursor.x - CGRectGetMinX(safe);
    else if (cursor.x > CGRectGetMaxX(safe)) offset.x += cursor.x - CGRectGetMaxX(safe);
    if (cursor.y < CGRectGetMinY(safe)) offset.y += cursor.y - CGRectGetMinY(safe);
    else if (cursor.y > CGRectGetMaxY(safe)) offset.y += cursor.y - CGRectGetMaxY(safe);
    offset.x = fmax(0, fmin(fmax(0, content.width - viewport.size.width), offset.x));
    offset.y = fmax(0, fmin(fmax(0, content.height - viewport.size.height), offset.y));
    return offset;
}

static inline CGRect CompanionVNCSmartZoomRect(CGSize crop, CGSize canvas, CGPoint point, CGFloat minimum, CGFloat maximum) {
    if (!isfinite(crop.width) || !isfinite(crop.height) || !isfinite(canvas.width) || !isfinite(canvas.height)
        || !isfinite(point.x) || !isfinite(point.y) || !isfinite(minimum) || !isfinite(maximum)
        || crop.width <= 0 || crop.height <= 0 || canvas.width <= 0 || canvas.height <= 0
        || minimum <= 0 || maximum < minimum || point.x < 0 || point.y < 0 || point.x >= crop.width || point.y >= crop.height) return CGRectNull;
    CGFloat zoom = fmin(maximum, minimum * 2);
    CGFloat width = fmin(crop.width, canvas.width / zoom), height = fmin(crop.height, canvas.height / zoom);
    return CGRectMake(fmax(0, fmin(crop.width - width, point.x - width / 2)),
                      fmax(0, fmin(crop.height - height, point.y - height / 2)), width, height);
}
