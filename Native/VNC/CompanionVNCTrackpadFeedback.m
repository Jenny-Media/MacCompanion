#import "CompanionVNCTrackpadFeedback.h"
#import <UIKit/UIGestureRecognizerSubclass.h>

@interface CompanionVNCTrackpadFeedback ()
@property NSMutableDictionary<NSValue *, CAShapeLayer *> *rings;
@property NSMutableSet<CAShapeLayer *> *retiringRings;
@property CAShapeLayer *pulse;
@property UIGestureRecognizer *touchObserver;
@property UIImpactFeedbackGenerator *clickFeedback, *dragFeedback;
@property(nonatomic) BOOL dragging;
- (void)updateTouchPoints:(NSDictionary<NSValue *, NSValue *> *)points;
- (void)prepareHaptics;
@end

/// Stays Possible until all fingers lift. It never recognizes, delays touches,
/// or participates in failure dependencies with the actual input recognizers.
@interface CompanionVNCTrackpadTouchObserver : UIGestureRecognizer
@property(nonatomic, weak) CompanionVNCTrackpadFeedback *feedback;
@property NSMutableSet<UITouch *> *fingers;
@end
@implementation CompanionVNCTrackpadTouchObserver
- (instancetype)init {
    if ((self = [super initWithTarget:nil action:nil])) {
        self.fingers = [NSMutableSet new];
        self.cancelsTouchesInView = NO; self.delaysTouchesBegan = NO; self.delaysTouchesEnded = NO;
    }
    return self;
}
- (BOOL)canPreventGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (BOOL)canBePreventedByGestureRecognizer:(UIGestureRecognizer *)other { return NO; }
- (void)publish {
    NSMutableDictionary *points = [NSMutableDictionary new];
    for (UITouch *finger in self.fingers) {
        if (points.count == 5) break;
        points[[NSValue valueWithNonretainedObject:finger]] = [NSValue valueWithCGPoint:[finger locationInView:self.feedback]];
    }
    [self.feedback updateTouchPoints:points];
}
- (void)touchesBegan:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (!self.feedback.active || (self.feedback.touchesAllowed && !self.feedback.touchesAllowed())) {
        self.state = UIGestureRecognizerStateFailed; return;
    }
    BOOL first = self.fingers.count == 0;
    for (UITouch *finger in touches) if (finger.type == UITouchTypeDirect) [self.fingers addObject:finger];
    if (first && self.fingers.count) [self.feedback prepareHaptics];
    [self publish];
}
- (void)touchesMoved:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    if (self.feedback.touchesAllowed && !self.feedback.touchesAllowed()) { self.state = UIGestureRecognizerStateFailed; return; }
    [self publish];
}
- (void)touchesEnded:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.fingers minusSet:touches]; [self publish];
    if (!self.fingers.count) self.state = UIGestureRecognizerStateFailed;
}
- (void)touchesCancelled:(NSSet<UITouch *> *)touches withEvent:(UIEvent *)event {
    [self.feedback cancelTouches];
}
- (void)reset { [super reset]; [self.fingers removeAllObjects]; [self publish]; }
@end

@implementation CompanionVNCTrackpadFeedback
- (instancetype)initWithSurface:(UIView *)surface {
    if ((self = [super initWithFrame:CGRectZero])) {
        self.userInteractionEnabled = NO; self.accessibilityElementsHidden = YES; self.clipsToBounds = YES;
        self.showsTouchPoints = YES; self.hapticsEnabled = YES;
        self.rings = [NSMutableDictionary new]; self.retiringRings = [NSMutableSet new];
        CompanionVNCTrackpadTouchObserver *observer = [CompanionVNCTrackpadTouchObserver new];
        observer.feedback = self; observer.enabled = NO; [surface addGestureRecognizer:observer]; self.touchObserver = observer;
        [self registerForTraitChanges:@[UITraitUserInterfaceStyle.class, UITraitAccessibilityContrast.class]
                           withHandler:^(__kindof CompanionVNCTrackpadFeedback *view, UITraitCollection *previous) { [view restyle]; }];
    }
    return self;
}
- (BOOL)reduceMotion { return UIAccessibilityIsReduceMotionEnabled(); }
- (void)setActive:(BOOL)active {
    if (_active == active) return;
    _active = active; self.hidden = !active;
    self.touchObserver.enabled = active;
    if (!active) [self cancelTouches];
}
- (void)setShowsTouchPoints:(BOOL)value {
    _showsTouchPoints = value;
    if (!value) [self clearRings];
}
- (void)setHapticsEnabled:(BOOL)value {
    _hapticsEnabled = value;
    if (!value) { self.clickFeedback = nil; self.dragFeedback = nil; }
}
- (void)prepareHaptics {
    if (!self.hapticsEnabled || !self.active) return;
    if (!self.clickFeedback) self.clickFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    if (!self.dragFeedback) self.dragFeedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleMedium];
    [self.clickFeedback prepare]; [self.dragFeedback prepare];
}
- (void)emitHaptic:(BOOL)drag {
    if (!self.hapticsEnabled || !self.active) return;
    [self prepareHaptics];
    [(drag ? self.dragFeedback : self.clickFeedback) impactOccurred];
}
- (void)styleRing:(CAShapeLayer *)ring {
    UIColor *accent = [UIColor.systemBlueColor resolvedColorWithTraitCollection:self.traitCollection];
    ring.fillColor = [accent colorWithAlphaComponent:self.dragging ? .20 : .10].CGColor;
    ring.strokeColor = [accent colorWithAlphaComponent:self.dragging ? .9 : .55].CGColor;
    ring.lineWidth = self.dragging ? 3 : 1.5;
}
- (void)restyle {
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (CAShapeLayer *ring in self.rings.allValues) [self styleRing:ring];
    [CATransaction commit];
}
- (CAShapeLayer *)ringAtPoint:(CGPoint)point {
    CAShapeLayer *ring = [CAShapeLayer layer]; ring.bounds = CGRectMake(0, 0, 48, 48); ring.position = point;
    ring.path = [UIBezierPath bezierPathWithOvalInRect:CGRectInset(ring.bounds, 2, 2)].CGPath;
    [self styleRing:ring]; [self.layer addSublayer:ring]; return ring;
}
- (void)retireRing:(CAShapeLayer *)ring {
    [self.retiringRings addObject:ring];
    __weak CompanionVNCTrackpadFeedback *weak = self;
    [CATransaction begin]; [CATransaction setAnimationDuration:.12];
    [CATransaction setCompletionBlock:^{ [ring removeFromSuperlayer]; [weak.retiringRings removeObject:ring]; }];
    ring.opacity = 0; [CATransaction commit];
}
- (void)updateTouchPoints:(NSDictionary<NSValue *, NSValue *> *)points {
    if (!self.active || !self.showsTouchPoints) return;
    for (NSValue *key in self.rings.allKeys) if (!points[key]) {
        [self retireRing:self.rings[key]]; [self.rings removeObjectForKey:key];
    }
    [CATransaction begin]; [CATransaction setDisableActions:YES];
    for (NSValue *key in points) {
        CGPoint point = points[key].CGPointValue;
        if (!isfinite(point.x) || !isfinite(point.y)) continue;
        CAShapeLayer *ring = self.rings[key];
        if (!ring) { if (self.rings.count >= 5) break; ring = [self ringAtPoint:point]; self.rings[key] = ring; }
        ring.position = point;
    }
    [CATransaction commit];
}
- (void)clickAtPoint:(CGPoint)point {
    if (!self.active || (self.touchesAllowed && !self.touchesAllowed())) return;
    [self emitHaptic:NO];
    if (!self.showsTouchPoints || !isfinite(point.x) || !isfinite(point.y)) return;
    [self.pulse removeAllAnimations]; [self.pulse removeFromSuperlayer];
    CAShapeLayer *pulse = [self ringAtPoint:point]; self.pulse = pulse;
    [CATransaction begin]; [CATransaction setAnimationDuration:.18];
    [CATransaction setCompletionBlock:^{ [pulse removeFromSuperlayer]; }];
    pulse.opacity = 0;
    if (![self reduceMotion]) pulse.transform = CATransform3DMakeScale(1.2, 1.2, 1);
    [CATransaction commit];
}
- (void)setDragging:(BOOL)dragging {
    if (_dragging == dragging) return;
    _dragging = dragging; [self restyle];
    if (dragging && (!self.touchesAllowed || self.touchesAllowed())) [self emitHaptic:YES];
}
- (void)clearRings {
    for (CAShapeLayer *ring in [self.rings.allValues arrayByAddingObjectsFromArray:self.retiringRings.allObjects]) {
        [ring removeAllAnimations]; [ring removeFromSuperlayer];
    }
    [self.rings removeAllObjects]; [self.retiringRings removeAllObjects];
    [self.pulse removeAllAnimations]; [self.pulse removeFromSuperlayer]; self.pulse = nil;
}
- (void)cancelTouches {
    BOOL enabled = self.touchObserver.enabled;
    self.touchObserver.enabled = NO;
    [((CompanionVNCTrackpadTouchObserver *)self.touchObserver).fingers removeAllObjects];
    [self setDragging:NO]; [self clearRings]; self.touchObserver.enabled = enabled;
}
@end
