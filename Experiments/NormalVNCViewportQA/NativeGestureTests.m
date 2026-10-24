#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCSession (NativeGestureTesting)
- (void)configureClient:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (BOOL)sendMagnificationEvent:(NSDictionary *)event client:(rfbClient *)client;
- (BOOL)releaseMagnification:(rfbClient *)client;
- (BOOL)sendScrollEvent:(NSDictionary *)event client:(rfbClient *)client;
- (BOOL)releaseScroll:(rfbClient *)client;
- (void)processConnectedClient:(rfbClient *)client;
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client;
- (BOOL)sendInputEvents:(NSArray *)events client:(rfbClient *)client inputEpoch:(NSUInteger)epoch;
- (BOOL)servicePendingInput:(rfbClient *)client;
- (void)retireNativeGesturesLocked;
@end
@interface CompanionVNCViewer (NativeGestureTesting)
- (void)scrollRemote:(UIPanGestureRecognizer *)gesture;
- (void)pinchRemote:(UIPinchGestureRecognizer *)gesture;
- (void)releasePointer;
- (void)secondaryClickAt:(UITapGestureRecognizer *)gesture;
- (void)setTrackpadModeEnabled:(BOOL)enabled;
- (void)becameInactive;
@end
@interface SyntheticPinch : UIPinchGestureRecognizer
@property UIGestureRecognizerState syntheticState;
@end
@implementation SyntheticPinch
- (UIGestureRecognizerState)state { return self.syntheticState; }
@end
@interface SyntheticScroll : UIPanGestureRecognizer
@property UIGestureRecognizerState syntheticState;
@property CGPoint delta;
@end
@implementation SyntheticScroll
- (UIGestureRecognizerState)state { return self.syntheticState; }
- (CGPoint)translationInView:(UIView *)view { return self.delta; }
- (void)setTranslation:(CGPoint)translation inView:(UIView *)view { self.delta = translation; }
@end
@interface SecondaryTapSample : UITapGestureRecognizer
@property UIGestureRecognizerState sampleState;
@property CGPoint point;
@property NSUInteger cancellations;
@end
@implementation SecondaryTapSample
- (UIGestureRecognizerState)state { return self.sampleState; }
- (CGPoint)locationInView:(UIView *)view { return self.point; }
- (void)setEnabled:(BOOL)enabled { if (!enabled) self.cancellations++; [super setEnabled:enabled]; }
@end
@interface GestureBoundarySession : CompanionVNCSession
@property(nonatomic, strong) dispatch_semaphore_t firstWrite, continueWrite;
@property BOOL stalled;
@end
@implementation GestureBoundarySession
- (instancetype)init { if ((self=[super init])) { _firstWrite=dispatch_semaphore_create(0); _continueWrite=dispatch_semaphore_create(0); } return self; }
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client {
    if (!self.stalled) { self.stalled=YES; dispatch_semaphore_signal(self.firstWrite);
        if (dispatch_semaphore_wait(self.continueWrite,dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_SEC))) return NO; }
    return [super writeKeyEvent:key down:down client:client];
}
@end
@interface NativeGestureTests : XCTestCase
@end
@implementation NativeGestureTests
- (CompanionVNCSession *)session {
    return [self sessionWithInputOnly:YES];
}
- (CompanionVNCSession *)sessionWithInputOnly:(BOOL)inputOnly {
    CompanionVNCSession *s = [CompanionVNCSession new]; s.inputOnly = inputOnly;
    for (NSString *key in @[@"running", @"established", @"inputReady", @"appleGestureServer", @"nativeGestureLayout"]) [s setValue:@YES forKey:key];
    [s setValue:@3024 forKey:@"framebufferWidth"]; [s setValue:@1964 forKey:@"framebufferHeight"];
    return s;
}
- (NSData *)packet:(NSUInteger)index { return [self packet:index cases:@"nativeMagnificationCases"]; }
- (NSData *)packet:(NSUInteger)index cases:(NSString *)cases {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSString *hex = profile[cases][index][@"hex"];
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
- (void)testFailedShortcutAdmissionLeavesTheExistingGestureAlone {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; viewer.inputOnly=YES; [viewer loadViewIfNeeded];
    CompanionVNCSession *s=[self session]; viewer.session=s;
    XCTAssertTrue([s beginScrollX:1000 y:600]);
    [viewer setValue:@YES forKey:@"scrollingActive"];
    NSUInteger epoch=[[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue];
    NSArray *pending=@[@{@"key":@0x61,@"down":@YES}];
    XCTAssertTrue([s tryComposedTextEvents:pending completion:^(BOOL ok){}]);
    XCTAssertNil([viewer beginControlSequence]);
    XCTAssertTrue([[viewer valueForKey:@"scrollingActive"] boolValue]);
    XCTAssertEqual([[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue],epoch);
    XCTAssertEqualObjects([self takeEvents:s].firstObject[@"scrollPhase"],@1);
    [s stop];
}
- (void)testReservedRecognizerCallbacksCannotRetireTheAcceptedGesturePrefix {
    CompanionVNCSession *s=[self session]; XCTAssertTrue([s beginScrollX:1000 y:600]);
    NSUInteger epoch=[[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue];
    NSString *owner=[s beginControlSequence]; XCTAssertNotNil(owner);
    [s cancelNativeGestures];
    XCTAssertFalse([s changeScrollX:12 y:24]); XCTAssertFalse([s changeMagnification:.05]);
    XCTAssertEqual([[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue],epoch);
    XCTAssertEqualObjects([self takeEvents:s].firstObject[@"scrollPhase"],@1);
    [s cancelControlSequence:owner]; [s stop];
}
- (void)testShortcutPreservesQueuedNativeScrollThroughTheViewer {
    [self checkShortcutGestureBoundary:NO copied:NO cancel:NO];
}
- (void)testShortcutPreservesCopiedNativePinchThroughTheViewer {
    [self checkShortcutGestureBoundary:YES copied:YES cancel:NO];
}
- (void)testCancelCleanupPreservesFreshScrollBehindItsBoundary {
    [self checkShortcutGestureBoundary:NO copied:YES cancel:YES];
}
- (void)testCancelOfFreshGesturesPreservesEveryQueuedAndCopiedPrefix {
    for (NSNumber *pinch in @[@NO,@YES]) for (NSNumber *copied in @[@NO,@YES]) for (NSNumber *freshPinch in @[@NO,@YES]) {
        [self checkShortcutGestureBoundary:pinch.boolValue copied:copied.boolValue cancel:YES
                               freshPinch:freshPinch.boolValue freshState:UIGestureRecognizerStateCancelled];
    }
}
- (void)testFailedFreshGesturePreservesTheEarlierAcceptedPrefix {
    [self checkShortcutGestureBoundary:NO copied:YES cancel:YES freshPinch:NO freshState:UIGestureRecognizerStateFailed];
}
- (void)testCleanupCapacityIsSharedByEveryUserInputProducer {
    NSArray *pair=@[@{@"key":@0x61,@"down":@YES},@{@"key":@0x61,@"down":@NO}];
    for (NSUInteger producer=0;producer<8;producer++) {
        CompanionVNCSession *s=[self session];
        for (NSUInteger i=0;i<255;i++) [s keyEvents:pair];
        NSString *owner=[s beginControlSequence]; XCTAssertNotNil(owner);
        XCTAssertTrue([s tryControlSequenceEvents:pair identifier:owner completion:^(BOOL ok){}]);
        [s cancelControlSequence:owner];
        switch (producer) {
            case 0: [s keyEvents:pair]; break;
            case 1: [s key:0x61 down:YES]; [s key:0x61 down:NO]; break;
            case 2: XCTAssertTrue([s tryKeyEvents:pair]); break;
            case 3: XCTAssertTrue([s tryComposedTextEvents:pair completion:^(BOOL ok){}]); break;
            case 4: XCTAssertTrue([s tryClickX:1000 y:600 mask:1]); break;
            case 5: [s pointerX:1000 y:600 mask:1]; [s pointerX:1000 y:600 mask:0]; break;
            case 6: XCTAssertTrue([s beginScrollX:1000 y:600]); [s endScroll]; break;
            case 7: XCTAssertTrue([s beginMagnificationX:1000 y:600]); [s endMagnification]; break;
        }
        NSArray *events=[self takeEvents:s];
        NSUInteger users=[events indexesOfObjectsPassingTest:^BOOL(NSDictionary *event,NSUInteger i,BOOL *stop){return ![event[@"controlCleanup"] boolValue];}].count;
        XCTAssertEqual(users,512,@"producer %lu",(unsigned long)producer);
        XCTAssertFalse([[s valueForKey:@"overflow"] boolValue],@"producer %lu",(unsigned long)producer);
        [s stop];
    }
}
- (void)testCleanupAllowanceDoesNotPermitRealUserOverflow {
    CompanionVNCSession *s=[self session];
    NSString *owner=[s beginControlSequence]; [s cancelControlSequence:owner];
    NSArray *pair=@[@{@"key":@0x61,@"down":@YES},@{@"key":@0x61,@"down":@NO}];
    for (NSUInteger i=0;i<256;i++) [s keyEvents:pair];
    XCTAssertFalse([[s valueForKey:@"overflow"] boolValue]);
    XCTAssertFalse([s tryKeyEvents:pair]);
    [s keyEvents:pair]; XCTAssertTrue([[s valueForKey:@"overflow"] boolValue]);
    [s stop];
}
- (void)testRepeatedCanceledGesturesAndShortcutsKeepBarriersBounded {
    CompanionVNCSession *s=[self session]; [s key:0x61 down:NO];
    for (NSUInteger i=0;i<1000;i++) {
        NSString *owner=[s beginControlSequence]; XCTAssertNotNil(owner);
        [s cancelControlSequence:owner];
        XCTAssertTrue([s beginScrollX:1000 y:600]); XCTAssertTrue([s changeScrollX:12 y:24]);
        [s cancelNativeGestures];
        XCTAssertLessThanOrEqual([[s valueForKey:@"events"] count],2);
        XCTAssertFalse([[s valueForKey:@"overflow"] boolValue]);
    }
    [s stop];
}
- (void)testGlobalGestureRetirementCoalescesBarriersWithoutDroppingOrdinaryInput {
    CompanionVNCSession *s=[self session]; [s key:0x61 down:NO];
    for (NSUInteger i=0;i<100;i++) {
        XCTAssertTrue([s beginScrollX:1000 y:600]); [s endScroll];
        NSString *owner=[s beginControlSequence]; XCTAssertNotNil(owner); [s cancelControlSequence:owner];
    }
    XCTAssertEqual([[s valueForKey:@"events"] count],301);
    // Metadata/lifecycle retirement can remove the native events separating
    // barriers while retaining ordinary input; exercise that locked operation.
    NSLock *lock=[s valueForKey:@"lock"]; [lock lock]; [s retireNativeGesturesLocked]; [lock unlock];
    NSArray *events=[self takeEvents:s]; XCTAssertEqual(events.count,2);
    XCTAssertEqualObjects(events.firstObject[@"key"],@0x61);
    XCTAssertTrue([events.lastObject[@"controlCleanup"] boolValue]);
    XCTAssertFalse([[s valueForKey:@"overflow"] boolValue]); [s stop];
}
- (void)testCompletedGesturesSurviveLaterLocalCancellationWithoutAShortcut {
    for (NSNumber *pinch in @[@NO,@YES]) for (NSNumber *copied in @[@NO,@YES]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3024; client->height=1964;
        CompanionVNCSession *s=[self session]; [s configureClient:client];
        XCTAssertTrue(pinch.boolValue ? [s beginMagnificationX:1000 y:600] : [s beginScrollX:1000 y:600]);
        XCTAssertTrue(pinch.boolValue ? [s changeMagnification:.05] : [s changeScrollX:12 y:24]);
        if (pinch.boolValue) [s endMagnification]; else [s endScroll];
        NSArray *old=copied.boolValue ? [self takeEvents:s] : nil;
        // The new gesture uses the opposite type to exercise shared retirement.
        XCTAssertTrue(pinch.boolValue ? [s beginScrollX:1000 y:600] : [s beginMagnificationX:1000 y:600]);
        [s cancelNativeGestures]; [s cancelNativeGestures];
        NSArray *events=old ?: [self takeEvents:s]; XCTAssertEqual(events.count,3);
        XCTAssertTrue([s sendInputEvents:events client:client inputEpoch:[[s valueForKey:@"inputEpoch"] unsignedIntegerValue]]);
        NSString *cases=pinch.boolValue ? @"nativeMagnificationCases" : @"nativeScrollCases";
        for (NSNumber *i in @[@0,@1,@3]) [self receive:pair[1] matches:[self packet:i.unsignedIntegerValue cases:cases]];
        [s stop]; close(pair[1]); rfbClientCleanup(client);
    }
}
- (void)testCancelledSentGestureIsReleasedByTheReaderWithoutQueuedInput {
    for (NSNumber *pinch in @[@NO,@YES]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3024; client->height=1964;
        CompanionVNCSession *s=[self session]; [s configureClient:client];
        [s setValue:@NO forKey:@"modeChanged"]; [s setValue:@NO forKey:@"releaseInputRequested"];
        XCTAssertTrue(pinch.boolValue ? [s beginMagnificationX:1000 y:600] : [s beginScrollX:1000 y:600]);
        XCTAssertTrue([s sendInputEvents:[self takeEvents:s] client:client inputEpoch:[[s valueForKey:@"inputEpoch"] unsignedIntegerValue]]);
        NSString *cases=pinch.boolValue ? @"nativeMagnificationCases" : @"nativeScrollCases";
        [self receive:pair[1] matches:[self packet:0 cases:cases]];
        [s cancelNativeGestures]; XCTAssertEqual([[s valueForKey:@"events"] count],0);
        XCTAssertTrue([s servicePendingInput:client]);
        [self receive:pair[1] matches:[self packet:3 cases:cases]];
        XCTAssertTrue([s servicePendingInput:client]);
        uint8_t byte; XCTAssertEqual(recv(pair[1],&byte,1,MSG_DONTWAIT),-1);
        [s stop]; close(pair[1]); rfbClientCleanup(client);
    }
}
- (void)testLifecycleStillRetiresCompletedAndBoundarySealedCopiedGestures {
    for (NSNumber *pinch in @[@NO,@YES]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3024; client->height=1964;
        CompanionVNCSession *s=[self session]; [s configureClient:client];
        XCTAssertTrue(pinch.boolValue ? [s beginMagnificationX:1000 y:600] : [s beginScrollX:1000 y:600]);
        if (pinch.boolValue) [s endMagnification]; else [s endScroll];
        NSArray *copied=[self takeEvents:s];
        NSString *owner=[s beginControlSequence]; [s cancelControlSequence:owner];
        [s suspendInputForInterruption]; [s resumeInputAfterInterruption];
        for (NSDictionary *event in copied) {
            XCTAssertTrue(pinch.boolValue ? [s sendMagnificationEvent:event client:client] : [s sendScrollEvent:event client:client]);
        }
        uint8_t byte; XCTAssertEqual(recv(pair[1],&byte,1,MSG_DONTWAIT),-1,@"A quick return must not revive old gesture tokens");
        [s stop]; close(pair[1]); rfbClientCleanup(client);
    }
}
- (void)checkShortcutGestureBoundary:(BOOL)pinch copied:(BOOL)copied cancel:(BOOL)cancel {
    [self checkShortcutGestureBoundary:pinch copied:copied cancel:cancel freshPinch:NO freshState:UIGestureRecognizerStateEnded];
}
- (void)checkShortcutGestureBoundary:(BOOL)pinch copied:(BOOL)copied cancel:(BOOL)cancel
                        freshPinch:(BOOL)freshPinch freshState:(UIGestureRecognizerState)freshState {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    GestureBoundarySession *s=[GestureBoundarySession new]; s.inputOnly=YES;
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3024; client->height=1964;
    [s configureClient:client];
    client->supportedMessages.client2server[0]|=(1<<rfbKeyEvent)|(1<<rfbPointerEvent);
    for (NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer",@"nativeGestureLayout"]) [s setValue:@YES forKey:key];
    [s setValue:@3024 forKey:@"framebufferWidth"]; [s setValue:@1964 forKey:@"framebufferHeight"];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; viewer.inputOnly=YES; [viewer loadViewIfNeeded]; viewer.session=s;
    [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,3024,1964)] forKey:@"activeCrop"];
    [viewer setValue:[NSValue valueWithCGPoint:CGPointMake(1000,600)] forKey:@"cursorPosition"];
    [viewer setValue:@YES forKey:@"cursorPositionKnown"];
    XCTAssertTrue(pinch ? [s beginMagnificationX:1000 y:600] : [s beginScrollX:1000 y:600]);
    NSArray *initial=[self takeEvents:s];
    XCTAssertTrue([s sendInputEvents:initial client:client inputEpoch:[[s valueForKey:@"inputEpoch"] unsignedIntegerValue]]);
    NSString *cases=pinch ? @"nativeMagnificationCases" : @"nativeScrollCases";
    [self receive:pair[1] matches:[self packet:0 cases:cases]];
    [s key:0x78 down:NO];
    void (^queueGesture)(void)=^{
        XCTAssertTrue(pinch ? [s changeMagnification:.05] : [s changeScrollX:12 y:24]);
        if (pinch) [s endMagnification]; else [s endScroll];
    };
    if (copied) queueGesture();
    XCTestExpectation *ended=[self expectationWithDescription:@"Gesture worker stops"];
    __weak CompanionVNCSession *weak=s;
    s.stateHandler=^(NSString *state,NSDictionary *stats){if(!weak.running)[ended fulfill];};
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[s processConnectedClient:client];});
    XCTAssertEqual(dispatch_semaphore_wait(s.firstWrite,dispatch_time(DISPATCH_TIME_NOW,2*NSEC_PER_SEC)),0);
    if (!copied) queueGesture();
    NSUInteger epoch=[[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue];
    NSString *owner=[viewer beginControlSequence]; XCTAssertNotNil(owner);
    NSUInteger after=[[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue];
    NSArray *chord=@[@{@"key":@0x61,@"down":@YES},@{@"key":@0x61,@"down":@NO}];
    XCTestExpectation *reply=[self expectationWithDescription:@"Sequence reply"];
    XCTAssertTrue([viewer sendControlSequenceEvents:chord identifier:owner completion:^(BOOL ok){XCTAssertEqual(ok,!cancel);[reply fulfill];}]);
    if (cancel) {
        [viewer cancelControlSequence:owner];
        // Exercise a real viewer recognizer after Cancel, including its local release path.
        if (freshPinch) {
            SyntheticPinch *fresh=[SyntheticPinch new]; fresh.syntheticState=UIGestureRecognizerStateBegan; fresh.scale=1;
            [viewer pinchRemote:fresh]; fresh.syntheticState=UIGestureRecognizerStateChanged; fresh.scale=1.05;
            [viewer pinchRemote:fresh]; fresh.syntheticState=freshState; fresh.scale=1; [viewer pinchRemote:fresh];
        } else {
            SyntheticScroll *fresh=[SyntheticScroll new]; fresh.syntheticState=UIGestureRecognizerStateBegan;
            [viewer scrollRemote:fresh]; fresh.syntheticState=UIGestureRecognizerStateChanged;
            fresh.delta=CGPointMake(4,8); [viewer scrollRemote:fresh];
            fresh.syntheticState=freshState; fresh.delta=CGPointZero; [viewer scrollRemote:fresh];
        }
    }
    dispatch_semaphore_signal(s.continueWrite);
    XCTAssertEqual(after,epoch,@"A shortcut must preserve accepted native input until its barrier");
    const uint8_t accepted[]={4,0,0,0,0,0,0,0x78};
    NSMutableData *expected=[NSMutableData dataWithBytes:accepted length:sizeof(accepted)];
    [expected appendData:[self packet:1 cases:cases]]; [expected appendData:[self packet:3 cases:cases]];
    const uint8_t cleanup[]={5,0,0,0,0,0}; [expected appendBytes:cleanup length:sizeof(cleanup)];
    if (cancel && freshState==UIGestureRecognizerStateEnded) { for (NSNumber *i in @[@0,@1,@3]) [expected appendData:[self packet:i.unsignedIntegerValue cases:@"nativeScrollCases"]]; }
    else if (!cancel) { const uint8_t keys[]={4,1,0,0,0,0,0,0x61, 4,0,0,0,0,0,0,0x61}; [expected appendBytes:keys length:sizeof(keys)]; }
    [self waitForExpectations:@[reply] timeout:2];
    [self receive:pair[1] matches:expected];
    if (!cancel) [viewer endControlSequence:owner];
    [s stop]; [self waitForExpectations:@[ended] timeout:2]; s.stateHandler=nil; close(pair[1]);
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
        [s cancelNativeGestures];
        XCTAssertTrue([s sendMagnificationEvent:events[1] client:client]); // copied stale update is ignored
        XCTAssertTrue([s releaseMagnification:client]); [self receive:pair[1] matches:[self packet:3]];
        XCTAssertTrue([s releaseMagnification:client]); // repeated cancel sends no extra end
        XCTAssertFalse([s changeMagnification:.05]);
    }
    close(pair[1]); rfbClientCleanup(client);
}
- (void)testFullQueueCanAlwaysRetireAnActiveGesture {
    CompanionVNCSession *s = [self session]; XCTAssertTrue([s beginMagnificationX:1000 y:600]);
    NSArray *copied = [self takeEvents:s]; NSUInteger epoch = [copied[0][@"gestureLifecycleEpoch"] unsignedIntegerValue];
    NSMutableArray *events = [s valueForKey:@"events"];
    for (NSUInteger i=0; i<512; i++) [events addObject:@{@"key":@0x61, @"down":@YES}];
    [s endMagnification]; XCTAssertEqual([[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue], epoch);
    XCTAssertTrue([[copied[0][@"gestureOwner"] valueForKey:@"cancelled"] boolValue]);
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
- (void)testPreciseScrollUsesGoldenPacketsBothAxesAndRetiresCopiedChanges {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair),0);
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3024; client->height=1964;
    CompanionVNCSession *s=[self sessionWithInputOnly:NO]; [s configureClient:client];
    for (NSUInteger repeat=0;repeat<3;repeat++) {
        XCTAssertTrue([s beginScrollX:1000 y:600]); XCTAssertTrue([s changeScrollX:12 y:24]);
        NSArray *events=[self takeEvents:s]; XCTAssertEqual(events.count,2);
        XCTAssertTrue([s sendScrollEvent:events[0] client:client]); [self receive:pair[1] matches:[self packet:0 cases:@"nativeScrollCases"]];
        XCTAssertTrue([s sendScrollEvent:events[1] client:client]); [self receive:pair[1] matches:[self packet:1 cases:@"nativeScrollCases"]];
        XCTAssertTrue([s changeScrollX:-12 y:-24]); NSArray *copied=[self takeEvents:s];
        [s cancelNativeGestures]; XCTAssertTrue([s sendScrollEvent:copied[0] client:client]);
        XCTAssertTrue([s releaseScroll:client]); [self receive:pair[1] matches:[self packet:3 cases:@"nativeScrollCases"]];
        XCTAssertTrue([s releaseScroll:client]); XCTAssertFalse([s changeScrollX:1 y:1]);
    }
    close(pair[1]); rfbClientCleanup(client);
}
- (void)testUnsupportedScrollAndQueuePressureDoNotLoseGestureEndOrSendShortcuts {
    CompanionVNCSession *s=[self session]; [s setValue:@NO forKey:@"appleGestureServer"];
    XCTAssertFalse([s beginScrollX:1000 y:600]); XCTAssertEqual([self takeEvents:s].count,0);
    [s setValue:@YES forKey:@"appleGestureServer"]; XCTAssertTrue([s beginScrollX:1000 y:600]);
    NSArray *copied=[self takeEvents:s]; NSUInteger epoch=[copied[0][@"gestureLifecycleEpoch"] unsignedIntegerValue];
    NSMutableArray *events=[s valueForKey:@"events"];
    for (NSUInteger i=0;i<512;i++) [events addObject:@{@"key":@0x61,@"down":@YES}];
    [s endScroll]; XCTAssertEqual([[s valueForKey:@"gestureLifecycleEpoch"] unsignedIntegerValue],epoch);
    XCTAssertTrue([[copied[0][@"gestureOwner"] valueForKey:@"cancelled"] boolValue]);
    XCTAssertFalse([[s valueForKey:@"queuedScroll"] boolValue]); XCTAssertEqual(events.count,512);
    XCTAssertFalse([s changeScrollX:1 y:1]);
}
- (void)testActualOwnerReleasesPreciseScrollBeforePauseInBothSessionModes {
    for (NSNumber *only in @[@NO,@YES]) {
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
        struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
        int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
        rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=3024; client->height=1964;
        client->supportedMessages.client2server[0] |= 1 << rfbPointerEvent;
        CompanionVNCSession *s=[self sessionWithInputOnly:only.boolValue]; [s setValue:@NO forKey:@"established"];
        [s configureClient:client]; XCTAssertTrue([s allocate:client]);
        // Mirror completed initialization and validated host gesture metadata. Video
        // has backing storage; input-only has only geometry, as in the real owner.
        for (NSString *key in @[@"established",@"inputReady",@"nativeGestureLayout"]) [s setValue:@YES forKey:key];
        // Keep this socket-owner test focused on input, without requiring desktop pixels.
        [s setValue:@YES forKey:@"baselinePresented"]; [s setValue:@NO forKey:@"modeChanged"];
        // The coverage timeout starts well after this bounded pause/stop check.
        [s setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"baselineStarted"];
        [s setValue:@(NSProcessInfo.processInfo.systemUptime) forKey:@"lastFullRefresh"];
        XCTestExpectation *ended=[self expectationWithDescription:@"Scroll owner stops"];
        __weak CompanionVNCSession *weak=s;
        s.stateHandler=^(NSString *state,NSDictionary *stats){if(!weak.running)[ended fulfill];};
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[s processConnectedClient:client];});
        XCTAssertTrue([s beginScrollX:1000 y:600]); [self receive:pair[1] matches:[self packet:0 cases:@"nativeScrollCases"]];
        XCTestExpectation *paused=[self expectationWithDescription:@"Scroll balanced before pause"];
        [s pauseWithCompletion:^{[paused fulfill];}];
        [self receive:pair[1] matches:[self packet:3 cases:@"nativeScrollCases"]];
        uint8_t pointer[6]; XCTAssertEqual(recv(pair[1],pointer,6,MSG_WAITALL),6); XCTAssertEqual(pointer[1],0);
        [self waitForExpectations:@[paused] timeout:1]; XCTAssertTrue(s.running); XCTAssertFalse(s.connected);
        [s stop]; [self waitForExpectations:@[ended] timeout:1]; s.stateHandler=nil; close(pair[1]);
    }
}
- (void)testViewerPreservesMotionUsesScrollSpeedAndCancelsAtControlsInBothModes {
    for (NSNumber *only in @[@NO,@YES]) {
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; viewer.inputOnly=only.boolValue; [viewer loadViewIfNeeded];
        CompanionVNCSession *s=[self sessionWithInputOnly:only.boolValue]; viewer.session=s;
        [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,3024,1964)] forKey:@"activeCrop"];
        [viewer setValue:[NSValue valueWithCGPoint:CGPointMake(1000,600)] forKey:@"cursorPosition"];
        [viewer setValue:@YES forKey:@"cursorPositionKnown"];
        SyntheticScroll *pan=[SyntheticScroll new]; pan.syntheticState=UIGestureRecognizerStateBegan;
        [viewer scrollRemote:pan];
        pan.syntheticState=UIGestureRecognizerStateChanged; pan.delta=CGPointMake(2,5); [viewer scrollRemote:pan];
        viewer.scrollSpeed=2; pan.delta=CGPointMake(-2,-5); [viewer scrollRemote:pan];
        NSArray *events=[self takeEvents:s]; XCTAssertEqual(events.count,3);
        XCTAssertEqualObjects(events[0][@"scrollPhase"],@1); XCTAssertEqualObjects(events[0][@"x"],@1000);
        XCTAssertEqualObjects(events[1][@"dx"],@6); XCTAssertEqualObjects(events[1][@"dy"],@15);
        XCTAssertEqualObjects(events[2][@"dx"],@(-12)); XCTAssertEqualObjects(events[2][@"dy"],@(-30));
        pan.delta=CGPointMake(6000,-6000); [viewer scrollRemote:pan]; events=[self takeEvents:s];
        XCTAssertEqual(events.count,1); XCTAssertEqualObjects(events[0][@"dx"],@2048); XCTAssertEqualObjects(events[0][@"dy"],@(-2048));
        [viewer releasePointer]; pan.delta=CGPointMake(1,1); [viewer scrollRemote:pan]; XCTAssertEqual([self takeEvents:s].count,0);
        pan.syntheticState=UIGestureRecognizerStateBegan; pan.delta=CGPointZero; [viewer scrollRemote:pan];
        viewer.scrollSpeed=1;
        pan.syntheticState=UIGestureRecognizerStateChanged;
        for (NSUInteger i=0;i<4;i++) { pan.delta=CGPointMake(0,.1); [viewer scrollRemote:pan]; }
        pan.syntheticState=UIGestureRecognizerStateEnded; pan.delta=CGPointZero; [viewer scrollRemote:pan]; events=[self takeEvents:s];
        XCTAssertEqual(events.count,3);
        XCTAssertEqualObjects(events[1][@"dy"],@1); // 1.2 total points: carry subpoint samples.
         XCTAssertEqualObjects(events[2][@"scrollPhase"],@4);
        XCTAssertEqualObjects([viewer valueForKey:@"cursorPosition"],[NSValue valueWithCGPoint:CGPointMake(1000,600)]);
    }
}


- (void)testTwoFingerTapUsesIndexedSecondaryClickTargetsAndBalancedButtonGroups {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSDictionary *contract = profile[@"twoFingerTap"];
    XCTAssertEqualObjects(contract[@"touches"], @2); XCTAssertEqualObjects(contract[@"taps"], @1);
    for (NSDictionary *sample in contract[@"cases"]) {
        NSString *mode = sample[@"mode"];
        CompanionVNCViewer *viewer = [CompanionVNCViewer new]; viewer.inputOnly = [mode isEqual:@"inputOnly"]; [viewer loadViewIfNeeded];
        CompanionVNCSession *session = [self sessionWithInputOnly:viewer.inputOnly]; viewer.session = session;
        [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,800,600)] forKey:@"activeCrop"];
        [viewer setValue:[NSValue valueWithCGPoint:CGPointMake([sample[@"cursor"][0] doubleValue], [sample[@"cursor"][1] doubleValue])] forKey:@"cursorPosition"];
        [viewer setValue:@YES forKey:@"cursorPositionKnown"];
        ((UIView *)[viewer valueForKey:@"login"]).hidden = YES;
        [viewer setTrackpadModeEnabled:![mode isEqual:@"pointer"] && ![mode isEqual:@"tabletop"]];
        SecondaryTapSample *tap = [SecondaryTapSample new];
        tap.point = CGPointMake([sample[@"touch"][0] doubleValue], [sample[@"touch"][1] doubleValue]);
        [[viewer valueForKey:[mode isEqual:@"tabletop"] ? @"tabletopPad" : @"canvas"] addGestureRecognizer:tap];
        tap.sampleState = UIGestureRecognizerStateRecognized; [viewer secondaryClickAt:tap];
        NSArray *events = [self takeEvents:session]; XCTAssertEqual(events.count, 2, @"%@", mode);
        for (NSDictionary *event in events) {
            XCTAssertEqualObjects(event[@"x"], sample[@"expected"][0]); XCTAssertEqualObjects(event[@"y"], sample[@"expected"][1]);
            XCTAssertEqualObjects(event[@"motion"], @NO); XCTAssertNil(event[@"key"]);
        }
        XCTAssertEqualObjects(events.firstObject[@"mask"], contract[@"buttonMask"]);
        XCTAssertEqualObjects(events.lastObject[@"mask"], contract[@"releaseMask"]);
        [session setValue:@NO forKey:@"running"];
    }
}
- (void)testSecondaryTapRecognizersKeepScrollingPinchAndDesktopDoubleTapSeparate {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    UITapGestureRecognizer *secondary = [viewer valueForKey:@"secondaryTap"], *smart = [viewer valueForKey:@"smartTap"];
    XCTAssertTrue([secondary.delegate gestureRecognizer:secondary shouldRequireFailureOfGestureRecognizer:smart]);
    XCTAssertEqual(secondary.numberOfTouchesRequired, 2); XCTAssertEqual(secondary.numberOfTapsRequired, 1);
    XCTAssertEqual(smart.numberOfTouchesRequired, 2); XCTAssertEqual(smart.numberOfTapsRequired, 2); XCTAssertTrue(smart.enabled);
    UITapGestureRecognizer *tabletop = [viewer valueForKey:@"tabletopSecondaryTap"];
    XCTAssertEqual(tabletop.numberOfTouchesRequired, 2); XCTAssertEqual(tabletop.numberOfTapsRequired, 1);
    UIPanGestureRecognizer *scroll = [viewer valueForKey:@"remoteScroll"];
    [viewer setTrackpadModeEnabled:YES]; XCTAssertTrue(scroll.enabled); XCTAssertEqual(scroll.minimumNumberOfTouches, 2);
    viewer.inputOnly = YES; XCTAssertFalse([secondary.delegate gestureRecognizer:secondary shouldRequireFailureOfGestureRecognizer:smart]); XCTAssertFalse(smart.enabled); XCTAssertTrue([[viewer valueForKey:@"remotePinch"] isEnabled]);
    viewer.inputOnly = NO; XCTAssertTrue(smart.enabled);
}
- (void)testCancelledSecondaryTapAndUnavailableSessionNeverQueueRemoteClicks {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; viewer.inputOnly = YES; [viewer loadViewIfNeeded];
    CompanionVNCSession *session = [self session]; viewer.session = session;
    [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,800,600)] forKey:@"activeCrop"];
    ((UIView *)[viewer valueForKey:@"login"]).hidden = YES;
    SecondaryTapSample *tap = [SecondaryTapSample new];
    for (NSNumber *state in @[@(UIGestureRecognizerStatePossible), @(UIGestureRecognizerStateCancelled), @(UIGestureRecognizerStateFailed)]) {
        tap.sampleState = state.integerValue; [viewer secondaryClickAt:tap]; XCTAssertEqual([self takeEvents:session].count, 0);
    }
    tap.sampleState = UIGestureRecognizerStateRecognized;
    for (NSString *key in @[@"inputInactive", @"restoreViewportPending", @"checkingResume", @"exited"]) {
        [viewer setValue:@YES forKey:key]; [viewer secondaryClickAt:tap]; XCTAssertEqual([self takeEvents:session].count, 0, @"%@", key);
        [viewer setValue:@NO forKey:key];
    }
    [viewer setValue:@NO forKey:@"foreground"]; [viewer secondaryClickAt:tap]; XCTAssertEqual([self takeEvents:session].count, 0);
    [viewer setValue:@YES forKey:@"foreground"]; [session setValue:@NO forKey:@"inputReady"];
    [viewer secondaryClickAt:tap]; XCTAssertEqual([self takeEvents:session].count, 0);
    [session setValue:@NO forKey:@"running"];
}
- (void)testPendingSecondaryTapIsRetiredByModeChangesControlsAndInactivity {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; viewer.inputOnly = YES; [viewer loadViewIfNeeded];
    CompanionVNCSession *session = [self session]; viewer.session = session;
    SecondaryTapSample *tap = [SecondaryTapSample new]; [viewer setValue:tap forKey:@"secondaryTap"];
    [viewer setTrackpadModeEnabled:YES]; XCTAssertGreaterThan(tap.cancellations, 0);
    NSUInteger before = tap.cancellations; [viewer releasePointer]; XCTAssertGreaterThan(tap.cancellations, before);
    before = tap.cancellations; [viewer becameInactive]; XCTAssertGreaterThan(tap.cancellations, before);
    XCTAssertEqual([self takeEvents:session].count, 0); [session setValue:@NO forKey:@"running"];
}
@end
