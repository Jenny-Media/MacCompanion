#import <UIKit/UIKit.h>

/// A tabletop is admitted only when the system divides enough usable space
/// horizontally for both content and input. No device or hinge-angle heuristics.
static inline BOOL CompanionVNCTabletopRegions(CGRect safe, CGRect division, CGRect *content, CGRect *input) {
    if (CGRectIsNull(division) || CGRectIsEmpty(division) || CGRectIsEmpty(safe)) return NO;
    CGRect overlap = CGRectIntersection(safe, division);
    if (CGRectIsNull(overlap) || overlap.size.width < safe.size.width * .6 || overlap.size.width <= overlap.size.height) return NO;
    CGFloat upper = CGRectGetMinY(overlap) - CGRectGetMinY(safe);
    CGFloat lower = CGRectGetMaxY(safe) - CGRectGetMaxY(overlap);
    if (upper < 160 || lower < 160) return NO;
    *content = CGRectMake(safe.origin.x, safe.origin.y, safe.size.width, upper);
    *input = CGRectMake(safe.origin.x, CGRectGetMaxY(overlap), safe.size.width, lower);
    return YES;
}

static inline CGRect CompanionVNCActiveDivision(UIView *view) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        for (UIViewReservedRegion *region in [view reservedRegionsOfKind:UIViewReservedRegionKind.divisionRegionKind]) {
            if (region.isActive && !CGRectIsEmpty(region.frame)) return region.frame;
        }
    }
#endif
    return CGRectNull;
}

static inline void CompanionVNCObserveDivision(UIView *view) {
#if __IPHONE_OS_VERSION_MAX_ALLOWED >= 270100
    if (@available(iOS 27.1, *)) {
        __weak UIView *weakView = view;
        [view addInteraction:[[UIHingeInteraction alloc] initWithUpdateHandler:^(UIHingeInteraction *interaction, UIHingeInteractionUpdate *update) {
            [weakView setNeedsLayout];
        }]];
    }
#endif
}
