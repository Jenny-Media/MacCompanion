#import <XCTest/XCTest.h>
#import "CompanionVNCTextReview.h"
#import "CompanionVNCTextGeometry.h"
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import <Vision/Vision.h>
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCTextReview (ScreenTextTests)
- (void)recognize;
- (void)cancelRecognition;
- (void)reselect;
- (void)copyText;
- (void)selectVisible;
- (void)returnToDesktop;
@end
@interface CompanionVNCSession (ScreenTextTests)
- (void)configureClient:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (void)processConnectedClient:(rfbClient *)client;
- (BOOL)registerSocket:(int)socket;
- (BOOL)resetBaseline:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
@end
@interface CompanionVNCViewer (ScreenTextTests)
- (void)frame:(UIImage *)frame;
- (BOOL)canCopyScreenText;
- (void)showCopyScreenText;
- (void)invalidateTextReview:(BOOL)resume;
- (void)backgroundWithCompletion:(void (^)(void))completion;
@end
@interface TextReviewOwner : CompanionVNCSession
@property NSInteger suspensions, resumptions;
@end
@implementation TextReviewOwner
- (BOOL)running { return YES; }
- (BOOL)connected { return YES; }
- (BOOL)suspendInputForReview:(void (^)(void))completion { self.suspensions++; completion(); return YES; }
- (void)resumeInputAfterReview { self.resumptions++; }
@end

@interface ScreenTextTests : XCTestCase
@end
@implementation ScreenTextTests
- (UIImage *)image:(CGSize)size scale:(CGFloat)scale text:(NSString *)text {
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat]; format.scale=scale;
    return [[[UIGraphicsImageRenderer alloc] initWithSize:size format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [UIColor.whiteColor setFill]; UIRectFill((CGRect){CGPointZero,size});
        [text drawInRect:CGRectMake(24,24,size.width-48,size.height-48) withAttributes:@{
            NSFontAttributeName:[UIFont monospacedSystemFontOfSize:28 weight:UIFontWeightRegular], NSForegroundColorAttributeName:UIColor.blackColor}];
    }];
}
- (CompanionVNCTextReview *)review:(UIImage *)image rect:(CGRect)rect {
    CompanionVNCTextReview *review=[[CompanionVNCTextReview alloc] initWithImage:image visibleRect:rect];
    [review loadViewIfNeeded]; review.view.frame=CGRectMake(0,0,440,956); [review.view layoutIfNeeded]; return review;
}
- (void)waitForRecognition:(CompanionVNCTextReview *)review {
    XCTestExpectation *done=[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings) {
        return ![[review valueForKey:@"busy"] boolValue];
    }] object:review];
    [self waitForExpectations:@[done] timeout:20];
}
- (void)settleLayout:(CompanionVNCTextReview *)review {
    [review.view setNeedsLayout]; [review.view layoutIfNeeded];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.1]];
    [review.view layoutIfNeeded];
}
- (void)assertButtonTitlesFit:(UIView *)view {
    if (view.hidden) return;
    if ([view isKindOfClass:UIButton.class]) {
        UIButton *button=(id)view;
        if (button.titleLabel.text.length) {
            CGRect title=[button.titleLabel convertRect:button.titleLabel.bounds toView:button];
            XCTAssertTrue(CGRectContainsRect(CGRectInset(button.bounds,-1,-1),title),@"Clipped button: %@",button.titleLabel.text);
            CGSize needed=[button.titleLabel sizeThatFits:CGSizeMake(button.titleLabel.bounds.size.width,CGFLOAT_MAX)];
            XCTAssertGreaterThanOrEqual(button.titleLabel.bounds.size.height+1,needed.height,@"Truncated button: %@",button.titleLabel.text);
        }
    }
    for (UIView *child in view.subviews) [self assertButtonTitlesFit:child];
}
- (void)testOriginalRetinaPixelsVisibleCropAndAccessibleZoomControls {
    UIImage *image=[self image:CGSizeMake(800,600) scale:2 text:@"Synthetic only"];
    CGRect visible=CGRectMake(200,120,400,300);
    CompanionVNCTextReview *review=[self review:image rect:visible];
    UIView *crop=[review valueForKey:@"crop"]; UIImageView *original=[crop valueForKey:@"imageView"];
    XCTAssertEqual(original.bounds.size.width,1600); XCTAssertEqual(original.bounds.size.height,1200);
    XCTAssertTrue(CGRectEqualToRect([[crop valueForKey:@"selection"] CGRectValue],visible));
    UIScrollView *scroll=[crop valueForKey:@"scroll"];
    scroll.zoomScale=scroll.minimumZoomScale*4; scroll.contentOffset=CGPointMake(75,90);
    CGRect expected=CompanionVNCTextPixelRect(original.bounds.size,[scroll convertRect:scroll.bounds toView:original]);
    [review selectVisible];
    XCTAssertTrue(CGRectEqualToRect([[crop valueForKey:@"selection"] CGRectValue],expected));
    for (UIButton *handle in [crop valueForKey:@"handles"]) {
        XCTAssertEqual(handle.bounds.size.width,44); XCTAssertEqual(handle.bounds.size.height,44);
        XCTAssertEqual(handle.accessibilityCustomActions.count,2);
    }
    [review invalidate]; XCTAssertNil(original.image);
}
- (void)testAccurateOfflineRecognitionAtOneAndTwoPixelScalesAndEditableCopy {
    for (NSNumber *scale in @[@1,@2]) {
        UIImage *image=[self image:CGSizeMake(760,280) scale:scale.doubleValue text:@"https://example.test/path?x=1\n    return value_42;\n你好世界"];
        CompanionVNCTextReview *review=[self review:image rect:CGRectMake(0,0,760*scale.doubleValue,280*scale.doubleValue)];
        [review recognize]; VNRecognizeTextRequest *request=[review valueForKey:@"request"];
        XCTAssertFalse(request.usesLanguageCorrection); XCTAssertTrue(request.automaticallyDetectsLanguage);
        [self waitForRecognition:review];
        UITextView *editor=[review valueForKey:@"editor"];
        XCTAssertTrue([editor.text containsString:@"example.test/path?x=1"],@"%@",editor.text);
        XCTAssertTrue([editor.text containsString:@"return value_42"],@"%@",editor.text);
        XCTAssertTrue([editor.text containsString:@"你好"],@"%@",editor.text);
        XCTAssertNotNil(((UIImageView *)[review valueForKey:@"preview"]).image);
        editor.text=@"Edited synthetic result"; [review copyText];
        XCTAssertEqualObjects(UIPasteboard.generalPasteboard.string,editor.text);
        XCTAssertFalse([[review valueForKey:@"invalidated"] boolValue]);
        [review reselect]; XCTAssertEqualObjects(editor.text,@"");
        XCTAssertNil(((UIImageView *)[review valueForKey:@"preview"]).image); [review invalidate];
    }
    UIPasteboard.generalPasteboard.items=@[];
}
- (void)testEmptyBoundedAndCancelledRecognitionNeverRestoresRetiredContent {
    CompanionVNCTextReview *review=[self review:[self image:CGSizeMake(200,100) scale:1 text:@""] rect:CGRectMake(0,0,200,100)];
    [review recognize]; [self waitForRecognition:review];
    XCTAssertTrue([((UILabel *)[review valueForKey:@"status"]).text containsString:@"No text found"]);
    [review recognize]; NSUInteger token=[[review valueForKey:@"generation"] unsignedIntegerValue];
    [review cancelRecognition]; XCTAssertGreaterThan([[review valueForKey:@"generation"] unsignedIntegerValue],token);
    [review recognize]; [review invalidate];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.2]];
    XCTAssertNil([review valueForKey:@"snapshot"]); XCTAssertNil(((UIImageView *)[review valueForKey:@"preview"]).image);
    XCTAssertEqualObjects(((UITextView *)[review valueForKey:@"editor"]).text,@"");
    XCTAssertFalse([[review valueForKey:@"busy"] boolValue]);
    CompanionVNCTextReview *large=[self review:[self image:CGSizeMake(8200,2) scale:1 text:@""] rect:CGRectMake(0,0,8200,2)];
    [large recognize]; XCTAssertFalse([[large valueForKey:@"busy"] boolValue]);
    XCTAssertTrue([((UILabel *)[large valueForKey:@"status"]).text containsString:@"smaller area"]); [large invalidate];
}
- (void)testPortraitLandscapeTabletAndLargeTextReviewLayouts {
    CompanionVNCTextReview *review=[self review:[self image:CGSizeMake(760,280) scale:1 text:@"Synthetic dialog\nReview before copying"] rect:CGRectMake(0,0,760,280)];
    UIWindowScene *scene=(id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous=nil; for (UIWindow *candidate in scene.windows) if (candidate.isKeyWindow) previous=candidate;
    UIViewController *holder=[UIViewController new]; [holder addChildViewController:review];
    [holder.view addSubview:review.view]; [review didMoveToParentViewController:holder];
    UIWindow *window=[[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController=holder; [window makeKeyAndVisible];
    NSArray *sizes=@[[NSValue valueWithCGSize:CGSizeMake(440,956)], [NSValue valueWithCGSize:CGSizeMake(956,440)],
                    [NSValue valueWithCGSize:CGSizeMake(1024,768)], [NSValue valueWithCGSize:CGSizeMake(440,956)]];
    NSString *folder=@"/private/tmp/maccompanion-copy-text-review-20261011/visuals";
    [[NSFileManager defaultManager] createDirectoryAtPath:folder withIntermediateDirectories:YES attributes:nil error:NULL];
    for (NSUInteger result=0; result<2; result++) {
        if (result) { [review recognize]; [self waitForRecognition:review]; }
        for (NSUInteger i=0;i<sizes.count;i++) {
            review.traitOverrides.preferredContentSizeCategory=i==3 ? UIContentSizeCategoryAccessibilityExtraExtraExtraLarge : UIContentSizeCategoryLarge;
            review.view.frame=(CGRect){CGPointZero,[sizes[i] CGSizeValue]}; [self settleLayout:review];
            UIStackView *stack=[review valueForKey:@"bodyStack"];
            XCTAssertFalse(stack.hasAmbiguousLayout); XCTAssertGreaterThan(stack.bounds.size.height,0);
            XCTAssertGreaterThan(((UIScrollView *)[review valueForKey:@"contentScroll"]).bounds.size.height,0);
            UIButton *back=[review valueForKey:@"returnButton"];
            XCTAssertTrue(CGRectContainsRect(review.view.bounds,back.frame)); XCTAssertGreaterThanOrEqual(back.bounds.size.height,44);
            [self assertButtonTitlesFit:review.view];
            UIView *crop=[review valueForKey:@"crop"]; XCTAssertFalse(crop.hasAmbiguousLayout);
            UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:review.view.bounds.size];
            UIImage *capture=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){ [review.view.layer renderInContext:context.CGContext]; }];
            [UIImagePNGRepresentation(capture) writeToFile:[folder stringByAppendingPathComponent:[NSString stringWithFormat:@"%lu-%lu.png",(unsigned long)result,(unsigned long)i]] atomically:YES];
        }
    }
    UITextView *editor=[review valueForKey:@"editor"]; XCTAssertTrue([editor becomeFirstResponder]);
    XCTestExpectation *keyboard=[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings) {
        return review.view.keyboardLayoutGuide.layoutFrame.size.height>100;
    }] object:review];
    [self waitForExpectations:@[keyboard] timeout:5]; [self settleLayout:review];
    UIButton *back=[review valueForKey:@"returnButton"];
    XCTAssertTrue(CGRectContainsRect(review.view.bounds,back.frame));
    XCTAssertLessThanOrEqual(CGRectGetMaxY(back.frame),CGRectGetMinY(review.view.keyboardLayoutGuide.layoutFrame)-7);
    [self assertButtonTitlesFit:review.view]; [editor resignFirstResponder];
    [review invalidate]; window.hidden=YES; window.rootViewController=nil; [previous makeKeyAndVisible];
}
- (void)testViewerCapturesCurrentDisplayAndRetiresOnBackgroundReplacementAndReturn {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame=CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
    TextReviewOwner *owner=[TextReviewOwner new]; viewer.session=owner;
    [viewer setValue:@YES forKey:@"foreground"];
    [viewer frame:[self image:CGSizeMake(800,600) scale:1 text:@"Synthetic"]];
    viewer.inputOnly=YES; XCTAssertFalse([viewer canCopyScreenText]); viewer.inputOnly=NO;
    [viewer showCopyScreenText]; CompanionVNCTextReview *review=[viewer valueForKey:@"textReview"];
    XCTAssertNotNil(review); XCTAssertEqual(owner.suspensions,1);
    XCTAssertEqual(CGImageGetWidth(((UIImage *)[review valueForKey:@"snapshot"]).CGImage),800);
    // A changing live framebuffer must not replace frozen pixels.
    [viewer frame:[self image:CGSizeMake(400,300) scale:1 text:@"Changed"]];
    XCTAssertEqual(CGImageGetWidth(((UIImage *)[review valueForKey:@"snapshot"]).CGImage),800);
    [viewer setValue:@300 forKey:@"keyboardOverlap"];
    [review returnToDesktop]; XCTAssertEqualObjects([viewer valueForKey:@"keyboardOverlap"],@0); XCTAssertNil([viewer valueForKey:@"textReview"]); XCTAssertEqual(owner.resumptions,1);
    [viewer frame:[self image:CGSizeMake(400,300) scale:1 text:@"Changed"]];
    XCTAssertFalse([[viewer valueForKey:@"textReviewViewportPending"] boolValue]);
    [viewer showCopyScreenText]; review=[viewer valueForKey:@"textReview"];
    [viewer backgroundWithCompletion:nil]; XCTAssertNil([viewer valueForKey:@"textReview"]); XCTAssertNil([review valueForKey:@"snapshot"]);
    [viewer setValue:@YES forKey:@"foreground"]; [viewer showCopyScreenText]; review=[viewer valueForKey:@"textReview"];
    [viewer prepareConnection]; XCTAssertNil([viewer valueForKey:@"textReview"]); XCTAssertNil([review valueForKey:@"snapshot"]);
    [viewer stopViewer];
}
- (void)testSocketOwnerReleasesKeysThenKeepsFramesFlowingAndRequiresFreshResumeFrame {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    struct timeval timeout={.tv_sec=2}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=2; client->height=2; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0]|=(1<<rfbKeyEvent)|(1<<rfbPointerEvent)|(1<<rfbFramebufferUpdateRequest);
    rfbClientSetUpdateRect(client,NULL); client->GotFrameBufferUpdate(client,0,0,2,2);
    [session setValue:@YES forKey:@"baselinePresented"]; [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    [session registerSocket:pair[0]]; [[session valueForKey:@"heldKeys"] addObject:@0xffe1];
    [session key:0x61 down:YES];
    XCTestExpectation *released=[self expectationWithDescription:@"Held input released before review"];
    XCTAssertTrue([session suspendInputForReview:^{ [released fulfill]; }]);
    XCTAssertFalse([session tryClickX:1 y:1 mask:1]); XCTAssertFalse(([session tryKeyEvents:@[@{@"key":@0x61,@"down":@YES}]]));
    [session pointerX:1 y:1 mask:1]; [session key:0x62 down:YES];
    XCTAssertEqual(((NSArray *)[session valueForKey:@"events"]).count,0);
    XCTestExpectation *ended=[self expectationWithDescription:@"Socket owner ended"]; __weak CompanionVNCSession *weak=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){ if (!weak.running) [ended fulfill]; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
    uint8_t release[14]; XCTAssertEqual(recv(pair[1],release,14,MSG_WAITALL),14);
    XCTAssertEqual(release[0],rfbKeyEvent); XCTAssertEqual(release[1],0); XCTAssertEqual(release[8],rfbPointerEvent); XCTAssertEqual(release[9],0);
    [self waitForExpectations:@[released] timeout:2]; XCTAssertTrue(session.connected);
    uint8_t frame[]={0,0,0,1,0,0,0,0,0,2,0,2,0,0,0,0, 0,0,255,0,0,0,255,0,0,0,255,0,0,0,255,0};
    XCTestExpectation *duringReview=[self expectationWithDescription:@"Frames continue during review"];
    session.frameHandler=^(UIImage *image){[duringReview fulfill];}; XCTAssertEqual(write(pair[1],frame,sizeof(frame)),sizeof(frame));
    [self waitForExpectations:@[duringReview] timeout:2]; session.frameHandler=nil;
    uint8_t request[10]; XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10); XCTAssertEqual(request[1],1);
    [session resumeInputAfterReview]; XCTAssertFalse(session.connected); XCTAssertFalse([session tryClickX:1 y:1 mask:1]);
    XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10); XCTAssertEqual(request[0],rfbFramebufferUpdateRequest); XCTAssertEqual(request[1],0);
    XCTestExpectation *fresh=[self expectationWithDescription:@"Fresh complete frame reopens input"];
    session.frameHandler=^(UIImage *image){[fresh fulfill];}; XCTAssertEqual(write(pair[1],frame,sizeof(frame)),sizeof(frame));
    [self waitForExpectations:@[fresh] timeout:2]; XCTAssertTrue(session.connected);
    session.frameHandler=nil; [session stop]; [self waitForExpectations:@[ended] timeout:3]; session.stateHandler=nil; close(pair[1]);
}
- (void)testFrameReceivedBeforeOwnerResetsBaselineCannotReopenInput {
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->width=2; client->height=2; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->GotFrameBufferUpdate(client,0,0,2,2);
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    XCTAssertTrue([session suspendInputForReview:nil]); [session resumeInputAfterReview];
    XCTestExpectation *old=[self expectationWithDescription:@"Old complete coverage does not satisfy resume"]; old.inverted=YES;
    session.frameHandler=^(UIImage *image){ [old fulfill]; }; [session publishFrame:client];
    [self waitForExpectations:@[old] timeout:.05]; XCTAssertFalse(session.connected);
    [session setValue:@NO forKey:@"resumeRequested"]; XCTAssertTrue([session resetBaseline:client]);
    client->GotFrameBufferUpdate(client,0,0,2,1); [session publishFrame:client]; XCTAssertFalse(session.connected);
    XCTestExpectation *fresh=[self expectationWithDescription:@"Only complete fresh coverage admits input"];
    session.frameHandler=^(UIImage *image){ [fresh fulfill]; }; client->GotFrameBufferUpdate(client,0,1,2,1); [session publishFrame:client];
    [self waitForExpectations:@[fresh] timeout:1]; XCTAssertTrue(session.connected);
    session.frameHandler=nil; [session setValue:@NO forKey:@"running"]; client->frameBuffer=NULL; rfbClientCleanup(client);
}
@end
