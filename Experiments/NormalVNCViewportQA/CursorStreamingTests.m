#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCAppleUpdates.h"
#import <rfb/rfbclient.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCSession (CursorStreamingTesting)
- (void)configureClient:(rfbClient *)client;
- (BOOL)configureDesktopUpdates:(rfbClient *)client;
- (BOOL)stopAutomaticUpdates:(rfbClient *)client;
- (BOOL)requestFullDesktop:(rfbClient *)client;
- (BOOL)registerSocket:(int)socket;
- (void)processConnectedClient:(rfbClient *)client;
- (void)publishCursor;
- (rfbBool)allocate:(rfbClient *)client;
@end
@interface CompanionVNCViewer (CursorStreamingTesting)
- (void)frame:(UIImage *)frame;
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known;
- (void)sendPointer:(CGPoint)point mask:(NSInteger)mask;
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
- (void)testSameGeometryLayoutRearmsAndFullRefreshBypassesRoutineRequestMask {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];
    XCTAssertFalse(SupportsClient2Server(c,rfbFramebufferUpdateRequest));
    XCTAssertTrue(SendIncrementalFramebufferUpdateRequest(c));[self assertNoBytes:peer];
    XCTAssertTrue([s requestFullDesktop:c]);[self assertRefresh:peer width:100 height:100];
    XCTAssertFalse(SupportsClient2Server(c,rfbFramebufferUpdateRequest));
    [self layout:c peer:peer valid:YES];[self assertNoBytes:peer];
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:YES width:100 height:100];
    XCTAssertEqualObjects(s.diagnosticCounters[@"automaticUpdateStarts"],@2);
    [self layout:c peer:peer valid:NO];[self assertNoBytes:peer];
    XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:NO width:100 height:100];
    XCTAssertTrue(SupportsClient2Server(c,rfbFramebufferUpdateRequest));
    XCTAssertEqualObjects(s.diagnosticCounters[@"automaticDesktopUpdates"],@NO);
    [self finish:s client:c peer:peer];
}
- (void)testInputOnlyDisablesAutomaticPixelsAndCapabilityRefreshStaysEmpty {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self prepareLayout:s client:c peer:peer];s.inputOnly=YES;
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
    s.inputOnly=NO;XCTAssertTrue([s configureDesktopUpdates:c]);[self assertControl:peer enabled:YES width:100 height:100];
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
    [viewer frame:frame];[viewer.view layoutIfNeeded];[viewer sendPointer:CGPointMake(50,50) mask:0];
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
        [self assertNoBytes:peer];
    }
    XCTAssertEqualObjects(s.diagnosticCounters[@"appleCursorSelections"],@1);
    XCTAssertEqualObjects(s.diagnosticCounters[@"appleCursorStores"],@2);
    s.cursorHandler=nil;[viewer stopViewer];[self finish:s client:c peer:peer];
}
- (void)testBrokenSubscriptionWriteFailsInsteadOfPretendingCursorDeliveryWorks {
    CompanionVNCSession *s=[CompanionVNCSession new];int peer;rfbClient *c=[self clientFor:s peer:&peer];
    [self layout:c peer:peer valid:YES];[self read:10 peer:peer];close(peer);
    XCTAssertFalse([s configureDesktopUpdates:c]);XCTAssertEqualObjects(s.diagnosticCounters[@"automaticDesktopUpdates"],@NO);
    [s setValue:@NO forKey:@"running"];rfbClientCleanup(c);
}
@end
