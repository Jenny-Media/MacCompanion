#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCMenu.h"
#import "CompanionVNCControls.h"
#import "CompanionVNCAppleUpdates.h"
#import <rfb/rfbclient.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>
#import <poll.h>

@interface CompanionVNCSession (CursorStreamingTesting)
- (void)configureClient:(rfbClient *)client;
- (BOOL)configureDesktopUpdates:(rfbClient *)client;
- (BOOL)stopAutomaticUpdates:(rfbClient *)client;
- (BOOL)requestFullDesktop:(rfbClient *)client;
- (BOOL)registerSocket:(int)socket;
- (void)processConnectedClient:(rfbClient *)client;
- (BOOL)servicePendingInput:(rfbClient *)client;
- (void)publishCursor;
- (BOOL)handleServerMessage:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (void)updatedX:(int)x y:(int)y width:(int)width height:(int)height;
@end
@interface CompanionVNCViewer (CursorStreamingTesting)
- (void)frame:(UIImage *)frame;
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known;
- (void)sendPointer:(CGPoint)point mask:(NSInteger)mask;
- (BOOL)clickPointer:(CGPoint)point mask:(NSInteger)mask;
- (void)dragAt:(UIPanGestureRecognizer *)gesture;
- (void)releasePointer;
- (void)performControlAction:(NSDictionary *)action;
- (void)showInputMenu;
- (void)clearCursor;
- (void)invalidateCursorPosition;
- (void)updateCursor;
- (NSDictionary *)cursorDiagnosticFlags;
- (void)updateConnectionChrome;
- (void)clickAt:(UIGestureRecognizer *)gesture;
- (void)selectDisplay:(NSDictionary *)display;
@end
@interface CompanionVNCControls (CursorStreamingTesting)
- (void)open;
@end
@interface CursorOwnershipPan : UIPanGestureRecognizer
@property UIGestureRecognizerState sampleState;
@end
@implementation CursorOwnershipPan
- (UIGestureRecognizerState)state { return self.sampleState; }
- (CGPoint)translationInView:(UIView *)view { return CGPointZero; }
- (CGPoint)velocityInView:(UIView *)view { return CGPointZero; }
- (CGPoint)locationInView:(UIView *)view { return CGPointMake(20,30); }
@end
@interface CursorStreamingTests : XCTestCase
@end
@implementation CursorStreamingTests
- (NSDictionary *)profile {
    NSBundle *bundle=[NSBundle bundleForClass:self.class];
    NSDictionary *index=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:
        [bundle URLForResource:@"manifest" withExtension:@"json"]] options:0 error:NULL];
    NSDictionary *entry=nil;
    for (NSDictionary *item in index[@"fixtures"]) if ([item[@"path"] isEqual:@"vnc-desktop-tunnel-v0.1.json"]) entry=item;
    XCTAssertEqualObjects(entry[@"expect"],@"valid");
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:
        [bundle.resourcePath stringByAppendingPathComponent:entry[@"path"]]] options:0 error:NULL];
}
- (NSData *)bytes:(NSArray *)values {
    NSMutableData *data=[NSMutableData new];
    for(NSNumber *n in values){uint8_t b=n.unsignedCharValue;[data appendBytes:&b length:1];}
    return data;
}
- (rfbClient *)clientFor:(CompanionVNCSession *)session peer:(int *)peer {
    int pair[2];XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1;setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval t={.tv_sec=1};setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&t,sizeof(t));
    rfbClient *client=rfbGetClient(8,3,4);[session configureClient:client];
    client->sock=pair[0];client->width=client->height=100;*peer=pair[1];
    client->supportedMessages.client2server[0]|=(1<<rfbFramebufferUpdateRequest)|(1<<rfbPointerEvent);
    for(NSString *key in @[@"running",@"established",@"inputReady",@"appleGestureServer"]) [session setValue:@YES forKey:key];
    return client;
}
- (void)assertNoBytes:(int)peer {uint8_t b;XCTAssertLessThan(recv(peer,&b,1,MSG_DONTWAIT),0);}
- (NSData *)read:(size_t)length peer:(int)peer {
    NSMutableData *data=[NSMutableData dataWithLength:length];
    XCTAssertEqual(recv(peer,data.mutableBytes,length,MSG_WAITALL),length);return data;
}
- (void)assertControl:(int)peer enabled:(BOOL)enabled width:(int)width height:(int)height {
    uint8_t expected[16];XCTAssertTrue(CompanionVNCAppleUpdatePacket(width,height,enabled,expected));
    XCTAssertEqualObjects([self read:16 peer:peer],[NSData dataWithBytes:expected length:16]);
}
- (void)assertRefresh:(int)peer width:(int)width height:(int)height {
    uint8_t expected[]={3,0,0,0,0,0,width>>8,width&255,height>>8,height&255};
    XCTAssertEqualObjects([self read:10 peer:peer],[NSData dataWithBytes:expected length:10]);
}
- (void)layout:(rfbClient *)client peer:(int)peer valid:(BOOL)valid {
    NSMutableData *body=[[self bytes:[self profile][@"appleAutomaticUpdates"][@"layoutBody"]] mutableCopy];
    if(!valid)((uint8_t *)body.mutableBytes)[1]=99;
    const uint8_t head[]={0,0,0,1,0,0,0,0,0,100,0,100,0,0,4,0x51};
    uint8_t length[]={body.length>>8,body.length&255};
    NSMutableData *packet=[NSMutableData dataWithBytes:head length:sizeof(head)];
    [packet appendBytes:length length:2];[packet appendData:body];
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client));
}
- (void)prepareLayout:(CompanionVNCSession *)session client:(rfbClient *)client peer:(int)peer {
    [self layout:client peer:peer valid:YES];
    uint8_t request[10];XCTAssertEqual(recv(peer,request,10,MSG_WAITALL),10);XCTAssertEqual(request[0],3);
    XCTAssertTrue([session configureDesktopUpdates:client]);[self assertControl:peer enabled:YES width:100 height:100];
}
- (void)finish:(CompanionVNCSession *)session client:(rfbClient *)client peer:(int)peer {
    [session setValue:@NO forKey:@"running"];session.cursorHandler=nil;session.displayLayoutHandler=nil;
    client->frameBuffer=NULL;rfbClientCleanup(client);close(peer);
}
- (void)testClassicControlMatchesGoldenBytesAndRejectsUnboundedGeometry {
    NSDictionary *policy=[self profile][@"appleAutomaticUpdates"];
    XCTAssertEqualObjects(policy[@"requiresMatchingVersion5Layout"],@YES);
    for(NSDictionary *vector in policy[@"cases"]){
        uint8_t packet[16];memset(packet,0xaa,sizeof(packet));
        BOOL valid=CompanionVNCAppleUpdatePacket([vector[@"size"][0] intValue],[vector[@"size"][1] intValue],
            [vector[@"enabled"] boolValue],packet);
        if(vector[@"packet"]==NSNull.null){XCTAssertFalse(valid);XCTAssertEqual(packet[0],0xaa);}
        else{XCTAssertTrue(valid);XCTAssertEqualObjects([NSData dataWithBytes:packet length:16],[self bytes:vector[@"packet"]]);}
    }
    XCTAssertFalse(CompanionVNCAppleUpdatePacket(100,100,YES,NULL));
}
- (void)testSubscriptionNeedsAuthenticatedAppleOwnerAndMatchingLayout {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertNoBytes:peer];
    [self layout:c peer:peer valid:YES];[self read:10 peer:peer];
    for(NSString *key in @[@"appleGestureServer",@"established",@"running"]){
        [s setValue:@NO forKey:key];XCTAssertTrue([s configureDesktopUpdates:c]);[self assertNoBytes:peer];[s setValue:@YES forKey:key];
    }
    c->width=99;XCTAssertTrue([s configureDesktopUpdates:c]);[self assertNoBytes:peer];c->width=100;
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:YES width:100 height:100];
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertNoBytes:peer];
    [self finish:s client:c peer:peer];
}
- (void)assertIncremental:(int)peer width:(int)width height:(int)height {
    uint8_t expected[]={3,1,0,0,0,0,width>>8,width&255,height>>8,height&255};
    XCTAssertEqualObjects([self read:10 peer:peer],[NSData dataWithBytes:expected length:10]);
}
- (void)testAutomaticDeliveryKeepsIncrementalRequestsForQuietCursorOnlyUpdates {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];
    XCTAssertEqualObjects([self profile][@"appleAutomaticUpdates"][@"routinePullRequestsWhileActive"],@YES);
    XCTAssertTrue(SupportsClient2Server(c,rfbFramebufferUpdateRequest));
    const uint8_t empty[]={0,0,0,0};
    XCTAssertEqual(send(peer,empty,sizeof(empty),0),sizeof(empty));
    XCTAssertTrue(HandleRFBServerMessage(c));
    // Check availability first so the original regression fails without blocking.
    uint8_t request[10];ssize_t count=recv(peer,request,sizeof(request),MSG_DONTWAIT);
    XCTAssertEqual(count,10);
    if(count==10) {
        const uint8_t expected[]={3,1,0,0,0,0,0,100,0,100};
        XCTAssertEqualObjects([NSData dataWithBytes:request length:10],[NSData dataWithBytes:expected length:10]);
    }
    [self assertNoBytes:peer];
    [self finish:s client:c peer:peer];
}
- (void)testSameGeometryLayoutRearmsWithoutSuppressingIncrementalOrFullRefresh {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];
    XCTAssertTrue(SupportsClient2Server(c,rfbFramebufferUpdateRequest));
    XCTAssertTrue(SendIncrementalFramebufferUpdateRequest(c));[self assertIncremental:peer width:100 height:100];
    XCTAssertTrue([s requestFullDesktop:c]);[self assertRefresh:peer width:100 height:100];
    XCTAssertTrue(SupportsClient2Server(c,rfbFramebufferUpdateRequest));
    [self layout:c peer:peer valid:YES];[self assertIncremental:peer width:100 height:100];
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:YES width:100 height:100];
    XCTAssertEqualObjects(s.diagnosticCounters[@"automaticUpdateStarts"],@2);
    [self layout:c peer:peer valid:NO];[self assertIncremental:peer width:100 height:100];
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:NO width:100 height:100];
    XCTAssertTrue(SupportsClient2Server(c,rfbFramebufferUpdateRequest));
    XCTAssertEqualObjects(s.diagnosticCounters[@"automaticDesktopUpdates"],@NO);
    [self finish:s client:c peer:peer];
}
- (void)testInputOnlyDisablesAutomaticPixelsAndCapabilityRefreshStaysEmpty {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    // The real Desktop handshake admits framebuffer geometry before an established
    // owner can switch back from input-only; client dimensions alone do not do so.
    XCTAssertTrue([s allocate:c]);XCTAssertTrue(s.desktopFramebufferAvailable);
    [self prepareLayout:s client:c peer:peer];s.inputOnly=YES;XCTAssertTrue(s.inputOnly);
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:NO width:100 height:100];
    XCTAssertTrue([s requestFullDesktop:c]);[self assertNoBytes:peer];
    c->supportedMessages.client2server[0]|=1<<rfbFramebufferUpdateRequest;
    const uint8_t empty[]={0,0,0,0};XCTAssertEqual(send(peer,empty,sizeof(empty),0),sizeof(empty));
    XCTAssertTrue(HandleRFBServerMessage(c));
    const uint8_t expected[]={3,1,0,0,0,0,0,0,0,0};
    XCTAssertEqualObjects([self read:10 peer:peer],[NSData dataWithBytes:expected length:10]);
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertNoBytes:peer];
    [self layout:c peer:peer valid:YES];[self assertNoBytes:peer];
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertNoBytes:peer];
    s.inputOnly=NO;XCTAssertFalse(s.inputOnly);
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:YES width:100 height:100];
    [self finish:s client:c peer:peer];
}
- (void)testPauseDisablesBeforeCompletionAndResumeRearmsTheRetainedOwner {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];XCTAssertTrue([s registerSocket:c->sock]);
    c->supportedMessages.client2server[0]|=1<<rfbKeyEvent;
    XCTAssertTrue(SendKeyEvent(c,0x61,TRUE));[self read:8 peer:peer];
    [[s valueForKey:@"heldKeys"] addObject:@0x61];
    XCTestExpectation *paused=[self expectationWithDescription:@"paused after disable"];
    [s pauseWithCompletion:^{[paused fulfill];}];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[s processConnectedClient:c];});
    const uint8_t keyUp[]={4,0,0,0,0,0,0,0x61};
    XCTAssertEqualObjects([self read:8 peer:peer],[NSData dataWithBytes:keyUp length:8]);
    NSData *release=[self read:6 peer:peer];XCTAssertEqual(((const uint8_t *)release.bytes)[0],rfbPointerEvent);
    [self assertControl:peer enabled:NO width:100 height:100];
    [self waitForExpectations:@[paused] timeout:1];[self assertNoBytes:peer];
    XCTAssertTrue(s.established);XCTAssertFalse(s.connected);
    [s resume];[self assertControl:peer enabled:YES width:100 height:100];[self assertRefresh:peer width:100 height:100];
    XCTAssertFalse(s.desktopFrameReady);XCTAssertFalse(s.connected);
    XCTestExpectation *ended=[self expectationWithDescription:@"closed"];
    s.stateHandler=^(NSString *state,NSDictionary *stats){if([state isEqual:@"Disconnected"])[ended fulfill];};
    [s stop];[self read:6 peer:peer];[self assertControl:peer enabled:NO width:100 height:100];
    [self waitForExpectations:@[ended] timeout:2];s.stateHandler=nil;close(peer);
}
- (void)testFramebufferResizeDisablesOldRegionUntilMatchingLayoutArrives {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];c->width=101;
    XCTAssertTrue([s allocate:c]);XCTAssertFalse(s.desktopFrameReady);
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:NO width:100 height:100];
    NSMutableData *body=[[self bytes:[self profile][@"appleAutomaticUpdates"][@"layoutBody"]] mutableCopy];
    uint8_t *b=body.mutableBytes;b[3]=101;b[7]=101;b[55]=101;
    const uint8_t head[]={0,0,0,1,0,0,0,0,0,101,0,100,0,0,4,0x51,0,76};
    NSMutableData *packet=[NSMutableData dataWithBytes:head length:sizeof(head)];[packet appendData:body];
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);XCTAssertTrue(HandleRFBServerMessage(c));
    [self read:10 peer:peer];XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:YES width:101 height:100];
    XCTAssertTrue([s requestFullDesktop:c]);[self assertRefresh:peer width:101 height:100];
    XCTAssertFalse(s.connected);XCTAssertFalse(s.desktopFrameReady);
    [self finish:s client:c peer:peer];
}
- (void)testStreamedStoresAndSelectionsChangeTheVisibleCursorWithoutVideoDamage {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];
    [s setValue:@YES forKey:@"baselinePresented"];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new];[viewer loadViewIfNeeded];viewer.session=s;
    viewer.view.frame=CGRectMake(0,0,440,956);
    UIImage *frame=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100,100)] imageWithActions:^(UIGraphicsImageRendererContext *ctx){
        [UIColor.systemBlueColor setFill];UIRectFill(CGRectMake(0,0,100,100));
    }];
    [viewer frame:frame];[(UIView *)[viewer valueForKey:@"login"] setHidden:YES];[viewer updateConnectionChrome];[viewer.view layoutIfNeeded];[viewer sendPointer:CGPointMake(50,50) mask:0];
    NSArray *vectors=[self profile][@"appleCursorCases"];
    UIImage *first=nil;
    for(NSUInteger i=0;i<3;i++) {
        NSDictionary *vector=vectors[i==1?1:0];
        NSMutableArray *payload=[vector[@"payload"] mutableCopy];
        if(i==1)payload[3]=@18;
        if(i==2)payload=[@[@0,@0,@0,@17,@0,@0,@0,@0] mutableCopy];
        uint8_t head[]={0,0,0,1,0,1,0,0,0,2,0,1,0,0,4,0x50};
        if(i==2)memset(head+4,0,8);
        NSMutableData *packet=[NSMutableData dataWithBytes:head length:sizeof(head)];[packet appendData:[self bytes:payload]];
        XCTestExpectation *shown=[self expectationWithDescription:@"new native shape"];
        s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
            [viewer receivedCursor:image hotspot:hotspot position:position known:known];[shown fulfill];
        };
        XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);XCTAssertTrue(HandleRFBServerMessage(c));
        [s publishCursor];[self waitForExpectations:@[shown] timeout:1];
        UIImage *shape=[viewer valueForKey:@"remoteCursorImage"];XCTAssertNotNil(shape);
        NSData *pixels=CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(shape.CGImage)));
        XCTAssertEqualObjects(pixels,[self bytes:vector[@"rgba"]]);
        XCTAssertFalse([(UIView *)[viewer valueForKey:@"cursorIndicator"] isHidden]);
        XCTAssertTrue([(CALayer *)[viewer valueForKey:@"fallbackCursor"] isHidden]);
        if(i==0)first=shape;else if(i==1)XCTAssertFalse(first==shape);else XCTAssertTrue(first==shape);
        XCTAssertEqualObjects([s valueForKey:@"updates"],@0);
        [self assertIncremental:peer width:100 height:100];
    }
    XCTAssertEqualObjects(s.diagnosticCounters[@"appleCursorSelections"],@1);
    XCTAssertEqualObjects(s.diagnosticCounters[@"appleCursorStores"],@2);
    s.cursorHandler=nil;[viewer stopViewer];[self finish:s client:c peer:peer];
}
// Use indexed cursor payloads over the real parser; no recorded screen data.
- (NSData *)cursorRectangle:(NSUInteger)index identifier:(uint32_t)identifier {
    NSMutableData *data=[NSMutableData new];
    uint8_t rect[]={0,1,0,0,0,2,0,1,0,0,4,0x50};
    if(index==NSNotFound) memset(rect,0,8);
    [data appendBytes:rect length:sizeof(rect)];
    NSMutableData *payload=index==NSNotFound ? [NSMutableData dataWithLength:8]
        : [[self bytes:[self profile][@"appleCursorCases"][index][@"payload"]] mutableCopy];
    uint32_t network=htonl(identifier); memcpy(payload.mutableBytes,&network,4);
    [data appendData:payload]; return data;
}
- (void)primeCursorCache:(CompanionVNCSession *)session client:(rfbClient *)client peer:(int)peer {
    for(NSUInteger i=0;i<2;i++) {
        uint8_t head[]={0,0,0,1};NSMutableData *message=[NSMutableData dataWithBytes:head length:4];
        [message appendData:[self cursorRectangle:i identifier:(uint32_t)(17+i)]];
        XCTestExpectation *stored=[self expectationWithDescription:@"Initial cached cursor"];
        session.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){XCTAssertNotNil(image);[stored fulfill];};
        XCTAssertEqual(send(peer,message.bytes,message.length,0),message.length);
        XCTAssertTrue(HandleRFBServerMessage(client));[session publishCursor];
        [self waitForExpectations:@[stored] timeout:1];[self assertIncremental:peer width:100 height:100];
    }
    session.cursorHandler=nil;
}
- (void)testTrackpadCursorSelectionAppearsBeforeFollowingDesktopRectangleCompletes {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    XCTAssertTrue([s allocate:c]);[self prepareLayout:s client:c peer:peer];[s setValue:@YES forKey:@"baselinePresented"];
    // This test starts after a completed baseline; allocation retired input.
    [s setValue:@YES forKey:@"inputReady"];[s setValue:@NO forKey:@"awaitingResumeFrame"];
    [self primeCursorCache:s client:c peer:peer];
    CompanionVNCViewer *viewer=[CompanionVNCViewer new];[viewer loadViewIfNeeded];viewer.session=s;
    [viewer setValue:@YES forKey:@"trackpadMode"];viewer.view.frame=CGRectMake(0,0,440,956);
    UIImage *frame=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100,100)] imageWithActions:^(UIGraphicsImageRendererContext *ctx){
        [UIColor.systemBlueColor setFill];UIRectFill(CGRectMake(0,0,100,100));
    }];
    [viewer frame:frame];[(UIView *)[viewer valueForKey:@"login"] setHidden:YES];[viewer updateConnectionChrome];[viewer.view layoutIfNeeded];[viewer sendPointer:CGPointMake(50,50) mask:0];
    uint8_t head[]={0,0,0,2},raw[]={0,0,0,0,0,1,0,1,0,0,0,0};
    NSMutableData *message=[NSMutableData dataWithBytes:head length:4];
    [message appendData:[self cursorRectangle:NSNotFound identifier:17]];
    [message appendBytes:raw length:sizeof(raw)]; // Withhold this rectangle's pixels.
    XCTestExpectation *changed=[self expectationWithDescription:@"Cursor does not wait for desktop pixels"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        [viewer receivedCursor:image hotspot:hotspot position:position known:known];[changed fulfill];
    };
    XCTAssertEqual(send(peer,message.bytes,message.length,0),message.length);
    XCTestExpectation *parsed=[self expectationWithDescription:@"Desktop update completed after release"];
    dispatch_semaphore_t completed=dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL ok=HandleRFBServerMessage(c);dispatch_semaphore_signal(completed);
        dispatch_async(dispatch_get_main_queue(),^{XCTAssertTrue(ok);[parsed fulfill];});
    });
    [self waitForExpectations:@[changed] timeout:1];
    XCTAssertNotEqual(dispatch_semaphore_wait(completed,DISPATCH_TIME_NOW),0);
    UIImage *shape=[viewer valueForKey:@"remoteCursorImage"];XCTAssertNotNil(shape);
    if(shape) {
        NSData *pixels=CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(shape.CGImage)));
        XCTAssertEqualObjects(pixels,[self bytes:[self profile][@"appleCursorCases"][0][@"rgba"]]);
    }
    XCTAssertFalse([(UIView *)[viewer valueForKey:@"cursorIndicator"] isHidden]);
    s.cursorHandler=nil;uint8_t pixel[4]={0};XCTAssertEqual(send(peer,pixel,4,0),4);
    [self waitForExpectations:@[parsed] timeout:2];
    [viewer stopViewer];[self finish:s client:c peer:peer];
}
- (void)testCursorBurstPublishesLatestSelectionWithoutQueuingStaleImages {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
    uint8_t head[]={0,0,0,2};NSMutableData *message=[NSMutableData dataWithBytes:head length:4];
    [message appendData:[self cursorRectangle:NSNotFound identifier:17]];
    [message appendData:[self cursorRectangle:NSNotFound identifier:18]];
    __block NSUInteger deliveries=0;
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        deliveries++;XCTAssertNotNil(image);
        if(image) {
            NSData *pixels=CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage)));
            XCTAssertEqualObjects(pixels,[self bytes:[self profile][@"appleCursorCases"][1][@"rgba"]]);
        }
    };
    XCTAssertEqual(send(peer,message.bytes,message.length,0),message.length);
    XCTAssertTrue(HandleRFBServerMessage(c));[s publishCursor];
    XCTestExpectation *drained=[self expectationWithDescription:@"Drain native cursor presentation"];
    dispatch_async(dispatch_get_main_queue(),^{[drained fulfill];});[self waitForExpectations:@[drained] timeout:1];
    XCTAssertEqual(deliveries,1);[self finish:s client:c peer:peer];
}
- (void)testDecodedCursorCannotAppearAfterPauseRetiresItsPresentation {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){XCTFail(@"Paused cursor must remain hidden");};
    uint8_t head[]={0,0,0,1};NSMutableData *message=[NSMutableData dataWithBytes:head length:4];
    [message appendData:[self cursorRectangle:NSNotFound identifier:17]];
    XCTAssertEqual(send(peer,message.bytes,message.length,0),message.length);XCTAssertTrue(HandleRFBServerMessage(c));
    [s pauseWithCompletion:nil];
    XCTestExpectation *drained=[self expectationWithDescription:@"Drain retired cursor presentation"];
    dispatch_async(dispatch_get_main_queue(),^{[drained fulfill];});[self waitForExpectations:@[drained] timeout:1];
    [self finish:s client:c peer:peer];
}

- (void)testClientRequestsAppleAndStandardCursorPositionReports {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    // These bits are normally established by the RFB handshake.
    c->supportedMessages.client2server[rfbSetPixelFormat/8]|=1<<(rfbSetPixelFormat%8);
    c->supportedMessages.client2server[rfbSetEncodings/8]|=1<<(rfbSetEncodings%8);
    XCTAssertTrue(SetFormatAndEncodings(c));[self read:sz_rfbSetPixelFormatMsg peer:peer];
    NSData *header=[self read:sz_rfbSetEncodingsMsg peer:peer];const uint8_t *bytes=header.bytes;
    NSUInteger count=((NSUInteger)bytes[2]<<8)|bytes[3];XCTAssertLessThan(count,128);
    NSMutableArray *encodings=[NSMutableArray new];
    for(NSUInteger i=0;i<count;i++) {
        NSData *value=[self read:4 peer:peer];uint32_t number=0;memcpy(&number,value.bytes,4);
        [encodings addObject:@((int32_t)ntohl(number))];
    }
    for(NSNumber *expected in [self profile][@"cursorNegotiationEncodings"]) XCTAssertTrue([encodings containsObject:expected],@"Missing %@",expected);
    [self finish:s client:c peer:peer];
}

- (void)testAppleHostPositionMovesTrackpadCursorWithoutDesktopDamage {
    for(NSDictionary *vector in [self profile][@"appleCursorPosition"][@"cases"]) {
        CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
        [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
        CompanionVNCViewer *viewer=[self ownershipViewer:s];
        XCTAssertEqualObjects([self profile][@"cursorPositionOwnership"][@"hostPositionFollowing"],@"automatic");
        NSArray *r=vector[@"rect"];uint16_t x=[r[0] unsignedShortValue],y=[r[1] unsignedShortValue];
        uint8_t packet[]={0,0,0,1,x>>8,x&255,y>>8,y&255,0,0,0,0,0,0,4,0x4c};
        XCTestExpectation *moved=[self expectationWithDescription:vector[@"name"]];
        s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
            XCTAssertNotNil(image);XCTAssertEqual(known,[vector[@"known"] boolValue]);
            [viewer receivedCursor:image hotspot:hotspot position:position known:known];[moved fulfill];
        };
        XCTAssertEqual(send(peer,packet,sizeof(packet),0),sizeof(packet));XCTAssertTrue(HandleRFBServerMessage(c));
        [self waitForExpectations:@[moved] timeout:1];
        if([vector[@"known"] boolValue]) {
            CGPoint position=[[viewer valueForKey:@"cursorPosition"] CGPointValue];
            XCTAssertEqual(position.x,x);XCTAssertEqual(position.y,y);
            XCTAssertFalse([(UIView *)[viewer valueForKey:@"cursorIndicator"] isHidden]);
        }
        XCTAssertEqualObjects(s.diagnosticCounters[@"cursorPositionUpdates"],@1);
        XCTAssertEqualObjects([s valueForKey:@"updates"],@0);
        [viewer stopViewer];[self finish:s client:c peer:peer];
    }
}

- (CompanionVNCViewer *)ownershipViewer:(CompanionVNCSession *)session {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new];[viewer loadViewIfNeeded];viewer.session=session;
    [viewer setValue:@YES forKey:@"trackpadMode"];viewer.view.frame=CGRectMake(0,0,440,956);
    [session setValue:@YES forKey:@"baselinePresented"];
    UIImage *frame=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100,100)] imageWithActions:^(UIGraphicsImageRendererContext *ctx){
        [UIColor.systemBlueColor setFill];UIRectFill(CGRectMake(0,0,100,100));
    }];
    [viewer frame:frame];
    // This fixture replaces the viewer's session instead of running its login
    // callbacks. Mirror the visible connected Desktop those callbacks produce.
    [(UIView *)[viewer valueForKey:@"login"] setHidden:YES];[viewer updateConnectionChrome];
    [viewer.view layoutIfNeeded];return viewer;
}
- (CGPoint)ownershipPoint:(NSString *)key {
    NSArray *p=[self profile][@"cursorPositionOwnership"][key];return CGPointMake([p[0] doubleValue],[p[1] doubleValue]);
}
- (NSData *)positionPacket:(CGPoint)point {
    uint16_t x=point.x,y=point.y;
    uint8_t packet[]={0,0,0,1,x>>8,x&255,y>>8,y&255,0,0,0,0,0,0,4,0x4c};
    return [NSData dataWithBytes:packet length:sizeof(packet)];
}
- (void)receivePacket:(NSData *)packet client:(rfbClient *)client peer:(int)peer {
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);XCTAssertTrue(HandleRFBServerMessage(client));
    [self assertIncremental:peer width:100 height:100];
}
- (void)testShapeOnlyUpdateCannotReplayHostPositionOverNewLocalTrackpadMovement {
    XCTAssertEqualObjects([self profile][@"cursorPositionOwnership"][@"shapeOnlyReplaysCachedPosition"],@NO);
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
    CompanionVNCViewer *viewer=[self ownershipViewer:s];
    XCTestExpectation *initial=[self expectationWithDescription:@"Fresh host coordinate"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        XCTAssertTrue(known);[viewer receivedCursor:image hotspot:hotspot position:position known:known];[initial fulfill];
    };
    [self receivePacket:[self positionPacket:[self ownershipPoint:@"firstHostPoint"]] client:c peer:peer];
    [self waitForExpectations:@[initial] timeout:1];
    CGPoint local=[self ownershipPoint:@"localInputPoint"];[viewer sendPointer:local mask:0];
    XCTestExpectation *shape=[self expectationWithDescription:@"New shape without cached-coordinate replay"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        XCTAssertFalse(known);[viewer receivedCursor:image hotspot:hotspot position:position known:known];[shape fulfill];
    };
    uint8_t head[]={0,0,0,1};NSMutableData *message=[NSMutableData dataWithBytes:head length:4];
    [message appendData:[self cursorRectangle:NSNotFound identifier:18]];
    [self receivePacket:message client:c peer:peer];[self waitForExpectations:@[shape] timeout:1];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    UIImage *image=[viewer valueForKey:@"remoteCursorImage"];XCTAssertNotNil(image);
    if(image) XCTAssertEqualObjects(CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(image.CGImage))),
                                  [self bytes:[self profile][@"appleCursorCases"][1][@"rgba"]]);
    [viewer stopViewer];[self finish:s client:c peer:peer];
}
- (void)testQueuedHostReportUpdatesMacCursorWithoutMovingLocalAim {
    XCTAssertEqualObjects([self profile][@"cursorPositionOwnership"][@"olderMessageRevisionMayReconcile"],@NO);
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
    CompanionVNCViewer *viewer=[self ownershipViewer:s];
    XCTestExpectation *delivered=[self expectationWithDescription:@"Shape survives stale-position suppression"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        XCTAssertFalse(known);XCTAssertNotNil(image);[viewer receivedCursor:image hotspot:hotspot position:position known:known];[delivered fulfill];
    };
    [self receivePacket:[self positionPacket:[self ownershipPoint:@"firstHostPoint"]] client:c peer:peer];
    CGPoint local=[self ownershipPoint:@"localInputPoint"];[viewer sendPointer:local mask:0];
    [self waitForExpectations:@[delivered] timeout:1];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    [viewer stopViewer];[self finish:s client:c peer:peer];
}

- (void)drainCursorQueue {
    XCTestExpectation *drained=[self expectationWithDescription:@"Main cursor delivery drained"];
    dispatch_async(dispatch_get_main_queue(),^{[drained fulfill];});[self waitForExpectations:@[drained] timeout:1];
}
- (NSData *)shapeSelection:(uint32_t)identifier {
    uint8_t head[]={0,0,0,1};NSMutableData *packet=[NSMutableData dataWithBytes:head length:4];
    [packet appendData:[self cursorRectangle:NSNotFound identifier:identifier]];return packet;
}
- (void)testCoalescedShapePreservesFreshPositionOnceInEitherRectangleOrder {
    XCTAssertEqualObjects([self profile][@"cursorPositionOwnership"][@"coalescedShapePreservesUndeliveredFreshPosition"],@YES);
    for(NSNumber *positionFirst in @[@YES,@NO]) {
        CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
        [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
        CGPoint host=[self ownershipPoint:@"nextHostPoint"];
        NSData *pos=[self positionPacket:host];pos=[pos subdataWithRange:NSMakeRange(4,pos.length-4)];
        NSData *shape=[self cursorRectangle:NSNotFound identifier:17];
        uint8_t head[]={0,0,0,2};NSMutableData *packet=[NSMutableData dataWithBytes:head length:4];
        [packet appendData:positionFirst.boolValue?pos:shape];[packet appendData:positionFirst.boolValue?shape:pos];
        __block NSUInteger deliveries=0;
        s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
            deliveries++;XCTAssertTrue(known);XCTAssertTrue(CGPointEqualToPoint(position,host));XCTAssertNotNil(image);
        };
        [self receivePacket:packet client:c peer:peer];[self drainCursorQueue];XCTAssertEqual(deliveries,1);
        s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){deliveries++;XCTAssertFalse(known);};
        [self receivePacket:[self shapeSelection:18] client:c peer:peer];[self drainCursorQueue];XCTAssertEqual(deliveries,2);
        XCTAssertEqualObjects(s.diagnosticCounters[@"cursorPositionPublications"],@1);
        [self finish:s client:c peer:peer];
    }
}
- (void)testPersistentCursorProtectsTouchAndFollowsFreshIdleHostMovement {
    NSDictionary *policy=[self profile][@"cursorPositionOwnership"];
    XCTAssertEqualObjects(policy[@"hostPositionFollowing"],@"automatic");
    XCTAssertEqualObjects(policy[@"displayedHotspotIsNextClickTarget"],@YES);
    for(NSNumber *trackpad in @[@YES,@NO]) {
        CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
        [self prepareLayout:session client:client peer:peer];[self primeCursorCache:session client:client peer:peer];
        CompanionVNCViewer *viewer=[self ownershipViewer:session];[viewer setValue:trackpad forKey:@"trackpadMode"];
        session.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint point,BOOL known){[viewer receivedCursor:image hotspot:hotspot position:point known:known];};
        CGPoint local=[self ownershipPoint:@"localInputPoint"];
        for(NSInteger repeat=0;repeat<3;repeat++) {
            [viewer sendPointer:local mask:0];session.localPointerInteractionActive=YES;
            [self receivePacket:[self positionPacket:CGPointMake(75,60)] client:client peer:peer];[self drainCursorQueue];
            [self receivePacket:[self shapeSelection:17+repeat%2] client:client peer:peer];[self drainCursorQueue];
            XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
            XCTAssertNotNil([viewer valueForKey:@"remoteCursorImage"]);
            [viewer releasePointer];[viewer setValue:@0 forKey:@"lastLocalPointerInputAt"];CGPoint host=CGPointMake(90+repeat,70+repeat);
            [self receivePacket:[self positionPacket:host] client:client peer:peer];[self drainCursorQueue];
            XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],host));
            XCTAssertFalse(((UIView *)[viewer valueForKey:@"cursorIndicator"]).hidden);
        }
        [viewer stopViewer];[self finish:session client:client peer:peer];
    }
}
- (void)testHostPositionAtEndOfPartialDesktopReadCannotUndoInputMadeDuringThatRead {
    XCTAssertEqualObjects([self profile][@"cursorPositionOwnership"][@"olderMessageRevisionMayReconcile"],@NO);
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    XCTAssertTrue([s allocate:c]);[self prepareLayout:s client:c peer:peer];
    [s setValue:@YES forKey:@"inputReady"];[s setValue:@NO forKey:@"awaitingResumeFrame"];
    [self primeCursorCache:s client:c peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:s];
    uint8_t head[]={0,0,0,3},raw[]={0,0,0,0,0,1,0,1,0,0,0,0};
    NSMutableData *prefix=[NSMutableData dataWithBytes:head length:4];
    [prefix appendData:[self cursorRectangle:NSNotFound identifier:17]];[prefix appendBytes:raw length:sizeof(raw)];
    XCTestExpectation *started=[self expectationWithDescription:@"Read reached first cursor before blocked pixels"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){XCTAssertFalse(known);[started fulfill];};
    XCTAssertEqual(send(peer,prefix.bytes,prefix.length,0),prefix.length);
    XCTestExpectation *finished=[self expectationWithDescription:@"Partial message finished"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL ok=[s handleServerMessage:c];
        dispatch_async(dispatch_get_main_queue(),^{XCTAssertTrue(ok);[finished fulfill];});
    });
    [self waitForExpectations:@[started] timeout:1];
    CGPoint local=[self ownershipPoint:@"localInputPoint"];[viewer sendPointer:local mask:0];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        XCTAssertFalse(known);[viewer receivedCursor:image hotspot:hotspot position:position known:known];
    };
    uint8_t pixel[4]={0};NSMutableData *tail=[NSMutableData dataWithBytes:pixel length:4];
    NSData *pos=[self positionPacket:[self ownershipPoint:@"firstHostPoint"]];[tail appendData:[pos subdataWithRange:NSMakeRange(4,pos.length-4)]];
    XCTAssertEqual(send(peer,tail.bytes,tail.length,0),tail.length);
    [self waitForExpectations:@[finished] timeout:2];[self drainCursorQueue];[self assertIncremental:peer width:100 height:100];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    XCTAssertEqualObjects(s.diagnosticCounters[@"cursorPositionsSuppressed"],@1);
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){XCTAssertTrue(known);};
    NSData *next=[self positionPacket:[self ownershipPoint:@"nextHostPoint"]];
    XCTAssertEqual(send(peer,next.bytes,next.length,0),next.length);XCTAssertTrue([s handleServerMessage:c]);
    [self assertIncremental:peer width:100 height:100];[self drainCursorQueue];
    [viewer stopViewer];[self finish:s client:c peer:peer];
}
- (void)testIncomingHostObservationDoesNotAcknowledgeAcceptedOrRejectedClicks {
    for(NSNumber *accepted in @[@NO,@YES]) {
        CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
        [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
        s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){XCTAssertEqual(known,!accepted.boolValue);};
        [self receivePacket:[self positionPacket:[self ownershipPoint:@"firstHostPoint"]] client:c peer:peer];
        [s setValue:accepted forKey:@"inputReady"];
        CGPoint local=[self ownershipPoint:@"localInputPoint"];XCTAssertEqual([s tryClickX:local.x y:local.y mask:1],accepted.boolValue);
        [s setValue:@YES forKey:@"inputReady"];[self drainCursorQueue];[self finish:s client:c peer:peer];
    }
}

- (void)testPipelineSeparatesBlockedReadWallTimeFromWorkerCPUAndInitialBaseline {
    NSDictionary *policy=[self profile][@"cursorPipelineDiagnostics"];
    XCTAssertEqualObjects(policy[@"workerCPUSeparateFromWall"],@YES);
    XCTAssertEqualObjects(policy[@"postBaselineSeparateFromInitialLoad"],@YES);
    XCTAssertEqualObjects(policy[@"recordsCoordinatesOrPayload"],@NO);
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    XCTAssertTrue([s allocate:c]);[self prepareLayout:s client:c peer:peer];
    const uint8_t prefix[]={0,0,0,1,0,0,0,0,0,1,0,1,0,0,0,0};
    XCTAssertEqual(send(peer,prefix,sizeof(prefix),0),sizeof(prefix));
    XCTestExpectation *finished=[self expectationWithDescription:@"Delayed pixel completed"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        BOOL ok=[s handleServerMessage:c];dispatch_async(dispatch_get_main_queue(),^{XCTAssertTrue(ok);[finished fulfill];});
    });
    // Observe the actual read boundary before starting the deliberate stall.
    XCTestExpectation *reading=[self expectationWithDescription:@"Read started"];
    __block void (^poll)(NSUInteger);
    poll=^(NSUInteger attempts){
        if ([s.diagnosticCounters[@"pipeline"][@"messageReadActive"] boolValue]) { [reading fulfill];return; }
        if (!attempts) { XCTFail(@"Reader did not start");[reading fulfill];return; }
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW,5*NSEC_PER_MSEC),dispatch_get_main_queue(),^{poll(attempts-1);});
    };
    poll(100);[self waitForExpectations:@[reading] timeout:1];poll=nil;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,150*NSEC_PER_MSEC),dispatch_get_main_queue(),^{
        const uint8_t pixel[4]={0};XCTAssertEqual(send(peer,pixel,4,0),4);
    });
    [self waitForExpectations:@[finished] timeout:2];[self assertIncremental:peer width:100 height:100];
    NSDictionary *stats=s.diagnosticCounters,*pipeline=stats[@"pipeline"];
    XCTAssertGreaterThanOrEqual([stats[@"serverMessageTotalMS"] doubleValue],140);
    XCTAssertEqualObjects(pipeline[@"workerCPUSamples"],@1);
    XCTAssertLessThan([pipeline[@"workerCPUTotalMS"] doubleValue],[stats[@"serverMessageTotalMS"] doubleValue]*.75);
    XCTAssertEqualObjects(pipeline[@"pixelMessages"],@1);XCTAssertEqualObjects(pipeline[@"interactiveMessages"],@0);
    [self finish:s client:c peer:peer];
}
- (void)testPipelineCountsUnreadMessageBytesWithoutTreatingThemAsReportAge {
    XCTAssertEqualObjects([self profile][@"cursorPipelineDiagnostics"][@"unreadBytesAreNotReportAge"],@YES);
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];
    NSData *one=[self positionPacket:[self ownershipPoint:@"firstHostPoint"]];
    NSData *two=[self positionPacket:[self ownershipPoint:@"nextHostPoint"]];
    NSMutableData *batch=[one mutableCopy];[batch appendData:two];
    XCTAssertEqual(send(peer,batch.bytes,batch.length,0),batch.length);XCTAssertTrue([s handleServerMessage:c]);
    [self assertIncremental:peer width:100 height:100];
    NSDictionary *first=s.diagnosticCounters[@"pipeline"];
    XCTAssertGreaterThanOrEqual([first[@"unreadBytesLatest"] unsignedIntegerValue],two.length);
    [s setValue:@YES forKey:@"baselinePresented"];XCTAssertTrue([s handleServerMessage:c]);
    [self assertIncremental:peer width:100 height:100];
    NSDictionary *last=s.diagnosticCounters[@"pipeline"];
    XCTAssertEqualObjects(last[@"unreadBytesLatest"],@0);XCTAssertEqualObjects(last[@"cursorOnlyMessages"],@2);
    XCTAssertEqualObjects(last[@"workerCPUSamples"],@2);XCTAssertEqualObjects(last[@"interactiveMessages"],@1);
    XCTAssertTrue([NSJSONSerialization isValidJSONObject:last]);
    for(id value in last.allValues) XCTAssertTrue([value isKindOfClass:NSNumber.class]);
    [self drainCursorQueue];[self finish:s client:c peer:peer];
}

- (void)testActiveControlAllowsHostPositionImmediatelyAfterSendingPixels {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    XCTAssertTrue([s allocate:c]);rfbClientSetUpdateRect(c,NULL);[self layout:c peer:peer valid:YES];[self assertIncremental:peer width:100 height:100];
    XCTAssertTrue([s configureDesktopUpdates:c]);NSData *control=[self read:16 peer:peer];
    XCTAssertEqualObjects(control,[self bytes:[self profile][@"appleAutomaticUpdates"][@"cases"][2][@"packet"]]);
    uint32_t networkPeriod;memcpy(&networkPeriod,(const uint8_t *)control.bytes+4,4);
    uint32_t period=ntohl(networkPeriod);
    // Source-derived host model: its position check follows the pixel send that
    // resets last-send time. A positive period makes the position ineligible here.
    // Earlier fake peers sent positions regardless of the control and missed this regression.
    BOOL hostPositionEligible=(period==0);
    uint8_t head[]={0,0,0,hostPositionEligible?2:1};
    uint8_t pixel[]={0,0,0,0,0,1,0,1,0,0,0,0,1,2,3,255};
    NSMutableData *packet=[NSMutableData dataWithBytes:head length:4];[packet appendBytes:pixel length:sizeof(pixel)];
    if (hostPositionEligible) {
        NSData *position=[self positionPacket:[self ownershipPoint:@"nextHostPoint"]];
        [packet appendData:[position subdataWithRange:NSMakeRange(4,position.length-4)]];
    }
    XCTestExpectation *moved=[self expectationWithDescription:@"Host position survives a preceding pixel send"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){if(known)[moved fulfill];};
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);XCTAssertTrue([s handleServerMessage:c]);
    [self assertIncremental:peer width:100 height:100];[self waitForExpectations:@[moved] timeout:.5];
    XCTAssertEqualObjects(s.diagnosticCounters[@"cursorPositionUpdates"],@1);
    [self finish:s client:c peer:peer];
}
- (void)testBufferedCursorMessageIsDrainedWithoutWaitingForAnotherNetworkPacket {
    XCTAssertEqualObjects([self profile][@"cursorPipelineDiagnostics"][@"drainLibVNCBufferedBytesBeforeSocketWait"],@YES);
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    XCTAssertTrue([s allocate:c]);[self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];
    [s updatedX:0 y:0 width:100 height:100];[s setValue:@YES forKey:@"inputReady"];
    [s setValue:@YES forKey:@"baselinePresented"];[s setValue:@NO forKey:@"desktopRefreshPending"];
    CGPoint last=[self ownershipPoint:@"nextHostPoint"];
    XCTestExpectation *latest=[self expectationWithDescription:@"Second buffered cursor arrives with peer silent"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        if (known && CGPointEqualToPoint(position,last)) [latest fulfill];
    };
    NSMutableData *batch=[[self positionPacket:[self ownershipPoint:@"firstHostPoint"]] mutableCopy];
    [batch appendData:[self positionPacket:last]];
    XCTAssertEqual(send(peer,batch.bytes,batch.length,0),batch.length);
    // Consume only the first message. Read-ahead leaves the second inside LibVNCClient,
    // while the socket itself is empty: select alone can no longer see that message.
    XCTAssertTrue([s handleServerMessage:c]);XCTAssertGreaterThan(c->buffered,0);
    uint8_t byte;XCTAssertLessThan(recv(c->sock,&byte,1,MSG_PEEK|MSG_DONTWAIT),0);
    XCTestExpectation *stopped=[self expectationWithDescription:@"Socket owner stopped"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        [s processConnectedClient:c];dispatch_async(dispatch_get_main_queue(),^{[stopped fulfill];});
    });
    [self waitForExpectations:@[latest] timeout:.5];
    XCTAssertTrue(s.running);
    XCTAssertEqualObjects([s valueForKey:@"failureStage"],@0);
    XCTAssertGreaterThan([s.diagnosticCounters[@"pipeline"][@"bufferedReadDispatches"] unsignedIntegerValue],0);
    [s stop];[self waitForExpectations:@[stopped] timeout:2];close(peer);
}

- (void)testUnreadHostPositionQueuedBeforeLocalGestureMustNotUndoFinalLocalPosition {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];[self primeCursorCache:s client:c peer:peer];[self drainCursorQueue];
    CompanionVNCViewer *viewer=[self ownershipViewer:s];
    NSData *stale=[self positionPacket:[self ownershipPoint:@"firstHostPoint"]];
    XCTAssertEqual(send(peer,stale.bytes,stale.length,0),stale.length);
    uint8_t bytes[16];XCTAssertEqual(recv(c->sock,bytes,sizeof(bytes),MSG_PEEK|MSG_DONTWAIT),stale.length);
    s.localPointerInteractionActive=YES;
    CGPoint local=[self ownershipPoint:@"localInputPoint"];[viewer sendPointer:local mask:0];
    s.localPointerInteractionActive=NO;
    XCTestExpectation *delivered=[self expectationWithDescription:@"Old unread host position cannot snap pointer back"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        XCTAssertTrue(known);
        [viewer receivedCursor:image hotspot:hotspot position:position known:known];[delivered fulfill];
    };
    XCTAssertTrue([s handleServerMessage:c]);[self assertIncremental:peer width:100 height:100];
    [self waitForExpectations:@[delivered] timeout:1];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    [viewer stopViewer];[self finish:s client:c peer:peer];
}


- (void)testAutomaticHostFollowingChangesVisibleAndClickTargetsWithoutSendingInput {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    CGPoint local=[self ownershipPoint:@"localInputPoint"],host=[self ownershipPoint:@"nextHostPoint"];
    [viewer sendPointer:local mask:0];[viewer setValue:@0 forKey:@"lastLocalPointerInputAt"];NSUInteger queued=[[session valueForKey:@"events"] count];
    session.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint point,BOOL known){XCTAssertTrue(known);[viewer receivedCursor:image hotspot:hotspot position:point known:known];};
    [self receivePacket:[self positionPacket:host] client:client peer:peer];[self drainCursorQueue];
    XCTAssertEqual([[session valueForKey:@"events"] count],queued);[self assertNoBytes:peer];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],host));
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"hostCursorPosition"] CGPointValue],host));
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testLocalAimSurvivesModeChangesAndPresentationInvalidation {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    CGPoint local=[self ownershipPoint:@"localInputPoint"];
    [viewer sendPointer:local mask:0];[viewer releasePointer];
    for(NSString *mode in @[@"setPointer",@"setTrackpad"]) {
        [viewer performControlAction:@{@"kind":mode}];
        XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    }
    [viewer invalidateCursorPosition];
    XCTAssertTrue([[viewer valueForKey:@"localAimPinned"] boolValue]);
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testHostObservationsRemainBlockedByReviewAndInterruption {
    for(NSString *gate in @[@"reviewInputSuspended",@"interruptionInputSuspended"]) {
        CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
        [self prepareLayout:session client:client peer:peer];[session setValue:@YES forKey:gate];
        session.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint point,BOOL known){XCTAssertFalse(known);};
        [self receivePacket:[self positionPacket:[self ownershipPoint:@"firstHostPoint"]] client:client peer:peer];[self drainCursorQueue];
        [session setValue:@NO forKey:gate];[self finish:session client:client peer:peer];
    }
}
- (void)testRetiringCursorAllowsNewHostToSeedLocalAimWithoutOldPosition {
    XCTAssertEqualObjects([self profile][@"cursorPositionOwnership"][@"newConnectionRetiresBothPositions"],@YES);
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    [viewer sendPointer:[self ownershipPoint:@"localInputPoint"] mask:0];[viewer clearCursor];
    XCTAssertFalse([[viewer valueForKey:@"localAimPinned"] boolValue]);XCTAssertFalse([[viewer valueForKey:@"hostCursorPositionKnown"] boolValue]);
    CGPoint host=[self ownershipPoint:@"nextHostPoint"];[viewer receivedCursor:nil hotspot:CGPointZero position:host known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],host));
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testDelayedEchoAfterLiftAndAfterHandoffCannotReplaceTheVisibleClickTarget {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    CGPoint old=CGPointMake(20,30),local=CGPointMake(40,45),host=CGPointMake(90,70);
    [viewer sendPointer:old mask:0];[viewer sendPointer:local mask:0];
    [viewer setValue:@0 forKey:@"lastLocalPointerInputAt"];
    UIView *cursor=[viewer valueForKey:@"cursorIndicator"];CGRect frame=cursor.frame;
    [viewer receivedCursor:nil hotspot:CGPointZero position:old known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    XCTAssertTrue(CGRectEqualToRect(cursor.frame,frame));XCTAssertFalse(cursor.hidden);
    [viewer receivedCursor:nil hotspot:CGPointZero position:host known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],host));
    [viewer clickAt:[CursorOwnershipPan new]];
    NSDictionary *click=[[session valueForKey:@"events"] lastObject];
    XCTAssertEqualObjects(click[@"x"],@90);XCTAssertEqualObjects(click[@"y"],@70);
    [viewer sendPointer:CGPointMake(91,71) mask:0];[viewer setValue:@0 forKey:@"lastLocalPointerInputAt"];
    [viewer receivedCursor:nil hotspot:CGPointZero position:host known:YES];
    [viewer receivedCursor:nil hotspot:CGPointZero position:local known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],CGPointMake(91,71)));
    [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(12,13) known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],CGPointMake(12,13)));
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testSettlingIntervalDropsReportsWithoutReplayingThemAndNeverChangesClickTargetInSecret {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    CGPoint local=CGPointMake(40,45),host=CGPointMake(90,70);[viewer sendPointer:local mask:0];
    [viewer receivedCursor:nil hotspot:CGPointZero position:host known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    // Advance the admission clock without a timer or another observation. A
    // discarded report must not reappear merely because the interval elapsed.
    [viewer setValue:@0 forKey:@"lastLocalPointerInputAt"];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    [viewer receivedCursor:nil hotspot:CGPointZero position:host known:NO];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    [viewer receivedCursor:nil hotspot:CGPointZero position:host known:YES];
    [viewer clickAt:[CursorOwnershipPan new]];
    NSDictionary *click=[[session valueForKey:@"events"] lastObject];
    XCTAssertEqualObjects(click[@"x"],@90);XCTAssertEqualObjects(click[@"y"],@70);
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testIndirectHostMovementOutsideSelectedCropKeepsTheVisibleClickTarget {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    [viewer setValue:[NSValue valueWithCGRect:CGRectMake(0,0,50,100)] forKey:@"activeCrop"];
    [viewer sendPointer:CGPointMake(20,30) mask:0];[viewer setValue:@0 forKey:@"lastLocalPointerInputAt"];
    [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(90,70) known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],CGPointMake(20,30)));
    [viewer clickAt:[CursorOwnershipPan new]];NSDictionary *click=[[session valueForKey:@"events"] lastObject];
    XCTAssertEqualObjects(click[@"x"],@20);XCTAssertEqualObjects(click[@"y"],@30);
    [viewer setValue:@0 forKey:@"lastLocalPointerInputAt"];
    [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(35,40) known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],CGPointMake(35,40)));
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testInitialHostPositionSeedsBeforeLoginCompletesWithoutShowingCursorOrSendingInput {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    UIView *login=[viewer valueForKey:@"login"];login.hidden=NO;
    NSUInteger queued=[[session valueForKey:@"events"] count];
    [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(75,60) known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],CGPointMake(75,60)));
    XCTAssertTrue(((UIView *)[viewer valueForKey:@"cursorIndicator"]).hidden);
    XCTAssertEqual([[session valueForKey:@"events"] count],queued);XCTAssertFalse(login.hidden);
    login.hidden=YES;[viewer updateConnectionChrome];[viewer updateCursor];
    XCTAssertFalse(((UIView *)[viewer valueForKey:@"cursorIndicator"]).hidden);
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testReplayHistoryIsBoundedAndRetiredWithConnectionAndFramebufferGeometry {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    for(NSInteger i=0;i<540;i++)[viewer sendPointer:CGPointMake(i%100,i/100) mask:0];
    XCTAssertEqual([(NSOrderedSet *)[viewer valueForKey:@"localPointerTargets"] count],512);
    [viewer clearCursor];XCTAssertEqual([(NSOrderedSet *)[viewer valueForKey:@"localPointerTargets"] count],0);
    [viewer receivedCursor:nil hotspot:CGPointZero position:CGPointMake(20,30) known:YES];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],CGPointMake(20,30)));
    [viewer sendPointer:CGPointMake(21,31) mask:0];
    UIGraphicsImageRendererFormat *format=[UIGraphicsImageRendererFormat defaultFormat];format.scale=1;
    [viewer frame:[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(200,200) format:format] imageWithActions:^(UIGraphicsImageRendererContext *ctx){}]];
    XCTAssertEqual([(NSOrderedSet *)[viewer valueForKey:@"localPointerTargets"] count],0);
    [viewer sendPointer:CGPointMake(30,30) mask:0];
    [viewer selectDisplay:@{@"title":@"Right display",@"x":@.5,@"y":@0,@"width":@.5,@"height":@1}];
    XCTAssertEqual([(NSOrderedSet *)[viewer valueForKey:@"localPointerTargets"] count],0);
    XCTAssertTrue(CGRectContainsPoint([[viewer valueForKey:@"activeCrop"] CGRectValue],[[viewer valueForKey:@"cursorPosition"] CGPointValue]));
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)openInputMenuThroughControls:(CompanionVNCViewer *)viewer {
    CompanionVNCControls *controls=[viewer valueForKey:@"controls"];[controls open];
    UIButton *input=nil;
    for(UIButton *choice in [controls valueForKey:@"choices"])
        if([choice.accessibilityIdentifier isEqual:@"session-action-inputMenu"]) input=choice;
    XCTAssertNotNil(input);[input sendActionsForControlEvents:UIControlEventTouchUpInside];
}
- (void)testNativeInputMenuHasNoHostFollowingOptionInEitherMode {
    XCTAssertEqualObjects([self profile][@"cursorPositionOwnership"][@"hostPositionFollowingSetting"],@NO);
    for(NSNumber *inputOnly in @[@NO,@YES]) {
        CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
        [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];viewer.inputOnly=inputOnly.boolValue;
        UIWindow *window=[[UIWindow alloc] initWithFrame:viewer.view.frame];window.rootViewController=viewer;[window makeKeyAndVisible];
        [self openInputMenuThroughControls:viewer];UINavigationController *navigation=(id)viewer.presentedViewController;
        XCTAssertTrue([navigation isKindOfClass:UINavigationController.class]);
        CompanionVNCMenu *menu=(id)navigation.topViewController;[menu loadViewIfNeeded];
        for(NSDictionary *section in menu.sections) for(NSDictionary *item in section[@"items"]) {
            XCTAssertNotEqualObjects(item[@"kind"],@"followMacPointer");XCTAssertNotEqualObjects(item[@"title"],@"Follow Mac Pointer");
        }
        [viewer dismissViewControllerAnimated:NO completion:nil];[viewer stopViewer];window.hidden=YES;window.rootViewController=nil;
        [self finish:session client:client peer:peer];
    }
}
- (void)assertQueuedInputBeforeUnfinishedPixels:(NSInteger)inputKind {
    BOOL keyboard=inputKind==1, click=inputKind>=2;
    NSInteger button=inputKind==3?4:1;
    XCTAssertEqualObjects([self profile][@"desktopReadInputService"][@"soleSocketOwner"],@YES);
    XCTAssertEqualObjects([self profile][@"desktopReadInputService"][@"wireBytesUnchanged"],@YES);
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;
    rfbClient *client=[self clientFor:session peer:&peer];XCTAssertTrue([session allocate:client]);
    rfbClientSetUpdateRect(client,NULL);[self prepareLayout:session client:client peer:peer];
    [session updatedX:0 y:0 width:100 height:100];
    [session setValue:@YES forKey:@"inputReady"];[session setValue:@YES forKey:@"baselinePresented"];
    [session setValue:@NO forKey:@"desktopRefreshPending"];XCTAssertTrue([session registerSocket:client->sock]);
    CompanionVNCViewer *viewer=click?[self ownershipViewer:session]:nil;
    XCTestExpectation *stopped=[self expectationWithDescription:@"Actual socket worker stopped"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        [session processConnectedClient:client];dispatch_async(dispatch_get_main_queue(),^{[stopped fulfill];});
    });
    const uint8_t release[]={5,0,0,0,0,0};XCTAssertEqualObjects([self read:6 peer:peer],[NSData dataWithBytes:release length:6]);
    // One raw rectangle with its four pixel bytes deliberately withheld.
    const uint8_t prefix[]={0,0,0,1,0,0,0,0,0,1,0,1,0,0,0,0};
    XCTAssertEqual(send(peer,prefix,sizeof(prefix),0),sizeof(prefix));
    XCTNSPredicateExpectation *reading=[[XCTNSPredicateExpectation alloc] initWithPredicate:
        [NSPredicate predicateWithBlock:^BOOL(id value,NSDictionary *bindings){return [session.diagnosticCounters[@"pipeline"][@"messageReadActive"] boolValue];}] object:nil];
    [self waitForExpectations:@[reading] timeout:2];
    if (keyboard) {
        client->supportedMessages.client2server[0] |= 1 << rfbKeyEvent;
        NSArray *events=@[@{@"key":@0xff0d,@"down":@YES},@{@"key":@0xff0d,@"down":@NO}];
        XCTAssertTrue([session tryKeyEvents:events]);
    } else if(click) XCTAssertTrue([viewer clickPointer:CGPointMake(20,30) mask:button]);
    else [session pointerX:20 y:30 mask:0];
    struct pollfd pending={.fd=peer,.events=POLLIN};int ready=poll(&pending,1,150);
    BOOL sentBeforePixels=ready>0 && (pending.revents&POLLIN);
    const uint8_t pointer[]={5,0,0,20,0,30},keys[]={4,1,0,0,0,0,0xff,0x0d,4,0,0,0,0,0,0xff,0x0d};
    const uint8_t clickBytes[]={5,(uint8_t)button,0,20,0,30,5,0,0,20,0,30};
    NSData *expected=click?[NSData dataWithBytes:clickBytes length:sizeof(clickBytes)]:keyboard?[NSData dataWithBytes:keys length:sizeof(keys)]:[NSData dataWithBytes:pointer length:sizeof(pointer)];
    if(sentBeforePixels) XCTAssertEqualObjects([self read:expected.length peer:peer],expected);
    const uint8_t pixel[]={0,0,0,0};XCTAssertEqual(send(peer,pixel,sizeof(pixel),0),sizeof(pixel));
    [self assertIncremental:peer width:100 height:100];
    if(!sentBeforePixels) XCTAssertEqualObjects([self read:expected.length peer:peer],expected);
    XCTAssertEqualObjects(session.diagnosticCounters[@"pipeline"][@"inputEventsDuringRead"],(keyboard||click)?@2:@1);
    [session stop];[self waitForExpectations:@[stopped] timeout:2];close(peer);[viewer stopViewer];
    XCTAssertTrue(sentBeforePixels,@"Input waits for unfinished incoming desktop pixels, despite being ready and queued on the active connection.");
}

- (void)testQueuedPointerIsWrittenBeforeUnfinishedIncomingPixels { [self assertQueuedInputBeforeUnfinishedPixels:NO]; }
- (void)testQueuedKeysAreWrittenBeforeUnfinishedIncomingPixels { [self assertQueuedInputBeforeUnfinishedPixels:YES]; }
- (void)testQueuedLeftClickPressAndReleaseAreWrittenBeforeUnfinishedIncomingPixels { [self assertQueuedInputBeforeUnfinishedPixels:2]; }
- (void)testQueuedRightClickPressAndReleaseAreWrittenBeforeUnfinishedIncomingPixels { [self assertQueuedInputBeforeUnfinishedPixels:3]; }
- (void)testReadInputServicePreservesAdmissionAndReleaseBoundaries {
    for(NSString *key in @[@"running",@"established",@"inputReady",@"paused",@"stopping",@"overflow",@"reviewInputSuspended",@"interruptionInputSuspended",@"releaseInputRequested",@"resumeRequested",@"modeChanged"]) {
        CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
        [session pointerX:20 y:30 mask:0];XCTAssertEqual([[session valueForKey:@"events"] count],1);
        BOOL normallyTrue=[@[@"running",@"established",@"inputReady"] containsObject:key];
        [session setValue:@(!normallyTrue) forKey:key];
        XCTAssertTrue([session servicePendingInput:client]);[self assertNoBytes:peer];
        XCTAssertEqual([[session valueForKey:@"events"] count],1);
        XCTAssertEqualObjects(session.diagnosticCounters[@"pipeline"][@"inputEventsDuringRead"],@0);
        [self finish:session client:client peer:peer];
    }
}

- (void)testActualSocketOwnerKeepsInputAnchorSeparateFromAutomaticHostReports {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    XCTAssertTrue([s allocate:c]);rfbClientSetUpdateRect(c,NULL);[self prepareLayout:s client:c peer:peer];
    [self primeCursorCache:s client:c peer:peer];[self drainCursorQueue];
    [s updatedX:0 y:0 width:100 height:100];[s setValue:@YES forKey:@"inputReady"];
    [s setValue:@YES forKey:@"baselinePresented"];[s setValue:@NO forKey:@"desktopRefreshPending"];
    XCTAssertTrue([s registerSocket:c->sock]);CompanionVNCViewer *viewer=[self ownershipViewer:s];
    CGPoint local=[self ownershipPoint:@"localInputPoint"],host=[self ownershipPoint:@"nextHostPoint"];
    [viewer sendPointer:local mask:0];
    XCTestExpectation *stopped=[self expectationWithDescription:@"Actual pointer socket owner stopped"];
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        [s processConnectedClient:c];dispatch_async(dispatch_get_main_queue(),^{[stopped fulfill];});
    });
    // This is an actual wire assertion, not the session's processed-event counter.
    uint8_t expected[]={5,0,0,(uint8_t)local.x,0,(uint8_t)local.y};
    // allocate() requests release of any old held input before the first batch.
    const uint8_t release[]={5,0,0,0,0,0};
    XCTAssertEqualObjects([self read:6 peer:peer],[NSData dataWithBytes:release length:6]);
    XCTAssertEqualObjects([self read:6 peer:peer],[NSData dataWithBytes:expected length:6]);
    XCTestExpectation *localOwns=[self expectationWithDescription:@"Incoming host position does not block outgoing local input"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        [viewer receivedCursor:image hotspot:hotspot position:position known:known];[localOwns fulfill];
    };
    NSData *packet=[self positionPacket:host];XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);
    [self waitForExpectations:@[localOwns] timeout:1];[self assertIncremental:peer width:100 height:100];
    XCTestExpectation *follows=[self expectationWithDescription:@"Actual receiver follows automatically"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        [viewer receivedCursor:image hotspot:hotspot position:position known:known];[follows fulfill];
    };
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);[self waitForExpectations:@[follows] timeout:1];
    [self assertIncremental:peer width:100 height:100];
    [viewer sendPointer:local mask:0];
    XCTAssertEqualObjects([self read:6 peer:peer],[NSData dataWithBytes:expected length:6]);
    XCTestExpectation *retaken=[self expectationWithDescription:@"New local input retakes ownership and remains on the wire"];
    s.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
        [viewer receivedCursor:image hotspot:hotspot position:position known:known];[retaken fulfill];
    };
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);[self waitForExpectations:@[retaken] timeout:1];
    [self assertIncremental:peer width:100 height:100];
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"cursorPosition"] CGPointValue],local));
    XCTAssertTrue(CGPointEqualToPoint([[viewer valueForKey:@"hostCursorPosition"] CGPointValue],host));
    s.cursorHandler=nil;[s stop];[self waitForExpectations:@[stopped] timeout:2];close(peer);[viewer stopViewer];
}


- (void)testCursorDiagnosticsSeparateHostObservationAndLocalAimWithoutInputValues {
    CompanionVNCSession *session=[CompanionVNCSession new];int peer;rfbClient *client=[self clientFor:session peer:&peer];
    [self prepareLayout:session client:client peer:peer];CompanionVNCViewer *viewer=[self ownershipViewer:session];
    [viewer sendPointer:[self ownershipPoint:@"localInputPoint"] mask:0];
    [viewer receivedCursor:nil hotspot:CGPointZero position:[self ownershipPoint:@"nextHostPoint"] known:YES];
    NSDictionary *flags=[viewer cursorDiagnosticFlags];XCTAssertEqualObjects(flags[@"hostPositionKnown"],@YES);XCTAssertEqualObjects(flags[@"localAimPinned"],@YES);XCTAssertEqualObjects(flags[@"singlePersistentCursor"],@YES);
    for(NSDictionary *snapshot in @[flags,session.diagnosticCounters[@"pipeline"]]) {
        XCTAssertTrue([NSJSONSerialization isValidJSONObject:snapshot]);
        for(id value in snapshot.allValues) XCTAssertTrue([value isKindOfClass:NSNumber.class]);
        for(NSString *forbidden in @[@"x",@"y",@"text",@"username",@"password",@"endpoint",@"action"]) XCTAssertNil(snapshot[forbidden]);
    }
    [viewer stopViewer];[self finish:session client:client peer:peer];
}
- (void)testBrokenSubscriptionWriteFailsInsteadOfPretendingCursorDeliveryWorks {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self layout:c peer:peer valid:YES];[self read:10 peer:peer];close(peer);
    XCTAssertFalse([s configureDesktopUpdates:c]);XCTAssertEqualObjects(s.diagnosticCounters[@"automaticDesktopUpdates"],@NO);
    [s setValue:@NO forKey:@"running"];rfbClientCleanup(c);
}
@end
