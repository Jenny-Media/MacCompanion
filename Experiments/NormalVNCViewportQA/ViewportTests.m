#import <XCTest/XCTest.h>
#import "CompanionVNCViewer.h"
#import "CompanionVNCDisplayPicker.h"
#import <rfb/rfbclient.h>

@interface CompanionVNCViewer (ViewportTests)
- (void)frame:(UIImage *)frame;
- (void)selectDisplay:(NSDictionary *)display;
- (void)smartZoomAt:(CGPoint)point;
- (void)clickAt:(UITapGestureRecognizer *)gesture;
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known;
- (void)fitDesktop;
- (void)setTrackpadModeEnabled:(BOOL)enabled;
- (void)chooseView;
- (void)dragAt:(UIPanGestureRecognizer *)gesture;
- (void)holdAt:(UILongPressGestureRecognizer *)gesture;
- (void)scrollRemote:(UIPanGestureRecognizer *)gesture;
@end
@interface CompanionVNCSession (CursorTests)
- (void)cursorShape:(rfbClient *)client x:(int)x y:(int)y width:(int)width height:(int)height bytesPerPixel:(int)bytes;
- (rfbBool)cursorPosition:(rfbClient *)client x:(int)x y:(int)y;
- (void)publishCursor;
@end
@interface ViewportSession : CompanionVNCSession
@property NSMutableArray *sent;
@end
@implementation ViewportSession
- (BOOL)running { return YES; }
- (BOOL)connected { return YES; }
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { [self pointerX:x y:y mask:mask]; [self pointerX:x y:y mask:0]; return YES; }
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask {
    [self.sent addObject:@[@(x), @(y), @(mask)]];
}
@end
@interface ViewportTap : UITapGestureRecognizer
@property CGPoint sample;
@end
@implementation ViewportTap
- (CGPoint)locationInView:(UIView *)view { return self.sample; }
@end

@interface ViewportPan : UIPanGestureRecognizer
@property CGPoint sample, delta;
@property UIGestureRecognizerState sampleState;
@end
@implementation ViewportPan
- (CGPoint)locationInView:(UIView *)view { return self.sample; }
- (CGPoint)translationInView:(UIView *)view { return self.delta; }
- (void)setTranslation:(CGPoint)p inView:(UIView *)view { self.delta = p; }
- (UIGestureRecognizerState)state { return self.sampleState; }
@end
@interface ViewportHold : UILongPressGestureRecognizer
@property CGPoint sample;
@property UIGestureRecognizerState sampleState;
@end
@implementation ViewportHold
- (CGPoint)locationInView:(UIView *)view { return self.sample; }
- (UIGestureRecognizerState)state { return self.sampleState; }
@end

@interface ViewportTests : XCTestCase
@end
@implementation ViewportTests
- (void)testDisplayPickerShowsArrangementDimensionsSelectionAndResolvesUpdatedIDs {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0, 0, 440, 956); [viewer.view layoutIfNeeded];
    [viewer frame:[self syntheticFrame:CGSizeMake(800, 600)]];
    NSDictionary *left = @{@"id": @1, @"title": @"Display 1", @"pixelWidth": @400, @"pixelHeight": @600,
        @"x": @0, @"y": @0, @"width": @.5, @"height": @1};
    NSMutableDictionary *right = [left mutableCopy]; right[@"id"] = @2; right[@"title"] = @"Display 2"; right[@"x"] = @.5;
    viewer.displayLayout = @{@"aspectRatio": @(800.0 / 600), @"views": @[left, right]};
    UIWindowScene *scene = (id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous = nil; for (UIWindow *w in scene.windows) if (w.isKeyWindow) previous = w;
    UIWindow *window = [[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController = viewer; [window makeKeyAndVisible];
    [viewer chooseView];
    CompanionVNCDisplayPicker *picker = [viewer valueForKey:@"displayPicker"];
    XCTAssertNotNil(picker); [picker loadViewIfNeeded];
    XCTAssertEqual([picker tableView:picker.tableView numberOfRowsInSection:0], 3);
    UITableViewCell *first = [picker tableView:picker.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:0 inSection:0]];
    UIListContentConfiguration *content = (id)first.contentConfiguration;
    XCTAssertEqualObjects(content.text, @"Display 1"); XCTAssertEqualObjects(content.secondaryText, @"400 × 600");
    XCTAssertEqual(content.image.size.width, 80); XCTAssertEqual(content.image.size.height, 44);
    UITableViewCell *all = [picker tableView:picker.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]];
    XCTAssertEqual(all.accessoryType, UITableViewCellAccessoryCheckmark);
    // An open picker receives layout updates and selects by the latest ID.
    right[@"width"] = @.25;
    viewer.displayLayout = @{@"aspectRatio": @(800.0 / 600), @"views": @[left, right]};
    picker.selectionHandler(@2);
    XCTAssertEqual(CGImageGetWidth(((UIImageView *)[viewer valueForKey:@"image"]).image.CGImage), 200);
    UITableViewCell *second = [picker tableView:picker.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]];
    XCTAssertEqual(second.accessoryType, UITableViewCellAccessoryCheckmark);
    viewer.displayLayout = @{@"aspectRatio": @(800.0 / 600), @"views": @[left]};
    picker.selectionHandler(@2); XCTAssertNil([viewer valueForKey:@"selectedDisplay"]);
    XCTAssertEqual(CGImageGetWidth(((UIImageView *)[viewer valueForKey:@"image"]).image.CGImage), 800);
    // Arrangement snapshots use only synthetic geometry, never desktop pixels.
    picker.displays = @[left, right]; picker.selectedID = @2;
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.4]];
    [window layoutIfNeeded]; [picker.tableView layoutIfNeeded];
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size];
    UIImage *snapshot = [renderer imageWithActions:^(UIGraphicsImageRendererContext *ctx) { [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES]; }];
    XCTAttachment *attachment = [XCTAttachment attachmentWithImage:snapshot]; attachment.name = @"Synthetic display picker"; attachment.lifetime = XCTAttachmentLifetimeKeepAlways;
    [self addAttachment:attachment]; [viewer dismissViewControllerAnimated:NO completion:nil]; [viewer stopViewer];
    window.hidden = YES; window.rootViewController = nil; [previous makeKeyAndVisible];
}
- (void)testTrackpadUsesRelativeMotionAndReleasesDragOnModeAndDisplayChanges {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; viewer.pointerSpeed = 1; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0, 0, 440, 956); [viewer.view layoutIfNeeded];
    ViewportSession *session = [ViewportSession new]; session.sent = [NSMutableArray new]; viewer.session = session;
    [viewer frame:[self syntheticFrame:CGSizeMake(800, 600)]];
    [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(200, 100) known:YES];
    [viewer setTrackpadModeEnabled:YES];
    ViewportPan *pan = [ViewportPan new]; pan.sampleState = UIGestureRecognizerStateBegan;
    pan.sample = CGPointMake(700, 500); pan.delta = CGPointMake(10, 5); [viewer dragAt:pan];
    XCTAssertEqualObjects(session.sent.lastObject, (@[@220, @110, @0])); // finger location does not jump cursor
    ViewportTap *tap = [ViewportTap new]; tap.sample = CGPointMake(700, 500); [viewer clickAt:tap];
    XCTAssertEqualObjects(session.sent.lastObject, (@[@220, @110, @0]));
    ViewportHold *hold = [ViewportHold new]; hold.sampleState = UIGestureRecognizerStateBegan; hold.sample = CGPointMake(20, 20);
    [viewer holdAt:hold]; XCTAssertEqualObjects(session.sent.lastObject, (@[@220, @110, @1]));
    hold.sampleState = UIGestureRecognizerStateChanged; hold.sample = CGPointMake(900, 900); [viewer holdAt:hold];
    XCTAssertEqualObjects(session.sent.lastObject, (@[@799, @599, @1]));
    [viewer setTrackpadModeEnabled:NO]; XCTAssertEqualObjects(session.sent.lastObject, (@[@799, @599, @0]));
    tap.sample = CGPointMake(50, 60); [viewer clickAt:tap];
    XCTAssertEqualObjects(session.sent.lastObject, (@[@50, @60, @0]));
    hold.sampleState = UIGestureRecognizerStateBegan; hold.sample = CGPointMake(50, 60); [viewer holdAt:hold];
    [viewer selectDisplay:nil]; XCTAssertEqualObjects(session.sent.lastObject, (@[@50, @60, @0]));
    [viewer setTrackpadModeEnabled:YES]; pan.sampleState = UIGestureRecognizerStateBegan; pan.delta = CGPointMake(0, 36);
    [viewer scrollRemote:pan];
    XCTAssertEqualObjects(session.sent[session.sent.count - 2], (@[@50, @60, @8]));
    XCTAssertEqualObjects(session.sent.lastObject, (@[@50, @60, @0]));
    [viewer stopViewer];
}
- (void)testUpdatedDisplayIDsKeepSelectionAndMissingOrIncompatibleBoundsReturnToDesktop {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    [viewer frame:[self syntheticFrame:CGSizeMake(800, 600)]];
    NSDictionary *left = @{@"id": @1, @"title": @"Display 1", @"x": @0, @"y": @0, @"width": @.5, @"height": @1};
    viewer.displayLayout = @{@"aspectRatio": @(800.0 / 600), @"views": @[left]}; [viewer selectDisplay:left];
    UIImageView *image = [viewer valueForKey:@"image"];
    XCTAssertEqual(CGImageGetWidth(image.image.CGImage), 400);
    NSMutableDictionary *changed = [left mutableCopy]; changed[@"width"] = @.75;
    viewer.displayLayout = @{@"aspectRatio": @(800.0 / 600), @"views": @[changed]};
    XCTAssertEqual(CGImageGetWidth(image.image.CGImage), 600);
    [viewer frame:[self syntheticFrame:CGSizeMake(800, 800)]];
    XCTAssertNotNil(image.image); XCTAssertNil([viewer valueForKey:@"selectedDisplay"]);
    XCTAssertEqual(CGImageGetHeight(image.image.CGImage), 800);
    viewer.displayLayout = @{@"aspectRatio": @1, @"views": @[]};
    [viewer stopViewer];
}
- (NSDictionary *)profile {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"vnc-desktop-tunnel-v0.1" withExtension:@"json"];
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
}
- (UIImage *)syntheticFrame:(CGSize)size {
    CGColorSpaceRef colors = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, size.width, size.height, 8, size.width * 4, colors, (CGBitmapInfo)kCGImageAlphaNoneSkipLast);
    CGImageRef image = CGBitmapContextCreateImage(context);
    UIImage *frame = [UIImage imageWithCGImage:image];
    CGImageRelease(image); CGContextRelease(context); CGColorSpaceRelease(colors); return frame;
}
- (void)testActualCanvasCropsMapsInputFitsWindowsAndIgnoresRetiredLookup {
    NSDictionary *profile = [self profile];
    NSDictionary *main = profile[@"viewportCases"][1];
    NSArray *f = main[@"framebuffer"], *n = main[@"normalized"], *r = main[@"rect"];
    CompanionVNCViewer *viewer = [CompanionVNCViewer new];
    [viewer loadViewIfNeeded]; viewer.view.frame = CGRectMake(0, 0, 440, 956);
    [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    ViewportSession *session = [ViewportSession new]; session.sent = [NSMutableArray new]; viewer.session = session;
    viewer.displayLayout = @{@"aspectRatio": main[@"aspect"], @"views": @[]};
    UIImage *frame = [self syntheticFrame:CGSizeMake([f[0] doubleValue], [f[1] doubleValue])];
    [viewer frame:frame];
    NSDictionary *display = @{@"title": @"Synthetic Display", @"x": n[0], @"y": n[1], @"width": n[2], @"height": n[3]};
    [viewer selectDisplay:display];
    UIImageView *image = [viewer valueForKey:@"image"]; UIScrollView *canvas = [viewer valueForKey:@"canvas"];
    XCTAssertEqual(CGImageGetWidth(image.image.CGImage), [r[2] unsignedIntegerValue]);
    XCTAssertEqual(CGImageGetHeight(image.image.CGImage), [r[3] unsignedIntegerValue]);
    CGFloat minimum = MIN(canvas.bounds.size.width / [r[2] doubleValue], canvas.bounds.size.height / [r[3] doubleValue]);
    XCTAssertEqualWithAccuracy(canvas.minimumZoomScale, minimum, .00001);
    [canvas setZoomScale:.001 animated:NO]; XCTAssertGreaterThanOrEqual(canvas.zoomScale, minimum);
    NSDictionary *pointer = profile[@"viewportPointerCases"][1]; NSArray *p = pointer[@"point"], *mapped = pointer[@"mapped"];
    ViewportTap *tap = [ViewportTap new]; tap.sample = CGPointMake([p[0] doubleValue], [p[1] doubleValue]);
    [viewer clickAt:tap]; XCTAssertEqualObjects(session.sent, (@[@[mapped[0], mapped[1], @1], @[mapped[0], mapped[1], @0]]));
    NSDictionary *fit = profile[@"windowFitCases"][0]; NSArray *w = fit[@"window"], *local = fit[@"local"];
    __block void (^reply)(CGRect);
    viewer.windowBoundsHandler = ^(CGPoint point, CGSize size, void (^completion)(CGRect)) { reply = [completion copy]; };
    [viewer smartZoomAt:tap.sample]; XCTAssertNotNil(reply);
    reply(CGRectMake([w[0] doubleValue], [w[1] doubleValue], [w[2] doubleValue], [w[3] doubleValue]));
    XCTAssertTrue([[viewer valueForKey:@"smartZoomed"] boolValue]);
    CGRect target = [[viewer valueForKey:@"smartWindow"] CGRectValue];
    XCTAssertTrue(CGRectEqualToRect(target, CGRectMake([local[0] doubleValue], [local[1] doubleValue], [local[2] doubleValue], [local[3] doubleValue])));
    [viewer smartZoomAt:tap.sample]; XCTAssertFalse([[viewer valueForKey:@"smartZoomed"] boolValue]);
    [viewer smartZoomAt:tap.sample]; void (^stale)(CGRect) = reply;
    [viewer selectDisplay:nil]; stale(CGRectMake([w[0] doubleValue], [w[1] doubleValue], [w[2] doubleValue], [w[3] doubleValue]));
    XCTAssertFalse([[viewer valueForKey:@"smartZoomed"] boolValue]);
    XCTAssertEqual(CGImageGetWidth(image.image.CGImage), [f[0] unsignedIntegerValue]);
    // Repeated crop changes reuse one framebuffer, and updates preserve zoom.
    for (NSUInteger i = 0; i < 30; i++) {
        @autoreleasepool { [viewer selectDisplay:display]; [viewer selectDisplay:nil]; }
    }
    [viewer selectDisplay:display]; [canvas setZoomScale:minimum * 2 animated:NO]; CGFloat zoom = canvas.zoomScale;
    [viewer frame:frame]; XCTAssertEqualWithAccuracy(canvas.zoomScale, zoom, .00001);
    XCTAssertEqual(CGImageGetWidth(image.image.CGImage), [r[2] unsignedIntegerValue]);
    // Manual pinch must toggle back to fit; no-window lookup still zooms in.
    [viewer smartZoomAt:tap.sample]; XCTAssertEqualWithAccuracy(canvas.zoomScale, minimum, .00001);
    [viewer smartZoomAt:tap.sample]; reply(CGRectNull);
    XCTAssertTrue([[viewer valueForKey:@"smartZoomed"] boolValue]);
    target = [[viewer valueForKey:@"smartWindow"] CGRectValue];
    XCTAssertEqualWithAccuracy(target.size.width, [r[2] doubleValue] / 2, .00001);
    [viewer smartZoomAt:tap.sample];
    [viewer smartZoomAt:tap.sample]; stale = reply;
    [viewer smartZoomAt:tap.sample]; stale(CGRectNull);
    XCTAssertFalse([[viewer valueForKey:@"smartZoomed"] boolValue]);
    [viewer stopViewer];
}
- (void)testCursorTracksCropHotspotZoomPanAndLocalInput {
    NSDictionary *profile = [self profile], *main = profile[@"viewportCases"][3];
    NSArray *f = main[@"framebuffer"], *n = main[@"normalized"];
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0, 0, 440, 956); [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
    ViewportSession *session = [ViewportSession new]; session.sent = [NSMutableArray new]; viewer.session = session;
    viewer.displayLayout = @{@"aspectRatio": main[@"aspect"], @"views": @[]};
    [viewer frame:[self syntheticFrame:CGSizeMake([f[0] doubleValue], [f[1] doubleValue])]];
    [viewer selectDisplay:@{@"title": @"Synthetic Display", @"x": n[0], @"y": n[1], @"width": n[2], @"height": n[3]}];
    UIImageView *image = [viewer valueForKey:@"image"]; UIView *overlay = [viewer valueForKey:@"cursorOverlay"], *cursor = [viewer valueForKey:@"cursorIndicator"];
    UIScrollView *canvas = [viewer valueForKey:@"canvas"];
    CGPoint point = CGPointMake(1280, 533); CGPoint framebuffer = CGPointMake(2792, 533);
    UIImage *shape = [self syntheticFrame:CGSizeMake(16, 24)];
    [viewer receivedCursor:shape hotspot:CGPointMake(1, 2) position:framebuffer known:YES];
    XCTAssertFalse(cursor.hidden); XCTAssertFalse(overlay.userInteractionEnabled);
    CGPoint anchor = [image convertPoint:point toView:overlay];
    XCTAssertEqualWithAccuracy(CGRectGetMinX(cursor.frame), anchor.x - 1, .001);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(cursor.frame), anchor.y - 2, .001);
    XCTAssertEqualWithAccuracy(cursor.frame.size.height, 24, .001);
    [canvas setZoomScale:canvas.minimumZoomScale * 2 animated:NO];
    [canvas setContentOffset:CGPointMake(60, 0) animated:NO];
    anchor = [image convertPoint:point toView:overlay];
    XCTAssertEqualWithAccuracy(CGRectGetMinX(cursor.frame), anchor.x - 1, .001);
    XCTAssertEqualWithAccuracy(CGRectGetMinY(cursor.frame), anchor.y - 2, .001);
    [viewer receivedCursor:shape hotspot:CGPointMake(1, 2) position:CGPointMake(100, 100) known:YES];
    XCTAssertTrue(cursor.hidden); // Position lies on the other display.
    [viewer fitDesktop];
    ViewportTap *tap = [ViewportTap new]; tap.sample = point; [viewer clickAt:tap];
    XCTAssertFalse(cursor.hidden); XCTAssertEqualObjects(session.sent.lastObject, (@[@2792, @533, @0]));
    [viewer stopViewer]; XCTAssertTrue(cursor.hidden);
}
- (void)testNativeCursorReceiverProducesRGBAAndDropsPresentationAfterStop {
    NSDictionary *c = [self profile][@"cursorPixelCases"][0];
    NSMutableData *source = [NSMutableData new], *mask = [NSMutableData new], *expected = [NSMutableData new];
    for (NSNumber *value in c[@"source"]) { uint8_t b = value.unsignedCharValue; [source appendBytes:&b length:1]; }
    for (NSNumber *value in c[@"mask"]) { uint8_t b = value.unsignedCharValue; [mask appendBytes:&b length:1]; }
    for (NSNumber *value in c[@"rgba"]) { uint8_t b = value.unsignedCharValue; [expected appendBytes:&b length:1]; }
    rfbClient client = {0}; client.width = 8144; client.height = 2134;
    client.rcSource = source.mutableBytes; client.rcMask = mask.mutableBytes;
    CompanionVNCSession *session = [CompanionVNCSession new]; [session setValue:@YES forKey:@"running"];
    XCTestExpectation *presented = [self expectationWithDescription:@"Native cursor received"];
    session.cursorHandler = ^(UIImage *shape, CGPoint hotspot, CGPoint position, BOOL known) {
        XCTAssertNotNil(shape); XCTAssertTrue(known);
        XCTAssertTrue(CGPointEqualToPoint(hotspot, CGPointMake(1, 0)));
        XCTAssertTrue(CGPointEqualToPoint(position, CGPointMake(5584, 1067)));
        NSData *rgba = CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(shape.CGImage)));
        XCTAssertEqualObjects(rgba, expected); [presented fulfill];
    };
    [session cursorShape:&client x:1 y:0 width:2 height:1 bytesPerPixel:4];
    [session cursorPosition:&client x:5584 y:1067]; [session publishCursor];
    [self waitForExpectations:@[presented] timeout:1];
    XCTestExpectation *retired = [self expectationWithDescription:@"Retired cursor is not presented"]; retired.inverted = YES;
    session.cursorHandler = ^(UIImage *shape, CGPoint hotspot, CGPoint position, BOOL known) { [retired fulfill]; };
    [session cursorPosition:&client x:100 y:100]; [session publishCursor]; [session stop];
    [self waitForExpectations:@[retired] timeout:.1];
    [session setValue:@NO forKey:@"running"];
}
@end
