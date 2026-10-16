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
+ (BOOL)prefersNativeSelectionForSize:(CGSize)size supported:(BOOL)supported;
- (void)recognize;
- (void)cancelRecognition;
- (void)reselect;
- (void)copyText;
- (void)selectVisible;
- (void)selectArea;
- (void)editText;
- (void)nativeSelectionChanged;
- (void)scheduleRecognition;
- (void)returnToDesktop;
- (void)textViewDidChange:(UITextView *)textView;
@end
@interface UIView (ScreenTextDragTests)
- (void)moveSelection:(UIPanGestureRecognizer *)gesture;
- (void)resize:(UIPanGestureRecognizer *)gesture;
@end
@interface ScreenTextDrag : UIPanGestureRecognizer
@property(nonatomic) UIGestureRecognizerState phase;
@end
@implementation ScreenTextDrag
- (UIGestureRecognizerState)state { return self.phase; }
- (CGPoint)translationInView:(UIView *)view { return CGPointZero; }
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
- (void)showTextComposer;
- (void)invalidateTextReview:(BOOL)resume;
- (void)backgroundWithCompletion:(void (^)(void))completion;
@end
@interface TextReviewOwner : CompanionVNCSession
@property NSInteger suspensions, resumptions;
@end
@implementation TextReviewOwner
- (BOOL)running { return YES; }
- (BOOL)established { return YES; }
- (BOOL)connected { return YES; }
- (BOOL)desktopFrameReady { return YES; }
- (BOOL)suspendInputForReview:(void (^)(void))completion { self.suspensions++; completion(); return YES; }
- (void)resumeInputAfterReview { self.resumptions++; }
@end
@interface DelayedTextReviewOwner : CompanionVNCSession
@property(nonatomic,copy) void (^acknowledgeRelease)(void);
@end
@implementation DelayedTextReviewOwner
- (BOOL)suspendInputForReview:(void (^)(void))completion {
    BOOL suspended=[super suspendInputForReview:nil];
    if (suspended) self.acknowledgeRelease=completion;
    return suspended;
}
@end

@interface ScreenTextTests : XCTestCase
@end
@implementation ScreenTextTests
- (NSDictionary *)profile {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
}
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
    [review loadViewIfNeeded]; [review selectArea]; review.view.frame=CGRectMake(0,0,440,956); [review.view layoutIfNeeded]; return review;
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
- (void)testManifestIndexedSelectionAvailabilityAndPixelBounds {
    for (NSDictionary *entry in [self profile][@"copyTextInteractionCases"]) {
        NSArray *size=entry[@"size"];
        BOOL native=[CompanionVNCTextReview prefersNativeSelectionForSize:CGSizeMake([size[0] doubleValue],[size[1] doubleValue]) supported:[entry[@"nativeSupported"] boolValue]];
        XCTAssertEqual(native,[entry[@"initialMode"] isEqual:@"text"],@"%@",entry[@"name"]);
    }
}
- (void)testDefaultSelectionUsesNativeInteractionWhenAvailableAndNeverExportsAutomatically {
    NSInteger clipboardChanges=UIPasteboard.generalPasteboard.changeCount;
    CompanionVNCTextReview *review=[[CompanionVNCTextReview alloc] initWithImage:[self image:CGSizeMake(760,280) scale:1 text:@"mini.local"] visibleRect:CGRectMake(0,0,760,280)];
    [review loadViewIfNeeded];
    id native=[review valueForKey:@"nativeSelection"]; UIView *crop=[review valueForKey:@"crop"];
    XCTAssertEqual([[review valueForKey:@"areaMode"] boolValue],native==nil);
    XCTAssertEqual([[crop valueForKey:@"selectionEnabled"] boolValue],native==nil);
    XCTAssertEqual(((UIScrollView *)[crop valueForKey:@"scroll"]).panGestureRecognizer.minimumNumberOfTouches,1);
    XCTAssertFalse([[review valueForKey:@"busy"] boolValue]);
    XCTAssertFalse(((UIButton *)[review valueForKey:@"exportButton"]).enabled);
    XCTAssertEqual(UIPasteboard.generalPasteboard.changeCount,clipboardChanges);
    XCTAssertEqualObjects(((UIButton *)[review valueForKey:@"returnButton"]).configuration.title,@"Done");
    [review invalidate]; UIPasteboard.generalPasteboard.items=@[];
}
- (void)testAutomaticAreaRecognitionShowsEditableReviewWithoutAnExtraRecognizeStep {
    CompanionVNCTextReview *review=[self review:[self image:CGSizeMake(760,280) scale:2 text:@"mini.local\nError: Connection refused"] rect:CGRectMake(0,0,1520,560)];
    [review viewDidAppear:NO];
    XCTestExpectation *read=[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings) {
        return [((UITextView *)[review valueForKey:@"editor"]).text containsString:@"mini.local"];
    }] object:review];
    [self waitForExpectations:@[read] timeout:20];
    XCTAssertFalse(((UIView *)[review valueForKey:@"crop"]).hidden);
    XCTAssertTrue([[review valueForKey:@"editorOpen"] boolValue]);
    UITextView *editor=[review valueForKey:@"editor"]; editor.text=@"Reviewed synthetic text"; [review copyText];
    XCTAssertEqualObjects(UIPasteboard.generalPasteboard.string,editor.text);
    [review editText]; XCTAssertTrue(editor.hidden); [review editText]; XCTAssertEqualObjects(editor.text,@"Reviewed synthetic text");
    [review invalidate]; UIPasteboard.generalPasteboard.items=@[];
}
- (void)testChangingAreaImmediatelyRetiresItsOldCopyAndPendingAnalysis {
    CompanionVNCTextReview *review=[self review:[self image:CGSizeMake(760,280) scale:1 text:@"Old synthetic result"] rect:CGRectMake(0,0,760,280)];
    [review recognize]; [self waitForRecognition:review];
    XCTAssertGreaterThan(((UITextView *)[review valueForKey:@"editor"]).text.length,0);
    [review setValue:@YES forKey:@"started"];
    id crop=[review valueForKey:@"crop"]; [crop setValue:[NSValue valueWithCGRect:CGRectMake(0,0,100,100)] forKey:@"selection"];
    XCTAssertEqualObjects(((UITextView *)[review valueForKey:@"editor"]).text,@"");
    XCTAssertFalse(((UIButton *)[review valueForKey:@"exportButton"]).enabled);
    [review invalidate];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];
    XCTAssertNil([review valueForKey:@"snapshot"]); XCTAssertNil(((UIImageView *)[crop valueForKey:@"magnifier"]).image);
    XCTAssertEqualObjects(((UITextView *)[review valueForKey:@"editor"]).text,@"");
}
- (void)testNativeReviewPreservesCorrectionsUntilSelectionChanges {
    CompanionVNCTextReview *review=[[CompanionVNCTextReview alloc] initWithImage:[self image:CGSizeMake(760,280) scale:1 text:@"mini.local"] visibleRect:CGRectMake(0,0,760,280)];
    [review loadViewIfNeeded];
    if (![review valueForKey:@"nativeSelection"]) { XCTSkip(@"System Live Text unavailable"); return; }
    [review viewDidAppear:NO]; [self waitForRecognition:review];
    [review editText]; UITextView *editor=[review valueForKey:@"editor"];
    XCTAssertTrue([editor.text containsString:@"mini.local"]);
    editor.text=@"Corrected synthetic hostname";
    [review editText]; XCTAssertTrue(editor.hidden);
    [review copyText]; XCTAssertEqualObjects(UIPasteboard.generalPasteboard.string,@"Corrected synthetic hostname");
    [review editText]; XCTAssertEqualObjects(editor.text,@"Corrected synthetic hostname");
    editor.text=@""; [review editText]; [review editText];
    XCTAssertFalse(editor.hidden); XCTAssertEqualObjects(editor.text,@"");
    editor.text=[@"x" stringByPaddingToLength:65537 withString:@"x" startingAtIndex:0]; [review textViewDidChange:editor];
    UIButton *more=[review valueForKey:@"moreButton"];
    for (UIAction *action in [more.menu.children subarrayWithRange:NSMakeRange(0,2)])
        XCTAssertTrue(action.attributes & UIMenuElementAttributesDisabled);
    [review editText]; [review editText]; XCTAssertEqual(editor.text.length,65537);
    [review editText]; [review nativeSelectionChanged];
    XCTAssertFalse([[review valueForKey:@"hasNativeReview"] boolValue]);
    XCTAssertEqualObjects(editor.text,@"");
    XCTAssertFalse(((UIButton *)[review valueForKey:@"exportButton"]).enabled);
    [review editText]; XCTAssertTrue([editor.text containsString:@"mini.local"]);
    [review invalidate]; UIPasteboard.generalPasteboard.items=@[];
}
- (void)testAutomaticAreaRecognitionWaitsForDragToEnd {
    CompanionVNCTextReview *review=[self review:[self image:CGSizeMake(760,280) scale:1 text:@"mini.local"] rect:CGRectMake(0,0,760,280)];
    id crop=[review valueForKey:@"crop"];
    [crop setValue:@YES forKey:@"adjustingSelection"]; [review viewDidAppear:NO];
    [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.6]];
    XCTAssertFalse([[review valueForKey:@"busy"] boolValue]);
    XCTAssertFalse([[review valueForKey:@"editorOpen"] boolValue]);
    XCTAssertNil([review valueForKey:@"request"]);
    [crop setValue:@NO forKey:@"adjustingSelection"];
    void (^changed)(void)=[crop valueForKey:@"selectionChanged"]; changed();
    XCTestExpectation *read=[[XCTNSPredicateExpectation alloc] initWithPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings) {
        return [((UITextView *)[review valueForKey:@"editor"]).text containsString:@"mini.local"];
    }] object:review];
    [self waitForExpectations:@[read] timeout:20];
    [review invalidate];
}
- (void)testClampedDragCancelsAnInflightReadAndKeepsCropHeightUntilRelease {
    for (NSNumber *resize in @[@NO,@YES]) {
        CompanionVNCTextReview *review=[self review:[self image:CGSizeMake(760,280) scale:1 text:@"mini.local"] rect:CGRectMake(0,0,760,280)];
        [review recognize]; [self waitForRecognition:review]; [self settleLayout:review];
        UIView *crop=[review valueForKey:@"crop"]; CGRect selection=[[crop valueForKey:@"selection"] CGRectValue];
        CGFloat height=((NSLayoutConstraint *)[review valueForKey:@"cropHeight"]).constant;
        // The completed review reserves its editor height while another read runs.
        [review recognize]; XCTAssertTrue([[review valueForKey:@"busy"] boolValue]);
        NSUInteger generation=[[review valueForKey:@"generation"] unsignedIntegerValue];
        ScreenTextDrag *drag=[ScreenTextDrag new]; drag.phase=UIGestureRecognizerStateBegan;
        if (resize.boolValue) {
            UIButton *corner=((NSArray *)[crop valueForKey:@"handles"])[2]; [corner addGestureRecognizer:drag]; [crop resize:drag];
        } else { [crop addGestureRecognizer:drag]; [crop moveSelection:drag]; }
        XCTAssertTrue(CGRectEqualToRect([[crop valueForKey:@"selection"] CGRectValue],selection));
        XCTAssertGreaterThan([[review valueForKey:@"generation"] unsignedIntegerValue],generation);
        XCTAssertNil([review valueForKey:@"request"]); XCTAssertFalse([[review valueForKey:@"busy"] boolValue]);
        [self settleLayout:review];
        XCTAssertEqualWithAccuracy(((NSLayoutConstraint *)[review valueForKey:@"cropHeight"]).constant,height,.5);
        [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.5]];
        XCTAssertFalse([[review valueForKey:@"editorOpen"] boolValue]);
        drag.phase=UIGestureRecognizerStateEnded;
        if (resize.boolValue) [crop resize:drag]; else [crop moveSelection:drag];
        [self settleLayout:review];
        XCTAssertFalse([[crop valueForKey:@"adjustingSelection"] boolValue]);
        [review invalidate];
    }
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
    UIScrollView *content=[review valueForKey:@"contentScroll"];
    UILabel *status=[review valueForKey:@"status"];
    XCTAssertGreaterThan(content.bounds.size.height,80,@"The keyboard must leave a usable scroll viewport at the largest text size");
    XCTAssertGreaterThanOrEqual(status.bounds.size.height+1,[status sizeThatFits:CGSizeMake(status.bounds.size.width,CGFLOAT_MAX)].height);
    UIGraphicsImageRenderer *keyboardRenderer=[[UIGraphicsImageRenderer alloc] initWithSize:review.view.bounds.size];
    UIImage *keyboardCapture=[keyboardRenderer imageWithActions:^(UIGraphicsImageRendererContext *context){ [review.view.layer renderInContext:context.CGContext]; }];
    [UIImagePNGRepresentation(keyboardCapture) writeToFile:[folder stringByAppendingPathComponent:@"keyboard-xxxlarge.png"] atomically:YES];
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
- (void)testCopyTextAdmissionUsesCurrentOwnerBaselineRatherThanRetainedPixels {
    for (NSDictionary *entry in [self profile][@"copyTextReadinessCases"]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        viewer.view.frame=CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
        [viewer setValue:@YES forKey:@"foreground"];
        [viewer frame:[self image:CGSizeMake(800,600) scale:1 text:@"Retained synthetic desktop"]];
        [viewer prepareConnection]; CompanionVNCSession *session=viewer.session;
        // This is the authenticated replacement's state before its first frame,
        // not an overridden connected getter on a fake owner.
        [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"established"];
        session.inputOnly=[entry[@"inputOnly"] boolValue];
        [session setValue:@YES forKey:@"inputReady"];
        [session setValue:entry[@"baselinePresented"] forKey:@"baselinePresented"];
        [session setValue:entry[@"awaitingResumeFrame"] forKey:@"awaitingResumeFrame"];
        XCTAssertNotNil([viewer valueForKey:@"lastFramebuffer"]);
        BOOL expected=[entry[@"allowsCopyText"] boolValue];
        XCTAssertEqual(session.desktopFrameReady,expected,@"%@",entry[@"name"]);
        XCTAssertEqual([viewer canCopyScreenText],expected,@"%@",entry[@"name"]);
        XCTAssertEqual([session suspendInputForReview:nil],expected,@"%@",entry[@"name"]);
        XCTAssertEqual([[session valueForKey:@"reviewInputSuspended"] boolValue],expected);
        if (!expected) { [viewer showCopyScreenText]; XCTAssertNil([viewer valueForKey:@"textReview"]); }
        [viewer stopViewer]; [session setValue:@NO forKey:@"running"];
    }
}
- (void)testReconnectCopyTextWaitsForCompleteCurrentFrameAndRechecksAtSuspension {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame=CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
    [viewer setValue:@YES forKey:@"foreground"];
    UIImage *retained=[self image:CGSizeMake(800,600) scale:1 text:@"Old synthetic desktop"];
    [viewer frame:retained]; [viewer prepareConnection]; CompanionVNCSession *session=viewer.session;
    rfbClient *client=rfbGetClient(8,3,4); client->width=4; client->height=4;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    XCTAssertTrue(session.connected); XCTAssertFalse(session.desktopFrameReady);
    [viewer showCopyScreenText]; XCTAssertNil([viewer valueForKey:@"textReview"]);
    XCTAssertEqual([viewer valueForKey:@"lastFramebuffer"],retained);
    client->GotFrameBufferUpdate(client,0,0,4,2); [session publishFrame:client];
    XCTAssertFalse([viewer canCopyScreenText]); XCTAssertFalse([session suspendInputForReview:nil]);
    XCTestExpectation *presented=[self expectationWithDescription:@"Replacement's complete frame is presented"];
    void (^deliver)(UIImage *)=[session.frameHandler copy];
    session.frameHandler=^(UIImage *image){deliver(image); [presented fulfill];};
    client->GotFrameBufferUpdate(client,0,2,4,2); [session publishFrame:client];
    [self waitForExpectations:@[presented] timeout:1];
    XCTAssertTrue([viewer canCopyScreenText]);
    [viewer showCopyScreenText]; CompanionVNCTextReview *review=[viewer valueForKey:@"textReview"];
    XCTAssertNotNil(review); XCTAssertEqual(CGImageGetWidth(((UIImage *)[review valueForKey:@"snapshot"]).CGImage),4);
    [viewer invalidateTextReview:NO]; [session setValue:@NO forKey:@"reviewInputSuspended"];
    // A reset between availability checking and suspension must reject atomically.
    XCTAssertTrue(session.desktopFrameReady); XCTAssertTrue([session resetBaseline:client]);
    XCTAssertFalse([session suspendInputForReview:nil]); XCTAssertFalse([[session valueForKey:@"reviewInputSuspended"] boolValue]);
    session.frameHandler=nil; [viewer stopViewer]; [session setValue:@NO forKey:@"running"];
    client->frameBuffer=NULL; rfbClientCleanup(client);
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
- (void)testComposerAdmissionWaitsForPresentedReplacementDesktopAndRechecksReset {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"ios-text-composer-v1" withExtension:@"json"];
    NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSDictionary *policy=fixture[@"lifecycle"][@"admission"][@"replacementDesktop"];
    NSMutableArray *events=[NSMutableArray new];
    for(NSDictionary *entry in fixture[@"cases"]) if([entry[@"name"] isEqual:@"ascii"])
        for(NSNumber *key in entry[@"desktopKeys"]) for(NSNumber *down in @[@YES,@NO]) [events addObject:@{@"key":key,@"down":down}];
    XCTAssertGreaterThan(events.count,0);
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame=CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
    [viewer setValue:@YES forKey:@"foreground"];
    UIImage *retained=[self image:CGSizeMake(800,600) scale:1 text:@"Retained synthetic desktop"];
    [viewer frame:retained]; [viewer prepareConnection]; CompanionVNCSession *session=viewer.session;
    rfbClient *client=rfbGetClient(8,3,4); client->width=4; client->height=4;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for(NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    XCTAssertTrue(session.connected); XCTAssertEqual([viewer valueForKey:@"lastFramebuffer"],retained);
    void (^assertRejected)(NSString *)=^(NSString *stage) {
        XCTAssertEqual(session.composedTextReady,[policy[stage] boolValue],@"%@",stage);
        XCTAssertEqual([session tryComposedTextEvents:events completion:^(BOOL written){XCTFail(@"Unseen Desktop cannot admit text");}],
            [policy[stage] boolValue],@"%@",stage);
        XCTAssertEqual([[session valueForKey:@"events"] count],0);
    };
    assertRejected(@"beforeFirstFrame"); [viewer showTextComposer]; XCTAssertNil([viewer valueForKey:@"textComposer"]);
    client->GotFrameBufferUpdate(client,0,0,4,2); [session publishFrame:client];
    assertRejected(@"partialFrame"); [viewer showTextComposer]; XCTAssertNil([viewer valueForKey:@"textComposer"]);
    XCTestExpectation *presented=[self expectationWithDescription:@"Current replacement frame presented before composer admission"];
    void (^deliver)(UIImage *)=[session.frameHandler copy];
    session.frameHandler=^(UIImage *image) {
        assertRejected(@"completeBeforePresentation"); deliver(image); [presented fulfill];
    };
    client->GotFrameBufferUpdate(client,0,2,4,2); [session publishFrame:client];
    [self waitForExpectations:@[presented] timeout:1];
    XCTAssertEqual(session.composedTextReady,[policy[@"presentedCurrentFrame"] boolValue]);
    XCTestExpectation *retired=[self expectationWithDescription:@"Reset retires the admitted composer group once"];
    __block NSUInteger replies=0;
    XCTAssertEqual([session tryComposedTextEvents:events completion:^(BOOL written){replies++; XCTAssertFalse(written); [retired fulfill];}],
        [policy[@"presentedCurrentFrame"] boolValue]);
    XCTAssertTrue([session resetBaseline:client]); assertRejected(@"afterBaselineReset");
    [self waitForExpectations:@[retired] timeout:1]; XCTAssertEqual(replies,1);
    session.frameHandler=nil; [viewer stopViewer]; [session setValue:@NO forKey:@"running"];
    client->frameBuffer=NULL; rfbClientCleanup(client);
}
- (void)testTrackpadComposerAdmitsWithoutDesktopPixelsOnAuthenticatedOwner {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"ios-text-composer-v1" withExtension:@"json"];
    NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSMutableArray *events=[NSMutableArray new];
    for(NSDictionary *entry in fixture[@"cases"]) if([entry[@"name"] isEqual:@"ascii"])
        for(NSNumber *key in entry[@"desktopKeys"]) for(NSNumber *down in @[@YES,@NO]) [events addObject:@{@"key":key,@"down":down}];
    CompanionVNCSession *session=[CompanionVNCSession new]; session.inputOnly=YES;
    for(NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    XCTAssertFalse(session.desktopFrameReady); XCTAssertEqualObjects([session valueForKey:@"baselinePresented"],@NO);
    BOOL admitted=[fixture[@"lifecycle"][@"admission"][@"trackpadWithoutPixels"] boolValue];
    XCTAssertEqual(session.composedTextReady,admitted);
    XCTestExpectation *retired=[self expectationWithDescription:@"Unwritten Trackpad composer group retires"];
    XCTAssertEqual([session tryComposedTextEvents:events completion:^(BOOL written){XCTAssertFalse(written); [retired fulfill];}],admitted);
    [session pauseWithCompletion:nil]; XCTAssertFalse(session.composedTextReady);
    [self waitForExpectations:@[retired] timeout:1];
    [session stop]; [session setValue:@NO forKey:@"running"];
}
- (void)testReviewAndBaselineResetCancelQueuedComposedTextOnce {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"ios-text-composer-v1" withExtension:@"json"];
    NSDictionary *fixture=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSDictionary *policy=fixture[@"lifecycle"][@"screenTextReview"];
    NSMutableArray *events=[NSMutableArray new];
    for(NSDictionary *entry in fixture[@"cases"]) if([entry[@"name"] isEqual:@"ascii"])
        for(NSNumber *key in entry[@"desktopKeys"]) for(NSNumber *down in @[@YES,@NO]) [events addObject:@{@"key":key,@"down":down}];
    XCTAssertGreaterThan(events.count,0);
    for(NSNumber *reviewBoundary in @[@YES,@NO]) {
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->width=2; client->height=2; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        for(NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
        XCTestExpectation *cancelled=[self expectationWithDescription:@"Queued composed send completes as interrupted"];
        __block NSUInteger replies=0;
        XCTAssertTrue([session tryComposedTextEvents:events completion:^(BOOL written){
            replies++; XCTAssertEqual(written,[policy[@"cancelQueuedCompletionWritten"] boolValue]); [cancelled fulfill];
        }]);
        if(reviewBoundary.boolValue) XCTAssertTrue([session suspendInputForReview:nil]);
        else XCTAssertTrue([session resetBaseline:client]);
        [self waitForExpectations:@[cancelled] timeout:1];
        XCTAssertEqual([[session valueForKey:@"events"] count],0);
        XCTAssertEqual([[session valueForKey:@"composedTextReplies"] count],[policy[@"repliesAfterReview"] unsignedIntegerValue]);
        XCTAssertEqual([session tryComposedTextEvents:events completion:^(BOOL written){XCTFail(@"Closed input gate must reject composer");}],
            [policy[@"allowsSendDuringReview"] boolValue]);
        [session stop]; XCTAssertEqual(replies,1); [session setValue:@NO forKey:@"running"];
        client->frameBuffer=NULL; rfbClientCleanup(client);
    }
}
- (void)testFrameReceivedBeforeOwnerResetsBaselineCannotReopenInput {
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->width=2; client->height=2; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->GotFrameBufferUpdate(client,0,0,2,2);
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    [session setValue:@YES forKey:@"baselinePresented"];
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
- (void)testBackgroundDuringReviewReturnRetainsSocketAndResumesWithFreshPixels {
    NSDictionary *policy=nil;
    for (NSDictionary *entry in [self profile][@"lifecycleCases"]) if ([entry[@"name"] isEqual:@"background established while review return frame pending"]) policy=entry;
    XCTAssertNotNil(policy);
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    struct timeval timeout={.tv_sec=2}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=2; client->height=2;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0]|=(1<<rfbKeyEvent)|(1<<rfbPointerEvent)|(1<<rfbFramebufferUpdateRequest);
    rfbClientSetUpdateRect(client,NULL); client->GotFrameBufferUpdate(client,0,0,2,2);
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
    [session registerSocket:pair[0]];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame=CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded]; viewer.session=session;
    [viewer setValue:@YES forKey:@"foreground"]; [viewer frame:[self image:CGSizeMake(2,2) scale:1 text:@""]];
    __block NSUInteger disconnects=0; viewer.disconnectHandler=^{disconnects++;};
    [viewer showCopyScreenText]; CompanionVNCTextReview *review=[viewer valueForKey:@"textReview"]; XCTAssertNotNil(review);
    XCTestExpectation *ended=[self expectationWithDescription:@"Retained owner ends on explicit exit"];
    __weak CompanionVNCSession *weak=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){if(!weak.running)[ended fulfill];};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
    uint8_t pointer[6]; XCTAssertEqual(recv(pair[1],pointer,6,MSG_WAITALL),6); XCTAssertEqual(pointer[0],rfbPointerEvent);
    [review returnToDesktop]; XCTAssertFalse(session.connected); XCTAssertTrue(session.established);
    XCTestExpectation *paused=[self expectationWithDescription:@"Background acknowledges release during fresh-frame wait"];
    [viewer backgroundWithCompletion:^{[paused fulfill];}];
    // A full refresh may have been sent just before background took ownership.
    BOOL released=NO;
    for (NSUInteger packet=0; packet<2 && !released; packet++) {
        uint8_t type=255; XCTAssertEqual(recv(pair[1],&type,1,MSG_WAITALL),1);
        if (type==rfbFramebufferUpdateRequest) {uint8_t rest[9]; XCTAssertEqual(recv(pair[1],rest,9,MSG_WAITALL),9);}
        else {XCTAssertEqual(type,rfbPointerEvent); uint8_t rest[5]; XCTAssertEqual(recv(pair[1],rest,5,MSG_WAITALL),5); XCTAssertEqual(rest[0],0); released=YES;}
    }
    XCTAssertTrue(released); [self waitForExpectations:@[paused] timeout:2];
    XCTAssertEqual(session.established,[policy[@"retainsSocket"] boolValue]); XCTAssertTrue(session.running);
    XCTAssertTrue([[session valueForKey:@"paused"] boolValue]); XCTAssertEqual(disconnects,0);
    XCTAssertEqual([session tryClickX:1 y:1 mask:1],[policy[@"allowsInput"] boolValue]);
    [viewer foregrounded]; XCTAssertTrue(session.established); XCTAssertFalse(session.connected);
    uint8_t request[10]; XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10); XCTAssertEqual(request[0],rfbFramebufferUpdateRequest); XCTAssertEqual(request[1],0);
    XCTestExpectation *fresh=[self expectationWithDescription:@"Fresh pixels from the same socket reopen input"];
    session.frameHandler=^(UIImage *image){[viewer frame:image]; [fresh fulfill];};
    uint8_t frame[]={0,0,0,1,0,0,0,0,0,2,0,2,0,0,0,0, 0,0,255,0,0,0,255,0,0,0,255,0,0,0,255,0};
    XCTAssertEqual(write(pair[1],frame,sizeof(frame)),sizeof(frame));
    [self waitForExpectations:@[fresh] timeout:2]; XCTAssertTrue(session.connected); XCTAssertEqual(viewer.session,session);
    session.frameHandler=nil; viewer.disconnectHandler=nil; [viewer stopViewer];
    [self waitForExpectations:@[ended] timeout:2]; session.stateHandler=nil; close(pair[1]);
}
- (void)testBaselineResetDuringPresentationCannotReopenInputUntilCurrentFrame {
    for (NSDictionary *entry in [self profile][@"framePresentationCases"]) {
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->width=[entry[@"before"][0] intValue]; client->height=[entry[@"before"][1] intValue];
        [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        client->GotFrameBufferUpdate(client,0,0,client->width,client->height);
        for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
        if ([entry[@"reviewReturn"] boolValue]) {
            XCTAssertTrue([session suspendInputForReview:nil]); [session resumeInputAfterReview];
            [session setValue:@NO forKey:@"resumeRequested"]; XCTAssertTrue([session resetBaseline:client]);
            client->GotFrameBufferUpdate(client,0,0,client->width,client->height);
        } else { XCTAssertTrue([session tryClickX:1 y:1 mask:1]); }
        XCTestExpectation *reset=[self expectationWithDescription:entry[@"name"]];
        session.frameHandler=^(UIImage *image){
            NSUInteger epoch=[[session valueForKey:@"presentationEpoch"] unsignedIntegerValue];
            // Inject the socket-owner reset precisely between validation and readiness commit.
            client->width=[entry[@"after"][0] intValue]; client->height=[entry[@"after"][1] intValue];
            XCTAssertTrue([session allocate:client]);
            XCTAssertGreaterThan([[session valueForKey:@"presentationEpoch"] unsignedIntegerValue],epoch);
            [reset fulfill];
        };
        [session publishFrame:client]; [self waitForExpectations:@[reset] timeout:1];
        XCTAssertEqual([[session valueForKey:@"expectedPixels"] unsignedIntegerValue],client->width*client->height);
        XCTAssertEqualObjects([session valueForKey:@"receivedPixels"],@0);
        XCTAssertFalse([[session valueForKey:@"baselinePresented"] boolValue]); XCTAssertTrue(session.established);
        XCTAssertEqual([session tryClickX:1 y:1 mask:1],[entry[@"allowsInputAfterReset"] boolValue]);
        XCTAssertEqual([[session valueForKey:@"events"] count],0);
        client->GotFrameBufferUpdate(client,0,0,client->width,client->height/2);
        [session publishFrame:client]; XCTAssertFalse(session.connected);
        XCTestExpectation *fresh=[self expectationWithDescription:@"Only the current complete baseline reopens input"];
        session.frameHandler=^(UIImage *image){[fresh fulfill];}; [session setValue:@0 forKey:@"lastFrame"];
        client->GotFrameBufferUpdate(client,0,client->height/2,client->width,client->height-client->height/2);
        [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:1];
        XCTAssertEqual([session tryClickX:1 y:1 mask:1],[entry[@"allowsInputAfterCurrentFrame"] boolValue]);
        session.frameHandler=nil; [session setValue:@NO forKey:@"running"]; client->frameBuffer=NULL; rfbClientCleanup(client);
    }
}
- (void)testDelayedReleaseStillPresentsFrozenReviewAfterDisplayReset {
    DelayedTextReviewOwner *session=[DelayedTextReviewOwner new]; rfbClient *client=rfbGetClient(8,3,4);
    client->width=800; client->height=600; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded]; viewer.session=session;
    UIWindowScene *scene=(id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous=nil; for (UIWindow *candidate in scene.windows) if(candidate.isKeyWindow) previous=candidate;
    UIWindow *window=[[UIWindow alloc] initWithWindowScene:scene]; window.rootViewController=viewer; [window makeKeyAndVisible];
    [viewer.view layoutIfNeeded]; [viewer setValue:@YES forKey:@"foreground"];
    [viewer frame:[self image:CGSizeMake(800,600) scale:1 text:@"Synthetic"]];
    [viewer showCopyScreenText]; CompanionVNCTextReview *review=[viewer valueForKey:@"textReview"];
    XCTAssertNotNil(review); XCTAssertNil(viewer.presentedViewController); XCTAssertNotNil(session.acknowledgeRelease);
    client->width=400; client->height=300; XCTAssertTrue([session allocate:client]);
    XCTAssertTrue(session.established); XCTAssertFalse(session.connected);
    session.acknowledgeRelease(); session.acknowledgeRelease=nil;
    XCTAssertEqual(viewer.presentedViewController,review);
    XCTAssertEqual(CGImageGetWidth(((UIImage *)[review valueForKey:@"snapshot"]).CGImage),800);
    XCTAssertFalse([session tryClickX:1 y:1 mask:1]);
    // Let UIKit finish presentation before retiring this test-owned window.
    NSDate *deadline=[NSDate dateWithTimeIntervalSinceNow:3];
    while(viewer.transitionCoordinator && deadline.timeIntervalSinceNow>0) [[NSRunLoop mainRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:.01]];
    [viewer stopViewer]; [session setValue:@NO forKey:@"running"];
    window.hidden=YES; window.rootViewController=nil; [previous makeKeyAndVisible];
    client->frameBuffer=NULL; rfbClientCleanup(client);
}
@end
