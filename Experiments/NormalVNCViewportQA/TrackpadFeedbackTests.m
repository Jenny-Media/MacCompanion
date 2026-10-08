#import <XCTest/XCTest.h>
#import "CompanionVNCTrackpadFeedback.h"
#import "CompanionVNCViewer.h"

@interface CompanionVNCTrackpadFeedback (Testing)
- (void)updateTouchPoints:(NSDictionary *)points;
- (BOOL)reduceMotion;
@end
@interface FeedbackImpact : UIImpactFeedbackGenerator
@property NSUInteger count;
@end
@implementation FeedbackImpact
- (void)prepare {}
- (void)impactOccurred { self.count++; }
@end
@interface MotionFeedback : CompanionVNCTrackpadFeedback
@end
@implementation MotionFeedback
- (BOOL)reduceMotion { return YES; }
@end
@interface FeedbackFinger : UITouch
@property CGPoint point;
@end
@implementation FeedbackFinger
- (UITouchType)type { return UITouchTypeDirect; }
- (CGPoint)locationInView:(UIView *)view { return self.point; }
@end
@interface UIGestureRecognizer (TouchObserverTesting)
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
@end
@interface CompanionVNCViewer (FeedbackTesting)
- (void)updateConnectionChrome;
- (void)setTrackpadModeEnabled:(BOOL)enabled;
- (void)clickAt:(UIGestureRecognizer *)gesture;
- (void)holdAt:(UILongPressGestureRecognizer *)gesture;
@end
@interface FeedbackConnection : CompanionVNCSession
@property BOOL acceptsClick;
@property NSUInteger clicks;
@end
@implementation FeedbackConnection
- (BOOL)connected { return YES; }
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { if (self.acceptsClick) self.clicks++; return self.acceptsClick; }
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask {}
@end
@interface FeedbackHold : UILongPressGestureRecognizer
@property UIGestureRecognizerState sampleState;
@end
@implementation FeedbackHold
- (UIGestureRecognizerState)state { return self.sampleState; }
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(100,100); }
@end

@interface TrackpadFeedbackTests : XCTestCase
@end
@implementation TrackpadFeedbackTests
- (void)testObserverDoesNotBlockRecognizersAndTracksTwoFingersThroughPartialLiftAndCancellation {
    UIView *surface = [[UIView alloc] initWithFrame:CGRectMake(0,0,400,600)];
    UIPanGestureRecognizer *pan = [UIPanGestureRecognizer new]; [surface addGestureRecognizer:pan];
    UIPinchGestureRecognizer *pinch = [UIPinchGestureRecognizer new]; [surface addGestureRecognizer:pinch];
    CompanionVNCTrackpadFeedback *feedback = [[CompanionVNCTrackpadFeedback alloc] initWithSurface:surface];
    feedback.frame = surface.bounds; [surface addSubview:feedback]; feedback.active = YES; feedback.hapticsEnabled = NO;
    UIGestureRecognizer *observer = [feedback valueForKey:@"touchObserver"];
    XCTAssertFalse(feedback.userInteractionEnabled); XCTAssertTrue(feedback.accessibilityElementsHidden);
    XCTAssertFalse(observer.cancelsTouchesInView); XCTAssertFalse(observer.delaysTouchesBegan); XCTAssertFalse(observer.delaysTouchesEnded);
    for (UIGestureRecognizer *input in @[pan,pinch]) {
        XCTAssertFalse([observer canPreventGestureRecognizer:input]); XCTAssertFalse([observer canBePreventedByGestureRecognizer:input]);
    }
    FeedbackFinger *one = [FeedbackFinger new], *two = [FeedbackFinger new];
    one.point = CGPointMake(80,100); two.point = CGPointMake(200,100);
    [observer touchesBegan:[NSSet setWithArray:@[one,two]] withEvent:nil];
    XCTAssertEqual(observer.state,UIGestureRecognizerStatePossible);
    NSDictionary *rings = [feedback valueForKey:@"rings"]; XCTAssertEqual(rings.count,2);
    two.point = CGPointMake(240,140); [observer touchesMoved:[NSSet setWithObject:two] withEvent:nil];
    CAShapeLayer *ring = rings[[NSValue valueWithNonretainedObject:two]];
    XCTAssertTrue(CGPointEqualToPoint(ring.position,two.point));
    XCTAssertEqual(observer.state,UIGestureRecognizerStatePossible);
    [observer touchesEnded:[NSSet setWithObject:one] withEvent:nil]; XCTAssertEqual(rings.count,1);
    [observer touchesCancelled:[NSSet setWithObject:two] withEvent:nil];
    XCTAssertEqual(rings.count,0); XCTAssertEqual(((NSSet *)[observer valueForKey:@"fingers"]).count,0);
    XCTAssertEqual(feedback.layer.sublayers.count,0);
}
- (void)testIndependentTogglesOneHapticPerDragAndReducedMotionPulse {
    UIView *surface = [UIView new];
    MotionFeedback *feedback = [[MotionFeedback alloc] initWithSurface:surface]; feedback.active = YES;
    FeedbackImpact *click = [FeedbackImpact new], *drag = [FeedbackImpact new];
    [feedback setValue:click forKey:@"clickFeedback"]; [feedback setValue:drag forKey:@"dragFeedback"];
    NSDictionary *point = @{@1: [NSValue valueWithCGPoint:CGPointMake(80,90)]};
    [feedback updateTouchPoints:point];
    for (NSUInteger i=0;i<100;i++) [feedback updateTouchPoints:point];
    XCTAssertEqual(click.count,0); XCTAssertEqual(drag.count,0);
    [feedback setDragging:YES]; for (NSUInteger i=0;i<100;i++) [feedback setDragging:YES];
    XCTAssertEqual(drag.count,1);
    CAShapeLayer *held = ((NSDictionary *)[feedback valueForKey:@"rings"]).allValues.firstObject;
    XCTAssertEqual(held.lineWidth,3);
    [feedback setDragging:NO]; XCTAssertEqual(held.lineWidth,1.5);
    [feedback clickAtPoint:CGPointMake(80,90)]; XCTAssertEqual(click.count,1);
    CAShapeLayer *pulse = [feedback valueForKey:@"pulse"];
    XCTAssertTrue(CATransform3DIsIdentity(pulse.transform),@"Reduce Motion removes the expanding pulse");
    feedback.showsTouchPoints = NO; XCTAssertEqual(feedback.layer.sublayers.count,0);
    [feedback clickAtPoint:CGPointZero]; XCTAssertEqual(click.count,2);
    feedback.hapticsEnabled = NO; feedback.showsTouchPoints = YES;
    [feedback updateTouchPoints:point]; [feedback clickAtPoint:CGPointZero]; [feedback setDragging:YES];
    XCTAssertEqual(click.count,2); XCTAssertEqual(drag.count,1);
    XCTAssertEqual(((NSDictionary *)[feedback valueForKey:@"rings"]).count,1);
    feedback.active = NO; XCTAssertEqual(feedback.layer.sublayers.count,0);
    [feedback clickAtPoint:CGPointZero]; XCTAssertEqual(feedback.layer.sublayers.count,0);
}
- (void)testViewerClickAdmissionDragTransitionsModeChangesAndBackgroundClearFeedback {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; viewer.inputOnly = YES; [viewer loadViewIfNeeded];
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *window in scene.windows) if (window.isKeyWindow) previous = window;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer; [window makeKeyAndVisible];
    FeedbackConnection *session = [FeedbackConnection new]; viewer.session = session;
    [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,1000,1000)] forKey:@"activeCrop"];
    ((UIView *)[viewer valueForKey:@"login"]).hidden = YES; [viewer updateConnectionChrome];
    CompanionVNCTrackpadFeedback *feedback = [viewer valueForKey:@"trackpadFeedback"];
    FeedbackImpact *click = [FeedbackImpact new], *drag = [FeedbackImpact new];
    [feedback setValue:click forKey:@"clickFeedback"]; [feedback setValue:drag forKey:@"dragFeedback"];
    UITapGestureRecognizer *tap = [UITapGestureRecognizer new]; [[viewer valueForKey:@"canvas"] addGestureRecognizer:tap];
    session.acceptsClick = NO; [viewer clickAt:tap]; XCTAssertEqual(click.count,0);
    session.acceptsClick = YES; [viewer clickAt:tap]; XCTAssertEqual(click.count,1); XCTAssertEqual(session.clicks,1);
    FeedbackHold *hold = [FeedbackHold new]; [[viewer valueForKey:@"canvas"] addGestureRecognizer:hold];
    hold.sampleState = UIGestureRecognizerStateBegan; [viewer holdAt:hold];
    hold.sampleState = UIGestureRecognizerStateChanged; [viewer holdAt:hold]; XCTAssertEqual(drag.count,1);
    hold.sampleState = UIGestureRecognizerStateEnded; [viewer holdAt:hold]; XCTAssertFalse([[feedback valueForKey:@"dragging"] boolValue]);
    [feedback updateTouchPoints:@{@1:[NSValue valueWithCGPoint:CGPointMake(100,100)]}];
    [viewer setTrackpadModeEnabled:NO]; XCTAssertFalse(feedback.active); XCTAssertEqual(feedback.layer.sublayers.count,0);
    [viewer setTrackpadModeEnabled:YES]; XCTAssertTrue(feedback.active);
    for (NSNumber *style in @[@(UIUserInterfaceStyleLight), @(UIUserInterfaceStyleDark)]) {
        window.overrideUserInterfaceStyle = style.integerValue; [window layoutIfNeeded];
        XCTAssertTrue(CGRectEqualToRect([feedback convertRect:feedback.bounds toView:viewer.view], ((UIView *)[viewer valueForKey:@"canvas"]).frame));
        [feedback updateTouchPoints:@{@1:[NSValue valueWithCGPoint:CGPointMake(feedback.bounds.size.width * .35,feedback.bounds.size.height * .35)],
                                     @2:[NSValue valueWithCGPoint:CGPointMake(feedback.bounds.size.width * .65,feedback.bounds.size.height * .35)]}];
        UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES];
        }];
        XCTAttachment *attachment = [XCTAttachment attachmentWithImage:image];
        attachment.name = style.integerValue == UIUserInterfaceStyleDark ? @"trackpad-touch-feedback-dark" : @"trackpad-touch-feedback-light";
        attachment.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:attachment];
    }
    [feedback updateTouchPoints:@{@1:[NSValue valueWithCGPoint:CGPointMake(100,100)]}];
    [viewer background]; XCTAssertFalse(feedback.active); XCTAssertEqual(feedback.layer.sublayers.count,0);
    [viewer stopViewer];
    window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
}
@end
