#import <XCTest/XCTest.h>
#import "CompanionVNCSession.h"
#import "CompanionVNCDisplayLayout.h"
#import "CompanionVNCCoverage.h"
#import <rfb/rfbclient.h>
#import <sys/socket.h>
#import <unistd.h>
#import <zlib.h>

@interface CompanionVNCSession (Diagnosis)
- (void)configureClient:(rfbClient *)client;
- (rfbBool)allocate:(rfbClient *)client;
- (void)publishFrame:(rfbClient *)client;
- (void)processConnectedClient:(rfbClient *)client;
- (BOOL)registerSocket:(int)socket;
- (BOOL)requestFullDesktop:(rfbClient *)client;
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client;
@end
@interface StalledComposerSession : CompanionVNCSession
@property(nonatomic, strong) dispatch_semaphore_t firstWrite, continueWrite;
@property BOOL stalled;
@end
@implementation StalledComposerSession
- (instancetype)init {
    if ((self = [super init])) { _firstWrite = dispatch_semaphore_create(0); _continueWrite = dispatch_semaphore_create(0); }
    return self;
}
- (BOOL)writeKeyEvent:(uint32_t)key down:(BOOL)down client:(rfbClient *)client {
    if (!self.stalled) {
        self.stalled = YES; dispatch_semaphore_signal(self.firstWrite);
        if (dispatch_semaphore_wait(self.continueWrite, dispatch_time(DISPATCH_TIME_NOW, 3 * NSEC_PER_SEC))) return NO;
    }
    return [super writeKeyEvent:key down:down client:client];
}
@end
@interface FrameReadinessTests : XCTestCase
@end
@implementation FrameReadinessTests
- (void)testCopiedComposerGroupIsRetiredAcrossTrackpadPauseResumeAndFreshTextStillSends {
    [self assertCopiedComposerGroupRetired:NO];
}
- (void)testCopiedComposerGroupIsRetiredByScreenTextReviewBeforeFreshDesktopSend {
    [self assertCopiedComposerGroupRetired:YES];
}
- (void)assertCopiedComposerGroupRetired:(BOOL)screenTextReview {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"ios-text-composer-v1" withExtension:@"json"];
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    NSDictionary *policy = fixture[@"lifecycle"][@"cancelCopiedGroup"];
    NSMutableDictionary *vectors = [NSMutableDictionary new];
    for (NSDictionary *vector in fixture[@"cases"]) vectors[vector[@"name"]] = vector;
    NSArray *(^events)(NSString *) = ^NSArray *(NSString *name) {
        NSMutableArray *group = [NSMutableArray new];
        for (NSNumber *key in vectors[name][@"desktopKeys"]) for (NSNumber *down in @[@YES, @NO])
            [group addObject:@{@"key": key, @"down": down}];
        return group;
    };
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    int yes = 1; setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
    struct timeval timeout = {.tv_sec = 2}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
    StalledComposerSession *session = [StalledComposerSession new];
    rfbClient *client = rfbGetClient(8, 3, 4); client->sock = pair[0]; client->width = 2; client->height = 2;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0] |= (1 << rfbKeyEvent) | (1 << rfbPointerEvent) | (1 << rfbFramebufferUpdateRequest);
    session.inputOnly = !screenTextReview;
    for (NSString *key in @[@"running",@"established",@"inputReady",@"baselinePresented"]) [session setValue:@YES forKey:key];
    if (screenTextReview) client->GotFrameBufferUpdate(client,0,0,2,2);
    [session registerSocket:pair[0]];
    XCTestExpectation *cancelled = [self expectationWithDescription:@"Interrupted group fails once"];
    XCTestExpectation *fresh = [self expectationWithDescription:@"New deliberately admitted group writes"];
    XCTestExpectation *ended = [self expectationWithDescription:@"Synthetic VNC worker retires"];
    __block NSUInteger cancelledReplies = 0, freshReplies = 0;
    __weak StalledComposerSession *weakSession = session;
    session.stateHandler = ^(NSString *state, NSDictionary *stats) { if (!weakSession.running) [ended fulfill]; };
    XCTAssertTrue([session tryComposedTextEvents:events(policy[@"interruptedCase"]) completion:^(BOOL written) {
        cancelledReplies++; XCTAssertEqual(written, [policy[@"cancelledCompletionWritten"] boolValue]); [cancelled fulfill];
    }]);
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [session processConnectedClient:client]; });
    XCTAssertEqual(dispatch_semaphore_wait(session.firstWrite, dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC)), 0);
    // The worker owns a copied batch and has admitted its first write. Pause and
    // resume before that write returns; the old queue itself is already empty.
    if (screenTextReview) XCTAssertTrue([session suspendInputForReview:nil]);
    else { [session pauseWithCompletion:nil]; [session resume]; }
    [self waitForExpectations:@[cancelled] timeout:1];
    NSMutableData *wire = [NSMutableData new];
    if (screenTextReview) {
        NSDictionary *reviewPolicy=fixture[@"lifecycle"][@"screenTextReview"];
        XCTAssertEqual([session tryComposedTextEvents:events(policy[@"freshCase"]) completion:^(BOOL written) { XCTFail(@"Review must reject input"); }],
            [reviewPolicy[@"allowsSendDuringReview"] boolValue]);
        XCTAssertEqual([(NSDictionary *)[session valueForKey:@"composedTextReplies"] count],[reviewPolicy[@"repliesAfterReview"] unsignedIntegerValue]);
        [session resumeInputAfterReview]; XCTAssertTrue(session.connected);
        XCTAssertFalse([[session valueForKey:@"resumeRequested"] boolValue]);
        dispatch_semaphore_signal(session.continueWrite);
        // The interrupted copied group stays retired; a new deliberate group
        // may use the unchanged live baseline after the held-input release.

    }
    XCTAssertTrue([session tryComposedTextEvents:events(policy[@"freshCase"]) completion:^(BOOL written) {
        freshReplies++; XCTAssertEqual(written, [policy[@"freshCompletionWritten"] boolValue]); [fresh fulfill];
    }]);
    if (!screenTextReview) dispatch_semaphore_signal(session.continueWrite);
    [self waitForExpectations:@[fresh] timeout:2];
    [session stop]; [self waitForExpectations:@[ended] timeout:2];
    uint8_t bytes[512]; ssize_t count;
    while ((count = recv(pair[1], bytes, sizeof(bytes), 0)) > 0) [wire appendBytes:bytes length:(NSUInteger)count];
    XCTAssertEqual(count, 0); close(pair[1]);
    NSMutableArray *keys = [NSMutableArray new]; const uint8_t *packets = wire.bytes;
    for (NSUInteger offset = 0; offset < wire.length;) {
        uint8_t type = packets[offset]; NSUInteger size = type == rfbKeyEvent ? 8 : type == rfbPointerEvent ? 6 : type == rfbFramebufferUpdateRequest ? 10 : 0;
        XCTAssertTrue(size && offset + size <= wire.length); if (!size || offset + size > wire.length) break;
        if (type == rfbKeyEvent) {
            uint32_t key = ((uint32_t)packets[offset + 4] << 24) | ((uint32_t)packets[offset + 5] << 16)
                | ((uint32_t)packets[offset + 6] << 8) | packets[offset + 7];
            [keys addObject:@[@(key), @(packets[offset + 1] != 0)]];
        }
        offset += size;
    }
    XCTAssertEqualObjects(keys, policy[@"expectedKeyEvents"], @"Only the in-flight key, its cleanup release, and fresh text may be written");
    XCTAssertEqual(cancelledReplies, 1); XCTAssertEqual(freshReplies, 1);
    XCTAssertEqual([(NSSet *)[session valueForKey:@"heldKeys"] count], 0);
}
- (void)testComposerCompletionFollowsExactUnicodeKeyPacketsWithoutExtraReturn {
    NSURL *url = [[NSBundle bundleForClass:self.class] URLForResource:@"ios-text-composer-v1" withExtension:@"json"];
    NSDictionary *fixture = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    for (NSDictionary *vector in fixture[@"cases"]) {
        if ([vector[@"invalid"] boolValue]) continue;
        int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
        int yes = 1; setsockopt(pair[0], SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        struct timeval timeout = {.tv_sec = 1}; setsockopt(pair[1], SOL_SOCKET, SO_RCVTIMEO, &timeout, sizeof(timeout));
        CompanionVNCSession *session = [CompanionVNCSession new];
        rfbClient *client = rfbGetClient(8, 3, 4); client->sock = pair[0]; client->width = 2; client->height = 2;
        [session configureClient:client]; XCTAssertTrue([session allocate:client]);
        client->supportedMessages.client2server[0] |= (1 << rfbKeyEvent) | (1 << rfbPointerEvent);
        // Input-only owns the same key writer and needs no desktop pixels.
        [session setValue:@YES forKey:@"inputOnly"]; [session setValue:@YES forKey:@"running"];
        [session setValue:@YES forKey:@"inputReady"]; [session registerSocket:pair[0]];
        NSMutableArray *events = [NSMutableArray new]; NSMutableData *expected = [NSMutableData new];
        for (NSNumber *key in vector[@"desktopKeys"]) {
            uint32_t value = key.unsignedIntValue;
            for (NSNumber *down in @[@YES, @NO]) {
                [events addObject:@{@"key": key, @"down": down}];
                uint8_t packet[] = {4, down.boolValue, 0, 0, value >> 24, value >> 16, value >> 8, value};
                [expected appendBytes:packet length:sizeof(packet)];
            }
        }
        XCTestExpectation *written = [self expectationWithDescription:@"The whole text group reached the local socket"];
        __block NSUInteger replies = 0;
        XCTAssertTrue([session tryComposedTextEvents:events completion:^(BOOL success) { replies++; XCTAssertTrue(success); [written fulfill]; }]);
        XCTestExpectation *ended = [self expectationWithDescription:@"Synthetic VNC worker stopped"];
        session.stateHandler = ^(NSString *state, NSDictionary *stats) { if (!session.running) [ended fulfill]; };
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{ [session processConnectedClient:client]; });
        NSMutableData *received = [NSMutableData dataWithLength:expected.length];
        XCTAssertEqual(recv(pair[1], received.mutableBytes, received.length, MSG_WAITALL), expected.length);
        XCTAssertEqualObjects(received, expected, @"%@", vector[@"name"]);
        [self waitForExpectations:@[written] timeout:1]; XCTAssertEqual(replies, 1);
        [session stop]; [self waitForExpectations:@[ended] timeout:1]; XCTAssertEqual(replies, 1);
        close(pair[1]);
    }
}
- (NSDictionary *)encodingPolicy {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    return [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL][@"desktopEncodingPolicy"];
}
- (void)testAdvertisedEncodingsAndCompleteZlibDesktop {
    int pair[2];XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new];rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0];client->width=4;client->height=4;[session configureClient:client];XCTAssertTrue([session allocate:client]);
    XCTAssertEqualObjects([NSString stringWithUTF8String:client->appData.encodingsString],[[self encodingPolicy][@"preferences"] componentsJoinedByString:@" "]);
    [session setValue:@YES forKey:@"running"];client->supportedMessages.client2server[0]|=(1<<rfbFramebufferUpdateRequest);rfbClientSetUpdateRect(client,NULL);
    uint8_t red[64];for(NSUInteger i=0;i<64;i+=4){red[i]=0;red[i+1]=0;red[i+2]=255;red[i+3]=0;}
    uint8_t compressed[128];z_stream stream={0};XCTAssertEqual(deflateInit(&stream,Z_DEFAULT_COMPRESSION),Z_OK);
    stream.next_in=red;stream.avail_in=sizeof(red);stream.next_out=compressed;stream.avail_out=sizeof(compressed);
    XCTAssertEqual(deflate(&stream,Z_SYNC_FLUSH),Z_OK);NSUInteger length=sizeof(compressed)-stream.avail_out;deflateEnd(&stream);
    uint8_t header[]={0,0,0,1,0,0,0,0,0,4,0,4,0,0,0,6};
    uint8_t size[]={(uint8_t)(length>>24),(uint8_t)(length>>16),(uint8_t)(length>>8),(uint8_t)length};
    XCTAssertEqual(write(pair[1],header,sizeof(header)),sizeof(header));XCTAssertEqual(write(pair[1],size,4),4);XCTAssertEqual(write(pair[1],compressed,length),length);
    XCTAssertTrue(HandleRFBServerMessage(client));XCTAssertEqual(memcmp(client->frameBuffer,red,sizeof(red)),0);
    XCTestExpectation *presented=[self expectationWithDescription:@"Complete lossless Zlib frame reaches the viewer"];
    session.frameHandler=^(UIImage *image){XCTAssertEqual(CGImageGetWidth(image.CGImage),4);[presented fulfill];};[session publishFrame:client];[self waitForExpectations:@[presented] timeout:1];
    XCTAssertEqualObjects([session valueForKey:@"baselinePresented"],@YES);
    session.frameHandler=nil;[session setValue:@NO forKey:@"running"];client->frameBuffer=NULL;rfbClientCleanup(client);close(pair[1]);
}
- (void)testFailedZRLEDecodeCannotPresentAZeroFilledDesktopAsComplete {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0];client->width=4;client->height=4;
    [session configureClient:client];XCTAssertTrue([session allocate:client]);
    [session setValue:@YES forKey:@"running"];
    client->supportedMessages.client2server[0]|=(1<<rfbFramebufferUpdateRequest);
    rfbClientSetUpdateRect(client,NULL);
    // Upstream 0.9.15 reports a tile failure but returns success. Its outer
    // update callback still covers the whole rectangle without writing pixels.
    NSString *tileHex=[self encodingPolicy][@"invalidZRLETileHex"];unsigned tile=0;[[NSScanner scannerWithString:tileHex] scanHexInt:&tile];
    uint8_t invalidTile[]={(uint8_t)tile}; uint8_t compressed[128];
    z_stream stream={0}; XCTAssertEqual(deflateInit(&stream,Z_DEFAULT_COMPRESSION),Z_OK);
    stream.next_in=invalidTile;stream.avail_in=sizeof(invalidTile);stream.next_out=compressed;stream.avail_out=sizeof(compressed);
    XCTAssertEqual(deflate(&stream,Z_SYNC_FLUSH),Z_OK);NSUInteger length=sizeof(compressed)-stream.avail_out;deflateEnd(&stream);
    uint8_t header[]={0,0,0,1,0,0,0,0,0,4,0,4,0,0,0,16};
    uint8_t size[]={(uint8_t)(length>>24),(uint8_t)(length>>16),(uint8_t)(length>>8),(uint8_t)length};
    XCTAssertEqual(write(pair[1],header,sizeof(header)),sizeof(header));XCTAssertEqual(write(pair[1],size,4),4);
    XCTAssertEqual(write(pair[1],compressed,length),length);
    XCTAssertTrue(HandleRFBServerMessage(client));
    XCTestExpectation *notPresented=[self expectationWithDescription:@"A failed decoder is not a complete black desktop"];notPresented.inverted=YES;
    session.frameHandler=^(UIImage *image){[notPresented fulfill];};[session publishFrame:client];
    [self waitForExpectations:@[notPresented] timeout:.05];
    XCTAssertEqualObjects([session valueForKey:@"baselinePresented"],@NO);
    XCTAssertEqualObjects([session valueForKey:@"failureStage"],[self encodingPolicy][@"decodeFailureStage"]);
    XCTAssertEqualObjects([session valueForKey:@"decoderFailures"],@1);
    session.frameHandler=nil;[session setValue:@NO forKey:@"running"];client->frameBuffer=NULL;rfbClientCleanup(client);close(pair[1]);
}
- (void)diagnoseMetadata:(BOOL)metadata {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX, SOCK_STREAM, 0, pair), 0);
    struct timeval timeout={.tv_sec=1}; setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new];
    rfbClient *client=rfbGetClient(8,3,4); client->sock=pair[0]; client->width=200; client->height=100;
    [session configureClient:client]; XCTAssertTrue([session allocate:client]);
    [session setValue:@YES forKey:@"running"]; [session setValue:@YES forKey:@"inputReady"];
    client->supportedMessages.client2server[0]|=(1<<rfbFramebufferUpdateRequest);
    rfbClientSetUpdateRect(client,NULL);
    NSMutableData *body=[NSMutableData new];
    if (metadata) {
        NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
        NSDictionary *profile=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
        NSString *hex=profile[@"displayLayoutCases"][0][@"bodyHex"];
        for(NSUInteger i=0;i<hex.length;i+=2){unsigned value=0;[[NSScanner scannerWithString:[hex substringWithRange:NSMakeRange(i,2)]] scanHexInt:&value];uint8_t byte=value;[body appendBytes:&byte length:1];}
        uint8_t header[]={0,0,0,1,0,0,0,0,0,200,0,100,0,0,4,0x51};
        uint8_t length[]={(uint8_t)(body.length>>8),(uint8_t)body.length};
        XCTAssertEqual(write(pair[1],header,sizeof(header)),sizeof(header));
        XCTAssertEqual(write(pair[1],length,2),2); XCTAssertEqual(write(pair[1],body.bytes,body.length),body.length);
    } else {
        uint8_t header[]={0,0,0,1,0,0,0,0,0,200,0,2,0,0,0,0};
        for(NSUInteger i=0;i<400;i++){uint8_t pixel[]={0,0,255,0};[body appendBytes:pixel length:4];}
        XCTAssertEqual(write(pair[1],header,sizeof(header)),sizeof(header));
        XCTAssertEqual(write(pair[1],body.bytes,body.length),body.length);
    }
    XCTAssertTrue(HandleRFBServerMessage(client));
    uint8_t request[10]; XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10);
    XCTAssertEqual(request[0],rfbFramebufferUpdateRequest); XCTAssertEqual(request[1],1);
    NSUInteger filled=0; for(NSUInteger i=0;i<20000;i++) if(client->frameBuffer[i*4]||client->frameBuffer[i*4+1]||client->frameBuffer[i*4+2]) filled++;
    XCTAssertEqual(filled,metadata?0:400);
    XCTestExpectation *frame=[self expectationWithDescription:@"Incomplete baseline is not presented"]; frame.inverted=YES;
    session.frameHandler=^(UIImage *image){XCTAssertEqual(CGImageGetWidth(image.CGImage),200);XCTAssertEqual(CGImageGetHeight(image.CGImage),100);[frame fulfill];};
    [session publishFrame:client]; [self waitForExpectations:@[frame] timeout:.05];
    XCTAssertEqualObjects([session valueForKey:@"presentedFrames"],@0);

    session.frameHandler=nil; [session stop]; [session setValue:@NO forKey:@"running"];
    client->frameBuffer=NULL; rfbClientCleanup(client); close(pair[1]);
}
- (void)testDisplayMetadataDoesNotPresentAFrame {[self diagnoseMetadata:YES];}
- (void)testTwoPixelStripCannotCompleteTheDesktop {[self diagnoseMetadata:NO];}
- (void)testIndexedCoverageCasesAndResizeReset {
    NSURL *url=[[NSBundle bundleForClass:self.class] URLForResource:@"direct-screen-sharing-v1" withExtension:@"json"];
    NSDictionary *profile=[NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    for (NSDictionary *sample in profile[@"frameReadinessCases"]) {
        CompanionVNCCoverage coverage = {0};
        XCTAssertTrue(CompanionVNCCoverageReset(&coverage, [sample[@"width"] intValue], [sample[@"height"] intValue]));
        if (sample[@"required"]) {
            CompanionVNCCoverageClearRequirements(&coverage);
            for (NSArray *r in sample[@"required"]) CompanionVNCCoverageRect(&coverage,[r[0] intValue],[r[1] intValue],[r[2] intValue],[r[3] intValue],true);
        }
        for (NSArray *r in sample[@"rectangles"]) CompanionVNCCoverageRect(&coverage,[r[0] intValue],[r[1] intValue],[r[2] intValue],[r[3] intValue],false);
        XCTAssertEqual(CompanionVNCCoverageReady(&coverage),[sample[@"ready"] boolValue],@"%@",sample[@"name"]);
        XCTAssertTrue(CompanionVNCCoverageReset(&coverage,2,2)); XCTAssertFalse(CompanionVNCCoverageReady(&coverage));
        CompanionVNCCoverageFree(&coverage);
    }
}
- (void)testACompleteBlackBaselinePresentsAndResizeWaitsForNewPixels {
    CompanionVNCSession *session=[CompanionVNCSession new]; rfbClient *client=rfbGetClient(8,3,4);
    [session configureClient:client]; client->width=2;client->height=2; XCTAssertTrue([session allocate:client]);
    [session setValue:@YES forKey:@"running"];
    XCTestExpectation *frame=[self expectationWithDescription:@"Legitimate black pixels are complete"];
    session.frameHandler=^(UIImage *image){[frame fulfill];};
    client->GotFrameBufferUpdate(client,0,0,2,2); [session publishFrame:client]; [self waitForExpectations:@[frame] timeout:1];
    XCTAssertEqualObjects([session valueForKey:@"baselinePresented"],@YES);
    client->width=4;client->height=4; XCTAssertTrue([session allocate:client]);
    XCTAssertEqualObjects([session valueForKey:@"baselinePresented"],@NO);
    XCTestExpectation *incomplete=[self expectationWithDescription:@"Resize does not present partial pixels"]; incomplete.inverted=YES;
    session.frameHandler=^(UIImage *image){[incomplete fulfill];}; client->GotFrameBufferUpdate(client,0,0,4,1);
    [session publishFrame:client]; [self waitForExpectations:@[incomplete] timeout:.05];
    session.frameHandler=nil; [session setValue:@NO forKey:@"running"];client->frameBuffer=NULL;rfbClientCleanup(client);
}
- (void)testIncompleteBaselineRequestsOnlyTwoFullRetriesThenEnds {
    int pair[2]; XCTAssertEqual(socketpair(AF_UNIX,SOCK_STREAM,0,pair),0);
    int yes=1;setsockopt(pair[0],SOL_SOCKET,SO_NOSIGPIPE,&yes,sizeof(yes));
    struct timeval timeout={.tv_sec=3};setsockopt(pair[1],SOL_SOCKET,SO_RCVTIMEO,&timeout,sizeof(timeout));
    CompanionVNCSession *session=[CompanionVNCSession new];rfbClient *client=rfbGetClient(8,3,4);
    client->sock=pair[0];client->width=2;client->height=2;[session configureClient:client];XCTAssertTrue([session allocate:client]);
    client->supportedMessages.client2server[0]|=(1<<rfbFramebufferUpdateRequest)|(1<<rfbPointerEvent);
    // Baseline maintenance belongs to an authenticated owner. Model the
    // successful handshake, including its initial full request, before retries.
    for(NSString *key in @[@"running",@"established",@"inputReady"]) [session setValue:@YES forKey:key];
    XCTAssertTrue(session.established);XCTAssertTrue([session registerSocket:pair[0]]);
    const uint8_t expectedRequest[]={3,0,0,0,0,0,0,2,0,2};
    XCTAssertTrue([session requestFullDesktop:client]);
    uint8_t initial[sizeof(expectedRequest)]={0};
    XCTAssertEqual(recv(pair[1],initial,sizeof(initial),MSG_WAITALL),sizeof(initial));
    XCTAssertEqual(memcmp(initial,expectedRequest,sizeof(initial)),0);
    XCTAssertEqualObjects(session.diagnosticCounters[@"fullRefreshRequests"],@1);
    XCTestExpectation *ended=[self expectationWithDescription:@"Incomplete baseline ends within deadline"];
    __weak CompanionVNCSession *weakSession=session;
    session.stateHandler=^(NSString *state,NSDictionary *stats){
        if(!weakSession.running){XCTAssertEqualObjects(stats[@"failureStage"],@102);XCTAssertEqualObjects(stats[@"fullRefreshRetries"],@2);XCTAssertEqualObjects(stats[@"baselineReady"],@NO);[ended fulfill];}
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
    for(NSUInteger i=0;i<2;i++){
        uint8_t request[sizeof(expectedRequest)]={0};
        XCTAssertEqual(recv(pair[1],request,sizeof(request),MSG_WAITALL),sizeof(request));
        XCTAssertEqual(memcmp(request,expectedRequest,sizeof(request)),0);
    }
    [self waitForExpectations:@[ended] timeout:8];
    XCTAssertEqualObjects(session.diagnosticCounters[@"fullRefreshRequests"],@3);
    const uint8_t expectedRelease[]={5,0,0,0,0,0};uint8_t release[sizeof(expectedRelease)]={0};
    XCTAssertEqual(recv(pair[1],release,sizeof(release),MSG_WAITALL),sizeof(release));
    XCTAssertEqual(memcmp(release,expectedRelease,sizeof(release)),0);
    uint8_t extra;XCTAssertEqual(recv(pair[1],&extra,1,0),0,@"No third retry may precede socket retirement");
    session.stateHandler=nil;close(pair[1]);
}
@end
