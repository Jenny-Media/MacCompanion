#import <XCTest/XCTest.h>
#import "CompanionVNCAdaptiveLayout.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCControls.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>
#import <zlib.h>

@interface CompanionVNCSession (AdaptiveFrameTesting)
- (void)configureClient:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
@end

@interface CompanionVNCControls (AdaptiveTesting)
- (void)open;
@end
@interface AdaptiveControls : CompanionVNCControls
@end
@implementation AdaptiveControls
- (CGRect)activeDivision { return CGRectMake(0,465,669,20); }
@end

@interface CompanionVNCViewer (AdaptiveTesting)
- (void)frame:(UIImage *)frame;
- (void)applyViewportRatio:(CGFloat)ratio center:(CGPoint)center;
- (CGPoint)viewportCenter;
- (void)holdAt:(UILongPressGestureRecognizer *)gesture;
- (void)dragAt:(UIPanGestureRecognizer *)gesture;
- (void)clickAt:(UIGestureRecognizer *)gesture;
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known;
- (void)updateConnectionChrome;
@end
@interface AdaptiveViewer : CompanionVNCViewer
@property CGRect division;
@end
@implementation AdaptiveViewer
- (CGRect)activeDivision { return self.division; }
@end
@interface AdaptiveSession : CompanionVNCSession
@property NSUInteger stops;
@property NSMutableArray *events;
@end
@implementation AdaptiveSession
- (BOOL)connected { return YES; }
- (BOOL)running { return YES; }
- (void)stop { self.stops++; }
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { [self.events addObject:@[@(x), @(y), @(mask)]]; }
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { [self pointerX:x y:y mask:mask]; [self pointerX:x y:y mask:0]; return YES; }
@end
@interface AdaptivePan : UIPanGestureRecognizer
@end
@implementation AdaptivePan
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateBegan; }
- (CGPoint)translationInView:(UIView *)view { return CGPointMake(10,5); }
- (CGPoint)velocityInView:(UIView *)view { return CGPointZero; }
@end
@interface AdaptiveHold : UILongPressGestureRecognizer
@end
@implementation AdaptiveHold
- (UIGestureRecognizerState)state { return UIGestureRecognizerStateBegan; }
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(100,100); }
@end
@interface AdaptiveLayoutTests : XCTestCase
@end
@implementation AdaptiveLayoutTests
- (void)testDecodedFourKDesktopRendersThroughTheActualSessionAndViewer {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer;
    [window makeKeyAndVisible]; [window layoutIfNeeded];
    CompanionVNCSession *session = viewer.session;
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    rfbClient *client = rfbGetClient(8,3,4); client->sock = pair[0]; client->width = 3840; client->height = 2160;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    client->supportedMessages.client2server[0] |= 1 << rfbFramebufferUpdateRequest; rfbClientSetUpdateRect(client, NULL);
    NSMutableData *raw = [NSMutableData dataWithLength:3840 * 2160 * 4];
    uint8_t *bytes = raw.mutableBytes; for (NSUInteger i=0;i<raw.length;i+=4) bytes[i+2] = 255;
    NSMutableData *compressed = [NSMutableData dataWithLength:compressBound(raw.length)]; z_stream stream = {0};
    XCTAssertEqual(deflateInit(&stream, Z_DEFAULT_COMPRESSION), Z_OK);
    stream.next_in = raw.mutableBytes; stream.avail_in = (uInt)raw.length;
    stream.next_out = compressed.mutableBytes; stream.avail_out = (uInt)compressed.length;
    XCTAssertEqual(deflate(&stream, Z_SYNC_FLUSH), Z_OK); NSUInteger length = compressed.length - stream.avail_out;
    deflateEnd(&stream); compressed.length = length;
    uint8_t header[] = {0,0,0,1,0,0,0,0,15,0,8,112,0,0,0,6};
    uint8_t size[] = {(uint8_t)(length>>24),(uint8_t)(length>>16),(uint8_t)(length>>8),(uint8_t)length};
    NSData *headerData=[NSData dataWithBytes:header length:sizeof(header)], *sizeData=[NSData dataWithBytes:size length:sizeof(size)];
    int writer=pair[1];
    XCTestExpectation *sent = [self expectationWithDescription:@"Synthetic 4K update sent"];
    // A compressed 4K update can exceed the socket buffer. Feed it concurrently
    // with the real decoder instead of blocking the test's main thread.
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        XCTAssertEqual(write(writer,headerData.bytes,headerData.length),headerData.length); XCTAssertEqual(write(writer,sizeData.bytes,sizeData.length),sizeData.length);
        NSUInteger offset=0; while(offset<length) { ssize_t n=write(writer,(const uint8_t *)compressed.bytes+offset,length-offset); if(n<=0) break; offset+=(NSUInteger)n; }
        XCTAssertEqual(offset,length); [sent fulfill];
    });
    XCTAssertTrue(HandleRFBServerMessage(client)); [self waitForExpectations:@[sent] timeout:2];
    XCTAssertEqual(memcmp(client->frameBuffer,raw.bytes,raw.length),0);
    XCTestExpectation *connected = [self expectationWithDescription:@"Decoded desktop reaches the normal viewer"];
    void (^handler)(NSString *,NSDictionary *) = session.stateHandler;
    session.stateHandler = ^(NSString *state,NSDictionary *stats) {
        handler(state,stats); if ([state isEqualToString:@"Connected"]) [connected fulfill];
    };
    [session publishFrame:client]; [self waitForExpectations:@[connected] timeout:2];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]]; [window layoutIfNeeded];
    UIScrollView *canvas = [viewer valueForKey:@"canvas"]; UIImageView *image = [viewer valueForKey:@"image"];
    XCTAssertFalse(canvas.hidden); XCTAssertFalse(image.hidden); XCTAssertEqual(image.alpha,1);
    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale=1; format.preferredRange=UIGraphicsImageRendererFormatRangeStandard;
    UIImage *snapshot = [[[UIGraphicsImageRenderer alloc] initWithSize:canvas.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [canvas drawViewHierarchyInRect:(CGRect){CGPointZero,canvas.bounds.size} afterScreenUpdates:YES];
    }];
    size_t width=CGImageGetWidth(snapshot.CGImage),height=CGImageGetHeight(snapshot.CGImage);
    NSMutableData *rendered=[NSMutableData dataWithLength:width*height*4]; CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap=CGBitmapContextCreate(rendered.mutableBytes,width,height,8,width*4,colors,kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast);
    XCTAssertNotEqual(bitmap,NULL); CGContextDrawImage(bitmap,CGRectMake(0,0,width,height),snapshot.CGImage); CGContextRelease(bitmap); CGColorSpaceRelease(colors);
    const uint8_t *rgb=rendered.bytes; NSUInteger red=0;
    for (NSUInteger i=0;i+3<rendered.length;i+=4) if(rgb[i]>150 && rgb[i+1]<50 && rgb[i+2]<50) red++;
    XCTAssertGreaterThan(red,5000,@"Actual BGRX network pixels must survive CGImage creation, cropping, zoom and login dismissal");
    session.frameHandler=nil; session.stateHandler=nil; [session setValue:@NO forKey:@"running"];
    client->frameBuffer=NULL; rfbClientCleanup(client); close(pair[1]); [viewer stopViewer];
    window.hidden=YES; window.rootViewController=nil; [previous makeKeyAndVisible];
}
- (void)testFirstNetworkFrameRemainsVisibleWhenLoginDismissesBeforeOrAfterInitialLayout {
    for (NSNumber *layoutFirst in @[@NO, @YES]) {
        CompanionVNCViewer *viewer = [CompanionVNCViewer new];
        [viewer loadViewIfNeeded];
        UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
        UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
        UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer;
        if (layoutFirst.boolValue) { [window makeKeyAndVisible]; [window layoutIfNeeded]; }
        CompanionVNCSession *session = viewer.session;
        __block NSDictionary *diagnostics;
        viewer.diagnosticHandler = ^(NSDictionary *value) { diagnostics = value; };
        [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
        [session setValue:@YES forKey:@"baselinePresented"];
        UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat]; format.scale = 1; format.preferredRange = UIGraphicsImageRendererFormatRangeStandard;
        UIImage *frame = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(4000,1200) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [UIColor.redColor setFill]; UIRectFill(CGRectMake(0,0,4000,1200));
        }];
        session.frameHandler(frame); session.stateHandler(@"Connected", @{});
        [window makeKeyAndVisible]; [window layoutIfNeeded];
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.3]];
        [window layoutIfNeeded];
        UIScrollView *canvas = [viewer valueForKey:@"canvas"]; UIImageView *image = [viewer valueForKey:@"image"];
        CGRect visibleImage = [image convertRect:image.bounds toView:canvas];
        XCTAssertFalse(canvas.hidden); XCTAssertFalse(image.hidden); XCTAssertNotNil(image.image);
        XCTAssertEqualObjects(diagnostics[@"viewer"][@"canvasHidden"],@NO);
        XCTAssertEqualObjects(diagnostics[@"viewer"][@"hasImage"],@YES);
        XCTAssertGreaterThan(CGRectIntersection(canvas.bounds,visibleImage).size.width,100);
        XCTAssertGreaterThan(CGRectIntersection(canvas.bounds,visibleImage).size.height,50);
        XCTAssertEqualWithAccuracy(canvas.zoomScale,canvas.minimumZoomScale,.001);
        UIImage *snapshot = [[[UIGraphicsImageRenderer alloc] initWithSize:canvas.bounds.size format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
            [canvas drawViewHierarchyInRect:(CGRect){CGPointZero,canvas.bounds.size} afterScreenUpdates:YES];
        }];
        size_t width=CGImageGetWidth(snapshot.CGImage), height=CGImageGetHeight(snapshot.CGImage);
        NSMutableData *pixels=[NSMutableData dataWithLength:width*height*4];CGColorSpaceRef colors=CGColorSpaceCreateDeviceRGB();
        CGContextRef bitmap=CGBitmapContextCreate(pixels.mutableBytes,width,height,8,width*4,colors,kCGBitmapByteOrder32Big|kCGImageAlphaPremultipliedLast);
        XCTAssertNotEqual(bitmap,NULL);CGContextDrawImage(bitmap,CGRectMake(0,0,width,height),snapshot.CGImage);CGContextRelease(bitmap);CGColorSpaceRelease(colors);
        const uint8_t *bytes = pixels.bytes; NSUInteger colored = 0;
        for (NSUInteger i=0;i+3<pixels.length;i+=4) if (bytes[i] > 150 && bytes[i+1] < 50 && bytes[i+2] < 50) colored++;
        XCTAssertGreaterThan(colored,5000, @"The connected desktop must actually render pixels, including when a frame arrives before layout");
        session.frameHandler = nil; session.stateHandler = nil; [session setValue:@NO forKey:@"running"];
        [viewer stopViewer]; window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
    }
}
- (UIImage *)frame {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1600,1000)] imageWithActions:^(UIGraphicsImageRendererContext *c) {
        [UIColor.blueColor setFill]; UIRectFill(CGRectMake(0,0,1600,1000));
    }];
}
- (void)testFoldNeedsTwoUsableRegionsAndDoesNotInventTabletopForVerticalOrEdgeDivision {
    CGRect safe = CGRectMake(0,82,669,835), content, input;
    XCTAssertTrue(CompanionVNCTabletopRegions(safe,CGRectMake(0,465,669,20),&content,&input));
    XCTAssertEqual(CGRectGetMaxY(content),465); XCTAssertEqual(input.origin.y,485);
    XCTAssertFalse(CGRectIntersectsRect(content,input));
    XCTAssertFalse(CompanionVNCTabletopRegions(safe,CGRectNull,&content,&input));
    XCTAssertFalse(CompanionVNCTabletopRegions(safe,CGRectMake(320,82,20,835),&content,&input));
    XCTAssertFalse(CompanionVNCTabletopRegions(safe,CGRectMake(0,100,669,20),&content,&input));
}
- (void)testRepeatedResizePreservesSessionDisplayZoomAndFocusAndReleasesInterruptedDrag {
    AdaptiveViewer *viewer = [AdaptiveViewer new]; viewer.division = CGRectNull; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
    AdaptiveSession *session = [AdaptiveSession new]; session.events = [NSMutableArray new]; viewer.session = session;
    [viewer frame:[self frame]]; [[viewer valueForKey:@"login"] setHidden:YES]; [viewer.view layoutIfNeeded];
    [viewer applyViewportRatio:3 center:CGPointMake(.55,.5)];
    UIScrollView *canvas = [viewer valueForKey:@"canvas"];
    CGPoint focus = [viewer viewportCenter];
    AdaptiveHold *hold = [AdaptiveHold new]; [viewer holdAt:hold];
    XCTAssertEqualObjects(session.events.lastObject[2],@1);
    for (NSValue *value in @[[NSValue valueWithCGSize:CGSizeMake(951,669)], [NSValue valueWithCGSize:CGSizeMake(669,951)], [NSValue valueWithCGSize:CGSizeMake(440,956)]]) {
        viewer.view.frame = (CGRect){CGPointZero,value.CGSizeValue}; [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
        XCTAssertEqual(viewer.session,session); XCTAssertEqual(session.stops,0);
        XCTAssertEqualWithAccuracy(canvas.zoomScale / canvas.minimumZoomScale,3,.01);
        CGPoint center = [viewer viewportCenter]; XCTAssertEqualWithAccuracy(center.x,focus.x,.01); XCTAssertEqualWithAccuracy(center.y,focus.y,.01);
    }
    XCTAssertEqualObjects(session.events.lastObject[2],@0);
    [viewer stopViewer];
}
- (void)testTabletopKeepsDesktopAboveDivisionAndInputBelowAndReturnsWithoutReplacingSession {
    AdaptiveViewer *viewer = [AdaptiveViewer new]; viewer.division = CGRectNull; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0,0,669,951); [viewer.view layoutIfNeeded]; [viewer frame:[self frame]];
    [[viewer valueForKey:@"login"] setHidden:YES]; CompanionVNCSession *owner = viewer.session;
    viewer.division = CGRectMake(0,465,669,20); [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    UIView *pad = [viewer valueForKey:@"tabletopPad"]; UIScrollView *canvas = [viewer valueForKey:@"canvas"];
    XCTAssertFalse(pad.hidden); XCTAssertLessThanOrEqual(CGRectGetMaxY(canvas.frame),465);
    XCTAssertGreaterThanOrEqual(pad.frame.origin.y,485); XCTAssertEqual(viewer.session,owner);
    viewer.division = CGRectNull; [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    XCTAssertTrue(pad.hidden); XCTAssertGreaterThan(CGRectGetMaxY(canvas.frame),800); XCTAssertEqual(viewer.session,owner);
    [viewer stopViewer];
}
- (void)testNarrowModifierRowScrollsInsteadOfShrinkingKeysBelowTouchTarget {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0,0,320,680); [viewer.view layoutIfNeeded];
    UIScrollView *toolbar = [viewer valueForKey:@"toolbar"]; UIStackView *row = [viewer valueForKey:@"keyRow"];
    XCTAssertGreaterThan(toolbar.contentSize.width,toolbar.bounds.size.width);
    for (UIView *key in row.arrangedSubviews) XCTAssertGreaterThanOrEqual(key.bounds.size.width,44);
    [viewer stopViewer];
}
- (void)testLowerTrackpadUsesRelativeMotionAndBalancedClickWhileDesktopRemainsInPointerMode {
    AdaptiveViewer *viewer = [AdaptiveViewer new]; viewer.division = CGRectMake(0,465,669,20); viewer.pointerSpeed = 1;
    [viewer loadViewIfNeeded]; viewer.view.frame = CGRectMake(0,0,669,951); [viewer.view layoutIfNeeded];
    AdaptiveSession *session = [AdaptiveSession new]; session.events = [NSMutableArray new]; viewer.session = session;
    [viewer frame:[self frame]]; [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(800,500) known:YES];
    UIView *pad = [viewer valueForKey:@"tabletopPad"]; AdaptivePan *pan = [AdaptivePan new]; [pad addGestureRecognizer:pan];
    [viewer dragAt:pan]; XCTAssertEqualObjects(session.events.lastObject,(@[@820,@510,@0]));
    UITapGestureRecognizer *tap = [UITapGestureRecognizer new]; [pad addGestureRecognizer:tap]; [viewer clickAt:tap];
    XCTAssertEqualObjects(session.events[session.events.count - 2],(@[@820,@510,@1]));
    XCTAssertEqualObjects(session.events.lastObject,(@[@820,@510,@0]));
    XCTAssertFalse([[viewer valueForKey:@"trackpadMode"] boolValue]);
    [viewer stopViewer];
}
- (void)testTallKeyboardNeverCoversTabletopDesktopOrLeavesANegativeTrackpadFrame {
    AdaptiveViewer *viewer = [AdaptiveViewer new]; viewer.division = CGRectMake(0,465,669,20);
    [viewer loadViewIfNeeded]; viewer.view.frame = CGRectMake(0,0,669,951); [viewer.view layoutIfNeeded]; [viewer frame:[self frame]];
    [[viewer valueForKey:@"login"] setHidden:YES];
    [viewer setValue:@600 forKey:@"keyboardOverlap"];
    ((NSLayoutConstraint *)[viewer valueForKey:@"toolbarBottom"]).constant = -604;
    [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    UIScrollView *canvas = [viewer valueForKey:@"canvas"]; UIView *toolbar = [viewer valueForKey:@"toolbar"], *pad = [viewer valueForKey:@"tabletopPad"];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(canvas.frame),CGRectGetMinY(toolbar.frame)-8);
    XCTAssertTrue(pad.hidden); XCTAssertGreaterThanOrEqual(pad.bounds.size.height,0);
    [viewer setValue:@0 forKey:@"keyboardOverlap"]; ((NSLayoutConstraint *)[viewer valueForKey:@"toolbarBottom"]).constant = -4;
    [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded]; XCTAssertFalse(pad.hidden);
    [viewer stopViewer];
}
- (void)testTabletopMenuStaysBelowFoldAndMovesAboveKeyboardWhenLowerPaneIsCovered {
    AdaptiveControls *controls = [[AdaptiveControls alloc] initWithFrame:CGRectMake(0,0,669,951)]; controls.bottomInset = 4;
    [controls open]; [controls layoutIfNeeded]; UIView *panel = [controls valueForKey:@"panel"];
    XCTAssertGreaterThanOrEqual(panel.frame.origin.y,485); XCTAssertGreaterThanOrEqual(controls.button.frame.origin.y,485);
    controls.bottomInset = 604; [controls setNeedsLayout]; [controls layoutIfNeeded];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(controls.button.frame),351);
    XCTAssertLessThanOrEqual(CGRectGetMaxY(panel.frame),351); XCTAssertGreaterThan(panel.frame.size.height,0);
    [controls close];
}
- (void)testCompactLoginKeepsPrimaryActionVisibleAndCancellingAvailableDuringProgress {
    AdaptiveViewer *viewer = [AdaptiveViewer new]; viewer.division = CGRectNull; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0,0,678,432); [viewer.view layoutIfNeeded];
    UIScrollView *login = [viewer valueForKey:@"loginScroll"]; UIButton *connect = [viewer valueForKey:@"connect"];
    CGRect action = [connect convertRect:connect.bounds toView:login];
    XCTAssertTrue(CGRectContainsRect(login.bounds,action));
    XCTAssertTrue(((UIView *)[viewer valueForKey:@"progressRow"]).hidden);
    [viewer setValue:@YES forKey:@"starting"]; [viewer performSelector:@selector(updateConnectionChrome)]; [viewer.view layoutIfNeeded];
    XCTAssertFalse(((UIView *)[viewer valueForKey:@"progressRow"]).hidden);
    XCTAssertFalse(((UIView *)[viewer valueForKey:@"loginFields"]).userInteractionEnabled);
    XCTAssertTrue(((UIView *)[viewer valueForKey:@"loginFields"]).hidden);
    XCTAssertTrue(connect.hidden);
    XCTAssertTrue(((UIView *)[viewer valueForKey:@"loginDetails"]).hidden);
    UIButton *cancel = [viewer valueForKey:@"loginCancel"];
    XCTAssertFalse(cancel.hidden); XCTAssertTrue(cancel.userInteractionEnabled);
    XCTAssertTrue(((UIView *)[viewer valueForKey:@"loginClose"]).hidden);
    [viewer showInvalidLogin]; [viewer.view layoutIfNeeded];
    XCTAssertTrue(((UIView *)[viewer valueForKey:@"progressRow"]).hidden);
    XCTAssertNotNil([viewer valueForKey:@"recoveryController"]);
    XCTAssertFalse(connect.hidden); XCTAssertTrue(cancel.hidden);
    XCTAssertFalse(((UIView *)[viewer valueForKey:@"loginClose"]).hidden);
    [viewer stopViewer];
}
- (void)testFoldedLoginUsesOneRegionAndMovesAboveATallKeyboard {
    AdaptiveViewer *viewer = [AdaptiveViewer new]; viewer.division = CGRectMake(0,465,669,20);
    [viewer loadViewIfNeeded]; viewer.view.frame = CGRectMake(0,0,669,951); [viewer.view layoutIfNeeded];
    UIScrollView *login = [viewer valueForKey:@"loginScroll"]; UIView *intro = [viewer valueForKey:@"loginIntro"];
    XCTAssertGreaterThanOrEqual(login.frame.origin.y,485); XCTAssertLessThanOrEqual(CGRectGetMaxY(intro.frame),465);
    CompanionVNCSession *owner = viewer.session;
    [viewer setValue:@600 forKey:@"keyboardOverlap"]; [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    XCTAssertLessThanOrEqual(CGRectGetMaxY(login.frame),351); XCTAssertGreaterThan(login.frame.size.height,0);
    XCTAssertEqual(viewer.session,owner); XCTAssertEqual(intro.superview,[viewer valueForKey:@"login"]);
    [viewer stopViewer];
}
- (void)testMenuHeaderAndCategoriesRemainVisibleWhenQuickActionsScroll {
    CompanionVNCControls *controls = [[CompanionVNCControls alloc] initWithFrame:CGRectMake(0,0,678,432)];
    NSMutableArray *actions = [NSMutableArray new]; for (NSUInteger i=0;i<15;i++) [actions addObject:@{@"kind":@"text",@"title":@"Saved Text",@"enabled":@YES}];
    controls.quickActions = actions; [controls open];
    UIView *panel = [controls valueForKey:@"panel"], *name = [controls valueForKey:@"nameLabel"]; UIScrollView *scroll = [controls valueForKey:@"scroll"];
    XCTAssertTrue(CGRectContainsRect(panel.bounds,name.frame)); XCTAssertNotEqual(name.superview,scroll);
    NSArray<UIButton *> *choices = [controls valueForKey:@"choices"];
    for (NSUInteger i=15;i<18;i++) { XCTAssertTrue(CGRectContainsRect(panel.bounds,choices[i].frame)); XCTAssertNotEqual(choices[i].superview,scroll); }
    scroll.contentOffset = CGPointZero; XCTAssertTrue(CGRectContainsRect(panel.bounds,name.frame));
    [controls close];
}
- (void)testShortKeyboardMenuScrollsWholeActionsBelowItsHeader {
    CompanionVNCControls *controls = [[CompanionVNCControls alloc] initWithFrame:CGRectMake(0,0,678,466)];
    controls.bottomInset = 240; controls.quickActions = @[@{@"kind":@"fit",@"title":@"Fit Display",@"enabled":@YES}];
    [controls open];
    UIView *panel = [controls valueForKey:@"panel"], *name = [controls valueForKey:@"nameLabel"];
    UIScrollView *scroll = [controls valueForKey:@"scroll"];
    XCTAssertTrue(CGRectContainsRect(panel.bounds,name.frame)); XCTAssertGreaterThanOrEqual(scroll.bounds.size.height,64);
    for (UIButton *choice in [controls valueForKey:@"choices"]) {
        XCTAssertEqual(choice.superview,scroll); XCTAssertGreaterThanOrEqual(choice.bounds.size.height,44);
    }
    XCTAssertGreaterThan(scroll.contentSize.height,scroll.bounds.size.height);
    [controls close];
}
- (void)testTapMenuSurvivesCanvasAndFoldLayoutChanges {
    AdaptiveViewer *viewer = [AdaptiveViewer new]; viewer.division = CGRectNull; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0,0,669,951); [viewer.view layoutIfNeeded]; [viewer frame:[self frame]];
    CompanionVNCControls *controls = [viewer valueForKey:@"controls"]; [controls open];
    UIView *panel = [controls valueForKey:@"panel"];
    viewer.division = CGRectMake(0,465,669,20); [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    XCTAssertEqual([controls valueForKey:@"panel"],panel);
    viewer.view.frame = CGRectMake(0,0,951,669); [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    XCTAssertEqual([controls valueForKey:@"panel"],panel);
    __block NSUInteger actions = 0; controls.actionHandler = ^(NSDictionary *action) { actions++; };
    [controls setValue:[AdaptiveHold new] forKey:@"slide"];
    [controls cancelSlideForLayoutChange];
    XCTAssertNil([controls valueForKey:@"panel"]); XCTAssertEqual(actions,0);
    [viewer stopViewer];
}
@end
