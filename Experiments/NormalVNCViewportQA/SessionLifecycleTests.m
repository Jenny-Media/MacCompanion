#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
@protocol LifecycleCredentialState <NSObject>
- (void)editWithUsername:(NSString *)username password:(NSString *)password remember:(BOOL)remember;
- (NSDictionary *)beginLogin;
- (void)authenticated;
@end
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCSession (LifecycleTesting)
- (void)configureClient:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (BOOL)registerSocket:(int)socket;
- (BOOL)resetBaseline:(rfbClient *)client;
- (void)processConnectedClient:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
- (void)report:(NSString *)state;
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client;
@end
@interface CompanionVNCViewer (LifecycleTesting)
- (void)frame:(UIImage *)frame;
- (void)selectDisplay:(NSDictionary *)display;
- (void)setTrackpadModeEnabled:(BOOL)enabled;
- (void)updateConnectionChrome;
- (void)sendPointer:(CGPoint)point mask:(NSInteger)mask;
- (BOOL)clickPointer:(CGPoint)point mask:(NSInteger)mask;
- (void)showTextComposer;
- (void)showCopyScreenText;
- (void)performControlAction:(NSDictionary *)action;
@end
@interface LifecycleSession : CompanionVNCSession
@property BOOL alive, ready, authenticated;
@property NSUInteger pauses, resumes, stops, pointerEvents, clicks;
@end
@implementation LifecycleSession
- (BOOL)running { return self.alive; }
- (BOOL)established { return self.alive && self.authenticated; }
- (BOOL)connected { return self.ready; }
- (void)pauseWithCompletion:(void (^)(void))completion { self.pauses++; self.ready = NO; if (completion) completion(); }
- (void)resume { self.resumes++; }
- (void)pointerX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { self.pointerEvents++; }
- (BOOL)tryClickX:(NSInteger)x y:(NSInteger)y mask:(NSInteger)mask { self.clicks++; return YES; }
- (void)stop { self.stops++; self.alive = NO; self.ready = NO; }
@end
@interface InterruptedBatchSession : CompanionVNCSession
@property(nonatomic, strong) dispatch_semaphore_t firstWrite, continueWrite;
@property BOOL stalled;
@end
@implementation InterruptedBatchSession
- (instancetype)init {
    if ((self=[super init])) { _firstWrite=dispatch_semaphore_create(0); _continueWrite=dispatch_semaphore_create(0); }
    return self;
}
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client {
    if (!self.stalled) {
        self.stalled=YES; dispatch_semaphore_signal(self.firstWrite);
        if (dispatch_semaphore_wait(self.continueWrite,dispatch_time(DISPATCH_TIME_NOW,3*NSEC_PER_SEC))) return NO;
    }
    return [super writeKeyEvent:key down:down client:client];
}
@end
@interface SessionLifecycleTests : XCTestCase
@end
@implementation SessionLifecycleTests
- (void)testWarmResumeKeepsPixelsAndPausedStatusUntilFreshEvidence {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    LifecycleSession *session=[LifecycleSession new]; session.alive=YES; session.ready=YES; session.authenticated=YES; viewer.session=session;
    NSMutableArray *phases=[NSMutableArray array]; viewer.sessionPhaseHandler=^(NSString *phase){ [phases addObject:phase]; };
    [viewer frame:[self frame]];
    UIImageView *image=[viewer valueForKey:@"image"]; UIImage *cached=image.image;
    [viewer background]; XCTAssertEqualObjects(phases.lastObject,@"paused"); XCTAssertEqual(image.alpha,1);
    [viewer foregrounded]; XCTAssertEqual(session.resumes,1); XCTAssertEqual(session.stops,0);
    XCTAssertEqualObjects(phases.lastObject,@"paused"); XCTAssertEqual(image.alpha,1); XCTAssertTrue(image.image==cached);
    XCTAssertTrue([[viewer valueForKey:@"checkingResume"] boolValue]);
    UILabel *status=[viewer valueForKey:@"status"]; XCTAssertTrue(status.hidden);
    XCTAssertFalse([[viewer valueForKey:@"inputInactive"] boolValue]);
    [viewer stopViewer];
}
- (void)testLayoutStatusCannotCompleteInitialLoginOrResumeBeforeFreshFrame {
    CompanionVNCSession *session = [CompanionVNCSession new]; [session setValue:@YES forKey:@"running"];
    // An authenticated Desktop still waits for fresh pixels. A Connected
    // report cannot manufacture authentication/input readiness on its own.
    [session setValue:@YES forKey:@"inputReady"];
    XCTestExpectation *premature = [self expectationWithDescription:@"Metadata does not admit stale pixels"]; premature.inverted = YES;
    session.stateHandler = ^(NSString *state, NSDictionary *stats) { [premature fulfill]; };
    [session report:@"Connected"];
    [session setValue:@10 forKey:@"presentedFrames"]; [session setValue:@YES forKey:@"awaitingResumeFrame"]; [session report:@"Connected"];
    [self waitForExpectations:@[premature] timeout:.05];
    XCTestExpectation *fresh = [self expectationWithDescription:@"Fresh frame permits connected status"];
    session.stateHandler = ^(NSString *state, NSDictionary *stats) { XCTAssertEqualObjects(state,@"Connected"); [fresh fulfill]; };
    [session setValue:@NO forKey:@"awaitingResumeFrame"]; [session setValue:@YES forKey:@"baselinePresented"]; [session report:@"Connected"];
    [self waitForExpectations:@[fresh] timeout:1]; session.stateHandler = nil; [session setValue:@NO forKey:@"running"];
}
- (NSDictionary *)profile {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
}
- (UIImage *)frame {
    return [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(800, 600)] imageWithActions:^(UIGraphicsImageRendererContext *ctx) {
        [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0, 0, 800, 600));
    }];
}
- (void)testActualNativeOwnerPausesReleasesInputAndResumesTheSameSocket {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    int yes = 1; setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct timeval timeout = {.tv_sec = 1}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    CompanionVNCSession *session = [CompanionVNCSession new];
    rfbClient *client = rfbGetClient(8, 3, 4); client->sock = pair[0]; client->width = 2; client->height = 2;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0] |= (1 << rfbKeyEvent) | (1 << rfbPointerEvent) | (1 << rfbFramebufferUpdateRequest);
    client->updateRect.w = 2; client->updateRect.h = 2;
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"]; XCTAssertTrue([session registerSocket:pair[0]]);
    [session setValue:@YES forKey:@"established"];
    XCTestExpectation *ended = [self expectationWithDescription:@"Paused owner stops without hanging"];
    __weak CompanionVNCSession *weakSession = session;
    session.stateHandler = ^(NSString *state, NSDictionary *stats) { if (!weakSession.running) [ended fulfill]; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [session processConnectedClient:client]; });
    [session key:0xffe1 down:YES]; [session pointerX:1 y:1 mask:1];
    uint8_t key[8], pointer[6];
    XCTAssertEqual(recv(pair[1], key, 8, MSG_WAITALL), 8); XCTAssertEqual(key[0], rfbKeyEvent); XCTAssertEqual(key[1], 1);
    XCTAssertEqual(recv(pair[1], pointer, 6, MSG_WAITALL), 6); XCTAssertEqual(pointer[1], 1);
    XCTestExpectation *paused = [self expectationWithDescription:@"Sent input released before suspension"];
    [session pauseWithCompletion:^{ [paused fulfill]; }];
    XCTAssertEqual(recv(pair[1], key, 8, MSG_WAITALL), 8); XCTAssertEqual(key[1], 0);
    XCTAssertEqual(recv(pair[1], pointer, 6, MSG_WAITALL), 6); XCTAssertEqual(pointer[1], 0);
    [self waitForExpectations:@[paused] timeout:1];
    XCTAssertTrue(session.running); XCTAssertFalse(session.connected);
    [session key:0x61 down:YES]; [session pointerX:1 y:1 mask:1];
    XCTAssertEqual([[session valueForKey:@"events"] count], 0);
    const uint8_t raw[] = {0,0,0,1, 0,0,0,0, 0,2,0,2, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0, 0,0,0,0};
    write(pair[1], raw, sizeof(raw));
    timeout = (struct timeval){.tv_usec = 100000}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    uint8_t update[10]; XCTAssertLessThan(recv(pair[1], update, 10, 0), 0); // no polling/automatic update loop while paused
    XCTAssertEqualObjects([session valueForKey:@"updates"], @0);
    XCTestExpectation *frame = [self expectationWithDescription:@"Frame from retained socket"];
    session.frameHandler = ^(UIImage *image) { [frame fulfill]; };
    [session resume]; XCTAssertFalse(session.connected);
    timeout = (struct timeval){.tv_sec = 1}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    XCTAssertEqual(recv(pair[1], update, 10, MSG_WAITALL), 10); XCTAssertEqual(update[0], rfbFramebufferUpdateRequest); XCTAssertEqual(update[1], 0);
    XCTAssertEqual(recv(pair[1], update, 10, MSG_WAITALL), 10); XCTAssertEqual(update[1], 1);
    [self waitForExpectations:@[frame] timeout:1]; XCTAssertTrue(session.connected);
    paused = [self expectationWithDescription:@"Pause again"];
    [session pauseWithCompletion:^{ [paused fulfill]; }];
    XCTAssertEqual(recv(pair[1], pointer, 6, MSG_WAITALL), 6);
    [self waitForExpectations:@[paused] timeout:1]; [session stop];
    [self waitForExpectations:@[ended] timeout:1]; session.stateHandler = nil; session.frameHandler = nil; close(pair[1]);
}
- (void)testPendingFrameCannotEnableInputAfterAPauseResumeBoundary {
    CompanionVNCSession *session = [CompanionVNCSession new];
    rfbClient *client = rfbGetClient(8, 3, 4); client->width = 2; client->height = 2;
    [session allocate:client]; [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    [session setValue:@YES forKey:@"established"];
    [session configureClient:client]; client->GotFrameBufferUpdate(client,0,0,2,2);
    XCTestExpectation *stale = [self expectationWithDescription:@"Pre-pause frame is rejected"]; stale.inverted = YES;
    session.frameHandler = ^(UIImage *image) { [stale fulfill]; };
    [session publishFrame:client]; [session pauseWithCompletion:nil]; [session resume];
    [self waitForExpectations:@[stale] timeout:.1];
    XCTAssertFalse(session.connected);
    XCTAssertEqual([[session valueForKey:@"events"] count], 0);
    [session stop]; [session setValue:@NO forKey:@"running"]; session.frameHandler = nil;
    // Session owns the test pixel buffer; avoid LibVNCClient freeing it twice.
    client->frameBuffer = NULL; rfbClientCleanup(client);
}
- (void)testStopReleasesSentKeyAndButtonWhileInputAdmissionIsClosed {
    for (NSDictionary *entry in [self profile][@"stopReleaseCases"]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
        struct timeval timeout={.tv_sec=2}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
        client->sock=pair[0]; client->width=2; client->height=2;
        [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        client->supportedMessages.client2server[0]|=(1<<rfbKeyEvent)|(1<<rfbPointerEvent);
        for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
        XCTAssertTrue([session registerSocket:pair[0]]);
        // Hold the owner at its iteration boundary after actual wire downs and
        // before it consumes the reset's release request, then Stop immediately.
        uint32_t heldKey=[entry[@"key"] unsignedIntValue];
        XCTAssertTrue(SendKeyEvent(client,heldKey,TRUE)); [[session valueForKey:@"heldKeys"] addObject:@(heldKey)];
        XCTAssertTrue(SendPointerEvent(client,1,1,[entry[@"buttonMask"] intValue]));
        [session setValue:@1 forKey:@"lastX"]; [session setValue:@1 forKey:@"lastY"];
        uint8_t down[14]; XCTAssertEqual(recv(pair[1],down,sizeof(down),MSG_WAITALL),sizeof(down));
        XCTAssertEqual(down[0],rfbKeyEvent); XCTAssertEqual(down[1],1);
        XCTAssertEqual(down[8],rfbPointerEvent); XCTAssertEqual(down[9],[entry[@"buttonMask"] intValue]);
        if ([entry[@"transition"] isEqual:@"baselineReset"]) XCTAssertTrue([session resetBaseline:client]);
        else if ([entry[@"transition"] isEqual:@"inputOnly"]) session.inputOnly=YES;
        else { XCTAssertTrue([session suspendInputForReview:nil]); [session resumeInputAfterReview]; }
        XCTAssertEqual(session.connected,[entry[@"connectedBeforeStop"] boolValue]); XCTAssertTrue(session.established);
        XCTestExpectation *ended=[self expectationWithDescription:entry[@"name"]]; __weak CompanionVNCSession *weak=session;
        session.stateHandler=^(NSString *state,NSDictionary *stats){if(!weak.running)[ended fulfill];};
        [session stop];
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
        uint8_t released[14]; ssize_t count=recv(pair[1],released,sizeof(released),MSG_WAITALL);
        XCTAssertEqual(count,sizeof(released)); XCTAssertTrue([entry[@"releasesBeforeClose"] boolValue]);
        if(count==sizeof(released)) {
            XCTAssertEqual(released[0],rfbKeyEvent); XCTAssertEqual(released[1],0);
            XCTAssertEqual(memcmp(released+4,down+4,4),0);
            XCTAssertEqual(released[8],rfbPointerEvent); XCTAssertEqual(released[9],0);
            XCTAssertEqual(memcmp(released+10,down+10,4),0);
        }
        [self waitForExpectations:@[ended] timeout:2]; session.stateHandler=nil;
        uint8_t extra; XCTAssertEqual(recv(pair[1],&extra,1,0),0); close(pair[1]);
    }
}
- (void)testInactiveInputOnlyReleasePrecedesNewInputWithoutResettingTheSocket {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={.tv_sec=2}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=2; client->height=2;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0]|=(1<<rfbKeyEvent)|(1<<rfbPointerEvent);
    session.inputOnly=YES;
    for (NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session registerSocket:pair[0]]);
    XCTAssertTrue(SendKeyEvent(client,0x61,TRUE)); [[session valueForKey:@"heldKeys"] addObject:@0x61];
    uint8_t key[8]; XCTAssertEqual(recv(pair[1],key,8,MSG_WAITALL),8);
    [session suspendInputForInterruption]; [session key:0x62 down:YES];
    XCTAssertEqual([[session valueForKey:@"events"] count],0);
    [session resumeInputAfterInterruption]; XCTAssertTrue(session.connected);
    [session key:0x63 down:YES];
    XCTestExpectation *ended=[self expectationWithDescription:@"Retained socket stops"]; __weak CompanionVNCSession *weak=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){if(!weak.running)[ended fulfill];};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
    uint8_t wire[22]; XCTAssertEqual(recv(pair[1],wire,sizeof(wire),MSG_WAITALL),sizeof(wire));
    XCTAssertEqual(wire[0],rfbKeyEvent); XCTAssertEqual(wire[1],0); XCTAssertEqual(wire[7],0x61);
    XCTAssertEqual(wire[8],rfbPointerEvent); XCTAssertEqual(wire[9],0);
    XCTAssertEqual(wire[14],rfbKeyEvent); XCTAssertEqual(wire[15],1); XCTAssertEqual(wire[21],0x63);
    XCTAssertEqualObjects([session valueForKey:@"resumeRequested"],@NO);
    [session stop]; [self waitForExpectations:@[ended] timeout:2]; session.stateHandler=nil; close(pair[1]);
}
- (void)testCopiedInputBatchCannotResumeAfterABriefInterruption {
    XCTAssertEqualObjects([self profile][@"recoveryPolicy"][@"retireCopiedInputOnInterruption"],@YES);
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={.tv_sec=2}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    InterruptedBatchSession *session=[InterruptedBatchSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=2; client->height=2;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0]|=(1<<rfbKeyEvent)|(1<<rfbPointerEvent);
    session.inputOnly=YES;
    for (NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session registerSocket:pair[0]]);
    [session keyEvents:@[@{@"key":@0x61,@"down":@YES},@{@"key":@0x62,@"down":@YES}]];
    XCTestExpectation *ended=[self expectationWithDescription:@"Interrupted owner stops"]; __weak CompanionVNCSession *weak=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){if(!weak.running)[ended fulfill];};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
    XCTAssertEqual(dispatch_semaphore_wait(session.firstWrite,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC)),0);
    [session suspendInputForInterruption]; [session resumeInputAfterInterruption]; [session key:0x63 down:YES];
    dispatch_semaphore_signal(session.continueWrite);
    uint8_t wire[30]; XCTAssertEqual(recv(pair[1],wire,sizeof(wire),MSG_WAITALL),sizeof(wire));
    // The already-admitted write may finish; unsent b must be retired. Release a,
    // then admit only c from the new epoch on the same authenticated socket.
    XCTAssertEqual(wire[0],rfbKeyEvent); XCTAssertEqual(wire[1],1); XCTAssertEqual(wire[7],0x61);
    XCTAssertEqual(wire[8],rfbKeyEvent); XCTAssertEqual(wire[9],0); XCTAssertEqual(wire[15],0x61);
    XCTAssertEqual(wire[16],rfbPointerEvent); XCTAssertEqual(wire[17],0);
    XCTAssertEqual(wire[22],rfbKeyEvent); XCTAssertEqual(wire[23],1); XCTAssertEqual(wire[29],0x63);
    [session stop]; [self waitForExpectations:@[ended] timeout:2]; session.stateHandler=nil; close(pair[1]);
}
- (void)testStopBoundsAnEstablishedSocketWhenItsOwnerCannotFinish {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new];
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"established"];
    XCTAssertTrue([session registerSocket:pair[0]]);
    [session stop]; uint8_t byte;
    // No socket owner can acknowledge here; the 250 ms fallback must end the read.
    XCTAssertEqual(recv(pair[1],&byte,1,0),0);
    [session registerSocket:-1]; [session setValue:@NO forKey:@"running"]; close(pair[0]); close(pair[1]);
}
- (void)testViewerRepeatedBackgroundResumeIsIdempotentAndExplicitExitNeverRestarts {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    LifecycleSession *session = [LifecycleSession new]; session.alive = YES; session.ready = YES; session.authenticated = YES; viewer.session = session;
    [viewer background]; [viewer background]; XCTAssertEqual(session.pauses, 1); XCTAssertEqual(session.stops, 0);
    [viewer foregrounded]; [viewer foregrounded]; XCTAssertEqual(session.resumes, 1);
    [viewer stopViewer]; [viewer foregrounded]; XCTAssertEqual(session.resumes, 1);
    XCTAssertFalse([[viewer valueForKey:@"reconnectWhenReady"] boolValue]);
}
- (void)testInterruptedHandshakeAndFailedResumeMakeOnlyOneReplacementAttempt {
    NSDictionary *policy = [self profile][@"recoveryPolicy"];
    XCTAssertEqualObjects(policy[@"automaticReconnectAttempts"], @1);
    for (NSNumber *ready in @[@NO, @YES]) {
        CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        LifecycleSession *session = [LifecycleSession new]; session.alive = YES; session.ready = ready.boolValue; session.authenticated = ready.boolValue; viewer.session = session;
        // Recovery uses the in-memory login captured by a real connection.
        // Seed synthetic state explicitly rather than relying on form defaults.
        id<LifecycleCredentialState> credentials=[viewer valueForKey:@"credentialState"];
        [credentials editWithUsername:@"synthetic-user" password:@"synthetic-password" remember:NO];
        [credentials beginLogin]; [credentials authenticated];
        __block NSUInteger attempts = 0; viewer.connectHandler = ^(NSString *u, NSString *p, BOOL save) { attempts++; };
        [viewer background]; [viewer foregrounded];
        if (ready.boolValue) {
            XCTestExpectation *timeout = [self expectationWithDescription:@"Resume deadline"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ([policy[@"resumeDeadlineMilliseconds"] integerValue] + 100) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [timeout fulfill]; });
            [self waitForExpectations:@[timeout] timeout:[policy[@"resumeDeadlineMilliseconds"] doubleValue] / 1000 + 1];
        }
        XCTAssertEqual(attempts, 1); [viewer foregrounded]; XCTAssertEqual(attempts, 1); [viewer stopViewer];
    }
}
- (void)testReplacementRestoresVerifiedDisplayZoomAndMouseMode {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    viewer.view.frame = CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
    NSDictionary *display = @{@"id":@2,@"title":@"Display 2",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
    NSDictionary *layout = @{@"aspectRatio":@(800.0/600),@"views":@[display]};
    viewer.displayLayout = layout; [viewer frame:[self frame]]; [viewer selectDisplay:display]; [viewer setTrackpadModeEnabled:YES];
    UIScrollView *canvas = [viewer valueForKey:@"canvas"]; CGFloat ratio = 2;
    [canvas setZoomScale:canvas.minimumZoomScale * ratio animated:NO];
    LifecycleSession *old = [LifecycleSession new]; old.alive = YES; old.ready = YES; old.authenticated = YES; viewer.session = old;
    [viewer background]; [viewer prepareConnection]; viewer.displayLayout = layout; [viewer frame:[self frame]];
    XCTAssertEqualObjects([viewer valueForKey:@"selectedDisplay"][@"id"], @2);
    XCTAssertEqualWithAccuracy(canvas.zoomScale / canvas.minimumZoomScale, ratio, .001);
    XCTAssertTrue([[viewer valueForKey:@"trackpadMode"] boolValue]);
    [viewer stopViewer];
}
- (void)testReplacementNeverShowsCombinedDesktopBeforeMatchingFrameAndLayoutInEitherOrder {
    for (NSNumber *frameFirst in @[@YES, @NO]) {
        CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        viewer.view.frame = CGRectMake(0,0,440,956); [viewer.view layoutIfNeeded];
        NSDictionary *display = @{@"id":@2,@"title":@"Display 2",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
        NSDictionary *layout = @{@"aspectRatio":@(800.0/600),@"views":@[display]};
        UIImage *frame = [self frame]; viewer.displayLayout = layout; [viewer frame:frame]; [viewer selectDisplay:display];
        UIImageView *image = [viewer valueForKey:@"image"]; size_t selectedWidth = CGImageGetWidth(image.image.CGImage);
        LifecycleSession *old = [LifecycleSession new]; old.alive=YES; old.ready=YES; old.authenticated=YES; viewer.session=old;
        [viewer background]; [viewer prepareConnection];
        XCTAssertEqual(CGImageGetWidth(image.image.CGImage),selectedWidth);
        if (frameFirst.boolValue) [viewer frame:frame]; else viewer.displayLayout=layout;
        [viewer.view layoutIfNeeded];
        XCTAssertEqual(CGImageGetWidth(image.image.CGImage),selectedWidth,@"Half a restoration must keep the prior crop");
        XCTAssertTrue([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
        if (frameFirst.boolValue) viewer.displayLayout=layout; else [viewer frame:frame];
        XCTAssertEqualObjects([viewer valueForKey:@"selectedDisplay"][@"id"],@2);
        XCTAssertEqual(CGImageGetWidth(image.image.CGImage),selectedWidth);
        XCTAssertFalse([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
        [viewer stopViewer];
    }
}
- (void)testNativeBufferedReplacementFrameRejectsComposerUntilMatchingLayout {
    NSDictionary *profile=[self profile];
    XCTAssertEqualObjects(profile[@"recoveryPolicy"][@"replacementComposeTextRequiresPresentedDesktop"],@YES);
    XCTAssertTrue([[profile[@"interruptionCases"] valueForKey:@"name"] containsObject:@"replacement-frame-first-composer"]);
    UIWindowScene *scene=nil;
    for (UIScene *candidate in UIApplication.sharedApplication.connectedScenes) if ([candidate isKindOfClass:UIWindowScene.class]) { scene=(UIWindowScene *)candidate; break; }
    XCTAssertNotNil(scene); UIWindow *previous=scene.keyWindow, *window=[[UIWindow alloc] initWithWindowScene:scene];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; window.rootViewController=viewer; [window makeKeyAndVisible]; [viewer loadViewIfNeeded];
    NSDictionary *display=@{@"id":@2,@"title":@"Synthetic display",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
    viewer.displayLayout=@{@"aspectRatio":@(800.0/600),@"views":@[display]}; [viewer frame:[self frame]]; [viewer selectDisplay:display];
    LifecycleSession *old=[LifecycleSession new]; old.alive=YES; old.ready=YES; old.authenticated=YES; viewer.session=old;
    [viewer background]; [viewer prepareConnection]; [viewer setValue:@YES forKey:@"foreground"]; [viewer setValue:@NO forKey:@"inputInactive"];
    ((UIView *)[viewer valueForKey:@"login"]).hidden=YES;
    CompanionVNCSession *owner=viewer.session;
    rfbClient *client=rfbGetClient(8,3,4); client->width=2; client->height=2;
    [owner configureClient:client]; XCTAssertTrue([owner allocate:client]);
    for (NSString *key in @[@"running",@"inputReady",@"established"]) [owner setValue:@YES forKey:key];
    client->GotFrameBufferUpdate(client,0,0,2,2); [owner publishFrame:client];
    XCTestExpectation *published=[self expectationWithDescription:@"Native frame callback completes"];
    dispatch_async(dispatch_get_main_queue(),^{ [published fulfill]; }); [self waitForExpectations:@[published] timeout:1];
    XCTAssertTrue(owner.composedTextReady,@"The native callback can be ready while the viewer still retains cached pixels");
    XCTAssertTrue([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
    UIImage *cached=((UIImageView *)[viewer valueForKey:@"image"]).image;
    [viewer performControlAction:@{@"kind":@"composeText"}];
    XCTAssertNil([viewer valueForKey:@"textComposer"],@"Native readiness must not bypass current presentation readiness");
    XCTAssertEqual([[owner valueForKey:@"events"] count],0);
    viewer.displayLayout=@{@"aspectRatio":@1,@"views":@[display]};
    XCTAssertFalse([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
    XCTAssertNotEqual(((UIImageView *)[viewer valueForKey:@"image"]).image,cached);
    [viewer performControlAction:@{@"kind":@"composeText"}]; XCTAssertNotNil([viewer valueForKey:@"textComposer"]);
    [viewer stopViewer]; [viewer dismissViewControllerAnimated:NO completion:nil]; window.hidden=YES; window.rootViewController=nil; [previous makeKeyAndVisible];
    [owner setValue:@NO forKey:@"running"]; client->frameBuffer=NULL; rfbClientCleanup(client);
}
- (void)testReplacementVideoModeRequestsKeepFramesUntilPresentationThenSwitchNormally {
    NSDictionary *profile=[self profile];
    XCTAssertEqualObjects(profile[@"recoveryPolicy"][@"replacementVideoModeChange"],@"defer-until-presentation-ready");
    for (NSNumber *frameFirst in @[@YES,@NO]) {
        NSString *name=frameFirst.boolValue ? @"replacement-video-mode-change-frame-first" : @"replacement-video-mode-change-before-frame";
        XCTAssertTrue([[profile[@"interruptionCases"] valueForKey:@"name"] containsObject:name]);
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        NSDictionary *display=@{@"id":@2,@"title":@"Synthetic display",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
        NSDictionary *layout=@{@"aspectRatio":@(800.0/600),@"views":@[display]};
        viewer.displayLayout=layout; [viewer frame:[self frame]]; [viewer selectDisplay:display];
        LifecycleSession *old=[LifecycleSession new]; old.alive=YES; old.ready=YES; old.authenticated=YES; viewer.session=old;
        [viewer background]; [viewer prepareConnection]; [viewer setValue:@YES forKey:@"foreground"]; [viewer setValue:@NO forKey:@"inputInactive"];
        CompanionVNCSession *owner=viewer.session; [owner setValue:@YES forKey:@"running"]; [owner setValue:@YES forKey:@"established"];
        if (frameFirst.boolValue) [viewer frame:[self frame]];
        UIImage *pending=[viewer valueForKey:@"pendingRestorationFrame"];
        [viewer performControlAction:@{@"kind":@"inputOnly"}]; viewer.inputOnly=YES;
        XCTAssertFalse(viewer.inputOnly); XCTAssertFalse(owner.inputOnly,@"Pending presentation must retain native frame delivery");
        XCTAssertTrue(owner.running); XCTAssertEqual([viewer valueForKey:@"pendingRestorationFrame"],pending);
        viewer.displayLayout=layout; if (!frameFirst.boolValue) [viewer frame:[self frame]];
        XCTAssertFalse([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
        [viewer performControlAction:@{@"kind":@"inputOnly"}]; XCTAssertTrue(viewer.inputOnly); XCTAssertTrue(owner.inputOnly);
        [viewer performControlAction:@{@"kind":@"inputOnly"}]; XCTAssertFalse(viewer.inputOnly); XCTAssertFalse(owner.inputOnly);
        [viewer stopViewer]; [owner setValue:@NO forKey:@"running"];
    }
}
- (void)testRestorationWaitsForMatchingAspectAndAllDisplaysNeedsNoMetadata {
    for (NSNumber *individual in @[@YES,@NO]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        NSDictionary *display=@{@"id":@2,@"title":@"Display 2",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
        NSDictionary *layout=@{@"aspectRatio":@(800.0/600),@"views":@[display]};
        viewer.displayLayout=layout; [viewer frame:[self frame]]; [viewer selectDisplay:individual.boolValue ? display : nil];
        LifecycleSession *old=[LifecycleSession new]; old.alive=YES; old.ready=YES; old.authenticated=YES; viewer.session=old;
        [viewer background]; [viewer prepareConnection];
        LifecycleSession *replacement=[LifecycleSession new]; replacement.alive=YES; replacement.ready=YES; replacement.authenticated=YES; viewer.session=replacement;
        UIImage *newFrame=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(1000,600)] imageWithActions:^(UIGraphicsImageRendererContext *ctx){ [UIColor.systemGreenColor setFill]; UIRectFill(CGRectMake(0,0,1000,600)); }];
        if (individual.boolValue) viewer.displayLayout=layout;
        [viewer setValue:@YES forKey:@"foreground"]; [viewer frame:newFrame];
        if (individual.boolValue) {
            XCTAssertTrue([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
            XCTAssertEqual(CGImageGetWidth(((UIImageView *)[viewer valueForKey:@"image"]).image.CGImage),CGImageGetWidth([self frame].CGImage)/2);
            [viewer sendPointer:CGPointMake(500,50) mask:1]; XCTAssertFalse([viewer clickPointer:CGPointMake(500,50) mask:1]);
            XCTAssertEqual(replacement.pointerEvents,0); XCTAssertEqual(replacement.clicks,0);
            viewer.displayLayout=@{@"aspectRatio":@(1000.0/600),@"views":@[display]};
            XCTAssertEqualObjects([viewer valueForKey:@"selectedDisplay"][@"id"],@2);
        }
        XCTAssertFalse([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
        XCTAssertEqual(CGImageGetWidth(((UIImageView *)[viewer valueForKey:@"image"]).image.CGImage),CGImageGetWidth(newFrame.CGImage)/(individual.boolValue ? 2 : 1));
        [viewer stopViewer];
    }
}
- (void)testReplayedTrackpadModeKeepsReplacementFramesUntilCurrentPresentation {
    XCTAssertTrue([[[self profile][@"interruptionCases"] valueForKey:@"name"] containsObject:@"replacement-video-mode-replay-before-frame"]);
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    NSDictionary *display=@{@"id":@2,@"title":@"Synthetic display",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1};
    NSDictionary *layout=@{@"aspectRatio":@(800.0/600),@"views":@[display]};
    viewer.displayLayout=layout; [viewer frame:[self frame]]; [viewer selectDisplay:display];
    LifecycleSession *old=[LifecycleSession new]; old.alive=YES; old.ready=YES; old.authenticated=YES; viewer.session=old;
    viewer.inputOnly=YES; [viewer background]; [viewer prepareConnection];
    [viewer setValue:@YES forKey:@"foreground"]; [viewer setValue:@NO forKey:@"inputInactive"];
    CompanionVNCSession *owner=viewer.session;
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [owner setValue:@YES forKey:key];
    XCTAssertFalse(owner.inputOnly);
    viewer.inputOnly=YES; // A representable update reapplies the current view mode.
    XCTAssertTrue(viewer.inputOnly); XCTAssertFalse(owner.inputOnly,@"A same-value replay must not suppress the pending frame");
    viewer.displayLayout=layout; [viewer frame:[self frame]];
    XCTAssertFalse([[viewer valueForKey:@"restoreViewportPending"] boolValue]);
    XCTAssertTrue(owner.inputOnly,@"The ready callback forwards the retained Trackpad mode after presentation");
    XCTAssertTrue(owner.running); [viewer stopViewer]; [owner setValue:@NO forKey:@"running"];
}
- (void)testBackgroundConnectionFailurePublishesEndedInsteadOfLeavingPausedActivity {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    [viewer prepareConnection]; CompanionVNCSession *owner=viewer.session;
    __block NSString *phase=nil; viewer.sessionPhaseHandler=^(NSString *value){ phase=value; };
    [owner setValue:@YES forKey:@"running"]; [owner setValue:@YES forKey:@"established"];
    [viewer background]; [owner setValue:@NO forKey:@"running"];
    owner.stateHandler(@"Connection ended",@{});
    XCTAssertEqualObjects(phase,@"ended"); [viewer stopViewer];
}
- (void)testInterruptedCopyTextReviewRetainsBaselineAndIndependentActiveAdmission {
    NSDictionary *profile=[self profile];
    XCTAssertEqualObjects(profile[@"recoveryPolicy"][@"interruptionAdmissionSeparateFromReview"],@YES);
    XCTAssertTrue([[profile[@"interruptionCases"] valueForKey:@"name"] containsObject:@"copy-review-brief-inactive-retains-live-baseline"]);
    NSArray *textEvents=@[@{@"key":@0x61,@"down":@YES},@{@"key":@0x61,@"down":@NO}];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded]; [viewer prepareConnection];
    CompanionVNCSession *owner=viewer.session;
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [owner setValue:@YES forKey:key];
    UIImage *initial=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(2,2)] imageWithActions:^(UIGraphicsImageRendererContext *context){
        [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0,0,2,2));
    }];
    [viewer frame:initial]; [viewer showCopyScreenText]; XCTAssertNotNil([viewer valueForKey:@"textReview"]);
    [owner suspendInputForInterruption]; [owner resumeInputAfterInterruption];
    XCTAssertEqualObjects([owner valueForKey:@"reviewInputSuspended"],@YES);
    XCTAssertFalse(owner.composedTextReady); XCTAssertFalse([owner tryClickX:1 y:1 mask:1]);
    [viewer becameInactive]; XCTAssertNil([viewer valueForKey:@"textReview"]);
    XCTAssertTrue(owner.desktopFrameReady); XCTAssertFalse(owner.composedTextReady);
    XCTAssertFalse([owner tryClickX:1 y:1 mask:1]);
    XCTAssertFalse([owner tryComposedTextEvents:textEvents completion:^(BOOL written){XCTFail(@"Inactive text must not be admitted");}]);
    XCTAssertFalse([[owner valueForKey:@"resumeRequested"] boolValue]);
    [viewer foregrounded]; XCTAssertTrue(owner.composedTextReady);
    XCTAssertTrue([owner tryClickX:1 y:1 mask:1]); XCTAssertTrue([owner tryComposedTextEvents:textEvents completion:^(BOOL written){}]);
    [viewer stopViewer]; [owner setValue:@NO forKey:@"running"];
}

- (void)testBriefInactiveReturnDoesNotPauseOrReconnectTheTransport {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    LifecycleSession *session=[LifecycleSession new]; session.alive=YES; session.ready=YES; session.authenticated=YES; viewer.session=session;
    [viewer becameInactive]; [viewer becameInactive]; [viewer foregrounded]; [viewer foregrounded];
    XCTAssertEqual(session.pauses,0); XCTAssertEqual(session.resumes,0); XCTAssertEqual(session.stops,0);
    XCTAssertFalse([[viewer valueForKey:@"inputInactive"] boolValue]);
    XCTAssertTrue(((UILabel *)[viewer valueForKey:@"status"]).hidden);
    [viewer stopViewer];
}
- (void)testResumeIndicatorIsDelayedAndCancellationRemovesIt {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    UIWindow *window=[[UIWindow alloc] initWithFrame:CGRectMake(0,0,440,956)]; window.rootViewController=viewer; window.hidden=NO;
    LifecycleSession *session=[LifecycleSession new]; session.alive=YES; session.ready=YES; session.authenticated=YES; viewer.session=session;
    [viewer frame:[self frame]]; ((UIView *)[viewer valueForKey:@"login"]).hidden=YES; [viewer updateConnectionChrome];
    [viewer background]; [viewer foregrounded];
    UILabel *status=[viewer valueForKey:@"status"]; XCTAssertTrue(status.hidden);
    XCTestExpectation *delay=[self expectationWithDescription:@"Delayed indication"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,1100*NSEC_PER_MSEC),dispatch_get_main_queue(),^{[delay fulfill];});
    [self waitForExpectations:@[delay] timeout:2];
    XCTAssertFalse(status.hidden); XCTAssertEqualObjects(status.text,@"Updating desktop…");
    UIView *pill=[viewer valueForKey:@"statusBackdrop"]; [viewer.view layoutIfNeeded]; XCTAssertFalse(pill.hidden);
    XCTAssertGreaterThan(pill.bounds.size.width,0); XCTAssertLessThanOrEqual(CGRectGetMaxX(pill.frame),viewer.view.bounds.size.width);
    UIGraphicsImageRenderer *renderer=[[UIGraphicsImageRenderer alloc] initWithSize:viewer.view.bounds.size];
    UIImage *capture=[renderer imageWithActions:^(UIGraphicsImageRendererContext *context){[viewer.view drawViewHierarchyInRect:viewer.view.bounds afterScreenUpdates:YES];}];
    XCTAttachment *attachment=[XCTAttachment attachmentWithImage:capture]; attachment.name=@"Desktop restoration capsule"; attachment.lifetime=XCTAttachmentLifetimeKeepAlways; [self addAttachment:attachment];
    [viewer stopViewer]; XCTAssertTrue(pill.hidden); window.hidden=YES; window.rootViewController=nil;
}
@end
