#import <XCTest/XCTest.h>
#import <UIKit/UIKit.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCViewer.h"
#import "CompanionVNCAppleCursor.h"
#import <rfb/rfbclient.h>
#import <arpa/inet.h>
#import <sys/socket.h>
#import <unistd.h>

@interface CompanionVNCSession (NativeCursorWireDiagnosis)
- (void)configureClient:(rfbClient *)client;
- (void)publishCursor;
- (rfbBool)allocate:(rfbClient *)client;
- (BOOL)resetBaseline:(rfbClient *)client;
- (void)report:(NSString *)state;
@end

@interface CompanionVNCViewer (CursorContinuityTesting)
- (void)updateConnectionChrome;
- (void)frame:(UIImage *)frame;
- (void)receivedCursor:(UIImage *)image hotspot:(CGPoint)hotspot position:(CGPoint)position known:(BOOL)known;
- (void)sendPointer:(CGPoint)point mask:(NSInteger)mask;
@end

@interface CursorWireTests : XCTestCase
@end
@implementation CursorWireTests
- (NSDictionary *)profile {
    NSString *root = [NSBundle bundleForClass:self.class].resourcePath;
    XCTAssertNotNil(root);
    NSDictionary *manifest = [NSJSONSerialization JSONObjectWithData:
        [NSData dataWithContentsOfFile:[root stringByAppendingPathComponent:@"manifest.json"]] options:0 error:NULL];
    NSDictionary *entry = nil;
    for (NSDictionary *candidate in manifest[@"fixtures"]) {
        if ([candidate[@"path"] isEqual:@"vnc-desktop-tunnel-v0.1.json"]) entry = candidate;
    }
    XCTAssertEqualObjects(entry[@"expect"], @"valid");
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfFile:
        [root stringByAppendingPathComponent:entry[@"path"]]] options:0 error:NULL];
}
- (rfbClient *)clientFor:(CompanionVNCSession *)session peer:(int *)peer {
    int sockets[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, sockets), 0);
    struct timeval timeout = {1, 0}; setsockopt(sockets[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    rfbClient *client = rfbGetClient(8, 3, 4);
    [session configureClient:client]; client->sock = sockets[0]; *peer = sockets[1];
    client->width = 100; client->height = 100;
    [session setValue:@YES forKey:@"running"];
    return client;
}
- (void)testBriefInactivityRestoresStandardAppleAndTransparentCursorsWithoutNewReports {
    NSDictionary *profile=[self profile];
    XCTAssertEqualObjects(profile[@"cursorPresentationPolicy"][@"sameOwnerBriefInactivePreservesCursor"],@YES);
    NSArray *vectors=[profile[@"cursorWireCases"] arrayByAddingObjectsFromArray:profile[@"appleCursorCases"]];
    for (NSDictionary *vector in vectors) {
        CompanionVNCSession *session=[CompanionVNCSession new]; int peer;
        rfbClient *client=[self clientFor:session peer:&peer];
        for (NSString *key in @[@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
        CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded]; viewer.session=session;
        viewer.view.frame=CGRectMake(0,0,440,956);
        UIImage *frame=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100,100)] imageWithActions:^(UIGraphicsImageRendererContext *context){
            [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0,0,100,100));
        }];
        [viewer frame:frame]; [(UIView *)[viewer valueForKey:@"login"] setHidden:YES]; [viewer updateConnectionChrome]; [viewer.view layoutIfNeeded];
        XCTestExpectation *shape=[self expectationWithDescription:vector[@"name"]];
        session.cursorHandler=^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known){
            [viewer receivedCursor:image hotspot:hotspot position:position known:known]; [shape fulfill];
        };
        NSData *packet=[self updateFor:vector]; XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor]; [self waitForExpectations:@[shape] timeout:1];
        [viewer sendPointer:CGPointMake(50,50) mask:0];
        UIImage *image=[viewer valueForKey:@"remoteCursorImage"]; XCTAssertNotNil(image);
        NSValue *hotspot=[viewer valueForKey:@"cursorHotspot"];
        UIView *indicator=[viewer valueForKey:@"cursorIndicator"], *fallback=[viewer valueForKey:@"fallbackCursor"];
        XCTAssertFalse(indicator.hidden); XCTAssertTrue(fallback.hidden);
        NSNumber *reports=[session valueForKey:@"cursorPublications"];
        [viewer becameInactive]; XCTAssertTrue(indicator.hidden);
        XCTAssertTrue([viewer valueForKey:@"remoteCursorImage"]==image);
        [viewer foregrounded]; XCTAssertFalse(indicator.hidden); XCTAssertTrue(fallback.hidden);
        XCTAssertEqualObjects([viewer valueForKey:@"cursorHotspot"],hotspot);
        [viewer sendPointer:CGPointMake(51,50) mask:0];
        XCTAssertTrue([viewer valueForKey:@"remoteCursorImage"]==image); XCTAssertTrue(fallback.hidden);
        XCTAssertEqualObjects([session valueForKey:@"cursorPublications"],reports);
        session.cursorHandler=nil; [viewer stopViewer]; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}

- (void)testEarlyAndRetainedCursorShapesSurviveCompleteFramesWithoutNewReports {
    NSDictionary *profile = [self profile];
    XCTAssertEqualObjects(profile[@"cursorPresentationPolicy"][@"earlyShapeSurvivesFirstFrame"], @YES);
    NSArray *vectors = [profile[@"cursorWireCases"] arrayByAddingObjectsFromArray:profile[@"appleCursorCases"]];
    for (NSDictionary *vector in vectors) {
        CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
        viewer.view.frame = CGRectMake(0,0,440,956);
        CompanionVNCSession *session = viewer.session; int peer;
        rfbClient *client = [self clientFor:session peer:&peer];
        for (NSString *key in @[@"established", @"inputReady", @"baselinePresented"]) [session setValue:@YES forKey:key];
        void (^receive)(UIImage *,CGPoint,CGPoint,BOOL) = session.cursorHandler;
        XCTestExpectation *first = [self expectationWithDescription:@"early shape"];
        session.cursorHandler = ^(UIImage *image,CGPoint hotspot,CGPoint position,BOOL known) {
            receive(image,hotspot,position,known); [first fulfill];
        };
        NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor]; [self waitForExpectations:@[first] timeout:1];
        UIImage *image = [viewer valueForKey:@"remoteCursorImage"]; XCTAssertNotNil(image);
        UIImage *frame = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100,100)] imageWithActions:^(UIGraphicsImageRendererContext *context) {
            [UIColor.systemBlueColor setFill]; UIRectFill(CGRectMake(0,0,100,100));
        }];
        session.cursorHandler = receive; [viewer frame:frame]; [(UIView *)[viewer valueForKey:@"login"] setHidden:YES]; [viewer updateConnectionChrome]; [viewer.view layoutIfNeeded];
        XCTAssertTrue([viewer valueForKey:@"remoteCursorImage"] == image);
        [viewer sendPointer:CGPointMake(50,50) mask:0];
        XCTAssertFalse([(UIView *)[viewer valueForKey:@"cursorIndicator"] isHidden]);
        [viewer background]; XCTAssertTrue([viewer valueForKey:@"remoteCursorImage"] == image);
        XCTAssertFalse([[viewer valueForKey:@"hostCursorPositionKnown"] boolValue]);
        XCTAssertTrue([[viewer valueForKey:@"localAimPinned"] boolValue]);
        [viewer foregrounded];
        XCTestExpectation *restored = [self expectationWithDescription:@"retained owner replay"];
        session.cursorHandler = ^(UIImage *shape,CGPoint hotspot,CGPoint position,BOOL known) {
            receive(shape,hotspot,position,known); XCTAssertFalse(known); [restored fulfill];
        };
        [session setValue:@NO forKey:@"resumeRequested"];
        XCTAssertTrue([session resetBaseline:client]); [session publishCursor]; [self waitForExpectations:@[restored] timeout:1];
        for (NSString *key in @[@"inputReady", @"baselinePresented"]) [session setValue:@YES forKey:key];
        [session setValue:@NO forKey:@"awaitingResumeFrame"];
        [session report:@"Connected"];
        XCTestExpectation *drained = [self expectationWithDescription:@"active ready notification"];
        dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; }); [self waitForExpectations:@[drained] timeout:1];
        XCTAssertFalse([[viewer valueForKey:@"checkingResume"] boolValue]);
        [viewer sendPointer:CGPointMake(51,50) mask:0];
        XCTAssertTrue([viewer valueForKey:@"remoteCursorImage"] == image);
        XCTAssertTrue([(UIView *)[viewer valueForKey:@"fallbackCursor"] isHidden]);
        session.cursorHandler = nil; [viewer stopViewer]; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}
- (void)testPendingResumeRejectsQueuedCursorAndFreshReplayInvalidatesOldPosition {
    CompanionVNCViewer *viewer = [CompanionVNCViewer new]; [viewer loadViewIfNeeded];
    CompanionVNCSession *session = viewer.session; int peer; rfbClient *client = [self clientFor:session peer:&peer];
    for (NSString *key in @[@"established", @"inputReady", @"baselinePresented", @"cursorPositionKnown"]) [session setValue:@YES forKey:key];
    NSData *packet = [self updateFor:[self profile][@"appleCursorCases"][0]];
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length); XCTAssertTrue(HandleRFBServerMessage(client));
    __block NSUInteger deliveries = 0; __block BOOL known = YES;
    session.cursorHandler = ^(UIImage *shape,CGPoint hotspot,CGPoint position,BOOL k) { deliveries++; known = k; };
    [session publishCursor]; [viewer background]; [viewer foregrounded]; [session publishCursor];
    XCTestExpectation *drained = [self expectationWithDescription:@"old callback retired"];
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; }); [self waitForExpectations:@[drained] timeout:1];
    XCTAssertEqual(deliveries,0);
    [session setValue:@NO forKey:@"resumeRequested"]; XCTAssertTrue([session resetBaseline:client]); [session publishCursor];
    XCTestExpectation *replayed = [self expectationWithDescription:@"fresh cached replay"];
    dispatch_async(dispatch_get_main_queue(), ^{ [replayed fulfill]; }); [self waitForExpectations:@[replayed] timeout:1];
    XCTAssertEqual(deliveries,1); XCTAssertFalse(known);
    session.cursorHandler=nil; [viewer stopViewer]; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
}
- (void)testCursorOnlyDiagnosticsAreFreshAndPointerMotionDoesNotWritePerEvent {
    CompanionVNCViewer *viewer=[CompanionVNCViewer new]; [viewer loadViewIfNeeded]; viewer.view.frame=CGRectMake(0,0,440,956);
    CompanionVNCSession *session=viewer.session; int peer; rfbClient *client=[self clientFor:session peer:&peer];
    for (NSString *key in @[@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
    UIImage *frame=[[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(100,100)] imageWithActions:^(UIGraphicsImageRendererContext *context){ UIRectFill(CGRectMake(0,0,100,100)); }];
    [viewer frame:frame]; [(UIView *)[viewer valueForKey:@"login"] setHidden:YES]; [viewer updateConnectionChrome]; [viewer.view layoutIfNeeded];
    __block NSUInteger writes=0; __block NSDictionary *latest;
    viewer.diagnosticHandler=^(NSDictionary *snapshot){ writes++; latest=snapshot; };
    NSData *packet=[self updateFor:[self profile][@"appleCursorCases"][0]];
    XCTAssertEqual(send(peer,packet.bytes,packet.length,0),packet.length); XCTAssertTrue(HandleRFBServerMessage(client));
    [session publishCursor];
    XCTestExpectation *drained=[self expectationWithDescription:@"shape callback"];
    dispatch_async(dispatch_get_main_queue(),^{ [drained fulfill]; }); [self waitForExpectations:@[drained] timeout:1];
    for (NSUInteger i=0;i<400;i++) [viewer sendPointer:CGPointMake(40+i%20,50) mask:0];
    XCTestExpectation *snapshot=[self expectationWithDescription:@"coalesced diagnostics"];
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW,400*NSEC_PER_MSEC),dispatch_get_main_queue(),^{ [snapshot fulfill]; });
    [self waitForExpectations:@[snapshot] timeout:1];
    XCTAssertEqual(writes,1); XCTAssertEqualObjects(latest[@"appleCursorStores"],@1);
    XCTAssertEqualObjects(latest[@"cursorPresentation"][@"hostShapeAvailable"],@YES);
    XCTAssertEqualObjects(latest[@"cursorPresentation"][@"usesFallback"],@NO);
    XCTAssertEqualObjects(session.diagnosticCounters[@"presentedFrames"],@0);
    viewer.diagnosticHandler=nil; session.cursorHandler=nil; [viewer stopViewer]; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
}
- (void)testActualSetEncodingsRequestsCursorShapesDespiteExplicitPixelEncodingList {
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
    rfbClient *client = [self clientFor:session peer:&peer];
    // The handshake normally establishes these standard supported-message bits.
    client->supportedMessages.client2server[rfbSetPixelFormat / 8] |= 1 << (rfbSetPixelFormat % 8);
    client->supportedMessages.client2server[rfbSetEncodings / 8] |= 1 << (rfbSetEncodings % 8);
    XCTAssertTrue(SetFormatAndEncodings(client));
    uint8_t format[sz_rfbSetPixelFormatMsg], header[sz_rfbSetEncodingsMsg];
    XCTAssertEqual(recv(peer, format, sizeof(format), MSG_WAITALL), sizeof(format));
    XCTAssertEqual(format[0], rfbSetPixelFormat); XCTAssertEqual(format[4], 32);
    XCTAssertEqual(format[6], 0); XCTAssertEqual(format[14], 16); XCTAssertEqual(format[15], 8); XCTAssertEqual(format[16], 0);
    XCTAssertEqual(recv(peer, header, sizeof(header), MSG_WAITALL), sizeof(header));
    XCTAssertEqual(header[0], rfbSetEncodings);
    NSUInteger count = ((NSUInteger)header[2] << 8) | header[3]; XCTAssertLessThan(count, 128);
    NSMutableArray *actual = [NSMutableArray array];
    for (NSUInteger i = 0; i < count; i++) {
        uint32_t encoding; XCTAssertEqual(recv(peer, &encoding, 4, MSG_WAITALL), 4);
        [actual addObject:@((int32_t)ntohl(encoding))];
    }
    for (NSNumber *encoding in [self profile][@"cursorNegotiationEncodings"]) XCTAssertTrue([actual containsObject:encoding]);
    XCTAssertTrue([actual containsObject:[self profile][@"appleCursor"][@"encoding"]]);
    [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
}
- (NSData *)updateFor:(NSDictionary *)vector {
    NSArray *size = vector[@"size"], *hot = vector[@"hotspot"];
    uint16_t x = [hot[0] unsignedShortValue], y = [hot[1] unsignedShortValue];
    uint16_t w = [size[0] unsignedShortValue], h = [size[1] unsignedShortValue];
    uint32_t encoding = htonl((uint32_t)[vector[@"encoding"] intValue]);
    uint8_t prefix[] = {rfbFramebufferUpdate, 0, 0, 1, x >> 8, x & 255, y >> 8, y & 255,
                       w >> 8, w & 255, h >> 8, h & 255};
    NSMutableData *data = [NSMutableData dataWithBytes:prefix length:sizeof(prefix)];
    [data appendBytes:&encoding length:4];
    for (NSNumber *number in vector[@"payload"]) { uint8_t value = number.unsignedCharValue; [data appendBytes:&value length:1]; }
    return data;
}
- (void)assertImage:(UIImage *)image vector:(NSDictionary *)vector {
    if (!image) { XCTFail(@"Decoded cursor image is missing"); return; }
    CGImageRef cg = image.CGImage;
    NSArray *size = vector[@"size"], *expected = vector[@"rgba"];
    XCTAssertEqual(CGImageGetWidth(cg), [size[0] unsignedIntegerValue]);
    XCTAssertEqual(CGImageGetHeight(cg), [size[1] unsignedIntegerValue]);
    NSData *pixels = CFBridgingRelease(CGDataProviderCopyData(CGImageGetDataProvider(cg)));
    XCTAssertEqual(pixels.length, expected.count);
    const uint8_t *bytes = pixels.bytes;
    for (NSUInteger i = 0; i < expected.count; i++) XCTAssertEqual(bytes[i], [expected[i] unsignedCharValue]);
}
- (void)testActualXCursorAndRichCursorMessagesReachNativeImagesWithoutVideoUpdates {
    for (NSDictionary *vector in [self profile][@"cursorWireCases"]) {
        CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
        rfbClient *client = [self clientFor:session peer:&peer];
        XCTestExpectation *shape = [self expectationWithDescription:vector[@"name"]];
        session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
            XCTAssertNotNil(image); [self assertImage:image vector:vector];
            XCTAssertEqual(hotspot.x, [vector[@"hotspot"][0] doubleValue]);
            XCTAssertEqual(hotspot.y, [vector[@"hotspot"][1] doubleValue]); XCTAssertFalse(known);
            [shape fulfill];
        };
        session.frameHandler = ^(UIImage *image) { XCTFail(@"Cursor messages must not fabricate framebuffer updates"); };
        NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        [self waitForExpectations:@[shape] timeout:1];
        session.cursorHandler = nil; session.frameHandler = nil;
        [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}
- (void)testInvalidHotspotClearsShapeAndStoppedPresentationIsFenced {
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
    rfbClient *client = [self clientFor:session peer:&peer];
    NSMutableDictionary *vector = [[self profile][@"cursorWireCases"][0] mutableCopy];
    vector[@"hotspot"] = @[@99, @0];
    XCTestExpectation *fallback = [self expectationWithDescription:@"Invalid shape uses local fallback"];
    session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
        XCTAssertNil(image); XCTAssertTrue(CGPointEqualToPoint(hotspot, CGPointZero)); [fallback fulfill];
    };
    NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
    [self waitForExpectations:@[fallback] timeout:1];
    session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) { XCTFail(@"Stopped cursor callback must be fenced"); };
    vector[@"hotspot"] = @[@1, @0]; packet = [self updateFor:vector];
    XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor]; [session stop];
    XCTestExpectation *turn = [self expectationWithDescription:@"Drain queued presentation"];
    dispatch_async(dispatch_get_main_queue(), ^{ [turn fulfill]; });
    [self waitForExpectations:@[turn] timeout:1];
    session.cursorHandler = nil; rfbClientCleanup(client); close(peer);
}
- (void)testEmptyCursorWireReportsClearAPreviouslyValidShape {
    NSDictionary *profile = [self profile];
    for (NSDictionary *sequence in profile[@"cursorWireSequences"]) {
        NSDictionary *initial = nil;
        for (NSDictionary *candidate in profile[@"cursorWireCases"]) {
            if ([candidate[@"name"] isEqual:sequence[@"initialCase"]]) initial = candidate;
        }
        XCTAssertNotNil(initial);
        CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
        rfbClient *client = [self clientFor:session peer:&peer];
        XCTestExpectation *valid = [self expectationWithDescription:@"Initial cursor"];
        session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
            XCTAssertNotNil(image); [self assertImage:image vector:initial]; [valid fulfill];
        };
        NSData *packet = [self updateFor:initial];
        XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        [self waitForExpectations:@[valid] timeout:1];
        XCTestExpectation *cleared = [self expectationWithDescription:sequence[@"name"]];
        session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
            XCTAssertNil(image); XCTAssertTrue(CGPointEqualToPoint(hotspot, CGPointZero)); [cleared fulfill];
        };
        packet = [self updateFor:sequence[@"clear"]];
        XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        [self waitForExpectations:@[cleared] timeout:1];
        session.cursorHandler = nil; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}
- (void)testAppleStoreAndZeroGeometrySelectKeepAlphaHotspotAndStayMetadata {
    for (NSDictionary *vector in [self profile][@"appleCursorCases"]) {
        CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
        rfbClient *client = [self clientFor:session peer:&peer];
        for (BOOL select = NO;; select = YES) {
            NSMutableDictionary *message = [vector mutableCopy];
            if (select) { message[@"size"] = @[@0, @0]; message[@"hotspot"] = @[@0, @0]; message[@"payload"] = @[@0, @0, @0, @17, @0, @0, @0, @0]; }
            XCTestExpectation *shape = [self expectationWithDescription:select ? @"Cached SELECT" : @"Apple STORE"];
            session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
                [self assertImage:image vector:vector]; XCTAssertEqual(hotspot.x, 1); XCTAssertEqual(hotspot.y, 0); [shape fulfill];
            };
            NSData *packet = [self updateFor:message]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
            XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
            [self waitForExpectations:@[shape] timeout:1];
            XCTAssertEqualObjects([session valueForKey:@"updates"], @0);
            if (select) break;
        }
        session.cursorHandler = nil; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}
- (void)testAppleCacheReplacementEvictionAndConnectionIsolation {
    NSDictionary *vector = [self profile][@"appleCursorCases"][0];
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
    rfbClient *client = [self clientFor:session peer:&peer];
    for (NSUInteger i = 0; i < 65; i++) {
        NSMutableDictionary *message = [vector mutableCopy]; NSMutableArray *payload = [vector[@"payload"] mutableCopy];
        payload[3] = @(i); message[@"payload"] = payload;
        NSData *packet = [self updateFor:message]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client));
    }
    NSDictionary *cache = [session valueForKey:@"appleCursorCache"];
    XCTAssertEqual(cache.count, 64); XCTAssertNil(cache[@0]); XCTAssertNotNil(cache[@64]);
    NSMutableDictionary *replacement = [[self profile][@"appleCursorCases"][1] mutableCopy];
    NSMutableArray *payload = [replacement[@"payload"] mutableCopy]; payload[3] = @64; replacement[@"payload"] = payload;
    NSData *packet = [self updateFor:replacement]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client));
    XCTAssertEqual([[session valueForKey:@"appleCursorCache"] count], 64);
    [self assertImage:[session valueForKey:@"cursorImage"] vector:replacement];
    NSMutableDictionary *select = [vector mutableCopy]; select[@"size"] = @[@0, @0]; select[@"hotspot"] = @[@0, @0];
    select[@"payload"] = @[@0, @0, @0, @0, @0, @0, @0, @0];
    packet = [self updateFor:select]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client)); XCTAssertNil([session valueForKey:@"cursorImage"]);
    [session configureClient:client]; XCTAssertEqual([[session valueForKey:@"appleCursorCache"] count], 0);
    select[@"payload"] = @[@0, @0, @0, @64, @0, @0, @0, @0];
    packet = [self updateFor:select]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
    XCTAssertTrue(HandleRFBServerMessage(client)); XCTAssertNil([session valueForKey:@"cursorImage"]);
    [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
}
- (void)testAppleCompressedBoundsRejectCorruptionTruncationAndExtraOutput {
    for (NSDictionary *vector in [self profile][@"appleCursorCases"]) {
        NSMutableData *compressed = [NSMutableData new]; NSArray *payload = vector[@"payload"];
        for (NSUInteger i = 8; i < payload.count; i++) { uint8_t byte = [payload[i] unsignedCharValue]; [compressed appendBytes:&byte length:1]; }
        uint8_t rgba[8];
        XCTAssertTrue(CompanionVNCAppleCursorRGBA(2, 1, 1, 0, compressed.bytes, compressed.length, rgba, sizeof(rgba)));
        for (NSUInteger i = 0; i < 8; i++) XCTAssertEqual(rgba[i], [vector[@"rgba"][i] unsignedCharValue]);
        for (NSUInteger length = 0; length < compressed.length; length++) XCTAssertFalse(CompanionVNCAppleCursorRGBA(2, 1, 1, 0, compressed.bytes, length, rgba, sizeof(rgba)));
        NSMutableData *extra = [compressed mutableCopy]; uint8_t zero = 0; [extra appendBytes:&zero length:1];
        XCTAssertFalse(CompanionVNCAppleCursorRGBA(2, 1, 1, 0, extra.bytes, extra.length, rgba, sizeof(rgba)));
        ((uint8_t *)extra.mutableBytes)[0] = 0;
        XCTAssertFalse(CompanionVNCAppleCursorRGBA(2, 1, 1, 0, extra.bytes, compressed.length, rgba, sizeof(rgba)));
        XCTAssertFalse(CompanionVNCAppleCursorRGBA(1, 1, 0, 0, compressed.bytes, compressed.length, rgba, sizeof(rgba)));
        XCTAssertFalse(CompanionVNCAppleCursorRGBA(2, 1, 2, 0, compressed.bytes, compressed.length, rgba, sizeof(rgba)));
        XCTAssertFalse(CompanionVNCAppleCursorRGBA(257, 1, 0, 0, compressed.bytes, compressed.length, rgba, sizeof(rgba)));
        XCTAssertFalse(CompanionVNCAppleCursorRGBA(2, 1, 1, 0, compressed.bytes, 512 * 1024 + 1, rgba, sizeof(rgba)));
    }
}
- (void)testAppleCursorPauseAndRetirementFenceQueuedPresentation {
    NSDictionary *vector = [self profile][@"appleCursorCases"][0];
    for (BOOL pause = NO;; pause = YES) {
        CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
        rfbClient *client = [self clientFor:session peer:&peer];
        session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) { XCTFail(@"Retired cursor must not be presented"); };
        NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        if (pause) { [session setValue:@YES forKey:@"established"]; [session pauseWithCompletion:^{}]; } else [session stop];
        XCTestExpectation *turn = [self expectationWithDescription:@"Drain cursor"];
        dispatch_async(dispatch_get_main_queue(), ^{ [turn fulfill]; }); [self waitForExpectations:@[turn] timeout:1];
        session.cursorHandler = nil; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
        if (pause) break;
    }
}
- (void)testAppleCachePixelBudgetAndMaximumDimensions {
    NSDictionary *policy = [self profile][@"appleCursor"];
    NSUInteger dimension = [policy[@"maximumDimension"] unsignedIntegerValue];
    NSMutableData *raw = [NSMutableData dataWithLength:dimension * dimension * 5];
    memset(raw.mutableBytes, 255, raw.length);
    uLongf length = compressBound(raw.length); NSMutableData *compressed = [NSMutableData dataWithLength:length];
    XCTAssertEqual(compress2(compressed.mutableBytes, &length, raw.bytes, raw.length, Z_BEST_SPEED), Z_OK); compressed.length = length;
    NSMutableData *rgba = [NSMutableData dataWithLength:dimension * dimension * 4];
    XCTAssertTrue(CompanionVNCAppleCursorRGBA((int)dimension, (int)dimension, (int)dimension - 1, 0, compressed.bytes, compressed.length, rgba.mutableBytes, rgba.length));
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer; rfbClient *client = [self clientFor:session peer:&peer];
    client->width = client->height = 512;
    NSMutableArray *payload = [NSMutableArray arrayWithArray:@[@0, @0, @0, @0, @(length >> 24), @((length >> 16) & 255), @((length >> 8) & 255), @(length & 255)]];
    for (NSUInteger i = 0; i < length; i++) [payload addObject:@(((const uint8_t *)compressed.bytes)[i])];
    for (NSUInteger i = 0; i < 17; i++) {
        payload[3] = @(i);
        NSData *packet = [self updateFor:@{@"size": @[@(dimension), @(dimension)], @"hotspot": @[@(dimension - 1), @0], @"encoding": policy[@"encoding"], @"payload": payload}];
        XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length); XCTAssertTrue(HandleRFBServerMessage(client));
        XCTAssertLessThanOrEqual([[session valueForKey:@"appleCursorBytes"] unsignedIntegerValue], [policy[@"maximumCachePixelBytes"] unsignedIntegerValue]);
    }
    XCTAssertNil([session valueForKey:@"appleCursorCache"][@0]);
    [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
}
- (void)testAppleCursorAndRawRectanglesShareOneAlignedUpdate {
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer; rfbClient *client = [self clientFor:session peer:&peer];
    XCTAssertTrue([session allocate:client]);
    NSMutableData *packet = [[self updateFor:[self profile][@"appleCursorCases"][0]] mutableCopy];
    ((uint8_t *)packet.mutableBytes)[3] = 2;
    // One red synthetic raw pixel follows the cursor rectangle in the SAME
    // update. Cursor geometry must not satisfy even one pixel of coverage.
    uint8_t raw[] = {0,0, 0,0, 0,1, 0,1, 0,0,0,0, 0,0,255,0};
    [packet appendBytes:raw length:sizeof(raw)];
    XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length); XCTAssertTrue(HandleRFBServerMessage(client));
    XCTAssertEqualObjects([session valueForKey:@"updates"], @1);
    XCTAssertEqualObjects([session valueForKey:@"receivedPixels"], @1);
    XCTAssertNotNil([session valueForKey:@"cursorImage"]);
    XCTAssertEqual(client->frameBuffer[2], 255);
    [session setValue:@NO forKey:@"running"]; client->frameBuffer = NULL; rfbClientCleanup(client); close(peer);
}
- (void)testAppleMalformedWireRetiresOwnerWithoutPublishingCursor {
    for (NSArray *payload in @[@[@0, @0, @0, @1, @0, @8, @0, @1], @[@0, @0, @0, @1, @0, @0, @0, @2, @0, @0]]) {
        CompanionVNCSession *session = [CompanionVNCSession new]; int peer; rfbClient *client = [self clientFor:session peer:&peer];
        NSData *packet = [self updateFor:@{@"size": @[@2, @1], @"hotspot": @[@1, @0], @"encoding": @1104, @"payload": payload}];
        XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length); XCTAssertFalse(HandleRFBServerMessage(client));
        XCTAssertEqualObjects([session valueForKey:@"extensionFailed"], @YES); XCTAssertNil([session valueForKey:@"cursorImage"]);
        [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
    }
}
- (void)testStationaryWireShapeChangesAndCoalescedReportsPublishLatestWithoutVideo {
    CompanionVNCSession *session = [CompanionVNCSession new]; int peer;
    rfbClient *client = [self clientFor:session peer:&peer];
    NSDictionary *profile = [self profile], *sequence = profile[@"stationaryCursorSequence"];
    NSMutableArray *vectors = [NSMutableArray new];
    for (NSString *kind in @[@"standard", @"apple"]) {
        NSArray *cases = profile[[kind isEqual:@"standard"] ? @"cursorWireCases" : @"appleCursorCases"];
        for (NSString *name in sequence[kind]) {
            for (NSDictionary *vector in cases) if ([vector[@"name"] isEqual:name]) [vectors addObject:vector];
        }
    }
    XCTAssertEqual(vectors.count, 4);
    for (NSDictionary *vector in vectors) {
        XCTestExpectation *delivered = [self expectationWithDescription:@"Stationary shape"];
        session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
            [self assertImage:image vector:vector]; XCTAssertFalse(known); [delivered fulfill];
        };
        NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
        [self waitForExpectations:@[delivered] timeout:1];
    }
    XCTestExpectation *latest = [self expectationWithDescription:@"Latest coalesced shape"];
    __block NSUInteger coalesced = 0;
    session.cursorHandler = ^(UIImage *image, CGPoint hotspot, CGPoint position, BOOL known) {
        [self assertImage:image vector:vectors.lastObject]; coalesced++; [latest fulfill];
    };
    for (NSDictionary *vector in @[vectors[0], vectors.lastObject]) {
        NSData *packet = [self updateFor:vector]; XCTAssertEqual(send(peer, packet.bytes, packet.length, 0), packet.length);
        XCTAssertTrue(HandleRFBServerMessage(client)); [session publishCursor];
    }
    [self waitForExpectations:@[latest] timeout:1];
    // A second publication must not be needed to replace an older queued image.
    [session publishCursor];
    XCTestExpectation *drained = [self expectationWithDescription:@"No stale queued cursor"];
    dispatch_async(dispatch_get_main_queue(), ^{ [drained fulfill]; });
    [self waitForExpectations:@[drained] timeout:1]; XCTAssertEqual(coalesced, 1);
    XCTAssertEqualObjects([session valueForKey:@"updates"], @0);
    XCTAssertEqualObjects([session valueForKey:@"cursorPositions"], @0);
    XCTAssertEqualObjects([session valueForKey:@"appleCursorStores"], @3);
    XCTAssertEqualObjects([session valueForKey:@"standardCursorReports"], @3);
    session.cursorHandler = nil; [session setValue:@NO forKey:@"running"]; rfbClientCleanup(client); close(peer);
}
@end
