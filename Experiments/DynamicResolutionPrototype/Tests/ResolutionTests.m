#import <XCTest/XCTest.h>
#import "PrototypeViewer.h"
#import "DynamicDisplay.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>
@interface CompanionVNCSession (PrototypeTesting)
- (void)configureClient:(rfbClient *)client;
- (BOOL)allocate:(rfbClient *)client;
- (BOOL)processDesktopSizeChange:(rfbClient *)client;
- (rfbBool)displayLayout:(rfbClient *)client encoding:(int)encoding;
- (void)updatedX:(int)x y:(int)y width:(int)width height:(int)height;
- (void)publishFrame:(rfbClient *)client;
- (void)finish:(NSString *)state;
@end
@interface MCPrototypeViewer (PrototypeTesting)
@end
@interface ResolutionTests : XCTestCase
@end
@implementation ResolutionTests
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
        MCDynamicSize size = {[row[@"points"][0] intValue], [row[@"points"][1] intValue]};
        uint8_t packet[196]; XCTAssertTrue(MCDynamicDisplayPacket(size, packet, sizeof(packet)));
        NSMutableString *hex = [NSMutableString new]; for (NSUInteger i = 0; i < sizeof(packet); i++) [hex appendFormat:@"%02x", packet[i]];
        XCTAssertEqualObjects(hex, row[@"hex"]);
    }
    MCDynamicSize size;
    XCTAssertFalse(MCDynamicSizeForViewport(NAN, 400, &size));
    XCTAssertFalse(MCDynamicSizeForViewport(INFINITY, 400, &size));
    XCTAssertTrue(MCDynamicSizeForViewport(1920, 1080, &size));
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
    XCTAssertTrue(MCDynamicDisplayPacket((MCDynamicSize){1132,600}, expected, sizeof(expected)));
    XCTAssertEqual(memcmp(bytes, expected, 196), 0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeRequests"], @1);
    [session setValue:@(NSProcessInfo.processInfo.systemUptime - 21) forKey:@"desktopResizeStarted"];
    XCTAssertTrue([session processDesktopSizeChange:client]);
    XCTAssertEqualObjects(session.diagnosticCounters[@"probeTimedOut"], @1);
    XCTAssertFalse([session tryClickX:1 y:1 mask:1]);
    [session setValue:@NO forKey:@"running"]; [session stop]; rfbClientCleanup(client); close(pair[1]);
}
- (void)testJournalRejectsContentAndSeparatesOwners {
    NSDictionary *filtered = [MCBenchmarkJournal filteredCounters:@{@"presentedFrames": @8, @"username": @"private", @"password": @"private", @"sampleUptime": @(NAN), @"sessionRunning": @(NAN), @"sessionEstablished": @YES, @"pipeline": @{@"workerCPUTotalMS": @2, @"text": @"private"}, @"desktopSSH": @{@"inboundBytes": @40, @"host": @"private"}}];
    XCTAssertNil(filtered[@"username"]); XCTAssertNil(filtered[@"password"]); XCTAssertNil(filtered[@"sampleUptime"]);
    XCTAssertNil(filtered[@"sessionRunning"]); XCTAssertEqualObjects(filtered[@"sessionEstablished"], @YES);
    XCTAssertEqualObjects(filtered[@"pipeline"], (@{@"workerCPUTotalMS": @2}));
    NSURL *directory = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString]];
    NSURL *file = [directory URLByAppendingPathComponent:@"journal.jsonl"];
    MCBenchmarkJournal *journal = [[MCBenchmarkJournal alloc] initWithURL:file maximumBytes:4096];
    NSObject *first = [NSObject new], *second = [NSObject new];
    [journal beginOwner:first]; [journal appendCounters:@{@"presentedFrames": @1} owner:first];
    XCTestExpectation *a = [self expectationWithDescription:@"First flush"]; [journal flush:^{ [a fulfill]; }]; [self waitForExpectations:@[a] timeout:2];
    [journal endOwner:first]; [journal beginOwner:second];
    [journal appendCounters:@{@"password": @"private"} owner:first];
    [journal appendCounters:@{@"presentedFrames": @2} owner:second];
    XCTestExpectation *b = [self expectationWithDescription:@"Second flush"]; [journal flush:^{ [b fulfill]; }]; [self waitForExpectations:@[b] timeout:2];
    NSString *text = [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL];
    NSArray *lines = [text componentsSeparatedByString:@"\n"]; XCTAssertEqual(lines.count, 3); XCTAssertFalse([text containsString:@"private"]);
    NSDictionary *one = [NSJSONSerialization JSONObjectWithData:[lines[0] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    NSDictionary *two = [NSJSONSerialization JSONObjectWithData:[lines[1] dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
    XCTAssertNotEqualObjects(one[@"owner"],two[@"owner"]); XCTAssertEqualObjects(two[@"sequence"],@1);
    MCBenchmarkJournal *bounded = [[MCBenchmarkJournal alloc] initWithURL:file maximumBytes:1];
    [bounded beginOwner:first]; [bounded appendCounters:@{@"presentedFrames": @3} owner:first];
    XCTestExpectation *c = [self expectationWithDescription:@"Bounded flush"]; [bounded flush:^{ [c fulfill]; }]; [self waitForExpectations:@[c] timeout:2];
    XCTAssertTrue(bounded.full); XCTAssertEqualObjects(text, [NSString stringWithContentsOfURL:file encoding:NSUTF8StringEncoding error:NULL]);
    [[NSFileManager defaultManager] removeItemAtURL:directory error:NULL];
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
- (void)testImmediateClosureLeavesNumericRequestOutcome {
    CompanionVNCSession *session = [CompanionVNCSession new];
    for (NSString *key in @[@"running", @"established", @"inputReady", @"appleGestureServer"]) [session setValue:@YES forKey:key];
    XCTAssertTrue([session requestDesktopSizeWidth:832 height:440]);
    [session finish:@"Disconnected"];
    NSDictionary *counters = [MCBenchmarkJournal filteredCounters:session.diagnosticCounters];
    XCTAssertEqualObjects(counters[@"probeOutcome"], @3);
    XCTAssertEqualObjects(counters[@"probeAwaiting"], @NO);
    XCTAssertEqualObjects(counters[@"sessionRunning"], @NO);
    XCTAssertEqualObjects(counters[@"sessionEstablished"], @NO);
    XCTAssertNotNil(counters[@"sampleUptime"]);
}
@end
