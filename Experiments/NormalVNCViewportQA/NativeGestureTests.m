#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCSession (NativeGestureTesting)
- (void)configureClient:(rfbClient *)client;
- (BOOL)sendMagnificationEvent:(NSDictionary *)event client:(rfbClient *)client;
- (BOOL)releaseMagnification:(rfbClient *)client;
- (void)processConnectedClient:(rfbClient *)client;
@end
@interface CompanionVNCViewer (NativeGestureTesting)
- (void)pinchRemote:(UIPinchGestureRecognizer *)gesture;
- (void)releasePointer;
@end
@interface SyntheticPinch : UIPinchGestureRecognizer
@property UIGestureRecognizerState syntheticState;
@end
@implementation SyntheticPinch
- (UIGestureRecognizerState)state { return self.syntheticState; }
@end
@interface NativeGestureTests : XCTestCase
@end
@implementation NativeGestureTests
- (CompanionVNCSession *)session {
    CompanionVNCSession *s = [CompanionVNCSession new]; s.inputOnly = YES;
    for (NSString *key in @[@"running", @"inputReady", @"appleGestureServer", @"nativeGestureLayout"]) [s setValue:@YES forKey:key];
    [s setValue:@3024 forKey:@"framebufferWidth"]; [s setValue:@1964 forKey:@"framebufferHeight"];
    return s;
}
- (NSData *)packet:(NSUInteger)index {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSString *hex = profile[@"nativeMagnificationCases"][index][@"hex"];
    NSMutableData *bytes = [NSMutableData new];
    for (NSUInteger i=0; i<hex.length; i+=2) {
        unsigned value; [[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&value];
        uint8_t byte = value; [bytes appendBytes:&byte length:1];
    }
    return bytes;
}
- (NSArray *)takeEvents:(CompanionVNCSession *)session {
    NSMutableArray *events = [session valueForKey:@"events"]; NSArray *copy = [events copy]; [events removeAllObjects]; return copy;
}
- (void)receive:(int)socket matches:(NSData *)expected {
    NSMutableData *actual = [NSMutableData dataWithLength:expected.length];
    XCTAssertEqual(recv(socket, actual.mutableBytes, actual.length, MSG_WAITALL), (ssize_t)actual.length);
    XCTAssertEqualObjects(actual, expected);
}
- (void)testUnsupportedConnectionNeverQueuesNativePinchAndDoesNotReplaceItWithKeys {
    CompanionVNCSession *s = [self session]; [s setValue:@NO forKey:@"appleGestureServer"];
    XCTAssertFalse(s.nativeMagnificationSupported); XCTAssertFalse([s beginMagnificationX:1000 y:600]);
    XCTAssertEqual([self takeEvents:s].count, 0);
    [s setValue:@YES forKey:@"appleGestureServer"]; s.inputOnly = NO;
    XCTAssertFalse([s beginMagnificationX:1000 y:600]); XCTAssertEqual([self takeEvents:s].count, 0);
}
- (void)testRepeatedSequencesUseGoldenWireGroupsAndCancelCopiedChanges {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    struct timeval timeout = {.tv_sec=1}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    rfbClient *client = rfbGetClient(8,3,4); client->sock = pair[0]; client->width = 3024; client->height = 1964;
    CompanionVNCSession *s = [self session]; [s configureClient:client];
    for (NSUInteger repeat=0; repeat<3; repeat++) {
        XCTAssertTrue([s beginMagnificationX:1000 y:600]); XCTAssertTrue([s changeMagnification:.05]);
        NSArray *events = [self takeEvents:s]; XCTAssertEqual(events.count, 2);
        XCTAssertTrue([s sendMagnificationEvent:events[0] client:client]); [self receive:pair[1] matches:[self packet:0]];
        [s cancelMagnification];
        XCTAssertTrue([s sendMagnificationEvent:events[1] client:client]); // copied stale update is ignored
        XCTAssertTrue([s releaseMagnification:client]); [self receive:pair[1] matches:[self packet:3]];
        XCTAssertTrue([s releaseMagnification:client]); // repeated cancel sends no extra end
        XCTAssertFalse([s changeMagnification:.05]);
    }
    close(pair[1]); rfbClientCleanup(client);
}
- (void)testFullQueueCanAlwaysRetireAnActiveGesture {
    CompanionVNCSession *s = [self session]; XCTAssertTrue([s beginMagnificationX:1000 y:600]);
    NSArray *copied = [self takeEvents:s]; NSUInteger epoch = [copied[0][@"gestureEpoch"] unsignedIntegerValue];
    NSMutableArray *events = [s valueForKey:@"events"];
    for (NSUInteger i=0; i<512; i++) [events addObject:@{@"key":@0x61, @"down":@YES}];
    [s endMagnification]; XCTAssertGreaterThan([[s valueForKey:@"magnificationEpoch"] unsignedIntegerValue], epoch);
    XCTAssertEqual(events.count, 512); XCTAssertFalse([[s valueForKey:@"queuedMagnification"] boolValue]);
    XCTAssertFalse([s changeMagnification:.05]);
}
- (void)testActualOwnerReleasesNativePinchBeforePauseAndKeepsSocketForRepeat {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    struct timeval timeout = {.tv_sec=1}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    int yes=1; setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    rfbClient *client = rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3024; client->height=1964;
    client->supportedMessages.client2server[0] |= 1 << rfbPointerEvent;
    CompanionVNCSession *s = [self session]; [s configureClient:client];
    XCTestExpectation *ended = [self expectationWithDescription:@"Owner stops"];
    __weak CompanionVNCSession *weak = s;
    s.stateHandler = ^(NSString *state, NSDictionary *stats) { if (!weak.running) [ended fulfill]; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0), ^{ [s processConnectedClient:client]; });
    for (NSUInteger repeat=0; repeat<2; repeat++) {
        XCTAssertTrue([s beginMagnificationX:1000 y:600]); [self receive:pair[1] matches:[self packet:0]];
        XCTestExpectation *paused = [self expectationWithDescription:@"Balanced pause"];
        [s pauseWithCompletion:^{ [paused fulfill]; }];
        [self receive:pair[1] matches:[self packet:3]];
        uint8_t pointer[6]; XCTAssertEqual(recv(pair[1],pointer,6,MSG_WAITALL),6); XCTAssertEqual(pointer[1],0);
        [self waitForExpectations:@[paused] timeout:1]; XCTAssertTrue(s.running); XCTAssertFalse(s.connected);
        [s resume]; XCTAssertTrue(s.connected);
    }
    [s stop]; [self waitForExpectations:@[ended] timeout:1]; s.stateHandler=nil; close(pair[1]);
}
- (void)testInputOnlyPinchUsesFixedCursorAndIncrementalScaleAndControlsCancelIt {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; viewer.inputOnly=YES; [viewer loadViewIfNeeded];
    CompanionVNCSession *s=[self session]; viewer.session=s;
    [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,3024,1964)] forKey:@"activeCrop"];
    [viewer setValue:[NSValue valueWithCGPoint:CGPointMake(1000,600)] forKey:@"cursorPosition"];
    [viewer setValue:@YES forKey:@"cursorPositionKnown"];
    XCTAssertTrue([[viewer valueForKey:@"remotePinch"] isEnabled]);
    XCTAssertFalse([[viewer valueForKey:@"canvas"] pinchGestureRecognizer].enabled);
    SyntheticPinch *pinch=[SyntheticPinch new]; pinch.syntheticState=UIGestureRecognizerStateBegan; pinch.scale=1;
    [viewer pinchRemote:pinch];
    pinch.syntheticState=UIGestureRecognizerStateChanged; pinch.scale=1.05; [viewer pinchRemote:pinch];
    XCTAssertEqualWithAccuracy(pinch.scale,1,.0001);
    NSArray *events=[self takeEvents:s]; XCTAssertEqual(events.count,2);
    XCTAssertEqualObjects(events[0][@"x"],@1000); XCTAssertEqualObjects(events[0][@"y"],@600);
    XCTAssertEqualWithAccuracy([events[1][@"delta"] doubleValue],.05,.000001);
    [viewer releasePointer]; pinch.scale=1.05; [viewer pinchRemote:pinch]; XCTAssertEqual([self takeEvents:s].count,0);
    viewer.inputOnly=NO; XCTAssertFalse([[viewer valueForKey:@"remotePinch"] isEnabled]);
    XCTAssertTrue([[viewer valueForKey:@"canvas"] pinchGestureRecognizer].enabled);
}
@end
