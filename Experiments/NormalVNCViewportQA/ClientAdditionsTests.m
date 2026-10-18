#import <XCTest/XCTest.h>
#import "CompanionVNCViewer.h"
#import "CompanionVNCTapGesture.h"
#import "CompanionVNCFramebufferBounds.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <arpa/inet.h>
#import <unistd.h>
@interface CompanionVNCTapGesture (Testing)
- (void)touchesBegan:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesMoved:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesEnded:(NSSet *)touches withEvent:(UIEvent *)event;
- (void)touchesCancelled:(NSSet *)touches withEvent:(UIEvent *)event;
@end
@interface SyntheticTouch : UITouch
@property CGPoint point;
@property NSTimeInterval sampleTime;
@end
@implementation SyntheticTouch
- (CGPoint)locationInView:(UIView *)view { return self.point; }
- (NSTimeInterval)timestamp { return self.sampleTime; }
@end
@interface SyntheticEvent : UIEvent
@property NSSet *sampleTouches;
@end
@implementation SyntheticEvent
- (NSSet *)allTouches { return self.sampleTouches; }
@end
@interface CompanionVNCSession (AdditionsTesting)
- (void)configureClient:(rfbClient *)client;
- (BOOL)allocate:(rfbClient *)client;
- (BOOL)resetBaseline:(rfbClient *)client;
- (BOOL)handleServerMessage:(rfbClient *)client;
- (BOOL)registerSocket:(int)socket;
- (void)processConnectedClient:(rfbClient *)client;
@end
@interface CompanionVNCViewer (AdditionsTesting)
- (void)frame:(UIImage *)image;
- (void)updateConnectionChrome;
- (void)performControlAction:(NSDictionary *)action;
@end
@interface ClientAdditionsTests : XCTestCase
@end
@implementation ClientAdditionsTests
- (void)testShortTapWithDriftRecognizesButMovementAndLongTouchDoNot {
    for (NSArray *sample in @[@[@12, @.15, @YES], @[@19, @.15, @NO], @[@0, @.4, @NO]]) {
        CompanionVNCTapGesture *tap = [CompanionVNCTapGesture new]; UIView *view = [UIView new]; [view addGestureRecognizer:tap];
        SyntheticTouch *touch = [SyntheticTouch new]; touch.point = CGPointMake(10,10); touch.sampleTime = 1;
        SyntheticEvent *event = [SyntheticEvent new]; event.sampleTouches = [NSSet setWithObject:touch];
        [tap touchesBegan:event.sampleTouches withEvent:event];
        touch.point = CGPointMake(10+[sample[0] doubleValue],10); touch.sampleTime += [sample[1] doubleValue];
        [tap touchesMoved:event.sampleTouches withEvent:event];
        if (tap.state == UIGestureRecognizerStatePossible) [tap touchesEnded:event.sampleTouches withEvent:event];
        XCTAssertEqual(tap.state == UIGestureRecognizerStateRecognized, [sample[2] boolValue]);
    }
}
- (void)testCancelledTouchCannotBecomeClick {
    CompanionVNCTapGesture *tap = [CompanionVNCTapGesture new]; UIView *view = [UIView new]; [view addGestureRecognizer:tap];
    SyntheticTouch *touch = [SyntheticTouch new]; touch.point = CGPointMake(10,10); touch.sampleTime = 1;
    SyntheticEvent *event = [SyntheticEvent new]; event.sampleTouches = [NSSet setWithObject:touch];
    [tap touchesBegan:event.sampleTouches withEvent:event]; [tap touchesCancelled:event.sampleTouches withEvent:event];
    XCTAssertNotEqual(tap.state,UIGestureRecognizerStateRecognized); // UIKit may immediately reset a cancelled discrete recognizer.
}
- (void)testAtomicClickAdmissionAndRejectedClickLeaveNoHalfPress {
    CompanionVNCSession *session = [CompanionVNCSession new];
    XCTAssertFalse([session tryClickX:10 y:20 mask:1]);
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    [session setValue:@YES forKey:@"established"];
    NSMutableArray *queue = [session valueForKey:@"events"];
    for (int i=0;i<511;i++) [queue addObject:@{@"key": @97, @"down": @YES}];
    XCTAssertFalse([session tryClickX:10 y:20 mask:1]); XCTAssertEqual(queue.count,511);
    [queue removeAllObjects]; XCTAssertTrue([session tryClickX:10 y:20 mask:1]);
    XCTAssertEqual(queue.count,2); XCTAssertEqualObjects(queue[0][@"mask"],@1); XCTAssertEqualObjects(queue[1][@"mask"],@0);
    [session pauseWithCompletion:nil]; XCTAssertFalse([session tryClickX:10 y:20 mask:1]); XCTAssertEqual(queue.count,0);
    [session stop]; [session setValue:@NO forKey:@"running"];
}
- (void)testFullscreenReclaimsViewportAndInputOnlyKeepsGeometryWithoutReconnect {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
    UIImage *image = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(800,600)] imageWithActions:^(UIGraphicsImageRendererContext *context) { [UIColor.blueColor setFill]; UIRectFill(CGRectMake(0,0,800,600)); }];
    [viewer frame:image]; [[viewer valueForKey:@"login"] setHidden:YES];
    // Measure connected geometry after its native status-area layout settles.
    [viewer updateConnectionChrome]; [viewer.view layoutIfNeeded];
    UIScrollView *canvas = [viewer valueForKey:@"canvas"]; CGFloat before = canvas.bounds.size.height;
    CompanionVNCSession *owner = viewer.session;
    viewer.fullscreen = YES; [viewer.view layoutIfNeeded];
    XCTAssertGreaterThan(canvas.bounds.size.height,before); XCTAssertTrue([[viewer valueForKey:@"toolbar"] isHidden]);
    XCTAssertEqual(viewer.session,owner); XCTAssertFalse([[viewer valueForKey:@"controls"] isHidden]);
    viewer.inputOnly = YES; XCTAssertTrue([[viewer valueForKey:@"image"] isHidden]); XCTAssertTrue([[viewer valueForKey:@"trackpadMode"] boolValue]);
    XCTAssertFalse(CGRectIsEmpty([[viewer valueForKey:@"activeCrop"] CGRectValue]));
    viewer.inputOnly = NO; viewer.fullscreen = NO; [viewer.view layoutIfNeeded];
    XCTAssertFalse([[viewer valueForKey:@"image"] isHidden]); XCTAssertEqualWithAccuracy(canvas.bounds.size.height,before,.1); XCTAssertEqual(viewer.session,owner);
    [viewer stopViewer];
}
- (void)testStandaloneInputOnlyStartsAndResumesWithoutADesktopImage {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; viewer.inputOnly=YES; [viewer loadViewIfNeeded];
    CompanionVNCSession *session=viewer.session; XCTAssertTrue(session.inputOnly);
    rfbClient *client=rfbGetClient(8,3,4); client->width=2; client->height=2;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    for (NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    __block NSUInteger connections=0; viewer.connectedHandler=^{connections++;};
    [viewer setValue:@YES forKey:@"starting"];
    session.stateHandler(@"Connected",session.diagnosticCounters);
    XCTAssertEqual(connections,1); XCTAssertTrue(((UIView *)[viewer valueForKey:@"login"]).hidden);
    XCTAssertFalse([[viewer valueForKey:@"starting"] boolValue]); XCTAssertNil([viewer valueForKey:@"lastFramebuffer"]);
    XCTAssertTrue(CGRectEqualToRect([[viewer valueForKey:@"activeCrop"] CGRectValue],CGRectMake(0,0,2,2)));
    [viewer background]; [viewer foregrounded];
    [session setValue:@YES forKey:@"inputReady"]; session.stateHandler(@"Connected",session.diagnosticCounters);
    XCTAssertFalse([[viewer valueForKey:@"checkingResume"] boolValue]); XCTAssertNil([viewer valueForKey:@"lastFramebuffer"]);
    XCTAssertEqualObjects(session.diagnosticCounters[@"presentedFrames"],@0);
    [session setValue:@NO forKey:@"running"]; [viewer stopViewer]; rfbClientCleanup(client);
}
- (void)testInputOnlyGeometryDoesNotAllocateDesktopStorageAndRetainsLargeDesktopControl {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSArray *cases=profile[@"inputOnlyInitializationCases"]; XCTAssertGreaterThan(cases.count,0);
    for (NSDictionary *sample in cases) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; viewer.inputOnly=YES; [viewer loadViewIfNeeded];
        CompanionVNCSession *session=viewer.session; rfbClient *client=rfbGetClient(8,3,4);
        client->width=[sample[@"width"] intValue]; client->height=[sample[@"height"] intValue]; [session configureClient:client];
        XCTAssertEqual([session allocate:client],[sample[@"inputGeometryValid"] boolValue],@"%@",sample[@"name"]);
        XCTAssertEqual(client->frameBuffer,NULL); XCTAssertEqualObjects(session.diagnosticCounters[@"framebufferAllocations"],@0);
        XCTAssertEqualObjects(session.diagnosticCounters[@"baselineExpectedPixels"],@0);
        if ([sample[@"inputGeometryValid"] boolValue]) {
            for (NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
            session.stateHandler(@"Connected",session.diagnosticCounters);
            XCTAssertTrue(CGRectEqualToRect([[viewer valueForKey:@"activeCrop"] CGRectValue],CGRectMake(0,0,client->width,client->height)));
            XCTAssertTrue([session resetBaseline:client]); XCTAssertEqualObjects(session.diagnosticCounters[@"baselineExpectedPixels"],@0);
            XCTAssertEqual(session.desktopFramebufferAvailable,[sample[@"videoAdmitted"] boolValue]);
            if (!session.desktopFramebufferAvailable) {
                viewer.inputOnly=NO; XCTAssertTrue(viewer.inputOnly); XCTAssertTrue(session.inputOnly); XCTAssertTrue(session.connected);
                session.inputOnly=NO; XCTAssertTrue(session.inputOnly); XCTAssertTrue(session.connected);
                XCTAssertTrue([session tryClickX:client->width-1 y:client->height-1 mask:1]);
                XCTAssertTrue([((UILabel *)[viewer valueForKey:@"status"]).text containsString:@"stays connected"]);
            }
            [session setValue:@NO forKey:@"running"];
        }
        [viewer stopViewer]; rfbClientCleanup(client);
    }
}
- (void)testGeometryOnlyOwnerRejectsEveryBuiltInPixelEncodingBeforeReadingPayload {
    for (NSNumber *encoding in @[@(rfbEncodingRaw),@(rfbEncodingCopyRect),@(rfbEncodingRRE),@(rfbEncodingCoRRE),@(rfbEncodingHextile),@(rfbEncodingUltra),@(rfbEncodingUltraZip),@(rfbEncodingTRLE),@(rfbEncodingZlib),@(rfbEncodingTight),@(rfbEncodingZRLE),@(rfbEncodingZYWRLE)]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        CompanionVNCSession *session=[CompanionVNCSession new]; session.inputOnly=YES;
        rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=2; client->height=2;
        [session configureClient:client]; XCTAssertTrue([session allocate:client]); XCTAssertEqual(client->frameBuffer,NULL);
        uint32_t be=htonl(encoding.unsignedIntValue);
        uint8_t header[]={0,0,0,1,0,0,0,0,0,1,0,1,0,0,0,0}; memcpy(header+12,&be,4);
        // No pixel payload follows: a decoder would block or access missing storage.
        XCTAssertEqual(write(pair[1],header,sizeof(header)),sizeof(header));
        XCTAssertFalse([session handleServerMessage:client]); XCTAssertEqual(client->frameBuffer,NULL);
        XCTAssertEqualObjects(session.diagnosticCounters[@"framebufferAllocations"],@0);
        rfbClientCleanup(client); close(pair[1]);
    }
}
- (void)testInputOnlyCapabilityRefreshCannotRequestDesktopPixels {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    struct timeval timeout={.tv_usec=100000}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new]; session.inputOnly=YES;
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=8192; client->height=8192;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    uint8_t packet[16+sz_rfbSupportedMessages]={0,0,0,1,0,0,0,0,0,64,0,1};
    uint32_t encoding=htonl(rfbEncodingSupportedMessages); memcpy(packet+12,&encoding,4); memset(packet+16,255,sz_rfbSupportedMessages);
    XCTAssertEqual(write(pair[1],packet,sizeof(packet)),sizeof(packet)); XCTAssertTrue([session handleServerMessage:client]);
    // A capability report may re-enable the library's request bit. Its rectangle
    // still has no area, so that response can never solicit a desktop image.
    uint8_t reply[10]; ssize_t count=recv(pair[1],reply,sizeof(reply),0);
    if (count>0) { XCTAssertEqual(count,10); XCTAssertEqual(reply[0],rfbFramebufferUpdateRequest); XCTAssertEqual(reply[6]|reply[7]|reply[8]|reply[9],0); }
    XCTAssertEqual(client->frameBuffer,NULL); XCTAssertEqualObjects(session.diagnosticCounters[@"framebufferAllocations"],@0);
    rfbClientCleanup(client); close(pair[1]);
}
- (void)testGeometryOnlyResizeAndPointerMetadataRemainSafeWithoutRequestingAnImage {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    struct timeval timeout={.tv_usec=100000}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new]; session.inputOnly=YES;
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=256; client->height=128;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    // NewFBSize followed by PointerPos, both metadata-only rectangles.
    uint8_t update[]={0,0,0,2,0,0,0,0,32,0,32,0,255,255,255,33,0,42,0,17,0,0,0,0,255,255,255,24};
    XCTAssertEqual(write(pair[1],update,sizeof(update)),sizeof(update)); XCTAssertTrue([session handleServerMessage:client]);
    XCTAssertEqual(client->width,8192); XCTAssertEqual(client->height,8192); XCTAssertEqual(client->frameBuffer,NULL);
    XCTAssertEqualObjects(session.diagnosticCounters[@"baselineExpectedPixels"],@0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"framebufferAllocations"],@0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"cursorPositionUpdates"],@1);
    uint8_t request[10]; XCTAssertLessThan(recv(pair[1],request,sizeof(request),0),0);
    rfbClientCleanup(client); close(pair[1]);
}
- (void)testActualSocketInputOnlySendsInputWithoutRequestingPixelsThenReturnsToDesktop {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=2; client->height=2; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0] |= (1<<rfbKeyEvent)|(1<<rfbPointerEvent)|(1<<rfbFramebufferUpdateRequest);
    session.inputOnly=YES;
    for (NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    [session registerSocket:pair[0]];
    XCTestExpectation *ended=[self expectationWithDescription:@"Owner ended"]; __weak CompanionVNCSession *weak=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){ if (!weak.running) [ended fulfill]; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ [session processConnectedClient:client]; });
    XCTAssertTrue([session tryClickX:1 y:1 mask:1]); [session key:97 down:YES]; [session key:97 down:NO];
    uint8_t click[12],keys[16]; XCTAssertEqual(recv(pair[1],click,12,MSG_WAITALL),12); XCTAssertEqual(click[1],1); XCTAssertEqual(click[7],0);
    XCTAssertEqual(recv(pair[1],keys,16,MSG_WAITALL),16); XCTAssertEqual(keys[1],1); XCTAssertEqual(keys[9],0);
    timeout=(struct timeval){.tv_usec=100000}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    uint8_t request[10]; XCTAssertLessThan(recv(pair[1],request,10,0),0); XCTAssertTrue(session.connected);
    session.inputOnly=NO; timeout=(struct timeval){.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    uint8_t release[6]; XCTAssertEqual(recv(pair[1],release,6,MSG_WAITALL),6); XCTAssertEqual(release[0],rfbPointerEvent); XCTAssertEqual(release[1],0);
    XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10); XCTAssertEqual(request[0],rfbFramebufferUpdateRequest); XCTAssertEqual(request[1],0);
    [session stop]; [self waitForExpectations:@[ended] timeout:2]; session.stateHandler=nil; close(pair[1]);
}
- (void)testViewerEntersInputOnlyDuringUnavailableBaselineAndReturnsWithFreshPixels {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSDictionary *policy=[profile[@"inputOnlyTransitionCases"] firstObject]; XCTAssertNotNil(policy);
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    CompanionVNCSession *session=viewer.session; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=2; client->height=2; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0]|=(1<<rfbKeyEvent)|(1<<rfbPointerEvent)|(1<<rfbFramebufferUpdateRequest);
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
    [session registerSocket:pair[0]];
    [[session valueForKey:@"heldKeys"] addObject:@97];
    XCTAssertTrue([session resetBaseline:client]); XCTAssertFalse(session.connected); XCTAssertTrue(session.established);
    // An unavailable desktop would already have reached its pixel deadline.
    [session setValue:@(NSProcessInfo.processInfo.systemUptime-9) forKey:@"baselineStarted"];
    [viewer performControlAction:@{@"kind":@"inputOnly"}];
    XCTAssertTrue(viewer.inputOnly); XCTAssertTrue(session.inputOnly); XCTAssertTrue([[viewer valueForKey:@"image"] isHidden]);
    XCTAssertEqual([session tryClickX:1 y:1 mask:1],[policy[@"allowsInputBeforeRelease"] boolValue]);
    XCTestExpectation *admitted=[self expectationWithDescription:@"Input-only admitted without pixels after release"];
    XCTestExpectation *ended=[self expectationWithDescription:@"Same owner stops"];
    __weak CompanionVNCSession *weak=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){
        if ([state isEqual:@"Connected"] && weak.inputOnly) [admitted fulfill];
        if (!weak.running) [ended fulfill];
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
    uint8_t keyRelease[8],pointerRelease[6];
    XCTAssertEqual(recv(pair[1],keyRelease,8,MSG_WAITALL),8); XCTAssertEqual(keyRelease[0],rfbKeyEvent); XCTAssertEqual(keyRelease[1],0);
    XCTAssertEqual(recv(pair[1],pointerRelease,6,MSG_WAITALL),6); XCTAssertEqual(pointerRelease[0],rfbPointerEvent); XCTAssertEqual(pointerRelease[1],0);
    [self waitForExpectations:@[admitted] timeout:2];
    XCTAssertEqualObjects([session valueForKey:@"receivedPixels"],@0); XCTAssertTrue(session.connected);
    XCTAssertEqual([session tryClickX:1 y:1 mask:1],[policy[@"allowsInputAfterRelease"] boolValue]);
    uint8_t click[12]; XCTAssertEqual(recv(pair[1],click,12,MSG_WAITALL),12); XCTAssertEqual(click[1],1); XCTAssertEqual(click[7],0);
    timeout=(struct timeval){.tv_usec=100000}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    uint8_t request[10]; BOOL requested=recv(pair[1],request,10,0)>0;
    XCTAssertEqual(requested,[policy[@"requestsPixelsInInputOnly"] boolValue]); XCTAssertTrue(session.running);
    [viewer performControlAction:@{@"kind":@"inputOnly"}];
    XCTAssertFalse(session.inputOnly); XCTAssertEqual(viewer.session,session);
    XCTAssertEqual([session tryClickX:1 y:1 mask:1],[policy[@"allowsInputAfterReturningToDesktop"] boolValue]);
    timeout=(struct timeval){.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    XCTAssertEqual(recv(pair[1],pointerRelease,6,MSG_WAITALL),6); XCTAssertEqual(pointerRelease[0],rfbPointerEvent); XCTAssertEqual(pointerRelease[1],0);
    XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10); XCTAssertEqual(request[0],rfbFramebufferUpdateRequest); XCTAssertEqual(request[1],0);
    XCTestExpectation *fresh=[self expectationWithDescription:@"Fresh Desktop frame admits input on retained owner"];
    session.frameHandler=^(UIImage *image){[viewer frame:image]; [fresh fulfill];};
    uint8_t frame[]={0,0,0,1,0,0,0,0,0,2,0,2,0,0,0,0, 0,0,255,0,0,0,255,0,0,0,255,0,0,0,255,0};
    XCTAssertEqual(write(pair[1],frame,sizeof(frame)),sizeof(frame));
    [self waitForExpectations:@[fresh] timeout:2];
    XCTAssertEqual([session tryClickX:1 y:1 mask:1],[policy[@"allowsInputAfterFreshDesktopFrame"] boolValue]);
    session.frameHandler=nil; [viewer stopViewer]; [self waitForExpectations:@[ended] timeout:2]; session.stateHandler=nil; close(pair[1]);
}
@end
