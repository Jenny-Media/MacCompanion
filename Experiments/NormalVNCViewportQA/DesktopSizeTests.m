#import <XCTest/XCTest.h>
#import "CompanionVNCViewer.h"
#import "CompanionVNCDesktopSize.h"
#import "CompanionVNCControls.h"
#import "CompanionVNCDisplayPicker.h"
#import "CompanionVNCMenu.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>
#import <fcntl.h>
static rfbBool RejectMetricRead(rfbClient *client) { (void)client; return FALSE; }
@protocol DesktopLoginRecoveryTesting <NSObject>
- (void)editWithUsername:(NSString *)username password:(NSString *)password remember:(BOOL)remember;
- (NSDictionary *)beginLogin;
- (NSDictionary *)loginForResume;
- (void)authenticated;
@end
@interface CompanionVNCSession (PrototypeTesting)
- (BOOL)requestDesktopSizeWidth:(double)width height:(double)height;
- (BOOL)requestDesktopDisplayID:(uint32_t)identifier;
- (void)configureClient:(rfbClient *)client;
- (BOOL)allocate:(rfbClient *)client;
- (BOOL)installDesktopReadService:(rfbClient *)client;
- (BOOL)processDesktopSizeChange:(rfbClient *)client;
- (BOOL)configureDesktopUpdates:(rfbClient *)client;
- (BOOL)requestFullDesktop:(rfbClient *)client;
- (BOOL)maintainDesktopBaseline:(rfbClient *)client now:(double)now;
- (BOOL)resumeDesktopPull:(rfbClient *)client;
- (void)recordDesktopSwitchLocked:(double)now;
- (BOOL)requestPendingDesktopLayout:(rfbClient *)client;
- (rfbBool)displayLayout:(rfbClient *)client encoding:(int)encoding;
- (void)updatedX:(int)x y:(int)y width:(int)width height:(int)height;
- (void)publishFrame:(rfbClient *)client;
- (void)finish:(NSString *)state;
@end
@interface CompanionVNCControls (DesktopMenuTesting)
- (void)open;
@end
@interface DesktopMenuPan : UIPanGestureRecognizer
@property UIGestureRecognizerState sampleState;
@end
@implementation DesktopMenuPan
- (UIGestureRecognizerState)state { return self.sampleState; }
- (CGPoint)translationInView:(UIView *)view { return CGPointZero; }
- (CGPoint)velocityInView:(UIView *)view { return CGPointZero; }
@end
@interface CompanionVNCViewer (DesktopSizeTesting)
- (void)showViewMenu;
- (void)performControlAction:(NSDictionary *)action;
- (NSArray *)displayMenuSections;
- (NSArray *)inputMenuSections;
- (void)frame:(UIImage *)frame;
- (void)chooseView;
- (void)updateDisplayPicker;
- (void)prepareConnection;
- (void)reportDiagnostics:(NSDictionary *)stats;
- (void)updateConnectionChrome;
- (BOOL)pointerForGesture:(UIGestureRecognizer *)gesture point:(CGPoint *)point;
- (NSDictionary *)cursorDiagnosticFlags;
- (void)showDesktopSizeMenu;
- (void)presentMenu:(NSString *)title sections:(NSArray *)sections;
- (BOOL)applyDesktopSizePreset:(NSInteger)preset;
- (void)updateDesktopSizeState;
- (void)updateDisplayModeRestoration;
- (void)expireDisplayModeVerification:(CompanionVNCSession *)owner generation:(NSUInteger)generation;
- (void)keyboardFrame:(NSNotification *)notification;
- (BOOL)applyStreamDisplay:(NSNumber *)identifier;
- (BOOL)applyMirrorDisplay;
- (UIAlertController *)displayModeConfirmationForPreset:(NSInteger)preset;
- (BOOL)acceptDisplayModeConfirmation;
- (UIAlertController *)inputOnlyConfirmation;
- (void)cancelDisplayModeConfirmation;
- (BOOL)restartDisplayModePreset:(NSInteger)preset;
- (void)connectionAction;
- (void)loginEdited;
- (void)startResuming:(BOOL)resuming;
- (void)restoreSavedDisplay;
- (void)completeResumeReadiness;
- (void)completeDisplayModeVerified:(BOOL)verified;
@end
@interface DesktopSizeSession : CompanionVNCSession
@property BOOL usable, available;
@property NSInteger requests, lastPreset;
@property NSDictionary *snapshot;
@property NSDictionary *catalogue;
@property NSNumber *requestedDisplay;
@end
@implementation DesktopSizeSession
- (instancetype)init {
    if ((self=[super init])) { [self setValue:@3200 forKey:@"framebufferWidth"]; [self setValue:@1200 forKey:@"framebufferHeight"]; }
    return self;
}
- (BOOL)running { return YES; }
- (BOOL)established { return self.usable; }
- (BOOL)connected { return self.usable; }
- (BOOL)desktopFrameReady { return self.usable; }
- (BOOL)desktopSizeAvailable { return self.available; }
- (NSDictionary *)diagnosticCounters { return self.snapshot ?: @{}; }
- (BOOL)requestDesktopSizePreset:(NSInteger)preset { self.requests++; self.lastPreset=preset; return self.available; }
- (BOOL)requestDesktopSizePresetForHandoff:(NSInteger)preset { self.requests++; self.lastPreset=preset; return self.available && self.displayHandoffInputBlocked; }
- (NSDictionary *)desktopDisplayLayout { return self.catalogue ?: @{}; }
- (BOOL)requestDesktopDisplayID:(uint32_t)identifier { self.requestedDisplay=@(identifier); return self.available; }
@end
@interface DesktopSizeViewer : CompanionVNCViewer
@property NSString *menuTitle;
@property NSArray *menuSections;
@property BOOL requestedResume;
@end
@implementation DesktopSizeViewer
- (void)presentMenu:(NSString *)title sections:(NSArray *)sections { self.menuTitle=title; self.menuSections=sections; }
- (void)startResuming:(BOOL)resuming { self.requestedResume=resuming; [self setValue:@YES forKey:@"starting"]; }
@end
@interface DesktopSizeTests : XCTestCase
@end
@implementation DesktopSizeTests
- (DesktopSizeViewer *)viewerWithSession:(DesktopSizeSession *)session {
    DesktopSizeViewer *viewer=[DesktopSizeViewer new]; [viewer loadViewIfNeeded];
    [viewer setValue:session forKey:@"session"]; session.available=YES; session.usable=YES;
    id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
    [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin]; [login authenticated];
    return viewer;
}
- (NSDictionary *)physicalSnapshot {
    return @{@"appleDisplayProtocol":@YES,@"layoutVirtual":@NO,@"layoutCount":@2,
        @"layoutWidth":@3200,@"layoutHeight":@1200,@"framebufferWidth":@3200,@"framebufferHeight":@1200};
}
- (NSDictionary *)acceptedSnapshot {
    return @{@"probeOutcome":@2,@"layoutVirtual":@YES,@"layoutCount":@1,@"framebufferWidth":@2560,
        @"framebufferHeight":@1600,@"layoutWidth":@2560,@"layoutHeight":@1600};
}
- (void)testDesktopSizeIsDirectlyReachableAndOffersThreeLandscapeSizes {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    session.catalogue=@{@"views": @[@{@"id":@5}]}; session.snapshot=[self acceptedSnapshot];
    [viewer showViewMenu];
    NSArray *items=viewer.menuSections[0][@"items"];
    XCTAssertEqualObjects([items valueForKey:@"kind"],(@[@"virtualDisplay",@"mirrorDisplay",@"desktopSizeMenu"]));
    [viewer showDesktopSizeMenu]; XCTAssertEqualObjects(viewer.menuTitle,@"Desktop Size");
    items=viewer.menuSections[0][@"items"]; XCTAssertEqual(items.count,3);
    XCTAssertEqualObjects([items valueForKey:@"title"],(@[@"Larger Text",@"Balanced",@"More Space"]));
    XCTAssertTrue([items[1][@"subtitle"] containsString:@"Recommended"]);
    for (NSDictionary *row in items) XCTAssertFalse([row[@"disabled"] boolValue]);
    session.available=NO; [viewer showDesktopSizeMenu];
    for (NSDictionary *row in viewer.menuSections[0][@"items"]) XCTAssertTrue([row[@"disabled"] boolValue]);
    [viewer stopViewer];
}
- (NSArray *)kindsInSections:(NSArray *)sections {
    NSMutableArray *kinds=[NSMutableArray new];
    for (NSDictionary *section in sections) [kinds addObjectsFromArray:[section[@"items"] valueForKey:@"kind"]];
    return kinds;
}
- (void)testDisplayMenusOnlyOfferRelevantMonitorAndSizeChoices {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    NSArray *displays=@[@{@"id":@5},@{@"id":@1}];
    session.catalogue=@{@"views":displays}; session.snapshot=@{@"layoutVirtual":@NO};
    [viewer setValue:displays forKey:@"displayViews"];
    NSArray *mirror=[self kindsInSections:[viewer displayMenuSections]];
    XCTAssertTrue([mirror containsObject:@"displays"]); XCTAssertTrue([mirror containsObject:@"virtualDisplay"]); XCTAssertTrue([mirror containsObject:@"mirrorDisplay"]);
    XCTAssertFalse([mirror containsObject:@"desktopSizeMenu"]); XCTAssertFalse([mirror containsObject:@"displaySettings"]);
    [viewer setValue:@[displays[0]] forKey:@"displayViews"];
    XCTAssertTrue([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"displays"], @"Streaming one monitor must retain access to the full host catalogue");
    session.catalogue=@{@"views":@[displays[0]]};
    XCTAssertFalse([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"displays"], @"A genuinely single-monitor Mac needs no picker");
    session.catalogue=@{@"views":displays};
    [viewer setValue:displays forKey:@"displayViews"]; session.snapshot=[self acceptedSnapshot];
    XCTAssertFalse([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"displays"]);
    XCTAssertTrue([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"desktopSizeMenu"]);
    session.catalogue=@{};
    XCTAssertFalse([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"displaySettings"]);
    XCTAssertFalse([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"desktopSizeMenu"]);
    session.snapshot=@{@"layoutVirtual":@NO};
    XCTAssertTrue([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"displays"], @"Legacy hosts retain local multi-display selection");
    [viewer setValue:@[displays[0]] forKey:@"displayViews"];
    XCTAssertFalse([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"displays"]);
    [viewer stopViewer];
}
- (void)testBusyDisplayMenuKeepsItsChoicesButDisablesThem {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    NSArray *displays=@[@{@"id":@5},@{@"id":@1}];
    session.catalogue=@{@"views":displays}; [viewer setValue:displays forKey:@"displayViews"];
    NSArray *before=[self kindsInSections:[viewer displayMenuSections]];
    session.available=NO; session.usable=NO;
    NSArray *busy=[viewer displayMenuSections];
    XCTAssertEqualObjects([self kindsInSections:busy],before);
    for (NSDictionary *item in busy[0][@"items"]) XCTAssertTrue([item[@"disabled"] boolValue], @"%@",item[@"kind"]);
    [viewer stopViewer];
}
- (void)testInputOnlyOmitsScreenAndPointerOptionsAndOffersResume {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    session.catalogue=@{@"views":@[@{@"id":@5},@{@"id":@1}]};
    viewer.inputOnly=YES;
    XCTAssertEqualObjects([self kindsInSections:[viewer displayMenuSections]],(@[@"inputOnly",@"fullscreen"]));
    XCTAssertEqualObjects([viewer displayMenuSections][0][@"items"][0][@"title"],@"Show Mac Screen");
    XCTAssertEqualObjects([self kindsInSections:[viewer inputMenuSections]],(@[@"composeText",@"keyboard",@"keys",@"remoteControls"]));
    XCTAssertFalse([[self kindsInSections:[viewer displayMenuSections]] containsObject:@"desktopSizeMenu"]);
    viewer.inputOnly=NO;
    NSArray *input=[self kindsInSections:[viewer inputMenuSections]];
    XCTAssertTrue([input containsObject:@"setPointer"]); XCTAssertTrue([input containsObject:@"setTrackpad"]);
    XCTAssertFalse([input containsObject:@"input"]); XCTAssertFalse([input containsObject:@"gestures"]);
    [viewer stopViewer];
}
- (void)testMenuSnapshotsStayStableWhenReadinessAndDisplayCatalogueChange {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    NSArray *displays=@[@{@"id":@5},@{@"id":@1}];
    session.catalogue=@{@"views":displays}; [viewer setValue:displays forKey:@"displayViews"];
    [viewer showViewMenu]; NSArray *snapshot=viewer.menuSections;
    NSArray *kinds=[[self kindsInSections:snapshot] copy];
    for (NSUInteger i=0;i<10;i++) {
        session.usable=NO; session.snapshot=@{@"layoutVirtual":@YES};
        [viewer setValue:@[displays[0]] forKey:@"displayViews"];
        [viewer updateConnectionChrome];
        XCTAssertEqual(viewer.menuSections,snapshot);
        XCTAssertEqualObjects([self kindsInSections:viewer.menuSections],kinds);
    }
    [viewer showViewMenu]; XCTAssertFalse([[self kindsInSections:viewer.menuSections] containsObject:@"displays"]);
    [viewer stopViewer];
}
- (void)testFlatDisplayMenuRendersConditionalRowsAtNormalAndAccessibilitySizes {
    UIWindowScene *scene=(id)UIApplication.sharedApplication.connectedScenes.anyObject;
    UIWindow *previous=nil; for (UIWindow *candidate in scene.windows) if (candidate.isKeyWindow) previous=candidate;
    UIWindow *window=[[UIWindow alloc] initWithWindowScene:scene];
    for (NSNumber *virtual in @[@NO,@YES]) for (NSString *category in @[UIContentSizeCategoryLarge,UIContentSizeCategoryAccessibilityExtraExtraExtraLarge]) {
        DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
        session.catalogue=@{@"views":@[@{@"id":@5},@{@"id":@9}]}; session.snapshot=@{@"layoutVirtual":virtual};
        CompanionVNCMenu *menu=[CompanionVNCMenu new]; menu.title=@"Display"; menu.sections=[viewer displayMenuSections];
        UINavigationController *navigation=[[UINavigationController alloc] initWithRootViewController:menu];
        navigation.traitOverrides.preferredContentSizeCategory=category;
        window.rootViewController=navigation; [window makeKeyAndVisible]; [navigation.view layoutIfNeeded]; [menu.view layoutIfNeeded]; [menu.tableView reloadData]; [menu.tableView layoutIfNeeded];
        NSArray *mode=menu.sections[0][@"items"];
        XCTAssertEqualObjects([mode valueForKey:@"kind"],virtual.boolValue ? (@[@"virtualDisplay",@"mirrorDisplay",@"desktopSizeMenu"]) : (@[@"virtualDisplay",@"mirrorDisplay",@"displays"]));
        for (NSUInteger row=0;row<mode.count;row++) {
            NSIndexPath *path=[NSIndexPath indexPathForRow:row inSection:0];
            [menu.tableView scrollToRowAtIndexPath:path atScrollPosition:UITableViewScrollPositionMiddle animated:NO]; [menu.tableView layoutIfNeeded];
            UITableViewCell *cell=[menu.tableView cellForRowAtIndexPath:path]; XCTAssertNotNil(cell);
            XCTAssertGreaterThanOrEqual(cell.bounds.size.height,44);
            XCTAssertLessThanOrEqual(cell.bounds.size.width,menu.tableView.bounds.size.width);
        }
        [menu.tableView setContentOffset:CGPointZero animated:NO]; [menu.tableView layoutIfNeeded];
        UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:window.bounds.size] imageWithActions:^(UIGraphicsImageRendererContext *context){ [window drawViewHierarchyInRect:window.bounds afterScreenUpdates:YES]; }];
        XCTAttachment *attachment=[XCTAttachment attachmentWithImage:image]; attachment.name=[NSString stringWithFormat:@"flat-display-%@-%@",virtual.boolValue?@"virtual":@"mirror",category]; attachment.lifetime=XCTAttachmentLifetimeKeepAlways; [self addAttachment:attachment];
        [viewer stopViewer];
    }
    window.hidden=YES; window.rootViewController=nil; [previous makeKeyAndVisible];
}
- (void)testPublicPresetsMatchGoldenPacketsAndRejectUnknownValues {
    for (NSDictionary *row in self.fixture[@"landscapePresets"]) {
        NSInteger preset=[row[@"id"] integerValue]; CompanionVNCDesktopSize size;
        XCTAssertTrue(CompanionVNCDesktopSizeForPreset((int)preset,&size)); XCTAssertGreaterThan(size.width,size.height);
        XCTAssertEqual(size.width,[row[@"points"][0] intValue]); XCTAssertEqual(size.height,[row[@"points"][1] intValue]);
        uint8_t packet[196]; XCTAssertTrue(CompanionVNCDesktopDisplayPacket(size,packet,sizeof(packet)));
        NSMutableString *hex=[NSMutableString new]; for (NSUInteger i=0;i<sizeof(packet);i++) [hex appendFormat:@"%02x",packet[i]];
        XCTAssertEqualObjects(hex,row[@"hex"]);
        CompanionVNCSession *session=[CompanionVNCSession new];
        [session setValue:@3200 forKey:@"framebufferWidth"]; [session setValue:@1200 forKey:@"framebufferHeight"];
        for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer",@"coverageLayoutValid"]) [session setValue:@YES forKey:key];
        XCTAssertFalse([session requestDesktopSizePreset:0]); XCTAssertFalse([session requestDesktopSizePreset:4]);
        XCTAssertFalse([session requestDesktopSizePreset:NSIntegerMax]);
        [session setValue:@YES forKey:@"inputOnly"]; XCTAssertFalse([session requestDesktopSizePreset:preset]);
        [session setValue:@NO forKey:@"inputOnly"]; [session setValue:@YES forKey:@"reviewInputSuspended"]; XCTAssertFalse([session requestDesktopSizePreset:preset]);
        [session setValue:@NO forKey:@"reviewInputSuspended"]; [session setValue:@YES forKey:@"inputReady"];
        XCTAssertTrue([session requestDesktopSizePreset:preset]);
        XCTAssertFalse([session requestDesktopSizePreset:preset]); [session setValue:@NO forKey:@"running"]; [session stop];
    }
}
- (void)testRememberOnlyExactAcceptedUsableDesktopAndKeepPreviousChoiceOnFailure {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    __block NSInteger saved=0, saves=0; viewer.desktopSizeSelectionHandler=^(NSInteger value){saved=value;saves++;};
    XCTAssertTrue([viewer applyDesktopSizePreset:2]); XCTAssertEqual(saves,0);
    session.snapshot=self.acceptedSnapshot; session.usable=NO; [viewer updateDesktopSizeState]; XCTAssertEqual(saves,0);
    NSMutableDictionary *different=[self.acceptedSnapshot mutableCopy]; different[@"layoutWidth"]=@2048; different[@"probeOutcome"]=@1;
    session.usable=YES; session.snapshot=different; [viewer updateDesktopSizeState]; XCTAssertEqual(saves,0);
    session.snapshot=self.acceptedSnapshot; [viewer updateDesktopSizeState]; XCTAssertEqual(saved,2); XCTAssertEqual(saves,1);
    [viewer updateDesktopSizeState]; XCTAssertEqual(saves,1);
    XCTAssertTrue([viewer applyDesktopSizePreset:3]); session.snapshot=@{@"probeOutcome":@4};
    [viewer updateDesktopSizeState]; XCTAssertEqual(saved,2); XCTAssertEqual(saves,1); XCTAssertEqual(viewer.restoredDesktopSizePreset,2);
    [viewer stopViewer];
}
- (void)testAlreadyMatchingChoiceSavesOnceAndExternalGeometryChangeDoesNotLeaveSpinner {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    __block NSInteger saves=0; viewer.desktopSizeSelectionHandler=^(NSInteger preset){saves++;};
    session.snapshot=self.acceptedSnapshot;
    XCTAssertTrue([viewer applyDesktopSizePreset:2]); [viewer updateDesktopSizeState];
    XCTAssertEqual(session.requests,0); XCTAssertEqual(saves,1);
    XCTAssertTrue([viewer applyDesktopSizePreset:3]); [viewer updateDesktopSizeState];
    XCTAssertEqualObjects([viewer valueForKey:@"pendingDesktopSizePreset"],@0);
    XCTAssertEqual(saves,1); XCTAssertEqual(viewer.restoredDesktopSizePreset,2);
    [viewer stopViewer];
}
- (void)testSavedSizeRestoresOnceButNewMacAndLocalLayoutNeverRequestResize {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    [viewer updateDesktopSizeState]; XCTAssertEqual(session.requests,0);
    viewer.restoredDesktopSizePreset=2; [viewer setValue:@NO forKey:@"desktopSizeRestored"];
    session.usable=NO; [viewer updateDesktopSizeState]; XCTAssertEqual(session.requests,0);
    session.usable=YES; [viewer updateDesktopSizeState]; XCTAssertEqual(session.requests,1); XCTAssertEqual(session.lastPreset,2);
    for (NSValue *value in @[[NSValue valueWithCGSize:CGSizeMake(440,956)],[NSValue valueWithCGSize:CGSizeMake(956,440)],[NSValue valueWithCGSize:CGSizeMake(1024,1366)]]) {
        viewer.view.frame=(CGRect){CGPointZero,value.CGSizeValue}; [viewer.view setNeedsLayout]; [viewer.view layoutIfNeeded];
        [viewer keyboardFrame:[NSNotification notificationWithName:UIKeyboardWillChangeFrameNotification object:nil userInfo:@{
            UIKeyboardFrameEndUserInfoKey:[NSValue valueWithCGRect:CGRectMake(0,value.CGSizeValue.height-300,value.CGSizeValue.width,300)],
            UIKeyboardAnimationDurationUserInfoKey:@0,UIKeyboardAnimationCurveUserInfoKey:@0}]];
        [viewer updateDesktopSizeState]; XCTAssertEqual(session.requests,1);
    }
    [viewer stopViewer];
}
- (NSDictionary *)fixture {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"ios-dynamic-resolution-prototype-v1" withExtension:@"json"];
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
}
- (void)deliverLayout:(NSDictionary *)row session:(CompanionVNCSession *)session client:(rfbClient *)client peer:(int)peer {
    NSString *hex = row[@"bodyHex"]; NSMutableData *body = [NSMutableData new];
    for (NSUInteger i=0; i<hex.length; i+=2) { unsigned int value=0; [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&value]; uint8_t byte=value; [body appendBytes:&byte length:1]; }
    uint8_t prefix[2]={(uint8_t)(body.length>>8),(uint8_t)body.length};
    XCTAssertEqual(write(peer,prefix,2),2); XCTAssertEqual(write(peer,body.bytes,body.length),body.length);
    XCTAssertTrue([session displayLayout:client encoding:1105]);
    [session updatedX:0 y:0 width:0 height:0]; // Metadata contributes no pixel coverage.
}
- (void)testViewportBoundsAndPacketUseAuthoritativeVectors {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"ios-dynamic-resolution-prototype-v1" withExtension:@"json"];
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    XCTAssertNotNil(fixture);
    for (NSDictionary *row in fixture[@"packetCases"]) {
        CompanionVNCDesktopSize size = {[row[@"points"][0] intValue], [row[@"points"][1] intValue]};
        uint8_t packet[196]; XCTAssertTrue(CompanionVNCDesktopDisplayPacket(size, packet, sizeof(packet)));
        NSMutableString *hex = [NSMutableString new]; for (NSUInteger i = 0; i < sizeof(packet); i++) [hex appendFormat:@"%02x", packet[i]];
        XCTAssertEqualObjects(hex, row[@"hex"]);
    }
    CompanionVNCDesktopSize size;
    XCTAssertFalse(CompanionVNCDesktopSizeForViewport(NAN, 400, &size));
    XCTAssertFalse(CompanionVNCDesktopSizeForViewport(INFINITY, 400, &size));
    XCTAssertTrue(CompanionVNCDesktopSizeForViewport(1920, 1080, &size));
    XCTAssertEqual(size.width, 1632); XCTAssertEqual(size.height, 916);
}
- (void)testRequestIsOwnedByLiveForegroundDesktopAndRetiresQueuedInput {
    CompanionVNCSession *session = [CompanionVNCSession new];
    XCTAssertFalse([session requestDesktopSizeWidth:832 height:440]);
    for (NSString *key in @[@"running", @"established", @"inputReady", @"appleGestureServer"]) [session setValue:@YES forKey:key];
    [session setValue:@YES forKey:@"paused"];
    XCTAssertFalse([session requestDesktopSizeWidth:832 height:440]);
    [session setValue:@NO forKey:@"paused"];
    XCTAssertTrue([session tryClickX:1 y:1 mask:1]);
    XCTAssertTrue([session requestDesktopSizeWidth:832 height:440]);
    XCTAssertEqual([[session valueForKey:@"events"] count], 0);
    XCTAssertFalse([session tryClickX:1 y:1 mask:1]);
    XCTAssertFalse([session requestDesktopSizeWidth:440 height:832]);
    [session setValue:@NO forKey:@"running"]; [session stop];
}
- (void)testSoleOwnerWritesOneRequestAndTimeoutRequiresFreshBaseline {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    CompanionVNCSession *session = [CompanionVNCSession new];
    rfbClient *client = rfbGetClient(8,3,4); client->sock = pair[0]; client->width = 2; client->height = 2;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running", @"established", @"inputReady", @"appleGestureServer", @"coverageLayoutValid"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:832 height:440]);
    XCTAssertTrue([session processDesktopSizeChange:client]);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"], @0);
    [session setValue:@NO forKey:@"releaseInputRequested"]; // The socket owner consumed and completed release.
    XCTAssertTrue([session processDesktopSizeChange:client]);
    uint8_t bytes[196], expected[196]; XCTAssertEqual(recv(pair[1], bytes, sizeof(bytes), MSG_WAITALL), 196);
    XCTAssertTrue(CompanionVNCDesktopDisplayPacket((CompanionVNCDesktopSize){1132,600}, expected, sizeof(expected)));
    XCTAssertEqual(memcmp(bytes, expected, 196), 0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"], @1);
    [session setValue:@(NSProcessInfo.processInfo.systemUptime - 21) forKey:@"desktopResizeStarted"];
    XCTAssertTrue([session processDesktopSizeChange:client]);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeTimedOut"], @1);
    XCTAssertFalse([session tryClickX:1 y:1 mask:1]);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testResizeDoesNotAcceptOldPhysicalPixelsAndRequiresVirtualLayoutAndFreshFrame {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    CompanionVNCSession *session = [CompanionVNCSession new];
    rfbClient *client = rfbGetClient(8,3,4); client->sock=pair[0]; client->width=1600; client->height=1600;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"ios-dynamic-resolution-prototype-v1" withExtension:@"json"];
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    int peer = pair[1];
    void (^layout)(NSDictionary *) = ^(NSDictionary *row) {
        NSString *hex = row[@"bodyHex"]; NSMutableData *body = [NSMutableData new];
        for (NSUInteger i=0; i<hex.length; i+=2) { unsigned int value=0; [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&value]; uint8_t byte=value; [body appendBytes:&byte length:1]; }
        uint8_t prefix[2]={(uint8_t)(body.length>>8),(uint8_t)body.length};
        XCTAssertEqual(write(peer,prefix,2),2); XCTAssertEqual(write(peer,body.bytes,body.length),body.length);
        XCTAssertTrue([session displayLayout:client encoding:1105]);
        [session updatedX:0 y:0 width:0 height:0]; // End the metadata callback, as the decoder does.
    };
    layout(fixture[@"layoutCases"][0]);
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:320 height:320]);
    [session setValue:@NO forKey:@"releaseInputRequested"];
    XCTAssertTrue([session processDesktopSizeChange:client]);
    uint8_t bytes[196]; XCTAssertEqual(recv(pair[1],bytes,196,MSG_WAITALL),196);
    XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertTrue([session requestFullDesktop:client]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1, @"Virtual sizing also waits for the new layout before requesting pixels");
    [session updatedX:0 y:0 width:1600 height:1600]; [session publishFrame:client];
    XCTAssertEqualObjects(session.diagnosticCounters[@"presentedFrames"],@0); XCTAssertFalse([session tryClickX:20 y:20 mask:1]);
    layout(fixture[@"layoutCases"][1]);
    [session publishFrame:client];
    XCTAssertEqualObjects(session.diagnosticCounters[@"presentedFrames"],@0);
    XCTAssertFalse(session.connected); // A same-size physical-to-virtual handoff retires old pixels too.
    XCTestExpectation *fresh = [self expectationWithDescription:@"Fresh virtual pixels"];
    session.frameHandler = ^(UIImage *image) { XCTAssertEqual(CGImageGetWidth(image.CGImage),1600); [fresh fulfill]; };
    [session updatedX:0 y:0 width:1600 height:1600];
    [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:2];
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@1); XCTAssertTrue(session.connected);
    [session setValue:@NO forKey:@"running"]; [session stop]; session.frameHandler=nil; rfbClientCleanup(client); close(pair[1]);
}
- (void)testDisplayMetadataAloneResizesTheCanvasAndFreshPixelsReopenInput {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session = [CompanionVNCSession new];
    rfbClient *client = rfbGetClient(8,3,4); client->sock=pair[0]; client->width=1600; client->height=1600;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"layoutCases"][0] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:440 height:956]);
    [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
    uint8_t bytes[196]; XCTAssertEqual(recv(pair[1],bytes,196,MSG_WAITALL),196);
    [self deliverLayout:self.fixture[@"layoutCases"][3] session:session client:client peer:pair[1]];
    XCTAssertEqual(client->width,1200); XCTAssertEqual(client->height,2600);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeLayoutResizes"],@1);
    XCTAssertFalse(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@0);
    XCTestExpectation *fresh=[self expectationWithDescription:@"Complete new canvas"];
    session.frameHandler=^(UIImage *image){ XCTAssertEqual(CGImageGetHeight(image.CGImage),2600); [fresh fulfill]; };
    [session updatedX:0 y:0 width:1200 height:2600]; [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:2];
    XCTAssertTrue(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@1);
    [session setValue:@NO forKey:@"running"]; [session stop]; session.frameHandler=nil; rfbClientCleanup(client); close(pair[1]);
}
- (void)testDifferentHostSizeRecoversFreshPixelsWithoutClaimingAcceptance {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=1600; client->height=1600;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"layoutCases"][0] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:440 height:956]);
    [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
    uint8_t bytes[196]; XCTAssertEqual(recv(pair[1],bytes,196,MSG_WAITALL),196);
    [self deliverLayout:self.fixture[@"layoutCases"][2] session:session client:client peer:pair[1]];
    XCTAssertEqual(client->width,1600); XCTAssertEqual(client->height,1200); XCTAssertFalse(session.connected);
    [session setValue:@(NSProcessInfo.processInfo.systemUptime-21) forKey:@"desktopResizeStarted"];
    XCTAssertTrue([session processDesktopSizeChange:client]);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@4);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@0); XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"],@1);
    XCTestExpectation *fresh=[self expectationWithDescription:@"Usable host fallback"];
    session.frameHandler=^(UIImage *image){ XCTAssertEqual(CGImageGetHeight(image.CGImage),1200); [fresh fulfill]; };
    [session updatedX:0 y:0 width:1600 height:1200]; [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:2];
    XCTAssertTrue(session.connected); XCTAssertTrue(session.running);
    [session setValue:@NO forKey:@"running"]; [session stop]; session.frameHandler=nil; rfbClientCleanup(client); close(pair[1]);
}
- (void)testFramebufferResizeStillRequiresMatchingDisplayMetadata {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=1600; client->height=1600;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"layoutCases"][1] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:440 height:956]);
    [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
    uint8_t bytes[196]; XCTAssertEqual(recv(pair[1],bytes,196,MSG_WAITALL),196);
    // Standard DesktopSize arrived first; the retained virtual layout still has the old dimensions.
    client->width=1200; client->height=2600; XCTAssertTrue([session allocate:client]);
    [session updatedX:0 y:0 width:1200 height:2600]; [session publishFrame:client];
    XCTAssertFalse(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"presentedFrames"],@0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@0);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testUnsolicitedLayoutCannotResizeCanvasAndDisplaySelectionSurvivesUICallback {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=1600; client->height=1600;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"layoutCases"][3] session:session client:client peer:pair[1]];
    XCTAssertEqual(client->width,1600); XCTAssertEqual(client->height,1600);
    XCTestExpectation *callback=[self expectationWithDescription:@"Pending layout consumed"];
    dispatch_async(dispatch_get_main_queue(),^{[callback fulfill];}); [self waitForExpectations:@[callback] timeout:2];
    XCTAssertEqual([session.desktopDisplayLayout[@"views"] count],1);
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertFalse([session requestDesktopDisplayID:999]); XCTAssertTrue([session requestDesktopDisplayID:9]);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testBackToBackLayoutsDeliverSelectedGeometryBeforeItsFreshFrame {
    for (NSNumber *repeat in @[@NO,@YES]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=3200; client->height=1200;
        [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
        NSMutableArray *events=[NSMutableArray new]; __block NSDictionary *visibleLayout=nil;
        session.displayLayoutHandler=^(NSDictionary *layout){
            XCTAssertTrue(NSThread.isMainThread); visibleLayout=layout; [events addObject:@"layout"];
        };
        NSDictionary *layouts=self.fixture[@"monitorLayouts"];
        // Hold the main thread through both reports. The second report allocates a
        // new selected-stream canvas before the first callback can run.
        [self deliverLayout:layouts[@"all"] session:session client:client peer:pair[1]];
        XCTAssertTrue([session requestDesktopDisplayID:9]);
        [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
        uint8_t packet[8]; XCTAssertEqual(recv(pair[1],packet,8,MSG_WAITALL),8);
        [self deliverLayout:layouts[@"second"] session:session client:client peer:pair[1]];
        XCTAssertEqual(client->width,1600); XCTAssertEqual(client->height,1200);
        XCTestExpectation *fresh=[self expectationWithDescription:@"Selected layout precedes its image"];
        session.frameHandler=^(UIImage *image){
            [events addObject:@"frame"];
            XCTAssertEqual([visibleLayout[@"views"] count],1);
            NSDictionary *display=[visibleLayout[@"views"] firstObject];
            XCTAssertEqualObjects(display[@"id"],@9);
            XCTAssertEqualObjects(display[@"x"],@0); XCTAssertEqualObjects(display[@"y"],@0);
            XCTAssertEqualObjects(display[@"width"],@1); XCTAssertEqualObjects(display[@"height"],@1);
            XCTAssertEqual(CGImageGetWidth(image.CGImage),1600); [fresh fulfill];
        };
        [session updatedX:0 y:0 width:1600 height:1200]; [session publishFrame:client];
        if (repeat.boolValue) [self deliverLayout:layouts[@"second"] session:session client:client peer:pair[1]];
        XCTestExpectation *drained=[self expectationWithDescription:@"All queued metadata delivered"];
        dispatch_async(dispatch_get_main_queue(),^{ [drained fulfill]; });
        [self waitForExpectations:@[fresh,drained] timeout:2];
        XCTAssertEqualObjects(events,repeat.boolValue ? (@[@"layout",@"frame",@"layout"]) : (@[@"layout",@"frame"]));
        XCTAssertEqual([session.desktopDisplayLayout[@"views"] count],2, @"The full host catalogue remains available");
        session.displayLayoutHandler=nil; session.frameHandler=nil; [session setValue:@NO forKey:@"running"];
        [session stop]; rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testQueuedLayoutsRejectRetiredEpochsAndPublishCurrentSnapshots {
    for (NSString *boundary in @[@"sameEpoch",@"pause",@"resume",@"stop",@"replacement"]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=3200; client->height=1200;
        [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        for (NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
        __block NSUInteger layouts=0;
        session.displayLayoutHandler=^(NSDictionary *layout){ layouts++; XCTAssertTrue(NSThread.isMainThread); };
        NSDictionary *all=self.fixture[@"monitorLayouts"][@"all"];
        [self deliverLayout:all session:session client:client peer:pair[1]];
        if ([boundary isEqualToString:@"pause"] || [boundary isEqualToString:@"resume"]) [session pauseWithCompletion:nil];
        if ([boundary isEqualToString:@"resume"]) [session resume];
        if ([boundary isEqualToString:@"stop"]) [session stop];
        if ([boundary isEqualToString:@"replacement"]) [session setValue:@([[session valueForKey:@"generation"] integerValue]+1) forKey:@"generation"];
        BOOL newSnapshot=[boundary isEqualToString:@"sameEpoch"] || [boundary isEqualToString:@"resume"];
        if (newSnapshot) [self deliverLayout:all session:session client:client peer:pair[1]];
        XCTestExpectation *drained=[self expectationWithDescription:boundary];
        dispatch_async(dispatch_get_main_queue(),^{ [drained fulfill]; });
        [self waitForExpectations:@[drained] timeout:2];
        XCTAssertEqual(layouts,[boundary isEqualToString:@"sameEpoch"] ? 2 : newSnapshot ? 1 : 0, @"%@",boundary);
        session.displayLayoutHandler=nil; [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testPhysicalAllCatalogueChangesAdoptCanvasAndRequireFreshPixelsWithoutSelection {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=3200; client->height=1200;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    NSDictionary *vectors=self.fixture[@"physicalCatalogueRecovery"];
    [self deliverLayout:vectors[@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    [session setValue:@YES forKey:@"desktopResizeSelection"]; [session setValue:@0 forKey:@"desktopResizeDisplayID"];
    uint8_t bytes[64];
    for (NSString *name in @[@"one",@"all",@"one"]) {
        XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,16,MSG_DONTWAIT),16);
        [self deliverLayout:vectors[name] session:session client:client peer:pair[1]];
        XCTAssertEqual(recv(pair[1],bytes,16,MSG_DONTWAIT),16); // Retire old subscription, no selection packet.
        XCTAssertEqual(bytes[0],9); XCTAssertEqual(CompanionVNCBE32(bytes+4),UINT32_MAX);
        int width=[name isEqualToString:@"all"]?3200:1600;
        XCTAssertEqual(client->width,width); XCTAssertEqual(client->height,1200);
        XCTAssertEqual([session.desktopDisplayLayout[@"views"] count],[name isEqualToString:@"all"]?2:1);
        XCTAssertFalse(session.connected); XCTAssertFalse([session tryClickX:5 y:5 mask:1]);
        XCTAssertEqualObjects(session.diagnosticCounters[@"baselineExpectedPixels"],@(width*1200));
        XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,16,MSG_DONTWAIT),16);
        XCTAssertEqual(CompanionVNCBE16(bytes+12),width); XCTAssertEqual(CompanionVNCBE16(bytes+14),1200);
        XCTAssertTrue([session requestFullDesktop:client]); XCTAssertEqual(recv(pair[1],bytes,10,MSG_DONTWAIT),10);
        XCTAssertEqual(CompanionVNCBE16(bytes+6),width);
        [session updatedX:0 y:0 width:width height:600]; [session publishFrame:client]; XCTAssertFalse(session.connected);
        XCTestExpectation *fresh=[self expectationWithDescription:@"Fresh resized physical catalogue baseline"];
        session.frameHandler=^(UIImage *image){[fresh fulfill];}; [session setValue:@0 forKey:@"lastFrame"];
        [session updatedX:0 y:600 width:width height:600]; [session publishFrame:client];
        [self waitForExpectations:@[fresh] timeout:2]; session.frameHandler=nil; XCTAssertTrue(session.connected);
        // Repeated metadata cannot restart an already proven baseline.
        [self deliverLayout:vectors[name] session:session client:client peer:pair[1]]; XCTAssertTrue(session.connected);
    }
    XCTAssertEqualObjects(session.diagnosticCounters[@"physicalLayoutAdoptions"],@3);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"],@0); XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@0);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testUnsolicitedPhysicalRecoveryRejectsUnprovenAndSelectedOrVirtualSessions {
    for (NSString *blocked in @[@"established",@"appleGestureServer",@"priorVirtual",@"selected",@"headerSelected",@"headerVirtual",@"pending",@"paused",@"oversized"]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        [self deliverLayout:self.fixture[@"physicalCatalogueRecovery"][@"all"] session:session client:client peer:pair[1]];
        for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
        NSDictionary *row=self.fixture[@"physicalCatalogueRecovery"][@"one"];
        if ([blocked isEqualToString:@"established"] || [blocked isEqualToString:@"appleGestureServer"]) [session setValue:@NO forKey:blocked];
        if ([blocked isEqualToString:@"priorVirtual"]) [session setValue:@YES forKey:@"desktopResizeVirtualLayout"];
        if ([blocked isEqualToString:@"selected"]) { [session setValue:@YES forKey:@"desktopResizeSelection"]; [session setValue:@5 forKey:@"desktopResizeDisplayID"]; }
        if ([blocked isEqualToString:@"headerSelected"]) row=self.fixture[@"monitorLayouts"][@"first"];
        if ([blocked isEqualToString:@"headerVirtual"]) row=self.fixture[@"layoutCases"][3];
        if ([blocked isEqualToString:@"pending"]) [session setValue:@YES forKey:@"desktopResizePending"];
        if ([blocked isEqualToString:@"paused"]) [session setValue:@YES forKey:@"paused"];
        if ([blocked isEqualToString:@"oversized"]) row=self.fixture[@"physicalCatalogueRecovery"][@"oversized"];
        [self deliverLayout:row session:session client:client peer:pair[1]];
        XCTAssertEqual(client->width,3200,@"%@",blocked); XCTAssertEqual(client->height,1200,@"%@",blocked);
        [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testMissingSelectionMetadataRetriesOnlyTinyProbeAtBoundedAges {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopDisplayID:5]); [session setValue:@NO forKey:@"releaseInputRequested"];
    XCTAssertTrue([session processDesktopSizeChange:client]); uint8_t bytes[32]; XCTAssertEqual(recv(pair[1],bytes,8,MSG_WAITALL),8);
    for (NSNumber *age in @[@0,@0.1,@0.6,@0.7,@1.6,@2,@5.9]) {
        [session setValue:@(NSProcessInfo.processInfo.systemUptime-age.doubleValue) forKey:@"desktopResizeStarted"];
        XCTAssertTrue([session requestPendingDesktopLayout:client]);
        BOOL expected=age.doubleValue==0 || age.doubleValue==0.6 || age.doubleValue==1.6;
        ssize_t count=recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT); XCTAssertEqual(count,expected?10:-1);
        if (count==10) { XCTAssertEqual(bytes[0],3); XCTAssertEqual(CompanionVNCBE16(bytes+6),1); XCTAssertEqual(CompanionVNCBE16(bytes+8),1); }
        XCTAssertFalse(session.connected);
    }
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeMetadataRequests"],@3);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"first"] session:session client:client peer:pair[1]];
    XCTAssertTrue([session requestPendingDesktopLayout:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testMirrorRestartsVirtualSessionOnceUsingExistingTransientLoginAndNeverReappliesSize {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    session.snapshot=self.acceptedSnapshot; viewer.restoredDesktopSizePreset=2;
    __block NSInteger choice=-1; viewer.desktopSizeSelectionHandler=^(NSInteger value){choice=value;};
    XCTAssertTrue([viewer applyMirrorDisplay]); XCTAssertTrue(viewer.requestedResume);
    XCTAssertEqual(choice,-1); XCTAssertEqual(viewer.restoredDesktopSizePreset,0);
    [viewer setValue:@NO forKey:@"starting"]; session.snapshot=self.physicalSnapshot;
    [viewer updateDesktopSizeState]; XCTAssertEqual(choice,0); XCTAssertEqual(session.requests,0);
    viewer.requestedResume=NO; XCTAssertTrue([viewer applyMirrorDisplay]); XCTAssertFalse(viewer.requestedResume);
    [viewer setValue:@YES forKey:@"inputInactive"]; XCTAssertFalse([viewer applyMirrorDisplay]);
    [viewer stopViewer];
}
- (void)testSelectedMonitorAndAllDisplaysUseSocketAndFreshPixelsAndRetainCatalogue {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3200; client->height=1200;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    NSDictionary *layouts=self.fixture[@"monitorLayouts"];
    [self deliverLayout:layouts[@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertFalse([session requestDesktopDisplayID:999]);
    __block NSUInteger frameCount=0;
    for (NSNumber *identifier in @[@5,@9,@0]) {
        XCTAssertTrue([session requestDesktopDisplayID:identifier.unsignedIntValue]);
        XCTAssertFalse([session tryClickX:5 y:5 mask:1]);
        [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
        uint8_t packet[8], expected[8]; XCTAssertEqual(recv(pair[1],packet,8,MSG_WAITALL),8);
        CompanionVNCDesktopSelectionPacket(identifier.unsignedIntValue,expected); XCTAssertEqual(memcmp(packet,expected,8),0);
        // Before the fresh matching layout, old pixels never accept the operation.
        [session updatedX:0 y:0 width:client->width height:client->height]; [session publishFrame:client];
        XCTAssertFalse(session.connected);
        NSString *name=identifier.unsignedIntValue==5 ? @"first" : identifier.unsignedIntValue==9 ? @"second" : @"all";
        [self deliverLayout:layouts[name] session:session client:client peer:pair[1]];
        XCTAssertEqual(client->width,identifier.unsignedIntValue ? 1600 : 3200);
        XCTAssertEqual([session.desktopDisplayLayout[@"views"] count],2);
        XCTAssertFalse(session.connected);
        XCTestExpectation *fresh=[self expectationWithDescription:@"Fresh selected display pixels"];
        session.frameHandler=^(UIImage *image){ frameCount++; [fresh fulfill]; };
        [session setValue:@0 forKey:@"lastFrame"];
        [session updatedX:0 y:0 width:client->width height:client->height]; [session publishFrame:client];
        [self waitForExpectations:@[fresh] timeout:2];
        XCTAssertTrue(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@2);
    }
    XCTAssertEqual(frameCount,3);
    [session setValue:@NO forKey:@"running"]; [session stop]; session.frameHandler=nil; rfbClientCleanup(client); close(pair[1]);
}
- (void)testSelectedStreamRetainsGlobalCatalogueWithoutWaitingForUnsentPixels {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=8144; client->height=2134;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    NSDictionary *vectors=self.fixture[@"selectedCatalogueLayouts"];
    XCTAssertTrue([self.fixture[@"physicalSelectionDelivery"][@"validatedCurrentStreamRepeatRetainsDelivery"] boolValue]);
    NSDictionary *all=@{@"bodyHex":vectors[@"catalogueHex"]};
    [self deliverLayout:all session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    __block NSDictionary *visibleLayout=nil;
    session.displayLayoutHandler=^(NSDictionary *layout){ visibleLayout=layout; };
    uint8_t delivery[16];
    XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],delivery,16,MSG_WAITALL),16);
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    for (NSNumber *identifier in @[@5,@9,@0]) {
        XCTAssertTrue([session requestDesktopDisplayID:identifier.unsignedIntValue]);
        [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
        uint8_t packet[8]; XCTAssertEqual(recv(pair[1],packet,8,MSG_WAITALL),8);
        NSDictionary *row=identifier.intValue==5 ? vectors[@"cases"][0] : identifier.intValue==9 ? vectors[@"cases"][1] : all;
        if (identifier.intValue!=5) {
            // The real loop configures updates between old and matching reports.
            // A repeat of the proven stream must not silence the target metadata.
            [self deliverLayout:vectors[@"cases"][identifier.intValue==9 ? 0 : 1] session:session client:client peer:pair[1]];
            XCTAssertEqual(client->width,identifier.intValue==9 ? 5120 : 3024); XCTAssertFalse(session.connected);
            XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@1);
            XCTAssertTrue([session configureDesktopUpdates:client]);
            XCTAssertEqual(recv(pair[1],delivery,16,MSG_DONTWAIT),-1, @"No disable packet before the requested layout");
            XCTAssertEqualObjects(session.diagnosticCounters[@"automaticDesktopUpdates"],@YES);
        }
        BOOL wasActive=[session.diagnosticCounters[@"automaticDesktopUpdates"] boolValue];
        [self deliverLayout:row session:session client:client peer:pair[1]];
        if (wasActive) { XCTAssertEqual(recv(pair[1],delivery,16,MSG_WAITALL),16); XCTAssertEqual(delivery[4],255); }
        XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],delivery,16,MSG_WAITALL),16);
        XCTAssertEqual(delivery[0],9); XCTAssertEqual(delivery[4],0);
        int width=identifier.intValue==5 ? 5120 : identifier.intValue==9 ? 3024 : 8144;
        int height=identifier.intValue==9 ? 1964 : 2134;
        XCTAssertEqual(client->width,width); XCTAssertEqual(client->height,height);
        XCTAssertEqual([session.desktopDisplayLayout[@"views"] count],2);
        XCTAssertFalse(session.connected);
        if (client->width!=width || client->height!=height) break; // Keep a failed regression bounded.
        uint64_t expectedPixels=identifier.intValue ? (uint64_t)width*height : (uint64_t)5120*2134+(uint64_t)3024*1964;
        XCTAssertEqualObjects(session.diagnosticCounters[@"baselineExpectedPixels"],@(expectedPixels));
        XCTAssertFalse([session tryClickX:1 y:1 mask:1]);
        XCTestExpectation *fresh=[self expectationWithDescription:@"Fresh selected stream"];
        session.frameHandler=^(UIImage *image){
            XCTAssertEqual(CGImageGetWidth(image.CGImage),width);
            if (identifier.intValue) XCTAssertEqualObjects(visibleLayout[@"backingScale"],@2);
            [fresh fulfill];
        };
        [session setValue:@0 forKey:@"lastFrame"];
        [session updatedX:0 y:0 width:width height:height]; [session publishFrame:client];
        [self waitForExpectations:@[fresh] timeout:3]; session.frameHandler=nil;
        XCTAssertTrue(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@2);
        // Repeated selected-stream metadata must not discard a usable baseline.
        [self deliverLayout:row session:session client:client peer:pair[1]];
        XCTAssertTrue(session.connected);
    }
    XCTAssertTrue([session requestDesktopDisplayID:0]); XCTAssertTrue(session.connected);
    XCTAssertTrue([session processDesktopSizeChange:client]);
    uint8_t noRequest[32]; XCTAssertEqual(recv(pair[1],noRequest,sizeof(noRequest),MSG_DONTWAIT),-1);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"],@3);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@3);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeNoops"],@1);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeTimedOut"],@0);
    [session setValue:@NO forKey:@"running"]; [session stop]; session.displayLayoutHandler=nil; session.frameHandler=nil; rfbClientCleanup(client); close(pair[1]);
}
- (void)testMonitorSwitchDoesNotRearmOrRefreshTheOldCanvasBeforeMatchingLayout {
    XCTAssertEqualObjects(self.fixture[@"selectionHandoffOrder"],(@[@"release-held-input",@"retain-established-physical-delivery",@"select-display",@"request-one-pixel-metadata",@"await-matching-layout",@"retire-old-subscription-if-bounds-change",@"start-matching-updates",@"request-full-stream",@"present-fresh-baseline"]));
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3200; client->height=1200;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    uint8_t bytes[64]; XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,16,MSG_WAITALL),16);
    XCTAssertTrue([session requestDesktopDisplayID:5]); [session setValue:@NO forKey:@"releaseInputRequested"];
    XCTAssertTrue([session processDesktopSizeChange:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),8);
    XCTAssertEqual(bytes[0],13); // Preserve the established metadata-delivery path.
    XCTAssertEqualObjects(session.diagnosticCounters[@"automaticDesktopUpdates"],@YES);
    XCTAssertTrue([session configureDesktopUpdates:client]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1, @"Never rearm the old combined desktop after selecting a monitor");
    XCTAssertTrue([session requestPendingDesktopLayout:client]); XCTAssertEqual(recv(pair[1],bytes,10,MSG_WAITALL),10);
    NSMutableString *hex=[NSMutableString new]; for (NSUInteger i=0;i<10;i++) [hex appendFormat:@"%02x",bytes[i]];
    XCTAssertEqualObjects(hex,self.fixture[@"layoutProbePacketHex"]);
    XCTAssertTrue([session requestPendingDesktopLayout:client]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1, @"Solicit metadata once, without polling");
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeMetadataRequests"],@1);
    XCTAssertTrue([session requestFullDesktop:client]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1, @"Never request old canvas pixels while waiting for layout");
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"first"] session:session client:client peer:pair[1]];
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),16); // Retire the old bounds only after metadata.
    XCTAssertEqual(bytes[0],9); XCTAssertEqual(CompanionVNCBE32(bytes+4),UINT32_MAX);
    XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,16,MSG_WAITALL),16);
    XCTAssertEqual(CompanionVNCBE16(bytes+12),1600); XCTAssertEqual(CompanionVNCBE16(bytes+14),1200);
    XCTAssertTrue([session requestFullDesktop:client]); XCTAssertEqual(recv(pair[1],bytes,10,MSG_WAITALL),10);
    XCTAssertEqual(CompanionVNCBE16(bytes+6),1600); XCTAssertEqual(CompanionVNCBE16(bytes+8),1200);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testPhysicalSelectionsKeepEstablishedMetadataDeliveryAcrossTwoCompleteCycles {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    NSDictionary *layouts=self.fixture[@"monitorLayouts"];
    [self deliverLayout:layouts[@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    uint8_t bytes[64]; XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),16);
    for (NSNumber *identifier in @[@5,@9,@0,@5,@9,@0]) {
        int oldWidth=client->width;
        XCTAssertTrue([session requestDesktopDisplayID:identifier.unsignedIntValue]); [session setValue:@NO forKey:@"releaseInputRequested"];
        XCTAssertTrue([session processDesktopSizeChange:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),8);
        XCTAssertEqual(bytes[0],13); XCTAssertEqualObjects(session.diagnosticCounters[@"automaticDesktopUpdates"],@YES);
        XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
        // The peer can send its new layout on the established automatic stream.
        // Do not restart old bounds, admit input, or present pre-layout pixels.
        [session updatedX:0 y:0 width:oldWidth height:1200]; [session publishFrame:client]; XCTAssertFalse(session.connected);
        NSString *name=identifier.intValue==5?@"first":identifier.intValue==9?@"second":@"all";
        [self deliverLayout:layouts[name] session:session client:client peer:pair[1]];
        int width=identifier.intValue?1600:3200;
        ssize_t stop=recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT); XCTAssertEqual(stop,oldWidth!=width?16:-1);
        if (stop==16) { XCTAssertEqual(bytes[0],9); XCTAssertEqual(CompanionVNCBE32(bytes+4),UINT32_MAX); }
        XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),16);
        XCTAssertEqual(CompanionVNCBE16(bytes+12),width); XCTAssertEqual(CompanionVNCBE16(bytes+14),1200);
        XCTAssertTrue([session requestFullDesktop:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),10);
        XCTAssertEqual(CompanionVNCBE16(bytes+6),width); XCTAssertFalse(session.connected);
        XCTestExpectation *fresh=[self expectationWithDescription:@"Fresh selected-stream baseline while metadata delivery stays live"];
        session.frameHandler=^(UIImage *image){[fresh fulfill];}; [session setValue:@0 forKey:@"lastFrame"];
        [session updatedX:0 y:0 width:width height:1200]; [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:2]; session.frameHandler=nil;
        XCTAssertTrue(session.connected);
    }
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@6); XCTAssertEqualObjects(session.diagnosticCounters[@"probeTimedOut"],@0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"selectionDeliveryPreserved"],@6);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testKeepingPhysicalMetadataDeliveryDoesNotBypassPauseOrVirtualSizeRetirement {
    for (NSString *mode in @[@"pause",@"virtual",@"inputOnly",@"invalidLayout"]) {
        BOOL virtualSize=[mode isEqualToString:@"virtual"];
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        [self deliverLayout:self.fixture[@"monitorLayouts"][@"all"] session:session client:client peer:pair[1]];
        for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
        uint8_t bytes[256]; XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),16);
        XCTAssertTrue(virtualSize?[session requestDesktopSizePreset:2]:[session requestDesktopDisplayID:5]);
        [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
        ssize_t count=recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT);
        if (virtualSize) { XCTAssertEqual(count,212); XCTAssertEqual(bytes[0],9); XCTAssertEqual(bytes[16],29); }
        else {
            XCTAssertEqual(count,8);
            if ([mode isEqualToString:@"pause"]) [session setValue:@YES forKey:@"paused"];
            else if ([mode isEqualToString:@"inputOnly"]) session.inputOnly=YES;
            else [session setValue:@NO forKey:@"coverageLayoutValid"];
            XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),16);
            XCTAssertEqual(bytes[0],9); XCTAssertEqual(CompanionVNCBE32(bytes+4),UINT32_MAX);
            XCTAssertFalse(session.connected); XCTAssertFalse([session tryClickX:5 y:5 mask:1]);
        }
        XCTAssertEqualObjects(session.diagnosticCounters[@"automaticDesktopUpdates"],@NO);
        [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testChoosingAnAlreadyPresentedMonitorIsImmediateAndDoesNotRetireInput {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=1600; client->height=1200;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"first"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTestExpectation *fresh=[self expectationWithDescription:@"Initially usable monitor"];
    session.frameHandler=^(UIImage *image){[fresh fulfill];};
    [session updatedX:0 y:0 width:1600 height:1200]; [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:2]; session.frameHandler=nil;
    for (NSUInteger i=0;i<3;i++) {
        XCTAssertTrue([session requestDesktopDisplayID:5]); XCTAssertTrue(session.connected);
        XCTAssertTrue([session processDesktopSizeChange:client]);
        uint8_t bytes[32]; XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
        XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"],@0);
        XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@2);
        XCTAssertEqualObjects(session.diagnosticCounters[@"probeAwaiting"],@NO);
    }
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testAlreadyActiveDisplayFinishesViewerSelectionImmediately {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    session.snapshot=@{@"probeOutcome":@2};
    NSDictionary *display=@{@"id":@5,@"title":@"Display 1",@"x":@0,@"y":@0,@"width":@1,@"height":@1};
    [viewer setValue:@[display] forKey:@"displayViews"];
    __block NSUInteger saves=0; viewer.displaySelectionHandler=^(NSNumber *identifier){ XCTAssertEqualObjects(identifier,@5); saves++; };
    XCTAssertTrue([viewer applyStreamDisplay:@5]);
    XCTAssertNil([viewer valueForKey:@"pendingStreamDisplayID"]); XCTAssertEqual(saves,1);
    [viewer stopViewer];
}
- (void)testProgressingBaselineDoesNotQueueAnotherFullImage {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=client->height=100; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running",@"established"]) [session setValue:@YES forKey:key];
    [session setValue:@NO forKey:@"desktopRefreshPending"];
    [session updatedX:0 y:0 width:100 height:50]; double now=NSProcessInfo.processInfo.systemUptime;
    [session setValue:@(now-1.5) forKey:@"baselineStarted"]; [session setValue:@(now-1.5) forKey:@"lastFullRefresh"];
    XCTAssertTrue([session maintainDesktopBaseline:client now:now]);
    uint8_t bytes[32]; XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1, @"The first image is making progress; do not queue another full copy");
    XCTAssertEqualObjects(session.diagnosticCounters[@"fullRefreshRetries"],@0);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testSwitchBaselineDoesNotCreateRoutinePullsAndRestartsTheChainOnceReady {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopDisplayID:5]); [session setValue:@NO forKey:@"releaseInputRequested"];
    XCTAssertTrue([session processDesktopSizeChange:client]); uint8_t bytes[32]; XCTAssertEqual(recv(pair[1],bytes,8,MSG_WAITALL),8);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"first"] session:session client:client peer:pair[1]];
    XCTAssertTrue([session configureDesktopUpdates:client]); XCTAssertEqual(recv(pair[1],bytes,16,MSG_WAITALL),16);
    XCTAssertFalse(SupportsClient2Server(client,rfbFramebufferUpdateRequest));
    const uint8_t empty[]={0,0,0,0}; XCTAssertEqual(send(pair[1],empty,4,0),4); XCTAssertTrue(HandleRFBServerMessage(client));
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
    XCTAssertTrue([session requestFullDesktop:client]); XCTAssertEqual(recv(pair[1],bytes,10,MSG_WAITALL),10);
    XCTestExpectation *fresh=[self expectationWithDescription:@"New target ready"];
    session.frameHandler=^(UIImage *image){[fresh fulfill];}; [session updatedX:0 y:0 width:1600 height:1200]; [session publishFrame:client];
    [self waitForExpectations:@[fresh] timeout:2]; session.frameHandler=nil;
    XCTAssertTrue(session.connected); XCTAssertTrue([session configureDesktopUpdates:client]);
    XCTAssertTrue(SupportsClient2Server(client,rfbFramebufferUpdateRequest)); XCTAssertTrue([session resumeDesktopPull:client]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),10);
    XCTAssertEqual(bytes[0],3); XCTAssertEqual(bytes[1],1);
    XCTAssertTrue([session resumeDesktopPull:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testStallRetriesAndAbsoluteDeadlineFollowIndexedPolicy {
    for (NSDictionary *row in self.fixture[@"baselineRefreshPolicy"][@"cases"]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=client->height=100; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        for (NSString *key in @[@"running",@"established"]) [session setValue:@YES forKey:key];
        double now=NSProcessInfo.processInfo.systemUptime;
        [session setValue:@(now-[row[@"elapsed"] doubleValue]) forKey:@"baselineStarted"];
        [session setValue:@(now-[row[@"lastRequestAge"] doubleValue]) forKey:@"lastFullRefresh"];
        [session setValue:@(now-[row[@"lastProgressAge"] doubleValue]) forKey:@"baselineLastProgress"];
        [session setValue:row[@"retries"] forKey:@"fullRefreshRetries"];
        // A pending flag cannot request more pixels beyond the hard deadline.
        [session setValue:row[@"expired"] forKey:@"desktopRefreshPending"];
        XCTAssertEqual([session maintainDesktopBaseline:client now:now],![row[@"expired"] boolValue],@"%@",row[@"name"]);
        uint8_t bytes[32]; ssize_t count=recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT);
        XCTAssertEqual(count,[row[@"retry"] boolValue]?10:-1,@"%@",row[@"name"]);
        if ([row[@"expired"] boolValue]) XCTAssertEqualObjects(session.diagnosticCounters[@"failureStage"],@102);
        XCTAssertFalse(session.connected);
        [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testDuplicatePixelsDoNotPostponeAStallRetry {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=client->height=100; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running",@"established"]) [session setValue:@YES forKey:key];
    [session updatedX:0 y:0 width:100 height:50]; double now=NSProcessInfo.processInfo.systemUptime;
    [session setValue:@(now-2) forKey:@"baselineStarted"]; [session setValue:@(now-2) forKey:@"lastFullRefresh"]; [session setValue:@(now-2) forKey:@"baselineLastProgress"];
    [session updatedX:0 y:0 width:100 height:50]; [session updatedX:100 y:0 width:1 height:1];
    XCTAssertEqualWithAccuracy([[session valueForKey:@"baselineLastProgress"] doubleValue],now-2,0.001);
    XCTAssertTrue([session maintainDesktopBaseline:client now:now]); uint8_t bytes[32]; XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),10);
    XCTAssertEqualObjects(session.diagnosticCounters[@"fullRefreshRetries"],@1);
    XCTAssertFalse(session.connected);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testSubscriptionRefreshFlagsCoalesceOnlyWithinTheSameIncompleteBaseline {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=client->height=100; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running",@"established"]) [session setValue:@YES forKey:key];
    double now=NSProcessInfo.processInfo.systemUptime; uint8_t bytes[32];
    [session setValue:@YES forKey:@"desktopRefreshPending"]; XCTAssertTrue([session maintainDesktopBaseline:client now:now]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),10);
    [session setValue:@YES forKey:@"desktopRefreshPending"]; XCTAssertTrue([session maintainDesktopBaseline:client now:now+0.1]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
    XCTAssertEqualObjects(session.diagnosticCounters[@"coalescedFullRefreshes"],@1);
    client->width=101; XCTAssertTrue([session allocate:client]);
    XCTAssertTrue([session maintainDesktopBaseline:client now:NSProcessInfo.processInfo.systemUptime]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),10); XCTAssertEqual(CompanionVNCBE16(bytes+6),101);
    XCTAssertEqualObjects(session.diagnosticCounters[@"fullRefreshRequests"],@2);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testRoutinePullRestartWaitsThroughPauseInputOnlyAndRetirement {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=client->height=100; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented",@"routinePullPausedForSwitch"]) [session setValue:@YES forKey:key];
    uint8_t bytes[32];
    for (NSString *key in @[@"paused",@"inputOnly",@"stopping",@"overflow"]) {
        [session setValue:@YES forKey:key]; XCTAssertTrue([session resumeDesktopPull:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
        [session setValue:@NO forKey:key];
    }
    // Leaving input-only mode retires readiness until its replacement baseline.
    XCTAssertFalse(session.connected); XCTAssertTrue([session resumeDesktopPull:client]);
    XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
    [session setValue:@YES forKey:@"inputReady"]; [session setValue:@YES forKey:@"baselinePresented"];
    [session setValue:@NO forKey:@"modeChanged"]; // The socket owner consumed the mode transition and presented fresh pixels.
    XCTAssertTrue([session resumeDesktopPull:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),10);
    XCTAssertTrue([session resumeDesktopPull:client]); XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
    XCTAssertEqualObjects(session.diagnosticCounters[@"routinePullRestarts"],@1);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testSwitchHistoryIsBoundedNumericAndDoesNotSurviveOwnerReplacement {
    CompanionVNCSession *session=[CompanionVNCSession new]; NSLock *lock=[session valueForKey:@"lock"];
    double now=NSProcessInfo.processInfo.systemUptime;
    for (NSUInteger i=1;i<=15;i++) {
        [session setValue:@(now-1) forKey:@"desktopResizeAdmitted"]; [session setValue:@(now-0.9) forKey:@"desktopResizeStarted"];
        [session setValue:@(i) forKey:@"desktopResizeRequests"]; [session setValue:@NO forKey:@"desktopResizeSampleRecorded"];
        [session setValue:@2 forKey:@"desktopResizeOutcome"]; [session setValue:@900 forKey:@"desktopResizeCompleteMS"];
        [lock lock]; [session recordDesktopSwitchLocked:now]; [lock unlock];
    }
    NSArray *samples=session.diagnosticCounters[@"switches"]; XCTAssertEqual(samples.count,12); XCTAssertEqualObjects(samples[0][@"sequence"],@4);
    for (NSDictionary *sample in samples) for (id value in sample.allValues) XCTAssertTrue([value isKindOfClass:NSNumber.class]);
    [session connectAddresses:@[] port:5900 username:@"synthetic" password:@"synthetic"];
    XCTAssertEqual([session.diagnosticCounters[@"switches"] count],0); [session stop];
}
- (void)testReadMetricsSeparateBufferedParserBytesFromSocketReadAhead {
    NSDictionary *row=self.fixture[@"switchTimingDiagnostics"][@"bufferedRead"];
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; XCTAssertTrue(SetNonBlocking(client->sock));
    CompanionVNCReadMetrics metrics={0}; CompanionVNCReadService service={.metrics=&metrics};
    CompanionVNCSetReadService(client,&service);
    NSData *payload=[NSMutableData dataWithLength:[row[@"sentBytes"] unsignedIntegerValue]];
    XCTAssertEqual(write(pair[1],payload.bytes,payload.length),payload.length);
    for (NSUInteger i=0;i<[row[@"requests"] count];i++) {
        uint8_t bytes[32]; XCTAssertTrue(ReadFromRFBServer(client,(char *)bytes,[row[@"requests"][i] unsignedIntValue]));
        XCTAssertEqual(metrics.deliveredBytes,[row[@"deliveredTotals"][i] unsignedLongLongValue]);
        XCTAssertEqual(metrics.socketBytes,[row[@"socketReadTotals"][i] unsignedLongLongValue]);
    }
    XCTAssertEqual(client->buffered,0); XCTAssertEqual(metrics.waitCalls,0);
    CompanionVNCSetReadService(client,NULL); rfbClientCleanup(client); close(pair[1]);
}
- (void)testReadMetricsCountLargeAndPhasedReadsWithoutChangingBytes {
    NSDictionary *policy=self.fixture[@"switchTimingDiagnostics"], *phased=policy[@"phasedRead"];
    for (NSNumber *large in @[@NO,@YES]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; XCTAssertTrue(SetNonBlocking(client->sock));
        CompanionVNCReadMetrics metrics={0}; CompanionVNCReadService service={.metrics=&metrics}; CompanionVNCSetReadService(client,&service);
        NSUInteger first=large.boolValue?0:[phased[@"firstBytes"] unsignedIntegerValue];
        NSUInteger length=large.boolValue?[policy[@"largeReadBytes"] unsignedIntegerValue]:first+[phased[@"lastBytes"] unsignedIntegerValue];
        NSMutableData *payload=[NSMutableData dataWithLength:length], *received=[NSMutableData dataWithLength:length];
        uint8_t *pattern=payload.mutableBytes; for(NSUInteger i=0;i<length;i++) pattern[i]=(uint8_t)(i%251);
        if(first) XCTAssertEqual(write(pair[1],payload.bytes,first),first);
        XCTestExpectation *sent=[self expectationWithDescription:@"Synthetic remaining bytes sent"]; int peer=pair[1];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
            usleep([phased[@"delayMicroseconds"] unsignedIntValue]);
            NSUInteger offset=first;
            while(offset<length) { ssize_t count=write(peer,(const uint8_t *)payload.bytes+offset,length-offset); if(count<=0) break; offset+=(NSUInteger)count; }
            XCTAssertEqual(offset,length); [sent fulfill];
        });
        XCTAssertTrue(ReadFromRFBServer(client,received.mutableBytes,(unsigned int)length));
        [self waitForExpectations:@[sent] timeout:2];
        XCTAssertEqualObjects(received,payload); XCTAssertEqual(metrics.socketBytes,length); XCTAssertEqual(metrics.deliveredBytes,length);
        XCTAssertGreaterThan(metrics.waitCalls,0); XCTAssertGreaterThan(metrics.waitMS,0);
        CompanionVNCSetReadService(client,NULL); rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testReadMetricsDisabledOrRejectedDoNotConsumeOrChangeTheStream {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; XCTAssertTrue(SetNonBlocking(client->sock));
    CompanionVNCReadMetrics metrics={0}; CompanionVNCReadService reject={.service=RejectMetricRead,.metrics=&metrics};
    CompanionVNCSetReadService(client,&reject);
    uint8_t payload[]={1,2,3,4}, received[4]={0}; XCTAssertEqual(write(pair[1],payload,sizeof(payload)),sizeof(payload));
    XCTAssertFalse(ReadFromRFBServer(client,(char *)received,sizeof(received)));
    XCTAssertEqual(metrics.socketBytes,0); XCTAssertEqual(metrics.deliveredBytes,0); XCTAssertEqual(metrics.waitCalls,0);
    XCTAssertEqual(recv(client->sock,received,sizeof(received),MSG_PEEK|MSG_DONTWAIT),sizeof(payload));
    CompanionVNCSetReadService(client,NULL); XCTAssertTrue(ReadFromRFBServer(client,(char *)received,sizeof(received)));
    XCTAssertEqual(memcmp(received,payload,sizeof(payload)),0); XCTAssertEqual(metrics.socketBytes,0); XCTAssertEqual(metrics.deliveredBytes,0);
    rfbClientCleanup(client); close(pair[1]);
}
- (void)testSwitchMetricsCapturePhaseBytesAndNeverReuseAFailedOrReplacementOwnersSample {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    XCTAssertTrue([session installDesktopReadService:client]);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopDisplayID:5]); [session setValue:@NO forKey:@"releaseInputRequested"];
    XCTAssertTrue([session processDesktopSizeChange:client]); uint8_t bytes[32]; XCTAssertEqual(recv(pair[1],bytes,8,MSG_WAITALL),8);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"first"] session:session client:client peer:pair[1]];
    NSUInteger fresh=[self.fixture[@"switchTimingDiagnostics"][@"bufferedRead"][@"sentBytes"] unsignedIntegerValue];
    NSData *payload=[NSMutableData dataWithLength:fresh]; XCTAssertEqual(write(pair[1],payload.bytes,payload.length),payload.length);
    XCTAssertTrue(ReadFromRFBServer(client,(char *)bytes,(unsigned int)fresh));
    XCTAssertFalse(session.connected);
    XCTestExpectation *ready=[self expectationWithDescription:@"Measured fresh image becomes usable"];
    ready.expectedFulfillmentCount=2; __block NSUInteger frames=0; int peer=pair[1];
    session.frameHandler=^(UIImage *image){
        if (++frames==1) {
            // Another complete frame can be queued while the first callback is
            // presenting. The accepted switch must retain its first-frame sample.
            XCTAssertEqual(write(peer,payload.bytes,payload.length),payload.length);
            uint8_t later[32]; XCTAssertTrue(ReadFromRFBServer(client,(char *)later,(unsigned int)fresh));
            [session updatedX:0 y:0 width:1 height:1]; [session setValue:@0 forKey:@"lastFrame"]; [session publishFrame:client];
        }
        [ready fulfill];
    };
    [session updatedX:0 y:0 width:1600 height:1200]; [session publishFrame:client];
    [self waitForExpectations:@[ready] timeout:2]; session.frameHandler=nil;
    NSDictionary *sample=[session.diagnosticCounters[@"switches"] lastObject];
    XCTAssertEqualObjects(sample[@"readMeasurementsAvailable"],@YES); XCTAssertEqualObjects(sample[@"processingClockAvailable"],@YES);
    XCTAssertEqualObjects(sample[@"freshRfbBytes"],@(fresh)); XCTAssertGreaterThan([sample[@"rfbBytes"] unsignedIntegerValue],fresh);
    for (NSString *key in @[@"processingCPUMS",@"freshProcessingCPUMS",@"socketWaitMS",@"freshSocketWaitMS",@"frameCopyMS",@"presentationQueueMS",@"frameCallbackMS"]) {
        XCTAssertNotNil(sample[key]); XCTAssertTrue(isfinite([sample[key] doubleValue])); XCTAssertGreaterThanOrEqual([sample[key] doubleValue],0);
    }
    XCTAssertTrue(session.connected); XCTAssertEqualObjects(sample[@"outcome"],@2);
    XCTAssertTrue([session requestDesktopDisplayID:0]); [session setValue:@NO forKey:@"releaseInputRequested"];
    XCTAssertTrue([session processDesktopSizeChange:client]);
    [session finish:@"Synthetic incomplete switch"];
    sample=[session.diagnosticCounters[@"switches"] lastObject];
    XCTAssertEqualObjects(sample[@"readMeasurementsAvailable"],@NO); XCTAssertEqualObjects(sample[@"rfbBytes"],@0);
    XCTAssertEqualObjects(sample[@"freshRfbBytes"],@0); XCTAssertEqualObjects(sample[@"processingCPUMS"],@0);
    CompanionVNCSetReadService(client,NULL); rfbClientCleanup(client); close(pair[1]);
    [session connectAddresses:@[] port:5900 username:@"synthetic" password:@"synthetic"];
    XCTAssertEqual([session.diagnosticCounters[@"switches"] count],0); [session stop];
}
- (void)withDisplayMenuViewer:(void (^)(CompanionVNCViewer *, CompanionVNCSession *))body {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"monitorLayouts"][@"all"] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer",@"baselinePresented"]) [session setValue:@YES forKey:key];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded]; viewer.session=session;
    viewer.view.frame=CGRectMake(0,0,440,956); [viewer setValue:@YES forKey:@"trackpadMode"]; [viewer setValue:@YES forKey:@"foreground"];
    [viewer frame:[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(640,240)] imageWithActions:^(UIGraphicsImageRendererContext *ctx){}]];
    [(UIView *)[viewer valueForKey:@"login"] setHidden:YES]; [viewer updateConnectionChrome];
    UIWindowScene *scene=(UIWindowScene *)UIApplication.sharedApplication.connectedScenes.allObjects.firstObject;
    UIWindow *previous=scene.keyWindow, *window=[[UIWindow alloc] initWithWindowScene:scene];
    window.frame=viewer.view.frame; window.rootViewController=viewer; [window makeKeyAndVisible]; [viewer.view layoutIfNeeded];
    body(viewer,session);
    if (viewer.presentedViewController) {
        XCTestExpectation *closed=[self expectationWithDescription:@"Native display picker closes"];
        [viewer dismissViewControllerAnimated:NO completion:^{[closed fulfill];}]; [self waitForExpectations:@[closed] timeout:2];
    }
    window.hidden=YES; [previous makeKeyAndVisible]; [session setValue:@NO forKey:@"running"]; [viewer stopViewer]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testDisplayFailureNumericSummarySurvivesReconnectAndCleanExitDoesNotReplaceIt {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded]; [viewer setValue:@YES forKey:@"foreground"];
    [viewer prepareConnection]; CompanionVNCSession *failed=viewer.session;
    [failed setValue:@102 forKey:@"failureStage"]; [failed setValue:@3200 forKey:@"framebufferWidth"];
    [failed setValue:@1200 forKey:@"framebufferHeight"]; [failed setValue:@3840000 forKey:@"expectedPixels"];
    [failed setValue:@1920000 forKey:@"receivedPixels"];
    __block NSDictionary *last; viewer.diagnosticHandler=^(NSDictionary *snapshot){last=snapshot;};
    failed.stateHandler(@"Desktop did not finish loading — reconnect",@{@"handshakeStage":@5,@"failureStage":@102});
    NSDictionary *retained=last[@"lastConnectionFailure"]; XCTAssertNotNil(retained);
    XCTAssertEqualObjects(retained[@"failureStage"],@102); XCTAssertEqualObjects(retained[@"baselineExpectedPixels"],@3840000);
    XCTAssertEqualObjects(retained[@"baselineReceivedPixels"],@1920000);
    [viewer prepareConnection]; [viewer reportDiagnostics:viewer.session.diagnosticCounters];
    XCTAssertEqualObjects(last[@"lastConnectionFailure"],retained);
    viewer.session.stateHandler(@"Disconnected",@{@"handshakeStage":@5,@"failureStage":@0});
    XCTAssertEqualObjects(last[@"lastConnectionFailure"],retained,@"An intentional clean exit must not erase the last failure");
    [viewer stopViewer];
}
- (void)testSingleMonitorStreamKeepsOtherMonitorAndAllDisplaysReachable {
    for (NSNumber *target in @[@9,@0]) {
        [self withDisplayMenuViewer:^(CompanionVNCViewer *viewer, CompanionVNCSession *session) {
            NSDictionary *catalogue=session.desktopDisplayLayout;
            NSArray *displays=catalogue[@"views"]; XCTAssertEqual(displays.count,2);
            // Selected-stream metadata contains only its local-origin monitor.
            // The authenticated session retains the complete physical catalogue.
            viewer.displayLayout=@{@"aspectRatio":@1.3333333333,@"views":@[displays.firstObject],@"virtual":@NO};
            XCTAssertEqual([[viewer valueForKey:@"displayViews"] count],1);
            XCTAssertEqual([session.desktopDisplayLayout[@"views"] count],2);
            NSArray *items=[viewer displayMenuSections][0][@"items"];
            NSUInteger index=[items indexOfObjectPassingTest:^BOOL(NSDictionary *item,NSUInteger i,BOOL *stop) { return [item[@"kind"] isEqual:@"displays"]; }];
            XCTAssertNotEqual(index,NSNotFound,@"Choose Display must remain reachable after selecting a single stream");
            if (index!=NSNotFound) XCTAssertFalse([items[index][@"disabled"] boolValue]);
            [viewer chooseView];
            CompanionVNCDisplayPicker *picker=[viewer valueForKey:@"displayPicker"];
            [picker loadViewIfNeeded];
            XCTAssertEqualObjects([picker.displays valueForKey:@"id"],(@[@5,@9]));
            XCTAssertEqual([picker tableView:picker.tableView numberOfRowsInSection:0],3);
            picker.selectionHandler(target.unsignedIntValue ? target : nil);
            XCTAssertEqualObjects([viewer valueForKey:@"pendingStreamDisplayID"],target);
            XCTAssertEqualObjects([session valueForKey:@"desktopResizeDisplayID"],target);
        }];
    }
}
- (void)testDisplayPickerKeepsTheTouchedRowStableAcrossRepeatedServerRefreshes {
    [self withDisplayMenuViewer:^(CompanionVNCViewer *viewer,CompanionVNCSession *session){
        BOOL animations=UIView.areAnimationsEnabled; [UIView setAnimationsEnabled:NO];
        [viewer chooseView];
        UINavigationController *navigation=(id)viewer.presentedViewController;
        [navigation.view layoutIfNeeded];
        CompanionVNCDisplayPicker *picker=[viewer valueForKey:@"displayPicker"];
        XCTestExpectation *shown=[self expectationForPredicate:[NSPredicate predicateWithBlock:^BOOL(id object,NSDictionary *bindings){
            return picker.view.window != nil && !navigation.isBeingPresented;
        }] evaluatedWithObject:picker handler:nil];
        [self waitForExpectations:@[shown] timeout:2];
        [navigation.view layoutIfNeeded]; [picker.view layoutIfNeeded]; [picker.tableView layoutIfNeeded];
        NSIndexPath *first=[NSIndexPath indexPathForRow:0 inSection:0];
        UITableViewCell *touched=[picker.tableView cellForRowAtIndexPath:first]; XCTAssertNotNil(touched);
        touched.highlighted=YES;
        CGRect before=[touched convertRect:touched.bounds toView:viewer.view.window];
        CGFloat barBottom=CGRectGetMaxY([navigation.navigationBar convertRect:navigation.navigationBar.bounds toView:viewer.view.window]);
        XCTAssertGreaterThanOrEqual(CGRectGetMinY(before),barBottom-1,@"The first display must be below the navigation bar");
        for (NSUInteger i=0;i<20;i++) { [viewer updateDisplayPicker]; [picker.tableView layoutIfNeeded]; }
        UITableViewCell *after=[picker.tableView cellForRowAtIndexPath:first];
        XCTAssertEqual(touched,after,@"An unchanged catalogue must not replace a row under the user's finger");
        XCTAssertTrue(after.highlighted); XCTAssertTrue(CGRectEqualToRect(before,[after convertRect:after.bounds toView:viewer.view.window]));
        NSArray *frozen=picker.displays;
        picker.displays=@[frozen.lastObject]; [picker.tableView layoutIfNeeded];
        XCTAssertEqualObjects(picker.displays,frozen,@"A real catalogue change waits for a fresh presentation");
        XCTAssertEqual([picker.tableView numberOfRowsInSection:0],3);
        XCTAssertEqual(touched,[picker.tableView cellForRowAtIndexPath:first]); XCTAssertTrue(touched.highlighted);
        picker.selectedID=@9; [picker.tableView layoutIfNeeded];
        XCTAssertEqual(touched,[picker.tableView cellForRowAtIndexPath:first]);
        XCTAssertEqual([picker.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:1 inSection:0]].accessoryType,UITableViewCellAccessoryCheckmark);
        picker.selectedID=nil; [picker.tableView layoutIfNeeded];
        XCTAssertEqual(touched,[picker.tableView cellForRowAtIndexPath:first]);
        XCTAssertEqual([picker.tableView cellForRowAtIndexPath:[NSIndexPath indexPathForRow:2 inSection:0]].accessoryType,UITableViewCellAccessoryCheckmark);
        [UIView setAnimationsEnabled:animations];
    }];
}
- (void)testNativeDisplayMenuRetiresPointerAndLateCallbacksCannotBlockItsChoice {
    XCTAssertEqualObjects(self.fixture[@"displayMenuHandoff"][@"sessionStillRejectsActivePointerRequests"],@YES);
    [self withDisplayMenuViewer:^(CompanionVNCViewer *viewer,CompanionVNCSession *session){
        session.localPointerInteractionActive=YES; XCTAssertFalse([session requestDesktopDisplayID:5]);
        CompanionVNCControls *controls=[viewer valueForKey:@"controls"]; [controls open];
        XCTAssertFalse(session.localPointerInteractionActive);
        DesktopMenuPan *pan=[DesktopMenuPan new]; pan.sampleState=UIGestureRecognizerStateChanged; CGPoint point;
        XCTAssertFalse([viewer pointerForGesture:pan point:&point],@"A late pan callback must not reactivate input behind the control panel");
        XCTAssertFalse(session.localPointerInteractionActive);
        [controls close];
        pan.sampleState=UIGestureRecognizerStateBegan; XCTAssertTrue([viewer pointerForGesture:pan point:&point]);
        XCTAssertTrue(session.localPointerInteractionActive,@"A fresh desktop gesture still works after closing the panel");
        [viewer chooseView];
        XCTAssertFalse(session.localPointerInteractionActive,@"Presenting the native picker ends prior pointer ownership");
        XCTAssertNotNil(viewer.presentedViewController);
        pan.sampleState=UIGestureRecognizerStateChanged;
        XCTAssertFalse([viewer pointerForGesture:pan point:&point],@"Late callbacks behind a modal menu are ignored");
        CompanionVNCDisplayPicker *picker=[viewer valueForKey:@"displayPicker"];
        session.localPointerInteractionActive=YES; // Earlier callback queued before the explicit choice.
        picker.selectionHandler(@5);
        XCTAssertFalse(session.localPointerInteractionActive);
        XCTAssertEqualObjects([viewer valueForKey:@"pendingStreamDisplayID"],@5);
        XCTAssertTrue([[session valueForKey:@"desktopResizePending"] boolValue]);
        XCTAssertFalse(session.connected,@"The new frame must still complete before input reopens");
    }];
}
- (void)testRejectedDisplayChoiceKeepsNoticeAndNeverBypassesPausedSession {
    [self withDisplayMenuViewer:^(CompanionVNCViewer *viewer,CompanionVNCSession *session){
        [viewer chooseView]; [session setValue:@YES forKey:@"paused"];
        CompanionVNCDisplayPicker *picker=[viewer valueForKey:@"displayPicker"]; picker.selectionHandler(@5);
        XCTAssertNil([viewer valueForKey:@"pendingStreamDisplayID"]);
        XCTAssertFalse([[session valueForKey:@"desktopResizePending"] boolValue]);
        XCTAssertGreaterThan([[viewer valueForKey:@"displayNoticeUntil"] doubleValue],NSProcessInfo.processInfo.systemUptime);
        XCTAssertEqualObjects([viewer cursorDiagnosticFlags][@"displaySelectionRejections"],@1);
        XCTAssertGreaterThan([[viewer cursorDiagnosticFlags][@"displaySelectionRejectMask"] unsignedIntegerValue],0);
        XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"],@0);
    }];
}
- (void)testMatchingDisplayKeepsProgressAfterLayoutDeadlineButHonorsBaselineDeadline {
    for (NSNumber *expire in @[@NO,@YES]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=3200; client->height=1200; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        [self deliverLayout:self.fixture[@"monitorLayouts"][@"all"] session:session client:client peer:pair[1]];
        for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
        XCTAssertTrue([session requestDesktopDisplayID:5]); [session setValue:@NO forKey:@"releaseInputRequested"];
        XCTAssertTrue([session processDesktopSizeChange:client]); uint8_t bytes[32]; XCTAssertEqual(recv(pair[1],bytes,8,MSG_WAITALL),8);
        [self deliverLayout:self.fixture[@"monitorLayouts"][@"first"] session:session client:client peer:pair[1]];
        XCTAssertTrue([session requestFullDesktop:client]); XCTAssertEqual(recv(pair[1],bytes,10,MSG_WAITALL),10);
        [session setValue:@NO forKey:@"desktopRefreshPending"]; [session updatedX:0 y:0 width:1600 height:600];
        NSNumber *received=session.diagnosticCounters[@"baselineReceivedPixels"]; double now=NSProcessInfo.processInfo.systemUptime;
        [session setValue:@(now-6.5) forKey:@"desktopResizeStarted"];
        [session setValue:@(now-(expire.boolValue?8.1:2.0)) forKey:@"baselineStarted"];
        [session setValue:@(now-0.1) forKey:@"baselineLastProgress"]; [session setValue:@(now-1.5) forKey:@"lastFullRefresh"];
        XCTAssertTrue([session processDesktopSizeChange:client]);
        XCTAssertEqualObjects(session.diagnosticCounters[@"probeTimedOut"],@0);
        XCTAssertEqualObjects(session.diagnosticCounters[@"baselineReceivedPixels"],received,@"The layout was accepted; do not throw away its fresh pixels at six seconds");
        XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
        XCTAssertFalse(session.connected);
        if (expire.boolValue) {
            XCTAssertFalse([session maintainDesktopBaseline:client now:now]); XCTAssertEqualObjects(session.diagnosticCounters[@"failureStage"],@102);
            XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
        } else {
            XCTAssertTrue([session maintainDesktopBaseline:client now:now]);
            XCTAssertEqual(recv(pair[1],bytes,sizeof(bytes),MSG_DONTWAIT),-1);
            XCTestExpectation *fresh=[self expectationWithDescription:@"Complete the same progressing baseline"];
            session.frameHandler=^(UIImage *image){[fresh fulfill];}; [session updatedX:0 y:600 width:1600 height:600]; [session publishFrame:client];
            [self waitForExpectations:@[fresh] timeout:2]; session.frameHandler=nil;
            XCTAssertTrue(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@1);
            XCTAssertEqualObjects(session.diagnosticCounters[@"fullRefreshRequests"],@1);
        }
        [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testDisplaySelectionTimeoutAndInterruptedStateDoNotPersistOrAdmitInput {
    DesktopSizeSession *fake=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:fake];
    __block NSUInteger saves=0; viewer.displaySelectionHandler=^(NSNumber *identifier){saves++;};
    [viewer setValue:@5 forKey:@"pendingStreamDisplayID"]; fake.snapshot=@{@"probeOutcome":@3};
    [viewer updateDesktopSizeState]; XCTAssertEqual(saves,0); XCTAssertNil([viewer valueForKey:@"pendingStreamDisplayID"]);
    for (NSString *key in @[@"inputInactive",@"restoreViewportPending",@"inputOnly"]) {
        [viewer setValue:@YES forKey:key]; XCTAssertFalse([viewer applyStreamDisplay:@5]); [viewer setValue:@NO forKey:key];
    }
    [viewer setValue:[NSObject new] forKey:@"textReview"]; XCTAssertFalse([viewer applyStreamDisplay:@5]); [viewer setValue:nil forKey:@"textReview"];
    XCTAssertFalse([viewer applyStreamDisplay:@(-1)]); XCTAssertFalse([viewer applyStreamDisplay:@(UINT64_MAX)]);
    [viewer stopViewer];
}
- (void)testReplacementOwnerCannotReusePreviousDisplayIDsOrPendingResize {
    CompanionVNCSession *session=[CompanionVNCSession new];
    [session setValue:@{@"views":@[@{@"id":@5}]} forKey:@"desktopCatalogue"];
    [session setValue:@3 forKey:@"desktopResizeOutcome"]; [session setValue:@2 forKey:@"desktopResizeRequests"];
    [session setValue:@YES forKey:@"desktopResizeAwaiting"];
    // No endpoints: exercise synchronous owner setup without contacting a Mac.
    [session connectAddresses:@[] port:5900 username:@"synthetic" password:@"synthetic"];
    XCTAssertEqual(session.desktopDisplayLayout.count,0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"],@0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeAwaiting"],@NO);
    XCTAssertFalse([session requestDesktopDisplayID:5]); [session stop];
}
- (void)testMirrorHandoffReusesUnrememberedLoginAndDropsOldVirtualDisplayID {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    DesktopSizeSession *session=[DesktopSizeSession new]; session.usable=YES; session.available=YES; session.snapshot=self.acceptedSnapshot;
    viewer.session=session;
    id<DesktopLoginRecoveryTesting> state=[viewer valueForKey:@"credentialState"];
    [state editWithUsername:@"synthetic" password:@"transient-only" remember:NO]; [state beginLogin]; [state authenticated];
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8,8)];
    UIImage *image=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){ [UIColor.whiteColor setFill]; UIRectFill(CGRectMake(0,0,8,8)); }];
    [viewer setValue:image forKey:@"lastFramebuffer"]; [viewer setValue:@{@"id":@99} forKey:@"selectedDisplay"];
    [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,8,8)] forKey:@"activeCrop"];
    __block NSUInteger attempts=0; __block BOOL retired=NO;
    viewer.disconnectHandler=^{retired=YES;};
    viewer.connectHandler=^(NSString *user,NSString *password,BOOL remember){
        attempts++; XCTAssertTrue(retired, @"Retire the old SSH owner before opening its replacement"); XCTAssertEqualObjects(user,@"synthetic"); XCTAssertEqualObjects(password,@"transient-only"); XCTAssertFalse(remember);
        XCTAssertNil([viewer valueForKey:@"resumeDisplayID"]);
        XCTAssertTrue(CGSizeEqualToSize([[viewer valueForKey:@"resumeCropSize"] CGSizeValue],CGSizeZero));
    };
    XCTAssertTrue([viewer applyMirrorDisplay]); XCTAssertEqual(attempts,1);
    XCTAssertNotNil([state loginForResume]); viewer.connectHandler=nil; viewer.disconnectHandler=nil; [viewer stopViewer];
}
- (void)testSavedMonitorWaitsForUsablePixelsAndRequestsStreamInsteadOfOnlyCropping {
    DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
    NSDictionary *display=@{@"id":@5,@"title":@"Display 1",@"pixelWidth":@1600,@"pixelHeight":@1200,@"x":@0,@"y":@0,@"width":@0.5,@"height":@1};
    session.catalogue=@{@"views":@[display],@"aspectRatio":@(3200.0/1200)};
    [viewer setValue:@[display] forKey:@"displayViews"]; [viewer setValue:@(3200.0/1200) forKey:@"displayAspect"];
    [viewer setValue:[NSValue valueWithCGSize:CGSizeMake(3200,1200)] forKey:@"framebufferSize"];
    viewer.restoredDisplayID=@5; viewer.restoredDesktopSizePreset=0;
    session.available=NO; session.usable=NO; [viewer restoreSavedDisplay]; XCTAssertNil(session.requestedDisplay);
    XCTAssertEqualObjects(viewer.restoredDisplayID,@5);
    session.available=YES; session.usable=YES; [viewer restoreSavedDisplay];
    XCTAssertEqualObjects(session.requestedDisplay,@5); XCTAssertEqualObjects([viewer valueForKey:@"pendingStreamDisplayID"],@5);
    XCTAssertNil(viewer.restoredDisplayID);
    [viewer stopViewer];
}
- (void)testImmediateClosureLeavesNumericRequestOutcome {
    CompanionVNCSession *session = [CompanionVNCSession new];
    for (NSString *key in @[@"running", @"established", @"inputReady", @"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:832 height:440]);
    [session finish:@"Disconnected"];
    NSDictionary *counters = session.diagnosticCounters;
    XCTAssertEqualObjects(counters[@"probeOutcome"], @3);
    XCTAssertEqualObjects(counters[@"probeAwaiting"], @NO);
    XCTAssertEqualObjects(counters[@"sessionRunning"], @NO);
    XCTAssertEqualObjects(counters[@"sessionEstablished"], @NO);
    XCTAssertNotNil(counters[@"sampleUptime"]);
}
- (void)testMirrorHandoffBlocksEveryRemoteInputPathWithoutBlockingFreshPixels {
    CompanionVNCSession *owner=[CompanionVNCSession new];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [owner setValue:@YES forKey:key];
    XCTAssertTrue(owner.desktopFrameReady); XCTAssertTrue(owner.composedTextReady);
    owner.displayHandoffInputBlocked=YES;
    XCTAssertTrue(owner.desktopFrameReady, @"Mode verification must still observe a fully presented baseline");
    XCTAssertFalse(owner.composedTextReady); XCTAssertFalse([owner tryClickX:1 y:1 mask:1]);
    NSArray *keys=@[@{@"key":@65,@"down":@YES}]; XCTAssertFalse([owner tryKeyEvents:keys]);
    [owner pointerX:1 y:1 mask:1]; [owner key:65 down:YES]; owner.localPointerInteractionActive=YES;
    XCTAssertFalse(owner.localPointerInteractionActive); XCTAssertEqual([[owner valueForKey:@"events"] count],0);
    [owner suspendInputForInterruption]; [owner resumeInputAfterInterruption]; [owner resumeInputAfterReview];
    XCTAssertTrue(owner.displayHandoffInputBlocked, @"Other readiness gates cannot release the display handoff");
    owner.displayHandoffInputBlocked=NO; XCTAssertTrue(owner.composedTextReady); XCTAssertTrue([owner tryClickX:1 y:1 mask:1]);
    [owner stop]; [owner setValue:@NO forKey:@"running"];
}
- (DesktopSizeViewer *)mirrorViewerWithSession:(DesktopSizeSession *)session attempt:(NSUInteger)attempt {
    DesktopSizeViewer *viewer=[self viewerWithSession:session];
    [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@(attempt) forKey:@"mirrorRestoreAttempts"];
    [viewer setValue:[NSMutableArray new] forKey:@"mirrorObservedLayouts"];
    session.displayHandoffInputBlocked=YES;
    return viewer;
}
- (void)testSavedMirrorEntersFullRestartOnceThenAcceptsOnlyFreshPhysicalOwner {
    NSDictionary *policy=self.fixture[@"mirrorHandoffPolicy"];
    XCTAssertEqualObjects(policy[@"maximumFreshConnectionsPerRestart"],@2); XCTAssertEqualObjects(policy[@"retirementGraceMilliseconds"],@16000);
    DesktopSizeSession *session=[DesktopSizeSession new]; session.snapshot=self.acceptedSnapshot;
    DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1];
    session.usable=NO; [viewer updateDisplayModeRestoration]; XCTAssertFalse([[viewer valueForKey:@"mirrorRestartScheduled"] boolValue]);
    session.usable=YES; __block NSUInteger retirements=0; viewer.disconnectHandler=^{retirements++;};
    [viewer setValue:@YES forKey:@"checkingResume"];
    [viewer updateDisplayModeRestoration]; [viewer updateDisplayModeRestoration];
    XCTAssertFalse([[viewer valueForKey:@"checkingResume"] boolValue], @"The old resume watchdog must not exceed the handoff budget");
    XCTAssertEqual(retirements,0); XCTAssertTrue(session.displayHandoffInputBlocked);
    XCTestExpectation *turn=[self expectationWithDescription:@"deferred retry"];
    dispatch_async(dispatch_get_main_queue(), ^{ [turn fulfill]; }); [self waitForExpectations:@[turn] timeout:2];
    XCTAssertEqual(retirements,1); XCTAssertTrue(viewer.requestedResume); XCTAssertTrue([[viewer valueForKey:@"changingDisplayMode"] boolValue]);
    XCTAssertTrue([[viewer valueForKey:@"mirrorFullRestartUsed"] boolValue]); XCTAssertEqual(viewer.mirrorRetirementDelay,16);
    // The real coordinator creates the replacement and increments the attempt.
    [viewer prepareConnection]; XCTAssertTrue(viewer.session.displayHandoffInputBlocked);
    XCTAssertEqualObjects([viewer valueForKey:@"mirrorRestoreAttempts"],@2);
    DesktopSizeSession *physical=[DesktopSizeSession new]; physical.usable=YES; physical.displayHandoffInputBlocked=YES;
    physical.snapshot=self.physicalSnapshot; viewer.session=physical;
    [viewer updateDisplayModeRestoration]; XCTAssertFalse(physical.displayHandoffInputBlocked);
    XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]); XCTAssertEqualObjects([viewer valueForKey:@"mirrorRestoreOutcome"],@2);
    XCTAssertEqualObjects([viewer valueForKey:@"mirrorObservedLayouts"],(@[@YES,@NO]));
    XCTAssertEqual(retirements,1); viewer.disconnectHandler=nil; [viewer stopViewer];
}
- (void)testFullMirrorRestartRejectsVirtualResultWithoutAnotherConnectionOrRemoteInput {
    DesktopSizeSession *session=[DesktopSizeSession new]; session.snapshot=self.acceptedSnapshot;
    DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1];
    [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"]; [viewer setValue:@1 forKey:@"modeRecoveryAttempts"];
    __block NSUInteger retirements=0; viewer.disconnectHandler=^{retirements++;};
    [viewer updateDisplayModeRestoration]; [viewer updateDisplayModeRestoration];
    XCTAssertTrue(session.displayHandoffInputBlocked); XCTAssertFalse(viewer.requestedResume);
    XCTestExpectation *turn=[self expectationWithDescription:@"failed Mirror retirement"];
    dispatch_async(dispatch_get_main_queue(), ^{[turn fulfill];}); [self waitForExpectations:@[turn] timeout:2];
    XCTAssertEqual(retirements,1); XCTAssertFalse(viewer.requestedResume); XCTAssertEqual(session.requests,0);
    XCTAssertTrue(session.displayHandoffInputBlocked, @"A virtual result must not reopen remote input");
    XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]);
    XCTAssertEqualObjects([viewer valueForKey:@"mirrorRestoreOutcome"],@3);
    XCTAssertTrue([[viewer valueForKey:@"loginIssueDetails"] containsString:@"Mirror Mac Screen couldn’t be opened"]);
    viewer.disconnectHandler=nil; [viewer stopViewer];
}
- (void)testExplicitMirrorRequestsOneFullCleanupWithoutDelayForPhysicalMonitorSwitch {
    DesktopSizeSession *session=[DesktopSizeSession new]; session.snapshot=self.acceptedSnapshot;
    DesktopSizeViewer *viewer=[self viewerWithSession:session];
    XCTAssertEqual(viewer.mirrorRetirementDelay,0);
    XCTAssertTrue([viewer applyMirrorDisplay]); XCTAssertEqual(viewer.mirrorRetirementDelay,16);
    XCTAssertTrue([[viewer valueForKey:@"mirrorFullRestartUsed"] boolValue]);
    ((UIView *)[viewer valueForKey:@"login"]).hidden=YES; // Connected desktop presentation.
    [viewer showMirrorCleanupRemaining:16];
    XCTAssertEqualObjects(((UILabel *)[viewer valueForKey:@"status"]).text,@"Switching display mode…");
    XCTAssertFalse(((UIView *)[viewer valueForKey:@"statusBackdrop"]).hidden);
    [viewer finishMirrorCleanup]; XCTAssertEqual(viewer.mirrorRetirementDelay,0);
    [viewer updateDisplayModeRestoration];
    XCTestExpectation *turn=[self expectationWithDescription:@"no fast reconnect"];
    viewer.requestedResume=NO; dispatch_async(dispatch_get_main_queue(),^{[turn fulfill];}); [self waitForExpectations:@[turn] timeout:2];
    XCTAssertTrue(viewer.requestedResume); XCTAssertEqual(viewer.mirrorRetirementDelay,16);
    XCTAssertEqualObjects([viewer valueForKey:@"modeRecoveryAttempts"],@1); [viewer stopViewer];
    session=[DesktopSizeSession new]; session.snapshot=@{@"layoutVirtual":@NO};
    viewer=[self viewerWithSession:session];
    XCTAssertTrue([viewer applyMirrorDisplay]); XCTAssertEqual(viewer.mirrorRetirementDelay,0); XCTAssertFalse(viewer.requestedResume);
    XCTAssertTrue([viewer applyStreamDisplay:@5]); XCTAssertEqual(viewer.mirrorRetirementDelay,0); [viewer stopViewer];
}
- (void)testQuietIntervalRemainsRequiredAcrossReplacementPreparationUntilItFinishes {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@YES forKey:@"mirrorRequiresCleanup"];
    [viewer prepareConnection]; XCTAssertEqual(viewer.mirrorRetirementDelay,16); XCTAssertTrue(viewer.session.displayHandoffInputBlocked);
    [viewer prepareConnection]; XCTAssertEqual(viewer.mirrorRetirementDelay,16);
    [viewer setValue:@YES forKey:@"starting"]; [viewer showMirrorCleanupRemaining:9];
    [viewer becameInactive]; XCTAssertFalse(viewer.connectionForegroundAvailable);
    [viewer showMirrorCleanupRemaining:8]; XCTAssertEqualObjects([viewer valueForKey:@"mirrorCleanupRemaining"],@9);
    [viewer foregrounded]; XCTAssertTrue(viewer.connectionForegroundAvailable);
    XCTAssertEqual(viewer.mirrorRetirementDelay,16); [viewer finishMirrorCleanup]; XCTAssertEqual(viewer.mirrorRetirementDelay,0);
    [viewer stopViewer]; XCTAssertFalse(viewer.connectionForegroundAvailable); XCTAssertEqual(viewer.mirrorRetirementDelay,0);
}
- (void)testPendingMirrorRetryCannotCrossExitOwnerReplacementOrInactivity {
    for (NSString *reason in @[@"exit",@"replacement",@"inactive",@"background"]) {
        DesktopSizeSession *session=[DesktopSizeSession new]; session.snapshot=self.acceptedSnapshot;
        DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1]; viewer.disconnectHandler=^{};
        [viewer updateDisplayModeRestoration]; XCTAssertTrue([[viewer valueForKey:@"mirrorRestartScheduled"] boolValue]);
        if ([reason isEqualToString:@"exit"]) [viewer stopViewer];
        if ([reason isEqualToString:@"replacement"]) [viewer prepareConnection];
        if ([reason isEqualToString:@"inactive"]) [viewer setValue:@YES forKey:@"inputInactive"];
        if ([reason isEqualToString:@"background"]) [viewer setValue:@NO forKey:@"foreground"];
        XCTestExpectation *turn=[self expectationWithDescription:reason]; dispatch_async(dispatch_get_main_queue(),^{[turn fulfill];});
        [self waitForExpectations:@[turn] timeout:2]; XCTAssertFalse(viewer.requestedResume,@"%@",reason);
        viewer.disconnectHandler=nil; [viewer stopViewer];
    }
}
- (void)testInitialSavedMirrorUsesTransientLoginAndKeepsInputBlockedUntilPhysicalBaseline {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded]; viewer.restoredDesktopSizePreset=0;
    ((UITextField *)[viewer valueForKey:@"username"]).text=@"synthetic";
    ((UITextField *)[viewer valueForKey:@"password"]).text=@"transient";
    __block NSUInteger connects=0; viewer.connectHandler=^(NSString *user,NSString *password,BOOL remember){
        connects++; [viewer prepareConnection]; XCTAssertTrue(viewer.session.displayHandoffInputBlocked);
        XCTAssertEqualObjects([viewer valueForKey:@"mirrorRestoreAttempts"],@1);
    };
    [viewer startResuming:NO]; XCTAssertEqual(connects,1);
    [viewer showConnectionFailureStage:4];
    XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]); XCTAssertFalse([[viewer valueForKey:@"mirrorRestartScheduled"] boolValue]);
    XCTAssertEqual(connects,1); viewer.connectHandler=nil; [viewer stopViewer];
}

- (void)testBothModeAlertsCancelWithoutChangingPreferenceOrRetiringOwner {
    for (NSNumber *target in @[@0,@2]) {
        DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
        BOOL fromVirtual=target.integerValue==0;
        session.snapshot=fromVirtual ? self.acceptedSnapshot : self.physicalSnapshot;
        viewer.restoredDesktopSizePreset=fromVirtual ? 2 : 0;
        __block NSUInteger retires=0,saves=0;
        viewer.disconnectHandler=^{retires++;}; viewer.desktopSizeSelectionHandler=^(NSInteger p){saves++;};
        UIAlertController *alert=[viewer displayModeConfirmationForPreset:target.integerValue]; XCTAssertNotNil(alert);
        XCTAssertEqualObjects(alert.title,fromVirtual ? @"Switch to Mirror Mac Screen?" : @"Switch to Virtual Display?");
        XCTAssertEqualObjects(alert.message,fromVirtual ? @"Your connection will restart to show your Mac’s displays." : @"Your connection will restart. Your Mac’s screen may go dark.");
        XCTAssertEqualObjects([alert.actions valueForKey:@"title"],(@[@"Cancel",@"Switch & Reconnect"]));
        XCTAssertEqual(alert.actions[0].style,UIAlertActionStyleCancel);
        [viewer cancelDisplayModeConfirmation]; XCTAssertFalse([viewer acceptDisplayModeConfirmation]);
        XCTAssertEqual(retires,0); XCTAssertEqual(saves,0); XCTAssertFalse(viewer.requestedResume);
        XCTAssertEqual(viewer.restoredDesktopSizePreset,fromVirtual?2:0); XCTAssertEqual(viewer.session,session);
        viewer.disconnectHandler=nil; [viewer stopViewer];
    }
}
- (void)testBothModeSwitchesRestartWithOneOwnerAndSaveOnlyMatchingFreshPixels {
    for (NSNumber *target in @[@0,@2]) {
        DesktopSizeSession *old=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:old];
        BOOL fromVirtual=target.integerValue==0;
        old.snapshot=fromVirtual ? self.acceptedSnapshot : self.physicalSnapshot;
        viewer.restoredDesktopSizePreset=fromVirtual ? 2 : 0;
        [viewer setValue:@{@"id":@9} forKey:@"selectedDisplay"];
        [viewer setValue:@2 forKey:@"pendingDesktopSizePreset"]; // Busy requests cannot open a confirmation.
        XCTAssertNil([viewer displayModeConfirmationForPreset:target.integerValue]); [viewer setValue:@0 forKey:@"pendingDesktopSizePreset"];
        __block NSUInteger retires=0,saves=0; __block NSInteger saved=-1;
        viewer.disconnectHandler=^{retires++;}; viewer.desktopSizeSelectionHandler=^(NSInteger p){saves++;saved=p;};
        UIAlertController *alert=[viewer displayModeConfirmationForPreset:target.integerValue]; XCTAssertNotNil(alert);
        XCTAssertTrue([viewer acceptDisplayModeConfirmation]); XCTAssertFalse([viewer acceptDisplayModeConfirmation]);
        XCTAssertEqual(retires,1); XCTAssertTrue(viewer.requestedResume); XCTAssertEqual(saves,0); XCTAssertEqual(old.requests,0);
        XCTAssertTrue(old.displayHandoffInputBlocked); XCTAssertNil([viewer valueForKey:@"selectedDisplay"]);
        XCTAssertNil(old.stateHandler); XCTAssertNil(old.frameHandler); XCTAssertNil(old.cursorHandler); XCTAssertNil(old.displayLayoutHandler);
        DesktopSizeSession *fresh=[DesktopSizeSession new]; fresh.usable=NO; fresh.available=YES; fresh.displayHandoffInputBlocked=YES;
        fresh.snapshot=target.integerValue ? self.acceptedSnapshot : self.physicalSnapshot;
        viewer.session=fresh; [viewer updateDisplayModeRestoration]; XCTAssertEqual(saves,0); XCTAssertTrue(fresh.displayHandoffInputBlocked);
        fresh.usable=YES; [viewer updateDisplayModeRestoration];
        XCTAssertEqual(saves,1); XCTAssertEqual(saved,target.integerValue); XCTAssertFalse(fresh.displayHandoffInputBlocked);
        XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]);
        viewer.disconnectHandler=nil; [viewer stopViewer];
    }
}
- (void)testConfirmationCannotCrossReplacementInactivityExitOrFileTransferWarning {
    for (NSString *reason in @[@"replacement",@"inactive",@"exit"]) {
        DesktopSizeSession *old=[DesktopSizeSession new]; old.snapshot=self.acceptedSnapshot;
        DesktopSizeViewer *viewer=[self viewerWithSession:old]; viewer.restoredDesktopSizePreset=2;
        viewer.filesTransferActiveHandler=^{return YES;};
        UIAlertController *alert=[viewer displayModeConfirmationForPreset:0];
        XCTAssertTrue([alert.message hasSuffix:@"File transfers using this connection will stop."]);
        if ([reason isEqualToString:@"replacement"]) [viewer prepareConnection];
        else if ([reason isEqualToString:@"inactive"]) [viewer becameInactive];
        else [viewer stopViewer];
        XCTAssertFalse([viewer acceptDisplayModeConfirmation]); XCTAssertFalse(viewer.requestedResume);
        XCTAssertEqual(viewer.restoredDesktopSizePreset,2); [viewer stopViewer];
    }
    DesktopSizeSession *physical=[DesktopSizeSession new]; physical.snapshot=self.physicalSnapshot;
    DesktopSizeViewer *viewer=[self viewerWithSession:physical];
    XCTAssertNil([viewer displayModeConfirmationForPreset:0]); XCTAssertTrue([viewer applyStreamDisplay:@5]);
    XCTAssertNil([viewer valueForKey:@"modeConfirmationPreset"]); XCTAssertFalse(viewer.requestedResume);
    XCTAssertEqualObjects(physical.requestedDisplay,@5); XCTAssertEqual(viewer.session,physical); [viewer stopViewer];
}
- (void)testVirtualModeHandoffRequestsOnceWhileAllRemoteInputRemainsBlocked {
    DesktopSizeSession *session=[DesktopSizeSession new]; session.snapshot=self.physicalSnapshot;
    DesktopSizeViewer *viewer=[self viewerWithSession:session];
    [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@2 forKey:@"modeTargetPreset"];
    session.displayHandoffInputBlocked=YES;
    [viewer updateDisplayModeRestoration]; [viewer updateDisplayModeRestoration];
    XCTAssertEqual(session.requests,1); XCTAssertEqual(session.lastPreset,2); XCTAssertTrue(session.displayHandoffInputBlocked);
    XCTAssertFalse([session tryClickX:1 y:1 mask:1]); XCTAssertFalse(session.composedTextReady);
    session.snapshot=@{@"layoutVirtual":@YES,@"layoutCount":@1,@"probeOutcome":@3};
    __block NSUInteger saves=0; viewer.desktopSizeSelectionHandler=^(NSInteger p){saves++;};
    viewer.restoredDesktopSizePreset=2; [viewer setValue:@0 forKey:@"modePreviousPreset"];
    [viewer updateDisplayModeRestoration];
    XCTAssertEqualObjects([viewer valueForKey:@"failedDisplayModePreset"],@2);
    XCTAssertEqual(viewer.restoredDesktopSizePreset,0); XCTAssertEqual(saves,0);
    XCTAssertEqualObjects([viewer valueForKey:@"lastConnectionFailure"][@"displayModeFailureStage"],@117);
    XCTAssertNil(session.stateHandler); XCTAssertNil(session.frameHandler);
    XCTAssertTrue([[viewer valueForKey:@"loginIssueDetails"] containsString:@"virtual display"]);
    XCTAssertNotNil([(id<DesktopLoginRecoveryTesting>)[viewer valueForKey:@"credentialState"] loginForResume]);
    [viewer stopViewer];
}
- (void)testHandoffOnlyResizeCannotBypassOtherNativeReadinessGates {
    for (NSString *blocked in @[@"none",@"paused",@"stopping",@"reviewInputSuspended",@"interruptionInputSuspended",@"localPointerInteractionActive",@"coverageLayoutValid"]) {
        CompanionVNCSession *session=[CompanionVNCSession new];
        for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented",@"appleGestureServer",@"coverageLayoutValid"]) [session setValue:@YES forKey:key];
        session.displayHandoffInputBlocked=YES;
        if (![blocked isEqualToString:@"none"]) [session setValue:@(![blocked isEqualToString:@"coverageLayoutValid"]) forKey:[blocked isEqualToString:@"localPointerInteractionActive"]?@"_localPointerInteractionActive":blocked];
        XCTAssertFalse([session requestDesktopSizePreset:2]);
        XCTAssertEqual([session requestDesktopSizePresetForHandoff:2],[blocked isEqualToString:@"none"],@"%@",blocked);
        XCTAssertFalse([session tryClickX:1 y:1 mask:1]); XCTAssertFalse(session.composedTextReady);
        XCTAssertTrue(session.displayHandoffInputBlocked); [session setValue:@NO forKey:@"running"]; [session stop];
    }
}
- (void)testVirtualLayoutCanArriveAfterTwelveSecondsWithoutTimeoutOrOldPixelAcceptance {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=1600; client->height=1600;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [self deliverLayout:self.fixture[@"layoutCases"][0] session:session client:client peer:pair[1]];
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:440 height:956]);
    [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
    uint8_t bytes[196]; XCTAssertEqual(recv(pair[1],bytes,196,MSG_WAITALL),196);
    [session setValue:@(NSProcessInfo.processInfo.systemUptime-12.3) forKey:@"desktopResizeStarted"];
    XCTAssertTrue([session processDesktopSizeChange:client]); XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@1);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeTimedOut"],@0);
    [self deliverLayout:self.fixture[@"layoutCases"][3] session:session client:client peer:pair[1]];
    XCTAssertFalse(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"probeAccepted"],@0);
    XCTestExpectation *fresh=[self expectationWithDescription:@"late-in-budget virtual frame"];
    session.frameHandler=^(UIImage *image){[fresh fulfill];};
    [session updatedX:0 y:0 width:1200 height:2600]; [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:2];
    XCTAssertTrue(session.connected); XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@2);
    session.frameHandler=nil; [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testLateVirtualResultIsBoundedAndInterruptionPermanentlyCancelsItsWindow {
    for (NSString *condition in @[@"within",@"expired",@"interrupted"]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=1600; client->height=1600;
        [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        [self deliverLayout:self.fixture[@"layoutCases"][0] session:session client:client peer:pair[1]];
        for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
        XCTAssertTrue([session requestDesktopSizeWidth:440 height:956]);
        [session setValue:@NO forKey:@"releaseInputRequested"]; XCTAssertTrue([session processDesktopSizeChange:client]);
        uint8_t bytes[196]; XCTAssertEqual(recv(pair[1],bytes,196,MSG_WAITALL),196);
        [session setValue:@(NSProcessInfo.processInfo.systemUptime-([condition isEqualToString:@"expired"]?31:21)) forKey:@"desktopResizeStarted"];
        XCTAssertTrue([session processDesktopSizeChange:client]); XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@3);
        if ([condition isEqualToString:@"interrupted"]) { [session suspendInputForInterruption]; [session resumeInputAfterInterruption]; }
        [self deliverLayout:self.fixture[@"layoutCases"][3] session:session client:client peer:pair[1]];
        if ([condition isEqualToString:@"within"]) {
            XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@1); XCTAssertFalse(session.connected);
            XCTestExpectation *fresh=[self expectationWithDescription:@"reconciled late exact frame"];
            session.frameHandler=^(UIImage *image){[fresh fulfill];};
            [session updatedX:0 y:0 width:1200 height:2600]; [session publishFrame:client]; [self waitForExpectations:@[fresh] timeout:2];
            XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@2); XCTAssertTrue(session.connected);
        } else { XCTAssertEqualObjects(session.diagnosticCounters[@"probeOutcome"],@3); }
        session.frameHandler=nil; [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testFailureDetachesIntentionalStopCallbacksAndRetryKeepsTargetAndTransientLogin {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
    [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin]; [login authenticated];
    [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"];
    [viewer setValue:@0 forKey:@"modeTargetPreset"]; [viewer setValue:@2 forKey:@"modePreviousPreset"];
    [viewer prepareConnection]; CompanionVNCSession *owner=viewer.session;
    void (^queued)(NSString *,NSDictionary *)=owner.stateHandler;
    [viewer showConnectionFailureStage:116]; NSString *failure=[viewer valueForKey:@"loginIssueDetails"];
    queued(@"Disconnected",@{@"failureStage":@0});
    XCTAssertEqualObjects([viewer valueForKey:@"loginIssueDetails"],failure); XCTAssertNil(owner.stateHandler);
    XCTAssertEqualObjects([viewer valueForKey:@"lastConnectionFailure"][@"displayModeFailureStage"],@116);
    __block NSUInteger connects=0;
    viewer.connectHandler=^(NSString *user,NSString *password,BOOL remember){
        connects++; XCTAssertEqualObjects(user,@"synthetic"); XCTAssertEqualObjects(password,@"transient"); XCTAssertFalse(remember);
    };
    UIButton *retry=[viewer valueForKey:@"connect"]; XCTAssertTrue(retry.enabled);
    XCTAssertEqualObjects([retry titleForState:UIControlStateNormal],@"Reconnect");
    [viewer connectionAction]; XCTAssertEqual(connects,1); XCTAssertEqual(viewer.mirrorRetirementDelay,16);
    XCTAssertEqualObjects([viewer valueForKey:@"lastConnectionFailure"][@"displayModeFailureStage"],@116);
    viewer.connectHandler=nil; [viewer stopViewer]; XCTAssertNil([login loginForResume]);
}

- (void)testFailedDisplayModeRetryPreservesTargetAndTransientLogin {
    for (NSDictionary *failure in @[@{@"target":@0,@"stage":@116}, @{@"target":@0,@"stage":@118},
                                    @{@"target":@2,@"stage":@117}, @{@"target":@2,@"stage":@118}]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        DesktopSizeSession *session=[DesktopSizeSession new]; session.usable=YES; session.available=YES;
        viewer.session=session;
        id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
        [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin]; [login authenticated];
        UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8,8)] imageWithActions:^(UIGraphicsImageRendererContext *context){
            [UIColor.blackColor setFill]; UIRectFill(CGRectMake(0,0,8,8));
        }];
        [viewer setValue:image forKey:@"lastFramebuffer"];
        NSDictionary *inputAction=[viewer displayMenuSections].lastObject[@"items"][0];
        XCTAssertEqualObjects(inputAction[@"kind"],@"inputOnly"); XCTAssertFalse([inputAction[@"disabled"] boolValue]);
        NSInteger target=[failure[@"target"] integerValue];
        viewer.restoredDesktopSizePreset=target == 0 ? 2 : 0;
        [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"];
        [viewer setValue:@(target) forKey:@"modeTargetPreset"];
        [viewer setValue:@(viewer.restoredDesktopSizePreset) forKey:@"modePreviousPreset"];
        [viewer showConnectionFailureStage:[failure[@"stage"] integerValue]];
        XCTAssertEqualObjects([viewer valueForKey:@"failedDisplayModePreset"],@(target));
        XCTAssertFalse(((UIView *)[viewer valueForKey:@"controls"]).hidden, @"Recovery over a cached frame keeps the controls menu reachable");
        NSDictionary *action=[viewer displayMenuSections].lastObject[@"items"][0];
        XCTAssertFalse([action[@"disabled"] boolValue], @"Input-only is an independent escape, while Reconnect still retries the display target");
        XCTAssertNotNil([login loginForResume]);
        XCTAssertEqualObjects(((UITextField *)[viewer valueForKey:@"username"]).text,@"");
        XCTAssertEqualObjects(((UITextField *)[viewer valueForKey:@"password"]).text,@"");
        __block NSUInteger connects=0;
        viewer.connectHandler=^(NSString *user,NSString *password,BOOL remember){
            connects++; XCTAssertEqualObjects(user,@"synthetic"); XCTAssertEqualObjects(password,@"transient"); XCTAssertFalse(remember);
        };
        viewer.session=[CompanionVNCSession new]; // The failed transport is no longer running.
        [viewer connectionAction];
        XCTAssertEqual(connects,1); XCTAssertEqual(viewer.restoredDesktopSizePreset,target);
        XCTAssertEqualObjects([viewer valueForKey:@"modeTargetPreset"],@(target));
        viewer.connectHandler=nil; [viewer stopViewer]; XCTAssertNil([login loginForResume]);
    }
}

- (void)testFailedDisplayRecoveryOpensIndependentInputOnlyBeforeOrAfterPixels {
    for (NSNumber *target in @[@0,@2]) for (NSNumber *hadFrame in @[@NO,@YES]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
        [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin]; [login authenticated];
        if (hadFrame.boolValue) {
            UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8,8)] imageWithActions:^(UIGraphicsImageRendererContext *context){
                [UIColor.blackColor setFill]; UIRectFill(CGRectMake(0,0,8,8));
            }];
            [viewer setValue:image forKey:@"lastFramebuffer"];
        }
        [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"];
        [viewer setValue:target forKey:@"modeTargetPreset"]; [viewer setValue:@1 forKey:@"modePreviousPreset"];
        [viewer showConnectionFailureStage:target.intValue == 0 ? 116 : 117];
        CompanionVNCSession *old=viewer.session;
        void (^fallback)(void)=[viewer valueForKey:@"recoveryInputOnlyAction"]; XCTAssertNotNil(fallback);
        __block NSUInteger connects=0,disconnects=0,saves=0;
        viewer.disconnectHandler=^{ disconnects++; };
        viewer.desktopSizeSelectionHandler=^(NSInteger preset){ saves++; };
        __weak CompanionVNCViewer *weakViewer=viewer;
        viewer.connectHandler=^(NSString *user,NSString *password,BOOL remember){
            connects++; XCTAssertEqualObjects(user,@"synthetic"); XCTAssertEqualObjects(password,@"transient"); XCTAssertFalse(remember);
            [weakViewer prepareConnection];
        };
        fallback();
        XCTAssertTrue(viewer.inputOnly); XCTAssertTrue(viewer.session.inputOnly); XCTAssertNotEqual(viewer.session,old);
        XCTAssertEqual(connects,1); XCTAssertEqual(disconnects,1); XCTAssertEqual(saves,0);
        XCTAssertEqual(viewer.restoredDesktopSizePreset,1); XCTAssertEqual(viewer.mirrorRetirementDelay,0);
        XCTAssertNil(old.stateHandler); XCTAssertNil(old.frameHandler); XCTAssertNil(old.displayLayoutHandler);
        XCTAssertNil([viewer valueForKey:@"failedDisplayModePreset"]); XCTAssertNil([viewer valueForKey:@"lastFramebuffer"]);
        for (NSString *key in @[@"changingDisplayMode",@"restoreViewportPending",@"checkingResume",@"awaitingReplacementLayout"]) XCTAssertFalse([[viewer valueForKey:key] boolValue]);
        fallback(); XCTAssertEqual(connects,1, @"The retired recovery card cannot restart the replacement");
        rfbClient *client=rfbGetClient(8,3,4); client->width=2; client->height=2;
        [viewer.session configureClient:client]; XCTAssertTrue([viewer.session allocate:client]);
        for (NSString *key in @[@"running",@"established",@"inputReady"]) [viewer.session setValue:@YES forKey:key];
        viewer.session.stateHandler(@"Connected",viewer.session.diagnosticCounters);
        XCTAssertTrue(((UIView *)[viewer valueForKey:@"login"]).hidden);
        XCTAssertFalse([[viewer valueForKey:@"starting"] boolValue]);
        XCTAssertTrue(CGRectEqualToRect([[viewer valueForKey:@"activeCrop"] CGRectValue],CGRectMake(0,0,2,2)));
        CGPoint point; DesktopMenuPan *pan=[DesktopMenuPan new]; pan.sampleState=UIGestureRecognizerStateBegan;
        XCTAssertTrue([viewer pointerForGesture:pan point:&point]); XCTAssertTrue(isfinite(point.x) && isfinite(point.y));
        XCTAssertTrue([viewer.session tryClickX:1 y:1 mask:1]);
        XCTAssertEqualObjects(viewer.session.diagnosticCounters[@"presentedFrames"],@0);
        XCTAssertEqualObjects(viewer.session.diagnosticCounters[@"probeRequests"],@0);
        [viewer.session setValue:@NO forKey:@"running"]; viewer.connectHandler=nil; viewer.disconnectHandler=nil;
        [viewer stopViewer]; rfbClientCleanup(client);
    }
}
- (void)testStaleOrInactiveInputOnlyRecoveryCannotReplaceAnotherConnection {
    for (NSString *boundary in @[@"replacement",@"inactive",@"exit"]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
        [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin]; [login authenticated];
        [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@2 forKey:@"modeTargetPreset"];
        [viewer showConnectionFailureStage:117];
        void (^fallback)(void)=[viewer valueForKey:@"recoveryInputOnlyAction"]; XCTAssertNotNil(fallback);
        __block NSUInteger connects=0; viewer.connectHandler=^(NSString *u,NSString *p,BOOL remember){ connects++; };
        if ([boundary isEqualToString:@"replacement"]) [viewer prepareConnection];
        else if ([boundary isEqualToString:@"inactive"]) [viewer becameInactive];
        else [viewer stopViewer];
        fallback(); XCTAssertEqual(connects,0); XCTAssertFalse(viewer.inputOnly);
        viewer.connectHandler=nil; [viewer stopViewer];
    }
}
- (void)testInputOnlyRecoveryConfirmsActiveFilesAndRejectsStaleConfirmation {
    for (NSString *boundary in @[@"accept",@"cancel",@"replacement",@"inactive",@"exit"]) {
        DesktopSizeSession *old=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:old];
        [viewer setValue:@5 forKey:@"pendingStreamDisplayID"];
        __block NSUInteger retires=0; viewer.disconnectHandler=^{retires++;};
        viewer.filesTransferActiveHandler=^{return YES;};
        viewer.inputOnly=YES; // Never retire a borrowed transfer before confirmation.
        XCTAssertFalse(viewer.inputOnly); XCTAssertEqual(retires,0); XCTAssertFalse(viewer.requestedResume);
        [viewer cancelDisplayModeConfirmation];
        UIAlertController *alert=[viewer inputOnlyConfirmation]; XCTAssertNotNil(alert);
        XCTAssertEqualObjects(alert.message,@"File transfers using this connection will stop.");
        XCTAssertEqualObjects([alert.actions valueForKey:@"title"],(@[@"Cancel",@"Continue"]));
        if ([boundary isEqualToString:@"cancel"]) [viewer cancelDisplayModeConfirmation];
        else if ([boundary isEqualToString:@"replacement"]) [viewer prepareConnection];
        else if ([boundary isEqualToString:@"inactive"]) [viewer becameInactive];
        else if ([boundary isEqualToString:@"exit"]) [viewer stopViewer];
        NSUInteger before=retires;
        XCTAssertEqual([viewer acceptDisplayModeConfirmation],[boundary isEqualToString:@"accept"]);
        XCTAssertFalse([viewer acceptDisplayModeConfirmation]);
        XCTAssertEqual(viewer.inputOnly,[boundary isEqualToString:@"accept"]);
        XCTAssertEqual(retires-before,[boundary isEqualToString:@"accept"] ? 1 : 0);
        if ([boundary isEqualToString:@"accept"]) { XCTAssertTrue(viewer.requestedResume); XCTAssertNil([viewer valueForKey:@"pendingStreamDisplayID"]); }
        viewer.disconnectHandler=nil; viewer.filesTransferActiveHandler=nil; [viewer stopViewer];
    }
}
- (void)testPendingDisplayProgressKeepsOneActionAndFailureOffersIndependentInputOnly {
    XCTAssertFalse([self.fixture[@"displayModeHandoffPolicy"][@"pendingNoFrameInputOnlyAction"] boolValue]);
    for (NSNumber *hadInitialFrame in @[@NO,@YES]) {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
    [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin];
    [viewer setValue:@YES forKey:@"starting"]; [viewer setValue:@YES forKey:@"changingDisplayMode"];
    [viewer setValue:@2 forKey:@"modeTargetPreset"]; [viewer setValue:@0 forKey:@"modePreviousPreset"];
    if (hadInitialFrame.boolValue) {
        UIImage *image=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(8,8)] imageWithActions:^(UIGraphicsImageRendererContext *context){ [UIColor.blueColor setFill]; UIRectFill(CGRectMake(0,0,8,8)); }];
        [viewer frame:image];
    }
    [viewer updateConnectionChrome];
    XCTAssertEqual([viewer valueForKey:@"lastFramebuffer"] != nil,hadInitialFrame.boolValue);
    XCTAssertFalse(((UIView *)[viewer valueForKey:@"loginScroll"]).hidden);
    XCTAssertTrue(((UIView *)[viewer valueForKey:@"controls"]).hidden);
    NSMutableArray<UIView *> *views=[NSMutableArray arrayWithObject:viewer.view]; UIButton *action=nil;
    for (NSUInteger i=0;i<views.count;i++) {
        UIView *view=views[i]; [views addObjectsFromArray:view.subviews];
        if ([view.accessibilityIdentifier isEqualToString:@"connection-inputOnly"] && [view isKindOfClass:UIButton.class]) action=(UIButton *)view;
    }
    XCTAssertNotNil(action); if (!action) { [viewer stopViewer]; return; }
    XCTAssertTrue(action.hidden);
    [viewer showConnectionFailureStage:117]; // Only a display failure offers video-free recovery.
    void (^fallback)(void)=[viewer valueForKey:@"recoveryInputOnlyAction"]; XCTAssertNotNil(fallback);
    if (!fallback) { [viewer stopViewer]; return; }
    CompanionVNCSession *old=viewer.session; __block NSUInteger connects=0,retires=0,saves=0;
    __weak CompanionVNCViewer *weak=viewer;
    viewer.connectHandler=^(NSString *u,NSString *p,BOOL remember){ connects++; XCTAssertEqualObjects(u,@"synthetic"); XCTAssertEqualObjects(p,@"transient"); XCTAssertFalse(remember); [weak prepareConnection]; };
    viewer.disconnectHandler=^{retires++;}; viewer.desktopSizeSelectionHandler=^(NSInteger preset){saves++;};
    fallback();
    XCTAssertEqual(connects,1); XCTAssertEqual(retires,1); XCTAssertEqual(saves,0);
    XCTAssertNotEqual(viewer.session,old); XCTAssertTrue(viewer.session.inputOnly); XCTAssertTrue(viewer.inputOnly);
    XCTAssertNil(old.stateHandler); XCTAssertNil(old.frameHandler); XCTAssertNil(old.displayLayoutHandler);
    XCTAssertNil([viewer valueForKey:@"failedDisplayModePreset"]); XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]);
    XCTAssertEqual(viewer.restoredDesktopSizePreset,0); XCTAssertTrue(action.hidden);
    viewer.connectHandler=nil; viewer.disconnectHandler=nil; [viewer stopViewer];
    }
}
- (void)testInputOnlyRecoveryWithoutSessionCredentialsShowsItsOwnLogin {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@2 forKey:@"modeTargetPreset"];
    [viewer showConnectionFailureStage:118]; // No retained login; input-only must show its own fields.
    __block NSUInteger connects=0; viewer.connectHandler=^(NSString *u,NSString *p,BOOL remember){ connects++; };
    void (^fallback)(void)=[viewer valueForKey:@"recoveryInputOnlyAction"]; XCTAssertNotNil(fallback);
    if (!fallback) { [viewer stopViewer]; return; }
    fallback();
    XCTAssertEqual(connects,0); XCTAssertTrue(viewer.inputOnly); XCTAssertNil([viewer valueForKey:@"failedDisplayModePreset"]);
    XCTAssertFalse(((UIView *)[viewer valueForKey:@"login"]).hidden); XCTAssertNil([viewer valueForKey:@"recoveryInputOnlyAction"]);
    XCTAssertEqualObjects(((UITextField *)[viewer valueForKey:@"username"]).text,@"");
    XCTAssertEqualObjects(((UITextField *)[viewer valueForKey:@"password"]).text,@"");
    viewer.connectHandler=nil; [viewer stopViewer];
}

- (void)testNonDisplayFailuresDoNotOfferInputOnlyAsAnAuthenticationBypass {
    for (NSNumber *stage in @[@0,@111,@112,@113,@114,@115]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@2 forKey:@"modeTargetPreset"];
        [viewer showConnectionFailureStage:stage.integerValue];
        XCTAssertNil([viewer valueForKey:@"recoveryInputOnlyAction"],@"stage %@",stage);
        XCTAssertFalse(viewer.inputOnly); [viewer stopViewer];
    }
}

- (void)testDisplayRecoveryDoesNotPermanentlyDisableInputOnly {
    for (NSNumber *target in @[@0,@2]) for (NSNumber *exit in @[@NO,@YES]) {
        DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
        [viewer setValue:target forKey:@"failedDisplayModePreset"];
        XCTAssertFalse([[viewer displayMenuSections].lastObject[@"items"][0][@"disabled"] boolValue]);
        if (exit.boolValue) {
            __block NSUInteger exits=0; viewer.macsHandler=^{ exits++; };
            [viewer performControlAction:@{@"kind":@"exit"}]; XCTAssertEqual(exits,1);
        } else {
            [viewer setValue:target forKey:@"modeTargetPreset"];
            [viewer completeDisplayModeVerified:YES];
        }
        XCTAssertNil([viewer valueForKey:@"failedDisplayModePreset"]);
        if (!exit.boolValue) XCTAssertFalse([[viewer displayMenuSections].lastObject[@"items"][0][@"disabled"] boolValue]);
        viewer.inputOnly=YES; XCTAssertTrue(viewer.inputOnly);
        viewer.macsHandler=nil; [viewer stopViewer];
    }
}

- (void)testModeVerificationDeadlineCannotCrossInterruptionOrOwnerReplacement {
    DesktopSizeSession *old=[DesktopSizeSession new]; old.snapshot=@{@"layoutVirtual":@NO,@"layoutCount":@0};
    DesktopSizeViewer *viewer=[self mirrorViewerWithSession:old attempt:1];
    [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"];
    [viewer updateDisplayModeRestoration]; NSUInteger interrupted=[[viewer valueForKey:@"modeVerificationGeneration"] unsignedIntegerValue];
    XCTAssertTrue([[viewer valueForKey:@"modeVerificationTimed"] boolValue]);
    [viewer becameInactive]; XCTAssertFalse([[viewer valueForKey:@"modeVerificationTimed"] boolValue]);
    [viewer foregrounded]; NSUInteger resumed=[[viewer valueForKey:@"modeVerificationGeneration"] unsignedIntegerValue];
    XCTAssertGreaterThan(resumed,interrupted); XCTAssertTrue([[viewer valueForKey:@"modeVerificationTimed"] boolValue]);
    [viewer expireDisplayModeVerification:old generation:interrupted]; XCTAssertTrue([[viewer valueForKey:@"changingDisplayMode"] boolValue]);
    [viewer prepareConnection];
    DesktopSizeSession *fresh=[DesktopSizeSession new]; fresh.usable=YES; fresh.snapshot=old.snapshot; viewer.session=fresh;
    [viewer updateDisplayModeRestoration]; NSUInteger current=[[viewer valueForKey:@"modeVerificationGeneration"] unsignedIntegerValue];
    [viewer expireDisplayModeVerification:old generation:resumed]; XCTAssertNil([viewer valueForKey:@"failedDisplayModePreset"]);
    [viewer expireDisplayModeVerification:fresh generation:current];
    XCTAssertEqualObjects([viewer valueForKey:@"lastConnectionFailure"][@"displayModeFailureStage"],@118);
    XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]); [viewer stopViewer];
}

- (void)testInitialAppleImageWaitsForMetadataBeforeApplyingEitherSavedMode {
    for (NSNumber *target in @[@0,@2]) {
        DesktopSizeSession *session=[DesktopSizeSession new];
        session.snapshot=@{@"appleDisplayProtocol":@YES,@"layoutVirtual":@NO,@"layoutCount":@0};
        DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1];
        [viewer setValue:target forKey:@"modeTargetPreset"]; viewer.restoredDesktopSizePreset=target.integerValue;
        __block NSUInteger saves=0; viewer.desktopSizeSelectionHandler=^(NSInteger p){saves++;};
        [viewer updateDisplayModeRestoration];
        XCTAssertTrue([[viewer valueForKey:@"changingDisplayMode"] boolValue]);
        XCTAssertTrue(session.displayHandoffInputBlocked); XCTAssertEqual(saves,0);
        session.snapshot=self.acceptedSnapshot;
        [viewer updateDisplayModeRestoration];
        if (target.integerValue) {
            XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]); XCTAssertEqual(saves,1);
        } else {
            XCTAssertTrue([[viewer valueForKey:@"mirrorRestartScheduled"] boolValue]);
            XCTestExpectation *next=[self expectationWithDescription:@"late metadata starts bounded Mirror recovery"];
            dispatch_async(dispatch_get_main_queue(),^{[next fulfill];}); [self waitForExpectations:@[next] timeout:2];
            XCTAssertTrue(viewer.requestedResume); XCTAssertEqual(viewer.mirrorRetirementDelay,16); XCTAssertEqual(saves,0);
        }
        [viewer stopViewer];
    }
}
- (void)testNonAppleLegacyImageCanFinishWithoutDisplayMetadataOrSavingMode {
    DesktopSizeSession *session=[DesktopSizeSession new];
    session.snapshot=@{@"appleDisplayProtocol":@NO,@"layoutVirtual":@NO,@"layoutCount":@0};
    DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1];
    __block NSUInteger saves=0; viewer.desktopSizeSelectionHandler=^(NSInteger p){saves++;};
    [viewer updateDisplayModeRestoration];
    XCTAssertFalse([[viewer valueForKey:@"changingDisplayMode"] boolValue]);
    XCTAssertFalse(session.displayHandoffInputBlocked); XCTAssertEqual(saves,0); [viewer stopViewer];
}
- (void)testAuthenticatedAppleProtocolIsKnownBeforeItsFirstDisplayLayout {
    CompanionVNCSession *session=[CompanionVNCSession new]; [session setValue:@YES forKey:@"appleGestureServer"];
    XCTAssertEqualObjects(session.diagnosticCounters[@"appleDisplayProtocol"],@YES);
    XCTAssertEqualObjects(session.diagnosticCounters[@"layoutCount"],@0); [session stop];
}
- (void)testMirrorRequiresMatchingFreshFramebufferGeometryBeforeSavingOrOpeningInput {
    DesktopSizeSession *session=[DesktopSizeSession new];
    session.snapshot=@{@"layoutVirtual":@NO,@"layoutCount":@2,@"layoutWidth":@3200,@"layoutHeight":@1200,
        @"framebufferWidth":@1600,@"framebufferHeight":@1200};
    DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1]; [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"];
    __block NSUInteger saves=0; viewer.desktopSizeSelectionHandler=^(NSInteger p){saves++;};
    [viewer updateDisplayModeRestoration];
    XCTAssertTrue([[viewer valueForKey:@"changingDisplayMode"] boolValue]); XCTAssertTrue(session.displayHandoffInputBlocked); XCTAssertEqual(saves,0);
    session.snapshot=@{@"layoutVirtual":@NO,@"layoutCount":@2,@"layoutWidth":@3200,@"layoutHeight":@1200,
        @"framebufferWidth":@3200,@"framebufferHeight":@1200};
    session.usable=NO; [viewer updateDisplayModeRestoration]; XCTAssertEqual(saves,0);
    session.usable=YES; [viewer updateDisplayModeRestoration]; XCTAssertEqual(saves,1); XCTAssertFalse(session.displayHandoffInputBlocked);
    [viewer stopViewer];
}
- (void)testSavedMirrorMonitorIsRequestedImmediatelyWhenInitialHandoffGateOpens {
    DesktopSizeSession *session=[DesktopSizeSession new];
    NSArray *views=@[@{@"id":@5,@"x":@0,@"y":@0,@"width":@0.5,@"height":@1},@{@"id":@9,@"x":@0.5,@"y":@0,@"width":@0.5,@"height":@1}];
    session.catalogue=@{@"views":views};
    session.snapshot=@{@"layoutVirtual":@NO,@"layoutCount":@2,@"layoutWidth":@3200,@"layoutHeight":@1200,
        @"framebufferWidth":@3200,@"framebufferHeight":@1200};
    DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1]; viewer.restoredDisplayID=@5;
    [viewer setValue:views forKey:@"displayViews"]; [viewer setValue:@(3200.0/1200) forKey:@"displayAspect"];
    [viewer setValue:[NSValue valueWithCGSize:CGSizeMake(3200,1200)] forKey:@"framebufferSize"];
    session.available=NO; [viewer restoreSavedDisplay]; XCTAssertNil(session.requestedDisplay);
    session.available=YES; [viewer updateDisplayModeRestoration];
    XCTAssertEqualObjects(session.requestedDisplay,@5, @"No second framebuffer/layout callback is required to apply the saved monitor");
    [viewer stopViewer];
}
- (void)testSavedMirrorMonitorRestoresAsSoonAsResumeReadinessClears {
    DesktopSizeSession *session=[DesktopSizeSession new];
    DesktopSizeViewer *viewer=[self mirrorViewerWithSession:session attempt:1];
    NSArray *views=@[@{@"id":@5,@"x":@0,@"y":@0,@"width":@0.5,@"height":@1},@{@"id":@9,@"x":@0.5,@"y":@0,@"width":@0.5,@"height":@1}];
    session.catalogue=@{@"views":views}; session.snapshot=self.physicalSnapshot; viewer.restoredDisplayID=@5;
    [viewer setValue:views forKey:@"displayViews"]; [viewer setValue:@(3200.0/1200) forKey:@"displayAspect"];
    [viewer setValue:[NSValue valueWithCGSize:CGSizeMake(3200,1200)] forKey:@"framebufferSize"];
    [viewer setValue:@YES forKey:@"checkingResume"];
    [viewer updateDisplayModeRestoration]; XCTAssertNil(session.requestedDisplay);
    [viewer completeResumeReadiness];
    XCTAssertEqualObjects(session.requestedDisplay,@5, @"Resume readiness retries the saved monitor without another frame or layout callback");
    [viewer stopViewer];
}
- (void)testModeRestartTransportFailuresRetainUnrememberedLoginForExplicitRetry {
    for (NSNumber *stage in @[@110,@114]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
        [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin]; [login authenticated];
        [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"];
        [viewer setValue:@0 forKey:@"modeTargetPreset"]; [viewer setValue:@2 forKey:@"modePreviousPreset"];
        [viewer prepareConnection]; [viewer showConnectionFailureStage:stage.integerValue];
        XCTAssertNotNil([login loginForResume]);
        XCTAssertEqualObjects(((UITextField *)[viewer valueForKey:@"username"]).text,@"");
        XCTAssertEqualObjects(((UITextField *)[viewer valueForKey:@"password"]).text,@"");
        __block NSUInteger connects=0;
        viewer.connectHandler=^(NSString *user,NSString *password,BOOL remember){
            connects++; XCTAssertEqualObjects(user,@"synthetic"); XCTAssertEqualObjects(password,@"transient"); XCTAssertFalse(remember);
        };
        [viewer connectionAction]; XCTAssertEqual(connects,1); XCTAssertEqual(viewer.restoredDesktopSizePreset,0);
        viewer.connectHandler=nil; [viewer stopViewer]; XCTAssertNil([login loginForResume]);
    }
}
- (void)testModeRestartCredentialTrustAndCancellationFailuresRetirePrivateRecovery {
    for (NSNumber *stage in @[@2,@7,@8,@111,@112,@113,@115]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
        [login editWithUsername:@"synthetic" password:@"transient" remember:NO]; [login beginLogin]; [login authenticated];
        [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@YES forKey:@"mirrorFullRestartUsed"];
        [viewer setValue:@0 forKey:@"modeTargetPreset"]; [viewer prepareConnection];
        [viewer showConnectionFailureStage:stage.integerValue]; XCTAssertNil([login loginForResume]);
        XCTAssertEqualObjects(((UITextField *)[viewer valueForKey:@"password"]).text,@"");
        [viewer stopViewer];
    }
}
- (void)testDeliberateFormEditReplacesPrivateLoginBeforeModeRetry {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    id<DesktopLoginRecoveryTesting> login=[viewer valueForKey:@"credentialState"];
    [login editWithUsername:@"original" password:@"original-only" remember:NO]; [login beginLogin];
    [viewer setValue:@YES forKey:@"changingDisplayMode"]; [viewer setValue:@2 forKey:@"modeTargetPreset"];
    [viewer prepareConnection]; [viewer showConnectionFailureStage:117]; XCTAssertNotNil([login loginForResume]);
    ((UITextField *)[viewer valueForKey:@"username"]).text=@"replacement";
    ((UITextField *)[viewer valueForKey:@"password"]).text=@"replacement-only";
    [viewer loginEdited]; XCTAssertNil([login loginForResume]);
    __block NSUInteger connects=0;
    viewer.connectHandler=^(NSString *user,NSString *password,BOOL remember){
        connects++; XCTAssertEqualObjects(user,@"replacement"); XCTAssertEqualObjects(password,@"replacement-only"); XCTAssertFalse(remember);
    };
    [viewer connectionAction]; XCTAssertEqual(connects,1); viewer.connectHandler=nil; [viewer stopViewer];
}
- (void)testLateExactVirtualFrameReconcilesBothTimeoutOutcomesOnlyAfterFreshPixels {
    for (NSNumber *outcome in @[@3,@4]) {
        DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
        session.snapshot=@{@"layoutVirtual":@YES,@"layoutCount":@1,@"layoutWidth":@2048,@"layoutHeight":@1280,
            @"framebufferWidth":@2048,@"framebufferHeight":@1280};
        __block NSInteger saved=-1; viewer.desktopSizeSelectionHandler=^(NSInteger p){saved=p;};
        XCTAssertTrue([viewer applyDesktopSizePreset:2]);
        NSMutableDictionary *timeout=[session.snapshot mutableCopy]; timeout[@"probeOutcome"]=outcome; session.snapshot=timeout;
        [viewer updateDesktopSizeState]; XCTAssertEqualObjects([viewer valueForKey:@"lateDesktopSizePreset"],@2); XCTAssertEqual(saved,-1);
        session.snapshot=self.acceptedSnapshot; session.usable=NO; [viewer updateDesktopSizeState]; XCTAssertEqual(saved,-1);
        session.usable=YES; [viewer updateDesktopSizeState]; XCTAssertEqual(saved,2);
        XCTAssertEqualObjects([viewer valueForKey:@"lateDesktopSizePreset"],@0); [viewer stopViewer];
    }
}
- (void)testInterruptionCannotPersistQueuedDisplayChoiceOrLateSizeResult {
    for (NSNumber *background in @[@NO,@YES]) for (NSNumber *physical in @[@NO,@YES]) {
        DesktopSizeSession *session=[DesktopSizeSession new]; DesktopSizeViewer *viewer=[self viewerWithSession:session];
        session.snapshot=self.acceptedSnapshot;
        if (physical.boolValue) [viewer setValue:@5 forKey:@"pendingStreamDisplayID"];
        else [viewer setValue:@2 forKey:@"pendingDesktopSizePreset"];
        [viewer setValue:@2 forKey:@"lateDesktopSizePreset"];
        __block NSUInteger saves=0; viewer.desktopSizeSelectionHandler=^(NSInteger p){saves++;}; viewer.displaySelectionHandler=^(NSNumber *p){saves++;};
        if (background.boolValue) [viewer background]; else [viewer becameInactive];
        [viewer updateDesktopSizeState];
        XCTAssertEqual(saves,0); XCTAssertEqualObjects([viewer valueForKey:@"pendingDesktopSizePreset"],@0);
        XCTAssertNil([viewer valueForKey:@"pendingStreamDisplayID"]); XCTAssertEqualObjects([viewer valueForKey:@"lateDesktopSizePreset"],@0);
        [viewer stopViewer];
    }
}

@end
