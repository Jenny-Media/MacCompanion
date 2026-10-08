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
@end
@interface FrameReadinessTests : XCTestCase
@end
@implementation FrameReadinessTests
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
    [session setValue:@YES forKey:@"running"];[session setValue:@YES forKey:@"inputReady"];[session registerSocket:pair[0]];
    XCTestExpectation *ended=[self expectationWithDescription:@"Incomplete baseline ends within deadline"];
    session.stateHandler=^(NSString *state,NSDictionary *stats){
        if(!session.running){XCTAssertEqualObjects(stats[@"failureStage"],@102);XCTAssertEqualObjects(stats[@"fullRefreshRetries"],@2);[ended fulfill];}
    };
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{[session processConnectedClient:client];});
    for(NSUInteger i=0;i<2;i++){
        uint8_t request[10];XCTAssertEqual(recv(pair[1],request,10,MSG_WAITALL),10);
        XCTAssertEqual(request[0],rfbFramebufferUpdateRequest);XCTAssertEqual(request[1],0);
    }
    [self waitForExpectations:@[ended] timeout:8];
    uint8_t release[6];XCTAssertEqual(recv(pair[1],release,6,MSG_WAITALL),6);XCTAssertEqual(release[0],rfbPointerEvent);
    session.stateHandler=nil;close(pair[1]);
}
@end
