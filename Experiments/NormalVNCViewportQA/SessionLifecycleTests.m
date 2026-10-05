#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCSession (LifecycleTesting)
- (void)configureClient:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (BOOL)registerSocket:(int)socket;
- (void)processConnectedClient:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
- (void)report:(NSString *)state;
@end
@interface CompanionVNCViewer (LifecycleTesting)
- (void)frame:(UIImage *)frame;
- (void)selectDisplay:(NSDictionary *)display;
- (void)setTrackpadModeEnabled:(BOOL)enabled;
@end
@interface LifecycleSession : CompanionVNCSession
@property BOOL alive, ready;
@property NSUInteger pauses, resumes, stops;
@end
@implementation LifecycleSession
- (BOOL)running { return self.alive; }
- (BOOL)connected { return self.ready; }
- (void)pauseWithCompletion:(void (^)(void))completion { self.pauses++; self.ready = NO; if (completion) completion(); }
- (void)resume { self.resumes++; }
- (void)stop { self.stops++; self.alive = NO; self.ready = NO; }
@end
@interface SessionLifecycleTests : XCTestCase
@end
@implementation SessionLifecycleTests
- (void)testLayoutStatusCannotCompleteInitialLoginOrResumeBeforeFreshFrame {
    CompanionVNCSession *session = [CompanionVNCSession new]; [session setValue:@YES forKey:@"running"];
    XCTestExpectation *premature = [self expectationWithDescription:@"Metadata does not admit stale pixels"]; premature.inverted = YES;
    session.stateHandler = ^(NSString *state, NSDictionary *stats) { [premature fulfill]; };
    [session report:@"Connected"];
    [session setValue:@10 forKey:@"presentedFrames"]; [session setValue:@YES forKey:@"awaitingResumeFrame"]; [session report:@"Connected"];
    [self waitForExpectations:@[premature] timeout:.05];
    XCTestExpectation *fresh = [self expectationWithDescription:@"Fresh frame permits connected status"];
    session.stateHandler = ^(NSString *state, NSDictionary *stats) { XCTAssertEqualObjects(state,@"Connected"); [fresh fulfill]; };
    [session setValue:@NO forKey:@"awaitingResumeFrame"]; [session report:@"Connected"];
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
    [session setValue:@YES forKey:@"dirty"];
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
- (void)testViewerRepeatedBackgroundResumeIsIdempotentAndExplicitExitNeverRestarts {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    LifecycleSession *session = [LifecycleSession new]; session.alive = YES; session.ready = YES; viewer.session = session;
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
        LifecycleSession *session = [LifecycleSession new]; session.alive = YES; session.ready = ready.boolValue; viewer.session = session;
        __block NSUInteger attempts = 0; viewer.connectHandler = ^(NSString *u, NSString *p, BOOL save) { attempts++; };
        [viewer background]; [viewer foregrounded];
        if (ready.boolValue) {
            XCTestExpectation *timeout = [self expectationWithDescription:@"Resume deadline"];
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, ([policy[@"resumeDeadlineMilliseconds"] integerValue] + 100) * NSEC_PER_MSEC), dispatch_get_main_queue(), ^{ [timeout fulfill]; });
            [self waitForExpectations:@[timeout] timeout:2];
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
    LifecycleSession *old = [LifecycleSession new]; old.alive = YES; old.ready = YES; viewer.session = old;
    [viewer background]; [viewer prepareConnection]; viewer.displayLayout = layout; [viewer frame:[self frame]];
    XCTAssertEqualObjects([viewer valueForKey:@"selectedDisplay"][@"id"], @2);
    XCTAssertEqualWithAccuracy(canvas.zoomScale / canvas.minimumZoomScale, ratio, .001);
    XCTAssertTrue([[viewer valueForKey:@"trackpadMode"] boolValue]);
    [viewer stopViewer];
}
@end
