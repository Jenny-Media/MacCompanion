#import <XCTest/XCTest.h>
#import "CompanionVNCControls.h"
#import "CompanionVNCMenu.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCDirectConnection.h"
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCControls (Testing)
- (void)open;
- (void)slide:(UILongPressGestureRecognizer *)gesture;
- (void)pressDown;
- (void)pressUp;
- (void)chosen:(UIButton *)button;
- (void)emitFeedback:(NSString *)kind;
- (BOOL)reduceMotion;
@end
@interface CompanionVNCViewer (ControlsTesting)
- (void)frame:(UIImage *)frame;
- (void)performControlAction:(NSDictionary *)action;
- (BOOL)pointerForGesture:(UIGestureRecognizer *)gesture point:(CGPoint *)point;
- (void)setTrackpadModeEnabled:(BOOL)enabled;
- (void)updateConnectionChrome;
- (void)keyboardFrame:(NSNotification *)notification;
- (void)keyboard;
- (CGPoint)viewportCenter;
- (void)applyViewportRatio:(CGFloat)ratio center:(CGPoint)center;
- (void)selectDisplay:(NSDictionary *)display;
- (void)dragAt:(UIPanGestureRecognizer *)gesture;
- (void)holdAt:(UILongPressGestureRecognizer *)gesture;
- (void)followTrackpadPointer:(CGPoint)point;
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known;
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView;
- (void)scrollViewWillBeginZooming:(UIScrollView *)scrollView withView:(UIView *)view;
- (void)fitDesktop;
@end
@interface ControlsHold : UILongPressGestureRecognizer
@property UIGestureRecognizerState sampleState;
@property CGPoint point;
@property UIView *reference;
@end
@implementation ControlsHold
- (UIGestureRecognizerState)state { return self.sampleState; }
- (CGPoint)locationInView:(UIView *)view { return [self.reference convertPoint:self.point toView:view]; }
@end
@interface ControlsPan : UIPanGestureRecognizer
@property UIGestureRecognizerState sampleState;
@property CGPoint delta, velocity;
@end
@implementation ControlsPan
- (UIGestureRecognizerState)state { return self.sampleState; }
- (CGPoint)translationInView:(UIView *)view { return self.delta; }
- (CGPoint)velocityInView:(UIView *)view { return self.velocity; }
@end
@interface ControlsSession : CompanionVNCSession
@property NSMutableArray *groups;
@property NSMutableArray *pointers;
@end
@implementation ControlsSession
- (BOOL)connected { return YES; }
- (void)keyEvents:(NSArray<NSDictionary *> *)events { [self.groups addObject:events]; }
- (BOOL)tryKeyEvents:(NSArray<NSDictionary *> *)events { [self.groups addObject:events]; return YES; }
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { [self.pointers addObject:@[@(x),@(y),@(mask)]]; }
@end
@interface FeedbackControls : CompanionVNCControls
@property NSMutableArray<NSString *> *feedbackEvents;
@property BOOL forceReducedMotion;
@end
@implementation FeedbackControls
- (void)emitFeedback:(NSString *)kind { [self.feedbackEvents addObject:kind]; }
- (BOOL)reduceMotion { return self.forceReducedMotion; }
@end
@interface SessionControlsTests : XCTestCase
@end
@implementation SessionControlsTests
- (void)testTerminalCategoriesSupportSlideCommitAndCancellationWithoutDesktopActions {
    CompanionVNCControls *controls = [[CompanionVNCControls alloc] initWithFrame:CGRectMake(0,0,440,956)];
    controls.categoryActions = @[@{@"kind":@"inputMenu",@"title":@"Keyboard & Input",@"symbol":@"keyboard"},
        @{@"kind":@"appearance",@"title":@"Appearance",@"symbol":@"circle.lefthalf.filled"},
        @{@"kind":@"session",@"title":@"Session",@"symbol":@"network"}];
    controls.quickActions = @[@{@"kind":@"keyboard",@"title":@"Show Keyboard",@"enabled":@YES}];
    __block NSMutableArray *committed = [NSMutableArray new]; controls.actionHandler = ^(NSDictionary *action) { [committed addObject:action[@"kind"]]; };
    ControlsHold *gesture = [ControlsHold new]; gesture.reference = controls;
    gesture.sampleState = UIGestureRecognizerStateBegan; [controls slide:gesture];
    NSArray *choices = [controls valueForKey:@"choices"]; XCTAssertEqual(choices.count,4);
    UIButton *appearance = choices[2];
    gesture.point = [appearance convertPoint:CGPointMake(CGRectGetMidX(appearance.bounds),CGRectGetMidY(appearance.bounds)) toView:controls];
    gesture.sampleState = UIGestureRecognizerStateChanged; [controls slide:gesture]; XCTAssertEqual(committed.count,0);
    gesture.sampleState = UIGestureRecognizerStateEnded; [controls slide:gesture]; XCTAssertEqualObjects(committed,(@[@"appearance"]));
    gesture.sampleState = UIGestureRecognizerStateBegan; [controls slide:gesture];
    gesture.sampleState = UIGestureRecognizerStateCancelled; [controls slide:gesture]; XCTAssertEqual(committed.count,1);
    XCTAssertNil([controls hitTest:CGPointMake(10,10) withEvent:nil]);
}
- (void)withFollowViewer:(void (^)(CompanionVNCViewer *, ControlsSession *))body {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded]; viewer.pointerSpeed = 1;
    ControlsSession *session = [ControlsSession new]; session.pointers = [NSMutableArray new]; viewer.session = session;
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer; [window makeKeyAndVisible];
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = 1;
    UIImage *frame = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1600,1600) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0,0,1600,1600));
    }];
    [viewer frame:frame]; ((UIView *)[viewer valueForKey:@"login"]).hidden = YES; [viewer updateConnectionChrome]; [window layoutIfNeeded];
    [viewer setTrackpadModeEnabled:YES]; [viewer applyViewportRatio:4 center:CGPointMake(.5,.5)];
    body(viewer, session);
    [viewer stopViewer]; window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
}
- (void)testTrackpadFollowingKeepsCursorVisibleWithoutChangingMouseDeltasOrAddingEvents {
    [self withFollowViewer:^(CompanionVNCViewer *viewer, ControlsSession *session) {
        UIScrollView *canvas = [viewer valueForKey:@"canvas"]; UIImageView *image = [viewer valueForKey:@"image"];
        CGPoint origin = [image convertPoint:CGPointMake(CGRectGetMidX(canvas.bounds),CGRectGetMidY(canvas.bounds)) fromView:canvas];
        origin.x = floor(origin.x); origin.y = floor(origin.y);
        [viewer receivedCursor:nil hotspot:CGPointZero position:origin known:YES];
        CGFloat zoom = canvas.zoomScale; CGPoint offset = canvas.contentOffset;
        // Move beyond the visible edge in portrait and landscape alike.
        // A fixed 300-pixel movement can remain visible on a wide canvas.
        CGFloat movement = MAX(300, ceil(canvas.bounds.size.width / zoom * .6));
        ControlsPan *pan = [ControlsPan new]; pan.sampleState = UIGestureRecognizerStateBegan; [viewer dragAt:pan];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset));
        pan.sampleState = UIGestureRecognizerStateChanged; pan.delta = CGPointMake(movement / 2,0); [viewer dragAt:pan];
        XCTAssertGreaterThan(canvas.contentOffset.x,offset.x);
        XCTAssertEqualObjects(session.pointers.lastObject[0],@(origin.x+movement));
        XCTAssertFalse(((UIView *)[viewer valueForKey:@"cursorIndicator"]).hidden);
        CGPoint moved = canvas.contentOffset;
        [viewer receivedCursor:nil hotspot:CGPointZero position:origin known:YES];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,moved)); // delayed server notification cannot pan
        pan.delta = CGPointMake(movement / 2 + 20,0); [viewer dragAt:pan];
        XCTAssertEqualObjects(session.pointers.lastObject[0],@(origin.x+movement+40));
        XCTAssertEqual(session.pointers.count,3); XCTAssertEqual(canvas.zoomScale,zoom);
        XCTAssertEqual([[viewer.session valueForKey:@"connections"] unsignedIntegerValue],0);
    }];
}
- (void)testHeldDragUsesFixedCoordinatesWhileTheViewportFollows {
    [self withFollowViewer:^(CompanionVNCViewer *viewer, ControlsSession *session) {
        UIScrollView *canvas = [viewer valueForKey:@"canvas"];
        CGFloat movement = MAX(300, ceil(canvas.bounds.size.width / canvas.zoomScale * .6));
        [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(800,800) known:YES];
        ControlsHold *hold = [ControlsHold new]; hold.reference = viewer.view; hold.point = CGPointMake(100,200);
        hold.sampleState = UIGestureRecognizerStateBegan; [viewer holdAt:hold]; CGPoint offset = canvas.contentOffset;
        hold.sampleState = UIGestureRecognizerStateChanged; hold.point = CGPointMake(100 + movement / 2,200); [viewer holdAt:hold];
        XCTAssertGreaterThan(canvas.contentOffset.x,offset.x); XCTAssertEqualObjects(session.pointers.lastObject,(@[@(800+movement),@800,@1]));
        [viewer holdAt:hold]; XCTAssertEqualObjects(session.pointers.lastObject,(@[@(800+movement),@800,@1]));
        hold.sampleState = UIGestureRecognizerStateEnded; [viewer holdAt:hold];
        XCTAssertEqualObjects(session.pointers.lastObject,(@[@(800+movement),@800,@0])); XCTAssertEqual(session.pointers.count,4);
    }];
}
- (void)testFollowingRespectsManualViewportNavigationOptOutModeAndLifecycle {
    [self withFollowViewer:^(CompanionVNCViewer *viewer, ControlsSession *session) {
        UIScrollView *canvas = [viewer valueForKey:@"canvas"]; CGPoint offset = canvas.contentOffset;
        CGPoint target = CGPointMake(1300,1300);
        [viewer scrollViewWillBeginDragging:canvas]; [viewer followTrackpadPointer:target];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset));
        ControlsPan *pan = [ControlsPan new]; pan.sampleState = UIGestureRecognizerStateBegan; CGPoint p;
        [viewer pointerForGesture:pan point:&p]; [viewer followTrackpadPointer:target];
        XCTAssertFalse(CGPointEqualToPoint(canvas.contentOffset,offset));
        [viewer applyViewportRatio:4 center:CGPointMake(.5,.5)]; offset = canvas.contentOffset;
        [viewer scrollViewWillBeginZooming:canvas withView:[viewer valueForKey:@"image"]]; [viewer followTrackpadPointer:target];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset)); [viewer pointerForGesture:pan point:&p];
        viewer.followCursorEnabled = NO; [viewer followTrackpadPointer:target]; XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset));
        viewer.followCursorEnabled = YES; [viewer setTrackpadModeEnabled:NO]; [viewer followTrackpadPointer:target];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset)); [viewer setTrackpadModeEnabled:YES];
        [viewer setValue:@YES forKey:@"checkingResume"]; [viewer followTrackpadPointer:target]; XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset));
        [viewer setValue:@NO forKey:@"checkingResume"]; [viewer setValue:@NO forKey:@"foreground"]; [viewer followTrackpadPointer:target];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset)); [viewer setValue:@YES forKey:@"foreground"];
        [viewer fitDesktop]; offset = canvas.contentOffset; [viewer followTrackpadPointer:target];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset)); XCTAssertEqual(canvas.zoomScale,canvas.minimumZoomScale);
        XCTAssertEqual(session.pointers.count,0);
    }];
}
- (void)testFollowingUsesTheKeyboardViewportAndKeepsTheSelectedDisplayCrop {
    [self withFollowViewer:^(CompanionVNCViewer *viewer, ControlsSession *session) {
        NSDictionary *display = @{@"id":@2,@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
        viewer.displayLayout = @{@"aspectRatio":@1,@"views":@[display]}; [viewer selectDisplay:display];
        [viewer applyViewportRatio:4 center:CGPointMake(.5,.5)];
        [self deliverKeyboardRect:CGRectMake(0,viewer.view.bounds.size.height-300,viewer.view.bounds.size.width,300) toViewer:viewer];
        UIScrollView *canvas = [viewer valueForKey:@"canvas"]; CGFloat zoom = canvas.zoomScale;
        [viewer followTrackpadPointer:CGPointMake(1200,1300)];
        [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(1200,1300) known:YES];
        XCTAssertFalse(((UIView *)[viewer valueForKey:@"cursorIndicator"]).hidden);
        XCTAssertEqualObjects([viewer valueForKey:@"selectedDisplay"][@"id"],@2); XCTAssertEqual(canvas.zoomScale,zoom);
        XCTAssertGreaterThanOrEqual(canvas.contentOffset.x,0); XCTAssertGreaterThanOrEqual(canvas.contentOffset.y,0);
        XCTAssertLessThanOrEqual(canvas.contentOffset.x,MAX(0,canvas.contentSize.width-canvas.bounds.size.width));
        XCTAssertLessThanOrEqual(canvas.contentOffset.y,MAX(0,canvas.contentSize.height-canvas.bounds.size.height));
        CGPoint offset = canvas.contentOffset; [viewer followTrackpadPointer:CGPointMake(100,100)];
        XCTAssertTrue(CGPointEqualToPoint(canvas.contentOffset,offset)); XCTAssertEqual(session.pointers.count,0);
    }];
}
- (void)deliverKeyboardRect:(CGRect)rect toViewer:(CompanionVNCViewer *)viewer {
    CGRect screen = [viewer.view convertRect:rect toView:nil];
    [viewer keyboardFrame:[NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:nil userInfo:@{
        UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:screen], UIKeyboardAnimationDurationUserInfoKey:@0,
        UIKeyboardAnimationCurveUserInfoKey:@(UIViewAnimationCurveEaseInOut)}]];
}
- (void)testKeyboardReflowsFitAndZoomThenRestoresTheOriginalViewport {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer; [window makeKeyAndVisible];
    UIImage *frame = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(800,1600)] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
    [viewer frame:frame]; ((UIView *)[viewer valueForKey:@"login"]).hidden = YES; [viewer updateConnectionChrome]; [window layoutIfNeeded];
    UIScrollView *canvas = [viewer valueForKey:@"canvas"]; UIView *toolbar = [viewer valueForKey:@"toolbar"];
    for (NSNumber *ratio in @[@1,@3]) {
        [viewer applyViewportRatio:ratio.doubleValue center:CGPointMake(.55,.6)];
        CGFloat original = canvas.zoomScale; CGPoint center = [viewer viewportCenter]; CGFloat height = canvas.bounds.size.height;
        CGFloat keyboardTop = viewer.view.bounds.size.height - 300;
        [self deliverKeyboardRect:CGRectMake(0,keyboardTop,viewer.view.bounds.size.width,300) toViewer:viewer];
        XCTAssertLessThan(canvas.bounds.size.height, height); XCTAssertLessThanOrEqual(CGRectGetMaxY(toolbar.frame), keyboardTop);
        XCTAssertLessThanOrEqual(CGRectGetMaxY(canvas.frame), CGRectGetMinY(toolbar.frame));
        XCTAssertEqualWithAccuracy(canvas.zoomScale/canvas.minimumZoomScale,ratio.doubleValue,.01);
        [self deliverKeyboardRect:CGRectMake(0,keyboardTop-60,viewer.view.bounds.size.width,360) toViewer:viewer];
        [self deliverKeyboardRect:CGRectMake(0,viewer.view.bounds.size.height,viewer.view.bounds.size.width,300) toViewer:viewer];
        XCTAssertEqualWithAccuracy(canvas.bounds.size.height,height,.01); XCTAssertEqualWithAccuracy(canvas.zoomScale,original,.01);
        CGPoint restored = [viewer viewportCenter]; XCTAssertEqualWithAccuracy(restored.x,center.x,.01); XCTAssertEqualWithAccuracy(restored.y,center.y,.01);
    }
    CGFloat height = canvas.bounds.size.height;
    [self deliverKeyboardRect:CGRectMake(100,100,180,180) toViewer:viewer]; XCTAssertEqualWithAccuracy(canvas.bounds.size.height,height,.01);
    XCTAssertEqual([[viewer.session valueForKey:@"connections"] unsignedIntegerValue],0);
    [viewer stopViewer]; window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
}
- (void)testKeyboardDismissalDoesNotRestoreAnObsoleteDisplayCrop {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer; [window makeKeyAndVisible];
    UIImage *frame = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(800,1600)] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
    [viewer frame:frame]; ((UIView *)[viewer valueForKey:@"login"]).hidden = YES; [viewer updateConnectionChrome]; [window layoutIfNeeded];
    [viewer applyViewportRatio:3 center:CGPointMake(.5,.5)];
    [self deliverKeyboardRect:CGRectMake(0,viewer.view.bounds.size.height-300,viewer.view.bounds.size.width,300) toViewer:viewer];
    NSDictionary *display = @{@"id":@3,@"title":@"Display 3",@"x":@0,@"y":@0,@"width":@1,@"height":@.5};
    viewer.displayLayout = @{@"aspectRatio":@.5,@"views":@[display]}; [viewer selectDisplay:display];
    [self deliverKeyboardRect:CGRectMake(0,viewer.view.bounds.size.height,viewer.view.bounds.size.width,300) toViewer:viewer];
    XCTAssertEqualObjects([viewer valueForKey:@"selectedDisplay"][@"id"],@3);
    UIScrollView *canvas = [viewer valueForKey:@"canvas"]; XCTAssertEqualWithAccuracy(canvas.zoomScale,canvas.minimumZoomScale,.01);
    XCTAssertEqual(((CGRect)[[viewer valueForKey:@"activeCrop"] CGRectValue]).size.height,CGImageGetHeight(frame.CGImage)/2);
    [viewer stopViewer]; window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
}
- (void)testKeyboardButtonReflectsActualInputFocusAndDismissal {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer; [window makeKeyAndVisible];
    UIButton *button = [viewer valueForKey:@"keyboardButton"]; UITextView *input = [viewer valueForKey:@"input"];
    XCTAssertEqualObjects(button.accessibilityLabel,@"Show Keyboard"); XCTAssertNotNil(button.currentImage);
    [viewer keyboard]; XCTAssertTrue(input.isFirstResponder); XCTAssertEqualObjects(button.accessibilityLabel,@"Hide Keyboard"); XCTAssertNotNil(button.currentImage);
    [viewer keyboard]; XCTAssertFalse(input.isFirstResponder); XCTAssertEqualObjects(button.accessibilityLabel,@"Show Keyboard");
    [viewer stopViewer]; window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
}
- (void)testSavedDisplayWaitsForVerifiedGeometryAndMissingIDFitsAllDisplays {
    NSDictionary *display = @{@"id":@2,@"title":@"Display 2",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
    UIImage *frame = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(800,600)] imageWithActions:^(UIGraphicsImageRendererContext *context) {}];
    for (NSNumber *saved in @[@2,@99]) {
        CompanionVNCViewer *viewer = [CompanionVNCViewer new]; viewer.restoredDisplayID = saved; [viewer loadViewIfNeeded];
        viewer.displayLayout = @{@"aspectRatio":@1,@"views":@[display]}; [viewer frame:frame];
        XCTAssertNil([viewer valueForKey:@"selectedDisplay"]); XCTAssertEqualObjects(viewer.restoredDisplayID, saved);
        viewer.displayLayout = @{@"aspectRatio":@(800.0/600),@"views":@[display]};
        NSDictionary *selection = [viewer valueForKey:@"selectedDisplay"];
        if (saved.intValue == 2) XCTAssertEqualObjects(selection[@"id"], saved); else XCTAssertNil(selection);
        XCTAssertNil(viewer.restoredDisplayID); [viewer stopViewer];
    }
}
- (void)testFloatingControlsFitPortraitLandscapeAndKeyboardAndCaptureSyntheticPreview {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; viewer.macName = @"Test Mac";
    viewer.quickActions = @[@{@"kind":@"mode",@"title":@"Mouse Mode",@"enabled":@YES},@{@"kind":@"fit",@"title":@"Fit View",@"enabled":@YES},@{@"kind":@"rightClick",@"title":@"Right Click",@"enabled":@YES}];
    [viewer loadViewIfNeeded]; viewer.overrideUserInterfaceStyle = UIUserInterfaceStyleDark;
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer; [window makeKeyAndVisible];
    UIImage *frame = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1600,1000)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.systemIndigoColor setFill]; UIRectFill(CGRectMake(0,0,1600,1000));
        [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(80,80,1440,840));
    }];
    [viewer frame:frame]; ((UIView *)[viewer valueForKey:@"login"]).hidden = YES; [viewer updateConnectionChrome];
    CompanionVNCControls *controls = [viewer valueForKey:@"controls"];
    [window layoutIfNeeded]; [controls open];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
    UIImage *snapshot = [[[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES]; }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot]; attachment.name = @"Synthetic floating controls"; attachment.lifetime = XCTAttachmentLifetimeKeepAlways; [self addAttachment:attachment];
    for (NSValue *size in @[[NSValue valueWithCGSize:CGSizeMake(440,956)],[NSValue valueWithCGSize:CGSizeMake(956,440)]]) {
        controls.frame = (CGRect){CGPointZero,size.CGSizeValue}; controls.bottomInset = 8; [controls setNeedsLayout]; [controls layoutIfNeeded];
        UIView *panel = [controls valueForKey:@"panel"]; XCTAssertTrue(CGRectContainsRect(controls.bounds,panel.frame));
    }
    controls.frame = CGRectMake(0,0,440,956); controls.bottomInset = 350; [controls setNeedsLayout]; [controls layoutIfNeeded];
    XCTAssertTrue(CGRectContainsRect(controls.bounds, ((UIView *)[controls valueForKey:@"panel"]).frame));
    [viewer stopViewer]; window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
}
- (void)testPressSlideCommitsOnlyOnReleaseAndCancelsOutsideOrOnBackgroundClose {
    CompanionVNCControls *controls = [[CompanionVNCControls alloc] initWithFrame:CGRectMake(0, 0, 440, 956)];
    controls.macName = @"Test Mac"; controls.quickActions = @[@{@"kind": @"fit", @"title": @"Fit View", @"enabled": @YES}];
    __block NSUInteger calls = 0;
    controls.actionHandler = ^(NSDictionary *item) { XCTAssertEqualObjects(item[@"kind"], @"fit"); calls++; };
    ControlsHold *gesture = [ControlsHold new]; gesture.reference = controls;
    gesture.sampleState = UIGestureRecognizerStateBegan; [controls slide:gesture];
    UIButton *choice = ((NSArray *)[controls valueForKey:@"choices"])[0];
    gesture.point = [choice convertPoint:CGPointMake(20, 20) toView:controls];
    gesture.sampleState = UIGestureRecognizerStateChanged; [controls slide:gesture]; XCTAssertEqual(calls, 0);
    gesture.sampleState = UIGestureRecognizerStateEnded; [controls slide:gesture]; XCTAssertEqual(calls, 1);
    gesture.sampleState = UIGestureRecognizerStateBegan; [controls slide:gesture];
    gesture.point = CGPointMake(0, 0); gesture.sampleState = UIGestureRecognizerStateEnded; [controls slide:gesture]; XCTAssertEqual(calls, 1);
    gesture.sampleState = UIGestureRecognizerStateBegan; [controls slide:gesture]; [controls close];
    gesture.sampleState = UIGestureRecognizerStateEnded; [controls slide:gesture]; XCTAssertEqual(calls, 1);
    [controls open];
    XCTAssertEqual([controls hitTest:CGPointMake(0, 0) withEvent:nil], controls); // outside dismiss is locally captured
    [controls close]; XCTAssertNil([controls hitTest:CGPointMake(0, 0) withEvent:nil]);
}
- (void)testQuickActionsStayReachableWithMaximumActionsAndInputOnlyDisablesVideoChoices {
    CompanionVNCControls *controls = [[CompanionVNCControls alloc] initWithFrame:CGRectMake(0,0,956,440)];
    NSMutableArray *actions = [NSMutableArray new];
    for (NSUInteger i=0;i<15;i++) [actions addObject:@{@"kind": i == 0 ? @"fit" : @"text", @"title": @"Quick Action", @"enabled": @YES}];
    controls.quickActions = actions; [controls open];
    NSArray<UIButton *> *choices = [controls valueForKey:@"choices"];
    UIScrollView *scroll = [controls valueForKey:@"scroll"];
    XCTAssertTrue(CGRectContainsRect(scroll.bounds, choices.firstObject.frame));
    XCTAssertEqual(choices.count,18); // only three category entries outside quick actions
    [controls close]; controls.inputOnly = YES; [controls open];
    choices = [controls valueForKey:@"choices"]; XCTAssertFalse(choices.firstObject.enabled);
    [controls close];
}
- (void)testGroupedMenusNavigateBackWithoutReplacingSessionAndDisabledChoicesDoNotRun {
    [self withFollowViewer:^(CompanionVNCViewer *viewer, ControlsSession *owner) {
        [viewer performControlAction:@{@"kind": @"inputMenu"}];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.35]];
        UINavigationController *navigation = (id)viewer.presentedViewController;
        XCTAssertTrue([navigation isKindOfClass:UINavigationController.class]);
        // UIKit's presentation duration varies with the Simulator/toolchain.
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:3];
        while (navigation.transitionCoordinator && deadline.timeIntervalSinceNow > 0) {
            [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
        }
        CompanionVNCMenu *input = (id)navigation.topViewController; [input loadViewIfNeeded];
        [input tableView:input.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:1]]; // Extra Keys
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.35]];
        XCTAssertEqual(navigation.viewControllers.count,2);
        [navigation popViewControllerAnimated:NO]; XCTAssertEqual(navigation.topViewController,input);
        XCTAssertEqual(viewer.session,owner); XCTAssertEqual(owner.groups.count,0);
        [viewer dismissViewControllerAnimated:NO completion:nil];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.35]];
        viewer.inputOnly = YES;
        [viewer performControlAction:@{@"kind": @"viewMenu"}];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.35]];
        navigation = (id)viewer.presentedViewController;
        CompanionVNCMenu *view = (id)navigation.topViewController; [view loadViewIfNeeded];
        XCTAssertTrue([view.sections.firstObject[@"items"][0][@"disabled"] boolValue]);
        [view tableView:view.tableView didSelectRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
        XCTAssertEqual(navigation.viewControllers.count,1); XCTAssertEqual(viewer.session,owner);
        [viewer dismissViewControllerAnimated:NO completion:nil];
    }];
}
- (void)testTrackpadAccelerationUsesIncrementalDeltasAndIsIndependentOfZoom {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded]; viewer.pointerSpeed = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(800, 600)];
    [viewer frame:[renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [UIColor.grayColor setFill]; UIRectFill(CGRectMake(0,0,800,600)); }]];
    [viewer setTrackpadModeEnabled:YES];
    ControlsPan *pan = [ControlsPan new]; CGPoint p;
    pan.sampleState = UIGestureRecognizerStateBegan; pan.delta = CGPointZero; [viewer pointerForGesture:pan point:&p]; CGPoint origin = p;
    pan.sampleState = UIGestureRecognizerStateChanged; pan.delta = CGPointMake(10, 0); pan.velocity = CGPointZero; [viewer pointerForGesture:pan point:&p];
    XCTAssertEqualWithAccuracy(p.x-origin.x, 20, .01); CGPoint slow = p;
    pan.delta = CGPointMake(20, 0); pan.velocity = CGPointMake(600, 0); [viewer pointerForGesture:pan point:&p];
    XCTAssertGreaterThan(p.x-slow.x, 20); XCTAssertLessThan(p.x-slow.x, 60);
    viewer.pointerSpeed = .5; pan.sampleState = UIGestureRecognizerStateBegan; pan.delta = CGPointZero; [viewer pointerForGesture:pan point:&p]; origin = p;
    UIScrollView *canvas = [viewer valueForKey:@"canvas"]; canvas.zoomScale = 3;
    pan.sampleState = UIGestureRecognizerStateChanged; pan.delta = CGPointMake(10, 0); pan.velocity = CGPointZero; [viewer pointerForGesture:pan point:&p];
    XCTAssertEqualWithAccuracy(p.x-origin.x, 10, .01); [viewer stopViewer];
}
- (void)testCustomShortcutBalancesModifiersAndTextClearsArmedKeys {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    ControlsSession *session = [ControlsSession new]; session.groups = [NSMutableArray new]; viewer.session = session;
    [viewer performControlAction:@{@"kind": @"shortcut", @"key": @0x63, @"modifiers": @[@0xffeb, @0xffe1]}];
    NSArray *group = session.groups.lastObject; XCTAssertEqual(group.count, 6);
    NSMutableSet *held = [NSMutableSet new];
    for (NSDictionary *event in group) { if ([event[@"down"] boolValue]) [held addObject:event[@"key"]]; else [held removeObject:event[@"key"]]; }
    XCTAssertEqual(held.count, 0);
    [viewer performControlAction:@{@"kind": @"text", @"text": @"Test"}]; XCTAssertEqual(session.groups.count, 2); XCTAssertEqual(((NSArray *)session.groups.lastObject).count, 8);
    [viewer background]; NSUInteger count = session.groups.count;
    [viewer performControlAction:@{@"kind": @"text", @"text": @"Ignored"}]; XCTAssertEqual(session.groups.count, count); [viewer stopViewer];
}
- (void)testMaximumCustomTextRejectsBusyQueueWithoutPartialInputOrDisconnect {
    CompanionVNCSession *session = [CompanionVNCSession new]; [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    NSMutableArray *batch = [NSMutableArray new];
    for (NSUInteger i=0;i<256;i++) [batch addObjectsFromArray:@[@{@"key":@0x61,@"down":@YES},@{@"key":@0x61,@"down":@NO}]];
    [session pointerX:1 y:1 mask:0];
    XCTAssertFalse([session tryKeyEvents:batch]); XCTAssertEqual([[session valueForKey:@"events"] count],1);
    XCTAssertFalse([[session valueForKey:@"overflow"] boolValue]); XCTAssertTrue(session.connected);
    [[session valueForKey:@"events"] removeAllObjects]; XCTAssertTrue([session tryKeyEvents:batch]);
    XCTAssertEqual([[session valueForKey:@"events"] count],512); XCTAssertFalse([[session valueForKey:@"overflow"] boolValue]);
    [session setValue:@NO forKey:@"running"];
}
- (void)testAddressFallbackUsesConfiguredPortAndStopsAtFirstTCPConnection {
    int listener = socket(AF_INET, SOCK_STREAM, 0);
    struct sockaddr_in address = {.sin_len = sizeof(address), .sin_family = AF_INET, .sin_addr.s_addr = htonl(INADDR_LOOPBACK)};
    XCTAssertEqual(bind(listener, (void *)&address, sizeof(address)), 0); XCTAssertEqual(listen(listener, 1), 0);
    socklen_t length = sizeof(address); getsockname(listener, (void *)&address, &length);
    __block NSUInteger attempts = 0; NSInteger failure = 0;
    int client = CompanionVNCConnectAddresses(@[@"203.0.113.1", @"127.0.0.1", @"127.0.0.2"], ntohs(address.sin_port), ^{ return NO; }, ^BOOL(int fd) { return YES; }, ^(NSUInteger index, NSUInteger count) { attempts++; }, &failure);
    XCTAssertGreaterThanOrEqual(client, 0); XCTAssertEqual(attempts, 2);
    if (client >= 0) close(client); close(listener);
}
- (void)testFeedbackMarksLocalSelectionOnlyAndOptOutKeepsSlideActions {
    FeedbackControls *controls=[[FeedbackControls alloc] initWithFrame:CGRectMake(0,0,440,956)];
    controls.feedbackEvents=[NSMutableArray new]; BOOL original=controls.hapticsEnabled; controls.hapticsEnabled=YES;
    controls.quickActions=@[@{@"kind":@"mode",@"title":@"Switch Mode",@"enabled":@YES}];
    __block NSUInteger calls=0;controls.actionHandler=^(NSDictionary *item){calls++;};
    ControlsHold *gesture=[ControlsHold new];gesture.reference=controls;
    gesture.sampleState=UIGestureRecognizerStateBegan;[controls slide:gesture];
    UIButton *choice=[controls valueForKey:@"choices"][0];
    gesture.point=[choice convertPoint:CGPointMake(CGRectGetMidX(choice.bounds),CGRectGetMidY(choice.bounds)) toView:controls];
    gesture.sampleState=UIGestureRecognizerStateChanged;[controls slide:gesture];[controls slide:gesture];
    XCTAssertEqualObjects(controls.feedbackEvents,(@[@"open",@"selection"]));XCTAssertEqual(calls,0);
    gesture.sampleState=UIGestureRecognizerStateEnded;[controls slide:gesture];
    XCTAssertEqualObjects(controls.feedbackEvents.lastObject,@"commit");XCTAssertEqual(calls,1);
    [controls.feedbackEvents removeAllObjects];gesture.point=controls.button.center;gesture.sampleState=UIGestureRecognizerStateBegan;[controls slide:gesture];
    gesture.sampleState=UIGestureRecognizerStateCancelled;[controls slide:gesture];
    XCTAssertEqualObjects(controls.feedbackEvents,(@[@"open"]));XCTAssertEqual(calls,1);
    controls.hapticsEnabled=NO;[controls.feedbackEvents removeAllObjects];[controls open];
    [controls chosen:[controls valueForKey:@"choices"][0]];
    XCTAssertEqual(calls,2);XCTAssertEqual(controls.feedbackEvents.count,0);controls.hapticsEnabled=original;
}
- (void)testReduceMotionSkipsCompressionAndCancelledPressRestoresButton {
    FeedbackControls *controls=[[FeedbackControls alloc] initWithFrame:CGRectMake(0,0,440,956)];
    controls.forceReducedMotion=YES;[controls pressDown];
    XCTAssertTrue(CGAffineTransformIsIdentity(controls.button.transform));
    controls.forceReducedMotion=NO;[controls pressDown];XCTAssertFalse(CGAffineTransformIsIdentity(controls.button.transform));
    [controls close];XCTAssertTrue(CGAffineTransformIsIdentity(controls.button.transform));
}
@end
