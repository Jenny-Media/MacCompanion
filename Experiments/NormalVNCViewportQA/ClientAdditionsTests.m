#import <XCTest/XCTest.h>
#import "CompanionVNCViewer.h"
#import "CompanionVNCTapGesture.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
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
- (BOOL)registerSocket:(int)socket;
- (void)processConnectedClient:(rfbClient *)client;
@end
@interface CompanionVNCViewer (AdditionsTesting)
- (void)frame:(UIImage *)image;
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
- (void)testActualSocketInputOnlySendsInputWithoutRequestingPixelsThenReturnsToDesktop {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1; setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0]; client->width=2; client->height=2; [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0] |= (1<<rfbKeyEvent)|(1<<rfbPointerEvent)|(1<<rfbFramebufferUpdateRequest);
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"]; [session registerSocket:pair[0]];
    session.inputOnly=YES;
    XCTestExpectation *ended=[self expectationWithDescription:@"Owner ended"]; __weak CompanionVNCSession *weak=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){ if (!weak.running) [ended fulfill]; };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{ [session processConnectedClient:client]; });
    XCTAssertTrue([session tryClickX:1 y:1 mask:1]); [session key:97 down:YES]; [session key:97 down:NO];
    uint8_t click[12],keys[16]; XCTAssertEqual(recv(pair[1],click,12,MSG_WAITALL),12); XCTAssertEqual(click[1],1); XCTAssertEqual(click[7],0);
    XCTAssertEqual(recv(pair[1],keys,16,MSG_WAITALL),16); XCTAssertEqual(keys[1],1); XCTAssertEqual(keys[9],0);
    timeout=(struct timeval){.tv_usec=100000}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    uint8_t request[10]; XCTAssertLessThan(recv(pair[1],request,10,0),0); XCTAssertTrue(session.connected);
    session.inputOnly=NO; timeout=(struct timeval){.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10); XCTAssertEqual(request[0],rfbFramebufferUpdateRequest); XCTAssertEqual(request[1],0);
    [session stop]; [self waitForExpectations:@[ended] timeout:2]; session.stateHandler=nil; close(pair[1]);
}
@end
